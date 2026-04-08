# Blessed Engine Reference

TUI 使用 blessed 库作为渲染引擎。本文档记录 blessed 的核心机制，供开发时参考。

## 渲染模型

### 双缓冲 + 差分输出

Blessed 使用经典双缓冲：

- `screen.lines` — 期望缓冲区，widget 的 `render()` 写入此处
- `screen.olines` — 当前显示缓冲区，代表终端上实际显示的内容

`screen.render()` 流程：
1. 遍历所有子组件，调用 `child.render()` 写入 `screen.lines`
2. 调用 `screen.draw()` 做**逐单元格差分**
3. 只输出变化的单元格

`screen.draw()` 的关键优化：
- **脏行跳过**：未标记 dirty 的行直接跳过
- **单元格级别 diff**：`lines[y][x] === olines[y][x]` 时跳过
- **单次写入**：所有输出累积为一个字符串，一次 `_write()` 刷新
- **绘制期间隐藏光标**：避免光标闪烁
- **永远不清屏重绘**：只覆盖变化的单元格

这就是 blessed 不闪烁的原因。

### smartCSR

启用后，blessed 检查滚动元素两侧是否有干净内容，如果是，使用终端原生 CSR（Change Scroll Region）+ IL/DL（Insert/Delete Line）进行高效滚动，避免重绘整个 widget。

```typescript
const screen = blessed.screen({ smartCSR: true })
```

## List Widget

### 继承链

`List -> Box -> Element -> Node -> EventEmitter`

当 `scrollable: true` 时，Element 构造函数会将 `ScrollableBox` 的方法混入实例。

### 关键属性

| 属性 | 说明 |
|------|------|
| `selected` | 当前选中项的索引（number） |
| `items[]` | Box 元素数组，每项一个 Box |
| `ritems[]` | 原始字符串数组 |
| `value` | 当前选中项的文本（去除标签） |
| `childBase` | 滚动偏移（顶部不可见的项数） |
| `childOffset` | 光标在可见区域内的位置 |

关系：`selected = childBase + childOffset`

### select(index) 方法

```
select(index):
  1. 如果非 interactive，返回
  2. 如果为空，重置 selected=0，返回
  3. 将 index 钳制到 [0, items.length-1]
  4. 如果 selected===index 且已初始化，短路返回
  5. 设置 this.selected = index
  6. 设置 this.value = cleanTags(ritems[selected])
  7. 调用 this.scrollTo(this.selected) ← 关键滚动调用
  8. 触发 'select item' 事件
```

### up() / down() 方法

```
up(offset)  = move(-(offset || 1))
down(offset) = move(offset || 1)
move(offset) = select(selected + offset)
```

### 自然滚动原理

当用户按 Down：
1. `list.down()` -> `list.move(1)` -> `list.select(selected + 1)`
2. `select()` 调用 `scrollTo(newIndex)`
3. `scrollTo` 调用 `scroll(newIndex - (childBase + childOffset))`
4. 如果光标在视口底部（`childOffset == visible - 1`），`childBase` 增加 1（视口滚动）
5. 如果光标不在底部，`childOffset` 增加 1（光标移动，视口不动）

**结果**：光标逐行向下移动，到达底部边缘时视口才滚动。

### 内置键盘处理

当 `keys: true` 时，List 在 `this.on('keypress', ...)` 中处理：

| 键 | 动作 | 需要 vi |
|----|------|---------|
| up / k | `self.up()` + `screen.render()` | k 需要 |
| down / j | `self.down()` + `screen.render()` | j 需要 |
| enter / l | `self.enterSelected()` | l 需要 |
| escape / q | `self.cancelSelected()` | q 需要 |
| Ctrl+u | 半页上 | 是 |
| Ctrl+d | 半页下 | 是 |
| Ctrl+b | 整页上 | 是 |
| Ctrl+f | 整页下 | 是 |
| g | 跳到第一项 | 是 |
| G | 跳到最后一项 | 是 |
| / 或 ? | 搜索 | 是 |

**重要**：内置处理已包含 `screen.render()` 调用。

### 事件

