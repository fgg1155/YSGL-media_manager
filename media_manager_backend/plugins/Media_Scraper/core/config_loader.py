"""
配置加载器
从 config.yml 加载插件配置
"""

import yaml
from pathlib import Path
from typing import Dict, Any


def load_config(config_file: str = "config/config.yml") -> Dict[str, Any]:
    """
    加载配置文件
    
    Args:
        config_file: 配置文件路径（相对于插件根目录）
    
    Returns:
        配置字典
    """
    # 获取插件根目录（core 的父目录）
    plugin_root = Path(__file__).parent.parent
    config_path = plugin_root / config_file
    
    # 加载 YAML 配置
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
        
        # 展平 api_tokens 到顶层（方便访问）
        if 'api_tokens' in config:
            for key, value in config['api_tokens'].items():
                config[key] = value
        
        return config or {}
    except FileNotFoundError:
        # 返回默认配置
        return _get_default_config()
    except Exception as e:
        raise RuntimeError(f"配置文件加载失败: {e}")


def _get_default_config() -> Dict[str, Any]:
    """返回默认配置"""
    return {
        'network': {
            'proxy_server': None,
            'timeout': 30,
            'retry': 3
        },
        'scraper': {
            'required_fields': ['title', 'release_date', 'actors', 'poster_url'],
            'use_javdb_cover': 'fallback',
            'normalize_actor_names': True
        },
        'actor': {
            'normalize_actor_names': True,
            'actor_alias_file': 'config/actress_alias.json',
            'filter_male_actors': True,
            'male_actors_file': 'config/male_actors.json'
        },
        'data_cleaning': {
            'enabled': True,
            'genre_map_file': 'data/genre_map.csv',
            'remove_actors_from_title': True,
            'max_overview_length': 1000
        },
        'cache': {
            'enabled': True,
            'cache_dir': 'cache',
            'ttl_days': 7
        },
        'logging': {
            'level': 'INFO',
            'log_file': 'media_scraper.log',
            'format': '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        }
    }
