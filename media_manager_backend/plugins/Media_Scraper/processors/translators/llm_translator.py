"""LLM 翻译器

使用 OpenAI 兼容 API 实现的翻译器，支持自定义提示词和重试机制。
"""

import logging
import asyncio
from typing import Optional, Dict, Any
import aiohttp

from .base_translator import BaseTranslator

logger = logging.getLogger(__name__)


class LLMTranslator(BaseTranslator):
    """LLM 翻译器实现（OpenAI 兼容 API）"""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """初始化 LLM 翻译器
        
        Args:
            config: 配置字典，包含：
                - api_key: API 密钥
                - base_url: API 基础URL（默认 OpenAI）
                - model: 模型名称（默认 gpt-3.5-turbo）
                - max_retries: 最大重试次数（默认 3）
                - timeout: 请求超时时间（默认 30秒）
                - system_prompt: 系统提示词（可选）
        """
        super().__init__(config)
        self.api_key = self.config.get("api_key", "")
        self.base_url = self.config.get("base_url", "https://api.openai.com/v1")
        self.model = self.config.get("model", "gpt-3.5-turbo")
        self.max_retries = self.config.get("max_retries", 3)
        self.timeout = self.config.get("timeout", 30)
        self.system_prompt = self.config.get(
            "system_prompt",
            "You are a professional translator. "
            "Translate the following Japanese paragraph into Simplified Chinese, "
            "while leaving non-Japanese text, names, or text that does not look like Japanese untranslated. "
            "Reply with the translated text only, do not add any text that is not in the original content."
        )
    
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
        if not self.api_key or not text or not text.strip():
            return None
        
        # 构建用户提示词（简化，不需要重复说明）
        user_prompt = text
        
        # 重试机制
        for attempt in range(self.max_retries):
            try:
                result = await self._call_api(user_prompt)
                if result:
                    # 移除可能的思考过程标记
                    result = self._remove_cot_markers(result)
                    logger.debug(f"LLM 翻译成功: {text[:50]}... -> {result[:50]}...")
                    return result
                
            except Exception as e:
                logger.warning(f"LLM 翻译失败 (尝试 {attempt + 1}/{self.max_retries}): {e}")
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(1 * (attempt + 1))  # 指数退避
        
        logger.error(f"LLM 翻译失败，已达最大重试次数")
        return None
    
    async def _call_api(self, user_prompt: str) -> Optional[str]:
        """调用 OpenAI 兼容 API
        
        Args:
            user_prompt: 用户提示词
        
        Returns:
            API 返回的文本，失败返回 None
        """
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": 0.3,  # 降低随机性，提高翻译一致性
            "max_tokens": 2000
        }
        
        async with aiohttp.ClientSession() as session:
            async with session.post(
                url,
                headers=headers,
                json=payload,
                timeout=aiohttp.ClientTimeout(total=self.timeout)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    if "choices" in data and len(data["choices"]) > 0:
                        return data["choices"][0]["message"]["content"].strip()
                else:
                    error_text = await response.text()
                    logger.error(f"API 请求失败 ({response.status}): {error_text}")
                    return None
    
    @staticmethod
    def _remove_cot_markers(text: str) -> str:
        """移除 CoT（Chain of Thought）思考过程标记
        
        Args:
            text: 原始文本
        
        Returns:
            清理后的文本
        """
        # 移除常见的思考过程标记
        markers = [
            "让我想想", "让我思考", "思考：", "分析：",
            "Let me think", "Thinking:", "Analysis:"
        ]
        
        for marker in markers:
            if marker in text:
                # 找到标记后的第一个换行，移除之前的内容
                parts = text.split(marker, 1)
                if len(parts) > 1:
                    # 找到下一个段落
                    remaining = parts[1].split("\n\n", 1)
                    if len(remaining) > 1:
                        text = remaining[1]
        
        return text.strip()
    
    @staticmethod
    def _get_lang_name(lang_code: str) -> str:
        """获取语言名称
        
        Args:
            lang_code: 语言代码
        
        Returns:
            语言名称
        """
        lang_map = {
            "ja": "日语",
            "zh-CN": "简体中文",
            "zh-TW": "繁体中文",
            "en": "英语"
        }
        return lang_map.get(lang_code, lang_code)
    
    def get_name(self) -> str:
        """获取翻译器名称"""
        return "llm"
    
    def is_available(self) -> bool:
        """检查翻译器是否可用"""
        return bool(self.api_key)
