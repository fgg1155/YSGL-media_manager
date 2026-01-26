"""
ThePornDB 刮削器
从 ThePornDB API 刮削欧美成人内容元数据
参考 MDCX 的实现
"""

import logging
import re
import os
from typing import Optional, List, Dict, Any, Tuple
from difflib import SequenceMatcher

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scrapers.base_scraper import BaseScraper
from core.models import ScrapeResult
from web.exceptions import MovieNotFoundError, NetworkError, CredentialError
from core.code_normalizer import CodeNormalizer


logger = logging.getLogger(__name__)


def similarity(a: str, b: str) -> float:
    """计算两个字符串的相似度"""
    return SequenceMatcher(None, a, b).ratio()


class ThePornDBScraper(BaseScraper):
    """ThePornDB 刮削器"""
    
    name = 'theporndb'
    base_url = 'https://api.theporndb.net'
    
    def __init__(self, config: Dict[str, Any]):
        """
        初始化刮削器
        
        Args:
            config: 配置字典，必须包含 'theporndb_api_token'
        """
        super().__init__(config, use_scraper=False)
        self.api_token = config.get('theporndb_api_token', '')
        self.logger = logging.getLogger(__name__)
        
        if not self.api_token:
            self.logger.warning("ThePornDB API token 未配置")
    
    def _scrape_impl(self, code: str, file_path: str = '', content_type_hint: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        刮削实现（由 BaseScraper.scrape() 调用，带统一错误处理）
        
        流程：
        1. 尝试通过文件 hash 搜索（如果提供了文件路径）
        2. 如果 hash 搜索失败，通过文件名搜索
        3. 解析返回的数据
        
        Args:
            code: 番号（如 sexart.11.11.11）
            file_path: 文件路径（可选）
            content_type_hint: 内容类型提示（Scene/Movie），用于选择 API 端点
        
        Returns:
            ScrapeResult 对象，失败抛出异常
        """
        if not self.api_token:
            self.logger.error("ThePornDB API token 未配置，请在配置文件中添加")
            raise CredentialError(
                "ThePornDB API token 未配置",
                "ThePornDB API token not configured",
                self.name
            )
        
        # 设置请求头（更新 Request 对象的 headers）
        self.request.headers.update({
            "Authorization": f"Bearer {self.api_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        
        scene_data = None
        real_url = ''
        
        if not file_path:
            file_path = code + ".mp4"
        
        is_potential_slug = (
            " " not in code
            and not any(code.lower().endswith(ext) for ext in [".mp4", ".mkv", ".avi", ".wmv", ".mov"])
        )
        
        if is_potential_slug:
            self.logger.debug(f"尝试直接使用 slug 获取详情: {code}, content_type_hint: {content_type_hint}")
            try:
                # 根据 content_type_hint 决定优先级
                if content_type_hint == "Movie":
                    # Movie 优先
                    url_detail_movie = f"{self.base_url}/movies/{code}"
                    response_movie = self.request.get(url_detail_movie, delay_raise=False)
                    
                    if response_movie.status_code == 200:
                        res_real_movie = response_movie.json()
                        movie_data = res_real_movie.get("data")
                        if movie_data:
                            self.logger.info(f"通过 slug 在 movies 中找到匹配: {url_detail_movie}")
                            return self._parse_scene_data(movie_data)
                    
                    # 回退到 scenes
                    url_detail = f"{self.base_url}/scenes/{code}"
                    response = self.request.get(url_detail, delay_raise=False)
                    
                    if response.status_code == 200:
                        res_real = response.json()
                        scene_data = res_real.get("data")
                        if scene_data:
                            self.logger.info(f"通过 slug 在 scenes 中找到匹配: {url_detail}")
                            return self._parse_scene_data(scene_data)
                else:
                    # Scene 优先（默认）
                    url_detail = f"{self.base_url}/scenes/{code}"
                    response = self.request.get(url_detail, delay_raise=False)
                    
                    if response.status_code == 200:
                        res_real = response.json()
                        scene_data = res_real.get("data")
                        if scene_data:
                            self.logger.info(f"通过 slug 在 scenes 中找到匹配: {url_detail}")
                            return self._parse_scene_data(scene_data)
                    
                    # 回退到 movies
                    url_detail_movie = f"{self.base_url}/movies/{code}"
                    response_movie = self.request.get(url_detail_movie, delay_raise=False)
                    
                    if response_movie.status_code == 200:
                        res_real_movie = response_movie.json()
                        movie_data = res_real_movie.get("data")
                        if movie_data:
                            self.logger.info(f"通过 slug 在 movies 中找到匹配: {url_detail_movie}")
                            return self._parse_scene_data(movie_data)
            except Exception as e:
                self.logger.warning(f"Slug 直接获取失败，转为搜索模式: {e}")

        search_keyword_list, series_ex, date = self._get_search_keyword(file_path)
        
        # 根据 content_type_hint 决定搜索顺序
        if content_type_hint == "Movie":
            # Movie 优先：先搜索 movies，再搜索 scenes
            search_endpoints = [("movies", "movies"), ("scenes", "scenes")]
        else:
            # Scene 优先（默认）：先搜索 scenes，再搜索 movies
            search_endpoints = [("scenes", "scenes"), ("movies", "movies")]
        
        self.logger.debug(f"搜索顺序: {[ep[0] for ep in search_endpoints]}, content_type_hint: {content_type_hint}")
        
        # 按顺序尝试搜索
        for endpoint_name, path_segment in search_endpoints:
            for search_keyword in search_keyword_list:
                from urllib.parse import quote
                encoded_keyword = quote(search_keyword)
                url_search = f"{self.base_url}/{endpoint_name}?q={encoded_keyword}&per_page=100"
                self.logger.debug(f"搜索 URL: {url_search}")
                
                try:
                    response = self.request.get(url_search, delay_raise=True)
                    
                    if response.status_code == 401:
                        self.logger.error("API Token 无效，请检查配置")
                        raise CredentialError(
                            "ThePornDB API Token 无效",
                            "ThePornDB API Token invalid",
                            self.name
                        )
                    
                    if response.status_code != 200:
                        self.logger.warning(f"搜索请求失败: {response.status_code} - {response.text[:200]}")
                        continue
                    
                    res_search = response.json()
                    real_url = self._get_real_url(res_search, file_path, series_ex, date, path_segment)
                    
                    if real_url:
                        self.logger.info(f"找到匹配: {real_url}")
                        break
                        
                except CredentialError:
                    raise
                except Exception as e:
                    self.logger.error(f"搜索失败: {e}")
                    import traceback
                    self.logger.debug(traceback.format_exc())
                    continue
            
            # 如果找到匹配，跳出外层循环
            if real_url:
                break

        if not real_url:
            self.logger.warning(f"未找到匹配的内容: {code}")
            raise MovieNotFoundError(self.name, code)
        
        # 2. 获取详情
        self.logger.debug(f"获取详情: {real_url}")
        response = self.request.get(real_url, delay_raise=True)
        
        if response.status_code != 200:
            self.logger.error(f"获取详情失败: {response.status_code}")
            raise NetworkError(
                f"获取详情失败: HTTP {response.status_code}",
                f"Failed to fetch details: HTTP {response.status_code}"
            )
        
        res_real = response.json()
        scene_data = res_real.get('data')
        
        if not scene_data:
            self.logger.error("未获取到有效数据")
            raise MovieNotFoundError(self.name, code)
        
        # 3. 解析数据
        result = self._parse_scene_data(scene_data)
        
        self.logger.info(f"刮削成功: {code}")
        return result
    
    def _get_search_keyword(self, file_path: str) -> Tuple[List[str], str, str]:
        """
        从文件路径提取搜索关键词
        
        Args:
            file_path: 文件路径
        
        Returns:
            (关键词列表, 系列名, 日期)
        """
        file_name = os.path.basename(file_path.replace("\\", "/")).replace(",", ".")
        file_name = os.path.splitext(file_name)[0]
        
        # 匹配欧美番号格式：系列.年.月.日
        # 例如: SexArt.11.11.11, Brazzers.22.03.15
        temp_number = re.findall(
            r"(([A-Z0-9-\.]{2,})[-_\. ]{1}2?0?(\d{2}[-\.]\d{2}[-\.]\d{2}))",
            file_path,
            re.I
        )
        
        keyword_list = []
        series_ex = ""
        date = ""
        
        if temp_number:
            full_number, series_ex, date = temp_number[0]
            
            # 转换系列缩写为完整名称
            series_ex = self._convert_studio_name(series_ex.lower().replace("-", "").replace(".", ""))
            
            # 规范化日期格式
            date = "20" + date.replace(".", "-")
            
            # 添加搜索关键词
            keyword_list.append(series_ex + " " + date)  # 系列 + 发行时间
            
            # 提取标题（去掉番号部分）
            temp_title = re.sub(r"[-_&\.]", " ", file_name.replace(full_number, "")).strip()
            temp_title_list = []
            [temp_title_list.append(i) for i in temp_title.split(" ") if i and i != series_ex]
            
            if temp_title_list:
                keyword_list.append(series_ex + " " + " ".join(temp_title_list[:2]))  # 系列 + 标题
        else:
            # 如果无法识别番号格式，使用文件名前两个词
            keyword_list.append(" ".join(file_name.split(".")[:2]).replace("-", " "))
        
        return keyword_list, series_ex, date
    
    def _convert_studio_name(self, short_name: str) -> str:
        """
        将厂商缩写转换为完整名称
        
        Args:
            short_name: 厂商缩写（如 bex, sart）
        
        Returns:
            完整厂商名称（如 BrazzersExxtra, SexArt）
        """
        # 使用 CodeNormalizer 中的映射表
        return CodeNormalizer.WESTERN_STUDIO_MAP.get(short_name, short_name.title())
    
    def _get_real_url(
        self,
        res_search: Dict,
        file_path: str,
        series_ex: str,
        date: str,
        path_segment: str = "scenes",
    ) -> str:
        """
        从搜索结果中找到最佳匹配的 URL
        
        Args:
            res_search: 搜索结果
            file_path: 文件路径
            series_ex: 系列名
            date: 日期
        
        Returns:
            匹配的 scene URL，未找到返回空字符串
        """
        search_data = res_search.get("data")
        if not search_data:
            return ""
        
        file_name = os.path.split(file_path)[1].lower()
        
        # 移除日期后的文件名
        new_file_name = re.findall(r"[\.-_]\d{2}\.\d{2}\.\d{2}(.+)", file_name)
        new_file_name = new_file_name[0] if new_file_name else file_name
        
        # 计算演员数量（通过 & 或 .and. 分隔）
        actor_number = len(new_file_name.replace(".and.", "&").split("&"))
        
        # 规范化文件路径（用于匹配）
        temp_file_path_space = re.sub(r"[\W_]", " ", file_path.lower()).replace("  ", " ")
        temp_file_path_nospace = temp_file_path_space.replace(" ", "")
        
        res_date_list = []
        res_title_list = []
        res_actor_list = []
        
        for each in search_data:
            res_id_url = f"{self.base_url}/{path_segment}/{each['slug']}"
            
            # 提取系列信息
            try:
                res_series = each["site"]["short_name"]
            except Exception:
                res_series = ""
            
            try:
                res_url = each["site"]["url"].replace("-", "")
            except Exception:
                res_url = ""
            
            res_date = each.get("date", "")
            
            # 规范化标题
            res_title_space = re.sub(r"[\W_]", " ", each["title"].lower())
            res_title_nospace = res_title_space.replace(" ", "")
            
            # 提取演员信息
            actor_list_space = []
            actor_list_nospace = []
            for a in each.get("performers", []):
                ac = re.sub(r"[\W_]", " ", a["name"].lower())
                actor_list_space.append(ac)
                actor_list_nospace.append(ac.replace(" ", ""))
            
            res_actor_title_space = (" ".join(actor_list_space) + " " + res_title_space).replace("  ", " ")
            
            # 匹配逻辑
            if series_ex:
                # 有系列时：先判断日期，再判断标题，再判断演员
                if series_ex == res_series or series_ex in res_url:
                    if date and res_date == date:
                        res_date_list.append([res_id_url, res_actor_title_space])
                    elif res_title_nospace in temp_file_path_nospace:
                        res_title_list.append([res_id_url, res_actor_title_space])
                    elif actor_list_nospace and len(actor_list_nospace) >= actor_number:
                        # 检查所有演员是否都在文件名中
                        all_actors_match = True
                        for a in actor_list_nospace:
                            if a not in temp_file_path_nospace:
                                all_actors_match = False
                                break
                        if all_actors_match:
                            res_actor_list.append([res_id_url, res_actor_title_space])
                else:
                    # 系列不同时，当日期和标题同时命中，则视为系列错误
                    if date and res_date == date and res_title_nospace in temp_file_path_nospace:
                        res_title_list.append([res_id_url, res_actor_title_space])
            else:
                # 没有系列时，只添加标题相似度高的结果（避免添加所有结果）
                # 计算标题相似度，只添加相似度 > 0.6 的结果
                title_sim = similarity(res_title_space, temp_file_path_space)
                if title_sim > 0.6:
                    res_title_list.append([res_id_url, res_actor_title_space, title_sim])
        
        # 优先级：日期匹配 > 标题匹配 > 演员匹配
        # 如果有多个结果，选择相似度最高的
        
        if res_date_list:
            if len(res_date_list) == 1:
                return res_date_list[0][0]
            # 多个结果，返回相似度最高的
            max_similarity = 0
            best_url = ""
            for url, text in res_date_list:
                sim = similarity(text, temp_file_path_space)
                if sim > max_similarity:
                    max_similarity = sim
                    best_url = url
            return best_url
        
        if res_title_list:
            if len(res_title_list) == 1:
                return res_title_list[0][0]
            max_similarity = 0
            best_url = ""
            for item in res_title_list:
                # 兼容新旧格式：[url, text, sim] 或 [url, text]
                if len(item) == 3:
                    url, text, sim = item
                else:
                    url, text = item
                    sim = similarity(text, temp_file_path_space)
                
                if sim > max_similarity:
                    max_similarity = sim
                    best_url = url
            return best_url
        
        if res_actor_list:
            if len(res_actor_list) == 1:
                return res_actor_list[0][0]
            max_similarity = 0
            best_url = ""
            for url, text in res_actor_list:
                sim = similarity(text, temp_file_path_space)
                if sim > max_similarity:
                    max_similarity = sim
                    best_url = url
            return best_url
        
        return ""
    
    def _parse_scene_data(self, data: Dict) -> ScrapeResult:
        """
        解析 scene 数据
        
        Args:
            data: ThePornDB API 返回的 scene 数据
        
        Returns:
            ScrapeResult 对象
        """
        result = self._create_result()
        
        try:
            # 标题
            result.title = data.get("title", "")
            result.original_title = result.title
            
            # 媒体类型（Scene/Movie）
            content_type = data.get("type", "")
            if content_type:
                # ThePornDB 返回 "Scene" 或 "Movie"
                result.media_type = content_type
            
            # 简介
            outline = data.get("description", "")
            if outline:
                outline = outline.replace("＜p＞", "").replace("＜/p＞", "")
            result.overview = outline
            
            # 发售日期
            release = data.get("date", "")
            if release:
                result.release_date = release
                # 提取年份
                year_match = re.search(r"(19|20)\d{2}", release)
                if year_match:
                    result.year = int(year_match.group(0))
            
            # 预告片（视频预览）- 灵活处理不同格式
            trailer = data.get("trailer", "")
            if trailer:
                preview_videos = []
                
                if isinstance(trailer, str):
                    # 情况1：单个 URL 字符串
                    # 尝试从 URL 中推断清晰度（如果包含 720p, 1080p 等）
                    quality = 'Unknown'
                    url_lower = trailer.lower()
                    if '4k' in url_lower or '2160p' in url_lower:
                        quality = '4K'
                    elif '1080p' in url_lower:
                        quality = '1080P'
                    elif '720p' in url_lower:
                        quality = '720P'
                    elif '480p' in url_lower:
                        quality = '480P'
                    
                    preview_videos.append({'quality': quality, 'url': trailer})
                    
                elif isinstance(trailer, dict):
                    # 情况2：字典格式，包含多个清晰度
                    # 例如: {'4K': 'url1', '1080P': 'url2', '720P': 'url3'}
                    for quality, url in trailer.items():
                        if url:  # 确保 URL 不为空
                            preview_videos.append({'quality': quality, 'url': url})
                    
                elif isinstance(trailer, list):
                    # 情况3：列表格式
                    for item in trailer:
                        if isinstance(item, dict):
                            # 列表中的每个元素是字典: [{'quality': '1080P', 'url': '...'}, ...]
                            if 'quality' in item and 'url' in item:
                                preview_videos.append(item)
                            elif 'url' in item:
                                # 只有 url，没有 quality
                                preview_videos.append({'quality': 'Unknown', 'url': item['url']})
                        elif isinstance(item, str):
                            # 列表中的每个元素是 URL 字符串
                            preview_videos.append({'quality': 'Unknown', 'url': item})
                
                result.preview_video_urls = preview_videos
                self.logger.debug(f"预览视频: 共 {len(preview_videos)} 个清晰度")
            
            # 封面图和背景图（根据类型区分）
            if content_type == "Movie":
                # 电影：优先使用 image 作为封面，如果没有则使用 posters
                result.poster_url = data.get("image", "")
                if not result.poster_url:
                    # 如果没有 image，尝试从 posters 获取
                    posters = data.get("posters", {})
                    if isinstance(posters, dict):
                        result.poster_url = posters.get("full") or posters.get("large", "")
                    elif isinstance(posters, list) and len(posters) > 0:
                        result.poster_url = posters[0].get("url", "")
                
                self.logger.debug(f"电影封面: image={data.get('image', '')}, poster_url={result.poster_url}")
                
                # 电影背景：添加 background 和 background_back（如果存在）
                backdrop_urls = []
                try:
                    # 添加 background
                    background = data.get("background", {})
                    if isinstance(background, dict) and background:
                        bg_url = background.get("full") or background.get("large", "")
                        if bg_url:
                            backdrop_urls.append(bg_url)
                            self.logger.debug(f"电影背景 background: {bg_url}")
                    
                    # 添加 background_back
                    background_back = data.get("background_back", {})
                    if isinstance(background_back, dict) and background_back:
                        bg_back_url = background_back.get("full") or background_back.get("large", "")
                        if bg_back_url:
                            backdrop_urls.append(bg_back_url)
                            self.logger.debug(f"电影背景 background_back: {bg_back_url}")
                    
                    result.backdrop_url = backdrop_urls
                    self.logger.info(f"电影背景: 共 {len(backdrop_urls)} 张, backdrop_url={backdrop_urls}")
                except Exception as e:
                    self.logger.warning(f"电影背景解析失败: {e}")
                    result.backdrop_url = []
            else:
                # 场景：封面用 image，背景用 background
                result.poster_url = data.get("image", "")
                self.logger.debug(f"场景封面: image={data.get('image', '')}, poster_url={result.poster_url}")
                
                try:
                    background = data.get("background", {})
                    if isinstance(background, dict) and background:
                        bg_url = background.get("full") or background.get("large", "")
                        result.backdrop_url = [bg_url] if bg_url else []
                    else:
                        result.backdrop_url = []
                    self.logger.debug(f"场景背景: backdrop_url={result.backdrop_url}")
                except Exception as e:
                    self.logger.warning(f"场景背景解析失败: {e}")
                    result.backdrop_url = []
            
            # 时长（秒转分钟）
            try:
                duration = int(data.get("duration", 0))
                result.runtime = int(duration / 60)
            except Exception:
                result.runtime = 0
            
            # 系列
            try:
                result.series = data["site"]["name"]
            except Exception:
                result.series = ""
            
            # 制作商
            try:
                result.studio = data["site"]["network"]["name"]
            except Exception:
                result.studio = ""
            
            # 导演
            try:
                result.director = data["director"]["name"]
            except Exception:
                result.director = ""
            
            # 语言（如果 API 返回）
            try:
                result.language = data.get("language", "")
            except Exception:
                result.language = ""
            
            # 国家/地区（如果 API 返回）
            try:
                result.country = data.get("country", "")
            except Exception:
                result.country = ""
            
            # 类型标签
            genres = []
            try:
                for tag in data.get("tags", []):
                    genres.append(tag["name"])
            except Exception:
                pass
            result.genres = genres
            
            # 演员（只包含女性演员）
            actors = []
            all_actors = []
            try:
                for performer in data.get("performers", []):
                    actor_name = performer["name"]
                    all_actors.append(actor_name)
                    
                    # 只添加非男性演员
                    try:
                        gender = performer["parent"]["extras"]["gender"]
                        if gender != "Male":
                            actors.append(actor_name)
                    except Exception:
                        # 如果无法获取性别，默认添加
                        actors.append(actor_name)
            except Exception:
                pass
            
            result.actors = actors
            
            # 番号（系列.日期格式）- 已禁用，不自动生成 code
            # if result.series and result.release_date:
            #     try:
            #         date_match = re.findall(r"\d{2}-\d{2}-\d{2}", result.release_date)
            #         if date_match:
            #             result.code = result.series.replace(" ", "") + "." + date_match[0].replace("-", ".")
            #     except Exception:
            #         result.code = result.title
            # else:
            #     result.code = result.title
            
            self.logger.debug(f"解析成功: 演员={len(actors)}, 类型={len(genres)}")
            
        except Exception as e:
            self.logger.error(f"解析数据失败: {e}", exc_info=True)
        
        return result
    
    def scrape_multiple(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> List[ScrapeResult]:
        """
        刮削多个结果（保底刮削器模式）
        
        ThePornDB 作为保底刮削器，支持多种搜索模式：
        1. 系列+标题：先尝试 slug，失败后用 "系列 + 标题" 搜索
        2. 系列+日期：用 "系列 + 日期" 搜索
        3. 纯标题：用纯标题搜索
        
        Args:
            title: 标题或日期（如 "Scene Title" 或 "26.01.20"）
            content_type_hint: 内容类型提示（Scene/Movie）
            series: 系列名（可选，如 "Brazzers"）
        
        Returns:
            ScrapeResult 列表
        """
        self.logger.info(f"=" * 80)
        self.logger.info(f"ThePornDB scrape_multiple 开始（保底模式）")
        self.logger.info(f"  title: {title}")
        self.logger.info(f"  series: {series}")
        self.logger.info(f"  content_type_hint: {content_type_hint}")
        self.logger.info(f"=" * 80)
        
        if not self.api_token:
            self.logger.error("ThePornDB API token 未配置")
            return []
        
        # 设置请求头
        self.request.headers.update({
            "Authorization": f"Bearer {self.api_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        
        results = []
        
        try:
            # 情况1：有系列名
            if series:
                # 检测 title 是否是日期格式（如 "26.01.20" 或 "2026-01-20"）
                is_date = self._is_date_format(title)
                
                if is_date:
                    # 系列+日期模式
                    self.logger.info(f"检测到日期格式，使用系列+日期搜索")
                    date_str = self._normalize_date(title)
                    search_query = f"{series} {date_str}"
                    self.logger.info(f"搜索查询: {search_query}")
                    results = self._search_scenes(search_query, content_type_hint)
                else:
                    # 系列+标题模式
                    self.logger.info(f"检测到标题格式，先尝试 slug 搜索")
                    
                    # 第一步：尝试 slug 搜索（构造 slug = 系列名-标题）
                    slug_result = self._try_slug_search(title, content_type_hint, series)
                    if slug_result:
                        self.logger.info(f"✓ Slug 搜索成功")
                        results = [slug_result]
                    else:
                        # 第二步：用 "系列 + 标题" 搜索
                        self.logger.info(f"✗ Slug 搜索失败，使用系列+标题搜索")
                        search_query = f"{series} {title}"
                        self.logger.info(f"搜索查询: {search_query}")
                        results = self._search_scenes(search_query, content_type_hint)
            else:
                # 情况2：没有系列名，用纯标题搜索
                self.logger.info(f"没有系列名，使用纯标题搜索")
                self.logger.info(f"搜索查询: {title}")
                results = self._search_scenes(title, content_type_hint)
            
            self.logger.info(f"ThePornDB 返回 {len(results)} 个结果")
            return results
            
        except Exception as e:
            self.logger.error(f"ThePornDB scrape_multiple 失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []
    
    def _is_date_format(self, text: str) -> bool:
        """
        检测文本是否是日期格式
        
        支持格式：
        - 26.01.20
        - 2026-01-20
        - 26-01-20
        
        Args:
            text: 文本
        
        Returns:
            True 如果是日期格式
        """
        # 匹配日期格式：YY.MM.DD 或 YYYY-MM-DD 或 YY-MM-DD
        date_patterns = [
            r'^\d{2}[.\-]\d{2}[.\-]\d{2}$',  # 26.01.20 或 26-01-20
            r'^20\d{2}[.\-]\d{2}[.\-]\d{2}$',  # 2026-01-20
        ]
        
        for pattern in date_patterns:
            if re.match(pattern, text):
                return True
        
        return False
    
    def _normalize_date(self, date_str: str) -> str:
        """
        规范化日期格式为 YYYY-MM-DD
        
        Args:
            date_str: 日期字符串（如 "26.01.20" 或 "2026-01-20"）
        
        Returns:
            规范化的日期字符串（如 "2026-01-20"）
        """
        # 替换点号为连字符
        date_str = date_str.replace('.', '-')
        
        # 如果是 YY-MM-DD 格式，转换为 YYYY-MM-DD
        if re.match(r'^\d{2}-\d{2}-\d{2}$', date_str):
            parts = date_str.split('-')
            year = '20' + parts[0]
            date_str = f"{year}-{parts[1]}-{parts[2]}"
        
        return date_str
    
    def _try_slug_search(self, title: str, content_type_hint: Optional[str] = None, series: Optional[str] = None) -> Optional[ScrapeResult]:
        """
        尝试通过 slug 直接获取详情
        
        Slug 格式：系列名-标题-单词-用连字符连接（全小写）
        例如：vixen-petite-eve-shares-a-cock-with-sexy-assistant-rikako
        
        Args:
            title: 标题字符串（可能包含系列名前缀，如 "BrazzersExxtra-Title"）
            content_type_hint: 内容类型提示（Scene/Movie）
            series: 系列名（可选）
        
        Returns:
            ScrapeResult 对象或 None
        """
        try:
            # 构造 slug
            if series:
                # 有系列名：需要从 title 中移除系列名前缀
                # 1. 规范化系列名（移除空格和特殊字符）
                normalized_series = re.sub(r'[^\w]', '', series).lower()
                
                # 2. 检查 title 是否以系列名开头（忽略大小写和分隔符）
                # 尝试匹配 "系列名-标题" 或 "系列名.标题" 或 "系列名 标题" 格式
                title_lower = title.lower()
                clean_title = title
                
                # 尝试移除系列名前缀（支持多种分隔符）
                for separator in ['-', '.', ' ', '_']:
                    prefix = series.lower() + separator
                    if title_lower.startswith(prefix):
                        clean_title = title[len(prefix):]
                        self.logger.debug(f"从标题中移除系列名前缀: {series}{separator}")
                        break
                
                # 3. 构造 slug：系列名-标题
                slug_text = f"{series} {clean_title}"
                self.logger.debug(f"构造 slug 文本: series={series}, clean_title={clean_title}")
            else:
                # 没有系列名：纯标题
                slug_text = title
            
            # 规范化 slug（转小写，空格换连字符，移除特殊字符）
            normalized_slug = slug_text.lower()
            normalized_slug = re.sub(r'[^\w\s-]', '', normalized_slug)  # 移除特殊字符（保留字母、数字、空格、连字符）
            normalized_slug = re.sub(r'\s+', '-', normalized_slug)  # 空格换连字符
            normalized_slug = re.sub(r'-+', '-', normalized_slug)  # 多个连字符合并为一个
            normalized_slug = normalized_slug.strip('-')  # 移除首尾连字符
            
            self.logger.info(f"构造的 slug: {normalized_slug}")
            
            # 根据 content_type_hint 决定搜索顺序
            if content_type_hint == "Movie":
                endpoints = [("movies", "movies"), ("scenes", "scenes")]
            else:
                endpoints = [("scenes", "scenes"), ("movies", "movies")]
            
            for endpoint_name, _ in endpoints:
                url = f"{self.base_url}/{endpoint_name}/{normalized_slug}"
                self.logger.debug(f"尝试 slug URL: {url}")
                
                response = self.request.get(url, delay_raise=False)
                
                if response.status_code == 200:
                    data = response.json().get("data")
                    if data:
                        self.logger.info(f"✓ Slug 搜索成功: {url}")
                        return self._parse_scene_data(data)
            
            return None
            
        except Exception as e:
            self.logger.debug(f"Slug 搜索失败: {e}")
            return None
    
    def _search_scenes(self, query: str, content_type_hint: Optional[str] = None) -> List[ScrapeResult]:
        """
        搜索场景
        
        Args:
            query: 搜索查询
            content_type_hint: 内容类型提示（Scene/Movie）
        
        Returns:
            ScrapeResult 列表
        """
        results = []
        
        try:
            # 根据 content_type_hint 决定搜索顺序
            if content_type_hint == "Movie":
                endpoints = [("movies", "movies"), ("scenes", "scenes")]
            else:
                endpoints = [("scenes", "scenes"), ("movies", "movies")]
            
            for endpoint_name, path_segment in endpoints:
                from urllib.parse import quote
                encoded_query = quote(query)
                url = f"{self.base_url}/{endpoint_name}?q={encoded_query}&per_page=100"
                
                self.logger.debug(f"搜索 URL: {url}")
                
                response = self.request.get(url, delay_raise=True)
                
                if response.status_code == 401:
                    self.logger.error("API Token 无效")
                    return []
                
                if response.status_code != 200:
                    self.logger.warning(f"搜索失败: {response.status_code}")
                    continue
                
                data = response.json()
                search_results = data.get("data", [])
                
                self.logger.info(f"✓ {endpoint_name} 搜索返回 {len(search_results)} 个结果")
                
                # 直接解析搜索结果（不需要再次获取详情）
                for item in search_results:
                    try:
                        # 搜索结果已经包含了基本信息，直接解析
                        result = self._parse_scene_data(item)
                        results.append(result)
                    except Exception as e:
                        self.logger.warning(f"解析结果失败: {e}")
                        continue
                
                # 如果找到结果，不再尝试其他端点
                if results:
                    break
            
            return results
            
        except Exception as e:
            self.logger.error(f"搜索失败: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return []


if __name__ == '__main__':
    # 测试用例
    import asyncio
    
    config = {
        'theporndb_api_token': 'YOUR_API_TOKEN_HERE',
        'proxy': None
    }
    
    scraper = ThePornDBScraper(config)
    
    # 测试刮削
    test_cases = [
        'sexart.11.11.11',
        'brazzers.22.03.15',
        'vixen.18.07.18',
    ]
    
    for code in test_cases:
        print(f"\n=== 测试: {code} ===")
        result = scraper.scrape(code)
        if result:
            print(f"标题: {result.title}")
            print(f"系列: {result.series}")
            print(f"制作商: {result.studio}")
            print(f"演员: {', '.join(result.actors)}")
            print(f"发售日期: {result.release_date}")
        else:
            print("刮削失败")
