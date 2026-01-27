"""
MatureNL 刮削器
刮削 mature.nl 网站的内容

TODO: 需要实现图像数据缓存功能
- 当前所有图片 URL 都是临时签名 URL（带 validfrom/validto 参数）
- 这些 URL 会在一段时间后失效
- 需要在主项目中实现图片缓存/下载功能，将图片保存到本地
- 建议缓存策略：
  1. poster_url (封面图) - 必须缓存
  2. backdrop_url (背景图) - 必须缓存
  3. preview_urls (预览图) - 可选缓存
  4. preview_video_urls (预览视频) - 可选缓存
- 实现方式：在主项目的媒体保存流程中，检测到临时 URL 时自动下载并替换为本地路径
"""

import logging
import re
from typing import Dict, Any, Optional, List
from datetime import datetime
from bs4 import BeautifulSoup

# 导入核心模块
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from core.models import ScrapeResult
from web.request import Request


logger = logging.getLogger(__name__)


class MatureNLScraper:
    """MatureNL 刮削器"""
    
    BASE_URL = "https://www.mature.nl"
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.logger = logging.getLogger(__name__)
        self.request = Request(config)
        
        # 加载站点配置
        self.sites_config = self._load_sites_config()
        self.logger.info(f"MatureNL 刮削器初始化完成，加载了 {len(self.sites_config)} 个站点配置")
        
        # 加载男演员过滤配置
        actor_config = config.get('actor', {})
        self.filter_male_actors = actor_config.get('filter_male_actors', True)
        self.male_actors = self._load_male_actors(actor_config.get('male_actors_file', 'config/male_actors.json'))
        self.logger.info(f"男演员过滤: {'启用' if self.filter_male_actors else '禁用'}，男演员列表: {len(self.male_actors)} 个")
    
    def _load_sites_config(self) -> Dict[str, Dict[str, Any]]:
        """
        加载站点配置文件
        
        Returns:
            站点配置字典
        """
        import csv
        
        config_file = Path(__file__).parent.parent.parent / 'config' / 'site' / 'MatureNL_sites.csv'
        sites_config = {}
        
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    site_name = row.get('site_name', '').strip()
                    if site_name and not site_name.startswith('#'):
                        sites_config[site_name] = {
                            'domain': row.get('domain', '').strip(),
                            'code': row.get('code', '').strip(),
                            'network': row.get('network', '').strip(),
                            'enabled': row.get('enabled', 'true').strip().lower() == 'true',
                            'priority': int(row.get('priority', '80').strip()),
                            'main_api': row.get('main_api', '').strip()
                        }
            
            self.logger.info(f"成功加载 {len(sites_config)} 个站点配置")
        except Exception as e:
            self.logger.error(f"加载站点配置失败: {e}")
        
        return sites_config
    
    def _load_male_actors(self, male_actors_file: str) -> set:
        """
        加载男演员列表
        
        Args:
            male_actors_file: 男演员文件路径
        
        Returns:
            男演员名称集合（小写）
        """
        import json
        
        male_actors = set()
        
        try:
            file_path = Path(__file__).parent.parent.parent / male_actors_file
            if file_path.exists():
                with open(file_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        male_actors = {name.lower() for name in data if isinstance(name, str)}
                    elif isinstance(data, dict):
                        male_actors = {name.lower() for name in data.keys() if isinstance(name, str)}
                
                self.logger.info(f"成功加载 {len(male_actors)} 个男演员")
            else:
                self.logger.warning(f"男演员文件不存在: {file_path}")
        except Exception as e:
            self.logger.error(f"加载男演员列表失败: {e}")
        
        return male_actors
    
    def scrape_multiple(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        搜索并返回多个结果
        
        Args:
            title: 搜索标题（可能包含系列名前缀）
            content_type_hint: 内容类型提示（未使用）
            series: 系列名（MatureNL 是独立站点，不需要系列名过滤）
        
        Returns:
            刮削结果列表
        """
        self.logger.info(f"开始搜索 MatureNL: title={title}, series={series}")
        
        # 移除系列名前缀（如果有）
        from utils.query_parser import extract_series_and_title
        
        extracted_series, clean_title = extract_series_and_title(title)
        if extracted_series:
            self.logger.info(f"移除系列名前缀: {extracted_series}, 搜索标题: {clean_title}")
            title = clean_title
        
        try:
            # 构建搜索 URL
            search_url = f"{self.BASE_URL}/en/updates?q={title}"
            self.logger.info(f"搜索 URL: {search_url}")
            
            # 发送请求
            response = self.request.get(search_url)
            if not response or response.status_code != 200:
                self.logger.error(f"搜索请求失败: status_code={response.status_code if response else 'None'}")
                return []
            
            # 解析搜索结果，传入搜索关键词用于 URL 匹配
            soup = BeautifulSoup(response.text, 'html.parser')
            results = self._parse_search_results(soup, max_results=20, search_keywords=title)
            
            self.logger.info(f"找到 {len(results)} 个搜索结果")
            return results
            
        except Exception as e:
            self.logger.error(f"搜索失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []

    def _parse_search_results(self, soup: BeautifulSoup, max_results: int = 20, search_keywords: Optional[str] = None) -> List[ScrapeResult]:
        """
        解析搜索结果页面
        
        Args:
            soup: BeautifulSoup 对象
            max_results: 最多处理的结果数量（默认20）
            search_keywords: 搜索关键词，用于 URL 匹配过滤（可选）
        
        Returns:
            刮削结果列表
        """
        results = []
        
        # 查找所有卡片
        cards = soup.select('div.grid-item div.card')
        self.logger.info(f"找到 {len(cards)} 个卡片")
        
        # 如果提供了搜索关键词，转换为 URL slug 格式（小写+连字符）
        url_slug = None
        if search_keywords:
            # 转换为小写，替换空格为连字符
            url_slug = search_keywords.lower().replace(' ', '-')
            self.logger.info(f"URL 匹配模式: 只处理包含 '{url_slug}' 的链接")
        
        processed_count = 0
        for card in cards:
            # 如果已经处理了足够的结果，停止
            if processed_count >= max_results:
                break
            
            try:
                # 先提取 URL，检查是否匹配
                title_link = card.select_one('div.card-title a')
                if not title_link:
                    continue
                
                detail_url = title_link.get('href', '')
                if not detail_url:
                    continue
                
                # 如果设置了 URL 匹配，检查 URL 是否包含关键词
                if url_slug:
                    if url_slug not in detail_url.lower():
                        self.logger.debug(f"跳过不匹配的 URL: {detail_url}")
                        continue
                    else:
                        self.logger.info(f"匹配的 URL: {detail_url}")
                
                # 解析卡片
                result = self._parse_card(card)
                if result:
                    results.append(result)
                    processed_count += 1
            except Exception as e:
                self.logger.error(f"解析卡片失败: {e}")
                continue
        
        self.logger.info(f"URL 匹配后处理了 {processed_count} 个卡片，返回 {len(results)} 个结果")
        return results

    def _parse_card(self, card) -> Optional[ScrapeResult]:
        """
        解析单个卡片
        
        Args:
            card: BeautifulSoup 卡片元素
        
        Returns:
            刮削结果或 None
        """
        result = ScrapeResult()
        result.source = "MatureNL"
        result.media_type = "Scene"  # MatureNL 都是场景内容
        
        # 提取详情页 URL
        title_link = card.select_one('div.card-title a')
        if not title_link:
            return None
        
        detail_url = title_link.get('href', '')
        if not detail_url:
            return None
        
        # 补全 URL
        if detail_url.startswith('/'):
            detail_url = f"{self.BASE_URL}{detail_url}"
        
        # 提取标题
        result.title = title_link.get_text(strip=True)
        
        # 提取封面图
        img = card.select_one('div.card-img img')
        if img:
            # 尝试多种可能的图片属性（懒加载）
            poster_url = (
                img.get('data-src') or 
                img.get('data-lazy') or 
                img.get('data-original') or 
                img.get('src') or 
                ''
            )
            
            # 如果是默认占位图，尝试从详情页获取
            if poster_url and not poster_url.endswith('cs_default.png'):
                # 补全相对 URL
                if poster_url.startswith('/'):
                    poster_url = f"{self.BASE_URL}{poster_url}"
                result.poster_url = poster_url
                self.logger.info(f"✓ 提取封面图: {poster_url[:100]}")
            else:
                self.logger.warning(f"✗ 封面图是默认占位图或为空，将使用详情页的背景图作为封面")
                # 不设置 poster_url，后续会用 backdrop_url 替代
        else:
            self.logger.warning(f"✗ 未找到封面图元素，尝试的选择器: 'div.card-img img'")
        
        # 提取演员
        subtitle = card.select_one('div.card-subtitle')
        if subtitle:
            actor_links = subtitle.select('a')
            actors = []
            for actor_link in actor_links:
                actor_name_raw = actor_link.get_text(strip=True)
                # 清理演员名称：
                # 1. 移除年龄信息：(27), (61) 等
                # 2. 移除地区标识：(EU), (US), (UK) 等
                # 3. 移除组合格式：(EU) (61), (US) (35) 等
                actor_name = actor_name_raw
                
                # 移除 (地区) (年龄) 格式，如 "Allison (EU) (61)"
                actor_name = re.sub(r'\s*\([A-Z]{2}\)\s*\(\d+\)', '', actor_name)
                
                # 移除单独的 (年龄) 格式，如 "Allison Sweet (27)"
                actor_name = re.sub(r'\s*\(\d+\)', '', actor_name)
                
                # 移除单独的 (地区) 格式，如 "Allison (EU)"
                actor_name = re.sub(r'\s*\([A-Z]{2}\)', '', actor_name)
                
                # 清理多余空格
                actor_name = actor_name.strip()
                
                if actor_name:
                    # 男演员过滤（使用清理后的名称）
                    if self.filter_male_actors and actor_name.lower() in self.male_actors:
                        self.logger.debug(f"过滤男演员: {actor_name}")
                        continue
                    actors.append({'name': actor_name})
            result.actors = actors
        
        # 提取标签（genres）
        tags_div = card.select_one('div.card-text div.overflow')
        if tags_div:
            tag_links = tags_div.select('a')
            genres = []
            for tag_link in tag_links:
                genre = tag_link.get_text(strip=True)
                if genre and genre not in genres:
                    genres.append(genre)
            result.genres = genres
        
        # 提取发布日期和制作商
        date_div = card.select_one('div.card-text.fs-small div.overflow')
        if date_div:
            date_text = date_div.get_text(strip=True)
            # 格式: "Grandpa Hans • 27-1-2026" 或 "B&B Media • 8-12-2025"
            parts = date_text.split('•')
            if len(parts) == 2:
                result.studio = parts[0].strip()
                date_str = parts[1].strip()
                # 解析日期
                result.release_date = self._parse_date(date_str)
        
        # 刮削详情页
        self.logger.info(f"刮削详情页: {detail_url}")
        detail_result = self._scrape_detail(detail_url)
        if detail_result:
            # 合并详情页数据
            if detail_result.backdrop_url:
                result.backdrop_url = detail_result.backdrop_url  # 已经是数组格式
                # 如果搜索页没有有效封面图，使用详情页的第一张背景图作为封面
                if not result.poster_url and len(detail_result.backdrop_url) > 0:
                    result.poster_url = detail_result.backdrop_url[0]
                    self.logger.info(f"✓ 使用背景图作为封面: {result.poster_url[:100]}")
            if detail_result.preview_video_urls:
                result.preview_video_urls = detail_result.preview_video_urls
            if detail_result.overview:
                result.overview = detail_result.overview
            if detail_result.runtime:
                result.runtime = detail_result.runtime
            if detail_result.preview_urls:
                result.preview_urls = detail_result.preview_urls
            if detail_result.genres and not result.genres:
                result.genres = detail_result.genres
        
        return result

    def _scrape_detail(self, url: str) -> Optional[ScrapeResult]:
        """
        刮削详情页
        
        Args:
            url: 详情页 URL
        
        Returns:
            刮削结果或 None
        """
        try:
            response = self.request.get(url)
            if not response or response.status_code != 200:
                self.logger.error(f"详情页请求失败: {url}")
                return None
            
            soup = BeautifulSoup(response.text, 'html.parser')
            result = ScrapeResult()
            
            # 提取视频播放器的背景图（poster）和预览视频
            video_tag = soup.find('video', {'id': 'vidUpdateTrailer'})
            if video_tag:
                # 背景图 - 注意：backdrop_url 是数组格式
                poster_url = video_tag.get('poster', '')
                if poster_url:
                    result.backdrop_url = [poster_url]  # 转换为数组
                    self.logger.info(f"✓ 提取背景图: {poster_url[:100]}")
                else:
                    self.logger.warning(f"✗ 背景图 URL 为空，video 属性: {video_tag.attrs}")
                
                # 预览视频 - 转换为正确的格式
                source_tag = video_tag.find('source')
                if source_tag:
                    video_url = source_tag.get('src', '')
                    if video_url:
                        # 格式: [{'quality': 'trailer', 'url': 'xxx'}]
                        result.preview_video_urls = [{'quality': 'trailer', 'url': video_url}]
                        self.logger.info(f"✓ 提取预览视频: {video_url[:100]}")
                else:
                    self.logger.warning(f"✗ 未找到 video source 标签")
            else:
                self.logger.warning(f"✗ 未找到视频播放器，尝试的选择器: video#vidUpdateTrailer")
            
            # 提取时长
            duration_span = soup.find('span', {'class': 'material-icons-outlined', 'title': 'Video length'})
            if duration_span:
                duration_text = duration_span.find_next_sibling('span')
                if duration_text:
                    duration_str = duration_text.get_text(strip=True)
                    result.runtime = self._parse_duration(duration_str)
            
            # 提取简介
            synopsis_spans = soup.find_all('span', {'class': 'col-accent'})
            for span in synopsis_spans:
                if 'Synopsis:' in span.get_text():
                    synopsis_text = span.find_next_sibling(text=True)
                    if synopsis_text:
                        result.overview = synopsis_text.strip()
                    break
            
            # 提取预览图
            gallery_links = soup.select('div.gal-block a.mfp-image')
            preview_urls = []
            for link in gallery_links:
                img_url = link.get('href', '')
                if img_url:
                    preview_urls.append(img_url)
            result.preview_urls = preview_urls
            if preview_urls:
                self.logger.info(f"✓ 提取预览图: {len(preview_urls)} 张")
            else:
                self.logger.warning(f"✗ 未找到预览图，尝试的选择器: 'div.gal-block a.mfp-image'")
            
            # 提取标签
            tags_div = soup.select_one('div#divPageUpdateNiches')
            if tags_div:
                tag_links = tags_div.select('a.tag')
                genres = []
                for tag_link in tag_links:
                    genre = tag_link.get_text(strip=True)
                    if genre and genre not in genres and not genre.startswith('…'):
                        genres.append(genre)
                result.genres = genres
            
            return result
            
        except Exception as e:
            self.logger.error(f"刮削详情页失败: {url}, error={e}")
            return None
    
    def _parse_date(self, date_str: str) -> Optional[str]:
        """
        解析日期字符串
        
        Args:
            date_str: 日期字符串（如 "27-1-2026" 或 "8-12-2025"）
        
        Returns:
            ISO 格式日期字符串或 None
        """
        try:
            # 尝试解析 "DD-MM-YYYY" 格式
            parts = date_str.split('-')
            if len(parts) == 3:
                day, month, year = parts
                date_obj = datetime(int(year), int(month), int(day))
                return date_obj.strftime('%Y-%m-%d')
        except Exception as e:
            self.logger.warning(f"日期解析失败: {date_str}, error={e}")
        
        return None
    
    def _parse_duration(self, duration_str: str) -> Optional[int]:
        """
        解析时长字符串
        
        Args:
            duration_str: 时长字符串（如 "15:16" 或 "1:00:03"）
        
        Returns:
            时长（分钟）或 None
        """
        try:
            parts = duration_str.split(':')
            if len(parts) == 2:
                # MM:SS 格式
                minutes, seconds = map(int, parts)
                return minutes
            elif len(parts) == 3:
                # HH:MM:SS 格式
                hours, minutes, seconds = map(int, parts)
                return hours * 60 + minutes
        except Exception as e:
            self.logger.warning(f"时长解析失败: {duration_str}, error={e}")
        
        return None
