# ✅ 手机端功能完善完成记录

> 汇总日期：2026-05-23
> 核心目标：解决 Android 手机端因缺少 Kotlin 后端导致的功能不可用问题

---

## 一、存储路径与权限

### 1.1 默认路径改为自有目录
- **文件**: `lib/backend_utils.dart`
- Android 默认路径从 `/storage/emulated/0/Academic Aegis` 改为 `getApplicationDocumentsDirectory()/Academic Aegis`（无需额外权限）
- 去掉之前的共享存储探测逻辑，开机不再因权限不足崩溃

### 1.2 文件夹选择器 + 权限申请
- **文件**: `lib/welcome.dart`, `lib/settings_page.dart`
- 欢迎页和设置页新增「选择输出文件夹」按钮（使用 `file_picker` 包）
- Android 选择文件夹后弹出权限弹窗：
  - 「去授权」→ 跳转系统设置，用户手动开启 `MANAGE_EXTERNAL_STORAGE`
  - 「不授权」→ 使用软件自有目录

### 1.3 存储权限
- **文件**: `android/app/src/main/AndroidManifest.xml`
- 添加 `MANAGE_EXTERNAL_STORAGE`、`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`
- 添加 `android:requestLegacyExternalStorage="true"`

### 1.4 权限通道（MethodChannel）
- **文件**: `android/.../MainActivity.kt`
- 新增 `com.academic.aegis/permission` 通道
- `checkStoragePermission`：检查 `MANAGE_EXTERNAL_STORAGE`
- `openStoragePermissionSettings`：跳转系统设置页
- 新增 `com.academic.aegis/backend` 的 `startBackend` 处理器，Android 直接返回成功

---

## 二、AI 聊天直连

### 2.1 直连 AI API
- **文件**: `lib/backend_utils.dart` — 新增 `directStreamChat()`
- Android 直接调用 OpenAI 兼容的 `/chat/completions` 接口（流式 SSE）
- 绕过了本地 Kotlin 后端

### 2.2 启动流程适配
- **文件**: `lib/main.dart`, `lib/welcome.dart`
- Android 检测到配置后不启动本地后端，自动切换到直连 AI API 模式
- 将 `baseUrl`、`apiKey`、`model` 传入页面组件

---

## 三、历史对话记录

### 3.1 Backlog 文件存取
- **文件**: `lib/backend_utils.dart`
- `BacklogMessage` 数据模型
- `saveBacklog()`：保存对话到 `{BASE_PATH}/Backlog/{yyyy-MM-dd}/{HH-mm-ss}.json`
- `loadBacklogForDate()`：读取单日 backlog 文件
- `loadBacklogForRange()`：读取日期范围内的 backlog 文件

### 3.2 对话保存
- **文件**: `lib/home_page.dart`
- 直连 AI 对话完成后自动调用 `saveBacklog()` 写入本地文件

### 3.3 历史页面适配
- **文件**: `lib/history_page.dart`
- Android 端 `_fetchHistory()` 改为直接调用 `loadBacklogForDate()`/`loadBacklogForRange()`
- 数据结构完全兼容 Kotlin 后端格式

### 3.4 排序修复
- **文件**: `lib/history_page.dart`
- 新增 `_sortedKeys` 缓存 + `_updateSortedKeys()` 方法
- 按文件名（时间 `HH-MM-SS`）实现正/倒序排列
- 改用 `_sortedKeys[index]` 而非 Map 插入顺序

### 3.5 时间段过滤逻辑修复
- **文件**: `lib/backend_utils.dart`, `backend_kotlin/.../Application.kt`
- 原逻辑：对所有日期同等应用 startTime~endTime 过滤
- 修复后：
  - 起始日：只过滤 ≥ startTime
  - 结束日：只过滤 ≤ endTime
  - 中间日期：不限时间

### 3.6 控件布局优化
- **文件**: `lib/history_page.dart`
- 时间选择器对齐到各自日期正下方
- 筛选区阴影提升（elevation: 4）以区分结果列表
- 时间开关始终显示在底部

### 3.7 空列表 RangeError 修复
- **文件**: `lib/history_page.dart`
- `itemCount` 改为 `_sortedKeys.length`
- 添加越界保护 `if (index >= _sortedKeys.length)`

---

## 四、成绩管理

