"""
Gfriends 演员照片刮削器
从 Gfriends 仓库获取演员照片 URL
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.actor.base_actor_scraper import BaseActorScraper, ActorMetadata, ActorPhotos
from web.request import Request
from typing import Optional, Dict
import json


class GfriendsActorScraper(BaseActorScraper):
    """Gfriends 演员照片刮削器"""
    
    name = 'gfriends'
    
    def __init__(self, config):
        """初始化刮削器"""
        super().__init__(config)
        
        # 获取配置
        gfriends_config = config.get('actor_scraper', {}).get('photos', {}).get('gfriends', {})
        self.base_url = gfriends_config.get('url', 'https://raw.githubusercontent.com/gfriends/gfriends/master/')
        self.use_ai_fix = gfriends_config.get('use_ai_fix', True)
        self.timeout = gfriends_config.get('timeout', 5)
        
        # 确保 base_url 以 / 结尾
        if not self.base_url.endswith('/'):
            self.base_url += '/'
        
        self.request = Request(config, use_scraper=False)
        
        # 缓存 Filetree
        self._filetree = None
    
    def _load_filetree(self) -> Dict:
        """加载 Filetree.json"""
        if self._filetree is not None:
            return self._filetree
        
        try:
            filetree_url = f"{self.base_url}Filetree.json"
            self.logger.info(f"加载 Filetree: {filetree_url}")
            response = self.request.get(filetree_url)
            self._filetree = response.json()
            self.logger.info("Filetree 加载成功")
            return self._filetree
        except Exception as e:
            self.logger.error(f"加载 Filetree 失败: {e}")
            return {}
    
    def scrape_metadata(self, actor_name: str) -> Optional[ActorMetadata]:
        """Gfriends 不提供元数据"""
        return None
    
    def scrape_photos(self, actor_name: str) -> Optional[ActorPhotos]:
        """
        从 Gfriends 获取演员照片 URL
        
        Args:
            actor_name: 演员名称（日文原名）
        
        Returns:
            ActorPhotos 对象，失败返回 None
        """
        try:
            # 加载 Filetree
            filetree = self._load_filetree()
            if not filetree:
                self.logger.warning("Filetree 为空，无法搜索")
                return None
            
            content = filetree.get('Content', {})
            
            # 搜索演员照片（支持 jpg 和 png）
            for ext in ['jpg', 'png']:
                filename = f"{actor_name}.{ext}"
                
                # 遍历所有分类目录
                for category, files in content.items():
                    if filename in files:
                        # 找到了！构建 URL
                        relative_path = files[filename]
                        # 移除时间戳参数
                        if '?' in relative_path:
                            relative_path = relative_path.split('?')[0]
                        
                        url = f"{self.base_url}Content/{category}/{relative_path}"
                        self.logger.info(f"找到 {actor_name} 的照片: {url}")
                        
                        return ActorPhotos(
                            name=actor_name,
                            avatar_url=None,         # Gfriends 不提供头像
                            poster_url=url,          # Gfriends 的图片作为封面
                            photo_urls=[],           # Gfriends 不提供写真
                            backdrop_url=url,        # Gfriends 的图片也作为背景图
                            source='gfriends'
                        )
            
            self.logger.warning(f"未找到 {actor_name} 的照片")
            return None
        
        except Exception as e:
            self.logger.exception(f"获取 {actor_name} 照片失败: {e}")
            return None


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== Gfriends 演员照片刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    
    # 创建刮削器
    scraper = GfriendsActorScraper(config)
    print(f"Base URL: {scraper.base_url}")
    print(f"使用 AI 优化: {scraper.use_ai_fix}\n")
    
    # 测试演员
    test_actors = ['天海つばさ', '桥本有菜', '明日花キララ']
    
    for actor in test_actors:
        print(f"测试演员: {actor}")
        try:
            photos = scraper.scrape_photos(actor)
            if photos:
                print(f"✓ 找到照片")
                print(f"  Avatar URL: {photos.avatar_url}")
                print(f"  Poster URL: {photos.poster_url}")
                print(f"  来源: {photos.source}")
            else:
                print(f"✗ 未找到照片")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
