from openai import OpenAI
from dotenv import load_dotenv
from memory import Backlog
import time

load_dotenv()
def main():
    # 加载OpenAI API，这里使用千问服务
    client=OpenAI(
        base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
    )

    # 初始化对话记录
    backlog=Backlog([
        {
            "role": "system",
            "content": "你是我的人工智能助手，协助我解答问题，提供信息，完成任务。请用中文回答我的问题。"
        }
    ])

    while(True):
        # 获取用户输入
        input_text = input("请输入：")
        if(input_text == "退出" or input_text == ""):
            break
        
        backlog.append_user_text(input_text)

        response=client.responses.create(
            
            model="qwen3.5-flash",
            input=backlog.get_text(),
            #开启流式输出
            stream=True,
        )

        # 处理流式输出
        content=""
        for event in response:
            if event.type== 'response.output_text.delta':
                print(event.delta, end="", flush=True)
                content+=event.delta
                time.sleep(0.02)
        backlog.append_assistant_text(content)
        
        print("\n\n**************\n")
        
        """如果你想看思考过程：
        elif event.type == 'response.reasoning_summary_text.delta':
            print(f"[思考中: {event.delta}]\n", end="", flush=True)"""
        
    # 退出循环后，将对话记录写入文件
    backlog.write_text()

if __name__ == '__main__':
    main()
