"""
MindGeek Network Scraper
支持 Brazzers, RealityKings, Mofos, Twistys, SexyHub 等 MindGeek 旗下网络
基于 Project1Service API 实现
"""

import logging
import re
import json
import time
from datetime import datetime
from typing import Optional, Dict, Any, List
from urllib.parse import urlencode, quote

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.request import Request

# 导入工具模块
from utils.query_parser import clean_title
from utils.date_parser import is_date_query, parse_date_query, filter_by_date


logger = logging.getLogger(__name__)


class MindGeekScraper(BaseScraper):
    """MindGeek 网络刮削器"""
    
    name = 'mindgeek'
    base_url = 'https://site-api.project1service.com'
    
    # API 端点
    SEARCH_URL_TEMPLATE = "https://site-api.project1service.com/v2/releases?limit=30&offset=0&search={}&type={}"
    SCENE_URL = "https://site-api.project1service.com/v2/releases/{}"
    MODEL_URL = "https://site-api.project1service.com/v1/actors?id={}&blockId=118061&blockName=PlayerBlock&pageType=WATCH_TRAILER"
    
    # JWT 令牌相关
    TOKEN_VALIDITY_MS = 10740000  # 约3小时
    JWT_REGEX = re.compile(r'"jwt"\s*:\s*"([^"]+)', re.IGNORECASE)
    
    def __init__(self, config: Dict[str, Any], use_scraper: bool = True):
        """
        初始化 MindGeek 刮削器
        
        Args:
            config: 配置字典
            use_scraper: 是否使用 cloudscraper（推荐开启以绕过 Cloudflare）
        """
        # 加载 IP 映射配置
        self._load_ip_mapping(config)
        
        super().__init__(config, use_scraper=use_scraper)
        
        # 加载站点配置
        self.sites_config = self._load_sites_config()
        
        # JWT 令牌管理 - 支持多个站点
        self._tokens = {}  # 存储多个站点的 token
        self._token_valid_until = {}  # 存储每个站点 token 的有效期
        
        # 可用的 token 源站点（按优先级排序）
        self.token_sources = [
            "https://www.realitykings.com",
            "https://www.brazzers.com",
            "https://bangbros.com",
            "https://www.mofos.com",
            "https://www.twistys.com",
            "https://www.digitalplayground.com",
            "https://www.letsdoeit.com"
        ]
        
        # 请求限制（每3分钟最多35个请求）
        self._rate_limit_enabled = config.get('rate_limit_enabled', False)
        self._request_times = []
        self._max_requests = 35
        self._time_window = 180  # 3分钟
        
        self.logger.info(f"MindGeek scraper initialized with {len(self.sites_config)} sites")
    
    def _load_ip_mapping(self, config: Dict[str, Any]):
        """加载 IP 映射配置"""
        import yaml
        
        # 确保 network 配置存在
        if 'network' not in config:
            config['network'] = {}
        
        # 如果配置中已经有 ip_mapping，保留它（优先使用传入的配置）
        existing_mapping = config['network'].get('ip_mapping', {})
        
        try:
            # 更新为新的路径: config/map/ip_mapping.yaml
            ip_mapping_path = Path(__file__).parent.parent.parent / 'config' / 'map' / 'ip_mapping.yaml'
            
            if ip_mapping_path.exists():
                with open(ip_mapping_path, 'r', encoding='utf-8') as f:
                    ip_mapping_config = yaml.safe_load(f) or {}
                
                # 过滤掉注释和空值
                ip_mapping = {}
                for domain, ip in ip_mapping_config.items():
                    if isinstance(domain, str) and isinstance(ip, str) and not domain.startswith('#'):
                        ip_mapping[domain] = ip
                
                # 合并：文件中的映射 + 已有的映射（已有的优先）
                ip_mapping.update(existing_mapping)
                
                if ip_mapping:
                    config['network']['ip_mapping'] = ip_mapping
                    logger.info(f"Loaded IP mapping from {ip_mapping_path}: {len(ip_mapping)} domains")
                else:
                    logger.info("No valid IP mappings found")
            else:
                # 文件不存在，但如果有传入的映射，仍然使用
                if existing_mapping:
                    logger.info(f"IP mapping file not found, using provided mapping: {len(existing_mapping)} domains")
                else:
                    logger.info(f"IP mapping file not found at {ip_mapping_path}, using direct connection")
                
        except Exception as e:
            logger.warning(f"Failed to load IP mapping: {e}")
            config['network']['ip_mapping'] = {}
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """加载站点配置"""
        sites = {}
        config_path = Path(__file__).parent.parent.parent / 'config' / 'site' / 'mindgeek_sites.csv'
        
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            # 跳过注释和标题行
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('site_name'):
                    continue
                
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 6:
                    site_name, domain, code, network, enabled, priority = parts[:6]
                    if enabled.lower() == 'true':
                        sites[site_name.lower()] = {
                            'name': site_name,
                            'domain': domain,
                            'code': code if code else None,
                            'network': network,
                            'priority': int(priority) if priority.isdigit() else 50
                        }
            
            self.logger.info(f"Loaded {len(sites)} MindGeek sites from config")
            return sites
            
        except Exception as e:
            self.logger.error(f"Failed to load sites config: {e}")
            return {}
    
    def _rate_limit(self):
        """请求频率限制"""
        if not self._rate_limit_enabled:
            return
        
        current_time = time.time()
        
        # 清理过期的请求记录
        self._request_times = [t for t in self._request_times if current_time - t < self._time_window]
        
        # 检查是否超过限制
        if len(self._request_times) >= self._max_requests:
            sleep_time = self._time_window - (current_time - self._request_times[0])
            if sleep_time > 0:
                self.logger.info(f"Rate limit reached, sleeping for {sleep_time:.2f} seconds")
                time.sleep(sleep_time)
                self._request_times.pop(0)
        
        # 记录当前请求时间
        self._request_times.append(current_time)
    
    def _get_instance_token(self, main_page: str) -> Optional[str]:
        """获取 JWT 实例令牌"""
        current_time = int(time.time() * 1000)
        
        # 检查该站点的令牌是否仍然有效
        if (main_page in self._token_valid_until and 
            current_time <= self._token_valid_until[main_page] and 
            main_page in self._tokens):
            return self._tokens[main_page]
        
        try:
            self._rate_limit()
            
            # 从主页获取 JWT 令牌
            response = self.request.get(main_page)
            if not response:
                return None
            
            match = self.JWT_REGEX.search(response.text)
            if match:
                token = match.group(1)
                self._tokens[main_page] = token
                self._token_valid_until[main_page] = current_time + self.TOKEN_VALIDITY_MS
                self.logger.debug(f"Successfully obtained JWT token from {main_page}")
                return token
            else:
                self.logger.error(f"JWT token not found in response from {main_page}")
                return None
                
        except Exception as e:
            self.logger.error(f"Failed to get instance token from {main_page}: {e}")
            return None
    
    def _get_any_valid_token(self) -> Optional[tuple[str, str]]:
        """尝试从任何可用的站点获取有效的 token"""
        for source in self.token_sources:
            try:
                token = self._get_instance_token(source)
                if token:
                    self.logger.info(f"Successfully got token from {source}")
                    return token, source
            except Exception as e:
                self.logger.debug(f"Failed to get token from {source}: {e}")
                continue
        
        self.logger.error("Failed to get token from any source")
        return None
    
    def _get_token_for_site(self, site_name: str) -> Optional[tuple[str, str]]:
        """
        为特定站点获取对应的 token（带回退机制）
        
        策略：
        1. 优先尝试网络主站 token（适用于已合并到主站的系列）
        2. 如果失败，尝试子站 token（适用于独立运营的系列）
        3. 如果都失败，返回 None（由 western_scraper_manager 调用 ThePornDB）
        
        Args:
            site_name: 站点名称或网络名称
        
        Returns:
            (token, token_source) 或 None
        """
        # 网络主域名映射
        network_domains = {
            'Brazzers': 'https://www.brazzers.com',
            'RealityKings': 'https://www.realitykings.com',
            'BangBros': 'https://bangbros.com',
            'DigitalPlayground': 'https://www.digitalplayground.com',
            'Mofos': 'https://www.mofos.com',
            'Twistys': 'https://www.twistys.com',
            'SexyHub': 'https://www.sexyhub.com',
            'FakeHub': 'https://www.fakehub.com',
            'MileHigh': 'https://www.sweetheartvideo.com',
            'Babes': 'https://www.babes.com',
            'TransAngels': 'https://www.transangels.com',
            'LetsDoeIt': 'https://www.letsdoeit.com',
            'Independent': 'https://www.biempire.com'
        }
        
        # 查找站点配置
        site_info = self._find_site_by_name(site_name)
        
        if site_info:
            network = site_info['network']
            subdomain = site_info['domain']
            
            # 1. 优先尝试网络主站 token
            network_domain = network_domains.get(network)
            if network_domain:
                try:
                    token = self._get_instance_token(network_domain)
                    if token:
                        self.logger.info(f"✓ 从网络主站获取 token: {network_domain} (系列: {site_name})")
                        return token, network_domain
                except Exception as e:
                    self.logger.debug(f"网络主站 token 获取失败 {network_domain}: {e}")
            
            # 2. 回退：尝试子站 token
            if subdomain:
                subdomain_url = f"https://{subdomain}"
                try:
                    token = self._get_instance_token(subdomain_url)
                    if token:
                        self.logger.info(f"✓ 从子站获取 token: {subdomain_url} (系列: {site_name})")
                        return token, subdomain_url
                except Exception as e:
                    self.logger.debug(f"子站 token 获取失败 {subdomain_url}: {e}")
            
            # 3. 都失败，返回 None
            self.logger.warning(f"✗ 无法为系列 {site_name} 获取 token（主站和子站都失败）")
            return None
        else:
            # 没有找到系列配置，尝试作为网络名称处理
            network_domains_lower = {
                'brazzers': 'https://www.brazzers.com',
                'realitykings': 'https://www.realitykings.com', 
                'bangbros': 'https://bangbros.com',
                'digitalplayground': 'https://www.digitalplayground.com',
                'mofos': 'https://www.mofos.com',
                'twistys': 'https://www.twistys.com',
                'sexyhub': 'https://www.sexyhub.com',
                'fakehub': 'https://www.fakehub.com',
                'milehigh': 'https://www.sweetheartvideo.com',
                'babes': 'https://www.babes.com',
                'transangels': 'https://www.transangels.com',
                'letsdoeit': 'https://www.letsdoeit.com',
                'independent': 'https://www.biempire.com'
            }
            
            preferred_domain = network_domains_lower.get(site_name.lower())
            if preferred_domain:
                try:
                    token = self._get_instance_token(preferred_domain)
                    if token:
                        self.logger.info(f"✓ 从网络名获取 token: {preferred_domain}")
                        return token, preferred_domain
                except Exception as e:
                    self.logger.debug(f"网络名 token 获取失败 {preferred_domain}: {e}")
            
            # 未找到配置且获取失败，返回 None
            self.logger.warning(f"✗ 未找到站点配置且无法获取 token: {site_name}")
            return None
    
    def _api_request(self, url: str, main_page: str = None) -> Optional[Dict[str, Any]]:
        """发送 API 请求"""
        # 如果没有指定主页，尝试获取任何可用的 token
        if main_page:
            token = self._get_instance_token(main_page)
            token_source = main_page
        else:
            token_result = self._get_any_valid_token()
            if token_result:
                token, token_source = token_result
            else:
                self.logger.error("Failed to get any valid token")
                return None
        
        if not token:
            self.logger.error("Failed to get instance token")
            return None
        
        # 临时保存原始 headers
        original_headers = self.request.headers.copy()
        
        # 设置 API 请求需要的 headers
        api_headers = {
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate',
            'Accept-Language': 'en-US,en;q=0.8',
            'Instance': token,
            'Origin': token_source,
            'Priority': 'u=1, i',
            'Referer': f'{token_source}/',
            'Sec-Ch-Ua': '"Not/A)Brand";v="8", "Chromium";v="126", "Brave";v="126"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"Windows"',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site',
            'Sec-Gpc': '1',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
        }
        
        try:
            self._rate_limit()
            
            # 更新 request 的 headers
            self.request.headers.update(api_headers)
            
            self.logger.debug(f"API 请求: {url}")
            self.logger.debug(f"Token 来源: {token_source}")
            self.logger.debug(f"Instance Token: {token[:20]}..." if token else "None")
            
            response = self.request.get(url)
            
            if response and response.status_code == 200:
                json_data = response.json()
                self.logger.debug(f"API 响应成功，数据键: {list(json_data.keys()) if isinstance(json_data, dict) else 'not a dict'}")
                return json_data
            else:
                self.logger.error(f"API 请求失败: URL={url}")
                self.logger.error(f"  - 状态码: {response.status_code if response else 'No response'}")
                if response:
                    self.logger.error(f"  - 响应内容: {response.text[:500]}")
                return None
                
        except Exception as e:
            self.logger.error(f"API 请求异常: {e}")
            self.logger.error(f"  - URL: {url}")
            self.logger.error(f"  - Token 来源: {token_source}")
            import traceback
            self.logger.error(traceback.format_exc())
            return None
        finally:
            # 恢复原始 headers
            self.request.headers = original_headers
    
    def _search_by_title(self, title: str, preferred_site: str = None, content_type: str = 'scene') -> tuple[List[Dict[str, Any]], Optional[str]]:
        """
        根据标题搜索
        
        Args:
            title: 搜索标题
            preferred_site: 首选站点（用于获取 token）
            content_type: 内容类型，'scene' 或 'movie'，默认 'scene'
        
        Returns:
            (搜索结果列表, 使用的 token_source)
        """
        # 使用工具模块清理标题：移除特殊符号，只保留字母、数字和空格
        # 例如: "You Bet Your Ass! Best Of Anal Vol. 2" -> "You Bet Your Ass Best Of Anal Vol 2"
        cleaned_title = clean_title(title)
        
        self.logger.info(f"原始标题: {title}")
        self.logger.info(f"清理后标题: {cleaned_title}")
        
        encoded_title = quote(cleaned_title, encoding='utf-8')
        # 使用模板构建 URL，支持动态类型
        search_url = self.SEARCH_URL_TEMPLATE.format(encoded_title, content_type.lower())
        
        self.logger.info(f"Searching for: {cleaned_title} (type: {content_type})")
        
        # 如果指定了首选站点，尝试使用对应的 token
        if preferred_site:
            token_result = self._get_token_for_site(preferred_site)
            if token_result:
                token, token_source = token_result
                result = self._api_request(search_url, token_source)
                if result and 'result' in result:
                    return result['result'], token_source
            else:
                # 无法获取 token，返回空结果
                self.logger.warning(f"无法为站点 {preferred_site} 获取 token，搜索失败")
                return [], None
        
        # 否则使用默认方式（尝试任意可用 token）
        token_result = self._get_any_valid_token()
        if token_result:
            token, token_source = token_result
            result = self._api_request(search_url, token_source)
            if result and 'result' in result:
                return result['result'], token_source
        
        return [], None
    
    def _get_scene_by_id(self, scene_id: str, token_source: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """
        根据ID获取场景详情
        
        Args:
            scene_id: 场景 ID
            token_source: Token 来源（如果指定，使用该来源的 token）
        
        Returns:
            场景详情数据
        """
        scene_url = self.SCENE_URL.format(scene_id)
        
        try:
            if token_source:
                # 使用指定来源的 token
                result = self._api_request(scene_url, token_source)
            else:
                # 使用任意可用的 token
                result = self._api_request(scene_url)
            
            if result and 'result' in result:
                return result['result']
            
            self.logger.warning(f"场景详情 API 返回空结果: scene_id={scene_id}")
            return None
        except Exception as e:
            self.logger.error(f"获取场景详情失败: scene_id={scene_id}, error={e}")
            return None
    
    def _get_actors_by_ids(self, actor_ids: List[int], token_source: Optional[str] = None) -> List[Dict[str, Any]]:
        """根据ID列表获取演员信息"""
        if not actor_ids:
            return []
        
        ids_str = '%3B'.join(map(str, actor_ids))
        model_url = self.MODEL_URL.format(ids_str)
        
        # 使用指定的 token_source（如果提供）
        if token_source:
            result = self._api_request(model_url, token_source)
        else:
            result = self._api_request(model_url)
            
        if result and 'result' in result:
            return result['result']
        
        return []
    
    def _process_images(self, images_dict: Dict[str, Dict[str, Dict[str, Any]]], max_count: int = 10) -> List[str]:
        """处理图片数据"""
        image_urls = []
        
        if not images_dict:
            return image_urls
        
        # 按索引顺序处理图片
        for i in range(max_count + 1):
            key = str(i)
            if key not in images_dict:
                continue
            
            size_dict = images_dict[key]
            
            # 优先选择较大尺寸的图片
            for size in ['xx', 'xl', 'lg', 'md', 'sm', 'xs']:
                if size in size_dict and 'url' in size_dict[size]:
                    image_urls.append(size_dict[size]['url'])
                    break
        
        return image_urls
    
    def _process_videos(self, videos_dict: Dict[str, Any]) -> List[Dict[str, str]]:
        """
        处理视频数据，提取预览视频 URL（结构化格式）
        
        MindGeek API 的视频数据结构：
        {
            "mediabook": {
                "files": {
                    "720p": {
                        "urls": {"view": "https://..."}
                    },
                    "320p": {
                        "urls": {"view": "https://..."}
                    }
                }
            }
        }
        或旧格式：
        {
            "trailer": {"url": "https://..."},
            "preview": {"url": "https://..."}
        }
        
        Returns:
            结构化视频列表: [{'quality': '720P', 'url': 'https://...'}, ...]
        """
        video_list = []
        
        if not videos_dict:
            self.logger.debug("_process_videos: videos_dict 为空")
            return video_list
        
        self.logger.debug(f"_process_videos: 开始处理，键={list(videos_dict.keys())}")
        
        # 方式1：处理 mediabook 格式（新格式）
        if 'mediabook' in videos_dict:
            mediabook = videos_dict['mediabook']
            self.logger.debug(f"  找到 mediabook 格式")
            
            if isinstance(mediabook, dict) and 'files' in mediabook:
                files = mediabook['files']
                self.logger.debug(f"  mediabook.files 键: {list(files.keys())}")
                
                # 按质量优先级提取：1080p > 720p > 480p > 320p
                quality_priority = ['1080p', '720p', '480p', '320p']
                for quality in quality_priority:
                    if quality in files:
                        file_data = files[quality]
                        if isinstance(file_data, dict) and 'urls' in file_data:
                            urls = file_data['urls']
                            if isinstance(urls, dict) and 'view' in urls:
                                url = urls['view']
                                # 格式化清晰度标签（720p -> 720P）
                                quality_label = quality.upper()
                                video_list.append({
                                    'quality': quality_label,
                                    'url': url
                                })
                                self.logger.debug(f"    提取 {quality_label} URL: {url[:80]}...")
        
        # 方式2：提取 trailer 和 preview（旧格式）
        if not video_list:
            self.logger.debug("  mediabook 未找到，尝试 trailer/preview 格式...")
            for key in ['trailer', 'preview', 'teaser']:
                if key in videos_dict:
                    video_data = videos_dict[key]
                    self.logger.debug(f"  找到键 '{key}': {type(video_data)}")
                    if isinstance(video_data, dict) and 'url' in video_data:
                        url = video_data['url']
                        video_list.append({
                            'quality': key.capitalize(),  # Trailer, Preview, Teaser
                            'url': url
                        })
                        self.logger.debug(f"    提取URL: {url[:80]}...")
                    elif isinstance(video_data, str):
                        video_list.append({
                            'quality': key.capitalize(),
                            'url': video_data
                        })
                        self.logger.debug(f"    提取URL(字符串): {video_data[:80]}...")
        
        # 方式3：按索引提取（如果上面都没找到）
        if not video_list:
            self.logger.debug("  方式2未找到，尝试索引方式...")
            for i in range(10):  # 最多提取10个视频
                key = str(i)
                if key in videos_dict:
                    video_data = videos_dict[key]
                    self.logger.debug(f"  找到索引 '{key}': {type(video_data)}")
                    if isinstance(video_data, dict) and 'url' in video_data:
                        url = video_data['url']
                        video_list.append({
                            'quality': f'Video {i+1}',
                            'url': url
                        })
                        self.logger.debug(f"    提取URL: {url[:80]}...")
                    elif isinstance(video_data, str):
                        video_list.append({
                            'quality': f'Video {i+1}',
                            'url': video_data
                        })
                        self.logger.debug(f"    提取URL(字符串): {video_data[:80]}...")
        
        self.logger.debug(f"_process_videos: 完成，提取到 {len(video_list)} 个视频")
        return video_list
    
    def _find_site_by_name(self, site_name: str) -> Optional[Dict[str, Any]]:
        """
        根据名称查找站点配置
        
        支持两种匹配方式：
        1. 精确匹配系列名（如 PornstarsLikeItBig）
        2. 网络名匹配（如 Brazzers 匹配任何 network=Brazzers 的条目）
        
        规范化处理：
        - 只保留字母和数字，移除所有其他字符（空格、撇号、连字符等）
        - 转小写
        - 例如：
          - Dad's Love Porn → dadsloveporn
          - Dad'sLovePorn → dadsloveporn
          - Dads-Love-Porn → dadsloveporn
          - 都能匹配 CSV 中的 "Dads Love Porn"
        """
        if not site_name:
            return None
        
        # 规范化：只保留字母和数字，转小写
        normalized_search = re.sub(r'[^a-zA-Z0-9]', '', site_name).lower()
        
        # 1. 精确匹配系列名（只保留字母数字后）
        for key, site_info in self.sites_config.items():
            normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
            if normalized_search == normalized_key:
                self.logger.debug(f"站点精确匹配: {site_name} -> {site_info['name']}")
                return site_info
        
        # 2. 模糊匹配系列名 - 检查是否包含关键词
        # 将搜索词按非字母数字字符分割
        search_words = [w for w in re.split(r'[^a-zA-Z0-9]+', site_name.lower()) if w]
        for key, site_info in self.sites_config.items():
            # 只保留字母数字
            normalized_key = re.sub(r'[^a-zA-Z0-9]', '', key).lower()
            # 如果搜索词都在站点名称中，认为匹配
            if all(word in normalized_key for word in search_words):
                self.logger.debug(f"站点模糊匹配: {site_name} -> {site_info['name']}")
                return site_info
        
        # 3. 网络名匹配 - 如果输入是网络名（如 Brazzers），返回该网络的任意一个系列配置
        # 这样可以获取到正确的 network 字段，用于 token 获取
        for key, site_info in self.sites_config.items():
            if site_info['network'].lower() == normalized_search:
                self.logger.debug(f"网络名匹配: {site_name} -> 网络 {site_info['network']} (使用系列 {site_info['name']} 的配置)")
                return site_info
        
        self.logger.debug(f"未找到站点配置: {site_name}")
        return None
    
    def scrape_multiple(self, query: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        搜索并返回多个结果（公共接口）
        
        Args:
            query: 搜索关键词（标题或场景ID）
            content_type_hint: 内容类型提示（'Scene' 或 'Movie'）
            series: 系列名（必须提供）
        
        Returns:
            ScrapeResult 列表
        """
        try:
            # 规范化 content_type_hint
            search_type = 'scene'  # 默认搜索 scene
            if content_type_hint:
                search_type = content_type_hint.lower()
            
            # 如果输入是纯数字，直接按 ID 获取单个结果
            if query.isdigit():
                self.logger.info(f"检测到纯数字 ID: {query}")
                scene_data = self._get_scene_by_id(query)
                if scene_data:
                    result = self._parse_scene_data(scene_data, None)
                    return [result] if result else []
                return []
            
            # 使用传入的 series 参数
            series_name = series
            search_title = query
            
            # 如果有系列名，从 query 中提取纯标题（不包含系列名）
            if series_name:
                from utils.query_parser import extract_series_and_title
                _, pure_title = extract_series_and_title(query, self._find_site_by_name)
                search_title = pure_title
                self.logger.debug(f"提取纯标题: '{query}' -> '{pure_title}'")
            
            if not series_name:
                self.logger.warning(f"MindGeek 刮削器需要系列名参数")
                return []
            
            self.logger.info(f"多结果模式：系列={series_name}, 标题={search_title}, 类型={search_type}")
            
            # 按标题搜索
            search_results, token_source = self._search_by_title(search_title, series_name, search_type)
            
            if not search_results:
                self.logger.warning(f"使用系列 {series_name} 搜索失败: {search_title}")
                return []
            
            self.logger.info(f"找到 {len(search_results)} 个搜索结果")
            
            # 使用匹配度过滤，只保留高匹配度的结果
            from utils.query_parser import calculate_title_match_score
            
            # 计算每个结果的匹配度
            scored_results = []
            for search_result in search_results:
                result_title = search_result.get('title', '')
                score = calculate_title_match_score(search_title, result_title)
                scored_results.append((score, search_result))
                self.logger.debug(f"  - {result_title}: 匹配度 {score:.2f}")
            
            # 按匹配度降序排序
            scored_results.sort(key=lambda x: x[0], reverse=True)
            
            # 过滤：只保留匹配度 >= 80 的结果，或者至少保留最佳匹配
            MATCH_THRESHOLD = 80.0
            filtered_results = []
            
            for score, search_result in scored_results:
                # 保留匹配度 >= 80 的结果
                if score >= MATCH_THRESHOLD:
                    filtered_results.append(search_result)
                # 如果没有任何结果 >= 80，至少保留最佳匹配（第一个）
                elif not filtered_results and score == scored_results[0][0]:
                    filtered_results.append(search_result)
                    self.logger.info(f"  保留最佳匹配（匹配度 {score:.2f}）: {search_result.get('title')}")
            
            if len(filtered_results) < len(search_results):
                self.logger.info(f"匹配度过滤：{len(search_results)} -> {len(filtered_results)} 个结果")
            
            # 为每个过滤后的结果获取详细信息
            results = []
            for idx, search_result in enumerate(filtered_results, 1):
                scene_id = str(search_result.get('id', ''))
                if not scene_id:
                    continue
                
                # 如果指定了系列名，验证结果是否属于该系列
                if series_name:
                    result_brand = search_result.get('brand', '')
                    result_collections = search_result.get('collections', [])
                    
                    # 获取系列配置
                    site_info = self._find_site_by_name(series_name)
                    
                    if site_info:
                        expected_network = site_info['network']
                        
                        # 验证 brand 是否匹配
                        brand_match = False
                        if result_brand:
                            brand_info = self._find_site_by_name(result_brand)
                            if brand_info and brand_info['network'] == expected_network:
                                brand_match = True
                        
                        # 验证 collections 是否匹配
                        collections_match = False
                        if result_collections:
                            for collection in result_collections:
                                collection_name = collection.get('name', '')
                                if collection_name:
                                    collection_info = self._find_site_by_name(collection_name)
                                    if collection_info and collection_info['network'] == expected_network:
                                        collections_match = True
                                        break
                        
                        # 如果都不匹配，跳过这个结果
                        if not brand_match and not collections_match:
                            self.logger.debug(
                                f"结果 {idx} 不属于指定系列 {series_name} (期望网络: {expected_network}), "
                                f"实际 brand: {result_brand}, collections: {[c.get('name') for c in result_collections]}"
                            )
                            continue
                
                # 获取场景详情
                self.logger.debug(f"获取结果 {idx} 的详细信息: scene_id={scene_id}")
                scene_data = self._get_scene_by_id(scene_id, token_source)
                if scene_data:
                    result = self._parse_scene_data(scene_data, token_source)
                    if result:
                        results.append(result)
            
            self.logger.info(f"成功获取 {len(results)} 个详细结果")
            return results
            
        except Exception as e:
            self.logger.error(f"scrape_multiple 失败: {query}, 错误: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []
    
    def _scrape_impl(self, code: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            code: 搜索关键词（标题或场景ID）
            content_type_hint: 内容类型提示（'Scene' 或 'Movie'），用于 API 搜索
            series: 系列名（可选，如果提供则直接使用，不再从 code 中提取）
        
        Returns:
            ScrapeResult 对象
        
        逻辑说明：
        - 如果输入是纯数字，直接按 ID 获取
        - 如果提供了 series 参数，使用它获取对应网站的 token
        - 实际搜索时只使用标题部分
        - content_type_hint 用于指定搜索类型（scene 或 movie）
        """
        # 规范化 content_type_hint
        search_type = 'scene'  # 默认搜索 scene
        if content_type_hint:
            search_type = content_type_hint.lower()
        
        # 尝试直接按ID获取
        if code.isdigit():
            self.logger.info(f"检测到纯数字 ID: {code}")
            scene_data = self._get_scene_by_id(code)
            if scene_data:
                return self._parse_scene_data(scene_data, None)  # 纯 ID 查询，无 token_source
        
        # 使用传入的 series 参数
        series_name = series
        search_title = code
        
        # 如果有系列名，从 code 中提取纯标题（不包含系列名）
        if series_name:
            from utils.query_parser import extract_series_and_title
            _, pure_title = extract_series_and_title(code, self._find_site_by_name)
            search_title = pure_title
            self.logger.debug(f"提取纯标题: '{code}' -> '{pure_title}'")
        
        # 按标题搜索
        search_results = []
        token_source = None
        
        if series_name:
            # 如果提供了系列名，只使用该系列获取 token 和搜索
            # 不尝试其他网络（失败后由 western_scraper_manager 调用 ThePornDB）
            self.logger.info(f"使用传入的系列名: {series_name}, 搜索标题: {search_title}, 类型: {search_type}")
            search_results, token_source = self._search_by_title(search_title, series_name, search_type)
            
            if not search_results:
                self.logger.warning(f"使用系列 {series_name} 搜索失败: {search_title}")
                return None
        else:
            # 没有系列名，按顺序尝试多个网络
            self.logger.info(f"未提供系列名，尝试多个网络搜索: {code}, 类型: {search_type}")
            
            # 尝试 Brazzers（最常用）
            self.logger.info(f"尝试使用 Brazzers 搜索: {code}")
            search_results, token_source = self._search_by_title(code, "Brazzers", search_type)
            
            if not search_results:
                # 尝试其他网络
                for network in ["RealityKings", "Mofos", "Twistys"]:
                    self.logger.info(f"尝试使用 {network} 搜索: {code}")
                    search_results, token_source = self._search_by_title(code, network, search_type)
                    if search_results:
                        break
            
            if not search_results:
                # 最后尝试默认搜索（不指定系列）
                self.logger.info(f"尝试默认搜索（无系列）: {code}")
                search_results, token_source = self._search_by_title(code, content_type=search_type)
            
            if not search_results:
                self.logger.warning(f"所有 MindGeek 网络都未找到结果: {code}")
                return None
        
        # 使用工具模块选择最佳匹配
        best_result = select_best_match(search_results, search_title, title_field='title')
        
        if not best_result:
            self.logger.warning(f"未找到合适的匹配结果")
            return None
        
        scene_id = str(best_result.get('id', ''))
        
        # 如果指定了系列名，验证结果是否属于该系列
        if series_name and scene_id:
            # 检查搜索结果中的 brand 或 collections
            result_brand = best_result.get('brand', '')
            result_collections = best_result.get('collections', [])
            
            # 获取系列配置
            site_info = self._find_site_by_name(series_name)
            
            if site_info:
                expected_network = site_info['network']
                expected_series = site_info['name']
                
                # 验证 brand 是否匹配
                brand_match = False
                if result_brand:
                    brand_info = self._find_site_by_name(result_brand)
                    if brand_info and brand_info['network'] == expected_network:
                        brand_match = True
                
                # 验证 collections 是否匹配
                collections_match = False
                if result_collections:
                    for collection in result_collections:
                        collection_name = collection.get('name', '')
                        if collection_name:
                            collection_info = self._find_site_by_name(collection_name)
                            if collection_info and collection_info['network'] == expected_network:
                                collections_match = True
                                break
                
                # 如果都不匹配，说明结果不属于指定的系列
                if not brand_match and not collections_match:
                    self.logger.warning(
                        f"搜索结果不属于指定系列 {series_name} (期望网络: {expected_network}), "
                        f"实际 brand: {result_brand}, collections: {[c.get('name') for c in result_collections]}"
                    )
                    return None
        
        if scene_id:
            self.logger.info(f"找到场景 ID: {scene_id}, 获取详细信息 (使用 token: {token_source})")
            scene_data = self._get_scene_by_id(scene_id, token_source)
            if scene_data:
                return self._parse_scene_data(scene_data, token_source)  # 传递 token_source
        
        return None
    
    def _parse_scene_data(self, scene_data: Dict[str, Any], token_source: Optional[str] = None) -> ScrapeResult:
        """解析场景数据"""
        result = self._create_result()
        
        try:
            # 基本信息
            result.title = scene_data.get('title', '')
            result.overview = scene_data.get('description', '')
            
            # 发布日期
            date_released = scene_data.get('dateReleased')
            if date_released:
                try:
                    release_dt = datetime.fromisoformat(date_released.replace('Z', '+00:00'))
                    result.release_date = release_dt.strftime('%Y-%m-%d')
                    result.year = release_dt.year
                except:
                    pass
            
            # 评分
            stats = scene_data.get('stats', {})
            if stats and stats.get('score', 0) > 0:
                result.rating = float(stats['score'])
            
            # 标签/类型
            tags = scene_data.get('tags', [])
            result.genres = [tag['name'] for tag in tags if tag.get('name') and tag.get('isVisible', True)]
            
            # 演员信息（传递 token_source）
            actors = scene_data.get('actors', [])
            if actors:
                actor_ids = [actor['id'] for actor in actors if actor.get('id')]
                actor_details = self._get_actors_by_ids(actor_ids, token_source)
                
                result.actors = []
                for actor in actor_details:
                    actor_name = actor.get('name', '')
                    if actor_name:
                        result.actors.append(actor_name)
            
            # 工作室/网络
            collections = scene_data.get('collections', [])
            brand = scene_data.get('brand', '')
            
            # 直接使用 API 返回的数据，不通过配置文件映射
            # studio 使用 brand（如 "brazzers"）
            # series 使用 collections 的第一个名称（如 "Brazzers Exxtra"）
            if brand:
                result.studio = brand
                self.logger.info(f"从 brand 设置 studio: {result.studio}")
            
            if collections:
                collection_name = collections[0].get('name', '')
                if collection_name:
                    result.series = collection_name
                    self.logger.info(f"从 collections 设置 series: {result.series}")
            elif brand:
                # 如果没有 collections，使用 brand 作为 series
                result.series = brand
                self.logger.info(f"collections 为空，使用 brand 作为 series: {result.series}")
            
            # 图片
            images = scene_data.get('images', {})
            if images:
                # 海报图片
                poster_images = images.get('poster', {})
                poster_urls = self._process_images(poster_images, 1)
                if poster_urls:
                    result.poster_url = poster_urls[0]
                
                # 截图作为预览图片
                result.preview_urls = self._process_images(poster_images, 10)
            
            # 预览视频
            videos = scene_data.get('videos', {})
            self.logger.debug(f"videos 字段: {videos}")
            if videos:
                self.logger.debug(f"videos 类型: {type(videos)}, 键: {list(videos.keys())}")
                # 提取视频（结构化格式）
                video_list = self._process_videos(videos)
                if video_list:
                    # MindGeek 的视频是短小的预览视频，适合作为封面视频（悬停播放）
                    # 只取第一个视频（最高清晰度）作为封面视频，其余的丢弃
                    result.cover_video_url = video_list[0]['url']
                    self.logger.info(f"  ✓ 提取到封面视频 ({video_list[0]['quality']}): {result.cover_video_url[:100]}...")
                else:
                    self.logger.warning(f"  ⚠️ videos 字段存在但未提取到视频URL")
            else:
                self.logger.warning(f"  ⚠️ scene_data 中没有 videos 字段")
            
            # 场景ID作为识别号
            result.code = str(scene_data.get('id', ''))
            
            # 设置媒体类型（直接使用 API 返回的 type 字段）
            # MindGeek API 返回的数据本身就带了 type 字段（scene/movie）
            api_type = scene_data.get('type', 'scene')
            result.media_type = api_type.capitalize()  # 转换为 Scene/Movie
            
            result.source = 'MindGeek'
            result.country = 'US'
            result.language = 'en'
            
            # 详细日志输出
            self.logger.info(f"✓ MindGeek 刮削成功: {result.title}")
            self.logger.info(f"  - 识别号: {result.code}")
            self.logger.info(f"  - 工作室: {result.studio}")
            self.logger.info(f"  - 系列: {result.series}")
            self.logger.info(f"  - 演员数: {len(result.actors)}")
            self.logger.info(f"  - 类型数: {len(result.genres)}")
            self.logger.info(f"  - 预览图数: {len(result.preview_urls)}")
            self.logger.info(f"  - 封面视频: {result.cover_video_url[:80] if result.cover_video_url else 'None'}...")
            self.logger.info(f"  - 预览视频数: {len(result.preview_video_urls)}")
            self.logger.info(f"  - 发布日期: {result.release_date}")
            self.logger.info(f"  - 媒体类型: {result.media_type} (来自API)")
            
            return result
            
        except Exception as e:
            self.logger.error(f"Error parsing scene data: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return result


# 为了兼容性，创建别名
class BrazzersScraper(MindGeekScraper):
    """Brazzers 专用刮削器"""
    name = 'brazzers'


class RealityKingsScraper(MindGeekScraper):
    """RealityKings 专用刮削器"""
    name = 'realitykings'


class BangBrosScraper(MindGeekScraper):
    """BangBros 专用刮削器"""
    name = 'bangbros'


class DigitalPlaygroundScraper(MindGeekScraper):
    """DigitalPlayground 专用刮削器"""
    name = 'digitalplayground'


class MofosScraper(MindGeekScraper):
    """Mofos 专用刮削器"""
    name = 'mofos'


class TwistysScraper(MindGeekScraper):
    """Twistys 专用刮削器"""
    name = 'twistys'


class SexyHubScraper(MindGeekScraper):
    """SexyHub 专用刮削器"""
    name = 'sexyhub'


class FakeHubScraper(MindGeekScraper):
    """FakeHub 专用刮削器"""
    name = 'fakehub'


class MileHighScraper(MindGeekScraper):
    """MileHigh 专用刮削器"""
    name = 'milehigh'


class BabesScraper(MindGeekScraper):
    """Babes 专用刮削器"""
    name = 'babes'


class TransAngelsScraper(MindGeekScraper):
    """TransAngels 专用刮削器"""
    name = 'transangels'


class LetsDoeItScraper(MindGeekScraper):
    """LetsDoeIt 专用刮削器"""
    name = 'letsdoeit'