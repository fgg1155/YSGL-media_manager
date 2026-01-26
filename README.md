# Media Manager

一个跨平台的媒体管理应用，使用 Flutter 和 Rust 构建。支持独立模式和 PC 模式，可通过油猴脚本从网站导入媒体信息。

## 🌟 核心特性

- **🔄 双模式运行**
  - **独立模式**：移动端完全独立运行，无需 PC 后端
  - **PC 模式**：连接 Rust 后端，获得完整功能和插件支持

- **📱 跨平台支持**
  - Android、iOS、Windows、macOS、Linux
  - 统一的用户体验

- **🔌 油猴脚本集成**
  - 从网站一键导入媒体信息
  - 支持多个网站配置
  - 自动提取元数据、演员、下载链接等

- **💾 智能数据管理**
  - 本地 SQLite 数据库
  - 自动同步（PC 模式）
  - 离线完全可用

- **🎨 现代化 UI**
  - Material Design 3
  - 深色/浅色主题
  - 流畅的动画效果

## 📁 项目结构

```
media_manager/
├── media_manager_app/              # Flutter 前端应用
│   ├── lib/src/
│   │   ├── core/                   # 核心功能
│   │   │   ├── database/           # 本地数据库（SQLite）
│   │   │   ├── services/           # 服务层
│   │   │   │   ├── backend_mode.dart          # 模式管理
│   │   │   │   ├── local_http_server.dart     # 本地服务器（接收油猴数据）
│   │   │   │   ├── scraper_service.dart       # 刮削服务
│   │   │   │   └── app_initializer.dart       # 应用初始化
│   │   │   ├── repositories/       # 数据仓库层
│   │   │   └── models/             # 数据模型
│   │   └── features/               # 功能模块
│   │       ├── media/              # 媒体管理
│   │       ├── actors/             # 演员管理
│   │       ├── collection/         # 收藏管理
│   │       └── settings/           # 设置
│   └── pubspec.yaml
├── media_manager_backend/          # Rust 后端服务器（可选）
│   ├── src/
│   │   ├── api/                    # REST API 端点
│   │   ├── database/               # 数据库层
│   │   ├── models/                 # 数据模型
│   │   └── services/               # 业务逻辑
│   ├── plugins/                    # 插件系统
│   │   └── scraper/                # 磁力刮削插件
│   └── Cargo.toml
├── media_manager_userscript/       # 油猴脚本
│   ├── media-importer.core.js      # 核心模块
│   ├── sites/                      # 网站配置
│   └── build.ps1                   # 构建脚本
└── docs/                           # 文档
    └── iOS_SETUP.md                # iOS 设置指南
```

## 🚀 快速开始

### 方式一：独立模式（推荐移动端用户）

只需安装移动应用，无需后端服务器。

#### 1. 安装 Flutter
```bash
# 下载 Flutter SDK: https://flutter.dev/docs/get-started/install
# 添加到 PATH
flutter doctor
```

#### 2. 安装 FFmpeg（仅 Windows 桌面模式需要）

如果你在 Windows 上运行桌面应用，需要安装 FFmpeg 来生成视频缩略图：

```bash
# 使用 Chocolatey（推荐）
choco install ffmpeg

# 或手动安装，详见：docs/FFMPEG_INSTALLATION.md
```

**注意**：Android 和 iOS 不需要安装 FFmpeg。

#### 3. 运行应用
```bash
cd media_manager_app
flutter pub get
flutter run
```

应用会自动：
- 启动本地 HTTP 服务器（端口 8080）
- 创建本地 SQLite 数据库
- 启用内置刮削功能

#### 3. 配置油猴脚本（可选）

安装浏览器扩展：
- **PC**: Tampermonkey (Chrome/Firefox/Edge)
- **Android**: Kiwi Browser + Tampermonkey
- **iOS**: Safari + Userscripts / Orion Browser

配置 API 地址：
- 移动端：`http://localhost:8080/api`（自动检测）
- 或在脚本侧边栏手动配置设备 IP

### 方式二：PC 模式（完整功能）

运行后端服务器，获得插件系统和更强大的功能。

#### 1. 安装 Rust
```bash
# 安装 Rust: https://rustup.rs/
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

#### 2. 设置后端
```bash
cd media_manager_backend
cp .env.example .env
# 编辑 .env 文件配置数据库等
cargo build --release
```

#### 3. 运行后端
```bash
cargo run --release
```
后端将在 http://localhost:3000 启动

#### 4. 运行应用
```bash
cd media_manager_app
flutter run
```

应用会自动检测并连接到后端。

#### 5. 配置油猴脚本
- PC 端：`http://localhost:3000/api`（自动检测）
- 移动端连接 PC：`http://PC的IP:3000/api`

## ✨ 功能特性

### 媒体管理
- ✅ 媒体库浏览和搜索
- ✅ 详细的元数据展示（标题、年份、评分、简介等）
- ✅ 演员信息管理
- ✅ 多种媒体类型支持（电影、场景、动漫等）
- ✅ 厂商和系列分类
- ✅ 高级筛选和排序

### 收藏功能
- ✅ 个人收藏管理
- ✅ 观看状态跟踪（想看、在看、看过等）
- ✅ 个人评分和笔记
- ✅ 自定义标签
- ✅ 观看进度记录

