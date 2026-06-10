# Vehicle Self-Tracking App — Simple System Design
**MFU Senior Project | E1 Parking Lot**

---

## What This System Does

A user registers their vehicle (photos + licence plate) in a Flutter app.
A CCTV camera watches the parking lot. An AI script detects the vehicle,
saves its location to a database, and sends a phone notification if it moves.
The user can see their vehicle's location on Google Maps.

That's it.

---

## Architecture

```
Flutter App  ──────────────────────────────────► FastAPI  ◄──── AI Worker
   (phone)        REST API + FCM notification    (Python)        (Python)
                                                     │
                                                  MongoDB
```

Three programs. One database. No extras.

---

## Tech Stack

| What | Tool |
|---|---|
| Mobile App | Flutter |
| Backend API | FastAPI (Python) |
| Database | MongoDB Atlas (collections)| // รูปภาพเก็บเป็น url ของ cloudianry  
| Image Storage | Cloudinary (รูปภาพจริง, ฟรี 25 GB) |
| AI Detection | YOLOv11 + PaddleOCR |
| Object Tracking | supervision (ByteTrack) |
| Push Notification | Firebase FCM |
| Maps | flutter_map + OpenStreetMap |

---

# Explain
Yolov11 ตรวจจับรถ,ป้าย จับเป็นกล่องเหลี่ยมๆรอบๆรถกับป้าย แยกกันกล่องใครกล่องมัน ใช้ dataset เทรนรอบรถ 4 มุม กับ dataset ป้าย ส่วน test ใช้ภาพจากฟูตเทจจริง
OpenCV-kMeans ใช้แตกสีรถออกมา เช่น "black", "red"
Bytetrack ใช้จับการเคลื่อนที่ของรถจากเฟรมข้ามเฟรม
Paddle OCR ใช้อ่านป้ายทะเบียนเป็นตัวอักษร รองรับป้ายทะเบียนไทย 
Flutter_map แสดงแผนที่ในแอป Flutter
OpenStreetMap แสดงข้อมูลแผนที่ เช่น ชื่อถนน, ชื่ออาคาร, ชื่อซอย.....
Firebase FCM ส่งแจ้งเตือนไปมือถือ
cloudinary เก็บรูปภาพ snap shot
## Folder Structure

```
project/
├── frontend/         ← Flutter mobile app
├── backend/          ← FastAPI server
    ├── db/        ← database
|       ├── database.py          
|   |── api/        ← api
|       ├── api.py          
|   ├── ai_worker/        ← AI detection script
|       ├── main.py       
|       ├── detector.py   ← YOLOv11 + ByteTrack + PaddleOCR
|       ├── tracker.py    ← stationary state machine
|       ├── Dockerfile
|       └── requirements.txt
    ├── cctv/       ← camera script
|        ├── seed_camera.py   ← run once to insert camera into DB 
|   |── Dockerfile
│   └── requirements.txt
├── docker-compose.yml
└── .env
```

---

## 1. Database — 6 Collections

Matching the ER diagram exactly. Every field, every type.

---

### users
```js
{
  "_id":                     ObjectId,
  "email":                   String,   // MFU email, unique
  "display_name":            String,
  "fcm_token":               String,   // updated every app open
  "oauth_provider":          String,   // always "lamduan"
  "detection_threshold_min": Number,   // default 2, user can change
  "created_at":              Date
}
```

---

### cctv_cameras
One document per physical CCTV camera. Insert with `seed_camera.py` before running.

```js
{
  "_id":               ObjectId,
  "camera_name":       String,   // e.g. "E1-Parking-01"
  "location": {                  // GeoJSON Point — where the camera is physically
    "type":        "Point",
    "coordinates": [Number, Number]   // [longitude, latitude]
  },
  "coverage_area":     String,   // e.g. "E1 Parking Lot rows A-C"
  "is_active":         Boolean,
  "detection_range_m": Number    // how far (metres) the camera can reliably detect
}
```

---

### vehicles
```js
{
  "_id":                ObjectId,
  "user_id":            ObjectId,   // ref → users._id
  "license_plate":      String,     // e.g. "กข1234"
  "model":              String,
  "color":              String,
  "photos": {                       // embedded subdocument { }
    "front_url":  String,
    "back_url":   String,
    "left_url":   String,
    "right_url":  String,
    "plate_url":  String,
  },
  "last_known_status":   String,    // "parked" | "moving" | "unknown"
  "last_seen_camera_id": ObjectId,  // ref → cctv_cameras._id
  "last_seen_at":        Date,
  "geofence_radius_m":   Number,    // default 5 — user can change per vehicle
  "last_location": {                // convenience field for Flutter map
    "lat": Number,
    "lng": Number
  },
  "created_at":          Date
}
```

---

### tracking_logs
One entry when a vehicle is confirmed parked, then one more every 10 minutes while
it stays parked. Used to build route_history waypoints.

```js
{
  "_id":                   ObjectId,
  "vehicle_id":            ObjectId,   // ref → vehicles._id
  "camera_id":             ObjectId,   // ref → cctv_cameras._id
  "track_id":              String,     // ByteTrack assigned ID
  "confidence_score":      Number,     // YOLOv11 confidence [0.0–1.0]
  "location": {                        // GeoJSON Point
    "type":        "Point",
    "coordinates": [Number, Number]    // [longitude, latitude]
  },
  "movement_delta":        Number,     // metres moved since previous log entry
  "timestamp":             Date,
  "detection_duration_min": Number     // minutes vehicle was stationary before this log
}
```

