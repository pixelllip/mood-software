import json
from typing import List, Dict
import os
from pathlib import Path

class Student:
    def __init__(self, student_id: str, name: str, scores: Dict[str, float]):
        self.student_id = student_id
        self.name = name
        self.scores = scores
    
    def to_dict(self):
        return {
            "student_id": self.student_id,
            "name": self.name,
            "scores": self.scores
        }

    @classmethod
    def from_dict(cls, data: dict):
        return cls(
            student_id=data["student_id"],
            name=data["name"],
            scores=data["scores"]
        )

class StudentScoreService:
    def __init__(self, data_file: str = "students.json"):
        env_path = os.getenv("BASE_PATH", ".")
        base_path = Path(env_path)
        self.data_file = base_path / "Score_info" / data_file
        self.students: List[Student] = []
        self.load_data()

    def load_data(self):
        try:
            if not self.data_file.exists():
                self.data_file.parent.mkdir(parents=True, exist_ok=True)
                self.students = []
                return
            with open(self.data_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.students = [Student.from_dict(item) for item in data]
        except (FileNotFoundError, json.JSONDecodeError):
            self.students = []

    def save_data(self):
        self.data_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.data_file, "w", encoding="utf-8") as f:
            json.dump([s.to_dict() for s in self.students], f, ensure_ascii=False, indent=2)

    def add_score(self, student_id, name, scores):
        existing_student = next((s for s in self.students if s.student_id == student_id), None)
        if existing_student:
            existing_student.scores.update(scores)
            existing_student.name = name
            msg = f"已为学生 [{name}] 更新/合并成绩。"
        else:
            new_student = Student(student_id, name, scores)
            self.students.append(new_student)
            msg = f"成功录入新学生：{name}"
        self.save_data()
        return msg
    
    def delete_student(self, student_id: str = None, name: str = None) -> bool:
        initial_count = len(self.students)
        if student_id:
            self.students = [s for s in self.students if s.student_id != student_id]
        elif name:
            self.students = [s for s in self.students if s.name != name]
        
        if len(self.students) < initial_count:
            self.save_data()
            return True
        return False

    def query_students(self, student_id: str = None, name: str = None) -> List[dict]:
        results = []
        if student_id:
            results = [s.to_dict() for s in self.students if s.student_id == student_id]
        elif name:
            results = [s.to_dict() for s in self.students if name.lower() in s.name.lower()]
        return results
