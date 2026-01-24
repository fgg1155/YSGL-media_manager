"""
刮削结果管理器
统一管理所有刮削器的返回结果，支持单个/多个结果返回
"""

import logging
from typing import List, Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum

from .jav_scraper_manager import ScrapeResult


logger = logging.getLogger(__name__)


class ResultMode(Enum):
    """结果返回模式"""
    SINGLE = "single"      # 单个结果（默认）
    MULTIPLE = "multiple"  # 多个结果（供前端选择）
    ALL = "all"           # 所有结果（不过滤）


@dataclass
class ScrapeResponse:
    """刮削响应数据模型"""
    success: bool                          # 是否成功
    mode: ResultMode                       # 返回模式
    results: List[ScrapeResult]           # 结果列表
    total_count: int                       # 总结果数
    message: Optional[str] = None          # 消息（错误或提示）
    metadata: Optional[Dict[str, Any]] = None  # 额外元数据
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            'success': self.success,
            'mode': self.mode.value,
            'results': [r.to_dict() for r in self.results],
            'total_count': self.total_count,
            'message': self.message,
            'metadata': self.metadata or {}
        }
    
    @property
    def first_result(self) -> Optional[ScrapeResult]:
        """获取第一个结果"""
        return self.results[0] if self.results else None


class ResultManager:
    """刮削结果管理器"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
    
    def create_single_response(
        self, 
        result: Optional[ScrapeResult], 
        message: Optional[str] = None
    ) -> ScrapeResponse:
        """
        创建单个结果响应
        
        Args:
            result: 刮削结果
            message: 消息
        
        Returns:
            ScrapeResponse
        """
        if result:
            return ScrapeResponse(
                success=True,
                mode=ResultMode.SINGLE,
                results=[result],
                total_count=1,
                message=message
            )
        else:
            return ScrapeResponse(
                success=False,
                mode=ResultMode.SINGLE,
                results=[],
                total_count=0,
                message=message or "未找到结果"
            )
    
    def create_multiple_response(
        self,
        results: List[ScrapeResult],
        message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> ScrapeResponse:
        """
        创建多个结果响应（供前端选择）
        
        Args:
            results: 结果列表
            message: 消息
            metadata: 额外元数据
        
        Returns:
            ScrapeResponse
        """
        if results:
            return ScrapeResponse(
                success=True,
                mode=ResultMode.MULTIPLE,
                results=results,
                total_count=len(results),
                message=message or f"找到 {len(results)} 个结果",
                metadata=metadata
            )
        else:
            return ScrapeResponse(
                success=False,
                mode=ResultMode.MULTIPLE,
                results=[],
                total_count=0,
                message=message or "未找到结果",
                metadata=metadata
            )
    
    def filter_results(
        self,
        results: List[ScrapeResult],
        filters: Optional[Dict[str, Any]] = None
    ) -> List[ScrapeResult]:
        """
        过滤结果
        
        Args:
            results: 结果列表
            filters: 过滤条件
                - media_type: 媒体类型（Scene/Movie/Compilation）
                - min_runtime: 最小时长（分钟）
                - max_runtime: 最大时长（分钟）
                - actors: 演员列表（包含任意一个）
                - genres: 类型列表（包含任意一个）
                - series: 系列名
                - studio: 工作室名
        
        Returns:
            过滤后的结果列表
        """
        if not filters:
            return results
        
        filtered = results
        
        # 媒体类型过滤
        if 'media_type' in filters and filters['media_type']:
            media_type = filters['media_type']
            filtered = [r for r in filtered if r.media_type == media_type]
            self.logger.info(f"按 media_type={media_type} 过滤: {len(filtered)} 个结果")
        
        # 时长过滤
        if 'min_runtime' in filters and filters['min_runtime']:
            min_runtime = filters['min_runtime']
            filtered = [r for r in filtered if r.runtime and r.runtime >= min_runtime]
            self.logger.info(f"按 min_runtime={min_runtime} 过滤: {len(filtered)} 个结果")
        
        if 'max_runtime' in filters and filters['max_runtime']:
            max_runtime = filters['max_runtime']
            filtered = [r for r in filtered if r.runtime and r.runtime <= max_runtime]
            self.logger.info(f"按 max_runtime={max_runtime} 过滤: {len(filtered)} 个结果")
        
        # 演员过滤
        if 'actors' in filters and filters['actors']:
            target_actors = set(filters['actors'])
            filtered = [
                r for r in filtered 
                if r.actors and any(actor in target_actors for actor in r.actors)
            ]
            self.logger.info(f"按 actors 过滤: {len(filtered)} 个结果")
        
        # 类型过滤
        if 'genres' in filters and filters['genres']:
            target_genres = set(filters['genres'])
            filtered = [
                r for r in filtered 
                if r.genres and any(genre in target_genres for genre in r.genres)
            ]
            self.logger.info(f"按 genres 过滤: {len(filtered)} 个结果")
        
        # 系列过滤
        if 'series' in filters and filters['series']:
            series = filters['series'].lower()
            filtered = [r for r in filtered if r.series and series in r.series.lower()]
            self.logger.info(f"按 series={series} 过滤: {len(filtered)} 个结果")
        
        # 工作室过滤
        if 'studio' in filters and filters['studio']:
            studio = filters['studio'].lower()
            filtered = [r for r in filtered if r.studio and studio in r.studio.lower()]
            self.logger.info(f"按 studio={studio} 过滤: {len(filtered)} 个结果")
        
        return filtered
    
    def sort_results(
        self,
        results: List[ScrapeResult],
        sort_by: str = 'release_date',
        reverse: bool = True
    ) -> List[ScrapeResult]:
        """
        排序结果
        
        Args:
            results: 结果列表
            sort_by: 排序字段（release_date/runtime/rating/title）
            reverse: 是否倒序
        
        Returns:
            排序后的结果列表
        """
        if not results:
            return results
        
        try:
            if sort_by == 'release_date':
                sorted_results = sorted(
                    results,
                    key=lambda r: r.release_date or '',
                    reverse=reverse
                )
            elif sort_by == 'runtime':
                sorted_results = sorted(
                    results,
                    key=lambda r: r.runtime or 0,
                    reverse=reverse
                )
            elif sort_by == 'rating':
                sorted_results = sorted(
                    results,
                    key=lambda r: r.rating or 0,
                    reverse=reverse
                )
            elif sort_by == 'title':
                sorted_results = sorted(
                    results,
                    key=lambda r: r.title or '',
                    reverse=reverse
                )
            else:
                self.logger.warning(f"未知的排序字段: {sort_by}")
                sorted_results = results
            
            self.logger.info(f"按 {sort_by} 排序（倒序={reverse}）")
            return sorted_results
            
        except Exception as e:
            self.logger.error(f"排序失败: {e}")
            return results
    
    def select_best_match(
        self,
        results: List[ScrapeResult],
        search_title: str,
        exclude_keywords: Optional[List[str]] = None
    ) -> Optional[ScrapeResult]:
        """
        从多个结果中智能选择最佳匹配
        
        Args:
            results: 结果列表
            search_title: 搜索的标题
            exclude_keywords: 排除关键词列表（如 BTS、花絮等）
        
        Returns:
            最佳匹配的结果，如果没有合适的返回 None
        """
        if not results:
            return None
        
        if len(results) == 1:
            return results[0]
        
        # 导入工具模块的匹配函数
        try:
            import sys
            from pathlib import Path
            sys.path.insert(0, str(Path(__file__).parent.parent))
            from utils.query_parser import calculate_title_match_score
        except ImportError:
            self.logger.error("无法导入 query_parser 模块")
            # 回退：返回第一个结果
            return results[0]
        
        # 默认排除关键词
        if exclude_keywords is None:
            exclude_keywords = ['bts', 'behind the scenes', 'behind-the-scenes', 'making of', 'bonus']
        
        # 计算每个结果的匹配度分数
        scored_results = []
        for result in results:
            result_title = result.title or ''
            score = calculate_title_match_score(search_title, result_title, exclude_keywords)
            scored_results.append((score, result))
            self.logger.debug(f"匹配分数: {score:.2f} - {result_title}")
        
        # 按分数降序排序
        scored_results.sort(key=lambda x: x[0], reverse=True)
        
        # 获取最高分
        best_score, best_result = scored_results[0]
        
        # 如果最高分太低（< 50），返回 None
        # 但如果只是因为包含排除关键词导致分数低，仍然返回（分数 >= 10）
        if best_score < 10:
            self.logger.warning(f"最佳匹配分数太低: {best_score:.2f}，返回 None")
            return None
        
        self.logger.info(f"选择最佳匹配: {best_result.title} (分数: {best_score:.2f})")
        return best_result
    
    def deduplicate_results(
        self,
        results: List[ScrapeResult],
        by: str = 'code'
    ) -> List[ScrapeResult]:
        """
        去重结果
        
        Args:
            results: 结果列表
            by: 去重依据（code/title/url）
        
        Returns:
            去重后的结果列表
        """
        if not results:
            return results
        
        seen = set()
        unique_results = []
        
        for result in results:
            if by == 'code':
                key = result.code
            elif by == 'title':
                key = result.title
            elif by == 'url':
                key = result.preview_video_urls[0] if result.preview_video_urls else None
            else:
                key = result.code
            
            if key and key not in seen:
                seen.add(key)
                unique_results.append(result)
        
        removed_count = len(results) - len(unique_results)
        if removed_count > 0:
            self.logger.info(f"去重: 移除 {removed_count} 个重复结果")
        
        return unique_results
    
    def paginate_results(
        self,
        results: List[ScrapeResult],
        page: int = 1,
        page_size: int = 20
    ) -> tuple[List[ScrapeResult], Dict[str, Any]]:
        """
        分页结果
        
        Args:
            results: 结果列表
            page: 页码（从 1 开始）
            page_size: 每页大小
        
        Returns:
            (当前页结果, 分页信息)
        """
        total_count = len(results)
        total_pages = (total_count + page_size - 1) // page_size
        
        # 边界检查
        if page < 1:
            page = 1
        if page > total_pages and total_pages > 0:
            page = total_pages
        
        # 计算起始和结束索引
        start_idx = (page - 1) * page_size
        end_idx = start_idx + page_size
        
        page_results = results[start_idx:end_idx]
        
        pagination_info = {
            'page': page,
            'page_size': page_size,
            'total_count': total_count,
            'total_pages': total_pages,
            'has_prev': page > 1,
            'has_next': page < total_pages
        }
        
        self.logger.info(f"分页: 第 {page}/{total_pages} 页，共 {total_count} 个结果")
        
        return page_results, pagination_info

    def process_results_with_matching(
        self,
        results: List[ScrapeResult],
        search_query: str,
        is_date_query: bool = False
    ) -> List[ScrapeResult]:
        """
        处理搜索结果，根据查询类型进行智能匹配
        
        Args:
            results: 搜索结果列表
            search_query: 搜索查询（标题或日期）
            is_date_query: 是否是日期查询
        
        Returns:
            处理后的结果列表
        
        逻辑：
        1. 只有 1 个结果 → 直接返回
        2. 日期查询 → 返回所有相同日期的结果
        3. 标题查询 → 精准匹配
           - 有多个相同标题 → 返回所有相同标题的
           - 只有 1 个匹配 → 返回最佳匹配
           - 匹配失败 → 返回所有结果
        """
        # 1. 只有 1 个结果，直接返回
        if len(results) == 1:
            self.logger.info(f"只有 1 个结果，直接返回")
            return results
        
        # 2. 日期查询：返回所有结果（已经按日期过滤）
        if is_date_query:
            self.logger.info(f"日期查询，返回所有 {len(results)} 个相同日期的结果")
            return results
        
        # 3. 标题查询：尝试精准匹配
        best_match = self.select_best_match(results, search_query)
        if best_match:
            # 检查是否有多个结果的标题完全相同
            best_title = best_match.title
            same_title_results = [r for r in results if r.title == best_title]
            
            if len(same_title_results) > 1:
                self.logger.info(f"找到 {len(same_title_results)} 个相同标题的结果，返回所有")
                return same_title_results
            else:
                self.logger.info(f"精准匹配成功，返回最佳匹配")
                return [best_match]
        else:
            self.logger.info(f"精准匹配失败，返回所有 {len(results)} 个结果供用户选择")
            return results
