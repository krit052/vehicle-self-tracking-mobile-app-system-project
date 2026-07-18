# New code cloud treading (Refactored & Stabilized)
import config as cfg
import tracking.tracker as trk
import utils as utl
import tracking.pairing as pr

#ใช้ logging เพื่อเวลาเกิดปัญหาจะได้รู้ว่าปัญหาเกิดที่กล้องตัวไหน และเกิดเวลาไหน
import logging
logger = logging.getLogger(__name__)

import re
import time
import json
import base64
import tempfile
import threading
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from datetime import datetime, timezone


from inference_sdk import InferenceHTTPClient
from pymongo import MongoClient
import requests as _requests
import difflib ##เพิ่ม difflib สำหรับการเปรียบเทียบข้อความ เวลา OCR อ่านป้ายทะเบียนผิดพลาดเล็กน้อย จะให้เทียบกับจังหวัดที่เคยเจอในฐานข้อมูล เพื่อให้สามารถจับคู่ได้แม่นยำขึ้น

import firebase_admin
from firebase_admin import credentials, messaging

from cameras import Camera, resolve_active_cameras



#สำหรับเปิด/ปิด Display window (หน้าต่างโชว์ภาพ) ถ้าไม่อยากให้โชว์ภาพให้ตั้งเป็น false
ENABLE_DISPLAY = cfg.ENABLE_DISPLAY

# 🛠️ 1. ดึงข้อมูลสภาพแวดล้อมพร้อมใส่ค่า Default ป้องกันแครช (Safe Environment Getters)
ROBOFLOW_API_KEY = cfg.ROBOFLOW_API_KEY
WORKSPACE_NAME = cfg.WORKSPACE_NAME
WORKFLOW_ID = cfg.WORKFLOW_ID
# ชื่อกล้องจากคอลัมน์ CAMERA NAME_NEW ใน backend/cctv/RTSP-CCTV-new.csv (คั่นหลายตัวด้วย comma)
ACTIVE_CAMERAS = cfg.ACTIVE_CAMERAS
# ใช้เฉพาะตอนทดสอบไฟล์วิดีโอ (จะถูกใช้ก็ต่อเมื่อ ACTIVE_CAMERAS ว่าง)
RTSP_URL = cfg.RTSP_URL

SAMPLE_SECONDS = cfg.SAMPLE_SECONDS
PIXELS_PER_METER = cfg.PIXELS_PER_METER
NEAR_DISTANCE_M = cfg.NEAR_DISTANCE_M
ALERT_DISTANCE_M = cfg.ALERT_DISTANCE_M
ALERT_COOLDOWN_SECONDS = cfg.ALERT_COOLDOWN_SECONDS

# ขนาดหน้าต่างแสดงผล (px) — ปรับให้ใหญ่ขึ้นถ้ามองไม่เห็น ไม่กระทบภาพที่ส่งไป AI
DISPLAY_WIDTH = cfg.DISPLAY_WIDTH

TRACKER_MAX_DISTANCE_PX = cfg.TRACKER_MAX_DISTANCE_PX
TRACKER_TTL_FRAMES = cfg.TRACKER_TTL_FRAMES
PAIR_TTL_SECONDS = cfg.PAIR_TTL_SECONDS

FIREBASE_SERVICE_ACCOUNT = cfg.FIREBASE_SERVICE_ACCOUNT
FCM_DEVICE_TOKEN = cfg.FCM_DEVICE_TOKEN

MONGODB_URL = cfg.MONGODB_URL
MONGO_NAME = cfg.MONGO_NAME

TYPHOON_OCR_API_KEY = cfg.TYPHOON_OCR_API_KEY
TYPHOON_OCR_MODEL = cfg.TYPHOON_OCR_MODEL
TYPHOON_OCR_TASK_TYPE = cfg.TYPHOON_OCR_TASK_TYPE
TYPHOON_OCR_MAX_TOKENS = cfg.TYPHOON_OCR_MAX_TOKENS
TYPHOON_OCR_TEMPERATURE = cfg.TYPHOON_OCR_TEMPERATURE
TYPHOON_OCR_TOP_P = cfg.TYPHOON_OCR_TOP_P
TYPHOON_OCR_REP_PENALTY = cfg.TYPHOON_OCR_REP_PENALTY

_TYPHOON_OCR_URL = "https://api.opentyphoon.ai/v1/ocr"

