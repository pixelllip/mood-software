from flask import Flask, request, jsonify, Response, stream_with_context
import os
import sys

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

@app.route('/history/dates', methods=['GET'])
def get_history_dates():
    base_path = os.getenv("BASE_PATH", ".").strip('"').strip("'")
    backlog_path = os.path.join(base_path, "Backlog")
    print(f">>> 正在扫描历史记录目录: {backlog_path}")
    if not os.path.exists(backlog_path):
        print(f">>> 目录不存在: {backlog_path}")
        return jsonify([])
    try:
        dates = [d for d in os.listdir(backlog_path) if os.path.isdir(os.path.join(backlog_path, d))]
        print(f">>> 找到日期: {dates}")
        return jsonify(sorted(dates, reverse=True))
    except Exception as e:
        print(f">>> 扫描失败: {e}")
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
    print("请在 Flutter 设置中填入地址: http://127.0.0.1:8080")
    print("="*50 + "\n")
    # debug=True 模式下会启动两个进程，如果不希望看到两次启动，可以设为 False
    app.run(host='0.0.0.0', port=8080, debug=False)
