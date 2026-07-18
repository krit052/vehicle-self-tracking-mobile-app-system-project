#แยกไฟล์ config.py ออกมาเพื่อให้ main.py สะอาดขึ้น
import os
from pathlib import Path
from dotenv import load_dotenv

_HERE = Path(__file__).parent
load_dotenv(_HERE / ".env")

#สำหรับเปิด/ปิด Display window (หน้าต่างโชว์ภาพ) ถ้าไม่อยากให้โชว์ภาพให้ตั้งเป็น false
ENABLE_DISPLAY = os.environ.get("ENABLE_DISPLAY", "true").strip().lower() == "true"

# 🛠️ 1. ดึงข้อมูลสภาพแวดล้อมพร้อมใส่ค่า Default ป้องกันแครช (Safe Environment Getters)
ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY", "")
WORKSPACE_NAME = os.environ.get("WORKSPACE_NAME", "default-workspace")
WORKFLOW_ID = os.environ.get("WORKFLOW_ID", "default-workflow")
# ชื่อกล้องจากคอลัมน์ CAMERA NAME_NEW ใน backend/cctv/RTSP-CCTV-new.csv (คั่นหลายตัวด้วย comma)
ACTIVE_CAMERAS = os.environ.get("ACTIVE_CAMERAS", "")
# ใช้เฉพาะตอนทดสอบไฟล์วิดีโอ (จะถูกใช้ก็ต่อเมื่อ ACTIVE_CAMERAS ว่าง)
RTSP_URL = os.environ.get("RTSP_URL", "")

SAMPLE_SECONDS = float(os.environ.get("SAMPLE_SECONDS", 1.0))
PIXELS_PER_METER = float(os.environ.get("PIXELS_PER_METER", 50.0))
NEAR_DISTANCE_M = float(os.environ.get("NEAR_DISTANCE_M", 1.2))
ALERT_DISTANCE_M = float(os.environ.get("ALERT_DISTANCE_M", 5.0))
ALERT_COOLDOWN_SECONDS = float(os.environ.get("ALERT_COOLDOWN_SECONDS", 30.0))

# ขนาดหน้าต่างแสดงผล (px) — ปรับให้ใหญ่ขึ้นถ้ามองไม่เห็น ไม่กระทบภาพที่ส่งไป AI
DISPLAY_WIDTH = int(os.environ.get("DISPLAY_WIDTH", 1280))

TRACKER_MAX_DISTANCE_PX = float(os.environ.get("TRACKER_MAX_DISTANCE_PX", 300.0))
TRACKER_TTL_FRAMES = int(os.environ.get("TRACKER_TTL_FRAMES", 5))
PAIR_TTL_SECONDS = float(os.environ.get("PAIR_TTL_SECONDS", 30.0))

FIREBASE_SERVICE_ACCOUNT = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
FCM_DEVICE_TOKEN = os.environ.get("FCM_DEVICE_TOKEN", "")

MONGODB_URL = os.environ.get("MONGODB_URL", "")
MONGO_NAME = os.environ.get("MONGO_NAME", "vehicle-tracking")

TYPHOON_OCR_API_KEY = os.environ.get("TYPHOON_OCR_API_KEY", "")
TYPHOON_OCR_MODEL = os.environ.get("TYPHOON_OCR_MODEL", "typhoon-ocr")
TYPHOON_OCR_TASK_TYPE = os.environ.get("TYPHOON_OCR_TASK_TYPE", "default")
TYPHOON_OCR_MAX_TOKENS = int(os.environ.get("TYPHOON_OCR_MAX_TOKENS", 16384))
TYPHOON_OCR_TEMPERATURE = float(os.environ.get("TYPHOON_OCR_TEMPERATURE", 0.1))
TYPHOON_OCR_TOP_P = float(os.environ.get("TYPHOON_OCR_TOP_P", 0.6))
TYPHOON_OCR_REP_PENALTY = float(os.environ.get("TYPHOON_OCR_REP_PENALTY", 1.2))
_TYPHOON_OCR_URL = "https://api.opentyphoon.ai/v1/ocr"

_MAX_FRAME_WIDTH = int(os.environ.get("MAX_FRAME_WIDTH", 1280))

_PLATE_MIN_WIDTH = int(os.environ.get("PLATE_MIN_WIDTH", 40))
_PLATE_MIN_HEIGHT = int(os.environ.get("PLATE_MIN_HEIGHT", 15))
_PLATE_CONF_MIN = float(os.environ.get("PLATE_CONFIDENCE_MIN", 0.35))
_PLATE_TEXT_MAX_CHARS = int(os.environ.get("PLATE_TEXT_MAX_CHARS", 25))


# 🐛 DEBUG: SAVE_PLATE=true จะเซฟภาพป้ายที่ crop ได้ลงโฟลเดอร์ plate_crops ไว้ดูว่า crop ตรงป้ายไหม
# ปิดไว้ (false) เป็นค่าปกติ — เป็นแค่ตัวช่วย debug ไม่เกี่ยวกับการทำงานจริง เปิด/ปิดแล้วระบบทำงานเหมือนเดิม
SAVE_PLATE = os.environ.get("SAVE_PLATE", "false").strip().lower() == "true"
_PLATE_CROPS_DIR = _HERE / "plate_crops"