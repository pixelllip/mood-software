from typing import Type, List, TypedDict, Dict, Any, Optional
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import requests
import sys
import os

# 导入 Backlog 类型用于注解
try:
    from core.memory import Backlog
    from tools.score_management.services import StudentScoreService
    from tools.task.task_organizer import TaskOrganizer
except ImportError:
    try:
        from ..core.memory import Backlog
        from .score_management.services import StudentScoreService
        from .task.task_organizer import TaskOrganizer
    except ImportError:
        Backlog = Any
        StudentScoreService = Any
        TaskOrganizer = Any

load_dotenv()

# 1. 定义工具字典结构
class CustomToolDict(TypedDict):
    type: str
    name: str
    description: str
    parameters: Dict[str, Any]

# 2. 定义 Pydantic 模型（放在使用它们类之前）

class Get_Local_Backlog(BaseModel):
    """获取当前的历史对话记录"""
    pass

class Get_Weather(BaseModel):
    """获取指定地区的实时天气信息"""
    adcode: str = Field(..., description="城市名称或中国城市编码（如 '广州' 或 '440100'）", alias="city")

    class Config:
        populate_by_name = True

class Get_Traffic(BaseModel):
    """获取两点间驾车路况（粗略估计）"""
    origin: str = Field(..., description="起点坐标 'lng,lat'")
    destination: str = Field(..., description="终点坐标 'lng,lat'")
    strategy: int = Field(0, description="路径策略（0为速度优先）")

class Load_Backlog(BaseModel):
    """加载指定日期的对话记录"""
    target_date: str = Field(..., description="目标日期")

class TaskOrganizerTool(BaseModel):
    """生成格式化的待办清单"""
    tasks: List[str] = Field(..., description="任务列表")

class Image_Recognition(BaseModel):
    """多场景图像识别"""
    image_path: str = Field(..., description="图片完整路径")
    scene: str = Field("car", description="识别场景：car/dish/animal/plant/logo/object/ingredient")

class Qwen_WebSearch(BaseModel):
    """通义千问联网搜索问答"""
    query: str = Field(..., description="用户要搜索或提问的问题")

class Locate_IP(BaseModel):
    """根据IP地址获取地理位置信息（基于高德地图API）"""
    ip: str = Field("", description="要查询的IP地址，不传则自动查询当前设备公网IP所在的位置")

class Query_Score(BaseModel):
    """查询学生成绩"""
    student_id: Optional[str] = Field(None, description="学生ID")
    name: Optional[str] = Field(None, description="学生姓名，支持模糊搜索")

class Add_Score(BaseModel):
    """录入或更新学生成绩"""
    student_id: str = Field(..., description="学生ID")
    name: str = Field(..., description="学生姓名")
    scores: Dict[str, float] = Field(..., description="成绩字典，例如 {'数学': 95, '英语': 88}")

class Delete_Score(BaseModel):
    """删除学生信息"""
    student_id: Optional[str] = Field(None, description="学生ID")
    name: Optional[str] = Field(None, description="学生姓名")

import re

def build_tools_list(models: List[Type[BaseModel]]) -> List[CustomToolDict]:
    tool_list: List[CustomToolDict] = []
    for model in models:
        schema = model.model_json_schema()
        tool_description = schema.pop("description", None) or model.__doc__ or ""
        schema.pop("title", None)
        
        # 将类名转换为下划线命名法 (Snake Case)
        # 如 TaskOrganizerTool -> task_organizer_tool
        name = model.__name__
        name = re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
        
        tool_list.append({
            "type": "function",
            "name": name,
            "description": tool_description,
            "parameters": schema
        })
    return tool_list

