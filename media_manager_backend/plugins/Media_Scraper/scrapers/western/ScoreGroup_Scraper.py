#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ScoreGroup_Scraper.py

Score Group / PornMegaLoad Network Scraper
支持 70+ 个大胸/BBW/熟女系列站点

网站: www.pornmegaload.com, www.scoreland.com, www.xlgirls.com 等
"""

import re
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime
from lxml import html

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError


logger = logging.getLogger(__name__)


class ScoreGroupScraper(BaseScraper):
    """Score Group 网络刮削器"""
    
    name = 'scoregroup'
    
    def __init__(self, config):
        """初始化刮削器"""
        super().__init__(config, use_scraper=True)
        self.logger.info("Score Group 刮削器初始化")
        
        # 加载站点配置
        self.sites_config = self._load_sites_config()
    
    def _scrape_impl(self, query: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            query: URL 或搜索关键词
        
        Returns:
            ScrapeResult 对象（包含完整详细信息）
        """
        # 检查是否为 URL
        if query.startswith('http://') or query.startswith('https://'):
            return self._scrape_by_url(query)
        else:
            # 标题搜索：返回第一个结果（已包含完整信息）
            results = self.scrape_multiple(query)
            return results[0] if results else None
    
    def scrape_multiple(self, query: str, content_type_hint: Optional[str] = None, 
                       series: Optional[str] = None) -> List[ScrapeResult]:
        """
        通过标题搜索多个结果
        
        Args:
            query: 搜索关键词
            content_type_hint: 内容类型（暂不使用）
            series: 系列名（站点名，如 pornmegaload, scoreland）
        
        Returns:
            搜索结果列表（包含完整详细信息）
        """
        self.logger.info(f"开始搜索: query={query}, series={series}")
        
        # 移除系列名前缀（如 "Xlgirls-" 或 "Xlgirls "）
        search_query = query
        if '-' in query or ' ' in query:
            # 尝试分割系列名
            for separator in ['-', ' ']:
                if separator in query:
                    parts = query.split(separator, 1)
                    if len(parts) == 2:
                        potential_series = parts[0].strip().lower()
                        # 检查是否是已知的系列名
                        if potential_series in self.sites_config or any(potential_series in key for key in self.sites_config.keys()):
                            search_query = parts[1].strip()
                            self.logger.info(f"检测到系列名前缀: {parts[0]}, 移除后搜索: {search_query}")
                            break
        
        # 1. 确定搜索的站点
        if series:
            site_config = self._get_site_config(series)
            if not site_config:
                self.logger.warning(f"未找到站点配置: {series}，使用默认站点")
                site_config = self._get_site_config('pornmegaload')
        else:
            # 默认使用 pornmegaload
            site_config = self._get_site_config('pornmegaload')
        
        if not site_config:
            self.logger.error("无法获取站点配置")
            return []
        
        # 2. 构建搜索 URL
        # 使用 GET 方式: https://www.{domain}/{video_url_part}/?search={keyword}
        from urllib.parse import quote
        encoded_query = quote(search_query)  # 使用移除系列名后的查询
        search_url = f"https://{site_config['domain']}/{site_config['video_url_part']}/?search={encoded_query}"
        
        self.logger.info(f"搜索 URL: {search_url}")
        
        try:
            # 3. 请求搜索页面
            response = self.request.get(search_url)
            
            if response.status_code != 200:
                self.logger.error(f"搜索请求失败: {response.status_code}")
                return []
            
            # 4. 解析搜索结果页面 - 先提取轻量级信息
            tree = html.fromstring(response.content)
            lightweight_results = self._extract_search_results(tree, site_config)
            
            self.logger.info(f"找到 {len(lightweight_results)} 个搜索结果")
            
            # 5. 对每个结果获取详细信息
            results = []
            max_results = 20  # 默认最多返回 20 个结果
            
            for i, light_result in enumerate(lightweight_results[:max_results], 1):
                try:
                    self.logger.info(f"获取详细信息 {i}/{min(len(lightweight_results), max_results)}: {light_result.title}")
                    
                    # 获取完整详细信息
                    full_result = self._scrape_by_url(light_result.url)
                    if full_result:
                        results.append(full_result)
                except Exception as e:
                    self.logger.error(f"获取详细信息失败: {light_result.url} - {e}")
                    continue
            
            self.logger.info(f"搜索完成，成功获取 {len(results)} 个场景的详细信息")
            return results
            
        except Exception as e:
            self.logger.error(f"搜索失败: {e}")
            import traceback
            traceback.print_exc()
            return []
    
    def _extract_search_results(self, tree, site_config: Dict[str, Any]) -> List[ScrapeResult]:
        """
        从搜索结果页面提取基本信息（轻量级，不请求详情页）
        
        Args:
            tree: lxml HTML 树
            site_config: 站点配置
        
        Returns:
            轻量级搜索结果列表
        """
        results = []
        video_url_part = site_config['video_url_part']
        
        # 查找所有场景容器
        # 搜索结果通常在 <div class="li-item video"> 或类似结构中
        scene_containers = tree.xpath("//div[contains(@class, 'li-item') and contains(@class, 'video')]")
        
        if not scene_containers:
            # 备用选择器
            scene_containers = tree.xpath(f"//a[contains(@href, '/{video_url_part}/')]/..")
        
        self.logger.info(f"找到 {len(scene_containers)} 个场景容器")
        
        seen_urls = set()
        max_results = 20
        
        for container in scene_containers[:max_results]:
            try:
                # 提取场景链接
                scene_link = container.xpath(f".//a[contains(@href, '/{video_url_part}/')]/@href")
                if not scene_link:
                    continue
                
                scene_url = scene_link[0]
                
                # 补全 URL
                if scene_url.startswith('/'):
                    scene_url = f"https://{site_config['domain']}{scene_url}"
                elif not scene_url.startswith('http'):
                    scene_url = f"https://{site_config['domain']}/{scene_url}"
                
                # 去重（只保留路径部分）
                url_path = scene_url.split('?')[0]
                if url_path in seen_urls:
                    continue
                seen_urls.add(url_path)
                
                # 验证是否为有效的场景链接
                scene_pattern = re.compile(rf'/{video_url_part}/[^/]+/\d+/?')
                if not scene_pattern.search(url_path):
                    continue
                
                # 提取标题（优先级：链接文本 > img alt > URL）
                title = None
                
                # 方法1: 从链接文本获取（最完整）
                link_texts = container.xpath(f".//a[contains(@href, '/{video_url_part}')]//text()")
                if link_texts:
                    # 合并所有文本，过滤空白
                    full_text = ' '.join([t.strip() for t in link_texts if t.strip()])
                    # 如果文本长度合理（不是太短也不是太长），使用它
                    if 10 < len(full_text) < 200:
                        title = full_text
                
                # 方法2: 从图片 alt 属性获取（备用）
                if not title:
                    img_alts = container.xpath(".//img/@alt")
                    if img_alts:
                        title = img_alts[0].strip()
                
                # 方法3: 从 URL 提取（最后的备用方案）
                if not title:
                    url_parts = url_path.rstrip('/').split('/')
                    if len(url_parts) >= 2:
                        title = url_parts[-2].replace('-', ' ')
                
                # 提取缩略图
                poster_url = None
                img_src = container.xpath(".//img/@src")
                if img_src:
                    poster_url = img_src[0]
                    if poster_url.startswith('//'):
                        poster_url = 'https:' + poster_url
                
                # 创建轻量级结果对象
                result = self._create_result()
                result.title = title
                result.url = scene_url
                result.poster_url = poster_url
                result.studio = self._extract_studio_from_url(scene_url)
                result.series = result.studio
                
                results.append(result)
                
                self.logger.debug(f"提取搜索结果: {title} - {scene_url}")
                
            except Exception as e:
                self.logger.error(f"提取搜索结果失败: {e}")
                continue
        
        return results
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """
        加载站点配置
        
        Returns:
            站点配置字典 {site_key: config}
        """
        import csv
        
        # 修正路径：从当前文件向上两级到 config/site
        config_file = Path(__file__).parent.parent.parent / 'config' / 'site' / 'score_group_sites.csv'
        
        if not config_file.exists():
            self.logger.error(f"站点配置文件不存在: {config_file}")
            return {}
        
        sites = {}
        
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # 生成站点 key（从域名提取）
                    domain = row['domain']
                    site_key = domain.replace('www.', '').replace('.com', '').replace('.tv', '').replace('.uk', '').replace('.co', '')
                    
                    sites[site_key] = {
                        'name': row['site_name'],
                        'domain': domain,
                        'video_url_part': row['video_url_part'],
                        'supports_genres': row['supports_genres'].lower() == 'true',
                        'supports_release_date': row['supports_release_date'].lower() == 'true',
                        'priority': int(row.get('priority', 50))
                    }
            
            self.logger.info(f"加载了 {len(sites)} 个站点配置")
            
        except Exception as e:
            self.logger.error(f"加载站点配置失败: {e}")
        
        return sites
    
    def _get_site_config(self, site_key: str) -> Optional[Dict[str, Any]]:
        """
        获取站点配置
        
        Args:
            site_key: 站点标识（如 pornmegaload, scoreland）
        
        Returns:
            站点配置字典
        """
        # 规范化 site_key
        site_key = site_key.lower().replace(' ', '').replace('-', '').replace('_', '')
        
        # 直接查找
        if site_key in self.sites_config:
            return self.sites_config[site_key]
        
        # 模糊匹配
        for key, config in self.sites_config.items():
            if site_key in key or key in site_key:
                return config
        
        self.logger.warning(f"未找到站点配置: {site_key}")
        return None
    
    def get_full_details(self, result: ScrapeResult) -> Optional[ScrapeResult]:
        """
        获取搜索结果的完整详细信息
        
        Args:
            result: 轻量级搜索结果（必须包含 url 字段）
        
        Returns:
            完整的 ScrapeResult 对象
        """
        if not result.url:
            self.logger.error("搜索结果缺少 URL，无法获取详细信息")
            return None
        
        self.logger.info(f"获取详细信息: {result.title} - {result.url}")
        
        try:
            # 调用 URL 刮削方法获取完整信息
            full_result = self._scrape_by_url(result.url)
            return full_result
        except Exception as e:
            self.logger.error(f"获取详细信息失败: {e}")
            return None
    
    def _scrape_by_url(self, url: str) -> Optional[ScrapeResult]:
        """
        通过 URL 刮削
        
        Args:
            url: 视频页面 URL
        
        Returns:
            ScrapeResult 对象
        """
        self.logger.info(f"开始刮削 URL: {url}")
        
        # 请求页面
        try:
            response = self.request.get(url)
            
            if response.status_code == 404:
                raise MovieNotFoundError(self.name, url)
            
            # 解析 HTML
            tree = html.fromstring(response.content)
            
            # 提取数据
            return self._parse_html(tree, url)
            
        except MovieNotFoundError:
            raise
        except Exception as e:
            self.logger.error(f"刮削失败: {e}")
            raise
    
    def _parse_html(self, tree, url: str) -> ScrapeResult:
        """
        解析 HTML 提取数据
        
        Args:
            tree: lxml HTML 树
            url: 页面 URL
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        # 1. 定位视频容器
        container = tree.xpath("//section[contains(@id, '_page-page')]")
        if not container:
            container = tree.xpath("//div[@id='content']//section[1]")
        
        if container:
            container = container[0]
        else:
            self.logger.warning("未找到视频容器，使用整个文档")
            container = tree
        
        # 2. 提取标题
        result.title = self._extract_title(container)
        
        # 3. 提取演员
        result.actors = self._extract_actors(container)
        
        # 4. 提取发行日期
        result.release_date = self._extract_release_date(container)
        if result.release_date:
            try:
                result.year = int(result.release_date.split('-')[0])
            except:
                pass
        
        # 5. 提取时长
        result.runtime = self._extract_runtime(container)
        
        # 6. 提取评分
        result.rating = self._extract_rating(container)
        
        # 7. 提取类型标签
        result.genres = self._extract_genres(container)
        
        # 8. 提取简介
        result.overview = self._extract_overview(container)
        
        # 9. 提取图片资源
        self._extract_images(container, tree, result)
        
        # 10. 提取视频资源
        self._extract_videos(container, result)
        
        # 11. 提取制作商和系列（从 URL 推断）
        result.studio = self._extract_studio_from_url(url)
        result.series = result.studio  # Score Group 的 series 就是站点名
        
        self.logger.info(f"刮削完成: {result.title}")
        
        return result
    
    def _extract_title(self, container) -> Optional[str]:
        """提取标题"""
        try:
            # 移除 accent-text span
            accent_spans = container.xpath(".//h1//span[contains(@class, 'accent-text')]")
            for span in accent_spans:
                span.getparent().remove(span)
            
            # 获取标题文本
            title_nodes = container.xpath(".//h1//text()")
            if title_nodes:
                raw_title = ''.join(title_nodes).strip()
                
                # 清理标题（移除 » 后面的网站名）
                if '»' in raw_title:
                    title = raw_title.split('»')[-1].strip()
                else:
                    title = raw_title
                
                # 规范化空格和引号
                title = title.replace(" '", "'")
                
                return title
        except Exception as e:
            self.logger.error(f"提取标题失败: {e}")
        
        return None
    
    def _extract_actors(self, container) -> List[str]:
        """提取演员列表"""
        actors = []
        
        try:
            # 方法1: 从链接获取
            actor_links = container.xpath(".//span[contains(text(), 'Featuring')]/parent::div//a")
            if actor_links:
                for link in actor_links:
                    actor_name = link.text_content().strip()
                    if actor_name:
                        actors.append(actor_name)
            else:
                # 方法2: 从文本获取
                actor_text_nodes = container.xpath(".//span[contains(text(), 'Featuring')]/following-sibling::span")
                if actor_text_nodes:
                    actor_text = actor_text_nodes[0].text_content().strip()
                    # 分割演员名（用 and 和 , 分割）
                    for separator in [' and ', ',']:
                        actor_text = actor_text.replace(separator, '|')
                    actors = [name.strip() for name in actor_text.split('|') if name.strip()]
        except Exception as e:
            self.logger.error(f"提取演员失败: {e}")
        
        return actors
    
    def _extract_release_date(self, container) -> Optional[str]:
        """提取发行日期"""
        try:
            # 尝试从 span 标签获取
            date_node = container.xpath(".//div[contains(@class, 'stat')]//span[contains(text(), 'Date:')]/following-sibling::span")
            if not date_node:
                # 尝试从文本节点获取
                date_node = container.xpath(".//div[contains(@class, 'stat')]//span[contains(text(), 'Date:')]/following-sibling::text()")
            
            if date_node:
                date_text = date_node[0].text_content().strip() if hasattr(date_node[0], 'text_content') else date_node[0].strip()
                
                # 移除序数标记（1st, 2nd, 3rd, 4th -> 1, 2, 3, 4）
                date_text = re.sub(r'(\d+)(st|nd|rd|th)', r'\1', date_text)
                
                # 解析日期
                # 格式1: January 24, 2026
                try:
                    date_obj = datetime.strptime(date_text, '%B %d, %Y')
                    return date_obj.strftime('%Y-%m-%d')
                except:
                    pass
                
                # 格式2: 01/24/2026
                try:
                    date_obj = datetime.strptime(date_text, '%m/%d/%Y')
                    return date_obj.strftime('%Y-%m-%d')
                except:
                    pass
                
                self.logger.warning(f"无法解析日期格式: {date_text}")
        except Exception as e:
            self.logger.error(f"提取发行日期失败: {e}")
        
        return None
    
    def _extract_runtime(self, container) -> Optional[int]:
        """提取时长（分钟）"""
        try:
            duration_node = container.xpath(".//div[contains(@class, 'stat')]//span[contains(text(), 'Duration')]/following-sibling::span")
            if not duration_node:
                duration_node = container.xpath(".//div[contains(@class, 'stat')]//span[contains(text(), 'Duration')]/following-sibling::text()")
            
            if duration_node:
                duration_text = duration_node[0].text_content().strip() if hasattr(duration_node[0], 'text_content') else duration_node[0].strip()
                
                # 格式1: 23:32 (mm:ss)
                if ':' in duration_text:
                    duration_text = duration_text.replace('min.', '').strip()
                    parts = duration_text.split(':')
                    if len(parts) == 2:
                        minutes = int(parts[0])
                        return minutes
                    elif len(parts) == 3:  # hh:mm:ss
                        hours = int(parts[0])
                        minutes = int(parts[1])
                        return hours * 60 + minutes
                else:
                    # 格式2: 23 (纯数字)
                    return int(duration_text)
        except Exception as e:
            self.logger.error(f"提取时长失败: {e}")
        
        return None
    
    def _extract_rating(self, container) -> Optional[float]:
        """提取评分"""
        try:
            rating_node = container.xpath(".//span[@class='rate-score']")
            if not rating_node:
                rating_node = container.xpath(".//small[@class='rate-score']")
            
            if rating_node:
                rating_text = rating_node[0].text_content().strip()
                # 移除星号
                rating_text = rating_text.replace('★', '').strip()
                
                # 提取数字（格式: "4.5" 或 "4.5 / 5"）
                match = re.search(r'(\d+\.?\d*)', rating_text)
                if match:
                    rating_value = float(match.group(1))
                    # Score Group 使用 5 星制，转换为 10 分制
                    return rating_value * 2
        except Exception as e:
            self.logger.error(f"提取评分失败: {e}")
        
        return None
    
    def _extract_genres(self, container) -> List[str]:
        """提取类型标签"""
        genres = []
        
        try:
            genre_nodes = container.xpath(".//div[./h3[contains(text(), 'Related Tags')]]//a[not(contains(@class, 'accent-text'))]")
            for node in genre_nodes:
                genre = node.text_content().strip()
                if genre:
                    genres.append(genre)
        except Exception as e:
            self.logger.error(f"提取类型标签失败: {e}")
        
        return genres
    
    def _extract_overview(self, container) -> Optional[str]:
        """提取简介"""
        try:
            desc_nodes = container.xpath(".//div[@class='p-desc']")
            if not desc_nodes:
                desc_nodes = container.xpath(".//div[contains(@class, 'desc')]")
            
            if desc_nodes:
                # 获取所有文本内容
                overview = desc_nodes[0].text_content().strip()
                # 清理多余空白
                overview = re.sub(r'\s+', ' ', overview)
                return overview
        except Exception as e:
            self.logger.error(f"提取简介失败: {e}")
        
        return None
    
    def _extract_images(self, container, tree, result: ScrapeResult):
        """提取图片资源"""
        try:
            # 1. OG 图片（封面）
            og_image = tree.xpath("//meta[@property='og:image']/@content")
            if og_image:
                result.poster_url = og_image[0]
            
            # 2. 预览图（图片库）- 通过 CDN 规律推导
            preview_urls = []
            
            # 先获取第一张图片的 URL（用于提取 URL 模式）
            gallery_thumbs = container.xpath(".//div[contains(@class, 'gallery')]//div[contains(@class, 'thumb')]//a/@href")
            
            # 找到第一个有效的 CDN 链接（不是会员链接）
            first_valid_url = None
            for thumb_url in gallery_thumbs:
                if 'join.' not in thumb_url and 'cdn77.scoreuniverse.com' in thumb_url:
                    first_valid_url = thumb_url
                    break
            
            if first_valid_url:
                # 从第一张图片 URL 推导出所有预览图
                # URL 格式: https://cdn77.scoreuniverse.com/scoreland/scenes/{scene_id}/Gallys/{site}/01.jpg
                # 推导: 01.jpg -> 02.jpg, 03.jpg, ... 16.jpg
                
                # 提取 URL 前缀（去掉编号和扩展名）
                match = re.match(r'(.*/)\d+\.jpg$', first_valid_url)
                if match:
                    url_prefix = match.group(1)
                    
                    # 生成所有预览图 URL（通常有 16 张）
                    for i in range(1, 17):  # 01-16
                        preview_url = f"{url_prefix}{i:02d}.jpg"
                        preview_urls.append(preview_url)
                    
                    self.logger.debug(f"通过 CDN 规律推导出 {len(preview_urls)} 张预览图")
                else:
                    # 如果无法匹配模式，回退到原始逻辑
                    self.logger.debug("无法匹配 URL 模式，使用原始逻辑")
                    for thumb_url in gallery_thumbs:
                        if 'join.' not in thumb_url:
                            preview_urls.append(thumb_url)
            else:
                # 如果没有找到有效的 CDN 链接，使用原始逻辑
                self.logger.debug("未找到有效的 CDN 链接，使用原始逻辑")
                for thumb_url in gallery_thumbs:
                    if 'join.' not in thumb_url:
                        preview_urls.append(thumb_url)
            
            result.preview_urls = preview_urls
            
            self.logger.info(f"提取图片: 封面={bool(result.poster_url)}, 预览图={len(preview_urls)}张")
            
        except Exception as e:
            self.logger.error(f"提取图片失败: {e}")
    
    def _extract_videos(self, container, result: ScrapeResult):
        """提取视频资源"""
        try:
            video_node = container.xpath(".//video")
            if not video_node:
                return
            
            video = video_node[0]
            
            # 1. 提取 trailer 视频（预览视频）
            sources = video.xpath(".//source")
            trailer_urls = []
            
            for source in sources:
                src = source.get('src', '')
                if src:
                    # 补全协议
                    if src.startswith('//'):
                        src = 'https:' + src
                    
                    # 提取分辨率
                    quality = 'Unknown'
                    if '360p' in src:
                        quality = '360p'
                    elif '720p' in src:
                        quality = '720p'
                    elif '1080p' in src:
                        quality = '1080p'
                    
                    trailer_urls.append({
                        'quality': quality,
                        'url': src
                    })
            
            result.preview_video_urls = trailer_urls
            
            # 2. 从 trailer URL 推导封面视频（硬编码规则）
            if trailer_urls:
                first_trailer = trailer_urls[0]['url']
                cover_video_url = self._derive_cover_video_url(first_trailer)
                
                if cover_video_url:
                    # 封面视频放到 cover_video_url 字段
                    result.cover_video_url = cover_video_url
            
            self.logger.info(f"提取视频: 预览视频={len(trailer_urls)}个, 封面视频={'有' if result.cover_video_url else '无'}")
            
        except Exception as e:
            self.logger.error(f"提取视频失败: {e}")
    
    def _derive_cover_video_url(self, trailer_url: str) -> Optional[str]:
        """
        从 trailer URL 推导封面视频 URL（硬编码规则）
        
        Args:
            trailer_url: 预览视频 URL
            
        Returns:
            封面视频 URL (webm 格式, 180p)
        """
        try:
            # 提取 scene_id
            # URL 格式: .../scenes/{scene_id}/Trailers/...
            match = re.search(r'/scenes/([^/]+)/', trailer_url)
            if match:
                scene_id = match.group(1)
                
                # 构建封面视频 URL
                # 格式: .../scenes/{scene_id}/PreviewClips/{scene_id}_180.webm
                cover_url = f"https://cdn77.scoreuniverse.com/scoreland/scenes/{scene_id}/PreviewClips/{scene_id}_180.webm"
                
                self.logger.debug(f"推导封面视频: {cover_url}")
                return cover_url
        except Exception as e:
            self.logger.error(f"推导封面视频失败: {e}")
        
        return None
    
    def _extract_studio_from_url(self, url: str) -> Optional[str]:
        """从 URL 推断制作商"""
        try:
            # 从域名提取
            if 'pornmegaload.com' in url:
                return 'Porn Mega Load'
            elif 'scoreland.com' in url:
                return 'Scoreland'
            elif 'xlgirls.com' in url:
                return 'XL Girls'
            elif '40somethingmag.com' in url:
                return '40 Something Mag'
            elif '50plusmilfs.com' in url:
                return '50 Plus MILFs'
            elif '60plusmilfs.com' in url:
                return '60 Plus MILFs'
            elif '18eighteen.com' in url:
                return '18eighteen'
            elif 'legsex.com' in url:
                return 'Leg Sex'
            elif 'naughtymag.com' in url:
                return 'Naughty Mag'
            else:
                # 尝试从域名提取
                match = re.search(r'https?://(?:www\.)?([^/]+)', url)
                if match:
                    domain = match.group(1)
                    # 移除 .com 等后缀
                    studio = domain.split('.')[0]
                    return studio.title()
        except Exception as e:
            self.logger.error(f"提取制作商失败: {e}")
        
        return 'Score Group'


if __name__ == '__main__':
    # 测试用例
    from core.config_loader import load_config
    
    print("=== Score Group 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 测试 URL
    test_url = "https://www.pornmegaload.com/hd-porn-scenes/Luna-Doll/80700/?nats=MTAwNC45Ljk5LjIyOS42ODMuMC4wLjAuMA"
    
    scraper = ScoreGroupScraper(config)
    
    print(f"测试 URL: {test_url}\n")
    
    try:
        result = scraper.scrape(test_url)
        
        if result:
            print(f"✓ 刮削成功\n")
            print(f"标题: {result.title}")
            print(f"制作商: {result.studio}")
            print(f"发行日期: {result.release_date}")
            print(f"年份: {result.year}")
            print(f"时长: {result.runtime} 分钟")
            print(f"评分: {result.rating}/10")
            print(f"演员: {', '.join(result.actors) if result.actors else '无'}")
            print(f"类型: {', '.join(result.genres[:5]) if result.genres else '无'}...")
            print(f"简介: {result.overview[:100]}..." if result.overview else "简介: 无")
            print(f"\n封面: {result.poster_url}")
            print(f"预览图: {len(result.preview_urls)} 张")
            if result.preview_urls:
                for i, url in enumerate(result.preview_urls[:3], 1):
                    print(f"  {i}. {url}")
            print(f"\n预览视频: {len(result.preview_video_urls)} 个")
            if result.preview_video_urls:
                for video in result.preview_video_urls:
                    print(f"  - {video['quality']}: {video['url']}")
        else:
            print(f"✗ 刮削失败")
            
    except Exception as e:
        print(f"✗ 错误: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n=== 测试完成 ===")
