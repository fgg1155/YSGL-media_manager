"""
Heyzo 刮削器
使用 HTML 页面解析 + JSON-LD 结构化数据

网站: https://www.heyzo.com
页面格式: https://www.heyzo.com/moviepages/{code}/index.html
"""

import logging
import re
import json
from typing import Optional
from lxml import html

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError


logger = logging.getLogger(__name__)


class HeyzoScraper(BaseScraper):
    """Heyzo 刮削器（HTML 解析 + JSON-LD）"""
    
    name = 'heyzo'
    
    def __init__(self, config):
        """初始化刮削器"""
        self.base_url = 'https://www.heyzo.com'
        super().__init__(config, use_scraper=True)
        self.logger.info(f"使用 Heyzo 刮削器（HTML 解析），base_url: {self.base_url}")
    
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            code: 番号（格式: 3764 或 HEYZO-3764）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 标准化番号格式（移除所有 HEYZO 前缀）
        code = code.upper()
        # 移除所有可能的 HEYZO 前缀（处理 HEYZO-HEYZO-3764 这种情况）
        while code.startswith('HEYZO-') or code.startswith('HEYZO'):
            if code.startswith('HEYZO-'):
                code = code[6:]  # 移除 "HEYZO-"
            elif code.startswith('HEYZO'):
                code = code[5:]  # 移除 "HEYZO"
            code = code.lstrip('-').strip()  # 移除开头的横杠和空格
        
        # 构建页面 URL
        page_url = f'{self.base_url}/moviepages/{code}/index.html'
        self.logger.info(f"请求页面: {page_url}")
        
        # 请求页面
        resp = self.request.get(page_url)
        
        # 记录响应状态
        self.logger.info(f"页面响应: status_code={resp.status_code}, content_length={len(resp.content)}")
        
        # 检查是否 404
        if resp.status_code == 404:
            raise MovieNotFoundError(self.name, code)
        
        # 解析 HTML
        try:
            tree = html.fromstring(resp.text)
            return self._parse_html(tree, code, resp.text)
        except Exception as e:
            self.logger.error(f"解析 HTML 失败: {e}")
            raise MovieNotFoundError(self.name, code)
    
    def _parse_html(self, tree, code: str, html_text: str) -> ScrapeResult:
        """
        从 HTML 解析数据
        
        Args:
            tree: lxml HTML 树
            code: 番号
            html_text: HTML 文本（用于正则匹配）
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        result.code = code  # 保持原始番号，不添加前缀
        result.studio = 'HEYZO'
        
        # 1. 尝试从 JSON-LD 结构化数据解析（最可靠）
        json_ld_data = self._extract_json_ld(html_text)
        
        if json_ld_data:
            # 标题
            if 'name' in json_ld_data:
                result.title = json_ld_data['name']
            
            # 简介
            if 'description' in json_ld_data:
                result.overview = json_ld_data['description']
            
            # 发行日期
            if 'dateCreated' in json_ld_data:
                date_str = json_ld_data['dateCreated']
                # 格式: 2026-01-17T00:00:00+09:00
                result.release_date = date_str.split('T')[0]
                try:
                    result.year = int(result.release_date.split('-')[0])
                except:
                    pass
            
            # 时长
            if 'duration' in json_ld_data:
                duration_str = json_ld_data['duration']
                # 格式: PT0H56M40S
                result.runtime = self._parse_duration(duration_str)
            
            # 演员
            if 'actor' in json_ld_data:
                actor_data = json_ld_data['actor']
                if isinstance(actor_data, dict) and 'name' in actor_data:
                    result.actors = [actor_data['name']]
                elif isinstance(actor_data, str):
                    result.actors = [actor_data]
            
            # 预览视频 - 不使用 JSON-LD 的 mp4，强制使用 m3u8
            # JSON-LD 中的 mp4 链接不可靠，统一使用 HLS 流媒体
        
        # 2. 从 HTML 表格补充数据
        # 演员（如果 JSON-LD 没有）
        if not result.actors:
            actor_elems = tree.xpath('//tr[@class="table-actor"]//a/span/text()')
            if actor_elems:
                result.actors = [elem.strip() for elem in actor_elems if elem.strip()]
        
        # 发行日期（如果 JSON-LD 没有）
        if not result.release_date:
            date_elem = tree.xpath('//tr[@class="table-release-day"]//td[2]/text()')
            if date_elem:
                date_str = date_elem[0].strip()
                result.release_date = date_str
                try:
                    result.year = int(date_str.split('-')[0])
                except:
                    pass
        
        # 系列
        series_elem = tree.xpath('//tr[@class="table-series"]//td[2]/text()')
        if series_elem:
            series_text = series_elem[0].strip()
            if series_text and series_text != '-----':
                result.series = series_text
        
        # 类型标签（女优タイプ）
        genre_elems = tree.xpath('//tr[@class="table-actor-type"]//a/text()')
        if genre_elems:
            result.genres = [elem.strip() for elem in genre_elems if elem.strip()]
        
        # 标签关键词（タグキーワード）
        tag_elems = tree.xpath('//ul[@class="tag-keyword-list"]//a/text()')
        if tag_elems:
            tags = [elem.strip() for elem in tag_elems if elem.strip()]
            # 合并到 genres
            if result.genres:
                result.genres.extend(tags)
            else:
                result.genres = tags
        
        # 3. 构建图片 URL
        # 计算 folder（千位数）
        folder = (int(code) // 1000) * 1000
        
        self.logger.info(f"构建图片 URL: code={code}, folder={folder}")
        
        # 封面图
        result.poster_url = f'{self.base_url}/contents/{folder}/{code}/images/player_thumbnail.jpg'
        self.logger.info(f"封面图 URL: {result.poster_url}")
        
        # 预览图（只返回免费可访问的前 5 张大图）
        preview_urls = []
        # Heyzo 非会员用户可以访问前 5 张 gallery 大图
        # 格式: /contents/{folder}/{code}/gallery/001.jpg
        for i in range(1, 6):  # 前 5 张免费图
            preview_urls.append(f'{self.base_url}/contents/{folder}/{code}/gallery/{i:03d}.jpg')
        
        result.preview_urls = preview_urls
        self.logger.info(f"预览图: {len(preview_urls)} 张免费大图")
        
        # 4. 预览视频（强制使用 m3u8，不使用 JSON-LD 的 mp4）
        # HLS 流媒体预览视频（m3u8 格式）
        # 提供主 m3u8 链接，项目会自动解析多个清晰度
        # 格式: //hls.heyzo.com/sample/{folder}/{code}/mb.m3u8
        sample_m3u8_url = f'https://hls.heyzo.com/sample/{folder}/{code}/mb.m3u8'
        result.preview_video_urls = [{
            'quality': 'HLS',
            'url': sample_m3u8_url
        }]
        
        # 无码
        result.mosaic = '无码'
        
        self.logger.info(f"解析完成: {result.title}")
        
        return result
    
    def _extract_json_ld(self, html_text: str) -> Optional[dict]:
        """
        从 HTML 中提取 JSON-LD 结构化数据
        
        Args:
            html_text: HTML 文本
        
        Returns:
            JSON-LD 数据字典，失败返回 None
        """
        try:
            # 查找 JSON-LD script 标签
            pattern = r'<script type="application/ld\+json">(.*?)</script>'
            matches = re.findall(pattern, html_text, re.DOTALL)
            
            if matches:
                # 解析第一个匹配的 JSON
                json_str = matches[0].strip()
                data = json.loads(json_str)
                self.logger.debug(f"成功提取 JSON-LD 数据")
                return data
            else:
                self.logger.warning("未找到 JSON-LD 数据")
                return None
        except Exception as e:
            self.logger.error(f"解析 JSON-LD 失败: {e}")
            return None
    
    def _parse_duration(self, duration_str: str) -> Optional[int]:
        """
        解析 ISO 8601 时长格式
        
        Args:
            duration_str: 时长字符串（如 PT0H56M40S）
        
        Returns:
            时长（分钟），失败返回 None
        """
        try:
            # 格式: PT0H56M40S
            match = re.search(r'PT(\d+)H(\d+)M(\d+)S', duration_str)
            if match:
                hours = int(match.group(1))
                minutes = int(match.group(2))
                return hours * 60 + minutes
            
            # 备选格式: PT56M40S
            match = re.search(r'PT(\d+)M(\d+)S', duration_str)
            if match:
                return int(match.group(1))
            
            return None
        except Exception as e:
            self.logger.error(f"解析时长失败: {duration_str} - {e}")
            return None


if __name__ == '__main__':
    # 测试用例
    from core.config_loader import load_config
    
    print("=== Heyzo 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 测试数据
    test_codes = ['3764', 'HEYZO-3764', '3765']
    
    scraper = HeyzoScraper(config)
    
    for code in test_codes:
        print(f"\n测试番号: {code}")
        try:
            result = scraper.scrape(code)
            if result:
                print(f"✓ 刮削成功")
                print(f"  标题: {result.title}")
                print(f"  番号: {result.code}")
                print(f"  制作商: {result.studio}")
                print(f"  封面: {result.poster_url}")
                print(f"  发行日期: {result.release_date}")
                print(f"  时长: {result.runtime} 分钟" if result.runtime else "  时长: 未知")
                print(f"  演员: {', '.join(result.actors) if result.actors else '无'}")
                print(f"  类型: {', '.join(result.genres[:5]) if result.genres else '无'}...")
                print(f"  预览图: {len(result.preview_urls)} 张")
                print(f"  预览视频: {len(result.preview_video_urls)} 个")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
    
    print("\n=== 测试完成 ===")
