#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Gamma_Entertainment_Scraper.py

Python implementation of Gamma Entertainment Scraper from C# source.
Handles all Gamma Entertainment network sites using Algolia API.

Based on: AdultScraper.Shared/AbstractGammaEntertainmentScraper.cs
"""

import json
import re
import requests
import urllib.parse
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
import logging
import sys
from pathlib import Path

# Add parent directories to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from base_scraper import BaseScraper
from core.models import ScrapeResult
from web.request import Request

# 导入工具模块
from utils.query_parser import calculate_title_match_score, select_best_match, clean_title
from utils.date_parser import is_date_query, parse_date_query, filter_by_date
from utils.content_type_filter import filter_by_content_type, log_content_type_debug

logger = logging.getLogger(__name__)


# Simple site config class for Gamma Entertainment sites
class GammaSiteConfig:
    """Configuration for Gamma Entertainment sites"""
    
    def __init__(self, site_name: str, domain: str, network: str = "GammaEntertainment", 
                 enabled: bool = True, priority: int = 80):
        self.site_name = site_name
        self.domain = domain
        self.network = network
        self.enabled = enabled
        self.priority = priority


class AlgoliaAPI:
    """Handles Algolia API interactions for Gamma Entertainment sites"""
    
    # 注意：Algolia API Key 时效性很短，不使用缓存
    # 每次都从网站动态提取最新凭证
    
    # Algolia 备用域名列表（用于容错）
    ALGOLIA_HOSTS = [
        "{app_id}-dsn.algolia.net",      # 主域名
        "{app_id}-1.algolianet.com",     # 备用域名 1
        "{app_id}-2.algolianet.com",     # 备用域名 2
        "{app_id}-3.algolianet.com"      # 备用域名 3
    ]
    
    def __init__(self, referer_url: str, id_handler_type: str = "clip_id", request_handler: Optional[Request] = None):
        self.referer_url = referer_url
        self.id_handler_type = id_handler_type  # "clip_id" or "site_and_clip_id"
        self.index_name = "all_scenes"
        self.app_id = None
        self.api_key = None
        self.content_sources = []
        self.request = request_handler  # 使用项目的 Request 类
        
        # Algolia API Key 时效性很短，不使用缓存
        # 每次都从网站动态提取最新凭证
        logger.info(f"初始化 Algolia API: {referer_url}")
        
    def _extract_api_credentials(self) -> bool:
        """Extract Algolia API credentials from website HTML"""
        try:
            # 使用项目的 Request 类（带完整浏览器请求头）
            if self.request:
                response = self.request.get(self.referer_url)
                html_content = response.text
            else:
                # 回退到原生 requests 库
                headers = {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36',
                    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
                    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                    'Accept-Encoding': 'gzip, deflate, br',
                    'Connection': 'keep-alive',
                    'Upgrade-Insecure-Requests': '1',
                    'Sec-Ch-Ua': '"Not A(Brand";v="8", "Chromium";v="132"',
                    'Sec-Ch-Ua-Mobile': '?0',
                    'Sec-Ch-Ua-Platform': '"Windows"',
                    'Sec-Fetch-Dest': 'document',
                    'Sec-Fetch-Mode': 'navigate',
                    'Sec-Fetch-Site': 'none',
                    'Sec-Fetch-User': '?1',
                }
                response = requests.get(self.referer_url, headers=headers, timeout=30)
                response.raise_for_status()
                html_content = response.text
            
            # Extract applicationID and apiKey using regex
            api_pattern = r'"applicationID"\s*:\s*"([^"]+)"\s*,\s*"apiKey"\s*:\s*"([^"]+)"'
            match = re.search(api_pattern, html_content)
            
            if match:
                self.app_id = match.group(1)
                self.api_key = match.group(2)
                
                # Extract content sources from window.context
                context_pattern = r'window\.context\s*=\s*({.*?});'
                context_match = re.search(context_pattern, html_content, re.DOTALL)
                
                if context_match:
                    try:
                        context_data = json.loads(context_match.group(1))
                        if 'site' in context_data and 'contentSource' in context_data['site']:
                            self.content_sources = context_data['site']['contentSource']
                    except json.JSONDecodeError:
                        logger.warning(f"Failed to parse context data from {self.referer_url}")
                
                logger.info(f"✓ 成功提取 Algolia 凭证: {self.referer_url}")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to extract API credentials from {self.referer_url}: {e}")
            return False
    
    def _make_api_request(self, payload: Dict[str, Any], headers: Dict[str, str]) -> Optional[Dict[str, Any]]:
        """
        发送 Algolia API 请求，带容错逻辑
        
        Args:
            payload: 请求体
            headers: 请求头
        
        Returns:
            响应数据或 None
        """
        if not self.app_id or not self.api_key:
            logger.error("Missing app_id or api_key")
            return None
        
        # 遍历所有备用域名
        for i, host_template in enumerate(self.ALGOLIA_HOSTS):
            host = host_template.format(app_id=self.app_id)
            
            # 构建 API URL
            api_url = (f"https://{host}/1/indexes/*/queries"
                      f"?x-algolia-agent=Algolia%20for%20JavaScript%20(3.35.1)%3B%20Browser%20(lite)"
                      f"&x-algolia-application-id={self.app_id}"
                      f"&x-algolia-api-key={urllib.parse.quote(self.api_key)}")
            
            try:
                logger.debug(f"尝试 Algolia 域名 {i+1}/{len(self.ALGOLIA_HOSTS)}: {host}")
                
                # 使用 Request 类或 requests 库
                if self.request:
                    response = self.request.post(api_url, json=payload, headers=headers)
                    data = response.json()
                else:
                    response = requests.post(
                        api_url,
                        json=payload,
                        headers=headers,
                        timeout=30
                    )
                    response.raise_for_status()
                    data = response.json()
                
                logger.info(f"✓ Algolia API 请求成功: {host}")
                return data
                
            except Exception as e:
                logger.warning(f"✗ Algolia 域名 {host} 失败: {e}")
                
                # 如果不是最后一个域名，继续尝试下一个
                if i < len(self.ALGOLIA_HOSTS) - 1:
                    logger.info(f"切换到备用域名...")
                    continue
                else:
                    # 所有域名都失败了
                    logger.error(f"所有 Algolia 域名都失败")
                    return None
        
        return None
    
    def search(self, query: str, max_results: int = 100, _retry: bool = True) -> List[Dict[str, Any]]:
        """Search for content using Algolia API"""
        if not self.app_id or not self.api_key:
            if not self._extract_api_credentials():
                raise Exception(f"Failed to extract Algolia credentials from {self.referer_url}")
        
        # Build search parameters
        params = f"query={urllib.parse.quote(query)}&hitsPerPage={max_results}"
        
        # Add content source filters if available
        if self.content_sources:
            facet_filters = []
            for source in self.content_sources:
                facet_filters.append(f'"availableOnSite:{source}"')
            
            facet_filter_str = f'[[{",".join(facet_filters)}]]'
            params += f"&facets={urllib.parse.quote('[\"availableOnSite\"]')}"
            params += f"&maxValuesPerFacet=100"
            params += f"&facetFilters={urllib.parse.quote(facet_filter_str)}"
        
        # Build request payload
        payload = {
            "requests": [{
                "indexName": self.index_name,
                "params": params
            }]
        }
        
        # 构建请求头
        headers = {
            'Content-Type': 'application/json',
            'Referer': self.referer_url,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Origin': self.referer_url.rstrip('/'),
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site'
        }
        
        try:
            # 使用容错逻辑发送请求
            data = self._make_api_request(payload, headers)
            
            if data and 'results' in data and len(data['results']) > 0:
                return data['results'][0].get('hits', [])
            
            return []
            
        except Exception as e:
            error_msg = str(e)
            # 检查是否是凭证过期错误，且允许重试
            # 400/403 Bad Request/Forbidden 可能是凭证过期导致的
            should_retry = False
            if _retry:
                # 检查错误消息中的关键词
                if any(keyword in error_msg for keyword in ['ValidUntil', '400', '403', 'Forbidden', '请求失败']):
                    should_retry = True
                # 检查是否是 NetworkError 且包含 HTTP 错误
                if hasattr(e, '__cause__') and e.__cause__:
                    cause_msg = str(e.__cause__)
                    if '400' in cause_msg or '403' in cause_msg:
                        should_retry = True
            
            if should_retry:
                logger.warning(f"Algolia 凭证可能已过期（错误: {error_msg[:100]}），尝试重新提取...")
                # 重新提取凭证
                if self._extract_api_credentials():
                    logger.info("✓ 成功重新提取凭证，重试搜索...")
                    # 递归调用一次（_retry=False 避免无限循环）
                    try:
                        return self.search(query, max_results, _retry=False)
                    except Exception as retry_error:
                        logger.error(f"重试后仍然失败: {retry_error}")
            
            logger.error(f"Algolia search failed for query '{query}': {e}")
            return []
    
    def search_by_date(self, target_date_str: str, max_results: int = 100, _retry: bool = True) -> List[Dict[str, Any]]:
        """
        按日期搜索内容（使用字符串日期格式）
        
        Args:
            target_date_str: 目标日期字符串（格式: YYYY-MM-DD）
            max_results: 最大结果数
            _retry: 是否允许重试
        
        Returns:
            搜索结果列表
        
        注意：
        - Algolia 的 release_date 字段是字符串格式（YYYY-MM-DD）
        - 我们先搜索所有结果，然后在客户端过滤日期
        """
        if not self.app_id or not self.api_key:
            if not self._extract_api_credentials():
                raise Exception(f"Failed to extract Algolia credentials from {self.referer_url}")
        
        # 搜索空字符串获取所有结果
        # 注意：这里不能使用 numericFilters，因为 release_date 是字符串
        params = f"query=&hitsPerPage={max_results}"
        
        # Add content source filters if available
        if self.content_sources:
            facet_filters = []
            for source in self.content_sources:
                facet_filters.append(f'"availableOnSite:{source}"')
            
            facet_filter_str = f'[[{",".join(facet_filters)}]]'
            params += f"&facets={urllib.parse.quote('[\"availableOnSite\"]')}"
            params += f"&maxValuesPerFacet=100"
            params += f"&facetFilters={urllib.parse.quote(facet_filter_str)}"
        
        # Build request payload
        payload = {
            "requests": [{
                "indexName": self.index_name,
                "params": params
            }]
        }
        
        # 构建请求头
        headers = {
            'Content-Type': 'application/json',
            'Referer': self.referer_url,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Origin': self.referer_url.rstrip('/'),
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site'
        }
        
        try:
            # 使用容错逻辑发送请求
            data = self._make_api_request(payload, headers)
            
            if data and 'results' in data and len(data['results']) > 0:
                all_hits = data['results'][0].get('hits', [])
                
                # 在客户端过滤日期
                matched_hits = []
                for hit in all_hits:
                    release_date = hit.get('release_date', '')
                    if isinstance(release_date, str) and release_date.startswith(target_date_str):
                        matched_hits.append(hit)
                
                logger.info(f"✓ 按日期搜索成功: 总共 {len(all_hits)} 个结果，匹配 {len(matched_hits)} 个")
                return matched_hits
            
            return []
            
        except Exception as e:
            error_msg = str(e)
            # 检查是否是凭证过期错误，且允许重试
            should_retry = False
            if _retry:
                if any(keyword in error_msg for keyword in ['ValidUntil', '400', '403', 'Forbidden', '请求失败']):
                    should_retry = True
                if hasattr(e, '__cause__') and e.__cause__:
                    cause_msg = str(e.__cause__)
                    if '400' in cause_msg or '403' in cause_msg:
                        should_retry = True
            
            if should_retry:
                logger.warning(f"Algolia 凭证可能已过期（错误: {error_msg[:100]}），尝试重新提取...")
                if self._extract_api_credentials():
                    logger.info("✓ 成功重新提取凭证，重试搜索...")
                    try:
                        return self.search_by_date(target_date_str, max_results, _retry=False)
                    except Exception as retry_error:
                        logger.error(f"重试后仍然失败: {retry_error}")
            
            logger.error(f"Algolia search_by_date failed: {e}")
            return []
    
    def get_by_id(self, external_id: str, _retry: bool = True) -> Optional[Dict[str, Any]]:
        """Get content by ID using Algolia API"""
        if not self.app_id or not self.api_key:
            if not self._extract_api_credentials():
                raise Exception(f"Failed to extract Algolia credentials from {self.referer_url}")
        
        # Parse ID based on handler type
        if self.id_handler_type == "site_and_clip_id":
            if '/' not in external_id:
                raise ValueError(f"Invalid ID format for site_and_clip_id: {external_id}")
            site_name, clip_id = external_id.split('/', 1)
            facet_filter = f'[["sitename:{site_name}"],["clip_id:{clip_id}"]]'
        else:  # clip_id only
            clip_id = external_id
            facet_filter = f'["clip_id:{clip_id}"]'
        
        # Build request payload
        payload = {
            "requests": [{
                "indexName": self.index_name,
                "params": f"query=&facetFilters={urllib.parse.quote(facet_filter)}&hitsPerPage=100"
            }]
        }
        
        # 构建请求头
        headers = {
            'Content-Type': 'application/json',
            'Referer': self.referer_url,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Origin': self.referer_url.rstrip('/'),
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site'
        }
        
        try:
            # 使用容错逻辑发送请求
            data = self._make_api_request(payload, headers)
            
            if data and 'results' in data and len(data['results']) > 0:
                hits = data['results'][0].get('hits', [])
                
                # Find matching hit
                for hit in hits:
                    if self.id_handler_type == "site_and_clip_id":
                        if (hit.get('sitename', '').lower() == site_name.lower() and 
                            str(hit.get('clip_id', '')) == str(clip_id)):
                            return hit
                    else:
                        if str(hit.get('clip_id', '')) == str(clip_id):
                            return hit
            
            return None
            
        except Exception as e:
            error_msg = str(e)
            # 检查是否是凭证过期错误，且允许重试
            # 400/403 Bad Request/Forbidden 可能是凭证过期导致的
            should_retry = False
            if _retry:
                # 检查错误消息中的关键词
                if any(keyword in error_msg for keyword in ['ValidUntil', '400', '403', 'Forbidden', '请求失败']):
                    should_retry = True
                # 检查是否是 NetworkError 且包含 HTTP 错误
                if hasattr(e, '__cause__') and e.__cause__:
                    cause_msg = str(e.__cause__)
                    if '400' in cause_msg or '403' in cause_msg:
                        should_retry = True
            
            if should_retry:
                logger.warning(f"Algolia 凭证可能已过期（错误: {error_msg[:100]}），尝试重新提取...")
                # 重新提取凭证
                if self._extract_api_credentials():
                    logger.info("✓ 成功重新提取凭证，重试查询...")
                    # 递归调用一次（_retry=False 避免无限循环）
                    try:
                        return self.get_by_id(external_id, _retry=False)
                    except Exception as retry_error:
                        logger.error(f"重试后仍然失败: {retry_error}")
            
            logger.error(f"Algolia get_by_id failed for ID '{external_id}': {e}")
            return None


class AbstractGammaEntertainmentScraper(BaseScraper):
    """Base scraper for all Gamma Entertainment network sites using Algolia API"""
    
    def __init__(self, site_config: GammaSiteConfig = None, config: Dict[str, Any] = None):
        # Initialize base scraper with config
        if config is None:
            config = {}
        # 启用 cloudscraper 绕过 Cloudflare（Evilangel 等站点需要）
        super().__init__(config, use_scraper=True)
        
        # 如果没有提供 site_config，加载站点配置
        if site_config is None:
            self.sites_config = self._load_sites_config()
            # 使用第一个站点作为默认配置（通常是主站）
            if self.sites_config:
                first_site = list(self.sites_config.values())[0]
                site_config = GammaSiteConfig(
                    site_name=first_site['name'],
                    domain=first_site['domain'],
                    network=first_site['network'],
                    enabled=first_site.get('enabled', True),
                    priority=first_site.get('priority', 80)
                )
            else:
                # 如果没有配置文件，使用默认配置
                site_config = GammaSiteConfig(
                    site_name="Gamma Entertainment",
                    domain="gammaentertainment.com",
                    network="GammaEntertainment",
                    enabled=True,
                    priority=80
                )
        else:
            # 如果提供了 site_config，也加载完整的站点配置用于查找
            self.sites_config = self._load_sites_config()
        
        self.site_config = site_config
        
        # Build referer URL from site config - add www. prefix if needed
        domain = site_config.domain.lower()
        if not domain.startswith('www.'):
            domain = 'www.' + domain
        self.referer_url = f"https://{domain}/en/"
        
        # Determine ID handler type based on site
        # Most Gamma sites use clip_id only, some use site_and_clip_id
        self.id_handler_type = self._get_id_handler_type()
        
        # Initialize Algolia API with Request handler
        self.algolia = AlgoliaAPI(self.referer_url, self.id_handler_type, self.request)
        
        # Image URL patterns
        self.image_url_prefix = "https://images01-fame.gammacdn.com/movies"
        self.actor_image_url_pattern = "https://transform.gammacdn.com/actors/{}/{}500x750.jpg?gravity=face&width=500&height=750&format=jpeg"
        
        # Override image prefix for specific networks
        if "evilangel" in site_config.domain.lower():
            self.image_url_prefix = "https://images01-evilangel.gammacdn.com/movies"
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """加载站点配置"""
        sites = {}
        config_path = Path(__file__).parent.parent.parent / 'config' / 'site' / 'gamma_sites.csv'
        
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            # 跳过注释和标题行
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('site_name'):
                    continue
                
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 6:
                    site_name, domain, code, network, enabled, priority = parts[:6]
                    if enabled.lower() == 'true':
                        sites[site_name.lower()] = {
                            'name': site_name,
                            'domain': domain,
                            'code': code if code else None,
                            'network': network,
                            'priority': int(priority) if priority.isdigit() else 80
                        }
            
            self.logger.info(f"Loaded {len(sites)} Gamma sites from config")
            return sites
            
        except Exception as e:
            self.logger.error(f"Failed to load sites config: {e}")
            return {}
    
    def _find_site_by_name(self, site_name: str) -> Optional[Dict[str, Any]]:
        """
        根据名称查找站点配置
        
        支持两种匹配方式：
        1. 精确匹配系列名（如 Evil Angel）
        2. 网络名匹配（如 GammaEntertainment 匹配任何 network=GammaEntertainment 的条目）
        
        规范化处理：
        - 只保留字母和数字，移除所有其他字符（空格、撇号、连字符等）
        - 转小写
        """
        if not site_name or not hasattr(self, 'sites_config'):
            return None
        
        # 规范化：只保留字母和数字，转小写
        normalized_search = re.sub(r'[^a-zA-Z0-9]', '', site_name).lower()
        
        # 1. 精确匹配系列名（只保留字母数字后）
        for key, site_info in self.sites_config.items():
            normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
            if normalized_search == normalized_key:
                self.logger.debug(f"站点精确匹配: {site_name} -> {site_info['name']}")
                return site_info
        
        # 2. 模糊匹配系列名 - 检查是否包含关键词
        search_words = [w for w in re.split(r'[^a-zA-Z0-9]+', site_name.lower()) if w]
        for key, site_info in self.sites_config.items():
            normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
            if all(word in normalized_key for word in search_words):
                self.logger.debug(f"站点模糊匹配: {site_name} -> {site_info['name']}")
                return site_info
        
        # 3. 网络名匹配
        for key, site_info in self.sites_config.items():
            if site_info['network'].lower() == normalized_search:
                self.logger.debug(f"网络名匹配: {site_name} -> 网络 {site_info['network']} (使用系列 {site_info['name']} 的配置)")
                return site_info
        
        self.logger.debug(f"未找到站点配置: {site_name}")
        return None
    
    def _scrape_impl(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        Implementation of abstract method from BaseScraper
        
        Args:
            query: 搜索关键词（标题、ID 或日期字符串）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
                - 如果指定，只返回匹配该类型的结果
                - 如果不指定，返回第一个搜索结果（任意类型）
            series: 系列名（可选，如果提供则直接使用，不再从 query 中提取）
        
        Returns:
            ScrapeResult 对象或 None
            
        注意：如果需要返回多个结果，使用 scrape_multiple 方法
        
        支持格式：
        - 纯数字 ID: "12345"
        - site/clip_id 格式: "evilangel/12345"
        - 纯标题: "Scene Title"（如果提供了 series 参数）
        - 日期格式: "2026-01-17" 或 "26.01.17"（如果提供了 series 参数）
        
        媒体类型判断：
        - Movie: movie_id > 0 且 movie_title 存在
        - Compilation: compilation 字段有值
        - Scene: 其他情况（默认）
        """
        return self._scrape_single(query, content_type_hint, series)
    
    def scrape_multiple(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        搜索并返回多个结果
        
        Args:
            query: 搜索关键词
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
            series: 系列名
        
        Returns:
            ScrapeResult 列表
        """
        try:
            # 统一使用 _scrape_multiple_scenes 方法
            # 不管是 Scene 还是 Movie 模式，都返回所有匹配的结果
            return self._scrape_multiple_scenes(query, content_type_hint, series)
            
        except Exception as e:
            self.logger.error(f"scrape_multiple 失败: {query}, 错误: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []
    
    def _scrape_multiple_scenes(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        搜索并返回多个匹配的场景
        
        Args:
            query: 搜索标题或日期格式（如 "Evilangel.26.01.23"）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
            series: 系列名
        
        Returns:
            场景列表（每个场景都是独立的 ScrapeResult）
        """
        try:
            # 使用传入的 series 参数
            series_name = series
            search_title = query
            
            # 检测是否是日期查询
            is_date_search = is_date_query(query)
            target_date = None
            
            if is_date_search:
                parsed_series, parsed_date = parse_date_query(query)
                if parsed_date:
                    target_date = parsed_date
                    self.logger.info(f"检测到日期查询: date={target_date.strftime('%Y-%m-%d')}")
                    # 如果解析出系列名，覆盖传入的 series 参数
                    if parsed_series and not series_name:
                        series_name = parsed_series
                        self.logger.info(f"使用解析出的系列名: {series_name}")
            
            if series_name:
                self.logger.info(f"多结果模式：系列={series_name}, 标题={search_title}, content_type_hint={content_type_hint}")
                
                # 根据系列名查找站点配置并更新当前配置
                site_info = self._find_site_by_name(series_name)
                if site_info:
                    # 动态更新站点配置
                    old_referer = self.referer_url
                    
                    self.site_config = GammaSiteConfig(
                        site_name=site_info['name'],
                        domain=site_info['domain'],
                        network=site_info['network'],
                        enabled=True,
                        priority=site_info.get('priority', 80)
                    )
                    
                    # 更新 referer URL
                    domain = self.site_config.domain.lower()
                    if not domain.startswith('www.'):
                        domain = 'www.' + domain
                    self.referer_url = f"https://{domain}/en/"
                    
                    # 如果 referer URL 改变了，需要重新初始化 Algolia API
                    if self.referer_url != old_referer:
                        self.algolia = AlgoliaAPI(self.referer_url, self.id_handler_type, self.request)
                else:
                    self.logger.warning(f"未找到系列 {series_name} 的站点配置")
                    return []
            
            # 使用工具模块清理标题
            # 如果有系列名，从 query 中提取纯标题（不包含系列名）
            if series_name:
                # 使用 extract_series_and_title 提取纯标题
                from utils.query_parser import extract_series_and_title
                _, pure_title = extract_series_and_title(query, self._find_site_by_name)
                cleaned_title = clean_title(pure_title)
                self.logger.debug(f"提取纯标题: '{query}' -> '{pure_title}' -> '{cleaned_title}'")
            else:
                # 没有系列名，直接清理原始标题
                cleaned_title = clean_title(search_title)
            
            # 根据查询类型选择搜索方法
            if is_date_search and target_date:
                # 按日期搜索
                target_date_str = target_date.strftime('%Y-%m-%d')
                self.logger.info(f"按日期搜索: {target_date_str}")
                hits = self.algolia.search_by_date(target_date_str)
            else:
                # 按标题搜索
                self.logger.info(f"按标题搜索: {cleaned_title}")
                hits = self.algolia.search(cleaned_title)
            
            if not hits:
                self.logger.warning(f"未找到搜索结果: {search_title}")
                return []
            
            self.logger.info(f"找到 {len(hits)} 个搜索结果")
            
            # 过滤匹配的结果
            if is_date_search:
                # 日期搜索：所有结果都是匹配的（已经按日期过滤）
                matched_hits = [(100.0, hit) for hit in hits]
                self.logger.info(f"日期搜索匹配到 {len(matched_hits)} 个结果")
            else:
                # 标题搜索：先尝试精确匹配
                from utils.query_parser import calculate_title_match_score
                
                # 标准化查询字符串用于精确匹配（使用 cleaned_title，因为搜索时用的也是 cleaned_title）
                normalized_query = self._normalize_title(cleaned_title)
                self.logger.info(f"标准化查询: '{cleaned_title}' -> '{normalized_query}'")
                
                # 第一步：查找精确匹配
                exact_matches = []
                for hit in hits:
                    hit_title = hit.get('title', '')
                    normalized_hit_title = self._normalize_title(hit_title)
                    
                    if normalized_hit_title == normalized_query:
                        exact_matches.append((100.0, hit))
                        self.logger.info(f"  ✓ 精确匹配: '{hit_title}' (标准化: '{normalized_hit_title}')")
                    else:
                        self.logger.debug(f"  ✗ 不匹配: '{hit_title}' (标准化: '{normalized_hit_title}')")
                
                # 如果找到精确匹配，只返回精确匹配的结果
                if exact_matches:
                    matched_hits = exact_matches
                    self.logger.info(f"✓ 找到 {len(exact_matches)} 个精确匹配的结果，忽略其他 {len(hits) - len(exact_matches)} 个结果")
                else:
                    # 第二步：如果没有精确匹配，使用模糊匹配
                    self.logger.info(f"未找到精确匹配，使用模糊匹配")
                    matched_hits = []
                    for hit in hits:
                        hit_title = hit.get('title', '')
                        score = calculate_title_match_score(cleaned_title, hit_title)
                        
                        # 如果匹配度 >= 0.6，认为是匹配的结果
                        if score >= 0.6:
                            matched_hits.append((score, hit))
                            self.logger.debug(f"  模糊匹配: {hit_title} (分数: {score:.2f})")
                        else:
                            self.logger.debug(f"  跳过: {hit_title} (分数: {score:.2f})")
                    
                    self.logger.info(f"模糊匹配到 {len(matched_hits)} 个结果")
                
                # 按匹配度排序
                matched_hits.sort(key=lambda x: x[0], reverse=True)
                
                if not matched_hits:
                    self.logger.warning(f"没有匹配度足够高的结果")
                    return []
                
                self.logger.info(f"匹配到 {len(matched_hits)} 个结果")
            
            # 为每个匹配的场景创建独立的 ScrapeResult
            results = []
            for i, (score, hit) in enumerate(matched_hits, 1):
                clip_id = str(hit.get('clip_id', ''))
                scene_title = hit.get('title', '')
                self.logger.info(f"  处理场景 {i}/{len(matched_hits)}: {scene_title} (clip_id={clip_id}, 匹配度={score:.2f})")
                
                # 如果指定了系列名，验证结果是否匹配
                if series_name:
                    hit_sitename = hit.get('sitename', '').lower()
                    if not self._is_site_match(series_name, hit_sitename):
                        self.logger.warning(f"    ✗ 站点不匹配: {hit_sitename} != {series_name}")
                        continue
                
                # 获取场景的完整元数据
                metadata = self.get_content_metadata(clip_id)
                if metadata:
                    # 解析为独立的 Scene 结果
                    # 传递 content_type_hint（Scene/Movie/Compilation）
                    scene_result = self._parse_metadata_to_result(metadata, content_type_hint or 'Scene')
                    results.append(scene_result)
                    self.logger.info(f"    ✓ 场景: {scene_result.title}")
                else:
                    self.logger.warning(f"    ✗ 场景 {clip_id} 元数据获取失败")
            
            self.logger.info(f"✓ 返回 {len(results)} 个场景")
            return results
            
        except Exception as e:
            self.logger.error(f"_scrape_multiple_scenes 失败: {query}, 错误: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []
    
    def _scrape_single(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        单个结果刮削（已废弃，保留以兼容旧代码）
        
        新架构下，此方法直接调用 scrape_multiple() 并返回第一个结果
        不再在刮削器层面进行结果选择，统一由 western_scraper_manager 处理
        
        Args:
            query: 搜索关键词（标题、ID 或日期字符串）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
            series: 系列名（可选）
        
        Returns:
            ScrapeResult 对象或 None
        """
        try:
            # 调用 scrape_multiple 获取所有结果
            results = self.scrape_multiple(query, content_type_hint, series)
            
            if not results:
                return None
            
            # 返回第一个结果（不做选择，由上层管理器处理）
            return results[0]
            
        except Exception as e:
            self.logger.error(f"_scrape_single 失败: {query}, 错误: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return None
    
    def _format_date(self, date_value: Any) -> Optional[str]:
        """格式化日期为字符串"""
        if not date_value:
            return None
        try:
            if isinstance(date_value, datetime):
                return date_value.strftime('%Y-%m-%d')
            elif isinstance(date_value, str):
                dt = datetime.fromisoformat(date_value.replace('Z', '+00:00'))
                return dt.strftime('%Y-%m-%d')
        except Exception as e:
            self.logger.warning(f"日期格式化失败: {date_value}, 错误: {e}")
        return None
    
    def _is_site_match(self, series_name: str, hit_sitename: str) -> bool:
        """
        检查搜索结果的站点名是否匹配指定的系列名
        
        Args:
            series_name: 指定的系列名
            hit_sitename: 搜索结果中的站点名
        
        Returns:
            True 如果匹配
        """
        # 规范化
        normalized_series = re.sub(r'[^a-zA-Z0-9]', '', series_name).lower()
        normalized_hit = re.sub(r'[^a-zA-Z0-9]', '', hit_sitename).lower()
        
        return (normalized_series == normalized_hit or
                normalized_series in normalized_hit or
                normalized_hit in normalized_series)
    
    def _is_valid_id(self, query: str) -> bool:
        """检查是否为有效的 ID 格式"""
        if self.id_handler_type == "site_and_clip_id":
            # 格式: sitename/clip_id
            return '/' in query and query.split('/')[1].isdigit()
        else:
            # 格式: clip_id (纯数字)
            return query.isdigit()
    
    def _parse_metadata_to_result(self, metadata: Dict[str, Any], content_type_hint: Optional[str] = None, scenes: Optional[List[Dict[str, Any]]] = None) -> ScrapeResult:
        """
        将元数据转换为 ScrapeResult 对象
        
        Args:
            metadata: 元数据字典
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
            scenes: 场景列表（保留参数以兼容，但不再使用）
        """
        result = self._create_result()
        
        try:
            # 基本信息
            result.title = metadata.get('title', '')
            result.overview = metadata.get('description', '')
            result.code = metadata.get('id', '')
            
            # 原始标题映射
            original_title = metadata.get('original_title', '')
            movie_title = metadata.get('movie_title', '')
            movie_id = metadata.get('movie_id', 0)
            
            if original_title:
                result.original_title = original_title
            elif movie_title and movie_id:
                # 如果有 movie_title 和 movie_id，将 movie_title 映射到 original_title
                result.original_title = movie_title
            
            # 视频链接
            video_url = metadata.get('url', '')
            trailer_urls = metadata.get('trailer_urls', [])
            cover_video_url = metadata.get('cover_video_url', '')
            
            # 优先使用预告片视频直接链接，如果没有则使用网页链接
            if trailer_urls:
                result.preview_video_urls = trailer_urls
            elif video_url:
                result.preview_video_urls = [video_url]
            
            # 封面视频（短小的视频缩略图，用于悬停播放）
            if cover_video_url:
                result.cover_video_url = cover_video_url
            
            # 发布日期
            release_date = metadata.get('release_date')
            if release_date:
                try:
                    if isinstance(release_date, datetime):
                        result.release_date = release_date.strftime('%Y-%m-%d')
                        result.year = release_date.year
                    elif isinstance(release_date, str):
                        dt = datetime.fromisoformat(release_date.replace('Z', '+00:00'))
                        result.release_date = dt.strftime('%Y-%m-%d')
                        result.year = dt.year
                except Exception as e:
                    self.logger.warning(f"日期解析失败: {release_date}, 错误: {e}")
            
            # 时长（秒转分钟）
            duration_seconds = metadata.get('duration', 0)
            if duration_seconds:
                result.runtime = int(duration_seconds / 60)
            
            # 工作室和系列
            result.studio = self.site_config.network
            result.series = metadata.get('site_name', '') or metadata.get('series_name', '') or self.site_config.site_name
            
            # 演员
            actors = metadata.get('actors', [])
            result.actors = [actor['name'] for actor in actors if actor.get('name')]
            
            # 导演
            directors = metadata.get('directors', [])
            if directors:
                result.director = ', '.join(directors)
            
            # 类型/标签
            result.genres = metadata.get('genres', [])
            
            # 图片
            images = metadata.get('images', [])
            if images:
                result.poster_url = images[0]  # 第一张作为海报
                result.preview_urls = images  # 所有图片作为预览
            
            # 评分
            rating_info = metadata.get('rating')
            if rating_info and isinstance(rating_info, dict):
                result.rating = rating_info.get('value', 0) * 10  # 转换为 0-10 分制
            
            # 媒体类型判断
            # 如果有 content_type_hint，优先使用
            if content_type_hint:
                if content_type_hint.lower() == 'movie':
                    result.media_type = 'Movie'
                elif content_type_hint.lower() == 'compilation':
                    result.media_type = 'Compilation'
                else:
                    result.media_type = 'Scene'
            else:
                # 根据数据判断
                compilation = metadata.get('compilation', '')
                
                if compilation and compilation not in ['', '0', 0, False]:
                    # 这是合集
                    result.media_type = 'Compilation'
                else:
                    # 所有其他情况都是 Scene（因为都有 clip_id）
                    result.media_type = 'Scene'
            
            # 来源信息
            result.source = f'Gamma-{self.site_config.network}'
            result.country = 'US'
            result.language = 'en'
            
            # 详细日志
            self.logger.info(f"✓ Gamma 刮削成功: {result.title}")
            self.logger.info(f"  - 识别号: {result.code}")
            self.logger.info(f"  - 媒体类型: {result.media_type}")
            self.logger.info(f"  - 封面视频: {result.cover_video_url}")
            self.logger.info(f"  - 视频预览: {result.preview_video_urls}")
            self.logger.info(f"  - 工作室: {result.studio}")
            self.logger.info(f"  - 系列: {result.series}")
            self.logger.info(f"  - 演员数: {len(result.actors)}")
            self.logger.info(f"  - 类型数: {len(result.genres)}")
            self.logger.info(f"  - 预览图数: {len(result.preview_urls)}")
            self.logger.info(f"  - 发布日期: {result.release_date}")
            self.logger.info(f"  - 时长: {result.runtime} 分钟")
            self.logger.info(f"  - 视频链接: {video_url}")
            
            return result
            
        except Exception as e:
            self.logger.error(f"解析元数据失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return result
    
    def _get_id_handler_type(self) -> str:
        """Determine ID handler type based on site configuration"""
        # Sites that use site_and_clip_id format
        site_and_clip_id_sites = [
            'dogfartnetwork', '21sextury', 'blowpass'
        ]
        
        site_name = self.site_config.site_name.lower().replace(' ', '')
        for site in site_and_clip_id_sites:
            if site in site_name:
                return "site_and_clip_id"
        
        return "clip_id"
    
    def search_content(self, query: str, **kwargs) -> List[Dict[str, Any]]:
        """Search for content using Algolia API"""
        try:
            hits = self.algolia.search(query)
            results = []
            
            # 标准化查询字符串用于匹配（移除特殊字符，转小写）
            normalized_query = self._normalize_title(query)
            
            for hit in hits:
                # Build ID based on handler type
                if self.id_handler_type == "site_and_clip_id":
                    content_id = f"{hit.get('sitename', '')}/{hit.get('clip_id', '')}"
                else:
                    content_id = str(hit.get('clip_id', ''))
                
                title = hit.get('title', '')
                result = {
                    'id': content_id,
                    'title': title,
                    'release_date': self._parse_date(hit.get('release_date')),
                    'site_name': hit.get('sitename', ''),
                    'views': hit.get('views', 0),
                    'raw_data': hit
                }
                results.append(result)
            
            # 如果有结果，尝试精确匹配
            if results:
                # 查找标题完全匹配的结果
                exact_matches = []
                for result in results:
                    normalized_title = self._normalize_title(result['title'])
                    if normalized_title == normalized_query:
                        exact_matches.append(result)
                
                # 如果找到精确匹配，只返回精确匹配的结果
                if exact_matches:
                    logger.info(f"Found {len(exact_matches)} exact match(es) for query '{query}'")
                    return exact_matches
                
                # 否则返回所有结果
                logger.info(f"No exact match found, returning all {len(results)} results for query '{query}'")
            
            return results
            
        except Exception as e:
            logger.error(f"Search failed for query '{query}': {e}")
            return []
    
    def _normalize_title(self, title: str) -> str:
        """标准化标题用于匹配（移除特殊字符，转小写）"""
        import re
        # 移除特殊字符，只保留字母、数字和空格
        normalized = re.sub(r'[^\w\s]', '', title.lower())
        # 移除多余的空格
        normalized = ' '.join(normalized.split())
        return normalized
    
    def get_content_metadata(self, content_id: str) -> Optional[Dict[str, Any]]:
        """Get detailed metadata for specific content"""
        try:
            hit = self.algolia.get_by_id(content_id)
            if not hit:
                return None
            
            # Build video URL (网页链接)
            video_url = self._build_video_url(hit)
            
            # Extract trailer video URLs (预告片视频直接链接)
            trailer_urls = self._extract_trailer_urls(hit)
            
            # Extract cover video URL (封面视频缩略图)
            cover_video_url = self._extract_backdrop_url(hit)
            
            # Extract metadata
            metadata = {
                'id': content_id,
                'title': hit.get('title', ''),
                'original_title': hit.get('original_title', ''),  # 原始标题（如果有）
                'description': self._clean_description(hit.get('description', '')),
                'release_date': self._parse_date(hit.get('release_date')),
                'duration': hit.get('length', 0),  # in seconds
                'site_name': hit.get('sitename', ''),
                'studio_name': hit.get('studio_name', ''),
                'series_name': hit.get('serie_name', ''),
                'movie_id': hit.get('movie_id', 0),  # Movie ID（用于判断是否是 Movie）
                'movie_title': hit.get('movie_title', ''),  # Movie 标题
                'compilation': hit.get('compilation', ''),  # 是否是合集
                'url': video_url,  # 网页链接
                'trailer_urls': trailer_urls,  # 预告片视频直接链接
                'cover_video_url': cover_video_url,  # 封面视频缩略图
                'actors': self._extract_actors(hit),
                'directors': self._extract_directors(hit),
                'genres': self._extract_genres(hit),
                'images': self._extract_images(hit),
                'rating': self._extract_rating(hit),
                'views': hit.get('views', 0)
            }
            
            return metadata
            
        except Exception as e:
            logger.error(f"Failed to get metadata for ID '{content_id}': {e}")
            return None
    
    
    def _build_video_url(self, hit: Dict[str, Any], force_scene_url: bool = False) -> str:
        """Build video URL from hit data - to be overridden by subclasses
        
        Args:
            hit: Algolia 搜索结果
            force_scene_url: 强制返回 Scene URL（用于场景列表）
        """
        # Default implementation - subclasses should override this
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        movie_id = hit.get('movie_id', 0)
        url_movie_title = hit.get('url_movie_title', '')
        title = hit.get('title', '')
        movie_title = hit.get('movie_title', '')
        
        # 如果强制返回 Scene URL，直接返回
        if force_scene_url:
            return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"
        
        # 判断是 Movie 还是 Scene
        # 如果 title == movie_title，说明这是 Movie 条目
        if title and movie_title and title.lower().strip() == movie_title.lower().strip() and movie_id:
            # Movie URL: /en/movie/{url_movie_title}/{movie_id}
            return f"https://{self.site_config.domain}/en/movie/{url_movie_title}/{movie_id}"
        else:
            # Scene URL: /en/video/{sitename}/{url_title}/{clip_id}
            return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"
    
    def _extract_actors(self, hit: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract actor information from hit data"""
        actors = []
        
        # Process both 'actors' and 'female_actors' fields
        for actor_list_key in ['actors', 'female_actors']:
            actor_list = hit.get(actor_list_key, [])
            if isinstance(actor_list, list):
                for actor in actor_list:
                    if isinstance(actor, dict):
                        actor_data = {
                            'name': actor.get('name', ''),
                            'gender': actor.get('gender', ''),
                            'image_url': None
                        }
                        
                        # Build actor image URL if actor_id is available
                        actor_id = actor.get('actor_id')
                        if actor_id:
                            actor_data['image_url'] = self.actor_image_url_pattern.format(actor_id, actor_id)
                        
                        actors.append(actor_data)
        
        return actors
    
    def _extract_directors(self, hit: Dict[str, Any]) -> List[str]:
        """Extract director names from hit data"""
        directors = []
        director_list = hit.get('directors', [])
        
        if isinstance(director_list, list):
            for director in director_list:
                if isinstance(director, dict):
                    name = director.get('name', '')
                    if name:
                        directors.append(name)
        
        return directors
    
    def _extract_genres(self, hit: Dict[str, Any]) -> List[str]:
        """Extract genre/category information from hit data"""
        genres = []
        categories = hit.get('categories', [])
        
        if isinstance(categories, list):
            for category in categories:
                if isinstance(category, dict):
                    name = category.get('name', '')
                    if name:
                        genres.append(name)
                    else:
                        # Handle categories with empty names but valid IDs
                        category_id = category.get('category_id', '')
                        mapped_name = self._map_category_id(category_id)
                        if mapped_name:
                            genres.append(mapped_name)
        
        return genres
    
    def _map_category_id(self, category_id: str) -> Optional[str]:
        """Map category IDs to names for categories with empty names"""
        category_mapping = {
            "180": "Straight",
            "187": "HD Porn", 
            "3804": "one on one",
            "4549": "Sci-Fi",
            "4572": "Award-Winning"
        }
        return category_mapping.get(category_id)
    
    def _extract_images(self, hit: Dict[str, Any]) -> List[str]:
        """Extract image URLs from hit data"""
        images = []
        pictures = hit.get('pictures', {})
        
        if isinstance(pictures, dict):
            # Try to get the best quality image
            image_url = None
            
            # Check NSFW top images first
            nsfw = pictures.get('nsfw', {})
            if isinstance(nsfw, dict):
                top_images = nsfw.get('top', {})
                if isinstance(top_images, dict) and top_images:
                    image_url = list(top_images.values())[0]
            
            # Fallback to other image sizes
            if not image_url:
                for size in ['960x540', '638x360']:
                    size_key = size.replace('x', 'x')  # Ensure correct format
                    if size_key in pictures:
                        image_url = pictures[size_key]
                        break
            
            if image_url:
                # Add image URL prefix if needed
                if not image_url.startswith('http'):
                    image_url = self.image_url_prefix + image_url
                images.append(image_url)
        
        return images
    
    def _extract_backdrop_url(self, hit: Dict[str, Any]) -> Optional[str]:
        """
        Extract backdrop/cover video URL from hit data
        
        Returns:
            封面视频 URL（videothumb.gammacdn.com）
            这是一个短小的视频缩略图，用于悬停播放
        """
        current_clip_id = str(hit.get('clip_id', ''))
        if current_clip_id:
            return f"https://videothumb.gammacdn.com/500x281/{current_clip_id}.mp4"
        return None
    
    def _extract_trailer_urls(self, hit: Dict[str, Any]) -> List[Dict[str, str]]:
        """
        Extract trailer video URLs from hit data
        
        Returns:
            List of trailer video dicts with quality info
            格式: [{'quality': '1080P', 'url': 'https://...'}, ...]
            
        注意：
        - videothumb.gammacdn.com 的链接是封面视频缩略图，不应该放在这里
        - 只返回 trailers-fame.gammacdn.com 等真正的预告片视频链接
        - 优先从 video_formats 字段提取（包含所有清晰度的正确链接）
        - 如果 video_formats 不存在，回退到 trailers 字段
        """
        trailer_list = []
        
        # 优先从 video_formats 字段提取（这里有所有清晰度的正确链接）
        video_formats = hit.get('video_formats', [])
        if video_formats and isinstance(video_formats, list):
            # 按清晰度从高到低排序
            quality_priority = {'2160p': 0, '1080p': 1, '720p': 2, '540p': 3, '480p': 4, '360p': 5, '240p': 6, '160p': 7}
            
            # 提取所有视频格式
            for video_format in video_formats:
                if isinstance(video_format, dict):
                    format_name = video_format.get('format', '')
                    trailer_url = video_format.get('trailer_url', '')
                    
                    if trailer_url and isinstance(trailer_url, str):
                        # 跳过封面视频缩略图（videothumb）
                        if 'videothumb.gammacdn.com' in trailer_url:
                            continue
                        
                        # 标准化清晰度名称
                        if format_name == '2160p':
                            quality = '4K'
                        else:
                            quality = format_name.upper()
                        
                        trailer_list.append({
                            'quality': quality,
                            'url': trailer_url,
                            '_priority': quality_priority.get(format_name.lower(), 99)
                        })
            
            # 按优先级排序
            trailer_list.sort(key=lambda x: x['_priority'])
            
            # 移除 _priority 字段
            for item in trailer_list:
                del item['_priority']
            
            if trailer_list:
                return trailer_list
        
        # 回退：检查 trailer/trailers 字段
        trailer_data = hit.get('trailer') or hit.get('trailers')
        
        if trailer_data:
            if isinstance(trailer_data, dict):
                # 按清晰度优先级排序（从高到低）
                quality_order = ['4k', '2160p', '1080p', '720p', '540p', '480p', '360p', '240p', '160p']
                
                for quality in quality_order:
                    if quality in trailer_data:
                        url = trailer_data[quality]
                        if url and isinstance(url, str):
                            # 跳过封面视频缩略图（videothumb）
                            if 'videothumb.gammacdn.com' in url:
                                continue
                            
                            # 标准化清晰度名称
                            if quality == '4k' or quality == '2160p':
                                quality_name = '4K'
                            else:
                                quality_name = quality.upper()
                            
                            trailer_list.append({
                                'quality': quality_name,
                                'url': url
                            })
                
                # If no quality-specific URLs, try to get any URL from the dict
                if not trailer_list:
                    for key, value in trailer_data.items():
                        if isinstance(value, str) and value.startswith('http'):
                            # 跳过封面视频缩略图（videothumb）
                            if 'videothumb.gammacdn.com' in value:
                                continue
                            # 尝试从 key 中提取清晰度
                            quality = key.upper() if key else 'Unknown'
                            trailer_list.append({
                                'quality': quality,
                                'url': value
                            })
            elif isinstance(trailer_data, str):
                # Single trailer URL
                if trailer_data.startswith('http'):
                    # 跳过封面视频缩略图（videothumb）
                    if 'videothumb.gammacdn.com' not in trailer_data:
                        # 尝试从 URL 中提取清晰度
                        quality = self._extract_quality_from_url(trailer_data)
                        trailer_list.append({
                            'quality': quality,
                            'url': trailer_data
                        })
            elif isinstance(trailer_data, list):
                # List of trailer URLs
                for item in trailer_data:
                    if isinstance(item, str) and item.startswith('http'):
                        # 跳过封面视频缩略图（videothumb）
                        if 'videothumb.gammacdn.com' not in item:
                            quality = self._extract_quality_from_url(item)
                            trailer_list.append({
                                'quality': quality,
                                'url': item
                            })
                    elif isinstance(item, dict):
                        # Extract URLs from dict items
                        for key, value in item.items():
                            if isinstance(value, str) and value.startswith('http'):
                                # 跳过封面视频缩略图（videothumb）
                                if 'videothumb.gammacdn.com' not in value:
                                    quality = key.upper() if key else 'Unknown'
                                    trailer_list.append({
                                        'quality': quality,
                                        'url': value
                                    })
        
        # 尝试从 pictures 字段中查找预告片
        if not trailer_list:
            pictures = hit.get('pictures', {})
            if isinstance(pictures, dict):
                # 查找 trailer 相关的键
                for key, value in pictures.items():
                    if 'trailer' in key.lower() or 'video' in key.lower():
                        if isinstance(value, str) and value.startswith('http'):
                            # 跳过封面视频缩略图（videothumb）
                            if 'videothumb.gammacdn.com' not in value:
                                quality = self._extract_quality_from_url(value)
                                trailer_list.append({
                                    'quality': quality,
                                    'url': value
                                })
                        elif isinstance(value, dict):
                            for sub_key, sub_value in value.items():
                                if isinstance(sub_value, str) and sub_value.startswith('http'):
                                    # 跳过封面视频缩略图（videothumb）
                                    if 'videothumb.gammacdn.com' not in sub_value:
                                        quality = sub_key.upper() if sub_key else 'Unknown'
                                        trailer_list.append({
                                            'quality': quality,
                                            'url': sub_value
                                        })
        
        # 去重（保持顺序）
        seen = set()
        unique_trailer_list = []
        for item in trailer_list:
            url = item['url']
            if url not in seen:
                seen.add(url)
                unique_trailer_list.append(item)
        
        return unique_trailer_list
    
    def _extract_quality_from_url(self, url: str) -> str:
        """从 URL 中提取清晰度信息"""
        import re
        # 尝试匹配常见的清晰度模式
        patterns = [
            r'_(\d+p)\.mp4',  # _1080p.mp4
            r'_(\d+k)\.mp4',  # _4k.mp4
            r'/(\d+p)/',      # /1080p/
            r'/(\d+k)/',      # /4k/
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url, re.IGNORECASE)
            if match:
                return match.group(1).upper()
        
        return 'Unknown'
        seen = set()
        unique_trailer_urls = []
        for url in trailer_urls:
            if url not in seen:
                seen.add(url)
                unique_trailer_urls.append(url)
        
        return unique_trailer_urls
    
    def _extract_rating(self, hit: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract rating information from hit data"""
        ratings_up = hit.get('ratings_up', 0)
        ratings_down = hit.get('ratings_down', 0)
        total_ratings = ratings_up + ratings_down
        
        if total_ratings > 0:
            rating_value = ratings_up / total_ratings
            return {
                'value': rating_value,
                'scale': 1.0,
                'votes': total_ratings
            }
        
        return None
    
    def _clean_description(self, description: str) -> str:
        """Clean HTML tags from description"""
        if not description:
            return ""
        
        # Replace HTML line breaks with newlines
        description = description.replace('<br></br>', '\n')
        description = description.replace('<br/>', '\n')
        description = description.replace('<br>', '\n')
        
        # Remove other HTML tags
        description = re.sub(r'<[^>]+>', '', description)
        
        return description.strip()
    
    def _parse_date(self, date_str: Any) -> Optional[datetime]:
        """Parse date string to datetime object"""
        if not date_str:
            return None
        
        try:
            if isinstance(date_str, str):
                # Try different date formats
                for fmt in ['%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%SZ']:
                    try:
                        return datetime.strptime(date_str, fmt)
                    except ValueError:
                        continue
            elif isinstance(date_str, (int, float)):
                # Unix timestamp
                return datetime.fromtimestamp(date_str)
        except Exception as e:
            logger.warning(f"Failed to parse date '{date_str}': {e}")
        
        return None


# Specific scraper implementations for different Gamma Entertainment networks

class GammaEntertainmentScraper(AbstractGammaEntertainmentScraper):
    """Scraper for main Gamma Entertainment sites"""
    
    def _build_video_url(self, hit: Dict[str, Any], force_scene_url: bool = False) -> str:
        """Build video URL for Gamma Entertainment sites
        
        Args:
            hit: Algolia 搜索结果
            force_scene_url: 强制返回 Scene URL（用于场景列表）
        """
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        movie_id = hit.get('movie_id', 0)
        url_movie_title = hit.get('url_movie_title', '')
        title = hit.get('title', '')
        movie_title = hit.get('movie_title', '')
        
        # 如果强制返回 Scene URL，直接返回
        if force_scene_url:
            return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"
        
        # 判断是 Movie 还是 Scene
        if title and movie_title and title.lower().strip() == movie_title.lower().strip() and movie_id:
            # Movie URL
            return f"https://{self.site_config.domain}/en/movie/{url_movie_title}/{movie_id}"
        else:
            # Scene URL
            return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"


class BlowPassScraper(AbstractGammaEntertainmentScraper):
    """Scraper for BlowPass network sites"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for BlowPass sites"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"


class cls21SexturyScraper(AbstractGammaEntertainmentScraper):
    """Scraper for 21Sextury network sites"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for 21Sextury sites"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"


class DogfartNetworkScraper(AbstractGammaEntertainmentScraper):
    """Scraper for Dogfart Network sites"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for Dogfart Network sites"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/-/{clip_id}"


class MommysBoyScraper(AbstractGammaEntertainmentScraper):
    """Scraper for Mommy's Boy site"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for Mommy's Boy"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"


class WhiteGhettoScraper(AbstractGammaEntertainmentScraper):
    """Scraper for White Ghetto network sites"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for White Ghetto sites"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"


class ZeroToleranceFilmsScraper(AbstractGammaEntertainmentScraper):
    """Scraper for Zero Tolerance Films network sites"""
    
    def _build_video_url(self, hit: Dict[str, Any]) -> str:
        """Build video URL for Zero Tolerance Films sites"""
        clip_id = hit.get('clip_id', '')
        url_title = hit.get('url_title', '')
        sitename = hit.get('sitename', '')
        
        return f"https://{self.site_config.domain}/en/video/{sitename}/{url_title}/{clip_id}"