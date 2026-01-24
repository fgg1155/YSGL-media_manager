# 多站点磁力刮削插件

## 功能

支持从多个磁力网站刮削磁力链接，具有智能回退机制。

## 支持的网站

1. **Kiteyuan** (优先) - `https://demosearch.kiteyuan.info`
   - 搜索 URL: `/search?q={query}&engine=local_db`
   - 技术：简单 HTTP 请求（reqwest）
   - 特点：快速、无需浏览器、无反爬虫

2. **SkrBT** (回退) - `https://skrbtux.top`
   - 技术：Headless Chrome 浏览器
   - 特点：需要反爬虫绕过、启动较慢但能处理复杂网站

## 工作流程

1. 首先尝试 Kiteyuan 网站（HTTP 请求，速度快）
2. 如果 Kiteyuan 失败或返回 0 结果，自动回退到 SkrBT（浏览器模式）
3. 返回找到的所有磁力链接

## 性能优化

- Kiteyuan 使用纯 HTTP 请求，不启动浏览器，速度快、资源占用少
- 只有在 Kiteyuan 失败时才启动 Chrome 浏览器访问 SkrBT
- 这样可以在大多数情况下获得最佳性能

## 构建

```powershell
# 在 plugins/scraper 目录下
cargo build --release
```

## 测试

```powershell
# 设置环境变量以保存调试 HTML
$env:DEBUG_HTML="1"

# 测试搜索
echo '{"action":"search_magnets","query":"300MIUM-901"}' | .\target\release\scraper.exe
```

## 调试

设置 `DEBUG_HTML=1` 环境变量会保存以下调试文件：
- `debug_demosearch.html` - DemoSearch 搜索结果页面
- `debug_homepage.html` - SkrBT 首页
- `debug_search.html` - SkrBT 搜索结果页面
- `debug_detail.html` - SkrBT 详情页面

## 扩展新网站

要添加新的磁力网站：

1. 在 `main.rs` 中添加新的网站常量
2. 在 `SiteType` 枚举中添加新类型
3. 实现新的 `search_xxx()` 方法
4. 在 `search_magnets()` 中添加回退逻辑

## 注意事项

- DemoSearch 使用简单的 HTTP 请求，速度快
- SkrBT 需要 Headless Chrome，启动较慢但能绕过反爬虫
- 建议优先使用速度快的网站，失败后再使用复杂的网站
