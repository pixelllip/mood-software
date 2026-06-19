# 🔥 Academic Aegis · 星火学伴

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)
![Kotlin](https://img.shields.io/badge/Kotlin-2.x-7F52FF?logo=kotlin)
![平台](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20iOS%20%7C%20macOS-FF6B6B)

**AI 驱动的多平台智能学伴工具 —— 聊天 · 查成绩 · 管日程 · 学习分析 · 全能助手**

> 🏛️ **项目溯源**：本项目的**核心逻辑最早以 Python 实现**，作为架构原型与概念验证。随后以 Python 原型为蓝本，重构为 **Kotlin 后端 + Flutter 前端**的多平台架构。

</div>

---

## 我真用，所以我维护

这个项目不出意外的话会继续维护一段时间。截止软件工程课程结课时，最新发行版是2.43。

---

## 📖 项目简介

**Academic Aegis（星火学伴）** 是一款面向学生群体的跨平台 AI 智能助手应用。它融合了大语言模型对话、成绩管理、日程规划、图像识别、联网搜索等多项功能，旨在为学生的学习生活提供一站式智能辅助。

> 🎯 **核心理念**：用 AI 的星火，点亮学业的每一段旅程。

---

## ✨ 功能特性

### 🤖 AI 智能对话
- 基于 **OPENAI 规范 API** 的多轮对话引擎
- **流式输出**（SSE），实时显示 AI 回复
- 支持多 AI 配置切换，兼容 OpenAI 格式的任意 API
- 对话记录自动持久化，支持按日期/时间段检索历史

### 📊 成绩管理
- 本地文件存储学生成绩（`Score_info/students.json`）
- **按学号/姓名**精确或模糊查询
- **成绩录入**与**删除**功能
- 可视化成绩卡片：总分、平均分、科目进度条（颜色分级）
- 多结果弹窗选择器

### 📅 日程规划
- AI 一键生成**个性化学习日程**（含早上/中午/晚上/自由安排）
- 日程以 Markdown 格式存储（`Schedule/{date}.md`）
- 支持 Markdown 富文本渲染查看

### � 学习分析
- **记录查询**：按关键词（自动发现+自定义）匹配当日对话记录
- **AI 关键词扩展**：自动联想同义词，提升匹配召回率
- **学习总结**：根据匹配条数+日程完成率综合评分（优秀/良好/合格/不合格）
- **AI 鼓励语**：等级变化时自动生成个性化鼓励语
- **日程完成确认**：每天首次访问弹窗勾选已完成事项

### 🖼️ 图像识别 & 生成
- **图像识别**：集成百度智能云，支持车型、菜品、动物、植物等多场景识别
- **图像生成**：集成 Stable Diffusion WebUI API，文字生图

### 🌐 联网搜索
- 模型内置联网搜索（`enable_search` 参数），自动获取实时网络信息
- 可独立配置开关，与 AI 聊天共享 API Key

### 🌤️ 实用工具
- **实时天气查询**（高德地图 API）
- **待办清单生成**（按时间段组织）
- **交通路况查询**
- **对话记录管理**（Backlog 系统）
- **关键词发现**：AI 自动从对话记录中提取学习关键词
- 灵活的**系统指令自定义**

---

## 🏗️ 项目架构

> 💡 **架构演进说明**：Python 后端（`backend/`）是本项目的**原型基础与参考实现**，Kotlin 后端与 Flutter 前端均以其为蓝本设计开发。当前 Python 后端不再作为运行时组件。

```
academic-aegis/
├── lib/                          # 🎯 Flutter 前端（跨平台 UI） ← 当前核心
│   ├── main.dart                 # 应用入口、配置加载、平台路由
│   ├── backend_utils.dart        # 后端通信、直连 AI、配置管理
│   ├── pages/
│   │   ├── welcome.dart          # 首次启动配置向导
│   │   ├── home_page.dart        # 主页（聊天/成绩/日程/学习分析 四 Tab）
│   │   ├── history_page.dart     # 历史对话记录
│   │   ├── score_result_page.dart # 成绩查询结果页
│   │   ├── schedule_detail_page.dart # 日程详情查看页
│   │   ├── settings/
│   │   │   ├── settings_page.dart      # 设置页
│   │   │   └── api_settings_page.dart   # API 独立设置页（AI + 联网搜索 + 高德）
│   │   └── study/
│   │       └── study_analysis_page.dart # 学习分析页（记录查询 + 学习总结）
│   ├── services/
│   │   ├── local_backend.dart    # 📱 Android 本地服务（成绩/日程）
│   │   ├── study_analysis_service.dart # 学习分析服务（关键词/评分/鼓励语）
│   │   └── location_service.dart # 📡 定位服务（GPS → 高德反地理编码 → IP）
│   ├── instructions.txt          # 系统指令模板
│   ├── configure.md / TODO.md / DONE.md  # 开发笔记
│
├── backend_kotlin/               # ☕ Kotlin 后端（Ktor，PC 用）← 当前核心
│   ├── build.gradle.kts          # Gradle 构建配置
│   └── src/main/
│       └── ...                   # Ktor 服务（SSE 流式 AI 调用）
│
├── android/                      # 📱 Android 原生层
│   ├── app/build.gradle.kts
│   └── app/src/.../MainActivity.kt  # 权限通道、后端启动
│
├── ios/                          # 🍎 iOS 工程
├── windows/                      # 🪟 Windows 原生
├── linux/                        # 🐧 Linux 原生
├── macos/                        # 🍏 macOS 原生
├── web/                          # 🌐 Web 端
│
├── pubspec.yaml                  # Flutter 依赖声明
├── build_package.ps1             # 🚀 一键构建脚本（PowerShell）
├── build_package.sh              # 🚀 一键构建脚本（Bash）
├── configure.ps1 / configure.sh  # 开发环境配置脚本
├── analysis.md                   # 静态分析配置
├── analysis_options.yaml         # Dart 分析配置
└── README.md
```

---

## 🚀 快速开始

### 环境要求

| 开发环境 | 版本 |
|------|------|
| Flutter | ≥ 3.x |
| Dart | ≥ 3.11.5 |
| JDK | ≥ 17（Kotlin 后端构建） |

| 运行环境 | 版本 |
|------|------|
| JDK | ≥ 17（Kotlin 后端） |

### 1️⃣ 配置 AI 密钥

首次启动会自动生成 `config.json` 配置模板，或在欢迎页引导填写。支持配置**多个 AI 提供商**和**独立联网搜索**：

```json
{
  "BASE_PATH": "C:/Users/.../Academic Aegis",
  "STUDENT_ID": "2024001",
  "STUDENT_NAME": "张三",
  "SERVER_PORT": 8080,
  "AI_CONFIGS": [
    {
      "name": "通义千问",
      "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "api_key": "sk-xxx",
      "model": "qwen-plus",
      "enabled": true
    }
  ],
  "WEB_SEARCH_CONFIG": {
    "enabled": true,
    "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "api_key": "sk-xxx",
    "model": "qwen3.5-flash"
  }
}
```

> 💡 **提示**：
> - AI 配置兼容任意 OpenAI 格式的 API，可自由切换不同模型。
> - `WEB_SEARCH_CONFIG` 为独立联网搜索配置，若 AI 选择的是通义千问，API Key 和模型会自动填充。
> - 不配置 `WEB_SEARCH_CONFIG` 时向后兼容，沿用 `DASHSCOPE_API_KEY` 旧字段。

### 2️⃣ 运行应用

```bash
# 获取 Flutter 依赖
flutter pub get

# --- Windows 桌面端 ---
# 自动构建 Kotlin 后端 Fat JAR + Flutter
.\build_package.ps1 -Target windows    # PowerShell
./build_package.sh -t windows          # Bash

# --- Android 手机端 ---
# Android 端自动直连 AI API，无需启动任何后端
.\build_package.ps1 -Target android    # PowerShell
./build_package.sh -t android          # Bash

# 或直接调试运行
flutter run
```

### 跨平台构建脚本

| 脚本 | 平台 | 用途 |
|------|------|------|
| `build_package.ps1` | Windows (PowerShell) | 一键构建 + JAR 打包 |
| `build_package.sh` | Linux / macOS (Bash) | 一键构建 + JAR 打包 |

```bash
# 所有支持的参数
./build_package.sh -t windows    # Windows 桌面
./build_package.sh -t linux      # Linux 桌面
./build_package.sh -t macos      # macOS 桌面
./build_package.sh -t android    # Android APK
./build_package.sh -t ios        # iOS (仅 macOS 宿主)
./build_package.sh -t desktop    # 所有桌面端
./build_package.sh -t all        # 全平台
```

---

## 📱 平台支持

| 功能 | 📱 Android | 🪟 Windows | 🐧 Linux | 🍎 macOS |
|------|:----------:|:----------:|:--------:|:--------:|
| 🤖 AI 聊天 | ✅ 直连 API | ✅ Kotlin 后端 | ✅ Kotlin 后端 | ✅ Kotlin 后端 |
| 📊 成绩查询 | ✅ 本地文件 | ✅ Kotlin 后端 | ✅ Kotlin 后端 | ✅ Kotlin 后端 |
| 📅 日程管理 | ✅ 本地文件 | ✅ Kotlin 后端 | ✅ Kotlin 后端 | ✅ Kotlin 后端 |
| � 学习分析 | ✅ 本地文件 | ✅ Kotlin 后端 | ✅ Kotlin 后端 | ✅ Kotlin 后端 |
| 📜 历史记录 | ✅ 本地文件 | ✅ Kotlin 后端 | ✅ Kotlin 后端 | ✅ Kotlin 后端 |
| 🔧 设置页 | ✅ | ✅ | ✅ | ✅ |

> Android 端采用**直连模式**，Flutter 直接调用 AI API 并操作本地文件，无需额外后端进程。

---

## 🛠️ 核心技术栈

| 层 | 技术 | 用途 | 状态 |
|----|------|------|:----:|
| **UI 框架** | Flutter / Dart | 跨平台用户界面 | 🟢 活跃 |
| **PC 后端** | Kotlin + Ktor | HTTP 服务、SSE 流式 AI 调用 | 🟢 活跃 |
| **原型参考** | Python + PySide6 | AI Agent 核心逻辑、工具链（历史存档） | 🔴 清除 |
| **AI 引擎** | DashScope / OpenAI API | 大语言模型推理 | 🟢 活跃 |
| **图像生成** | Stable Diffusion WebUI | 本地文生图 | 🟢 活跃 |
| **联网搜索** | 通义千问 (enable_search) | 实时网络信息 | 🟢 活跃 |
| **天气服务** | 高德地图 API | 实时天气查询 | 🟢 活跃 |
| **数据存储** | 本地 JSON 文件 | 成绩、对话记录、日程 | 🟢 活跃 |

---

## 🔌 工具系统

星火学伴内置了丰富的**工具调用（Tool Calling）** 系统，AI 可根据对话上下文自动选择合适的工具。工具系统最初在 Python 原型中设计和验证，现已由 Kotlin 后端完全实现。

| 工具 | 功能描述 | 所需 API | 实现 |
|------|---------|---------|:----:|
| `get_weather` | 查询实时天气 | 高德地图 | ☕ Kotlin |
| `image_recognition` | 多场景图像识别 | 百度智能云 | ☕ Kotlin |
| `task_organizer` | 生成待办清单 | — | ☕ Kotlin |
| `get_local_backlog` | 获取当前对话记录 | — | ☕ Kotlin / 📱 Dart |
| `backlog_read_range` | 按时间段查询历史 | — | ☕ Kotlin / 📱 Dart |
| `get_traffic` | 查询驾车路况 | 高德地图 | 🐍 Python 原型 |

---

## 📦 构建与打包

项目提供了一键构建脚本 `build_package.ps1`：

```powershell
# 构建 Windows 桌面版
.\build_package.ps1 -Target windows

# 构建 Android APK
.\build_package.ps1 -Target android

# 同时构建两个平台
.\build_package.ps1 -Target all
```

构建流程：
1. ✅ 编译 Kotlin 后端为 Fat JAR（Windows 需要）
2. ✅ 解析 `pubspec.yaml` 中的版本号
3. ✅ 执行 `flutter build` 打包目标平台
4. ✅ 将 Fat JAR 自动复制到输出目录

---

## 📜 对话记录系统

所有对话记录自动持久化，按日期和时间组织为 JSON 文件：

```
{BASE_PATH}/
└── Backlog/
    └── YYYY-MM-DD/
        └── HH-MM-SS.json
```

- 支持**单日查询**与**时间段范围查询**
- 支持**精确到小时**的时间筛选
- 支持**正序/倒序**排列
- 手机端直接读取本地文件，PC 端通过 Kotlin 后端 API

---

## 🧩 扩展开发

> 📌 Python 后端作为项目的**原型参考**，新增功能建议优先在 Kotlin 后端或 Flutter 前端实现。

### 添加新工具（Kotlin 后端）

工具逻辑实现在 `backend_kotlin/` 中，遵循 Ktor 路由模式：在对应 Service 中新增端点，Flutter 前端通过 Dio 调用。
---

## 📋 开发路线图

> 详见 `lib/TODO.md` 与 `lib/DONE.md`

| 阶段 | 内容 | 状态 |
|------|------|:----:|
| 🏁 基础架构 | 项目初始化、Python AI Agent | ✅ |
| 🏁 对话系统 | 多轮对话、Backlog 持久化 | ✅ |
| 🏁 工具链 | 天气/图像/搜索/待办工具 | ✅ |
| 🏁 前端 UI | Flutter 跨平台界面 | ✅ |
| 🏁 手机适配 | Android 直连模式、本地服务 | ✅ |
| 🔄 持续优化 | 性能、体验、稳定性 | ⏳ |

---

## 📄 许可证

本项目基于 **MIT** 许可证开源。

---

## 📬 更新日志

- **2026-05-29** — 新增了学习分析界面；接入本地/AI的OCR服务，现在可以上传附件；学习分析界面等待队友设计好关键词匹配度搜索；现在AI聊天可以尝试调用markdown格式和Latex公式格式。
- **2026-05-23** — 完成 Android 手机端完整适配（直连 AI + 本地成绩/日程/历史）
- **2026-05-21** — 将 Python 后端 重构为Kotlin后端，Flutter 前端上线
- **2026-05-17** — 完成 Flutter 前端的主要设计
- **2026-04-16** — PyQt (PySide6) 前端上线，支持聊天/成绩/日程三 Tab
- **2026-04-03** — 日程规划、图像识别、联网搜索功能上线
- **2026-03-29** — 对话记录管理系统、天气查询功能上线
- **2026-03-26** — 项目初始化，Python AI Agent 核心架构搭建


