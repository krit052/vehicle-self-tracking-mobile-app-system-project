"""
Test backend  –  connects to mongodb://localhost:27017/test
Endpoints:
  POST /auth/login   -> returns JWT
  GET  /auth/me      -> returns user info (requires JWT)

Run: uvicorn main:app --reload --port 8001
"""

import os
import bcrypt
import cloudinary
import cloudinary.uploader
import csv
import hashlib
import hmac
import json
import math
import random
# import smtplib
import requests
import secrets
import threading
import time

from pathlib import Path
from urllib.parse import unquote, urlparse
from dotenv import load_dotenv
# from email.mime.text import MIMEText
# from email.mime.multipart import MIMEMultipart
from fastapi import Body, FastAPI, Header, HTTPException, Depends, UploadFile, File
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from pymongo import MongoClient
from jose import jwt, JWTError
from bson import ObjectId
from bson.errors import InvalidId
from datetime import datetime, timedelta, timezone
import firebase_admin
from firebase_admin import credentials, messaging

load_dotenv(dotenv_path=Path(__file__).parent.parent / ".env")

def configure_cloudinary() -> None:
    cloudinary_url = os.getenv("CLOUDINARY_URL")
    if cloudinary_url:
        parsed_url = urlparse(cloudinary_url)
        if parsed_url.scheme != "cloudinary" or not all(
            [parsed_url.username, parsed_url.password, parsed_url.hostname]
        ):
            raise RuntimeError(
                "Invalid CLOUDINARY_URL. Expected format: "
                "cloudinary://API_KEY:API_SECRET@CLOUD_NAME"
            )

        cloudinary.config(
            cloud_name=parsed_url.hostname,
            api_key=unquote(parsed_url.username),
            api_secret=unquote(parsed_url.password),
            secure=True,
        )
        return

    required_keys = [
        "CLOUDINARY_CLOUD_NAME",
        "CLOUDINARY_API_KEY",
        "CLOUDINARY_API_SECRET",
    ]
    missing_keys = [key for key in required_keys if not os.getenv(key)]
    if missing_keys:
        raise RuntimeError(
            "Missing Cloudinary config. Set CLOUDINARY_URL or these variables: "
            + ", ".join(missing_keys)
        )

    cloudinary.config(
        cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME"),
        api_key=os.getenv("CLOUDINARY_API_KEY"),
        api_secret=os.getenv("CLOUDINARY_API_SECRET"),
        secure=True,
    )


configure_cloudinary()

# ── Config ────────────────────────────────────────────────────────────────────
MONGODB_URL = os.environ["MONGODB_URL"]
MONGO_NAME = os.environ["MONGO_NAME"]
JWT_SECRET = os.environ["JWT_SECRET"]
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")
JWT_EXPIRE_HOURS = int(os.environ.get("JWT_EXPIRE_HOURS", 24))
INTERNAL_SECRET = os.environ["INTERNAL_SECRET"]
OTP_EXPIRE_MINUTES = int(os.environ.get("OTP_EXPIRE_MINUTES", 5))
OTP_MAX_ATTEMPTS = int(os.environ.get("OTP_MAX_ATTEMPTS", 5))
OTP_PURPOSE_PASSWORD_RESET = "password_reset"
CAMERAS_FILE = Path(__file__).parent.parent / "cameras.json"

# แหล่งข้อมูลกล้อง = CSV เดียวกับที่ ai_worker ใช้ (backend/cctv/RTSP-CCTV-new.csv)
# ai_worker อ่าน CSV ตรง ๆ ส่วน backend/admin จะ sync CSV → Mongo แล้วเก็บเฉพาะ
# "พิกัดที่ปักหมุด" (latitude/longitude/located) ต่อยอดบน Mongo
# → CSV เป็นตัวกำหนดว่ามีกล้องอะไรบ้าง (ชื่อตรงกับที่ใส่ใน ACTIVE_CAMERAS)
#   ทั้งสองระบบจึงใช้ชื่อกล้องชุดเดียวกัน โยงหากันได้เองด้วยชื่อ
CAMERA_CSV_PATH = (Path(__file__).parent.parent / "cctv" / "RTSP-CCTV-new.csv").resolve()
CSV_NAME_COL, CSV_RTSP_COL, CSV_ENABLE_COL, CSV_POSITION_COL, CSV_IP_COL = (
    "CAMERA NAME_NEW", "RTSP", "enable rtsp", "POSITION", "IP ADDRESS",
)
# พิกัด placeholder = ใจกลาง มฟล. ตั้งตอน insert ครั้งแรก (located=False) รอ admin ปักจริง
CAMERA_PLACEHOLDER_LAT, CAMERA_PLACEHOLDER_LON = 20.0459, 99.8934

# ระยะเวลาที่ถือว่า "รถยังจอดอยู่ตรงกล้อง" นับจากครั้งล่าสุดที่กล้องเห็นป้าย
# - ถ้ากล้องเห็นซ้ำภายในช่วงนี้ = ยังจอดอยู่ (หมุดค้าง, ไม่แจ้งเตือนซ้ำ)
# - ถ้าเกินช่วงนี้ไม่เห็นเลย = รถออกไปแล้ว → หมุดหาย, ถ้ากลับมาเห็นใหม่ = แจ้งเตือน "มาจอด" อีกครั้ง
# ตั้งให้ "ยาวกว่าช่วงห่างที่ OCR อ่านป้ายได้" (OCR อ่านได้เป็นช่วง ๆ ไม่ใช่ทุกวินาที)
# ไม่งั้นช่องว่างระหว่างการอ่านจะถูกนับเป็น "มาจอดใหม่" แล้วแจ้งซ้ำ + หมุดกระพริบ
# ยิ่งค่ามาก = แจ้งน้อยลง/หมุดนิ่ง แต่ตรวจ "รถออกจากกล้อง" (หมุดหาย/Is this you) ช้าลง
DETECTION_PRESENCE_SECONDS = int(os.environ.get("DETECTION_PRESENCE_SECONDS", 900))
# ทุกกี่วินาทีให้ background watcher เช็กว่ามีรถ locked ตัวไหน "หายไปจากกล้อง" แล้วบ้าง
DEPARTURE_CHECK_SECONDS = int(os.environ.get("DEPARTURE_CHECK_SECONDS", 30))

EMAIL_PROVIDER = os.getenv("EMAIL_PROVIDER", "brevo").strip().lower()
BREVO_API_KEY = os.getenv("BREVO_API_KEY", "")
EMAIL_FROM = os.getenv("EMAIL_FROM", "")

# ── DB ────────────────────────────────────────────────────────────────────────
client = MongoClient(MONGODB_URL)
db = client[MONGO_NAME]
users_col = db["users"]
vehicles_col = db["vehicles"]
cameras_col = db["cameras"]
otp_codes_col = db["otp_codes"]

try:
    client.admin.command("ping")
    print(f"✅ Connected to MongoDB: {MONGODB_URL}{MONGO_NAME}")
except Exception as e:
    print(f"❌ MongoDB connection failed: {e}")

# ── Firebase Cloud Messaging (push) ───────────────────────────────────────────
_FIREBASE_KEY = Path(__file__).parent.parent / "db_config" / "firebase-adminsdk-key-fbsvc-a8c8f167bd.json"
_fcm_ready = False
try:
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(str(_FIREBASE_KEY)))
    _fcm_ready = True
    print("✅ Firebase Messaging initialized")
