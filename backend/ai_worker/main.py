# New code cloud treading

import os
import time
import json
import base64
import tempfile
import threading
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from datetime import datetime, timezone
from dotenv import load_dotenv
from inference_sdk import InferenceHTTPClient
from pymongo import MongoClient

import firebase_admin
from firebase_admin import credentials, messaging


_HERE = Path(__file__).parent

load_dotenv(_HERE / ".env")         # ai_worker/.env overrides

ROBOFLOW_API_KEY = os.environ["ROBOFLOW_API_KEY"]
WORKSPACE_NAME = os.environ["WORKSPACE_NAME"]
WORKFLOW_ID = os.environ["WORKFLOW_ID"]
RTSP_URL = os.environ["RTSP_URL"]

SAMPLE_SECONDS = float(os.environ["SAMPLE_SECONDS"])
PIXELS_PER_METER = float(os.environ["PIXELS_PER_METER"])
NEAR_DISTANCE_M = float(os.environ["NEAR_DISTANCE_M"])
ALERT_DISTANCE_M = float(os.environ["ALERT_DISTANCE_M"])
ALERT_COOLDOWN_SECONDS = float(os.environ["ALERT_COOLDOWN_SECONDS"])

PERSON_CONFIDENCE_MIN = float(os.environ["PERSON_CONFIDENCE_MIN"])
MOTORCYCLE_CONFIDENCE_MIN = float(os.environ["MOTORCYCLE_CONFIDENCE_MIN"])
NMS_IOU_THRESHOLD = float(os.environ["NMS_IOU_THRESHOLD"])



FIREBASE_SERVICE_ACCOUNT = os.environ["FIREBASE_SERVICE_ACCOUNT"]
FCM_DEVICE_TOKEN = os.environ["FCM_DEVICE_TOKEN"]

MONGODB_URL = os.environ["MONGODB_URL"]
MONGO_NAME = os.environ["MONGO_NAME"]


_mongo_collection = None

def get_notifications_collection():
    global _mongo_collection
    if _mongo_collection is None and MONGODB_URL:
        _mongo_collection = MongoClient(MONGODB_URL)[MONGO_NAME]["notifications"]
    return _mongo_collection

if not ROBOFLOW_API_KEY:
    raise RuntimeError("Missing ROBOFLOW_API_KEY in .env")

if not RTSP_URL:
    raise RuntimeError("Missing RTSP_URL in .env")


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


class SimpleTracker:
    """
    Lightweight tracker for sampled cloud frames.

    This is not ByteTrack. It just keeps stable-ish IDs between sampled frames
    based on nearest bbox center.
    """

    def __init__(self, max_distance_px: float = 160, ttl_seconds: float = 10):
        self.max_distance_px = max_distance_px
        self.ttl_seconds = ttl_seconds
        self.next_id = 1
        self.tracks: Dict[int, SimpleTrack] = {}

    def update(self, detections: List[dict]) -> List[SimpleTrack]:
        now = time.time()

        # Remove stale tracks.
        stale_ids = [
            tid for tid, t in self.tracks.items()
            if now - t.last_seen > self.ttl_seconds
        ]
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
                if track_id in assigned_track_ids:
                    continue

                if track.cls != cls:
                    continue

                dist = euclidean(center, track.center)

                if best_distance is None or dist < best_distance:
                    best_distance = dist
                    best_track_id = track_id

            if best_track_id is not None and best_distance is not None and best_distance <= self.max_distance_px:
                track = self.tracks[best_track_id]
                track.center = center
                track.bbox = det
                track.last_seen = now
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


tracker = SimpleTracker()


