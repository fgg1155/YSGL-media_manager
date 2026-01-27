"""
一本道系列网站通用刮削器
支持一本道旗下的多个无码网站，它们使用相同的 API 结构

支持的网站：
- 1pondo (一本道): https://www.1pondo.com
- Pacopacomama (人妻斬り): https://www.pacopacomama.com
- 10musume (天然むすめ): https://www.10musume.com

注意：Caribbeancom 和 CaribbeancomPR 使用 HTML 解析，不在此列

API 结构：
- 详情: /dyn/phpauto/movie_details/movie_id/{code}.json
- 预览图: /dyn/dla/json/movie_gallery/{code}.json
"""

import logging
import re
from typing import Optional, Dict, Any

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, NetworkError


logger = logging.getLogger(__name__)


# 网站配置
IPPONDO_SITES = {
    '1pondo': {
        'name': '1Pondo',
        'base_url': 'https://www.1pondo.tv',  # API 只能通过 .tv 访问
        'studio': '1Pondo',
        'pattern': r'^\d{6}[-_]\d{3}$',  # 格式: 082713-417 或 082713_417
    },
    'pacopacomama': {
        'name': 'Pacopacomama',
        'base_url': 'https://www.pacopacomama.com',
        'studio': 'Pacopacomama',
        'pattern': r'^\d{6}[-_]\d{3}$',  # 格式: 012426_100 或 012426-100
    },
    '10musume': {
        'name': '10musume',
        'base_url': 'https://www.10musume.com',
        'studio': '10musume',
        'pattern': r'^\d{6}[-_]\d{2}$',  # 格式: 010120_01 或 010120-01
    },
}


