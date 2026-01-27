"""
JapanHDV Network 刮削器
支持 JapanHDV 及其 11 个子站点
"""

import logging
import re
from typing import Optional, List, Dict, Any
from urllib.parse import urlencode, quote_plus
from pathlib import Path
import csv

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult


logger = logging.getLogger(__name__)


class JapanHDVNetworkScraper(BaseScraper):
    """JapanHDV Network 刮削器"""
    
    name = 'japanhdv_network'
    base_url = 'https://japanhdv.com'
    
    def __init__(self, config: Dict[str, Any]):
        """初始化刮削器"""
        super().__init__(config, use_scraper=True)
        
        # 加载站点配置
        self.sites_config = self._load_sites_config()
        
        self.logger.info(f"JapanHDV Network 刮削器初始化，加载了 {len(self.sites_config)} 个站点")
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """加载站点配置"""
        sites = {}
        config_path = Path(__file__).parent.parent.parent / 'config' / 'site' / 'JapanHDV_Network_sites.csv'
        
        if not config_path.exists():
            self.logger.warning(f"站点配置文件不存在: {config_path}")
            return sites
        
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # 跳过空行和注释行
                    if not row.get('site_name') or row['site_name'].startswith('#'):
                        continue
                    
                    site_name = row['site_name'].strip()
                    if site_name:
                        # 规范化站点名（转小写，用于匹配）
                        normalized_name = re.sub(r'[^a-zA-Z0-9]', '', site_name).lower()
                        sites[normalized_name] = {
                            'name': site_name,
                            'domain': row.get('domain', '').strip(),
                            'code': row.get('code', '').strip(),
                            'network': row.get('network', 'JapanHDV Network').strip(),
                            'enabled': row.get('enabled', 'TRUE').strip().upper() == 'TRUE',
                            'priority': int(row.get('priority', '50').strip() or '50'),
                            'main_api': row.get('main_api', '').strip(),
                        }
            
            self.logger.info(f"成功加载 {len(sites)} 个 JapanHDV Network 站点配置")
            
        except Exception as e:
            self.logger.error(f"加载站点配置失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
        
        return sites
    
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现（单个结果）
        
        Args:
            code: 搜索关键词
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 调用 scrape_multiple 获取所有结果
        results = self.scrape_multiple(code, None, None)
        
        if not results:
            return None
        
        # 返回第一个结果
        return results[0]
    
    def scrape_multiple(
        self,
        title: str,
        content_type_hint: Optional[str] = None,
        series: Optional[str] = None
    ) -> List[ScrapeResult]:
        """
        通过标题搜索，返回多个结果
        
        Args:
            title: 搜索标题
            content_type_hint: 内容类型提示（Scene/Movie）
            series: 系列名（子站点名称）
        
        Returns:
            刮削结果列表
        """
        self.logger.info(f"=" * 80)
        self.logger.info(f"JapanHDV Network 搜索:")
        self.logger.info(f"  标题: {title}")
        self.logger.info(f"  系列: {series}")
        self.logger.info(f"  内容类型: {content_type_hint}")
        self.logger.info(f"=" * 80)
        
        # 确定搜索的站点
        search_domain = self.base_url  # 默认使用主站
        if series:
            # 规范化系列名
            normalized_series = re.sub(r'[^a-zA-Z0-9]', '', series).lower()
            # 查找对应的站点配置
            if normalized_series in self.sites_config:
                site_config = self.sites_config[normalized_series]
                search_domain = f"https://{site_config['domain']}"
                self.logger.info(f"使用子站点搜索: {search_domain}")
        
        # 移除系列名前缀（如 "Japanhdv-" 或 "Japanhdv "）
        search_title = title
        if '-' in title or ' ' in title:
            # 尝试分割系列名
            for separator in ['-', ' ']:
                if separator in title:
                    parts = title.split(separator, 1)
                    if len(parts) == 2:
                        potential_series = parts[0].strip().lower()
                        # 检查是否是已知的系列名
                        if potential_series in self.sites_config or any(potential_series in key for key in self.sites_config.keys()):
                            search_title = parts[1].strip()
                            self.logger.info(f"检测到系列名前缀: {parts[0]}, 移除后搜索: {search_title}")
                            break
        
        # 执行搜索（传递搜索域名）
        search_results = self._search(search_title, search_domain)
        
        if not search_results:
            self.logger.warning(f"未找到搜索结果: {title}")
            return []
        
        self.logger.info(f"找到 {len(search_results)} 个搜索结果")
        
        # 如果指定了系列名（子站点），过滤结果
        if series:
            normalized_series = re.sub(r'[^a-zA-Z0-9]', '', series).lower()
            filtered_results = []
            
            for result in search_results:
                result_site = result.get('site', '').lower()
                result_site_normalized = re.sub(r'[^a-zA-Z0-9]', '', result_site).lower()
                
                if normalized_series in result_site_normalized or result_site_normalized in normalized_series:
                    filtered_results.append(result)
                    self.logger.debug(f"  ✓ 站点匹配: {result_site}")
                else:
                    self.logger.debug(f"  ✗ 站点不匹配: {result_site} != {series}")
            
            if filtered_results:
                self.logger.info(f"站点过滤: {len(search_results)} -> {len(filtered_results)} 个结果")
                search_results = filtered_results
            else:
                self.logger.warning(f"站点过滤后无结果")
                return []
        
        # 为每个搜索结果获取详细信息
        results = []
        for idx, search_result in enumerate(search_results, 1):
            scene_url = search_result.get('url')
            if not scene_url:
                continue
            
            self.logger.info(f"获取详情 {idx}/{len(search_results)}: {search_result.get('title')}")
            
            # 获取场景详细信息
            result = self._scrape_scene(scene_url, search_result)
            if result:
                results.append(result)
        
        self.logger.info(f"成功获取 {len(results)} 个完整结果")
        return results
    
    def _search(self, keyword: str, search_domain: str = None) -> List[Dict[str, Any]]:
        """
        搜索场景
        
        Args:
            keyword: 搜索关键词
            search_domain: 搜索域名（可选，默认使用 base_url）
        
        Returns:
            搜索结果列表 [{'title': '', 'url': '', 'site': '', ...}, ...]
        """
        # 使用指定的搜索域名，如果未指定则使用默认的 base_url
        domain = search_domain if search_domain else self.base_url
        
        # 构建搜索 URL
        search_url = f"{domain}/?s={quote_plus(keyword)}&search=search"
        
        self.logger.info(f"搜索 URL: {search_url}")
        
        try:
            # 发送请求
            response = self.request.get(search_url)
            if not response:
                self.logger.error("搜索请求失败")
                return []
            
            html = response.text
            
            # 解析搜索结果
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(html, 'html.parser')
            
            results = []
            
            # 尝试主站格式 (JapanHDV)
            # 结构: <div class="back"><a class="video-thumb-prev" ...>
            # 注意: 必须检查 video-thumb-prev 类,避免与 TeenThais 的 video-thumb 混淆
            video_cards = soup.find_all('div', class_='back')
            
            # 检查是否真的是主站格式 (必须有 video-thumb-prev)
            is_main_site_format = False
            if video_cards:
                # 检查第一个卡片是否包含 video-thumb-prev
                first_card = video_cards[0]
                if first_card.find('a', class_='video-thumb-prev'):
                    is_main_site_format = True
            
            if is_main_site_format:
                self.logger.info(f"检测到主站格式 (JapanHDV)")
                for card in video_cards:
                    try:
                        # 查找链接
                        link = card.find('a', class_='video-thumb-prev')
                        if not link:
                            continue
                        
                        scene_url = link.get('href', '')
                        title = link.get('title', '')
                        
                        if not scene_url or not title:
                            continue
                        
                        # 缩略图
                        img = link.find('img')
                        thumbnail = img.get('src', '') if img else ''
                        
                        # 时长
                        duration_span = card.find('span', class_='th_video_duration')
                        duration = duration_span.text.strip() if duration_span else ''
                        
                        # 图片数量
                        photo_count_span = card.find('span', class_='th_photo_count')
                        photo_count = 0
                        if photo_count_span:
                            photo_text = photo_count_span.text.strip()
                            photo_count = int(re.sub(r'\D', '', photo_text)) if photo_text else 0
                        
                        # 演员列表
                        actors = []
                        act_list = card.find('div', class_='act_list')
                        if act_list:
                            actor_links = act_list.find_all('a')
                            actors = [a.text.strip() for a in actor_links if a.text.strip()]
                        
                        # 点赞数
                        like_span = card.find('span', class_='like')
                        likes = 0
                        if like_span:
                            like_text = like_span.text.strip()
                            likes = int(re.sub(r'\D', '', like_text)) if like_text else 0
                        
                        results.append({
                            'url': scene_url,
                            'title': title,
                            'thumbnail': thumbnail,
                            'duration': duration,
                            'photo_count': photo_count,
                            'actors': actors,
                            'likes': likes,
                            'site': 'JapanHDV',
                        })
                        
                        self.logger.debug(f"  找到: {title}")
                        
                    except Exception as e:
                        self.logger.error(f"解析视频卡片失败: {e}")
                        continue
            
            # 如果主站格式没找到，尝试 AvidolZ 格式
            if not results:
                # AvidolZ 格式: <ul class="th-grid"><li class="pure-u-1-3"><div class="border">
                th_grid = soup.find('ul', class_='th-grid')
                if th_grid:
                    self.logger.info(f"检测到 AvidolZ 格式")
                    grid_items = th_grid.find_all('li', class_=re.compile(r'pure-u-1-3|pure-u-1-4'))
                    
                    for item in grid_items:
                        try:
                            # 查找链接 - 在 div.rel2 或 div.rel 中
                            link = item.find('a')
                            if not link:
                                continue
                            
                            scene_url = link.get('href', '')
                            title = link.get('title', '')
                            
                            # 如果 title 为空，尝试从 <h3> 标签获取
                            if not title:
                                h3 = item.find('h3')
                                if h3:
                                    h3_link = h3.find('a')
                                    if h3_link:
                                        title = h3_link.text.strip()
                            
                            if not scene_url or not title:
                                continue
                            
                            # 缩略图
                            img = link.find('img')
                            thumbnail = img.get('src', '') if img else ''
                            
                            # 时长
                            duration_span = item.find('span', class_='th_video_duration')
                            duration = duration_span.text.strip() if duration_span else ''
                            
                            # 图片数量
                            photo_count_span = item.find('span', class_='th_photo_count')
                            photo_count = 0
                            if photo_count_span:
                                photo_text = photo_count_span.text.strip()
                                photo_count = int(re.sub(r'\D', '', photo_text)) if photo_text else 0
                            
                            # 确保缩略图有协议前缀
                            if thumbnail and thumbnail.startswith('//'):
                                thumbnail = 'https:' + thumbnail
                            
                            results.append({
                                'url': scene_url,
                                'title': title,
                                'thumbnail': thumbnail,
                                'duration': duration,
                                'photo_count': photo_count,
                                'actors': [],
                                'likes': 0,
                                'site': domain.replace('https://', '').replace('www.', '').split('.')[0].title(),
                            })
                            
                            self.logger.debug(f"  找到: {title}")
                            
                        except Exception as e:
                            self.logger.error(f"解析视频卡片失败: {e}")
                            continue
            
            # 如果还是没找到,尝试子站格式
            if not results:
                # 尝试子站格式1 (Tenshigao, Hamezo) - <div class="thumb-videos flex">
                # 结构: <div class="thumb-videos flex"><div class="thumb"><a class="block2" 或 class="block" ...>
                thumb_videos = soup.find_all('div', class_='thumb-videos')
                
                if thumb_videos:
                    self.logger.info(f"检测到子站格式1 (Tenshigao/Hamezo)")
                    for thumb_div in thumb_videos:
                        try:
                            # 查找链接 - 支持 block2 (Tenshigao) 和 block (Hamezo)
                            link = thumb_div.find('a', class_='block2')
                            if not link:
                                link = thumb_div.find('a', class_='block')
                            if not link:
                                continue
                            
                            scene_url = link.get('href', '')
                            title = link.get('title', '')
                            
                            if not scene_url or not title:
                                continue
                            
                            # 缩略图 - 从 img 标签获取
                            img = link.find('img')
                            thumbnail = ''
                            if img:
                                # 优先使用 src，如果没有则使用 srcset 的第一个
                                thumbnail = img.get('src', '')
                                if not thumbnail and img.get('srcset'):
                                    # srcset 格式: "url1 1x, url2 2x, url3 3x"
                                    srcset = img.get('srcset', '')
                                    if srcset:
                                        first_url = srcset.split(',')[0].strip().split()[0]
                                        thumbnail = first_url
                            
                            # 标题描述 - 从 <p> 标签获取（作为备用标题）
                            desc_p = thumb_div.find('p')
                            description = desc_p.text.strip() if desc_p else ''
                            
                            # 如果 title 为空，使用 description
                            if not title and description:
                                title = description
                            
                            # 确保缩略图有协议前缀
                            if thumbnail and thumbnail.startswith('//'):
                                thumbnail = 'https:' + thumbnail
                            
                            results.append({
                                'url': scene_url,
                                'title': title,
                                'thumbnail': thumbnail,
                                'duration': '',  # 子站搜索页没有时长信息
                                'photo_count': 0,
                                'actors': [],  # 子站搜索页没有演员信息
                                'likes': 0,
                                'site': domain.replace('https://', '').replace('www.', '').split('.')[0].title(),
                            })
                            
                            self.logger.debug(f"  找到: {title}")
                            
                        except Exception as e:
                            self.logger.error(f"解析视频卡片失败: {e}")
                            continue
                else:
                    # 尝试子站格式2 (TeenThais) - <ul><li><div class="back">
                    # 结构: <div class="th-wrapper"><ul><li class="pure-u-1-3"><div class="back"><a class="video-thumb">
                    # 注意: 需要在 th-wrapper 容器内查找,避免找到导航菜单的 ul
                    th_wrapper = soup.find('div', class_='th-wrapper')
                    if th_wrapper:
                        search_ul = th_wrapper.find('ul')
                        if search_ul:
                            # 查找包含 class="back" 的 li 元素
                            li_items = search_ul.find_all('li', class_=re.compile(r'pure-u'))
                            
                            if li_items:
                                self.logger.info(f"检测到子站格式2 (TeenThais)")
                                for li in li_items:
                                    try:
                                        back_div = li.find('div', class_='back')
                                        if not back_div:
                                            continue
                                        
                                        # 查找链接
                                        link = back_div.find('a', class_='video-thumb')
                                        if not link:
                                            continue
                                        
                                        scene_url = link.get('href', '')
                                        title = link.get('title', '')
                                        
                                        # 如果 title 为空，尝试从 <h3> 标签获取
                                        if not title:
                                            h3 = back_div.find('h3')
                                            if h3:
                                                title = h3.text.strip()
                                        
                                        if not scene_url or not title:
                                            continue
                                        
                                        # 缩略图
                                        img = link.find('img')
                                        thumbnail = img.get('src', '') if img else ''
                                        
                                        # 时长
                                        duration_span = back_div.find('span', class_='duration')
                                        duration = duration_span.text.strip() if duration_span else ''
                                        
                                        # 演员
                                        actors = []
                                        actress_span = back_div.find('span', class_='actress')
                                        if actress_span:
                                            actor_links = actress_span.find_all('a')
                                            actors = [a.text.strip() for a in actor_links if a.text.strip()]
                                        
                                        # 点赞数
                                        like_span = back_div.find('span', class_='like')
                                        likes = 0
                                        if like_span:
                                            like_text = like_span.text.strip()
                                            # 格式: "81%"
                                            likes = int(re.sub(r'\D', '', like_text)) if like_text else 0
                                        
                                        # 确保缩略图有协议前缀
                                        if thumbnail and thumbnail.startswith('//'):
                                            thumbnail = 'https:' + thumbnail
                                        
                                        results.append({
                                            'url': scene_url,
                                            'title': title,
                                            'thumbnail': thumbnail,
                                            'duration': duration,
                                            'photo_count': 0,
                                            'actors': actors,
                                            'likes': likes,
                                            'site': domain.replace('https://', '').replace('www.', '').split('.')[0].title(),
                                        })
                                        
                                        self.logger.debug(f"  找到: {title}")
                                        
                                    except Exception as e:
                                        self.logger.error(f"解析视频卡片失败: {e}")
                                        continue
                            else:
                                self.logger.warning(f"未找到任何已知格式的搜索结果")
                        else:
                            self.logger.warning(f"未找到任何已知格式的搜索结果")
                    else:
                        self.logger.warning(f"未找到任何已知格式的搜索结果")
            
            self.logger.info(f"解析到 {len(results)} 个搜索结果")
            return results
            
        except Exception as e:
            self.logger.error(f"搜索失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []
    
    def _scrape_scene(self, scene_url: str, search_result: Dict[str, Any]) -> Optional[ScrapeResult]:
        """
        刮削场景详细信息
        
        Args:
            scene_url: 场景 URL
            search_result: 搜索结果（包含基本信息）
        
        Returns:
            ScrapeResult 对象
        """
        self.logger.info(f"刮削场景: {scene_url}")
        
        try:
            # 发送请求
            response = self.request.get(scene_url)
            if not response:
                self.logger.error("场景页面请求失败")
                return None
            
            html = response.text
            
            # 解析 HTML
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(html, 'html.parser')
            
            # 创建结果对象
            result = ScrapeResult()
            
            # 标题 - 尝试两种格式
            # 格式1: JapanHDV 主站 <h1 class="bg">
            title_h1 = soup.find('h1', class_='bg')
            if title_h1:
                # 移除 icon span
                for icon in title_h1.find_all('span', class_='icon-video'):
                    icon.decompose()
                result.title = title_h1.text.strip()
            else:
                # 格式2: Hamezo 等子站 <h1 class="center">
                title_h1 = soup.find('h1', class_='center')
                if title_h1:
                    result.title = title_h1.text.strip()
                else:
                    result.title = search_result.get('title', '')
            
            # 视频信息区域 - JapanHDV 主站格式
            video_info = soup.find('div', class_='video-info')
            
            if video_info:
                # 演员
                actress_p = video_info.find('strong', string='Actress: ')
                if actress_p:
                    actress_links = actress_p.parent.find_all('a')
                    result.actors = [a.text.strip() for a in actress_links if a.text.strip()]
                
                # 时长 (Duration: 61Min 00sec)
                duration_p = video_info.find('strong', string='Duration:')
                if duration_p:
                    duration_text = duration_p.parent.text.replace('Duration:', '').strip()
                    # 解析时长 "61Min 00sec" -> 61 分钟
                    match = re.search(r'(\d+)Min', duration_text)
                    if match:
                        result.runtime = int(match.group(1))
                
                # 分辨率
                resolution_p = video_info.find('strong', string='Resolution:')
                if resolution_p:
                    resolution_text = resolution_p.parent.text.replace('Resolution:', '').strip()
                    # 可以存储到 metadata 中
                
                # 类型/标签
                categories_p = video_info.find('strong', string='Categories: ')
                if categories_p:
                    category_links = categories_p.parent.find_all('a')
                    result.genres = [a.text.strip() for a in category_links if a.text.strip()]
                
                # 系列
                series_p = video_info.find('strong', string='Series: ')
                if series_p:
                    series_link = series_p.parent.find('a')
                    if series_link:
                        result.series = series_link.text.strip()
                
                # 图片数量
                photos_p = video_info.find('strong', string='High Res Pictures:')
                if photos_p:
                    photos_text = photos_p.parent.text.replace('High Res Pictures:', '').strip()
                    # 可以存储到 metadata 中
            else:
                # Hamezo/SuckMeVR 等子站格式 - 从 video-details 或直接从页面提取
                video_details = soup.find('div', class_='video-details')
                if video_details:
                    # 时长 - 从 video-duration 提取
                    duration_div = video_details.find('div', class_='video-duration')
                    if duration_div:
                        duration_text = duration_div.text.strip()
                        # 解析时长 "35:09" -> 35 分钟
                        match = re.search(r'(\d+):(\d+)', duration_text)
                        if match:
                            result.runtime = int(match.group(1))
                    
                    # 发布日期 - 从 video-date 提取
                    date_div = video_details.find('div', class_='video-date')
                    if date_div:
                        date_text = date_div.text.strip()
                        # 解析日期 "March 29th, 2025" -> 2025-03-29
                        try:
                            from datetime import datetime
                            # 移除序数词后缀 (st, nd, rd, th)
                            date_text_clean = re.sub(r'(\d+)(st|nd|rd|th)', r'\1', date_text)
                            parsed_date = datetime.strptime(date_text_clean, '%B %d, %Y')
                            result.release_date = parsed_date.strftime('%Y-%m-%d')
                            result.year = parsed_date.year
                        except Exception as e:
                            self.logger.warning(f"解析日期失败: {date_text} - {e}")
                else:
                    # SuckMeVR 格式 - 元数据在 <ul> 列表中
                    # 时长 - 从 video-duration div 提取
                    duration_div = soup.find('div', class_='video-duration')
                    if duration_div:
                        duration_text = duration_div.text.strip()
                        # 解析时长 "21:38" -> 21 分钟
                        match = re.search(r'(\d+):(\d+)', duration_text)
                        if match:
                            result.runtime = int(match.group(1))
                    
                    # 发布日期 - 从 video-date div 提取
                    date_div = soup.find('div', class_='video-date')
                    if date_div:
                        date_text = date_div.text.strip()
                        # 解析日期 "May 08th, 2024" -> 2024-05-08
                        try:
                            from datetime import datetime
                            # 移除序数词后缀 (st, nd, rd, th)
                            date_text_clean = re.sub(r'(\d+)(st|nd|rd|th)', r'\1', date_text)
                            parsed_date = datetime.strptime(date_text_clean, '%B %d, %Y')
                            result.release_date = parsed_date.strftime('%Y-%m-%d')
                            result.year = parsed_date.year
                        except Exception as e:
                            self.logger.warning(f"解析日期失败: {date_text} - {e}")
                    
                    # 图片数量 - 从 video-photos div 提取（可选，存储到 metadata）
                    photos_div = soup.find('div', class_='video-photos')
                    if photos_div:
                        photos_text = photos_div.text.strip()
                        # 可以存储到 metadata 中
                
                # 演员 - 从描述段落中的链接提取
                # 查找包含 /pornstar/ 的链接
                actor_links = soup.find_all('a', href=re.compile(r'/pornstar/'))
                if actor_links:
                    result.actors = [a.text.strip() for a in actor_links if a.text.strip()]
                
                # 类别/标签 - 从 cat div 中的链接提取（SuckMeVR 格式）
                if not result.genres:
                    cat_divs = soup.find_all('div', class_='cat')
                    for cat_div in cat_divs:
                        # 跳过演员链接（已经处理过）
                        if cat_div.find('a', href=re.compile(r'/pornstar/')):
                            continue
                        # 提取类别链接
                        category_links = cat_div.find_all('a', rel='tag')
                        if category_links:
                            result.genres = [a.text.strip() for a in category_links if a.text.strip()]
                            break
            
            # 简介 (description) - 从段落提取
            description_p = soup.find('p')
            if description_p:
                # 移除 "Read More" 按钮和其他不需要的元素
                for span in description_p.find_all('span', class_=['dots', 'readmore']):
                    span.decompose()
                result.overview = description_p.text.strip()
            
            # 封面图 (poster) - 从视频播放器获取
            self.logger.info(f"开始提取封面图...")
            video_poster = soup.find('div', class_='vjs-poster')
            if video_poster:
                self.logger.info(f"找到 vjs-poster 元素")
                poster_style = video_poster.get('style', '')
                self.logger.info(f"poster style: {poster_style[:200]}")
                # 提取 background-image: url("...")
                match = re.search(r'url\(["\']?([^"\']+)["\']?\)', poster_style)
                if match:
                    poster_url = match.group(1)
                    if poster_url.startswith('//'):
                        poster_url = 'https:' + poster_url
                    result.poster_url = poster_url
                    self.logger.info(f"✓ 从 vjs-poster 提取封面: {poster_url}")
                else:
                    self.logger.warning(f"vjs-poster 中未找到 background-image URL")
            else:
                self.logger.warning(f"未找到 vjs-poster 元素")
            
            # 备用方案1: 从搜索结果中获取缩略图
            if not result.poster_url and search_result.get('thumbnail'):
                poster_url = search_result['thumbnail']
                if poster_url.startswith('//'):
                    poster_url = 'https:' + poster_url
                result.poster_url = poster_url
                self.logger.info(f"✓ 使用搜索结果缩略图作为封面: {result.poster_url}")
            
            # 备用方案2: 从 og:image meta 标签获取
            if not result.poster_url:
                og_image = soup.find('meta', property='og:image')
                if og_image:
                    poster_url = og_image.get('content', '')
                    if poster_url:
                        if poster_url.startswith('//'):
                            poster_url = 'https:' + poster_url
                        result.poster_url = poster_url
                        self.logger.info(f"✓ 从 og:image 提取封面: {poster_url}")
                else:
                    self.logger.warning(f"未找到 og:image meta 标签")
            
            # 备用方案3: 从第一张预览图获取
            if not result.poster_url:
                carousel = soup.find('ul', id='preview')
                if carousel:
                    first_img = carousel.find('a')
                    if first_img:
                        img_url = first_img.get('href', '')
                        if img_url:
                            if img_url.startswith('//'):
                                img_url = 'https:' + img_url
                            result.poster_url = img_url
                            self.logger.info(f"✓ 使用第一张预览图作为封面: {img_url}")
            
            if not result.poster_url:
                self.logger.warning(f"所有封面图提取方案都失败了")
            
            # 预览图片 (从轮播图获取)
            preview_images = []
            
            # 尝试主站格式 (JapanHDV/AvidolZ) - <ul id="preview"> 或 <ul class="caroussel" id="preview">
            carousel = soup.find('ul', id='preview')
            if carousel:
                # 检测是否有 caroussel class (AvidolZ 格式)
                if 'caroussel' in carousel.get('class', []):
                    self.logger.info(f"检测到 AvidolZ 预览图格式 (caroussel)")
                else:
                    self.logger.info(f"检测到主站预览图格式 (JapanHDV)")
                
                img_links = carousel.find_all('a')
                for link in img_links:
                    img_url = link.get('href', '')
                    if img_url:
                        if img_url.startswith('//'):
                            img_url = 'https:' + img_url
                        preview_images.append(img_url)
            else:
                # 尝试子站格式 (Hamezo) - <ul id="lightgallery">
                gallery = soup.find('ul', id='lightgallery')
                if gallery:
                    self.logger.info(f"检测到子站预览图格式 (Hamezo)")
                    gallery_items = gallery.find_all('li')
                    for item in gallery_items:
                        # 优先使用 data-src 属性
                        img_url = item.get('data-src', '')
                        if not img_url:
                            # 备用：从 <a> 标签的 href 获取
                            link = item.find('a', class_='gal')
                            if link:
                                img_url = link.get('href', '')
                        
                        if img_url:
                            if img_url.startswith('//'):
                                img_url = 'https:' + img_url
                            preview_images.append(img_url)
                else:
                    self.logger.warning(f"未找到预览图（尝试了 #preview 和 #lightgallery）")
            
            result.preview_urls = preview_images
            self.logger.info(f"提取到 {len(preview_images)} 张预览图")
            
            # 预览视频 (trailer)
            video_source = soup.find('source', {'data-res': 'HD'})
            if not video_source:
                # 尝试查找任何 source 标签
                video_source = soup.find('source', type='video/mp4')
            
            if video_source:
                trailer_url = video_source.get('src', '')
                if trailer_url:
                    if trailer_url.startswith('//'):
                        trailer_url = 'https:' + trailer_url
                    result.preview_video_urls = [{'quality': 'HD', 'url': trailer_url}]
            
            # 基本信息
            result.studio = 'JapanHDV Network'
            result.media_type = 'Scene'
            result.code = scene_url.split('/')[-2] if '/' in scene_url else ''
            
            self.logger.info(f"✓ 刮削成功: {result.title}")
            self.logger.info(f"  演员: {', '.join(result.actors) if result.actors else 'N/A'}")
            self.logger.info(f"  时长: {result.runtime} 分钟" if result.runtime else "  时长: N/A")
            self.logger.info(f"  发布日期: {result.release_date or 'N/A'}")
            self.logger.info(f"  类型: {', '.join(result.genres[:5]) if result.genres else 'N/A'}")
            self.logger.info(f"  系列: {result.series or 'N/A'}")
            self.logger.info(f"  封面图: {result.poster_url or 'N/A'}")
            self.logger.info(f"  预览图: {len(result.preview_urls)} 张")
            
            return result
            
        except Exception as e:
            self.logger.error(f"刮削场景失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return None
