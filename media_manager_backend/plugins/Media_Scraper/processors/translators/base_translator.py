"""翻译器基类

定义翻译器的抽象接口，所有翻译器实现必须继承此类。
"""

from abc import ABC, abstractmethod
from typing import Optional, Dict, Any


class BaseTranslator(ABC):
    """翻译器抽象基类"""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """初始化翻译器
        
        Args:
            config: 翻译器配置字典，不同翻译器有不同的配置项
        """
        self.config = config or {}
    
    @abstractmethod
    async def translate(
        self,
        text: str,
        source_lang: str = "ja",
        target_lang: str = "zh-CN"
    ) -> Optional[str]:
        """翻译文本
        
        Args:
            text: 要翻译的文本
            source_lang: 源语言代码（默认日语）
            target_lang: 目标语言代码（默认简体中文）
        
        Returns:
            翻译后的文本，失败返回 None
        """
        pass
    
    @abstractmethod
    def get_name(self) -> str:
        """获取翻译器名称"""
        pass
    
    def is_available(self) -> bool:
        """检查翻译器是否可用
        
        Returns:
            True 如果翻译器可用，否则 False
        """
        return True
