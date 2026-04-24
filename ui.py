# ui.py
from PySide6.QtWidgets import (QApplication, QWidget, QPushButton, QLabel, QTextEdit, 
                               QVBoxLayout,QStackedWidget, QHBoxLayout, QListWidget,
                               QFrame, QCalendarWidget)
from PySide6.QtCore import Qt, QDate
from PySide6.QtGui import QTextCursor
from event import MySignal, MySlot
from ai_agent import AI_Agent

class MyWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("我的程序")
        self.resize(800,600)

        # ✅ 1. 创建信号和槽对象
        self.my_signal_obj = MySignal()
        self.my_slot_obj = MySlot()

        self.stacked_widget = QStackedWidget(self)

        self.fun_layout = QVBoxLayout() # 存放实际功能界面
        self.mainlayout = QHBoxLayout() # 主布局，水平分布导航和功能区

        self.init_navigation_ui()
        self.init_chat_ui()
        self.init_backlog_ui()
        self.init_schedule_ui()
        self.init_score_ui()
        
        self.stacked_widget.addWidget(self.chat_page)   #默认显示聊天界面
        self.stacked_widget.addWidget(self.backlog_page)    #第二页是 历史记录 界面
        self.stacked_widget.addWidget(self.schedule_page)    #第三页占位，日程安排界面（如果需要）可以在这里添加
        self.fun_layout.addWidget(self.stacked_widget)
        self.stacked_widget.addWidget(self.score_page)

        self.setLayout(self.mainlayout) # 设置主布局
        self.mainlayout.addLayout(self.fun_layout,4) # 将功能布局添加到主布局

        # ✅ 3. 连接发送的信息到槽
        # 注意：这里需要把 agent 传递给 slot，或者让 slot 能访问到 agent
        # 为了简单演示，我们假设 agent 是全局的或者通过其他方式注入
        # 更优雅的方式是让 MySlot 持有 agent 引用，见下方 event.py 修改
        self.agent = AI_Agent()  # 在窗口中创建 agent 实例，方便管理
        
        # 重新设计连接方式：让 slot 知道 agent 是谁
        self.my_slot_obj.set_agent(self.agent)

        # ✅ 关键连接：将 AI 的输出信号直接连接到 UI 更新方法
        # 这样就不需要经过 MySlot 来处理 UI 更新了，解耦更清晰
        self.agent.signal.text_output.connect(self.append_ai_text)
        self.agent.signal.is_finished.connect(self.on_ai_finished)
        self.agent.signal.error.connect(self.my_slot_obj.error_process)  # 连接错误信号到槽函数
        self.agent.check_api_key()

        # ✅ 5. 连接按钮点击
        self.btn_send.clicked.connect(self.emit_custom_signal)

        self.input.installEventFilter(self)  # 安装事件过滤器，捕获 Enter 键

    def init_navigation_ui(self):
        """初始化导航界面（如果需要）"""
        nav_layout = QVBoxLayout()

        # --- 1. 日期选择区域 ---
        date_label = QLabel("选择查询日期:")
        date_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        nav_layout.addWidget(date_label)

        # 使用 QCalendarWidget (直观的日历)
        self.calendar = QCalendarWidget()
        self.calendar.setGridVisible(True)
        self.calendar.setFixedHeight(200)
        # 设置默认选择今天
        self.calendar.setSelectedDate(QDate.currentDate())
        self.selected_date=self.calendar.setSelectedDate
        # 当日期改变时触发方法
        self.calendar.clicked.connect(self.my_slot_obj.on_date_changed)
        nav_layout.addWidget(self.calendar)

        btn_go_backlog = QPushButton("聊天")
        btn_go_backlog.clicked.connect(lambda: self.switch_page(0))
        nav_layout.addWidget(btn_go_backlog)

        btn_back = QPushButton("历史记录")
        btn_back.clicked.connect(lambda: self.switch_page(1))
        nav_layout.addWidget(btn_back)

        btn_schedule = QPushButton("日程安排")
        btn_schedule.clicked.connect(lambda: self.switch_page(2))
        nav_layout.addWidget(btn_schedule)
        
        btn_score = QPushButton("成绩管理")
        btn_score.clicked.connect(lambda: self.switch_page(3))
        nav_layout.addWidget(btn_score)

        self.mainlayout.addLayout(nav_layout,1) # 将导航布局添加到主布局
        nav_layout.addStretch() # 将所有加入的功能置顶

    def init_chat_ui(self):
        """初始化聊天界面"""
        self.chat_page = QWidget()  # 聊天界面容器
        layout = QVBoxLayout()  # 聊天界面主布局
        
        # 顶部导航栏
        nav_layout = QHBoxLayout()
        nav_layout.addWidget(QLabel("AI 聊天"))
        layout.addLayout(nav_layout)

        # 聊天显示区和输入区
        self.output = QTextEdit(self)
        self.output.setReadOnly(True)  # 设置为只读，用户不能手动修改AI回复
        self.output.setPlaceholderText("AI 回答将显示在这里...")

        self.input = QTextEdit(self)
        self.input.setPlaceholderText("请输入文本...")
        self.input.setMaximumHeight(100)  # 限制输入框高度

        # 发送按钮和状态标签
        self.btn_send = QPushButton("发送", self)
        self.label = QLabel("标签", self)
        self.label.setText("你好")
        self.label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        
        # 调整布局顺序：通常输入在下，输出在上，或者根据需求
        layout.addWidget(self.label)
        layout.addWidget(self.output)  # 添加输出框
        layout.addWidget(self.input)   # 添加输入框
        layout.addWidget(self.btn_send)     # 添加按钮
        
        self.chat_page.setLayout(layout)    # 设置chat_page的布局

    def init_backlog_ui(self):
        """初始化 Backlog 界面"""
        self.backlog_page = QWidget()   # Backlog界面容器
        layout = QVBoxLayout()

        # 顶部导航栏
        nav_layout = QHBoxLayout()
        nav_layout.addWidget(QLabel("历史对话记录"), alignment=Qt.AlignmentFlag.AlignCenter)
        
        # 历史文本内容展示区
        # 这里可以用 QListWidget 展示对话条目，或者 QTextEdit 展示原始 JSON
        self.backlog_display = QListWidget() 
        self.backlog_display.setWordWrap(True)                              # 1. 开启自动换行
        self.backlog_display.setResizeMode(QListWidget.ResizeMode.Adjust)   # 2. 调整调整调整模式，确保宽度变化时内部条目重新计算高度

        layout.addLayout(nav_layout)
        layout.addWidget(self.backlog_display)
        
        self.backlog_page.setLayout(layout)

    def init_schedule_ui(self):
        """初始化 Schedule 界面（如果需要）"""
        self.schedule_page = QWidget()  # Schedule界面容器
        layout = QVBoxLayout()
        nav_layout = QHBoxLayout()
        nav_layout.addWidget(QLabel("日程安排"), alignment=Qt.AlignmentFlag.AlignCenter)

        self.schedule_display = QTextEdit()
        self.schedule_display.setReadOnly(True)

        layout.addLayout(nav_layout)
        layout.addWidget(self.schedule_display)
        self.schedule_page.setLayout(layout)
    
    def init_score_ui(self):
        """初始化成绩管理界面"""
        from tools import AgentTools
        self.score_page = QWidget()
        layout = QVBoxLayout()
    
        title = QLabel("成绩管理")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)
    
        from PySide6.QtWidgets import QTabWidget, QFormLayout, QLineEdit, QPushButton, QTextEdit, QLabel as QLabel2
        
        tabs = QTabWidget()

        query_widget = QWidget()
        query_layout = QVBoxLayout()
        form = QFormLayout()
        self.query_sid = QLineEdit()
        self.query_name = QLineEdit()
        form.addRow("学号:", self.query_sid)
        form.addRow("姓名:", self.query_name)
        query_btn = QPushButton("查询")
        self.query_result = QTextEdit()
        self.query_result.setReadOnly(True)
        query_layout.addLayout(form)
        query_layout.addWidget(query_btn)
        query_layout.addWidget(self.query_result)
        query_widget.setLayout(query_layout)
        
        # 查询按钮点击事件（放在类的方法中，后面定义）
        query_btn.clicked.connect(self.on_query_score)
    
        add_widget = QWidget()
        add_layout = QVBoxLayout()
        add_form = QFormLayout()
        self.add_class = QLineEdit()
        self.add_sid = QLineEdit()
        self.add_name = QLineEdit()
        self.add_math = QLineEdit()
        self.add_se = QLineEdit()
        self.add_prog = QLineEdit()
        add_form.addRow("班级ID:", self.add_class)
        add_form.addRow("学号:", self.add_sid)
        add_form.addRow("姓名:", self.add_name)
        add_form.addRow("高数:", self.add_math)
        add_form.addRow("软件工程:", self.add_se)
        add_form.addRow("程序设计:", self.add_prog)
        add_btn = QPushButton("添加")
        self.add_result = QLabel2()
        add_layout.addLayout(add_form)
        add_layout.addWidget(add_btn)
        add_layout.addWidget(self.add_result)
        add_widget.setLayout(add_layout)
        add_btn.clicked.connect(self.on_add_score)
    
        # ---- 删除页 ----
        del_widget = QWidget()
        del_layout = QVBoxLayout()
        del_form = QFormLayout()
        self.del_sid = QLineEdit()
        del_form.addRow("学号:", self.del_sid)
        del_btn = QPushButton("删除")
        self.del_result = QLabel2()
        del_layout.addLayout(del_form)
        del_layout.addWidget(del_btn)
        del_layout.addWidget(self.del_result)
        del_widget.setLayout(del_layout)
        del_btn.clicked.connect(self.on_delete_score)
        
        tabs.addTab(query_widget, "查询")
        tabs.addTab(add_widget, "添加")
        tabs.addTab(del_widget, "删除")
    
        layout.addWidget(tabs)
        self.score_page.setLayout(layout)
    
    def load_backlog_data(self):
        """从 Agent 的 backlog 文件中加载数据"""
        self.calendar.clicked.connect(self.load_backlog_data)  # 确保每次点击日期都会刷新数据
        self.backlog_display.clear()
        # load_backlog 返回的是字典: {"文件夹/文件名.json": [msg1, msg2, ...]}
        backlog_dict = self.agent.backlog.load_backlog(self.calendar.selectedDate().toString("yyyy-MM-dd"))
        
        if isinstance(backlog_dict, str):  # 错误处理（如目录不存在）
            self.backlog_display.addItem(backlog_dict)
            return

        formatted_list = []
        
        # 遍历字典的每一个文件内容
        for file_key, messages in (backlog_dict or {}).items():
            # 如果你想区分文件，可以加个分割线
            formatted_list.append(f"--- File: {file_key} ---")
            
            for msg in messages:  
                role = msg.get("role", "unknown")
                content = msg.get("content", "")
                formatted_list.append(f"{role}: {content}")
                
        self.backlog_display.addItems(formatted_list)
        
    def switch_page(self, index):
        """切换界面索引"""
        if index == 1:
            self.load_backlog_data() # 进入 backlog 页面时自动刷新
        self.stacked_widget.setCurrentIndex(index)

    def emit_custom_signal(self):
        """中间层：将输入文本转换为自定义信号"""
        text = self.input.toPlainText().strip()
        if text:
            # 清理界面
            self.output.clear()
            self.btn_send.setEnabled(False)  # 禁用按钮防止连续点击导致线程冲突
            self.label.setText("AI 正在思考...")

            # 配置线程并启动
            self.agent.set_input(text)
            self.agent.start()  # ✅ 启动子线程，不会卡死 UI

            self.input.clear()
            self.input.setFocus()

    def append_ai_text(self, text_chunk):
        """
        由 AI 信号触发，在主线程中执行。
        将流式文本追加到输出框。
        """
        # 1. 获取当前光标对象
        cursor = self.output.textCursor()
        
        # 2. 移动光标到末尾
        """（为什么要移？ 因为如果用户在输出过程中，
        不小心点击了文本框中间，光标就会停在中间。如果没有这一行，
        AI 的新回复就会插在用户点击的地方，导致整段话乱序。）"""
        cursor.movePosition(QTextCursor.MoveOperation.End)
        
        # 3. 将修改后的光标设置回控件
        self.output.setTextCursor(cursor)
        
        # 4. 插入文本
        self.output.insertPlainText(text_chunk)
        
        # 5. 自动滚动到底部 (确保用户能看到最新文字)
        self.output.ensureCursorVisible()

    def on_ai_finished(self):
        """AI回复结束时，告诉用户回复完成"""
        self.label.setText("AI 回复完成")
        self.btn_send.setEnabled(True) # 重新启用按钮
    
    def on_query_score(self):
        from tools import AgentTools
        tools = AgentTools()
        student_id = self.query_sid.text().strip()
        name = self.query_name.text().strip()
        if not student_id and not name:
            self.query_result.setText("请填写学号或姓名")
            return
    # 为了避免阻塞 UI，使用 QThread（简单起见，先直接调用，因为查询通常很快）
    # 如果你担心阻塞，可以像 AI_Agent 一样用线程，但推荐先用同步方式
        try:
            result = tools.studentscorequery("query", student_id=student_id, name=name)
            self.query_result.setText(str(result))
        except Exception as e:
            self.query_result.setText(f"查询失败: {e}")

    def on_add_score(self):
        from tools import AgentTools
        tools = AgentTools()
        try:
            class_id = int(self.add_class.text().strip())
            student_id = self.add_sid.text().strip()
            name = self.add_name.text().strip()
            scores = {
                "高数": float(self.add_math.text().strip() or 0),
                "软件工程": float(self.add_se.text().strip() or 0),
                "程序设计": float(self.add_prog.text().strip() or 0)
            }
            if not student_id or not name:
                self.add_result.setText("学号和姓名不能为空")
                return
            result = tools.studentscoreadd(class_id, student_id, name, scores)
            self.add_result.setText(str(result))
        except Exception as e:
            self.add_result.setText(f"添加失败: {e}")

    def on_delete_score(self):
        from tools import AgentTools
        tools = AgentTools()
        student_id = self.del_sid.text().strip()
        if not student_id:
            self.del_result.setText("学号不能为空")
            return
        try:
            result = tools.studentscoredelete(student_id)
            self.del_result.setText(str(result))
        except Exception as e:
            self.del_result.setText(f"删除失败: {e}")

    def center(self):
        # 得到一个表示窗口框架的矩形
        frame_geometry = self.frameGeometry()
        # 获取屏幕中心点
        center_point = self.screen().availableGeometry().center()
        # 将矩形的中心移动到屏幕中心
        frame_geometry.moveCenter(center_point)
        # 移动窗口左上角到矩形左上角
        self.move(frame_geometry.topLeft())

    def eventFilter(self, obj, event):
        if obj is self.input and event.type() == event.Type.KeyPress:
            if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
                # Shift + Enter: 允许换行（返回 False 让事件继续传递）
                if event.modifiers() & Qt.KeyboardModifier.ShiftModifier:
                    return False
                
                # 纯 Enter: 触发点击并拦截换行
                self.btn_send.animateClick()
                return True # 返回 True 表示事件已处理，不再向下传递
                
        return super().eventFilter(obj, event)

if __name__ == "__main__":
    app = QApplication([])
    window = MyWindow()
    window.show()
    window.center()
    app.exec()