### 4.1 本地成绩服务
- **文件**: `lib/local_backend.dart` — 新增 `LocalScoreService`
- `loadStudents()`：读取 `{BASE_PATH}/Score_info/students.json`
- `queryStudent()`：按 ID 或姓名查询
- `queryStudentsByName()`：模糊匹配返回所有结果
- `listAllStudents()`：列出全部学生
- `addScore()`：添加/更新成绩，自动标准化分数值
- `deleteStudent()`：删除学生
- 分数值自动处理字符串转数字（如 "88" → 88）

### 4.2 查询界面（搜索页）
- **文件**: `lib/home_page.dart`
- 新增复选框：☑ 按学号查找 / ☑ 按姓名查找
- 默认勾选学号，未勾选的输入框自动禁用
- 勾选逻辑：
  - 仅 ID → 精确匹配
  - 仅姓名 → 模糊匹配
  - 两者都勾 → 严格模式（AND）
  - 都不勾 → 显示全部学生
- 勾选了未填内容 → 精确提示「请输入学号」/「请输入姓名」
- 多条匹配 → 居中弹窗选择器

### 4.3 删除界面
- **文件**: `lib/home_page.dart`
- 先「查询学生信息」→ 展示学生详情卡片（头像、姓名、学号、科目数）
- 「共 X 门课程」可点击查看详情（跳转 ScoreResultPage）
- 确认后再「确认删除这名学生」→ 二次确认弹窗

### 4.4 查询结果页面
- **文件**: `lib/score_result_page.dart` — 全新设计
- 学生信息卡片（头像 + 姓名 + 学号）
- 成绩概览：科目数、总分、平均分、及格/不及格数
- 各科成绩彩色进度条（绿≥90 / 蓝≥80 / 橙≥70 / 黄≥60 / 红<60）

---

## 五、日程安排

### 5.1 本地日程服务
- **文件**: `lib/local_backend.dart` — 新增 `LocalScheduleService`
- `loadItinerary()`：读取 `{BASE_PATH}/Schedule/{date}.md`
- `saveItinerary()`：保存日程到文件
- `generateSchedule()`：通过直连 AI API 生成日程规划

### 5.2 日程页面适配
- **文件**: `lib/home_page.dart`
- Android 端 `_fetchSavedSchedule()` 改用 `LocalScheduleService.loadItinerary()`
- Android 端 `_generateSchedule()` 改用 `LocalScheduleService.generateSchedule()` 直连 AI
- 生成的日程自动保存到本地文件

### 5.3 像素溢出修复
- **文件**: `lib/home_page.dart`
- 日程页面根布局从 `Padding` 改为 `SingleChildScrollView(padding: ...)`
- 内容可滚动，不再溢出

---

## 六、后端同步修复

### 6.1 Kotlin 后端 `StudentScoreService`
- **文件**: `backend_kotlin/.../Services.kt`
- `queryStudents()`：同时传 id+name 时改为 AND 过滤（之前只过滤 id）
- `loadData()`：改为手动 JSON 解析，兼容字符串分数（如 "88"）

### 6.2 Kotlin 后端 `Application.kt`
- `/history/range`：时间段过滤逻辑与 Dart 端同步修复

### 6.3 Kotlin 后端 `EnvConfig`
- **文件**: `backend_kotlin/.../Memory.kt`
- Android 路径检测，使用 `/storage/emulated/0/Academic Aegis`

---

## 七、新增/修改依赖

- `pubspec.yaml`：添加 `file_picker: ^8.0.0`

---

## 八、最终手机端功能状态

| 功能 | Android | PC |
|------|---------|-----|
| 🤖 AI 聊天 | ✅ 直连 API + 自动保存记录 | ✅ 通过 Kotlin 后端 |
| 📜 历史记录 | ✅ 读取本地 backlog 文件 | ✅ 通过 Kotlin 后端 |
| 📊 成绩查询 | ✅ 本地 `students.json` 文件 | ✅ 通过 Kotlin 后端 |
| ➕ 成绩录入 | ✅ 本地 `students.json` 文件 | ✅ 通过 Kotlin 后端 |
| 🗑 成绩删除 | ✅ 本地 `students.json` 文件 | ✅ 通过 Kotlin 后端 |
| 📅 日程读取 | ✅ 本地 `Schedule/` 文件 | ✅ 通过 Kotlin 后端 |
| 🤖 日程生成 | ✅ 直连 AI API + 保存文件 | ✅ 通过 Kotlin 后端 |
| 📁 文件夹选择 | ✅ file_picker + 权限申请 | ✅ file_picker |
