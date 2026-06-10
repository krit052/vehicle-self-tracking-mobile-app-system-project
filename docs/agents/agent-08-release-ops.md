# Agent 08: Release/Ops

## Mission

วางแผนปล่อย MFU Vehicle Self-Tracking System change ให้พร้อมใช้งานจริง โดยครอบคลุม env/config, deploy, seed, smoke, AI Worker calibration, monitoring, rollback และ support handoff.

## Role Type

`Planner`

## Source Inputs

- implementation summary from Backend/Flutter/AI Worker
- Data Model seed/rollback note
- Security decision
- QA/UAT result
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- `SETUP.md`
- deployment sources:
  - `docker-compose.yml`
  - `backend/Dockerfile`
  - `ai_worker/Dockerfile`
  - `backend/requirements.txt`
  - `ai_worker/requirements.txt`
  - `frontend/pubspec.yaml`
  - `.env`

## Two Deployment Modes

| Mode | When | How |
|---|---|---|
| Manual (dev) | Development, offline testing | Run each process separately in terminal |
| Docker (prod) | Handoff, demo, production | `docker compose up --build` |

**Manual mode** runs three separate processes:

| Terminal | Command | Notes |
|---|---|---|
| 1 — Backend | `cd backend && uvicorn main:app --reload --port 8000` | After `pip install -r requirements.txt` |
| 2 — AI Worker | `cd ai_worker && python main.py` | After `pip install -r requirements.txt` |
| 3 — Flutter | `cd frontend && flutter run` | After `flutter pub get` |

MongoDB is either local (`net start MongoDB`) or MongoDB Atlas via `MONGODB_URL`.

**Docker mode** runs three containers:

| Container | Service |
|---|---|
| `mfu_mongodb` | MongoDB 7 (local) |
| `mfu_backend` | FastAPI on port 8000 |
| `mfu_ai_worker` | AI detection pipeline |

```bash
# Build and start all containers
docker compose up --build

# Start without rebuild (subsequent runs)
docker compose up

# Stop
docker compose down

# Logs
docker compose logs -f backend
docker compose logs -f ai_worker

# Rebuild single service after code change
docker compose up --build backend
docker compose up --build ai_worker
```

Swagger API docs (smoke check): `http://localhost:8000/docs`

**MongoDB URL differs by mode:**
- Manual: `MONGODB_URL=mongodb://localhost:27017/...`
- Docker: `MONGODB_URL=mongodb://mongodb:27017/mfu-vehicle-tracking` (service name, not localhost)

## Responsibilities

- define release scope and window
- list env/config changes and validate `.env` completeness
- confirm `seed_camera.py` has been run and `CAMERA_ID` is in `.env`
- confirm `VIDEO_SOURCE` is removed/commented out for production (live RTSP mode)
- confirm `yolov11s_mfu.pt` model file is present in `ai_worker/` before Docker build
- confirm `firebase_key.json` is present in `backend/` before Docker build
- confirm homography calibration (`PIXEL_PTS`/`GPS_PTS`) is measured on-site at E1
- define deploy steps by environment (manual vs Docker)
- define smoke and post-release verification
- define monitoring/log checks
- define rollback triggers and steps
- identify owners and support handoff
- produce T19/T20 release handoff

## Release Surfaces

| Change type | Release concern |
|---|---|
| Backend route/logic | rebuild `mfu_backend` image; smoke `/docs` and changed endpoints |
| AI Worker pipeline | rebuild `mfu_ai_worker` image; offline `.mp4` test first; verify MongoDB docs on PARKED/ALERT |
| Flutter app | `flutter build apk --release`; install on device; verify OAuth → map → notification |
| `.env` variable change | update `.env` on host; restart affected containers; do NOT commit `.env` to git |
| `seed_camera.py` re-run | creates new `cctv_cameras` document; update `CAMERA_ID` in `.env`; restart `ai_worker` |
| YOLO model file change | place new `.pt` file in `ai_worker/`; rebuild Docker image; test detection accuracy offline |
| Homography calibration | on-site E1 measurement required; update `PIXEL_PTS`/`GPS_PTS` in `ai_worker/main.py`; test with `.mp4` |
| Firebase key rotation | replace `firebase_key.json` in `backend/`; rebuild backend image |
| `INTERNAL_SECRET` rotation | update both `backend/.env` and `ai_worker/.env` atomically; restart both containers |
| MongoDB collection change | no migration script needed (MongoDB flexible schema); verify AI Worker payload compatibility |

