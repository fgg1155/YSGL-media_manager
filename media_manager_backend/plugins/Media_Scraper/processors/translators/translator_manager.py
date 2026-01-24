"""翻译管理器

管理多个翻译器，提供翻译缓存和失败降级功能。
"""

import logging
import hashlib
import json
from typing import Optional, List, Dict, Any
from pathlib import Path

from .base_translator import BaseTranslator
from .google_translator import GoogleTranslator
from .llm_translator import LLMTranslator

logger = logging.getLogger(__name__)


class TranslationCache:
    """翻译缓存管理器"""
    
    def __init__(self, cache_file: Optional[Path] = None):
        """初始化缓存
        
        Args:
            cache_file: 缓存文件路径，None 则使用默认路径
        """
        if cache_file is None:
            cache_file = Path(__file__).parent.parent.parent / "cache" / "translation_cache.json"
        
        self.cache_file = cache_file
        self.cache: Dict[str, str] = {}
        self._load_cache()
    
    def _load_cache(self):
        """从文件加载缓存"""
        try:
            if self.cache_file.exists():
                with open(self.cache_file, 'r', encoding='utf-8') as f:
                    self.cache = json.load(f)
                logger.info(f"加载翻译缓存: {len(self.cache)} 条记录")
        except Exception as e:
            logger.warning(f"加载翻译缓存失败: {e}")
            self.cache = {}
    
    def _save_cache(self):
        """保存缓存到文件"""
        try:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.cache_file, 'w', encoding='utf-8') as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error(f"保存翻译缓存失败: {e}")
    
    def get(self, text: str, source_lang: str, target_lang: str) -> Optional[str]:
        """获取缓存的翻译
        
        Args:
            text: 原文
            source_lang: 源语言
            target_lang: 目标语言
        
        Returns:
            缓存的翻译，不存在返回 None
        """
        key = self._make_key(text, source_lang, target_lang)
        return self.cache.get(key)
    
    def set(self, text: str, source_lang: str, target_lang: str, translation: str):
        """设置翻译缓存
        
        Args:
            text: 原文
            source_lang: 源语言
            target_lang: 目标语言
            translation: 翻译结果
        """
        key = self._make_key(text, source_lang, target_lang)
        self.cache[key] = translation
        self._save_cache()
    
    @staticmethod
    def _make_key(text: str, source_lang: str, target_lang: str) -> str:
        """生成缓存键
        
        Args:
            text: 原文
            source_lang: 源语言
            target_lang: 目标语言
        
        Returns:
            缓存键（MD5哈希）
        """
        content = f"{source_lang}:{target_lang}:{text}"
        return hashlib.md5(content.encode('utf-8')).hexdigest()
    
    def clear(self):
        """清空缓存"""
        self.cache = {}
        self._save_cache()
        logger.info("翻译缓存已清空")
    
    def size(self) -> int:
        """获取缓存大小"""
        return len(self.cache)