---

### alert_history
```js
{
  "_id":                 ObjectId,
  "vehicle_id":          ObjectId,   // ref → vehicles._id
  "alert_type":          String,     // "MOVED" | "LOST"
  "snapshot_url":        String,     // CCTV frame at moment of alert
  "triggered_location": {            // GeoJSON Point
    "type":        "Point",
    "coordinates": [Number, Number]  // [longitude, latitude]
  },
  "created_at":          Date
}
```

---

### route_history
Built from tracking_logs entries when a vehicle alerts (moved or lost).

```js
{
  "_id":        ObjectId,
  "vehicle_id": ObjectId,   // ref → vehicles._id
  "start_time": Date,       // timestamp of first tracking_log in this trip
  "end_time":   Date,       // timestamp when alert fired
  "waypoints": [            // array of embedded subdocuments [ ]
    {
      "location": {         // GeoJSON Point
        "type":        "Point",
        "coordinates": [Number, Number]  // [lng, lat]
      },
      "camera_id": ObjectId,            // which camera saw the vehicle here
      "ts":        Date                 // timestamp of this waypoint
    }
  ],
  "created_at": Date
}
```

---

## 2. Seed the Camera (Run Once)

Before starting the backend or AI worker, insert the E1 camera into MongoDB.
This gives you the `camera_id` that tracking_logs and the AI worker will reference.

```python
# backend/at_worker/cctv/seed_camera.py
# Run: python seed_camera.py
import asyncio
from motor.motor_asyncio import AsyncIOMotorClient

async def seed():
    client = AsyncIOMotorClient("mongodb://localhost:27017")
    db = client.mfu-vehicle-tracking

    # Replace coordinates with the real GPS of the E1 camera
    camera = {
        "camera_name":       "E1-Parking-01",
        "location": {
            "type":        "Point",
            "coordinates": [99.0490, 18.9143]   # [lng, lat] of the camera
        },
        "coverage_area":     "E1 Parking Lot",
        "is_active":         True,
        "detection_range_m": 30
    }
    result = await db.cctv_cameras.insert_one(camera)
    print(f"Camera inserted. Add this to your .env:")
    print(f"CAMERA_ID={result.inserted_id}")

asyncio.run(seed())
```

Then copy the printed `CAMERA_ID` value into `.env`.

---

## 3. Backend (FastAPI)

```python
# backend/api/api.py
from fastapi import FastAPI, Header, HTTPException, Depends
from motor.motor_asyncio import AsyncIOMotorClient
from bson import ObjectId
from datetime import datetime
from jose import jwt
import httpx, os, firebase_admin
from firebase_admin import messaging, credentials

app = FastAPI()

# MongoDB
client = AsyncIOMotorClient(os.environ["MONGODB_URL"])
db     = client.mfu-vehicle-tracking

# Firebase
cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)

JWT_SECRET      = os.environ["JWT_SECRET"]
INTERNAL_SECRET = os.environ["INTERNAL_SECRET"]

def get_user_id(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401)
    token = authorization.replace("Bearer ", "")
    data  = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    return data["user_id"]
```

### All Endpoints

**Auth**
```
POST /auth/login
  body:    { code: string }
  returns: { token: string }
```

**Vehicles (CRUD)**
```
GET    /vehicles
POST   /vehicles
PATCH  /vehicles/{id}
DELETE /vehicles/{id}
```

**Tracking**
```
GET /vehicles/{id}/location         ← current GPS (from last_location on vehicle doc)
GET /vehicles/{id}/routes           ← list of route_history records
GET /vehicles/{id}/routes/{rid}     ← one route with waypoints for polyline
```

**Alerts**
```
GET /alerts                               ← my alerts, newest first
```

**Cameras**
```
GET /cameras                        ← list all active cameras (Flutter may display these)
```

**Internal — AI Worker only (protected by X-Secret header)**
```
POST /internal/parked               ← vehicle confirmed parked
POST /internal/heartbeat            ← vehicle still parked, 10-min save
POST /internal/alert                ← vehicle moved or disappeared
GET  /internal/vehicle-by-plate/{plate}   ← look up vehicle_id by licence plate
```

**Settings**
```
PATCH /users/me
  body: { fcm_token, detection_threshold_min }
```

---

### Key Endpoint Implementations

