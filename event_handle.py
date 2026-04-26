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

    # --- 统一弹窗助手 ---
    def _show_message(self, title, text, icon=QMessageBox.Icon.Information, 
                      buttons=QMessageBox.StandardButton.Ok, default_btn=None):
        msg_box = QMessageBox()
        msg_box.setWindowTitle(title)
        msg_box.setText(str(text))
        msg_box.setIcon(icon)
        msg_box.setStandardButtons(buttons)
        if default_btn:
            msg_box.setDefaultButton(default_btn)
        # 保持置顶
        msg_box.setWindowFlags(msg_box.windowFlags() | Qt.WindowStaysOnTopHint) # type: ignore 
        return msg_box.exec()

    # --- 整合后的槽函数 ---

    @Slot(str)
    def error_process(self, error_message):
        """处理错误信号"""
        print(f"收到错误信号: {error_message}")
        self._show_message("错误", error_message, QMessageBox.Icon.Critical)