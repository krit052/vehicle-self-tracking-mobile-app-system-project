# New code cloud treading (Refactored & Stabilized)

import os
import re
import time
import json
import base64
import tempfile
import threading
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from datetime import datetime, timezone
from dotenv import load_dotenv
from inference_sdk import InferenceHTTPClient
from pymongo import MongoClient
import requests as _requests
import difflib ##เพิ่ม difflib สำหรับการเปรียบเทียบข้อความ เวลา OCR อ่านป้ายทะเบียนผิดพลาดเล็กน้อย จะให้เทียบกับจังหวัดที่เคยเจอในฐานข้อมูล เพื่อให้สามารถจับคู่ได้แม่นยำขึ้น

import firebase_admin
from firebase_admin import credentials, messaging

_HERE = Path(__file__).parent
load_dotenv(_HERE / ".env")

# 🛠️ 1. ดึงข้อมูลสภาพแวดล้อมพร้อมใส่ค่า Default ป้องกันแครช (Safe Environment Getters)
ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY", "")
WORKSPACE_NAME = os.environ.get("WORKSPACE_NAME", "default-workspace")
WORKFLOW_ID = os.environ.get("WORKFLOW_ID", "default-workflow")
RTSP_URL = os.environ.get("RTSP_URL", "0")

SAMPLE_SECONDS = float(os.environ.get("SAMPLE_SECONDS", 1.0))
PIXELS_PER_METER = float(os.environ.get("PIXELS_PER_METER", 50.0))
NEAR_DISTANCE_M = float(os.environ.get("NEAR_DISTANCE_M", 1.2))
ALERT_DISTANCE_M = float(os.environ.get("ALERT_DISTANCE_M", 5.0))
ALERT_COOLDOWN_SECONDS = float(os.environ.get("ALERT_COOLDOWN_SECONDS", 30.0))

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


# 🔐 2. ตัวควบคุมการเข้าถึงข้อมูลข้าม Thread (Threading Lock สำหรับแชร์ภาพ)
box_lock = threading.Lock()

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

if not ROBOFLOW_API_KEY:
    raise RuntimeError("Missing ROBOFLOW_API_KEY in .env")

client = InferenceHTTPClient(
    api_url="https://serverless.roboflow.com",
    api_key=ROBOFLOW_API_KEY,
)

firebase_initialized = False
last_alert_sent_at = 0

class SimpleTrack:
    def __init__(self, track_id: int, cls: str, center: Tuple[float, float], bbox: dict):
        self.track_id = track_id
        self.cls = cls
        self.center = center
        self.bbox = bbox
        self.last_seen = time.time()
        self.was_near_motorcycle = False
        self.plate_text: str = "-"  # 💡 มีค่าตั้งต้นเป็น string ป้องกันการเจอบั๊กข้อมูลว่างเปล่า
        self.age: int = 1
        self.missed: int = 0

class SimpleTracker:
    def __init__(self, max_distance_px: float = 160, ttl_frames: int = 5):
        self.max_distance_px = max_distance_px
        self.ttl_frames = ttl_frames
        self.next_id = 1
        self.tracks: Dict[int, SimpleTrack] = {}

    def update(self, detections: List[dict]) -> List[SimpleTrack]:
        now = time.time()

        for t in self.tracks.values():
            t.missed += 1

        stale_ids = [tid for tid, t in self.tracks.items() if t.missed > self.ttl_frames]
        for tid in stale_ids:
            del self.tracks[tid]

        assigned_track_ids = set()
        output_tracks = []

        for det in detections:
            cls = det.get("class")
            center = bbox_bottom_center(det)
            if center is None:
                continue

            best_track_id = None
            best_distance = None

            for track_id, track in self.tracks.items():
                if track_id in assigned_track_ids or track.cls != cls:
                    continue

                dist = euclidean(center, track.center)
                if best_distance is None or dist < best_distance:
                    best_distance = dist
                    best_track_id = track_id

            if best_track_id is not None and best_distance is not None and best_distance <= self.max_distance_px:
                track = self.tracks[best_track_id]
                # 💡 รักษาข้อมูลป้ายทะเบียนเดิมเอาไว้ ไม่ให้หายไปกับการอัปเดตพิกัดเฟรมใหม่
                old_plate = track.plate_text
                track.center = center
                track.bbox = det
                track.last_seen = now
                track.missed = 0
                track.age += 1
                if old_plate and old_plate != "-":
                    track.plate_text = old_plate
                assigned_track_ids.add(best_track_id)
                output_tracks.append(track)
            else:
                track = SimpleTrack(
                    track_id=self.next_id,
                    cls=cls,
                    center=center,
                    bbox=det,
                )
                self.tracks[self.next_id] = track
                assigned_track_ids.add(self.next_id)
                output_tracks.append(track)
                self.next_id += 1

        return output_tracks

