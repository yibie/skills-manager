# Skills Manager - Development Guide

## TUI Engine: blessed

TUI (`tui/`) 使用 [blessed](https://github.com/chjj/blessed) 作为渲染引擎。

### 核心原则

1. **让 blessed list 自己处理导航** — 设置 `keys: true, vi: true`，不要用 `screen.key('j')` 手动管理光标
2. **监听 `'select item'` 事件更新 detail** — 不要自己维护 `selectedIndex`
3. **全局快捷键检查焦点** — 在 `screen.key()` 中用 `screen.focused !== target` 来限制作用域
4. **异步更新只改 detail box** — blessed 差分渲染确保不闪烁

### 参考文档

- `tui/docs/blessed-engine.md` — blessed 渲染模型、List widget、键盘处理、滚动机制的详细说明

### 正确的 List 用法

```typescript
// 创建 list 时启用内置导航
const list = blessed.list({
  keys: true,   // 方向键导航
  vi: true,     // j/k/g/G 等 vim 键
  mouse: true,  // 鼠标支持
  style: { selected: { bg: 'blue', fg: 'white' } },
  items: [...],
})

// 监听光标移动（不是手动管理 selectedIndex）
list.on('select item', (item, index) => {
  updateDetail(index)
})

// 监听 Enter 确认
list.on('select', (item, index) => {
  performAction(index)
})

list.focus()
```

### 不要做的事

- **不要** `screen.key(['j'], () => { selectedIndex++; list.select(selectedIndex) })` — 会和 list 内置处理冲突
- **不要** 自己管理 `selectedIndex` 变量 — 用 `(list as any).selected` 读取
- **不要** 在光标移动时调用 `render()` 以外的全量刷新 — list 的内置处理已包含 `screen.render()`

### 弹窗模式

创建新的 blessed widget 作为弹窗，设置 `parent: screen`，调用 `.focus()` 抢占焦点。关闭时 `.destroy()` 并恢复原焦点。

## 项目结构

```
tui/
├── src/
│   ├── index.ts            # 入口（blessed 版本）
│   ├── app-blessed.ts      # 主应用
│   ├── services/           # 数据服务
│   │   ├── SkillStore.ts
│   │   ├── InstallService.ts
│   │   ├── DiscoverInstallService.ts
│   │   └── SkillsDirectoryService.ts
│   └── types.ts
├── docs/
│   └── blessed-engine.md   # blessed 引擎参考文档
└── package.json
```
