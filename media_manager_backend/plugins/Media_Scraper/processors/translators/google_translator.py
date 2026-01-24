"""Google 翻译器

使用 Google Translate 免费 API 实现的翻译器，无需配置。
支持代理设置以解决网络访问问题。
"""

import logging
from typing import Optional
from urllib.parse import quote
import aiohttp
import asyncio

from .base_translator import BaseTranslator

logger = logging.getLogger(__name__)


class GoogleTranslator(BaseTranslator):
    """Google 翻译器实现（使用免费 API）"""
    
    def __init__(self, config: Optional[dict] = None):
        super().__init__(config)
        # 使用多个可用的 Google 翻译域名
        self.api_urls = [
            "https://translate.googleapis.com/translate_a/single",
            "https://translate.google.com.hk/translate_a/single",
            "https://translate.google.cn/translate_a/single",
        ]
        self.current_url_index = 0
        self.proxy = self.config.get("proxy")  # 可选代理配置
        logger.info("Google 翻译器初始化成功（免费 API）")
    
    async def translate(
        self,
        text: str,
        source_lang: str = "ja",
        target_lang: str = "zh-CN"
    ) -> Optional[str]:
        """翻译文本
        
        Args:
            text: 要翻译的文本
            source_lang: 源语言代码（ja=日语）
            target_lang: 目标语言代码（zh-CN=简体中文）
        
        Returns:
            翻译后的文本，失败返回 None
        """
        if not text or not text.strip():
            return None
        
        # 尝试所有可用的 API URL
        for i in range(len(self.api_urls)):
            url = self.api_urls[(self.current_url_index + i) % len(self.api_urls)]
            result = await self._try_translate(url, text, source_lang, target_lang)
            if result:
                # 记录成功的 URL
                self.current_url_index = (self.current_url_index + i) % len(self.api_urls)
                return result
        
        logger.error("所有 Google 翻译 API 均失败")
        return None
    
    async def _try_translate(
        self,
        api_url: str,
        text: str,
        source_lang: str,
        target_lang: str
    ) -> Optional[str]:
        """尝试使用指定 URL 翻译"""
        try:
            # 构建请求参数
            params = {
                'client': 'gtx',
                'sl': source_lang,
                'tl': 'zh-CN',  # 固定使用简体中文
                'dt': 't',
                'q': text
            }
            
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            
            # 配置连接器（禁用 SSL 验证以避免证书问题）
            connector = aiohttp.TCPConnector(ssl=False)
            
            async with aiohttp.ClientSession(connector=connector) as session:
                async with session.get(
                    api_url,
                    params=params,
                    headers=headers,
                    proxy=self.proxy,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        # Google API 返回格式: [[["译文", "原文", null, null, 10]], ...]
                        if data and len(data) > 0 and len(data[0]) > 0:
                            # 拼接所有句子的翻译
                            result = ''.join([sentence[0] for sentence in data[0] if sentence[0]])
                            logger.debug(f"Google 翻译成功 ({api_url}): {text[:50]}... -> {result[:50]}...")
                            return result
                    else:
                        logger.debug(f"Google API ({api_url}) 请求失败: HTTP {response.status}")
                        return None
            
        except asyncio.TimeoutError:
            logger.debug(f"Google API ({api_url}) 请求超时")
            return None
        except Exception as e:
            logger.debug(f"Google API ({api_url}) 翻译失败: {e}")
            return None
    
    def get_name(self) -> str:
        """获取翻译器名称"""
        return "google"
    
    def is_available(self) -> bool:
        """检查翻译器是否可用"""
        return True  # 免费 API，始终可用
