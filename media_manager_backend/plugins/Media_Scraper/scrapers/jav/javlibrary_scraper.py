"""
JAVLibrary 刮削器
从 JAVLibrary 抓取影片数据
"""

import logging
from typing import Optional
from urllib.parse import urlsplit

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, MovieDuplicateError, NetworkError


logger = logging.getLogger(__name__)


class JAVLibraryScraper(BaseScraper):
    """JAVLibrary 刮削器"""
    
    name = 'javlibrary'
    # 使用代理网站访问
    base_url = 'https://w91h.com'
    permanent_url = 'https://www.javlibrary.com'
    
    def __init__(self, config):
        """初始化 JAVLibrary 刮削器（使用 cloudscraper）"""
        super().__init__(config, use_scraper=True)
        self.logger.info(f"使用代理网站: {self.base_url}")
    
    def _scrape_impl(self, dvdid: str) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        Args:
            dvdid: DVD ID 格式的番号（如 IPX-177）
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        # 1. 搜索番号
        search_url = f'{self.base_url}/cn/vl_searchbyid.php?keyword={dvdid}'
        self.logger.debug(f"搜索 URL: {search_url}")
        
        resp = self.request.get(search_url)
        
        # 2. 解析 HTML（使用 resp2html 方式）
        html = self._resp2html(resp)
        
        # 3. 处理重定向
        if resp.history:
            if urlsplit(resp.url).netloc == urlsplit(self.base_url).netloc:
                # 重定向到详情页（只有一个搜索结果）
                detail_url = resp.url
                self.logger.debug(f"自动重定向到详情页: {detail_url}")
            else:
                # 重定向到不同域名，更新 base_url
                new_base = 'https://' + urlsplit(resp.url).netloc
                self.logger.warning(f"检测到新的 base_url: {new_base}")
                self.base_url = new_base
                # 重新搜索
                return self._scrape_impl(dvdid)
        else:
            # 没有重定向，需要从搜索结果中选择
            detail_url = self._parse_search_results_from_html(html, dvdid)
            self.logger.debug(f"从搜索结果选择: {detail_url}")
            # 重新获取详情页
            html = self.request.get_html(detail_url)
            html.make_links_absolute(detail_url, resolve_base_href=True)
        
        # 4. 解析详情页
        result = self._parse_detail(html, dvdid)
        
        # 5. 设置 code
        result.code = dvdid
        
        self.logger.info(f"刮削成功: {dvdid}")
        return result
    
    def _resp2html(self, resp):
        """
        将 Response 转换为 lxml HTML 对象
        参考 JavSP 的 resp2html 实现
        """
        import lxml.html
        
        # 设置编码
        if resp.encoding:
            text = resp.text
        else:
            resp.encoding = resp.apparent_encoding
            text = resp.text
        
        # 解析 HTML
        html = lxml.html.fromstring(text)
        
        # 将相对链接转换为绝对链接
        html.make_links_absolute(resp.url, resolve_base_href=True)
        
        return html
    
    def _parse_search_results_from_html(self, html, dvdid: str) -> str:
        """
        从已解析的 HTML 中提取搜索结果
        
        Args:
            html: lxml.html.HtmlElement 对象
            dvdid: 番号
        
        Returns:
            详情页 URL
        """
        # 查找所有视频结果
        video_tags = html.xpath("//div[@class='video'][@id]/a")
        
        if not video_tags:
            raise MovieNotFoundError(self.name, dvdid)
        
        # 查找完全匹配的结果
        matches = []
        for tag in video_tags:
            tag_dvdid = tag.xpath("div[@class='id']/text()")
            if tag_dvdid and tag_dvdid[0].upper() == dvdid.upper():
                matches.append(tag)
        
        match_count = len(matches)
        
        if match_count == 0:
            raise MovieNotFoundError(self.name, dvdid)
        elif match_count == 1:
            # 由于已经调用了 make_links_absolute，这里的 href 已经是绝对 URL
            return matches[0].get('href')
        elif match_count == 2:
            # 可能有蓝光版本，过滤掉蓝光版
            no_blueray = []
            for tag in matches:
                title = tag.get('title', '')
                if 'ブルーレイディスク' not in title:  # Blu-ray Disc
                    no_blueray.append(tag)
            
            if len(no_blueray) == 1:
                self.logger.debug(f"存在 {match_count} 个结果，已过滤蓝光版本")
                return no_blueray[0].get('href')
            else:
                # 番号重复
                raise MovieDuplicateError(self.name, dvdid, match_count)
        else:
            # 番号重复
            raise MovieDuplicateError(self.name, dvdid, match_count)
    
    def _parse_detail(self, html, dvdid: str) -> ScrapeResult:
        """
        解析详情页
        
        Args:
            html: lxml.html.HtmlElement 对象
            dvdid: 番号
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        try:
            # 右侧容器
            container_list = html.xpath("/html/body/div/div[@id='rightcolumn']")
            if not container_list:
                # 尝试其他可能的路径
                container_list = html.xpath("//div[@id='rightcolumn']")
            
            if not container_list:
                self.logger.error(f"无法找到内容容器: {dvdid}")
                return result
            
            container = container_list[0]
            
            # 标题
            title_tag = container.xpath("div/h3/a/text()")
            if title_tag:
                title = title_tag[0]
                # 移除标题中的番号
                result.title = title.replace(dvdid, '').strip()
            
            # 封面
            cover_tag = container.xpath("//img[@id='video_jacket_img']/@src")
            if cover_tag:
                cover = cover_tag[0]
                # 补全协议
                if cover.startswith('//'):
                    cover = 'https:' + cover
                
                # JAVLibrary 的封面 URL 格式：
                # https://pics.dmm.co.jp/mono/movie/adult/83sma132/83sma132pl.jpg (大图)
                # 我们需要：
                # - pl.jpg (大图) 作为背景图 (backdrop)
                # - ps.jpg (小图) 作为封面图 (poster)
                
                if 'pl.jpg' in cover:
                    # 当前是大图，用作背景图
                    result.backdrop_url = cover
                    # 生成小图 URL 作为封面
                    result.poster_url = cover.replace('pl.jpg', 'ps.jpg')
                else:
                    # 如果不是标准格式，直接使用
                    result.poster_url = cover
            
            # 信息区域
            info_list = container.xpath("//div[@id='video_info']")
            if not info_list:
                self.logger.warning(f"无法找到信息区域: {dvdid}")
                return result
            
            info = info_list[0]
            
            # 番号（确认）
            dvdid_tag = info.xpath("div[@id='video_id']//td[@class='text']/text()")
            if dvdid_tag:
                result.code = dvdid_tag[0]
            
            # 发行日期
            date_tag = info.xpath("div[@id='video_date']//td[@class='text']/text()")
            if date_tag:
                result.release_date = date_tag[0]
                # 提取年份
                try:
                    result.year = int(date_tag[0].split('-')[0])
                except:
                    pass
            
            # 时长
            duration_tag = info.xpath("div[@id='video_length']//span[@class='text']/text()")
            if duration_tag:
                try:
                    # 格式: "120 分钟"
                    duration_str = duration_tag[0].strip()
                    result.runtime = int(duration_str.split()[0])
                except:
                    pass
            
            # 导演
            director_tag = info.xpath("//span[@class='director']/a/text()")
            if director_tag:
                # 导演信息暂时不存储在 ScrapeResult 中
                pass
            
            # 制作商
            producer_tag = info.xpath("//span[@class='maker']/a/text()")
            if producer_tag:
                result.studio = producer_tag[0]
            
            # 发行商
            publisher_tag = info.xpath("//span[@class='label']/a/text()")
            if publisher_tag:
                # 发行商信息暂时不存储（可以用 series 字段）
                result.series = publisher_tag[0]
            
            # 评分
            score_tag = info.xpath("//span[@class='score']/text()")
            if score_tag:
                try:
                    score_str = score_tag[0].strip('()')
                    result.rating = float(score_str)
                except:
                    pass
            
            # 类型/标签
            genre_tags = info.xpath("//span[@class='genre']/a/text()")
            if genre_tags:
                result.genres = genre_tags
            
            # 演员
            actress_tags = info.xpath("//span[@class='star']/a/text()")
            if actress_tags:
                result.actors = actress_tags
            
            # 预览图/截图
            # 尝试从 HTML 中提取预览图（有些番号的预览图直接在 HTML 中）
            preview_tags = html.xpath("//div[@class='previewthumbs']//a/@href")
            if preview_tags:
                # 补全协议
                previews = []
                for preview in preview_tags:
                    if preview.startswith('//'):
                        preview = 'https:' + preview
                    previews.append(preview)
                
                if previews:
                    result.preview_urls = previews
                    self.logger.debug(f"找到 {len(previews)} 张预览图")
            else:
                # 有些番号的预览图需要 JavaScript 动态加载，这里暂时不支持
                self.logger.debug("未找到预览图（可能需要 JavaScript 加载）")
            
            return result
        
        except Exception as e:
            self.logger.exception(f"解析详情页失败: {dvdid}")
            # 返回部分结果而不是抛出异常
            return result


if __name__ == '__main__':
    # 测试用例
    import json
    
    print("=== JAVLibrary 刮削器测试 ===\n")
    
    # 创建配置
    config = {
        'network': {
            'proxy_server': None,
            'timeout': 30,
            'retry': 3
        }
    }
    
    # 创建刮削器
    scraper = JAVLibraryScraper(config)
    
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
                print(f"  演员: {', '.join(result.actors[:3])}...")
                print(f"  类型: {', '.join(result.genres[:3])}...")
                print(f"  预览图: {len(result.preview_urls)} 张")
                if result.preview_urls:
                    print(f"    第一张: {result.preview_urls[0]}")
            else:
                print(f"✗ 刮削失败")
        except Exception as e:
            print(f"✗ 错误: {e}")
        print()
    
    print("=== 测试完成 ===")
