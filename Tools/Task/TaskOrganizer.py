from __future__ import annotations

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
        # tools: Tools.tools.AgentTools 或兼容对象（提供 get_weather / get_traffic）
        self.tools = tools

    def parse_tasks_text(self, text: str) -> List[TaskItem]:
        tasks: List[TaskItem] = []
        for raw in (text or "").splitlines():
            line = raw.strip()
            if not line:
                continue
            # 允许用户写： "早上 跑步 @outdoor" / "中午 自习 @indoor"
            time_hint = None
            is_outdoor: Optional[bool] = None
            lowered = line.lower()
            if "早上" in line:
                time_hint = "早上"
            elif "中午" in line:
                time_hint = "中午"
            elif "晚上" in line:
                time_hint = "晚上"
            if "@outdoor" in lowered or "户外" in line:
                is_outdoor = True
                line = line.replace("@outdoor", "").strip()
            if "@indoor" in lowered or "室内" in line:
                is_outdoor = False
                line = line.replace("@indoor", "").strip()
            tasks.append(TaskItem(title=line, time_hint=time_hint, is_outdoor=is_outdoor))
        return tasks

    def _summarize_weather(self, amap_weather_json: Dict[str, Any]) -> WeatherSummary:
        # 高德天气接口：lives[0] 里包含 weather/temperature/humidity/winddirection/windpower
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
        # 常见中文：晴/多云/阴/小雨/中雨/大雨/暴雨/雷阵雨/雪/雾/霾
        rainy = any(k in weather for k in ["雨", "雷阵雨", "暴雨"])
        snowy = "雪" in weather
        foggy = any(k in weather for k in ["雾", "霾"])
        hot = (w.temperature is not None and w.temperature >= 33.0)
        cold = (w.temperature is not None and w.temperature <= 5.0)
        return {"rainy": rainy, "snowy": snowy, "foggy": foggy, "hot": hot, "cold": cold}

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

        # 评分：越高越优先
        def score(t: TaskItem) -> float:
            s = 0.0
            # 天气影响
            if flags["rainy"] or flags["snowy"]:
                if t.is_outdoor is True:
                    s -= 5.0
                if t.is_outdoor is False:
                    s += 1.0
            if flags["hot"]:
                # 中午尽量少户外
                if t.is_outdoor is True and (t.time_hint in [None, "中午"]):
                    s -= 3.0
            if flags["foggy"]:
                # 能减少通勤则更好
                if t.destination:
                    s -= 1.0

            # 路况影响：拥堵时，减少外出/减少跨城通勤任务
            if traffic.traffic_level == "congested":
                if t.destination:
                    s -= 2.0
                if t.flexible:
                    s += 0.5  # 可调整任务更容易塞进“就近/室内”
            elif traffic.traffic_level == "good":
                if t.destination:
                    s += 0.5

            # 时间提示：有明确时段的更优先（更像“硬约束”）
            if t.time_hint is not None:
                s += 1.0
            return s

        sorted_tasks = sorted(tasks, key=score, reverse=True)

        # 兜底：如果恶劣天气，且前几项大多户外，给出提醒
        if (flags["rainy"] or flags["snowy"]) and any(t.is_outdoor is True for t in tasks):
            notes.append("建议：有降水时优先室内/可延期的户外事项")
        if flags["hot"]:
            notes.append("建议：高温时段尽量避开正午户外暴晒")
        if traffic.traffic_level == "congested":
            notes.append("建议：路况拥堵时尽量合并行程、减少远距离移动")

        return sorted_tasks, notes

    def build_plan_text(self, tasks: List[TaskItem], notes: List[str]) -> str:
        lines: List[str] = []
        if notes:
            lines.append("环境因素：")
            for n in notes:
                lines.append(f"- {n}")
            lines.append("")

        if not tasks:
            lines.append("今日暂无任务。")
            return "\n".join(lines).strip()

        # 按 time_hint 分组展示
        buckets = {"早上": [], "中午": [], "晚上": [], "全天/未指定": []}
        for t in tasks:
            key = t.time_hint if t.time_hint in ["早上", "中午", "晚上"] else "全天/未指定"
            buckets[key].append(t)

        lines.append("今日推荐行程：")
        for key in ["早上", "中午", "晚上", "全天/未指定"]:
            if not buckets[key]:
                continue
            lines.append(f"\n【{key}】")
            for i, t in enumerate(buckets[key], start=1):
                tag = ""
                if t.is_outdoor is True:
                    tag = "（户外）"
                elif t.is_outdoor is False:
                    tag = "（室内）"
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

