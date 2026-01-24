# Media Scraper 插件

通用媒体元数据刮削插件，支持日本AV（JAV）和欧美内容的元数据获取。

## 🎯 功能特性

- ✅ 支持多数据源并发刮削（Fanza、JavBus、JAVLibrary、JAVDB、AVSOX）
- ✅ 智能番号规范化（DVD ID ↔ CID）
- ✅ 支持新老番号格式
- ✅ 自动内容类型检测（JAV vs 欧美）
- ✅ 支持无码内容刮削（一本道、加勒比、东京热等）
- ✅ 演员信息刮削（元数据 + 照片）
- ✅ 与主项目完全集成
- ✅ **插件UI系统** - 通过配置文件动态添加UI元素

## 📦 支持的番号格式

### 普通番号
- `IPX-177`, `SSIS-001` (DVD ID)
- `ipx00177`, `ssis00001` (CID)

### 老番号
- `83sma132`, `oned00001` (老番号 CID)
- `SMA-132`, `ONED-001` (老番号 DVD ID)

### 特殊番号
- `FC2-PPV-1234567` (FC2)
- `HEYZO-1234` (HEYZO)
- `HEYDOUGA-4030-1234` (HEYDOUGA)
- `RED-123`, `SKY-234` (东热)

### 无码番号
- `082713-417` (一本道)
- `032620_001` (加勒比)
- `n1234` (东京热)
- `010120_01` (10musume)

## 🚀 快速开始

### 1. 安装依赖

```bash
pip install -r requirements.txt
```

### 2. 测试插件

```bash
# 测试插件通信
python tests/test_plugin_integration.py

# 测试番号格式
python tests/test_quick_integration.py

# 最终验证
python tests/test_final_verification.py
```

### 3. 启动后端

```bash
cd ../../..  # 回到 media_manager_backend 目录
cargo run
```

### 4. 验证集成

```bash
# 检查插件是否加载
curl http://localhost:3000/api/scrape/plugins

# 测试刮削
curl http://localhost:3000/api/scrape/IPX-177
```

## 🔧 配置

### 插件配置 (plugin.json)

```json
{
  "id": "media_scraper",
  "name": "媒体刮削器",
  "version": "1.0.0",
  "executable": "run_plugin.bat",
  "enabled": true
}
```

### UI配置 (config/ui_manifest.yaml)

插件UI系统允许通过配置文件动态添加UI元素到应用中，无需修改应用源代码。

**配置文件位置**: `config/ui_manifest.yaml`

**支持的UI元素**:
- 按钮 (Buttons) - 在预定义的注入点添加可点击按钮
- 对话框 (Dialogs) - 包含表单字段的弹窗
- 动作 (Actions) - 按钮点击或对话框提交时执行的操作

**注入点**:
- `media_detail_appbar` - 媒体详情页顶部操作栏
- `actor_detail_appbar` - 演员详情页顶部操作栏
- `actor_list_appbar` - 演员列表页顶部操作栏

**示例配置**:

```yaml
plugin:
  id: "media_scraper"
  name: "Media Scraper"
  version: "1.0.0"

ui_elements:
  buttons:
    - id: "scrape_media_button"
      injection_point: "media_detail_appbar"
      icon: "download_outlined"
      tooltip:
        zh: "刮削媒体信息"
        en: "Scrape Media Info"
      action:
        type: "show_dialog"
        dialog_id: "scrape_media_dialog"

  dialogs:
    - id: "scrape_media_dialog"
      title:
        zh: "刮削媒体信息"
        en: "Scrape Media Info"
      fields:
        - id: "scrape_method"
          type: "radio"
          label:
            zh: "刮削方式"
            en: "Scrape Method"
          options:
            - value: "code"
              label:
                zh: "按番号"
                en: "By Code"
      actions:
        - id: "scrape_action"
          label:
            zh: "开始刮削"
            en: "Start"
          type: "call_api"
          api_endpoint: "/api/scrape/apply/{media_id}/{code}"
          method: "POST"

permissions:
  injection_points:
    - "media_detail_appbar"
  api_access:
    - "/api/scrape/*"
  data_access:
    - "media_id"
    - "code"
```

**详细文档**:
- [UI插件开发指南](../../../docs/guides/UI_PLUGIN_GUIDE.md)
- [UI配置参考文档](../../../docs/guides/UI_CONFIG_REFERENCE.md)

### 环境变量

```bash
# .env 文件（可选）
PLUGINS_DIR=./plugins
```

## 📖 使用方式

### 方式 1: 详情页刮削

在媒体详情页面手动刮削元数据。

```typescript
// 使用媒体自身的番号
POST /api/scrape/apply/:media_id

// 指定番号刮削
POST /api/scrape/apply/:media_id/:code
```

### 方式 2: 扫描文件刮削

在设置页面扫描本地文件并批量刮削。

```typescript
POST /api/scan/auto-scrape
{
  "unmatched_files": [
    {
      "file_path": "/path/to/IPX-177.mp4",
      "file_name": "IPX-177.mp4",
      "file_size": 1234567890,
      "parsed_code": "IPX-177"
    }
  ]
}
```

### 方式 3: 演员信息刮削

刮削演员元数据和照片（独立功能）。

```typescript
// 刮削单个演员
POST /api/actors/:actor_id/scrape

// 批量刮削演员
POST /api/actors/batch-scrape
{
  "actor_ids": ["actor_id_1", "actor_id_2"]
}
```

