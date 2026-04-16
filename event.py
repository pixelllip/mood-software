# event.py
from PySide6.QtCore import QObject, Signal, Slot

class MySignal(QObject):
    is_finished = Signal()
    text_input = Signal(str)
    text_output = Signal(str) 
    key_pressed = Signal(int, str)
    
    def __init__(self):
        super().__init__()

class MySlot(QObject):
    def __init__(self):
        super().__init__()
        self.agent = None
    
    def set_agent(self, agent):
        self.agent = agent