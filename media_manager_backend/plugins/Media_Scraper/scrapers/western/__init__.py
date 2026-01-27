"""
欧美内容刮削器模块
"""

# from .adultempire_scraper import AdultEmpireScraper  # 暂时禁用
# from .iafd_scraper import IAFDScraper  # 暂时禁用
from .theporndb_scraper import ThePornDBScraper
from .MariskaX_Scraper import MariskaXScraper
# Straplez 已移至 MetArt Network 刮削器
from .AdultPrime_Scraper import AdultPrimeScraper
from .MindGeek_Network_Scraper import (
    MindGeekScraper, BrazzersScraper, RealityKingsScraper, BangBrosScraper,
    DigitalPlaygroundScraper, MofosScraper, TwistysScraper, SexyHubScraper,
    FakeHubScraper, MileHighScraper, BabesScraper, TransAngelsScraper, LetsDoeItScraper
)
from .ScoreGroup_Scraper import ScoreGroupScraper

__all__ = [
    # 'AdultEmpireScraper', 'IAFDScraper',  # 暂时禁用
    'ThePornDBScraper', 'MariskaXScraper', 'AdultPrimeScraper',
    'MindGeekScraper', 'BrazzersScraper', 'RealityKingsScraper', 'BangBrosScraper',
    'DigitalPlaygroundScraper', 'MofosScraper', 'TwistysScraper', 'SexyHubScraper',
    'FakeHubScraper', 'MileHighScraper', 'BabesScraper', 'TransAngelsScraper', 'LetsDoeItScraper',
    'ScoreGroupScraper'
]