# รายชื่อจังหวัด ในประเทศไทย (ใช้สำหรับการแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน)
THAI_PROVINCES = [
    "กระบี่", "กรุงเทพมหานคร", "กาญจนบุรี", "กาฬสินธุ์", "กำแพงเพชร", 
    "ขอนแก่น", "จันทบุรี", "ฉะเชิงเทรา", "ชลบุรี", "ชัยนาท", 
    "ชัยภูมิ", "ชุมพร", "เชียงราย", "เชียงใหม่", "ตรัง", 
    "ตราด", "ตาก", "นครนายก", "นครปฐม", "นครพนม", 
    "นครราชสีมา", "นครศรีธรรมราช", "นครสวรรค์", "นนทบุรี", "นราธิวาส", 
    "น่าน", "บึงกาฬ", "บุรีรัมย์", "ปทุมธานี", "ประจวบคีรีขันธ์", 
    "ปราจีนบุรี", "ปัตตานี", "พระนครศรีอยุธยา", "พะเยา", "พังงา", 
    "พัทลุง", "พิจิตร", "พิษณุโลก", "เพชรบุรี", "เพชรบูรณ์", 
    "แพร่", "ภูเก็ต", "มหาสารคาม", "มุกดาหาร", "แม่ฮ่องสอน", 
    "ยโสธร", "ยะลา", "ร้อยเอ็ด", "ระนอง", "ระยอง", 
    "ราชบุรี", "ลพบุรี", "ลำปาง", "ลำพูน", "เลย", 
    "ศรีสะเกษ", "สกลนคร", "สงขลา", "สตูล", "สมุทรปราการ", 
    "สมุทรสงคราม", "สมุทรสาคร", "สระแก้ว", "สระบุรี", "สิงห์บุรี", 
    "สุโขทัย", "สุพรรณบุรี", "สุราษฎร์ธานี", "สุรินทร์", "หนองคาย", 
    "หนองบัวลำภู", "อ่างทอง", "อำนาจเจริญ", "อุดรธานี", "อุตรดิตถ์", 
    "อุทัยธานี", "อุบลราชธานี"
]


## ฟังก์ชันช่วยดักและแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน
def clean_and_correct_plate(ocr_text: str) -> str:
    """ ฟังก์ชันช่วยดักและแก้ไขคำเพี้ยนของจังหวัดในป้ายทะเบียน """
    parts = ocr_text.split()
    if len(parts) < 3:
        return ocr_text # ถ้าข้อความอ่านมาไม่ครบ 3 ส่วน ให้คืนค่าเดิมไปก่อน
        
    prefix = parts[0]       # บรรทัดบน (เช่น "1กท")
    raw_province = parts[1] # บรรทัดกลาง (เช่น "นจร้าวล")
    suffix = parts[2]       # บรรทัดล่าง (เช่น "6761")
    
    # หาจังหวัดที่ใกล้เคียงที่สุดจากฐานข้อมูล THAI_PROVINCES
    matches = difflib.get_close_matches(raw_province, THAI_PROVINCES, n=1, cutoff=0.4)
    
    if matches:
        corrected_province = matches[0]
        return f"{prefix} {corrected_province} {suffix}"
    
    return ocr_text


# 🔐 2. ตัวควบคุมการเข้าถึงข้อมูลข้าม Thread ย้ายไปเป็น lock รายกล้องใน CameraContext แล้ว

def _call_typhoon_ocr(img_np) -> str:
    if not TYPHOON_OCR_API_KEY:
        return ""
    success, encoded = cv2.imencode(".jpg", img_np)
    if not success:
        return ""
    try:
        resp = _requests.post(
            _TYPHOON_OCR_URL,
            headers={"Authorization": f"Bearer {TYPHOON_OCR_API_KEY}"},
            files={"file": ("plate.jpg", encoded.tobytes(), "image/jpeg")},
            data={
                "model": TYPHOON_OCR_MODEL,
                "task_type": TYPHOON_OCR_TASK_TYPE,
                "max_tokens": str(TYPHOON_OCR_MAX_TOKENS),
                "temperature": str(TYPHOON_OCR_TEMPERATURE),
                "top_p": str(TYPHOON_OCR_TOP_P),
                "repetition_penalty": str(TYPHOON_OCR_REP_PENALTY),
            },
            timeout=30,
        )
        if resp.status_code != 200:
            print(f"[TyphoonOCR] API error {resp.status_code}: {resp.text[:200]}")
            return ""
        
        texts = []
        for page in resp.json().get("results", []):
            if not isinstance(page, dict):
                continue
            if page.get("success") and page.get("message"):
                try:
                    content = page["message"]["choices"][0]["message"]["content"]
                except (KeyError, IndexError, TypeError, AttributeError):
                    continue
                try:
                    text = json.loads(content).get("natural_text", content)
                except (json.JSONDecodeError, TypeError, AttributeError):
                    text = content
                if text:
                    texts.append(text.strip())
        return "\n".join(texts).strip()
    except Exception as e:
        print("[TyphoonOCR] Connection error:", repr(e))
        return ""

_mongo_collection = None

