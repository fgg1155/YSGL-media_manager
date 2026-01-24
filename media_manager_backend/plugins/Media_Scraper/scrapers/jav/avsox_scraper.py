"""
AVSOX 刮削器
从 AVSOX 抓取影片数据（无码影片数据库）
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


class AvsoxScraper(BaseScraper):
    """AVSOX 刮削器 - 专注于无码影片"""
    
    name = 'avsox'
    permanent_url = 'https://avsox.click'
    
    def __init__(self, config):
        """初始化 AVSOX 刮削器"""
        super().__init__(config, use_scraper=True)  # 使用 cloudscraper 绕过 Cloudflare
        
        # 根据是否有代理选择 base_url
        if config.get('network', {}).get('proxy_server'):
            self.base_url = self.permanent_url
            self.mirror_sites = []
        else:
            # 如果没有代理，使用免代理镜像站点
            proxy_free = config.get('network', {}).get('proxy_free', {}).get('avsox', [])
            
            if isinstance(proxy_free, list) and proxy_free:
                self.base_url = proxy_free[0]
                self.mirror_sites = proxy_free[1:]
            elif isinstance(proxy_free, str):
                self.base_url = proxy_free
                self.mirror_sites = []
            else:
                self.base_url = self.permanent_url
                self.mirror_sites = []
        
        # 记录上次成功的站点
        self.last_working_site = self.base_url
        
        # 设置快速失败的超时时间（秒）
        self.quick_timeout = 30  # AVSOX 需要更长时间处理 Cloudflare（从10秒改为30秒）
        
        self.logger.info(f"使用 base_url: {self.base_url}")
        if self.mirror_sites:
            self.logger.info(f"备用镜像站点: {len(self.mirror_sites)} 个")
    
    def _scrape_impl(self, dvdid: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        Args:
            dvdid: DVD ID 格式的番号（如 082713-417, FC2-1234567）
        
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
        # AVSOX 无法直接跳转到影片页面，需要先搜索
        full_id = dvdid
        
        # FC2 番号特殊处理
        if full_id.startswith('FC2-'):
            full_id = full_id.replace('FC2-', 'FC2-PPV-')
        
        # 1. 搜索番号（带重试机制，因为 Cloudflare 第一次可能会拒绝）
        search_url = f'{base_url}/tw/search/{full_id}'
        self.logger.debug(f"搜索 URL: {search_url}")
        
        # 重试最多 3 次
        max_retries = 3
        last_error = None
        
        for attempt in range(max_retries):
            try:
                if attempt > 0:
                    self.logger.debug(f"重试第 {attempt} 次...")
                    import time
                    time.sleep(2)  # 等待 2 秒后重试
                
                resp = self.request.get(search_url)
                resp.encoding = 'utf-8'
                html = lxml.html.fromstring(resp.text)
                html.make_links_absolute(search_url, resolve_base_href=True)
                break  # 成功，跳出重试循环
                
            except NetworkError as e:
                last_error = e
                if attempt < max_retries - 1:
                    self.logger.debug(f"连接失败，准备重试: {e}")
                    continue
                else:
                    # 最后一次重试也失败了
                    raise e
        
        # 2. 从搜索结果中找到目标影片
        ids = html.xpath("//div[@class='photo-info']/span/date[1]/text()")
        urls = html.xpath("//a[contains(@class, 'movie-box')]/@href")
        
        if not ids or not urls:
            raise MovieNotFoundError(self.name, dvdid, [])
        
        # 查找匹配的番号（不区分大小写）
        ids_lower = [id.lower() for id in ids]
        full_id_lower = full_id.lower()
        
        if full_id_lower not in ids_lower:
            raise MovieNotFoundError(self.name, dvdid, ids)
        
        # 获取详情页 URL（切换到中文版）
        detail_url = urls[ids_lower.index(full_id_lower)]
        detail_url = detail_url.replace('/tw/', '/cn/', 1)
        
        self.logger.debug(f"详情页 URL: {detail_url}")
        
        # 3. 访问详情页
        resp = self.request.get(detail_url)
        resp.encoding = 'utf-8'
        html = lxml.html.fromstring(resp.text)
        html.make_links_absolute(detail_url, resolve_base_href=True)
        
        # 4. 解析详情页
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
            container = html.xpath("/html/body/div[@class='container']")[0]
            
            # 标题
            title_tag = container.xpath("h3/text()")
            if title_tag:
                result.title = title_tag[0].strip()
            
            # 封面（大图）
            cover_tag = container.xpath("//a[@class='bigImage']/@href")
            if cover_tag:
                result.poster_url = cover_tag[0]
                # AVSOX 的大图可以作为背景图
                result.backdrop_url = cover_tag[0]
            
            # 信息区域
            info = container.xpath("div/div[@class='col-md-3 info']")[0]
            
            # 番号（确认）
            dvdid_tag = info.xpath("p/span[@style]/text()")
            if dvdid_tag:
                code = dvdid_tag[0].strip()
                # FC2 番号还原
                result.code = code.replace('FC2-PPV-', 'FC2-')
            else:
                result.code = dvdid
            
            # 发行日期
            date_tag = info.xpath("p/span[text()='发行时间:']")
            if date_tag:
                date_text = date_tag[0].tail
                if date_text:
                    date_text = date_text.strip()
                    if date_text and date_text != '0000-00-00':
                        result.release_date = date_text
                        try:
                            result.year = int(date_text.split('-')[0])
                        except:
                            pass
            
            # 时长
            duration_tag = info.xpath("p/span[text()='长度:']")
            if duration_tag:
                duration_text = duration_tag[0].tail
                if duration_text:
                    duration_text = duration_text.replace('分钟', '').strip()
                    try:
                        duration = int(duration_text)
                        if duration > 0:
                            result.runtime = duration
                    except:
                        pass
            
            # 制作商
            producer_tag = info.xpath("p[text()='制作商: ']")
            if producer_tag:
                producer_elem = producer_tag[0].getnext()
                if producer_elem is not None:
                    producer_links = producer_elem.xpath("a")
                    if producer_links:
                        result.studio = producer_links[0].text_content().strip()
            
            # 系列
            serial_tag = info.xpath("p[text()='系列:']")
            if serial_tag:
                serial_elem = serial_tag[0].getnext()
                if serial_elem is not None:
                    serial_links = serial_elem.xpath("a/text()")
                    if serial_links:
                        series_name = serial_links[0].strip()
                        
                        # FC2 特殊处理：AVSOX 把 FC2 作品的拍摄者归类到'系列'
                        # 而制作商固定为'FC2-PPV'，这不合理，需要调整
                        if dvdid.startswith('FC2-'):
                            result.studio = series_name  # 拍摄者作为制作商
                        else:
                            result.series = series_name
            
            # 类型/标签
            genre_tags = info.xpath("p/span[@class='genre']/a/text()")
            if genre_tags:
                result.genres = [g.strip() for g in genre_tags if g.strip()]
            
            # 演员
            actress_tags = container.xpath("//a[@class='avatar-box']/span/text()")
            if actress_tags:
                result.actors = [a.strip() for a in actress_tags if a.strip()]
            
            # 移除标题中的番号
            if result.title and result.code:
                result.title = result.title.replace(result.code, '').strip()
            
            # 不在这里设置 mosaic，由管理器统一判定
            # result.mosaic = '无码'
            
            return result
            
        except Exception as e:
            self.logger.exception(f"解析详情页失败: {dvdid}")
            return result


if __name__ == '__main__':
    # 测试用例
    import json
    from core.config_loader import load_config
    
    print("=== AVSOX 刮削器测试 ===\n")
    
    # 加载配置
    config = load_config()
    print(f"配置加载成功")
    print(f"  proxy_free.avsox: {config.get('network', {}).get('proxy_free', {}).get('avsox', [])}")
    print()
    
    # 创建刮削器
    scraper = AvsoxScraper(config)
    
    # 测试番号（无码作品）
    test_codes = [
        '082713-417',      # 一本道
        'FC2-1234567',     # FC2
        '032620_001',      # 加勒比
    ]
    
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
                print(f"  系列: {result.series}")
                print(f"  演员: {', '.join(result.actors[:3]) if result.actors else '无'}...")
                print(f"  类型: {', '.join(result.genres[:3]) if result.genres else '无'}...")
                print(f"  马赛克: {result.mosaic}")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
