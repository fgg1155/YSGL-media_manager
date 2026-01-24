"""Media Scraper Plugin - 通用媒体元数据刮削插件"""

__version__ = "1.0.0"
__author__ = "Media Manager"
__description__ = "通用媒体元数据刮削插件，支持日本AV和欧美内容"

# 导出主要的类和函数
from .core import CodeNormalizer, ContentTypeDetector, load_config
from .managers import JAVScraperManager, WesternScraperManager
from .scrapers import BaseScraper
from .web import Request

__all__ = [
    # 核心模块
    'CodeNormalizer',
    'ContentTypeDetector',
    'load_config',
    # 管理器
    'JAVScraperManager',
    'WesternScraperManager',
    # 刮削器
    'BaseScraper',
    # HTTP 客户端
    'Request',
]