class IppondoNetworkScraper(BaseScraper):
    """一本道系列网站通用刮削器"""
    
    def __init__(self, config, site_key: str = 'pacopacomama'):
        """
        初始化刮削器
        
        Args:
            config: 配置字典
            site_key: 网站标识 (1pondo, pacopacomama, 10musume)
        """
        if site_key not in IPPONDO_SITES:
            raise ValueError(f"不支持的网站: {site_key}，支持的网站: {list(IPPONDO_SITES.keys())}")
        
        self.site_config = IPPONDO_SITES[site_key]
        self.name = site_key
        self.base_url = self.site_config['base_url']
        
        # 使用 cloudscraper 来处理可能的 Cloudflare 保护
        super().__init__(config, use_scraper=True)
        self.logger.info(f"使用 {self.site_config['name']} 刮削器，base_url: {self.base_url}")
    
    def _scrape_impl(self, code: str) -> Optional[ScrapeResult]:
        """
        刮削实现
        
        Args:
            code: 番号（格式根据网站不同）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 标准化番号格式（统一使用下划线）
        code = code.replace('-', '_')
        
        # 验证番号格式
        if not re.match(self.site_config['pattern'], code):
            self.logger.warning(f"番号格式不匹配: {code}，期望格式: {self.site_config['pattern']}")
        
        # 直接访问 API 获取 JSON 数据
        api_url = f'{self.base_url}/dyn/phpauto/movie_details/movie_id/{code}.json'
        self.logger.info(f"请求 API: {api_url}")
        
        resp = self.request.get(api_url)
        
        # 记录响应状态
        self.logger.info(f"API 响应: status_code={resp.status_code}, content_length={len(resp.content)}")
        
        # 检查是否 404
        if resp.status_code == 404:
            raise MovieNotFoundError(self.name, code)
        
        # 解析 JSON
        try:
            data = resp.json()
            self.logger.info(f"JSON 解析成功，数据字段: {list(data.keys())}")
            return self._parse_api_data(data, code)
        except Exception as e:
            self.logger.error(f"解析 API 数据失败: {e}")
            self.logger.error(f"响应内容（前500字符）: {resp.text[:500]}")
            raise MovieNotFoundError(self.name, code)
    
    def _parse_api_data(self, data: dict, code: str) -> ScrapeResult:
        """
        从 API JSON 数据解析
        
        Args:
            data: API 返回的 JSON 数据
            code: 番号
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        result.code = code
        result.studio = self.site_config['studio']
        
        # 标题（优先使用完整标题，fallback 到系列+演员）
        title = data.get('Title', '')
        title_en = data.get('TitleEn', '')
        
        if title:
            result.title = title
        elif title_en:
            result.title = title_en
        else:
            # Fallback: 系列 + 演员
            series = data.get('Series', '')
            actor = data.get('Actor', '')
            if series and actor:
                result.title = f"{series} {actor}"
            elif actor:
                result.title = actor
            else:
                result.title = code
        
        # 发行日期
        release = data.get('Release', '')
        if release:
            result.release_date = release
            try:
                result.year = int(release.split('-')[0])
            except:
                pass
        
        # 时长（秒转分钟）
        duration = data.get('Duration', 0)
        if duration:
            result.runtime = int(duration / 60)
        
        # 演员（优先使用英文名，fallback 到日文名）
        actresses_en = data.get('ActressesEn', [])
        actresses_ja = data.get('ActressesJa', [])
        
        if actresses_en:
            result.actors = actresses_en
        elif actresses_ja:
            result.actors = actresses_ja
        elif data.get('Actor'):
            result.actors = [data['Actor']]
        
        # 封面图（使用高清图）
        thumb_high = data.get('ThumbHigh', '')
        thumb_ultra = data.get('ThumbUltra', '')
        movie_thumb = data.get('MovieThumb', '')
        
        self.logger.debug(f"封面图字段: ThumbUltra={thumb_ultra}, ThumbHigh={thumb_high}, MovieThumb={movie_thumb}")
        
        # 优先使用 Ultra，然后 High，最后 MovieThumb
        if thumb_ultra:
            result.poster_url = thumb_ultra
            self.logger.debug(f"使用 ThumbUltra: {thumb_ultra}")
        elif thumb_high:
            result.poster_url = thumb_high
            self.logger.debug(f"使用 ThumbHigh: {thumb_high}")
        elif movie_thumb:
            # 将缩略图转换为高清图
            poster_url = re.sub(r'l_thum\.jpg$', 'l_hd.jpg', movie_thumb)
            result.poster_url = poster_url
            self.logger.debug(f"使用 MovieThumb 转换: {poster_url}")
        
        self.logger.info(f"最终封面图: {result.poster_url}")
        
        # 预览图（从 Gallery API 获取，包含所有图片）
        if data.get('Gallery', False):
            try:
                # 调用预览图 API
                gallery_url = f"{self.base_url}/dyn/dla/json/movie_gallery/{code}.json"
                gallery_resp = self.request.get(gallery_url)
                
                if gallery_resp.status_code == 200:
                    gallery_data = gallery_resp.json()
                    rows = gallery_data.get('Rows', [])
                    
                    # 获取所有预览图（包括会员专属的）
                    preview_urls = []
                    for row in rows:
                        img_path = row.get('Img', '')
                        if img_path:
                            # 构建完整 URL
                            preview_url = f"{self.base_url}/dyn/dla/images/{img_path}"
                            preview_urls.append(preview_url)
                    
                    result.preview_urls = preview_urls
                    self.logger.debug(f"找到 {len(preview_urls)} 张预览图")
            except Exception as e:
                self.logger.warning(f"获取预览图失败: {e}")
        
        # 预览视频（使用统一格式）
        sample_files = data.get('SampleFiles', [])
        if sample_files:
            # 转换为统一格式: [{'quality': '1080P', 'url': '...'}, ...]
            preview_videos = []
            for sample in sample_files:
                filename = sample.get('FileName', '')
                url = sample.get('URL', '')
                
                if url:
                    # 从文件名提取清晰度（240p.mp4 -> 240P）
                    quality = filename.replace('.mp4', '').upper() if filename else 'Unknown'
                    preview_videos.append({
                        'quality': quality,
                        'url': url
                    })
            
            result.preview_video_urls = preview_videos
        
        # 简介
        desc = data.get('Desc', '')
        if desc:
            result.overview = desc.strip()
        
        # 系列（优先英文，fallback 日文）
        series_en = data.get('SeriesEn', '')
        series_ja = data.get('Series', '')
        
        if series_en:
            result.series = series_en
        elif series_ja:
            result.series = series_ja
        
        # 类型标签（优先英文，fallback 日文）
        genres_en = data.get('UCNAMEEn', [])
        genres_ja = data.get('UCNAME', [])
        
        if genres_en:
            # 过滤掉技术标签（1080p, 60fps, SVIP 等）
            filtered_genres = [g for g in genres_en if g not in ['1080p', '60fps', 'SVIP', '超VIP']]
            result.genres = filtered_genres
        elif genres_ja:
            filtered_genres = [g for g in genres_ja if g not in ['1080p', '60fps', '超VIP']]
            result.genres = filtered_genres
        
        # 评分
        avg_rating = data.get('AvgRating', 0)
        if avg_rating:
            result.rating = float(avg_rating)
        
        return result


# 为每个网站创建独立的类（方便导入和使用）
class OnePondoScraper(IppondoNetworkScraper):
    """1Pondo (一本道) 刮削器"""
    name = '1pondo'
    
    def __init__(self, config):
        super().__init__(config, site_key='1pondo')


class PacopacomamaScraper(IppondoNetworkScraper):
    """Pacopacomama (人妻斬り) 刮削器"""
    name = 'pacopacomama'
    
    def __init__(self, config):
        super().__init__(config, site_key='pacopacomama')


class TenMusumeScraper(IppondoNetworkScraper):
    """10musume (天然むすめ) 刮削器"""
    name = '10musume'
    
    def __init__(self, config):
        super().__init__(config, site_key='10musume')


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== 一本道系列刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 测试数据
    test_cases = [
        ('1pondo', ['082713-417', '010120-001']),
        ('pacopacomama', ['012426_100', '010125_100']),
        ('10musume', ['010120_01', '123119_01']),
    ]
    
    for site_key, codes in test_cases:
        print(f"=== 测试 {IPPONDO_SITES[site_key]['name']} ===")
        scraper = IppondoNetworkScraper(config, site_key=site_key)
        
        for code in codes:
            print(f"\n测试番号: {code}")
            try:
                result = scraper.scrape(code)
                if result:
                    print(f"✓ 刮削成功")
                    print(f"  标题: {result.title}")
                    print(f"  番号: {result.code}")
                    print(f"  制作商: {result.studio}")
                    print(f"  封面: {result.poster_url[:80] if result.poster_url else '无'}...")
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
    
    print("=== 测试完成 ===")
