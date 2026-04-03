# AI-Agent

一个功能完整的 AI 智能助手系统，集成了大语言模型、本地图像生成、图像识别、联网搜索、对话记录管理等多项功能。

## 项目概述

本项目采用模块化架构，分为三个核心板块：**AI 代理**、**工具集**和**内存管理**。通过这些模块的协作，实现了一个智能的、可扩展的 AI 助手系统，支持文本对话、图像生成与识别、实时搜索等多种功能。

## 项目特性

- **AI 对话引擎**：基于阿里千问 API，支持多轮对话和上下文理解
- **本地图像生成**：集成 Stable Diffusion WebUI，支持文本到图像的本地生成
- **图像识别**：集成百度智能云，支持多场景图像识别（车型、菜品、动物、植物等）
- **联网搜索**：集成通义千问联网搜索，提供实时网络信息查询
- **工具扩展系统**：模块化工具设计，支持天气查询、脚本执行、对话记录管理、待办清单生成等
- **对话记录持久化**：自动保存对话历史，支持时间范围查询
- **指令管理系统**：灵活的系统指令加载和更新

## 核心模块

### 1. `ai_agent.py` - AI 代理核心
- **功能**：对接大语言模型（阿里千问），处理用户输入并生成智能回复
- **特点**：
  - 支持多轮对话，维持对话上下文
  - 集成工具调用能力（Tool Calling）
  - 自动保存对话记录
  - 支持自定义系统指令

### 2. `tools.py` - 工具集合
提供多个实用工具：

| 工具名 | 功能 | 参数 |
|------|------|------|
| `text_to_image` | 文本生成图片（调用本地 SD WebUI） | prompt, negative_prompt, width, height, steps, guidance_scale, seed |
| `get_weather` | 获取实时天气信息 | adcode（城市编码） |
| `get_local_backlog` | 获取当前对话记录 | backlog 对象 |
| `backlog_read_range` | 查询日期范围内的对话 | start_date, end_date |
| `run_script` | 执行本地脚本（Python/BAT） | script_path, target_path |
| `image_recognition` | 多场景图像识别（车型、菜品、动物等） | image_path, scene |
| `qwen_websearch` | 通义千问联网搜索问答 | query |
| `task_organizer` | 生成格式化的待办清单 | tasks |

### 3. `memory.py` - 对话记录与指令管理

#### `Backlog` 类
- **用途**：管理对话历史记录
- **功能**：
  - 记录用户和助手的所有对话
  - 自动按日期和时间戳组织文件
  - 支持追加新消息
  - 支持时间范围查询
  - JSON 格式持久化存储

#### `Instructions` 类
- **用途**：管理系统指令
- **功能**：
  - 加载外部指令文件
  - 动态更新系统提示词

## 项目结构

```
Software engineering/
├── ai_agent.py              # AI 代理主程序
├── tools.py                 # 工具集合
├── memory.py                # 对话记录与指令管理
├── instructions.txt         # 系统指令文件
├── README.md                # 项目文档
├── .env                      # 环境变量配置
└── Backlog/                 # 对话记录存储
    └── YYYY-MM-DD/
        └── HH-MM-SS.json
```

## 使用前准备

### 环境变量配置 (`.env` 文件)
```
# 【必需】AI 对话引擎
OPENAI_API_KEY=your_api_key          # 支持 OpenAI API 的密钥，可以是阿里千问 API 密钥
                                     # 申请地址：https://dashscope.aliyuncs.com

# 【必需】项目基础路径
BASE_PATH=c:/path/to/project         # 项目基础路径，用于存储对话记录和指令文件

# 【可选】高德地图 API - 用于 get_weather 工具获取实时天气
Gaode_API_Key=your_gaode_api_key     # 高德地图 API 密钥
                                     # 申请地址：https://lbs.amap.com/

# 【可选】百度智能云 API - 用于 image_recognition 工具进行图像识别
BAIDU_API_KEY=your_baidu_api_key                    # 百度 API 密钥
BAIDU_SECRET_KEY=your_baidu_secret_key              # 百度 Secret 密钥
                                                   # 申请地址：https://cloud.baidu.com/product/imagerecognition

# 【可选】阿里云 DashScope API - 用于 qwen_websearch 工具进行联网搜索
DASHSCOPE_API_KEY=your_dashscope_api_key            # 通义千问 API 密钥
                                                   # 申请地址：https://dashscope.aliyuncs.com
```

### 依赖安装
```bash
pip install openai python-dotenv requests pillow
```

### 启动 SD WebUI（如需使用图片生成功能）
```bash
cd d:\stable-diffusion-webui
python webui.py --api
```

## 工作流程

```
用户输入
   ↓
AI Agent 接收
   ↓
调用 LLM 推理
   ↓
判断是否需要调用工具
   ├─ 是 → 执行工具 → 获取结果
   └─ 否 → 直接回复
   ↓
保存对话记录到 Backlog
   ↓
返回结果给用户
```

## 快速开始

```python
from ai_agent import AI_Agent

# 创建 AI 代理实例
agent = AI_Agent()

# 与 AI 对话
response = agent.chat("帮我生成一个关于春天的图片")

# 查看生成的图片（保存在 Generated Images 文件夹）
```

## 对话记录查询

如果程序正常退出（输入退出/空内容），所有对话将自动保存在 `Backlog/` 目录下，按日期和时间组织：
- 每天一个文件夹：`YYYY-MM-DD`
- 每次对话一个文件：`HH-MM-SS.json`

使用 `backlog_read_range` 工具可查询指定时间范围的对话记录。

## 功能扩展

### 添加新工具

在 `tools.py` 中：

1. **定义工具模型**（Pydantic）
```python
class New_Tool(BaseModel):
    """工具描述"""
    param1: str = Field(..., description="参数说明")
```

2. **实现工具方法**
```python
def new_tool(self, arguments: Dict[str, Any]):
    """具体实现"""
    pass
```

3. **注册到工具列表**
```python
self.tool_list = build_tools_list([..., New_Tool])
```

## 许可证

MIT

## 更新日志

- **2026-04-03**：日程规划功能、图文识别功能、联网搜索功能陆续上线
- **2026-03-30**：完成本地 SD WebUI 调用，图片生成功能上线
- **2026-03-29**：完成对话记录管理系统，查询天气功能上线
- **2026-03-26**：初始化项目架构