## Pre-Release Checklist

Complete every item before starting deployment. Include owner and evidence.

```txt
[ ] .env is complete — all keys present and non-empty (see required keys below)
[ ] VIDEO_SOURCE is commented out or absent in .env (production uses RTSP, not .mp4)
[ ] CAMERA_ID is in .env — obtained from seed_camera.py output
[ ] yolov11s_mfu.pt is in ai_worker/ directory
[ ] firebase_key.json is in backend/ directory
[ ] PIXEL_PTS / GPS_PTS in ai_worker/main.py are real on-site E1 measurements
[ ] AI Worker offline smoke completed (VIDEO_SOURCE=test.mp4 + MongoDB docs verified)
[ ] Backend pytest passed
[ ] Flutter analyze passed; APK built successfully
[ ] Security review: pass or pass-with-risk
[ ] QA go decision received
[ ] .env NOT committed to git
```

## Required .env Keys

All keys must be present and non-placeholder before production deploy:

```env
# MongoDB
MONGODB_URL=mongodb+srv://<user>:<pass>@<cluster>/<dbname>

# App secrets — use random strings, not defaults
JWT_SECRET=<random-string>
INTERNAL_SECRET=<random-string>

# MFU OAuth
LAMDUAN_CLIENT_ID=<mfu-oauth-client-id>
LAMDUAN_CLIENT_SECRET=<mfu-oauth-client-secret>

# Camera — must match cctv_cameras document
CAMERA_RTSP_URL=rtsp://<user>:<pass>@<camera-ip>/stream
CAMERA_ID=<objectid-from-seed_camera.py>
BACKEND_URL=http://localhost:8000

# Cloudinary
CLOUDINARY_URL=cloudinary://<api_key>:<api_secret>@<cloud_name>

# VIDEO_SOURCE must NOT be set in production
# VIDEO_SOURCE=test_footage.mp4
```

## Deploy Steps — Manual Mode

```bash
# 1. Install/update backend dependencies
cd backend
pip install -r requirements.txt

# 2. Seed camera (run once — skip if CAMERA_ID already in .env)
python seed_camera.py
# Copy printed CAMERA_ID → .env

# 3. Start backend
uvicorn main:app --reload --port 8000

# 4. Verify backend
curl http://localhost:8000/docs   # Swagger must load

# 5. Install/update AI Worker dependencies
cd ai_worker
pip install -r requirements.txt

# 6. Run AI Worker offline smoke first
VIDEO_SOURCE=test_footage.mp4 python main.py
# Verify: tracking_logs, alert_history, route_history created in MongoDB

# 7. Switch to live RTSP (comment out VIDEO_SOURCE in .env)
python main.py

# 8. Run Flutter
cd frontend
flutter pub get
flutter run
```

## Deploy Steps — Docker Mode

```bash
# 1. Place required files
#    ai_worker/yolov11s_mfu.pt   ← YOLO model
#    backend/firebase_key.json   ← Firebase credentials

# 2. Set .env at project root (do not commit)

# 3. Build and start all containers
docker compose up --build

# 4. Seed camera (run once while containers are up)
docker exec mfu_backend python seed_camera.py
# Copy printed CAMERA_ID → .env CAMERA_ID=

# 5. Restart AI Worker with updated CAMERA_ID
docker compose restart ai_worker

# 6. Smoke check
curl http://localhost:8000/docs
```

## GPU vs CPU for AI Worker (Docker)

| Hardware | Action |
|---|---|
| NVIDIA GPU | Install nvidia-container-toolkit; keep `use_gpu=True` in `detector.py`; keep GPU block in `docker-compose.yml` |
| AMD or no GPU | Remove GPU block from `docker-compose.yml`; set `use_gpu=False` in `ai_worker/detector.py`; runs on CPU — slower but sufficient for demo |