| 事件 | 触发时机 | 参数 |
|------|----------|------|
| `select item` | 光标移动（每次 up/down） | `(item, index)` |
| `select` | 按 Enter 确认 | `(item, index)` |
| `action` | Enter 或 Escape | `(item, index)` 或 `()` |
| `cancel` | Escape | 无 |

**关键区别**：`'select item'` 在光标移动时触发，`'select'` 在 Enter 时触发。

### 高亮渲染

每个 item 在 render 时动态检查：
```javascript
var attr = self.items[self.selected] === item && self.interactive
  ? self.style.selected[name]  // 选中样式
  : self.style.item[name]      // 普通样式
```

## 键盘处理

### 传播模型

```
program.on('keypress') 处理器：
  1. Screen 先收到事件（screen.emit('key X')）
  2. 如果 grabKeys/lockKeys 未改变...
  3. 聚焦的元素收到事件（focused.emit('key X')）
```

**两者都会触发，没有事件停止/冒泡机制。**

### screen.key() vs element.key()

两者都是注册在 `program.on('key X')` 上，区别只是 `this` 上下文不同。**它们不存在优先级差异。**

### 正确做法

- 使用 `element.on('keypress', ...)` 处理焦点相关的键盘事件
- 使用 `screen.key()` 处理全局键盘事件
- 在 `screen.key()` 中用 `if (screen.focused !== myElement) return` 来限制作用域
- **不要同时用 `screen.key('j')` 和 list 的 `keys: true`**，它们会同时触发

## 正确的 List 使用模式

```typescript
const list = blessed.list({
  parent: screen,
  keys: true,          // 启用内置键盘导航
  vi: true,            // 启用 j/k/g/G 等
  mouse: true,         // 启用鼠标/滚轮
  border: { type: 'line' },
  style: {
    selected: { bg: 'blue', fg: 'white' },
    item: { fg: 'white' }
  },
  items: ['Item 1', 'Item 2', ...],
})

// 光标移动时更新 detail panel
list.on('select item', (item, index) => {
  updateDetailPanel(index)
})

// Enter 确认时执行操作
list.on('select', (item, index) => {
  performAction(index)
})

list.focus()
screen.render()
```

**要点**：
1. 不要自己管理 `selectedIndex`，用 `list.selected` 读取
2. 不要在 `screen.key('j')` 中调用 `list.select()`，让 list 自己处理
3. 监听 `'select item'` 事件来响应光标移动
4. `setItems()` 会尝试保留选中位置

## 弹窗/对话框模式

```typescript
function showDialog() {
  const dialog = blessed.list({
    parent: screen,
    top: 'center',
    left: 'center',
    width: 50,
    height: 10,
    keys: true,
    vi: true,
    border: { type: 'line' },
    style: { selected: { bg: 'blue' } },
    items: ['Option 1', 'Option 2'],
  })

  dialog.on('select', (item, index) => {
    dialog.destroy()
    // 处理选择...
    list.focus()  // 恢复焦点
    screen.render()
  })

  dialog.key(['escape', 'q'], () => {
    dialog.destroy()
    list.focus()
    screen.render()
  })

  dialog.focus()
  screen.render()
}
```

## 异步更新（不闪烁）

```typescript
// 只更新 detail box 的内容
detail.setContent('Loading...')
screen.render()  // 只重绘 detail box 变化的部分

fetchData().then(data => {
  detail.setContent(data)
  screen.render()  // 同样只重绘变化的部分
})
```

因为 blessed 的差分渲染，只有实际变化的单元格会被重绘，所以异步更新不会导致闪烁。

## 常见陷阱

1. **screen.key() 和 list keys 冲突**：如果 list 设置了 `keys: true, vi: true`，不要再用 `screen.key(['j'])` 处理同一个键，两者都会触发
2. **setItems() 后需要 screen.render()**：`setItems()` 不会自动渲染
3. **list.selected 是 number**：类型定义可能标记为不存在，用 `(list as any).selected` 访问
4. **screen.key() 的 this**：在 `screen.key()` 中 `this` 是 screen，不是调用者
5. **element.key() 不限作用域**：它注册在 program 上，不管元素是否聚焦都会触发