except Exception as e:
    print(f"⚠️ Firebase init failed (push disabled): {e}")


def _push_to_user(user_id: str, title: str, body: str, data: dict | None = None) -> int:
    """ส่ง FCM push ไปทุก device ของ user คนนี้ คืนจำนวนที่ส่งสำเร็จ
    (ไม่ throw — push ล้มเหลวไม่ควรทำให้ endpoint พัง)"""
    if not _fcm_ready:
        return 0
    try:
        user = users_col.find_one({"_id": ObjectId(user_id)})
    except Exception:
        return 0
    tokens = (user or {}).get("device_tokens", []) or []
    sent = 0
    stale = []
    for tok in tokens:
        try:
            messaging.send(messaging.Message(
                token=tok,
                notification=messaging.Notification(title=title, body=body),
                data={k: str(v) for k, v in (data or {}).items()},
            ))
            sent += 1
        except messaging.UnregisteredError:
            stale.append(tok)  # token ตายแล้ว เก็บไว้ลบ
        except Exception as e:
            print(f"[FCM] send error: {e!r}")
    if stale:
        users_col.update_one({"_id": ObjectId(user_id)},
                             {"$pull": {"device_tokens": {"$in": stale}}})
    return sent
    raise

# ── Helpers ───────────────────────────────────────────────────────────────────
try:
    otp_codes_col.create_index(
        "expires_at",
        expireAfterSeconds=0,
        name="otp_codes_expires_at_ttl",
    )
    otp_codes_col.create_index(
        [("email", 1), ("purpose", 1), ("created_at", -1)],
        name="otp_codes_lookup",
    )
except Exception as e:
    print(f"Warning: unable to ensure otp_codes indexes: {e}")

bearer_scheme = HTTPBearer()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


def create_token(payload: dict) -> str:
    data = payload.copy()
    data["exp"] = datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRE_HOURS)
    return jwt.encode(data, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


def get_current_user(creds: HTTPAuthorizationCredentials = Depends(bearer_scheme)):
    return decode_token(creds.credentials)


def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user


def require_internal_secret(x_internal_secret: str = Header(...)) -> None:
    if x_internal_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Invalid internal secret")

def hash_password(password: str) -> str:
    return bcrypt.hashpw(
        password.encode(),
        bcrypt.gensalt()
    ).decode()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _normalize_lamduan_email(email: str) -> str:
    normalized = email.strip().lower()
    if not normalized.endswith("@lamduan.mfu.ac.th"):
        raise HTTPException(
            status_code=400,
            detail="Only @lamduan.mfu.ac.th email is allowed",
        )
    return normalized


def _hash_secret(value: str) -> str:
    return hmac.new(
        JWT_SECRET.encode(),
        value.encode(),
        hashlib.sha256,
    ).hexdigest()


def _hash_otp(email: str, otp: str) -> str:
    return _hash_secret(f"{OTP_PURPOSE_PASSWORD_RESET}:otp:{email}:{otp}")


def _hash_reset_token(email: str, token: str) -> str:
    return _hash_secret(f"{OTP_PURPOSE_PASSWORD_RESET}:token:{email}:{token}")


def _find_password_reset_user(username: str, email: str) -> dict:
    user = users_col.find_one(
        {
            "name": username.strip(),
            "email": email,
        }
    )
    if not user:
        raise HTTPException(status_code=404, detail="Username or email incorrect")
    return user


def _send_password_reset_otp(to_email: str, otp: str) -> None:
    if EMAIL_PROVIDER != "brevo":
        raise HTTPException(status_code=500, detail="Unsupported email provider")

    brevo_api_key = os.getenv("BREVO_API_KEY", "").strip()
    email_from = os.getenv("EMAIL_FROM", "").strip()

    if not brevo_api_key or not email_from:
        raise HTTPException(status_code=500, detail="Email service is not configured")

    subject = "Vehicle Self-Tracking Password Reset OTP"
    text_body = f"""Your Vehicle Self-Tracking password reset OTP is:

{otp}

This code expires in {OTP_EXPIRE_MINUTES} minutes.
If you did not request a password reset, you can ignore this email.
"""

    html_body = f"""
    <div style="font-family:Arial,sans-serif;line-height:1.6">
      <h2>Password Reset OTP</h2>
      <p>Your Vehicle Self-Tracking password reset OTP is:</p>
      <p style="font-size:28px;font-weight:700;letter-spacing:4px">{otp}</p>
      <p>This code expires in {OTP_EXPIRE_MINUTES} minutes.</p>
      <p>If you did not request a password reset, you can ignore this email.</p>
    </div>
    """

    payload = {
        "sender": {"name": "MFU Tracker", "email": EMAIL_FROM},
        "to": [{"email": to_email}],
        "subject": subject,
        "textContent": text_body,
        "htmlContent": html_body,
    }

    try:
        res = requests.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={
                "accept": "application/json",
                "api-key": brevo_api_key,
                "content-type": "application/json",
            },
            json=payload,
            timeout=10,
        )
        if res.status_code >= 300:
            raise HTTPException(
                status_code=500,
                detail=f"Unable to send OTP email. Brevo error: {res.text}",
            )
    except requests.RequestException:
        raise HTTPException(
            status_code=500,
            detail="Unable to send OTP email. Please try again later.",
        )

def _camera_to_public_dict(doc: dict) -> dict:
    return {
        "id": str(doc["_id"]),
        "name": doc.get("name", "Camera"),
        "location_name": doc.get("location_name", ""),
        "latitude": doc["latitude"],
        "longitude": doc["longitude"],
        "status": doc.get("status", "unknown"),
    }


def _camera_to_admin_dict(doc: dict) -> dict:
    public = _camera_to_public_dict(doc)
    public["rtsp_url"] = doc.get("rtsp_url", "")
    public["detection_zones"] = doc.get("detection_zones", [])
    public["located"] = doc.get("located", True)
    public["ip"] = doc.get("ip", "")
    return public


