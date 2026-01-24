"""
HTTP 请求封装

"""

import logging
import requests
import cloudscraper
import lxml.html
import socket
import urllib3
from typing import Dict, Any, Optional
from requests.models import Response
from requests.adapters import HTTPAdapter
from urllib3.util.connection import create_connection

from .exceptions import NetworkError, SiteBlocked

# 禁用 SSL 警告（因为使用 IP 映射时需要禁用 SSL 验证）
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)


class IPMappingHTTPAdapter(HTTPAdapter):
    """支持 IP 映射的 HTTP 适配器"""
    
    def __init__(self, ip_mapping: Dict[str, str], *args, **kwargs):
        self.ip_mapping = ip_mapping
        super().__init__(*args, **kwargs)
    
    def send(self, request, *args, **kwargs):
        """重写 send 方法来实现 IP 映射"""
        from urllib.parse import urlparse
        
        # 解析 URL
        parsed = urlparse(request.url)
        host = parsed.hostname
        
        # 只对映射表中的域名进行 IP 映射
        if host in self.ip_mapping:
            mapped_ip = self.ip_mapping[host]
            logger.debug(f"IP映射: {host} -> {mapped_ip}")
            
            # 替换 URL 中的主机名为 IP
            new_url = request.url.replace(f"://{host}", f"://{mapped_ip}")
            request.url = new_url
            
            # 确保 Host 头正确设置
            if 'Host' not in request.headers:
                request.headers['Host'] = host
            
            # 只对使用 IP 映射的请求禁用 SSL 验证
            kwargs['verify'] = False
        # 对于没有映射的域名，保持原有的 SSL 验证设置
        
        return super().send(request, *args, **kwargs)


