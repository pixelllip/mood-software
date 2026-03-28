import memory
from typing import Type,List,TypedDict,Dict,Any
from pydantic import BaseModel,Field,ConfigDict

class AgentTools:
    
    def __init__(self):
        self.tool_list = build_tools_list([Get_Local_Backlog, Get_Weather])

    def get_local_backlog(self, backlog: memory.Backlog):
        """获取对话记录"""
        print(backlog.get_text())

    def get_weather(self):
        """获取天气信息"""
        print(f"今天天气不错。")

# 1. 定义工具字典结构
class CustomToolDict(TypedDict):
    type: str
    name: str
    description: str       # 工具本身的功能描述
    parameters: Dict[str, Any] # 参数的 JSON Schema

# 2. 定义模型 (修改点：使用类文档字符串描述工具，Field 描述描述参数)
class Get_Local_Backlog(BaseModel):
    """获取本地历史对话记录"""  # <--- 这里写工具的功能描述
    content: str = Field(..., description="查询关键词或过滤条件") # <--- 这里写参数的具体含义

class Get_Weather(BaseModel):
    """获取指定地区的实时天气信息""" # <--- 这里写工具的功能描述
    location: str = Field(..., description="城市名称或地区代码") # <--- 这里写参数的具体含义
    # 为了演示区别，我稍微修改了字段名，如果你必须用 content 也可以，只要描述不同即可

# 3. 批量转换函数 (修改点：分离描述来源)
def build_tools_list(models: List[Type[BaseModel]]) -> List[CustomToolDict]:
    tool_list: List[CustomToolDict] = []
    for model in models:
        # 获取 JSON Schema
        schema = model.model_json_schema()
        
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
            "name": model.__name__.lower(), 
            "description": tool_description,    # 使用类文档字符串/功能描述
            "parameters": schema                # 使用包含字段描述的 Schema
        })
        
    return tool_list

# --- 测试验证 ---