**演员刮削数据源：**
- **元数据**: XSlist（biography, birth_date, nationality, height, measurements）
- **照片**: Gfriends（avatar_url, poster_url, photo_urls）

## 📊 数据源说明

### JAV 内容数据源

插件会根据番号类型自动选择合适的数据源：

**有码内容（普通番号）**：
- **Fanza** - 官方数据，质量最高（优先级1）
- **JAVLibrary** - 评分、演员信息完整（优先级2）
- **JavBus** - 预览图丰富（优先级3）
- **JAVDB** - 备用数据源（优先级4）

**无码内容（一本道、加勒比等）**：
- **AVSOX** - 无码影片专用数据库（优先级1）
- **JAVDB** - 备用数据源（优先级2）

**FC2 内容**：
- **JAVDB** - FC2 内容主要来源（优先级1）
- **AVSOX** - 备用数据源（优先级2）

**数据合并策略**：
- 采用补充式合并：优先使用高优先级数据源的数据
- 只有当高优先级数据源字段为空时，才使用低优先级数据源补充
- 封面图片优先使用非 JAVDB 来源（避免水印）
- Genre 标签会收集所有来源并统一翻译去重

## 📊 数据模型

### 刮削结果 (ScrapeResult)

```python
{
  "code": "IPX-177",
  "title": "...",
  "actors": ["..."],
  "genres": ["..."],
  "poster_url": "...",
  "backdrop_url": "...",
  "preview_urls": ["..."],
  "preview_video_urls": ["..."],  # List<String>
  "release_date": "2018-07-14",
  "year": 2018,
  "studio": "...",
  "series": "...",
  "rating": 8.8,
  "runtime": 170,
  "overview": "...",
  "source": "javlibrary+fanza"
}
```

### 演员刮削结果 (ActorScrapeResult)

```python
{
  "name": "天海つばさ",
  "biography": "...",
  "birth_date": "1988-03-08",
  "nationality": "日本",
  "height": "163cm",
  "measurements": "B88-W58-H86",
  "cup_size": "E",
  "avatar_url": "https://raw.githubusercontent.com/gfriends/gfriends/master/Content/...",
  "poster_url": "https://raw.githubusercontent.com/gfriends/gfriends/master/Content/...",
  "photo_urls": ["https://..."],
  "backdrop_url": null
}
```

## 🧪 测试结果

### 有码内容
```
✅ IPX-177      (新番号 DVD ID)  - 来源: javlibrary+fanza, 12张预览图, 2个视频
✅ ipx00177     (新番号 CID)     - 来源: javlibrary
✅ SSIS-001     (新番号 DVD ID)  - 来源: javlibrary+javbus, 10张预览图
✅ ssis00001    (新番号 CID)     - 来源: javlibrary+javbus, 10张预览图
✅ 83sma132     (老番号 CID)     - 来源: javlibrary
✅ SMA-132      (老番号 DVD ID)  - 来源: javlibrary
```

### 无码内容
```
✅ 082713-417   (一本道)         - 来源: avsox, 无码标记
✅ 032620_001   (加勒比)         - 来源: avsox, 无码标记
✅ FC2-1234567  (FC2)           - 来源: javdb+avsox
```

## 📚 文档

- [PLUGIN_INTEGRATION.md](docs/PLUGIN_INTEGRATION.md) - 插件集成文档
- [BACKEND_INTEGRATION.md](docs/BACKEND_INTEGRATION.md) - 后端集成配置
- [UI插件开发指南](../../../docs/guides/UI_PLUGIN_GUIDE.md) - UI系统开发指南
- [UI配置参考文档](../../../docs/guides/UI_CONFIG_REFERENCE.md) - UI配置完整参考
- [../../PLUGIN_CONFIGURATION_CHECKLIST.md](../../PLUGIN_CONFIGURATION_CHECKLIST.md) - 配置检查清单

## 🔍 故障排查

### 插件未加载

```bash
# 检查插件目录
ls media_manager_backend/plugins/media_scraper/

# 检查配置文件
cat media_manager_backend/plugins/media_scraper/plugin.json

# 查看后端日志
```

### 刮削失败

```bash
# 查看插件日志
cat media_manager_backend/plugins/media_scraper/media_scraper.log

# 独立测试插件
cd media_manager_backend/plugins/media_scraper
echo {"action":"get","id":"IPX-177"} | run_plugin.bat
```

### 老番号无法识别

```bash
# 测试规范化器
python media_manager_backend/plugins/media_scraper/core/code_normalizer.py
```

## 📝 更新日志

### v1.0.1 (2024-01-12)

**UI系统**:
- ✅ 添加插件UI配置系统
- ✅ 支持动态UI元素注入
- ✅ 支持多语言UI文本
- ✅ 支持权限系统
- ✅ 完整的开发文档

### v1.0.0 (2024-01-09)

**核心功能**:
- ✅ 多数据源并发刮削
- ✅ 智能番号规范化
- ✅ 内容类型自动检测

**Fanza 刮削器增强**:
- ✅ 修正图片 URL 映射
- ✅ 预览图 null 值处理
- ✅ 视频预览字段改为 List
- ✅ 视频预览回退机制

**番号规范化器更新**:
- ✅ 支持老番号格式
- ✅ 老番号 CID 不补零

**后端集成**:
- ✅ 详情页刮削
- ✅ 扫描文件刮削
- ✅ 自动插件选择

## 👥 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License
