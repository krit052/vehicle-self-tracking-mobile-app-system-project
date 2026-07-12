# ทดสอบส่ง FCM แจ้งเตือน โดยไม่ต้องเปิดกล้อง/รัน AI
# รัน: python backend/ai_worker/firebase_test.py

import sys
from pathlib import Path

# main.py ใช้ flat import (from cameras import ...) จึงต้องมี ai_worker อยู่ใน sys.path
sys.path.insert(0, str(Path(__file__).parent))

from cameras import Camera
from main import CameraContext, init_firebase, send_fcm_alert
import main

print("Initializing firebase...")
init_firebase()
if not main.firebase_initialized:
    print("Firebase init FAILED (check FIREBASE_SERVICE_ACCOUNT in .env)")
    sys.exit(1)
print("Firebase OK")

if not main.FCM_DEVICE_TOKEN:
    print("Missing FCM_DEVICE_TOKEN in .env, nothing to send")
    sys.exit(1)

# กล้องจำลอง ไม่เปิด capture จริง แค่ต้องการ name/position + cooldown state ให้ send_fcm_alert
cam = CameraContext(Camera(name="TEST-CAM", url="", position="Test Position", ip="0.0.0.0"))

send_fcm_alert(cam, {
    "status": "TEST",
    "distance_m": 9.99,
    "person_track_id": 1,
    "motorcycle_track_id": 2,
    "license_plate_text": "TEST-PLATE",
})
