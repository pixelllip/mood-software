# event.py
from PySide6.QtCore import QObject, Signal, Slot, Qt
from PySide6.QtWidgets import QMessageBox

class MySignal(QObject):
    is_finished = Signal()
    text_input = Signal(str)
    text_output = Signal(str) 
    key_pressed = Signal(int, str)
    error = Signal(str)
    
    def __init__(self):
        super().__init__()

class MySlot(QObject):
    def __init__(self):
        super().__init__()
        self.agent = None
    
    def set_agent(self, agent):
        self.agent = agent

    @Slot(str)
    def error_process(self, error_message):
        print(f"收到错误信号: {error_message}") # 调试用：确认槽函数被调用
        
        # ✅ 正确创建并显示 QMessageBox 的方式
        msg_box = QMessageBox() # 传入父窗口，确保模态行为正确
        msg_box.setWindowTitle("错误")
        msg_box.setText(str(error_message)) # 确保转换为字符串
        msg_box.setIcon(QMessageBox.Icon.Critical) # 设置错误图标
        msg_box.setStandardButtons(QMessageBox.StandardButton.Ok)
        msg_box.setWindowFlags(msg_box.windowFlags() | Qt.WindowStaysOnTopHint) # type: ignore
        
        # ✅ 关键：使用 exec() 显示模态对话框
        # exec() 会阻塞代码执行，直到用户点击按钮，这样窗口就不会瞬间消失
        msg_box.exec() 

    @Slot(int, str)
    def on_date_changed(self, date):
        print(f"日期改变了: {date.toString()}") # 调试用：确认槽函数被调用
        return date