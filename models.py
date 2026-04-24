from dataclasses import dataclass, asdict
from typing import List, Dict, Optional

COURSE_LIST = ["高数", "软件工程", "程序设计"]

@dataclass
class Student:
    class_id: int
    student_id: str
    name: str
    scores: Dict[str, float]

    def to_dict(self):
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict):
        return cls(
            class_id=data["class_id"],
            student_id=data["student_id"],
            name=data["name"],
            scores=data["scores"]
        )