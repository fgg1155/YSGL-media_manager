#!/usr/bin/env python3
"""
Media Scraper Plugin - 主入口
通过 stdin/stdout 与主程序通信
"""

import sys
import json
import logging
import io
from pathlib import Path
from typing import Dict, Any, Optional

# 设置 stdin/stdout 为 UTF-8 编码
sys.stdin = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8')
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', line_buffering=True)
# stderr 也设置为 UTF-8，用于进度输出
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', line_buffering=True)

# 添加当前目录到 Python 路径
sys.path.insert(0, str(Path(__file__).parent))

from core.config_loader import load_config
from core.content_type_detector import ContentTypeDetector, ContentType
from utils.date_parser import is_date_query, parse_date_query


def emit_progress(current: int, total: int, item_name: str, status: str, error: Optional[str] = None):
    """
    输出进度到 stderr（实时流式输出）
    
    Args:
        current: 当前进度
        total: 总数
        item_name: 当前处理的项目名称
        status: 状态 ("scraping", "completed", "failed", "skipped")
        error: 错误信息（可选）
    """
    progress = {
        "current": current,
        "total": total,
        "item_name": item_name,
        "status": status
    }
    if error:
        progress["error"] = error
    
    # 使用 PROGRESS: 前缀，与磁力刮削保持一致
    print(f"PROGRESS:{json.dumps(progress, ensure_ascii=False)}", file=sys.stderr, flush=True)


