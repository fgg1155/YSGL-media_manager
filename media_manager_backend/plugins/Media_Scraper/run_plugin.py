#!/usr/bin/env python3
"""
Media Scraper Plugin Entry Point
插件入口文件，用于启动插件主程序
"""

import sys
from pathlib import Path

# 添加插件目录到 Python 路径
plugin_dir = Path(__file__).parent
sys.path.insert(0, str(plugin_dir))

# 导入并运行插件主程序
from plugin_main import main

if __name__ == '__main__':
    main()
