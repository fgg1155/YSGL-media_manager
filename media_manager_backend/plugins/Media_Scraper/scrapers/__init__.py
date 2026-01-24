"""刮削器模块"""

from .base_scraper import BaseScraper

# JAV 刮削器
from .jav import (
    FanzaScraper,
    JavBusScraper,
    JAVDBScraper,
    JAVLibraryScraper,
)

# Western 刮削器
from .western import (
    # AdultEmpireScraper,  # 暂时禁用
    # IAFDScraper,  # 暂时禁用
    ThePornDBScraper,
    MariskaXScraper,
    StraplezScraper,
    AdultPrimeScraper,
    MindGeekScraper,
    BrazzersScraper,
    RealityKingsScraper,
    BangBrosScraper,
    DigitalPlaygroundScraper,
    MofosScraper,
    TwistysScraper,
    SexyHubScraper,
    FakeHubScraper,
    MileHighScraper,
    BabesScraper,
    TransAngelsScraper,
    LetsDoeItScraper,
)

__all__ = [
    'BaseScraper',
    # JAV
    'FanzaScraper',
    'JavBusScraper',
    'JAVDBScraper',
    'JAVLibraryScraper',
    # Western
    # 'AdultEmpireScraper',  # 暂时禁用
    # 'IAFDScraper',  # 暂时禁用
    'ThePornDBScraper',
    'MariskaXScraper',
    'StraplezScraper',
    'AdultPrimeScraper',
    'MindGeekScraper',
    'BrazzersScraper',
    'RealityKingsScraper',
    'BangBrosScraper',
    'DigitalPlaygroundScraper',
    'MofosScraper',
    'TwistysScraper',
    'SexyHubScraper',
    'FakeHubScraper',
    'MileHighScraper',
    'BabesScraper',
    'TransAngelsScraper',
    'LetsDoeItScraper',
]
