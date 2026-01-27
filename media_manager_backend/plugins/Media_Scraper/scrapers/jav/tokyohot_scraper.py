"""
Tokyo-Hot 刮削器
使用 HTML 页面解析

网站: https://www.tokyo-hot.com
页面格式: https://www.tokyo-hot.com/product/{code}/
"""

import logging
import re
from typing import Optional
from lxml import html

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError


logger = logging.getLogger(__name__)


class TokyoHotScraper(BaseScraper):
    """Tokyo-Hot 刮削器（HTML 解析）"""
    
    name = 'tokyohot'
    
    def __init__(self, config):
        """初始化刮削器"""
        self.base_url = 'https://www.tokyo-hot.com'
        super().__init__(config, use_scraper=True)
        self.logger.info(f"使用 Tokyo-Hot 刮削器（HTML 解析），base_url: {self.base_url}")
    
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            code: 番号（格式: n2046 或 N2046）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 标准化番号格式（转小写）
        code = code.lower()
        
        # 移除可能的 tokyo-hot 或 tokyohot 前缀
        code = re.sub(r'^(tokyo-?hot-?)', '', code, flags=re.IGNORECASE)
        
        # 构建页面 URL（添加日文语言参数）
        page_url = f'{self.base_url}/product/{code}/?lang=ja'
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
        从 HTML 解析数据（日文版）
        
        Args:
            tree: lxml HTML 树
            code: 番号
            html_text: HTML 文本（用于正则匹配）
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        result.code = code.upper()  # Tokyo-Hot 番号通常大写
        result.studio = 'Tokyo-Hot'
        
        # 标题（从 h2 标签获取）
        title_elem = tree.xpath('//div[@class="contents"]/h2/text()')
        if title_elem:
            result.title = title_elem[0].strip()
        
        # 演员（从"出演者"字段获取）
        actor_elems = tree.xpath('//dl[@class="info"]/dt[contains(text(), "出演者")]/following-sibling::dd[1]/a/text()')
        if actor_elems:
            result.actors = [actor.strip() for actor in actor_elems if actor.strip()]
        
        # 发行日期（从"配信開始日"字段获取）
        date_elem = tree.xpath('//dl[@class="info"]/dt[contains(text(), "配信開始日")]/following-sibling::dd[1]/text()')
        if date_elem:
            date_text = date_elem[0].strip()
            # 格式: 2025/12/30
            date_match = re.search(r'(\d{4})/(\d{1,2})/(\d{1,2})', date_text)
            if date_match:
                result.release_date = f"{date_match.group(1)}-{int(date_match.group(2)):02d}-{int(date_match.group(3)):02d}"
                try:
                    result.year = int(date_match.group(1))
                except:
                    pass
        
        # 时长（从"収録時間"字段获取）
        duration_elem = tree.xpath('//dl[@class="info"]/dt[contains(text(), "収録時間")]/following-sibling::dd[1]/text()')
        if duration_elem:
            duration_text = duration_elem[0].strip()
            # 格式: 01:05:26
            match = re.search(r'(\d+):(\d+):(\d+)', duration_text)
            if match:
                hours = int(match.group(1))
                minutes = int(match.group(2))
                result.runtime = hours * 60 + minutes
        
        # 类型标签（从"プレイ内容"和"タグ"字段获取）
        genre_elems = tree.xpath('//dl[@class="info"]/dt[contains(text(), "プレイ内容") or contains(text(), "タグ")]/following-sibling::dd[1]/a/text()')
        if genre_elems:
            result.genres = [genre.strip() for genre in genre_elems if genre.strip()]
        
        # 系列（从"シリーズ"或"レーベル"字段获取）
        series_elem = tree.xpath('//dl[@class="info"]/dt[contains(text(), "シリーズ") or contains(text(), "レーベル")]/following-sibling::dd[1]/a/text()')
        if series_elem:
            result.series = series_elem[0].strip()
        
        # 封面图（从 jacket 链接获取）
        poster_elem = tree.xpath('//a[contains(@href, "/jacket/")]//@href')
        if poster_elem:
            result.poster_url = poster_elem[0]
        
        # 预览图（从 Movie Digest 部分获取）
        # 获取大图链接（640x480）
        preview_elems = tree.xpath('//div[@class="vcap"]/a[contains(@href, "/vcap/")]/@href')
        if preview_elems:
            # 只取前 10 张免费预览图
            result.preview_urls = preview_elems[:10]
            self.logger.info(f"找到 {len(result.preview_urls)} 张预览图")
        
        # 预览视频（从 video source 获取）
        video_elem = tree.xpath('//video/source/@src')
        if video_elem:
            video_url = video_elem[0]
            result.preview_video_urls = [{
                'quality': 'Sample',
                'url': video_url
            }]
            self.logger.info(f"找到预览视频: {video_url}")
        
        # 无码
        result.mosaic = '无码'
        
        self.logger.info(f"解析完成: {result.title}")
        
        return result


if __name__ == '__main__':
    # 测试用例
    from core.config_loader import load_config
    
    print("=== Tokyo-Hot 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 测试数据
    test_codes = ['n2046', 'N2046']
    
    scraper = TokyoHotScraper(config)
    
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
                print(f"  系列: {result.series if result.series else '无'}")
                print(f"\n  预览图 ({len(result.preview_urls)} 张):")
                for i, url in enumerate(result.preview_urls, 1):
                    print(f"    {i}. {url}")
                print(f"\n  预览视频 ({len(result.preview_video_urls)} 个):")
                for video in result.preview_video_urls:
                    print(f"    - {video['quality']}: {video['url']}")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
    
    print("\n=== 测试完成 ===")
