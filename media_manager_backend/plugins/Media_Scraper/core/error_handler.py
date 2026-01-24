"""
错误处理核心模块
提供错误分类、双语消息生成、建议生成和错误聚合功能
"""

import logging
from typing import Dict, List, Optional, Any
from enum import Enum
from dataclasses import dataclass, field
from datetime import datetime

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from web.exceptions import (
    ScraperError, NetworkError, MovieNotFoundError, MovieDuplicateError,
    SiteBlocked, SitePermissionError, CredentialError, WebsiteError
)


logger = logging.getLogger(__name__)


class ErrorCategory(Enum):
    """错误分类枚举"""
    NETWORK_ERROR = "network_error"
    PROXY_REQUIRED = "proxy_required"
    REGIONAL_RESTRICTION = "regional_restriction"
    NOT_FOUND = "not_found"
    SITE_ERROR = "site_error"
    PERMISSION_ERROR = "permission_error"
    CREDENTIAL_ERROR = "credential_error"
    DUPLICATE_ERROR = "duplicate_error"
    UNKNOWN = "unknown"


@dataclass
class StructuredError:
    """结构化错误对象（用于 JSON 序列化）"""
    category: ErrorCategory
    source: str
    code: str
    message_zh: str
    message_en: str
    suggestions_zh: List[str] = field(default_factory=list)
    suggestions_en: List[str] = field(default_factory=list)
    http_status: Optional[int] = None
    timestamp: datetime = field(default_factory=datetime.now)
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典（用于 JSON 序列化）"""
        return {
            'category': self.category.value,
            'source': self.source,
            'code': self.code,
            'message': {
                'zh': self.message_zh,
                'en': self.message_en
            },
            'suggestions': {
                'zh': self.suggestions_zh,
                'en': self.suggestions_en
            },
            'http_status': self.http_status,
            'timestamp': self.timestamp.isoformat()
        }


class ErrorHandler:
    """错误处理器 - 负责错误分类、消息生成和建议生成"""
    
    def __init__(self, config: Dict[str, Any], logger: logging.Logger = None):
        """
        初始化错误处理器
        
        Args:
            config: 配置字典
            logger: 日志记录器（可选）
        """
        self.config = config
        self.logger = logger or logging.getLogger(__name__)
    
    def handle_exception(
        self, 
        exception: Exception, 
        source: str, 
        code: str,
        http_status: Optional[int] = None
    ) -> StructuredError:
        """
        处理异常，生成结构化错误
        
        Args:
            exception: 捕获的异常
            source: 数据源名称
            code: 番号或标题
            http_status: HTTP 状态码（可选）
        
        Returns:
            StructuredError 对象
        """
        # 1. 错误分类
        category = self._categorize_error(exception, http_status)
        
        # 2. 获取双语消息
        if isinstance(exception, ScraperError):
            message_zh = exception.message_zh
            message_en = exception.message_en
        else:
            message_zh = str(exception)
            message_en = str(exception)
        
        # 3. 生成建议
        suggestions_zh, suggestions_en = self._generate_suggestions(
            category, exception, source, http_status
        )
        
        # 4. 记录日志
        self._log_error(exception, source, code, category, http_status)
        
        # 5. 创建结构化错误
        return StructuredError(
            category=category,
            source=source,
            code=code,
            message_zh=message_zh,
            message_en=message_en,
            suggestions_zh=suggestions_zh,
            suggestions_en=suggestions_en,
            http_status=http_status
        )
    
    def _detect_region_restriction(self, exception: Exception, http_status: Optional[int] = None) -> Optional[str]:
        """
        从错误消息中检测地域限制信息
        
        Args:
            exception: 异常对象
            http_status: HTTP 状态码（可选）
        
        Returns:
            检测到的地域要求（如 'japan', 'japan_or_us', 'any'），如果未检测到返回 None
        """
        error_msg = str(exception).lower()
        
        # 地域限制关键词检测
        region_keywords = {
            'japan': [
                'japan only', '日本限定', '日本地区', '日本のみ', 'japanese ip',
                'jp only', 'japan ip', '仅限日本', '只限日本', 'from japan'
            ],
            'us': [
                'us only', '美国限定', '美国地区', 'us ip', 'united states',
                'american ip', '仅限美国', '只限美国', 'from us'
            ],
            'general': [
                'not available in your region', 'region', 'geo', 'location',
                '地区', '区域', '地域', 'geographic', 'country',
                'not available in your country', 'blocked in your region'
            ]
        }
        
        # 检测日本地区限制
        for keyword in region_keywords['japan']:
            if keyword in error_msg:
                return 'japan'
        
        # 检测美国地区限制
        for keyword in region_keywords['us']:
            if keyword in error_msg:
                return 'us'
        
        # 检测一般地域限制（未指定具体地区）
        for keyword in region_keywords['general']:
            if keyword in error_msg:
                return 'any'
        
        # HTTP 451 通常表示地域限制
        if http_status == 451:
            return 'any'
        
        return None
    
    def _categorize_error(
        self, 
        exception: Exception, 
        http_status: Optional[int] = None
    ) -> ErrorCategory:
        """
        错误分类逻辑
        
        Args:
            exception: 异常对象
            http_status: HTTP 状态码（可选）
        
        Returns:
            错误分类
        """
        # 根据异常类型分类
        if isinstance(exception, NetworkError):
            return ErrorCategory.NETWORK_ERROR
        elif isinstance(exception, SiteBlocked):
            # 检测是否为地域限制
            region = self._detect_region_restriction(exception, http_status)
            if region:
                return ErrorCategory.REGIONAL_RESTRICTION
            else:
                return ErrorCategory.PROXY_REQUIRED
        elif isinstance(exception, MovieNotFoundError):
            return ErrorCategory.NOT_FOUND
        elif isinstance(exception, MovieDuplicateError):
            return ErrorCategory.DUPLICATE_ERROR
        elif isinstance(exception, SitePermissionError):
            return ErrorCategory.PERMISSION_ERROR
        elif isinstance(exception, CredentialError):
            return ErrorCategory.CREDENTIAL_ERROR
        elif isinstance(exception, WebsiteError):
            return ErrorCategory.SITE_ERROR
        
        # 根据 HTTP 状态码分类
        if http_status:
            if http_status == 403:
                # 403 可能是代理问题或地域限制，需要进一步检测
                region = self._detect_region_restriction(exception, http_status)
                if region:
                    return ErrorCategory.REGIONAL_RESTRICTION
                else:
                    return ErrorCategory.PROXY_REQUIRED
            elif http_status == 404:
                return ErrorCategory.NOT_FOUND
            elif http_status == 401 or http_status == 407:
                return ErrorCategory.CREDENTIAL_ERROR
            elif http_status == 451:
                return ErrorCategory.REGIONAL_RESTRICTION
            elif http_status >= 500:
                return ErrorCategory.SITE_ERROR
        
        return ErrorCategory.UNKNOWN
    
    def _generate_suggestions(
        self, 
        category: ErrorCategory, 
        exception: Exception,
        source: str,
        http_status: Optional[int] = None
    ) -> tuple[List[str], List[str]]:
        """
        生成可操作的建议（简洁、友好的前端提示）
        
        Args:
            category: 错误分类
            exception: 异常对象
            source: 数据源名称
            http_status: HTTP 状态码（可选）
        
        Returns:
            (中文建议列表, 英文建议列表)
        """
        network_config = self.config.get('network', {})
        proxy_server = network_config.get('proxy_server')
        
        if category == ErrorCategory.NETWORK_ERROR:
            return (
                [
                    '🔌 检查网络连接',
                    '🔄 稍后重试'
                ],
                [
                    '🔌 Check network connection',
                    '🔄 Try again later'
                ]
            )
        
        elif category == ErrorCategory.PROXY_REQUIRED:
            if proxy_server:
                # 已配置代理 - 简化提示
                return (
                    [
                        f'🔧 当前代理: {proxy_server}',
                        '✅ 确认代理正常运行',
                        '🔄 或尝试更换代理'
                    ],
                    [
                        f'🔧 Current proxy: {proxy_server}',
                        '✅ Ensure proxy is running',
                        '🔄 Or try different proxy'
                    ]
                )
            else:
                # 未配置代理 - 精简配置指引
                return (
                    [
                        f'🚫 {source} 需要代理访问',
                        '⚙️ 请在设置中配置代理',
                        '💡 推荐使用日本或美国代理'
                    ],
                    [
                        f'🚫 {source} requires proxy',
                        '⚙️ Configure proxy in settings',
                        '💡 Use Japan or US proxy'
                    ]
                )
        
        elif category == ErrorCategory.REGIONAL_RESTRICTION:
            # 区域限制 - 根据检测到的地域提供精准建议
            region = self._detect_region_restriction(exception, http_status)
            source_lower = source.lower()
            
            if source_lower == 'fanza' or region == 'japan':
                return (
                    [
                        f'🌏 {source} 仅限日本地区访问',
                        '🇯🇵 必须使用日本 IP 代理'
                    ],
                    [
                        f'🌏 {source} Japan only',
                        '🇯🇵 Must use Japan IP proxy'
                    ]
                )
            elif region == 'us':
                return (
                    [
                        f'🌏 {source} 仅限美国地区访问',
                        '🇺🇸 必须使用美国 IP 代理'
                    ],
                    [
                        f'🌏 {source} US only',
                        '🇺🇸 Must use US IP proxy'
                    ]
                )
            else:
                return (
                    [
                        f'🌏 {source} 限制当前地区访问',
                        '🔧 请使用代理或 VPN'
                    ],
                    [
                        f'🌏 {source} region restricted',
                        '🔧 Use proxy or VPN'
                    ]
                )
        
        elif category == ErrorCategory.NOT_FOUND:
            return (
                [
                    '🔍 确认番号是否正确',
                    '🔄 尝试其他数据源'
                ],
                [
                    '🔍 Verify the code',
                    '🔄 Try other sources'
                ]
            )
        
        elif category == ErrorCategory.DUPLICATE_ERROR:
            return (
                [
                    '⚠️ 搜索结果有多个匹配',
                    '✏️ 使用更精确的番号'
                ],
                [
                    '⚠️ Multiple matches found',
                    '✏️ Use more specific code'
                ]
            )
        
        elif category == ErrorCategory.CREDENTIAL_ERROR:
            return (
                [
                    f'🔐 {source} 需要登录',
                    '⚙️ 请在设置中配置 Cookies'
                ],
                [
                    f'🔐 {source} requires login',
                    '⚙️ Configure cookies in settings'
                ]
            )
        
        elif category == ErrorCategory.SITE_ERROR:
            return (
                [
                    f'⚠️ {source} 服务器错误',
                    '🔄 稍后重试或换其他源'
                ],
                [
                    f'⚠️ {source} server error',
                    '🔄 Retry or try other sources'
                ]
            )
        
        else:  # UNKNOWN
            return (
                [
                    '❓ 未知错误',
                    '📋 查看日志了解详情'
                ],
                [
                    '❓ Unknown error',
                    '📋 Check logs for details'
                ]
            )
    
    def _log_error(
        self,
        exception: Exception,
        source: str,
        code: str,
        category: ErrorCategory,
        http_status: Optional[int] = None
    ):
        """
        记录错误日志
        
        Args:
            exception: 异常对象
            source: 数据源名称
            code: 番号或标题
            category: 错误分类
            http_status: HTTP 状态码（可选）
        """
        log_msg = f"[{category.value}] {source}: {code} - {exception}"
        if http_status:
            log_msg += f" (HTTP {http_status})"
        
        self.logger.error(log_msg)
        
        # 记录详细的堆栈跟踪（仅在 DEBUG 模式）
        if self.logger.isEnabledFor(logging.DEBUG):
            self.logger.debug(f"Exception details:", exc_info=exception)


class ErrorAggregator:
    """错误聚合器 - 收集和汇总多个数据源的错误"""
    
    def __init__(self):
        """初始化错误聚合器"""
        self.errors: List[StructuredError] = []
    
    def add_error(self, error: StructuredError):
        """
        添加错误
        
        Args:
            error: 结构化错误对象
        """
        self.errors.append(error)
    
    def has_errors(self) -> bool:
        """
        是否有错误
        
        Returns:
            True 如果有错误
        """
        return len(self.errors) > 0
    
    def get_error_count(self) -> int:
        """
        获取错误数量
        
        Returns:
            错误数量
        """
        return len(self.errors)
    
    def get_summary(self) -> Dict[str, Any]:
        """
        生成错误摘要
        
        Returns:
            错误摘要字典
        """
        if not self.errors:
            return {}
        
        # 统计失败的数据源
        failed_sources = list(set(e.source for e in self.errors))
        
        # 按分类分组
        by_category = {}
        for error in self.errors:
            category = error.category.value
            if category not in by_category:
                by_category[category] = []
            by_category[category].append(error.source)
        
        # 生成摘要消息
        summary_zh = f"共 {len(failed_sources)} 个数据源失败: {', '.join(failed_sources)}"
        summary_en = f"{len(failed_sources)} data source(s) failed: {', '.join(failed_sources)}"
        
        # 收集所有建议（去重）
        all_suggestions_zh = []
        all_suggestions_en = []
        for error in self.errors:
            all_suggestions_zh.extend(error.suggestions_zh)
            all_suggestions_en.extend(error.suggestions_en)
        
        # 去重并保持顺序
        unique_suggestions_zh = list(dict.fromkeys(all_suggestions_zh))
        unique_suggestions_en = list(dict.fromkeys(all_suggestions_en))
        
        return {
            'total_errors': len(self.errors),
            'failed_sources': failed_sources,
            'summary': {
                'zh': summary_zh,
                'en': summary_en
            },
            'by_category': by_category,
            'suggestions': {
                'zh': unique_suggestions_zh,
                'en': unique_suggestions_en
            },
            'errors': [e.to_dict() for e in self.errors]
        }
    
    def get_consolidated_suggestions(self) -> Dict[str, List[str]]:
        """
        获取合并后的建议列表（去重）
        
        Returns:
            {'zh': [...], 'en': [...]}
        """
        all_suggestions_zh = []
        all_suggestions_en = []
        
        for error in self.errors:
            all_suggestions_zh.extend(error.suggestions_zh)
            all_suggestions_en.extend(error.suggestions_en)
        
        # 去重并保持顺序
        return {
            'zh': list(dict.fromkeys(all_suggestions_zh)),
            'en': list(dict.fromkeys(all_suggestions_en))
        }
    
    def clear(self):
        """清空所有错误"""
        self.errors.clear()


if __name__ == '__main__':
    # 测试用例
    print("=== ErrorHandler 测试 ===\n")
    
    config = {
        'network': {
            'proxy_server': 'http://127.0.0.1:7890'
        }
    }
    
    handler = ErrorHandler(config)
    
    # 测试 1: NetworkError
    try:
        raise NetworkError("请求超时: https://example.com", "Request timeout: https://example.com")
    except Exception as e:
        error = handler.handle_exception(e, 'fanza', 'IPX-177')
        print(f"✓ NetworkError 测试:")
        print(f"  分类: {error.category.value}")
        print(f"  中文消息: {error.message_zh}")
        print(f"  英文消息: {error.message_en}")
        print(f"  建议数: {len(error.suggestions_zh)}")
        print()
    
    # 测试 2: SiteBlocked
    try:
        raise SiteBlocked("javlibrary: 站点封锁", "javlibrary: Site blocked", "javlibrary")
    except Exception as e:
        error = handler.handle_exception(e, 'javlibrary', 'IPX-177')
        print(f"✓ SiteBlocked 测试:")
        print(f"  分类: {error.category.value}")
        print(f"  建议: {error.suggestions_zh[0]}")
        print()
    
    # 测试 3: ErrorAggregator
    aggregator = ErrorAggregator()
    aggregator.add_error(error)
    
    try:
        raise MovieNotFoundError('javbus', 'IPX-177')
    except Exception as e:
        error2 = handler.handle_exception(e, 'javbus', 'IPX-177')
        aggregator.add_error(error2)
    
    summary = aggregator.get_summary()
    print(f"✓ ErrorAggregator 测试:")
    print(f"  总错误数: {summary['total_errors']}")
    print(f"  失败数据源: {summary['failed_sources']}")
    print(f"  摘要: {summary['summary']['zh']}")
    print()
    
    print("=== 测试完成 ===")
