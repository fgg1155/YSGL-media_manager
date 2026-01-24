# 数据处理器模块

本模块包含用于处理刮削数据的各种处理器。

## Genre 处理器 (GenreProcessor)

Genre 处理器用于加载 Genre 映射表并进行翻译和清洗。

### 功能特性

1. **多数据源支持**：支持 JAVBus、JAVDB、JAVLibrary、AVSox 等多个数据源的映射表
2. **多语言映射**：支持日文、中文（简体/繁体）、英文等多种语言的 Genre 映射
3. **自动去重**：自动去除重复的 Genre
4. **智能翻译**：优先使用指定数据源的映射表，如果找不到则尝试其他映射表
5. **空值过滤**：自动过滤掉映射为空的 Genre（表示该 Genre 应被删除）

### 使用方法

#### 1. 基本使用

```python
from processors.genre_processor import GenreProcessor

# 初始化处理器
processor = GenreProcessor()

# 处理 Genre 列表
genres = ['中出し', '巨乳', 'フェラ', '潮吹き']
processed = processor.process_genres(genres, source='javlib')
print(processed)  # ['中出', '巨乳', '口交', '潮吹']
```

#### 2. 指定数据源

```python
# 使用 JAVBus 的映射表
javbus_genres = ['中出し', 'Big Tits', 'フェラ']
processed = processor.process_genres(javbus_genres, source='javbus')

# 使用 JAVDB 的映射表
javdb_genres = ['中出', '巨乳', '口交']
processed = processor.process_genres(javdb_genres, source='javdb')
```

#### 3. 自动检测（不指定数据源）

```python
# 不指定数据源，处理器会尝试所有映射表
mixed_genres = ['中出し', '巨乳', 'Creampie', '口交']
processed = processor.process_genres(mixed_genres)
# 自动去重：['中出', '巨乳', '口交']
```

#### 4. 在刮削管理器中集成

```python
from processors.genre_processor import GenreProcessor

class JAVScraperManager:
    def __init__(self, config):
        self.config = config
        # 初始化 Genre 处理器
        self.genre_processor = GenreProcessor()
    
    def aggregate_results(self, results):
        """聚合多个数据源的结果"""
        # 聚合 Genres
        all_genres = []
        for source, result in results.items():
            if result and result.get('genres'):
                all_genres.extend(result['genres'])
        
        # 使用 Genre 处理器进行翻译和去重
        final_genres = self.genre_processor.process_genres(all_genres)
        
        return {
            'title': self._aggregate_field(results, 'title'),
            'actors': self._aggregate_actors(results),
            'genres': final_genres,  # 处理后的 Genres
            # ... 其他字段 ...
        }
```

### 映射表格式

映射表使用 CSV 格式，位于 `config/` 目录下：

- `genre_javbus.csv` - JAVBus 的 Genre 映射表
- `genre_javdb.csv` - JAVDB 的 Genre 映射表
- `genre_javlib.csv` - JAVLibrary 的 Genre 映射表
- `genre_avsox.csv` - AVSox 的 Genre 映射表

#### CSV 格式说明

不同数据源的 CSV 格式略有不同，但都包含以下关键列：

- `id`: Genre 的唯一标识
- `ja`: 日文名称
- `en`: 英文名称
- `zh_tw` / `zh_cn`: 中文名称（繁体/简体）
- `translate`: 最终的翻译结果（中文）
- `note`: 备注说明

**示例（JAVLib 格式）：**

```csv
id,url,zh_cn,zh_tw,en,ja,translate,note
ky,https://www.b49t.com/cn/vl_genre.php?g=ky,中出,中出,Creampie,中出し,中出,
pq,https://www.b49t.com/cn/vl_genre.php?g=pq,巨乳,巨乳,Big Tits,巨乳,巨乳,
bu,https://www.b49t.com/cn/vl_genre.php?g=bu,口交,口交,Blow,フェラ,口交,
```

### API 参考

#### GenreProcessor

**初始化**

```python
GenreProcessor(config_dir: str = None)
```

- `config_dir`: 配置文件目录路径，默认为 `../config`

**方法**

- `process_genres(genres: List[str], source: str = None) -> List[str]`
  - 处理 Genre 列表，进行翻译和清洗
  - `genres`: 原始 Genre 列表
  - `source`: 数据源名称（可选）
  - 返回：处理后的 Genre 列表

- `get_available_sources() -> List[str]`
  - 获取已加载的数据源列表

- `get_map_size(source: str) -> int`
  - 获取指定数据源的映射表大小

### 测试

运行测试：

```bash
# 基本功能测试
python tests/test_genre_processor.py

# 集成示例测试
python tests/test_genre_integration.py
```

### 注意事项

1. **映射表编码**：CSV 文件必须使用 UTF-8-BOM 编码保存
2. **空值处理**：如果 `translate` 列为空，表示该 Genre 应被删除
3. **去重逻辑**：处理器会自动去除重复的 Genre
4. **多语言支持**：处理器会将所有语言版本都作为键添加到映射表中，以支持多语言输入

### 扩展

如果需要添加新的数据源映射表：

1. 在 `config/` 目录下创建新的 CSV 文件（如 `genre_newsource.csv`）
2. 按照上述格式填写映射关系
3. 在 `GenreProcessor._load_all_maps()` 方法中添加新的映射表配置

```python
map_files = {
    'javbus': 'genre_javbus.csv',
    'javdb': 'genre_javdb.csv',
    'javlib': 'genre_javlib.csv',
    'avsox': 'genre_avsox.csv',
    'newsource': 'genre_newsource.csv',  # 新增
}
```
