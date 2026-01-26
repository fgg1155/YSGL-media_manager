#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Hustler_Network_Scraper.py

Python implementation of Hustler Network Scraper from C# source.
Handles all Hustler network sites using Builder.io API.

Based on: AdultScraper.Shared/AbstractHustlerScraper.cs
"""

import json
import re
import requests
import urllib.parse
import yaml
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
import logging
import sys
from pathlib import Path

# Add parent directories to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from base_scraper import BaseScraper
from web.request import Request

logger = logging.getLogger(__name__)


# Simple site config class for Hustler sites
class HustlerSiteConfig:
    """Configuration for Hustler sites"""
    
    def __init__(self, site_name: str, domain: str, network: str = "Hustler", 
                 enabled: bool = True, priority: int = 80):
        self.site_name = site_name
        self.domain = domain
        self.network = network
        self.enabled = enabled
        self.priority = priority


class HustlerAPI:
    """Handles WordPress REST API interactions for Hustler sites"""
    
    def __init__(self, base_url: str, wp_api_base: str, image_url_prefix: str):
        self.base_url = base_url.rstrip('/')
        self.wp_api_base = wp_api_base
        self.search_api_url = f"{self.wp_api_base}/search"
        self.videos_api_url = f"{self.wp_api_base}/videos"  # 自定义文章类型
        self.image_url_prefix = image_url_prefix
        
    def search(self, query: str, page: int = 1, page_size: int = 30) -> List[Dict[str, Any]]:
        """Search for content using WordPress REST API"""
        try:
            params = {
                'search': query,
                'per_page': page_size,
                'page': page,
                'subtype': 'videos'  # 只搜索视频类型
            }
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'application/json, text/plain, */*',
                'Accept-Language': 'en-US,en;q=0.9'
            }
            
            logger.info(f"[Hustler API] 搜索请求:")
            logger.info(f"  URL: {self.search_api_url}")
            logger.info(f"  参数: {params}")
            
            response = requests.get(
                self.search_api_url,
                params=params,
                headers=headers,
                timeout=10
            )
            
            logger.info(f"[Hustler API] 响应状态码: {response.status_code}")
            logger.info(f"[Hustler API] 响应头: {dict(response.headers)}")
            
            response.raise_for_status()
            
            search_results = response.json()
            logger.info(f"[Hustler API] 搜索结果数量: {len(search_results) if isinstance(search_results, list) else 'N/A'}")
            
            if search_results:
                import json
                logger.info(f"[Hustler API] 第一个结果完整数据:")
                logger.info(json.dumps(search_results[0] if isinstance(search_results, list) else search_results, indent=2, ensure_ascii=False))
            
            # 获取每个搜索结果的详细信息
            results = []
            for item in search_results:
                # 从搜索结果获取 ID
                post_id = item.get('id')
                if post_id:
                    # 获取视频详情
                    video_data = self.get_video_by_id(post_id)
                    if video_data:
                        results.append(video_data)
            
            return results
            
        except requests.exceptions.HTTPError as e:
            logger.error(f"[Hustler API] HTTP 错误: {e}")
            logger.error(f"[Hustler API] 响应内容: {e.response.text if hasattr(e, 'response') else 'N/A'}")
            return []
        except Exception as e:
            logger.error(f"[Hustler API] 搜索失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return []
    
    def get_video_by_id(self, post_id: int) -> Optional[Dict[str, Any]]:
        """Get video details by ID"""
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'application/json, text/plain, */*',
                'Accept-Language': 'en-US,en;q=0.9'
            }
            
            logger.info(f"[Hustler API] 获取视频详情: post_id={post_id}")
            
            # 使用 _embed 参数获取关联数据（如 featured_media, author 等）
            response = requests.get(
                f"{self.videos_api_url}/{post_id}",
                params={'_embed': '1'},  # 嵌入关联数据
                headers=headers,
                timeout=10
            )
            response.raise_for_status()
            
            video_data = response.json()
            
            # 输出完整的视频数据
            import json
            logger.info(f"[Hustler API] 视频详情完整数据（带 _embed）:")
            logger.info(json.dumps(video_data, indent=2, ensure_ascii=False))
            
            return video_data
            
        except Exception as e:
            logger.error(f"Failed to get video {post_id}: {e}")
            return None
    
    def get_post_by_id(self, post_id: int) -> Optional[Dict[str, Any]]:
        """Get post details by ID (alias for get_video_by_id)"""
        return self.get_video_by_id(post_id)
    
    def get_by_id(self, content_id: str) -> Optional[Dict[str, Any]]:
        """Get content by ID (WordPress post ID or slug)"""
        try:
            # content_id 可能是数字 ID 或 slug
            if content_id.isdigit():
                return self.get_video_by_id(int(content_id))
            else:
                # 通过 slug 搜索
                headers = {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                    'Accept': 'application/json, text/plain, */*',
                    'Accept-Language': 'en-US,en;q=0.9'
                }
                
                response = requests.get(
                    self.videos_api_url,
                    params={'slug': content_id},
                    headers=headers,
                    timeout=10
                )
                response.raise_for_status()
                
                videos = response.json()
                if videos:
                    return videos[0]
                    
            return None
            
        except Exception as e:
            logger.error(f"Hustler get_by_id failed for ID '{content_id}': {e}")
            return None


class AbstractHustlerScraper(BaseScraper):
    """Base scraper for all Hustler network sites using REST API"""
    
    name = 'hustler'
    
    # API 配置（类属性，将从 CSV 配置文件读取）
    WP_API_BASE = None
    SEARCH_API_URL = None
    VIDEOS_API_URL = None
    IMAGE_URL_PREFIX = "https://cdn-hustlernetwork.metartnetwork.com"
    
    def __init__(self, site_config: Optional[HustlerSiteConfig] = None, config: Dict[str, Any] = None):
        # Initialize base scraper with config
        if config is None:
            config = {}
        
        # 加载 IP 映射配置
        self._load_ip_mapping(config)
        
        super().__init__(config, use_scraper=False)
        
        self.site_config = site_config
        
        # 加载站点配置（用于系列名匹配）
        self.sites_config = self._load_sites_config()
        
        # Build base URL from site config (如果提供了)
        if site_config:
            domain = site_config.domain.lower()
            self.base_url = f"https://{domain}"
        else:
            # 使用默认的 Hustler 主站
            self.base_url = "https://hustler.com"
        
        # 如果 WP_API_BASE 还未设置（_load_sites_config 中会设置），使用默认值
        if not self.WP_API_BASE:
            self.WP_API_BASE = "https://hustlerunlimited.com/wp-json/wp/v2"
            logger.warning("未从配置文件读取到 main_api，使用默认值")
        
        self.SEARCH_API_URL = f"{self.WP_API_BASE}/search"
        self.VIDEOS_API_URL = f"{self.WP_API_BASE}/videos"
        
        # Initialize Hustler API
        self.hustler_api = HustlerAPI(
            base_url=self.base_url,
            wp_api_base=self.WP_API_BASE,
            image_url_prefix=self.IMAGE_URL_PREFIX
        )
        
        # Image URL patterns
        self.image_url_prefix = self.IMAGE_URL_PREFIX
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """加载站点配置"""
        sites = {}
        config_path = Path(__file__).parent.parent.parent / 'config' / 'site' / 'hustler_sites.csv'
        
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
                    main_api = parts[6] if len(parts) > 6 else None
                    
                    if enabled.lower() == 'true':
                        sites[site_name.lower()] = {
                            'name': site_name,
                            'domain': domain,
                            'code': code if code else None,
                            'network': network,
                            'priority': int(priority) if priority.isdigit() else 50,
                            'main_api': main_api if main_api else None
                        }
                        
                        # 如果是第一行且有 main_api，设置类属性
                        if main_api and not AbstractHustlerScraper.WP_API_BASE:
                            AbstractHustlerScraper.WP_API_BASE = main_api
                            logger.info(f"从配置文件读取 API 地址: {main_api}")
            
            logger.info(f"Loaded {len(sites)} Hustler sites from config")
            return sites
            
        except Exception as e:
            logger.error(f"Failed to load Hustler sites config: {e}")
            return {}
    
    def _load_ip_mapping(self, config: Dict[str, Any]):
        """加载 IP 映射配置"""
        import yaml
        
        # 确保 network 配置存在
        if 'network' not in config:
            config['network'] = {}
        
        # 如果配置中已经有 ip_mapping，保留它（优先使用传入的配置）
        existing_mapping = config['network'].get('ip_mapping', {})
        
        try:
            # 加载 IP 映射文件: config/map/ip_mapping.yaml
            ip_mapping_path = Path(__file__).parent.parent.parent / 'config' / 'map' / 'ip_mapping.yaml'
            
            if ip_mapping_path.exists():
                with open(ip_mapping_path, 'r', encoding='utf-8') as f:
                    ip_mapping_config = yaml.safe_load(f) or {}
                
                # 过滤掉注释和空值
                ip_mapping = {}
                for domain, ip in ip_mapping_config.items():
                    if isinstance(domain, str) and isinstance(ip, str) and not domain.startswith('#'):
                        ip_mapping[domain] = ip
                
                # 合并：文件中的映射 + 已有的映射（已有的优先）
                ip_mapping.update(existing_mapping)
                
                if ip_mapping:
                    config['network']['ip_mapping'] = ip_mapping
                    logger.info(f"Loaded IP mapping from {ip_mapping_path}: {len(ip_mapping)} domains")
                else:
                    logger.info("No valid IP mappings found")
            else:
                # 文件不存在，但如果有传入的映射，仍然使用
                if existing_mapping:
                    logger.info(f"IP mapping file not found, using provided mapping: {len(existing_mapping)} domains")
                else:
                    logger.info(f"IP mapping file not found at {ip_mapping_path}, using direct connection")
                
        except Exception as e:
            logger.warning(f"Failed to load IP mapping: {e}")
            config['network']['ip_mapping'] = {}
    
    def _scrape_impl(self, query: str, **kwargs) -> List[Dict[str, Any]]:
        """Implementation of abstract method from BaseScraper"""
        return self.search_content(query, **kwargs)
    
    def search_content(self, query: str, **kwargs) -> List[Dict[str, Any]]:
        """Search for content using Hustler API"""
        try:
            videos = self.hustler_api.search(query)
            results = []
            
            for video in videos:
                # WordPress 视频数据结构
                video_id = video.get('id')
                slug = video.get('slug', '')
                title_obj = video.get('title', {})
                title = title_obj.get('rendered', '') if isinstance(title_obj, dict) else str(title_obj)
                
                # 发布日期
                date_str = video.get('date', '')
                release_date = self._parse_date(date_str)
                
                result = {
                    'id': str(video_id),  # 使用 WordPress post ID
                    'slug': slug,
                    'title': title,
                    'release_date': release_date,
                    'site_name': self.site_config.site_name if self.site_config else 'Hustler',
                    'url': video.get('link', ''),
                    'raw_data': video
                }
                results.append(result)
            
            return results
            
        except Exception as e:
            logger.error(f"Search failed for query '{query}': {e}")
            return []
    
    def scrape_multiple(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List['ScrapeResult']:
        """
        搜索并返回多个结果（公共接口）
        
        Args:
            query: 搜索关键词（标题）
            content_type_hint: 内容类型提示（暂不使用）
            series: 系列名（必须提供）
        
        Returns:
            ScrapeResult 列表
        """
        from core.models import ScrapeResult
        
        try:
            logger.info(f"=" * 80)
            logger.info(f"Hustler scrape_multiple 开始")
            logger.info(f"  原始 query: {query}")
            logger.info(f"  series: {series}")
            logger.info(f"  content_type_hint: {content_type_hint}")
            logger.info(f"=" * 80)
            
            if not series:
                logger.warning(f"Hustler 刮削器需要系列名参数")
                return []
            
            # 1. 根据系列名查找站点配置
            site_info = self._find_site_by_name(series)
            if not site_info:
                logger.warning(f"✗ 未找到系列 '{series}' 的站点配置")
                logger.warning(f"  可用的站点: {list(self.sites_config.keys())[:10]}...")
                return []
            
            logger.info(f"✓ 找到站点配置:")
            logger.info(f"  - 站点名: {site_info['name']}")
            logger.info(f"  - 域名: {site_info['domain']}")
            logger.info(f"  - 网络: {site_info['network']}")
            logger.info(f"  - 优先级: {site_info['priority']}")
            
            # 2. 从 query 中提取纯标题（不包含系列名）
            from utils.query_parser import extract_series_and_title
            _, search_title = extract_series_and_title(query, self._find_site_by_name)
            
            logger.info(f"Hustler 多结果模式：系列={series}, 标题={search_title}")
            
            # 搜索内容
            logger.info(f"开始搜索: {search_title}")
            search_results = self.search_content(search_title)
            
            if not search_results:
                logger.warning(f"使用系列 {series} 搜索失败: {search_title}")
                logger.warning(f"WordPress API 未返回任何结果")
                return []
            
            logger.info(f"找到 {len(search_results)} 个搜索结果")
            
            # 转换为 ScrapeResult 对象
            results = []
            for idx, search_result in enumerate(search_results, 1):
                video_id = search_result.get('id')
                video_title = search_result.get('title', '')
                logger.debug(f"  处理结果 {idx}/{len(search_results)}: {video_title} (ID: {video_id})")
                
                if not video_id:
                    logger.warning(f"  跳过：缺少 video_id")
                    continue
                
                # 获取详细元数据
                logger.info(f"  开始获取元数据: video_id={video_id}")
                metadata = self.get_content_metadata(video_id)
                if not metadata:
                    logger.warning(f"  跳过：无法获取元数据")
                    continue
                
                logger.info(f"  元数据获取成功:")
                logger.info(f"    - 图片数量: {len(metadata.get('images', []))}")
                logger.info(f"    - 封面视频: {metadata.get('cover_video', '无')}")
                logger.info(f"    - 预览视频数量: {len(metadata.get('preview_videos', []))}")
                
                # 创建 ScrapeResult
                result = ScrapeResult()
                result.title = metadata.get('title', '')
                result.original_title = metadata.get('title', '')
                result.overview = metadata.get('description', '')
                result.release_date = metadata.get('release_date')
                result.studio = metadata.get('studio_name', 'Hustler')
                result.series = series
                result.poster_url = metadata.get('images', [None])[0] if metadata.get('images') else None
                result.preview_urls = metadata.get('images', [])
                result.actors = [{'name': actor.get('name', '')} for actor in metadata.get('actors', [])]
                result.genres = metadata.get('genres', [])
                result.source = 'hustler'
                
                # 添加封面视频
                cover_video = metadata.get('cover_video')
                if cover_video:
                    result.cover_video_url = cover_video
                
                # 添加预览视频
                preview_videos = metadata.get('preview_videos', [])
                if preview_videos:
                    result.preview_video_urls = preview_videos
                
                results.append(result)
                logger.debug(f"  ✓ 成功创建 ScrapeResult: {result.title}")
            
            logger.info(f"✓ Hustler 返回 {len(results)} 个结果")
            return results
            
        except Exception as e:
            logger.error(f"Hustler scrape_multiple 失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return []
    
    def _find_site_by_name(self, site_name: str) -> Optional[Dict[str, Any]]:
        """根据站点名查找站点配置"""
        if not site_name:
            return None
        
        normalized_name = site_name.lower().strip()
        return self.sites_config.get(normalized_name)
    
    def get_content_metadata(self, content_id: str) -> Optional[Dict[str, Any]]:
        """Get detailed metadata for specific content"""
        try:
            # content_id 是 WordPress post ID 或 slug
            video_data = self.hustler_api.get_by_id(content_id)
            if not video_data:
                return None
            
            # 提取标题
            title_obj = video_data.get('title', {})
            title = title_obj.get('rendered', '') if isinstance(title_obj, dict) else str(title_obj)
            
            # 提取描述 (可能在 content 或 excerpt 中)
            content_obj = video_data.get('content', {})
            description = content_obj.get('rendered', '') if isinstance(content_obj, dict) else ''
            if not description:
                excerpt_obj = video_data.get('excerpt', {})
                description = excerpt_obj.get('rendered', '') if isinstance(excerpt_obj, dict) else ''
            
            # 清理 HTML
            description = self._clean_description(description)
            
            # 构建视频 URL
            video_url = video_data.get('link', '')
            
            # 从网页中提取图片和视频（传入标题用于搜索）
            images, cover_video, preview_videos = self._extract_media_from_page(video_url, title)
            
            # 提取元数据
            metadata = {
                'id': str(video_data.get('id', content_id)),
                'slug': video_data.get('slug', ''),
                'title': title,
                'description': description,
                'release_date': self._parse_date(video_data.get('date')),
                'site_name': self.site_config.site_name if self.site_config else 'Hustler',
                'studio_name': self.site_config.network if self.site_config else 'Hustler',
                'url': video_url,
                'actors': self._extract_actors_from_wp(video_data),
                'directors': self._extract_directors_from_wp(video_data),
                'genres': self._extract_genres_from_wp(video_data),
                'images': images,
                'cover_video': cover_video,
                'preview_videos': preview_videos,
                'raw_data': video_data
            }
            
            return metadata
            
        except Exception as e:
            logger.error(f"Failed to get metadata for ID '{content_id}': {e}")
            return None
    
    def _build_video_url(self, movie_data: Dict[str, Any]) -> str:
        """Build video URL from movie data"""
        # WordPress 数据直接包含 link
        return movie_data.get('link', self.base_url)
    
    def _extract_actors_from_wp(self, video_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract actor information from WordPress video data"""
        actors = []
        
        # 优先从 _embedded 中提取演员信息（使用 _embed 参数时可用）
        embedded = video_data.get('_embedded', {})
        wp_terms = embedded.get('wp:term', [])
        
        # wp:term 是一个二维数组，每个子数组对应一个 taxonomy
        for term_group in wp_terms:
            if isinstance(term_group, list):
                for term in term_group:
                    if isinstance(term, dict) and term.get('taxonomy') == 'hu_actors':
                        actor_name = term.get('name', '')
                        if actor_name:
                            actors.append({
                                'name': actor_name,
                            })
        
        # 如果 _embedded 中没有数据，回退到从 class_list 中提取
        if not actors:
            class_list = video_data.get('class_list', [])
            for class_name in class_list:
                if class_name.startswith('hu_actors-'):
                    # 去掉前缀
                    actor_name = class_name.replace('hu_actors-', '')
                    # 跳过纯数字的标签
                    if not actor_name.isdigit():
                        # 将连字符替换为空格，并转换为标题格式
                        actor_name = actor_name.replace('-', ' ').title()
                        actors.append({
                            'name': actor_name,
                        })
        
        return actors
    
    def _extract_directors_from_wp(self, video_data: Dict[str, Any]) -> List[str]:
        """Extract director names from WordPress video data"""
        directors = []
        
        # WordPress 使用 taxonomy IDs
        director_ids = video_data.get('video_director', [])
        
        # TODO: 需要额外 API 调用获取导演名称
        # 目前返回空列表
        
        return directors
    
    def _extract_genres_from_wp(self, video_data: Dict[str, Any]) -> List[str]:
        """Extract genre/category information from WordPress video data"""
        genres = set()
        
        # 优先从 _embedded 中提取标签信息（使用 _embed 参数时可用）
        embedded = video_data.get('_embedded', {})
        wp_terms = embedded.get('wp:term', [])
        
        # wp:term 是一个二维数组，每个子数组对应一个 taxonomy
        for term_group in wp_terms:
            if isinstance(term_group, list):
                for term in term_group:
                    if isinstance(term, dict):
                        taxonomy = term.get('taxonomy', '')
                        name = term.get('name', '')
                        
                        # 提取标签、频道、工作室
                        if taxonomy in ['video_tags', 'video_channels', 'video_studio'] and name:
                            genres.add(name)
        
        # 如果 _embedded 中没有数据，回退到从 class_list 中提取
        if not genres:
            class_list = video_data.get('class_list', [])
            for class_name in class_list:
                # 提取 video_tags- 开头的类名
                if class_name.startswith('video_tags-'):
                    # 去掉前缀
                    tag_name = class_name.replace('video_tags-', '')
                    # 跳过纯数字的标签
                    if not tag_name.isdigit():
                        # 将连字符替换为空格，并转换为标题格式
                        tag_name = tag_name.replace('-', ' ').title()
                        genres.add(tag_name)
                
                # 提取 video_channels- 开头的类名
                elif class_name.startswith('video_channels-'):
                    channel_name = class_name.replace('video_channels-', '')
                    if not channel_name.isdigit():
                        channel_name = channel_name.replace('-', ' ').title()
                        genres.add(channel_name)
                
                # 提取 video_studio- 开头的类名
                elif class_name.startswith('video_studio-'):
                    studio_name = class_name.replace('video_studio-', '')
                    if not studio_name.isdigit():
                        studio_name = studio_name.replace('-', ' ').title()
                        genres.add(studio_name)
        
        return list(genres)
    
    def _extract_images_from_wp(self, video_data: Dict[str, Any]) -> List[str]:
        """Extract image URLs from WordPress video data (deprecated - use _extract_media_from_page)"""
        images = []
        
        # WordPress API 不返回图片，需要抓取网页
        # 这个方法已被 _extract_media_from_page 替代
        
        return images
    
    def _get_video_id_from_list_page(self, video_url: str, video_title: str = None) -> Optional[str]:
        """
        从列表页中获取视频 ID
        
        Args:
            video_url: 视频详情页 URL
            video_title: 视频标题（用于搜索列表页）
        
        Returns:
            视频 ID (如 '00821950')，如果找不到则返回 None
        """
        try:
            import requests
            from bs4 import BeautifulSoup
            import re
            import urllib.parse
            
            # 从详情页 URL 中提取 slug
            # 例如: https://hustlerunlimited.com/videos/no-boys-allowed-all-girl-fantasies/
            slug_match = re.search(r'/videos/([^/]+)/?$', video_url)
            if not slug_match:
                logger.warning(f"[Hustler] 无法从 URL 中提取 slug: {video_url}")
                return None
            
            slug = slug_match.group(1)
            logger.info(f"[Hustler] 从 URL 提取 slug: {slug}")
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            }
            
            # 从 WP_API_BASE 提取主域名
            # 例如: https://hustlerunlimited.com/wp-json/wp/v2 -> https://hustlerunlimited.com
            import re
            domain_match = re.match(r'(https?://[^/]+)', self.WP_API_BASE)
            base_domain = domain_match.group(1) if domain_match else "https://hustlerunlimited.com"
            
            # 策略1: 先尝试搜索列表页（优先，使用标题搜索）
            if video_title:
                # 使用标题搜索
                search_query = urllib.parse.quote(video_title)
                search_url = f"{base_domain}/videos/?_sf_s={search_query}"
                logger.info(f"[Hustler] 尝试搜索列表页（使用标题）: {search_url}")
                
                try:
                    response = requests.get(search_url, headers=headers, timeout=10)
                    response.raise_for_status()
                    soup = BeautifulSoup(response.text, 'html.parser')
                    
                    # 查找包含目标 slug 的链接
                    target_link = soup.find('a', href=re.compile(f'/{slug}/?$'))
                    if target_link:
                        logger.info(f"[Hustler] 在搜索列表页中找到视频链接")
                        
                        # 在父容器中查找图片或视频，提取 ID
                        parent = target_link.parent
                        while parent and parent.name != 'body':
                            # 查找 hh-thumbnail 图片
                            imgs = parent.find_all('img', src=re.compile(r'/hh-thumbnail/(\d+)\.jpg'))
                            if imgs:
                                img_src = imgs[0].get('src', '')
                                match = re.search(r'/hh-thumbnail/(\d+)\.jpg', img_src)
                                if match:
                                    video_id = match.group(1)
                                    logger.info(f"[Hustler] 从搜索列表页提取视频 ID: {video_id}")
                                    return video_id
                            
                            # 查找 hh-rollover 视频
                            videos = parent.find_all('source', src=re.compile(r'/hh-rollover/(\d+)\.mp4'))
                            if videos:
                                video_src = videos[0].get('src', '')
                                match = re.search(r'/hh-rollover/(\d+)\.mp4', video_src)
                                if match:
                                    video_id = match.group(1)
                                    logger.info(f"[Hustler] 从搜索列表页提取视频 ID: {video_id}")
                                    return video_id
                            
                            parent = parent.parent
                        
                        logger.warning(f"[Hustler] 在搜索列表页中找到链接但未找到视频 ID")
                    else:
                        logger.info(f"[Hustler] 搜索列表页中未找到视频，尝试主列表页")
                except Exception as e:
                    logger.warning(f"[Hustler] 搜索列表页失败: {e}，尝试主列表页")
            else:
                logger.info(f"[Hustler] 未提供标题，跳过搜索列表页，直接尝试主列表页")
            
            # 策略2: 降级到主列表页（备用）
            list_url = f"{base_domain}/videos/"
            logger.info(f"[Hustler] 抓取主列表页查找视频 ID: {list_url}")
            
            response = requests.get(list_url, headers=headers, timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # 查找包含目标 slug 的链接
            target_link = soup.find('a', href=re.compile(f'/{slug}/?$'))
            if not target_link:
                logger.warning(f"[Hustler] 在主列表页中也未找到视频: {slug}")
                return None
            
            logger.info(f"[Hustler] 在主列表页中找到视频链接")
            
            # 在父容器中查找图片或视频，提取 ID
            parent = target_link.parent
            while parent and parent.name != 'body':
                # 查找 hh-thumbnail 图片
                imgs = parent.find_all('img', src=re.compile(r'/hh-thumbnail/(\d+)\.jpg'))
                if imgs:
                    img_src = imgs[0].get('src', '')
                    match = re.search(r'/hh-thumbnail/(\d+)\.jpg', img_src)
                    if match:
                        video_id = match.group(1)
                        logger.info(f"[Hustler] 从主列表页提取视频 ID: {video_id}")
                        return video_id
                
                # 查找 hh-rollover 视频
                videos = parent.find_all('source', src=re.compile(r'/hh-rollover/(\d+)\.mp4'))
                if videos:
                    video_src = videos[0].get('src', '')
                    match = re.search(r'/hh-rollover/(\d+)\.mp4', video_src)
                    if match:
                        video_id = match.group(1)
                        logger.info(f"[Hustler] 从主列表页提取视频 ID: {video_id}")
                        return video_id
                
                parent = parent.parent
            
            logger.warning(f"[Hustler] 在主列表页中找到链接但未找到视频 ID")
            return None
            
        except Exception as e:
            logger.error(f"[Hustler] 从列表页获取视频 ID 失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return None
    
    def _extract_media_from_page(self, video_url: str, video_title: str = None) -> tuple:
        """
        从网页中提取图片、封面视频和预览视频
        
        Args:
            video_url: 视频详情页 URL
            video_title: 视频标题（用于搜索列表页）
        
        Returns:
            tuple: (images, cover_video, preview_videos)
                - images: List[str] - 图片 URL 列表
                - cover_video: str - 封面视频 URL
                - preview_videos: List[Dict] - 预览视频列表 [{'quality': str, 'url': str}]
        """
        images = []
        cover_video = None
        preview_videos = []
        
        if not video_url:
            return images, cover_video, preview_videos
        
        try:
            import requests
            from bs4 import BeautifulSoup
            import re
            
            # 从 WP_API_BASE 提取主域名
            domain_match = re.match(r'(https?://[^/]+)', self.WP_API_BASE)
            base_domain = domain_match.group(1) if domain_match else "https://hustlerunlimited.com"
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            }
            
            logger.info(f"[Hustler] 抓取详情页获取媒体资源: {video_url}")
            response = requests.get(video_url, headers=headers, timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, 'html.parser')
            all_text = response.text
            
            # 1. 从 script 中提取 Dacast Content ID
            scripts = soup.find_all('script')
            dacast_content_id = None
            
            page_text = response.text
            
            # 提取 CONTENT_ID
            for script in scripts:
                if script.string:
                    match = re.search(r'CONTENT_ID_\d+\s*=\s*["\']([^"\']+)["\']', script.string)
                    if match:
                        dacast_content_id = match.group(1)
                        logger.info(f"[Hustler] 找到 Dacast Content ID: {dacast_content_id}")
                        break
            
            # 2. 通过 Dacast API 获取带 context 参数的 M3U8 URL
            if dacast_content_id:
                try:
                    # 调用 Dacast API
                    api_url = f"https://playback.dacast.com/content/access?contentId={dacast_content_id}&provider=universe"
                    api_headers = {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                        'Accept': 'application/json',
                        'Referer': video_url,
                        'Origin': base_domain  # 使用动态域名
                    }
                    
                    logger.info(f"[Hustler] 调用 Dacast API 获取预览视频 URL")
                    api_response = requests.get(api_url, headers=api_headers, timeout=10)
                    api_response.raise_for_status()
                    
                    api_data = api_response.json()
                    hls_url = api_data.get('hls')
                    
                    if hls_url:
                        # 成功获取带 context 参数的完整 URL
                        preview_videos.append({
                            'quality': 'HLS',
                            'url': hls_url
                        })
                        logger.info(f"[Hustler] ✓ 通过 API 获取完整预览视频 URL（带 context）")
                    else:
                        logger.warning(f"[Hustler] API 响应中没有 hls 字段")
                        # 降级方案：使用基础 URL
                        base_content_id = dacast_content_id.split('-vod-')[0] if '-vod-' in dacast_content_id else dacast_content_id
                        m3u8_url = f"https://video.dacast.com/usp/{base_content_id}.ism/{base_content_id}.m3u8"
                        preview_videos.append({
                            'quality': 'HLS',
                            'url': m3u8_url
                        })
                        logger.info(f"[Hustler] 使用基础预览视频 URL（无 context）")
                        
                except Exception as e:
                    logger.error(f"[Hustler] Dacast API 调用失败: {e}")
                    # 降级方案：使用基础 URL
                    base_content_id = dacast_content_id.split('-vod-')[0] if '-vod-' in dacast_content_id else dacast_content_id
                    m3u8_url = f"https://video.dacast.com/usp/{base_content_id}.ism/{base_content_id}.m3u8"
                    preview_videos.append({
                        'quality': 'HLS',
                        'url': m3u8_url
                    })
                    logger.info(f"[Hustler] 使用基础预览视频 URL（无 context）")
            
            # 3. 从列表页获取视频 ID（传入标题用于搜索）
            video_id = self._get_video_id_from_list_page(video_url, video_title)
            
            if video_id:
                # 构建封面图片 URL（使用动态域名）
                thumbnail_url = f"{base_domain}/hh-thumbnail/{video_id}.jpg"
                images.append(thumbnail_url)
                logger.info(f"[Hustler] 构建封面图片 URL: {thumbnail_url}")
                
                # 构建封面视频 URL
                cover_video = f"https://hustlerunlimited.com/hh-rollover/{video_id}.mp4"
                logger.info(f"[Hustler] 构建封面视频 URL: {cover_video}")
                
                # 提取 dacast 图片 (如 https://universe-files.dacast.com/...jpeg)
                dacast_img_matches = re.findall(r'https?://[^"\'\s]*dacast\.com/[^"\'\s]+\.(?:jpg|jpeg|png)', all_text)
                for img_url in dacast_img_matches:
                    if img_url not in images:
                        images.append(img_url)
                        logger.info(f"[Hustler] 找到 dacast 图片: {img_url}")
            else:
                logger.warning(f"[Hustler] 无法获取视频 ID，跳过封面图片和封面视频")
            
        except Exception as e:
            logger.error(f"[Hustler] 抓取网页失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
        
        return images, cover_video, preview_videos
    
    def _extract_actors(self, movie_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract actor information from movie data (legacy method for old API)"""
        actors = []
        
        models = movie_data.get('models', [])
        if isinstance(models, list):
            for model in models:
                if isinstance(model, dict):
                    actor_data = {
                        'name': model.get('name', ''),
                        'age': model.get('age'),
                        'gender': model.get('gender', ''),
                        'ethnicity': model.get('ethnicity', ''),
                        'hair': model.get('hair', ''),
                        'eyes': model.get('eyes', ''),
                        'height': model.get('height'),
                        'weight': model.get('weight'),
                        'image_url': None
                    }
                    
                    # Build actor image URL if available
                    headshot_path = model.get('headshotImagePath')
                    site_uuid = model.get('siteUUID')
                    if headshot_path and site_uuid:
                        actor_data['image_url'] = f"{self.image_url_prefix}/{site_uuid}{headshot_path}"
                    
                    actors.append(actor_data)
        
        return actors
    
    def _extract_directors(self, movie_data: Dict[str, Any]) -> List[str]:
        """Extract director names from movie data"""
        directors = []
        
        # Hustler API uses 'photographers' field for directors
        photographers = movie_data.get('photographers', [])
        if isinstance(photographers, list):
            for photographer in photographers:
                if isinstance(photographer, dict):
                    name = photographer.get('name', '')
                    if name:
                        directors.append(name)
        
        return directors
    
    def _extract_genres(self, movie_data: Dict[str, Any]) -> List[str]:
        """Extract genre/category information from movie data"""
        genres = set()
        
        # Add tags
        tags = movie_data.get('tags', [])
        if isinstance(tags, list):
            for tag in tags:
                if isinstance(tag, str) and tag.strip():
                    genres.add(tag.strip())
        
        # Add categories (excluding subsite categories)
        categories = movie_data.get('categories', [])
        if isinstance(categories, list):
            subsite_regex = re.compile(r'\s+subsite', re.IGNORECASE)
            for category in categories:
                if isinstance(category, dict):
                    name = category.get('name', '')
                    if name and not subsite_regex.search(name):
                        genres.add(name)
        
        return list(genres)
    
    def _extract_images(self, movie_data: Dict[str, Any]) -> List[str]:
        """Extract image URLs from movie data"""
        images = []
        
        site_uuid = movie_data.get('siteUUID', '')
        if not site_uuid:
            return images
        
        base_url = f"{self.image_url_prefix}/{site_uuid}"
        
        # Add cover image
        cover_path = movie_data.get('coverImagePath')
        if cover_path:
            images.append(f"{base_url}{cover_path}")
        
        # Add splash image
        splash_path = movie_data.get('splashImagePath')
        if splash_path:
            images.append(f"{base_url}{splash_path}")
        
        # Add thumbnail cover
        thumbnail_path = movie_data.get('thumbnailCoverPath')
        if thumbnail_path:
            images.append(f"{base_url}{thumbnail_path}")
        
        return images
    
    def _extract_rating(self, movie_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract rating information from movie data"""
        rating_average = movie_data.get('ratingAverage', 0)
        rating_count = movie_data.get('ratingCount', 0)
        
        if rating_count > 0 and rating_average > 0:
            return {
                'value': rating_average / 10.0,  # Convert from 0-10 to 0-1 scale
                'scale': 1.0,
                'votes': rating_count
            }
        
        return None
    
    def _clean_description(self, description: str) -> str:
        """Clean HTML tags from description"""
        if not description:
            return ""
        
        # Remove HTML tags
        description = re.sub(r'<[^>]+>', '', description)
        
        return description.strip()
    
    def _parse_date(self, date_str: Any) -> Optional[datetime]:
        """Parse date string to datetime object"""
        if not date_str:
            return None
        
        try:
            if isinstance(date_str, str):
                # Handle ISO format with Z suffix
                if date_str.endswith('Z'):
                    date_str = date_str[:-1] + '+00:00'
                
                # Try different date formats
                for fmt in ['%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d']:
                    try:
                        return datetime.strptime(date_str, fmt)
                    except ValueError:
                        continue
                        
                # Try parsing with fromisoformat
                try:
                    return datetime.fromisoformat(date_str)
                except ValueError:
                    pass
                    
            elif isinstance(date_str, (int, float)):
                # Unix timestamp
                return datetime.fromtimestamp(date_str)
        except Exception as e:
            logger.warning(f"Failed to parse date '{date_str}': {e}")
        
        return None


# Specific scraper implementations for different Hustler sites

class HustlerScraper(AbstractHustlerScraper):
    """Scraper for main Hustler site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler", "hustler.com")
        super().__init__(config)


class BarelyLegalScraper(AbstractHustlerScraper):
    """Scraper for Barely Legal site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Barely Legal", "barelylegal.com")
        super().__init__(config)


class AssMeatScraper(AbstractHustlerScraper):
    """Scraper for Ass Meat site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Ass Meat", "assmeat.com")
        super().__init__(config)


class SeeMySexTapesScraper(AbstractHustlerScraper):
    """Scraper for See My Sex Tapes site"""
    
    def __init__(self):
        config = HustlerSiteConfig("See My Sex Tapes", "seemysextapes.com")
        super().__init__(config)


class MuchasLatinasScraper(AbstractHustlerScraper):
    """Scraper for Muchas Latinas site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Muchas Latinas", "muchaslatinas.com")
        super().__init__(config)


class HustlazScraper(AbstractHustlerScraper):
    """Scraper for Hustlaz site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustlaz", "hustlaz.com")
        super().__init__(config)


class LesbianAssScraper(AbstractHustlerScraper):
    """Scraper for Lesbian Ass site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Lesbian Ass", "lesbianass.com")
        super().__init__(config)


class BattleBangScraper(AbstractHustlerScraper):
    """Scraper for Battle Bang site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Battle Bang", "battlebang.com")
        super().__init__(config)


class FuckFiestaScraper(AbstractHustlerScraper):
    """Scraper for Fuck Fiesta site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Fuck Fiesta", "fuckfiesta.com")
        super().__init__(config)


class VCAClassicsScraper(AbstractHustlerScraper):
    """Scraper for VCA Classics site"""
    
    def __init__(self):
        config = HustlerSiteConfig("VCA Classics", "vcaxxx.com")
        super().__init__(config)


class BossyMilfsScraper(AbstractHustlerScraper):
    """Scraper for Bossy Milfs site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Bossy Milfs", "bossymilfs.com")
        super().__init__(config)


class Asian18Scraper(AbstractHustlerScraper):
    """Scraper for Asian18 site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Asian18", "asian18.com")
        super().__init__(config)


class AsianFeverScraper(AbstractHustlerScraper):
    """Scraper for Asian Fever site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Asian Fever", "asianfever.com")
        super().__init__(config)


class XTSYScraper(AbstractHustlerScraper):
    """Scraper for XTSY site"""
    
    def __init__(self):
        config = HustlerSiteConfig("XTSY", "xtsy.com")
        super().__init__(config)


class DaddyGetsLuckyScraper(AbstractHustlerScraper):
    """Scraper for Daddy Gets Lucky site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Daddy Gets Lucky", "daddygetslucky.com")
        super().__init__(config)


class SexSeeScraper(AbstractHustlerScraper):
    """Scraper for Sex See site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Sex See", "sexsee.com")
        super().__init__(config)


class TooManyTranniesScraper(AbstractHustlerScraper):
    """Scraper for Too Many Trannies site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Too Many Trannies", "toomanytrannies.com")
        super().__init__(config)


class HustlersCollegeGirlsScraper(AbstractHustlerScraper):
    """Scraper for Hustler's College Girls site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler's College Girls", "hustlerscollegegirls.com")
        super().__init__(config)


class ScaryBigDicksScraper(AbstractHustlerScraper):
    """Scraper for Scary Big Dicks site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Scary Big Dicks", "scarybigdicks.com")
        super().__init__(config)


class HustlersTabooScraper(AbstractHustlerScraper):
    """Scraper for Hustler's Taboo site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler's Taboo", "hustlerstaboo.com")
        super().__init__(config)


class WatchRealScraper(AbstractHustlerScraper):
    """Scraper for Watch Real site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Watch Real", "watchreal.com")
        super().__init__(config)


class HometownHoneysScraper(AbstractHustlerScraper):
    """Scraper for Hometown Honeys site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hometown Honeys", "hometownhoneys.com")
        super().__init__(config)


class HottieMomsScraper(AbstractHustlerScraper):
    """Scraper for Hottie Moms site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hottie Moms", "hottiemoms.com")
        super().__init__(config)


class FuckingHardcoreScraper(AbstractHustlerScraper):
    """Scraper for Fucking Hardcore site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Fucking Hardcore", "fuckinghardcore.com")
        super().__init__(config)


class HustlerHDScraper(AbstractHustlerScraper):
    """Scraper for Hustler HD site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler HD", "hustlerhd.com")
        super().__init__(config)


class TitWorldScraper(AbstractHustlerScraper):
    """Scraper for Tit World site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Tit World", "titworld.com")
        super().__init__(config)


class SororitySlutsScraper(AbstractHustlerScraper):
    """Scraper for Sorority Sluts site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Sorority Sluts", "sororitysluts.com")
        super().__init__(config)


class SexCircusScraper(AbstractHustlerScraper):
    """Scraper for Sex Circus site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Sex Circus", "sexcircus.com")
        super().__init__(config)


class JuicyTVScraper(AbstractHustlerScraper):
    """Scraper for Juicy TV site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Juicy TV", "juicytv.com")
        super().__init__(config)


class BustyBeautiesScraper(AbstractHustlerScraper):
    """Scraper for Busty Beauties site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Busty Beauties", "bustybeauties.com")
        super().__init__(config)


class HustlerParodiesScraper(AbstractHustlerScraper):
    """Scraper for Hustler Parodies site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler Parodies", "hustlerparodies.com")
        super().__init__(config)


class AnalHookersScraper(AbstractHustlerScraper):
    """Scraper for Anal Hookers site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Anal Hookers", "analhookers.com")
        super().__init__(config)


class PornstarHardcoreScraper(AbstractHustlerScraper):
    """Scraper for Pornstar Hardcore site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Pornstar Hardcore", "pornstarhardcore.com")
        super().__init__(config)


class BootyClapXXXScraper(AbstractHustlerScraper):
    """Scraper for Booty Clap XXX site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Booty Clap XXX", "bootyclapxxx.com")
        super().__init__(config)


class BeaverHuntScraper(AbstractHustlerScraper):
    """Scraper for Beaver Hunt site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Beaver Hunt", "beaverhunt.com")
        super().__init__(config)


class HometownGirlsScraper(AbstractHustlerScraper):
    """Scraper for Hometown Girls site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hometown Girls", "hometowngirls.com")
        super().__init__(config)


class HustlersLesbiansScraper(AbstractHustlerScraper):
    """Scraper for Hustler's Lesbians site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Hustler's Lesbians", "hustlerslesbians.com")
        super().__init__(config)


class BootySistersScraper(AbstractHustlerScraper):
    """Scraper for Booty Sisters site"""
    
    def __init__(self):
        config = HustlerSiteConfig("Booty Sisters", "bootysisters.com")
        super().__init__(config)


# All Hustler network scrapers are now implemented