### 数据导入
- ✅ 油猴脚本一键导入
- ✅ 自动提取元数据
- ✅ 批量导入支持
- ✅ 预览图和视频链接
- ✅ 下载链接（磁力、网盘等）

### 刮削功能
- ✅ 内置磁力搜索（Kiteyuan、Knaben）
- ✅ PC 模式插件系统（更多数据源）
- ✅ 智能回退机制

### 同步功能
- ✅ 独立模式：本地存储
- ✅ PC 模式：自动同步到后端
- ✅ 多设备支持

### 用户界面
- ✅ Material Design 3
- ✅ 深色/浅色主题
- ✅ 响应式布局
- ✅ 流畅动画
- ✅ 图片缓存和代理

## 🔧 技术栈

### 前端（Flutter）
- **框架**: Flutter 3.x
- **状态管理**: Riverpod
- **路由**: GoRouter
- **本地存储**: SQLite (sqflite)
- **网络**: Dio
- **UI**: Material Design 3

### 后端（Rust）
- **框架**: Actix-web
- **数据库**: SQLite (rusqlite)
- **ORM**: 自定义
- **插件系统**: 动态加载

### 油猴脚本
- **核心**: JavaScript ES6+
- **模块化**: 网站配置分离
- **构建**: PowerShell 脚本

## 📱 平台支持

| 平台 | 独立模式 | PC 模式 | 油猴脚本 | 状态 |
|------|----------|---------|----------|------|
| Android | ✅ | ✅ | ✅ (Kiwi Browser) | 完全支持 |
| iOS | ✅ | ✅ | ✅ (Safari/Orion) | 完全支持 |
| Windows | ✅ | ✅ | ✅ | 完全支持 |
| macOS | ✅ | ✅ | ✅ | 完全支持 |
| Linux | ✅ | ✅ | ✅ | 完全支持 |

## 🎯 使用场景

### 场景 1：移动端独立使用
```
用户 → 移动应用（独立模式）
     ↓
   本地数据库
     ↓
   浏览器 + 油猴脚本 → 本地服务器(8080) → 应用
```

### 场景 2：PC + 移动端协同
```
PC 后端(3000) ← → 移动应用（PC 模式）
     ↓                    ↓
  数据库              自动同步
     ↑
油猴脚本（PC 浏览器）
```

## 🌐 油猴脚本使用

### 支持的网站
脚本采用模块化设计，支持多个网站。每个网站有独立的配置文件。

### 导入流程
1. 访问支持的网站
2. 脚本自动在卡片上添加"导入"按钮
3. 点击导入或批量选择
4. 数据自动发送到应用
5. 在应用中查看和管理

### 配置 API 地址
脚本会自动检测平台：
- **移动端**: 默认 `http://localhost:8080/api`
- **PC 端**: 默认 `http://localhost:3000/api`
- **自定义**: 在脚本侧边栏手动配置

## 📊 API 端点

### 媒体相关
- `GET /api/media` - 获取媒体列表
- `GET /api/media/:id` - 获取媒体详情
- `POST /api/media` - 创建媒体项
- `PUT /api/media/:id` - 更新媒体
- `DELETE /api/media/:id` - 删除媒体

### 演员相关
- `GET /api/actors` - 获取演员列表
- `GET /api/actors/:id` - 获取演员详情
- `POST /api/actors` - 创建演员
- `PUT /api/actors/:id` - 更新演员
- `DELETE /api/actors/:id` - 删除演员

### 收藏相关
- `GET /api/collections` - 获取收藏列表
- `GET /api/collections/:mediaId` - 获取收藏详情
- `POST /api/collections` - 添加到收藏
- `PUT /api/collections/:mediaId` - 更新收藏
- `DELETE /api/collections/:mediaId` - 删除收藏

### 刮削相关（PC 模式）
- `POST /api/plugins/scraper/search` - 搜索磁力链接

## 🔍 故障排除

### 应用无法启动
- 运行 `flutter doctor` 检查环境
- 确保依赖已安装：`flutter pub get`
- 清理缓存：`flutter clean`

### 油猴脚本无法连接
- 检查应用是否在运行
- 确认 API 地址配置正确
- 移动端确保应用在前台
- 检查防火墙设置

### 后端连接失败
- 确认后端正在运行（端口 3000）
- 检查网络连接
- 移动端使用 PC 的局域网 IP
- 在设置中查看服务器信息

### 图片无法加载
- 独立模式：图片直接从源站加载
- PC 模式：通过后端代理加载
- 检查网络连接
- 某些网站可能需要代理

### 数据库问题
- 独立模式：数据存储在应用本地
- PC 模式：数据存储在后端
- 可以在设置中导出/导入数据
- 重装应用会清空本地数据（独立模式）

## 📚 更多文档

- [iOS 设置指南](docs/iOS_SETUP.md) - iOS 平台详细配置
- [开发环境设置](setup.md) - 开发者环境配置
- [插件开发](media_manager_backend/plugins/scraper/README.md) - 后端插件开发

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- Flutter 团队提供的优秀框架
- Rust 社区的强大生态
- 所有开源项目的贡献者