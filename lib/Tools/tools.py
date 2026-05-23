try:
    import memory
except ImportError:
    try:
        from lib import memory
    except ImportError:
        import lib.memory as memory # type: ignore
from typing import Type, List, TypedDict, Dict, Any, Optional
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import requests
import sys
import os

load_dotenv()

class AgentTools:
    
    def __init__(self):
        self.tool_list = build_tools_list([Get_Local_Backlog, Get_Weather, Get_Traffic, Load_Backlog, 
                                           Image_Recognition,
                                           TaskOrganizerTool, Qwen_WebSearch, Locate_IP])
    
    def get_local_backlog(self, backlog: 'memory.Backlog') -> None:
        """获取对话记录"""
        print(backlog.get_text())

    def get_weather(self, adcode: str = "", **kwargs) -> Optional[Dict[str, Any]]:
        """获取天气信息"""
        # 兼容处理：如果 AI 传了 city 而不是 adcode
        target_city = adcode or kwargs.get("city") or kwargs.get("adcode")
        
        # ⚠️ 【需要 API KEY】高德地图 API
        Gaode_API_Key = os.getenv("Gaode_API_Key")
        if not target_city:
            print(f"没有提供城市信息，无法获取天气。")
            return None
            
        url = f"https://restapi.amap.com/v3/weather/weatherInfo?city={target_city}&key={Gaode_API_Key}"
        result = requests.get(url, timeout=10).json()
        return result

    def get_traffic(self, origin: str, destination: str, strategy: int = 0) -> Dict[str, Any]:
        """
        通过高德驾车路径规划 API 粗略估计路况。

        origin/destination 格式："lng,lat"
        返回：{traffic_level, duration_sec, tmcs_status_counts, raw}
        """
        Gaode_API_Key = os.getenv("Gaode_API_Key")
        if not Gaode_API_Key:
            raise Exception("❌ 环境变量缺失：Gaode_API_Key")
        if not origin or not destination:
            raise ValueError("origin/destination 不能为空，格式应为 'lng,lat'")

        url = "https://restapi.amap.com/v3/direction/driving"
        params = {
            "origin": origin,
            "destination": destination,
            "strategy": str(strategy),
            "extensions": "all",  # 尝试拿 tmcs；若账号/接口不返回则自动降级
            "key": Gaode_API_Key,
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

            # extensions=all 时，steps 里可能有 tmcs
            steps = (paths[0] or {}).get("steps") or []
            for st in steps:
                for t in (st or {}).get("tmcs") or []:
                    status = str((t or {}).get("status") or "").strip()
                    if not status:
                        continue
                    tmcs_status_counts[status] = tmcs_status_counts.get(status, 0) + 1

        # 用 tmcs 估计一个离散“路况等级”
        if tmcs_status_counts:
            # 高德常见：畅通/缓行/拥堵/严重拥堵
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

    def load_backlog(self, backlog: 'memory.Backlog', target_date: str) -> None:
        """加载指定日期的对话记录"""
        backlog.load_backlog(target_date)

    def get_resource_path(self, relative_path: str) -> str:
        """
        智能获取资源路径
        relative_path: 传入文件夹名+文件名，例如 "Windows-UZDoom-Nightly/uzdoom.exe"
        """
        # 1. 检查是否在打包环境 (_MEIPASS)
        if hasattr(sys, '_MEIPASS'):
            base_path = getattr(sys, '_MEIPASS', os.path.abspath("."))
            return os.path.join(base_path, relative_path)
        
        # 2. 如果在开发环境，手动补上 Tools 目录前缀
        # 假设你的主程序 ui.py 在 Tools 的上一级
        dev_path = os.path.join(os.path.abspath("."), "Tools", relative_path)
        return dev_path

    def image_recognition(self, image_path: str, scene: str = "car") -> Optional[Dict[str, Any]]:
        """多场景图像识别，支持车型、菜品、动物、植物、Logo、物体、食材识别并总结"""
        import base64

        # ⚠️ 【需要 API KEY】百度智能云 API
        # 在 .env 文件中配置：
        #   BAIDU_API_KEY=your_baidu_api_key
        #   BAIDU_SECRET_KEY=your_baidu_secret_key
        # 申请地址：https://cloud.baidu.com/product/imagerecognition
        BAIDU_API_KEY = os.getenv("BAIDU_API_KEY")
        BAIDU_SECRET_KEY = os.getenv("BAIDU_SECRET_KEY")

        if not all([BAIDU_API_KEY, BAIDU_SECRET_KEY]):
            raise Exception("❌ 环境变量缺失，请检查 .env 文件中的 BAIDU_API_KEY、BAIDU_SECRET_KEY 是否填写")

        # 获取百度Token（和你完全一样）
        def get_baidu_token():
            url = f"https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id={BAIDU_API_KEY}&client_secret={BAIDU_SECRET_KEY}"
            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
            payload = ""
            try:
                response = requests.request("POST", url, headers=headers, data=payload, timeout=10)
                response.raise_for_status()
                res_json = response.json()
            except requests.exceptions.RequestException as e:
                raise Exception(f"❌ 获取Token网络错误：{str(e)}")

            if "access_token" not in res_json:
                raise Exception(f"❌ 获取Token失败：{res_json.get('error_msg', res_json)}")
            return res_json["access_token"]

        # 图片识别（和你完全一样）
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"❌ 文件不存在：{image_path}")
        valid_ext = (".jpg", ".jpeg", ".png", ".bmp", ".gif")
        if not image_path.lower().endswith(valid_ext):
            raise ValueError(f"❌ 不是有效图片文件，仅支持：{valid_ext}")

        with open(image_path, "rb") as f:
            img_base64 = base64.b64encode(f.read()).decode("utf-8")

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
            raise Exception(f"❌ 不支持的场景：{scene}，可选：{list(api_urls.keys())}")

        url = f"{api_urls[scene]}?access_token={token}"
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {"image": img_base64}

        try:
            response = requests.post(url, headers=headers, data=data, timeout=10)
            response.raise_for_status()
            baidu_result = response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"❌ 百度API网络错误：{str(e)}")

        if "error_code" in baidu_result:
            raise Exception(f"❌ 百度识别失败：{baidu_result.get('error_msg', '未知错误')}（错误码：{baidu_result['error_code']}）")

        info = baidu_result["result"][0] if (baidu_result.get("result") and len(baidu_result["result"]) > 0) else None
        if not info:
            print("未能识别到有效内容")
            return None
        
        return info
        
    def qwen_websearch(self, query: str) -> Optional[str]:
        """通义千问联网搜索问答"""
        # ⚠️ 【需要 API KEY】阿里云 DashScope API
        # 在 .env 文件中配置：DASHSCOPE_API_KEY=your_dashscope_api_key
        # 申请地址：https://dashscope.aliyuncs.com
        api_key = os.getenv("DASHSCOPE_API_KEY")
        url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"

        headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
        }

        payload = {
        "model": "qwen-flash",
        "input": {
            "messages": [
                {"role": "user", "content": query}
            ]
        },
        "parameters": {
            "temperature": 0.2,
            "enable_search": True,
            "incremental_output": False
        }
        }

        try:
            resp = requests.post(url, headers=headers, json=payload)
            result = resp.json()
            text = result['output']['text'].strip()
            print(f"搜索结果：{text}")
            return text
        except Exception as e:
            return f"调用失败：{str(e)}"
    
    def locate_ip(self, ip: str = "") -> Optional[Dict[str, Any]]:
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

    def task_organizer(self, tasks: List[str]) -> None:
        """生成格式化的待办清单"""
        morning_tasks = [task.replace('早上', '').strip() for task in tasks if '早上' in task]
        noon_tasks = [task.replace('中午', '').strip() for task in tasks if '中午' in task]
        evening_tasks = [task.replace('晚上', '').strip() for task in tasks if '晚上' in task]
        free_tasks = [task for task in tasks if '早上' not in task and '中午' not in task and '晚上' not in task]

        todo_list = ""
        if morning_tasks:
            todo_list += "早上做什么：\n" + "\n".join([f"- {task}" for task in morning_tasks]) + "\n"
        if noon_tasks:
            todo_list += "中午做什么：\n" + "\n".join([f"- {task}" for task in noon_tasks]) + "\n"
        if evening_tasks:
            todo_list += "晚上做什么：\n" + "\n".join([f"- {task}" for task in evening_tasks]) + "\n"
        if free_tasks:
            todo_list += "自由安排的事项：\n" + "\n".join([f"- {task}" for task in free_tasks])

        print(f"\n生成的待办清单：\n{todo_list}")
    

    def query_score(self, student_file: List[Dict[str, Any]], name: str) -> List[Dict[str, Any]]:
        """查询学生成绩，名字支持模糊搜索"""
        results = [s for s in student_file if name.lower() in s['name'].lower()]
        return results
        
        



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
    """多场景图像识别，支持车型、菜品、动物、植物、logo、物体、食材，并流式输出描述"""
    image_path: str = Field(..., description="图片完整路径，例如 C:/images/car.jpg")
    scene: str = Field("car", description="识别场景：car/dish/animal/plant/logo/object/ingredient，默认car")

class Qwen_WebSearch(BaseModel):
    """通义千问联网搜索问答"""
    query: str = Field(..., description="用户要搜索或提问的问题")

class Locate_IP(BaseModel):
    """根据IP地址获取地理位置信息（基于高德地图API）"""
    ip: str = Field("", description="要查询的IP地址，不传则自动查询当前设备公网IP所在的位置")

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
