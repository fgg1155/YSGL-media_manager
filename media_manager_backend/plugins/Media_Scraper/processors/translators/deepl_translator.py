"""DeepL 翻译器

使用 DeepL API 实现的高质量翻译器，需要 API 密钥。
"""

import logging
from typing import Optional, Dict, Any
import aiohttp

from .base_translator import BaseTranslator

logger = logging.getLogger(__name__)


class DeepLTranslator(BaseTranslator):
    """DeepL 翻译器实现"""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """初始化 DeepL 翻译器
        
        Args:
            config: 配置字典，包含：
                - api_key: DeepL API 密钥（必需）
                  免费版密钥包含 ":fx" 后缀，付费版不包含
        """
        super().__init__(config)
        self.api_key = self.config.get("api_key", "")
        
        # 根据密钥类型选择 API URL
        if ":fx" in self.api_key:
            self.api_url = "https://api-free.deepl.com/v2/translate"
            logger.info("DeepL 翻译器初始化成功（免费版）")
        else:
            self.api_url = "https://api.deepl.com/v2/translate"
            logger.info("DeepL 翻译器初始化成功（付费版）")
    
    async def translate(
        self,
        text: str,
        source_lang: str = "ja",
        target_lang: str = "zh-CN"
    ) -> Optional[str]:
        """翻译文本
        
        Args:
            text: 要翻译的文本
            source_lang: 源语言代码（ja=日语, en=英语）
            target_lang: 目标语言代码（zh-CN=简体中文）
        
        Returns:
            翻译后的文本，失败返回 None
        """
        if not self.api_key or not text or not text.strip():
            return None
        
        try:
            # DeepL 使用大写语言代码
            source_lang_upper = source_lang.upper()
            # DeepL 的中文代码是 "ZH"
            target_lang_deepl = "ZH" if target_lang.startswith("zh") else target_lang.upper()
            
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"DeepL-Auth-Key {self.api_key}"
            }
            
            data = {
                "text": [text],
                "source_lang": source_lang_upper,
                "target_lang": target_lang_deepl
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.api_url,
                    json=data,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        
                        if "translations" in result and len(result["translations"]) > 0:
                            translated_text = result["translations"][0]["text"]
                            logger.debug(f"DeepL 翻译成功: {text[:50]}... -> {translated_text[:50]}...")
                            return translated_text
                        else:
                            logger.error(f"DeepL API 返回数据异常: {result}")
                            return None
                    else:
                        error_text = await response.text()
                        logger.error(f"DeepL API 请求失败 ({response.status}): {error_text}")
                        return None
            
        except Exception as e:
            logger.error(f"DeepL 翻译失败: {e}")
            return None
    
    def get_name(self) -> str:
        """获取翻译器名称"""
        return "deepl"
    
    def is_available(self) -> bool:
        """检查翻译器是否可用"""
        return bool(self.api_key)
