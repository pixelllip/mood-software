from flask import Flask, request, jsonify, Response, stream_with_context
import os
import sys
import traceback

# 确保可以导入 core 模块
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from core.ai_agent import AiAgent
from tools.score_management.services import StudentScoreService
from dotenv import load_dotenv

load_dotenv()

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
    print(f">>> 用户消息: {prompt}")
    
    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400
    
    def generate():
        try:
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
    try:
        data = request.json
        tasks_text = data.get('tasks', '')
        city = data.get('city', '440100')
        origin = data.get('origin')
        destination = data.get('destination')
        target_date = data.get('date', '今日')
        
        organizer = agent.tool.task_organizer_service

        # 逻辑增强：如果任务内容为空，尝试读取该日期的已有存档
        if not tasks_text.strip():
            saved_content = organizer.load_itinerary(target_date)
            if saved_content:
                return jsonify({"itinerary": saved_content, "from_cache": True})
            elif target_date != '今日':
                return jsonify({"itinerary": f"📅 {target_date} 暂无存档，请在上方输入任务后点击生成。"}), 200

        # 1. 获取并提取天气关键信息
        weather_raw = agent.tool.get_weather(city)
        weather = organizer._summarize_weather(weather_raw)
        weather_info = f"状况: {weather.weather}, 温度: {weather.temperature}°C, 风力: {weather.wind}"
        
        # 2. 获取路况信息
        traffic_info = "路况未知"
        if origin and destination:
            t_res = agent.tool.get_traffic(origin, destination)
            if t_res:
                traffic_info = f"等级: {t_res.get('traffic_level', '未知')}, 预计耗时: {t_res.get('duration_sec', '未知')}秒"

        # 3. 让 AI 进行综合规划
        prompt = f"""
        你是一个集成了天气和交通信息的智能日程规划专家。请为用户生成一份精练的日程表。

        【选定日期】：{target_date}
        【环境参考数据（基于实时查询）】：
        - 天气：{weather_info}
        - 交通：{traffic_info}
        （注：如果日期不是今天，环境数据仅供参考，请在回复中说明）

        【待办任务】：
        {tasks_text}

        【要求】：
        1. 标题必须注明适用日期，如：# 📅 {target_date} 日程规划。
        2. 必须深刻结合环境数据。如果任务带有 '@outdoor' 且天气恶劣，请给出调整建议。
        3. 按时间顺序组织内容，使用 Markdown 格式（列表、加粗）。
        4. 结尾加上一句简短（15字以内）的温馨提醒。
        """
        
        response = agent.client.chat.completions.create(
            model="qwen-plus",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7
        )
        itinerary = response.choices[0].message.content
        
        # 保存到本地 Schedule 文件夹
        organizer.save_itinerary(target_date, itinerary)

        return jsonify({"itinerary": itinerary})
        
    except Exception as e:
        print(">>> 日程规划接口报错:")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/history/dates', methods=['GET'])
def get_history_dates():
    base_path = os.getenv("BASE_PATH", ".").strip('"').strip("'")
    backlog_path = os.path.join(base_path, "Backlog")
    if not os.path.exists(backlog_path):
        return jsonify([])
    try:
        dates = [d for d in os.listdir(backlog_path) if os.path.isdir(os.path.join(backlog_path, d))]
        return jsonify(sorted(dates, reverse=True))
    except Exception as e:
        return jsonify([])

@app.route('/history/list', methods=['GET'])
def get_history_list():
    target_date = request.args.get('date')
    if not target_date:
        return jsonify({"error": "No date provided"}), 400
    results = agent.backlog.load_backlog(target_date)
    return jsonify(results)

if __name__ == '__main__':
    print("\n" + "="*50)
    print("服务启动中...")
    print("请手动重启此脚本以应用更改！")
    print("请在 Flutter 设置中填入地址: http://127.0.0.1:8080")
    print("="*50 + "\n")
    # debug=True 模式下会启动两个进程，如果不希望看到两次启动，可以设为 False
    app.run(host='0.0.0.0', port=8080, debug=False)
