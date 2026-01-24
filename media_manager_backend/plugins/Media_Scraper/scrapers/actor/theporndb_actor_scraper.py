"""
ThePornDB 演员刮削器
从 ThePornDB API 获取欧美演员信息
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.actor.base_actor_scraper import BaseActorScraper, ActorMetadata, ActorPhotos
from web.request import Request
from typing import Optional
import logging


logger = logging.getLogger(__name__)


class ThePornDBActorScraper(BaseActorScraper):
    """ThePornDB 演员刮削器"""
    
    name = 'theporndb'
    base_url = 'https://api.theporndb.net'
    
    def __init__(self, config):
        """初始化刮削器"""
        super().__init__(config)
        self.request = Request(config, use_scraper=False)
        
        # 获取 API Token
        self.api_token = config.get('api_tokens', {}).get('theporndb_api_token', '')
        
        if not self.api_token:
            self.logger.warning("未配置 ThePornDB API Token，演员刮削可能失败")
        
        # 设置 API headers
        self.request.headers.update({
            'Authorization': f'Bearer {self.api_token}',
            'Accept': 'application/json',
            'User-Agent': 'MediaManager/1.0',
        })
    
    def scrape_metadata(self, actor_name: str) -> Optional[ActorMetadata]:
        """
        从 ThePornDB 刮削演员元数据
        
        Args:
            actor_name: 演员名称（英文名）
        
        Returns:
            ActorMetadata 对象，失败返回 None
        """
        try:
            # 1. 搜索演员获取 ID
            search_url = f"{self.base_url}/performers"
            params = {'q': actor_name}
            
            self.logger.debug(f"搜索演员: {actor_name}")
            response = self.request.get(search_url, params=params)
            
            # 检查响应状态
            if response.status_code != 200:
                self.logger.warning(f"API 请求失败: HTTP {response.status_code}")
                return None
            
            data = response.json()
            
            if not data.get('data') or len(data['data']) == 0:
                self.logger.debug(f"未找到演员: {actor_name}")
                return None
            
            # 取第一个结果的 ID
            first_result = data['data'][0]
            performer_id = first_result.get('id')
            
            if not performer_id:
                self.logger.warning(f"演员 {actor_name} 没有 ID")
                return None
            
            # 2. 获取演员详情
            detail_url = f"{self.base_url}/performers/{performer_id}"
            self.logger.debug(f"获取演员详情: {detail_url}")
            detail_response = self.request.get(detail_url)
            
            if detail_response.status_code != 200:
                self.logger.warning(f"获取详情失败: HTTP {detail_response.status_code}")
                return None
            
            detail_data = detail_response.json()
            performer = detail_data.get('data')
            
            if not performer:
                self.logger.warning(f"演员 {actor_name} 详情数据为空")
                return None
            
            # 3. 解析元数据
            metadata = ActorMetadata(name=actor_name, source='theporndb')
            
            # 基本信息 - bio 字段
            if performer.get('bio'):
                metadata.biography = performer['bio']
            
            # 尝试从 extras 中提取（优先使用 extras，因为数据更完整）
            if performer.get('extras'):
                extras = performer['extras']
                if isinstance(extras, dict):
                    # 出生日期
                    if extras.get('birthday'):
                        metadata.birth_date = extras['birthday']
                    # 国籍
                    if extras.get('nationality'):
                        metadata.nationality = extras['nationality']
                    # 身高（extras 中的 height 可能是数字或字符串）
                    if extras.get('height'):
                        height_value = extras['height']
                        # 如果已经包含 cm，直接使用；否则添加 cm
                        if isinstance(height_value, str):
                            metadata.height = height_value if 'cm' in height_value.lower() else f"{height_value}cm"
                        else:
                            metadata.height = f"{height_value}cm"
                    # 三围
                    if extras.get('measurements'):
                        metadata.measurements = extras['measurements']
                    # 罩杯（注意是 cupsize 不是 cup_size）
                    if extras.get('cupsize'):
                        metadata.cup_size = extras['cupsize']
            
            # 如果 extras 中没有，尝试从顶层字段获取
            if not metadata.birth_date and performer.get('born'):
                metadata.birth_date = performer['born']
            if not metadata.nationality and performer.get('nationality'):
                metadata.nationality = performer['nationality']
            if not metadata.height and performer.get('height'):
                height_value = performer['height']
                # 如果已经包含 cm，直接使用；否则添加 cm
                if isinstance(height_value, str):
                    metadata.height = height_value if 'cm' in height_value.lower() else f"{height_value}cm"
                else:
                    metadata.height = f"{height_value}cm"
            if not metadata.measurements and performer.get('measurements'):
                metadata.measurements = performer['measurements']
            if not metadata.cup_size and performer.get('cup_size'):
                metadata.cup_size = performer['cup_size']
            
            self.logger.info(f"成功获取 {actor_name} 的元数据")
            return metadata
        
        except Exception as e:
            self.logger.warning(f"刮削 {actor_name} 元数据失败: {e}", exc_info=True)
            return None
    
    def scrape_photos(self, actor_name: str) -> Optional[ActorPhotos]:
        """
        从 ThePornDB 刮削演员照片
        
        Args:
            actor_name: 演员名称（英文名）
        
        Returns:
            ActorPhotos 对象，失败返回 None
        """
        try:
            # 1. 搜索演员获取 ID
            search_url = f"{self.base_url}/performers"
            params = {'q': actor_name}
            
            self.logger.debug(f"搜索演员照片: {actor_name}")
            response = self.request.get(search_url, params=params)
            
            # 检查响应状态
            if response.status_code != 200:
                self.logger.warning(f"API 请求失败: HTTP {response.status_code}")
                return None
            
            data = response.json()
            
            if not data.get('data') or len(data['data']) == 0:
                self.logger.debug(f"未找到演员: {actor_name}")
                return None
            
            # 取第一个结果的 ID
            first_result = data['data'][0]
            performer_id = first_result.get('id')
            
            if not performer_id:
                self.logger.warning(f"演员 {actor_name} 没有 ID")
                return None
            
            # 2. 获取演员详情
            detail_url = f"{self.base_url}/performers/{performer_id}"
            self.logger.debug(f"获取演员详情: {detail_url}")
            detail_response = self.request.get(detail_url)
            
            if detail_response.status_code != 200:
                self.logger.warning(f"获取详情失败: HTTP {detail_response.status_code}")
                return None
            
            detail_data = detail_response.json()
            performer = detail_data.get('data')
            
            if not performer:
                self.logger.warning(f"演员 {actor_name} 详情数据为空")
                return None
            
            # 3. 提取图片
            photos = ActorPhotos(name=actor_name, source='theporndb')
            
            # 头像（优先使用 face，其次 thumbnail，最后 image）
            if performer.get('face'):
                photos.avatar_url = performer['face']
            elif performer.get('thumbnail'):
                photos.avatar_url = performer['thumbnail']
            elif performer.get('image'):
                photos.avatar_url = performer['image']
            
            # 封面和写真（使用 posters 列表）
            if performer.get('posters'):
                posters = performer['posters']
                if isinstance(posters, list) and len(posters) > 0:
                    # 第一张作为封面
                    first_poster = posters[0]
                    if isinstance(first_poster, dict):
                        # 优先使用 large，其次 medium，最后 small
                        if 'large' in first_poster:
                            photos.poster_url = first_poster['large']
                        elif 'medium' in first_poster:
                            photos.poster_url = first_poster['medium']
                        elif 'small' in first_poster:
                            photos.poster_url = first_poster['small']
                        elif 'url' in first_poster:
                            photos.poster_url = first_poster['url']
                    elif isinstance(first_poster, str):
                        photos.poster_url = first_poster
                    
                    # 写真从第二张开始（避免和封面重复），最多取10张
                    photo_list = []
                    for poster in posters[1:11]:  # 从索引1开始，取10张
                        if isinstance(poster, dict):
                            if 'large' in poster:
                                photo_list.append(poster['large'])
                            elif 'medium' in poster:
                                photo_list.append(poster['medium'])
                            elif 'url' in poster:
                                photo_list.append(poster['url'])
                        elif isinstance(poster, str):
                            photo_list.append(poster)
                    
                    if photo_list:
                        photos.photo_urls = photo_list
            
            # 背景图（使用第一张 poster 的大图作为背景）
            if photos.poster_url:
                photos.backdrop_url = photos.poster_url
            
            self.logger.info(f"找到 {actor_name} 的照片")
            return photos
        
        except Exception as e:
            self.logger.warning(f"刮削 {actor_name} 照片失败: {e}", exc_info=True)
            return None


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== ThePornDB 演员刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    
    # 创建刮削器
    scraper = ThePornDBActorScraper(config)
    
    # 测试演员
    test_actors = ['Riley Reid', 'Mia Malkova']
    
    for actor in test_actors:
        print(f"测试演员: {actor}")
        try:
            # 测试元数据
            metadata = scraper.scrape_metadata(actor)
            if metadata:
                print(f"✓ 元数据刮削成功")
                print(f"  出生日期: {metadata.birth_date}")
                print(f"  国籍: {metadata.nationality}")
                print(f"  身高: {metadata.height}")
                print(f"  简介: {metadata.biography[:100] if metadata.biography else 'None'}...")
            else:
                print(f"✗ 元数据刮削失败")
            
            # 测试照片
            photos = scraper.scrape_photos(actor)
            if photos:
                print(f"✓ 照片刮削成功")
                print(f"  Avatar URL: {photos.avatar_url}")
                print(f"  Poster URL: {photos.poster_url}")
                print(f"  Backdrop URL: {photos.backdrop_url}")
                print(f"  Photo URLs: {len(photos.photo_urls) if photos.photo_urls else 0} 张")
            else:
                print(f"✗ 照片刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
