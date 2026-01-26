#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
MetArt_Network_Scraper.py

MetArt Network 刮削器
使用 Playwright 采集页面数据
支持 MetArt, SexArt, MetArtX 等站点
"""

import re
import logging
import json
from datetime import datetime
from typing import Dict, List, Optional, Any
import sys
from pathlib import Path
from urllib.parse import quote

# Add parent directories to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from base_scraper import BaseScraper
from core.models import ScrapeResult

logger = logging.getLogger(__name__)


class MetArtNetworkScraper(BaseScraper):
    """MetArt Network 刮削器（使用 Playwright）"""
    
    name = 'metart_network'
    cdn_url = 'https://gccdn.metartnetwork.com'
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = False):
        """初始化 MetArt Network 刮削器"""
        super().__init__(config, use_scraper=False)
        
        # Playwright 相关
        self.playwright = None
        self.browser = None
        self.context = None
        
        # 从 CSV 文件加载站点配置
        self.base_url, self.sub_sites = self._load_sites_from_csv()
        
        self.logger.info(f"MetArt Network scraper initialized (Playwright mode)")
        self.logger.info(f"主站点: {self.base_url}")
        self.logger.info(f"从 CSV 加载了 {len(self.sub_sites)} 个子站点")
    
    def _load_sites_from_csv(self) -> tuple[str, Dict[str, str]]:
        """从 CSV 文件加载站点配置
        
        Returns:
            (主站点URL, 子站点字典)
        """
        from pathlib import Path
        
        # 路径: scrapers/western/MetArt_Network_Scraper.py -> plugins/Media_Scraper/config/site/
        csv_path = Path(__file__).parent.parent.parent / 'config' / 'site' / 'metart_network_sites.csv'
        main_site_url = 'https://www.metartnetwork.com'  # 默认值
        sub_sites = {}
        first_row = True
        
        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
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
                    
                    if enabled.lower() != 'true':
                        continue
                    
                    # 规范化站点名（移除空格，转小写）
                    normalized_name = site_name.lower().replace(' ', '')
                    
                    # 构建完整 URL
                    site_url = f"https://{domain}"
                    
                    # 第一行且有 main_api 的是主站点
                    if first_row and main_api:
                        main_site_url = main_api
                        self.logger.info(f"主站点: {site_name} -> {main_api}")
                        first_row = False
                        # 主站点不加入子站点列表
                    else:
                        # 其他所有站点都是子站点
                        sub_sites[normalized_name] = site_url
                        first_row = False
            
            self.logger.info(f"成功从 CSV 加载站点配置: 主站点 + {len(sub_sites)} 个子站点")
        except Exception as e:
            self.logger.error(f"加载 CSV 文件失败: {e}")
        
        return main_site_url, sub_sites
    
    def _init_playwright(self):
        """初始化 Playwright 浏览器"""
        if self.playwright is None:
            from playwright.sync_api import sync_playwright
            
            self.playwright = sync_playwright().start()
            
            # 从配置文件读取 DNS 映射
            dns_mapping = self.config.get('network', {}).get('dns_mapping', {})
            
            # 构建 Chromium 启动参数
            launch_args = []
            if dns_mapping:
                # 构建 --host-resolver-rules 参数
                # 格式: MAP domain1 ip1, MAP domain2 ip2
                rules = []
                for domain, ip in dns_mapping.items():
                    rules.append(f"MAP {domain} {ip}")
                    self.logger.info(f"DNS 映射: {domain} -> {ip}")
                
                if rules:
                    host_resolver_rules = ", ".join(rules)
                    launch_args.append(f"--host-resolver-rules={host_resolver_rules}")
            
            # 启动浏览器
            self.browser = self.playwright.chromium.launch(
                headless=True,
                args=launch_args if launch_args else None
            )
            
            self.context = self.browser.new_context(
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            )
            self.logger.info("Playwright browser initialized")
    
    def _close_playwright(self):
        """关闭 Playwright 浏览器"""
        if self.context:
            self.context.close()
        if self.browser:
            self.browser.close()
        if self.playwright:
            self.playwright.stop()
        self.playwright = None
        self.browser = None
        self.context = None
    
    def __del__(self):
        """析构函数"""
        try:
            self._close_playwright()
        except:
            pass
    
    def _extract_url_info(self, url: str) -> Optional[tuple]:
        """从 URL 提取日期和标题"""
        pattern = r'/model/[^/]+/(movie|gallery)/(\d{8})/([^/\s]+)'
        match = re.search(pattern, url, re.I)
        
        if match:
            date_str = match.group(2)
            title_slug = match.group(3)
            date = f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]}"
            title = title_slug.replace('_', ' ').replace('-', ' ')
            return (date, title)
        
        return None
    
    def _scrape_impl(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> Optional[ScrapeResult]:
        """实现刮削逻辑"""
        results = self.scrape_multiple(query)
        return results[0] if results else None
    
    def scrape_multiple(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """搜索并返回多个结果"""
        self.logger.info(f"scrape_multiple called: query={query}, series={series}")
        
        # 移除系列名前缀（如 "StrapLez-" 或 "Straplez "）
        search_query = query
        detected_series = None
        if '-' in query:
            parts = query.split('-', 1)
            if len(parts) == 2:
                detected_series = parts[0].strip().lower()
                search_query = parts[1].strip()
                self.logger.info(f"检测到系列名: {detected_series}, 搜索标题: {search_query}")
        
        search_results = []
        
        # 1. 如果检测到系列名，优先尝试对应的子站点
        if detected_series and detected_series in self.sub_sites:
            sub_site_url = self.sub_sites[detected_series]
            self.logger.info(f"步骤 1: 优先尝试子站点 {detected_series} ({sub_site_url})")
            search_results = self._fetch_search_results(search_query, sub_site_url)
        
        # 2. 如果子站点失败或没有系列名，回退到主站搜索
        if not search_results:
            if detected_series:
                self.logger.info(f"步骤 2: 子站点失败，回退到主站搜索")
            else:
                self.logger.info(f"步骤 1: 未检测到系列名，直接使用主站搜索")
            search_results = self._fetch_search_results(search_query, self.base_url)
        
        if not search_results:
            self.logger.warning("子站点和主站都未找到搜索结果")
            return []
        
        print(f"[DEBUG] 找到 {len(search_results)} 个搜索结果")
        
        # 将查询转换为 URL slug 格式用于匹配
        # "Sensual Intent 2" -> "SENSUAL_INTENT_2" 或 "SENSUAL-INTENT-2"
        query_slug = search_query.upper().replace(' ', '_')
        query_slug_alt = search_query.upper().replace(' ', '-')
        
        print(f"[DEBUG] 查询 slug: {query_slug} 或 {query_slug_alt}")
        
        # 过滤：只保留 URL 中包含查询 slug 的结果
        matched_results = []
        for item in search_results:
            url_upper = item['url'].upper()
            # 检查 URL 是否包含查询 slug
            if query_slug in url_upper or query_slug_alt in url_upper:
                matched_results.append(item)
                print(f"[DEBUG] URL 匹配: {item['url']}")
            else:
                print(f"[DEBUG] URL 不匹配，跳过: {item['url']}")
        
        if not matched_results:
            print(f"[DEBUG] 没有 URL 匹配的结果")
            return []
        
        print(f"[DEBUG] 过滤后剩余 {len(matched_results)} 个匹配结果")
        
        # 访问每个详情页提取完整数据
        results = []
        for item in matched_results[:5]:  # 限制最多5个结果
            result = self._scrape_detail_page(item['url'], item['title'], item['date'])
            if result:
                results.append(result)
        
        self.logger.info(f"返回 {len(results)} 个结果")
        return results
    
    def _fetch_search_results(self, query: str, base_url: str = None) -> List[Dict[str, Any]]:
        """使用 Playwright 获取搜索结果链接
        
        Args:
            query: 搜索关键词
            base_url: 搜索的基础 URL（默认使用 self.base_url）
        """
        if base_url is None:
            base_url = self.base_url
            
        try:
            self._init_playwright()
            page = self.context.new_page()
            
            try:
                search_url = f"{base_url}/search/{quote(query)}"
                print(f"[DEBUG] 正在加载搜索页面: {search_url}")
                
                # 使用 domcontentloaded 而不是 networkidle，更快
                page.goto(search_url, wait_until='domcontentloaded', timeout=30000)
                
                # 等待搜索结果加载
                try:
                    page.wait_for_selector('a[href*="/movie/"], a[href*="/gallery/"]', timeout=10000)
                except:
                    self.logger.warning(f"未找到搜索结果链接: {search_url}")
                    return []
                
                # 等待一下让内容完全加载
                page.wait_for_timeout(2000)
                
                # 提取搜索结果链接
                results = []
                links = page.query_selector_all('a[href*="/movie/"], a[href*="/gallery/"]')
                
                seen_urls = set()
                for link in links:
                    href = link.get_attribute('href')
                    if href and href not in seen_urls:
                        seen_urls.add(href)
                        
                        # 从 href 提取信息
                        url_info = self._extract_url_info(href)
                        if url_info:
                            date, title = url_info
                            # 构建完整 URL（如果是相对路径，使用当前 base_url）
                            full_url = href if href.startswith('http') else f"{base_url}{href}"
                            results.append({
                                'url': full_url,
                                'title': title,
                                'date': date
                            })
                            print(f"[DEBUG] 提取链接: {title} ({date}) - {href}")
                
                return results
                
            finally:
                page.close()
                
        except Exception as e:
            self.logger.error(f"搜索失败: {e}")
            return []
            return []
    
    def _build_video_preview_url(self, image_url: str) -> Optional[str]:
        """根据封面图 URL 构建预览视频 URL"""
        # 从图片 URL 中提取 site_uuid 和 media_uuid
        # 示例: https://gccdn.metartnetwork.com/94DB3D0036FC11E1B86C0800200C9A66/media/994C0BB481F0A914153F62D71C22687E/wide_994C0BB481F0A914153F62D71C22687E.jpg
        # 预览: https://gccdn.metartnetwork.com/94DB3D0036FC11E1B86C0800200C9A66/media/994C0BB481F0A914153F62D71C22687E/tease_994C0BB481F0A914153F62D71C22687E.mp4
        
        match = re.search(r'gccdn\.metartnetwork\.com/([A-F0-9]+)/media/([A-F0-9]+)/', image_url)
        if match:
            site_uuid = match.group(1)
            media_uuid = match.group(2)
            video_url = f"https://gccdn.metartnetwork.com/{site_uuid}/media/{media_uuid}/tease_{media_uuid}.mp4"
            print(f"[DEBUG] 构建预览视频 URL: {video_url[:80]}...")
            return video_url
        
        return None
    
    def _scrape_detail_page(self, url: str, title: str, date: str) -> Optional[ScrapeResult]:
        """访问详情页提取完整元数据（从 DOM 提取）"""
        print(f"[DEBUG] 正在访问详情页: {url}")
        
        try:
            self._init_playwright()
            page = self.context.new_page()
            
            try:
                # 加载详情页 - 使用 domcontentloaded 更快
                page.goto(url, wait_until='domcontentloaded', timeout=30000)
                page.wait_for_timeout(3000)  # 等待内容加载
                
                # 创建结果对象
                result = self._create_result()
                
                # 基本信息
                result.title = title.title()
                result.release_date = date
                result.year = int(date[:4])
                result.source = f"MetArt Network: {url}"
                result.studio = "MetArt Network"
                result.series = "MetArt Network"
                result.country = "Czech Republic"
                result.language = "en"
                result.media_type = "Scene" if '/movie/' in url else "Gallery"
                
                # 提取标题（从 h1 标签）
                try:
                    h1 = page.query_selector('h1')
                    if h1:
                        h1_text = h1.inner_text().strip()
                        # 移除年份后缀 "(2017)"
                        h1_text = re.sub(r'\s*\(\d{4}\)\s*$', '', h1_text)
                        if h1_text:
                            result.title = h1_text
                            print(f"[DEBUG] 提取到标题: {result.title}")
                except Exception as e:
                    print(f"[DEBUG] 提取标题失败: {e}")
                
                # 提取演员信息（只提取 /model/xxx 格式的链接，排除带日期的）
                try:
                    actor_links = page.query_selector_all('a[href*="/model/"]')
                    actors = []
                    seen_actors = set()
                    for link in actor_links:
                        href = link.get_attribute('href') or ''
                        # 只保留 /model/xxx 格式的链接，排除 /model/xxx/movie/... 格式
                        if re.match(r'^/model/[^/]+$', href):
                            actor_name = link.inner_text().strip()
                            if actor_name and actor_name not in seen_actors and len(actor_name) > 1:
                                actors.append({'name': actor_name, 'role': 'Actress'})
                                seen_actors.add(actor_name)
                    if actors:
                        result.actors = actors
                        print(f"[DEBUG] 提取到演员: {[a['name'] for a in actors]}")
                except Exception as e:
                    print(f"[DEBUG] 提取演员失败: {e}")
                
                # 提取封面图（第一张 CDN 图片）
                try:
                    img = page.query_selector('img[src*="gccdn.metartnetwork.com"]')
                    if img:
                        img_src = img.get_attribute('src')
                        if img_src:
                            result.poster_url = img_src
                            print(f"[DEBUG] 提取到封面图: {img_src[:80]}...")
                            
                            # 根据封面图 URL 构建预览视频 URL
                            video_url = self._build_video_preview_url(img_src)
                            if video_url:
                                # 添加到预览视频列表（使用标准格式）
                                result.preview_video_urls = [{
                                    'quality': 'Preview',
                                    'url': video_url
                                }]
                                print(f"[DEBUG] 构建预览视频 URL: {video_url[:80]}...")
                except Exception as e:
                    print(f"[DEBUG] 提取封面图失败: {e}")
                
                # 提取背景图（从视频播放器预览元素的 background-image）
                try:
                    preview_elem = page.query_selector('.jw-preview')
                    if preview_elem:
                        style = preview_elem.get_attribute('style')
                        if style:
                            # 从 style 中提取 background-image URL
                            import re
                            match = re.search(r'background-image:\s*url\(["\']?([^"\']+)["\']?\)', style)
                            if match:
                                backdrop_url = match.group(1)
                                result.backdrop_url = [backdrop_url]
                                print(f"[DEBUG] 提取到背景图: {backdrop_url[:80]}...")
                except Exception as e:
                    print(f"[DEBUG] 提取背景图失败: {e}")
                
                # 提取评分
                try:
                    rating_elem = page.query_selector('.movie-avg-rating')
                    if rating_elem:
                        rating_text = rating_elem.inner_text().strip()
                        # "Rating: 9.4" -> 9.4
                        match = re.search(r'(\d+\.?\d*)', rating_text)
                        if match:
                            rating = float(match.group(1))
                            result.rating = rating
                            print(f"[DEBUG] 提取到评分: {rating}")
                except Exception as e:
                    print(f"[DEBUG] 提取评分失败: {e}")
                
                # 提取时长（仅视频）
                if '/movie/' in url:
                    try:
                        # 等待视频播放器加载
                        page.wait_for_timeout(2000)
                        duration_elem = page.query_selector('.jw-text-duration, [class*="duration"]')
                        if duration_elem:
                            duration_text = duration_elem.inner_text().strip()
                            # "02:00" -> 2 分钟
                            match = re.match(r'(\d+):(\d+)', duration_text)
                            if match:
                                minutes = int(match.group(1))
                                seconds = int(match.group(2))
                                result.runtime = minutes
                                print(f"[DEBUG] 提取到时长: {result.runtime} 分钟")
                    except Exception as e:
                        print(f"[DEBUG] 提取时长失败: {e}")
                
                # 提取描述（查找较长的 p 标签，排除 cookie 相关）
                try:
                    paragraphs = page.query_selector_all('p')
                    for p in paragraphs:
                        text = p.inner_text().strip()
                        if text and len(text) > 50 and 'cookie' not in text.lower():
                            result.overview = text
                            print(f"[DEBUG] 提取到描述: {text[:100]}...")
                            break
                except Exception as e:
                    print(f"[DEBUG] 提取描述失败: {e}")
                
                print(f"[DEBUG] 详情页刮削完成: {result.title}")
                return result
                
            finally:
                page.close()
                
        except Exception as e:
            print(f"[DEBUG] 详情页访问失败: {e}")
            import traceback
            traceback.print_exc()
            return self._create_basic_result(url, title, date)
    
    def _create_basic_result(self, url: str, title: str, date: str) -> ScrapeResult:
        """创建基本的 ScrapeResult"""
        result = self._create_result()
        
        result.title = title.title()
        result.release_date = date
        result.year = int(date[:4])
        result.source = f"MetArt Network: {url}"
        result.studio = "MetArt Network"
        result.series = "MetArt Network"
        result.country = "Czech Republic"
        result.language = "en"
        result.media_type = "Scene" if '/movie/' in url else "Gallery"
        
        return result

