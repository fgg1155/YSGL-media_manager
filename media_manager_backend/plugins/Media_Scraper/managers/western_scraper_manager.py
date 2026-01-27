"""
欧美内容刮削管理器
管理欧美成人内容的刮削流程
"""

import logging
import threading
import re
from typing import Dict, Any, Optional, List
from .jav_scraper_manager import ScrapeResult

# 导入工具模块
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.query_parser import extract_series_and_title, normalize_series_name
from utils.date_parser import is_date_query, parse_date_query, filter_by_date


logger = logging.getLogger(__name__)


class WesternScraperManager:
    """欧美内容刮削管理器"""
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化管理器
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # 结果数量限制配置（统一管理）
        scraper_config = config.get('scraper', {})
        self.max_results = scraper_config.get('max_results', 20)  # 默认最多返回 20 个结果
        self.logger.info(f"结果数量限制: {self.max_results}")
        
        # 刮削器能力配置（用于过滤刮削器）
        capabilities = scraper_config.get('capabilities', {})
        self.movie_search_scrapers = set(capabilities.get('movie_search', ['theporndb']))
        self.scene_search_scrapers = set(capabilities.get('scene_search', [
            'theporndb', 'mindgeek', 'gamma', 'hustler', 'mariskax', 'straplez', 'adultprime', 'metart_network'
        ]))
        self.title_search_scrapers = set(capabilities.get('title_search', [
            'theporndb', 'adultprime'
        ]))
        self.series_title_search_scrapers = set(capabilities.get('series_title_search', [
            'theporndb', 'mindgeek', 'gamma', 'hustler', 'mariskax', 'adultprime', 'metart_network'
        ]))
        self.series_date_search_scrapers = set(capabilities.get('series_date_search', [
            'theporndb', 'gamma', 'hustler', 'adultprime'
        ]))
        self.logger.info(f"支持电影搜索的刮削器: {self.movie_search_scrapers}")
        self.logger.info(f"支持场景搜索的刮削器: {self.scene_search_scrapers}")
        self.logger.info(f"支持纯标题搜索的刮削器: {self.title_search_scrapers}")
        self.logger.info(f"支持系列+标题搜索的刮削器: {self.series_title_search_scrapers}")
        self.logger.info(f"支持系列+日期搜索的刮削器: {self.series_date_search_scrapers}")
        
        # 初始化结果管理器（统一处理刮削结果）
        from .result_manager import ResultManager
        self.result_manager = ResultManager()
        
        # 初始化翻译管理器（欧美内容只翻译简介）
        translator_config = config.get('translator', {})
        self.translation_enabled = translator_config.get('enabled', False)
        
        if self.translation_enabled:
            from processors.translators import TranslatorManager, GoogleTranslator, LLMTranslator
            
            translators = []
            
            # 添加 LLM 翻译器（优先级1）
            if 'llm' in translator_config and translator_config['llm'].get('api_key'):
                translators.append(LLMTranslator(translator_config['llm']))
            
            # 添加 DeepL 翻译器（优先级2）
            if 'deepl' in translator_config and translator_config['deepl'].get('api_key'):
                from processors.translators import DeepLTranslator
                translators.append(DeepLTranslator(translator_config['deepl']))
            
            # 添加 Google 翻译器（优先级3）
            if translator_config.get('google', {}).get('enabled', False):
                translators.append(GoogleTranslator(translator_config.get('google', {})))
            
            self.translator = TranslatorManager(translators)
            self.logger.info("翻译功能已启用（欧美内容只翻译简介）")
        else:
            self.translator = None
            self.logger.info("翻译功能未启用")
        
        # 延迟导入刮削器（避免循环导入）
        try:
            from scrapers.western.theporndb_scraper import ThePornDBScraper
            from scrapers.western.MindGeek_Network_Scraper import MindGeekScraper
            from scrapers.western.Gamma_Entertainment_Scraper import AbstractGammaEntertainmentScraper
            from scrapers.western.Hustler_Network_Scraper import AbstractHustlerScraper
            from scrapers.western.MariskaX_Scraper import MariskaXScraper
            from scrapers.western.AdultPrime_Scraper import AdultPrimeScraper
            from scrapers.western.MetArt_Network_Scraper import MetArtNetworkScraper
            from scrapers.western.ScoreGroup_Scraper import ScoreGroupScraper
            # from scrapers.western.adultempire_scraper import AdultEmpireScraper
            # from scrapers.western.iafd_scraper import IAFDScraper
            
            # 初始化刮削器
            self.theporndb = ThePornDBScraper(config)  # 开启 ThePornDB
            self.mindgeek = MindGeekScraper(config)
            self.gamma = AbstractGammaEntertainmentScraper(config=config)  # 添加 Gamma 刮削器
            self.hustler = AbstractHustlerScraper(site_config=None, config=config)  # 添加 Hustler 刮削器
            self.mariskax = MariskaXScraper(config, use_scraper=True)  # 添加 MariskaX 刮削器
            self.adultprime = AdultPrimeScraper(config, use_scraper=True)  # 添加 AdultPrime 刮削器
            self.metart = MetArtNetworkScraper(config, use_scraper=False)  # 添加 MetArt Network 刮削器
            self.scoregroup = ScoreGroupScraper(config)  # 添加 Score Group 刮削器
            # self.adultempire = AdultEmpireScraper(config)
            # self.iafd = IAFDScraper(config)
            
            # 禁用 IAFD 和 AdultEmpire
            self.adultempire = None
            self.iafd = None
            
            self.logger.info("WesternScraperManager initialized with ThePornDB, MindGeek, Gamma, Hustler, MariskaX, AdultPrime, MetArt Network and Score Group scrapers")
        except ImportError as e:
            self.logger.warning(f"Failed to import Western scrapers: {e}")
            self.theporndb = None
            self.mindgeek = None
            self.gamma = None
            self.hustler = None
            self.mariskax = None
            self.adultprime = None
            self.metart = None
            self.scoregroup = None
            self.adultempire = None
            self.iafd = None
    
    def scrape_multiple(self, title: str, series: Optional[str] = None, content_type_hint: Optional[str] = None) -> List[ScrapeResult]:
        """
        通过标题刮削欧美内容，返回多个结果
        
        Args:
            title: 作品标题（可能包含系列名，如 "EvilAngel-Title" 或纯 "Title"）
                  或日期格式（如 "Evilangel.26.01.23" 或 "26.01.23"）
            series: 系列名（可选，如果提供则优先使用）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation）
        
        Returns:
            刮削结果列表
        """
        self.logger.info(f"=" * 80)
        self.logger.info(f"开始刮削欧美内容（多结果模式）:")
        self.logger.info(f"  原始输入 title={title}")
        self.logger.info(f"  series={series}")
        self.logger.info(f"  content_type_hint={content_type_hint}")
        self.logger.info(f"=" * 80)
        
        # 1. 检查刮削器是否可用
        if not self.theporndb and not self.mindgeek and not self.gamma and not self.mariskax and not self.adultprime and not self.metart:
            self.logger.error("No scrapers available")
            return []
        
        # 2. 检测是否是日期查询
        if is_date_query(title):
            parsed_series, parsed_date = parse_date_query(title)
            if parsed_series and parsed_date:
                self.logger.info(f"检测到日期查询: series={parsed_series}, date={parsed_date.strftime('%Y-%m-%d')}")
                # 如果解析出系列名，覆盖传入的 series 参数
                if not series:
                    series = parsed_series
                    self.logger.info(f"使用解析出的系列名: {series}")
        
        # 3. 如果有系列名，查找对应的刮削器
        if series:
            # 检测是否是日期查询
            is_date_query_flag = is_date_query(title)
            
            target_scraper = self._find_scraper_for_series(series, content_type_hint, is_date_query=is_date_query_flag)
            
            if not target_scraper:
                # 未找到对应的刮削器，说明 series 不是真正的系列名
                # 直接走"无系列名"流程（AdultPrime → ThePornDB）
                self.logger.info(f"系列 {series} 不是已知系列名，按无系列名模式处理")
                series = None  # 清空 series，走无系列名流程
            else:
                # 找到对应的刮削器
                scraper_name, scraper = target_scraper
                self.logger.info(f"系列 {series} 属于 {scraper_name} 刮削器")
                
                # 所有刮削器都应该实现 scrape_multiple 公共接口
                try:
                    results = scraper.scrape_multiple(title, content_type_hint, series)
                    
                    # 统一限制结果数量（由管理器控制）
                    if len(results) > self.max_results:
                        self.logger.info(f"结果数量限制: {len(results)} -> {self.max_results}")
                        results = results[:self.max_results]
                    
                    if results:
                        self.logger.info(f"✓ {scraper_name} 返回 {len(results)} 个结果")
                        
                        # 使用 ResultManager 统一处理匹配逻辑
                        results = self.result_manager.process_results_with_matching(
                            results, 
                            title, 
                            is_date_query=is_date_query(title)
                        )
                        return results
                    else:
                        self.logger.warning(f"✗ {scraper_name} 未找到结果")
                        # 继续尝试 ThePornDB 作为保底
                        
                except Exception as e:
                    self.logger.error(f"✗ {scraper_name}.scrape_multiple 失败: {e}")
                    import traceback
                    self.logger.error(traceback.format_exc())
                    # 继续尝试 ThePornDB 作为保底
        
        # 4. 无系列名或未找到对应刮削器：按标题直接搜索
        # 使用 title_search 配置的刮削器
        if not series:
            self.logger.info(f"按标题直接搜索（无系列名模式）")
            
            # 根据 content_type_hint 确定可用的刮削器
            if content_type_hint == "Movie":
                available_scrapers = self.movie_search_scrapers
                self.logger.info(f"内容类型: Movie，只使用支持电影搜索的刮削器: {available_scrapers}")
            else:
                available_scrapers = self.scene_search_scrapers
                self.logger.info(f"内容类型: {content_type_hint or 'Scene'}，使用所有刮削器")
            
            # 进一步过滤：只使用支持纯标题搜索的刮削器
            title_scrapers = available_scrapers & self.title_search_scrapers
            self.logger.info(f"支持纯标题搜索的刮削器: {title_scrapers}")
            
            # 按配置顺序尝试刮削器
            scrapers_to_try = []
            if self.adultprime and 'adultprime' in title_scrapers:
                scrapers_to_try.append(('adultprime', self.adultprime))
            if self.theporndb and 'theporndb' in title_scrapers:
                scrapers_to_try.append(('theporndb', self.theporndb))
            
            # 依次尝试刮削器
            for scraper_name, scraper in scrapers_to_try:
                self.logger.info(f"尝试使用 {scraper_name} 刮削器")
                try:
                    results = scraper.scrape_multiple(title, content_type_hint, None)
                    if results:
                        # 统一限制结果数量（由管理器控制）
                        if len(results) > self.max_results:
                            self.logger.info(f"结果数量限制: {len(results)} -> {self.max_results}")
                            results = results[:self.max_results]
                        
                        self.logger.info(f"✓ {scraper_name} 返回 {len(results)} 个结果")
                        
                        # 使用 ResultManager 统一处理匹配逻辑
                        results = self.result_manager.process_results_with_matching(
                            results, 
                            title, 
                            is_date_query=is_date_query(title)
                        )
                        return results
                    else:
                        self.logger.info(f"✗ {scraper_name} 未找到结果")
                except Exception as e:
                    self.logger.error(f"✗ {scraper_name} 刮削失败: {e}")
                    import traceback
                    self.logger.error(traceback.format_exc())
            
            self.logger.warning(f"所有刮削器都未找到结果")
            return []
        
        # 5. 有系列名但专用刮削器失败：回退到 ThePornDB
        if self.theporndb and 'theporndb' in (self.movie_search_scrapers if content_type_hint == "Movie" else self.scene_search_scrapers):
            self.logger.info(f"回退到 ThePornDB 刮削器（保底模式）")
            try:
                results = self.theporndb.scrape_multiple(title, content_type_hint, series)
                if results:
                    # 统一限制结果数量（由管理器控制）
                    if len(results) > self.max_results:
                        self.logger.info(f"结果数量限制: {len(results)} -> {self.max_results}")
                        results = results[:self.max_results]
                    
                    self.logger.info(f"✓ ThePornDB 返回 {len(results)} 个结果")
                    
                    # 使用 ResultManager 统一处理匹配逻辑
                    results = self.result_manager.process_results_with_matching(
                        results, 
                        title, 
                        is_date_query=is_date_query(title)
                    )
                    return results
                else:
                    self.logger.info(f"✗ ThePornDB 未找到结果")
            except Exception as e:
                self.logger.error(f"✗ ThePornDB 刮削失败: {e}")
                import traceback
                self.logger.error(traceback.format_exc())
        
        self.logger.warning(f"所有刮削器都未找到结果")
        return []
    
    def scrape(self, title: str, series: Optional[str] = None, content_type_hint: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        通过标题刮削欧美内容（单个刮削模式）
        
        行为：
        - 如果只有 1 个结果：直接返回
        - 如果有多个结果：返回 None（让调用方调用 scrape_multiple 获取所有结果）
        - 如果没有结果：返回 None
        
        Args:
            title: 作品标题
            series: 系列名
            content_type_hint: 内容类型提示
        
        Returns:
            单个结果或 None
        """
        self.logger.info(f"=" * 80)
        self.logger.info(f"开始刮削欧美内容（单个刮削模式）:")
        self.logger.info(f"  原始输入 title={title}")
        self.logger.info(f"  series={series}")
        self.logger.info(f"  content_type_hint={content_type_hint}")
        self.logger.info(f"=" * 80)
        
        # 调用 scrape_multiple() 获取所有结果
        results = self.scrape_multiple(title, series, content_type_hint)
        
        if not results:
            self.logger.warning(f"未找到任何结果: title={title}, series={series}")
            return None
        
        self.logger.info(f"获得 {len(results)} 个结果")
        
        # 如果只有一个结果，直接返回
        if len(results) == 1:
            self.logger.info(f"只有一个结果，直接返回")
            result = results[0]
            
            # 翻译处理
            if self.translation_enabled and self.translator:
                result = self._translate_overview(result)
            
            return result
        
        # 多个结果：返回 None，让调用方调用 scrape_multiple
        self.logger.info(f"多个结果（{len(results)} 个），返回 None")
        return None
    
    def scrape_with_auto_select(self, title: str, series: Optional[str] = None, content_type_hint: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        通过标题刮削欧美内容（批量刮削模式 - 自动选择最佳匹配）
        
        行为：
        - 如果只有 1 个结果：直接返回
        - 如果有多个结果：使用 result_manager 自动选择最佳匹配
        
        用于批量刮削场景，自动选择最佳匹配而不需要用户干预
        
        Args:
            title: 作品标题
            series: 系列名
            content_type_hint: 内容类型提示
        
        Returns:
            最佳匹配结果或 None
        """
        self.logger.info(f"=" * 80)
        self.logger.info(f"开始刮削欧美内容（批量刮削模式 - 自动选择）:")
        self.logger.info(f"  原始输入 title={title}")
        self.logger.info(f"  series={series}")
        self.logger.info(f"  content_type_hint={content_type_hint}")
        self.logger.info(f"=" * 80)
        
        # 调用 scrape_multiple() 获取所有结果
        results = self.scrape_multiple(title, series, content_type_hint)
        
        if not results:
            self.logger.warning(f"未找到任何结果: title={title}, series={series}")
            return None
        
        self.logger.info(f"获得 {len(results)} 个结果")
        
        # 如果只有一个结果，直接返回
        if len(results) == 1:
            self.logger.info(f"只有一个结果，直接返回")
            result = results[0]
            
            # 翻译处理
            if self.translation_enabled and self.translator:
                result = self._translate_overview(result)
            
            return result
        
        # 多个结果：使用统一的结果选择逻辑
        self.logger.info(f"多个结果，使用统一选择逻辑（批量刮削模式）")
        
        # 提取搜索标题（用于匹配）
        search_title = title
        if series:
            # 如果有系列名，尝试从 title 中移除系列名前缀
            _, search_title = extract_series_and_title(title)
        
        # 检测是否是日期查询，提取目标日期
        target_date = None
        try:
            from utils.date_parser import is_date_query, parse_date_query
            if is_date_query(title):
                _, parsed_date = parse_date_query(title)
                if parsed_date:
                    target_date = parsed_date.strftime('%Y-%m-%d')
                    self.logger.info(f"检测到日期查询，目标日期: {target_date}")
        except Exception as e:
            self.logger.warning(f"日期检测失败: {e}")
        
        # 使用 result_manager 选择最佳匹配
        best_result = self.result_manager.select_best_match(
            results,
            search_title,
            exclude_keywords=['bts', 'behind the scenes', 'behind-the-scenes', 'making of', 'bonus'],
            target_date=target_date  # 传递目标日期
        )
        
        if not best_result:
            self.logger.warning(f"未找到合适的匹配结果")
            return None
        
        self.logger.info(f"选择最佳匹配: {best_result.title} (批量刮削模式)")
        
        # 翻译处理
        if self.translation_enabled and self.translator:
            best_result = self._translate_overview(best_result)
        
        return best_result
    
    def _detect_series_in_title(self, title: str) -> bool:
        """
        检测标题中是否包含系列名
        
        判断逻辑：
        - 格式为 "系列-标题"（如 BrazzersExxtra-Title）
        - 第一个词是大写字母开头
        - 包含连字符、点号或空格分隔符
        
        Args:
            title: 标题
        
        Returns:
            True 如果检测到系列名
        """
        if not title:
            return False
        
        # 尝试匹配 系列-标题 或 系列.标题 或 系列 标题 格式
        # 第一个词必须是大写字母开头
        match = re.match(r'^([A-Z][a-zA-Z0-9]+)[.\-\s]', title)
        
        if not match:
            return False
        
        potential_series = match.group(1)
        
        # 检查是否是已知的系列名或网络名
        known_series = [
            'Brazzers', 'RealityKings', 'Mofos', 'Twistys', 'DigitalPlayground',
            'BangBros', 'SexyHub', 'FakeHub', 'MileHigh', 'Babes', 'TransAngels',
            'LetsDoeIt', 'DaneJones', 'FakeAgent', 'FakeTaxi', 'PublicAgent',
            # 添加一些常见的系列名变体
            'BrazzersExxtra', 'RealityKingsPrime', 'MofosLab', 'TwistysHard',
            'PornstarsLikeItBig', 'MomsInControl', 'BigTitsAtWork', 'TeensLikeItBig'
        ]
        
        # 不区分大小写匹配
        for series in known_series:
            if potential_series.lower() == series.lower():
                return True
        
        # 如果不在已知列表中，但格式符合（大写字母开头+分隔符），也认为可能是系列名
        # 这样可以支持新的系列名
        return len(potential_series) >= 4  # 至少4个字符，避免误判
    
    def _find_scraper_for_series(self, series_name: str, content_type_hint: Optional[str] = None, is_date_query: bool = False) -> Optional[tuple[str, Any]]:
        """
        根据系列名查找对应的刮削器
        
        Args:
            series_name: 系列名（如 Girlsway, Brazzers, Evil Angel, Hustler, MariskaX）
            content_type_hint: 内容类型提示（Scene/Movie/Compilation），用于过滤刮削器
            is_date_query: 是否是日期查询（如果是，只返回支持日期搜索的刮削器）
        
        Returns:
            (刮削器名称, 刮削器对象) 或 None
        """
        if not series_name:
            return None
        
        # 规范化系列名：只保留字母和数字，转小写
        normalized_series = re.sub(r'[^a-zA-Z0-9]', '', series_name).lower()
        self.logger.info(f"[查找刮削器] 系列名: {series_name} (规范化: {normalized_series})")
        
        # 根据 content_type_hint 确定可用的刮削器列表
        if content_type_hint == "Movie":
            available_scrapers = self.movie_search_scrapers
            self.logger.info(f"[查找刮削器] 内容类型: Movie，只使用支持电影搜索的刮削器: {available_scrapers}")
        else:
            available_scrapers = self.scene_search_scrapers
            self.logger.info(f"[查找刮削器] 内容类型: {content_type_hint or 'Scene'}，使用所有刮削器")
        
        # 如果是日期查询，进一步过滤只支持日期搜索的刮削器
        if is_date_query:
            available_scrapers = available_scrapers & self.series_date_search_scrapers
            self.logger.info(f"[查找刮削器] 日期查询模式，只使用支持系列+日期搜索的刮削器: {available_scrapers}")
        
        # 0. 检查独立刮削器（MariskaX, MetArt Network, Score Group）
        if normalized_series == 'mariskax' and self.mariskax and 'mariskax' in available_scrapers:
            self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 匹配 MariskaX 刮削器")
            return ('mariskax', self.mariskax)
        
        # MetArt Network 站点（Straplez, X-Art, MetArt, SexArt, TheLifeErotic 等）
        metart_sites = ['straplez', 'xart', 'metart', 'sexart', 'thelifeerotic', 'metartnetwork', 
                        'vivthomas', 'erroticaarchives', 'domai', 'goddessnudes', 'eroticbeauty', 
                        'lovehairy', 'alsscan', 'rylskyart', 'eternaldesire', 'stunning18']
        if normalized_series in metart_sites and self.metart and 'metart_network' in available_scrapers:
            self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 匹配 MetArt Network 刮削器")
            return ('metart_network', self.metart)
        
        # Score Group 站点（107个站点 - 完整列表，包含所有官方站点）
        scoregroup_sites = [
            # 主要站点
            'pornmegaload', 'scoreland', 'scoreland2', 'xlgirls', 'scoretv',
            # 年龄分类站点
            '40somethingmag', '50plusmilfs', '60plusmilfs', '18eighteen',
            # 特色站点
            'legsex', 'naughtymag', 'bigboobbundle', 'bigboobspov',
            # Big Tit/Big Boob 系列
            'bigtitangelawhite', 'bigtithitomi', 'bigtithooker', 'bigtitterrynova', 'bigtitvenera',
            'bigtitkatiethornton', 'bigboobalexya', 'bigboobdaria', 'bigboobvanessay',
            # 个人站点
            'ashleysageellison', 'autumnjade', 'blackandstacked', 'linseysworld', 'sarennasworld',
            'crystalgunnsworld', 'bonedathome', 'bootyliciousmag', 'bustyangelique', 'bustyarianna',
            'bustydanniashe', 'bustydustystash', 'bustyinescudna', 'bustykellykay', 'bustykerrymarie',
            'bustylornamorgan', 'bustymerilyn', 'bustyoldsluts', 'bustysammieblack', 'bustylezzies',
            'cherrybrady', 'chloesworld', 'christymarks', 'daylenerio', 'desiraesworld', 'dianepoppos',
            'evanottyvideos', 'jessicaturner', 'joanabliss', 'juliamiles', 'karinahart', 'karlajames',
            'leannecrowvideos', 'megatitsminka', 'mickybells', 'millymarks', 'nataliefiore', 'nicolepeters',
            'reneerossvideos', 'roxired', 'sharizelvideos', 'stacyvandenbergboobs', 'susiewildin',
            'tawnypeaks', 'tiffanytowers', 'valoryirene',
            # 主题站点 - MILF/Granny
            'cock4stepmom', 'codivorexxx', 'creampieforgranny', 'feedherfuckher',
            'flatandfuckedmilfs', 'grannygetsafacial', 'grannylovesblack', 'grannylovesyoungcock',
            'homealonemilfs', 'hornyasianmilfs', 'ibonedyourmom', 'ifuckedtheboss', 
            'milfbundle', 'milfthreesomes', 'milftugs', 'mommystoytime',
            'naughtyfootjobs', 'naughtytugs', 'oldhornymilfs', 'pickinguppussy', 'pornloser',
            'scoreclassics', 'scorevideos', 'silversluts', 'titsandtugs', 'tnatryouts',
            'yourmomlovesanal', 'yourmomsgotbigtits', 'yourwifemymeat',
            # 种族/特色主题站点
            'analqts', 'asiancoochies', 'chicksonblackdicks', 'ebonythots', 
            'hairycoochies', 'latinacoochies', 'latinmommas',
            # 通用别名
            'scoregroup'
        ]
        if normalized_series in scoregroup_sites and self.scoregroup and 'scoregroup' in available_scrapers:
            self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 匹配 Score Group 刮削器")
            return ('scoregroup', self.scoregroup)
        
        # 1. 检查 AdultPrime 刮削器（匹配任何 AdultPrime 相关的系列名）
        # AdultPrime 包含 104 个子站点，这里简单匹配常见的站点名
        adultprime_sites = [
            'adultprime', 'clubsweethearts', 'metartnetwork', 'digitaldesire',
            '4kcfnm', 'arousins', 'bbvideo', 'beautyandthesenior', 'bifuck',
            'bionixxx', 'bondagettes', 'boundmenwanked', 'brasilbimbos', 'breedbus',
            'clubbangboys', 'clubcastings', 'cockin', 'colorclimax', 'cuckoldest',
            'daringsexhd', 'desibang', 'dirtygunther', 'dirtyhospital', 'distorded',
            'elegantraw', 'evilplaygrounds', 'familyscrew', 'fanfuckers', 'fetishprime',
            'fixxxion', 'freshpov', 'fuckingskinny', 'genderflux', 'gonzo2000',
            'granddadz', 'grandmams', 'grandparentsx', 'groupbanged', 'groupmams',
            'groupsexgames', 'hardcoreholiday', 'hollandschepassie', 'hotts',
            'industryinvaders', 'interraced', 'jimslip', 'jimsclassics', 'kingbbc',
            'ladylyne', 'larasplayground', 'lesbiansummer', 'letsgobi', 'magmafilm',
            'mamscasting', 'manalized', 'manko88', 'manupfilms', 'maturenl',
            'massagesins', 'maturevan', 'muchosexo', 'myfriendshotmom', 'mymilfz',
            'mysexykittens', 'niceandslutty', 'oldhans', 'oldiex', 'originaljav',
            'pawgqueen', 'peepleak', 'peghim', 'perfect18', 'plumperd',
            'pornstarclassics', 'pornstarslive', 'primelesbian', 'prime3dx',
            'raweuro', 'redlightsextrips', 'retroraw', 'rodox', 'salsaxxx',
            'sensualheat', 'shadowslaves', 'sinfulraw', 'sinfulsoft', 'sinfulxxx',
            'southernsins', 'submissed', 'summersinners', 'sweetfemdom',
            'sweetheartsclassics', 'swhores', 'teenrs', 'thepainfiles',
            'tonightsgirlfriend', 'trannybizarre', 'ukflashers', 'vintageclassicporn',
            'vlaamschepassie', 'vrteenrs', 'wankrs', 'yanks', 'youngbusty'
        ]
        
        if self.adultprime and normalized_series in adultprime_sites and 'adultprime' in available_scrapers:
            self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 匹配 AdultPrime 刮削器")
            return ('adultprime', self.adultprime)
        
        # 2. 检查 Gamma 刮削器（优先检查，因为 Gamma 站点更多）
        if self.gamma and hasattr(self.gamma, 'sites_config') and 'gamma' in available_scrapers:
            for key in self.gamma.sites_config.keys():
                normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
                if normalized_series == normalized_key:
                    self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 在 Gamma 配置中找到 (key={key})")
                    return ('gamma', self.gamma)
        
        # 3. 检查 MindGeek 刮削器
        if self.mindgeek and hasattr(self.mindgeek, 'sites_config') and 'mindgeek' in available_scrapers:
            for key in self.mindgeek.sites_config.keys():
                normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
                if normalized_series == normalized_key:
                    self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 在 MindGeek 配置中找到 (key={key})")
                    return ('mindgeek', self.mindgeek)
        
        # 4. 检查 Hustler 刮削器
        if self.hustler and hasattr(self.hustler, 'sites_config') and 'hustler' in available_scrapers:
            for key in self.hustler.sites_config.keys():
                normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
                if normalized_series == normalized_key:
                    self.logger.info(f"[查找刮削器] ✓ 系列 {series_name} 在 Hustler 配置中找到 (key={key})")
                    return ('hustler', self.hustler)
        
        self.logger.warning(f"[查找刮削器] ✗ 系列 {series_name} 未在任何刮削器配置中找到")
        return None
    
    def _normalize_title(self, title: str) -> str:
        """
        规范化标题（仅用于 ThePornDB）
        
        处理内容：
        - 转为小写
        - 将点号和下划线转换为连字符
        - 移除特殊字符（保留字母、数字、连字符）
        - 移除多余连字符
        - 移除常见的标记（如 [HD]、(2024) 等）
        
        示例：
        - Brazzers.Hot.Scene.Title -> brazzers-hot-scene-title
        - Brazzers-Hot-Scene-Title -> brazzers-hot-scene-title
        - Brazzers Hot Scene Title -> brazzers-hot-scene-title
        
        Args:
            title: 原始标题
        
        Returns:
            规范化后的标题（小写+连字符格式）
        """
        if not title:
            return ""
        
        # 转为小写
        normalized = title.lower().strip()
        
        # 移除常见标记
        # 移除方括号内容：[HD], [4K], [中文字幕] 等
        normalized = re.sub(r'\[.*?\]', '', normalized)
        
        # 移除圆括号内容：(2024), (1080p) 等
        normalized = re.sub(r'\((?:19|20)\d{2}\)', '', normalized)  # 年份
        normalized = re.sub(r'\((?:HD|FHD|4K|1080p|720p|480p)\)', '', normalized, flags=re.I)
        
        # 将点号和下划线转换为连字符
        normalized = normalized.replace('.', '-').replace('_', '-')
        
        # 将空格转换为连字符
        normalized = normalized.replace(' ', '-')
        
        # 移除特殊字符（保留字母、数字、连字符）
        normalized = re.sub(r'[^a-z0-9\-]', '', normalized)
        
        # 移除多余连字符（连续的连字符替换为单个）
        normalized = re.sub(r'-+', '-', normalized)
        
        # 移除首尾连字符
        normalized = normalized.strip('-')
        
        return normalized
    
    def _scrape_concurrent(self, scrapers: List[tuple]) -> List[ScrapeResult]:
        """
        并发刮削多个数据源
        
        Args:
            scrapers: 刮削器列表，格式为 [(name, scraper, title, content_type_hint, series), ...]
                     或 [(name, scraper, title, content_type_hint), ...] (向后兼容)
        
        Returns:
            刮削结果列表
        """
        results = []
        threads = []
        lock = threading.Lock()
        completed_count = [0]
        total_count = len(scrapers)
        
        def scrape_worker(name: str, scraper, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None):
            """刮削工作线程"""
            try:
                self.logger.debug(f"开始刮削 {name}: title={title}, content_type_hint={content_type_hint}, series={series}")
                
                # 检查刮削器是否支持参数
                import inspect
                if hasattr(scraper, '_scrape_impl'):
                    sig = inspect.signature(scraper._scrape_impl)
                    params = sig.parameters
                    
                    # 构建参数字典
                    kwargs = {}
                    if 'content_type_hint' in params:
                        kwargs['content_type_hint'] = content_type_hint
                    if 'series' in params and series:
                        kwargs['series'] = series
                    
                    # 调用刮削器
                    result = scraper._scrape_impl(title, **kwargs)
                else:
                    # 回退到普通 scrape 方法
                    result = scraper.scrape(title)
                
                if result:
                    result.source = name  # 标记数据来源
                    with lock:
                        results.append((name, result))
                    self.logger.info(f"✓ {name} 刮削成功: {title}")
                else:
                    self.logger.warning(f"✗ {name} 未找到数据: {title}")
            except Exception as e:
                self.logger.error(f"✗ {name} 刮削异常: {title} - {e}")
                import traceback
                self.logger.error(traceback.format_exc())
            finally:
                with lock:
                    completed_count[0] += 1
        
        # 创建并启动线程
        for item in scrapers:
            # 支持 3/4/5 元素元组（向后兼容）
            if len(item) == 5:
                name, scraper, title, content_type_hint, series = item
            elif len(item) == 4:
                name, scraper, title, content_type_hint = item
                series = None
            else:
                name, scraper, title = item
                content_type_hint = None
                series = None
            
            thread = threading.Thread(target=scrape_worker, args=(name, scraper, title, content_type_hint, series))
            thread.daemon = True
            threads.append(thread)
            thread.start()
        
        # 等待所有线程完成（设置总超时和轮询）
        total_timeout = self.config.get('network', {}).get('total_timeout', 30)
        import time
        start_time = time.time()
        poll_interval = 0.5
        
        while True:
            # 检查是否所有线程都完成
            if completed_count[0] >= total_count:
                self.logger.debug(f"所有线程已完成: {completed_count[0]}/{total_count}")
                break
            
            # 检查是否已有结果（早期退出优化）
            if results and (time.time() - start_time) > 5:
                self.logger.debug(f"已有 {len(results)} 个结果，提前返回")
                break
            
            # 检查是否超时
            if time.time() - start_time > total_timeout:
                self.logger.warning(f"刮削超时: {completed_count[0]}/{total_count} 完成")
                break
            
            # 等待一小段时间
            time.sleep(poll_interval)
        
        return results
    
    def _merge_results(self, results: List[tuple], original_title: str) -> ScrapeResult:
        """
        合并多个刮削结果（补充式策略）
        
        Args:
            results: 刮削结果列表，格式为 [(name, result), ...]
            original_title: 原始标题
        
        Returns:
            合并后的结果
        
        合并策略（补充式）：
        - 按结果顺序合并（第一个结果优先级最高）
        - 对所有字段采用"第一个非空值"策略
        - 只有当高优先级数据源的字段为空时，才使用低优先级数据源的值
        """
        # 按结果顺序合并（results 已经按优先级排序）
        # 第一个结果优先级最高
        
        # 创建合并结果
        merged = ScrapeResult()
        # 保存原始文件名到 original_title
        merged.original_title = original_title
        
        # 遍历所有结果，按顺序合并（补充式）
        for source, result in results:
            # 标量字段：使用第一个非空值
            if not merged.title and result.title:
                merged.title = result.title
            if not merged.code and result.code:
                merged.code = result.code
            # original_title 已设置为原始文件名，不再从刮削结果覆盖
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
            if not merged.poster_url and result.poster_url:
                merged.poster_url = result.poster_url
            if not merged.backdrop_url and result.backdrop_url:
                merged.backdrop_url = result.backdrop_url
            if not merged.media_type and result.media_type:
                merged.media_type = result.media_type
            if not merged.language and result.language:
                merged.language = result.language
            if not merged.country and result.country:
                merged.country = result.country
            
            # 列表字段：使用第一个非空列表（补充式，不合并）
            if not merged.actors and result.actors:
                merged.actors = result.actors
            if not merged.genres and result.genres:
                merged.genres = result.genres
            if not merged.preview_urls and result.preview_urls:
                merged.preview_urls = result.preview_urls
            if not merged.preview_video_urls and result.preview_video_urls:
                merged.preview_video_urls = result.preview_video_urls
        
        # 记录合并来源
        sources = [name for name, _ in results]
        merged.source = '+'.join(sources)
        
        self.logger.debug(
            f"合并结果: 来源={merged.source}, "
            f"演员数={len(merged.actors)}, "
            f"类型数={len(merged.genres)}, "
            f"预览图数={len(merged.preview_urls)}, "
            f"预览视频数={len(merged.preview_video_urls)}"
        )
        
        return merged
    
    def _translate_overview(self, result: ScrapeResult) -> ScrapeResult:
        """
        翻译简介字段（欧美内容只翻译简介，不翻译标题）
        
        Args:
            result: 刮削结果
        
        Returns:
            翻译后的结果
        """
        import asyncio
        
        self.logger.info("开始翻译简介字段")
        
        # 创建异步任务
        async def translate_async():
            # 只翻译 overview 字段
            if result.overview and isinstance(result.overview, str):
                # 检查是否为英语（简单判断：只包含ASCII字符和常见标点）
                if self._is_english(result.overview):
                    try:
                        translated = await self.translator.translate(result.overview, "en", "zh-CN")
                        if translated:
                            result.overview = translated
                            self.logger.info("简介翻译成功")
                        else:
                            self.logger.warning("简介翻译失败，保留原文")
                    except Exception as e:
                        self.logger.error(f"简介翻译异常: {e}")
                else:
                    self.logger.debug("简介不是英语，跳过翻译")
        
        # 运行异步任务
        try:
            asyncio.run(translate_async())
        except Exception as e:
            self.logger.error(f"翻译过程异常: {e}")
        
        return result
    
    @staticmethod
    def _is_english(text: str) -> bool:
        """
        检查文本是否为英语（简单判断）
        
        Args:
            text: 文本
        
        Returns:
            True 如果主要是英文字符
        """
        if not text:
            return False
        
        # 统计ASCII字符（字母、数字、空格、标点）的比例
        ascii_count = sum(1 for char in text if ord(char) < 128)
        total_count = len(text)
        
        # 如果ASCII字符占比超过80%，认为是英语
        return (ascii_count / total_count) > 0.8 if total_count > 0 else False
