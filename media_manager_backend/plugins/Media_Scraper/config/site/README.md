# Site Configuration CSV Format

## 文件格式规范

### 1. 文件命名规范
```
{network}_sites.csv
```
例如：
- `mindgeek_sites.csv` - MindGeek 网络站点
- `gamma_sites.csv` - Gamma Entertainment 网络站点
- `vixen_sites.csv` - Vixen Group 网络站点

### 2. CSV 字段定义

| 字段名 | 类型 | 必填 | 说明 | 示例 |
|--------|------|------|------|------|
| `site_name` | string | ✅ | 站点显示名称 | `Moms in Control` |
| `domain` | string | ✅ | 站点域名（不含协议） | `MomsInControl.com` |
| `code` | string | ❌ | 站点代码（API调用用） | `mic` |
| `network` | string | ✅ | 所属网络 | `Brazzers` |
| `enabled` | boolean | ❌ | 是否启用（默认true） | `true` |
| `priority` | integer | ❌ | 优先级1-100（默认50） | `90` |

### 3. 格式要求

#### 3.1 文件头部
```csv
# 网络名称 Sites Configuration
# 格式说明和字段定义...

site_name,domain,code,network,enabled,priority
```

#### 3.2 注释规范
- 使用 `#` 开头的行作为注释
- 按网络分组，用注释分隔
- 注释中包含站点数量统计

#### 3.3 数据格式
- **字符串**: 不需要引号，除非包含逗号
- **布尔值**: `true` / `false`
- **数字**: 直接写数字
- **空值**: 留空即可

#### 3.4 分组规范
```csv
# ==================== Network Name (X sites) ====================
site1,domain1.com,code1,Network,true,90
site2,domain2.com,code2,Network,true,85

# ==================== Another Network (Y sites) ====================
site3,domain3.com,code3,AnotherNetwork,true,80
```

### 4. 优先级指南

| 优先级范围 | 用途 | 说明 |
|------------|------|------|
| 90-100 | 顶级站点 | 最重要的主站点 |
| 80-89 | 高优先级 | 热门子站点 |
| 70-79 | 中等优先级 | 常规子站点 |
| 60-69 | 低优先级 | 较少使用的站点 |
| 50-59 | 默认优先级 | 新添加的站点 |

### 5. 扩展示例

#### 5.1 添加新网络
```csv
# ==================== RealityKings Network (45 sites) ====================
Reality Kings,RealityKings.com,rk,RealityKings,true,95
RK Prime,RKPrime.com,rkp,RealityKings,true,90
Moms Bang Teens,MomsBangTeens.com,mbt,RealityKings,true,85
```

#### 5.2 禁用站点
```csv
Old Site,OldSite.com,old,Network,false,0
```

#### 5.3 包含特殊字符的站点名
```csv
"Site, with comma",SiteWithComma.com,swc,Network,true,80
```

### 6. 验证规则

#### 6.1 必填字段检查
- `site_name` 不能为空
- `domain` 必须是有效域名格式
- `network` 不能为空

#### 6.2 数据类型检查
- `enabled` 必须是 `true` 或 `false`
- `priority` 必须是 1-100 的整数

#### 6.3 唯一性检查
- 同一文件内 `domain` 不能重复
- 同一网络内 `code` 不能重复（如果不为空）

### 7. 最佳实践

#### 7.1 命名规范
- 站点名称使用官方名称
- 域名使用主域名（不含 www）
- 代码使用简短的缩写

#### 7.2 维护建议
- 定期检查站点可用性
- 及时更新域名变更
- 按优先级排序站点

#### 7.3 性能考虑
- 高优先级站点放在前面
- 禁用不可用的站点
- 控制单个网络的站点数量

### 8. 工具支持

#### 8.1 验证脚本
```bash
# 验证 CSV 格式
python validate_sites_csv.py mindgeek_sites.csv
```

#### 8.2 转换工具
```bash
# 从源代码生成 CSV
python extract_sites_from_source.py Brazzers.cs > brazzers_sites.csv
```

#### 8.3 统计工具
```bash
# 统计站点数量
python count_sites.py mindgeek_sites.csv
```