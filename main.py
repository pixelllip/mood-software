from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, Dict
from pydantic import BaseModel
from models import Student, COURSE_LIST
from services import StudentScoreService

app = FastAPI(title="学生成绩管理系统API", version="1.0")

origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

service = StudentScoreService()

class StudentCreate(BaseModel):
    class_id: int
    student_id: str
    name: str
    scores: Dict[str, float]

class StudentUpdate(BaseModel):
    name: Optional[str] = None
    class_id: Optional[int] = None
    scores: Optional[Dict[str, float]] = None

@app.post("/students/", summary="新增学生")
def add_student(student: StudentCreate):
    if set(student.scores.keys()) != set(COURSE_LIST):
        raise HTTPException(status_code=400, detail=f"成绩科目必须为：{COURSE_LIST}")
    new_stu = Student(
        class_id=student.class_id,
        student_id=student.student_id,
        name=student.name,
        scores=student.scores
    )
    ok = service.add_student(new_stu)
    if not ok:
        raise HTTPException(status_code=400, detail="学号重复或班级人数已满")
    return {"code": 200, "msg": "添加成功", "data": new_stu.to_dict()}

@app.get("/students/", summary="查询学生")
def get_student(student_id: Optional[str] = None, name: Optional[str] = None):
    if student_id:
        stu = service.get_student_by_id(student_id)
        if not stu:
            raise HTTPException(status_code=404, detail="学生不存在")
        return {"code": 200, "msg": "查询成功", "data": stu.to_dict()}
    elif name:
        stus = service.get_students_by_name(name)
        return {"code": 200, "msg": "查询成功", "data": [s.to_dict() for s in stus]}
    raise HTTPException(status_code=400, detail="请传入学号或姓名")

@app.put("/students/{student_id}", summary="修改学生")
def update_student(student_id: str, data: StudentUpdate):
    update_dict = data.dict(exclude_unset=True)
    if "scores" in update_dict and set(update_dict["scores"].keys()) != set(COURSE_LIST):
        raise HTTPException(status_code=400, detail=f"成绩科目必须为：{COURSE_LIST}")
    ok = service.update_student(student_id, update_dict)
    if not ok:
        raise HTTPException(status_code=404, detail="学生不存在")
    return {"code": 200, "msg": "修改成功"}

@app.delete("/students/{student_id}", summary="删除学生")
def del_student(student_id: str):
    ok = service.delete_student(student_id)
    if not ok:
        raise HTTPException(status_code=404, detail="学生不存在")
    return {"code": 200, "msg": "删除成功"}

@app.get("/stats/grade-avg")
def grade_avg():
    return {"code": 200, "data": service.get_grade_avg_scores()}

@app.get("/stats/class-avg")
def class_avg():
    data = {str(k): v for k, v in service.get_class_avg_scores().items()}
    return {"code": 200, "data": data}

@app.get("/stats/grade-seg")
def grade_seg():
    return {"code": 200, "data": service.get_grade_score_segments()}

@app.get("/stats/class-seg")
def class_seg():
    data = {str(k): v for k, v in service.get_class_score_segments().items()}
    return {"code": 200, "data": data}

@app.get("/stats/grade-sort")
def grade_sort(reverse: bool = True):
    res = service.sort_students_by_avg(reverse)
    data = [{"student": s[0].to_dict(), "avg_score": s[1]} for s in res]
    return {"code": 200, "data": data}

@app.get("/stats/class-sort")
def class_sort(reverse: bool = True):
    raw = service.sort_students_by_class_avg(reverse)
    data = {}
    for cid, lst in raw.items():
        data[str(cid)] = [{"student": s[0].to_dict(), "avg_score": s[1]} for s in lst]
    return {"code": 200, "data": data}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)