def get_notifications_collection():
    global _mongo_collection
    if _mongo_collection is None and MONGODB_URL:
        try:
            _mongo_collection = MongoClient(MONGODB_URL, serverSelectionTimeoutMS=5000)[MONGO_NAME]["notifications"]
        except Exception as e:
            print("[Mongo] Connection setup failed:", repr(e))
    return _mongo_collection

_client = None

def get_roboflow_client() -> InferenceHTTPClient:
    global _client
    if _client is None:
        if not ROBOFLOW_API_KEY:
            raise RuntimeError("Missing ROBOFLOW_API_KEY in .env")
        _client = InferenceHTTPClient(
            api_url="https://serverless.roboflow.com",
            api_key=ROBOFLOW_API_KEY,
        )
    return _client

firebase_initialized = False


class CameraContext:
    """สถานะแยกของกล้องแต่ละตัว: capture, tracker, คู่คน↔รถ, cooldown ของ FCM และภาพ annotate ล่าสุด"""

    def __init__(self, camera: Camera):
        self.camera = camera
        self.name = camera.name
        self.url = camera.url

        self.tracker = trk.SimpleTracker(
            max_distance_px=TRACKER_MAX_DISTANCE_PX,
            ttl_frames=TRACKER_TTL_FRAMES,
        )
        self.pair_state_manager = pr.PairStateManager(ttl_seconds=PAIR_TTL_SECONDS)

        self.cap = None
        self.last_alert_sent_at = 0.0
        self.last_sample_at = 0.0
        self.cloud_thread: Optional[threading.Thread] = None

        self.lock = threading.Lock()
        self.latest_annotated: Optional[np.ndarray] = None  # ภาพ annotate ล่าสุดจาก Roboflow
        self.window_sized = False   # ปรับขนาดหน้าต่างครั้งเดียว ตอนเห็นเฟรมแรก (รู้สัดส่วนจริงแล้ว)

def init_firebase():
    global firebase_initialized
    if firebase_initialized:
        return
    if not FIREBASE_SERVICE_ACCOUNT:
        return
    try:
        sa_path = cfg.Path(FIREBASE_SERVICE_ACCOUNT)
        if not sa_path.is_absolute():
            sa_path = (cfg._HERE / sa_path).resolve()
        cred = credentials.Certificate(str(sa_path))
        firebase_admin.initialize_app(cred)
        firebase_initialized = True
    except Exception as e:
        print("[FCM] Initialization failed:", repr(e))

def send_fcm_alert(cam: "CameraContext", payload: dict):
    if not FCM_DEVICE_TOKEN:
        print("[FCM] Missing FCM_DEVICE_TOKEN, skipping")
        return

    # 💡 cooldown แยกรายกล้อง กล้องหนึ่ง alert แล้วต้องไม่ไปปิดปาก alert ของกล้องอื่น
    now = time.time()
    if now - cam.last_alert_sent_at < ALERT_COOLDOWN_SECONDS:
        print(f"[FCM][{cam.name}] Cooldown active, skipping duplicate")
        return

    init_firebase()
    if not firebase_initialized:
        return

    plate_text = stringify(payload.get("license_plate_text", "-"))
    distance = payload.get("distance_m", "unknown")
    title = f"Motorcycle Alert - {cam.name}"
    body = f"Person moved {distance}m away from motorcycle"
    if plate_text and plate_text != "-":
        body += f", plate: {plate_text}"
    if cam.camera.position:
        body += f" ({cam.camera.position})"

    try:
        message = messaging.Message(
            token=FCM_DEVICE_TOKEN,
            notification=messaging.Notification(title=title, body=body),
            data={
                "event": "motorcycle_left_area",
                "camera_name": cam.name,
                "camera_position": cam.camera.position,
                "distance_m": str(distance),
                "person_track_id": str(payload.get("person_track_id", "")),
                "motorcycle_track_id": str(payload.get("motorcycle_track_id", "")),
                "license_plate_text": plate_text,
                "status": str(payload.get("status", "")),
            },
        )
        response = messaging.send(message)
        cam.last_alert_sent_at = now
        print(f"[FCM][{cam.name}] Sent:", response)
    except Exception as e:
        print(f"[FCM][{cam.name}] Error sending message:", repr(e))

    try:
        col = get_notifications_collection()
        if col is not None:
            col.insert_one({
                "title": title,
                "body": body,
                "event": "motorcycle_left_area",
                "camera_name": cam.name,
                "camera_position": cam.camera.position,
                "distance_m": payload.get("distance_m"),
                "person_track_id": payload.get("person_track_id"),
                "motorcycle_track_id": payload.get("motorcycle_track_id"),
                "license_plate_text": plate_text,
                "status": payload.get("status"),
                "sent_at": datetime.now(timezone.utc),
            })
            print(f"[Mongo][{cam.name}] Notification saved")
    except Exception as e:
        print("[Mongo] Failed to save notification:", repr(e))

