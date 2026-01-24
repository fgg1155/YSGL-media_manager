"""
IAFD 刮削器
从 IAFD (Internet Adult Film Database) 网站刮削欧美成人内容元数据
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
    def __init__(self, title: str, url: str, year: Optional[int] = None):
        self.title = title
        self.url = url
        self.year = year


class IAFDScraper(BaseScraper):
    """IAFD 刮削器"""
    
    name = 'iafd'
    base_url = 'https://www.iafd.com'
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
        """
        super().__init__(config, use_scraper=True)  # 使用 cloudscraper
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"IAFDScraper initialized")
    
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
            # IAFD 使用 /results.asp?searchtype=title&searchstring=xxx
            search_url = f'{self.base_url}/results.asp?searchtype=title&searchstring={quote(title)}'
            self.logger.debug(f"搜索 URL: {search_url}")
            
            # 获取搜索页面
            search_html = self.request.get_html(search_url)
            
            # 解析搜索结果
            results = self._parse_search_results(search_html)
            
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
            # IAFD 搜索结果通常在表格中
            # 尝试多种选择器
            rows = html_doc.xpath('//table[@id="titleresult"]//tr | //table[@id="tblMal"]//tr')
            
            self.logger.debug(f"找到 {len(rows)} 个搜索结果行")
            
            for row in rows:
                try:
                    # 跳过表头
                    if row.xpath('.//th'):
                        continue
                    
                    # 提取标题和链接
                    title_elem = row.xpath('.//td[1]//a')
                    if not title_elem:
                        continue
                    
                    title = title_elem[0].text_content().strip()
                    url = title_elem[0].get('href', '')
                    
                    if not url:
                        continue
                    
                    # 确保 URL 是绝对路径
                    if not url.startswith('http'):
                        url = urljoin(self.base_url, url)
                    
                    # 提取年份（通常在第二列）
                    year = None
                    year_elem = row.xpath('.//td[2]//text()')
                    if year_elem:
                        year_text = year_elem[0].strip()
                        year_match = re.search(r'(19|20)\d{2}', year_text)
                        if year_match:
                            year = int(year_match.group(0))
                    
                    results.append(SearchResult(
                        title=title,
                        url=url,
                        year=year
                    ))
                    
                except Exception as e:
                    self.logger.debug(f"解析搜索结果行失败: {e}")
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
            title_elem = html_doc.xpath('//h1//text()')
            if title_elem:
                result.original_title = title_elem[0].strip()
            
            # 提取发售日期和年份
            # IAFD 通常在 "Release Date:" 标签后
            date_elem = html_doc.xpath('//p[contains(text(), "Release Date:")]/text()')
            if date_elem:
                date_text = date_elem[0]
                date_match = re.search(r'(\w+)\s+(\d{1,2}),\s+(\d{4})', date_text)
                if date_match:
                    month_name, day, year = date_match.groups()
                    # 转换月份名称为数字
                    month_map = {
                        'January': '01', 'February': '02', 'March': '03', 'April': '04',
                        'May': '05', 'June': '06', 'July': '07', 'August': '08',
                        'September': '09', 'October': '10', 'November': '11', 'December': '12'
                    }
                    month = month_map.get(month_name, '01')
                    result.release_date = f"{year}-{month}-{day.zfill(2)}"
                    result.year = int(year)
            
            # 提取制作商
            studio_elem = html_doc.xpath('//p[contains(text(), "Studio:")]/a//text() | //p[contains(text(), "Distributor:")]/a//text()')
            if studio_elem:
                result.studio = studio_elem[0].strip()
            
            # 提取系列
            series_elem = html_doc.xpath('//p[contains(text(), "Series:")]/a//text()')
            if series_elem:
                result.series = series_elem[0].strip()
            
            # 提取演员
            actors = []
            # IAFD 演员通常在特定的 div 或表格中
            actor_elems = html_doc.xpath('//div[@id="castbox"]//a//text() | //p[contains(text(), "Performers:")]/following-sibling::p//a//text()')
            for actor in actor_elems:
                actor_name = actor.strip()
                if actor_name and actor_name not in actors:
                    actors.append(actor_name)
            result.actors = actors
            
            # 提取类型标签
            genres = []
            genre_elems = html_doc.xpath('//p[contains(text(), "Categories:")]/a//text()')
            for genre in genre_elems:
                genre_name = genre.strip()
                if genre_name and genre_name not in genres:
                    genres.append(genre_name)
            result.genres = genres
            
            # 提取封面图
            poster_elem = html_doc.xpath('//img[@id="cover-pic"]/@src | //div[@id="coverbox"]//img/@src')
            if poster_elem:
                poster_url = poster_elem[0]
                if not poster_url.startswith('http'):
                    poster_url = urljoin(self.base_url, poster_url)
                result.poster_url = poster_url
            
            # 提取简介
            overview_elem = html_doc.xpath('//div[@id="synopsis"]//text() | //p[contains(@class, "synopsis")]//text()')
            if overview_elem:
                overview = ' '.join([text.strip() for text in overview_elem if text.strip()])
                result.overview = overview
            
            # 提取时长
            runtime_elem = html_doc.xpath('//p[contains(text(), "Minutes:")]/text()')
            if runtime_elem:
                runtime_text = runtime_elem[0]
                runtime_match = re.search(r'(\d+)', runtime_text)
                if runtime_match:
                    result.runtime = int(runtime_match.group(1))
            
            # 提取导演
            director_elem = html_doc.xpath('//p[contains(text(), "Director:")]/a//text()')
            if director_elem:
                result.director = director_elem[0].strip()
            
            self.logger.debug(f"解析详情页成功: 演员={len(result.actors)}, 类型={len(result.genres)}")
            
        except Exception as e:
            self.logger.error(f"解析详情页失败: {e}", exc_info=True)
        
        return result
