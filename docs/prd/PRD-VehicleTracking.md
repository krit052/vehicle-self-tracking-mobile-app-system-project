# PRD: MFU Vehicle Self-Tracking System

## Document Control

| Field | Value |
|---|---|
| Product | MFU Vehicle Self-Tracking System |
| Version | 0.1 |
| Status | Baseline From Design Document |
| Source checked date | 2026-06-10 |
| Related design | `Vehicle_tracking_simple.md` |
| Related workflow | `docs/AI-WORKFLOW.md` |
| Related agents | `docs/agents/README.md` |

## Source Truth

This PRD must stay aligned with current source. If source and PRD conflict, source wins until PRD is updated.

| Area | Source |
|---|---|
| Backend routes | `backend/api/api.py` |
| Database schema | `backend/db/database.py` |
| Camera seed script | `backend/cctv/seed_camera.py` |
| AI detection pipeline | `ai_worker/detector.py` |
| AI stationary state machine | `ai_worker/tracker.py` |
| AI main loop | `ai_worker/main.py` |
| Flutter screens | `frontend/lib/` |
| Flutter dependencies | `frontend/pubspec.yaml` |
| Backend dependencies | `backend/requirements.txt` |

## Product Overview

This system is a vehicle self-tracking mobile application for MFU's E1 Parking Lot, developed as a senior project. It provides:

- Lamduan OAuth login (MFU SSO)
- Vehicle registration with 5-angle photo upload to Cloudinary
- Real-time CCTV-based AI detection using YOLOv11 + ByteTrack + PaddleOCR
- Location tracking displayed on OpenStreetMap via Flutter
- Push notification (FCM) when a registered vehicle moves or disappears
- Route history playback as a polyline on the map

Three runtime processes: **Flutter app**, **FastAPI backend**, **AI Worker**. One database: **MongoDB Atlas**.

## Current Backend Route Domains

All routes are served by FastAPI (`backend/api/api.py`). No route prefix mount layer — routes are registered flat.

| Path | Domain | Notes |
|---|---|---|
| `/auth/login` | Authentication | Lamduan OAuth code exchange |
| `/vehicles` | Vehicle CRUD | Owner-scoped list, create, update, delete |
| `/vehicles/{id}/location` | Tracking | Returns `last_location` from vehicle document |
| `/vehicles/{id}/routes` | Route History | List of route_history records |
| `/vehicles/{id}/routes/{rid}` | Route History | Single route with waypoints for polyline |
| `/alerts` | Alert History | Owner-scoped, newest-first |
| `/cameras` | Camera Registry | List of active CCTV cameras |
| `/users/me` | User Settings | FCM token and detection threshold |
| `/internal/*` | AI Worker Internal | Protected by `X-Secret` header |

## Current Frontend Screen Domains (Flutter)

| Screen | Entry condition | Notes |
|---|---|---|
| `login_screen` | App launch | Checks JWT in secure storage |
| `oauth_screen` | No saved JWT | Lamduan WebView OAuth flow |
| `home_screen` | JWT present | Root navigation hub |
| `vehicle_profile_screen` | From home_screen | Shows owned vehicles + 5-photo upload + plate/model form|
| `live_tracking_screen` | From home_screen | Live vehicle pin on OpenStreetMap |
| `route_history_screen` | From home_screen | Lists route_history records |
| `route_detail_screen` | From route_history_screen | A-to-B polyline on map |
| `notifications_screen` | From home_screen | Alert history list |

## Functional Areas

### FR-VT-001 Authentication and Session

Users authenticate via Lamduan (MFU SSO) OAuth code exchange. The backend issues a JWT stored securely on device. On each app open, the FCM token is refreshed by calling `PATCH /users/me`.

Source:

- `backend/api/api.py` — `POST /auth/login`
- `frontend/lib/screens/login_screen.dart`
- `frontend/lib/screens/oauth_screen.dart`

Current API contract:

| Method | Endpoint | Auth | Body / Response |
|---|---|---|---|
| POST | `/auth/login` | none | body: `{ code }` → `{ token }` |
| PATCH | `/users/me` | Bearer JWT | body: `{ fcm_token?, detection_threshold_min? }` → `{ ok }` |

---

### FR-VT-002 Vehicle Registration and Management

