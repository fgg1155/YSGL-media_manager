"""
演员刮削器基类
"""

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional, List


@dataclass
class ActorMetadata:
    """演员元数据"""
    name: str
    biography: Optional[str] = None
    birth_date: Optional[str] = None
    nationality: Optional[str] = None
    height: Optional[str] = None
    measurements: Optional[str] = None  # 三围
    cup_size: Optional[str] = None      # 罩杯
    source: Optional[str] = None


@dataclass
class ActorPhotos:
    """演员照片"""
    name: str
    avatar_url: Optional[str] = None          # 头像（圆形小图）
    poster_url: Optional[str] = None          # 封面（竖版海报）
    photo_urls: Optional[List[str]] = field(default_factory=list)  # 写真（多图）
    backdrop_url: Optional[str] = None        # 背景（横版大图）
    source: Optional[str] = None


class BaseActorScraper(ABC):
    """演员刮削器基类"""
    
    # 数据源名称（子类必须设置）
    name: str = 'base'
    
    def __init__(self, config):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.logger = logging.getLogger(f"{__name__}.{self.name}")
    
    @abstractmethod
    def scrape_metadata(self, actor_name: str) -> Optional[ActorMetadata]:
        """
        刮削演员元数据
        
        Args:
            actor_name: 演员名称
        
        Returns:
            ActorMetadata 对象，失败返回 None
        """
        pass
    
    @abstractmethod
    def scrape_photos(self, actor_name: str) -> Optional[ActorPhotos]:
        """
        刮削演员照片
        
        Args:
            actor_name: 演员名称
        
        Returns:
            ActorPhotos 对象，失败返回 None
        """
        pass
