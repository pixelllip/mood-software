from openai import OpenAI
from dotenv import load_dotenv
from memory import Backlog, Instructions
from tools import AgentTools
import time
import os
import json
import os
import re

load_dotenv()

class AI_Agent:
    def __init__(self):
        # 加载OpenAI API，这里使用千问服务
        load_dotenv()
        # 获取 OPENAI_API_KEY 环境变量
        api_key = os.getenv('OPENAI_API_KEY')
        # 创建 OpenAI 客户端
        self.client = OpenAI(
            api_key=api_key,
            base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
        )

        # 初始化对话记录
        self.backlog = Backlog([
            {
                "role": "system",
                "content": """你是一个智能助手，帮助用户整理任务并生成待办清单。请用中文回答我的问题。"""
            }
        ])

        # 初始化工具
        self.tool = AgentTools()

        # 初始化给AI看的指引
        self.instructions = Instructions()

    def _create_response(self):
        """创建一个新的响应对象"""
        response = self.client.responses.create(
            model="qwen3.5-flash",
            input=self.backlog.message,
            stream=True,
            tools=self.tool.tool_list,  # type: ignore
            tool_choice="auto",
            instructions=self.instructions.content if self.instructions.content else ""
        )  # type: ignore
        return response

    def _process_response(self, response, final=False):
        """处理响应事件（流式）"""
        initial_answer = ""
        tool_name = ""
        tool_arguments = {}
        thinking = 0
        for event in response:
            # 处理响应失败
            if event.type == 'response.failed':
                print(f"\n[响应失败: {event.response.error.message}]")
                break

            # 处理思考过程
            elif event.type == 'response.reasoning_summary_text.delta' and not final:
                if thinking == 0:
                    print(f"思考中: {event.delta}", end="", flush=True)
                    thinking = 1
                else:
                    print(f"{event.delta}", end="", flush=True)
            elif event.type == 'response.reasoning_summary_text.done':
                print("\n")

            # 处理回答内容
            elif event.type == 'response.output_text.delta':
                print(event.delta, end="", flush=True)
                initial_answer += event.delta

            # 处理工具调用
            elif event.type == 'response.function_call_arguments.done':
                tool_name = event.name.strip()
                print(f"\n[工具调用: {tool_name}]\n")

                # 解析工具参数
                raw_args = getattr(event, 'arguments', None)
                if raw_args:
                    try:
                        # 解析 JSON 字符串 -> Python 字典
                        tool_arguments = json.loads(raw_args)
                        print(f"[解析参数]: {tool_arguments}")
                    except (json.JSONDecodeError, TypeError) as e:
                        print(f"[参数解析错误]: {raw_args} | {e}")
               

            time.sleep(0.01)


        return initial_answer, tool_name, tool_arguments

    def _use_tool(self, tool_name, arguments=None):
        """根据工具名称调用对应的方法"""
        if tool_name == "":
            return

        # 处理传入工具名和参数
        tool_name = tool_name.strip()
        if not arguments:
            arguments = {}

        if tool_name == "get_local_backlog":
            self.tool.get_local_backlog(self.backlog)
        elif tool_name == "get_weather":
            info = self.tool.get_weather(**arguments)
            final_response = self.client.responses.create(
                model="qwen3.5-flash",
                input=[{
                    "role": "system",
                    "content": f"以下是根据工具获取的信息：{info}。请基于这些信息回答用户的问题。"
                }],
                stream=True
            )
            self._process_response(final_response, final=True)
        elif tool_name == "backlog_read_range":
            self.tool.backlog_read_range(self.backlog, **arguments)
        elif tool_name == "run_script":
            self.tool.run_script(**arguments)
        elif tool_name == "text_to_image":
            image = self.tool.text_to_image(arguments)
            if image:
                print(f"成功生成图片。")
            else:
                print("未能生成图片。")
        elif tool_name == "task_organizer_tool":
            tasks = arguments.get('tasks', [])
            self.tool.task_organizer(tasks)
        else:
            print(f"\n[未知工具: {tool_name}]")

        return f"\n已调用工具: {tool_name}"

    def main(self):
        """主循环，持续获取用户输入并处理"""
        while True:
            # 获取用户输入
            input_text = input("请输入：")
            if input_text == "退出" or input_text == "":
                break

            self.backlog.append_user_text(input_text)

            try:
                response = self._create_response()

                initial_answer, tool_name, tool_arguments = self._process_response(response)

                if tool_name:
                    result = self._use_tool(tool_name, tool_arguments)
                    print(f"\n工具执行结果：{result}")

                self.backlog.append_assistant_text(initial_answer)

            except Exception as e:
                print(f"\n[处理以下事件时出错: {e}]")
                continue

            print("\n**************\n")

        # 退出循环后，将对话记录写入文件
        self.backlog.write_text()

if __name__ == '__main__':
    agent = AI_Agent()
    agent.main()
