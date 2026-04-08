# Skills Manager TUI - Blessed Version

## 迁移到 Blessed

TUI 已从 Ink (React) 迁移到 blessed，带来以下改进：

### 优势

✅ **真正的局部刷新** - 只更新变化的部分，无全屏闪烁
✅ **异步加载** - Detail panel 可以异步加载内容，显示 "Loading..." 然后局部更新
✅ **更好的性能** - 更底层的控制，更快的渲染
✅ **更流畅的体验** - 类似 lazygit, k9s 等专业 TUI 工具

### 架构变化

**之前 (Ink):**
- 基于 React 组件
- 每次状态变化重新渲染整个界面
- 异步加载需要 overlay 或全屏刷新

**现在 (Blessed):**
- 直接操作 blessed boxes
- 只更新变化的 box
- 异步加载可以局部更新 detail panel

### 使用方法

正式 CLI 命令名：`skills-manager`

```bash
# 在当前仓库里运行正式 CLI（推荐）
npm exec skills-manager

# 开发模式直接运行 blessed 源码（默认）
npm start

# 运行旧的 Ink 版本（备份）
npm run start:ink

# 构建
npm run build
```

如果要从任意目录直接调用，可以在 `tui/` 里执行一次：

```bash
npm link
```

之后即可全局运行：

```bash
skills-manager
```

### 功能对比

| 功能 | Ink 版本 | Blessed 版本 |
|------|---------|-------------|
| 三栏布局 | ✅ | ✅ |
| 键盘导航 | ✅ | ✅ |
| Install/Uninstall | ✅ | ✅ |
| Star/Unstar | ✅ | ✅ |
| 异步加载详情 | ❌ (需要 overlay) | ✅ (局部更新) |
| 无闪烁刷新 | ❌ | ✅ |
| Sidebar 导航 | ✅ | ✅ |
| 搜索 | ✅ | ✅ |
| 版本历史 | ✅ | ✅ |
| Discover 详情 overlay | ✅ | ✅ |
| 在编辑器中打开本地 skill | ✅ | ✅ |
| 在浏览器中打开 discover skill | ✅ | ✅ |
| 源过滤 | ✅ | ✅ |
| Agent 选择 overlay | ✅ | ✅ |

### 键盘快捷键

- `h/l` - 切换面板 (sidebar ← → list ← → detail)
- `j/k` 或 `↑/↓` - 上下移动
- `g/G` - 跳到第一个/最后一个
- `i` - 安装 skill
- `x` - 卸载 skill
- `s` - 标星/取消标星
- `H` - 打开本地 skill 的版本历史
- `d` - 打开 discover skill 的详情 overlay
- `o` - 打开 skill 的源文件（优先用 `$EDITOR`，否则交给系统默认应用）
- `O` - 在 Discover 视图里打开 skill 的 source 页面
- `/` - 搜索当前视图
- `f/F` - Switch Source：切换 discover 来源过滤
- `0` - Reset Source：重置 discover 来源过滤
- `Enter` - 与 `l` 一样仅用于切换面板
- `r` - 刷新 discover 目录（仅 discover 视图）
- `R` - 完全刷新页面：重载本地 skills、agents、discover 目录，并强制整屏重绘
- 侧边栏 `Sources` - 区分 Local 与各个 Plugin bundle（`pluginSource · pluginName`）
- 列表前缀 `L/P` - 区分 Local skill / Plugin resource；Pi extension 在 UI 上归类为 Plugin
- `q` 或 `Ctrl+C` - 退出
- 当前 Blessed 版为键盘优先，默认禁用鼠标交互，避免出现“能点但不响应”的误导行为

### 待实现功能

- [ ] 搜索结果高亮匹配词
- [ ] 历史 overlay 的分页/滚动优化
- [ ] 更完整的浏览器/编辑器跨平台打开策略

### 文件结构

```
src/
├── app-blessed.ts      # Blessed 版本主应用
├── index.ts            # 主入口 (blessed)
├── index-ink.tsx       # Ink 版本入口 (备份)
├── app.tsx             # Ink 版本主应用 (备份)
└── components/         # Ink 组件 (备份)
```

## 开发说明

Blessed 版本使用命令式 API，不是声明式的 React。主要概念：

1. **创建 boxes** - `blessed.box()`, `blessed.list()` 等
2. **更新内容** - `box.setContent()`, `list.setItems()`
3. **渲染** - `screen.render()` 只渲染变化的部分
4. **键盘处理** - `screen.key(['j'], () => {...})`

### 异步加载示例

```typescript
// 显示 loading
detail.setContent('Loading...')
screen.render()

// 异步加载
fetchData().then(data => {
  detail.setContent(data)
  screen.render() // 只更新 detail box
})
```

这就是 blessed 的核心优势 - 局部更新，无闪烁！
