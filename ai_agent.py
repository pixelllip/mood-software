from openai import OpenAI
from dotenv import load_dotenv
from memory import Backlog, Instructions
from Tools.tools import AgentTools
from event_handle import MySignal
from PySide6.QtCore import QThread
import time
import sys
import os
import json
import os

load_dotenv()

class AI_Agent(QThread):
    def __init__(self):
        super().__init__()
        self.signal = MySignal()  # 创建MySignal实例作为AI_Agent的属性

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
        self.backlog = Backlog()

        # 初始化工具
        self.tool = AgentTools()

        # 初始化给AI看的指引
        self.instructions = Instructions()

        self.current_text = ""  # 用于存放本次要处理的文本
        
    def set_input(self, text):
        """由外部调用，设置本次对话的输入"""
        self.current_text = text

    def _create_response(self):
        """创建一个新的响应对象"""
        response = self.client.responses.create(
            model="qwen3.5-flash",
            input=self.backlog.message+[
                {
                    "role": "system",
                    "content": """你是一个智能助手，帮助用户整理任务并生成待办清单。请用中文回答我的问题。"""
                }
            ],
            stream=True,
            tools=self.tool.tool_list,  # type: ignore
            tool_choice="auto",
            instructions=self.instructions.content if self.instructions.content else ""
        )  # type: ignore
        return response

    def process_response(self, response, final=False):
        """处理响应事件（流式）"""
        initial_answer = ""
        tool_name = ""
        tool_arguments = {}
        thinking = False
        for event in response:
            # 处理响应失败
            if event.type == 'response.failed':
                print(f"\n[响应失败: {event.response.error.message}]")
                break

            # 处理思考过程
            elif event.type == 'response.reasoning_summary_text.delta' and not final:
                self.current_text = event.delta.strip()
                if thinking == False:
                    print(f"思考中: {self.current_text}", end="", flush=True)
                    self.signal.text_output.emit(f"思考中: {self.current_text}")  # 发射信号更新UI
                    thinking = True
                else:
                    print(f"{event.delta}", end="", flush=True)
                    self.signal.text_output.emit(f"{event.delta}")  
            elif event.type == 'response.reasoning_summary_text.done':
                print("\n")
                self.signal.text_output.emit("\n")

            # 处理回答内容
            elif event.type == 'response.output_text.delta':
                self.current_text = event.delta.strip()
                print(self.current_text, end="", flush=True)
                self.signal.text_output.emit(f"{self.current_text}")  # 发射信号更新UI
                initial_answer += self.current_text

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

    def use_tool(self, tool_name, arguments=None):
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
            self.process_response(final_response, final=True)
        elif tool_name == "load_backlog":
            self.tool.load_backlog(self.backlog, **arguments)
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
        elif tool_name == "image_recognition":
            result = self.tool.image_recognition(**arguments)
            if result:
                final_response=self.client.responses.create(
                    model="qwen3.5-flash",
                    input=[
                        {"role": "system", "content": f"""工具识别logo信息：{result}。
                         用一句自然的话描述图片内容。"""},
                        {"role": "user", "content": "描述这张图片"}
                    ],
                    stream=True,
                )
                self.process_response(final_response, final=True)
        elif tool_name == "qwen_websearch":
                self.tool.qwen_websearch(**arguments)
        else:
            print(f"\n[未知工具: {tool_name}]")

        
        return f"\n已调用工具: {tool_name}"

    def run(self):
        """重写 QThread里的run 方法：当 UI 调用 agent.start() 时，此处的代码会自动在子线程执行"""
        input_text = self.current_text.strip()
        if not input_text:
            return

        self.backlog.append_user_text(input_text)

        try:
            # 获取流式响应
            response = self._create_response()

            # 处理响应并在内部发射信号
            initial_answer, tool_name, tool_arguments = self.process_response(response)

            if tool_name:
                result = self.use_tool(tool_name, tool_arguments)
                print(f"\n工具执行结果：{result}") # 也可以发射信号告知UI工具在运行

            self.backlog.append_assistant_text(initial_answer)

        except Exception as e:
            print(f"\n[线程执行出错: {e}]")
            self.signal.text_output.emit(f"\n系统错误: {str(e)}")
        finally:
            self.backlog.write_text()
            self.signal.is_finished.emit()  # ✅ 完成后发射信号通知 UI 恢复按钮

    def check_api_key(self):
        openai_api_key=os.getenv("OPENAI_API_KEY")
        base_path=os.getenv("BASE_PATH")
        if not openai_api_key or openai_api_key=="":
            print("""请先在软件目录创建.env文件，然后在其中填入必须的信息：\n
                  OPENAI_API_KEY=*你的支持OPENAI API的密钥；""")
            self.signal.error.emit("""请先在软件目录创建.env文件，然后在其中填入：\nOPENAI_API_KEY=*你的OPENAI API的密钥*""")
        if not base_path or base_path=="":
            print("""请先在软件目录创建.env文件，然后在其中填入: BASE_PATH=*你希望将生成的文件放置于何处*""")
            self.signal.error.emit("""请先在软件目录创建.env文件，然后在其中填入: \nBASE_PATH=*你希望将生成的文件放置于何处*""")
            return False

if __name__ == '__main__':
    agent = AI_Agent()
    while True:   
        user_input = input("请输入内容（输入'退出'结束对话）：") 
        if user_input.strip() == "退出" or user_input.strip() == "":
            print("对话结束。")
            break
        agent.set_input(user_input)
        agent.run() # 直接在主线程运行