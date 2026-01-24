"""
网页抓取相关的异常
参考 JavSP 的异常层次结构
增强：添加双语消息支持
"""

__all__ = ['ScraperError', 'NetworkError', 'MovieNotFoundError', 'MovieDuplicateError', 
           'SiteBlocked', 'SitePermissionError', 'CredentialError', 'WebsiteError']


class ScraperError(Exception):
    """所有刮削器相关异常的基类（支持双语消息）"""
    
    def __init__(self, message_zh: str, message_en: str = None, *args):
        """
        初始化异常
        
        Args:
            message_zh: 中文错误消息
            message_en: 英文错误消息（可选，默认使用中文消息）
            *args: 其他参数
        """
        self.message_zh = message_zh
        self.message_en = message_en or message_zh
        super().__init__(message_zh, *args)
    
    def get_message(self, locale: str = 'zh') -> str:
        """
        获取指定语言的消息
        
        Args:
            locale: 语言代码（'zh' 或 'en'）
        
        Returns:
            对应语言的错误消息
        """
        return self.message_zh if locale == 'zh' else self.message_en


class NetworkError(ScraperError):
    """网络连接错误"""
    
    def __init__(self, message_zh: str, message_en: str = None, *args):
        """
        初始化网络错误
        
        Args:
            message_zh: 中文错误消息
            message_en: 英文错误消息（可选）
            *args: 其他参数
        """
        if message_en is None:
            # 如果没有提供英文消息，尝试简单翻译
            message_en = message_zh.replace('请求超时', 'Request timeout') \
                                   .replace('连接错误', 'Connection error') \
                                   .replace('请求失败', 'Request failed')
        super().__init__(message_zh, message_en, *args)


class MovieNotFoundError(ScraperError):
    """表示某个站点没有找到某部影片"""
    
    def __init__(self, source: str, code: str, *args) -> None:
        """
        Args:
            source: 数据源名称（如 'fanza', 'javlibrary'）
            code: 番号或标题
        """
        message_zh = f"{source}: 未找到影片: '{code}'"
        message_en = f"{source}: Movie not found: '{code}'"
        super().__init__(message_zh, message_en, *args)
        self.source = source
        self.code = code
    
    def __str__(self):
        return self.message_zh


class MovieDuplicateError(ScraperError):
    """影片重复（搜索结果有多个匹配）"""
    
    def __init__(self, source: str, code: str, count: int, *args) -> None:
        """
        Args:
            source: 数据源名称
            code: 番号或标题
            count: 重复数量
        """
        message_zh = f"{source}: '{code}': 存在 {count} 个匹配结果"
        message_en = f"{source}: '{code}': Found {count} matching results"
        super().__init__(message_zh, message_en, *args)
        self.source = source
        self.code = code
        self.count = count
    
    def __str__(self):
        return self.message_zh


class SiteBlocked(ScraperError):
    """由于 IP 段或触发反爬机制等原因导致用户被站点封锁"""
    
    def __init__(self, message_zh: str = None, message_en: str = None, source: str = None, *args):
        """
        初始化站点封锁异常
        
        Args:
            message_zh: 中文错误消息（可选）
            message_en: 英文错误消息（可选）
            source: 数据源名称（可选）
            *args: 其他参数
        """
        if message_zh is None:
            if source:
                message_zh = f"{source}: 站点封锁"
                message_en = f"{source}: Site blocked"
            else:
                message_zh = "站点封锁"
                message_en = "Site blocked"
        
        super().__init__(message_zh, message_en, *args)
        self.source = source


class SitePermissionError(ScraperError):
    """由于缺少权限而无法访问影片资源"""
    
    def __init__(self, message_zh: str = "缺少访问权限", message_en: str = "Permission denied", *args):
        super().__init__(message_zh, message_en, *args)


class CredentialError(ScraperError):
    """由于缺少 Cookies 等凭据而无法访问影片资源"""
    
    def __init__(self, message_zh: str = "缺少访问凭据", message_en: str = "Credentials required", *args):
        super().__init__(message_zh, message_en, *args)


class WebsiteError(ScraperError):
    """非预期的状态码等网页故障"""
    
    def __init__(self, message_zh: str = "网页故障", message_en: str = "Website error", *args):
        super().__init__(message_zh, message_en, *args)
