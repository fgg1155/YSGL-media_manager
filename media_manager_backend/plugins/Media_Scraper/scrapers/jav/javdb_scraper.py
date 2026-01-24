"""
JAVDatabase (JAVDB) 刮削器
从 JAVDB 抓取影片数据
"""

import logging
import re
from typing import Optional
from urllib.parse import urlsplit

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, MovieDuplicateError, NetworkError, SitePermissionError, CredentialError


logger = logging.getLogger(__name__)


class JAVDBScraper(BaseScraper):
    """JAVDB 刮削器"""
    
    name = 'javdb'
    permanent_url = 'https://javdb.com'
    
    def __init__(self, config):
        """初始化 JAVDB 刮削器（使用 cloudscraper 绕过 CloudFlare）"""
        super().__init__(config, use_scraper=True)
        
        # 设置语言为中文，避免返回其他语言页面
        self.request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,zh-TW;q=0.8,en-US;q=0.7,en;q=0.6,ja;q=0.5'
        
        # 根据是否有代理选择 base_url
        if config.get('network', {}).get('proxy_server'):
            self.base_url = self.permanent_url
            self.mirror_sites = []
        else:
            # 如果没有代理，使用免代理镜像站点
            proxy_free = config.get('network', {}).get('proxy_free', {}).get('javdb', [])
            
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
        # 1. 搜索番号
        search_url = f'{base_url}/search?q={dvdid}'
        self.logger.debug(f"搜索 URL: {search_url}")
        
        html = self.request.get_html(search_url)
        
        # 2. 从搜索结果中找到匹配的番号
        ids = html.xpath("//div[@class='video-title']/strong/text()")
        ids_lower = [i.lower() for i in ids]
        movie_urls = html.xpath("//a[@class='box']/@href")
        
        match_count = ids_lower.count(dvdid.lower())
        
        if match_count == 0:
            raise MovieNotFoundError(self.name, dvdid)
        elif match_count == 1:
            index = ids_lower.index(dvdid.lower())
            detail_url = movie_urls[index]
            
            # 补全 URL
            if not detail_url.startswith('http'):
                detail_url = base_url + detail_url
            
            self.logger.debug(f"详情页 URL: {detail_url}")
            
            # 3. 获取详情页
            try:
                html2 = self.request.get_html(detail_url)
            except (SitePermissionError, CredentialError) as e:
                # VIP 内容，尝试从搜索结果中提取基本信息
                self.logger.warning(f"VIP 内容，仅提取搜索结果中的基本信息: {e}")
                return self._parse_search_result(html, index, detail_url, dvdid)
            
            # 4. 解析详情页
            result = self._parse_detail(html2, detail_url, dvdid)
            return result
        else:
            raise MovieDuplicateError(self.name, dvdid, match_count)
    
    def _parse_search_result(self, html, index: int, detail_url: str, dvdid: str) -> ScrapeResult:
        """
        从搜索结果中提取基本信息（用于 VIP 内容）
        
        Args:
            html: 搜索结果页面的 HTML
            index: 匹配结果的索引
            detail_url: 详情页 URL
            dvdid: 番号
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        box = html.xpath("//a[@class='box']")[index]
        
        # 标题
        result.title = box.get('title', '').replace(dvdid, '').strip()
        
        # 封面
        cover_tag = box.xpath("div/img/@src")
        if cover_tag:
            result.poster_url = cover_tag[0]
        
        # 评分
        score_tag = box.xpath("div[@class='score']/span/span")
        if score_tag and score_tag[0].tail:
            score_match = re.search(r'([\d.]+)分', score_tag[0].tail)
            if score_match:
                # JAVDB 评分是 5 分制，转换为 10 分制
                result.rating = float(score_match.group(1)) * 2
        
        # 发行日期
        date_tag = box.xpath("div[@class='meta']/text()")
        if date_tag:
            result.release_date = date_tag[0].strip()
            try:
                result.year = int(date_tag[0].split('-')[0])
            except:
                pass
        
        result.code = dvdid
        
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
            container = html.xpath("/html/body/section/div/div[@class='video-detail']")[0]
            info = container.xpath("//nav[@class='panel movie-panel-info']")[0]
            
            # 标题
            title_tag = container.xpath("h2/strong[@class='current-title']/text()")
            if title_tag:
                result.title = title_tag[0].replace(dvdid, '').strip()
            
            # 封面
            cover_tag = container.xpath("//img[@class='video-cover']/@src")
            if cover_tag:
                result.poster_url = cover_tag[0]
            
            # 预览图
            preview_pics = container.xpath("//a[@class='tile-item'][@data-fancybox='gallery']/@href")
            if preview_pics:
                result.preview_urls = preview_pics
                self.logger.debug(f"找到 {len(preview_pics)} 张预览图")
            
            # 番号（确认）
            dvdid_tag = info.xpath("div/span")
            if dvdid_tag:
                result.code = dvdid_tag[0].text_content().strip()
            
            # 发行日期
            date_tag = info.xpath("div/strong[text()='日期:']")
            if date_tag:
                date_text = date_tag[0].getnext().text
                if date_text:
                    result.release_date = date_text.strip()
                    try:
                        result.year = int(date_text.split('-')[0])
                    except:
                        pass
            
            # 时长
            duration_tag = info.xpath("div/strong[text()='時長:']")
            if duration_tag:
                duration_text = duration_tag[0].getnext().text
                if duration_text:
                    try:
                        result.runtime = int(duration_text.replace('分鍾', '').strip())
                    except:
                        pass
            
            # 制作商
            producer_tag = info.xpath("div/strong[text()='片商:']")
            if producer_tag:
                result.studio = producer_tag[0].getnext().text_content().strip()
            
            # 发行商（用 series 字段存储）
            publisher_tag = info.xpath("div/strong[text()='發行:']")
            if publisher_tag:
                result.series = publisher_tag[0].getnext().text_content().strip()
            
            # 系列（如果有的话，覆盖 series 字段）
            serial_tag = info.xpath("div/strong[text()='系列:']")
            if serial_tag:
                result.series = serial_tag[0].getnext().text_content().strip()
            
            # 评分
            score_tag = info.xpath("//span[@class='score-stars']")
            if score_tag and score_tag[0].tail:
                score_match = re.search(r'([\d.]+)分', score_tag[0].tail)
                if score_match:
                    # JAVDB 评分是 5 分制，转换为 10 分制
                    result.rating = float(score_match.group(1)) * 2
            
            # 类型/标签
            genre_tags = info.xpath("//strong[text()='類別:']/../span/a/text()")
            if genre_tags:
                result.genres = genre_tags
            
            # 演员（只提取女优，过滤男优）
            actors_tag = info.xpath("//strong[text()='演員:']/../span")
            if actors_tag:
                all_actors = actors_tag[0].xpath("a/text()")
                genders = actors_tag[0].xpath("strong/text()")
                
                # 筛选女优（标记为 ♀）
                actresses = [actor for actor in all_actors 
                           if genders[all_actors.index(actor)] == '♀']
                
                if actresses:
                    result.actors = actresses
            
            return result
        
        except Exception as e:
            self.logger.exception(f"解析详情页失败: {dvdid}")
            return result


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== JAVDB 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功")
    print(f"  proxy_free.javdb: {config.get('network', {}).get('proxy_free', {}).get('javdb', [])}")
    print()
    
    # 创建刮削器
    scraper = JAVDBScraper(config)
    
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
