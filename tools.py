import memory
from typing import Type,List,TypedDict,Dict,Any
from pydantic import BaseModel,Field
from dotenv import load_dotenv
import subprocess
import requests
import os

load_dotenv()
Gaode_API_Key = os.getenv("Gaode_API_Key")

class AgentTools:
    
    def __init__(self):
        self.tool_list = build_tools_list([Get_Local_Backlog, Get_Weather, Backlog_Read_Range, Run_Script])
    
    def get_local_backlog(self, backlog: memory.Backlog):
        """获取对话记录"""
        print(backlog.get_text())

    def get_weather(self, adcode: str):
        """获取天气信息"""
        if not adcode:
            print(f"没有提供城市编码，无法获取天气信息。")
        else:
            url = f"https://restapi.amap.com/v3/weather/weatherInfo?city={adcode}&key={Gaode_API_Key}"
            result = requests.get(url).json()
            return result

    def backlog_read_range(self, backlog: memory.Backlog, start_date: str, end_date: str):
        """读取指定日期范围内的对话记录"""
        results = backlog.read_range(start_date, end_date)
        print(results)

    def run_script(self, script_path: str, target_path: str):
        """运行指定的脚本文件（支持 Python 和 BAT）"""
        
        # 1. 路径预处理：自动转为绝对路径，并统一斜杠方向（解决转义和格式问题）
        script_path = os.path.abspath(os.path.normpath(script_path))
        target_path = os.path.abspath(os.path.normpath(target_path))

        # 2. 检查文件是否存在（这里报错通常是因为简繁体不匹配或路径真的写错了）
        if not os.path.isfile(script_path):
            print(f"【错误】脚本不存在: {script_path}")
            # 打印一下文件夹内容，方便排查是否是简繁体问题
            parent = os.path.dirname(script_path)
            if os.path.exists(parent):
                print(f"该目录下文件有: {os.listdir(parent)}")
            return
        
        if not os.path.isfile(target_path):
            print(f"【错误】目标文件不存在: {target_path}")
            return

        # 获取脚本后缀
        _, ext = os.path.splitext(script_path.lower())

        # 3. 运行命令，支持 BAT/CMD 和 Python 脚本
        try:
            if ext in ['.bat', '.cmd']:
                # 终端执行方式：脚本后面跟目标路径
                # .bat/.cmd 在 Windows 上必须通过 cmd.exe 来执行
                cmd = f'"{script_path}" "{target_path}"'
                print(f"[INFO] 执行命令: {cmd}")
                result = subprocess.run(cmd, shell=True, check=True)
            elif ext == '.py':
                # Python 脚本
                import sys
                cmd = [sys.executable, script_path, target_path]
                print(f"[INFO] 执行命令: {cmd}")
                result = subprocess.run(cmd, shell=False, check=True)
            else:
                print(f"【错误】不支持的脚本类型: {ext}")
                return

            print(f"[INFO] 运行完成，返回码: {result.returncode}")
            return result.returncode
        except subprocess.CalledProcessError as exc:
            print(f"【错误】脚本执行失败，返回码: {exc.returncode}")
            return exc.returncode
        except Exception as exc:
            print(f"【错误】脚本执行异常: {exc}")
            return -1


# 1. 定义工具字典结构
class CustomToolDict(TypedDict):
    type: str
    name: str
    description: str       # 工具本身的功能描述
    parameters: Dict[str, Any] # 参数的 JSON Schema

# 2. 定义模型 (使用类文档字符串描述工具，Field 描述描述参数)
class Get_Local_Backlog(BaseModel):
    """获取当前的历史对话记录"""  # <--- 这里写工具的功能描述
    backlog: str = Field(..., description="需要查询的 Backlog 对象") # <--- 这里写参数的具体含义

class Get_Weather(BaseModel):
    """获取指定地区的实时天气信息""" # <--- 这里写工具的功能描述
    adcode: str = Field(..., description="中国城市编码") # <--- 这里写参数的具体含义
    # 为了演示区别，我稍微修改了字段名，如果你必须用 content 也可以，只要描述不同即可

class Backlog_Read_Range(BaseModel):
    """读取指定日期范围内的对话记录"""
    start_date: str = Field(..., description="开始日期")
    end_date: str = Field(..., description="结束日期")

class Run_Script(BaseModel):
    """运行指定的脚本文件"""
    script_path: str = Field(..., description="要运行的脚本的文件路径")
    target_path: str = Field(..., description="被脚本加工的对象的文件路径")

# 3. 批量转换函数 (修改点：分离描述来源)
def build_tools_list(models: List[Type[BaseModel]]) -> List[CustomToolDict]:
    tool_list: List[CustomToolDict] = []
    for model in models:
        # 获取 JSON Schema
        schema = model.model_json_schema()
        """print(f"原始 Schema for {model.__name__}:", schema)  # 调试输出，查看原始 Schema"""
        
        # 1. 提取工具描述 (Tool Description)
        # Pydantic V2 通常会将类文档字符串放入 schema 的顶层 description 中
        # 我们将其弹出，作为工具的 description，避免在 parameters 中重复
        tool_description = schema.pop("description", None)
        
        # 如果 schema 里没有 (比如没写 docstring)，则 fallback 到 __doc__
        if not tool_description:
            tool_description = model.__doc__ or ""
            
        # 2. 清理 Schema 用于 Parameters
        # 移除 Pydantic 默认生成的 title 字段
        schema.pop("title", None)
        # 确保 parameters 里没有顶层 description (因为已经提取到工具描述里了)
        # 这样 LLM 不会混淆“工具是干嘛的”和“参数对象是干嘛的”
        
        tool_list.append({
            "type": "function",
            "name": model.__name__.lower(),     # 使用模型类名的小写作为工具名称
            "description": tool_description,    # 使用类文档字符串/功能描述
            "parameters": schema                # 使用包含字段描述的 Schema
        })
        
    return tool_list

"""# --- 方便理解要构建openai要求的tools参数，需要做什么改动 ---
if __name__ == "__main__":
    tools = build_tools_list([Get_Local_Backlog, Get_Weather])
    for tool in tools:
        print(f"工具名称: {tool['name']}")
        print(f"工具描述: {tool['description']}")
        print(f"参数 Schema: {tool['parameters']}")
        print("-" * 40)"""
