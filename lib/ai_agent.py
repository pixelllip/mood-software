from openai import OpenAI
from dotenv import load_dotenv
from memory import Backlog, Instructions
from Tools.tools import AgentTools
import time
import os
import json
from typing import Any, Dict, List, Optional, Tuple

load_dotenv()

class AI_Agent:
    client: OpenAI
    backlog: Backlog
    tool: AgentTools
    instructions: Instructions
    current_text: str
    _schedule_max_total_tokens: int
    _schedule_max_output_tokens: int

    def __init__(self) -> None:

        # 加载OpenAI API，这里使用千问服务
        load_dotenv()
        # 获取 OPENAI_API_KEY 环境变量
        api_key = os.getenv('OPENAI_API_KEY') or ""
        # 创建 OpenAI 客户端
        self.client = OpenAI(
            api_key=api_key,
            base_url='https://dashscope.aliyuncs.com/compatible-mode/v1'
        )

        # 初始化对话记录
        self.backlog = Backlog()

        # 初始化工具
        self.tool = AgentTools()

        # 初始化给AI看的指引
        self.instructions = Instructions()

        self.current_text = ""  # 用于存放本次要处理的文本

        # 学习日程生成：尽量将总 token 控制在 1600 内
        # 由于不同服务端的 token 统计口径可能不同，这里主要通过限制输出 token + 精简提示词来逼近上限。
        self._schedule_max_total_tokens = 1600
        self._schedule_max_output_tokens = 140

    def _compact_student_profile_for_schedule(self, student_profile: Optional[Dict[str, Any]], *, weak_n: int = 4) -> Dict[str, Any]:
        """
        为了减少 token：裁剪 student_profile，仅保留生成日程所需的最小信息。
        - 保留学号/姓名
        - 所有科目只保留“科目名称列表”（不传分数）
        - 仅对薄弱科目（最低 weak_n 门）保留分数，用于决定优先级
        """
        sp = student_profile or {}
        scores = (sp.get("scores") or {}) if isinstance(sp, dict) else {}
        if not isinstance(scores, dict):
            scores = {}

        items: list[tuple[str, float]] = []
        for k, v in scores.items():
            try:
                items.append((str(k), float(v)))
            except Exception:
                continue

        items_sorted = sorted(items, key=lambda x: x[1])
        weak = items_sorted[: max(0, int(weak_n))]

        weak_scores: dict[str, float] = {}
        for k, v in weak:
            if k not in weak_scores:
                weak_scores[k] = v

        return {
            "student_id": sp.get("student_id", ""),
            "name": sp.get("name", ""),
            "all_subjects": [k for k, _ in items_sorted],
            "weak_scores": weak_scores,
        }

    def _extract_usage_tokens(self, resp: Any) -> Tuple[Optional[int], Optional[int], Optional[int]]:
        """
        返回 (prompt_tokens, completion_tokens, total_tokens)。
        兼容不同响应结构；拿不到则返回 None。
        """
        usage = getattr(resp, "usage", None)
        if not usage:
            return None, None, None

        def _get(obj, key: str):
            if isinstance(obj, dict):
                return obj.get(key)
            return getattr(obj, key, None)

        prompt_tokens = _get(usage, "prompt_tokens")
        completion_tokens = _get(usage, "completion_tokens")
        total_tokens = _get(usage, "total_tokens")
        return (
            prompt_tokens if isinstance(prompt_tokens, int) else None,
            completion_tokens if isinstance(completion_tokens, int) else None,
            total_tokens if isinstance(total_tokens, int) else None,
        )
        
    def set_input(self, text: str) -> None:
        """由外部调用，设置本次对话的输入"""
        self.current_text = text

    def _create_response(self) -> Any:
        """创建一个新的响应对象"""
        # 合并系统指引和当前任务指令
        system_content = "你是一个智能助手，帮助用户整理任务并生成待办清单。请用中文回答我的问题。"
        if self.instructions.content:
            system_content += f"\n\n额外指令：\n{self.instructions.content}"

        # 确保 system 消息是第一个且只有一个
        messages = [{"role": "system", "content": system_content}] + self.backlog.message

        response = self.client.responses.create(
            model="qwen3.5-flash",
            input=messages,
            stream=True,
            tools=self.tool.tool_list,  # type: ignore
            tool_choice="auto"
        )  # type: ignore
        return response

    def process_response(self, response: Any, final: bool = False) -> Tuple[str, str, Dict[str, Any]]:
        """处理响应事件（流式）"""
        initial_answer = ""
        tool_name = ""
        tool_arguments: Dict[str, Any] = {}
        thinking = False
        for event in response:
            # 处理响应失败
            if event.type == 'response.failed':
                print(f"\n[响应失败: {event.response.error.message}]")
                break

            # 处理思考过程
            elif event.type == 'response.reasoning_summary_text.delta' and not final:
                self.current_text = event.delta.strip()
                if thinking == False:
                    print(f"思考中: {self.current_text}", end="", flush=True)
                    thinking = True
                else:
                    print(f"{event.delta}", end="", flush=True)
            elif event.type == 'response.reasoning_summary_text.done':
                print("\n")

            # 处理回答内容
            elif event.type == 'response.output_text.delta':
                self.current_text = event.delta.strip()
                print(self.current_text, end="", flush=True)
                initial_answer += self.current_text

            # 处理工具调用
            elif event.type == 'response.function_call_arguments.done':
                tool_name = event.name.strip()
                print(f"\n[工具调用: {tool_name}]\n")

                # 解析工具参数
                raw_args = getattr(event, 'arguments', None)
                if raw_args:
                    try:
                        # 解析 JSON 字符串 -> Python 字典
                        tool_arguments = json.loads(raw_args)
                        print(f"[解析参数]: {tool_arguments}")
                    except (json.JSONDecodeError, TypeError) as e:
                        print(f"[参数解析错误]: {raw_args} | {e}")
               

            time.sleep(0.01)


        return initial_answer, tool_name, tool_arguments

    def use_tool(self, tool_name: str, arguments: Optional[Dict[str, Any]] = None) -> str:
        """根据工具名称调用对应的方法"""
        if not tool_name:
            return ""

        # 处理传入工具名和参数
        tool_name = tool_name.strip()
        args = arguments or {}

        if tool_name == "get_local_backlog":
            self.tool.get_local_backlog(self.backlog)
        elif tool_name == "get_weather":
            info = self.tool.get_weather(**args)
            final_response = self.client.responses.create(
                model="qwen3.5-flash",
                input=[{
                    "role": "system",
                    "content": f"以下是根据工具获取的信息：{info}。请基于这些信息回答用户的问题。"
                }],
                stream=True
            )
            self.process_response(final_response, final=True)
        elif tool_name == "get_traffic":
            info = self.tool.get_traffic(**args)
            final_response = self.client.responses.create(
                model="qwen3.5-flash",
                input=[{
                    "role": "system",
                    "content": f"以下是根据工具获取的信息：{info}。请基于这些信息回答用户的问题。"
                }],
                stream=True
            )
            self.process_response(final_response, final=True)
        elif tool_name == "load_backlog":
            self.tool.load_backlog(self.backlog, **args)
        elif tool_name == "run_script":
            self.tool.run_script(**args)
        elif tool_name == "text_to_image":
            image = self.tool.text_to_image(args)
            if image:
                print(f"成功生成图片。")
            else:
                print("未能生成图片。")
        elif tool_name == "task_organizer_tool":
            tasks = args.get('tasks', [])
            self.tool.task_organizer(tasks)
        elif tool_name == "image_recognition":
            result = self.tool.image_recognition(**args)
            if result:
                final_response=self.client.responses.create(
                    model="qwen3.5-flash",
                    input=[
                        {"role": "system", "content": f"""工具识别logo信息：{result}。
                         用一句自然的话描述图片内容。"""},
                        {"role": "user", "content": "描述这张图片"}
                    ],
                    stream=True,
                )
                self.process_response(final_response, final=True)
        elif tool_name == "qwen_websearch":
                self.tool.qwen_websearch(**args)
        else:
            print(f"\n[未知工具: {tool_name}]")

        
        return f"\n已调用工具: {tool_name}"

    def run(self) -> None:
        """运行 AI 代理处理当前输入"""
        input_text = self.current_text.strip()
        if not input_text:
            return

        self.backlog.append_user_text(input_text)

        try:
            # 获取流式响应
            response = self._create_response()

            # 处理响应并在内部发射信号
            initial_answer, tool_name, tool_arguments = self.process_response(response)

            if tool_name:
                result = self.use_tool(tool_name, tool_arguments)
                print(f"\n工具执行结果：{result}") # 也可以发射信号告知UI工具在运行

            self.backlog.append_assistant_text(initial_answer)

        except Exception as e:
            print(f"\n[线程执行出错: {e}]")
        finally:
            self.backlog.write_text()

    @staticmethod
    def check_api_key() -> bool:
        openai_api_key = os.getenv("OPENAI_API_KEY")
        base_path = os.getenv("BASE_PATH")
        if not openai_api_key:
            print("""请先在软件目录创建.env文件，然后在其中填入必须的信息：\n
                  OPENAI_API_KEY=*你的支持OPENAI API的密钥；""")
            return False
        if not base_path:
            print("""请先在软件目录创建.env文件，然后在其中填入: BASE_PATH=*你希望将生成的文件放置于何处*""")
            return False
        return True

    def generate_tasks_for_schedule(
        self,
        date: str,
        preferences: str,
        weather_info: Dict[str, Any],
        traffic_info: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        为“日程安排”界面生成原始任务清单（每行一个任务）。
        输出将交给 TaskOrganizer 进一步按天气/路况排序与取舍。
        """
        sys_prompt = (
            "你是日程规划助手。你将根据日期、用户偏好、天气与路况生成今日任务清单。\n"
            "输出要求：\n"
            "1) 只输出任务清单，每行一个任务，不要解释、不加前后缀、不输出Markdown。\n"
            "2) 每行可带时间段提示（早上/中午/晚上/全天），并在行末加 @outdoor 或 @indoor。\n"
            "3) 任务要具体可执行，数量控制在 6-10 条。\n"
            "4) 如果天气有雨/雪/高温/大风/雾霾等，尽量给出替代的室内方案。\n"
        )

        user_payload = {
            "date": date,
            "preferences": preferences or "",
            "weather": weather_info or {},
            "traffic": traffic_info or {},
        }

        resp = self.client.responses.create(
            model="qwen3.5-flash",
            input=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": f"请生成今天任务清单：{user_payload}"},
            ],
            stream=False,
        )

        # 尽量兼容不同 SDK 返回结构
        text = getattr(resp, "output_text", None)
        if isinstance(text, str) and text.strip():
            return text.strip()
        try:
            # response.output[0].content[0].text
            output0 = (getattr(resp, "output", None) or [None])[0] or {}
            content0 = (output0.get("content") or [None])[0] or {}
            t = content0.get("text")
            if isinstance(t, str) and t.strip():
                return t.strip()
        except Exception:
            pass

        return ""

    def generate_tomorrow_study_schedule(
        self,
        *,
        date: str,
        student_profile: Optional[Dict[str, Any]],
        preferences: str = "",
        wake_time: str = "07:00",
        sleep_time: str = "22:30",
        not_before_time: Optional[str] = None,
        exclude_subjects: Optional[List[str]] = None,
        weather_info: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        根据学生成绩生成“指定日期学习日程”（精确到时间段）。
        输出为纯文本时间表，便于直接展示/保存。
        """
        sys_prompt = (
            "生成学习日程（中文）。仅输出正文纯文本。\n"
            "每行：HH:MM-HH:MM 任务。\n"
            "严格：总行数 6-8 行；薄弱科目优先，包含 诊断->训练->复盘；不解释。\n"
            "尽量：相邻两行安排的科目不同（不要连续两段复习同一科）。\n"
        )

        compact_profile = self._compact_student_profile_for_schedule(student_profile, weak_n=4)
        all_subjects = compact_profile.get("all_subjects") or []
        if isinstance(all_subjects, list):
            all_subjects = [str(s).strip() for s in all_subjects if str(s).strip()]
        else:
            all_subjects = []

        weak_scores = compact_profile.get("weak_scores") or {}
        weak_subjects = "，".join([f"{k}{v:g}" for k, v in weak_scores.items()]) if isinstance(weak_scores, dict) and weak_scores else "无"

        # 不要把 dict 直接 stringify 给模型（会显著增加 token）
        user_lines = [
            f"日期：{date}",
            f"时间范围：{wake_time} 到 {sleep_time}",
        ]
        nbt = (not_before_time or "").strip()
        if nbt:
            user_lines.append(f"仅生成 {nbt} 之后的安排（不要输出更早时间段）")
        ex = [s.strip() for s in (exclude_subjects or []) if isinstance(s, str) and s.strip()]
        if ex:
            user_lines.append(f"禁止出现这些已复习科目：{','.join(ex)}")
        if all_subjects:
            user_lines.append(f"今日科目范围（可轮换安排）：{','.join(all_subjects)}")
        user_lines.append(f"薄弱科目（优先）：{weak_subjects}")
        pref = (preferences or "").strip()
        if pref:
            user_lines.append(f"偏好：{pref}")
        user_content = "\n".join(user_lines)

        resp = self.client.responses.create(
            model="qwen3.5-flash",
            input=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_content},
            ],
            stream=False,
            max_output_tokens=self._schedule_max_output_tokens,
        )

        prompt_tokens, completion_tokens, total_tokens = self._extract_usage_tokens(resp)
        # 某些兼容模式下 total_tokens 可能口径异常（会被放大），这里优先用 completion_tokens 判断是否“爆输出”
        if isinstance(completion_tokens, int) and completion_tokens > self._schedule_max_total_tokens:
            raise ValueError(
                f"本次生成 completion_tokens={completion_tokens}，超过 {self._schedule_max_total_tokens} 上限，请减少输入信息后重试。"
            )
        if (
            completion_tokens is None
            and isinstance(total_tokens, int)
            and total_tokens > self._schedule_max_total_tokens * 5
        ):
            # 兜底：当服务端只给 total_tokens 且明显异常时，不直接拦截，避免误判
            pass

        text = getattr(resp, "output_text", None)
        if isinstance(text, str) and text.strip():
            return text.strip()
        try:
            output0 = (getattr(resp, "output", None) or [None])[0] or {}
            content0 = (output0.get("content") or [None])[0] or {}
            t = content0.get("text")
            if isinstance(t, str) and t.strip():
                return t.strip()
        except Exception:
            pass
        return ""

if __name__ == '__main__':
    agent = AI_Agent()
    while True:   
        user_input = input("请输入内容（输入'退出'结束对话）：") 
        if user_input.strip() == "退出" or user_input.strip() == "":
            print("对话结束。")
            break
        agent.set_input(user_input)
        agent.run() # 直接在主线程运行