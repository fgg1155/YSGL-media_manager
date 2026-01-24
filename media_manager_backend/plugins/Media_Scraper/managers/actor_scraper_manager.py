"""
演员刮削管理器
管理演员元数据和照片的刮削流程
"""

import logging
from typing import Dict, Any, Optional, List
from dataclasses import asdict


logger = logging.getLogger(__name__)


class ActorScraperManager:
    """演员刮削管理器"""
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化管理器
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # 延迟导入刮削器（避免循环导入）
        from scrapers.actor.xslist_scraper import XSlistActorScraper
        from scrapers.actor.gfriends_scraper import GfriendsActorScraper
        from scrapers.actor.theporndb_actor_scraper import ThePornDBActorScraper
        
        # 初始化元数据刮削器
        self.metadata_scrapers = []
        metadata_config = config.get('actor_scraper', {}).get('metadata', {})
        
        # XSlist（日本演员）
        if metadata_config.get('xslist', {}).get('enabled', True):
            self.metadata_scrapers.append(XSlistActorScraper(config))
            self.logger.info("XSlist 元数据刮削器已启用")
        
        # ThePornDB（欧美演员）
        if metadata_config.get('theporndb', {}).get('enabled', True):
            self.metadata_scrapers.append(ThePornDBActorScraper(config))
            self.logger.info("ThePornDB 元数据刮削器已启用")
        
        # 初始化照片刮削器
        self.photo_scrapers = []
        photos_config = config.get('actor_scraper', {}).get('photos', {})
        
        if photos_config.get('gfriends', {}).get('enabled', True):
            self.photo_scrapers.append(GfriendsActorScraper(config))
            self.logger.info("Gfriends 照片刮削器已启用")
        
        self.logger.info("ActorScraperManager initialized")
    
    def _is_western_name(self, name: str) -> bool:
        """
        判断是否为欧美演员名称（简单判断：是否包含日文字符）
        
        Args:
            name: 演员名称
        
        Returns:
            True 表示欧美演员，False 表示日本演员
        """
        # 检查是否包含日文字符（平假名、片假名、汉字）
        for char in name:
            code = ord(char)
            # 平假名: 0x3040-0x309F
            # 片假名: 0x30A0-0x30FF
            # CJK统一汉字: 0x4E00-0x9FFF
            if (0x3040 <= code <= 0x309F or 
                0x30A0 <= code <= 0x30FF or 
                0x4E00 <= code <= 0x9FFF):
                return False
        return True
    
    def scrape_actor(self, actor_name: str) -> Optional[Dict[str, Any]]:
        """
        刮削单个演员的完整信息（元数据 + 照片）
        
        根据演员名称自动选择数据源：
        - 日本演员：XSlist（元数据+头像+写真） + Gfriends（封面+背景图）
        - 欧美演员：ThePornDB（所有数据）
        
        Args:
            actor_name: 演员名称
        
        Returns:
            演员信息字典，包含：
            {
                'name': '天海つばさ',
                'biography': '...',
                'birth_date': '1988-03-08',
                'nationality': '日本',
                'height': '163cm',
                'measurements': 'B88-W58-H86',
                'cup_size': 'E',
                'avatar_url': 'https://...',
                'poster_url': 'https://...',
                'photo_urls': ['https://...'],
                'backdrop_url': None
            }
            失败返回 None
        """
        self.logger.info(f"开始刮削演员: {actor_name}")
        
        result = {'name': actor_name}
        is_western = self._is_western_name(actor_name)
        
        if is_western:
            self.logger.info(f"{actor_name} 识别为欧美演员，使用 ThePornDB")
            return self._scrape_western_actor(actor_name)
        else:
            self.logger.info(f"{actor_name} 识别为日本演员，使用 XSlist + Gfriends")
            return self._scrape_japanese_actor(actor_name)
    
    def _scrape_western_actor(self, actor_name: str) -> Optional[Dict[str, Any]]:
        """
        刮削欧美演员（使用 ThePornDB）
        
        Args:
            actor_name: 演员名称
        
        Returns:
            演员信息字典或 None
        """
        result = {'name': actor_name}
        metadata_found = False
        photos_found = False
        
        # 查找 ThePornDB 刮削器
        theporndb_scraper = None
        for scraper in self.metadata_scrapers:
            if scraper.name == 'theporndb':
                theporndb_scraper = scraper
                break
        
        if not theporndb_scraper:
            self.logger.warning("ThePornDB 刮削器未启用")
            return None
        
        # 1. 刮削元数据
        try:
            metadata = theporndb_scraper.scrape_metadata(actor_name)
            if metadata:
                result.update({
                    'biography': metadata.biography,
                    'birth_date': metadata.birth_date,
                    'nationality': metadata.nationality,
                    'height': metadata.height,
                    'measurements': metadata.measurements,
                    'cup_size': metadata.cup_size,
                })
                self.logger.info(f"从 ThePornDB 获取到 {actor_name} 的元数据")
                metadata_found = True
        except Exception as e:
            self.logger.warning(f"ThePornDB 刮削元数据失败: {e}")
        
        # 2. 刮削照片
        try:
            photos = theporndb_scraper.scrape_photos(actor_name)
            if photos:
                if photos.avatar_url:
                    result['avatar_url'] = photos.avatar_url
                if photos.poster_url:
                    result['poster_url'] = photos.poster_url
                if photos.backdrop_url:
                    result['backdrop_url'] = photos.backdrop_url
                if photos.photo_urls:
                    result['photo_urls'] = photos.photo_urls
                self.logger.info(f"从 ThePornDB 获取到 {actor_name} 的照片")
                photos_found = True
        except Exception as e:
            self.logger.warning(f"ThePornDB 刮削照片失败: {e}")
        
        # 3. 返回结果
        if metadata_found or photos_found:
            self.logger.info(f"欧美演员 {actor_name} 刮削完成")
            return result
        else:
            self.logger.warning(f"欧美演员 {actor_name} 刮削失败：未找到任何信息")
            return None
    
    def _scrape_japanese_actor(self, actor_name: str) -> Optional[Dict[str, Any]]:
        """
        刮削日本演员（使用 XSlist + Gfriends）
        
        Args:
            actor_name: 演员名称
        
        Returns:
            演员信息字典或 None
        """
        result = {'name': actor_name}
        metadata_found = False
        xslist_photos_found = False
        gfriends_photos_found = False
        
        # 查找 XSlist 刮削器
        xslist_scraper = None
        for scraper in self.metadata_scrapers:
            if scraper.name == 'xslist':
                xslist_scraper = scraper
                break
        
        # 1. 刮削元数据（XSlist）
        if xslist_scraper:
            try:
                metadata = xslist_scraper.scrape_metadata(actor_name)
                if metadata:
                    result.update({
                        'biography': metadata.biography,
                        'birth_date': metadata.birth_date,
                        'nationality': metadata.nationality,
                        'height': metadata.height,
                        'measurements': metadata.measurements,
                        'cup_size': metadata.cup_size,
                    })
                    self.logger.info(f"从 XSlist 获取到 {actor_name} 的元数据")
                    metadata_found = True
            except Exception as e:
                self.logger.warning(f"XSlist 刮削元数据失败: {e}")
        
        # 2. 刮削照片 - XSlist（头像 + 写真）
        if xslist_scraper:
            try:
                photos = xslist_scraper.scrape_photos(actor_name)
                if photos:
                    if photos.avatar_url:
                        result['avatar_url'] = photos.avatar_url
                    if photos.photo_urls:
                        result['photo_urls'] = photos.photo_urls
                    self.logger.info(f"从 XSlist 获取到 {actor_name} 的头像和写真")
                    xslist_photos_found = True
            except Exception as e:
                self.logger.warning(f"XSlist 刮削照片失败: {e}")
        
        # 3. 刮削照片 - Gfriends（背景图 + 封面）
        for scraper in self.photo_scrapers:
            try:
                photos = scraper.scrape_photos(actor_name)
                if photos:
                    if photos.backdrop_url:
                        result['backdrop_url'] = photos.backdrop_url
                    if photos.poster_url:
                        result['poster_url'] = photos.poster_url
                    self.logger.info(f"从 {scraper.name} 获取到 {actor_name} 的背景图和封面")
                    gfriends_photos_found = True
                    break
            except Exception as e:
                self.logger.warning(f"{scraper.name} 刮削照片失败: {e}")
                continue
        
        # 4. 返回结果
        if metadata_found or xslist_photos_found or gfriends_photos_found:
            self.logger.info(f"日本演员 {actor_name} 刮削完成 (元数据: {metadata_found}, XSlist照片: {xslist_photos_found}, Gfriends照片: {gfriends_photos_found})")
            return result
        else:
            self.logger.warning(f"日本演员 {actor_name} 刮削失败：未找到任何信息")
            return None
    
    def batch_scrape_actors(self, actor_names: List[str]) -> List[Dict[str, Any]]:
        """
        批量刮削演员信息
        
        Args:
            actor_names: 演员名称列表
        
        Returns:
            演员信息列表，每个元素是一个字典
        """
        self.logger.info(f"开始批量刮削 {len(actor_names)} 位演员")
        
        results = []
        success_count = 0
        
        for actor_name in actor_names:
            try:
                result = self.scrape_actor(actor_name)
                if result:
                    results.append(result)
                    success_count += 1
                else:
                    # 即使失败也返回基本信息
                    results.append({'name': actor_name})
            except Exception as e:
                self.logger.error(f"刮削 {actor_name} 时发生错误: {e}")
                results.append({'name': actor_name})
        
        self.logger.info(f"批量刮削完成: 成功 {success_count}/{len(actor_names)}")
        return results


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== 演员刮削管理器测试 ===\n")
    
    # 加载配置
    config = load_config()
    
    # 创建管理器
    manager = ActorScraperManager(config)
    
    # 测试单个演员
    print("【测试1】单个演员刮削")
    actor_name = '天海つばさ'
    result = manager.scrape_actor(actor_name)
    if result:
        print(f"✓ 刮削成功: {actor_name}")
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"✗ 刮削失败: {actor_name}")
    print()
    
    # 测试批量刮削
    print("【测试2】批量演员刮削")
    actor_names = ['桥本有菜', '明日花キララ', '不存在的演员']
    results = manager.batch_scrape_actors(actor_names)
    print(f"批量刮削完成，共 {len(results)} 位演员")
    for result in results:
        has_data = any(k != 'name' for k in result.keys())
        status = "✓" if has_data else "✗"
        print(f"{status} {result['name']}: {len(result)} 个字段")
    print()
    
    print("=== 测试完成 ===")