tracker = SimpleTracker(
    max_distance_px=TRACKER_MAX_DISTANCE_PX,
    ttl_frames=TRACKER_TTL_FRAMES,
)

class PairState(Enum):
    RIDING = "riding"
    DISMOUNTED = "dismounted"

class PairRecord:
    def __init__(self, person_id: int, motorcycle_id: int):
        self.person_id = person_id
        self.motorcycle_id = motorcycle_id
        self.state = PairState.RIDING
        self.alert_sent = False
        self.last_dist_m = 0.0
        self.plate_text = "-"  # 💡 บันทึกป้ายทะเบียนฝังไว้ในคู่ ป้องกันการเป็นค่าว่างตอนรถหายไปจากจอ
        self.last_updated = time.time()

class PairStateManager:
    def __init__(self, ttl_seconds: float = 30.0):
        self.pairs: Dict[Tuple[int, int], PairRecord] = {}
        self.ttl_seconds = ttl_seconds

    def _evict_stale(self):
        now = time.time()
        stale = [k for k, v in self.pairs.items() if now - v.last_updated > self.ttl_seconds]
        for k in stale:
            print(f"[PairState] Evict stale pair person={k[0]} moto={k[1]}")
            del self.pairs[k]

    def update(
        self,
        people: List[SimpleTrack],
        motorcycles: List[SimpleTrack],
        # license_plate_text: str = "",
    ) -> List[dict]:
        self._evict_stale()
        now = time.time()
        alerts: List[dict] = []

        paired_person_ids = {k[0] for k in self.pairs}
        paired_moto_ids = {k[1] for k in self.pairs}

        # ── Step 1: อัปเดตข้อมูลคู่เดิมอย่างต่อเนื่อง (ไม่ใช้บรรทัด continue ตัดหน้าอีกต่อไป) ──
        for (pid, mid), pair in list(self.pairs.items()):
            person = next((p for p in people if p.track_id == pid), None)
            moto = next((m for m in motorcycles if m.track_id == mid), None)

            is_person_visible = person is not None and person.missed == 0
            is_moto_visible = moto is not None and moto.missed == 0

            # สืบทอดข้อมูลป้ายทะเบียนล่าสุดเข้าไปเก็บใน Pair ความทรงจำระยะยาว
            if pair.plate_text == "-" and moto and getattr(moto, 'plate_text', "-") != "-":
                # ถ้า AI อ่านป้ายได้และจับคู่ให้รถคันนี้แล้ว ให้อัปเดตเข้า Pair
                pair.plate_text = moto.plate_text
            # elif license_plate_text and is_moto_visible:
            #     pair.plate_text = license_plate_text

            if is_person_visible and is_moto_visible:
                pair.last_updated = now
                dist_m = euclidean(person.center, moto.center) / PIXELS_PER_METER
                pair.last_dist_m = dist_m

                if pair.state == PairState.RIDING:
                    if dist_m > NEAR_DISTANCE_M:
                        pair.state = PairState.DISMOUNTED
                        print(f"[PairState] ({pid},{mid}) RIDING → DISMOUNTED dist={dist_m:.2f}m")
                elif pair.state == PairState.DISMOUNTED:
                    if dist_m <= NEAR_DISTANCE_M:
                        pair.state = PairState.RIDING
                        pair.alert_sent = False
                        print(f"[PairState] ({pid},{mid}) DISMOUNTED → RIDING (returned)")
            else:
                # 💡 หากคนหรือรถหายไปชั่วคราว ให้คงระยะและสถานะล่าสุดไว้เพื่อประเมินผล Alert
                if is_person_visible or is_moto_visible:
                    pair.last_updated = now

            # 🎯 ตรรกะประมวลผล ALERT ที่แยกตัวเป็นอิสระ ป้องกันการโดนหลุดข้ามค้าง
            if pair.state == PairState.DISMOUNTED and pair.last_dist_m >= ALERT_DISTANCE_M:
                if not pair.alert_sent:
                    pair.alert_sent = True
                    alerts.append({
                        "status": f"ALERT: person moved {ALERT_DISTANCE_M}m+ from motorcycle",
                        "distance_m": round(pair.last_dist_m, 2),
                        "person_track_id": pid,
                        "motorcycle_track_id": mid,
                        "license_plate_text": pair.plate_text,
                    })

        # ── Step 2: จับคู่ใหม่ให้วัตถุที่ยังว่างอยู่ ──
        unpaired_people = [p for p in people if p.track_id not in paired_person_ids]
        unpaired_motos = [m for m in motorcycles if m.track_id not in paired_moto_ids]

        used_moto_ids = set()
        for person in unpaired_people:
            nearest_moto: Optional[SimpleTrack] = None
            nearest_dist_m = float("inf")

            for moto in unpaired_motos:
                if moto.track_id in used_moto_ids:
                    continue
                dist_m = euclidean(person.center, moto.center) / PIXELS_PER_METER
                if dist_m < nearest_dist_m:
                    nearest_dist_m = dist_m
                    nearest_moto = moto

            if nearest_moto is not None and nearest_dist_m <= NEAR_DISTANCE_M:
                key = (person.track_id, nearest_moto.track_id)
                record = PairRecord(person.track_id, nearest_moto.track_id)
                if nearest_moto.plate_text != "-":
                    record.plate_text = nearest_moto.plate_text
                self.pairs[key] = record
                used_moto_ids.add(nearest_moto.track_id)
                print(f"[PairState] New pair person={person.track_id} moto={nearest_moto.track_id} dist={nearest_dist_m:.2f}m → RIDING")

        return alerts