```python
# ── AUTH ──────────────────────────────────────────────────────────────────────
@app.post("/auth/login")
async def login(body: dict):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://lamduan.mfu.ac.th/oauth/token",
            data={"grant_type":    "authorization_code",
                  "code":          body["code"],
                  "client_id":     os.environ["LAMDUAN_CLIENT_ID"],
                  "client_secret": os.environ["LAMDUAN_CLIENT_SECRET"],
                  "redirect_uri":  "mfutrack://callback"}
        )
    data  = resp.json()
    email = data["email"]
    name  = data.get("name", email)

    await db.users.update_one(
        {"email": email},
        {"$set":       {"display_name": name, "oauth_provider": "lamduan"},
         "$setOnInsert": {"detection_threshold_min": 2,
                          "created_at": datetime.utcnow()}},
        upsert=True
    )
    user  = await db.users.find_one({"email": email})
    token = jwt.encode({"user_id": str(user["_id"]), "email": email},
                       JWT_SECRET, algorithm="HS256")
    return {"token": token}


# ── INTERNAL: look up vehicle_id by licence plate ────────────────────────────
@app.get("/internal/vehicle-by-plate/{plate}")
async def vehicle_by_plate(plate: str, x_secret: str = Header(None)):
    if x_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403)
    v = await db.vehicles.find_one({"license_plate": plate})
    if not v:
        raise HTTPException(status_code=404)
    return {
        "vehicle_id":          str(v["_id"]),
        "geofence_radius_m":   v.get("geofence_radius_m", 5),
        "color":               v.get("color", "")
    }


# ── INTERNAL: vehicle confirmed parked ───────────────────────────────────────
@app.post("/internal/parked")
async def vehicle_parked(payload: dict, x_secret: str = Header(None)):
    if x_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403)

    vehicle_id = payload["vehicle_id"]
    camera_id  = payload["camera_id"]
    lng, lat   = payload["lng"], payload["lat"]

    location_geojson = {"type": "Point", "coordinates": [lng, lat]}

    # Save tracking_log entry (matches ER diagram exactly)
    await db.tracking_logs.insert_one({
        "vehicle_id":              ObjectId(vehicle_id),
        "camera_id":               ObjectId(camera_id),
        "track_id":                payload["track_id"],
        "confidence_score":        payload["confidence_score"],
        "location":                location_geojson,
        "movement_delta":          0.0,   # just parked — no movement
        "timestamp":               datetime.utcnow(),
        "detection_duration_min":  payload["detection_duration_min"]
    })

    # Update vehicle's status and last known info
    await db.vehicles.update_one(
        {"_id": ObjectId(vehicle_id)},
        {"$set": {
            "last_known_status":   "parked",
            "last_seen_camera_id": ObjectId(camera_id),
            "last_seen_at":        datetime.utcnow(),
            "last_location":       {"lat": lat, "lng": lng}
        }}
    )
    return {"ok": True}


# ── INTERNAL: vehicle still parked — 10-minute heartbeat ─────────────────────
@app.post("/internal/heartbeat")
async def vehicle_heartbeat(payload: dict, x_secret: str = Header(None)):
    if x_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403)

    lng, lat = payload["lng"], payload["lat"]
    location_geojson = {"type": "Point", "coordinates": [lng, lat]}

    await db.tracking_logs.insert_one({
        "vehicle_id":              ObjectId(payload["vehicle_id"]),
        "camera_id":               ObjectId(payload["camera_id"]),
        "track_id":                payload["track_id"],
        "confidence_score":        payload["confidence_score"],
        "location":                location_geojson,
        "movement_delta":          payload.get("movement_delta", 0.0),
        "timestamp":               datetime.utcnow(),
        "detection_duration_min":  payload["detection_duration_min"]
    })
    return {"ok": True}


# ── INTERNAL: vehicle moved or disappeared ────────────────────────────────────
@app.post("/internal/alert")
async def vehicle_alert(payload: dict, x_secret: str = Header(None)):
    if x_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403)

    vehicle_id = payload["vehicle_id"]
    camera_id  = payload["camera_id"]
    lng, lat   = payload["lng"], payload["lat"]

    triggered_location = {"type": "Point", "coordinates": [lng, lat]}

    # 1. Save alert_history (matches ER diagram)
    await db.alert_history.insert_one({
        "vehicle_id":          ObjectId(vehicle_id),
        "alert_type":          payload["alert_type"],   # "MOVED" | "LOST"
        "snapshot_url":        payload.get("snapshot_url", ""),
        "triggered_location":  triggered_location,
        "created_at":          datetime.utcnow()
    })

    # 2. Update vehicle status
    await db.vehicles.update_one(
        {"_id": ObjectId(vehicle_id)},
        {"$set": {
            "last_known_status":   "unknown",
            "last_seen_camera_id": ObjectId(camera_id),
            "last_seen_at":        datetime.utcnow(),
            "last_location":       {"lat": lat, "lng": lng}
        }}
    )

    # 3. Bundle tracking_logs into route_history
    logs = await db.tracking_logs.find(
        {"vehicle_id": ObjectId(vehicle_id)}
    ).sort("timestamp", 1).to_list(length=500)

    if len(logs) >= 2:
        waypoints = [
            {
                "location":  log["location"],            # already GeoJSON
                "camera_id": log["camera_id"],
                "ts":        log["timestamp"]
            }
            for log in logs
        ]
        await db.route_history.insert_one({
            "vehicle_id": ObjectId(vehicle_id),
            "start_time": logs[0]["timestamp"],
            "end_time":   logs[-1]["timestamp"],
            "waypoints":  waypoints,
            "created_at": datetime.utcnow()
        })
        # Clear used tracking_logs for this vehicle
        await db.tracking_logs.delete_many({"vehicle_id": ObjectId(vehicle_id)})

    # 4. Send FCM push notification
    vehicle = await db.vehicles.find_one({"_id": ObjectId(vehicle_id)})
    owner   = await db.users.find_one({"_id": vehicle["user_id"]})
    if owner and owner.get("fcm_token"):
        body = ("Your vehicle may have moved!"
                if payload["alert_type"] == "MOVED"
                else "Your vehicle disappeared from camera view.")
        messaging.send(messaging.Message(
            notification=messaging.Notification(title="Vehicle Alert", body=body),
            token=owner["fcm_token"]
        ))

    return {"ok": True}


# ── GET current location ──────────────────────────────────────────────────────
@app.get("/vehicles/{vehicle_id}/location")
async def get_location(vehicle_id: str, user_id: str = Depends(get_user_id)):
    v = await db.vehicles.find_one({
        "_id":     ObjectId(vehicle_id),
        "user_id": ObjectId(user_id)
    })
    if not v:
        raise HTTPException(status_code=404)
    return v["last_location"]   # { lat, lng } — Flutter uses this directly


# ── GET route history list ────────────────────────────────────────────────────
@app.get("/vehicles/{vehicle_id}/routes")
async def get_routes(vehicle_id: str, user_id: str = Depends(get_user_id)):
    routes = await db.route_history.find(
        {"vehicle_id": ObjectId(vehicle_id)}
    ).sort("start_time", -1).to_list(length=50)
    result = []
    for r in routes:
        result.append({
            "id":         str(r["_id"]),
            "start_time": r["start_time"].isoformat(),
            "end_time":   r["end_time"].isoformat()
        })
    return result


# ── GET one route with waypoints (for polyline) ───────────────────────────────
@app.get("/vehicles/{vehicle_id}/routes/{route_id}")
async def get_route(vehicle_id: str, route_id: str,
                    user_id: str = Depends(get_user_id)):
    r = await db.route_history.find_one({"_id": ObjectId(route_id)})
    if not r:
        raise HTTPException(status_code=404)
    # Convert GeoJSON waypoints → {lat, lng} for Flutter
    waypoints = [
        {
            "lat":  w["location"]["coordinates"][1],
            "lng":  w["location"]["coordinates"][0],
            "time": w["ts"].isoformat()
        }
        for w in r["waypoints"]
    ]
    return {"waypoints": waypoints,
            "start_time": r["start_time"].isoformat(),
            "end_time":   r["end_time"].isoformat()}


# ── GET cameras list ──────────────────────────────────────────────────────────
@app.get("/cameras")
async def list_cameras():
    cameras = await db.cctv_cameras.find({"is_active": True}).to_list(length=20)
    for c in cameras:
        c["_id"] = str(c["_id"])
    return cameras


# ── GET alerts ────────────────────────────────────────────────────────────────
@app.get("/alerts")
async def get_alerts(user_id: str = Depends(get_user_id)):
    # Find all vehicles owned by the user first
    vehicles = await db.vehicles.find(
        {"user_id": ObjectId(user_id)}
    ).to_list(length=100)
    vehicle_ids = [v["_id"] for v in vehicles]

    alerts = await db.alert_history.find(
        {"vehicle_id": {"$in": vehicle_ids}}
    ).sort("created_at", -1).to_list(length=50)

    result = []
    for a in alerts:
        result.append({
            "id":           str(a["_id"]),
            "vehicle_id":   str(a["vehicle_id"]),
            "alert_type":   a["alert_type"],
            "lat":          a["triggered_location"]["coordinates"][1],
            "lng":          a["triggered_location"]["coordinates"][0],
            "snapshot_url": a.get("snapshot_url", ""),
            "created_at":   a["created_at"].isoformat()
        })
    return result


# ── PATCH user settings ───────────────────────────────────────────────────────
@app.patch("/users/me")
async def update_settings(body: dict, user_id: str = Depends(get_user_id)):
    update = {}
    if "fcm_token" in body:
        update["fcm_token"] = body["fcm_token"]
    if "detection_threshold_min" in body:
        update["detection_threshold_min"] = body["detection_threshold_min"]
    await db.users.update_one({"_id": ObjectId(user_id)}, {"$set": update})
    return {"ok": True}
```

