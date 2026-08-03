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
import hashlib
import hmac
import json
import math
import random
# import smtplib
import requests
import secrets

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

EMAIL_PROVIDER = os.getenv("EMAIL_PROVIDER", "resend").strip().lower()
RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
EMAIL_FROM = os.getenv("EMAIL_FROM", "")  # เช่น "MFU Tracker <no-reply@yourdomain.com>"

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
    if EMAIL_PROVIDER != "resend":
        raise HTTPException(status_code=500, detail="Unsupported email provider")

    if not RESEND_API_KEY or not EMAIL_FROM:
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

    try:
        res = requests.post(
            "https://api.resend.com/emails",
            headers={
                "Authorization": f"Bearer {RESEND_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "from": EMAIL_FROM,
                "to": [to_email],
                "subject": subject,
                "text": text_body,
                "html": html_body,
            },
            timeout=10,
        )
        if res.status_code >= 300:
            raise HTTPException(
                status_code=500,
                detail="Unable to send OTP email. Please try again later.",
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


@app.get("/notifications")
def get_notifications(current_user: dict = Depends(get_current_user)):
    alerts_col = db["notifications"]
    docs = alerts_col.find(
        {"user_id": current_user["sub"]},
        sort=[("created_at", -1)],
        limit=50,
    )
    results = []
    for doc in docs:
        results.append({
            "id": str(doc["_id"]),
            "alert_type": doc.get("alert_type", "INFO"),
            "snapshot_url": doc.get("snapshot_url", ""),
            "created_at": doc["created_at"].isoformat() + "Z",
            "read": doc.get("read", False),
        })
    return results


@app.patch("/notifications/{notification_id}/read")
def mark_read(notification_id: str, current_user: dict = Depends(get_current_user)):
    from bson import ObjectId
    alerts_col = db["notifications"]
    result = alerts_col.update_one(
        {"_id": ObjectId(notification_id), "user_id": current_user["sub"]},
        {"$set": {"read": True}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"ok": True}


@app.get("/cameras")
def get_cameras(current_user: dict = Depends(get_current_user)):
    docs = cameras_col.find(sort=[("created_at", 1)])
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
    docs = cameras_col.find(sort=[("created_at", 1)])
    return [_camera_to_admin_dict(doc) for doc in docs]


@app.post("/admin/cameras")
def admin_create_camera(req: CameraCreate, current_user: dict = Depends(require_admin)):
    now = datetime.now(timezone.utc)
    doc = {
        "name": req.name.strip() or "Camera",
        "location_name": req.location_name.strip(),
        "latitude": req.latitude,
        "longitude": req.longitude,
        "rtsp_url": req.rtsp_url.strip(),
        "status": "active",
        "detection_zones": [],
        "created_at": now,
        "updated_at": now,
    }
    result = cameras_col.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _camera_to_admin_dict(doc)


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
        "images": {slot: images.get(slot, "") for slot in IMAGE_SLOTS}
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


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    speed: float | None = None
    accuracy: float | None = None


@app.post("/vehicles/{vehicle_id}/location")
def update_location(
    vehicle_id: str,
    req: LocationUpdate,
    current_user: dict = Depends(get_current_user),
):
    from bson import ObjectId

    vehicle = vehicles_col.find_one(
        {"_id": ObjectId(vehicle_id), "user_id": current_user["sub"]}
    )
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    location = {
        "vehicle_id": vehicle_id,
        "user_id": current_user["sub"],
        "latitude": req.latitude,
        "longitude": req.longitude,
        "speed": req.speed,
        "accuracy": req.accuracy,
        "created_at": datetime.now(timezone.utc),
    }
    db["locations"].insert_one(location)
    vehicles_col.update_one(
        {"_id": ObjectId(vehicle_id)},
        {"$set": {"last_location": location}},
    )
    return {"ok": True}


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
