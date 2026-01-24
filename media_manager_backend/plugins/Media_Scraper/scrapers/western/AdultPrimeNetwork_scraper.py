"""
AdultEmpire 刮削器
从 AdultEmpire 网站刮削欧美成人内容元数据
"""

import logging
import re
from typing import Optional, List, Dict, Any
from urllib.parse import quote, urljoin
from lxml import html as lxml_html

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, NetworkError


logger = logging.getLogger(__name__)


class SearchResult:
    """搜索结果数据类"""
    def __init__(self, title: str, url: str, year: Optional[int] = None, 
                 poster_url: Optional[str] = None):
        self.title = title
        self.url = url
        self.year = year
        self.poster_url = poster_url


class AdultEmpireScraper(BaseScraper):
    """AdultEmpire 刮削器"""
    
    name = 'adultempire'
    base_url = 'https://www.adultempire.com'
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
        """
        super().__init__(config, use_scraper=True)  # 使用 cloudscraper
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"AdultEmpireScraper initialized")
    
    def _scrape_impl(self, title: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        流程：
        1. 搜索标题
        2. 从搜索结果中选择最佳匹配
        3. 获取详情页
        4. 解析元数据
        
        Args:
            title: 作品标题
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 1. 搜索
        search_results = self.search(title)
        if not search_results:
            self.logger.warning(f"搜索无结果: {title}")
            raise MovieNotFoundError(self.name, title)
        
        self.logger.info(f"找到 {len(search_results)} 个搜索结果")
        
        # 2. 选择最佳匹配
        best_match = self._find_best_match(title, search_results)
        if not best_match:
            self.logger.warning(f"未找到匹配结果: {title}")
            raise MovieNotFoundError(self.name, title)
        
        self.logger.info(f"最佳匹配: {best_match.title} ({best_match.url})")
        
        # 3. 获取详情页
        detail_html = self.request.get_html(best_match.url)
        
        # 4. 解析详情页
        result = self._parse_detail(detail_html, title)
        
        self.logger.info(f"刮削成功: {title}")
        return result
    
    def search(self, title: str) -> List[SearchResult]:
        """
        搜索作品
        
        Args:
            title: 作品标题
        
        Returns:
            搜索结果列表
        """
        try:
            # 构建搜索 URL
            search_url = f'{self.base_url}/allsearch/search?q={quote(title)}'
            self.logger.debug(f"搜索 URL: {search_url}")
            
            # 获取搜索页面
            self.logger.debug(f"开始请求搜索页面...")
            search_html = self.request.get_html(search_url)
            self.logger.debug(f"搜索页面请求完成")
            
            # 解析搜索结果
            results = self._parse_search_results(search_html)
            self.logger.debug(f"解析到 {len(results)} 个搜索结果")
            
            return results
            
        except Exception as e:
            self.logger.error(f"搜索失败: {title} - {e}")
            return []
    
    def _parse_search_results(self, html_doc) -> List[SearchResult]:
        """
        解析搜索结果页面
        
        Args:
            html_doc: lxml HTML 文档对象
        
        Returns:
            搜索结果列表
        """
        results = []
        
        try:
            # AdultEmpire 搜索结果通常在 .item-list 或 .product-list 中
            # 尝试多种选择器
            items = html_doc.xpath('//div[contains(@class, "item")]')
            
            if not items:
                # 尝试备用选择器
                items = html_doc.xpath('//div[contains(@class, "product")]')
            
            self.logger.debug(f"找到 {len(items)} 个搜索结果项")
            
            for item in items:
                try:
                    # 提取标题和链接
                    title_elem = item.xpath('.//a[contains(@class, "title") or contains(@class, "name")]')
                    if not title_elem:
                        title_elem = item.xpath('.//h3//a | .//h4//a')
                    
                    if not title_elem:
                        continue
                    
                    title = title_elem[0].text_content().strip()
                    url = title_elem[0].get('href', '')
                    
                    if not url:
                        continue
                    
                    # 确保 URL 是绝对路径
                    if not url.startswith('http'):
                        url = urljoin(self.base_url, url)
                    
                    # 提取年份（如果有）
                    year = None
                    year_text = item.xpath('.//span[contains(@class, "year")]//text()')
                    if year_text:
                        year_match = re.search(r'(19|20)\d{2}', year_text[0])
                        if year_match:
                            year = int(year_match.group(0))
                    
                    # 提取封面图（如果有）
                    poster_url = None
                    poster_elem = item.xpath('.//img/@src')
                    if poster_elem:
                        poster_url = poster_elem[0]
                        if not poster_url.startswith('http'):
                            poster_url = urljoin(self.base_url, poster_url)
                    
                    results.append(SearchResult(
                        title=title,
                        url=url,
                        year=year,
                        poster_url=poster_url
                    ))
                    
                except Exception as e:
                    self.logger.debug(f"解析搜索结果项失败: {e}")
                    continue
            
        except Exception as e:
            self.logger.error(f"解析搜索结果失败: {e}")
        
        return results
    
    def _find_best_match(self, query: str, results: List[SearchResult]) -> Optional[SearchResult]:
        """
        从搜索结果中找到最佳匹配
        
        策略：
        1. 优先选择标题完全匹配的结果
        2. 如果没有完全匹配，选择第一个结果
        
        Args:
            query: 搜索查询
            results: 搜索结果列表
        
        Returns:
            最佳匹配结果，如果没有则返回 None
        """
        if not results:
            return None
        
        # 规范化查询字符串
        query_normalized = query.lower().strip()
        
        # 尝试找到完全匹配
        for result in results:
            result_normalized = result.title.lower().strip()
            if query_normalized == result_normalized:
                self.logger.debug(f"找到完全匹配: {result.title}")
                return result
        
        # 尝试找到包含匹配
        for result in results:
            result_normalized = result.title.lower().strip()
            if query_normalized in result_normalized or result_normalized in query_normalized:
                self.logger.debug(f"找到包含匹配: {result.title}")
                return result
        
        # 如果没有匹配，返回第一个结果
        self.logger.debug(f"使用第一个结果: {results[0].title}")
        return results[0]
    
    def _parse_detail(self, html_doc, title: str) -> ScrapeResult:
        """
        解析详情页
        
        Args:
            html_doc: lxml HTML 文档对象
            title: 原始标题
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        result.title = title
        
        try:
            # 提取标题
            title_elem = html_doc.xpath('//h1[@class="item-title" or contains(@class, "title")]//text()')
            if title_elem:
                result.original_title = title_elem[0].strip()
            
            # 提取发售日期
            date_elem = html_doc.xpath('//span[contains(text(), "Released")]/following-sibling::text() | //li[contains(text(), "Released")]//text()')
            if date_elem:
                date_text = date_elem[0].strip()
                date_match = re.search(r'(\d{1,2})/(\d{1,2})/(\d{4})', date_text)
                if date_match:
                    month, day, year = date_match.groups()
                    result.release_date = f"{year}-{month.zfill(2)}-{day.zfill(2)}"
                    result.year = int(year)
            
            # 提取制作商
            studio_elem = html_doc.xpath('//span[contains(text(), "Studio")]/following-sibling::a//text() | //li[contains(text(), "Studio")]//a//text()')
            if studio_elem:
                result.studio = studio_elem[0].strip()
            
            # 提取系列
            series_elem = html_doc.xpath('//span[contains(text(), "Series")]/following-sibling::a//text() | //li[contains(text(), "Series")]//a//text()')
            if series_elem:
                result.series = series_elem[0].strip()
            
            # 提取演员
            actors = []
            actor_elems = html_doc.xpath('//div[contains(@class, "cast")]//a//text() | //ul[contains(@class, "performers")]//a//text()')
            for actor in actor_elems:
                actor_name = actor.strip()
                if actor_name and actor_name not in actors:
                    actors.append(actor_name)
            result.actors = actors
            
            # 提取类型标签
            genres = []
            genre_elems = html_doc.xpath('//div[contains(@class, "categories")]//a//text() | //ul[contains(@class, "categories")]//a//text()')
            for genre in genre_elems:
                genre_name = genre.strip()
                if genre_name and genre_name not in genres:
                    genres.append(genre_name)
            result.genres = genres
            
            # 提取封面图
            poster_elem = html_doc.xpath('//img[@class="front-cover" or contains(@class, "boxcover")]/@src')
            if poster_elem:
                poster_url = poster_elem[0]
                if not poster_url.startswith('http'):
                    poster_url = urljoin(self.base_url, poster_url)
                result.poster_url = poster_url
            
            # 提取简介
            overview_elem = html_doc.xpath('//div[contains(@class, "synopsis") or contains(@class, "description")]//text()')
            if overview_elem:
                overview = ' '.join([text.strip() for text in overview_elem if text.strip()])
                result.overview = overview
            
            # 提取时长
            runtime_elem = html_doc.xpath('//span[contains(text(), "Length")]/following-sibling::text() | //li[contains(text(), "Length")]//text()')
            if runtime_elem:
                runtime_text = runtime_elem[0].strip()
                runtime_match = re.search(r'(\d+)\s*min', runtime_text, re.I)
                if runtime_match:
                    result.runtime = int(runtime_match.group(1))
            
            # 提取导演
            director_elem = html_doc.xpath('//span[contains(text(), "Director")]/following-sibling::a//text() | //li[contains(text(), "Director")]//a//text()')
            if director_elem:
                result.director = director_elem[0].strip()
            
            self.logger.debug(f"解析详情页成功: 演员={len(result.actors)}, 类型={len(result.genres)}")
            
        except Exception as e:
            self.logger.error(f"解析详情页失败: {e}", exc_info=True)
        
        return result