---

## 4. AI Worker

### How It Works
```
Every 0.5s (2 fps):
  read frame → brightness check → YOLOv11 → ByteTrack → PaddleOCR
  → for each tracked vehicle:
      update state machine
      "PARKED"    → POST /internal/parked    (first confirmed park)
      "HEARTBEAT" → POST /internal/heartbeat (every 10 min while parked)
      "MOVED"     → POST /internal/alert     (geofence breach)
      "LOST"      → POST /internal/alert     (disappeared from camera)
```

---

### detector.py — YOLOv11 + ByteTrack + PaddleOCR

```python
# ai_worker/detector.py
from ultralytics import YOLO
from supervision import ByteTrack, Detections
from paddleocr import PaddleOCR
import cv2, numpy as np

model   = YOLO("yolov11s_mfu.pt")
tracker = ByteTrack(track_thresh=0.25, track_buffer=30, match_thresh=0.8)
ocr     = PaddleOCR(lang="th", use_gpu=True, show_log=False)

PLATE_CLASS = "license_plate"

# HSV color buckets — covers common Thai motorcycle colors
_HSV_BUCKETS = [
    ("black",  lambda h, s, v: v < 60),
    ("white",  lambda h, s, v: v > 180 and s < 40),
    ("silver", lambda h, s, v: v > 120 and s < 60),
    ("red",    lambda h, s, v: s > 80 and (h < 15 or h > 165)),
    ("blue",   lambda h, s, v: s > 80 and 95 < h < 135),
    ("green",  lambda h, s, v: s > 80 and 35 < h < 95),
    ("yellow", lambda h, s, v: s > 80 and 15 <= h <= 35),
]


def detect_and_track(frame: np.ndarray) -> list[dict]:
    """
    Runs YOLOv11 → ByteTrack → PaddleOCR on one frame.
    Returns list of dicts with track_id, centroid, confidence, plate_text, detected_color.
    Classes: 0=motorcycle, 1=license_plate
    """
    results = model.predict(frame, imgsz=640, conf=0.55, verbose=False)

    moto_bboxes, moto_confs = [], []
    plate_boxes = []

    for box in results[0].boxes:
        cls_name = model.names[int(box.cls)]
        bbox     = box.xyxy[0].tolist()
        if cls_name == "motorcycle":
            moto_bboxes.append(bbox)
            moto_confs.append(float(box.conf))
        elif cls_name == PLATE_CLASS:
            plate_boxes.append(bbox)

    if not moto_bboxes:
        return []

    # ByteTrack assigns persistent track_ids across frames
    sv      = Detections(xyxy=np.array(moto_bboxes), confidence=np.array(moto_confs))
    tracked = tracker.update_with_detections(sv)

    vehicles = []
    for i, track_id in enumerate(tracked.tracker_id):
        x1, y1, x2, y2 = map(int, tracked.xyxy[i])
        cx, cy          = (x1 + x2) // 2, (y1 + y2) // 2

        plate_crop = _find_plate_crop(frame, x1, y1, x2, y2, plate_boxes)
        plate_text = _read_plate(plate_crop) if plate_crop is not None else "UNKNOWN"

        vehicles.append({
            "track_id":       int(track_id),
            "centroid":       (cx, cy),
            "confidence":     float(tracked.confidence[i]),
            "plate_text":     plate_text or "UNKNOWN",
            "detected_color": _extract_color(frame[y1:y2, x1:x2])
        })
    return vehicles


def _find_plate_crop(frame: np.ndarray,
                     vx1: int, vy1: int, vx2: int, vy2: int,
                     plate_boxes: list) -> np.ndarray | None:
    """Return the crop of the plate bbox whose centre falls inside the motorcycle bbox."""
    for px1, py1, px2, py2 in plate_boxes:
        px1, py1, px2, py2 = int(px1), int(py1), int(px2), int(py2)
        pcx, pcy = (px1 + px2) // 2, (py1 + py2) // 2
        if vx1 <= pcx <= vx2 and vy1 <= pcy <= vy2:
            return frame[py1:py2, px1:px2]
    return None


def _read_plate(crop: np.ndarray) -> str | None:
    if crop is None or crop.size == 0:
        return None
    results = ocr.ocr(crop, cls=False)
    if not results or not results[0]:
        return None
    best = max(results[0], key=lambda r: r[1][1])
    text, conf = best[1]
    return text.replace(" ", "").upper() if conf >= 0.6 else None


def _extract_color(crop: np.ndarray) -> str:
    """Returns dominant color of the motorcycle body via K-means on HSV."""
    if crop is None or crop.size == 0:
        return "unknown"
    h, w = crop.shape[:2]
    if h < 10 or w < 10:
        return "unknown"
    resized = cv2.resize(crop, (32, 32))
    hsv     = cv2.cvtColor(resized, cv2.COLOR_BGR2HSV)
    pixels  = hsv.reshape(-1, 3).astype(np.float32)
    _, labels, centers = cv2.kmeans(
        pixels, 3, None,
        (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0),
        3, cv2.KMEANS_RANDOM_CENTERS
    )
    dominant = centers[np.bincount(labels.flatten()).argmax()]
    h_val, s_val, v_val = int(dominant[0]), int(dominant[1]), int(dominant[2])
    for name, check in _HSV_BUCKETS:
        if check(h_val, s_val, v_val):
            return name
    return "other"
```

