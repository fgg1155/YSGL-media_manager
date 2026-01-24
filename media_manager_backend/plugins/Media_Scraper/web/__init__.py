"""Web 模块 - HTTP 客户端和异常"""

from .exceptions import *
from .request import Request

__all__ = ['Request', 'ScraperError', 'NetworkError', 'WebsiteError', 
           'MovieNotFoundError', 'MovieDuplicateError', 'SiteBlocked', 
           'SitePermissionError', 'CredentialError']
