from pathlib import Path
import json
import time
from datetime import datetime

class Backlog:
    def __init__(self,text=None):
        """### 定义路径对象"""
        self.base_path = Path(f"C:/Users/Administrator/Documents/Python/Software engineering/")
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

    def read_range(self, start_date, end_date):
        """
        ### 读取指定日期范围内的所有对话
        Args:
            start_date: 字符串格式 'YYYY-MM-DD'
            end_date: 字符串格式 'YYYY-MM-DD'
        Returns:
            包含所有符合条件对话的字典，键为文件名，值为内容
        """
        results = {}
        
        # 将输入字符串转为 date 对象方便比较
        start = datetime.strptime(start_date, '%Y-%m-%d').date()
        end = datetime.strptime(end_date, '%Y-%m-%d').date()

        # 遍历 Backlog 目录下所有的日期文件夹
        backlog_path = self.base_path / "Backlog"
        if not backlog_path.exists():
            return "Backlog 目录不存在"

        print(f"\n[读取 {start_date} 至 {end_date} 的对话记录]:")
        
        for date_dir in backlog_path.iterdir():
            if date_dir.is_dir():
                try:
                    # 尝试将文件夹名解析为日期
                    current_dir_date = datetime.strptime(date_dir.name, '%Y-%m-%d').date()
                    
                    # 检查是否在范围内
                    if start <= current_dir_date <= end:
                        # 读取该文件夹下所有的 .json 文件
                        for json_file in date_dir.glob("*.json"):
                            with open(json_file, 'r', encoding='utf-8') as f:
                                file_key=f"{date_dir.name}/{json_file.name}"
                                message = json.load(f)
                                results[file_key] = message
                                print(f"已读取: {file_key}")
                                for msg in message:
                                    print(f"  [{msg['role']}]: {msg['content']}")
                except ValueError:
                    # 跳过名称不符合日期格式的文件夹
                    continue
        
class Instructions:
    def __init__(self):
        self.base_path = Path(f"C:/Users/Administrator/Documents/Python/Software engineering/")
        self.path = self.base_path / "instructions.txt"
        self.content=self.load_instructions()

    def load_instructions(self):
        """从指定的 TXT 文件加载指令"""
        try:
            with open(self.path, 'r', encoding='utf-8') as f:
                instructions = f.read()
                print(f"已加载指令: {self.path}")
                return instructions
        except Exception as e:
            print(f"【错误】加载指令失败: {e}")
            return None

    def write_instructions(self, new_instructions):
        """将新的指令写入 TXT 文件"""
        try:
            with open(self.path, 'w', encoding='utf-8') as f:
                f.write(new_instructions)
                print(f"已更新指令: {self.path}")
        except Exception as e:
            print(f"【错误】写入指令失败: {e}")