---

### tracker.py — Stationary State Machine

```python
# ai_worker/tracker.py
import time

STILL_THRESHOLD_DEG = 0.00005   # ~5 m in degree units (fine for E1 parking lot)
HEARTBEAT_SEC       = 600        # 10 minutes — "save data every 10 min" requirement

class StationaryTracker:

    def __init__(self, threshold_minutes: float = 2.0):
        self.threshold_sec = threshold_minutes * 60
        self.tracks = {}

    def update(self, track_id: int, plate: str,
               lat: float, lng: float) -> tuple[str | None, dict]:
        """
        Returns (event, extra_data).
        event = "PARKED" | "HEARTBEAT" | "MOVED" | None
        extra_data = { detection_duration_min, movement_delta_deg }
        """
        now = time.time()

        if track_id not in self.tracks:
            self.tracks[track_id] = {
                "plate":           plate,
                "lat":             lat,
                "lng":             lng,
                "still_since":     now,
                "last_heartbeat":  now,
                "state":           "moving",
                "parked_lat":      None,
                "parked_lng":      None,
                "still_start_lat": lat,
                "still_start_lng": lng,
            }
            return None, {}

        t    = self.tracks[track_id]
        dist = ((lat - t["lat"])**2 + (lng - t["lng"])**2) ** 0.5

        extra = {
            "detection_duration_min": (now - t["still_since"]) / 60,
            "movement_delta_deg":     dist
        }

        if dist > STILL_THRESHOLD_DEG:
            # Vehicle moved this frame
            t["lat"], t["lng"] = lat, lng
            t["still_since"]   = now

            if t["state"] == "parked":
                t["state"] = "moving"
                return "MOVED", extra
        else:
            # Vehicle is still
            still_duration = now - t["still_since"]

            if t["state"] == "moving" and still_duration >= self.threshold_sec:
                t["state"]          = "parked"
                t["parked_lat"]     = lat
                t["parked_lng"]     = lng
                t["last_heartbeat"] = now
                return "PARKED", extra

            if t["state"] == "parked" and (now - t["last_heartbeat"]) >= HEARTBEAT_SEC:
                t["last_heartbeat"] = now
                return "HEARTBEAT", extra

        return None, {}
```

