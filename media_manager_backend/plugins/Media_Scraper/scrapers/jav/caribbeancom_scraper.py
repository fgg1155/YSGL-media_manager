"""
Caribbeancom 系列刮削器
使用 HTML 页面解析（没有 JSON API）

支持的网站：
- Caribbeancom (カリビアンコム): https://www.caribbeancom.com
- CaribbeancomPR (カリビアンコムプレミアム): https://www.caribbeancompr.com

页面格式: https://www.{domain}/moviepages/{code}/index.html
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


# 网站配置
CARIBBEAN_SITES = {
    'caribbeancom': {
        'name': 'Caribbeancom',
        'base_url': 'https://www.caribbeancom.com',
        'studio': 'Caribbeancom',
        'code_format': '-',  # 使用横杠
    },
    'caribbeancompr': {
        'name': 'CaribbeancomPR',
        'base_url': 'https://www.caribbeancompr.com',
        'studio': 'CaribbeancomPR',
        'code_format': '_',  # 使用下划线
    },
}


class CaribbeanBaseScraper(BaseScraper):
    """Caribbeancom 系列基础刮削器（HTML 解析）"""
    
    def __init__(self, config, site_key: str = 'caribbeancom'):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
            site_key: 网站标识 (caribbeancom, caribbeancompr)
        """
        if site_key not in CARIBBEAN_SITES:
            raise ValueError(f"不支持的网站: {site_key}，支持的网站: {list(CARIBBEAN_SITES.keys())}")
        
        self.site_config = CARIBBEAN_SITES[site_key]
        self.name = site_key
        self.base_url = self.site_config['base_url']
        
        super().__init__(config, use_scraper=True)
        self.logger.info(f"使用 {self.site_config['name']} 刮削器（HTML 解析），base_url: {self.base_url}")
    
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            code: 番号（格式: 081925-001 或 081925_001）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 根据网站配置标准化番号格式
        code_format = self.site_config['code_format']
        if code_format == '-':
            # Caribbeancom 使用横杠
            code = code.replace('_', '-')
        else:
            # CaribbeancomPR 使用下划线
            code = code.replace('-', '_')
        
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
        
        # 解析 HTML（使用 EUC-JP 编码）
        try:
            # Caribbeancom 使用 EUC-JP 编码
            resp.encoding = 'euc-jp'
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
        result.code = code
        result.studio = self.site_config['studio']
        
        # 标题
        title_elem = tree.xpath('//h1[@itemprop="name"]')
        if title_elem:
            result.title = title_elem[0].text_content().strip()
        
        # 简介
        desc_elem = tree.xpath('//p[@itemprop="description"]')
        if desc_elem:
            result.overview = desc_elem[0].text_content().strip()
        
        # 发行日期
        date_elem = tree.xpath('//span[@itemprop="uploadDate"]')
        if date_elem:
            release_date = date_elem[0].text_content().strip()
            result.release_date = release_date
            try:
                result.year = int(release_date.split('/')[0])
            except:
                pass
        
        # 时长
        duration_elem = tree.xpath('//span[@itemprop="duration"]')
        if duration_elem:
            duration_text = duration_elem[0].text_content().strip()
            # 格式: 01:02:34
            match = re.search(r'(\d+):(\d+):(\d+)', duration_text)
            if match:
                hours = int(match.group(1))
                minutes = int(match.group(2))
                result.runtime = hours * 60 + minutes
        
        # 演员
        actor_elems = tree.xpath('//a[@class="spec__tag"]/span[@itemprop="name"]')
        if actor_elems:
            result.actors = [elem.text_content().strip() for elem in actor_elems]
        
        # 系列
        series_elem = tree.xpath('//a[contains(@href, "/series/")]')
        if series_elem:
            result.series = series_elem[0].text_content().strip()
        
        # 类型标签
        genre_elems = tree.xpath('//a[@itemprop="genre"]')
        if genre_elems:
            result.genres = [elem.text_content().strip() for elem in genre_elems]
        
        # 封面图
        result.poster_url = f'{self.base_url}/moviepages/{code}/images/l_l.jpg'
        
        # 预览图（从页面 HTML 解析，只保留免费图）
        preview_urls = []
        
        # 查找所有 a 标签的 href（包含大图链接）
        gallery_links = tree.xpath('//a[contains(@href, "/images/l/")]/@href')
        
        if gallery_links:
            # 过滤掉会员图（包含 /member/ 的 URL）
            for link in gallery_links:
                # 跳过会员图
                if '/member/' in link:
                    continue
                
                if link.startswith('http'):
                    preview_urls.append(link)
                elif link.startswith('/'):
                    preview_urls.append(f'{self.base_url}{link}')
                else:
                    preview_urls.append(link)
            
            self.logger.info(f"从页面解析到 {len(preview_urls)} 张免费预览图")
        else:
            # 备选方案：生成前 3 张免费图的 URL
            for i in range(1, 4):  # 通常前 3 张是免费的
                preview_url = f'{self.base_url}/moviepages/{code}/images/l/{i:03d}.jpg'
                preview_urls.append(preview_url)
            self.logger.debug(f"使用备选方案生成 {len(preview_urls)} 个免费预览图 URL")
        
        result.preview_urls = preview_urls
        
        # 预览视频（查找免费的 sample 视频）
        preview_videos = []
        
        # 查找 sample 视频 URL（格式：https://smovie.{domain}/sample/movies/{code}/480p.mp4）
        sample_video_pattern = r'https?://smovie\.[^/]+/sample/movies/[^/]+/(\d+p)\.mp4'
        sample_matches = re.findall(sample_video_pattern, html_text)
        
        if sample_matches:
            # 构建 sample 视频 URL
            # 从 base_url 提取域名（去掉 www.）
            domain = self.base_url.split('//')[1].replace('www.', '')
            for quality in sample_matches:
                video_url = f'https://smovie.{domain}/sample/movies/{code}/{quality}.mp4'
                preview_videos.append({
                    'quality': quality.upper(),
                    'url': video_url
                })
            self.logger.info(f"找到 {len(preview_videos)} 个预览视频")
        else:
            # 备选方案：尝试常见的 sample 视频质量
            domain = self.base_url.split('//')[1].replace('www.', '')
            for quality in ['480p', '360p', '240p']:
                video_url = f'https://smovie.{domain}/sample/movies/{code}/{quality}.mp4'
                preview_videos.append({
                    'quality': quality.upper(),
                    'url': video_url
                })
            self.logger.debug(f"使用备选方案生成 {len(preview_videos)} 个预览视频 URL")
        
        result.preview_video_urls = preview_videos
        
        # 无码
        result.mosaic = '无码'
        
        self.logger.info(f"解析完成: {result.title}")
        
        return result


