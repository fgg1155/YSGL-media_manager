"""
Genre 处理器

负责加载 Genre 映射表并进行翻译和清洗

**注意**: 此处理器仅用于 JAV（日本 AV）内容的 Genre 处理。
Western（欧美）内容的 Genre 通常是英文的，不需要映射翻译。
"""

import csv
import os
from typing import List, Dict, Optional
import logging


class GenreProcessor:
    """
    Genre 处理器，用于加载映射表并进行 Genre 翻译
    
    **适用范围**: 仅用于 JAV（日本 AV）内容
    
    JAV 内容的 Genre 通常是日文、中文或英文，需要统一翻译为中文。
    Western（欧美）内容的 Genre 通常已经是英文，不需要此处理器。
    
    **新增功能**:
    - 大小写不敏感匹配
    - 全角半角字符自动转换
    """
    
    # 全角半角字符映射表
    FULL_TO_HALF = {
        # 大写字母
        'Ａ': 'A', 'Ｂ': 'B', 'Ｃ': 'C', 'Ｄ': 'D', 'Ｅ': 'E', 'Ｆ': 'F', 'Ｇ': 'G', 'Ｈ': 'H',
        'Ｉ': 'I', 'Ｊ': 'J', 'Ｋ': 'K', 'Ｌ': 'L', 'Ｍ': 'M', 'Ｎ': 'N', 'Ｏ': 'O', 'Ｐ': 'P',
        'Ｑ': 'Q', 'Ｒ': 'R', 'Ｓ': 'S', 'Ｔ': 'T', 'Ｕ': 'U', 'Ｖ': 'V', 'Ｗ': 'W', 'Ｘ': 'X',
        'Ｙ': 'Y', 'Ｚ': 'Z',
        # 小写字母
        'ａ': 'a', 'ｂ': 'b', 'ｃ': 'c', 'ｄ': 'd', 'ｅ': 'e', 'ｆ': 'f', 'ｇ': 'g', 'ｈ': 'h',
        'ｉ': 'i', 'ｊ': 'j', 'ｋ': 'k', 'ｌ': 'l', 'ｍ': 'm', 'ｎ': 'n', 'ｏ': 'o', 'ｐ': 'p',
        'ｑ': 'q', 'ｒ': 'r', 'ｓ': 's', 'ｔ': 't', 'ｕ': 'u', 'ｖ': 'v', 'ｗ': 'w', 'ｘ': 'x',
        'ｙ': 'y', 'ｚ': 'z',
        # 数字
        '０': '0', '１': '1', '２': '2', '３': '3', '４': '4', '５': '5', '６': '6', '７': '7',
        '８': '8', '９': '9',
        # 常用符号
        '　': ' ',  # 全角空格
        '！': '!', '＂': '"', '＃': '#', '＄': '$', '％': '%', '＆': '&', '＇': "'",
        '（': '(', '）': ')', '＊': '*', '＋': '+', '，': ',', '－': '-', '．': '.',
        '／': '/', '：': ':', '；': ';', '＜': '<', '＝': '=', '＞': '>', '？': '?',
        '＠': '@', '［': '[', '＼': '\\', '］': ']', '＾': '^', '＿': '_', '｀': '`',
        '｛': '{', '｜': '|', '｝': '}', '～': '~',
        # 日文特殊符号
        '・': '·',  # 日文中点
        '｡': '。',  # 日文句号
        '｢': '「',  # 日文左引号
        '｣': '」',  # 日文右引号
    }
    
    def __init__(self, config_dir: str = None):
        """
        初始化 Genre 处理器
        
        Args:
            config_dir: 配置文件目录路径，默认为当前目录下的 config
        """
        self.logger = logging.getLogger(__name__)
        
        # 确定配置目录
        if config_dir is None:
            # 默认使用当前文件所在目录的上级目录下的 config
            current_dir = os.path.dirname(os.path.abspath(__file__))
            config_dir = os.path.join(os.path.dirname(current_dir), 'config')
        
        self.config_dir = config_dir
        
        # 存储各个数据源的映射表
        self.genre_maps: Dict[str, Dict[str, str]] = {}
        
        # 存储规范化后的键到原始键的映射（用于大小写不敏感和全角半角转换）
        self.normalized_keys: Dict[str, Dict[str, str]] = {}
        
        # 加载所有映射表
        self._load_all_maps()
    
    def _load_all_maps(self):
        """加载所有 Genre 映射表"""
        # 定义映射表文件
        map_files = {
            'javbus': 'genre_javbus.csv',
            'javdb': 'genre_javdb.csv',
            'javlib': 'genre_javlib.csv',
            'avsox': 'genre_avsox.csv'
        }
        
        for source, filename in map_files.items():
            filepath = os.path.join(self.config_dir, filename)
            if os.path.exists(filepath):
                try:
                    self.genre_maps[source] = self._load_map(filepath)
                    self.logger.info(f"已加载 {source} 的 Genre 映射表，共 {len(self.genre_maps[source])} 条")
                except Exception as e:
                    self.logger.error(f"加载 {source} 映射表失败: {e}")
            else:
                self.logger.warning(f"映射表文件不存在: {filepath}")
    
    @staticmethod
    def _normalize_text(text: str) -> str:
        """
        规范化文本：全角转半角 + 转小写
        
        Args:
            text: 原始文本
            
        Returns:
            规范化后的文本
        """
        # 全角转半角
        for full, half in GenreProcessor.FULL_TO_HALF.items():
            text = text.replace(full, half)
        
        # 转小写（用于大小写不敏感匹配）
        text = text.lower()
        
        return text
    
    def _load_map(self, filepath: str) -> Dict[str, str]:
        """
        加载单个映射表文件
        
        Args:
            filepath: CSV 文件路径
            
        Returns:
            映射字典 {规范化后的键: 译文}
        """
        genre_map = {}
        source_name = os.path.basename(filepath).replace('genre_', '').replace('.csv', '')
        
        # 初始化该数据源的规范化键映射
        if source_name not in self.normalized_keys:
            self.normalized_keys[source_name] = {}
        
        try:
            with open(filepath, 'r', encoding='utf-8-sig', newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                
                for row in reader:
                    # 根据不同的 CSV 格式处理
                    # JAVBus 格式: id, url, zh_tw, ja, en, translate, note
                    # JAVLib 格式: id, url, zh_cn, zh_tw, en, ja, translate, note
                    # JAVDB 格式: id, url, zh_tw, en, translate, note
                    
                    # 获取译文
                    translate = row.get('translate', '').strip()
                    
                    # 如果译文为空，跳过
                    if not translate:
                        continue
                    
                    # 收集所有可能的原文
                    originals = []
                    if 'ja' in row and row['ja']:
                        originals.append(row['ja'].strip())
                    if 'en' in row and row['en']:
                        originals.append(row['en'].strip())
                    if 'zh_tw' in row and row['zh_tw']:
                        originals.append(row['zh_tw'].strip())
                    if 'zh_cn' in row and row['zh_cn']:
                        originals.append(row['zh_cn'].strip())
                    
                    # 为每个原文创建规范化映射
                    for original in originals:
                        if original:
                            # 规范化键（全角转半角 + 小写）
                            normalized_key = self._normalize_text(original)
                            
                            # 存储映射：规范化键 -> 译文
                            genre_map[normalized_key] = translate
                            
                            # 存储规范化键到原始键的映射（用于调试）
                            if normalized_key not in self.normalized_keys[source_name]:
                                self.normalized_keys[source_name][normalized_key] = []
                            self.normalized_keys[source_name][normalized_key].append(original)
                    
        except UnicodeDecodeError:
            self.logger.error(f'CSV 文件必须以 UTF-8-BOM 编码保存: {filepath}')
            raise
        except KeyError as e:
            self.logger.error(f"CSV 文件缺少必要的列: {e}")
            raise
        except Exception as e:
            self.logger.error(f"加载映射表时出错: {e}")
            raise
        
        return genre_map
    
    def process_genres(self, genres: List[str], source: str = None) -> List[str]:
        """
        处理 Genre 列表，进行翻译和清洗
        
        Args:
            genres: 原始 Genre 列表
            source: 数据源名称（javbus, javdb, javlib, avsox），如果为 None 则尝试所有映射表
            
        Returns:
            处理后的 Genre 列表
        """
        if not genres:
            return []
        
        processed = []
        
        for genre in genres:
            genre = genre.strip()
            if not genre:
                continue
            
            # 尝试映射
            translated = self._translate_genre(genre, source)
            
            # 如果译文不为空，则添加（译文为空表示该 genre 应被删除）
            if translated:
                # 去重
                if translated not in processed:
                    processed.append(translated)
        
        return processed
    
    def _translate_genre(self, genre: str, source: str = None) -> Optional[str]:
        """
        翻译单个 Genre（支持大小写不敏感和全角半角转换）
        
        Args:
            genre: 原始 Genre
            source: 数据源名称
            
        Returns:
            翻译后的 Genre，如果不需要翻译则返回原文，如果应删除则返回 None
        """
        # 规范化输入（全角转半角 + 小写）
        normalized_genre = self._normalize_text(genre)
        
        # 如果指定了数据源，优先使用该数据源的映射表
        if source and source in self.genre_maps:
            if normalized_genre in self.genre_maps[source]:
                return self.genre_maps[source][normalized_genre]
        
        # 尝试所有映射表
        for map_name, genre_map in self.genre_maps.items():
            if normalized_genre in genre_map:
                return genre_map[normalized_genre]
        
        # 如果没有找到映射，返回原文
        return genre
    
    def get_available_sources(self) -> List[str]:
        """获取已加载的数据源列表"""
        return list(self.genre_maps.keys())
    
    def get_map_size(self, source: str) -> int:
        """获取指定数据源的映射表大小"""
        if source in self.genre_maps:
            return len(self.genre_maps[source])
        return 0