---

### main.py — The Main Loop

```python
# ai_worker/main.py
import cv2, time, requests, os, glob
import numpy as np, cv2 as _cv2
from detector import detect_and_track
from tracker  import StationaryTracker

def get_video_sources() -> list[str]:
    src = os.environ.get("VIDEO_SOURCE")
    if not src:
        return [os.environ["CAMERA_RTSP_URL"]]   # live RTSP
    if os.path.isdir(src):
        files = sorted(glob.glob(os.path.join(src, "*.mp4")))
        return files if files else [os.environ["CAMERA_RTSP_URL"]]
    return [src]   # single file
CAMERA_ID        = os.environ["CAMERA_ID"]          # ObjectId from seed_camera.py
BACKEND          = os.environ.get("BACKEND_URL", "http://localhost:8000")
INTERNAL_SECRET  = os.environ["INTERNAL_SECRET"]
HEADERS          = {"X-Secret": INTERNAL_SECRET}

# ── Homography: pixel → GPS ───────────────────────────────────────────────────
# Visit E1, record GPS coordinates of 4 easily-identifiable points
# (e.g. parking bay corners), then find their pixel coords in a calibration frame.
PIXEL_PTS = np.float32([[120,300],[450,300],[450,500],[120,500]])   # replace with real values
GPS_PTS   = np.float32([[18.9142,99.0489],[18.9145,99.0489],        # replace with real values
                         [18.9145,99.0492],[18.9142,99.0492]])
H, _ = _cv2.findHomography(PIXEL_PTS, GPS_PTS)

def pixel_to_gps(cx: float, cy: float) -> tuple[float, float]:
    pt  = np.float32([[[cx, cy]]])
    out = _cv2.perspectiveTransform(pt, H)[0][0]
    return float(out[0]), float(out[1])   # lat, lng

# ── Plate → vehicle info cache ────────────────────────────────────────────────
plate_cache: dict[str, dict] = {}   # plate → { vehicle_id, geofence_radius_m, color }

def find_vehicle(plate: str) -> dict | None:
    if plate in plate_cache:
        return plate_cache[plate]
    r = requests.get(f"{BACKEND}/internal/vehicle-by-plate/{plate}",
                     headers=HEADERS)
    if r.status_code == 200:
        plate_cache[plate] = r.json()
        return plate_cache[plate]
    return None

# ── Color verification gate ───────────────────────────────────────────────────
COLOR_GROUPS = {
    "black": "dark",   "charcoal": "dark",
    "white": "light",  "silver":   "light",  "grey": "light", "gray": "light",
    "red":   "red",    "maroon":   "red",     "orange": "red",
    "blue":  "blue",   "navy":     "blue",    "teal":   "blue",
    "green": "green",
    "yellow": "yellow",
}

def colors_match(detected: str, registered: str) -> bool:
    """Returns True when colors are in the same group, or when either side is unknown."""
    if not detected or not registered:
        return True   # missing data — don't block
    g1 = COLOR_GROUPS.get(detected.lower())
    g2 = COLOR_GROUPS.get(registered.lower().split()[0])
    if g1 is None or g2 is None:
        return True   # unmappable color — don't block
    return g1 == g2

# ── Main loop ─────────────────────────────────────────────────────────────────
tracker = StationaryTracker(threshold_minutes=2)

for source in get_video_sources():
    print(f"AI Worker started | source={source} | camera={CAMERA_ID}")
    cap = cv2.VideoCapture(source)

    while True:
        ret, frame = cap.read()
        if not ret:
            if os.path.isfile(source):
                break          # video file ended → move to next file
            time.sleep(5)
            cap = cv2.VideoCapture(source)   # RTSP dropped → reconnect
            continue

        # Skip dark frames (night / rain / fog)
        if cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).mean() < 60:
            time.sleep(30)
            continue

        vehicles = detect_and_track(frame)

        for v in vehicles:
            lat, lng = pixel_to_gps(*v["centroid"])
            event, extra = tracker.update(v["track_id"], v["plate_text"], lat, lng)

            if event is None:
                continue

            vehicle_info = find_vehicle(v["plate_text"])
            if vehicle_info is None:
                continue   # unregistered vehicle — skip

            # Verification gate: detected color must match registered color before any alert
            if not colors_match(v.get("detected_color", ""), vehicle_info.get("color", "")):
                continue   # color mismatch — likely wrong vehicle, suppress alert

            vehicle_id = vehicle_info["vehicle_id"]

            # Base payload sent with every internal call
            base = {
                "vehicle_id":             vehicle_id,
                "camera_id":              CAMERA_ID,
                "track_id":               str(v["track_id"]),
                "confidence_score":       v["confidence"],
                "lat":                    lat,
                "lng":                    lng,
                "detection_duration_min": round(extra.get("detection_duration_min", 0), 2)
            }

            if event == "PARKED":
                requests.post(f"{BACKEND}/internal/parked",
                              json=base, headers=HEADERS)

            elif event == "HEARTBEAT":
                base["movement_delta"] = extra.get("movement_delta_deg", 0.0)
                requests.post(f"{BACKEND}/internal/heartbeat",
                              json=base, headers=HEADERS)

            elif event == "MOVED":
                requests.post(f"{BACKEND}/internal/alert",
                              json={**base, "alert_type": "MOVED"},
                              headers=HEADERS)

        time.sleep(0.5)   # 2 fps

    cap.release()
```

