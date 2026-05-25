## ✅ 已完成

### 1. 主题深浅颜色切换
- 默认跟随系统主题
- `main.dart`: 添加 `darkTheme`（深色主题）+ `themeMode` 控制
- `backend_utils.dart`: 添加全局 `themeModeNotifier`（ValueNotifier）
- 启动时从 `config.json` 的 `THEME_MODE` 字段读取用户偏好

### 2. 设置页面新增深浅模式切换
- `settings_page.dart`: 新增"主题模式"区域
- 三个选项：跟随系统 / 浅色模式 / 深色模式（RadioListTile + 图标）
- 保存时更新 `config.json` 并通知全局 `themeModeNotifier`

### 3. AI 聊天底部导航栏
- `home_page.dart`:
  - 从 AppBar 移除"查看聊天历史"按钮
  - 在输入框下方新增"聊天" | "历史" 导航栏（带选中指示器）
  - 点击"历史"跳转到 HistoryPage，返回后自动切回"聊天"标签
  - AI 回复气泡适配深色模式文字颜色

### 4. 滑动切换 + 底部导航 + 成绩页导航栏移到底部
- `home_page.dart`:
  - 手机端 `IndexedStack` → `PageView`，支持左右滑动切换主页面
  - 新增 `PageController`，与 `selectedIndex` 双向同步
  - ScorePage 的 TabBar（查询/录入/删除）从顶部移到底部

### 5. 聊天历史嵌入 AI 聊天界面 + 恢复3主页面
- `home_page.dart`:
  - **HomeContent 内部**新增 PageView（0=聊天, 1=历史），支持左右滑动切换
  - 底部恢复"聊天"|"历史"导航栏，选中标签有主题色指示线
  - 输入框仅在"聊天"标签下显示，"历史"标签全屏展示 HistoryPage
  - **ScorePage** 的 `IndexedStack` → `TabBarView`，支持左右滑动切换查询/录入/删除
  - 移除 `bottomNavigationBar`（不复现抽屉逻辑）
  - **桌面端** `IndexedStack` → `PageView`，修复 NavigationRail 点击切换
  - 主页面恢复为 3 个：AI聊天 → 我的成绩 → 日程安排
  - 侧栏/抽屉**移除"聊天历史"** 条目（从 AI 聊天底部进入）
  - `loadHistory` 自动切回聊天标签

### 修改的文件
- `lib/main.dart`
- `lib/backend_utils.dart`
- `lib/settings_page.dart`
- `lib/home_page.dart`

