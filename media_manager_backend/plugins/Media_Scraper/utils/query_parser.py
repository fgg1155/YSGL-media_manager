#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
query_parser.py

查询字符串解析工具模块
用于解析 "系列-标题" 或 "系列.标题" 格式的查询字符串
支持多种刮削器使用
"""

import re
from typing import Optional, Tuple, Dict, Any, Callable


def extract_series_and_title(
    query: str,
    site_finder: Optional[Callable[[str], Optional[Dict[str, Any]]]] = None
) -> Tuple[Optional[str], str]:
    """
    从输入中提取系列名和标题
    
    支持格式：
    - Series-Scene Title (连字符分隔)
    - Series.Scene.Title (点号分隔)
    - Series Name-Scene Title (系列名包含空格)
    
    Args:
        query: 输入字符串
        site_finder: 可选的站点查找函数，用于验证系列名是否有效
                    函数签名: (series_name: str) -> Optional[Dict[str, Any]]
                    返回站点配置字典或 None
    
    Returns:
        (series_name, search_title) 元组
        - series_name: 系列名（如果有），否则为 None
        - search_title: 搜索标题（移除了系列名前缀）
    
    Examples:
        >>> extract_series_and_title("EvilAngel-Nympho Wars")
        ('EvilAngel', 'Nympho Wars')
        
        >>> extract_series_and_title("EvilAngel.Nympho.Wars")
        ('EvilAngel', 'Nympho Wars')
        
        >>> extract_series_and_title("Nympho Wars")
        (None, 'Nympho Wars')
        
        >>> # 使用站点查找函数验证
        >>> def finder(name):
        ...     return {'name': 'Evil Angel'} if name.lower() == 'evilangel' else None
        >>> extract_series_and_title("EvilAngel-Nympho Wars", site_finder=finder)
        ('EvilAngel', 'Nympho Wars')
    """
    # 移除文件扩展名
    query_clean = re.sub(r'\.(mp4|mkv|avi|wmv|mov|flv|webm)$', '', query, flags=re.I)
    
    # 查找第一个连字符或点号的位置
    separators = ['-', '.']
    first_sep_pos = -1
    first_sep = None
    
    for sep in separators:
        pos = query_clean.find(sep)
        if pos > 0:  # 必须在字符串中间，不能在开头
            if first_sep_pos == -1 or pos < first_sep_pos:
                first_sep_pos = pos
                first_sep = sep
    
    if first_sep_pos > 0:
        potential_series = query_clean[:first_sep_pos].strip()
        title_part = query_clean[first_sep_pos + 1:].strip()
        
        # 系列名必须以大写字母开头
        if potential_series and potential_series[0].isupper():
            # 如果提供了站点查找函数，验证系列名
            if site_finder:
                site_info = site_finder(potential_series)
                if site_info:
                    # 标题保持原样，只处理开头的分隔符
                    # 如果是点号分隔，需要将点号替换为空格
                    if first_sep == '.':
                        search_title = title_part.replace('.', ' ')
                    else:
                        search_title = title_part
                    
                    search_title = search_title.lstrip('.-_ ')
                    return (potential_series, search_title)
            else:
                # 没有提供站点查找函数，直接返回提取的结果
                if first_sep == '.':
                    search_title = title_part.replace('.', ' ')
                else:
                    search_title = title_part
                
                search_title = search_title.lstrip('.-_ ')
                return (potential_series, search_title)
    
    # 无法提取系列名，返回原始 query
    return (None, query)


def normalize_series_name(series_name: str) -> str:
    """
    规范化系列名（用于比较）
    
    规范化处理：
    - 只保留字母和数字，移除所有其他字符（空格、撇号、连字符等）
    - 转小写
    
    Args:
        series_name: 系列名
    
    Returns:
        规范化后的系列名
    
    Examples:
        >>> normalize_series_name("Evil Angel")
        'evilangel'
        
        >>> normalize_series_name("Brazzers")
        'brazzers'
        
        >>> normalize_series_name("21 Sextury")
        '21sextury'
    """
    return re.sub(r'[^a-zA-Z0-9]', '', series_name).lower()


def is_series_match(series_name1: str, series_name2: str) -> bool:
    """
    检查两个系列名是否匹配
    
    使用规范化比较，忽略大小写、空格、特殊字符等
    
    Args:
        series_name1: 第一个系列名
        series_name2: 第二个系列名
    
    Returns:
        True 如果匹配，否则 False
    
    Examples:
        >>> is_series_match("EvilAngel", "Evil Angel")
        True
        
        >>> is_series_match("Brazzers", "brazzers")
        True
        
        >>> is_series_match("EvilAngel", "Brazzers")
        False
    """
    normalized1 = normalize_series_name(series_name1)
    normalized2 = normalize_series_name(series_name2)
    
    return (normalized1 == normalized2 or
            normalized1 in normalized2 or
            normalized2 in normalized1)


def clean_title(title: str) -> str:
    """
    清理标题：移除特殊符号，只保留字母、数字和空格
    
    Args:
        title: 原始标题
    
    Returns:
        清理后的标题
    
    Examples:
        >>> clean_title("You Bet Your Ass! Best Of Anal Vol. 2")
        'You Bet Your Ass Best Of Anal Vol 2'
        
        >>> clean_title("Scene #1: The Beginning")
        'Scene 1 The Beginning'
    """
    # 移除非字母数字和空格的字符
    cleaned = re.sub(r'[^\w\s]', ' ', title)
    # 合并多个空格为一个
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned


def parse_query(
    query: str,
    site_finder: Optional[Callable[[str], Optional[Dict[str, Any]]]] = None,
    clean_title_flag: bool = False
) -> Tuple[Optional[str], str]:
    """
    解析查询字符串（综合方法）
    
    结合系列名提取和标题清理
    
    Args:
        query: 查询字符串
        site_finder: 可选的站点查找函数
        clean_title_flag: 是否清理标题中的特殊字符
    
    Returns:
        (series_name, search_title) 元组
    
    Examples:
        >>> parse_query("EvilAngel-Nympho Wars!")
        ('EvilAngel', 'Nympho Wars!')
        
        >>> parse_query("EvilAngel-Nympho Wars!", clean_title_flag=True)
        ('EvilAngel', 'Nympho Wars')
    """
    series_name, search_title = extract_series_and_title(query, site_finder)
    
    if clean_title_flag:
        search_title = clean_title(search_title)
    
    return (series_name, search_title)


def calculate_title_match_score(search_title: str, hit_title: str, 
                                exclude_keywords: Optional[list] = None) -> float:
    """
    计算标题匹配度分数
    
    Args:
        search_title: 搜索的标题
        hit_title: 搜索结果的标题
        exclude_keywords: 排除关键词列表（如 BTS、花絮等），包含这些关键词的结果会降低分数
    
    Returns:
        匹配度分数 (0-100)，分数越高越匹配
    
    Examples:
        >>> calculate_title_match_score("Nympho Wars", "Nympho Wars")
        100.0
        
        >>> calculate_title_match_score("Nympho Wars", "BTS - Nympho Wars")
        42.35...
        
        >>> calculate_title_match_score("Scene Title", "Scene Title Extended")
        85.0...
    """
    # 默认排除关键词（BTS、花絮等）
    if exclude_keywords is None:
        exclude_keywords = ['bts', 'behind the scenes', 'behind-the-scenes', 'making of', 'bonus']
    
    # 规范化标题（转小写，移除多余空格）
    search_normalized = search_title.lower().strip()
    hit_normalized = hit_title.lower().strip()
    
    # 1. 完全匹配 -> 100分
    if search_normalized == hit_normalized:
        return 100.0
    
    # 2. 检查是否包含排除关键词 -> 大幅降低分数
    has_exclude_keyword = any(keyword in hit_normalized for keyword in exclude_keywords)
    if has_exclude_keyword:
        # 包含排除关键词的版本基础分数很低
        base_score = 10.0
    else:
        base_score = 50.0
    
    # 3. 计算相似度
    # 使用简单的字符串包含关系
    if search_normalized in hit_normalized:
        # 搜索词是结果的子串
        length_ratio = len(search_normalized) / len(hit_normalized)
        similarity_score = base_score + (50.0 * length_ratio)
    elif hit_normalized in search_normalized:
        # 结果是搜索词的子串
        length_ratio = len(hit_normalized) / len(search_normalized)
        similarity_score = base_score + (30.0 * length_ratio)
    else:
        # 计算共同单词数
        search_words = set(search_normalized.split())
        hit_words = set(hit_normalized.split())
        common_words = search_words & hit_words
        if common_words:
            word_match_ratio = len(common_words) / max(len(search_words), len(hit_words))
            similarity_score = base_score + (40.0 * word_match_ratio)
        else:
            similarity_score = 0.0
    
    return similarity_score


def select_best_match(hits: list, search_title: str, 
                      title_field: str = 'title',
                      exclude_keywords: Optional[list] = None) -> Optional[Dict[str, Any]]:
    """
    从搜索结果中选择最佳匹配
    
    Args:
        hits: 搜索结果列表（字典列表）
        search_title: 搜索的标题
        title_field: 标题字段名（默认为 'title'）
        exclude_keywords: 排除关键词列表（如 BTS、花絮等）
    
    Returns:
        最佳匹配的结果，如果没有结果则返回 None
    
    Examples:
        >>> hits = [
        ...     {'title': 'Nympho Wars'},
        ...     {'title': 'BTS - Nympho Wars'},
        ... ]
        >>> best = select_best_match(hits, 'Nympho Wars')
        >>> best['title']
        'Nympho Wars'
    """
    if not hits:
        return None
    
    if len(hits) == 1:
        return hits[0]
    
    # 计算每个结果的匹配度分数
    scored_hits = []
    for hit in hits:
        hit_title = hit.get(title_field, '')
        score = calculate_title_match_score(search_title, hit_title, exclude_keywords)
        scored_hits.append((score, hit))
    
    # 按分数降序排序
    scored_hits.sort(key=lambda x: x[0], reverse=True)
    
    # 返回分数最高的结果
    best_score, best_hit = scored_hits[0]
    
    return best_hit



def generate_series_date_query(series: str, release_date: str) -> Optional[str]:
    """
    生成系列+日期格式的查询字符串
    
    格式：系列.YY.MM.DD
    例如：Evilangel.26.01.23
    
    Args:
        series: 系列名（如 "Evil Angel"）
        release_date: 发布日期（ISO 格式，如 "2026-01-23"）
    
    Returns:
        格式化的查询字符串，如果无法生成则返回 None
    
    Examples:
        >>> generate_series_date_query("Evil Angel", "2026-01-23")
        'Evilangel.26.01.23'
        
        >>> generate_series_date_query("Brazzers Exxtra", "2025-12-15")
        'BrazzersExxtra.25.12.15'
    """
    from datetime import datetime
    
    if not series or not release_date:
        return None
    
    try:
        # 解析日期
        date = datetime.fromisoformat(release_date.replace('Z', '+00:00'))
        
        # 格式化日期：YY.MM.DD
        year = str(date.year)[2:]  # 取后两位
        month = str(date.month).zfill(2)
        day = str(date.day).zfill(2)
        
        # 处理系列名：去除空格，保持每个单词首字母大写
        series_formatted = ''.join(
            word.capitalize() for word in series.split() if word
        )
        
        return f"{series_formatted}.{year}.{month}.{day}"
    
    except (ValueError, AttributeError) as e:
        return None


def generate_series_title_query(series: str, title: str) -> Optional[str]:
    """
    生成系列+标题格式的查询字符串
    
    格式：系列-标题
    例如：Brazzers-You Bet Your Ass! Vol. 2
    
    Args:
        series: 系列名（如 "Brazzers Exxtra"）
        title: 标题（如 "You Bet Your Ass! Vol. 2"）
    
    Returns:
        格式化的查询字符串，如果无法生成则返回 None
    
    Examples:
        >>> generate_series_title_query("Brazzers Exxtra", "You Bet Your Ass! Vol. 2")
        'BrazzersExxtra-You Bet Your Ass! Vol. 2'
        
        >>> generate_series_title_query("Evil Angel", "Nympho Wars")
        'Evilangel-Nympho Wars'
    """
    if not series or not title:
        return None
    
    # 处理系列名：去除空格，保持每个单词首字母大写
    series_formatted = ''.join(
        word.capitalize() for word in series.split() if word
    )
    
    # 标题保持原样
    return f"{series_formatted}-{title}"
