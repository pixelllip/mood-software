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
        system_prompt = (
            "你是一个功能强大的智能助手。你有权调用各种工具来帮助用户，"
            "例如查询天气（get_weather）、生成图片（text_to_image）、搜索网页（qwen_websearch）等。"
            "当用户的问题需要实时信息或特定功能时，请务必先调用对应的工具。"
            "请用中文回答。"
        )
        messages = [
            {"role": "system", "content": system_prompt}
        ]
        if self.instructions.content:
            messages.insert(0, {"role": "system", "content": self.instructions.content})
        
        messages.extend(self.backlog.message)

        response = self.client.chat.completions.create(
            model="qwen-plus",
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

    def stream_chat(self, user_input: str):
        self.backlog.append_user_text(user_input)
        
        system_prompt = (
            "你是一个集成了一系列本地和线上工具的超级助理。你的名字是星火学伴 AI。\n"
            "【核心规则】：\n"
            "1. 当用户询问天气、路况、搜索信息、识别图片、生成图片等需求时，必须直接调用对应的工具，不要回复说你做不到。\n"
            "2. 如果工具调用需要参数（如城市名），请从用户对话中提取。\n"
            "3. 你的回答应当简洁、友好且有用。\n"
            "【当前可用工具】：get_weather, get_traffic, text_to_image, qwen_websearch, image_recognition"
        )
        
        messages = [{"role": "system", "content": system_prompt}]
        if self.instructions.content:
            messages.append({"role": "system", "content": self.instructions.content})
        messages.extend(self.backlog.message)

        # 发起带工具的流式请求
        response = self.client.chat.completions.create(
            model="qwen-plus",
            messages=messages,
            tools=self.tool.tool_list,
            tool_choice="auto",
            stream=True
        )

        full_reply = ""
        tool_calls = []
        
        for chunk in response:
            delta = chunk.choices[0].delta
            
            # 处理文本内容
            if delta.content:
                full_reply += delta.content
                yield delta.content
            
            # 收集工具调用信息 (流式中工具调用是分片返回的)
            if delta.tool_calls:
                for tc_delta in delta.tool_calls:
                    if len(tool_calls) <= tc_delta.index:
                        tool_calls.append({
                            "id": tc_delta.id,
                            "name": tc_delta.function.name,
                            "arguments": ""
                        })
                    if tc_delta.function.arguments:
                        tool_calls[tc_delta.index]["arguments"] += tc_delta.function.arguments

        # 如果有工具调用，执行它们并获取最终结果
        if tool_calls:
            messages.append({
                "role": "assistant",
                "content": full_reply,
                "tool_calls": [
                    {
                        "id": tc["id"],
                        "type": "function",
                        "function": {"name": tc["name"], "arguments": tc["arguments"]}
                    } for tc in tool_calls
                ]
            })
            
            for tc in tool_calls:
                tool_result = self.use_tool(tc["name"], json.loads(tc["arguments"]))
                messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "name": tc["name"],
                    "content": str(tool_result)
                })
            
            # 执行完工具后，再次流式调用以汇总结果
            final_stream = self.client.chat.completions.create(
                model="qwen-plus",
                messages=messages,
                stream=True
            )
            
            for chunk in final_stream:
                content = chunk.choices[0].delta.content
                if content:
                    full_reply += content
                    yield content

        # 保存历史
        if full_reply:
            self.backlog.append_assistant_text(full_reply)
            self.backlog.write_text()

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