Authenticated users can register vehicles with a licence plate, model form And 5 photos upload (front, back, left, right, plate). Photos are uploaded directly from Flutter to Cloudinary before `POST /vehicles` is called. The backend stores only Cloudinary URLs.

Source:

- `backend/api/api.py` — `/vehicles` routes
- `frontend/lib/screens/vehicle_profile_screen`

Current API contract:

| Method | Endpoint | Auth | Notes |
|---|---|---|---|
| GET | `/vehicles` | Bearer JWT | Returns vehicles owned by caller |
| POST | `/vehicles` | Bearer JWT | Registers new vehicle with photo URLs |
| PATCH | `/vehicles/{id}` | Bearer JWT | Update plate / model / color / geofence_radius_m |
| DELETE | `/vehicles/{id}` | Bearer JWT | Remove vehicle; caller must own it |

Vehicle document fields relevant to the app:

| Field | Type | Notes |
|---|---|---|
| `license_plate` | String | e.g. `กข1234` |
| `model` | String | e.g. `Honda Wave` |
| `color` | String | e.g. `red` — used by AI color-verification gate |
| `photos.{front,back,left,right,plate}_url` | String | Cloudinary secure URLs |
| `geofence_radius_m` | Number | Default 5 m; user can change per vehicle |
| `last_known_status` | String | `"parked"` \| `"moving"` \| `"unknown"` |
| `last_location` | `{ lat, lng }` | Populated by AI Worker; Flutter reads this directly |

---

### FR-VT-003 Location Tracking and Map Display

The Flutter `MapScreen` polls `GET /vehicles/{id}/location` to display a live motorcycle pin on an OpenStreetMap tile layer (`flutter_map`). Route history (`route_history_screen`) fetches waypoints and renders a blue polyline.

Source:

- `backend/api/api.py` — `/vehicles/{id}/location`, `/vehicles/{id}/routes`, `/vehicles/{id}/routes/{rid}`
- `frontend/lib/screens/live_tracking_screen.dart`
- `frontend/lib/screens/route_detail_screen.dart`

Current API contract:

| Method | Endpoint | Auth | Response |
|---|---|---|---|
| GET | `/vehicles/{id}/location` | Bearer JWT | `{ lat, lng }` from `vehicles.last_location` |
| GET | `/vehicles/{id}/routes` | Bearer JWT | `[{ id, start_time, end_time }]` — newest first |
| GET | `/vehicles/{id}/routes/{rid}` | Bearer JWT | `{ waypoints: [{lat, lng, time}], start_time, end_time }` |

Backend converts GeoJSON `[lng, lat]` coordinates to `{ lat, lng }` before returning to Flutter — Flutter must not reverse this.

---

### FR-VT-004 AI Detection and Stationary State Management

The AI Worker runs at 2 fps against an RTSP stream (or a `.mp4` file for development). For each frame it runs:

1. **YOLOv11** — detects `motorcycle` and `license_plate` bounding boxes
2. **ByteTrack** — assigns persistent `track_id` across frames
3. **PaddleOCR** — reads licence plate text (Thai, ≥ 0.6 confidence)
4. **K-Means HSV** — extracts dominant vehicle color
5. **Color-verification gate** — suppresses alerts when detected color and registered color are in different groups
6. **Homography** — maps pixel centroid to GPS `(lat, lng)` via 4 calibration points at E1
7. **StationaryTracker** — per-`track_id` state machine that emits events

State machine events and thresholds:

| Event | Condition | Backend call |
|---|---|---|
| `PARKED` | Vehicle stationary ≥ `detection_threshold_min` (default 2 min) | `POST /internal/parked` |
| `HEARTBEAT` | Vehicle still parked after 10 min since last log | `POST /internal/heartbeat` |
| `MOVED` | Vehicle was `parked`, centroid moved > `STILL_THRESHOLD_DEG` (~5 m) | `POST /internal/alert` (`alert_type: "MOVED"`) |
| `LOST` | Vehicle disappears from camera while parked | `POST /internal/alert` (`alert_type: "LOST"`) |

Dark-frame guard: frames with mean brightness < 60 are skipped; worker sleeps 30 s.

Source:

- `ai_worker/detector.py` — YOLOv11 + ByteTrack + PaddleOCR pipeline
- `ai_worker/tracker.py` — `StationaryTracker` class
- `ai_worker/main.py` — main loop, homography, color gate, backend calls

