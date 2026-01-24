"""
AdultPrime Network Scraper
刮削 AdultPrime 网络的场景数据
基于 HTML 解析实现（参考 AdultPrimeNetwork.cs）
"""

import logging
import re
from datetime import datetime
from typing import Optional, Dict, Any, List
from urllib.parse import quote, urljoin
from lxml import html as lxml_html

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult

logger = logging.getLogger(__name__)


class AdultPrimeScraper(BaseScraper):
    """AdultPrime Network 刮削器"""
    
    name = 'adultprime'
    base_url = 'https://adultprime.com'
    search_url_template = 'https://adultprime.com/studios/search?q={}'
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = True):
        """
        初始化 AdultPrime 刮削器
        
        Args:
            config: 配置字典
            use_scraper: 是否使用 cloudscraper（推荐开启）
        """
        super().__init__(config, use_scraper=use_scraper)
        
        self.logger.info("AdultPrime scraper initialized")
    
    def _scrape_impl(self, query: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            query: 场景 ID 或标题
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 如果是完整 URL
        if query.startswith('http'):
            scene_url = query
        # 如果是场景 ID（纯数字）
        elif query.isdigit():
            scene_url = f"{self.base_url}/studios/video/{query}"
        else:
            # 按标题搜索
            self.logger.info(f"Searching for: {query}")
            search_results = self._search_by_title(query)
            
            if not search_results:
                self.logger.warning(f"No search results found for: {query}")
                return None
            
            # 使用第一个结果
            scene_url = search_results[0]['url']
            self.logger.info(f"Using first result: {scene_url}")
        
        # 获取场景详情页
        self.logger.info(f"Scraping AdultPrime scene: {scene_url}")
        
        response = self.request.get(scene_url)
        if not response or response.status_code != 200:
            self.logger.error(f"Failed to fetch scene page: {scene_url}")
            return None
        
        # 解析 HTML
        html_doc = lxml_html.fromstring(response.content)
        
        # 解析场景数据
        return self._parse_scene_data(html_doc, scene_url)
    
    def _search_by_title(self, title: str) -> List[Dict[str, Any]]:
        """
        按标题搜索场景
        
        Args:
            title: 搜索关键词
        
        Returns:
            搜索结果列表
        """
        search_url = self.search_url_template.format(quote(title))
        self.logger.info(f"Searching: {search_url}")
        
        response = self.request.get(search_url)
        if not response or response.status_code != 200:
            self.logger.error(f"Failed to fetch search page: {search_url}")
            return []
        
        # 解析搜索结果
        html_doc = lxml_html.fromstring(response.content)
        
        # 检查是否有结果
        no_results = html_doc.xpath("//h2[contains(@class, 'no-results-text')]")
        if no_results:
            no_results_text = no_results[0].text_content().strip()
            if 'No results found' in no_results_text:
                self.logger.info("No results found")
                return []
        
        # 提取搜索结果
        results = []
        items = html_doc.xpath("//ul[@id='studio-videos-container']/li")
        
        if not items:
            self.logger.warning("No search result items found")
            return []
        
        for item in items:
            try:
                # 提取链接
                link_elem = item.xpath(".//a")
                if not link_elem:
                    continue
                
                href = link_elem[0].get('href', '')
                if not href:
                    continue
                
                # 构建完整 URL
                url = urljoin(self.base_url, href)
                
                # 提取场景 ID
                scene_id = self._extract_scene_id(href)
                if not scene_id:
                    continue
                
                # 提取标题
                title_elem = item.xpath(".//span[contains(@class, 'description-title')]")
                scene_title = title_elem[0].text_content().strip() if title_elem else ''
                
                # 提取发布日期
                date_elem = item.xpath(".//span[contains(@class, 'description-releasedate')]")
                release_date = None
                if date_elem:
                    date_text = date_elem[0].text_content().strip()
                    try:
                        # 格式: "MMM dd, yyyy" (e.g., "Jan 15, 2024")
                        dt = datetime.strptime(date_text, "%b %d, %Y")
                        release_date = dt.strftime("%Y-%m-%d")
                    except ValueError:
                        pass
                
                # 提取时长
                duration_elem = item.xpath(".//span[contains(@class, 'video-duration')]")
                runtime = None
                if duration_elem:
                    duration_text = duration_elem[0].text_content().strip()
                    # 时长是秒数
                    try:
                        runtime = int(duration_text) // 60  # 转换为分钟
                    except ValueError:
                        pass
                
                results.append({
                    'id': scene_id,
                    'title': scene_title,
                    'url': url,
                    'release_date': release_date,
                    'runtime': runtime
                })
                
            except Exception as e:
                self.logger.warning(f"Failed to parse search result item: {e}")
                continue
        
        self.logger.info(f"Found {len(results)} search results")
        return results
    
    def _extract_scene_id(self, url: str) -> Optional[str]:
        """
        从 URL 中提取场景 ID
        
        Args:
            url: URL 或路径
        
        Returns:
            场景 ID，失败返回 None
        """
        # 支持两种格式:
        # /studios/video/123456
        # /signup?galleryId=123456
        
        match = re.search(r'/video/(\d+)', url)
        if match:
            return match.group(1)
        
        match = re.search(r'galleryId=(\d+)', url)
        if match:
            return match.group(1)
        
        return None
    

    def _parse_scene_data(self, html_doc, scene_url: str) -> ScrapeResult:
        """
        解析场景数据
        
        Args:
            html_doc: lxml HTML 文档对象
            scene_url: 场景 URL
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        # 提取场景 ID
        result.code = self._extract_scene_id(scene_url) or ''
        
        # 查找内容描述容器
        content_div = html_doc.xpath("//div[@class='update-info-container'][.//h1]")
        if not content_div:
            self.logger.warning("Content container not found")
            return result
        
        content_div = content_div[0]
        
        # 提取标题
        title_elem = content_div.xpath(".//h1[contains(@class, 'update-info-title')]")
        if title_elem:
            # 使用 text_content() 获取所有文本，然后清理
            title_text = title_elem[0].text_content()
            
            # 移除 "video:" 前缀
            if 'video:' in title_text:
                title_text = title_text.split('video:', 1)[1]
            
            # 移除 " video by " 及其后面的内容
            if ' video by ' in title_text:
                title_text = title_text.split(' video by ')[0]
            
            # 清理空白字符（包括制表符、换行符等）
            title_text = ' '.join(title_text.split())
            
            # 移除末尾的 "Full" 文本（如果存在）
            title_text = re.sub(r'\s+Full\s*$', '', title_text, flags=re.IGNORECASE)
            
            result.title = title_text.strip()
        
        # 提取演员
        actor_elems = content_div.xpath(".//p[contains(@class, 'update-info-line')][.//b[contains(text(), 'Performer')]]//a")
        actors = []
        for actor_elem in actor_elems:
            actor_name = actor_elem.text_content().strip()
            if actor_name:
                actors.append(actor_name)
        result.actors = actors
        
        # 提取标签
        tag_elems = content_div.xpath(".//p[contains(@class, 'update-info-line')]//b[contains(text(), 'Niches')]/following-sibling::a")
        tags = []
        for tag_elem in tag_elems:
            tag_name = tag_elem.text_content().strip()
            if tag_name:
                tags.append(tag_name)
        result.genres = tags
        
        # 提取简介
        desc_elem = content_div.xpath(".//p[contains(@class, 'update-info-line')][contains(@class, 'ap-limited-description-text')]")
        if desc_elem:
            result.overview = desc_elem[0].text_content().strip()
        
        # 提取封面图和预览视频
        # 方式1: video poster (封面图)
        poster_elem = html_doc.xpath("//video[@id='portal-video']/@poster")
        if poster_elem:
            result.poster_url = poster_elem[0]
        else:
            # 方式2: background-url (封面图备选)
            theatre_elem = html_doc.xpath("//div[@id='theatre-row']//div[./svg]/@style")
            if theatre_elem:
                style_text = theatre_elem[0]
                # 提取 background-url
                match = re.search(r'url\(["\']?([^"\'\)]+)["\']?\)', style_text)
                if match:
                    bg_url = match.group(1)
                    if '://' in bg_url:
                        result.poster_url = bg_url
        
        # 硬编码封面视频 URL（基于场景 ID）
        # URL 格式: https://cdnstatic.imctransfer.com/static_01/{前5位}/{完整ID}/preview_320.mp4
        if result.code and result.code.isdigit():
            scene_id = result.code
            # 计算前5位（向下取整到千位）
            id_prefix = (int(scene_id) // 1000) * 1000
            
            # 构建封面视频 URL
            cover_video_url = f"https://cdnstatic.imctransfer.com/static_01/{id_prefix}/{scene_id}/preview_320.mp4"
            result.cover_video_url = cover_video_url
            self.logger.info(f"生成封面视频 URL: {cover_video_url}")
        
        # 提取预览视频（从 video 标签的 source 子元素）
        video_sources = html_doc.xpath("//video[@id='portal-video']//source")
        if video_sources:
            preview_videos = []
            for source in video_sources:
                src = source.get('src', '')
                type_attr = source.get('type', '')
                
                if src and '://' in src:
                    # 尝试从 URL 或 type 推断质量
                    quality = 'Unknown'
                    if '1080' in src or '1080p' in type_attr:
                        quality = '1080p'
                    elif '720' in src or '720p' in type_attr:
                        quality = '720p'
                    elif '480' in src or '480p' in type_attr:
                        quality = '480p'
                    elif 'hd' in src.lower() or 'hd' in type_attr.lower():
                        quality = 'HD'
                    
                    preview_videos.append({
                        'quality': quality,
                        'url': src
                    })
            
            if preview_videos:
                result.preview_video_urls = preview_videos
                self.logger.info(f"找到 {len(preview_videos)} 个预览视频")
        
        # 提取工作室（子站点名）
        studio_elem = content_div.xpath(".//p[contains(@class, 'update-info-line')]//b[contains(text(), 'Studio')]//a")
        if studio_elem:
            studio_name = studio_elem[0].text_content().strip()
            result.studio = studio_name  # 子站点名（如 Club SweetHearts）
            result.series = studio_name  # AdultPrime 的 series 就是子站点名
        else:
            # 如果没有找到工作室，使用 AdultPrime
            result.studio = "AdultPrime"
            result.series = "AdultPrime"
        
        # 国家和语言
        result.country = "Netherlands"  # AdultPrime 总部在荷兰
        result.language = "en"
        
        # 媒体类型
        result.media_type = "Scene"
        
        # 数据来源
        result.source = f"AdultPrime (ID: {result.code})"
        
        return result
    
    def scrape_multiple(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        刮削多个结果（实现 WesternScraperManager 接口）
        
        Args:
            title: 标题或场景 ID
            content_type_hint: 内容类型提示（忽略）
            series: 系列名（工作室名）
        
        Returns:
            ScrapeResult 列表
        """
        self.logger.info(f"scrape_multiple called: title={title}, series={series}")
        
        # 移除系列名前缀（如果有）
        from utils.query_parser import extract_series_and_title
        
        extracted_series, clean_title = extract_series_and_title(title)
        if extracted_series:
            self.logger.info(f"检测到系列名前缀: {extracted_series}, 移除后的标题: {clean_title}")
            title = clean_title
            if not series:
                series = extracted_series
        
        # 如果是场景 ID 或 URL，返回单个结果
        if title.isdigit() or title.startswith('http') or '/video/' in title or 'galleryId=' in title:
            self.logger.info(f"检测到场景 ID 或 URL: {title}")
            result = self._scrape_impl(title)
            
            if result:
                return [result]
            else:
                return []
        
        # 否则按标题搜索
        self.logger.info(f"按标题搜索: {title}")
        search_results = self._search_by_title(title)
        
        if not search_results:
            return []
        
        # 刮削所有搜索结果（不限制数量，由管理器统一控制）
        results = []
        for search_result in search_results:
            try:
                result = self._scrape_impl(search_result['url'])
                if result:
                    results.append(result)
            except Exception as e:
                self.logger.warning(f"Failed to scrape scene: {search_result['url']} - {e}")
                continue
        
        self.logger.info(f"找到 {len(results)} 个场景")
        return results
