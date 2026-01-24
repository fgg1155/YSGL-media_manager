"""有道翻译器

使用有道翻译免费 API 实现的翻译器，无需配置。
"""

import logging
import hashlib
import random
import time
from typing import Optional
import aiohttp

from .base_translator import BaseTranslator

logger = logging.getLogger(__name__)


class YoudaoTranslator(BaseTranslator):
    """有道翻译器实现（免费 API）"""
    
    def __init__(self, config: Optional[dict] = None):
        super().__init__(config)
        self.api_url = "https://fanyi.youdao.com/translate_o?smartresult=dict&smartresult=rule"
        self._last_request_time = 0
        logger.info("有道翻译器初始化成功（免费 API）")
    
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
        
        # 限制请求频率（至少间隔 1 秒）
        now = time.time()
        wait_time = 1.0 - (now - self._last_request_time)
        if wait_time > 0:
            await asyncio.sleep(wait_time)
        
        try:
            # 生成签名
            lts = str(int(time.time() * 1000))
            salt = lts + str(random.randint(0, 10))
            sign_str = "fanyideskweb" + text + salt + "Ygy_4c=r#e#4EX^NUGUc5"
            sign = hashlib.md5(sign_str.encode("utf-8")).hexdigest()
            
            # 构建请求数据
            data = {
                "i": text,
                "from": "ja",  # 明确指定日语
                "to": "zh-CHS",  # 简体中文
                "smartresult": "dict",
                "client": "fanyideskweb",
                "salt": salt,
                "sign": sign,
                "lts": lts,
                "bv": "c6b8c998b2cbaa29bd94afc223bc106c",
                "doctype": "json",
                "version": "2.1",
                "keyfrom": "fanyi.web",
                "action": "FY_BY_REALTlME",
            }
            
            headers = {
                "Referer": "https://fanyi.youdao.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                "Origin": "https://fanyi.youdao.com",
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.api_url,
                    data=data,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    self._last_request_time = time.time()
                    
                    if response.status == 200:
                        result = await response.json()
                        
                        # 解析翻译结果
                        translate_result = result.get("translateResult")
                        if translate_result:
                            # 拼接所有段落的翻译
                            translated_text = ""
                            for paragraph in translate_result:
                                for sentence in paragraph:
                                    translated_text += sentence.get("tgt", "")
                            
                            if translated_text:
                                logger.debug(f"有道翻译成功: {text[:50]}... -> {translated_text[:50]}...")
                                return translated_text.strip()
                        
                        logger.error(f"有道翻译返回数据异常: {result}")
                        return None
                    else:
                        logger.error(f"有道 API 请求失败: HTTP {response.status}")
                        return None
            
        except Exception as e:
            logger.error(f"有道翻译失败: {e}")
            return None
    
    def get_name(self) -> str:
        """获取翻译器名称"""
        return "youdao"
    
    def is_available(self) -> bool:
        """检查翻译器是否可用"""
        return True  # 免费 API，始终可用


# 需要导入 asyncio
import asyncio
