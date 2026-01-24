#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
date_parser.py

日期解析工具模块
用于解析各种日期格式的查询字符串，支持多种刮削器使用
"""

import re
from datetime import datetime
from typing import Optional, Tuple, List, Dict, Any


def parse_date_query(query: str) -> Tuple[Optional[str], Optional[datetime]]:
    """
    解析日期格式的查询
    
    支持格式:
    - series.YY.MM.DD (系列.YY.MM.DD) 例如: evilangel.26.01.17
    - YY.MM.DD (YY.MM.DD) 例如: 26.01.17
    - YYYY-MM-DD (YYYY-MM-DD) 例如: 2026-01-17
    - MM/DD/YYYY (MM/DD/YYYY) 例如: 01/17/2026
    - YYYY/MM/DD (YYYY/MM/DD) 例如: 2026/01/17
    - MMM DD, YYYY (MMM DD, YYYY) 例如: Jan 20, 2026
    
    Args:
        query: 输入字符串
    
    Returns:
        (series_name, target_date) 元组
        - series_name: 系列名（如果有），否则为 None
        - target_date: 解析出的日期对象，如果无法解析则为 None
    
    Examples:
        >>> parse_date_query("evilangel.26.01.17")
        ('evilangel', datetime(2026, 1, 17))
        
        >>> parse_date_query("26.01.17")
        (None, datetime(2026, 1, 17))
        
        >>> parse_date_query("2026-01-17")
        (None, datetime(2026, 1, 17))
    """
    # 格式 1: 系列.YY.MM.DD
    match = re.match(r'^([a-zA-Z]+)\.(\d{2})\.(\d{2})\.(\d{2})$', query)
    if match:
        series_name = match.group(1)
        yy = int(match.group(2))
        mm = int(match.group(3))
        dd = int(match.group(4))
        # 假设 20xx 年
        yyyy = 2000 + yy
        try:
            target_date = datetime(yyyy, mm, dd)
            return (series_name, target_date)
        except ValueError:
            pass
    
    # 格式 2: YY.MM.DD
    match = re.match(r'^(\d{2})\.(\d{2})\.(\d{2})$', query)
    if match:
        yy = int(match.group(1))
        mm = int(match.group(2))
        dd = int(match.group(3))
        yyyy = 2000 + yy
        try:
            target_date = datetime(yyyy, mm, dd)
            return (None, target_date)
        except ValueError:
            pass
    
    # 格式 3: YYYY-MM-DD
    match = re.match(r'^(\d{4})-(\d{2})-(\d{2})$', query)
    if match:
        yyyy = int(match.group(1))
        mm = int(match.group(2))
        dd = int(match.group(3))
        try:
            target_date = datetime(yyyy, mm, dd)
            return (None, target_date)
        except ValueError:
            pass
    
    # 格式 4: MM/DD/YYYY
    match = re.match(r'^(\d{2})/(\d{2})/(\d{4})$', query)
    if match:
        mm = int(match.group(1))
        dd = int(match.group(2))
        yyyy = int(match.group(3))
        try:
            target_date = datetime(yyyy, mm, dd)
            return (None, target_date)
        except ValueError:
            pass
    
    # 格式 5: YYYY/MM/DD
    match = re.match(r'^(\d{4})/(\d{2})/(\d{2})$', query)
    if match:
        yyyy = int(match.group(1))
        mm = int(match.group(2))
        dd = int(match.group(3))
        try:
            target_date = datetime(yyyy, mm, dd)
            return (None, target_date)
        except ValueError:
            pass
    
    # 格式 6: MMM DD, YYYY (例如: Jan 20, 2026)
    try:
        target_date = datetime.strptime(query, '%b %d, %Y')
        return (None, target_date)
    except ValueError:
        pass
    
    # 格式 7: MMMM DD, YYYY (例如: January 20, 2026)
    try:
        target_date = datetime.strptime(query, '%B %d, %Y')
        return (None, target_date)
    except ValueError:
        pass
    
    return (None, None)


def filter_by_date(hits: List[Dict[str, Any]], target_date: datetime, 
                   date_field: str = 'release_date') -> List[Dict[str, Any]]:
    """
    按日期过滤搜索结果
    
    Args:
        hits: 搜索结果列表（字典列表）
        target_date: 目标日期 (datetime 对象)
        date_field: 日期字段名（默认为 'release_date'）
    
    Returns:
        匹配的结果列表
    
    Examples:
        >>> hits = [
        ...     {'title': 'Video 1', 'release_date': '2026-01-17'},
        ...     {'title': 'Video 2', 'release_date': '2026-01-18'},
        ... ]
        >>> target = datetime(2026, 1, 17)
        >>> filter_by_date(hits, target)
        [{'title': 'Video 1', 'release_date': '2026-01-17'}]
    """
    matched = []
    target_date_str = target_date.strftime('%Y-%m-%d')
    
    for hit in hits:
        release_date = hit.get(date_field, '')
        if not release_date:
            continue
        
        # 解析发布日期
        try:
            if isinstance(release_date, str):
                # 尝试解析 ISO 格式
                if 'T' in release_date:
                    dt = datetime.fromisoformat(release_date.replace('Z', '+00:00'))
                else:
                    dt = datetime.strptime(release_date, '%Y-%m-%d')
                
                # 比较日期（忽略时间）
                if dt.strftime('%Y-%m-%d') == target_date_str:
                    matched.append(hit)
            elif isinstance(release_date, datetime):
                # 如果已经是 datetime 对象
                if release_date.strftime('%Y-%m-%d') == target_date_str:
                    matched.append(hit)
        except Exception:
            # 忽略解析失败的条目
            continue
    
    return matched


def is_date_query(query: str) -> bool:
    """
    检查查询字符串是否是日期格式
    
    Args:
        query: 查询字符串
    
    Returns:
        True 如果是日期格式，否则 False
    
    Examples:
        >>> is_date_query("2026-01-17")
        True
        
        >>> is_date_query("evilangel.26.01.17")
        True
        
        >>> is_date_query("Nympho Wars")
        False
    """
    series_name, target_date = parse_date_query(query)
    return target_date is not None


def format_date_query(series: Optional[str], date: datetime) -> str:
    """
    格式化系列名和日期为标准查询字符串
    
    Args:
        series: 系列名（可选）
        date: 日期对象
    
    Returns:
        格式化后的查询字符串
        - 如果有系列名: "series.YY.MM.DD" (例如: "evilangel.26.01.17")
        - 如果没有系列名: "YYYY-MM-DD" (例如: "2026-01-17")
    
    Examples:
        >>> from datetime import datetime
        >>> format_date_query("EvilAngel", datetime(2026, 1, 17))
        'evilangel.26.01.17'
        
        >>> format_date_query("Evil Angel", datetime(2026, 1, 17))
        'evilangel.26.01.17'
        
        >>> format_date_query(None, datetime(2026, 1, 17))
        '2026-01-17'
    """
    if series:
        # 规范化系列名：移除空格和特殊字符，转小写
        import re
        normalized_series = re.sub(r'[^a-zA-Z0-9]', '', series).lower()
        
        # 格式化为 series.YY.MM.DD
        yy = date.strftime('%y')  # 两位年份
        mm = date.strftime('%m')  # 两位月份
        dd = date.strftime('%d')  # 两位日期
        
        return f"{normalized_series}.{yy}.{mm}.{dd}"
    else:
        # 格式化为 YYYY-MM-DD (ISO 标准格式)
        return date.strftime('%Y-%m-%d')
