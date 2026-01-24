"""
统一刮削管理器
整合 JAV 和 Western 刮削器，提供统一的接口和返回格式
"""

import logging
from typing import List, Optional, Dict, Any
from enum import Enum

from .jav_scraper_manager import JAVScraperManager, ScrapeResult
from .western_scraper_manager import WesternScraperManager
from .result_manager import ResultManager, ScrapeResponse, ResultMode


logger = logging.getLogger(__name__)


class ContentRegion(Enum):
    """内容地区"""
    JAV = "jav"        # 日本 AV
    WESTERN = "western"  # 欧美内容
    AUTO = "auto"      # 自动检测


class UnifiedScraperManager:
    """统一刮削管理器"""
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化管理器
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # 初始化子管理器
        self.jav_manager = JAVScraperManager(config)
        self.western_manager = WesternScraperManager(config)
        self.result_manager = ResultManager()
        
        self.logger.info("UnifiedScraperManager initialized")
    
    def scrape(
        self,
        query: str,
        region: ContentRegion = ContentRegion.AUTO,
        series: Optional[str] = None,
        content_type_hint: Optional[str] = None,
        return_mode: str = 'single',
        filters: Optional[Dict[str, Any]] = None,
        sort_by: str = 'release_date',
        page: int = 1,
        page_size: int = 20
    ) -> ScrapeResponse:
        """
        统一刮削接口
        
        Args:
            query: 搜索关键词（标题、识别号、日期等）
            region: 内容地区（jav/western/auto）
            series: 系列名（Western 用）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
            return_mode: 返回模式
                - 'single': 返回单个结果（默认）
                - 'multiple': 返回多个结果（供前端选择）
            filters: 过滤条件
            sort_by: 排序字段
            page: 页码
            page_size: 每页大小
        
        Returns:
            ScrapeResponse 统一响应格式
        """
        try:
            # 1. 检测地区
            if region == ContentRegion.AUTO:
                region = self._detect_region(query, series)
                self.logger.info(f"自动检测地区: {region.value}")
            
            # 2. 调用对应的管理器
            if region == ContentRegion.JAV:
                results = self._scrape_jav(query)
            elif region == ContentRegion.WESTERN:
                results = self._scrape_western(query, series, content_type_hint, return_mode)
            else:
                return self.result_manager.create_single_response(
                    None,
                    message=f"不支持的地区: {region}"
                )
            
            # 3. 处理结果
            if not results:
                return self.result_manager.create_single_response(
                    None,
                    message="未找到结果"
                )
            
            # 4. 过滤
            if filters:
                results = self.result_manager.filter_results(results, filters)
            
            # 5. 排序
            results = self.result_manager.sort_results(results, sort_by, reverse=True)
            
            # 6. 去重
            results = self.result_manager.deduplicate_results(results, by='code')
            
            # 7. 根据返回模式处理
            if return_mode == 'single':
                # 单个结果模式：返回第一个
                return self.result_manager.create_single_response(
                    results[0] if results else None,
                    message="刮削成功"
                )
            else:
                # 多个结果模式：分页返回
                page_results, pagination_info = self.result_manager.paginate_results(
                    results, page, page_size
                )
                
                return self.result_manager.create_multiple_response(
                    page_results,
                    message=f"找到 {len(results)} 个结果",
                    metadata=pagination_info
                )
        
        except Exception as e:
            self.logger.error(f"刮削失败: {query}, 错误: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            
            return self.result_manager.create_single_response(
                None,
                message=f"刮削失败: {str(e)}"
            )
    
    def _detect_region(self, query: str, series: Optional[str] = None) -> ContentRegion:
        """
        自动检测内容地区
        
        Args:
            query: 搜索关键词
            series: 系列名
        
        Returns:
            ContentRegion
        """
        # 如果有系列名，判断为 Western
        if series:
            return ContentRegion.WESTERN
        
        # 检查是否是 JAV 识别号格式
        # 常见格式：ABC-123, ABCD-123, ABC123
        import re
        jav_pattern = r'^[A-Z]{2,5}-?\d{3,5}$'
        if re.match(jav_pattern, query.upper().replace(' ', '')):
            return ContentRegion.JAV
        
        # 默认为 Western
        return ContentRegion.WESTERN
    
    def _scrape_jav(self, query: str) -> List[ScrapeResult]:
        """
        刮削 JAV 内容
        
        Args:
            query: 识别号
        
        Returns:
            结果列表
        """
        try:
            result = self.jav_manager.scrape(query)
            return [result] if result else []
        except Exception as e:
            self.logger.error(f"JAV 刮削失败: {query}, 错误: {e}")
            return []
    
    def _scrape_western(
        self,
        query: str,
        series: Optional[str] = None,
        content_type_hint: Optional[str] = None,
        return_mode: str = 'single'
    ) -> List[ScrapeResult]:
        """
        刮削 Western 内容
        
        Args:
            query: 搜索关键词
            series: 系列名
            content_type_hint: 内容类型提示
            return_mode: 返回模式
        
        Returns:
            结果列表
        """
        try:
            # 如果是 Movie 模式或 multiple 模式，尝试获取多个结果
            if content_type_hint == 'Movie' or return_mode == 'multiple':
                # 检查刮削器是否支持 scrape_multiple
                if hasattr(self.western_manager, 'scrape_multiple'):
                    results = self.western_manager.scrape_multiple(
                        query, series, content_type_hint
                    )
                    if results:
                        return results
            
            # 默认：单个结果
            result = self.western_manager.scrape(query, series, content_type_hint)
            return [result] if result else []
            
        except Exception as e:
            self.logger.error(f"Western 刮削失败: {query}, 错误: {e}")
            return []
    
    def scrape_by_id(
        self,
        content_id: str,
        region: ContentRegion = ContentRegion.AUTO
    ) -> ScrapeResponse:
        """
        按 ID 刮削
        
        Args:
            content_id: 内容 ID（识别号或 clip_id）
            region: 内容地区
        
        Returns:
            ScrapeResponse
        """
        return self.scrape(
            query=content_id,
            region=region,
            return_mode='single'
        )
    
    def scrape_movie_scenes(
        self,
        movie_title: str,
        series: str,
        filters: Optional[Dict[str, Any]] = None,
        sort_by: str = 'release_date',
        page: int = 1,
        page_size: int = 20
    ) -> ScrapeResponse:
        """
        按 Movie 刮削所有场景
        
        Args:
            movie_title: Movie 标题
            series: 系列名
            filters: 过滤条件
            sort_by: 排序字段
            page: 页码
            page_size: 每页大小
        
        Returns:
            ScrapeResponse（包含所有场景）
        """
        return self.scrape(
            query=movie_title,
            region=ContentRegion.WESTERN,
            series=series,
            content_type_hint='Movie',
            return_mode='multiple',
            filters=filters,
            sort_by=sort_by,
            page=page,
            page_size=page_size
        )
    
    def scrape_by_date(
        self,
        date_str: str,
        series: str,
        region: ContentRegion = ContentRegion.WESTERN,
        filters: Optional[Dict[str, Any]] = None,
        sort_by: str = 'release_date',
        page: int = 1,
        page_size: int = 20
    ) -> ScrapeResponse:
        """
        按日期刮削
        
        Args:
            date_str: 日期字符串（YYYY-MM-DD 或其他格式）
            series: 系列名
            region: 内容地区
            filters: 过滤条件
            sort_by: 排序字段
            page: 页码
            page_size: 每页大小
        
        Returns:
            ScrapeResponse（包含该日期的所有内容）
        """
        return self.scrape(
            query=date_str,
            region=region,
            series=series,
            return_mode='multiple',
            filters=filters,
            sort_by=sort_by,
            page=page,
            page_size=page_size
        )
