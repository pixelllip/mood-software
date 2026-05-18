import json
import os
from openai import OpenAI
from dotenv import load_dotenv

# 使用绝对路径导入，确保在 backend 目录下运行时正常
# 如果 IDE 仍然报错，请在 IDE 中将 backend 文件夹标记为 "Sources Root"
try:
    from core.memory import Backlog, Instructions
    from tools.tools import AgentTools
except ImportError:
    # 兼容性导入
    from .memory import Backlog, Instructions
    from ..tools.tools import AgentTools

load_dotenv()

class AiAgent:
    def __init__(self):
        api_key = os.getenv('OPENAI_API_KEY')
        self.client = OpenAI(
            api_key=api_key,
            base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
        )
        self.backlog = Backlog()
        self.tool = AgentTools()
        self.instructions = Instructions()

    def chat(self, user_input: str):
        self.backlog.append_user_text(user_input)
        
        # 构建消息列表
        messages = [
            {"role": "system", "content": "你是一个智能助手，帮助用户整理任务并生成待办清单。请用中文回答我的问题。"}
        ]
        if self.instructions.content:
            messages.insert(0, {"role": "system", "content": self.instructions.content})
        
        messages.extend(self.backlog.message)

        response = self.client.chat.completions.create(
            model="qwen-plus",  # 修正为通用模型名
            messages=messages,
            tools=self.tool.tool_list,
            tool_choice="auto"
        )

        assistant_message = response.choices[0].message
        
        if assistant_message.tool_calls:
            # 简单处理第一个工具调用
            tool_call = assistant_message.tool_calls[0]
            tool_name = tool_call.function.name
            arguments = json.loads(tool_call.function.arguments)
            
            # 执行工具
            tool_result = self.use_tool(tool_name, arguments)
            
            # 再次调用模型获取最终回答
            messages.append(assistant_message)
            messages.append({
                "role": "tool",
                "tool_call_id": tool_call.id,
                "name": tool_name,
                "content": str(tool_result)
            })
            
            final_response = self.client.chat.completions.create(
                model="qwen-plus",
                messages=messages
            )
            reply = final_response.choices[0].message.content
        else:
            reply = assistant_message.content

        self.backlog.append_assistant_text(reply)
        self.backlog.write_text()
        return reply

    def use_tool(self, tool_name, arguments=None):
        if not arguments:
            arguments = {}
        
        if tool_name == "get_local_backlog":
            return self.backlog.get_text()
        elif tool_name == "get_weather":
            return self.tool.get_weather(**arguments)
        elif tool_name == "get_traffic":
            return self.tool.get_traffic(**arguments)
        elif tool_name == "load_backlog":
            return self.tool.load_backlog(self.backlog, **arguments)
        elif tool_name == "run_script":
            return self.tool.run_script(**arguments)
        elif tool_name == "text_to_image":
            return self.tool.text_to_image(arguments)
        elif tool_name == "task_organizer_tool":
            return self.tool.task_organizer(arguments.get('tasks', []))
        elif tool_name == "image_recognition":
            return self.tool.image_recognition(**arguments)
        elif tool_name == "qwen_websearch":
            return self.tool.qwen_websearch(**arguments)
        return "未知工具"
