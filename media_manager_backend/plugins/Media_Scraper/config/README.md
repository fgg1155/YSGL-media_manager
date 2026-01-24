# 配置文件说明

本目录包含所有配置和数据映射文件。

## 配置文件

### config.yml
主配置文件，包含所有插件设置。

**配置项**：

#### 网络配置 (network)
- `proxy_server`: 代理服务器地址（可选）
- `timeout`: 请求超时时间（秒）
- `retry`: 重试次数
- `proxy_free`: 免代理镜像站点配置
  - `javlibrary`: JAVLibrary 镜像站点
  - `javdb`: JAVDB 镜像站点列表
  - `javbus`: JAVBus 镜像站点列表

#### 刮削器配置 (scraper)
- `required_fields`: 必填字段列表
- `use_javdb_cover`: 是否使用 JAVDB 封面（yes/no/fallback）
- `normalize_actor_names`: 是否规范化演员名称

#### 演员配置 (actor)
- `normalize_actor_names`: 是否规范化演员名称
- `actor_alias_file`: 演员别名映射文件路径
- `filter_male_actors`: 是否过滤男演员
- `male_actors_file`: 男演员列表文件路径

#### 数据清洗配置 (data_cleaning)
- `enabled`: 是否启用数据清洗
- `genre_map_file`: Genre 映射文件路径
- `remove_actors_from_title`: 是否移除标题中的演员名
- `max_overview_length`: 简介最大长度

#### 缓存配置 (cache)
- `enabled`: 是否启用缓存
- `cache_dir`: 缓存目录
- `ttl_days`: 缓存过期时间（天）

#### 日志配置 (logging)
- `level`: 日志级别（DEBUG/INFO/WARNING/ERROR）
- `log_file`: 日志文件路径
- `format`: 日志格式

---

## 数据映射文件

### actor_alias.json
演员别名映射表。

**格式**：
```json
{
  "标准名称": ["别名1", "别名2", "别名3"]
}
```

**用途**：
- 统一不同数据源的演员名称
- 处理演员改名情况
- 支持中文名和日文名映射

**示例**：
```json
{
  "桥本有菜": ["橋本ありな", "Hashimoto Arina"],
  "三上悠亚": ["三上悠亜", "鬼頭桃菜", "Mikami Yua"]
}
```

---

### male_actors.json
男演员列表。

**格式**：
```json
[
  "男演员1",
  "男演员2",
  "男演员3"
]
```

**用途**：
- 过滤男演员（如果配置启用）
- 只保留女演员信息

**示例**：
```json
[
  "沢井亮",
  "森林原人",
  "イセドン内村"
]
```

---

### genre_map.csv
类型/标签映射表。

**格式**：
```csv
原始类型,翻译类型,是否保留
```

**用途**：
- 翻译日文类型为中文
- 过滤不需要的类型
- 统一不同数据源的类型名称

**示例**：
```csv
巨乳,大胸,true
美少女,美少女,true
企画,企划,true
単体作品,单体作品,false
```

**字段说明**：
- `原始类型`: 从数据源获取的原始类型名称
- `翻译类型`: 翻译后的类型名称
- `是否保留`: true 保留该类型，false 过滤掉

---

## 配置文件位置

所有配置文件都位于 `config/` 目录：

```
config/
├── config.yml           # 主配置文件
├── actor_alias.json     # 演员别名映射
├── male_actors.json     # 男演员列表
├── genre_map.csv        # 类型映射
└── README.md            # 本文件
```

---

## 使用说明

### 1. 修改主配置

编辑 `config.yml` 来调整插件行为：

```bash
# 使用文本编辑器打开
notepad config/config.yml  # Windows
nano config/config.yml     # Linux/Mac
```

### 2. 更新演员别名

编辑 `actor_alias.json` 来添加新的演员别名：

```json
{
  "新演员": ["别名1", "别名2"]
}
```

### 3. 更新类型映射

编辑 `genre_map.csv` 来添加新的类型映射：

```csv
新类型,翻译,true
```

### 4. 配置代理

如果需要使用代理访问某些网站：

```yaml
network:
  proxy_server: "http://127.0.0.1:7890"
```

### 5. 使用免代理镜像

如果不想使用代理，可以配置免代理镜像站点：

```yaml
network:
  proxy_free:
    javdb:
      - "https://javdb561.com"
      - "https://javdb562.com"
```

---

## 注意事项

1. **配置文件格式**：
   - YAML 文件对缩进敏感，使用空格而非 Tab
   - JSON 文件必须是有效的 JSON 格式
   - CSV 文件使用逗号分隔

2. **文件编码**：
   - 所有配置文件应使用 UTF-8 编码
   - 避免使用 BOM

3. **路径配置**：
   - 相对路径是相对于插件根目录
   - 可以使用绝对路径

4. **配置生效**：
   - 修改配置后需要重启插件
   - 某些配置可能需要清除缓存

---

## 默认配置

如果配置文件不存在或格式错误，插件会使用默认配置：

- 不使用代理
- 超时 30 秒
- 重试 3 次
- 启用缓存（7天过期）
- 日志级别 INFO
- 不过滤男演员
- 不清洗数据

---

## 故障排除

### 配置文件加载失败

**症状**：插件启动时报错 "Failed to load config"

**解决方法**：
1. 检查 YAML 语法是否正确
2. 检查文件编码是否为 UTF-8
3. 检查文件路径是否正确

### 演员别名不生效

**症状**：演员名称没有被规范化

**解决方法**：
1. 检查 `actor_alias.json` 格式是否正确
2. 确认配置中 `normalize_actor_names: true`
3. 清除缓存后重试

### 类型映射不生效

**症状**：类型没有被翻译或过滤

**解决方法**：
1. 检查 `genre_map.csv` 格式是否正确
2. 确认配置中 `data_cleaning.enabled: true`
3. 检查 CSV 文件编码是否为 UTF-8

---

## 示例配置

完整的配置示例请参考 `config.yml` 文件。
