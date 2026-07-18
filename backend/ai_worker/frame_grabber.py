#frame_grabber.py 
import threading
import time
import cv2

def connect_rtsp(url: str):
    cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        raise RuntimeError(
            f"Could not open stream: {url}\n"
            "Check URL, network, credentials, and camera permissions."
        )
    return cap

class FrameGrabber:
    """อ่านเฟรมจาก RTSP ต่อเนื่องใน thread แยก เก็บแค่เฟรมล่าสุดไว้ในตัวแปรเดียว"""
    def __init__(self, url: str, name: str):
        self.url = url
        self.name = name
        self.cap = None
        self.lock = threading.Lock()
        self.latest_frame = None
        self.running = False
        self.thread = None

    def start(self):
        self.running = True
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def _loop(self):
        while self.running:
            if self.cap is None:
                try:
                    self.cap = connect_rtsp(self.url)
                except Exception:
                    time.sleep(2)
                    continue
            try:
                ret, frame = self.cap.read()
            except Exception:
                # เกิด error ระดับ OpenCV ตอนอ่าน (สาย RTSP หลุดกลางทาง ฯลฯ) — reconnect ใหม่
                self.cap = None
                continue

            if not ret or frame is None:
                self.cap.release()
                self.cap = None
                continue
            with self.lock:
                self.latest_frame = frame

        # ── เดินออกจาก loop เพราะ stop() สั่ง running=False แล้ว ──
        # ปิด cap ตรงนี้ "ในเธรดของตัวเอง" เท่านั้น กัน thread อื่นมาแตะพร้อมกัน
        if self.cap is not None:
            self.cap.release()
            self.cap = None

    def get_latest(self):
        with self.lock:
            return None if self.latest_frame is None else self.latest_frame.copy()

    def stop(self):
        self.running = False
        if self.thread is not None:
            self.thread.join(timeout=5)   # รอให้เธรดปิด cap ให้เสร็จก่อนค่อยคืน control