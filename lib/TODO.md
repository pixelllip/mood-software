调试之前，如果动过kotlin源代码，请在终端执行：
cd backend_kotlin
./gradlew buildFatJar

升级AI功能：已完成 ✅
welcome page 和setting page 对于 AI API 配置已升级为：
- API提供方描述（名称）
- Base_URL
- 用户的API-KEY
- 刷新按钮：若 Base_URL 和 API Key 都填妥，联网请求 Base_URL/models 获取可用模型列表
- 在下方列表中展示模型，点击选择
- 选定模型后保存到 config.json

config.json 新增 AI_CONFIGS 数组，支持多个 AI 配置
每个配置项包含：name, base_url, api_key, model, enabled
用户通过 Radio 选择其中一项，"启用"的配置 enabled=true，其余为 false

后端（Kotlin/Python）均改为从 config.json 读取 AI_CONFIGS：
- 找到 enabled=true 的配置
- 使用其 base_url + "/chat/completions" 进行 API 调用（URL在AiAgent中已正确无需修改）
- 使用其 model 字段作为模型名
- 使用其 api_key 作为认证密钥

✅ IP定位功能已完成
在 backend/tools/tools.py 和 lib/Tools/tools.py 中添加了 Locate_IP 工具：
- 模型 Locate_IP(BaseModel)：参数 ip（可选），不传则自动查询当前公网IP位置
- 方法 locate_ip()：调用高德地图 API https://restapi.amap.com/v3/ip
- 返回 status、info、infocode、province、city、adcode、rectangle
- 已注册到 tool_list 并在 use_tool 中添加了调度分支