Internal API contract (all require `X-Secret` header):

| Method | Endpoint | Body fields |
|---|---|---|
| GET | `/internal/vehicle-by-plate/{plate}` | — → `{ vehicle_id, geofence_radius_m, color }` |
| POST | `/internal/parked` | `vehicle_id, camera_id, track_id, confidence_score, lat, lng, detection_duration_min` |
| POST | `/internal/heartbeat` | same as parked + `movement_delta` |
| POST | `/internal/alert` | same as parked + `alert_type ("MOVED"\|"LOST")`, `snapshot_url?` |

---

### FR-VT-005 Alert and Push Notification

When the AI Worker fires `POST /internal/alert`, the backend:

1. Inserts an `alert_history` document
2. Sets `vehicles.last_known_status` to `"unknown"`
3. Collects all `tracking_logs` for the vehicle, bundles them into a `route_history` document, then deletes the consumed logs
4. Sends an FCM push notification to the vehicle owner's `fcm_token`

The `NotificationScreen` in Flutter fetches `GET /alerts` (owner-scoped, newest-first).

Source:

- `backend/api/api.py` — `POST /internal/alert`, `GET /alerts`
- `frontend/lib/screens/notifications_screen.dart`

Alert response shape:

```json
{
  "id": "string",
  "vehicle_id": "string",
  "alert_type": "MOVED | LOST",
  "lat": 18.9143,
  "lng": 99.0490,
  "snapshot_url": "string",
  "created_at": "ISO8601"
}
```

FCM message body:
- `MOVED` → `"Your vehicle may have moved!"`
- `LOST` → `"Your vehicle disappeared from camera view."`

---

### FR-VT-006 Camera Registry

`GET /cameras` returns all active CCTV cameras from `cctv_cameras`. Flutter may display camera locations on the map. The E1 camera is inserted once by running `backend/cctv/seed_camera.py`; its `ObjectId` must be copied into `.env` as `CAMERA_ID` before starting the AI Worker.

Source:

- `backend/api/api.py` — `GET /cameras`
- `backend/cctv/seed_camera.py`

---

## Database — 6 Collections

| Collection | Purpose |
|---|---|
| `users` | MFU email, display name, FCM token, detection threshold |
| `cctv_cameras` | Physical camera location (GeoJSON Point), coverage, active flag |
| `vehicles` | Registered vehicles with photos, color, geofence, last known state |
| `tracking_logs` | One entry per PARKED event + one per HEARTBEAT; cleared after alert |
| `alert_history` | Permanent record of MOVED / LOST events with snapshot URL |
| `route_history` | Trip waypoints bundled from tracking_logs when an alert fires |

All location fields use GeoJSON `{ type: "Point", coordinates: [lng, lat] }` internally. The backend converts to `{ lat, lng }` before returning to Flutter.

---

## Non-Functional Requirements

| Area | Requirement |
|---|---|
| Security | `/internal/*` routes require matching `X-Secret` header; all other protected routes require Bearer JWT |
| AI reliability | Dark-frame skip guard must be in place; RTSP reconnect on frame drop |
| Color verification | AI Worker must not fire alerts when detected color group ≠ registered color group |
| Homography calibration | `PIXEL_PTS` and `GPS_PTS` in `ai_worker/main.py` must be measured on-site at E1 before go-live |
| Image storage | Vehicle photos must not be stored in MongoDB; only Cloudinary `secure_url` strings |
| Frontend structure | All screens must be widget-based; map rendered with `flutter_map` + OpenStreetMap tiles |
| Compatibility | Backend returns `{ lat, lng }` (not GeoJSON) to Flutter; do not change this without updating all map consumers |
| Testing | AI Worker must be validated against a recorded `.mp4` before connecting to live RTSP |
| Documentation | Changes must produce T1-T20 handoff and PRD update decision |

---

## PRD Update Rules

Update this PRD when any change affects:

- FR/AC
- API endpoint, request body, response shape, or error behavior
- Flutter screen workflow or navigation graph
- MongoDB collection schema, index, or seed data
- AI Worker detection parameters, thresholds, or state machine logic
- Permission model (JWT claims, X-Secret rotation)
- Homography calibration points
- Test or release expectation

Use `docs/AI-WORKFLOW.md` section `T1-T20` for change documentation.
