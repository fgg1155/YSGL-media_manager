"""
内容类型检测器
检测输入是日本 AV 番号还是欧美内容标题
"""

import re
from enum import Enum
from typing import Optional
from dataclasses import dataclass


class ContentType(Enum):
    """内容类型"""
    JAV = "jav"          # 日本 AV
    WESTERN = "western"  # 欧美成人内容


class ContentTypeDetector:
    """内容类型检测器"""
    
    # 番号格式正则表达式（参考 JavSP 的 avid.py）
    JAV_PATTERNS = [
        # 普通番号: PREFIX-NUMBER 或 PREFIXNUMBER
        r'^[A-Z]{2,6}-?\d{3,5}$',
        
        # 老番号格式：数字开头+字母+数字（如 83sma132）
        r'^\d{2}[A-Z]{2,10}\d{2,5}$',
        
        # FC2 系列
        r'^FC2[^A-Z\d]{0,5}(PPV[^A-Z\d]{0,5})?\d{5,7}$',
        
        # HEYZO 系列
        r'^HEYZO[-_]?\d{4}$',
        
        # HEYDOUGA 系列
        r'^(HEYDOUGA|HEY)[-_]?\d{4}[-_]0?\d{3,5}$',
        
        # 东热系列
        r'^(RED|SKY|EX)-?\d{3,4}$',
        r'^[NK]\d{4}$',
        
        # 纯数字番号（无码）
        r'^\d{6}-\d{3}$',
        
        # CID 格式（小写字母+数字，可能包含下划线）
        r'^[a-z\d_]+\d{5}$',
        
        # 特殊厂商
        r'^(GETCHU|GYUTTO)[-_]?\d{5}$',
        r'^259LUXU[-_]?\d{4}$',
        r'^T(28|38)[-_]?\d{3}$',
        r'^IBW[-_]?\d{3}z$',
        r'^(MKD-S|MK3D2DBD)[-_]?\d{3}$',
    ]
    
    @staticmethod
    def detect(query: str) -> ContentType:
        """
        检测内容类型
        
        Args:
            query: 用户输入（番号或标题）
        
        Returns:
            ContentType: JAV 或 WESTERN
        """
        if not query:
            return ContentType.WESTERN
        
        # 清理输入
        query = query.strip()
        
        # 尝试匹配番号格式
        query_upper = query.upper()
        for pattern in ContentTypeDetector.JAV_PATTERNS:
            if re.match(pattern, query_upper, re.IGNORECASE):
                return ContentType.JAV
        
        # 如果不匹配任何番号格式，视为欧美内容标题
        return ContentType.WESTERN
    
    @staticmethod
    def is_jav_code(query: str) -> bool:
        """
        判断是否为日本 AV 番号
        
        Args:
            query: 用户输入
        
        Returns:
            bool: 是否为番号
        """
        return ContentTypeDetector.detect(query) == ContentType.JAV
