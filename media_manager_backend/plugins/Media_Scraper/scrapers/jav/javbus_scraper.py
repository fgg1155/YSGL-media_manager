"""
JavBus 刮削器
从 JavBus 抓取影片数据
"""

import logging
import lxml.html
from typing import Optional

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, NetworkError


logger = logging.getLogger(__name__)


class JavBusScraper(BaseScraper):
    """JavBus 刮削器"""
    
    name = 'javbus'
    permanent_url = 'https://www.javbus.com'
    
    def __init__(self, config):
        """初始化 JavBus 刮削器"""
        super().__init__(config, use_scraper=False)
        
        # JavBus 不需要特殊的 cookie，保持默认即可
        # self.request.cookies = {}  # 已经在 Request 类中初始化为空字典
        
        # 根据是否有代理选择 base_url
        if config.get('network', {}).get('proxy_server'):
            self.base_url = self.permanent_url
            self.mirror_sites = []
        else:
            # 如果没有代理，使用免代理镜像站点
            proxy_free = config.get('network', {}).get('proxy_free', {}).get('javbus', [])
            
            # 如果配置的是列表，使用第一个作为 base_url，其余作为备用
            if isinstance(proxy_free, list) and proxy_free:
                self.base_url = proxy_free[0]
                self.mirror_sites = proxy_free[1:]
            elif isinstance(proxy_free, str):
                self.base_url = proxy_free
                self.mirror_sites = []
            else:
                self.base_url = self.permanent_url
                self.mirror_sites = []
        
        # 记录上次成功的站点（用于优化）
        self.last_working_site = self.base_url
        
        # 设置快速失败的超时时间（秒）
        self.quick_timeout = 5
        
        self.logger.info(f"使用 base_url: {self.base_url}")
        if self.mirror_sites:
            self.logger.info(f"备用镜像站点: {len(self.mirror_sites)} 个")
    
    def _scrape_impl(self, dvdid: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        Args:
            dvdid: DVD ID 格式的番号（如 IPX-177）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 优化：优先尝试上次成功的站点
        all_sites = [self.last_working_site]
        
        # 添加其他站点（排除上次成功的）
        for site in [self.base_url] + self.mirror_sites:
            if site != self.last_working_site and site not in all_sites:
                all_sites.append(site)
        
        last_error = None
        for url in all_sites:
            try:
                self.logger.debug(f"尝试使用站点: {url}")
                
                # 使用快速超时进行尝试
                old_timeout = self.request.timeout
                self.request.timeout = self.quick_timeout
                
                try:
                    result = self._scrape_with_url(url, dvdid)
                finally:
                    # 恢复原始超时
                    self.request.timeout = old_timeout
                
                # 如果成功，记录这个站点并更新 base_url
                if result:
                    self.last_working_site = url
                    if url != self.base_url:
                        self.logger.info(f"切换到可用镜像站点: {url}")
                        self.base_url = url
                    return result
                    
            except NetworkError as e:
                last_error = e
                self.logger.debug(f"站点 {url} 连接失败: {e}")
                continue
            except Exception as e:
                # 其他错误（如未找到影片）直接抛出
                raise e
        
        # 所有站点都失败，抛出最后一个网络错误
        if last_error:
            raise last_error
        
        # 不应该到这里
        raise NetworkError("所有镜像站点均无法连接", "All mirror sites failed")
    
    def _scrape_with_url(self, base_url: str, dvdid: str) -> Optional[ScrapeResult]:
        """
        使用指定的 base_url 刮削番号
        
        Args:
            base_url: 站点 URL
            dvdid: DVD ID 格式的番号
        
        Returns:
            ScrapeResult 对象，失败返回 None
        """
        # 1. 访问详情页
        detail_url = f'{base_url}/{dvdid}'
        self.logger.debug(f"详情页 URL: {detail_url}")
        
        # 获取响应（使用 delay_raise=True 来处理 302 重定向）
        resp = self.request.get(detail_url, delay_raise=True)
        
        # JavBus 特殊处理：如果有 302 重定向，使用重定向前的响应
        # 疑似 JavBus 检测到类似爬虫的行为时会要求登录，但重定向前的网页中已包含完整信息
        if resp.history and resp.history[0].status_code == 302:
            resp = resp.history[0]
        
        # 解析 HTML
        resp.encoding = 'utf-8'
        html = lxml.html.fromstring(resp.text)
        html.make_links_absolute(detail_url, resolve_base_href=True)
        
        # 2. 检查是否 404
        page_title = html.xpath('/html/head/title/text()')
        if page_title and page_title[0].startswith('404 Page Not Found!'):
            raise MovieNotFoundError(self.name, dvdid)
        
        # 3. 解析详情页
        result = self._parse_detail(html, detail_url, dvdid)
        return result
    
    def _parse_detail(self, html, detail_url: str, dvdid: str) -> ScrapeResult:
        """
        解析详情页
        
        Args:
            html: lxml.html.HtmlElement 对象
            detail_url: 详情页 URL
            dvdid: 番号
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        try:
            # 主容器
            container = html.xpath("//div[@class='container']")[0]
            
            # 标题
            title_tag = container.xpath("h3/text()")
            if title_tag:
                result.title = title_tag[0].strip()
            
            # 封面
            cover_tag = container.xpath("//a[@class='bigImage']/img/@src")
            if cover_tag:
                cover_url = cover_tag[0]
                # 检查是否是大图格式 (例如: /pics/cover/bxh1_b.jpg)
                if '/pics/cover/' in cover_url and cover_url.endswith('_b.jpg'):
                    # 大图作为背景图
                    result.backdrop_url = cover_url
                    # 生成小图作为封面 (例如: /pics/thumb/bxh1.jpg)
                    # 提取文件名部分，去掉 _b.jpg，替换为 .jpg，并改变路径
                    filename = cover_url.split('/')[-1]  # 获取 bxh1_b.jpg
                    base_name = filename.replace('_b.jpg', '')  # 获取 bxh1
                    # 保留原始域名，只替换路径和文件名
                    result.poster_url = cover_url.replace(f'/pics/cover/{filename}', f'/pics/thumb/{base_name}.jpg')
                else:
                    # 其他格式直接作为封面
                    result.poster_url = cover_url
            
            # 预览图
            preview_pics = container.xpath("//div[@id='sample-waterfall']/a/@href")
            if preview_pics:
                result.preview_urls = preview_pics
                self.logger.debug(f"找到 {len(preview_pics)} 张预览图")
            
            # 信息区域
            info = container.xpath("//div[@class='col-md-3 info']")[0]
            
            # 番号（确认）
            dvdid_tag = info.xpath("p/span[text()='識別碼:']")
            if dvdid_tag:
                result.code = dvdid_tag[0].getnext().text.strip()
            else:
                result.code = dvdid
            
            # 发行日期
            date_tag = info.xpath("p/span[text()='發行日期:']")
            if date_tag:
                date_text = date_tag[0].tail.strip()
                if date_text and date_text != '0000-00-00':  # 丢弃无效日期
                    result.release_date = date_text
                    try:
                        result.year = int(date_text.split('-')[0])
                    except:
                        pass
            
            # 时长
            duration_tag = info.xpath("p/span[text()='長度:']")
            if duration_tag:
                duration_text = duration_tag[0].tail.replace('分鐘', '').strip()
                try:
                    duration = int(duration_text)
                    if duration > 0:
                        result.runtime = duration
                except:
                    pass
            
            # 导演
            director_tag = info.xpath("p/span[text()='導演:']")
            if director_tag:
                director_elem = director_tag[0].getnext()
                if director_elem is not None and director_elem.text:
                    result.director = director_elem.text.strip()
            
            # 制作商
            producer_tag = info.xpath("p/span[text()='製作商:']")
            if producer_tag:
                producer_elem = producer_tag[0].getnext()
                if producer_elem is not None and producer_elem.text:
                    result.studio = producer_elem.text.strip()
            
            # 发行商（用 series 字段存储）
            publisher_tag = info.xpath("p/span[text()='發行商:']")
            if publisher_tag:
                publisher_elem = publisher_tag[0].getnext()
                if publisher_elem is not None and publisher_elem.text:
                    result.series = publisher_elem.text.strip()
            
            # 系列（如果有的话，覆盖 series 字段）
            serial_tag = info.xpath("p/span[text()='系列:']")
            if serial_tag:
                serial_elem = serial_tag[0].getnext()
                if serial_elem is not None and serial_elem.text:
                    result.series = serial_elem.text.strip()
            
            # 类型/标签
            genre_tags = info.xpath("//span[@class='genre']/label/a")
            if genre_tags:
                genres = []
                for tag in genre_tags:
                    genre_text = tag.text
                    if genre_text:
                        genres.append(genre_text.strip())
                result.genres = genres
            
            # 演员
            actress_tags = html.xpath("//a[@class='avatar-box']/div/img")
            if actress_tags:
                actresses = []
                for tag in actress_tags:
                    name = tag.get('title')
                    if name:
                        actresses.append(name.strip())
                result.actors = actresses
            
            # 移除标题中的番号
            if result.title and result.code:
                result.title = result.title.replace(result.code, '').strip()
            
            return result
            
        except Exception as e:
            self.logger.exception(f"解析详情页失败: {dvdid}")
            return result


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== JavBus 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功")
    print(f"  proxy_free.javbus: {config.get('network', {}).get('proxy_free', {}).get('javbus', [])}")
    print()
    
    # 创建刮削器
    scraper = JavBusScraper(config)
    
    # 测试番号
    test_codes = ['IPX-177', 'SSIS-001']
    
    for code in test_codes:
        print(f"测试番号: {code}")
        try:
            result = scraper.scrape(code)
            if result:
                print(f"✓ 刮削成功")
                print(f"  标题: {result.title}")
                print(f"  封面: {result.poster_url}")
                print(f"  发行日期: {result.release_date}")
                print(f"  制作商: {result.studio}")
                print(f"  演员: {', '.join(result.actors[:3]) if result.actors else '无'}...")
                print(f"  类型: {', '.join(result.genres[:3]) if result.genres else '无'}...")
                print(f"  预览图: {len(result.preview_urls)} 张")
                if result.preview_urls:
                    print(f"    第一张: {result.preview_urls[0]}")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