pair_state_manager = PairStateManager(ttl_seconds=PAIR_TTL_SECONDS)

def init_firebase():
    global firebase_initialized
    if firebase_initialized:
        return
    if not FIREBASE_SERVICE_ACCOUNT:
        return
    try:
        sa_path = Path(FIREBASE_SERVICE_ACCOUNT)
        if not sa_path.is_absolute():
            sa_path = (_HERE / sa_path).resolve()
        cred = credentials.Certificate(str(sa_path))
        firebase_admin.initialize_app(cred)
        firebase_initialized = True
    except Exception as e:
        print("[FCM] Initialization failed:", repr(e))

def send_fcm_alert(payload: dict):
    global last_alert_sent_at
    if not FCM_DEVICE_TOKEN:
        print("[FCM] Missing FCM_DEVICE_TOKEN, skipping")
        return

    now = time.time()
    if now - last_alert_sent_at < ALERT_COOLDOWN_SECONDS:
        print("[FCM] Cooldown active, skipping duplicate")
        return

    init_firebase()
    if not firebase_initialized:
        return

    plate_text = stringify(payload.get("license_plate_text", "-"))
    distance = payload.get("distance_m", "unknown")
    title = "Motorcycle Alert"
    body = f"Person moved {distance}m away from motorcycle"
    if plate_text and plate_text != "-":
        body += f", plate: {plate_text}"

    try:
        message = messaging.Message(
            token=FCM_DEVICE_TOKEN,
            notification=messaging.Notification(title=title, body=body),
            data={
                "event": "motorcycle_left_area",
                "distance_m": str(distance),
                "person_track_id": str(payload.get("person_track_id", "")),
                "motorcycle_track_id": str(payload.get("motorcycle_track_id", "")),
                "license_plate_text": plate_text,
                "status": str(payload.get("status", "")),
            },
        )
        response = messaging.send(message)
        last_alert_sent_at = now
        print("[FCM] Sent:", response)
    except Exception as e:
        print("[FCM] Error sending message:", repr(e))

    try:
        col = get_notifications_collection()
        if col is not None:
            col.insert_one({
                "title": title,
                "body": body,
                "event": "motorcycle_left_area",
                "distance_m": payload.get("distance_m"),
                "person_track_id": payload.get("person_track_id"),
                "motorcycle_track_id": payload.get("motorcycle_track_id"),
                "license_plate_text": plate_text,
                "status": payload.get("status"),
                "sent_at": datetime.now(timezone.utc),
            })
            print("[Mongo] Notification saved")
    except Exception as e:
        print("[Mongo] Failed to save notification:", repr(e))