def init_firebase():
    global firebase_initialized

    if firebase_initialized:
        return

    if not FIREBASE_SERVICE_ACCOUNT:
        raise RuntimeError("Missing FIREBASE_SERVICE_ACCOUNT in .env")

    sa_path = Path(FIREBASE_SERVICE_ACCOUNT)
    if not sa_path.is_absolute():
        sa_path = (_HERE / sa_path).resolve()

    cred = credentials.Certificate(str(sa_path))
    firebase_admin.initialize_app(cred)
    firebase_initialized = True


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

    plate_text = stringify(payload.get("license_plate_text", ""))
    distance = payload.get("distance_m", "unknown")

    title = "Motorcycle Alert"
    body = f"Person moved {distance}m away from motorcycle"

    if plate_text:
        body += f", plate: {plate_text}"

    message = messaging.Message(
        token=FCM_DEVICE_TOKEN,
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
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
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    return float((dx * dx + dy * dy) ** 0.5)


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

    b64_value = None

    if isinstance(output_image, dict):
        b64_value = output_image.get("value")
    elif isinstance(output_image, str):
        b64_value = output_image

    if not b64_value:
        return None

    try:
        img_bytes = base64.b64decode(b64_value)
        img_array = np.frombuffer(img_bytes, dtype=np.uint8)
        return cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    except Exception as e:
        print("[Display] Could not decode output image:", e)
        return None


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


def compute_distance_alert(output: dict) -> Optional[dict]:
    """
    Uses Roboflow cloud detections, then keeps near-to-far state locally.
    """

    raw_preds = get_predictions(output, "raw_person_motorcycle_predictions")

    useful = [
        p for p in raw_preds
        if p.get("class") in ["person", "motorcycle"]
    ]

    tracks = tracker.update(useful)

    people = [t for t in tracks if t.cls == "person"]
    motorcycles = [t for t in tracks if t.cls == "motorcycle"]

    if not people or not motorcycles:
        return None

    best_pair = None

    for person in people:
        nearest_motorcycle = None
        nearest_distance_m = None

        for motorcycle in motorcycles:
            dist_px = euclidean(person.center, motorcycle.center)
            dist_m = dist_px / PIXELS_PER_METER

            if nearest_distance_m is None or dist_m < nearest_distance_m:
                nearest_distance_m = dist_m
                nearest_motorcycle = motorcycle

        if nearest_motorcycle is None or nearest_distance_m is None:
            continue

        if nearest_distance_m <= NEAR_DISTANCE_M:
            person.was_near_motorcycle = True

        candidate = {
            "person_track_id": person.track_id,
            "motorcycle_track_id": nearest_motorcycle.track_id,
            "distance_m": round(float(nearest_distance_m), 2),
            "person_was_near": person.was_near_motorcycle,
        }

        if best_pair is None or candidate["distance_m"] > best_pair["distance_m"]:
            best_pair = candidate

        if person.was_near_motorcycle and nearest_distance_m >= ALERT_DISTANCE_M:
            plate_text = output.get("license_plate_text", "")
            payload = {
                "status": "ALERT: person left motorcycle area",
                "distance_m": round(float(nearest_distance_m), 2),
                "person_track_id": person.track_id,
                "motorcycle_track_id": nearest_motorcycle.track_id,
                "license_plate_text": plate_text,
                "workflow_distance_status": output.get("distance_alert_status", ""),
                "workflow_nearest_distance_m": output.get("nearest_person_motorcycle_distance_m", ""),
            }
            return payload

    if best_pair:
        print(
            "[Distance]",
            f"person_track={best_pair['person_track_id']}",
            f"motorcycle_track={best_pair['motorcycle_track_id']}",
            f"distance={best_pair['distance_m']}m",
            f"was_near={best_pair['person_was_near']}",
            
        )

    return None


def print_summary(output: dict):
    plate_preds = get_predictions(output, "license_plate_predictions")
    raw_preds = get_predictions(output, "raw_person_motorcycle_predictions")

    people = [p for p in raw_preds if p.get("class") == "person"]
    motorcycles = [p for p in raw_preds if p.get("class") == "motorcycle"]

    print("\n========== Cloud Workflow ==========")
    print("People:", len(people))
    print("Motorcycles:", len(motorcycles))
    print("License plates:", len(plate_preds))
    print("Plate text:", stringify(output.get("license_plate_text", "")))
    print("Workflow distance status:", output.get("distance_alert_status"))
    print("Workflow nearest distance:", output.get("nearest_person_motorcycle_distance_m"))
    print("Motorcycle colors:", output.get("motorcycle_colors_rgb"))
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
        print_summary(output)

        annotated = decode_output_image(output.get("tracked_output_image"))
        if annotated is not None:
            latest_annotated_box[0] = annotated

        alert_payload = compute_distance_alert(output)

        if alert_payload:
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

    cap = connect_rtsp()
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
            continue

        now = time.time()

        display = latest_annotated_box[0] if latest_annotated_box[0] is not None else frame
        cv2.imshow("Edge Gateway, Roboflow Cloud GLM-OCR", display)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

        if now - last_sample_at < SAMPLE_SECONDS:
            continue

        if cloud_thread and cloud_thread.is_alive():
            continue

        last_sample_at = now
        cloud_thread = threading.Thread(
            target=_cloud_worker,
            args=(frame.copy(), latest_annotated_box),
            daemon=True,
        )
        cloud_thread.start()

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