class TranslatorManager:
    """翻译管理器"""
    
    def __init__(
        self,
        translators: Optional[List[BaseTranslator]] = None,
        cache_file: Optional[Path] = None
    ):
        """初始化翻译管理器
        
        Args:
            translators: 翻译器列表（按优先级排序）
            cache_file: 缓存文件路径
        """
        self.translators = translators or []
        self.cache = TranslationCache(cache_file)
        
        # 过滤不可用的翻译器
        self.translators = [t for t in self.translators if t.is_available()]
        
        if not self.translators:
            logger.warning("没有可用的翻译器")
        else:
            logger.info(f"已加载 {len(self.translators)} 个翻译器: {[t.get_name() for t in self.translators]}")
    
    async def translate(
        self,
        text: str,
        source_lang: str = "ja",
        target_lang: str = "zh-CN",
        use_cache: bool = True
    ) -> Optional[str]:
        """翻译文本（带缓存和失败降级）
        
        Args:
            text: 要翻译的文本
            source_lang: 源语言代码
            target_lang: 目标语言代码
            use_cache: 是否使用缓存
        
        Returns:
            翻译后的文本，失败返回 None
        """
        if not text or not text.strip():
            return None
        
        # 检查缓存
        if use_cache:
            cached = self.cache.get(text, source_lang, target_lang)
            if cached:
                logger.debug(f"使用缓存翻译: {text[:50]}...")
                return cached
        
        # 尝试所有翻译器（按优先级）
        for translator in self.translators:
            try:
                result = await translator.translate(text, source_lang, target_lang)
                if result:
                    # 保存到缓存
                    if use_cache:
                        self.cache.set(text, source_lang, target_lang, result)
                    
                    logger.info(f"使用 {translator.get_name()} 翻译成功")
                    return result
                    
            except Exception as e:
                logger.warning(f"{translator.get_name()} 翻译失败: {e}")
                continue
        
        logger.error(f"所有翻译器均失败，保留原文")
        return None
    
    async def translate_fields(
        self,
        data: Dict[str, Any],
        fields: List[str],
        source_lang: str = "ja",
        target_lang: str = "zh-CN"
    ) -> Dict[str, Any]:
        """翻译字典中的指定字段
        
        Args:
            data: 数据字典
            fields: 需要翻译的字段列表
            source_lang: 源语言代码
            target_lang: 目标语言代码
        
        Returns:
            翻译后的数据字典
        """
        result = data.copy()
        
        for field in fields:
            if field in result and result[field]:
                original = result[field]
                translated = await self.translate(original, source_lang, target_lang)
                
                if translated:
                    result[field] = translated
                    logger.debug(f"字段 {field} 翻译成功")
                else:
                    logger.warning(f"字段 {field} 翻译失败，保留原文")
        
        return result
    
    def add_translator(self, translator: BaseTranslator):
        """添加翻译器
        
        Args:
            translator: 翻译器实例
        """
        if translator.is_available():
            self.translators.append(translator)
            logger.info(f"添加翻译器: {translator.get_name()}")
        else:
            logger.warning(f"翻译器 {translator.get_name()} 不可用，跳过")
    
    def get_available_translators(self) -> List[str]:
        """获取可用翻译器列表"""
        return [t.get_name() for t in self.translators]
    
    def clear_cache(self):
        """清空翻译缓存"""
        self.cache.clear()


def create_default_manager(config: Optional[Dict[str, Any]] = None) -> TranslatorManager:
    """创建默认的翻译管理器
    
    Args:
        config: 配置字典，包含：
            - llm: LLM 翻译器配置（推荐，需要 api_key）
            - deepl: DeepL 翻译器配置（需要 api_key）
            - google: Google 翻译器配置（可选，可能需要代理）
            - youdao: 有道翻译器配置（可选，不稳定）
            - cache_file: 缓存文件路径
    
    Returns:
        配置好的 TranslatorManager 实例
    
    翻译器优先级：
        1. LLM（推荐，翻译质量最高）
        2. DeepL（高质量，需要密钥）
        3. Google（免费备用，可能需要代理）
        4. 有道（免费但不稳定）
    """
    config = config or {}
    
    translators = []
    
    # 添加 LLM 翻译器（优先级1，推荐使用）
    if "llm" in config and config["llm"].get("api_key"):
        translators.append(LLMTranslator(config["llm"]))
    
    # 添加 DeepL 翻译器（优先级2，高质量，需要配置）
    if "deepl" in config and config["deepl"].get("api_key"):
        from .deepl_translator import DeepLTranslator
        translators.append(DeepLTranslator(config["deepl"]))
    
    # 添加 Google 翻译器（优先级3，免费备用）
    if config.get("google", {}).get("enabled", False):
        translators.append(GoogleTranslator(config.get("google", {})))
    
    # 添加有道翻译器（优先级4，免费但不稳定）
    if config.get("youdao", {}).get("enabled", False):
        from .youdao_translator import YoudaoTranslator
        translators.append(YoudaoTranslator())
    
    cache_file = config.get("cache_file")
    return TranslatorManager(translators, cache_file)