class PluginMain:
    """插件主入口"""
    
    def __init__(self):
        """初始化插件"""
        # 加载配置
        self.config = load_config()
        
        # 设置日志（写入文件，避免干扰 stdout）
        self._setup_logging()
        
        # 初始化组件
        self.content_detector = ContentTypeDetector()
        
        # 延迟初始化管理器（避免循环导入）
        self._jav_manager = None
        self._western_manager = None
        self._actor_manager = None
        
        self.logger.info("Plugin initialized")
    
    def _setup_logging(self):
        """设置日志"""
        log_config = self.config.get('logging', {})
        log_level = log_config.get('level', 'INFO')
        log_file = log_config.get('log_file', 'media_scraper.log')
        log_format = log_config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        
        # 配置日志到文件
        logging.basicConfig(
            level=getattr(logging, log_level),
            format=log_format,
            filename=log_file,
            filemode='a',
            encoding='utf-8'
        )
        
        self.logger = logging.getLogger(__name__)
    
    @property
    def jav_manager(self):
        """延迟加载 JAV 管理器"""
        if self._jav_manager is None:
            from managers.jav_scraper_manager import JAVScraperManager
            self._jav_manager = JAVScraperManager(self.config)
        return self._jav_manager
    
    @property
    def western_manager(self):
        """延迟加载欧美内容管理器"""
        if self._western_manager is None:
            from managers.western_scraper_manager import WesternScraperManager
            self._western_manager = WesternScraperManager(self.config)
        return self._western_manager
    
    @property
    def actor_manager(self):
        """延迟加载演员刮削管理器"""
        if self._actor_manager is None:
            from managers.actor_scraper_manager import ActorScraperManager
            self._actor_manager = ActorScraperManager(self.config)
        return self._actor_manager
    
    def run(self):
        """运行插件主循环"""
        self.logger.info("Plugin started")
        
        try:
            while True:
                # 从 stdin 读取请求
                line = sys.stdin.readline()
                if not line:
                    break
                
                line = line.strip()
                if not line:
                    continue
                
                try:
                    # 解析 JSON 请求
                    request = json.loads(line)
                    self.logger.debug(f"Received request: {request}")
                    
                    # 处理请求
                    response = self.handle_request(request)
                    
                    # 输出响应到 stdout
                    print(json.dumps(response, ensure_ascii=False))
                    sys.stdout.flush()
                    
                except json.JSONDecodeError as e:
                    self.logger.error(f"JSON decode error: {e}")
                    error_response = {
                        'success': False,
                        'error': f'Invalid JSON: {str(e)}'
                    }
                    print(json.dumps(error_response, ensure_ascii=False))
                    sys.stdout.flush()
                
                except Exception as e:
                    self.logger.exception(f"Unexpected error: {e}")
                    error_response = {
                        'success': False,
                        'error': f'Internal error: {str(e)}'
                    }
                    print(json.dumps(error_response, ensure_ascii=False))
                    sys.stdout.flush()
        
        except KeyboardInterrupt:
            self.logger.info("Plugin interrupted by user")
        
        except Exception as e:
            self.logger.exception(f"Fatal error: {e}")
            sys.exit(1)
        
        finally:
            self.logger.info("Plugin stopped")
    
    def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        处理请求
        
        Args:
            request: 请求字典，包含 action 字段
        
        Returns:
            响应字典
        """
        action = request.get('action')
        
        if action == 'info':
            return self._handle_info()
        elif action == 'get':
            return self._handle_get(request)
        elif action == 'search':
            return self._handle_search(request)
        elif action == 'scrape_actor':
            return self._handle_scrape_actor(request)
        elif action == 'batch_scrape_actors':
            return self._handle_batch_scrape_actors(request)
        elif action == 'batch_scrape_media':
            return self._handle_batch_scrape_media(request)
        else:
            return {
                'success': False,
                'error': f'Unknown action: {action}'
            }
    
    def _handle_info(self) -> Dict[str, Any]:
        """
        返回插件信息
        
        Returns:
            插件信息字典
        """
        return {
            'success': True,
            'data': {
                'id': 'media_scraper',
                'name': 'Media Scraper',
                'version': '1.0.0',
                'description': '通用媒体元数据刮削插件，支持日本AV和欧美内容',
                'author': 'Media Manager',
                'id_patterns': [
                    r'[A-Z]{2,6}-\d{3,5}',      # 普通番号
                    r'FC2-PPV-\d{5,7}',          # FC2
                    r'HEYZO-\d{4}',              # HEYZO
                    r'HEYDOUGA-\d{4}-\d{3,5}',   # HEYDOUGA
                    r'(RED|SKY|EX)-\d{3,4}',     # 东热
                ],
                'supports_search': False  # 暂不支持搜索
            }
        }
    
    def _handle_get(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        刮削单个或多个结果（自动判断）
        
        Args:
            request: 请求字典，包含：
                - id: 番号或标题
                - series: 系列名（可选，用于 Western）
                - studio: 片商名（可选，用于 JAV）
                - content_type: 内容类型提示（可选）
                - field_source: 字段来源（可选）："code"表示从番号字段来，"title"表示从标题字段来
        
        Returns:
            刮削结果字典
            - 1个结果：返回 {success: true, data: {...}}，后端直接入库
            - 多个结果：返回 {success: true, mode: 'multiple', results: [...]}，前端弹窗选择
        """
        id_or_title = request.get('id', '')
        series = request.get('series')
        studio = request.get('studio')  # 新增：获取片商名
        content_type_hint = request.get('content_type')
        field_source = request.get('field_source')  # 新增：获取字段来源
        
        # 规范化系列名：移除空格（例如 "Strap Lez" -> "StrapLez"）
        if series:
            series = series.replace(' ', '')
            self.logger.debug(f"规范化系列名: {request.get('series')} -> {series}")
        
        if not id_or_title:
            return {
                'success': False,
                'error': {
                    'category': 'invalid_input',
                    'message': {
                        'zh': '缺少 id 参数',
                        'en': 'Missing id parameter'
                    },
                    'suggestions': {
                        'zh': ['请提供番号或标题'],
                        'en': ['Please provide a code or title']
                    }
                }
            }
        
        self.logger.info(f"Scraping: {id_or_title}, series: {series}, studio: {studio}, content_type_hint: {content_type_hint}, field_source: {field_source}")
        
        try:
            # 1. 检测是否是日期查询（如 "Evilangel.26.01.23"）
            if is_date_query(id_or_title):
                parsed_series, parsed_date = parse_date_query(id_or_title)
                if parsed_series and parsed_date:
                    self.logger.info(f"检测到日期查询: series={parsed_series}, date={parsed_date.strftime('%Y-%m-%d')}")
                    # 如果解析出系列名，覆盖传入的 series 参数
                    if not series:
                        series = parsed_series
                        self.logger.info(f"使用解析出的系列名: {series}")
            
            # 2. 如果没有系列名/片商名，尝试从 id_or_title 中提取
            if not series and not studio:
                from utils.query_parser import extract_series_and_title
                extracted_series, extracted_title = extract_series_and_title(id_or_title)
                if extracted_series:
                    series = extracted_series
                    # 注意：这里不修改 id_or_title，让刮削器自己处理
                    self.logger.info(f"从标题中提取到系列名: {series}")
            
            # 3. 检测内容类型
            content_type = self.content_detector.detect(id_or_title)
            self.logger.debug(f"检测到内容类型: {content_type}")
            
            # 如果 field_source 是 "code"：
            # - 检测到 JAV：使用 JAV 流程
            # - 检测到 WESTERN 但有 studio 参数：强制使用 JAV 流程（因为 studio 是 JAV 专用）
            # - 检测到 WESTERN 且无 studio：使用 WESTERN 流程
            if field_source == 'code':
                if content_type == ContentType.JAV:
                    self.logger.info(f"字段来源为'番号'且检测到 JAV 格式，使用 JAV 刮削流程")
                elif studio:
                    # 有 studio 参数说明是 JAV，强制使用 JAV
                    content_type = ContentType.JAV
                    self.logger.info(f"字段来源为'番号'且提供了片商名，强制使用 JAV 刮削流程")
                else:
                    # 检测为 WESTERN 且无 studio，使用 WESTERN 流程
                    self.logger.info(f"字段来源为'番号'但检测为欧美内容，使用欧美刮削流程")
            
            # 4. 如果有 studio 参数，将其添加到 id_or_title 前面（用于 JAV）
            scrape_code = id_or_title
            if studio and content_type == ContentType.JAV:
                # 如果 id_or_title 已经包含片商名，不重复添加
                from utils.query_parser import extract_studio_and_code
                existing_studio, _ = extract_studio_and_code(id_or_title)
                if not existing_studio:
                    scrape_code = f"{studio}-{id_or_title}"
                    self.logger.info(f"添加片商名前缀: {scrape_code}")
            
            # 5. 调用 scrape() 方法获取结果
            if content_type == ContentType.JAV:
                # JAV 内容
                result = self.jav_manager.scrape(scrape_code)
            else:
                # 欧美内容
                result = self.western_manager.scrape(id_or_title, series=series, content_type_hint=content_type_hint)
            
            # 3. 根据返回结果判断
            if result is None:
                # 没有结果或需要多选：调用 scrape_multiple 获取所有结果
                self.logger.info(f"scrape() 返回 None，调用 scrape_multiple 获取所有结果")
                
                if content_type == ContentType.JAV:
                    results = []  # JAV 暂不支持多结果
                else:
                    results = self.western_manager.scrape_multiple(id_or_title, series=series, content_type_hint=content_type_hint)
                
                if not results:
                    # 真的没有结果
                    self.logger.warning(f"Scrape failed: {id_or_title} - No data found")
                    return {
                        'success': False,
                        'error': {
                            'category': 'not_found',
                            'message': {
                                'zh': f'未找到内容: {id_or_title}',
                                'en': f'Content not found: {id_or_title}'
                            },
                            'suggestions': {
                                'zh': [
                                    '确认番号是否正确',
                                    '尝试其他数据源',
                                    '检查番号格式（如 IPX-177）'
                                ],
                                'en': [
                                    'Verify the code is correct',
                                    'Try other data sources',
                                    'Check code format (e.g., IPX-177)'
                                ]
                            }
                        }
                    }
                else:
                    # 有多个结果：返回多结果格式
                    self.logger.info(f"找到 {len(results)} 个结果，返回多结果格式")
                    
                    # 转换所有结果为字典
                    results_data = []
                    for r in results:
                        data = r.to_dict()
                        
                        # 映射 mosaic 到 media_type
                        if 'mosaic' in data and data['mosaic']:
                            if data['mosaic'] == '无码':
                                data['media_type'] = 'Uncensored'
                            elif data['mosaic'] == '有码':
                                data['media_type'] = 'Censored'
                            del data['mosaic']
                        elif 'mosaic' in data:
                            del data['mosaic']
                        
                        results_data.append(data)
                    
                    return {
                        'success': True,
                        'mode': 'multiple',
                        'total_count': len(results_data),
                        'results': results_data
                    }
            else:
                # 有单个结果：返回单结果格式
                self.logger.info(f"Scrape success: {id_or_title}, 找到 1 个结果")
                data = result.to_dict()
                
                # 映射 mosaic 到 media_type
                if 'mosaic' in data and data['mosaic']:
                    if data['mosaic'] == '无码':
                        data['media_type'] = 'Uncensored'
                    elif data['mosaic'] == '有码':
                        data['media_type'] = 'Censored'
                    del data['mosaic']
                elif 'mosaic' in data:
                    del data['mosaic']
                
                return {
                    'success': True,
                    'data': data
                }
        
        except Exception as e:
            self.logger.exception(f"Scrape error: {id_or_title}")
            return {
                'success': False,
                'error': {
                    'category': 'unknown',
                    'message': {
                        'zh': f'刮削失败: {str(e)}',
                        'en': f'Scrape failed: {str(e)}'
                    },
                    'suggestions': {
                        'zh': [
                            '查看日志获取详细信息',
                            '如问题持续，请联系开发者'
                        ],
                        'en': [
                            'Check logs for details',
                            'Contact developer if issue persists'
                        ]
                    }
                }
            }
    
    def _handle_search(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        搜索（暂不实现）
        
        Args:
            request: 请求字典
        
        Returns:
            错误响应
        """
        return {
            'success': False,
            'error': 'Search not implemented yet'
        }
    
    def _handle_scrape_actor(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        刮削单个演员信息
        
        Args:
            request: 请求字典，包含 actor_name 字段
        
        Returns:
            演员信息字典（支持结构化错误）
        """
        actor_name = request.get('actor_name', '')
        if not actor_name:
            return {
                'success': False,
                'error': {
                    'category': 'invalid_input',
                    'message': {
                        'zh': '缺少 actor_name 参数',
                        'en': 'Missing actor_name parameter'
                    },
                    'suggestions': {
                        'zh': ['请提供演员名称'],
                        'en': ['Please provide actor name']
                    }
                }
            }
        
        self.logger.info(f"Scraping actor: {actor_name}")
        
        try:
            result = self.actor_manager.scrape_actor(actor_name)
            
            if result:
                self.logger.info(f"Actor scrape success: {actor_name}")
                return {
                    'success': True,
                    'data': result
                }
            else:
                self.logger.warning(f"Actor scrape failed: {actor_name} - No data found")
                # 返回结构化错误
                return {
                    'success': False,
                    'error': {
                        'category': 'not_found',
                        'message': {
                            'zh': f'未找到演员信息: {actor_name}',
                            'en': f'Actor not found: {actor_name}'
                        },
                        'suggestions': {
                            'zh': [
                                '确认演员名称是否正确',
                                '尝试使用日文名称',
                                '尝试其他数据源'
                            ],
                            'en': [
                                'Verify the actor name is correct',
                                'Try using Japanese name',
                                'Try other data sources'
                            ]
                        }
                    }
                }
        
        except Exception as e:
            self.logger.exception(f"Actor scrape error: {actor_name}")
            # 返回结构化错误
            return {
                'success': False,
                'error': {
                    'category': 'unknown',
                    'message': {
                        'zh': f'刮削失败: {str(e)}',
                        'en': f'Scrape failed: {str(e)}'
                    },
                    'suggestions': {
                        'zh': [
                            '查看日志获取详细信息',
                            '如问题持续，请联系开发者'
                        ],
                        'en': [
                            'Check logs for details',
                            'Contact developer if issue persists'
                        ]
                    }
                }
            }
    
    def _handle_batch_scrape_actors(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        批量刮削演员信息
        
        Args:
            request: 请求字典，包含 actor_names 字段（列表）和 concurrent 字段（布尔值）
        
        Returns:
            批量刮削结果
        """
        actor_names = request.get('actor_names', [])
        concurrent = request.get('concurrent', False)
        
        if not actor_names:
            return {
                'success': False,
                'error': 'Missing actor_names parameter'
            }
        
        if not isinstance(actor_names, list):
            return {
                'success': False,
                'error': 'actor_names must be a list'
            }
        
        self.logger.info(f"Batch scraping {len(actor_names)} actors (concurrent={concurrent})")
        
        try:
            if concurrent:
                # 并发模式：使用线程池
                results = self._batch_scrape_actors_concurrent(actor_names)
            else:
                # 串行模式：逐个处理（带进度）
                results = self._batch_scrape_actors_sequential(actor_names)
            
            self.logger.info(f"Batch scrape complete: {len(results)} actors")
            return {
                'success': True,
                'data': results
            }
        
        except Exception as e:
            self.logger.exception(f"Batch scrape error")
            return {
                'success': False,
                'error': str(e)
            }
    
    def _batch_scrape_actors_sequential(self, actor_names: list) -> list:
        """
        串行批量刮削演员（带进度）
        
        Args:
            actor_names: 演员名称列表
        
        Returns:
            演员信息列表
        """
        results = []
        total = len(actor_names)
        
        for i, actor_name in enumerate(actor_names):
            # 发送进度：开始刮削
            emit_progress(i + 1, total, actor_name, "scraping")
            
            try:
                result = self.actor_manager.scrape_actor(actor_name)
                if result:
                    results.append(result)
                    emit_progress(i + 1, total, actor_name, "completed")
                else:
                    results.append({'name': actor_name})
                    emit_progress(i + 1, total, actor_name, "failed", "未找到演员信息")
            except Exception as e:
                self.logger.exception(f"Scrape error for actor: {actor_name}")
                results.append({'name': actor_name})
                emit_progress(i + 1, total, actor_name, "failed", str(e))
        
        return results
    
    def _batch_scrape_actors_concurrent(self, actor_names: list) -> list:
        """
        并发批量刮削演员
        
        Args:
            actor_names: 演员名称列表
        
        Returns:
            演员信息列表
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading
        
        # 获取并发数配置（默认5个线程）
        max_workers = self.config.get('actor_scraper', {}).get('concurrent', 5)
        self.logger.info(f"Using {max_workers} concurrent workers for actors")
        
        results = []
        total = len(actor_names)
        completed_count = 0
        progress_lock = threading.Lock()
        
        def scrape_with_progress(actor_name):
            nonlocal completed_count
            
            # 发送进度：开始刮削（线程安全）
            with progress_lock:
                emit_progress(completed_count + 1, total, actor_name, "scraping")
            
            try:
                result = self.actor_manager.scrape_actor(actor_name)
                
                with progress_lock:
                    completed_count += 1
                    if result:
                        emit_progress(completed_count, total, actor_name, "completed")
                        return result
                    else:
                        emit_progress(completed_count, total, actor_name, "failed", "未找到演员信息")
                        return {'name': actor_name}
            except Exception as e:
                with progress_lock:
                    completed_count += 1
                    emit_progress(completed_count, total, actor_name, "failed", str(e))
                return {'name': actor_name}
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有任务
            future_to_actor = {
                executor.submit(scrape_with_progress, actor_name): actor_name
                for actor_name in actor_names
            }
            
            # 收集结果（按完成顺序）
            for future in as_completed(future_to_actor):
                actor_name = future_to_actor[future]
                try:
                    result = future.result()
                    if result:
                        results.append(result)
                    else:
                        results.append({'name': actor_name})
                except Exception as e:
                    self.logger.exception(f"Concurrent scrape error for actor: {actor_name}")
                    results.append({'name': actor_name})
        
        return results
    
    def _handle_batch_scrape_media(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        批量刮削媒体信息
        
        Args:
            request: 请求字典，包含：
                - media_list: 媒体列表
                - concurrent: 是否并发（布尔值）
                - scrape_mode: 刮削方式（code/title/series_date/series_title）
                - content_type: 内容类型（Scene/Movie）
        
        Returns:
            批量刮削结果
        """
        media_list = request.get('media_list', [])
        concurrent = request.get('concurrent', False)
        scrape_mode = request.get('scrape_mode', 'code')  # 默认使用 code 模式
        content_type = request.get('content_type', 'Scene')  # 默认 Scene
        
        if not media_list:
            return {
                'success': False,
                'error': 'Missing media_list parameter'
            }
        
        if not isinstance(media_list, list):
            return {
                'success': False,
                'error': 'media_list must be a list'
            }
        
        self.logger.info(f"Batch scraping {len(media_list)} media items (concurrent={concurrent}, scrape_mode={scrape_mode}, content_type={content_type})")
        
        try:
            if concurrent:
                # 并发模式：使用线程池
                results = self._batch_scrape_concurrent(media_list, scrape_mode, content_type)
            else:
                # 串行模式：逐个处理
                results = self._batch_scrape_sequential(media_list, scrape_mode, content_type)
            
            # 统计结果
            success_count = sum(1 for r in results if r.get('success'))
            failed_count = len(results) - success_count
            
            self.logger.info(f"Batch scrape complete: {success_count} success, {failed_count} failed")
            return {
                'success': True,
                'data': results
            }
        
        except Exception as e:
            self.logger.exception(f"Batch scrape error")
            return {
                'success': False,
                'error': str(e)
            }
    
    def _batch_scrape_sequential(self, media_list: list, scrape_mode: str = 'code', content_type: str = 'Scene') -> list:
        """
        串行批量刮削
        
        Args:
            media_list: 媒体列表
            scrape_mode: 刮削方式（code/title/series_date/series_title）
            content_type: 内容类型（Scene/Movie）
        
        Returns:
            刮削结果列表
        """
        results = []
        total = len(media_list)
        
        for i, media_info in enumerate(media_list):
            media_id = media_info.get('id', '')
            code = media_info.get('code', '') or media_info.get('title', '')
            
            # 发送进度：开始刮削
            emit_progress(i + 1, total, code or media_id, "scraping")
            
            result = self._scrape_single_media(media_info, scrape_mode, content_type)
            results.append(result)
            
            # 发送进度：完成或失败
            if result.get('success'):
                emit_progress(i + 1, total, code or media_id, "completed")
            else:
                emit_progress(i + 1, total, code or media_id, "failed", result.get('error'))
        
        return results
    
    def _batch_scrape_concurrent(self, media_list: list, scrape_mode: str = 'code', content_type: str = 'Scene') -> list:
        """
        并发批量刮削
        
        Args:
            media_list: 媒体列表
            scrape_mode: 刮削方式（code/title/series_date/series_title）
            content_type: 内容类型（Scene/Movie）
        
        Returns:
            刮削结果列表
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading
        
        # 获取并发数配置（默认5个线程）
        max_workers = self.config.get('scraper', {}).get('max_concurrent_workers', 5)
        self.logger.info(f"Using {max_workers} concurrent workers")
        
        results = []
        total = len(media_list)
        completed_count = 0
        progress_lock = threading.Lock()
        
        def scrape_with_progress(media_info, index):
            nonlocal completed_count
            media_id = media_info.get('id', '')
            code = media_info.get('code', '') or media_info.get('title', '')
            
            # 发送进度：开始刮削（线程安全）
            with progress_lock:
                emit_progress(completed_count + 1, total, code or media_id, "scraping")
            
            result = self._scrape_single_media(media_info, scrape_mode, content_type)
            
            # 发送进度：完成或失败（线程安全）
            with progress_lock:
                completed_count += 1
                if result.get('success'):
                    emit_progress(completed_count, total, code or media_id, "completed")
                else:
                    emit_progress(completed_count, total, code or media_id, "failed", result.get('error'))
            
            return result
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有任务
            future_to_media = {
                executor.submit(scrape_with_progress, media_info, i): media_info
                for i, media_info in enumerate(media_list)
            }
            
            # 收集结果（按完成顺序）
            for future in as_completed(future_to_media):
                media_info = future_to_media[future]
                try:
                    result = future.result()
                    results.append(result)
                except Exception as e:
                    media_id = media_info.get('id', '')
                    self.logger.exception(f"Concurrent scrape error: {media_id}")
                    results.append({
                        'media_id': media_id,
                        'success': False,
                        'error': f'Concurrent execution error: {str(e)}'
                    })
        
        return results
    
    def _scrape_single_media(self, media_info: Dict[str, Any], scrape_mode: str = 'code', content_type: str = 'Scene') -> Dict[str, Any]:
        """
        刮削单个媒体项（用于批量刮削）
        
        注意：批量刮削时使用自动选择逻辑，多个结果时自动选择最佳匹配
        
        Args:
            media_info: 媒体信息字典，包含：
                - id: 媒体ID
                - code: 番号或识别号（可选）
                - title: 标题（可选）
                - series: 系列名（可选）
                - release_date: 发布日期（可选）
            scrape_mode: 刮削方式（code/title/series_date/series_title/auto）
            content_type: 内容类型（Scene/Movie）
        
        Returns:
            刮削结果字典
        
        逻辑：
        - auto: 自动判断（优先级：code > series+date > series+title > title）
        - code: 使用 code 字段
        - title: 使用 title 字段
        - series_date: 使用 系列.YY.MM.DD 格式
        - series_title: 使用 系列-标题 格式
        """
        media_id = media_info.get('id', '')
        code = media_info.get('code', '')
        title = media_info.get('title', '')
        series = media_info.get('series')  # 获取系列名
        release_date = media_info.get('release_date')  # 获取发布日期
        
        # 规范化系列名：移除空格（例如 "Strap Lez" -> "StrapLez"）
        if series:
            original_series = series
            series = series.replace(' ', '')
            if original_series != series:
                self.logger.debug(f"规范化系列名: {original_series} -> {series}")
        
        # 如果是 auto 模式，根据字段自动判断
        if scrape_mode == 'auto':
            if code:
                scrape_mode = 'code'
                self.logger.info(f"Auto mode: 检测到 code 字段，使用 code 模式")
            elif series and release_date:
                scrape_mode = 'series_date'
                self.logger.info(f"Auto mode: 检测到 series+date 字段，使用 series_date 模式")
            elif series and title:
                scrape_mode = 'series_title'
                self.logger.info(f"Auto mode: 检测到 series+title 字段，使用 series_title 模式")
            elif title:
                scrape_mode = 'title'
                self.logger.info(f"Auto mode: 检测到 title 字段，使用 title 模式")
            else:
                self.logger.warning(f"Auto mode: 无法判断刮削模式，跳过")
                return {
                    'media_id': media_id,
                    'success': False,
                    'error': 'No valid fields for scraping'
                }
        
        # 根据 scrape_mode 选择搜索关键词
        search_key = None
        
        if scrape_mode == 'code':
            # code 模式：使用 code 字段
            search_key = code
        elif scrape_mode == 'title':
            # title 模式：使用 title 字段
            search_key = title
        elif scrape_mode == 'series_date':
            # series_date 模式：生成 系列.YY.MM.DD 格式
            if series and release_date:
                from utils.query_parser import generate_series_date_query
                search_key = generate_series_date_query(series, release_date)
                if not search_key:
                    self.logger.warning(f"无法生成 series_date 查询，回退到 title 模式")
                    search_key = title
            else:
                self.logger.warning(f"缺少 series 或 release_date，回退到 title 模式")
                search_key = title
        elif scrape_mode == 'series_title':
            # series_title 模式：生成 系列-标题 格式
            if series and title:
                from utils.query_parser import generate_series_title_query
                search_key = generate_series_title_query(series, title)
                if not search_key:
                    self.logger.warning(f"无法生成 series_title 查询，回退到 title 模式")
                    search_key = title
            else:
                self.logger.warning(f"缺少 series 或 title，回退到 title 模式")
                search_key = title
        else:
            # 未知模式：回退到 code 或 title
            self.logger.warning(f"未知的 scrape_mode: {scrape_mode}，回退到默认模式")
            search_key = code if code else title
        
        if not search_key:
            self.logger.warning(f"Skipping media {media_id}: no search key generated")
            return {
                'media_id': media_id,
                'success': False,
                'error': 'No search key generated'
            }
        
        self.logger.info(f"Scraping media {media_id}: {search_key} (mode={scrape_mode}, content_type={content_type}), series: {series}")
        
        try:
            # 1. 检测是否是日期查询（如 "Evilangel.26.01.23"）
            if is_date_query(search_key):
                parsed_series, parsed_date = parse_date_query(search_key)
                if parsed_series and parsed_date:
                    self.logger.info(f"检测到日期查询: series={parsed_series}, date={parsed_date.strftime('%Y-%m-%d')}")
                    # 如果解析出系列名，覆盖传入的 series 参数
                    if not series:
                        series = parsed_series
                        self.logger.info(f"使用解析出的系列名: {series}")
            
            # 2. 如果没有系列名，尝试从 search_key 中提取（如 "BrazzersExxtra-Title"）
            if not series:
                from utils.query_parser import extract_series_and_title
                extracted_series, extracted_title = extract_series_and_title(search_key)
                if extracted_series:
                    series = extracted_series
                    self.logger.info(f"从标题中提取到系列名: {series}")
            
            # 3. 检测内容类型
            # 如果 scrape_mode 是 'code'，强制使用 JAV 流程
            if scrape_mode == 'code':
                detected_content_type = ContentType.JAV
                self.logger.info(f"刮削模式为'code'，强制使用 JAV 刮削流程")
            else:
                detected_content_type = self.content_detector.detect(search_key)
            
            # 4. 根据类型选择管理器
            if detected_content_type == ContentType.JAV:
                result = self.jav_manager.scrape(search_key)
            else:
                # 批量刮削：使用自动选择逻辑（传递 series 和 content_type 参数）
                result = self.western_manager.scrape_with_auto_select(search_key, series=series, content_type_hint=content_type)
            
            if result:
                data = result.to_dict()
                
                # 映射 mosaic 到 media_type
                if 'mosaic' in data and data['mosaic']:
                    if data['mosaic'] == '无码':
                        data['media_type'] = 'Uncensored'
                    elif data['mosaic'] == '有码':
                        data['media_type'] = 'Censored'
                    # 移除 mosaic 字段（已映射到 media_type）
                    del data['mosaic']
                
                self.logger.info(f"Scrape success: {media_id} - {search_key}")
                return {
                    'media_id': media_id,
                    'success': True,
                    'data': data
                }
            else:
                self.logger.warning(f"Scrape failed: {media_id} - {search_key}")
                return {
                    'media_id': media_id,
                    'success': False,
                    'error': f'未找到内容: {search_key}'
                }
        
        except Exception as e:
            self.logger.exception(f"Scrape error: {media_id} - {search_key}")
            return {
                'media_id': media_id,
                'success': False,
                'error': str(e)
            }


def main():
    """主函数"""
    plugin = PluginMain()
    plugin.run()


if __name__ == '__main__':
    main()
