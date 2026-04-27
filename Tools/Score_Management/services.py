import json
from typing import List, Dict
import os
from pathlib import Path

class Student:
    def __init__(self, class_id: int, student_id: str, name: str, scores: Dict[str, float]):
        self.class_id = class_id
        self.student_id = student_id
        self.name = name
        self.scores = scores
    
    def __repr__(self):
        return f"Student(name={self.name}, id={self.student_id})"

    def to_dict(self):
        # 普通类直接返回字典
        return {
            "class_id": self.class_id,
            "student_id": self.student_id,
            "name": self.name,
            "scores": self.scores
        }

    @classmethod
    def from_dict(cls, data: dict):
        return cls(
            class_id=data["class_id"],
            student_id=data["student_id"],
            name=data["name"],
            scores=data["scores"]
        )

class StudentScoreService:
    def __init__(self, data_file: str = "students.json"):
        env_path = os.getenv("BASE_PATH", ".")  #获取软件目录路径，默认为当前目录
        base_path = Path(env_path)
        self.data_file = base_path / "Tools" / "Score_Management" / data_file
        self.students: List[Student] = []
        self.load_data()

    def load_data(self):
        """从 JSON 文件加载学生数据，如果文件不存在则初始化为空列表"""
        try:
            with open(self.data_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.students = [Student.from_dict(item) for item in data]
        except FileNotFoundError:
            self.students = []

    def save_data(self):
        """将学生数据保存到JSON文件"""
        with open(self.data_file, "w", encoding="utf-8") as f:
            json.dump([s.to_dict() for s in self.students], f, ensure_ascii=False, indent=2)

    def add_score(self, class_id, student_id, name, scores):
        """后端逻辑：添加或合并成绩"""
        # 查找是否已有该学生 (student_id 是唯一标识)
        existing_student = next((s for s in self.students if s.student_id == student_id), None)

        if existing_student:
            # 情况 A: 学生已存在，合并成绩 (使用 update 确保不限制科目)
            existing_student.scores.update(scores)
            # 可选：如果姓名或班级有变动也可以更新
            existing_student.name = name
            if class_id:
                existing_student.class_id = int(class_id)
            
            self.save_data()
            msg = f"已为学生 [{name}] 更新/合并成绩。"
        else:
            # 情况 B: 新学生，检查班级人数限制（你之前逻辑中有提到 50 人限制）
            try:
                cid = int(class_id) if class_id else 0
                class_stu_count = sum(1 for s in self.students if s.class_id == cid)
                if class_stu_count >= 50:
                    msg = "错误：该班级人数已达上限（50人）。"

                new_student = Student(cid, student_id, name, scores)
                self.students.append(new_student)
                self.save_data()
                msg = f"成功录入新学生：{name}"
            except ValueError:
                msg = "错误：班级ID必须为数字。"

        return msg
    
    def delete_student(self, class_id:str, student_id: str, name:str) -> bool:
        """
        根据班级/学号/学生姓名删除学生信息
        Args:
            student_id: 要删除的学生 ID
        """
        result=False
        # 记录初始长度以便判断是否执行了删除
        initial_count = len(self.students)
        
        # 过滤掉 ID 匹配的学生
        if not class_id or not name:
            self.students = [s for s in self.students if s.student_id != student_id]
        else:
            # 筛选掉班级和姓名都匹配的学生
            self.students = [s for s in self.students if s.name != name or s.class_id!=class_id]
        
        if len(self.students) < initial_count:
            self.save_data()  # 立即同步到本地 JSON 文件
            result=True
        
        return result

    def get_student_by_id(self, student_id: str) -> List[Student]:
        """根据学号查询学生"""
        return [s for s in self.students if s.student_id == student_id]

    def get_students_by_name(self, name: str) -> List[Student]:
        """根据姓名查询学生，支持模糊搜索"""
        return [s for s in self.students if name in s.name]

    @staticmethod
    def get_score_segment(score: float) -> str:
        if 90 <= score <= 100:
            return "90-100"
        elif 80 <= score < 90:
            return "80-89"
        elif 70 <= score < 80:
            return "70-79"
        elif 60 <= score < 70:
            return "60-69"
        else:
            return "0-59"
