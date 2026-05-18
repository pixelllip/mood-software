from typing import Type, List, TypedDict, Dict, Any, Optional
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import subprocess
import requests
import sys
import os

# 导入 Backlog 类型用于注解
try:
    from core.memory import Backlog
except ImportError:
    try:
        from ..core.memory import Backlog
    except ImportError:
        Backlog = Any

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

class Run_Script(BaseModel):
    """运行指定的脚本文件"""
    script_path: str = Field(..., description="要运行的脚本的文件路径")
    target_path: str = Field(..., description="被脚本加工的对象的文件路径")

class Text_to_Image(BaseModel):
    """根据文本描述生成图片"""
    prompt: str = Field(..., description="用于生成图片的文本描述")
    negative_prompt: str = Field("", description="（可选）生成图片时要避免的元素描述")
    width: int = Field(512, description="生成图片的宽度")
    height: int = Field(512, description="生成图片的高度")
    num_inference_steps: int = Field(20, description="生成图片的迭代步数")
    guidance_scale: float = Field(7.0, description="引导尺度")
    seed: int = Field(-1, description="随机种子")

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
            Run_Script, Text_to_Image, Image_Recognition,
            TaskOrganizerTool, Qwen_WebSearch
        ])
    
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

    def run_script(self, script_path: str, target_path: str = ""):
        """对目标运行指定的脚本文件"""
        if script_path == "EasterEgg":
            doom_path = self.get_resource_path(os.path.join("tools", "Windows-UZDoom-Nightly", "uzdoom.exe"))
            if os.path.exists(doom_path):
                print(f"[BONUS] 激活彩蛋！正在启动: {doom_path}")
                try:
                    subprocess.Popen([doom_path]) 
                    return 0
                except Exception as e:
                    print(f"【错误】无法启动彩蛋程序: {e}")
                    return -1
            else:
                print(f"【提醒】发现彩蛋指令，但未找到程序: {doom_path}")
        
        script_path = os.path.abspath(os.path.normpath(script_path))
        target_path = os.path.abspath(os.path.normpath(target_path))

        if not os.path.isfile(script_path):
            print(f"【错误】脚本不存在: {script_path}")
            return -1

        _, ext = os.path.splitext(script_path.lower())

        try:
            if ext in ['.bat', '.cmd']:
                cmd = f'"{script_path}" "{target_path}"'
                print(f"[INFO] 执行命令: {cmd}")
                result = subprocess.run(cmd, shell=True, check=True)
            elif ext == '.py':
                cmd = [sys.executable, script_path, target_path]
                print(f"[INFO] 执行命令: {cmd}")
                result = subprocess.run(cmd, shell=False, check=True)
            else:
                print(f"【错误】不支持的脚本类型: {ext}")
                return -1

            print(f"[INFO] 运行完成，返回码: {result.returncode}")
            return result.returncode
        except subprocess.CalledProcessError as exc:
            print(f"【错误】脚本执行失败，返回码: {exc.returncode}")
            return exc.returncode
        except Exception as exc:
            print(f"【错误】脚本执行异常: {exc}")
            return -1
        

    def text_to_image(self, arguments: Dict[str, Any]):
        """根据文本描述生成图片"""
        import base64
        from io import BytesIO
        from PIL import Image
        import time
        
        try:
            prompt = arguments.get("prompt")
            if not prompt:
                return None
            
            negative_prompt = arguments.get("negative_prompt", "")
            width = int(arguments.get("width", 512))
            height = int(arguments.get("height", 512))
            num_inference_steps = int(arguments.get("num_inference_steps", 20))
            guidance_scale = float(arguments.get("guidance_scale", 7.0))
            seed = int(arguments.get("seed", -1))
            
            width = (width // 8) * 8
            height = (height // 8) * 8
            
            api_url = "http://127.0.0.1:7860/sdapi/v1/txt2img"
            payload = {
                "prompt": prompt,
                "negative_prompt": negative_prompt,
                "width": width,
                "height": height,
                "steps": num_inference_steps,
                "cfg_scale": guidance_scale,
                "seed": seed
            }
            
            response = requests.post(api_url, json=payload, timeout=300)
            response.raise_for_status()
            result = response.json()
            
            if "images" in result and len(result["images"]) > 0:
                img_base64 = result["images"][0]
                img_data = base64.b64decode(img_base64)
                image = Image.open(BytesIO(img_data))
                
                timestamp = int(time.time() * 1000)
                output_dir = os.path.join(os.getcwd(), "Generated Images")
                os.makedirs(output_dir, exist_ok=True)
                local_file = os.path.join(output_dir, f"generated_{timestamp}.png")
                image.save(local_file)
                
                try:
                    if os.name == 'nt':
                        os.startfile(local_file)
                    elif os.name == 'posix':
                        subprocess.run(['xdg-open', local_file], check=False)
                except Exception:
                    pass
                return local_file
            return None
        except Exception:
            return None
        
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
    

    def task_organizer(self, tasks: List[str]):
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
        return todo_list
    

    def query_score(self, student_file, name):
        """查询学生成绩，名字支持模糊搜索"""
        results = [s for s in student_file if name.lower() in s['name'].lower()]
        return results
