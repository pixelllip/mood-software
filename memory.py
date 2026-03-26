from pathlib import Path
import json
import time
from datetime import datetime

class Backlog:
    def __init__(self,text=""):
        """### 定义路径对象"""
        self.base_path = Path(f"C:/Users/Administrator/Documents/Python/Software engineering/")
        self.path=self.base_path / f"Backlog/{time.strftime('%Y-%m-%d')}/{time.strftime('%H-%M-%S')}.json"
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

        # 遍历基础目录下所有的日期文件夹
        if not self.base_path.exists():
            return "目录不存在"

        for date_dir in self.base_path.iterdir():
            if date_dir.is_dir():
                try:
                    # 尝试将文件夹名解析为日期
                    current_dir_date = datetime.strptime(date_dir.name, '%Y-%m-%d').date()
                    
                    # 检查是否在范围内
                    if start <= current_dir_date <= end:
                        # 读取该文件夹下所有的 .json 文件
                        for json_file in date_dir.glob("*.json"):
                            with open(json_file, 'r', encoding='utf-8') as f:
                                results[f"{date_dir.name}/{json_file.name}"] = json.load(f)
                except ValueError:
                    # 跳过名称不符合日期格式的文件夹
                    continue
        
        return results