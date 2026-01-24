"""
XSlist 演员元数据刮削器
从 XSlist.org 获取演员个人信息
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.actor.base_actor_scraper import BaseActorScraper, ActorMetadata, ActorPhotos
from web.request import Request
from typing import Optional
import lxml.html


class XSlistActorScraper(BaseActorScraper):
    """XSlist 演员元数据刮削器"""
    
    name = 'xslist'
    base_url = 'https://xslist.org'
    
    def __init__(self, config):
        """初始化刮削器"""
        super().__init__(config)
        
        # XSlist 使用严格的 Cloudflare Turnstile 验证，cloudscraper 无法自动绕过
        # 因此我们先尝试 cloudscraper，如果失败则使用手动 cookie
        self.request = Request(config, use_scraper=True)
        self.timeout = config.get('actor_scraper', {}).get('metadata', {}).get('xslist', {}).get('timeout', 10)
        
        # 获取 Cloudflare cookie（作为备用方案）
        cf_clearance = config.get('actor_scraper', {}).get('metadata', {}).get('xslist', {}).get('cf_clearance', '')
        
        if cf_clearance:
            # 如果配置了 cookie，直接设置（cloudscraper 也支持手动 cookie）
            self.request.cookies['cf_clearance'] = cf_clearance
            self.logger.info("已设置 Cloudflare cookie（手动）")
        else:
            self.logger.warning("未配置 Cloudflare cookie，将尝试 cloudscraper 自动绕过（可能失败）")
        
        # 设置更真实的浏览器 headers
        self.request.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'sec-ch-ua': '"Microsoft Edge";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"',
            'sec-fetch-dest': 'document',
            'sec-fetch-mode': 'navigate',
            'sec-fetch-site': 'none',
            'sec-fetch-user': '?1',
            'upgrade-insecure-requests': '1'
        })
    
    def scrape_metadata(self, actor_name: str) -> Optional[ActorMetadata]:
        """
        从 XSlist 刮削演员元数据
        
        Args:
            actor_name: 演员名称(日文原名效果最佳)
        
        Returns:
            ActorMetadata 对象,失败返回 None
        """
        try:
            # 1. 搜索演员
            search_url = f"{self.base_url}/search?lg=zh&query={actor_name}"
            self.logger.debug(f"搜索演员: {search_url}")
            
            html = self.request.get_html(search_url)
            
            # 2. 获取详情页链接
            detail_urls = html.xpath('/html/body/ul/li/h3/a/@href')
            if not detail_urls:
                self.logger.debug(f"未找到演员: {actor_name}")
                return None
            
            detail_url = detail_urls[0]
            self.logger.debug(f"详情页: {detail_url}")
            
            # 3. 获取详情页
            response = self.request.get(detail_url)
            
            detail_html = lxml.html.fromstring(response.text)
            detail_html.make_links_absolute(detail_url, resolve_base_href=True)
            
            # 4. 解析元数据
            # 尝试多个可能的 XPath
            detail_list = detail_html.xpath('/html/body/div[1]/div[3]/div/p[1]/descendant-or-self::text()')
            
            if not detail_list:
                # 尝试更通用的路径
                detail_list = detail_html.xpath('//div[@class="bio"]//text()')
            if not detail_list:
                detail_list = detail_html.xpath('//div[contains(@class,"content")]//p//text()')
            if not detail_list:
                # 尝试所有 p 标签
                detail_list = detail_html.xpath('//p//text()')
            
            metadata = ActorMetadata(name=actor_name, source='xslist')
            detail_dict = {}
            
            # 解析字段
            for index, info in enumerate(detail_list):
                info = info.replace(' ', '', 2)  # 删掉多余空格
                
                if '身高' in info or '国籍' in info:
                    if index + 1 < len(detail_list) and detail_list[index + 1].split(':')[0] != 'n/a':
                        detail_dict[info.split(':')[0]] = detail_list[index + 1].split(':')[0]
                else:
                    if len(info.split(':')) > 1 and info.split(':')[1] != 'n/a':
                        detail_dict[info.split(':')[0]] = info.split(':')[1]
            
            self.logger.debug(f"解析到的信息: {detail_dict}")
            
            # 映射字段
            if '出生' in detail_dict:
                metadata.birth_date = detail_dict['出生'].replace("年", "-").replace("月", "-").replace("日", "")
            
            if '国籍' in detail_dict:
                metadata.nationality = detail_dict['国籍']
            
            if '身高' in detail_dict:
                metadata.height = detail_dict['身高']
            
            if '罩杯' in detail_dict:
                metadata.cup_size = detail_dict['罩杯']
            
            if '三围' in detail_dict:
                metadata.measurements = detail_dict['三围']
            
            # 构建简介：排除已经单独提取的字段（出生、国籍），保留其他信息
            # 这样可以避免前端显示时重复
            excluded_fields = ['出生', '国籍']
            bio_parts = []
            
            for key, value in detail_dict.items():
                if key not in excluded_fields:
                    bio_parts.append(f"{key}: {value}")
            
            if bio_parts:
                metadata.biography = '\n'.join(bio_parts)
            
            self.logger.info(f"成功获取 {actor_name} 的元数据")
            return metadata
        
        except Exception as e:
            self.logger.warning(f"刮削 {actor_name} 元数据失败: {e}")
            return None
    
    def scrape_photos(self, actor_name: str) -> Optional[ActorPhotos]:
        """
        从 XSlist 刮削演员照片
        
        Args:
            actor_name: 演员名称（日文原名效果最佳）
        
        Returns:
            ActorPhotos 对象，失败返回 None
        """
        try:
            # 1. 搜索演员
            search_url = f"{self.base_url}/search?lg=zh&query={actor_name}"
            self.logger.debug(f"搜索演员照片: {search_url}")
            
            html = self.request.get_html(search_url)
            
            # 2. 获取详情页链接
            detail_urls = html.xpath('/html/body/ul/li/h3/a/@href')
            if not detail_urls:
                self.logger.debug(f"未找到演员: {actor_name}")
                return None
            
            detail_url = detail_urls[0]
            
            # 3. 获取详情页
            response = self.request.get(detail_url)
            detail_html = lxml.html.fromstring(response.text)
            detail_html.make_links_absolute(detail_url, resolve_base_href=True)
            
            # 4. 提取图片
            # 从 gallery 提取所有图片
            photo_urls = detail_html.xpath('//div[@id="gallery"]//img/@src')
            
            if not photo_urls:
                # 如果没有 gallery,尝试其他方式
                photo_urls = detail_html.xpath('//div[@class="gallery"]//img/@src')
            
            if not photo_urls:
                # 最后尝试获取所有演员相关图片
                photo_urls = detail_html.xpath('//img[contains(@src, "model")]/@src')
            
            # 去重
            photo_urls = list(dict.fromkeys(photo_urls)) if photo_urls else []
            
            if not photo_urls:
                self.logger.warning(f"未找到 {actor_name} 的照片")
                return None
            
            # 第一张作为头像,其余作为写真
            # XSlist 不提供封面（poster）和背景图（backdrop）
            avatar_url = photo_urls[0] if photo_urls else None
            photo_list = photo_urls[1:] if len(photo_urls) > 1 else []
            
            self.logger.info(f"找到 {actor_name} 的照片: avatar=1张, photos={len(photo_list)}张")
            
            return ActorPhotos(
                name=actor_name,
                avatar_url=avatar_url,
                poster_url=None,  # XSlist 不提供封面
                photo_urls=photo_list,  # 其余图片作为写真
                backdrop_url=None,  # XSlist 不提供背景图
                source='xslist'
            )
        
        except Exception as e:
            self.logger.warning(f"刮削 {actor_name} 照片失败: {e}")
            return None


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== XSlist 演员刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    
    # 创建刮削器
    scraper = XSlistActorScraper(config)
    
    # 测试演员
    test_actors = ['天海つばさ', '桥本有菜']
    
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
                print(f"  罩杯: {metadata.cup_size}")
                print(f"  简介:\n{metadata.biography}")
            else:
                print(f"✗ 元数据刮削失败")
            
            # 测试照片
            photos = scraper.scrape_photos(actor)
            if photos:
                print(f"✓ 照片刮削成功")
                print(f"  Avatar URL: {photos.avatar_url}")
                print(f"  Poster URL: {photos.poster_url}")
                print(f"  Photo URLs: {len(photos.photo_urls)} 张")
                if photos.photo_urls:
                    print(f"  第一张: {photos.photo_urls[0]}")
            else:
                print(f"✗ 照片刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
