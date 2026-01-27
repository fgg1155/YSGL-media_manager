"""
JAV (Japanese Adult Video) 刮削器模块
"""

from .avsox_scraper import AvsoxScraper
from .fanza_scraper import FanzaScraper
from .javbus_scraper import JavBusScraper
from .javdb_scraper import JAVDBScraper
from .javlibrary_scraper import JAVLibraryScraper
from .ippondo_network_scraper import (
    OnePondoScraper,
    PacopacomamaScraper,
    TenMusumeScraper,
)
from .caribbeancom_scraper import (
    CaribbeancomScraper,
    CaribbeancomPRScraper,
)
from .heyzo_scraper import HeyzoScraper
from .tokyohot_scraper import TokyoHotScraper

__all__ = [
    'AvsoxScraper',
    'FanzaScraper',
    'JavBusScraper',
    'JAVDBScraper',
    'JAVLibraryScraper',
    'PacopacomamaScraper',
    'HeyzoScraper',
    'TokyoHotScraper',
]
