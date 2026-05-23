from flask import Flask, request, jsonify, Response, stream_with_context
import os
import sys
import traceback
import json

# 确保可以导入 core 模块
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from core.ai_agent import AiAgent, _load_ai_config_from_json
from tools.score_management.services import StudentScoreService

# 💡 平台路径自动修正逻辑
def _resolve_base_path():
    # 尝试从 config.json 读取 BASE_PATH
    config_paths = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config.json"),
        os.path.join(os.path.expanduser("~"), "Documents", "Academic Aegis", "config.json"),
    ]
    for cp in config_paths:
        if os.path.exists(cp):
            try:
                with open(cp, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                bp = cfg.get("BASE_PATH", "")
                if bp:
                    return bp
            except:
                pass
    return os.getenv("BASE_PATH", ".")

base_path = _resolve_base_path()
if sys.platform == 'win32' and base_path.startswith('/storage/emulated/'):
    # 如果在 Windows 上运行且路径是安卓格式，修正为本地目录
    new_path = os.path.join(os.path.expanduser("~"), "Documents", "Aegis Academic")
    base_path = new_path
    print(f">>> 检测到 Windows 环境，已将安卓路径修正为: {new_path}")
    if not os.path.exists(new_path):
        os.makedirs(new_path)

os.environ["BASE_PATH"] = base_path
print(f">>> BASE_PATH: {base_path}")

app = Flask(__name__)

# 初始化 Agent
agent = AiAgent()
score_service = StudentScoreService()

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({"status": "ok", "message": "Backend is running!"})

@app.route('/chat', methods=['POST'])
def chat():
    print(">>> 收到聊天请求")
    data = request.json
    if not data:
        return jsonify({"error": "No JSON data"}), 400
        
    prompt = data.get('prompt')
    history = data.get('history')  # 可选的历史消息
    print(f">>> 用户消息: {prompt}")
    
    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400
    
    def generate():
        try:
            # 如果传入了历史消息，先加载到 agent 的 backlog 中
            if history:
                agent.backlog.message = history
                agent.backlog.reset_path()  # 重置时间为当前，实现“时间重置”

            # 使用我们在 core/ai_agent.py 中定义的 stream_chat 方法
            for chunk in agent.stream_chat(prompt):
                yield chunk
        except Exception as e:
            print(f">>> Agent 运行出错: {e}")
            yield f"Error: {str(e)}"
            
    return Response(stream_with_context(generate()), mimetype='text/plain')

@app.route('/query', methods=['GET'])
def query():
    student_id = request.args.get('id')
    name = request.args.get('name')
    print(f">>> 查询请求: id={student_id}, name={name}")
    
    # 强制重新加载数据以确保路径正确并包含最新信息
    score_service.load_data()
    print(f">>> 当前加载的学生数量: {len(score_service.students)}")
    if score_service.students:
        print(f">>> 第一个学生 ID: {score_service.students[0].student_id}")

    results = score_service.query_students(student_id=student_id, name=name)
    if results:
        return jsonify({
            "name": results[0]["name"],
            "scores": results[0]["scores"]
        })
    return jsonify({"error": "Student not found"}), 404

@app.route('/add', methods=['POST'])
def add():
    data = request.json
    student_id = data.get('id')
    name = data.get('name')
    scores_list = data.get('scores', [])
    formatted_scores = {}
    for item in scores_list:
        formatted_scores.update(item)
    msg = score_service.add_score(student_id, name, formatted_scores)
    return jsonify({"message": msg})

@app.route('/delete', methods=['DELETE'])
def delete():
    student_id = request.args.get('id')
    name = request.args.get('name')
    success = score_service.delete_student(student_id=student_id, name=name)
    if success:
        return jsonify({"message": "Deleted successfully"})
    return jsonify({"error": "Failed to delete"}), 400

@app.route('/schedule', methods=['POST'])
def schedule():
    import time
    start_time = time.time()
    try:
        data = request.json
        tasks_text = data.get('tasks', '')
        city = data.get('city', '440100')
        origin = data.get('origin')
        destination = data.get('destination')
        target_date = data.get('date', '今日')
        study_weaknesses = data.get('study_weaknesses', [])
        
        print(f">>> 开始生成日程: {target_date}, 任务长度: {len(tasks_text)}")
        organizer = agent.tool.task_organizer_service

        if not tasks_text.strip() and not study_weaknesses:
            saved_content = organizer.load_itinerary(target_date)
            if saved_content:
                # 尝试从内容中提取第一行作为摘要
                summary = "已加载历史日程规划"
                lines = [l.strip() for l in saved_content.split("\n") if l.strip()]
                if lines:
                    summary = lines[0].replace("#", "").strip()
                return jsonify({"itinerary": saved_content, "summary": summary, "from_cache": True})
            elif target_date != '今日':
                return jsonify({"itinerary": f"📅 {target_date} 暂无存档，请在上方输入任务后点击生成。", "summary": ""}), 200

        # 1. 获取天气
        print(f"[{time.time()-start_time:.2f}s] 正在请求天气...")
        weather_raw = agent.tool.get_weather(city)
        weather = organizer._summarize_weather(weather_raw)
        weather_info = f"状况: {weather.weather}, 温度: {weather.temperature}°C, 风力: {weather.wind}"
        
        # 2. 获取路况
        print(f"[{time.time()-start_time:.2f}s] 正在请求路况...")
        traffic_info = "路况未知"
        if origin and destination:
            t_res = agent.tool.get_traffic(origin, destination)
            if t_res:
                traffic_info = f"等级: {t_res.get('traffic_level', '未知')}, 预计耗时: {t_res.get('duration_sec', '未知')}秒"

        study_advice_section = ""
        if study_weaknesses:
            study_list = ", ".join(study_weaknesses)
            study_advice_section = f"\n【学习情况参考】：该学生薄弱学科：{study_list}。请在日程中合理插入复习时间。\n"

        # 3. AI 规划
        print(f"[{time.time()-start_time:.2f}s] 正在调用 AI 规划...")
        prompt = f"""
        你是一个集成了天气和交通信息的智能日程规划专家。请为用户生成一份日程规划。
        【选定日期】：{target_date}
        【环境参考数据】：天气: {weather_info}; 交通: {traffic_info}
        {study_advice_section}
        【待办任务】：{tasks_text}
        
        【输出要求】：
        请严格按以下 JSON 格式返回，不要包含任何其他文字：
        {{
          "summary": "一句话总结今日行程重点（30字以内）",
          "detail": "完整的详细日程，包含：1. 今日天气与出行综述。2. 使用 Markdown 表格展示日程安排（列：时间、任务、地点、环境建议）。3. 结尾温馨提醒。"
        }}
        """
        
        response = agent.client.chat.completions.create(
            model=agent.model,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            timeout=60
        )
        
        # 解析返回的 JSON
        import json
        raw_res = response.choices[0].message.content.strip()
        # 兼容处理：移除可能出现的 ```json 标记
        if raw_res.startswith("```"):
            raw_res = raw_res.split("\n", 1)[1].rsplit("\n", 1)[0].strip()
        
        try:
            res_data = json.loads(raw_res)
            summary = res_data.get("summary", "今日日程已准备就绪")
            detail = res_data.get("detail", raw_res)
        except:
            summary = "今日日程规划"
            detail = raw_res

        print(f"[{time.time()-start_time:.2f}s] 生成成功！")
        
        organizer.save_itinerary(target_date, detail) # 存档保存详细内容
        return jsonify({"summary": summary, "itinerary": detail})
        
    except Exception as e:
        print(">>> 日程规划接口报错:")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/history/dates', methods=['GET'])
def get_history_dates():
    sort_order = request.args.get('sort', 'desc')
    base_path = os.getenv("BASE_PATH", ".").strip('"').strip("'")
    backlog_path = os.path.join(base_path, "Backlog")
    if not os.path.exists(backlog_path):
        return jsonify([])
    try:
        dates = [d for d in os.listdir(backlog_path) if os.path.isdir(os.path.join(backlog_path, d))]
        if sort_order == 'asc':
            return jsonify(sorted(dates))
        else:
            return jsonify(sorted(dates, reverse=True))
    except Exception as e:
        return jsonify([])

@app.route('/history/list', methods=['GET'])
def get_history_list():
    target_date = request.args.get('date')
    if not target_date:
        return jsonify({"error": "No date provided"}), 400
    start_time = request.args.get('start_time')  # HH:MM
    end_time = request.args.get('end_time')      # HH:MM
    results = agent.backlog.load_backlog(target_date, start_time=start_time, end_time=end_time)
    return jsonify(results)

@app.route('/history/range', methods=['GET'])
def get_history_range():
    """获取指定日期范围内的所有对话记录"""
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    sort_order = request.args.get('sort', 'desc')
    start_time = request.args.get('start_time')  # HH:MM
    end_time = request.args.get('end_time')      # HH:MM
    
    if not start_date or not end_date:
        return jsonify({"error": "start_date and end_date required"}), 400
    
    base_path = os.getenv("BASE_PATH", ".").strip('"').strip("'")
    backlog_path = os.path.join(base_path, "Backlog")
    if not os.path.exists(backlog_path):
        return jsonify({})
    
    try:
        # 收集在日期范围内的所有文件夹
        all_dates = [d for d in os.listdir(backlog_path) if os.path.isdir(os.path.join(backlog_path, d))]
        filtered_dates = [d for d in all_dates if start_date <= d <= end_date]
        
        if sort_order == 'asc':
            filtered_dates.sort()
        else:
            filtered_dates.sort(reverse=True)
        
        results = {}
        for date_str in filtered_dates:
            day_results = agent.backlog.load_backlog(date_str, start_time=start_time, end_time=end_time)
            results.update(day_results)
        
        return jsonify(results)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def start_server():
    print("\n" + "="*50)
    print("星火学伴服务启动中...")
    print("="*50 + "\n")
    app.run(host='0.0.0.0', port=8080, debug=False)

if __name__ == '__main__':
    start_server()
