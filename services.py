import json
from typing import List, Optional, Dict, Tuple
from models import Student, COURSE_LIST

class StudentScoreService:
    def __init__(self, data_file: str = "students.json"):
        self.data_file = data_file
        self.students: List[Student] = []
        self.load_data()

    def load_data(self):
        try:
            with open(self.data_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.students = [Student.from_dict(item) for item in data]
        except FileNotFoundError:
            self.students = []

    def save_data(self):
        with open(self.data_file, "w", encoding="utf-8") as f:
            json.dump([s.to_dict() for s in self.students], f, ensure_ascii=False, indent=2)

    def add_student(self, student: Student) -> bool:
        if any(s.student_id == student.student_id for s in self.students):
            return False
        class_stu = [s for s in self.students if s.class_id == student.class_id]
        if len(class_stu) >= 50:
            return False
        self.students.append(student)
        self.save_data()
        return True

    def get_student_by_id(self, student_id: str) -> Optional[Student]:
        return next((s for s in self.students if s.student_id == student_id), None)

    def get_students_by_name(self, name: str) -> List[Student]:
        return [s for s in self.students if s.name == name]

    def update_student(self, student_id: str, new_data: dict) -> bool:
        stu = self.get_student_by_id(student_id)
        if not stu:
            return False
        if "name" in new_data:
            stu.name = new_data["name"]
        if "class_id" in new_data:
            stu.class_id = new_data["class_id"]
        if "scores" in new_data:
            stu.scores = new_data["scores"]
        self.save_data()
        return True

    def delete_student(self, student_id: str) -> bool:
        stu = self.get_student_by_id(student_id)
        if not stu:
            return False
        self.students.remove(stu)
        self.save_data()
        return True

    def get_grade_avg_scores(self) -> Dict[str, float]:
        if not self.students:
            return {}
        avg = {}
        for course in COURSE_LIST:
            total = sum(s.scores.get(course, 0) for s in self.students)
            avg[course] = round(total / len(self.students), 2)
        return avg

    def get_class_avg_scores(self) -> Dict[int, Dict[str, float]]:
        class_ids = sorted({s.class_id for s in self.students})
        res = {}
        for cid in class_ids:
            cls_stu = [s for s in self.students if s.class_id == cid]
            cls_avg = {}
            for course in COURSE_LIST:
                total = sum(s.scores.get(course, 0) for s in cls_stu)
                cls_avg[course] = round(total / len(cls_stu), 2)
            res[cid] = cls_avg
        return res

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

    def get_grade_score_segments(self) -> Dict[str, int]:
        seg = {"90-100": 0, "80-89": 0, "70-79": 0, "60-69": 0, "0-59": 0}
        for s in self.students:
            avg = sum(s.scores.values()) / len(COURSE_LIST)
            seg[self.get_score_segment(avg)] += 1
        return seg

    def get_class_score_segments(self) -> Dict[int, Dict[str, int]]:
        class_ids = sorted({s.class_id for s in self.students})
        res = {}
        for cid in class_ids:
            cls_stu = [s for s in self.students if s.class_id == cid]
            seg = {"90-100": 0, "80-89": 0, "70-79": 0, "60-69": 0, "0-59": 0}
            for s in cls_stu:
                avg = sum(s.scores.values()) / len(COURSE_LIST)
                seg[self.get_score_segment(avg)] += 1
            res[cid] = seg
        return res

    def sort_students_by_avg(self, reverse: bool = True) -> List[Tuple[Student, float]]:
        lst = []
        for s in self.students:
            avg = sum(s.scores.values()) / len(COURSE_LIST)
            lst.append((s, round(avg, 2)))
        return sorted(lst, key=lambda x: x[1], reverse=reverse)

    def sort_students_by_class_avg(self, reverse: bool = True) -> Dict[int, List[Tuple[Student, float]]]:
        class_ids = sorted({s.class_id for s in self.students})
        res = {}
        for cid in class_ids:
            cls_stu = [s for s in self.students if s.class_id == cid]
            lst = []
            for s in cls_stu:
                avg = sum(s.scores.values()) / len(COURSE_LIST)
                lst.append((s, round(avg, 2)))
            res[cid] = sorted(lst, key=lambda x: x[1], reverse=reverse)
        return res