def _seed_cameras_from_file_if_empty() -> None:
    if cameras_col.count_documents({}) > 0 or not CAMERAS_FILE.exists():
        return

    try:
        raw_cameras = json.loads(CAMERAS_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return
    if not isinstance(raw_cameras, list):
        return

    docs = []
    for item in raw_cameras:
        if not isinstance(item, dict) or item.get("enabled") is False:
            continue
        try:
            latitude = float(item["latitude"])
            longitude = float(item["longitude"])
        except (KeyError, TypeError, ValueError):
            continue
        docs.append(
            {
                "name": str(item.get("name") or "Camera"),
                "location_name": str(item.get("location_name") or ""),
                "latitude": latitude,
                "longitude": longitude,
                "rtsp_url": "",
                "status": str(item.get("status") or "unknown"),
                "detection_zones": [],
                "created_at": datetime.now(timezone.utc),
                "updated_at": datetime.now(timezone.utc),
            }
        )
    if docs:
        cameras_col.insert_many(docs)


_seed_cameras_from_file_if_empty()


def _read_camera_csv_rows() -> list[dict]:
    """อ่าน CSV กล้อง (ไฟล์เดียวกับที่ ai_worker ใช้) รองรับทั้ง utf-8 และ cp874
    คืน [] ถ้าหาไฟล์ไม่เจอ/อ่านไม่ได้ (เพื่อไม่ให้ endpoint พังเวลาไม่มี CSV)"""
    if not CAMERA_CSV_PATH.exists():
        return []
    for enc in ("utf-8-sig", "cp874"):
        try:
            with CAMERA_CSV_PATH.open("r", encoding=enc, newline="") as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    return []


def _sync_cameras_from_csv() -> None:
    """upsert กล้องจาก CSV เข้า collection `cameras` (idempotent, key = ชื่อกล้อง)

    - rtsp_url / ip = อัปเดตจาก CSV ทุกครั้ง (CSV เป็นเจ้าของสตรีม — ตรงกับที่ ai_worker ใช้)
    - location_name / latitude / longitude / located / status / detection_zones
      = ตั้งเฉพาะตอน insert ครั้งแรก (placeholder + located=False) แล้วปล่อยให้ admin
      แก้/ปักหมุดจริงทีหลัง โดยไม่โดน sync เขียนทับ

    เรียกตอน admin โหลดรายชื่อกล้อง เพื่อให้ชื่อที่เพิ่งเพิ่มใน CSV/ACTIVE_CAMERAS
    โผล่มาให้ปักหมุดได้เอง โดยไม่ต้องแตะ ai_worker"""
    now = datetime.now(timezone.utc)
    for row in _read_camera_csv_rows():
        name = (row.get(CSV_NAME_COL) or "").strip()
        rtsp = (row.get(CSV_RTSP_COL) or "").strip()
        enabled = (row.get(CSV_ENABLE_COL) or "").strip().lower() == "ok"
        if not name or not rtsp or not enabled:
            continue
        cameras_col.update_one(
            {"name": name},
            {
                "$set": {
                    "rtsp_url": rtsp,
                    "ip": (row.get(CSV_IP_COL) or "").strip(),
                    "source": "csv-import",
                },
                "$setOnInsert": {
                    "location_name": (row.get(CSV_POSITION_COL) or "").strip(),
                    "latitude": CAMERA_PLACEHOLDER_LAT,
                    "longitude": CAMERA_PLACEHOLDER_LON,
                    "located": False,
                    "status": "active",
                    "detection_zones": [],
                    "created_at": now,
                    "updated_at": now,
                },
            },
            upsert=True,
        )


def _check_departed_locked_vehicles() -> None:
    """หา 'รถที่ล็อกอยู่แล้วหายไปจากกล้อง' → ยิงแจ้งเตือน UNAUTHORIZED_MOVE ('Is this you?')
    ครั้งเดียวต่อการหายไปหนึ่งครั้ง

    เงื่อนไข: locked=True และเคยถูกกล้องเห็น (last_detection มี) แต่ไม่เห็นมานานเกิน
    DETECTION_PRESENCE_SECONDS (= รถถูกเคลื่อนออกไปจากกล้อง) และยังไม่เคยเตือนการหายรอบนี้
    (กันเตือนซ้ำด้วย flag last_detection.departed_alerted — จะรีเซ็ตเองเมื่อกล้องเห็นรถอีก
    เพราะ /internal/plate-detected เขียน last_detection ก้อนใหม่ทับ)"""
    now = datetime.now(timezone.utc)
    now_naive = now.replace(tzinfo=None)
    for v in vehicles_col.find({"locked": True, "last_detection": {"$ne": None}}):
        ld = v.get("last_detection") or {}
        at = ld.get("at")
        if at is None or ld.get("departed_alerted"):
            continue
        if getattr(at, "tzinfo", None) is not None:
            at = at.astimezone(timezone.utc).replace(tzinfo=None)
        # ยังเห็นอยู่ (ยังจอด) → ไม่ใช่การหาย
        if (now_naive - at).total_seconds() <= DETECTION_PRESENCE_SECONDS:
            continue
        db["notifications"].insert_one({
            "user_id": v["user_id"],
            "alert_type": "UNAUTHORIZED_MOVE",
            "snapshot_url": "",
            "license_plate": v.get("license_plate", ""),
            "camera_name": ld.get("camera_name", ""),
            "created_at": now,
            "read": False,
        })
        _push_to_user(
            v["user_id"],
            "Is this you?",
            (v.get("license_plate", "") +
             (f" left {ld.get('camera_name')}" if ld.get("camera_name") else " left the camera") +
             " while locked"),
            data={"alert_type": "UNAUTHORIZED_MOVE",
                  "license_plate": v.get("license_plate", ""),
                  "camera_name": ld.get("camera_name", "")},
        )
        # กันเตือนซ้ำการหายรอบนี้ (จะถูกล้างเมื่อกล้องเห็นรถอีกครั้ง)
        vehicles_col.update_one(
            {"_id": v["_id"]},
            {"$set": {"last_detection.departed_alerted": True}},
        )
        print(f"[departure-watcher] UNAUTHORIZED_MOVE → {v.get('license_plate','')} "
              f"left {ld.get('camera_name','')}")


def _departure_watcher_loop() -> None:
    while True:
        try:
            _check_departed_locked_vehicles()
        except Exception as e:
            print(f"[departure-watcher] error: {e!r}")
        time.sleep(DEPARTURE_CHECK_SECONDS)


# background thread คอยเช็กรถ locked ที่หายไปจากกล้อง (daemon → ปิดพร้อมเซิร์ฟเวอร์)
threading.Thread(target=_departure_watcher_loop, daemon=True,
                 name="departure-watcher").start()
print(f"✅ Departure watcher started (every {DEPARTURE_CHECK_SECONDS}s, "
      f"presence window {DETECTION_PRESENCE_SECONDS}s)")


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="Test Backend", version="0.1.0")

class LoginRequest(BaseModel):
    email: str
    password: str

class RegisterRequest(BaseModel):
    name: str
    email: str
    password: str

