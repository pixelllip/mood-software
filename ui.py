# ui.py
from PySide6.QtWidgets import (QApplication, QWidget, QPushButton, QLabel, QTextEdit, 
                               QVBoxLayout,QStackedWidget, QHBoxLayout, QListWidget,
                               QFrame, QCalendarWidget, QSizePolicy,QMessageBox,QCheckBox)
from PySide6.QtCore import Qt, QDate,QThread, Signal, QTimer
from PySide6.QtGui import QTextCursor, QFont
from event_handle import MySignal, MySlot
from ai_agent import AI_Agent
from Tools.Task.TaskOrganizer import TaskOrganizer
from Tools.Score_Management.services import StudentScoreService
import re
import os
import json
from pathlib import Path
from datetime import datetime
from Tools.Score_Management.services import StudentScoreService

class ScheduleGenThread(QThread):
    finished_with_text = Signal(str, str, str)  # plan_text, date_str, picked_note
    failed = Signal(str)

    def __init__(
        self,
        agent: AI_Agent,
        *,
        date_str: str,
        student_profile: dict,
        wake_time: str,
        sleep_time: str,
        picked_note: str,
        not_before_time: str | None = None,
        exclude_subjects: list[str] | None = None,
    ):
        super().__init__()
        self._agent = agent
        self._date_str = date_str
        self._student_profile = student_profile
        self._wake_time = wake_time
        self._sleep_time = sleep_time
        self._picked_note = picked_note
        self._not_before_time = not_before_time
        self._exclude_subjects = exclude_subjects or []

    def run(self):
        try:
            plan_text = self._agent.generate_tomorrow_study_schedule(
                date=self._date_str,
                student_profile=self._student_profile,
                wake_time=self._wake_time,
                sleep_time=self._sleep_time,
                not_before_time=self._not_before_time,
                exclude_subjects=self._exclude_subjects,
            )
            if not plan_text or not str(plan_text).strip():
                self.failed.emit("AI 未返回有效的日程文本。")
                return
            self.finished_with_text.emit(str(plan_text).strip(), self._date_str, self._picked_note)
        except Exception as e:
            self.failed.emit(str(e))

class MyWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("学习助手")
        self.resize(980, 680)
        self.setMinimumSize(880, 620)

        # ✅ 1. 创建信号和槽对象
        self.event_handler = MySlot()

        self.stacked_widget = QStackedWidget(self)

        self.fun_layout = QVBoxLayout() # 存放实际功能界面
        self.mainlayout = QHBoxLayout() # 主布局，水平分布导航和功能区

        # 设置项（持久化）
        self.settings = self._load_settings()
        self._apply_styles(self.settings.get("theme", "light"))

        self.init_navigation_ui()
        self.init_chat_ui()
        self.init_backlog_ui()
        self.init_schedule_ui()
        self.init_score_ui()
        self.init_settings_ui()

        # 启动后提醒今日是否有日程（避免阻塞初始化）
        QTimer.singleShot(0, self.remind_today_schedule)
        
        self.stacked_widget.addWidget(self.chat_page)   #默认显示聊天界面
        self.stacked_widget.addWidget(self.backlog_page)    #第二页是 历史记录 界面
        self.stacked_widget.addWidget(self.schedule_page)    #第三页占位，日程安排界面（如果需要）可以在这里添加
        self.fun_layout.addWidget(self.stacked_widget)
        self.stacked_widget.addWidget(self.score_page)
        self.stacked_widget.addWidget(self.settings_page)

        self.setLayout(self.mainlayout) # 设置主布局
        self.mainlayout.addLayout(self.fun_layout,4) # 将功能布局添加到主布局

        # ✅ 3. 连接发送的信息到槽
        # 注意：这里需要把 agent 传递给 slot，或者让 slot 能访问到 agent
        # 为了简单演示，我们假设 agent 是全局的或者通过其他方式注入
        # 更优雅的方式是让 MySlot 持有 agent 引用，见下方 event.py 修改
        self.agent = AI_Agent()  # 在窗口中创建 agent 实例，方便管理
        self.task_organizer = TaskOrganizer(self.agent.tool)
        self.signal = MySignal()
        # ✅ 关键连接：将 AI 的输出信号直接连接到 UI 更新方法
        # 这样就不需要经过 MySlot 来处理 UI 更新了，解耦更清晰
        self.agent.signal.text_output.connect(self.append_ai_text)
        self.agent.signal.is_finished.connect(self.on_ai_finished)
        self.agent.signal.error.connect(self.event_handler.error_process)  # 连接错误信号到槽函数
        self.agent.check_api_key()

        # ✅ 5. 连接按钮点击
        self.btn_send.clicked.connect(self.emit_custom_signal)

        self.input.installEventFilter(self)  # 安装事件过滤器，捕获 Enter 键

        # 日历点击统一走路由（按页面启用/禁用）
        self.calendar.clicked.connect(self._on_calendar_clicked_router)
        # 默认在聊天页：禁用日历（只允许在“聊天历史记录/日程安排”更改）
        self._set_calendar_enabled_for_page(self.stacked_widget.currentIndex())

    def _apply_styles(self, theme: str = "light"):
        """统一字体（Windows 下观感更稳定）"""
        self.setFont(QFont("NOTOSANS", 10))
        # 设计两套基础样式（light/dark），覆盖常用控件，保持整体风格一致
        self._qss_light = """
        QWidget { background: #e3e7ee; color: #0f172a; }
        QFrame#NavPanel { background: #eceff4; border: 1px solid #000000; border-radius: 14px; }
        QLabel#PageTitle { font-size: 16px; font-weight: 700; color: #0f172a; }
        QLabel#StatusLabel { padding: 10px 12px; background: #eceff4; border: 1px solid #000000; border-radius: 12px; color: #334155; }

        QPushButton { background: #eceff4; border: 1px solid #000000; border-radius: 10px; padding: 8px 12px; }
        QPushButton:hover { border-color: #000000; background: #e3e7ee; }
        QPushButton:pressed { background: #eef2ff; border-color: #000000; }
        QPushButton:disabled { background: #f1f5f9; color: #94a3b8; border-color: #000000; }

        QPushButton#PrimaryButton { background: #4f46e5; color: #ffffff; border: 1px solid #4f46e5; }
        QPushButton#PrimaryButton:hover { background: #4338ca; border-color: #4338ca; }
        QPushButton#DangerButton { background: #ffffff; color: #b91c1c; border: 1px solid #fecaca; }
        QPushButton#DangerButton:hover { background: #fef2f2; border-color: #fca5a5; }

        QTextEdit, QLineEdit, QListWidget, QComboBox { background: #f0f2f5; border: 1px solid #000000; border-radius: 12px; padding: 10px; selection-background-color: #c7d2fe; }
        QTextEdit:focus, QLineEdit:focus, QListWidget:focus, QComboBox:focus { border-color: #000000; }

        QTabWidget::pane { border: 1px solid #000000; border-radius: 12px; top: -1px; background: #f0f2f5; }
        QTabBar::tab { background: #e3e7ee; border: 1px solid #000000; padding: 8px 12px; border-top-left-radius: 10px; border-top-right-radius: 10px; margin-right: 6px; }
        QTabBar::tab:selected { background: #f0f2f5; border-bottom-color: #f0f2f5; }

        QCalendarWidget QWidget { background: transparent; }
        QCalendarWidget QWidget#qt_calendar_navigationbar { min-height: 36px; max-height: 36px; }
        QCalendarWidget QToolButton { background: #eceff4; border: 1px solid #000000; border-radius: 10px; padding: 6px 10px; min-height: 28px; }
        QCalendarWidget QToolButton#qt_calendar_prevmonth,
        QCalendarWidget QToolButton#qt_calendar_nextmonth { min-width: 28px; }
        QCalendarWidget QToolButton#qt_calendar_monthbutton { min-width: 92px; }
        QCalendarWidget QToolButton#qt_calendar_yearbutton { min-width: 72px; }
        QCalendarWidget QAbstractItemView { background: #f0f2f5; border: 1px solid #000000; border-radius: 12px; outline: 0; }
        QCalendarWidget QAbstractItemView::item:hover { background: #dbe2ef; }
        QCalendarWidget QAbstractItemView::item:selected { background: #2563eb; color: #ffffff; border: 1px solid #000000; }
        """

        self._qss_dark = """
        QWidget { background: #121417; color: #e6e7ea; }
        QFrame#NavPanel { background: #171a1f; border: 1px solid #2a2f36; border-radius: 14px; }
        QLabel#PageTitle { font-size: 16px; font-weight: 700; color: #f2f3f5; }
        QLabel#StatusLabel { padding: 10px 12px; background: #171a1f; border: 1px solid #2a2f36; border-radius: 12px; color: #cfd3d8; }

        QPushButton { background: #171a1f; border: 1px solid #2a2f36; border-radius: 10px; padding: 8px 12px; }
        QPushButton:hover { border-color: #3a424c; background: #1b1f25; }
        QPushButton:pressed { background: #12171d; border-color: #64748b; }
        QPushButton:disabled { background: #14171c; color: #7b8491; border-color: #2a2f36; }

        QPushButton#PrimaryButton { background: #64748b; color: #0b0d10; border: 1px solid #64748b; }
        QPushButton#PrimaryButton:hover { background: #7b889b; border-color: #7b889b; }
        QPushButton#DangerButton { background: #171a1f; color: #f2b3b3; border: 1px solid #6b2a2a; }
        QPushButton#DangerButton:hover { background: #1e1618; border-color: #8a3434; }

        QTextEdit, QLineEdit, QListWidget, QComboBox { background: #171a1f; border: 1px solid #2a2f36; border-radius: 12px; padding: 10px; selection-background-color: #64748b; selection-color: #0b0d10; }
        QTextEdit:focus, QLineEdit:focus, QListWidget:focus, QComboBox:focus { border-color: #8a94a3; }

        QTabWidget::pane { border: 1px solid #2a2f36; border-radius: 12px; top: -1px; background: #171a1f; }
        QTabBar::tab { background: #14171c; border: 1px solid #2a2f36; padding: 8px 12px; border-top-left-radius: 10px; border-top-right-radius: 10px; margin-right: 6px; }
        QTabBar::tab:selected { background: #171a1f; border-bottom-color: #171a1f; }

        QCalendarWidget QWidget { background: transparent; }
        QCalendarWidget QWidget#qt_calendar_navigationbar { min-height: 36px; max-height: 36px; }
        QCalendarWidget QToolButton { background: #171a1f; border: 1px solid #2a2f36; border-radius: 10px; padding: 6px 10px; color: #ffffff; min-height: 28px; }
        QCalendarWidget QToolButton#qt_calendar_prevmonth,
        QCalendarWidget QToolButton#qt_calendar_nextmonth,
        QCalendarWidget QToolButton#qt_calendar_monthbutton,
        QCalendarWidget QToolButton#qt_calendar_yearbutton { color: #ffffff; }
        QCalendarWidget QToolButton#qt_calendar_prevmonth,
        QCalendarWidget QToolButton#qt_calendar_nextmonth { min-width: 28px; }
        QCalendarWidget QToolButton#qt_calendar_monthbutton { min-width: 92px; }
        QCalendarWidget QToolButton#qt_calendar_yearbutton { min-width: 72px; }
        QCalendarWidget QToolButton:hover { border-color: #3a424c; background: #1b1f25; }
        QCalendarWidget QToolButton:pressed { background: #12171d; border-color: #64748b; }
        QCalendarWidget QAbstractItemView { background: #171a1f; border: 1px solid #2a2f36; border-radius: 12px; selection-background-color: #64748b; selection-color: #0b0d10; outline: 0; }
        """

        self.apply_theme(theme, persist=False)

    def apply_theme(self, theme: str, *, persist: bool = True):
        """应用主题（light/dark），并可选择是否持久化到设置。"""
        theme = (theme or "").strip().lower()
        if theme not in ("light", "dark"):
            theme = "light"
        qss = self._qss_dark if theme == "dark" else self._qss_light
        self.setStyleSheet(qss)
        if persist:
            self.settings["theme"] = theme
            self._save_settings()

    def init_navigation_ui(self):
        """初始化导航界面"""
        nav_layout = QVBoxLayout()

        # --- 1. 日期选择区域 ---
        date_label = QLabel("选择查询日期:")
        date_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        nav_layout.addWidget(date_label)

        # 使用 QCalendarWidget (直观的日历)
        self.calendar = QCalendarWidget()
        self.calendar.setGridVisible(True)
        # 设置固定宽度，防止月份名称变化时宽度变化
        self.calendar.setFixedWidth(300)
        # 设置星期几的标题为短格式（如"周一"而不是"星期一"）
        self.calendar.setHorizontalHeaderFormat(QCalendarWidget.HorizontalHeaderFormat.ShortDayNames)
        # 设置垂直标题（周数）不显示
        self.calendar.setVerticalHeaderFormat(QCalendarWidget.VerticalHeaderFormat.NoVerticalHeader)
        # 设置导航栏月份按钮的最小宽度，防止月份名称遮挡星期几
        self.calendar.setMinimumWidth(280)
        # 设置默认选择今天
        self.calendar.setSelectedDate(QDate.currentDate())
        self.selected_date=self.calendar.setSelectedDate
        nav_layout.addWidget(self.calendar)

        btn_go_backlog = QPushButton("AI聊天")
        btn_go_backlog.clicked.connect(lambda: self.switch_page(0))
        nav_layout.addWidget(btn_go_backlog)

        btn_back = QPushButton("聊天历史记录")
        btn_back.clicked.connect(lambda: self.switch_page(1))
        nav_layout.addWidget(btn_back)

        btn_schedule = QPushButton("日程安排")
        btn_schedule.clicked.connect(lambda: self.switch_page(2))
        nav_layout.addWidget(btn_schedule)
        
        btn_score = QPushButton("成绩管理")
        btn_score.clicked.connect(lambda: self.switch_page(3))
        nav_layout.addWidget(btn_score)

        self.btn_settings = QPushButton("设置")
        self.btn_settings.clicked.connect(lambda: self.switch_page(4))
        nav_layout.addWidget(self.btn_settings)
        self.mainlayout.addLayout(nav_layout,1) # 将导航布局添加到主布局
        nav_layout.addStretch() # 将所有加入的功能置顶

    def init_chat_ui(self):
        """初始化聊天界面"""
        self.chat_page = QWidget()  # 聊天界面容器
        layout = QVBoxLayout()  # 聊天界面主布局
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)
        
        # 顶部导航栏
        nav_layout = QHBoxLayout()
        nav_layout.setContentsMargins(0, 0, 0, 0)
        nav_layout.setSpacing(8)
        title = QLabel("AI 聊天")
        title.setObjectName("PageTitle")
        nav_layout.addWidget(title)
        nav_layout.addStretch()
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
        self.btn_send.setObjectName("PrimaryButton")
        self.btn_send.setFixedHeight(100)

        self.label = QLabel("就绪", self)
        self.label.setObjectName("StatusLabel")
        self.label.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
        
        input_row = QHBoxLayout()
        input_row.setContentsMargins(0, 0, 0, 0)
        input_row.setSpacing(10)
        input_row.addWidget(self.input, 1)
        input_row.addWidget(self.btn_send, 0)

        layout.addWidget(self.label, 0)
        layout.addWidget(self.output, 1)  # 添加输出框
        layout.addLayout(input_row, 0)
        
        self.chat_page.setLayout(layout)    # 设置chat_page的布局

    def init_backlog_ui(self):
        """初始化 Backlog 界面"""
        self.backlog_page = QWidget()   # Backlog界面容器
        layout = QVBoxLayout()
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)

        # 顶部导航栏
        nav_layout = QHBoxLayout()
        nav_layout.setContentsMargins(0, 0, 0, 0)
        nav_layout.setSpacing(8)
        title = QLabel("聊天历史记录")
        title.setObjectName("PageTitle")
        nav_layout.addWidget(title)
        nav_layout.addStretch()
        
        # 历史文本内容展示区
        # 这里可以用 QListWidget 展示对话条目，或者 QTextEdit 展示原始 JSON
        self.backlog_display = QListWidget() 
        self.backlog_display.setWordWrap(True)                              # 1. 开启自动换行
        self.backlog_display.setResizeMode(QListWidget.ResizeMode.Adjust)   # 2. 调整调整调整模式，确保宽度变化时内部条目重新计算高度

        layout.addLayout(nav_layout)
        layout.addWidget(self.backlog_display)
        
        self.backlog_page.setLayout(layout)

    def init_schedule_ui(self):
        """初始化 Schedule 界面"""
        self.schedule_page = QWidget()  # Schedule界面容器
        layout = QVBoxLayout()
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)

        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.setSpacing(8)
        title = QLabel("日程安排")
        title.setObjectName("PageTitle")
        header.addWidget(title)
        header.addStretch()

        nav_layout = QHBoxLayout()
        nav_layout.setContentsMargins(0, 0, 0, 0)
        nav_layout.setSpacing(10)

        # 顶部“模式切换”按钮
        self.btn_schedule_tab_plan = QPushButton("日程安排")
        self.btn_schedule_tab_today = QPushButton("今日日程")
        self.btn_schedule_tab_plan.clicked.connect(lambda: self.switch_schedule_mode("plan"))
        self.btn_schedule_tab_today.clicked.connect(lambda: self.switch_schedule_mode("today"))
        nav_layout.addWidget(self.btn_schedule_tab_plan)
        nav_layout.addWidget(self.btn_schedule_tab_today)

        # “今日日程”下显示的删除按钮（放在顶部，避免被隐藏）
        self.btn_delete_schedule = QPushButton("删除日程")
        self.btn_delete_schedule.setObjectName("DangerButton")
        self.btn_delete_schedule.clicked.connect(self.on_delete_schedule)
        self.btn_delete_schedule.setVisible(False)
        nav_layout.addWidget(self.btn_delete_schedule)
        nav_layout.addStretch()

        self.schedule_display = QTextEdit()
        self.schedule_display.setReadOnly(True)
        self.schedule_display.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

        # 输入区：学生(成绩) + 作息时间（可选）
        from PySide6.QtWidgets import QLineEdit
        self.schedule_student_id_input = QLineEdit()
        self.schedule_student_id_input.setPlaceholderText("学生学号（用于按成绩生成学习日程，日期由左侧日历决定：今天或之后）")

        self.schedule_student_name_input = QLineEdit()
        self.schedule_student_name_input.setPlaceholderText("学生姓名（可选，支持模糊匹配）")

        self.schedule_wake_time_input = QLineEdit()
        self.schedule_wake_time_input.setPlaceholderText("起床时间 HH:MM（可选，默认 07:00）")

        self.schedule_sleep_time_input = QLineEdit()
        self.schedule_sleep_time_input.setPlaceholderText("睡觉时间 HH:MM（可选，默认 22:30）")

        self.btn_generate_schedule = QPushButton("根据成绩生成指定日期学习日程（今天或之后）")
        self.btn_generate_schedule.setObjectName("PrimaryButton")
        self.btn_generate_schedule.clicked.connect(self.on_generate_schedule)

        # “日程安排”模式控件页（两列并排）
        self.schedule_plan_controls = QWidget()
        plan_layout = QVBoxLayout()
        plan_layout.setContentsMargins(0, 0, 0, 0)
        plan_layout.setSpacing(2)

        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(6)
        col_left = QVBoxLayout()
        col_left.setContentsMargins(0, 0, 0, 0)
        col_left.setSpacing(2)
        col_left.addWidget(QLabel("学生信息（用于按成绩生成）："))
        col_left.addWidget(self.schedule_student_id_input)
        col_left.addWidget(self.schedule_student_name_input)

        col_right = QVBoxLayout()
        col_right.setContentsMargins(0, 0, 0, 0)
        col_right.setSpacing(2)
        col_right.addWidget(QLabel("作息时间（可选）："))
        col_right.addWidget(self.schedule_wake_time_input)
        col_right.addWidget(self.schedule_sleep_time_input)

        row.addLayout(col_left, 1)
        row.addLayout(col_right, 1)
        plan_layout.addLayout(row)
        plan_layout.addWidget(self.btn_generate_schedule)
        self.schedule_plan_controls.setLayout(plan_layout)

        # “今日日程”模式控件页（空，仅显示下方文本框）
        self.schedule_today_controls = QWidget()
        today_layout = QVBoxLayout()
        today_layout.setContentsMargins(0, 0, 0, 0)
        today_layout.setSpacing(0)

        self.schedule_today_controls.setLayout(today_layout)

        self.schedule_mode_stack = QStackedWidget()
        self.schedule_mode_stack.addWidget(self.schedule_plan_controls)   # index 0
        self.schedule_mode_stack.addWidget(self.schedule_today_controls)  # index 1
        self.schedule_mode_stack.setContentsMargins(0, 0, 0, 0)
        # 控件区尽量“按内容高度”，不要把显示框挤到下面
        self.schedule_mode_stack.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)

        layout.addLayout(header)
        layout.addLayout(nav_layout)
        layout.addWidget(self.schedule_mode_stack, 0)
        layout.addWidget(self.schedule_display, 1)
        self.schedule_page.setLayout(layout)

        # 默认进入“日程安排”模式
        self.switch_schedule_mode("plan")

    def switch_schedule_mode(self, mode: str):
        """切换日程界面模式（“日程安排”/“今日日程”）"""
        mode = (mode or "").strip().lower()
        self._schedule_mode = mode if mode in ["today", "plan"] else "plan"
        if mode == "today":
            self.schedule_mode_stack.setCurrentIndex(1)
            # 今日日程：隐藏上方控件容器，让显示框紧贴顶部按钮
            self.schedule_mode_stack.setVisible(False)
            self.btn_delete_schedule.setVisible(True)
            self.on_show_today_schedule()
        else:
            self.schedule_mode_stack.setCurrentIndex(0)
            self.schedule_mode_stack.setVisible(True)
            self.btn_delete_schedule.setVisible(False)
            # 切回“日程安排”时，不应继续显示“今日日程”的内容
            self.schedule_display.setText("请在左侧日历选择日期（今天或之后），在上方输入学号/姓名，然后点击“根据成绩生成指定日期学习日程”。")

    def on_calendar_date_clicked(self, _date):
        """日历日期被点击时的处理：如果在“今日日程”模式，刷新显示框内容。"""
        # 如果当前在“今日日程”模式，点击日历任意日期都刷新显示框
        if getattr(self, "_schedule_mode", "plan") == "today":
            self.on_show_today_schedule()

    def _set_calendar_enabled_for_page(self, index: int):
        """根据当前页面索引启用或禁用日历，只有在“聊天历史记录(1)”与“日程安排(2)”页面启用。"""
        # 只允许在“聊天历史记录(1)”与“日程安排(2)”更改日历日期
        self._calendar_locked = index not in (1, 2)
        self.calendar.setToolTip("仅在“聊天历史记录/日程安排”页面可切换日期" if self._calendar_locked else "")

    def _on_calendar_clicked_router(self, date: QDate):
        """统一的日历点击处理路由，根据当前页面和模式决定如何响应日期变化。"""
        # 只有在允许页面才处理点击（日历在其它页面会被禁用，但这里再兜底一次）
        if getattr(self, "_calendar_locked", False):
            return

        # backlog 页：点击日期刷新记录
        if self.stacked_widget.currentIndex() == 1:
            self.load_backlog_data()

        # 日程页：若处于“今日日程”模式则自动刷新显示
        if self.stacked_widget.currentIndex() == 2:
            self.on_calendar_date_clicked(date)

    def _get_schedules_dir(self) -> Path:
        """获取日程文件夹路径，优先使用环境变量 BASE_PATH 指定的路径，否则使用当前目录下的 Schedules 文件夹。确保文件夹存在。"""
        base_path = os.getenv("BASE_PATH")
        root_dir = Path(base_path) if base_path else Path(__file__).resolve().parent
        out_dir = root_dir / "Schedules"
        out_dir.mkdir(parents=True, exist_ok=True)
        return out_dir

    def _schedule_stable_path(self, date_str: str) -> Path:
        """生成日程文本文件的稳定路径，命名为 schedule_YYYY-MM-DD.txt，放在 BASE_PATH/Schedules/ 下（如果 BASE_PATH 不存在则放在当前目录下的 Schedules/ 中）。"""
        # 固定命名，便于识别与加载：schedule_YYYY-MM-DD.txt
        safe_date = (date_str or "").strip() or datetime.now().strftime("%Y-%m-%d")
        return self._get_schedules_dir() / f"schedule_{safe_date}.txt"

    def _settings_path(self) -> Path:
        """设置文件路径：BASE_PATH/Schedules/settings.json，若 BASE_PATH 不存在则放在当前目录下的 Schedules/ 中。"""
        return self._get_schedules_dir() / "settings.json"

    def _load_settings(self) -> dict:
        """加载设置，若文件不存在或内容无效则返回默认设置。"""
        default = {"schedule_reminder_enabled": True}
        path = self._settings_path()
        if not path.exists():
            return default
        try:
            data = json.loads(path.read_text(encoding="utf-8") or "{}")
            if isinstance(data, dict):
                merged = {**default, **data}
                merged["schedule_reminder_enabled"] = bool(merged.get("schedule_reminder_enabled", True))
                return merged
        except Exception:
            pass
        return default

    def _save_settings(self) -> None:
        """保存设置到文件，失败时静默处理（不影响用户操作）。"""
        try:
            self._settings_path().write_text(json.dumps(self.settings, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass

    def open_settings_dialog(self):
        """打开设置对话框：兼容旧调用，直接切到设置页面。"""
        # 兼容旧调用：不再弹窗，直接切到设置页面
        self.switch_page(4)

    def _reminder_skip_flag_path(self, date_str: str) -> Path:
        """生成“今日提醒跳过”标志文件路径，命名为 reminder_skip_YYYY-MM-DD.flag"""
        safe_date = (date_str or "").strip() or datetime.now().strftime("%Y-%m-%d")
        return self._get_schedules_dir() / f"reminder_skip_{safe_date}.flag"

    def _read_schedule_text(self, date_str: str) -> str:
        """根据日期字符串读取对应的日程文本，优先尝试 UTF-8 编码，失败后尝试 GBK 编码，最终返回文本内容或空字符串。"""
        path = self._schedule_stable_path(date_str)
        if not path.exists():
            return ""
        try:
            return path.read_text(encoding="utf-8").strip()
        except Exception:
            # 兜底：部分 Windows 文本可能是 gbk
            try:
                return path.read_text(encoding="gbk").strip()
            except Exception:
                return ""

    def _extract_reviewed_subjects_before(self, schedule_text: str, *, before_hm: str) -> list[str]:
        """
        从已保存的日程文本中提取“在某个时间点之前已经复习过的科目”。
        约定日程行格式为：HH:MM-HH:MM 任务...
        科目提取策略（尽量稳健）：
        - 优先取“任务”部分在第一个中文冒号/英文冒号前的片段作为科目
        - 否则取任务部分的第一个词
        """
        if not schedule_text or not before_hm:
            return []

        try:
            before_t = datetime.strptime(before_hm, "%H:%M").time()
        except Exception:
            return []

        reviewed: set[str] = set()
        line_re = re.compile(r"^(?P<s>\d{2}:\d{2})-(?P<e>\d{2}:\d{2})\s+(?P<body>.+?)\s*$")
        for raw in schedule_text.splitlines():
            line = raw.strip()
            if not line:
                continue
            m = line_re.match(line)
            if not m:
                continue
            try:
                start_t = datetime.strptime(m.group("s"), "%H:%M").time()
            except Exception:
                continue
            # 只要该时间段开始时间早于“当前时间”，就视为已经复习过（避免重复）
            if not (start_t < before_t):
                continue

            body = (m.group("body") or "").strip()
            if not body:
                continue
            subj = body.split("：", 1)[0].split(":", 1)[0].strip()
            if not subj:
                subj = body.split()[0].strip() if body.split() else ""
            if subj:
                reviewed.add(subj)

        return sorted(reviewed)

    def _save_itinerary_to_txt(self, plan_text: str, date_str: str | None = None) -> str:
        """
        将生成的日程保存为 txt，返回保存路径（字符串）。
        优先保存到 BASE_PATH/Schedules/，否则保存到 ui.py 同目录下的 Schedules/。
        """
        if not plan_text:
            raise ValueError("日程内容为空，无法保存。")

        safe_date = (date_str or "").strip() or datetime.now().strftime("%Y-%m-%d")
        ts = datetime.now().strftime("%H-%M-%S")
        out_dir = self._get_schedules_dir()

        # 1) 带时间戳的历史归档
        archive_path = out_dir / f"itinerary_{safe_date}_{ts}.txt"
        archive_path.write_text(plan_text, encoding="utf-8")

        # 2) 当天稳定文件名（用于“今日日程/启动提醒”直接读取）
        stable_path = self._schedule_stable_path(safe_date)
        stable_path.write_text(plan_text, encoding="utf-8")

        return str(archive_path)

    def on_show_today_schedule(self):
        """展示“今日日程”：根据左侧日历选中日期加载对应的 schedule_YYYY-MM-DD.txt 内容。"""
        # 按左侧日历“当前选中日期”展示日程
        date_str = self.calendar.selectedDate().toString("yyyy-MM-dd")
        text = self._read_schedule_text(date_str)
        if not text:
            self.schedule_display.setText(f"{date_str} 还没有已保存的日程（未找到 schedule_YYYY-MM-DD.txt）。")
            return
        self.schedule_display.setText(text)

    def on_delete_schedule(self):
        """删除“今日日程”：删除对应 schedule_YYYY-MM-DD.txt 文件，并刷新显示。"""
        date_str = self.calendar.selectedDate().toString("yyyy-MM-dd")
        path = self._schedule_stable_path(date_str)
        if not path.exists():
            QMessageBox.information(self, "提示", f"{date_str} 没有可删除的日程文件。")
            self.on_show_today_schedule()
            return

        confirm = QMessageBox.question(
            self,
            "确认删除",
            f"确定要删除 {date_str} 的日程吗？\n\n文件：{path}",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if confirm != QMessageBox.StandardButton.Yes:
            return

        try:
            path.unlink()
            QMessageBox.information(self, "删除成功", f"已删除 {date_str} 的日程。")
        except Exception as e:
            QMessageBox.warning(self, "删除失败", f"删除失败：{e}")
        finally:
            self.on_show_today_schedule()

    def remind_today_schedule(self):
        """确保每次点击日期都会刷新数据"""
        if not bool(getattr(self, "settings", {}).get("schedule_reminder_enabled", True)):
            return
        today_str = QDate.currentDate().toString("yyyy-MM-dd")
        if self._reminder_skip_flag_path(today_str).exists():
            return
        text = self._read_schedule_text(today_str)
        if not text:
            return

        msg = QMessageBox(self)
        msg.setWindowTitle("今日日程提醒")
        preview = text if len(text) <= 400 else (text[:400] + "…")
        msg.setText(f"检测到今日日程（{today_str}）：\n\n{preview}")
        cb = QCheckBox("今日不再提醒")
        msg.setCheckBox(cb)
        btn_open = msg.addButton("打开txt", QMessageBox.ButtonRole.AcceptRole)
        btn_view = msg.addButton("在页面查看", QMessageBox.ButtonRole.ActionRole)
        msg.addButton("关闭", QMessageBox.ButtonRole.RejectRole)
        msg.exec()

        if cb.isChecked():
            try:
                self._reminder_skip_flag_path(today_str).write_text("1", encoding="utf-8")
            except Exception:
                pass

        clicked = msg.clickedButton()
        if clicked == btn_open:
            try:
                os.startfile(str(self._schedule_stable_path(today_str)))  # type: ignore[attr-defined]
            except Exception as e:
                self.event_handler.error_process(f"打开失败：{e}")
        elif clicked == btn_view:
            self.switch_page(2)
            self.schedule_display.setText(text)

    def _get_target_plan_qdate(self) -> QDate:
        """
        生成学习日程的目标日期（由左侧日历选中日期决定）。
        约束：
        - 允许选择“今天”或“未来”
        - 不允许选择“过去”
        """
        selected = self.calendar.selectedDate()
        today = QDate.currentDate()
        if selected < today:
            raise ValueError("不能生成过去日期的日程，请在左侧日历重新选择（今天或之后）。")
        return selected

    def on_generate_schedule(self):
        """根据成绩生成指定日期的学习日程（今天或之后）。"""
        try:
            # 目标日期：由日历选择；必须为今天或之后（禁止过去）
            target_qdate = self._get_target_plan_qdate()
            target_str = target_qdate.toString("yyyy-MM-dd")
            today_str = QDate.currentDate().toString("yyyy-MM-dd")

            not_before_time = None
            if target_str == today_str:
                now_hm = datetime.now().strftime("%H:%M")
                not_before_time = now_hm

            # 按成绩生成“指定日期学习日程（今天或之后）”
            sid = self.schedule_student_id_input.text().strip()
            name = self.schedule_student_name_input.text().strip()
            if not sid and not name:
                self.schedule_display.setText("请先填写学生学号或姓名（用于读取成绩并生成学习日程）。")
                return

            students = self.on_query_score()
            if not students:
                self.schedule_display.setText("未找到该学生的成绩记录。请先在“成绩管理”里录入/更新成绩。")
                return

            student = students[0]
            picked_note = ""
            if len(students) > 1:
                picked_note = f"（提示：匹配到 {len(students)} 条记录，已默认选择：{student.name} / {student.student_id}）\n\n"

            wake_time = (self.schedule_wake_time_input.text().strip() or "07:00").strip()
            sleep_time = (self.schedule_sleep_time_input.text().strip() or "22:30").strip()

            if not_before_time:
                # 若已经过了睡觉时间，就没必要生成“今日剩余日程”
                if not_before_time >= sleep_time:
                    self.schedule_display.setText("当前时间已晚于（或等于）睡觉时间，无法生成“今日剩余日程”。请改选明天或之后的日期。")
                    return

            student_profile = {
                "class_id": getattr(student, "class_id", None),
                "student_id": getattr(student, "student_id", ""),
                "name": getattr(student, "name", ""),
                "scores": getattr(student, "scores", {}) or {},
            }

            exclude_subjects: list[str] = []
            if not_before_time:
                # 今日生成：避免安排今日已经复习过的科目
                existing_text = self._read_schedule_text(today_str)
                if existing_text:
                    exclude_subjects = self._extract_reviewed_subjects_before(existing_text, before_hm=not_before_time)

            # 后台线程生成，避免 UI 卡死
            self.btn_generate_schedule.setEnabled(False)
            self.btn_schedule_tab_today.setEnabled(False)
            self.schedule_display.setText("AI 正在后台生成日程，请稍等…")

            self._schedule_thread = ScheduleGenThread(
                self.agent,
                date_str=target_str,
                student_profile=student_profile,
                wake_time=wake_time,
                sleep_time=sleep_time,
                picked_note=picked_note,
                not_before_time=not_before_time,
                exclude_subjects=exclude_subjects,
            )
            self._schedule_thread.finished_with_text.connect(self._on_schedule_generated)
            self._schedule_thread.failed.connect(self._on_schedule_generate_failed)
            self._schedule_thread.start()
        except Exception as e:
            self.schedule_display.setText(f"生成失败：{str(e)}")

    def _on_schedule_generated(self, plan_text: str, date_str: str, picked_note: str):
        """日程生成成功后的处理：显示日程文本，并保存到 txt 文件。"""
        try:
            saved_path = self._save_itinerary_to_txt(plan_text, date_str=date_str)
            self.schedule_display.setText(f"{picked_note}{plan_text}\n\n—— 已保存到：{saved_path}")
        finally:
            self.btn_generate_schedule.setEnabled(True)
            self.btn_schedule_tab_today.setEnabled(True)

    def _on_schedule_generate_failed(self, msg: str):
        """日程生成失败后的处理：显示错误信息，并恢复按钮状态。"""
        self.schedule_display.setText(f"生成失败：{msg}")
        self.btn_generate_schedule.setEnabled(True)
        self.btn_schedule_tab_today.setEnabled(True)
    
    def init_score_ui(self):
        """初始化成绩管理界面"""
        self.score_page = QWidget()
        layout = QVBoxLayout()
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)

        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.setSpacing(8)
        title = QLabel("成绩管理")
        title.setObjectName("PageTitle")
        header.addWidget(title)
        header.addStretch()
        layout.addLayout(header)
    
        from PySide6.QtWidgets import QTabWidget, QFormLayout, QLineEdit, QPushButton, QTextEdit, QLabel as QLabel2
        
        tabs = QTabWidget()

        # 以下定义查询菜单
        query_widget = QWidget()
        query_layout = QVBoxLayout()
        form = QFormLayout()
        self.query_sid = QLineEdit()    # 学号输入框
        self.query_name = QLineEdit()   # 姓名输入框
        form.addRow("学号:", self.query_sid)
        form.addRow("姓名:", self.query_name)
        query_btn = QPushButton("查询")
        self.query_result = QTextEdit()
        self.query_result.setReadOnly(True)
        query_layout.addLayout(form)
        query_layout.addWidget(query_btn)
        query_layout.addWidget(self.query_result)
        query_widget.setLayout(query_layout)
        query_btn.clicked.connect(self.on_query_score)
        # 关联enter发送
        self.query_sid.installEventFilter(self)
        self.query_name.installEventFilter(self)
    
        # 以下定义添加界面
        add_widget = QWidget()
        add_layout = QVBoxLayout()
        add_form = QFormLayout()
        self.add_class = QLineEdit()
        self.add_sid = QLineEdit()
        self.add_name = QLineEdit()
        self.add_scores = QTextEdit()
        add_form.addRow("班级ID:", self.add_class)
        add_form.addRow("学号:", self.add_sid)
        add_form.addRow("姓名:", self.add_name)
        add_form.addRow("成绩 (格式: 课程:分数, 每行一个):", self.add_scores)
        add_btn = QPushButton("添加")
        self.add_result = QLabel2()
        add_layout.addLayout(add_form)
        add_layout.addWidget(add_btn)
        add_layout.addWidget(self.add_result)
        add_widget.setLayout(add_layout)
        add_btn.clicked.connect(self.on_add_score_clicked)
        # 关联enter发送
        self.add_class.installEventFilter(self)
        self.add_sid.installEventFilter(self)
        self.add_name.installEventFilter(self)
        self.add_scores.installEventFilter(self)
    
        # 以下定义删除界面
        del_widget = QWidget()
        del_layout = QVBoxLayout()
        del_form = QFormLayout()
        self.del_class = QLineEdit()
        self.del_sid = QLineEdit()
        self.del_name = QLineEdit()
        del_form.addRow("班级ID:", self.del_class)
        del_form.addRow("学号:", self.del_sid)
        del_form.addRow("姓名:", self.del_name)
        del_btn = QPushButton("删除")
        self.del_result = QLabel2()
        del_layout.addLayout(del_form)
        del_layout.addWidget(del_btn)
        del_layout.addWidget(self.del_result)
        del_widget.setLayout(del_layout)
        del_btn.clicked.connect(self.on_delete_score_clicked)
        
        tabs.addTab(query_widget, "查询")
        tabs.addTab(add_widget, "添加")
        tabs.addTab(del_widget, "删除")
    
        layout.addWidget(tabs)
        self.score_page.setLayout(layout)
        # 关联enter发送
        self.del_class.installEventFilter(self)
        self.del_sid.installEventFilter(self)
        self.del_name.installEventFilter(self)

    def init_settings_ui(self):
        """初始化设置界面（不使用弹窗，直接页面内设置）"""
        self.settings_page = QWidget()
        layout = QVBoxLayout()
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)

        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.setSpacing(8)
        title = QLabel("设置")
        title.setObjectName("PageTitle")
        header.addWidget(title)
        header.addStretch()
        layout.addLayout(header)

        content = QVBoxLayout()
        content.setContentsMargins(0, 0, 0, 0)
        content.setSpacing(10)

        theme_row = QHBoxLayout()
        theme_row.setContentsMargins(0, 0, 0, 0)
        theme_row.setSpacing(10)
        theme_label = QLabel("主题：")
        theme_label.setMinimumWidth(52)
        theme_row.addWidget(theme_label, 0)

        current_theme = (self.settings.get("theme", "light") or "light").strip().lower()
        self._theme_updating = False
        self.dark_theme_cb = QCheckBox("朦胧灰")
        self.light_theme_cb = QCheckBox("纯净白")
        self.dark_theme_cb.setChecked(current_theme == "dark")
        self.light_theme_cb.setChecked(current_theme != "dark")
        # 用 clicked 而不是 stateChanged：避免互相切换时信号顺序导致“两者都不选”
        self.dark_theme_cb.clicked.connect(self._on_theme_clicked)
        self.light_theme_cb.clicked.connect(self._on_theme_clicked)
        theme_row.addWidget(self.dark_theme_cb, 0)
        theme_row.addWidget(self.light_theme_cb, 0)
        theme_row.addStretch(1)
        content.addLayout(theme_row)

        self.settings_reminder_cb = QCheckBox("启用日程提醒")
        self.settings_reminder_cb.setChecked(bool(self.settings.get("schedule_reminder_enabled", True)))
        self.settings_reminder_cb.stateChanged.connect(self._on_settings_changed)
        content.addWidget(self.settings_reminder_cb)

        hint = QLabel("提示：日程提醒会在程序启动时检测“今日日程”并提示。")
        hint.setStyleSheet("color: #64748b;")
        hint.setWordWrap(True)
        content.addWidget(hint)

        content.addStretch()
        layout.addLayout(content, 1)
        self.settings_page.setLayout(layout)

    def _on_theme_clicked(self, checked: bool):
        """主题选择的强约束逻辑：不允许两者都不选，必须始终保持至少一个主题被选中。"""
        if getattr(self, "_theme_updating", False):
            return
        self._theme_updating = True
        try:
            sender = self.sender()

            # 强约束：不允许“取消当前主题”导致两者都不选
            if sender is self.dark_theme_cb:
                if checked:
                    self.light_theme_cb.blockSignals(True)
                    self.light_theme_cb.setChecked(False)
                    self.light_theme_cb.blockSignals(False)
                else:
                    self.dark_theme_cb.blockSignals(True)
                    self.dark_theme_cb.setChecked(True)
                    self.dark_theme_cb.blockSignals(False)
            elif sender is self.light_theme_cb:
                if checked:
                    self.dark_theme_cb.blockSignals(True)
                    self.dark_theme_cb.setChecked(False)
                    self.dark_theme_cb.blockSignals(False)
                else:
                    self.light_theme_cb.blockSignals(True)
                    self.light_theme_cb.setChecked(True)
                    self.light_theme_cb.blockSignals(False)

            theme = "dark" if bool(self.dark_theme_cb.isChecked()) else "light"
            self.apply_theme(theme, persist=True)
        finally:
            self._theme_updating = False

    def _on_settings_changed(self):
        """当设置项发生变化时更新设置字典并保存。"""
        self.settings["schedule_reminder_enabled"] = bool(self.settings_reminder_cb.isChecked())
        self._save_settings()
    
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
        """点击“查询”按钮查询学生成绩，名字可以模糊搜索
        
        仅当当前显示的是 Schedule 界面时，才读取 schedule_student_id_input 和 schedule_student_name_input 的输入
        """
        student_id = ""
        name = ""
        
        # 检查当前是否在 Schedule 界面
        is_schedule_page = False
        if hasattr(self, 'stacked_widget'):
            current_widget = self.stacked_widget.currentWidget()
            if hasattr(self, 'schedule_page') and current_widget == self.schedule_page:
                is_schedule_page = True
        
        # 如果在 Schedule 界面，优先使用 schedule 界面的输入框
        if is_schedule_page:
            if hasattr(self, 'schedule_student_id_input') and self.schedule_student_id_input:
                student_id = self.schedule_student_id_input.text().strip()
            
            if hasattr(self, 'schedule_student_name_input') and self.schedule_student_name_input:
                name = self.schedule_student_name_input.text().strip()
        else:
            # 不在 Schedule 界面，使用成绩查询界面的输入框
            student_id = self.query_sid.text().strip()
            name = self.query_name.text().strip()
        
        if not student_id and not name:
            self.query_result.setText("请填写学号或姓名")
            return   
        
        to_search = StudentScoreService()
        query_result = to_search.get_student_by_id(student_id)
        if not query_result:
            query_result = to_search.get_students_by_name(name)
            if not query_result:
                query_result = [s for s in to_search.students if name.lower() in s.name.lower()]
        display_text = ""

        for s in query_result:
            # 提取各个属性，分类拼接
            info = f"【姓名】: {s.name:<8} 【学号】: {s.student_id}\n"
            score_items = [f"{k:<8}: {v:>6.1f}" for k, v in s.scores.items()]
            scores = "【成绩】:\n\t" + ",\n\t".join(score_items)
            display_text += info + scores + "\n" + "-"*30 + "\n"

        self.query_result.setText(display_text)
        return query_result

    def on_add_score_clicked(self):
        """处理成绩管理界面“添加”按钮的点击事件"""
        # 1. 获取前端输入的数据
        class_id_str = self.add_class.text().strip()
        sid = self.add_sid.text().strip()
        name = self.add_name.text().strip()
        scores_raw = self.add_scores.toPlainText().strip()

        msg=""

        # 2. 基础数据校验
        if not sid or not name:
            self.add_result.setText("错误：学号和姓名不能为空！")
            return

        # 3. 解析成绩字符串 (格式: 课程:分数)
        new_scores = {}
        for line in scores_raw.splitlines():
            match = re.split(r'[:：=]', line, maxsplit=1)
            if len(match) == 2:
                course, score = match
            try:
                new_scores[course.strip()] = float(score.strip())
                to_add = StudentScoreService()
                msg+=f"{to_add.add_score(int(class_id_str), sid, name, new_scores)}\n" # 此处开始执行添加信息的方法
            except ValueError:
                self.add_result.setText("")
                self.event_handler._show_message("输入非法", "成绩格式必须为 数字 (例如 英语:95.5)", QMessageBox.Icon.Critical)
                break
        
        self.add_result.setText(msg)

    def on_delete_score_clicked(self):
        """处理成绩管理界面“删除”按钮的点击事件"""
        class_id = self.del_class.text().strip()
        sid = self.del_sid.text().strip()
        name = self.del_name.text().strip()

        if not sid and not (class_id and name):
            # 替换用法 1: 警告弹窗
            self.event_handler._show_message(
                title="输入错误",
                text="请提供【学号】或【班级+姓名】以进行删除。",
                icon=QMessageBox.Icon.Warning
            )
            return

        confirm_msg = f"学号为 {sid}" if sid else f"班级为 {class_id} 的 {name}"
        
        # 替换用法 2: 询问弹窗
        reply = self.event_handler._show_message(
            title="确认删除",
            text=f"您确定要删除 {confirm_msg} 的学生信息吗？",
            icon=QMessageBox.Icon.Question,
            buttons=QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            default_btn=QMessageBox.StandardButton.No
        )

        if reply == QMessageBox.StandardButton.Yes:
            try:
                service = StudentScoreService() 
                success = service.delete_student(class_id, sid, name)
                
                if success:
                    # 替换用法 3: 信息提示
                    self.event_handler._show_message("成功", "学生信息已成功删除。")
                else:
                    self.event_handler._show_message("失败", "未找到符合条件的记录。", QMessageBox.Icon.Warning)
                    
            except Exception as e:
                # 替换用法 4: 错误提示
                self.event_handler._show_message("错误", f"删除过程中发生异常: {str(e)}", QMessageBox.Icon.Critical)

    def center(self):
        """将窗口居中显示"""
        # 得到一个表示窗口框架的矩形
        frame_geometry = self.frameGeometry()
        # 获取屏幕中心点
        center_point = self.screen().availableGeometry().center()
        # 将矩形的中心移动到屏幕中心
        frame_geometry.moveCenter(center_point)
        # 移动窗口左上角到矩形左上角
        self.move(frame_geometry.topLeft())

    def eventFilter(self, obj, event):
        """捕捉Enter键，支持 Shift+Enter 换行，纯 Enter 触发提交"""
        # 日历：在非“聊天历史记录/日程安排”页面锁定日期切换，但保持外观不变
        if obj is getattr(self, "calendar", None) and getattr(self, "_calendar_locked", False):
            if event.type() in (
                event.Type.MouseButtonPress,
                event.Type.MouseButtonRelease,
                event.Type.MouseButtonDblClick,
                event.Type.Wheel,
                event.Type.KeyPress,
                event.Type.KeyRelease,
            ):
                return True

        input_box = getattr(self, "input", None)
        if obj is input_box and event.type() == event.Type.KeyPress:
            if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
                
                # 判断是否按下了 Shift 键
                is_shift_pressed = event.modifiers() & Qt.KeyboardModifier.ShiftModifier
                
                # 1. 如果按下了 Shift + Enter
                if is_shift_pressed:
                    # 如果是多行文本框 (QTextEdit)，允许换行
                    if isinstance(obj, QTextEdit):
                        return False  # 返回 False 让系统处理换行
                    # 如果是单行文本框 (QLineEdit)，Shift+Enter 通常没意义，直接拦截不响应即可
                    return True 

                # 2. 如果只按了 Enter (不带 Shift)
                
                # 聊天界面
                if obj is self.input:
                    self.btn_send.animateClick()
                    return True 
                
                # 查询界面 (QLineEdit)
                elif obj in (self.query_sid, self.query_name):
                    self.on_query_score()
                    return True

                # 添加界面 (包括多行的 self.add_scores)
                elif obj in (self.add_class, self.add_sid, self.add_name, self.add_scores):
                    self.on_add_score_clicked()
                    return True

                # 删除界面
                elif obj in (self.del_class, self.del_sid, self.del_name):
                    self.on_delete_score_clicked()
                    return True
                    
        return super().eventFilter(obj, event)

if __name__ == "__main__":
    app = QApplication([])
    window = MyWindow()
    window.show()
    window.center()
    app.exec()