# 为每个网站创建独立的类（方便导入和使用）
class CaribbeancomScraper(CaribbeanBaseScraper):
    """Caribbeancom (カリビアンコム) 刮削器"""
    name = 'caribbeancom'
    
    def __init__(self, config):
        super().__init__(config, site_key='caribbeancom')


class CaribbeancomPRScraper(CaribbeanBaseScraper):
    """CaribbeancomPR (カリビアンコムプレミアム) 刮削器"""
    name = 'caribbeancompr'
    
    def __init__(self, config):
        super().__init__(config, site_key='caribbeancompr')


if __name__ == '__main__':
    # 测试用例
    from core.config_loader import load_config
    
    print("=== Caribbeancom 系列刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 测试数据
    test_cases = [
        ('caribbeancom', ['081925-001', '032620-001']),
        ('caribbeancompr', ['012626_001', '010120_001']),
    ]
    
    for site_key, codes in test_cases:
        print(f"=== 测试 {CARIBBEAN_SITES[site_key]['name']} ===")
        scraper = CaribbeanBaseScraper(config, site_key=site_key)
        
        for code in codes:
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
                    print(f"  演员: {', '.join(result.actors[:3]) if result.actors else '无'}...")
                    print(f"  类型: {', '.join(result.genres[:5]) if result.genres else '无'}...")
                    print(f"  预览图: {len(result.preview_urls)} 张")
                    print(f"  预览视频: {len(result.preview_video_urls)} 个")
                else:
                    print(f"✗ 刮削失败")
            except Exception as e:
                print(f"✗ 错误: {e}")
        
        print()
    
    print("\n=== 测试完成 ===")
