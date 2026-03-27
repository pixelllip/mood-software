import memory
from typing import Type,List
from pydantic import BaseModel,Field,ConfigDict

class AgentTools:
    
    def __init__(self):
        self.tools = build_tools_list([Get_Local_Backlog, Get_Weather])

    def get_local_backlog(self, backlog: memory.Backlog):
        """获取对话记录"""
        print(backlog.get_text())

    def get_weather(self):
        """获取天气信息"""
        print(f"今天天气不错。")

class Get_Local_Backlog(BaseModel):
    content: str = Field(..., description="获取本地对话记录")

class Get_Weather(BaseModel):
    content: str = Field(..., description="获取天气信息")

# 批量转换函数
def build_tools_list(models: List[Type[BaseModel]]) -> List[dict]:
    tools = []
    for model in models:
        # 获取 JSON Schema
        schema = model.model_json_schema()
        description = model.model_fields['content'].description
        # 移除 Pydantic 默认生成的 title 字段（可选，OpenAI 偶尔会对此敏感）
        schema.pop("title", None)
        
        tools.append({
            "type": "function",
            "name": model.__name__.lower(), # 使用类名小写作为函数名
            "description": description,    # 使用 Docstring 作为描述
            "parameters": schema          # 直接使用 JSON Schema 作为参数定义
        })
    return tools