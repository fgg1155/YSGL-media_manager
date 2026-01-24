#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
content_type_filter.py

内容类型过滤工具模块
用于判断和过滤媒体内容类型（Scene/Movie/Compilation）
"""

from typing import List, Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)


def detect_content_type(hit: Dict[str, Any], search_title: Optional[str] = None, 
                       content_type_hint: Optional[str] = None) -> str:
    """
    检测搜索结果的内容类型
    
    Args:
        hit: 搜索结果字典
        search_title: 搜索标题（可选，用于判断是否搜索的是 movie_title）
        content_type_hint: 内容类型提示（可选，用于辅助判断）
    
    Returns:
        内容类型：'scene', 'movie', 或 'compilation'
    
    判断逻辑：
    ⚠️ 重要：Algolia 返回的所有数据都是 clip（场景）级别的
    
    1. Compilation: compilation 字段为 True 或 1
    2. Scene: 所有其他情况（包括 title == movie_title 的情况）
       - 因为 Algolia 返回的都是 clip，即使 title == movie_title 也是场景
    
    注意：不再区分 Movie 类型，因为所有数据本质上都是 Scene
    
    Examples:
        >>> hit = {'title': 'Scene 1', 'movie_title': 'Movie A', 'compilation': ''}
        >>> detect_content_type(hit)
        'scene'
        
        >>> hit = {'title': 'Movie A', 'movie_title': 'Movie A', 'compilation': ''}
        >>> detect_content_type(hit)
        'scene'  # 注意：这也是 scene，因为 Algolia 返回的都是 clip
        
        >>> hit = {'title': 'Best Of', 'compilation': '1'}
        >>> detect_content_type(hit)
        'compilation'
    """
    # 提取字段
    compilation = hit.get('compilation', '')
    
    # 判断逻辑
    # 1. Compilation: compilation 字段为 True 或 1
    if compilation and compilation not in ['', '0', 0, False]:
        return 'compilation'
    
    # 2. 所有其他情况都是 Scene（因为 Algolia 返回的都是 clip）
    return 'scene'


def filter_by_content_type(hits: List[Dict[str, Any]], content_type: str, 
                           search_title: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    按内容类型过滤搜索结果
    
    Args:
        hits: 搜索结果列表
        content_type: 目标内容类型（'scene', 'movie', 'compilation'）
        search_title: 搜索标题（可选，用于辅助判断）
    
    Returns:
        过滤后的结果列表
    
    Examples:
        >>> hits = [
        ...     {'title': 'Scene 1', 'movie_title': 'Movie A'},
        ...     {'title': 'Movie A', 'movie_title': 'Movie A'},
        ... ]
        >>> filter_by_content_type(hits, 'movie')
        [{'title': 'Movie A', 'movie_title': 'Movie A'}]
    """
    if not hits:
        return []
    
    # 规范化目标类型
    content_type_normalized = content_type.lower()
    
    filtered = []
    for hit in hits:
        hit_type = detect_content_type(hit, search_title, content_type)
        if hit_type == content_type_normalized:
            filtered.append(hit)
    
    return filtered


def get_content_type_stats(hits: List[Dict[str, Any]], search_title: Optional[str] = None) -> Dict[str, int]:
    """
    统计搜索结果中各类型的数量
    
    Args:
        hits: 搜索结果列表
        search_title: 搜索标题（可选）
    
    Returns:
        类型统计字典，格式：{'scene': 10, 'movie': 2, 'compilation': 1}
    
    Examples:
        >>> hits = [
        ...     {'title': 'Scene 1', 'movie_title': 'Movie A'},
        ...     {'title': 'Scene 2', 'movie_title': 'Movie A'},
        ...     {'title': 'Movie A', 'movie_title': 'Movie A'},
        ... ]
        >>> get_content_type_stats(hits)
        {'scene': 2, 'movie': 1, 'compilation': 0}
    """
    stats = {'scene': 0, 'movie': 0, 'compilation': 0}
    
    for hit in hits:
        hit_type = detect_content_type(hit, search_title)
        stats[hit_type] = stats.get(hit_type, 0) + 1
    
    return stats


def log_content_type_debug(hits: List[Dict[str, Any]], search_title: Optional[str] = None, 
                           max_items: int = 3) -> None:
    """
    输出内容类型调试信息（用于日志）
    
    Args:
        hits: 搜索结果列表
        search_title: 搜索标题（可选）
        max_items: 最多输出的条目数
    
    Examples:
        >>> hits = [{'title': 'Scene 1', 'movie_title': 'Movie A'}]
        >>> log_content_type_debug(hits, 'Scene 1')
        # 输出日志：结果 1: 类型=scene, title=Scene 1, movie_title=Movie A
    """
    for i, hit in enumerate(hits[:max_items], 1):
        hit_type = detect_content_type(hit, search_title)
        title = hit.get('title', '')
        movie_title = hit.get('movie_title', '')
        compilation = hit.get('compilation', '')
        
        logger.warning(
            f"  结果 {i}: 类型={hit_type}, "
            f"title={title}, "
            f"movie_title={movie_title}, "
            f"compilation={compilation}, "
            f"搜索={search_title or 'N/A'}"
        )
