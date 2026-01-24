"""
基础刮削器类
所有刮削器的基类
增强：集成 ErrorHandler 进行统一错误处理
"""

import logging
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from managers.jav_scraper_manager import ScrapeResult
from web.request import Request
from core.error_handler import ErrorHandler


logger = logging.getLogger(__name__)


class BaseScraper(ABC):
    """刮削器基类（带统一错误处理）"""
    
    # 数据源名称（子类必须设置）
    name: str = 'base'
    
    # 基础 URL（子类必须设置）
    base_url: str = ''
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = False):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
            use_scraper: 是否使用 cloudscraper
        """
        self.config = config
        self.request = Request(config, use_scraper=use_scraper)
        self.logger = logging.getLogger(f"{__name__}.{self.name}")
        # 初始化错误处理器
        self.error_handler = ErrorHandler(config, self.logger)
    
    def scrape(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削指定番号/标题（带统一错误处理）
        
        Args:
            code: 番号或标题
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        try:
            return self._scrape_impl(code)
        except Exception as e:
            # 使用 ErrorHandler 处理异常
            error = self.error_handler.handle_exception(e, self.name, code)
            # 记录结构化错误（已在 ErrorHandler 中记录）
            # 返回 None 表示刮削失败
            return None
    
    @abstractmethod
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由子类覆盖）
        
        Args:
            code: 番号或标题
        
        Returns:
            ScrapeResult 对象，失败返回 None
        
        注意：
            - 子类应该实现这个方法而不是 scrape()
            - 异常会被 scrape() 方法捕获并处理
            - 可以直接抛出异常，不需要捕获
        """
        pass
    
    def _create_result(self) -> ScrapeResult:
        """创建一个空的 ScrapeResult 对象"""
        return ScrapeResult()
