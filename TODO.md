## ✅ 已完成

### 1. 附加文件上传与预览
- 附件类型：代码/文本文件（读取为文本内容）、图片文件（转为Base64编码）
- **附件预览增强**：图片附件显示真实缩略图（带文件名浮层），非图片附件显示文件图标+名称
- **附件数量标记**：附加按钮旁显示红色圆形数字标记
- 每个附件均可单独删除
- 发送时附件内容自动拼接到用户消息中，保证OpenAI兼容格式API的通用性
- 使用 `file_selector` 插件，支持多类型文件选择

### 2. OCR 识别（前后端完整实现）
- **混合 OCR 方案**：Tesseract (tess4j) 做普通文本识别 + AI Vision API 做数学公式识别
- **Kotlin 后端 OCR 服务**：
  - `POST /api/ocr` — 接收 Base64 图片，返回识别文本 + 公式 LaTeX
  - `GET /api/ocr/check` — 检查 OCR 环境状态
  - 图片预处理：灰度化 + 放大 + 二值化提升识别率
  - 自动查找 tessdata 目录（resources/项目目录/用户主目录）
- **Gradle 配置**：已添加 `net.sourceforge.tess4j:tess4j:5.4.0` 依赖
- **前端 OCR 入口**：输入框旁新增 OCR 按钮，选择图片后调用后端识别

### 3. 学习分析页面（含后端 API）
- 导航栏/抽屉新增「学习分析」入口（第4个页面）
- 包含两个子界面：**记录查询** 和 **学习总结**

#### 记录查询
- 关键词自动获取：用户名、学号、成绩科目名
- 支持用户自定义添加/删除关键词（保存在配置中）
- 日历控件选择日期
- 列出当日与关键词匹配的对话记录（一问一答对），含匹配关键词标签
- 关键词编辑面板可折叠

#### 学习总结
- 根据关键词匹配记录条数 + 日程完成率计算评分
- 评分算法：匹配条数评分（最高50分）+ 日程完成率评分（最高50分）
- 等级判定：≥85优秀 / ≥65良好 / ≥45合格 / <45不合格
- 每天首次访问弹窗确认日程完成项（复选框+表格）
- 提供按钮重新打开勾选弹窗
- 等级变化时自动生成鼓励语（优先调用后端 AI API，失败回退本地规则）
- 评分卡片带渐变背景和大号图标

### 4. 后端 API 端点
- `POST /api/ocr` — OCR 识别（Tesseract + AI 公式）
- `GET /api/ocr/check` — 检查 OCR 环境
- `POST /api/study/encouragement` — AI 生成鼓励语（带本地规则回退）
- `POST /api/study/query` — 关键词匹配对话记录查询
- `POST /api/study/summary` — 学习总结生成（评分+等级）

## 📋 使用说明

### OCR 使用前准备
下载 Tesseract 训练数据放入 `backend_kotlin/src/main/resources/tessdata/`：
- `chi_sim.traineddata`（简体中文）
- `eng.traineddata`（英文）
下载地址：https://github.com/tesseract-ocr/tessdata/

### 附件预览说明
- 选择图片后自动显示 56x56 缩略图，文件名浮层在底部
- 非图片文件显示文件图标 + 文件名
- 上传按钮旁红色数字显示已选择的文件数量

### 5. Markdown 加粗兼容（手机端）
- 手机端 `**xx**` 加粗不显示的问题已修复
- 方案：将包含中文的 `**...**` 自动转为 `<strong>...</strong>` HTML 标签
- 不影响公式渲染（`$...$` 语法未做任何改动）

### 6. AI 聊天输入框按钮位置优化
- OCR 按钮和附件添加按钮现固定在输入框底部对齐
- 无论输入框是单行还是多行（最多4行），按钮始终在最下面一排等高位置

### 7. PreciseSearch 改进 & 学习分析联动
- **PreciseSearch 改为 OpenAI 兼容模式**：`expandKeywords()` 改用 `EnvConfig.activeApiKey`/`activeBaseUrl`/`activeModel`，使用 `/chat/completions` OpenAI 兼容端点
- **后端 `/api/study/query` 集成 PreciseSearch**：新增 `use_ai_expansion` 参数，开启后自动用 PreciseSearch 扩展联想词再搜索
- **前端 StudyAnalysisService 对接后端**：
  - 新增 `queryWithBackend()` 方法：优先调用后端 API（支持 AI 扩展），失败回退本地
  - 新增 `MatchedConversation.fromJson()` 工厂方法
  - `getOrComputeSummary()` 支持传入 `dio` 走后端查询
- **记录查询页（_RecordQueryTab）**：`_doSearch()` 优先走 `queryWithBackend()`
- **学习总结页（_StudySummaryTab）**：`_refreshSummary()` 传入 `dio` 使用后端 AI 扩展查询

### 8. 关键词自动发现（从对话中学习）
- **PreciseSearch.discoverKeywords()**：扫描最近 N 天 backlog，用 AI 从用户问题中提取学习关键词
- **POST /api/study/discover-keywords**：新 API 端点，返回发现的关键词列表
- **前端"从对话中发现关键词"按钮**：记录查询页关键词编辑面板中新增，点击后调用后端 API
- **_DiscoverKeywordsDialog 选择弹窗**：展示发现的关键词，用户可勾选后添加到自定义关键词列表

### 9. 新关键词自动关联到已有缓存
- **KeywordCache.mergeInto()**：向已有缓存条目的扩展列表追加新词
- **PreciseSearch.integrateDiscoveredKeywords()**：发现新关键词后自动关联：
  - 扩展新关键词 → 检查扩展结果中是否有已缓存的学科名（如"语文"）→ 将新关键词合并进去
  - 反向：如果新关键词是硬编码映射中的知识点，也合并到对应学科
- **效果**：发现"小石潭记"后，搜"语文"也能搜到它