# ── login ───────────────────────────────────────────────────────────────────────
@app.post("/auth/login")
def login(req: LoginRequest):
    user = users_col.find_one({"$or": [{"email": req.email}, {"name": req.email}]})
    if not user or not verify_password(req.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    role = user.get("role", "user")
    token = create_token(
        {"sub": str(user["_id"]), "name": user["name"], "email": user["email"], "role": role}
    )
    return {"access_token": token, "token_type": "bearer", "role": role}

# ── register ───────────────────────────────────────────────────────────────────────
@app.post("/auth/register")
def register(req: RegisterRequest):

    email = req.email.strip().lower()

    # รับเฉพาะเมล MFU
    if not email.endswith("@lamduan.mfu.ac.th"):
        raise HTTPException(
            status_code=400,
            detail="Only MFU email is allowed."
        )

    # ตรวจสอบ email ซ้ำ
    if users_col.find_one({"email": email}):
        raise HTTPException(
            status_code=409,
            detail="Email already exists."
        )

    # ตรวจสอบ username ซ้ำ
    if users_col.find_one({"name": req.name.strip()}):
        raise HTTPException(
            status_code=409,
            detail="Username already exists."
        )

    user = {
        "name": req.name.strip(),
        "email": email,
        "password": hash_password(req.password),
        "created_at": datetime.now(timezone.utc)
    }

    result = users_col.insert_one(user)

    return {
        "message": "Register success",
        "id": str(result.inserted_id)
    }

# ── delete user ───────────────────────────────────────────────────────────────────────
@app.delete("/auth/user/{user_id}")
def delete_user(user_id: str):

    result = users_col.delete_one(
        {"_id": ObjectId(user_id)}
    )

    if result.deleted_count == 0:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    return {
        "message": "User deleted successfully"
    }

@app.get("/auth/me")
def me(current_user: dict = Depends(get_current_user)):
    return {
        "id": current_user["sub"],
        "name": current_user["name"],
        "email": current_user["email"],
        "role": current_user.get("role", "user"),
    }


class UpdateProfileRequest(BaseModel):
    name: str | None = None
    email: str | None = None

class ForgotVerifyRequest(BaseModel):
    username: str
    email: str

class ForgotOtpVerifyRequest(BaseModel):
    username: str
    email: str
    otp: str

class ResetPasswordRequest(BaseModel):
    username: str
    email: str
    password: str
    reset_token: str

class OTPRequest(BaseModel):
    username: str
    email: str


@app.post("/auth/forgot-password/verify")
def verify_account(req: ForgotVerifyRequest):
    email = _normalize_lamduan_email(req.email)
    username = req.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="Username is required")

    user = _find_password_reset_user(username, email)
    now = _utcnow()
    otp = f"{secrets.randbelow(1000000):06d}"

    otp_codes_col.update_many(
        {
            "email": email,
            "purpose": OTP_PURPOSE_PASSWORD_RESET,
            "used_at": {"$exists": False},
        },
        {
            "$set": {
                "used_at": now,
                "invalidated_at": now,
                "updated_at": now,
            }
        },
    )

    otp_doc = {
        "user_id": str(user["_id"]),
        "username": username,
        "email": email,
        "purpose": OTP_PURPOSE_PASSWORD_RESET,
        "otp_hash": _hash_otp(email, otp),
        "attempts": 0,
        "max_attempts": OTP_MAX_ATTEMPTS,
        "expires_at": now + timedelta(minutes=OTP_EXPIRE_MINUTES),
        "created_at": now,
        "updated_at": now,
    }
    result = otp_codes_col.insert_one(otp_doc)

    try:
        _send_password_reset_otp(email, otp)
    except HTTPException:
        otp_codes_col.delete_one({"_id": result.inserted_id})
        raise

    return {
        "success": True,
        "message": "OTP sent to Lamduan Mail",
        "expires_in_minutes": OTP_EXPIRE_MINUTES,
    }


@app.post("/auth/forgot-password/request")
def request_password_reset_otp(req: OTPRequest):
    return verify_account(ForgotVerifyRequest(username=req.username, email=req.email))


@app.post("/auth/forgot-password/verify-otp")
def verify_otp(req: ForgotOtpVerifyRequest):
    email = _normalize_lamduan_email(req.email)
    username = req.username.strip()
    otp = req.otp.strip()

    if not username:
        raise HTTPException(status_code=400, detail="Username is required")
    if len(otp) != 6 or not otp.isdigit():
        raise HTTPException(status_code=400, detail="OTP must be 6 digits")

    now = _utcnow()
    otp_doc = otp_codes_col.find_one(
        {
            "username": username,
            "email": email,
            "purpose": OTP_PURPOSE_PASSWORD_RESET,
            "used_at": {"$exists": False},
            "verified_at": {"$exists": False},
        },
        sort=[("created_at", -1)],
    )

    if not otp_doc:
        raise HTTPException(status_code=400, detail="OTP not found. Please request a new code")

    if now > otp_doc["expires_at"]:
        otp_codes_col.update_one(
            {"_id": otp_doc["_id"]},
            {"$set": {"used_at": now, "expired_at": now, "updated_at": now}},
        )
        raise HTTPException(status_code=400, detail="OTP expired")

    attempts = int(otp_doc.get("attempts", 0))
    max_attempts = int(otp_doc.get("max_attempts", OTP_MAX_ATTEMPTS))
    if attempts >= max_attempts:
        otp_codes_col.update_one(
            {"_id": otp_doc["_id"]},
            {"$set": {"used_at": now, "updated_at": now}},
        )
        raise HTTPException(status_code=400, detail="Too many invalid attempts. Request a new OTP")

    if not hmac.compare_digest(otp_doc["otp_hash"], _hash_otp(email, otp)):
        next_attempts = attempts + 1
        update = {"$inc": {"attempts": 1}, "$set": {"updated_at": now}}
        if next_attempts >= max_attempts:
            update["$set"]["used_at"] = now
        otp_codes_col.update_one({"_id": otp_doc["_id"]}, update)
        if next_attempts >= max_attempts:
            raise HTTPException(status_code=400, detail="Too many invalid attempts. Request a new OTP")
        raise HTTPException(status_code=400, detail="Invalid OTP")

    reset_token = secrets.token_urlsafe(32)
    otp_codes_col.update_one(
        {"_id": otp_doc["_id"]},
        {
            "$set": {
                "verified_at": now,
                "reset_token_hash": _hash_reset_token(email, reset_token),
                "updated_at": now,
            }
        },
    )

    return {
        "success": True,
        "message": "OTP verified",
        "reset_token": reset_token,
    }


@app.post("/auth/forgot-password/reset")
def reset_password(req: ResetPasswordRequest):
    email = _normalize_lamduan_email(req.email)
    username = req.username.strip()
    password = req.password
    reset_token = req.reset_token.strip()

    if not username:
        raise HTTPException(status_code=400, detail="Username is required")
    if len(password) < 4:
        raise HTTPException(status_code=400, detail="Password must be at least 4 characters")
    if not reset_token:
        raise HTTPException(status_code=400, detail="OTP verification is required")

    user = _find_password_reset_user(username, email)
    now = _utcnow()
    otp_doc = otp_codes_col.find_one(
        {
            "user_id": str(user["_id"]),
            "username": username,
            "email": email,
            "purpose": OTP_PURPOSE_PASSWORD_RESET,
            "reset_token_hash": _hash_reset_token(email, reset_token),
            "verified_at": {"$exists": True},
            "used_at": {"$exists": False},
            "expires_at": {"$gt": now},
        },
        sort=[("verified_at", -1)],
    )

    if not otp_doc:
        raise HTTPException(status_code=400, detail="OTP verification expired or invalid")

    users_col.update_one(
        {"_id": user["_id"]},
        {"$set": {"password": hash_password(password), "updated_at": now}},
    )
    otp_codes_col.update_one(
        {"_id": otp_doc["_id"]},
        {"$set": {"used_at": now, "updated_at": now}},
    )

    return {
        "success": True,
        "message": "Password updated",
    }

@app.patch("/auth/profile")
def update_profile(req: UpdateProfileRequest, current_user: dict = Depends(get_current_user)):
    from bson import ObjectId
    update = {}
    if req.name is not None and req.name.strip():
        update["name"] = req.name.strip()
    if req.email is not None and req.email.strip():
        new_email = req.email.strip().lower()
        # ตรวจสอบว่า email ซ้ำกับคนอื่นไหม
        existing = users_col.find_one({"email": new_email, "_id": {"$ne": ObjectId(current_user["sub"])}})
        if existing:
            raise HTTPException(status_code=409, detail="Email already in use")
        update["email"] = new_email
    if not update:
        raise HTTPException(status_code=400, detail="Nothing to update")
    users_col.update_one({"_id": ObjectId(current_user["sub"])}, {"$set": update})
    updated = users_col.find_one({"_id": ObjectId(current_user["sub"])})
    return {
        "id": str(updated["_id"]),
        "name": updated["name"],
        "email": updated["email"],
    }