def euclidean(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return float(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5)

def bbox_bottom_center(det: dict) -> Optional[Tuple[float, float]]:
    try:
        x = float(det["x"])
        y = float(det["y"])
        h = float(det["height"])
        return x, y + h / 2.0
    except Exception:
        return None

def save_temp_frame(frame) -> str:
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp_path = tmp.name
    tmp.close()
    cv2.imwrite(tmp_path, frame, [cv2.IMWRITE_JPEG_QUALITY, 98])
    return tmp_path

def normalize_result(result):
    if isinstance(result, list) and len(result) > 0:
        return result[0]
    if isinstance(result, dict):
        return result
    return {}

def run_roboflow_cloud(frame) -> dict:
    frame_path = save_temp_frame(frame)
    try:
        result = client.run_workflow(
            workspace_name=WORKSPACE_NAME,
            workflow_id=WORKFLOW_ID,
            images={"image": frame_path},
            use_cache=True,
        )
        return normalize_result(result)
    finally:
        try:
            os.remove(frame_path)
        except OSError:
            pass

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

_PLATE_MIN_WIDTH = int(os.environ.get("PLATE_MIN_WIDTH", 40))
_PLATE_MIN_HEIGHT = int(os.environ.get("PLATE_MIN_HEIGHT", 15))
_PLATE_CONF_MIN = float(os.environ.get("PLATE_CONFIDENCE_MIN", 0.35))
_PLATE_TEXT_MAX_CHARS = int(os.environ.get("PLATE_TEXT_MAX_CHARS", 25))

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

def crop_plates_and_ocr(frame, plate_predictions: List[dict]) -> str:
    if not plate_predictions or frame is None:
        return ""

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
        return ""

    print(f"[TyphoonOCR] Processing {len(valid)} plate(s) (filtered from {len(plate_predictions)})")
    texts = []
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
            
            if clean:
                texts.append(clean)
                print("[TyphoonOCR] Plate text:", clean)
        except Exception as e:
            print("[TyphoonOCR] Processing error:", repr(e))

    return " | ".join(texts)

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

def assign_plate_to_nearest_motorcycle(
    tracks: List[SimpleTrack],
    plate_preds: List[dict],
    plate_text: str,
):
    if not plate_text or not plate_preds:
        return
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    if not motorcycles:
        return
    best_plate = max(plate_preds, key=lambda p: float(p.get("confidence", 0)))
    px = float(best_plate.get("x", 0))
    py = float(best_plate.get("y", 0))

    nearest = min(motorcycles, key=lambda m: euclidean((px, py), m.center))
    nearest.plate_text = plate_text

def compute_distance_alerts(tracks: List[SimpleTrack], plate_text: str) -> List[dict]:
    people = [t for t in tracks if t.cls == "person"]
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    # ไม่ต้องส่ง plate_text เข้าไปแล้ว ปล่อยให้มันดึงจาก motorcycles[i].plate_text เอง
    return pair_state_manager.update(people, motorcycles)

def print_summary(output: dict, tracks: List[SimpleTrack]):
    people = [t for t in tracks if t.cls == "person"]
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]
    moto_colors = output.get("motorcycle_colors_rgb") or []

    moto_to_color: Dict[int, list] = {
        moto.track_id: moto_colors[i]
        for i, moto in enumerate(motorcycles)
        if i < len(moto_colors)
    }

    print("\n========== Cloud Workflow ==========")
    used_person_ids = set()
    used_moto_ids = set()
    pair_num = 0

    for (pid, mid), pair in pair_state_manager.pairs.items():
        person = next((p for p in people if p.track_id == pid), None)
        moto = next((m for m in motorcycles if m.track_id == mid), None)

        dist_m = None
        if person and moto:
            dist_m = round(euclidean(person.center, moto.center) / PIXELS_PER_METER, 2)
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

