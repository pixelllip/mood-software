from pathlib import Path
import json
import time
from datetime import datetime
from dotenv import load_dotenv
import os

load_dotenv()

class Backlog:
    def __init__(self,text=None):
        base_path = os.getenv("BASE_PATH")
        if not base_path:
            raise EnvironmentError("环境变量 BASE_PATH 未设置或为空")
        self.base_path = Path(base_path)
        self.path=self.base_path / f"Backlog/{time.strftime('%Y-%m-%d')}/{time.strftime('%H-%M-%S')}.json"
        # 如果 text 为 None，则初始化为空列表
        if text is None:
            self.message = []
        else:
            self.message = text if isinstance(text, list) else []

    def append_user_text(self,text):
        """### 追加用户输入的文本"""
        self.message += [{
            "role": "user",
            "content": text
        }]

    def append_assistant_text(self,text):
        """### 追加助手回复的文本"""
        self.message += [{
            "role": "assistant",
            "content": text
        }]

    def get_text(self):
        """### 获取当前的对话文本"""
        return self.message

    def write_text(self):
        """### 写入文本"""
        # 自动创建父目录（如果不存在）
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # 直接写入文本
        json_data = json.dumps(self.message, ensure_ascii=False, indent=4)
        self.path.write_text(json_data, encoding="utf-8")

    def load_backlog(self, target_date):
        """
        ### 读取指定日期范围内的所有对话
        Args:
            target_date (str): 目标日期，格式为 'YYYY-MM-DD'
        Returns:
            包含所有符合条件对话的字典，键为文件名，值为内容
        """
        results = {}

        # 遍历 Backlog 目录下所有的日期文件夹
        backlog_path = Path(self.base_path).joinpath("Backlog", target_date)
        if not backlog_path.exists():
            return "Backlog 不存在"

        print(f"\n[读取 {target_date} 的对话记录]:")
        
        # 读取该文件夹下所有的 .json 文件
        for json_file in backlog_path.glob("*.json"):
            with open(json_file, 'r', encoding='utf-8') as f:
                try:
                    file_key=f"{backlog_path.name}/{json_file.name}"
                    raw_messages = json.load(f)
                    filtered_messages = [msg for msg in raw_messages if msg.get("role") != "system"]
                    results[file_key] = filtered_messages
                    print(f"已读取: {file_key}")
                    for msg in filtered_messages:
                        print(f"  [{msg['role']}]: {msg['content']}")
                except Exception as e:
                    print(f"【错误】读取 {json_file} 失败: {e}")
        return results
        
class Instructions:
    def __init__(self):
        # 1. 尝试从 BASE_PATH 获取（用户自定义）
        base_path_str = os.getenv("BASE_PATH")
        self.path = None
        
        if base_path_str:
            target_path = Path(base_path_str) / "instructions.txt"
            if target_path.exists():
                self.path = target_path

        # 2. 如果 BASE_PATH 下没有，尝试从当前脚本所在目录获取（默认指引）
        if not self.path:
            local_path = Path(__file__).parent / "instructions.txt"
            if local_path.exists():
                self.path = local_path
            else:
                # 如果还是没有，回退到 BASE_PATH 路径（即使不存在，也保留该路径用于后续写入）
                if base_path_str:
                    self.path = Path(base_path_str) / "instructions.txt"
                else:
                    self.path = local_path

        self.content = self.load_instructions()

    def load_instructions(self):
        """从指定的 TXT 文件加载指令"""
        if not self.path or not self.path.exists():
            print(f"【提醒】未找到指引文件，将使用空指引。")
            return ""
            
        try:
            with open(self.path, 'r', encoding='utf-8') as f:
                instructions = f.read()
                print(f"已加载指引: {self.path}")
                return instructions
        except Exception as e:
            print(f"【错误】加载指引失败: {e}")
            return ""

    def write_instructions(self, new_instructions):
        """将新的指令写入 TXT 文件"""
        if not self.path:
            print("【错误】未定义指引保存路径")
            return

        try:
            # 确保父目录存在
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.path, 'w', encoding='utf-8') as f:
                f.write(new_instructions)
                print(f"已更新指引: {self.path}")
            self.content = new_instructions # 更新内存中的内容
        except Exception as e:
            print(f"【错误】写入指引失败: {e}")