---_

## 5. Flutter App

*********
MCP ต่อกับ google stitch ให้อ่าน ux, ui โดยตรง
บอก ai ว่า "mcp stitch for me [วางลิ้ง mcp config]" กด enter ไปเรื่อยๆจนกว่าเสร็จ
ทดสอบว่า mcp ใช้ได้ไหม /mcp stitch test ถ้าใช้ไม่ได้ ปิด vscode เปิดใหม่
การใช้งาน /mcp stitch help เพื่อดูว่าจะใช้ฟังก์ชันไหน 

create_project	สร้างโปรเจกต์ใหม่สำหรับเก็บหน้าจอและงานออกแบบ
list_projects	ดูรายการโปรเจกต์ที่เป็นเจ้าของหรือถูกแชร์ให้
get_project	ดูรายละเอียดของโปรเจกต์ที่เลือก
generate_screen_from_text	สร้างหน้าจอ UI จากคำอธิบายข้อความ รองรับ Mobile, Desktop และ Tablet
get_screen	อ่านรายละเอียดของหน้าจอที่สร้างไว้
list_screens	แสดงรายการหน้าจอทั้งหมดในโปรเจกต์
edit_screens	แก้ไขหน้าจอที่มีอยู่ผ่านคำสั่งข้อความ
generate_variants	สร้างรูปแบบทางเลือกของหน้าจอ 1–5 แบบ (ปรับปรุง, สำรวจแนวทางใหม่, หรือออกแบบใหม่ทั้งหมด)

เช่น ถ้าอยากให้มันสร้างหน้า ui ก็ใช้ mcp stitch get_screen [หน้าที่ต้องการ]

### Screens

```
login_screen
  ├── JWT stored → home_screen
  └── no JWT     → oauth_screen (Lamduan WebView)
                       ↓
                   home_screen
                  /    |    \         \
     live_tracking  route_history  vehicle_profile  notifications
      _screen        _screen          _screen         _screen
                        ↓                
               route_detail_screen   
                                    
```

### pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8

  # Maps
  flutter_map: ^7.0.2
  flutter_osm_plugin: ^1.4.5 
  latlong2: ^0.9.1

  # Firebase
  firebase_core: ^3.13.1
  firebase_messaging: ^15.2.7

  # HTTP
  dio: ^5.8.0+1

  # Storage
  flutter_secure_storage: ^9.2.4

  # Camera / image
  image_picker: ^1.1.2

  # OAuth WebView
  flutter_inappwebview: ^6.1.5

  # State management
  provider: ^6.1.2

  # Fonts
  google_fonts: ^6.2.1
```

### Photo Upload — Cloudinary

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

Future<String> uploadToCloudinary(XFile file, String side) async {
  final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload');
  final req = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = cloudinaryUploadPreset
    ..fields['folder'] = 'vehicles'
    ..fields['public_id'] = '${vehicleId}_$side'
    ..files.add(await http.MultipartFile.fromPath('file', file.path));
  final res = await req.send();
  final body = jsonDecode(await res.stream.bytesToString());
  return body['secure_url'] as String;   // ← URL นี้ s
}

// ตอน POST /vehicles
Future<void> registerVehicle() async {
  final urls = await Future.wait([
    uploadToCloudinary(frontImg, 'front'),
    uploadToCloudinary(backImg,  'back'),
    uploadToCloudinary(leftImg,  'left'),
    uploadToCloudinary(rightImg, 'right'),
    uploadToCloudinary(plateImg, 'plate'),
  ]);

  await dio.post('/vehicles',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
    data: {
      'license_plate': plate,
      'model': model,
      'color': color,
      'photos': {
        'front_url': urls[0],
        'back_url':  urls[1],
        'left_url':  urls[2],
        'right_url': urls[3],
        'plate_url': urls[4],
      },
    },
  );
}
```

### FCM Setup — Flutter