def connect_rtsp():
    cap = cv2.VideoCapture(RTSP_URL, cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        raise RuntimeError("Could not open RTSP stream. Check URL, network, credentials, and camera permissions.")
    return cap

def _cloud_worker(frame, latest_annotated_box: list):
    try:
        print("[Cloud] Sending frame to Roboflow...")
        output = run_roboflow_cloud(frame)
        output.pop("license_plate_text", None)

        plate_preds = get_predictions(output, "license_plate_predictions")
        if plate_preds:
            plate_text = crop_plates_and_ocr(frame, plate_preds)
            if plate_text:
                output["license_plate_text"] = plate_text

        raw_preds = get_predictions(output, "raw_person_motorcycle_predictions")
        useful = [p for p in raw_preds if p.get("class") in ["person", "motorcycle"]]
        tracks = tracker.update(useful)

        plate_text = output.get("license_plate_text", "")
        assign_plate_to_nearest_motorcycle(tracks, plate_preds, plate_text)
        alert_payloads = compute_distance_alerts(tracks, plate_text)
        print_summary(output, tracks)

        annotated = decode_output_image(output.get("tracked_output_image"))
        if annotated is not None:
            # 🔐 ใช้ Lock เพื่อความปลอดภัย ป้องกัน Thread ชนกันตอนเขียนข้อมูลภาพ
            with box_lock:
                latest_annotated_box[0] = annotated

        if alert_payloads:
            for alert_payload in alert_payloads:
                print("[Alert]", json.dumps(alert_payload, ensure_ascii=False, indent=2))
                send_fcm_alert(alert_payload)
        else:
            print("[Alert] No alert")

    except Exception as e:
        print("[Cloud] Error:", repr(e))

def main():
    print("[Gateway] Starting edge gateway")
    print("[Gateway] RTSP:", RTSP_URL)
    print("[Gateway] Cloud workflow:", WORKSPACE_NAME, "/", WORKFLOW_ID)
    print("[Gateway] Sampling every", SAMPLE_SECONDS, "seconds")

    def _cap_frame_ms(c) -> int:
        return 40

    cap = connect_rtsp()
    frame_ms = _cap_frame_ms(cap)
    print(f"[Gateway] Display FPS target: {1000 // frame_ms} fps  (frame_ms={frame_ms})")

    last_sample_at = 0
    latest_annotated_box = [None]
    cloud_thread = None

    while True:
        ret, frame = cap.read()
        if not ret or frame is None:
            print("[RTSP] Lost frame, reconnecting...")
            cap.release()
            time.sleep(2)
            cap = connect_rtsp()
            frame_ms = _cap_frame_ms(cap)
            continue

        now = time.time()
        ready_to_send = (
            now - last_sample_at >= SAMPLE_SECONDS
            and not (cloud_thread and cloud_thread.is_alive())
        )
        clean_frame = frame.copy() if ready_to_send else None

        # 🔐 ใช้ Lock ตอนอ่านข้อมูลภาพแชร์ข้าม Thread หลักเพื่อไปซ้อนมุมจออย่างปลอดภัย
        annotated = None
        with box_lock:
            if latest_annotated_box[0] is not None:
                annotated = latest_annotated_box[0].copy()

        if annotated is not None:
            h, w = frame.shape[:2]
            ah, aw = annotated.shape[:2]
            # 💡 3. ดักจับเงื่อนไขภาพว่างเปล่า (aw/ah เป็น 0) ป้องกันบั๊กหารด้วยศูนย์
            if aw > 0 and ah > 0:
                scale = min(0.25, (w * 0.25) / aw, (h * 0.25) / ah)
                small = cv2.resize(annotated, (int(aw * scale), int(ah * scale)))
                sh, sw = small.shape[:2]
                frame[0:sh, w - sw:w] = small

        cv2.imshow("Edge Gateway | Roboflow + Typhoon OCR", frame)
        if cv2.waitKey(frame_ms) & 0xFF == ord("q"):
            break

        if clean_frame is None:
            continue

        last_sample_at = now
        cloud_thread = threading.Thread(
            target=_cloud_worker,
            args=(clean_frame, latest_annotated_box),
            daemon=True,
        )
        cloud_thread.start()

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()