def _normalize_plate(s: str) -> str:
    """ตัดช่องว่างทั้งหมดและทำเป็นตัวพิมพ์ใหญ่ เพื่อใช้เทียบป้ายข้ามฟอร์แมต
    (ตัวพิมพ์ใหญ่ไม่กระทบอักษรไทย แต่ช่วยเวลาป้ายมีตัวอังกฤษ)"""
    return "".join((s or "").split()).upper()


def _ai_plate_matches(doc: dict, vehicle: dict) -> bool:
    """เอกสาร notification จาก ai_worker เก็บป้ายเป็นสตริงเดียว จังหวัดอยู่กลาง
    (เช่น "2กฏ เชียงราย 2026") ส่วน vehicles เก็บ license_plate ("2กฏ 2026")
    กับ province ("เชียงราย") แยกช่อง — จึงตัดจังหวัดออกก่อนแล้วค่อยเทียบ"""
    if not vehicle:
        return False
    province = (vehicle.get("province") or "").strip()
    plate = vehicle.get("license_plate", "")
    # ตัดจังหวัดออกจากทั้งสองฝั่งก่อนเทียบ (เผื่อฝั่ง vehicle กรอกจังหวัดปนในช่องป้าย)
    target = _normalize_plate(plate.replace(province, " ") if province else plate)
    if not target:
        return False
    raw = str(doc.get("license_plate_text") or "")
    cleaned = raw.replace(province, " ") if province else raw
    return _normalize_plate(cleaned) == target


def _iso_z(dt) -> str | None:
    """แปลง datetime เป็น ISO string ลงท้ายด้วย Z (บังคับเป็น UTC naive ก่อน
    เพื่อไม่ให้ได้ค่าอย่าง '...+00:00Z' ที่ frontend parse ไม่ได้)"""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.isoformat() + "Z"


class DeviceTokenBody(BaseModel):
    token: str


