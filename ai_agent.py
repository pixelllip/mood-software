from openai import OpenAI
from dotenv import load_dotenv
from memory import Backlog
from tools import AgentTools
import time

load_dotenv()
class AI_Agent:
    def __init__(self):# 加载OpenAI API，这里使用千问服务
        self.client=OpenAI(
            base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
        )

        # 初始化对话记录
        self.backlog=Backlog([
            {
                "role": "system",
                "content": """你是我的人工智能助手，协助我解答问题，提供信息，完成任务。请用中文回答我的问题。
                            请严格按照以下格式回答问题："""
            }
        ])

        # 初始化工具
        self.tool=AgentTools()

    def main(self):
        while(True):
            # 获取用户输入
            input_text = input("请输入：")
            if(input_text == "退出" or input_text == ""):
                break
            
            self.backlog.append_user_text(input_text)

            #try:
            response=self.client.responses.create(

                model="qwen3.5-flash",
                input=self.backlog.get_text(),
                #开启流式输出
                stream=True,
                #工具调用配置
                tools=self.tool.tools,
                tool_choice="auto"
            )

            # 处理流式输出
            initial_answer=""
            tool_name=""
            for event in response:
                if event.type == 'response.failed':
                    print(f"\n[响应失败: {event.response.error.message}]")
                    break
                if event.type == 'response.output_text.delta':
                    print(event.delta, end="", flush=True)
                    initial_answer+=event.delta
                    time.sleep(0.02)
                if(event.type == 'response.function_call_arguments.done'):
                    tool_name=event.name.strip()
                    print(f"\n[工具调用: {tool_name}]\n")
                    
            result=self._use_tool(tool_name)
            self.backlog.append_assistant_text(initial_answer)
            
            """except Exception as e:
                print(f"\n[处理以下事件时出错: {e}]")
                continue"""

            print("\n\n**************\n")
            
            """如果你想看思考过程：
            elif event.type == 'response.reasoning_summary_text.delta':
                print(f"[思考中: {event.delta}]\n", end="", flush=True)"""
            
        # 退出循环后，将对话记录写入文件
        self.backlog.write_text()

    def _use_tool(self,toolname):
        pass
    

if __name__ == '__main__':
    agent = AI_Agent()
    agent.main()
