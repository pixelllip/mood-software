# ui.py
from PySide6.QtWidgets import (QApplication, QWidget, QPushButton, QLabel, QTextEdit, 
                               QVBoxLayout,QStackedWidget, QHBoxLayout, QListWidget,
                               QComboBox)
from PySide6.QtCore import Qt
from PySide6.QtGui import QTextCursor
from event import MySignal, MySlot
from ai_agent import AI_Agent

class MyWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("我的程序")

        self.stacked_widget = QStackedWidget(self)

        self.mainlayout = QVBoxLayout()

        self.init_chat_ui()
        self.init_backlog_ui()

        self.stacked_widget.addWidget(self.chat_page)   #默认显示聊天界面
        self.stacked_widget.addWidget(self.backlog_page)    #第二页是 Backlog 界面
        self.mainlayout.addWidget(self.stacked_widget)
        self.setLayout(self.mainlayout) # 设置主布局

        # ✅ 1. 创建信号和槽对象
        self.my_signal_obj = MySignal()
        self.my_slot_obj = MySlot()

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

    def init_chat_ui(self):
        """初始化聊天界面"""
        self.chat_page = QWidget()  # 聊天界面容器
        layout = QVBoxLayout()  # 聊天界面布局
        
        # 顶部导航栏
        nav_layout = QHBoxLayout()
        nav_layout.addWidget(QLabel("AI 聊天"))
        btn_go_backlog = QPushButton("查看历史对话记录")
        btn_go_backlog.clicked.connect(lambda: self.switch_page(1))
        nav_layout.addWidget(btn_go_backlog)

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
        btn_back = QPushButton("返回聊天")
        btn_back.clicked.connect(lambda: self.switch_page(0))
        nav_layout.addWidget(btn_back)
        
        # 历史文本内容展示区
        # 这里可以用 QListWidget 展示对话条目，或者 QTextEdit 展示原始 JSON
        self.backlog_display = QListWidget() 
        self.backlog_display.setWordWrap(True)                              # 1. 开启自动换行
        self.backlog_display.setResizeMode(QListWidget.ResizeMode.Adjust)   # 2. 调整调整调整模式，确保宽度变化时内部条目重新计算高度
        
        btn_refresh = QPushButton("刷新记录")
        btn_refresh.clicked.connect(self.load_backlog_data)

        layout.addLayout(nav_layout)
        layout.addWidget(self.backlog_display)
        layout.addWidget(btn_refresh)
        
        self.backlog_page.setLayout(layout)

    def init_schedule_ui(self):
        """初始化 Schedule 界面（如果需要）"""
        pass

    def load_backlog_data(self):
        """从 Agent 的 backlog 文件或内存中加载数据"""
        self.backlog_display.clear()
        # 假设你的 agent 有个 backlog 列表
        backlog = self.agent.backlog
        formatted_list = []
        for msg in backlog.message:  # 假设 backlog.message 是一个包含对话条目的列表
            role = msg.get("role", "unknown")
            content = msg.get("content", "")
            # 格式化成类似 "user: 你好" 的字符串
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