from flask import Flask, request, jsonify
from core.ai_agent import AiAgent
from tools.score_management.services import StudentScoreService
from dotenv import load_dotenv
import os

load_dotenv()

app = Flask(__name__)
agent = AiAgent()
score_service = StudentScoreService()

@app.route('/chat', methods=['POST'])
def chat():
    data = request.json
    prompt = data.get('prompt')
    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400
    
    try:
        reply = agent.chat(prompt)
        return jsonify({"reply": reply})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/query', methods=['GET'])
def query():
    student_id = request.args.get('id')
    name = request.args.get('name')
    results = score_service.query_students(student_id=student_id, name=name)
    if results:
        # 假设 Flutter 需要第一个匹配项的格式
        return jsonify({
            "name": results[0]["name"],
            "scores": results[0]["scores"]
        })
    return jsonify({"error": "Student not found"}), 404

@app.route('/add', methods=['POST'])
def add():
    data = request.json
    # data format: {"id": "...", "name": "...", "scores": [{"Math": "90"}, ...]}
    student_id = data.get('id')
    name = data.get('name')
    scores_list = data.get('scores', [])
    
    # 转换格式为 Dict[str, float]
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

if __name__ == '__main__':
    # 获取本地 IP 方便调试
    app.run(host='0.0.0.0', port=5000, debug=True)