@app.post("/me/device-token")
def save_device_token(body: DeviceTokenBody, current_user: dict = Depends(get_current_user)):
    """แอปเรียกหลัง login เพื่อผูก FCM token ของเครื่องเข้ากับ user คนนี้"""
    token = (body.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token required")
    users_col.update_one(
        {"_id": ObjectId(current_user["sub"])},
        {"$addToSet": {"device_tokens": token}},
    )
    return {"ok": True}


@app.delete("/me/device-token")
def delete_device_token(body: DeviceTokenBody, current_user: dict = Depends(get_current_user)):
    """แอปเรียกตอน logout เพื่อเลิกรับ push บนเครื่องนี้"""
    users_col.update_one(
        {"_id": ObjectId(current_user["sub"])},
        {"$pull": {"device_tokens": (body.token or "").strip()}},
    )
    return {"ok": True}


@app.get("/notifications")
def get_notifications(current_user: dict = Depends(get_current_user)):
    alerts_col = db["notifications"]
    results = []

    # 1) การแจ้งเตือนที่ backend สร้างเอง (มี user_id + created_at ครบ)
    native = alerts_col.find(
        {"user_id": current_user["sub"]},
        sort=[("created_at", -1)],
        limit=50,
    )
    for doc in native:
        results.append({
            "id": str(doc["_id"]),
            "alert_type": doc.get("alert_type", "INFO"),
            "snapshot_url": doc.get("snapshot_url", ""),
            "created_at": _iso_z(doc.get("created_at")) or _iso_z(datetime.now(timezone.utc)),
            "read": doc.get("read", False),
            "license_plate": str(doc.get("license_plate") or ""),
            "camera_name": doc.get("camera_name", ""),
        })

    # 2) การแจ้งเตือนจากตัวตรวจจับ AI (ai_worker เขียน Mongo ตรง ๆ ไม่มี user_id)
    #    เชื่อมเข้ากับ user ด้วยการแมตช์ป้ายทะเบียนกับรถของ user เอง
    vehicle = vehicles_col.find_one({"user_id": current_user["sub"]})
    if vehicle:
        ai_docs = alerts_col.find(
            {"user_id": {"$exists": False}, "license_plate_text": {"$exists": True}},
            sort=[("sent_at", -1)],
            limit=50,
        )
        for doc in ai_docs:
            if not _ai_plate_matches(doc, vehicle):
                continue
            results.append({
                "id": str(doc["_id"]),
                "alert_type": "PLATE_DETECTED",
                "snapshot_url": doc.get("snapshot_url", ""),
                "created_at": _iso_z(doc.get("sent_at")) or _iso_z(doc.get("created_at")) or _iso_z(datetime.now(timezone.utc)),
                "read": doc.get("read", False),
                "license_plate": str(doc.get("license_plate_text") or ""),
                "camera_name": doc.get("camera_name", ""),
            })

    # รวมสองแหล่งแล้วเรียงใหม่-เก่า (ISO string ลงท้าย Z เรียงแบบ lexicographic ได้)
    results.sort(key=lambda r: r["created_at"], reverse=True)
    return results[:50]


@app.patch("/notifications/{notification_id}/read")
def mark_read(notification_id: str, current_user: dict = Depends(get_current_user)):
    from bson import ObjectId
    alerts_col = db["notifications"]
    try:
        oid = ObjectId(notification_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid notification id")

    doc = alerts_col.find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Notification not found")

    # ตรวจความเป็นเจ้าของ: doc ของ backend ใช้ user_id, doc ของ AI ใช้การแมตช์ป้าย
    owned = doc.get("user_id") == current_user["sub"]
    if not owned and "user_id" not in doc:
        vehicle = vehicles_col.find_one({"user_id": current_user["sub"]})
        owned = _ai_plate_matches(doc, vehicle)
    if not owned:
        raise HTTPException(status_code=404, detail="Notification not found")

    alerts_col.update_one({"_id": oid}, {"$set": {"read": True}})
    return {"ok": True}


@app.get("/internal/cameras")
def internal_list_cameras(_: None = Depends(require_internal_secret)):
    """ai_worker เรียกดึงรายชื่อกล้องจาก DB (แหล่งข้อมูลเดียว) แทนการอ่าน CSV
    คืน field เทียบเท่า CSV เดิม: name, rtsp_url(=RTSP), position(=POSITION), ip"""
    docs = cameras_col.find(sort=[("name", 1)])
    return [
        {
            "name": d.get("name", ""),
            "rtsp_url": d.get("rtsp_url", ""),
            "position": d.get("location_name", ""),
            "ip": d.get("ip", ""),
            "latitude": d.get("latitude"),
            "longitude": d.get("longitude"),
            "status": d.get("status", "unknown"),
        }
        for d in docs
    ]


@app.get("/cameras")
def get_cameras(current_user: dict = Depends(get_current_user)):
    # แสดงเฉพาะกล้องที่ปักพิกัดจริงแล้ว (located != False) เพื่อไม่ให้กล้องที่ import
    # มาจาก CSV (ยังไม่ได้ปักพิกัด) ไปกองที่ placeholder บนแผนที่ user
    docs = cameras_col.find({"located": {"$ne": False}}, sort=[("created_at", 1)])
    return [_camera_to_public_dict(doc) for doc in docs]


class CameraCreate(BaseModel):
    name: str
    location_name: str = ""
    latitude: float
    longitude: float
    rtsp_url: str = ""


class CameraUpdate(BaseModel):
    name: str | None = None
    location_name: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    rtsp_url: str | None = None
    status: str | None = None


class DetectionZone(BaseModel):
    id: str
    points: list[dict]


class DetectionZonesUpdate(BaseModel):
    detection_zones: list[DetectionZone]


@app.get("/admin/cameras")
def admin_list_cameras(current_user: dict = Depends(require_admin)):
    # คืนเฉพาะกล้องที่มีใน Mongo (= ที่ปักหมุดผ่าน dropdown แล้ว) — เร็ว ไม่ sync ที่นี่
    # รายชื่อกล้องทั้งหมดให้เลือกปักอยู่ที่ GET /admin/csv-cameras (อ่าน CSV ตรง)
    docs = cameras_col.find(sort=[("created_at", 1)])
    return [_camera_to_admin_dict(doc) for doc in docs]


@app.get("/admin/csv-cameras")
def admin_list_csv_cameras(current_user: dict = Depends(require_admin)):
    """คืนรายชื่อกล้องจาก CSV ตรง ๆ (name + rtsp_url + position) สำหรับทำ dropdown
    ให้ admin เลือกมาปักหมุด — ไม่ผูกกับสถานะใน Mongo จึงเห็นครบทุกตัวเสมอ
    (แต่ติด flag `pinned` ให้ด้วยถ้าเช็ค Mongo ได้ เพื่อกันเลือกตัวที่ปักไปแล้วซ้ำ)"""
    try:
        pinned = {d["name"] for d in cameras_col.find({"located": True}, {"name": 1})}
    except Exception as e:
        print(f"[cameras] pinned-check skipped: {e!r}")
        pinned = set()
    out = []
    for row in _read_camera_csv_rows():
        name = (row.get(CSV_NAME_COL) or "").strip()
        rtsp = (row.get(CSV_RTSP_COL) or "").strip()
        enabled = (row.get(CSV_ENABLE_COL) or "").strip().lower() == "ok"
        if not name or not rtsp or not enabled:
            continue
        out.append({
            "name": name,
            "rtsp_url": rtsp,
            "position": (row.get(CSV_POSITION_COL) or "").strip(),
            "pinned": name in pinned,
        })
    return out


@app.post("/admin/cameras")
def admin_create_camera(req: CameraCreate, current_user: dict = Depends(require_admin)):
    now = datetime.now(timezone.utc)
    name = req.name.strip() or "Camera"
    # upsert ด้วย "ชื่อกล้อง" → ปักหมุดกล้องจาก CSV โดยไม่สร้าง doc ซ้ำ
    # (ถ้ากล้องชื่อนี้เคย sync/สร้างไว้แล้ว จะอัปเดตตัวเดิมให้ located=True)
    cameras_col.update_one(
        {"name": name},
        {
            "$set": {
                "name": name,
                "location_name": req.location_name.strip(),
                "latitude": req.latitude,
                "longitude": req.longitude,
                "rtsp_url": req.rtsp_url.strip(),
                "located": True,
                "status": "active",
                "updated_at": now,
            },
            "$setOnInsert": {"detection_zones": [], "created_at": now},
        },
        upsert=True,
    )
    return _camera_to_admin_dict(cameras_col.find_one({"name": name}))


@app.patch("/admin/cameras/{camera_id}")
def admin_update_camera(
    camera_id: str,
    req: CameraUpdate,
    current_user: dict = Depends(require_admin),
):
    try:
        object_id = ObjectId(camera_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid camera id")

    update = {}
    if req.name is not None and req.name.strip():
        update["name"] = req.name.strip()
    if req.location_name is not None:
        update["location_name"] = req.location_name.strip()
    if req.latitude is not None:
        update["latitude"] = req.latitude
    if req.longitude is not None:
        update["longitude"] = req.longitude
    if req.latitude is not None or req.longitude is not None:
        # ปักพิกัดจริงแล้ว → ให้กล้องนี้โผล่บนแผนที่ฝั่ง user
        update["located"] = True
    if req.rtsp_url is not None:
        update["rtsp_url"] = req.rtsp_url.strip()
    if req.status is not None and req.status.strip():
        update["status"] = req.status.strip()
    if not update:
        raise HTTPException(status_code=400, detail="Nothing to update")
    update["updated_at"] = datetime.now(timezone.utc)

    result = cameras_col.update_one({"_id": object_id}, {"$set": update})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Camera not found")
    updated = cameras_col.find_one({"_id": object_id})
    return _camera_to_admin_dict(updated)


@app.patch("/admin/cameras/{camera_id}/detection-zones")
def admin_update_detection_zones(
    camera_id: str,
    req: DetectionZonesUpdate,
    current_user: dict = Depends(require_admin),
):
    try:
        object_id = ObjectId(camera_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid camera id")

    zones = [zone.model_dump() for zone in req.detection_zones]
    result = cameras_col.update_one(
        {"_id": object_id},
        {"$set": {"detection_zones": zones, "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Camera not found")
    updated = cameras_col.find_one({"_id": object_id})
    return _camera_to_admin_dict(updated)


@app.delete("/admin/cameras/{camera_id}")
def admin_delete_camera(camera_id: str, current_user: dict = Depends(require_admin)):
    try:
        object_id = ObjectId(camera_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid camera id")

    result = cameras_col.delete_one({"_id": object_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Camera not found")
    return {"ok": True}


class VehicleCreate(BaseModel):
    model: str
    license_plate: str
    province: str
    color: str | None = None
    geofence_radius_m: int = 50

class VehicleUpdate(BaseModel):
    model: str | None = None
    license_plate: str | None = None
    province: str | None = None
    color: str | None = None
    geofence_radius_m: int | None = None


IMAGE_SLOTS = ["front", "back", "left", "right", "plate"]


def _vehicle_to_dict(doc: dict) -> dict:
    images = doc.get("images", {})
    return {
        "id": str(doc["_id"]),
        "model": doc.get("model", ""),
        "license_plate": doc.get("license_plate", ""),
        "province": doc.get("province", ""),
        "color": doc.get("color", ""),
        "detection": doc.get("detection",1),
        "geofence_radius_m": doc.get("geofence_radius_m", 50),
        "locked": doc.get("locked", False),
        "images": {slot: images.get(slot, "") for slot in IMAGE_SLOTS},
        "last_detection": _last_detection_public(doc.get("last_detection")),
    }


def _last_detection_public(ld: dict | None) -> dict | None:
    """แปลง last_detection (ตำแหน่งกล้องที่ AI จับป้ายได้ล่าสุด) เป็นรูปแบบ JSON
    ที่ frontend ใช้ได้ (เวลาเป็น ISO ...Z)"""
    if not ld:
        return None
    at = ld.get("at")
    if at is not None and getattr(at, "tzinfo", None) is not None:
        at = at.astimezone(timezone.utc).replace(tzinfo=None)
    # หมุดหายเมื่อรถออก: ถ้ากล้องไม่เห็นเกิน DETECTION_PRESENCE_SECONDS ถือว่ารถไม่อยู่แล้ว
    # → คืน None เพื่อให้ frontend ไม่ปักหมุด (จนกว่าจะกลับมาเห็นใหม่)
    if at is not None:
        age = (datetime.now(timezone.utc).replace(tzinfo=None) - at).total_seconds()
        if age > DETECTION_PRESENCE_SECONDS:
            return None
    return {
        "camera_name": ld.get("camera_name", ""),
        "latitude": ld.get("latitude"),
        "longitude": ld.get("longitude"),
        "at": (at.isoformat() + "Z") if at is not None else None,
    }


@app.get("/vehicles")
def get_vehicles(current_user: dict = Depends(get_current_user)):
    docs = vehicles_col.find({"user_id": current_user["sub"]}, sort=[("created_at", 1)])
    return [_vehicle_to_dict(doc) for doc in docs]


@app.post("/vehicles")
def create_vehicle(req: VehicleCreate, current_user: dict = Depends(get_current_user)):
    if vehicles_col.count_documents({"user_id": current_user["sub"]}) > 0:
        raise HTTPException(status_code=409, detail="You can only register 1 vehicle per account")
    doc = {
        "user_id": current_user["sub"],
        "model": req.model.strip(),
        "license_plate": req.license_plate.strip().upper(),
        "province": req.province.strip(),
        "color": (req.color or "").strip(),
        "detection": req.detection if hasattr(req, 'detection') else 1,
        "geofence_radius_m": req.geofence_radius_m,
        "locked": False,
        "created_at": datetime.now(timezone.utc),
    }
    result = vehicles_col.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _vehicle_to_dict(doc)


@app.patch("/vehicles/{vehicle_id}")
def update_vehicle(
    vehicle_id: str,
    req: VehicleUpdate,
    current_user: dict = Depends(get_current_user),
):
    from bson import ObjectId

    update = {}
    if req.model is not None and req.model.strip():
        update["model"] = req.model.strip()
    if req.license_plate is not None and req.license_plate.strip():
        update["license_plate"] = req.license_plate.strip().upper()
    if req.province is not None and req.province.strip():
        update["province"] = req.province.strip()
    if req.color is not None:
        update["color"] = req.color.strip()
    if req.geofence_radius_m is not None:
        update["geofence_radius_m"] = req.geofence_radius_m
    if not update:
        raise HTTPException(status_code=400, detail="Nothing to update")

    result = vehicles_col.update_one(
        {"_id": ObjectId(vehicle_id), "user_id": current_user["sub"]},
        {"$set": update},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    updated = vehicles_col.find_one({"_id": ObjectId(vehicle_id)})
    return _vehicle_to_dict(updated)


MAX_IMAGE_BYTES = 8 * 1024 * 1024


@app.post("/vehicles/{vehicle_id}/photos")
async def upload_vehicle_photos(
    vehicle_id: str,
    front: UploadFile | None = File(None),
    back: UploadFile | None = File(None),
    left: UploadFile | None = File(None),
    right: UploadFile | None = File(None),
    plate: UploadFile | None = File(None),
    current_user: dict = Depends(get_current_user),
):
    from bson import ObjectId

    vehicle = vehicles_col.find_one(
        {"_id": ObjectId(vehicle_id), "user_id": current_user["sub"]}
    )
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    uploads = {"front": front, "back": back, "left": left, "right": right, "plate": plate}
    update = {}
    for slot, upload in uploads.items():
        if upload is None:
            continue
        if not (upload.content_type or "").startswith("image/"):
            raise HTTPException(status_code=400, detail=f"{slot} must be an image file")
        contents = await upload.read()
        if len(contents) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=400, detail=f"{slot} image exceeds 8MB")
        result = cloudinary.uploader.upload(
            contents,
            folder=f"vehicle-self-tracking/vehicles/{vehicle_id}",
            public_id=slot,
            overwrite=True,
            transformation=[
                {
                    "width": 1280,
                    "height": 1280,
                    "crop": "limit",
                    "quality": "auto",
                    "fetch_format": "auto"
                }
            ]
        )
        update[f"images.{slot}"] = result["secure_url"]

    if not update:
        raise HTTPException(status_code=400, detail="No images provided")

    vehicles_col.update_one({"_id": ObjectId(vehicle_id)}, {"$set": update})
    updated = vehicles_col.find_one({"_id": ObjectId(vehicle_id)})
    return _vehicle_to_dict(updated)


@app.delete("/vehicles/{vehicle_id}")
def delete_vehicle(vehicle_id: str, current_user: dict = Depends(get_current_user)):
    from bson import ObjectId

    result = vehicles_col.delete_one(
        {"_id": ObjectId(vehicle_id), "user_id": current_user["sub"]}
    )
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return {"ok": True}


class DetectionRequest(BaseModel):
    vehicle_id: str
    detection: int

class LockRequest(BaseModel):
    vehicle_id: str
    locked: bool


@app.put("/vehicle/detection")
def update_detection(
    data: DetectionRequest,
    user=Depends(get_current_user)
):
    if data.detection < 1 or data.detection > 5:
        raise HTTPException(
            status_code=400,
            detail="Detection must be between 1 and 5 minutes"
        )

    try:
        vehicle_id = ObjectId(data.vehicle_id)
    except InvalidId:
        raise HTTPException(
            status_code=400,
            detail="Invalid vehicle id"
        )

    result = vehicles_col.update_one(
        {
            "_id": vehicle_id,
            "user_id": user["sub"]   # เพิ่มบรรทัดนี้ให้ตรงกับโครงสร้างฐานข้อมูลของคุณ
        },
        {
            "$set": {
                "detection": data.detection
            }
        }
    )

    if result.matched_count == 0:
        raise HTTPException(
            status_code=404,
            detail="Vehicle not found"
        )

    updated = vehicles_col.find_one({
        "_id": vehicle_id
    })

    return _vehicle_to_dict(updated)

@app.put("/vehicle/lock")
def update_lock(
    data: LockRequest,
    user=Depends(get_current_user)
):
    try:
        vehicle_id = ObjectId(data.vehicle_id)
    except InvalidId:
        raise HTTPException(
            status_code=400,
            detail="Invalid vehicle id"
        )

    result = vehicles_col.update_one(
        {
            "_id": vehicle_id,
            "user_id": user["sub"]
        },
        {
            "$set": {
                "locked": data.locked
            }
        }
    )

    if result.matched_count == 0:
        raise HTTPException(
            status_code=404,
            detail="Vehicle not found"
        )

    updated = vehicles_col.find_one({
        "_id": vehicle_id
    })

    return _vehicle_to_dict(updated)


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class PlateDetectedEvent(BaseModel):
    license_plate: str
    province: str | None = None
    camera_name: str = ""
    latitude: float | None = None
    longitude: float | None = None
    snapshot_url: str | None = None


@app.post("/internal/plate-detected")
def report_plate_detected(
    event: PlateDetectedEvent,
    _: None = Depends(require_internal_secret),
):
    """เรียกโดยระบบตรวจจับ AI ทุกครั้งที่ OCR อ่านป้ายได้ — backend จะ resolve
    ป้าย → รถ → เจ้าของ แล้วสร้าง notification (schema เดียวกับของ backend)
    พร้อมยิง FCM push เข้าเครื่องเจ้าของ ระบบ AI จึงไม่ต้องแตะ Mongo/Firebase เอง"""
    plate = (event.license_plate or "").strip()
    if not plate:
        raise HTTPException(status_code=400, detail="license_plate required")

    # แมตช์ป้ายกับรถทุกคัน (reuse _ai_plate_matches ที่ normalize + ตัดจังหวัดให้)
    detected = {"license_plate_text": plate}
    matches = [v for v in vehicles_col.find({}) if _ai_plate_matches(detected, v)]
    if not matches:
        return {"ok": True, "notified": 0, "reason": "no matching vehicle"}

    # หาพิกัดของกล้องที่จับได้ (ใช้พิกัดกล้องเป็นตำแหน่งล่าสุดของรถ ถ้า event
    # ไม่ได้ส่งพิกัดมาเอง) — เพื่อให้ frontend แสดงรถ ณ ตำแหน่งกล้องที่ตรวจเจอ
    cam = cameras_col.find_one({"name": event.camera_name}) if event.camera_name else None
    det_lat = event.latitude if event.latitude is not None else (cam or {}).get("latitude")
    det_lon = event.longitude if event.longitude is not None else (cam or {}).get("longitude")

    now = datetime.now(timezone.utc)
    now_naive = now.replace(tzinfo=None)
    notified = 0
    refreshed = 0
    for vehicle in matches:
        # last_detection เดิม: เห็นล่าสุดเมื่อไหร่ + เคยแจ้ง "ตรวจเจอ" ในรอบจอดนี้ไปหรือยัง
        prev = vehicle.get("last_detection") or {}
        prev_at = prev.get("at")
        if prev_at is not None and getattr(prev_at, "tzinfo", None) is not None:
            prev_at = prev_at.astimezone(timezone.utc).replace(tzinfo=None)
        # "ยังจอดต่อเนื่อง (รอบเดิม)" = เคยเห็น และเพิ่งเห็นภายใน DETECTION_PRESENCE_SECONDS
        # OCR อ่านป้ายได้ห่าง ๆ → window ต้องยาวพอ ไม่งั้นจะนับเป็นรอบใหม่แล้วแจ้งซ้ำ
        same_session = (
            prev_at is not None
            and (now_naive - prev_at).total_seconds() <= DETECTION_PRESENCE_SECONDS
        )
        # แจ้ง "รถถูกตรวจจับ" แค่ครั้งเดียวต่อการมาจอด 1 รอบ:
        #   - รอบเดิม + เคยแจ้งแล้ว → ไม่แจ้งซ้ำ (แม้กล้องเห็นซ้ำอีกกี่ครั้ง)
        #   - มาจอดรอบใหม่ (หายไปนานเกิน window แล้วกลับมา) → แจ้งได้อีก
        already_notified = same_session and bool(prev.get("notified"))
        should_notify = not already_notified

        # อัปเดตตำแหน่ง + at + flag notified "เสมอ" → หมุดค้าง/ขยับตามกล้องที่เห็นล่าสุด
        # และจำได้ว่าแจ้งไปแล้วในรอบนี้ (เขียนก้อนใหม่ทับ → departed_alerted ของ watcher หายเอง)
        vehicles_col.update_one(
            {"_id": vehicle["_id"]},
            {"$set": {"last_detection": {
                "camera_name": event.camera_name or "",
                "latitude": det_lat,
                "longitude": det_lon,
                "at": now,
                "notified": already_notified or should_notify,
            }}},
        )
        refreshed += 1

        if not should_notify:
            continue

        # การตรวจเจอป้าย = "รถถูกตรวจจับ" เสมอ (ไม่ใช่การเคลื่อนย้าย) → PLATE_DETECTED
        # แม้รถจะอยู่สถานะ locked ก็ตาม — ส่วนแจ้งเตือน "เคลื่อนย้ายโดยไม่ได้รับอนุญาต"
        # (UNAUTHORIZED_MOVE) อยู่ที่ background departure watcher / geofence แยกต่างหาก
        alert_type = "PLATE_DETECTED"
        db["notifications"].insert_one({
            "user_id": vehicle["user_id"],
            "alert_type": alert_type,
            "snapshot_url": event.snapshot_url or "",
            "license_plate": plate,
            "camera_name": event.camera_name or "",
            "created_at": now,
            "read": False,
        })
        _push_to_user(
            vehicle["user_id"],
            "License Plate Detected",
            plate + (f" @ {event.camera_name}" if event.camera_name else ""),
            data={"alert_type": alert_type, "license_plate": plate,
                  "camera_name": event.camera_name or ""},
        )
        notified += 1
    return {"ok": True, "notified": notified, "refreshed": refreshed}


class VehicleExitEvent(BaseModel):
    vehicle_id: str
    camera_id: str
    latitude: float
    longitude: float
    snapshot_url: str | None = None


@app.post("/internal/vehicle-exit-event")
def report_vehicle_exit_event(
    event: VehicleExitEvent,
    _: None = Depends(require_internal_secret),
):
    """Called by the camera detection system whenever it reports where it saw
    a vehicle. If that position is farther from the camera than the
    vehicle's geofence_radius_m, the vehicle has left the camera's range —
    the owner is notified. The alert is more urgent (UNAUTHORIZED_MOVE)
    if the owner hasn't unlocked the vehicle first, otherwise it's a
    routine MOVED alert."""
    try:
        vehicle_id = ObjectId(event.vehicle_id)
        camera_id = ObjectId(event.camera_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid vehicle or camera id")

    vehicle = vehicles_col.find_one({"_id": vehicle_id})
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    camera = cameras_col.find_one({"_id": camera_id})
    if not camera:
        raise HTTPException(status_code=404, detail="Camera not found")

    distance_m = _haversine_m(
        event.latitude, event.longitude, camera["latitude"], camera["longitude"]
    )
    radius_m = vehicle.get("geofence_radius_m", 50)
    if distance_m <= radius_m:
        return {
            "ok": True,
            "notified": False,
            "reason": "Vehicle is still within camera range",
            "distance_m": round(distance_m, 1),
        }

    alert_type = "UNAUTHORIZED_MOVE" if vehicle.get("locked", False) else "MOVED"
    notification = {
        "user_id": vehicle["user_id"],
        "alert_type": alert_type,
        "snapshot_url": event.snapshot_url or "",
        "created_at": datetime.now(timezone.utc),
        "read": False,
    }
    result = db["notifications"].insert_one(notification)
    return {
        "ok": True,
        "notified": True,
        "alert_type": alert_type,
        "distance_m": round(distance_m, 1),
        "notification_id": str(result.inserted_id),
    }


@app.get("/vehicles/{vehicle_id}/history")
def get_vehicle_history(vehicle_id: str, current_user: dict = Depends(get_current_user)):
    try:
        object_id = ObjectId(vehicle_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid vehicle id")

    vehicle = vehicles_col.find_one(
        {"_id": object_id, "user_id": current_user["sub"]}
    )
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    history_col = db["history"]
    docs = history_col.find(
        {"vehicle_id": vehicle_id},
        sort=[("start_time", 1)],
    )
    return [
        {
            "id": str(doc["_id"]),
            "start_time": doc["start_time"].isoformat() + "Z",
            "end_time": doc["end_time"].isoformat() + "Z",
            "waypoints": doc.get("waypoints", []),
        }
        for doc in docs
    ]


@app.get("/health")
def health():
    return {"status": "ok"}
