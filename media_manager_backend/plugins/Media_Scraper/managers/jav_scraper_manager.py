"""
JAV 刮削管理器
管理日本 AV 内容的刮削流程
"""

import re
import logging
import threading
from typing import Dict, Any, Optional, List

# 从核心模块导入 ScrapeResult
from core.models import ScrapeResult


logger = logging.getLogger(__name__)


class JAVScraperManager:
    """JAV 刮削管理器"""
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化管理器
        
        Args:
            config: 配置字典，包含：
                - translator: 翻译器配置（可选）
                    - enabled: 是否启用翻译（默认 False）
                    - fields: 需要翻译的字段列表（默认 ['title', 'overview']）
                    - llm: LLM 翻译器配置（可选）
        """
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # 延迟导入刮削器（避免循环导入）
        from scrapers.jav.avsox_scraper import AvsoxScraper
        from scrapers.jav.javlibrary_scraper import JAVLibraryScraper
        from scrapers.jav.javbus_scraper import JavBusScraper
        from scrapers.jav.javdb_scraper import JAVDBScraper
        from scrapers.jav.fanza_scraper import FanzaScraper
        from core.code_normalizer import CodeNormalizer
        from processors.genre_processor import GenreProcessor
        from processors.translators import TranslatorManager, GoogleTranslator, LLMTranslator
        
        # 初始化刮削器
        self.avsox = AvsoxScraper(config)
        self.javlibrary = JAVLibraryScraper(config)
        self.javbus = JavBusScraper(config)
        self.javdb = JAVDBScraper(config)
        self.fanza = FanzaScraper(config)
        self.normalizer = CodeNormalizer()
        
        # 初始化 Genre 处理器（仅用于 JAV 内容）
        self.genre_processor = GenreProcessor()
        
        # 初始化翻译管理器
        translator_config = config.get('translator', {})
        self.translation_enabled = translator_config.get('enabled', False)
        self.translation_fields = translator_config.get('fields', ['title', 'overview'])
        
        if self.translation_enabled:
            translators = []
            
            # 添加 LLM 翻译器（优先级1，翻译质量最高，推荐使用）
            if 'llm' in translator_config and translator_config['llm'].get('api_key'):
                translators.append(LLMTranslator(translator_config['llm']))
            
            # 添加 DeepL 翻译器（优先级2，高质量，需要配置）
            if 'deepl' in translator_config and translator_config['deepl'].get('api_key'):
                from processors.translators import DeepLTranslator
                translators.append(DeepLTranslator(translator_config['deepl']))
            
            # 添加 Google 翻译器（优先级3，免费备用，可能需要代理）
            if translator_config.get('google', {}).get('enabled', False):
                translators.append(GoogleTranslator(translator_config.get('google', {})))
            
            # 添加有道翻译器（优先级4，免费但不稳定，默认禁用）
            if translator_config.get('youdao', {}).get('enabled', False):
                from processors.translators import YoudaoTranslator
                translators.append(YoudaoTranslator())
            
            self.translator = TranslatorManager(translators)
            self.logger.info(f"翻译功能已启用，翻译字段: {self.translation_fields}")
            self.logger.info(f"可用翻译器: {self.translator.get_available_translators()}")
        else:
            self.translator = None
            self.logger.info("翻译功能未启用")
        
        self.logger.info("JAVScraperManager initialized")
    
    def scrape(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削指定番号
        
        Args:
            code: 番号（DVD ID 或 CID）
        
        Returns:
            刮削结果，如果失败返回 None
        """
        self.logger.info(f"开始刮削番号: {code}")
        
        # 1. 番号规范化
        code_info = self.normalizer.normalize(code)
        self.logger.info(f"番号规范化: DVD ID={code_info.dvdid}, CID={code_info.cid}, 类型={code_info.code_type}")
        
        # 2. 根据番号类型选择数据源
        scrapers = self._select_scrapers(code_info)
        self.logger.info(f"选择的数据源: {[s[0] for s in scrapers]}")
        
        # 3. 并发刮削
        results = self._scrape_concurrent(scrapers)
        self.logger.info(f"刮削完成，获得 {len(results)} 个结果")
        
        # 4. 结果聚合
        if not results:
            self.logger.warning(f"所有数据源都未能获取到数据: {code}")
            return None
        
        final_result = self._merge_results(results)
        self.logger.info(f"结果聚合完成: {final_result.code}")
        
        # 4.5. 去除标题中的演员名
        if final_result.title and final_result.actors:
            final_result.title = self._remove_trail_actor_in_title(final_result.title, final_result.actors)
        
        # 5. 翻译处理（如果启用）
        if self.translation_enabled and self.translator:
            final_result = self._translate_result(final_result)
        
        return final_result
    
    def _select_scrapers(self, code_info) -> List[tuple]:
        """
        根据番号类型选择数据源
        
        Args:
            code_info: 番号信息
        
        Returns:
            刮削器列表，格式为 [(name, scraper, code), ...]
            按优先级排序：fanza > javlibrary > javbus > javdb > avsox
        """
        scrapers = []
        code_type = code_info.code_type
        
        # FC2 番号：使用 JAVDB 和 AVSOX（无码）
        if code_type == 'fc2':
            if code_info.dvdid:
                scrapers.append(('javdb', self.javdb, code_info.dvdid))
                scrapers.append(('avsox', self.avsox, code_info.dvdid))
            return scrapers
        
        # 纯 CID 只使用 Fanza
        if code_type == 'cid_only':
            if code_info.cid:
                scrapers.append(('fanza', self.fanza, code_info.cid))
            return scrapers
        
        # 无码番号（一本道、加勒比等）：优先使用 AVSOX
        # 无码番号特征：纯数字格式（如 082713-417, 032620_001）
        if code_info.dvdid and self._is_uncensored_code(code_info.dvdid):
            scrapers.append(('avsox', self.avsox, code_info.dvdid))
            scrapers.append(('javdb', self.javdb, code_info.dvdid))
            return scrapers
        
        # 普通番号使用所有数据源（按优先级排序）
        # 优先级：fanza > javlibrary > javbus > javdb
        if code_info.cid:
            scrapers.append(('fanza', self.fanza, code_info.cid))
        
        if code_info.dvdid:
            scrapers.append(('javlibrary', self.javlibrary, code_info.dvdid))
            scrapers.append(('javbus', self.javbus, code_info.dvdid))
            scrapers.append(('javdb', self.javdb, code_info.dvdid))
        
        return scrapers
    
    @staticmethod
    def _is_uncensored_code(dvdid: str) -> bool:
        """
        判断是否为无码番号
        
        Args:
            dvdid: DVD ID
        
        Returns:
            True 如果是无码番号
        """
        # 无码番号特征：
        # 1. 一本道：6位数字-3位数字（如 082713-417）
        # 2. 加勒比：6位数字_3位数字（如 032620_001）
        # 3. 东京热：n开头+4位数字（如 n1234）
        # 4. 10musume：6位数字_2位数字（如 010120_01）
        # 5. pacopacomama：6位数字_3位数字（如 010120_001）
        
        uncensored_patterns = [
            r'^\d{6}-\d{3}$',      # 一本道
            r'^\d{6}_\d{3}$',      # 加勒比
            r'^n\d{4}$',           # 东京热
            r'^\d{6}_\d{2}$',      # 10musume
        ]
        
        for pattern in uncensored_patterns:
            if re.match(pattern, dvdid, re.IGNORECASE):
                return True
        
        return False
    
    def _scrape_concurrent(self, scrapers: List[tuple]) -> List[ScrapeResult]:
        """
        按优先级顺序刮削（带提前终止优化和错误聚合）
        
        Args:
            scrapers: 刮削器列表，格式为 [(name, scraper, code), ...]
                     已按优先级排序
        
        Returns:
            刮削结果列表
        
        优化策略：
        - 按优先级顺序执行刮削
        - 如果高优先级数据源已获取所有必要字段，跳过低优先级刮削
        - 使用 ErrorAggregator 收集所有错误
        """
        # 导入 ErrorAggregator
        from core.error_handler import ErrorAggregator
        
        results = []
        error_aggregator = ErrorAggregator()
        
        # 定义必要字段（如果这些字段都有值，可以提前终止）
        required_fields = ['title', 'release_date', 'actors', 'poster_url']
        
        def check_if_complete():
            """检查是否已获取所有必要字段"""
            if not results:
                return False
            
            # 按优先级排序结果
            priority_order = ['fanza', 'javlibrary', 'javbus', 'avsox', 'javdb']
            sorted_results = sorted(results, key=lambda x: priority_order.index(x[0]) if x[0] in priority_order else 999)
            
            # 临时合并检查
            temp_merged = {}
            for source, result in sorted_results:
                for field in required_fields:
                    if field not in temp_merged or not temp_merged[field]:
                        value = getattr(result, field, None)
                        if value:
                            temp_merged[field] = value
            
            # 检查是否所有必要字段都有值
            return all(temp_merged.get(field) for field in required_fields)
        
        # 按优先级顺序执行刮削
        for name, scraper, code in scrapers:
            try:
                self.logger.debug(f"开始刮削 {name}: {code}")
                result = scraper.scrape(code)
                
                if result:
                    result.source = name  # 标记数据来源
                    results.append((name, result))
                    self.logger.info(f"✓ {name} 刮削成功: {code}")
                    
                    # 检查是否已获取所有必要字段
                    if check_if_complete():
                        self.logger.info(f"✓ 已获取所有必要字段，跳过剩余 {len(scrapers) - len(results)} 个数据源")
                        break
                else:
                    self.logger.warning(f"✗ {name} 未找到数据: {code}")
                    # 注意：scraper.scrape() 内部已经处理了异常并记录了错误
                    # 这里不需要再次添加到 error_aggregator
                    
            except Exception as e:
                # 这里捕获的是 scraper.scrape() 之外的异常
                self.logger.error(f"✗ {name} 刮削异常: {code} - {e}")
                # 使用 scraper 的 error_handler 处理异常
                if hasattr(scraper, 'error_handler'):
                    error = scraper.error_handler.handle_exception(e, name, code)
                    error_aggregator.add_error(error)
        
        # 如果所有数据源都失败，记录错误摘要
        if not results and error_aggregator.has_errors():
            summary = error_aggregator.get_summary()
            self.logger.error(f"所有数据源失败: {summary['summary']['zh']}")
            self.logger.debug(f"错误详情: {summary}")
        
        return results
    
    def _merge_results(self, results: List[tuple]) -> ScrapeResult:
        """
        合并多个刮削结果（补充式策略）
        
        Args:
            results: 刮削结果列表，格式为 [(name, result), ...]
        
        Returns:
            合并后的结果
        
        合并策略（补充式）：
        - 按优先级排序：fanza > javlibrary > javbus > avsox > javdb
        - 对所有字段采用"第一个非空值"策略（包括列表字段）
        - 只有当高优先级数据源的字段为空时，才使用低优先级数据源的值
        - 特殊处理：封面URL避免使用JAVDB水印封面（除非没有其他来源）
        - Genre处理：收集所有来源的genres，使用GenreProcessor进行翻译和去重
        """
        # 定义优先级顺序
        priority_order = ['fanza', 'javlibrary', 'javbus', 'avsox', 'javdb']
        
        # 按优先级排序结果
        sorted_results = sorted(results, key=lambda x: priority_order.index(x[0]) if x[0] in priority_order else 999)
        
        # 创建合并结果
        merged = ScrapeResult()
        
        # 用于封面URL的特殊处理
        poster_urls = {}  # {source: url}
        
        # 用于Genre的特殊处理：收集所有来源的genres
        all_genres = []
        
        # 遍历所有结果，按优先级合并（补充式）
        for source, result in sorted_results:
            # 标量字段：使用第一个非空值
            if not merged.code and result.code:
                merged.code = result.code
            if not merged.title and result.title:
                merged.title = result.title
            if not merged.original_title and result.original_title:
                merged.original_title = result.original_title
            if not merged.release_date and result.release_date:
                merged.release_date = result.release_date
            if not merged.year and result.year:
                merged.year = result.year
            if not merged.studio and result.studio:
                merged.studio = result.studio
            if not merged.series and result.series:
                merged.series = result.series
            if not merged.overview and result.overview:
                merged.overview = result.overview
            if not merged.rating and result.rating:
                merged.rating = result.rating
            if not merged.runtime and result.runtime:
                merged.runtime = result.runtime
            if not merged.director and result.director:
                merged.director = result.director
            if not merged.backdrop_url and result.backdrop_url:
                merged.backdrop_url = result.backdrop_url
            if not merged.mosaic and result.mosaic:
                merged.mosaic = result.mosaic
            
            # 视频预览URL列表
            if not merged.preview_video_urls and result.preview_video_urls:
                merged.preview_video_urls = result.preview_video_urls
            
            # 封面URL：收集所有来源（后续特殊处理）
            if result.poster_url:
                poster_urls[source] = result.poster_url
            
            # 列表字段：使用第一个非空列表（补充式，不合并）
            if not merged.actors and result.actors:
                merged.actors = result.actors
            if not merged.preview_urls and result.preview_urls:
                merged.preview_urls = result.preview_urls
            
            # Genres：收集所有来源的genres（后续统一处理）
            if result.genres:
                all_genres.extend(result.genres)
        
        # 处理封面URL：优先使用非JAVDB来源（避免水印）
        if poster_urls:
            # 优先级：fanza > javlibrary > javbus > avsox > javdb
            for source in ['fanza', 'javlibrary', 'javbus', 'avsox', 'javdb']:
                if source in poster_urls:
                    merged.poster_url = poster_urls[source]
                    self.logger.debug(f"选择封面来源: {source}")
                    break
        
        # 处理Genres：使用GenreProcessor进行翻译和去重
        if all_genres:
            try:
                merged.genres = self.genre_processor.process_genres(all_genres)
                self.logger.debug(f"Genre处理: 原始{len(all_genres)}个 -> 处理后{len(merged.genres)}个")
            except Exception as e:
                self.logger.error(f"Genre处理失败: {e}，使用原始genres")
                # 如果处理失败，至少做个简单去重
                merged.genres = list(dict.fromkeys(all_genres))
        
        # 记录合并来源
        sources = [name for name, _ in sorted_results]
        merged.source = '+'.join(sources)
        
        # 如果没有 mosaic 信息，根据番号类型判定
        if not merged.mosaic and merged.code:
            if self._is_uncensored_code(merged.code):
                merged.mosaic = '无码'
            else:
                merged.mosaic = '有码'
        
        self.logger.debug(f"合并结果: 来源={merged.source}, 演员数={len(merged.actors)}, 类型数={len(merged.genres)}, 预览图数={len(merged.preview_urls)}, 马赛克={merged.mosaic}")
        
        return merged
    
    def _translate_result(self, result: ScrapeResult) -> ScrapeResult:
        """
        翻译刮削结果中的指定字段
        
        Args:
            result: 刮削结果
        
        Returns:
            翻译后的结果
        """
        import asyncio
        
        self.logger.info(f"开始翻译字段: {self.translation_fields}")
        
        # 创建异步任务
        async def translate_async():
            for field in self.translation_fields:
                # 获取字段值
                value = getattr(result, field, None)
                
                if not value or not isinstance(value, str):
                    continue
                
                # 检查是否为日语（简单判断：包含日文字符）
                if not self._is_japanese(value):
                    self.logger.debug(f"字段 {field} 不是日语，跳过翻译")
                    continue
                
                # 翻译
                try:
                    translated = await self.translator.translate(value, "ja", "zh-CN")
                    if translated:
                        setattr(result, field, translated)
                        self.logger.info(f"字段 {field} 翻译成功")
                    else:
                        self.logger.warning(f"字段 {field} 翻译失败，保留原文")
                except Exception as e:
                    self.logger.error(f"字段 {field} 翻译异常: {e}")
        
        # 运行异步任务
        try:
            asyncio.run(translate_async())
        except Exception as e:
            self.logger.error(f"翻译过程异常: {e}")
        
        return result
    
    @staticmethod
    def _is_japanese(text: str) -> bool:
        """
        检查文本是否包含日文字符
        
        Args:
            text: 文本
        
        Returns:
            True 如果包含日文字符
        """
        # 日文字符范围：平假名、片假名、汉字
        japanese_ranges = [
            (0x3040, 0x309F),  # 平假名
            (0x30A0, 0x30FF),  # 片假名
            (0x4E00, 0x9FFF),  # CJK 统一汉字
        ]
        
        for char in text:
            code = ord(char)
            for start, end in japanese_ranges:
                if start <= code <= end:
                    return True
        
        return False
    
    def _remove_trail_actor_in_title(self, title: str, actors: list) -> str:
        """
        寻找并移除标题尾部的演员名
        
        Args:
            title: 标题
            actors: 演员列表
        
        Returns:
            处理后的标题
        """
        if not (actors and title):
            return title
        
        # 目前使用分隔符白名单来做检测（担心按Unicode范围匹配误伤太多），考虑尽可能多的分隔符
        delimiters = '-xX &·,;　＆・，；'
        actor_ls = [re.escape(i) for i in actors if i]
        pattern = f"^(.*?)([{delimiters}]{{1,3}}({'|'.join(actor_ls)}))+$"
        
        # 使用match而不是sub是为了将替换掉的部分写入日志
        match = re.match(pattern, title)
        if match:
            original_title = title
            new_title = match.group(1)
            self.logger.info(f"已去除标题中的演员名: '{original_title}' -> '{new_title}'")
            return new_title
        else:
            return title
