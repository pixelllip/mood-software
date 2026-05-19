from __future__ import annotations
import os
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Dict, Any, Tuple

@dataclass(frozen=True)
class TaskItem:
    title: str
    time_hint: Optional[str] = None  # e.g. "早上/中午/晚上/全天"
    is_outdoor: Optional[bool] = None
    destination: Optional[str] = None  # "lng,lat" for traffic estimation
    flexible: bool = True

@dataclass(frozen=True)
class WeatherSummary:
    weather: str
    temperature: Optional[float] = None
    humidity: Optional[float] = None
    wind: Optional[str] = None
    raw: Optional[Dict[str, Any]] = None

@dataclass(frozen=True)
class TrafficSummary:
    duration_sec: Optional[int] = None
    traffic_level: str = "unknown"  # good/slow/congested/unknown
    tmcs_status_counts: Optional[Dict[str, int]] = None
    raw: Optional[Dict[str, Any]] = None

class TaskOrganizer:
    def __init__(self, tools):
        # tools: AgentTools instance
        self.tools = tools

    def parse_tasks_text(self, text: str) -> List[TaskItem]:
        tasks: List[TaskItem] = []
        for raw in (text or "").splitlines():
            line = raw.strip()
            if not line:
                continue
            
            time_hint = None
            is_outdoor: Optional[bool] = None
            lowered = line.lower()
            
            # 简单的关键词提取
            if any(k in line for k in ["早上", "上午", "早晨"]):
                time_hint = "早上"
            elif any(k in line for k in ["中午", "午间", "下午"]):
                time_hint = "中午"
            elif any(k in line for k in ["晚上", "夜间", "傍晚"]):
                time_hint = "晚上"
            
            if "@outdoor" in lowered or "户外" in line or "出门" in line:
                is_outdoor = True
                line = line.replace("@outdoor", "").strip()
            elif "@indoor" in lowered or "室内" in line or "在办公" in line:
                is_outdoor = False
                line = line.replace("@indoor", "").strip()
            
            tasks.append(TaskItem(title=line, time_hint=time_hint, is_outdoor=is_outdoor))
        return tasks

    def _summarize_weather(self, amap_weather_json: Dict[str, Any]) -> WeatherSummary:
        lives = (amap_weather_json or {}).get("lives") or []
        if not lives:
            return WeatherSummary(weather="unknown", raw=amap_weather_json)
        
        live = lives[0] or {}
        weather = str(live.get("weather") or "unknown")
        temp = live.get("temperature")
        hum = live.get("humidity")
        wind_dir = live.get("winddirection")
        wind_pow = live.get("windpower")
        
        wind = None
        if wind_dir or wind_pow:
            wind = f"{wind_dir or ''}{wind_pow or ''}".strip()
            
        return WeatherSummary(
            weather=weather,
            temperature=float(temp) if temp is not None and str(temp).strip() != "" else None,
            humidity=float(hum) if hum is not None and str(hum).strip() != "" else None,
            wind=wind,
            raw=amap_weather_json,
        )

    def _weather_risk_flags(self, w: WeatherSummary) -> Dict[str, bool]:
        weather = (w.weather or "").strip()
        # 常见降水描述
        rainy = any(k in weather for k in ["雨", "雷", "阵雨"])
        snowy = "雪" in weather
        foggy = any(k in weather for k in ["雾", "霾", "尘", "沙"])
        
        temp = w.temperature
        hot = (temp is not None and temp >= 34.0)
        very_hot = (temp is not None and temp >= 38.0)
        cold = (temp is not None and temp <= 5.0)
        very_cold = (temp is not None and temp <= -5.0)
        
        return {
            "rainy": rainy, 
            "snowy": snowy, 
            "foggy": foggy, 
            "hot": hot, 
            "very_hot": very_hot,
            "cold": cold,
            "very_cold": very_cold
        }

    def decide_today_plan(
        self,
        tasks: List[TaskItem],
        weather: WeatherSummary,
        traffic: TrafficSummary,
    ) -> Tuple[List[TaskItem], List[str]]:
        flags = self._weather_risk_flags(weather)
        notes: List[str] = []

        if weather.weather != "unknown":
            notes.append(f"天气：{weather.weather}" + (f" {weather.temperature}°C" if weather.temperature is not None else ""))
        if traffic.traffic_level != "unknown":
            notes.append(f"路况：{traffic.traffic_level}")

        def score(t: TaskItem) -> float:
            s = 0.0
            # 1. 降水影响
            if flags["rainy"] or flags["snowy"]:
                if t.is_outdoor is True:
                    s -= 6.0  # 严厉扣分
                if t.is_outdoor is False:
                    s += 1.5  # 推荐室内
            
            # 2. 极端气温影响
            if flags["very_hot"] or flags["very_cold"]:
                if t.is_outdoor is True:
                    s -= 8.0
            elif flags["hot"]:
                if t.is_outdoor is True and (t.time_hint in [None, "中午"]):
                    s -= 4.0
            elif flags["cold"]:
                if t.is_outdoor is True:
                    s -= 2.0

            # 3. 能见度影响
            if flags["foggy"]:
                if t.is_outdoor is True:
                    s -= 3.0
                if t.destination: # 需要通勤
                    s -= 2.0

            # 4. 路况影响
            if traffic.traffic_level == "congested":
                if t.destination or t.is_outdoor:
                    s -= 3.0
                if t.flexible:
                    s += 1.0 # 灵活任务可以延后
            elif traffic.traffic_level == "good":
                if t.destination:
                    s += 1.0

            # 5. 时间硬约束权重
            if t.time_hint is not None:
                s += 0.5
                
            return s

        # 排序
        sorted_tasks = sorted(tasks, key=score, reverse=True)

        # 生成动态建议
        if flags["rainy"]:
            notes.append("建议：今日有雨，出门请备好雨具，尽量安排室内活动。")
        if flags["snowy"]:
            notes.append("建议：有降雪，路面湿滑，建议减少不必要的户外行程。")
        if flags["very_hot"]:
            notes.append("建议：气温极高，谨防中暑，尽量留在室内空调环境。")
        elif flags["hot"]:
            notes.append("建议：天气炎热，午后尽量避免高强度户外运动。")
        if flags["foggy"]:
            notes.append("建议：空气质量欠佳或能见度低，建议佩戴口罩，驾驶注意安全。")
        
        if traffic.traffic_level == "congested":
            notes.append("建议：当前路况拥堵，建议避开高峰期或搭乘公共交通。")

        return sorted_tasks, notes

    def build_plan_text(self, tasks: List[TaskItem], notes: List[str]) -> str:
        lines: List[str] = []
        if notes:
            lines.append("【环境提醒】")
            for n in notes:
                lines.append(f"• {n}")
            lines.append("")

        if not tasks:
            lines.append("📅 今日暂无待办事项。")
            return "\n".join(lines).strip()

        # 分组展示
        buckets = {"早上": [], "中午": [], "晚上": [], "全天/未指定": []}
        for t in tasks:
            key = t.time_hint if t.time_hint in ["早上", "中午", "晚上"] else "全天/未指定"
            buckets[key].append(t)

        lines.append("📅 今日行程规划建议：")
        for key in ["早上", "中午", "晚上", "全天/未指定"]:
            if not buckets[key]:
                continue
            lines.append(f"\n[{key}]")
            for i, t in enumerate(buckets[key], start=1):
                tag = ""
                if t.is_outdoor is True:
                    tag = " 📍户外"
                elif t.is_outdoor is False:
                    tag = " 🏠室内"
                lines.append(f"{i}. {t.title}{tag}")

        return "\n".join(lines).strip()

    def generate_today_itinerary(
        self,
        tasks_text: str,
        city_adcode: str,
        origin: Optional[str] = None,
        destination: Optional[str] = None,
    ) -> str:
        tasks = self.parse_tasks_text(tasks_text)
        if not tasks:
            return "请输入您的任务列表。例如：\n早上 跑步 @outdoor\n中午 办公 @indoor"
            
        weather_json = self.tools.get_weather(city_adcode)
        weather = self._summarize_weather(weather_json if isinstance(weather_json, dict) else {})

        traffic = TrafficSummary()
        if origin and destination:
            traffic_json = self.tools.get_traffic(origin=origin, destination=destination)
            if isinstance(traffic_json, dict):
                traffic = TrafficSummary(
                    duration_sec=traffic_json.get("duration_sec"),
                    traffic_level=str(traffic_json.get("traffic_level") or "unknown"),
                    tmcs_status_counts=traffic_json.get("tmcs_status_counts"),
                    raw=traffic_json.get("raw"),
                )

        planned, notes = self.decide_today_plan(tasks, weather, traffic)
        return self.build_plan_text(planned, notes)

    def save_itinerary(self, date_str: str, content: str):
        """将日程内容保存到本地 Schedule 文件夹"""
        env_path = os.getenv("BASE_PATH", ".")
        base_path = Path(env_path)
        schedule_dir = base_path / "Schedule"
        schedule_dir.mkdir(parents=True, exist_ok=True)
        
        # 处理日期字符串作为文件名（去除不合法字符）
        safe_date = date_str.replace(" ", "_").replace("/", "-").replace(":", "-")
        file_path = schedule_dir / f"{safe_date}.md"
        
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
        return str(file_path)

    def load_itinerary(self, date_str: str) -> Optional[str]:
        """从本地 Schedule 文件夹加载日程内容"""
        env_path = os.getenv("BASE_PATH", ".")
        base_path = Path(env_path)
        safe_date = date_str.replace(" ", "_").replace("/", "-").replace(":", "-")
        file_path = base_path / "Schedule" / f"{safe_date}.md"
        
        if file_path.exists():
            return file_path.read_text(encoding="utf-8")
        return None