```dart
// main.dart — เรียกตอน app เริ่ม
Future<void> initFCM() async {
  await FirebaseMessaging.instance.requestPermission();

  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await dio.patch('/users/me',
      options: Options(headers: {'Authorization': 'Be
      data: {'fcm_token': token},
    );
  }

  // แอปเปิดอยู่ (foreground)
  FirebaseMessaging.onMessage.listen((message) {
    // แสดง in-app banner หรือ navigate ไปหน้า notifica
  });

  // กด notification ขณะแอป background
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    // navigate ไปหน้า notifications
  });
}
```


### Map Screen — show vehicle pin

```dart
Future<void> loadVehicleLocation() async {
  final res = await dio.get('/vehicles/$vehicleId/location',
      options: Options(headers: {'Authorization': 'Bearer $token'}));
  setState(() {
    vehiclePoint = LatLng(res.data['lat'], res.data['lng']);
  });
}

Widget build(BuildContext context) {
  return FlutterMap(
    options: MapOptions(
      initialCenter: vehiclePoint ?? LatLng(18.9143, 99.0490),
      initialZoom: 18,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.mfu.vehicletracker',
      ),
      if (vehiclePoint != null)
        MarkerLayer(
          markers: [
            Marker(
              point: vehiclePoint!,
              child: const Icon(Icons.motorcycle, color: Colors.red, size: 36),
            ),
          ],
        ),
    ],
  );
}
```

### Route History Screen — A to B polyline

```dart
Future<void> loadRoute(String routeId) async {
  final res = await dio.get('/vehicles/$vehicleId/routes/$routeId',
      options: Options(headers: {'Authorization': 'Bearer $token'}));
  final List pts = res.data['waypoints'];
  setState(() {
    // Backend already converts GeoJSON → {lat, lng} so Flutter just uses it
    routePoints = pts.map((p) => LatLng(p['lat'], p['lng'])).toList();
  });
}

Widget build(BuildContext context) {
  return FlutterMap(
    options: MapOptions(
      initialCenter: routePoints.isNotEmpty ? routePoints.first : LatLng(18.9143, 99.0490),
      initialZoom: 18,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.mfu.vehicletracker',
      ),
      PolylineLayer(
        polylines: [
          Polyline(
            points: routePoints,
            color: Colors.blue,
            strokeWidth: 4,
          ),
        ],
      ),
      MarkerLayer(
        markers: [
          if (routePoints.isNotEmpty) ...[
            Marker(
              point: routePoints.first,
              child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
            ),
            Marker(
              point: routePoints.last,
              child: const Icon(Icons.location_on, color: Colors.red, size: 32),
            ),
          ]
        ],
      ),
    ],
  );
}
```

---

## 6. Build Order

1. **MongoDB + FastAPI + seed camera** — get all 6 collections and endpoints working.
   Test at `http://localhost:8000/docs`.

2. **Flutter basic screens** — OAuth login → vehicle list → add vehicle form.

3. **AI worker offline** — test on a saved `.mp4`, not live RTSP.
   Check detection, OCR, and state machine work before touching the camera.

4. **Connect AI → Backend** — fire `/internal/parked` and `/internal/alert`
   from a test video, verify tracking_logs and route_history are created.

5. **Map screen** — show the pin from `vehicles.last_location`.

6. **Route polyline** — draw from `route_history.waypoints`.

7. **Push notifications** — add FCM last, it's independent.

8. **Camera calibration** — visit E1, measure 4 GPS points,
   update `PIXEL_PTS` and `GPS_PTS` in `ai_worker/main.py`.

---

## 7. What Is Intentionally Skipped ***Optional***

| Skipped | Why it's fine |
|---|---|
| NGINX | Not needed until real server deployment |
| Celery + Redis | FastAPI handles FCM inline fine for this load |
| PKCE OAuth | Basic code exchange works for a senior project demo |

---

## .env File

```env
# MongoDB
MONGO_USER=66xxxxxx_db_user   # user ตัวเองใน Database Users ของตัวเอง ใน atlas
MONGO_PASSWORD=dawdawdawdawdad  # รหัสเอามาจาก Database users ของตัวเอง ใน atlas ถ้าไม่รู้ให้เจนรหัสใหม่
MONGO_NAME=vehicle-self-tracking
MONGODB_URL=mongodb+srv://66xxxxxx_db_user:dawdawdawdawdad@vehicle-self-tracking.axgoaf1.mongodb.net/

# App secrets
JWT_SECRET=any-random-string-here
INTERNAL_SECRET=another-random-string-here

# MFU OAuth
LAMDUAN_CLIENT_ID=your-mfu-oauth-client-id
LAMDUAN_CLIENT_SECRET=your-mfu-oauth-client-secret

# Camera
CAMERA_RTSP_URL=rtsp://username:password@camera-ip/stream
CAMERA_ID=paste-the-objectid-from-seed_camera.py-here
BACKEND_URL=http://localhost:8000
# VIDEO_SOURCE=footage.mp4   ← ใส่ตอน develop เพื่อใช้ไฟล์แทน RTSP, ลบออกตอน deploy จริง

# Cloudinary (รูปภาพ)
CLOUDINARY_URL=cloudinary://596868621737339:<xLufQYj-Go_Krta_I6Ady_WVpTU>@dbhgmwsfg
```

---

*All 6 collections. All endpoints. All proposal requirements. Matches ER diagram exactly.*