## Smoke Tests After Deploy

```bash
# Backend health
curl http://localhost:8000/docs

# Auth endpoint
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"code": "test"}'

# Camera list (public)
curl http://localhost:8000/cameras

# Internal route (must reject wrong secret)
curl http://localhost:8000/internal/vehicle-by-plate/test \
  -H "X-Secret: wrong" 
# expect 403
```

Flutter device smoke:
- OAuth login completes → JWT stored
- Vehicle list screen loads
- Map pin appears at `last_location`
- FCM notification received on MOVED event

## Post-Release Monitoring

| Check | How |
|---|---|
| AI Worker running | `docker compose logs -f ai_worker` — no repeated reconnect errors |
| PARKED events firing | `db.tracking_logs.countDocuments({})` increasing over time |
| Alerts firing | `db.alert_history.find().sort({created_at:-1}).limit(5)` |
| FCM delivery | Firebase console → Cloud Messaging → Deliveries |
| Backend errors | `docker compose logs -f backend` — no unhandled exceptions |
| MongoDB Atlas connection | Atlas dashboard — active connections > 0 |

## Rollback Plan

| Scenario | Trigger | Steps |
|---|---|---|
| Backend broken | `/docs` returns 500 or routes fail smoke | `docker compose up --build backend` with previous code; or `git revert` + rebuild |
| AI Worker not detecting | No new `tracking_logs` after 15 min with vehicle present | Check `docker logs ai_worker` for exceptions; verify `CAMERA_ID` matches DB; verify RTSP URL |
| Wrong CAMERA_ID | AI Worker fires internal API but backend returns 404 on vehicle lookup | Re-run `seed_camera.py`; update `.env`; restart `ai_worker` |
| FCM not delivered | Alerts in `alert_history` but no phone notification | Verify `fcm_token` in `users` doc; verify `firebase_key.json` matches Firebase project |
| MongoDB connection lost | Backend returns 500 on all routes | Check `MONGODB_URL` in `.env`; check Atlas IP allowlist includes server IP |
| `tracking_logs` not clearing | `db.tracking_logs.countDocuments({})` grows unbounded | `POST /internal/alert` may have failed — check backend logs; manual clear: `db.tracking_logs.deleteMany({vehicle_id: ObjectId("...")})` |

## Writing Conditions

- Do not invent infrastructure not present in `docker-compose.yml` or `SETUP.md`.
- Pre-release checklist must include owner and evidence for each item.
- Rollback must include trigger, steps, expected impact, and data handling.
- `seed_camera.py` is one-time — running it twice creates a duplicate camera document; document this risk.
- `VIDEO_SOURCE` in `.env` overrides RTSP — must be absent in production; flag if present.
- GPU configuration differs between NVIDIA and AMD/CPU; confirm hardware before release.
- Confirm PRD/docs update status before release sign-off.

## Output

- release scope
- env/config checklist
- seed/file checklist
- deployment steps (manual and Docker)
- smoke/post-release verification
- monitoring checks
- rollback plan
- support handoff
- go/no-go criteria
- T19/T20 release handoff

## Output Template

```txt
1. Release Scope
2. Environment / Config Checklist (.env keys)
3. File Checklist (model, firebase_key)
4. Calibration Checklist (PIXEL_PTS / GPS_PTS)
5. Deployment Steps (Manual or Docker)
6. Smoke Tests
7. Post-Release Monitoring
8. Rollback Plan
9. Owners And Support Handoff
10. Go / No-Go Criteria
11. T1-T20 Release Handoff
```

## Prompt Template

```txt
ทำหน้าที่ Release/Ops Agent สำหรับ MFU Vehicle Self-Tracking System
Change summary: [summary]
QA result: [summary]
Security decision: [summary]
Deploy mode: [Manual / Docker]

ช่วยทำ:
1) pre-release checklist (.env, model file, firebase_key, CAMERA_ID, VIDEO_SOURCE removed)
2) calibration status (PIXEL_PTS/GPS_PTS on-site?)
3) deploy steps ตาม mode
4) seed_camera.py status
5) smoke tests
6) post-release monitoring
7) rollback plan per failure scenario
8) go/no-go criteria
```
