"""
核心数据模型
包含所有刮削器共用的数据结构
"""

from dataclasses import dataclass, field
from typing import Dict, Any, Optional, List


@dataclass
class ScrapeResult:
    """
    刮削结果数据模型（支持 JAV 和 Western 内容）
    
    通用字段：
        code: 识别码/番号
        title: 标题
        original_title: 原始标题
        release_date: 发售日期 (YYYY-MM-DD)
        year: 年份
        studio: 厂商/制作商
        series: 系列
        actors: 演员列表
        genres: 类型/标签列表
        poster_url: 封面图 URL
        backdrop_url: 背景图 URL
        preview_urls: 预览图 URL 列表
        overview: 简介
        rating: 评分
        runtime: 时长（分钟）
        director: 导演
        language: 语言
        country: 国家/地区
        source: 数据来源（用于调试）
    
    视频字段：
        preview_video_urls: 预览视频列表（统一格式）
            格式: [{'quality': '4K', 'url': 'https://...'}, {'quality': '1080P', 'url': '...'}]
            如果没有清晰度信息，使用 'Unknown' 作为 quality 值
        cover_video_url: 封面视频 URL（短小的视频缩略图，用于悬停播放）
    
    JAV 专用字段：
        mosaic: 马赛克类型（有码/无码）
    
    Western 专用字段：
        media_type: 媒体类型（Scene/Movie/Compilation）
        scenes: Movie 的场景列表
    """
    
    # 通用字段
    code: Optional[str] = None
    title: str = ""
    original_title: Optional[str] = None
    release_date: Optional[str] = None
    year: Optional[int] = None
    studio: Optional[str] = None
    series: Optional[str] = None
    actors: list = field(default_factory=list)
    genres: list = field(default_factory=list)
    poster_url: Optional[str] = None
    backdrop_url: list = field(default_factory=list)  # 支持多个背景图
    preview_urls: list = field(default_factory=list)
    overview: Optional[str] = None
    rating: Optional[float] = None
    runtime: Optional[int] = None
    director: Optional[str] = None
    language: Optional[str] = None
    country: Optional[str] = None
    source: Optional[str] = None
    
    # 视频相关字段（统一格式）
    preview_video_urls: list = field(default_factory=list)
    # 统一格式: [{'quality': '4K', 'url': '...'}, {'quality': '1080P', 'url': '...'}]
    # 如果没有清晰度信息，使用 'Unknown' 作为 quality 值
    
    cover_video_url: Optional[str] = None  # 封面视频（悬停播放用）
    
    # JAV 专用字段
    mosaic: Optional[str] = None  # 马赛克类型（有码/无码）
    
    # Western 专用字段
    media_type: Optional[str] = None  # 媒体类型（Scene/Movie/Compilation）
    scenes: Optional[List[Dict[str, Any]]] = None  # Movie 的场景列表
    
    def to_dict(self) -> Dict[str, Any]:
        """
        转换为字典（用于 JSON 序列化）
        
        验证 preview_video_urls 格式：
        - 必须是字典列表格式: [{'quality': str, 'url': str}, ...]
        - 如果格式不正确，抛出 ValueError
        
        Returns:
            Dict[str, Any]: 序列化后的字典
        
        Raises:
            ValueError: 如果 preview_video_urls 格式不正确
        """
        from datetime import datetime
        
        # 验证 preview_video_urls 格式
        if self.preview_video_urls:
            if not all(
                isinstance(item, dict) and 
                'quality' in item and 
                'url' in item and
                isinstance(item['quality'], str) and
                isinstance(item['url'], str)
                for item in self.preview_video_urls
            ):
                raise ValueError(
                    f"preview_video_urls 格式错误。"
                    f"期望: [{{'quality': str, 'url': str}}, ...]，"
                    f"实际: {self.preview_video_urls}"
                )
        
        # 处理 release_date：如果是 datetime 对象，转换为字符串
        release_date_str = self.release_date
        if isinstance(self.release_date, datetime):
            release_date_str = self.release_date.strftime('%Y-%m-%d')
        
        result = {
            'code': self.code,
            'title': self.title,
            'original_title': self.original_title,
            'release_date': release_date_str,  # 使用转换后的字符串
            'year': self.year,
            'studio': self.studio,
            'series': self.series,
            'actors': self.actors,
            'genres': self.genres,
            'poster_url': self.poster_url,
            'backdrop_url': self.backdrop_url,
            'preview_urls': self.preview_urls,
            'preview_video_urls': self.preview_video_urls,  # 保持字典列表格式
            'cover_video_url': self.cover_video_url,
            'overview': self.overview,
            'rating': self.rating,
            'runtime': self.runtime,
            'director': self.director,
            'language': self.language,
            'country': self.country,
            'mosaic': self.mosaic,
            'media_type': self.media_type,
            'source': self.source
        }
        
        # 只在有 scenes 数据时才添加
        if self.scenes is not None:
            result['scenes'] = self.scenes
        
        return result