class AgentTools:
    
    def __init__(self):
        self.tool_list = build_tools_list([
            Get_Local_Backlog, Get_Weather, Get_Traffic, Load_Backlog, 
            Image_Recognition,
            TaskOrganizerTool, Qwen_WebSearch, Locate_IP,
            Query_Score, Add_Score, Delete_Score
        ])
        self.score_service = StudentScoreService()
        self.task_organizer_service = TaskOrganizer(self)
    
    def get_local_backlog(self, backlog: Backlog):
        """获取对话记录"""
        print(backlog.get_text())

    def get_weather(self, adcode: str = "", **kwargs):
        """获取天气信息"""
        gaode_api_key = os.getenv("Gaode_API_Key")
        target_city = adcode or kwargs.get("city") or kwargs.get("adcode")
        if not target_city:
            print("没有提供城市信息，无法获取天气。")
            return None
        url = f"https://restapi.amap.com/v3/weather/weatherInfo?city={target_city}&key={gaode_api_key}"
        result = requests.get(url, timeout=10).json()
        return result

    def get_traffic(self, origin: str, destination: str, strategy: int = 0):
        """通过高德驾车路径规划 API 粗略估计路况。"""
        gaode_api_key = os.getenv("Gaode_API_Key")
        if not gaode_api_key:
            raise Exception("❌ 环境变量缺失：Gaode_API_Key")
        if not origin or not destination:
            raise ValueError("origin/destination 不能为空，格式应为 'lng,lat'")

        url = "https://restapi.amap.com/v3/direction/driving"
        params = {
            "origin": origin,
            "destination": destination,
            "strategy": str(strategy),
            "extensions": "all",
            "key": gaode_api_key,
        }
        raw = requests.get(url, params=params, timeout=10).json()

        def safe_int(v):
            try:
                return int(float(v))
            except Exception:
                return None

        duration_sec = None
        tmcs_status_counts: Dict[str, int] = {}
        traffic_level = "unknown"

        route = (raw or {}).get("route") or {}
        paths = route.get("paths") or []
        if paths:
            duration_sec = safe_int((paths[0] or {}).get("duration"))
            steps = (paths[0] or {}).get("steps") or []
            for st in steps:
                for t in (st or {}).get("tmcs") or []:
                    status = str((t or {}).get("status") or "").strip()
                    if not status:
                        continue
                    tmcs_status_counts[status] = tmcs_status_counts.get(status, 0) + 1

        if tmcs_status_counts:
            bad = tmcs_status_counts.get("严重拥堵", 0) + tmcs_status_counts.get("拥堵", 0)
            mid = tmcs_status_counts.get("缓行", 0)
            good = tmcs_status_counts.get("畅通", 0)
            if bad > 0:
                traffic_level = "congested"
            elif mid > 0:
                traffic_level = "slow"
            elif good > 0:
                traffic_level = "good"

        return {
            "traffic_level": traffic_level,
            "duration_sec": duration_sec,
            "tmcs_status_counts": tmcs_status_counts if tmcs_status_counts else None,
            "raw": raw,
        }

    def load_backlog(self, backlog: Backlog, target_date: str):
        """加载指定日期的对话记录"""
        return backlog.load_backlog(target_date)

    def get_resource_path(self, relative_path):
        """智能获取资源路径"""
        if hasattr(sys, '_MEIPASS'):
            base_path = getattr(sys, '_MEIPASS', os.path.abspath("."))
            return os.path.join(base_path, relative_path)
        
        dev_path = os.path.join(os.path.abspath("."), relative_path)
        return dev_path

    def image_recognition(self, image_path: str, scene: str = "car"):
        """多场景图像识别"""
        import base64
        baidu_api_key = os.getenv("BAIDU_API_KEY")
        baidu_secret_key = os.getenv("BAIDU_SECRET_KEY")

        if not all([baidu_api_key, baidu_secret_key]):
            raise Exception("❌ 百度API配置缺失")

        def get_baidu_token():
            token_url = f"https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id={baidu_api_key}&client_secret={baidu_secret_key}"
            res_json = requests.post(token_url, timeout=10).json()
            return res_json.get("access_token")

        if not os.path.exists(image_path):
            # 这里的 f-string 可能在某些旧版分析器报错，尝试简化
            msg = "文件不存在: " + str(image_path)
            raise FileNotFoundError(msg)

        with open(image_path, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode("utf-8")

        token = get_baidu_token()
        api_urls = {
            "car": "https://aip.baidubce.com/rest/2.0/image-classify/v1/car",
            "animal": "https://aip.baidubce.com/rest/2.0/image-classify/v1/animal",
            "plant": "https://aip.baidubce.com/rest/2.0/image-classify/v1/plant",
            "object": "https://aip.baidubce.com/rest/2.0/image-classify/v1/object_detect",
            "logo": "https://aip.baidubce.com/rest/2.0/image-classify/v2/logo",
            "dish": "https://aip.baidubce.com/rest/2.0/image-classify/v2/dish",
            "ingredient": "https://aip.baidubce.com/rest/2.0/image-classify/v1/ingredient"
        }

        if scene not in api_urls:
            return None

        url = f"{api_urls[scene]}?access_token={token}"
        data = {"image": img_b64}
        baidu_result = requests.post(url, data=data, timeout=10).json()

        if "result" in baidu_result and len(baidu_result["result"]) > 0:
            return baidu_result["result"][0]
        return None
        
    def qwen_websearch(self, query: str):
        """通义千问联网搜索问答"""
        api_key = os.getenv("DASHSCOPE_API_KEY")
        url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        payload = {
            "model": "qwen-flash",
            "input": {"messages": [{"role": "user", "content": query}]},
            "parameters": {"enable_search": True}
        }
        try:
            resp = requests.post(url, headers=headers, json=payload)
            return resp.json()['output']['text'].strip()
        except Exception as e:
            return f"搜索失败：{str(e)}"
    
    def locate_ip(self, ip: str = ""):
        """根据IP地址获取地理位置信息（基于高德地图API）"""
        gaode_api_key = os.getenv("Gaode_API_Key")
        if not gaode_api_key:
            raise Exception("❌ 环境变量缺失：Gaode_API_Key")
        
        url = "https://restapi.amap.com/v3/ip"
        params = {"key": gaode_api_key}
        if ip:
            params["ip"] = ip
        
        result = requests.get(url, params=params, timeout=10).json()
        return result

    def task_organizer(self, tasks: List[str]):
        """生成格式化的待办清单"""
        tasks_text = "\n".join(tasks)
        # 默认使用广州的 adcode 进行天气查询，实际应用中可动态获取
        return self.task_organizer_service.generate_today_itinerary(tasks_text, city_adcode="440100")
    

    def query_score(self, student_id: str = None, name: str = None):
        """查询学生成绩"""
        return self.score_service.query_students(student_id=student_id, name=name)

    def add_score(self, student_id: str, name: str, scores: Dict[str, float]):
        """录入或更新成绩"""
        return self.score_service.add_score(student_id, name, scores)

    def delete_score(self, student_id: str = None, name: str = None):
        """删除学生信息"""
        success = self.score_service.delete_student(student_id=student_id, name=name)
        return "删除成功" if success else "未找到对应学生或删除失败"