def normalize_result(result):
    if isinstance(result, list) and len(result) > 0:
        return result[0]
    if isinstance(result, dict):
        return result
    return {}

def _scale_preds(preds: list, factor: float):
    for p in preds:
        for key in ("x", "y", "width", "height"):
            if key in p:
                try:
                    p[key] = float(p[key]) * factor
                except (TypeError, ValueError):
                    pass

def run_roboflow_cloud(frame) -> dict:
    h, w = frame.shape[:2]
    if w > _MAX_FRAME_WIDTH:
        scale = _MAX_FRAME_WIDTH / w
        send_frame = cv2.resize(frame, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
        inv_scale = 1.0 / scale
    else:
        send_frame = frame
        inv_scale = 1.0

    result = get_roboflow_client().run_workflow(
        workspace_name=WORKSPACE_NAME,
        workflow_id=WORKFLOW_ID,
        images={"image": send_frame},
        use_cache=True,
    )
    r = normalize_result(result)
    if inv_scale != 1.0:
        for key in ("license_plate_predictions", "raw_person_motorcycle_predictions"):
            _scale_preds(r.get(key, {}).get("predictions", []), inv_scale)
    return r

def decode_output_image(output_image):
    if not output_image:
        return None
    b64_value = output_image.get("value") if isinstance(output_image, dict) else output_image
    if not b64_value:
        return None
    try:
        img_bytes = base64.b64decode(b64_value)
        img_array = np.frombuffer(img_bytes, dtype=np.uint8)
        return cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    except Exception as e:
        print("[Display] Could not decode output image:", e)
        return None

_MAX_FRAME_WIDTH = cfg._MAX_FRAME_WIDTH

_PLATE_MIN_WIDTH = cfg._PLATE_MIN_WIDTH
_PLATE_MIN_HEIGHT = cfg._PLATE_MIN_HEIGHT
_PLATE_CONF_MIN = cfg._PLATE_CONF_MIN
_PLATE_TEXT_MAX_CHARS = cfg._PLATE_TEXT_MAX_CHARS
# ป้ายที่อยู่ห่างจากรถทุกคันเกินระยะนี้ (px) ถือว่าไม่ใช่ป้ายของรถในเฟรม → ไม่ยกให้ใคร
_PLATE_MAX_OWNER_DIST_PX = 250.0

# 🐛 DEBUG: SAVE_PLATE=true จะเซฟภาพป้ายที่ crop ได้ลงโฟลเดอร์ plate_crops ไว้ดูว่า crop ตรงป้ายไหม
# ปิดไว้ (false) เป็นค่าปกติ — เป็นแค่ตัวช่วย debug ไม่เกี่ยวกับการทำงานจริง เปิด/ปิดแล้วระบบทำงานเหมือนเดิม
SAVE_PLATE = cfg.SAVE_PLATE
_PLATE_CROPS_DIR = cfg._PLATE_CROPS_DIR

def _safe_filename(text: str) -> str:
    """ตัดอักขระที่ตั้งเป็นชื่อไฟล์บน Windows ไม่ได้ออก"""
    return re.sub(r'[<>:"/\\|?*\s]+', "_", text).strip("_")

def _save_plate_crop(cam_name: str, img_np, plate_text: str = ""):
    """
    เซฟภาพป้ายที่ crop มาได้ ไว้ดูว่ากรอบที่ตัดมาตรงป้ายจริงไหม
    ตั้งชื่อไฟล์ให้บอกผล OCR ด้วย: อ่านออก = ใส่ข้อความป้าย, อ่านไม่ออก = unread
    → เปิดโฟลเดอร์แล้วเห็นเลยว่า "crop พลาด" หรือ "crop ตรงแต่ OCR อ่านไม่ออก"
    ห้ามให้ error ตรงนี้ไปทำให้ pipeline หลักล้ม — debug ล้วนๆ
    """
    if not SAVE_PLATE:
        return
    try:
        _PLATE_CROPS_DIR.mkdir(exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        label = _safe_filename(plate_text) if plate_text else "unread"
        fname = f"{_safe_filename(cam_name)}_{stamp}_{label}.jpg"

        # เข้ารหัสเป็น jpg ในหน่วยความจำแล้วเขียนไฟล์เอง — ไม่ใช้ cv2.imwrite
        # เพราะชื่อไฟล์มีภาษาไทย (ป้ายทะเบียน) แล้ว imwrite บน Windows จะเงียบๆ เขียนไม่สำเร็จ
        ok, encoded = cv2.imencode(".jpg", img_np)
        if not ok:
            print(f"[PlateCrop][{cam_name}] Encode failed, skipped")
            return
        (_PLATE_CROPS_DIR / fname).write_bytes(encoded.tobytes())
        print(f"[PlateCrop][{cam_name}] Saved {fname}")
    except Exception as e:
        print(f"[PlateCrop][{cam_name}] Save failed:", repr(e))

_THAI_NON_PLATE_TERMS = re.compile(
    r'ตำบล|ต\.|อำเภอ|อ\.|จังหวัด|จ\.|ถนน|ถ\.|หมู่ที่|หมู่บ้าน|ซอย|แขวง|เขต|ทะเล|นิคม|เทศบาล|องค์การ|บริษัท|ห้างหุ้น'
)

def _filter_plate_text(raw: str) -> str:
    lines = [l.strip() for l in raw.splitlines() if l.strip()]
    kept = [
        l for l in lines
        if 2 <= len(l) <= _PLATE_TEXT_MAX_CHARS
        # 💡 4. ปรับเปลี่ยนช่วงพิกัดสากลแบบสากล (\u0e00-\u0e7f ครอบคลุมอักษรไทยทั้งหมด)
        and re.search(r'[\d\u0e00-\u0e7f]', l)
        and not _THAI_NON_PLATE_TERMS.search(l)
    ]
    return " ".join(kept)

def crop_plates_and_ocr(cam_name: str, frame, plate_predictions: List[dict]) -> List[Tuple[dict, str]]:
    """คืน [(กรอบป้าย, ข้อความที่อ่านได้), ...] — ต้องคืนกรอบมาด้วย คนเรียกจะได้รู้ว่าป้ายนี้เป็นของรถคันไหน"""
    if not plate_predictions or frame is None:
        return []

    fh, fw = frame.shape[:2]
    valid = []
    for p in plate_predictions:
        try:
            if float(p.get("confidence", 1.0)) < _PLATE_CONF_MIN:
                continue
            if float(p.get("width", 0)) < _PLATE_MIN_WIDTH:
                continue
            if float(p.get("height", 0)) < _PLATE_MIN_HEIGHT:
                continue
            valid.append(p)
        except (TypeError, ValueError):
            continue

    valid.sort(key=lambda p: float(p.get("confidence", 0)), reverse=True)
    valid = valid[:1]
    if not valid:
        return []

    print(f"[TyphoonOCR][{cam_name}] Processing {len(valid)} plate(s) (filtered from {len(plate_predictions)})")
    reads: List[Tuple[dict, str]] = []
    for pred in valid:
        try:
            cx = float(pred["x"])
            cy = float(pred["y"])
            w = float(pred["width"])
            h = float(pred["height"])

            x1 = max(0, int(cx - w / 2))
            y1 = max(0, int(cy - h / 2))
            x2 = min(fw, int(cx + w / 2))
            y2 = min(fh, int(cy + h / 2))

            if x2 <= x1 or y2 <= y1:
                continue

            raw = frame[y1:y2, x1:x2]
            h_p, w_p = raw.shape[:2]
            if w_p < 80:
                gray = cv2.cvtColor(raw, cv2.COLOR_BGR2GRAY)
                processed = cv2.resize(gray, None, fx=4.0, fy=4.0, interpolation=cv2.INTER_CUBIC)
                kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
                processed = cv2.filter2D(processed, -1, kernel)
            elif w_p < 150:
                processed = cv2.resize(raw, None, fx=2.5, fy=2.5, interpolation=cv2.INTER_CUBIC)
            else:
                processed = cv2.resize(raw, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)

            raw_text = _call_typhoon_ocr(processed)
            clean = _filter_plate_text(raw_text)

            # ─── 🛠️ แทรกโค้ดใหม่ตรงนี้ ───
            # ส่งข้อความไปปรับคำจังหวัดให้ถูกต้องก่อนนำไปใช้งาน
            clean = clean_and_correct_plate(clean)
            # ─────────────────────────────

            # 🐛 DEBUG: เซฟภาพป้ายที่ crop ได้ (ทำงานเฉพาะตอน SAVE_PLATE=true)
            _save_plate_crop(cam_name, raw, clean)

            if clean:
                reads.append((pred, clean))
                print(f"[TyphoonOCR][{cam_name}] Plate text:", clean)
        except Exception as e:
            print(f"[TyphoonOCR][{cam_name}] Processing error:", repr(e))

    return reads

def stringify(value) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return " | ".join([str(v).strip() for v in value if str(v).strip()])
    return str(value).strip()

def get_predictions(output: dict, key: str) -> List[dict]:
    data = output.get(key, {})
    if isinstance(data, dict):
        preds = data.get("predictions", [])
        if isinstance(preds, list):
            return preds
    return []

def _plate_inside_bbox(px: float, py: float, bbox: dict, margin: float = 1.15) -> bool:
    """จุดกึ่งกลางป้าย อยู่ในกรอบรถคันนี้ไหม (ขยายกรอบนิดหน่อย กัน bbox รถตัดป้ายขาด)"""
    try:
        cx = float(bbox["x"])
        cy = float(bbox["y"])
        w = float(bbox["width"]) * margin
        h = float(bbox["height"]) * margin
    except (KeyError, TypeError, ValueError):
        return False
    return abs(px - cx) <= w / 2.0 and abs(py - cy) <= h / 2.0

def find_plate_owner(tracks: List[trk.SimpleTrack], plate_pred: dict) -> Optional[trk.SimpleTrack]:
    """
    หารถเจ้าของป้ายนี้:
      1. รถที่กรอบครอบจุดกึ่งกลางป้ายอยู่ ได้สิทธิ์ก่อน (ป้ายติดอยู่บนรถคันนั้นจริงๆ)
      2. ไม่มีคันไหนครอบเลย → ใช้คันที่ใกล้ที่สุด แต่ต้องไม่ไกลเกิน _PLATE_MAX_OWNER_DIST_PX
      3. ไกลเกินทุกคัน → คืน None ดีกว่าเดามั่วแล้วยกป้ายให้ผิดคัน
    """
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    if not motorcycles:
        return None

    try:
        px = float(plate_pred["x"])
        py = float(plate_pred["y"])
    except (KeyError, TypeError, ValueError):
        return None

    inside = [m for m in motorcycles if _plate_inside_bbox(px, py, m.bbox)]
    if inside:
        return min(inside, key=lambda m: utl.euclidean((px, py), m.center))

    nearest = min(motorcycles, key=lambda m: utl.euclidean((px, py), m.center))
    if utl.euclidean((px, py), nearest.center) > _PLATE_MAX_OWNER_DIST_PX:
        return None
    return nearest

def assign_plates_to_owners(cam_name: str, tracks: List[trk.SimpleTrack], plate_reads: List[Tuple[dict, str]]) -> str:
    """ยกป้ายแต่ละกรอบให้ 'รถเจ้าของกรอบนั้น' ไม่ใช่ยกให้คันที่ใกล้ที่สุดเฉยๆ"""
    texts = []
    for pred, text in plate_reads:
        owner = find_plate_owner(tracks, pred)
        if owner is None:
            # ไม่มีรถคันไหนรับป้ายนี้ → ทิ้งไปเลย อย่าไปยัดให้คันอื่นมั่วๆ
            print(f"[Plate][{cam_name}] No owner for plate '{text}', skipped")
            continue
        if owner.plate_text != text:
            print(f"[Plate][{cam_name}] moto:{owner.track_id} → '{text}'")
        owner.plate_text = text
        texts.append(text)
    return " | ".join(texts)

def compute_distance_alerts(cam: "CameraContext", tracks: List[trk.SimpleTrack]) -> List[dict]:
    people = [t for t in tracks if t.cls == "person"]
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    # ไม่ต้องส่ง plate_text เข้าไปแล้ว ปล่อยให้มันดึงจาก motorcycles[i].plate_text เอง
    return cam.pair_state_manager.update(people, motorcycles)

def print_summary(cam: "CameraContext", output: dict, tracks: List[trk.SimpleTrack]):
    people = [t for t in tracks if t.cls == "person"]
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    moto_colors = output.get("motorcycle_colors_rgb") or []

    moto_to_color: Dict[int, list] = {
        moto.track_id: moto_colors[i]
        for i, moto in enumerate(motorcycles)
        if i < len(moto_colors)
    }

    print(f"\n========== {cam.name} ==========")
    used_person_ids = set()
    used_moto_ids = set()
    pair_num = 0

    for (pid, mid), pair in cam.pair_state_manager.pairs.items():
        person = next((p for p in people if p.track_id == pid), None)
        moto = next((m for m in motorcycles if m.track_id == mid), None)

        dist_m = None
        if person and moto:
            dist_m = round(utl.euclidean(person.center, moto.center) / PIXELS_PER_METER, 2)
        elif pair.last_dist_m > 0:
            dist_m = round(pair.last_dist_m, 2)

        # 💡 ดึงประวัติทะเบียนรถจากคู่เก็บความจำโดยตรง แม้ตัวรถจะหายไปแล้ว ทะเบียนก็จะไม่แสดงผลเป็น "-" 
        plate_str = pair.plate_text
        color = moto_to_color.get(mid)

        pair_num += 1
        dist_str = f"{dist_m}m" if dist_m is not None else "-"
        color_str = f"  color:{color}" if color else ""
        p_age = f"(age:{person.age})" if person else "(gone)"
        m_age = f"(age:{moto.age})" if moto else "(gone)"
        print(f"Pair {pair_num} | Person:{pid}{p_age}  Vehicle:{mid}{m_age}  Plate:{plate_str}  State:{pair.state.value}  Dist:{dist_str}{color_str}")

        if person: used_person_ids.add(pid)
        if moto: used_moto_ids.add(mid)

    unpaired_p = [p.track_id for p in people if p.track_id not in used_person_ids]
    unpaired_m = [m.track_id for m in motorcycles if m.track_id not in used_moto_ids]
    if unpaired_p or unpaired_m:
        parts = []
        if unpaired_p: parts.append("Person:" + ",".join(map(str, unpaired_p)))
        if unpaired_m: parts.append("Vehicle:" + ",".join(map(str, unpaired_m)))
        print("Unpaired — " + "  ".join(parts))

    print("====================================\n")

def connect_rtsp(url: str):
    cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        raise RuntimeError(
            f"Could not open stream: {url}\n"
            "Check URL, network, credentials, and camera permissions."
        )
    return cap

def _cloud_worker(cam: CameraContext, frame):
    try:
        logger.info(f"[Cloud][{cam.name}] Sending frame to Roboflow...")
        output = run_roboflow_cloud(frame)
        output.pop("license_plate_text", None)

        # ต้อง track ให้เสร็จก่อน แล้วค่อยยกป้ายให้เจ้าของ จะได้รู้ว่าป้ายกรอบนี้เป็นของรถคันไหน
        raw_preds = get_predictions(output, "raw_person_motorcycle_predictions")
        useful = [p for p in raw_preds if p.get("class") in ["person", "motorcycle"]]
        tracks = cam.tracker.update(useful)

        plate_preds = get_predictions(output, "license_plate_predictions")
        plate_reads = crop_plates_and_ocr(cam.name, frame, plate_preds)
        plate_text = assign_plates_to_owners(cam.name, tracks, plate_reads)
        if plate_text:
            output["license_plate_text"] = plate_text

        alert_payloads = compute_distance_alerts(cam, tracks)
        print_summary(cam, output, tracks)

        annotated = decode_output_image(output.get("tracked_output_image"))
        if annotated is not None:
            # 🔐 ใช้ Lock เพื่อความปลอดภัย ป้องกัน Thread ชนกันตอนเขียนข้อมูลภาพ
            with cam.lock:
                cam.latest_annotated = annotated

        if alert_payloads:
            for alert_payload in alert_payloads:
                alert_payload["camera_name"] = cam.name
                print(f"[Alert][{cam.name}]", json.dumps(alert_payload, ensure_ascii=False, indent=2))
                send_fcm_alert(cam, alert_payload)
        else:
            print(f"[Alert][{cam.name}] No alert")

    except Exception as e:
        logger.exception(f"[Cloud][{cam.name}] Error")

def _fit_window(cam: CameraContext, frame, index: int, total: int):
    """
    ปรับขนาดหน้าต่างตาม 'สัดส่วนจริงของเฟรม' ไม่ใช่เดาเอาว่าเป็น 16:9
    (กล้อง/คลิปบางตัวเป็นแนวตั้ง ถ้ายัดใส่กรอบแนวนอน ภาพจะถูกยืดจนเพี้ยน)

    ย่อให้พอดีกรอบ DISPLAY_WIDTH x (DISPLAY_WIDTH*9/16) โดยคงอัตราส่วนเดิม
    → ภาพไม่บิด และไม่ว่าจะกล้องแนวนอนหรือแนวตั้ง หน้าต่างก็ไม่ใหญ่เกินจอ
    """
    fh, fw = frame.shape[:2]
    if fw <= 0 or fh <= 0:
        return

    box_w = DISPLAY_WIDTH
    box_h = int(DISPLAY_WIDTH * 9 / 16)

    scale = min(box_w / fw, box_h / fh)
    win_w = max(1, int(fw * scale))
    win_h = max(1, int(fh * scale))

    cv2.resizeWindow(cam.name, win_w, win_h)

    # วางเรียงเป็นตาราง โดยใช้ขนาดกรอบเป็นช่อง จะได้ไม่ซ้อนกันแม้แต่ละกล้องสัดส่วนไม่เท่ากัน
    cols = 1 if total == 1 else 2
    cv2.moveWindow(cam.name, (index % cols) * (box_w + 20), (index // cols) * (box_h + 60))

    print(f"[Gateway][{cam.name}] Frame {fw}x{fh} → window {win_w}x{win_h} "
          f"(aspect {fw / fh:.2f} preserved)")

def main():
    cameras = resolve_active_cameras(ACTIVE_CAMERAS, fallback_url=RTSP_URL)

    print("[Gateway] Starting edge gateway")
    print(f"[Gateway] Cameras ({len(cameras)}):")
    for c in cameras:
        print(f"           - {c.name}  {c.position}  {c.url}")
    print("[Gateway] Cloud workflow:", WORKSPACE_NAME, "/", WORKFLOW_ID)
    print("[Gateway] Sampling every", SAMPLE_SECONDS, "seconds per camera")

    frame_ms = 40
    print(f"[Gateway] Display FPS target: {1000 // frame_ms} fps  (frame_ms={frame_ms})")

    contexts = [CameraContext(c) for c in cameras]

    # WINDOW_KEEPRATIO = ต่อให้ลากขยายหน้าต่างเอง ภาพก็จะไม่ถูกยืดจนเพี้ยน
    # ขนาดจริงยังตั้งไม่ได้ตอนนี้ ต้องรอเห็นเฟรมแรกก่อน ถึงจะรู้สัดส่วนจริงของกล้อง (ดู _fit_window)
    if ENABLE_DISPLAY:
        for cam in contexts:
            cv2.namedWindow(cam.name, cv2.WINDOW_NORMAL | cv2.WINDOW_KEEPRATIO)
    print(f"[Gateway] Display box: {DISPLAY_WIDTH}x{int(DISPLAY_WIDTH * 9 / 16)} "
          f"(ปรับด้วย DISPLAY_WIDTH ใน .env — ภาพจะย่อให้พอดีกรอบนี้ โดยคงสัดส่วนเดิม)")

    try:
        while True:
            for cam_index, cam in enumerate(contexts):
                # อ่านเฟรมตรงนี้เหมือนเดิม (ไม่มี grabber thread) — ต่อกล้องแบบ lazy
                # กล้องที่ยังต่อไม่ติดจะถูกข้ามไปก่อน ไม่ให้ล้มทั้งระบบ
                if cam.cap is None:
                    try:
                        cam.cap = connect_rtsp(cam.url)
                        print(f"[RTSP][{cam.name}] Connected")
                    except Exception as e:
                        print(f"[RTSP][{cam.name}] Connect failed:", repr(e))
                        continue

                ret, frame = cam.cap.read()
                if not ret or frame is None:
                    print(f"[RTSP][{cam.name}] Lost frame, reconnecting...")
                    cam.cap.release()
                    cam.cap = None
                    continue

                # เห็นเฟรมแรกแล้ว = รู้สัดส่วนจริงของกล้องตัวนี้ ค่อยตั้งขนาดหน้าต่างให้ตรง
                if ENABLE_DISPLAY and not cam.window_sized:
                    _fit_window(cam, frame, cam_index, len(contexts))
                    cam.window_sized = True

                now = time.time()
                ready_to_send = (
                    now - cam.last_sample_at >= SAMPLE_SECONDS
                    and not (cam.cloud_thread and cam.cloud_thread.is_alive())
                )
                clean_frame = frame.copy() if ready_to_send else None

                # 🔐 ใช้ Lock ตอนอ่านข้อมูลภาพแชร์ข้าม Thread เพื่อไปซ้อนมุมจออย่างปลอดภัย
                with cam.lock:
                    annotated = cam.latest_annotated.copy() if cam.latest_annotated is not None else None

                if ENABLE_DISPLAY and annotated is not None:
                    h, w = frame.shape[:2]
                    ah, aw = annotated.shape[:2]
                    # 💡 3. ดักจับเงื่อนไขภาพว่างเปล่า (aw/ah เป็น 0) ป้องกันบั๊กหารด้วยศูนย์
                    if aw > 0 and ah > 0:
                        scale = min(0.5, (w * 0.5) / aw, (h * 0.5) / ah)
                        small = cv2.resize(annotated, (int(aw * scale), int(ah * scale)))
                        sh, sw = small.shape[:2]
                        frame[0:sh, w - sw:w] = small
                if ENABLE_DISPLAY:
                    cv2.imshow(cam.name, frame)

                if clean_frame is None:
                    continue

                cam.last_sample_at = now
                cam.cloud_thread = threading.Thread(
                    target=_cloud_worker,
                    args=(cam, clean_frame),
                    daemon=True,
                )
                cam.cloud_thread.start()

            if ENABLE_DISPLAY and cv2.waitKey(frame_ms) & 0xFF == ord("q"):
                break
            else:
                time.sleep(frame_ms / 1000)  # กัน loop ไม่ให้กิน CPU 100% ตอนไม่มีหน้าจอ
    finally:
        for cam in contexts:
            if cam.cap is not None:
                cam.cap.release()
        if ENABLE_DISPLAY: 
            cv2.destroyAllWindows()

if __name__ == "__main__":
    main()