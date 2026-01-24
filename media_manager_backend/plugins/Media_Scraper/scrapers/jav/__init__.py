"""
JAV (Japanese Adult Video) 刮削器模块
"""

from .avsox_scraper import AvsoxScraper
from .fanza_scraper import FanzaScraper
from .javbus_scraper import JavBusScraper
from .javdb_scraper import JAVDBScraper
from .javlibrary_scraper import JAVLibraryScraper

__all__ = [
    'AvsoxScraper',
    'FanzaScraper',
    'JavBusScraper',
    'JAVDBScraper',
    'JAVLibraryScraper',
]
