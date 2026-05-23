import json
import time
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()


class Backlog:
    def __init__(self, text=None):
        base_path = os.getenv("BASE_PATH", ".")
        self.base_path = Path(base_path)
        # 格式化路径以符合规范
        date_str = time.strftime('%Y-%m-%d')
        time_str = time.strftime('%H-%M-%S')
        self.path = self.base_path / f"Backlog/{date_str}/{time_str}.json"
        
        # 如果 text 为 None，则初始化为空列表
        if text is None:
            self.message = []
        else:
            self.message = text if isinstance(text, list) else []

    def append_user_text(self, text):
        """### 追加用户输入的文本"""
        self.message += [{
            "role": "user",
            "content": text
        }]

    def append_assistant_text(self, text):
        """### 追加助手回复的文本"""
        self.message += [{
            "role": "assistant",
            "content": text
        }]

    def get_text(self):
        """### 获取当前的对话文本"""
        return self.message

    def reset_path(self):
        """重置路径为当前时间（用于接续对话时更新文件时间）"""
        date_str = time.strftime('%Y-%m-%d')
        time_str = time.strftime('%H-%M-%S')
        self.path = self.base_path / f"Backlog/{date_str}/{time_str}.json"

    def write_text(self):
        """### 写入文本并生成摘要"""
        # 自动创建父目录（如果不存在）
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # 直接写入文本
        json_data = json.dumps(self.message, ensure_ascii=False, indent=4)
        self.path.write_text(json_data, encoding="utf-8")
        
        # 生成并保存摘要
        self._save_summary()

    def _save_summary(self):
        """生成对话摘要并保存到 meta 文件"""
        if not self.message:
            return
            
        try:
            # 简单提取用户第一句话的前 20 字作为摘要
            first_user_msg = next((m['content'] for m in self.message if m['role'] == 'user'), "")
            summary = first_user_msg[:20] if first_user_msg else "新对话"
            
            meta_path = self.path.with_suffix('.meta.json')
            meta_data = {"summary": summary}
            meta_path.write_text(json.dumps(meta_data, ensure_ascii=False), encoding="utf-8")
        except Exception as e:
            print(f"保存摘要失败: {e}")

    @staticmethod
    def _time_from_filename(filename):
        """从文件名 HH-MM-SS.json 中提取时间字符串 HH:MM"""
        try:
            name = filename.replace('.json', '')
            parts = name.split('-')
            if len(parts) >= 2:
                return f"{int(parts[0]):02d}:{int(parts[1]):02d}"
        except:
            pass
        return None

    def load_backlog(self, target_date, start_time=None, end_time=None):
        """
        ### 读取指定日期范围内的所有对话
        Args:
            target_date (str): 目标日期，格式为 'YYYY-MM-DD'
            start_time (str, optional): 起始时间 'HH:MM'，只返回该时间之后的记录
            end_time (str, optional): 结束时间 'HH:MM'，只返回该时间之前的记录
        Returns:
            包含所有符合条件对话的字典，键为文件名，值为包含 messages 和 summary 的对象
        """
        results = {}

        # 遍历 Backlog 目录下所有的日期文件夹
        backlog_path = Path(self.base_path).joinpath("Backlog", target_date)
        if not backlog_path.exists():
            return {}

        print(f"\n[读取 {target_date} 的对话记录]:")
        
        # 读取该文件夹下所有的 .json 文件
        for json_file in backlog_path.glob("*.json"):
            if json_file.suffix != '.json': continue
            # 跳过 meta 文件
            if json_file.name.endswith('.meta.json'): continue

            # 时间范围过滤
            if start_time or end_time:
                file_time = self._time_from_filename(json_file.name)
                if file_time:
                    if start_time and file_time < start_time:
                        continue
                    if end_time and file_time > end_time:
                        continue
            
            with open(json_file, 'r', encoding='utf-8') as f:
                try:
                    file_key = f"{backlog_path.name}/{json_file.name}"
                    raw_messages = json.load(f)
                    filtered_messages = [msg for msg in raw_messages if msg.get("role") != "system"]
                    
                    # 读取摘要
                    summary = ""
                    meta_file = json_file.with_suffix('.meta.json')
                    if meta_file.exists():
                        try:
                            meta_data = json.loads(meta_file.read_text(encoding='utf-8'))
                            summary = meta_data.get("summary", "")
                        except:
                            pass
                            
                    results[file_key] = {
                        "messages": filtered_messages,
                        "summary": summary
                    }
                    print(f"已读取: {file_key}")
                except Exception as e:
                    print(f"【错误】读取 {json_file} 失败: {e}")
        return results


class Instructions:
    def __init__(self):
        base_path = os.getenv("BASE_PATH", ".")
        self.base_path = Path(base_path)
        # 优先从 lib/ 查找 instructions.txt，因为用户说目前都在 lib/ 下
        lib_path = self.base_path / "lib" / "instructions.txt"
        root_path = self.base_path / "instructions.txt"
        
        if lib_path.exists():
            self.path = lib_path
        else:
            self.path = root_path
            
        self.content = self.load_instructions()

    def load_instructions(self):
        """从指定的 TXT 文件加载指令"""
        try:
            if not self.path.exists():
                print(f"警告：未找到指令文件 {self.path}")
                return ""
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
