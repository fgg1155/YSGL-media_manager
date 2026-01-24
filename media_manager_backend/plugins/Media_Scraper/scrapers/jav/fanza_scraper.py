"""
Fanza (DMM) 刮削器
从 Fanza 抓取影片数据（使用 GraphQL API）
"""

import logging
import re
import json
from typing import Optional, List, Dict
from datetime import datetime

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, SiteBlocked


logger = logging.getLogger(__name__)


class FanzaScraper(BaseScraper):
    """Fanza 刮削器（使用 GraphQL API）"""
    
    name = 'fanza'
    base_url = 'https://video.dmm.co.jp'
    api_url = 'https://api.video.dmm.co.jp/graphql'
    
    def __init__(self, config):
        """初始化 Fanza 刮削器"""
        super().__init__(config, use_scraper=False)
        
        # 设置 API 请求头
        self.request.headers.update({
            'fanza-device': 'BROWSER',
            'accept-language': 'zh-CN',
            'content-type': 'application/json',
            'accept': 'application/graphql-response+json, application/graphql+json, application/json',
            'referer': self.base_url + '/'
        })
        
        # 设置 R18 认证 cookie
        self.request.cookies = {'age_check_done': '1'}
    
    def _scrape_impl(self, cid: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        Args:
            cid: CID 格式的番号（如 ipx00177）
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 调用 GraphQL API 获取影片数据
        data = self._fetch_content_data(cid)
        
        if not data:
            self.logger.warning(f"未找到影片: {cid}")
            raise MovieNotFoundError('fanza', cid)
        
        # 解析数据
        result = self._parse_content_data(data, cid)
        
        # 尝试从播放器 API 获取所有清晰度的预览视频
        video_urls = self._fetch_preview_videos(cid)
        if video_urls:
            # 播放器 API 返回了多个清晰度，转换为统一格式
            # 格式: [{'quality': '清晰度名称', 'url': 'URL'}, ...]
            result.preview_video_urls = [
                {'quality': quality, 'url': url}
                for quality, url in video_urls.items()
            ]
            self.logger.info(f"从播放器 API 获取到 {len(video_urls)} 个清晰度的预览视频")
        else:
            self.logger.debug(f"播放器 API 未返回视频，使用 GraphQL API 的视频")
        
        return result
    
    def _fetch_content_data(self, cid: str) -> Optional[Dict]:
        """
        调用 GraphQL API 获取影片数据
        
        Args:
            cid: CID 格式的番号
        
        Returns:
            影片数据字典，失败返回 None
        """
        # 简化的 GraphQL 查询（只查询需要的字段）
        query = """query ContentPageData($id: ID!) {
  ppvContent(id: $id) {
    id
    floor
    title
    description
    packageImage {
      largeUrl
      mediumUrl
    }
    sampleImages {
      number
      imageUrl
      largeImageUrl
    }
    sample2DMovie {
      highestMovieUrl
      hlsMovieUrl
    }
    deliveryStartDate
    makerReleasedAt
    duration
    actresses {
      id
      name
      nameRuby
      imageUrl
    }
    directors {
      id
      name
    }
    series {
      id
      name
    }
    maker {
      id
      name
    }
    label {
      id
      name
    }
    genres {
      id
      name
    }
    makerContentId
  }
  reviewSummary(contentId: $id) {
    average
    total
  }
}"""
        
        # 请求变量
        variables = {
            'id': cid
        }
        
        # 构造请求体
        payload = {
            'operationName': 'ContentPageData',
            'query': query,
            'variables': variables
        }
        
        try:
            # 发送 POST 请求
            response = self.request.post(
                self.api_url,
                data=json.dumps(payload),
                delay_raise=True
            )
            
            if response.status_code != 200:
                self.logger.error(f"API 请求失败: {response.status_code}")
                return None
            
            # 解析响应
            result = response.json()
            
            # 检查是否有数据
            if 'data' not in result or not result['data'].get('ppvContent'):
                self.logger.warning(f"API 返回空数据: {cid}")
                return None
            
            return result['data']
            
        except Exception as e:
            self.logger.exception(f"API 请求异常: {cid}")
            return None
    
    def _fetch_preview_videos(self, cid: str) -> Dict[str, str]:
        """
        获取所有清晰度的预览视频URL
        
        Args:
            cid: CID 格式的番号
        
        Returns:
            包含不同清晰度视频URL的字典，key为清晰度名称，value为URL
        """
        try:
            # 构造播放器API URL
            player_url = f'https://www.dmm.co.jp/service/digitalapi/-/html5_player/=/cid={cid}/'
            
            self.logger.debug(f"请求播放器API: {player_url}")
            
            # 请求播放器页面
            response = self.request.get(player_url, delay_raise=True)
            
            if response.status_code != 200:
                self.logger.warning(f"播放器API请求失败: {response.status_code}")
                return {}
            
            html_content = response.text
            self.logger.debug(f"播放器页面长度: {len(html_content)}")
            
            # 从HTML中提取视频配置
            # 查找 const args = {...} 或 var args = {...}
            import re
            args_match = re.search(r'(?:const|var)\s+args\s*=\s*(\{[^;]*?"bitrates"[^;]*?\});', html_content, re.DOTALL)
            
            if not args_match:
                self.logger.warning(f"未找到视频配置（bitrates）")
                # 尝试查找是否有其他格式
                if 'bitrates' in html_content:
                    self.logger.debug("HTML中包含 'bitrates' 关键字，但正则匹配失败")
                else:
                    self.logger.debug("HTML中不包含 'bitrates' 关键字")
                return {}
            
            # 提取JSON字符串
            args_json = args_match.group(1)
            self.logger.debug(f"找到视频配置JSON，长度: {len(args_json)}")
            
            # 处理转义的斜杠
            args_json = args_json.replace('\\/', '/')
            
            # 解析JSON
            args = json.loads(args_json)
            
            # 提取所有清晰度的视频URL
            video_urls = {}
            if 'bitrates' in args and isinstance(args['bitrates'], list):
                for bitrate in args['bitrates']:
                    if 'src' in bitrate and 'bitrate' in bitrate:
                        src = bitrate['src']
                        # 添加https协议
                        if src.startswith('//'):
                            src = 'https:' + src
                        
                        # 使用bitrate名称作为key
                        bitrate_name = bitrate['bitrate']
                        video_urls[bitrate_name] = src
                
                self.logger.info(f"提取到 {len(video_urls)} 个清晰度的视频: {list(video_urls.keys())}")
            else:
                self.logger.warning(f"bitrates 字段不存在或格式不正确")
            
            return video_urls
            
        except Exception as e:
            self.logger.debug(f"获取预览视频失败: {e}")
            return {}
    
    def _parse_content_data(self, data: Dict, cid: str) -> ScrapeResult:
        """
        解析 GraphQL API 返回的数据
        
        Args:
            data: API 返回的数据字典
            cid: CID 格式的番号
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        try:
            content = data.get('ppvContent', {})
            review = data.get('reviewSummary', {})
            
            # 标题
            result.title = content.get('title', '')
            
            # 封面和背景图
            package_image = content.get('packageImage', {})
            actual_cid = cid  # 默认使用传入的 CID
            if package_image:
                # mediumUrl (ps.jpg) 作为封面图（小图）
                result.poster_url = package_image.get('mediumUrl', '')
                # largeUrl (pl.jpg) 作为背景图（大图）
                result.backdrop_url = package_image.get('largeUrl', '')
                
                # 从封面图 URL 中提取实际的 CID（用于构造预览图 URL）
                # 例如: https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/83sma00132/83sma00132pl.jpg
                # 提取: 83sma00132
                if result.backdrop_url:
                    match = re.search(r'/video/([^/]+)/\1pl\.jpg', result.backdrop_url)
                    if match:
                        actual_cid = match.group(1)
                        self.logger.debug(f"从封面图 URL 提取实际 CID: {actual_cid}")
            
            # 番号
            result.code = content.get('makerContentId', cid)
            
            # 简介
            result.overview = content.get('description', '')
            
            # 发行日期
            maker_released_at = content.get('makerReleasedAt')
            if maker_released_at:
                try:
                    # 解析 ISO 8601 格式日期
                    dt = datetime.fromisoformat(maker_released_at.replace('Z', '+00:00'))
                    result.release_date = dt.strftime('%Y-%m-%d')
                    result.year = dt.year
                except:
                    pass
            
            # 时长（秒转分钟）
            duration = content.get('duration')
            if duration:
                result.runtime = duration // 60
            
            # 演员
            actresses = content.get('actresses', [])
            if actresses:
                result.actors = [actress['name'] for actress in actresses]
            
            # 导演
            directors = content.get('directors', [])
            if directors:
                result.director = directors[0]['name']
            
            # 系列
            series = content.get('series')
            if series:
                result.series = series['name']
            
            # 制作商
            maker = content.get('maker')
            if maker:
                result.studio = maker['name']
            
            # 类型/标签
            genres = content.get('genres', [])
            if genres:
                result.genres = [genre['name'] for genre in genres]
            
            # 预览图（使用 largeImageUrl 或 imageUrl，但排除封面图）
            sample_images = content.get('sampleImages', [])
            if sample_images:
                result.preview_urls = []
                # 从封面图 URL 中提取实际的 CID（用于识别封面图）
                cover_cid = None
                if result.backdrop_url:
                    # 例如: https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/83sma00132/83sma00132pl.jpg
                    # 提取: 83sma00132
                    match = re.search(r'/video/([^/]+)/\1pl\.jpg', result.backdrop_url)
                    if match:
                        cover_cid = match.group(1)
                        self.logger.debug(f"封面图 CID: {cover_cid}")
                
                for img in sample_images:
                    # 优先使用 largeImageUrl（大图）
                    url = img.get('largeImageUrl')
                    if not url:
                        # 如果没有 largeImageUrl，使用 imageUrl
                        url = img.get('imageUrl')
                    
                    if url:
                        # 排除封面图（pl.jpg 格式）
                        if cover_cid and f'{cover_cid}pl.jpg' in url:
                            self.logger.debug(f"跳过封面图: {url}")
                            continue
                        # 也排除 ps.jpg 格式的封面图
                        if cover_cid and f'{cover_cid}ps.jpg' in url:
                            self.logger.debug(f"跳过封面图: {url}")
                            continue
                        
                        result.preview_urls.append(url)
                
                self.logger.debug(f"找到 {len(result.preview_urls)} 张预览图（已排除封面图）")
            
            # 视频预览 - 从 GraphQL API 提取
            sample_movie = content.get('sample2DMovie')
            if sample_movie:
                video_urls = []
                
                # 提取所有可用的视频URL（按优先级排序）
                if sample_movie.get('highestMovieUrl'):
                    video_urls.append({'quality': 'High', 'url': sample_movie['highestMovieUrl']})
                if sample_movie.get('hlsMovieUrl'):
                    video_urls.append({'quality': 'HLS', 'url': sample_movie['hlsMovieUrl']})
                
                if video_urls:
                    result.preview_video_urls = video_urls
                    self.logger.debug(f"找到 {len(video_urls)} 个视频预览")
            
            # 评分（5分制转10分制）
            average_rating = review.get('average')
            if average_rating:
                result.rating = float(average_rating) * 2
            
            return result
            
        except Exception as e:
            self.logger.exception(f"解析数据失败: {cid}")
            return result


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== Fanza 刮削器测试（GraphQL API）===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功\n")
    
    # 创建刮削器
    scraper = FanzaScraper(config)
    
    # 测试番号列表
    test_cids = ['ipx00177', 'ssis00001']
    
    for cid in test_cids:
        print(f"测试番号: {cid}")
        try:
            result = scraper.scrape(cid)
            if result:
                print(f"✓ 刮削成功")
                print(f"  标题: {result.title}")
                print(f"  番号: {result.code}")
                print(f"  封面: {result.poster_url}")
                print(f"  演员: {', '.join(result.actors) if result.actors else '无'}")
                print(f"  导演: {result.director or '无'}")
                print(f"  系列: {result.series or '无'}")
                print(f"  制作商: {result.studio or '无'}")
                print(f"  类型: {', '.join(result.genres) if result.genres else '无'}")
                print(f"  发行日期: {result.release_date or '无'}")
                print(f"  时长: {result.runtime}分钟" if result.runtime else "  时长: 无")
                print(f"  评分: {result.rating}" if result.rating else "  评分: 无")
                print(f"  预览图: {len(result.preview_urls)}张")
                
                # 显示视频预览列表
                if result.preview_video_urls:
                    print(f"  视频预览 ({len(result.preview_video_urls)}个):")
                    for i, url in enumerate(result.preview_video_urls, 1):
                        print(f"    {i}. {url}")
                else:
                    print(f"  视频预览: 无")
                
                print(f"  简介: {result.overview[:100]}..." if result.overview else "  简介: 无")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
            import traceback
            traceback.print_exc()
        print()
    
    print("=== 测试完成 ===")
