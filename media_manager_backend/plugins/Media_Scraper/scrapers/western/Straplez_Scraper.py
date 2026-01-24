"""
Straplez Scraper
刮削 Straplez 网站的场景数据
基于 MetArt Network API 实现（类似 Hustler Network）
"""

import logging
import re
import json
from datetime import datetime
from typing import Optional, Dict, Any, List

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult

logger = logging.getLogger(__name__)


class StraplezScraper(BaseScraper):
    """Straplez 刮削器（MetArt Network）"""
    
    name = 'straplez'
    base_url = 'https://www.straplez.com'
    cdn_url = 'https://gccdn.metartnetwork.com'
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = False):
        """
        初始化 Straplez 刮削器
        
        Args:
            config: 配置字典
            use_scraper: 是否使用 cloudscraper（Straplez 不需要）
        """
        super().__init__(config, use_scraper=use_scraper)
        
        # 配置 IP 映射（Straplez 需要使用 IP 地址访问）
        self._setup_ip_mapping()
        
        self.logger.info("Straplez scraper initialized")
    
    def _setup_ip_mapping(self):
        """设置 IP 映射（使用 IP 地址访问 Straplez）"""
        # 从配置中读取 IP 映射
        ip_mapping = self.config.get('ip_mapping', {})
        straplez_ip = ip_mapping.get('www.straplez.com', '207.66.141.189')
        
        # 设置自定义 DNS 解析
        try:
            import urllib3.util.connection
            from urllib3.util.connection import create_connection
            
            original_create_connection = urllib3.util.connection.create_connection
            
            def patched_create_connection(address, *args, **kwargs):
                """强制使用指定 IP"""
                host, port = address
                if host == 'www.straplez.com':
                    host = straplez_ip
                return original_create_connection((host, port), *args, **kwargs)
            
            urllib3.util.connection.create_connection = patched_create_connection
            self.logger.info(f"IP mapping configured: www.straplez.com -> {straplez_ip}")
        except Exception as e:
            self.logger.warning(f"Failed to setup IP mapping: {e}")
    
    def _scrape_impl(self, query: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            query: UUID 或场景 URL
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 提取 UUID
        uuid = self._extract_uuid(query)
        if not uuid:
            self.logger.error(f"Failed to extract UUID from query: {query}")
            return None
        
        self.logger.info(f"Scraping Straplez scene: UUID={uuid}")
        
        # 注意：单个场景详情 API 需要登录（返回 403）
        # 我们只能从列表 API 中获取数据
        # 这里尝试从列表中查找匹配的场景
        return self._scrape_from_list(uuid)
    
    def _extract_uuid(self, query: str) -> Optional[str]:
        """
        从查询中提取 UUID
        
        Args:
            query: UUID、URL 或路径
        
        Returns:
            UUID 字符串，失败返回 None
        """
        # 如果是 UUID 格式（32位十六进制）
        if re.match(r'^[A-F0-9]{32}$', query, re.I):
            return query.upper()
        
        # 如果是 URL 或路径，尝试提取 UUID
        # 路径格式: /model/xxx/gallery/20220802/XXX
        # 但 API 返回的是 UUID，不是路径
        # 所以这里无法从路径提取 UUID
        
        return None
    
    def _scrape_from_list(self, uuid: str) -> Optional[ScrapeResult]:
        """
        从列表 API 中查找并刮削场景
        
        Args:
            uuid: 场景 UUID
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 遍历所有页面，查找匹配的 UUID
        page = 1
        max_pages = 10  # 最多搜索10页（600个场景）
        
        while page <= max_pages:
            galleries = self.scrape_list(page, limit=60)
            if not galleries:
                break
            
            # 查找匹配的场景
            for gallery in galleries:
                if gallery.get('UUID') == uuid:
                    self.logger.info(f"Found scene with UUID: {uuid}")
                    return self._parse_gallery_data(gallery)
            
            page += 1
        
        self.logger.warning(f"Scene not found: UUID={uuid}")
        return None
    
    def scrape_list(self, page: int = 1, limit: int = 60) -> List[Dict[str, Any]]:
        """
        刮削场景列表
        
        Args:
            page: 页码（从1开始）
            limit: 每页数量（默认60）
        
        Returns:
            场景列表
        """
        url = f"{self.base_url}/api/movies"
        params = {'page': page, 'limit': limit}
        
        # 临时设置 Host 头（Straplez 需要正确的 Host 头）
        original_headers = self.request.headers.copy()
        self.request.headers.update({
            'Host': 'www.straplez.com',
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://www.straplez.com/'
        })
        
        self.logger.info(f"Scraping Straplez scenes list: page {page}, limit {limit}")
        
        try:
            response = self.request.get(url, params=params)
            if not response or response.status_code != 200:
                self.logger.error(f"Failed to fetch scenes list: {url}")
                return []
            
            data = response.json()
            galleries = data.get('galleries', [])
            total = data.get('total', 0)
            
            self.logger.info(f"Found {len(galleries)} scenes on page {page} (total: {total})")
            return galleries
        except Exception as e:
            self.logger.error(f"Error parsing scenes list: {e}")
            return []
        finally:
            # 恢复原始 headers
            self.request.headers = original_headers
    
    def _parse_gallery_data(self, gallery: Dict[str, Any]) -> ScrapeResult:
        """
        解析场景数据
        
        Args:
            gallery: 场景数据字典
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        # 基本信息
        result.code = gallery.get('UUID', '')
        result.title = gallery.get('name', '')
        result.overview = gallery.get('description', '')
        
        # 日期处理
        published_at = gallery.get('publishedAt')
        if published_at:
            try:
                # 格式: "2022-08-02T00:00:00.000Z"
                dt = datetime.fromisoformat(published_at.replace('Z', '+00:00'))
                result.release_date = dt.strftime("%Y-%m-%d")
                result.year = dt.year
            except ValueError:
                self.logger.warning(f"Failed to parse date: {published_at}")
        
        # 时长（秒转分钟）
        # 注意：Straplez 的 runtime 字段为 -1（这些是图库 GALLERY，不是视频）
        runtime = gallery.get('runtime')
        if runtime and runtime > 0:
            result.runtime = int(runtime / 60)
        
        # 评分
        rating_average = gallery.get('ratingAverage')
        if rating_average:
            try:
                result.rating = float(rating_average)
            except (ValueError, TypeError):
                pass
        
        # 制作商和系列
        result.studio = "Straplez"
        result.series = "Straplez"  # Straplez 是独立网站
        result.country = "Czech Republic"  # MetArt Network 总部在捷克
        result.language = "en"
        
        # 媒体类型
        gallery_type = gallery.get('type', '')
        if gallery_type == 'GALLERY':
            result.media_type = "Gallery"  # 图库
        else:
            result.media_type = "Scene"
        
        # 演员
        models = gallery.get('models', [])
        if isinstance(models, list):
            result.actors = [model.get('name') for model in models if model.get('name')]
        
        # 标签
        tags = gallery.get('tags', [])
        if isinstance(tags, list):
            result.genres = tags
        
        # 图片
        cover_image_path = gallery.get('coverImagePath')
        if cover_image_path:
            result.poster_url = f"{self.cdn_url}{cover_image_path}"
        
        # 大图
        splash_image_path = gallery.get('splashImagePath')
        if splash_image_path:
            result.backdrop_url = f"{self.cdn_url}{splash_image_path}"
        
        # 缩略图
        thumbnail_cover_path = gallery.get('thumbnailCoverPath')
        if thumbnail_cover_path:
            thumbnail_url = f"{self.cdn_url}{thumbnail_cover_path}"
            result.preview_urls = [thumbnail_url]
        
        # 数据来源
        result.source = f"Straplez (UUID: {result.code})"
        
        return result
    
    def scrape_by_date_range(self, start_date: str, end_date: str) -> List[ScrapeResult]:
        """
        按日期范围刮削场景
        
        Args:
            start_date: 开始日期 (YYYY-MM-DD)
            end_date: 结束日期 (YYYY-MM-DD)
        
        Returns:
            ScrapeResult 列表
        """
        from datetime import datetime
        
        start_dt = datetime.strptime(start_date, "%Y-%m-%d")
        end_dt = datetime.strptime(end_date, "%Y-%m-%d")
        
        results = []
        page = 1
        
        self.logger.info(f"Scraping scenes from {start_date} to {end_date}")
        
        while True:
            galleries = self.scrape_list(page)
            if not galleries:
                break
            
            found_in_range = False
            for gallery in galleries:
                published_at = gallery.get('publishedAt')
                if not published_at:
                    continue
                
                try:
                    # 解析日期
                    scene_dt = datetime.fromisoformat(published_at.replace('Z', '+00:00'))
                    
                    # 检查是否在范围内
                    if start_dt <= scene_dt <= end_dt:
                        # 解析场景数据
                        result = self._parse_gallery_data(gallery)
                        if result:
                            results.append(result)
                            found_in_range = True
                    # 如果场景日期早于开始日期，停止
                    elif scene_dt < start_dt:
                        self.logger.info(f"Reached scenes before start date, stopping")
                        return results
                        
                except ValueError as e:
                    self.logger.warning(f"Failed to parse date: {published_at}")
                    continue
            
            # 如果没有找到任何在范围内的场景，继续下一页
            page += 1
            
            # 安全限制：最多10页
            if page > 10:
                self.logger.warning("Reached maximum page limit (10)")
                break
        
        self.logger.info(f"Found {len(results)} scenes in date range")
        return results
    
    def scrape_multiple(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        刮削多个结果（实现 WesternScraperManager 接口）
        
        Straplez 的实现：
        - 如果 title 是 UUID，返回单个结果
        - 如果 title 是日期格式，按日期搜索
        - 如果 title 是标题关键词，按标题搜索
        
        Args:
            title: 标题、UUID 或日期
            content_type_hint: 内容类型提示（忽略）
            series: 系列名（忽略，Straplez 是独立网站）
        
        Returns:
            ScrapeResult 列表
        """
        self.logger.info(f"scrape_multiple called: title={title}")
        
        # 0. 移除系列名前缀（如果有）
        from utils.query_parser import extract_series_and_title
        
        extracted_series, clean_title = extract_series_and_title(title)
        if extracted_series:
            self.logger.info(f"检测到系列名前缀: {extracted_series}, 移除后的标题: {clean_title}")
            title = clean_title
        
        # 1. 检测是否为日期格式
        from utils.date_parser import is_date_query, parse_date_query
        
        if is_date_query(title):
            self.logger.info(f"检测到日期查询: {title}")
            _, target_date = parse_date_query(title)
            
            if target_date:
                # 按日期搜索（搜索当天的场景）
                date_str = target_date.strftime("%Y-%m-%d")
                self.logger.info(f"按日期搜索: {date_str}")
                
                results = self.scrape_by_date_range(date_str, date_str)
                self.logger.info(f"找到 {len(results)} 个场景")
                return results
        
        # 2. 检测是否为 UUID
        if re.match(r'^[A-F0-9]{32}$', title, re.I):
            self.logger.info(f"检测到 UUID: {title}")
            # 尝试刮削单个场景
            result = self._scrape_impl(title)
            
            if result:
                return [result]
            else:
                return []
        
        # 3. 否则按标题关键词搜索
        self.logger.info(f"按标题关键词搜索: {title}")
        return self._search_by_title(title)
    
    def _search_by_title(self, keywords: str) -> List[ScrapeResult]:
        """
        按标题关键词搜索场景
        
        Args:
            keywords: 搜索关键词
        
        Returns:
            匹配的场景列表（不限制数量，由管理器统一控制）
        """
        self.logger.info(f"搜索标题包含 '{keywords}' 的场景")
        
        # 规范化关键词（转小写，用于不区分大小写匹配）
        keywords_lower = keywords.lower()
        keywords_parts = keywords_lower.split()
        
        results = []
        page = 1
        max_pages = 10  # 最多搜索10页（600个场景），避免无限循环
        
        while page <= max_pages:
            galleries = self.scrape_list(page)
            if not galleries:
                break
            
            # 遍历场景，查找标题匹配的
            for gallery in galleries:
                title = gallery.get('name', '')
                title_lower = title.lower()
                
                # 检查是否所有关键词都在标题中
                if all(keyword in title_lower for keyword in keywords_parts):
                    self.logger.info(f"找到匹配场景: {title}")
                    
                    # 解析场景数据
                    result = self._parse_gallery_data(gallery)
                    if result:
                        results.append(result)
            
            # 如果已经找到结果，可以提前返回
            if results:
                break
            
            page += 1
        
        self.logger.info(f"标题搜索完成，找到 {len(results)} 个场景")
        return results
