"""
MariskaX Scraper
刮削 MariskaX 网站的场景数据
基于 Next.js __NEXT_DATA__ 实现
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


class MariskaXScraper(BaseScraper):
    """MariskaX 刮削器"""
    
    name = 'mariskax'
    base_url = 'https://tour.mariskax.com'
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = True):
        """
        初始化 MariskaX 刮削器
        
        Args:
            config: 配置字典
            use_scraper: 是否使用 cloudscraper（推荐开启）
        """
        super().__init__(config, use_scraper=use_scraper)
        self.logger.info("MariskaX scraper initialized")
    
    def _scrape_impl(self, slug: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            slug: 场景 slug
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 构建场景 URL
        scene_url = f"{self.base_url}/scenes/{slug}"
        
        self.logger.info(f"Scraping MariskaX scene: {scene_url}")
        
        # 获取场景页面
        response = self.request.get(scene_url)
        if not response or response.status_code != 200:
            self.logger.error(f"Failed to fetch scene page: {scene_url}")
            return None
        
        html = response.text
        
        # 提取 __NEXT_DATA__
        scene_data = self._extract_next_data(html)
        if not scene_data:
            self.logger.error("Failed to extract __NEXT_DATA__ from page")
            return None
        
        # 解析场景数据
        return self._parse_scene_data(scene_data)
    
    def _extract_next_data(self, html: str) -> Optional[Dict[str, Any]]:
        """
        从 HTML 中提取 __NEXT_DATA__
        
        Args:
            html: HTML 内容
        
        Returns:
            场景数据字典，失败返回 None
        """
        try:
            # 查找 __NEXT_DATA__ script 标签
            pattern = r'<script[^>]*id=["\']__NEXT_DATA__["\'][^>]*type=["\']application/json["\'][^>]*>(.*?)</script>'
            match = re.search(pattern, html, re.DOTALL)
            
            if not match:
                self.logger.error("__NEXT_DATA__ script tag not found")
                return None
            
            # 解析 JSON
            data = json.loads(match.group(1))
            
            # 提取场景数据
            props = data.get('props', {})
            page_props = props.get('pageProps', {})
            content = page_props.get('content')
            
            if not content:
                self.logger.error("No content found in __NEXT_DATA__")
                return None
            
            return content
            
        except json.JSONDecodeError as e:
            self.logger.error(f"Failed to parse __NEXT_DATA__ JSON: {e}")
            return None
        except Exception as e:
            self.logger.error(f"Error extracting __NEXT_DATA__: {e}")
            return None
    
    def _parse_scene_data(self, data: Dict[str, Any]) -> ScrapeResult:
        """
        解析场景数据
        
        Args:
            data: 场景数据字典
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        # 基本信息
        result.code = str(data.get('id', ''))
        result.title = data.get('title', '')
        result.overview = data.get('description', '')
        
        # 日期处理
        publish_date = data.get('publish_date')
        if publish_date:
            try:
                # 格式: "2026/01/23 12:00:00"
                dt = datetime.strptime(publish_date, "%Y/%m/%d %H:%M:%S")
                result.release_date = dt.strftime("%Y-%m-%d")
                result.year = dt.year
            except ValueError:
                self.logger.warning(f"Failed to parse date: {publish_date}")
        
        # 时长（秒转分钟）
        seconds_duration = data.get('seconds_duration')
        if seconds_duration:
            result.runtime = int(seconds_duration / 60)
        
        # 评分
        rating = data.get('rating')
        if rating:
            try:
                result.rating = float(rating)
            except (ValueError, TypeError):
                pass
        
        # 制作商和系列
        result.studio = "MariskaX"
        result.series = "MariskaX"  # MariskaX 是独立网站，系列名就是网站名
        result.country = "Netherlands"  # MariskaX 是荷兰网站
        result.language = "en"
        
        # 媒体类型
        result.media_type = "Scene"
        
        # 演员
        models = data.get('models', [])
        if isinstance(models, list):
            result.actors = models
        
        # 标签
        tags = data.get('tags', [])
        if isinstance(tags, list):
            result.genres = tags
        
        # 图片
        result.poster_url = data.get('thumb')
        
        # 额外缩略图
        extra_thumbnails = data.get('extra_thumbnails', [])
        if extra_thumbnails:
            result.preview_urls = extra_thumbnails
        
        # 预览视频
        trailer_url = data.get('trailer_url')
        if trailer_url:
            result.preview_video_urls = [{
                'quality': 'Trailer',
                'url': trailer_url
            }]
        
        # 视频数据（多种质量）
        videos = data.get('videos', {})
        if isinstance(videos, dict):
            video_list = self._parse_videos(videos)
            if video_list:
                # 合并到 preview_video_urls
                if not result.preview_video_urls:
                    result.preview_video_urls = []
                result.preview_video_urls.extend(video_list)
        
        # HLS 流
        hls = data.get('hls')
        if hls and not hls.startswith('http'):
            # HLS 是相对路径，需要拼接
            # 注意：完整的 HLS URL 可能需要认证，这里只记录路径
            pass
        
        # 数据来源
        result.source = f"MariskaX (ID: {result.code})"
        
        return result
    
    def _parse_videos(self, videos: Dict[str, Any]) -> List[Dict[str, str]]:
        """
        解析视频数据
        
        Args:
            videos: 视频数据字典
                格式: {
                    "stream": {"height": 720, "width": 1280, ...},
                    "mobile": {"height": 360, "width": 640, ...},
                    "hq": {"height": 1080, "width": 1920, ...},
                    "orig": {"height": 1080, "width": 1920, ...}
                }
        
        Returns:
            视频列表: [{'quality': '720P', 'url': '...'}, ...]
            注意：MariskaX 的视频 URL 需要会员认证，这里只记录质量信息
        """
        video_list = []
        
        # 质量映射
        quality_map = {
            'stream': 'Stream',
            'mobile': 'Mobile',
            'hq': 'HQ',
            'orig': 'Original'
        }
        
        for key, quality_name in quality_map.items():
            if key in videos:
                video_info = videos[key]
                if isinstance(video_info, dict):
                    height = video_info.get('height')
                    if height:
                        quality_label = f"{height}P"
                    else:
                        quality_label = quality_name
                    
                    # 注意：实际的视频 URL 需要会员认证
                    # 这里只记录质量信息，URL 留空或使用占位符
                    video_list.append({
                        'quality': quality_label,
                        'url': ''  # 需要会员认证
                    })
        
        return video_list
    
    def scrape_list(self, page: int = 1) -> List[Dict[str, Any]]:
        """
        刮削场景列表
        
        Args:
            page: 页码（从1开始）
        
        Returns:
            场景列表
        """
        url = f"{self.base_url}/scenes?page={page}"
        self.logger.info(f"Scraping MariskaX scenes list: page {page}")
        
        response = self.request.get(url)
        if not response or response.status_code != 200:
            self.logger.error(f"Failed to fetch scenes list: {url}")
            return []
        
        html = response.text
        
        # 提取 __NEXT_DATA__
        try:
            pattern = r'<script[^>]*id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>'
            match = re.search(pattern, html, re.DOTALL)
            
            if not match:
                self.logger.error("__NEXT_DATA__ not found in list page")
                return []
            
            data = json.loads(match.group(1))
            props = data.get('props', {})
            page_props = props.get('pageProps', {})
            contents = page_props.get('contents', {})
            
            scenes = contents.get('data', [])
            
            self.logger.info(f"Found {len(scenes)} scenes on page {page}")
            return scenes
            
        except Exception as e:
            self.logger.error(f"Error parsing scenes list: {e}")
            return []
    
    def scrape_multiple(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        刮削多个结果（实现 WesternScraperManager 接口）
        
        MariskaX 的实现：
        - 移除系列名前缀（如 "MariskaX-Title" → "Title"）
        - 按标题关键词搜索
        
        Args:
            title: 标题（可能包含系列名前缀）
            content_type_hint: 内容类型提示（忽略）
            series: 系列名（忽略）
        
        Returns:
            ScrapeResult 列表
        """
        self.logger.info(f"scrape_multiple called: title={title}")
        
        # 移除系列名前缀（如果有）
        from utils.query_parser import extract_series_and_title
        
        extracted_series, clean_title = extract_series_and_title(title)
        if extracted_series:
            self.logger.info(f"移除系列名前缀: {extracted_series}, 搜索标题: {clean_title}")
            title = clean_title
        
        # 按标题关键词搜索
        self.logger.info(f"按标题搜索: {title}")
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
        max_pages = 10  # 最多搜索10页（120个场景），避免无限循环
        
        while page <= max_pages:
            scenes = self.scrape_list(page)
            if not scenes:
                break
            
            # 遍历场景，查找标题匹配的
            for scene in scenes:
                title = scene.get('title', '')
                title_lower = title.lower()
                
                # 检查是否所有关键词都在标题中
                if all(keyword in title_lower for keyword in keywords_parts):
                    self.logger.info(f"找到匹配场景: {title}")
                    
                    # 刮削详细数据
                    slug = scene.get('slug')
                    if slug:
                        result = self._scrape_impl(slug)
                        if result:
                            results.append(result)
            
            # 如果已经找到结果，继续搜索更多页（不提前返回）
            # 由管理器统一控制最终返回的结果数量
            
            page += 1
        
        self.logger.info(f"标题搜索完成，找到 {len(results)} 个场景")
        return results
