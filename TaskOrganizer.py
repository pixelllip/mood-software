from openai import OpenAI
from dotenv import load_dotenv
import os
import json
import re

load_dotenv()

class TaskOrganizer:
    def __init__(self):
        # 获取 OPENAI_API_KEY 环境变量
        api_key = os.getenv('OPENAI_API_KEY')
        # 创建 OpenAI 客户端
        self.client = OpenAI(
            api_key=api_key,
            base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
        )

        # 初始化对话记录
        self.backlog = [
            {
                "role": "system",
                "content": """你是一个智能助手，帮助用户整理任务并生成待办清单。请用中文回答用户的问题。"""
            }
        ]

    def _create_response(self, user_input):
        """创建一个新的响应对象"""
        response = self.client.responses.create(
            model="qwen3.5-flash",
            input=self.backlog + [{"role": "user", "content": user_input}],
            stream=True,
            instructions="请帮助用户整理任务并生成待办清单。"
        )
        return response
    
    def remove_emojis(self, text):
        """去除字符串中的Emoji"""
        emoji_pattern = re.compile("["
                                   u"\U0001F600-\U0001F64F"  # 表情符号
                                   u"\U0001F300-\U0001F5FF"  # 符号和图标
                                   u"\U0001F680-\U0001F6FF"  # 运输和地图
                                   u"\U0001F700-\U0001F77F"  # 对象
                                   u"\U0001F780-\U0001F7FF"  # 符号
                                   u"\U0001F800-\U0001F8FF"  # 运输和地图补充
                                   u"\U0001F900-\U0001F9FF"  # 笑脸符号和其他表情
                                   u"\U0001FA00-\U0001FA6F"  # 补充符号和图标
                                   u"\U00002600-\U000026FF"  # 杂项符号
                                   u"\U00002700-\U000027BF"  # 方向指示器
                                   u"\U0001F1E6-\U0001F1FF"  # 国旗
                                   "]+", flags=re.UNICODE)
        return emoji_pattern.sub(r'', text)

    def _process_response(self, response):
        """处理响应事件（流式）"""
        initial_answer = ""
        for event in response:
            # 处理响应失败
            if event.type == 'response.failed':
                print(f"\n[响应失败: {event.response.error.message}]")
                break

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
                else:
                    tool_arguments = {}

                return tool_name, tool_arguments

        return "", {}

    def _use_tool(self, tool_name, tool_arguments):
        """根据工具名称调用对应的方法"""
        if tool_name == "task_organizer_tool":
            tasks = tool_arguments.get('tasks', [])
            self.agent_tools.task_organizer(tasks)
        elif tool_name == "get_local_backlog":
            backlog = tool_arguments.get('backlog', '')
            self.agent_tools.get_local_backlog(backlog)
        elif tool_name == "get_weather":
            adcode = tool_arguments.get('adcode', '')
            self.agent_tools.get_weather(adcode)
        elif tool_name == "backlog_read_range":
            start_date = tool_arguments.get('start_date', '')
            end_date = tool_arguments.get('end_date', '')
            self.agent_tools.backlog_read_range(start_date, end_date)
        elif tool_name == "run_script":
            script_path = tool_arguments.get('script_path', '')
            target_path = tool_arguments.get('target_path', '')
            self.agent_tools.run_script(script_path, target_path)
        elif tool_name == "text_to_image":
            arguments = tool_arguments
            self.agent_tools.text_to_image(arguments)
        else:
            print(f"\n[未知工具: {tool_name}]")

    def _generate_todo_list(self, tasks):
        """生成待办清单，按照早上、中午、晚上和自由安排分类"""
        morning_tasks = [task for task in tasks if '早上' in task]
        noon_tasks = [task for task in tasks if '中午' in task]
        evening_tasks = [task for task in tasks if '晚上' in task]
        free_tasks = [task for task in tasks if '早上' not in task and '中午' not in task and '晚上' not in task]

        todo_list = ""
        if morning_tasks:
            todo_list += "早上做什么：\n" + "\n".join([f"- {task.replace('早上', '').strip()}" for task in morning_tasks]) + "\n"
        if noon_tasks:
            todo_list += "中午做什么：\n" + "\n".join([f"- {task.replace('中午', '').strip()}" for task in noon_tasks]) + "\n"
        if evening_tasks:
            todo_list += "晚上做什么：\n" + "\n".join([f"- {task.replace('晚上', '').strip()}" for task in evening_tasks]) + "\n"
        if free_tasks:
            todo_list += "自由安排的事项：\n" + "\n".join([f"- {task}" for task in free_tasks])
        #需要用户在输入代办清单时，附带“早上”，“中午”或“晚上”标签，否则会将其归类为自由安排
        # 将待办清单写入txt文件
        with open("todo_list.txt", "w", encoding="utf-8") as file:
           file.write(todo_list)
        print("待办清单已保存到todo_list.txt文件中。")
        return todo_list

    def main(self):
        """主循环，持续获取用户输入并处理"""
        while True:
            # 获取用户输入
            input_text = input("请输入：")
            if input_text == "退出" or input_text == "" or input_text == "结束":
                break
            #处理空白输出与结束对话输入

            # 检查输入是否包含特定关键字
            if '早上' not in input_text and '中午' not in input_text and '晚上' not in input_text and '自由安排的事项' not in input_text:
                print("\n请输入与待办清单相关的内容。")
                print("\n**************\n")
                continue
            # 若输入包含特定关键字，则将其归类为待办事项，否则智能体将告诉用户输入有误

            self.backlog.append({"role": "user", "content": input_text})

            try:
                response = self._create_response(input_text)

                tool_name, tool_arguments = self._process_response(response)

                if tool_name:
                    self._use_tool(tool_name, tool_arguments)

            except Exception as e:
                print(f"\n[处理以下事件时出错: {e}]")
                continue

            print("\n**************\n")

if __name__ == '__main__':
    agent = TaskOrganizer()
    agent.main()