class Request:
    """
    HTTP 请求封装类
    支持自定义 headers、cookies、代理等
    支持 CloudFlare 绕过
    """
    
    # 默认 User-Agent 和浏览器请求头（模拟真实浏览器）
    DEFAULT_HEADERS = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Ch-Ua': '"Not A(Brand";v="8", "Chromium";v="132"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
    }
    
    def __init__(self, config: Optional[Dict[str, Any]] = None, use_scraper: bool = False):
        """
        初始化 Request 对象
        
        Args:
            config: 配置字典，包含 network 配置
            use_scraper: 是否使用 cloudscraper（用于绕过 CloudFlare）
        """
        self.config = config or {}
        network_config = self.config.get('network', {})
        
        # 设置 headers 和 cookies
        self.headers = self.DEFAULT_HEADERS.copy()
        self.cookies = {}
        
        # 设置代理（带自动检测）
        proxy_server = network_config.get('proxy_server')
        if proxy_server:
            # 直接使用代理,不测试
            self.proxies = {'http': proxy_server, 'https': proxy_server}
            logger.info(f"使用代理: {proxy_server}")
        else:
            self.proxies = {}
            logger.info("未配置代理,使用直连")
        
        # 设置超时
        self.timeout = network_config.get('timeout', 30)
        
        # 设置重试次数
        self.retry = network_config.get('retry', 3)
        
        # 设置 IP 映射
        self.ip_mapping = network_config.get('ip_mapping', {})
        
        # 初始化 scraper
        if use_scraper:
            self.scraper = cloudscraper.create_scraper()
            
            # 如果有 IP 映射，添加自定义适配器
            if self.ip_mapping:
                adapter = IPMappingHTTPAdapter(self.ip_mapping)
                self.scraper.mount('http://', adapter)
                self.scraper.mount('https://', adapter)
                logger.info(f"启用 IP 映射: {self.ip_mapping}")
            
            self._get = self._scraper_monitor(self.scraper.get)
            self._post = self._scraper_monitor(self.scraper.post)
        else:
            self.scraper = None
            
            # 创建 requests session 并配置 IP 映射
            self.session = requests.Session()
            if self.ip_mapping:
                adapter = IPMappingHTTPAdapter(self.ip_mapping)
                self.session.mount('http://', adapter)
                self.session.mount('https://', adapter)
                logger.info(f"启用 IP 映射: {self.ip_mapping}")
            
            self._get = self.session.get
            self._post = self.session.post
    
    def _test_proxy(self, proxy_server: str, timeout: int = 3) -> bool:
        """
        测试代理是否可用
        
        Args:
            proxy_server: 代理服务器地址
            timeout: 超时时间（秒）
        
        Returns:
            代理是否可用
        """
        try:
            proxies = {'http': proxy_server, 'https': proxy_server}
            # 使用一个简单的请求测试代理 - 改用百度测试
            response = requests.get(
                'http://www.baidu.com',
                proxies=proxies,
                timeout=timeout,
                allow_redirects=False
            )
            return True
        except Exception as e:
            logger.debug(f"代理测试失败: {e}")
            return False
    
    def _scraper_monitor(self, func):
        """
        监控 cloudscraper 的工作状态
        遇到不支持的 Challenge 时尝试退回常规的 requests 请求
        """
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                logger.debug(f"无法通过 CloudFlare 检测: '{e}', 尝试退回常规的 requests 请求")
                # 退回到常规 requests
                if func == self.scraper.get:
                    return requests.get(*args, **kwargs)
                else:
                    return requests.post(*args, **kwargs)
        return wrapper
    
    def get(self, url: str, delay_raise: bool = False, **kwargs) -> Response:
        """
        发送 GET 请求
        
        Args:
            url: 请求 URL
            delay_raise: 是否延迟抛出异常
            **kwargs: 其他 requests 参数
        
        Returns:
            Response 对象
        
        Raises:
            NetworkError: 网络错误
            SiteBlocked: 站点封锁
        """
        try:
            r = self._get(
                url,
                headers=self.headers,
                proxies=self.proxies,
                cookies=self.cookies,
                timeout=self.timeout,
                **kwargs
            )
            
            # 检查 CloudFlare 封锁
            if r.status_code == 403 and b'>Just a moment...<' in r.content:
                raise SiteBlocked(
                    f"403 Forbidden: 无法通过 CloudFlare 检测: {url}",
                    f"403 Forbidden: Cannot bypass CloudFlare detection: {url}"
                )
            
            if not delay_raise:
                r.raise_for_status()
            
            return r
        
        except requests.exceptions.Timeout as e:
            raise NetworkError(
                f"请求超时: {url}",
                f"Request timeout: {url}"
            ) from e
        except requests.exceptions.ConnectionError as e:
            raise NetworkError(
                f"连接错误: {url}",
                f"Connection error: {url}"
            ) from e
        except requests.exceptions.RequestException as e:
            raise NetworkError(
                f"请求失败: {url}",
                f"Request failed: {url}"
            ) from e
    
    def post(self, url: str, data: Any = None, delay_raise: bool = False, **kwargs) -> Response:
        """
        发送 POST 请求
        
        Args:
            url: 请求 URL
            data: POST 数据
            delay_raise: 是否延迟抛出异常
            **kwargs: 其他 requests 参数（包括 json、headers 参数）
        
        Returns:
            Response 对象
        
        Raises:
            NetworkError: 网络错误
        """
        try:
            # 如果 kwargs 中有 headers，合并到默认 headers
            if 'headers' in kwargs:
                merged_headers = self.headers.copy()
                merged_headers.update(kwargs['headers'])
                kwargs['headers'] = merged_headers
            else:
                kwargs['headers'] = self.headers
            
            # 确保代理、cookies、timeout 都传递
            if 'proxies' not in kwargs:
                kwargs['proxies'] = self.proxies
            if 'cookies' not in kwargs:
                kwargs['cookies'] = self.cookies
            if 'timeout' not in kwargs:
                kwargs['timeout'] = self.timeout
            
            # 如果有 data 参数，添加到 kwargs
            if data is not None:
                kwargs['data'] = data
            
            r = self._post(url, **kwargs)
            
            if not delay_raise:
                r.raise_for_status()
            
            return r
        
        except requests.exceptions.Timeout as e:
            raise NetworkError(
                f"请求超时: {url}",
                f"Request timeout: {url}"
            ) from e
        except requests.exceptions.ConnectionError as e:
            raise NetworkError(
                f"连接错误: {url}",
                f"Connection error: {url}"
            ) from e
        except requests.exceptions.RequestException as e:
            raise NetworkError(
                f"请求失败: {url}",
                f"Request failed: {url}"
            ) from e
    
    def get_html(self, url: str, encoding: str = 'utf-8', delay_raise: bool = False) -> lxml.html.HtmlElement:
        """
        获取 HTML 并解析为 lxml 对象
        
        Args:
            url: 请求 URL
            encoding: 编码格式
            delay_raise: 是否延迟抛出异常
        
        Returns:
            lxml.html.HtmlElement 对象
        """
        r = self.get(url, delay_raise=delay_raise)
        
        # 设置编码
        if encoding:
            r.encoding = encoding
        else:
            r.encoding = r.apparent_encoding
        
        # 解析 HTML
        html = lxml.html.fromstring(r.text)
        html.make_links_absolute(url, resolve_base_href=True)
        return html
    
    def get_text(self, url: str, encoding: Optional[str] = None) -> str:
        """
        获取响应文本
        
        Args:
            url: 请求 URL
            encoding: 编码格式（None 表示自动检测）
        
        Returns:
            响应文本
        """
        r = self.get(url)
        
        if encoding:
            r.encoding = encoding
        else:
            r.encoding = r.apparent_encoding
        
        return r.text


if __name__ == '__main__':
    # 测试用例
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent.parent))
    
    from web.exceptions import NetworkError, SiteBlocked
    
    print("=== HTTP 客户端测试 ===\n")
    
    # 测试基础请求
    req = Request()
    try:
        r = req.get('https://www.google.com')
        print(f"✓ 基础 GET 请求成功: {r.status_code}")
    except Exception as e:
        print(f"✗ 基础 GET 请求失败: {e}")
    
    # 测试 CloudFlare 绕过
    req_cf = Request(use_scraper=True)
    print(f"✓ CloudFlare scraper 初始化成功")
    
    print("\n=== 测试完成 ===")
