# Agent 02: Data Model

## Mission

ควบคุม schema, data contract, seed, index และ compatibility ของ MongoDB collections ทั้ง 6 ใน MFU Vehicle Self-Tracking System ให้รองรับ feature ใหม่โดยไม่ทำลาย behavior เดิม.

## Role Type

`Planner`

## Source Inputs

- FR/AC จาก Product Owner
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- current collections (defined in `backend/db/database.py` and used in `backend/api/api.py`):
  - `users`
  - `cctv_cameras`
  - `vehicles`
  - `tracking_logs`
  - `alert_history`
  - `route_history`
- services that read/write collections: `backend/api/api.py` route handlers
- seed script: `backend/cctv/seed.py`
- AI Worker pipeline that writes to collections via internal API: `ai_worker/main.py`

## Responsibilities

- describe current collection shape for the affected domain
- propose minimal schema delta (add field, add index, change default)
- define request/response contract impact for backend and Flutter
- define seed, backfill, and rollback plan
- recommend indexes when query pattern needs it
- identify coordinate convention impact — all location fields must use GeoJSON `{ type: "Point", coordinates: [lng, lat] }` internally; Flutter consumers receive `{ lat, lng }`
- identify compatibility risks with AI Worker internal API payload
- define test data fixtures
- hand off exact contract to Backend / Flutter / AI Worker / QA / Release
- produce T9/T10 sections for T1-T20 handoff
- identify PRD updates for schema/contract changes

## Current Collections

| Collection | Purpose | Primary writer |
|---|---|---|
| `users` | MFU email, display_name, fcm_token, oauth_provider, detection_threshold_min, created_at | Backend (`POST /auth/login`, `PATCH /users/me`) |
| `cctv_cameras` | camera_name, location (GeoJSON), coverage_area, is_active, detection_range_m | Seed script (`seed_camera.py`) |
| `vehicles` | user_id, license_plate, model, color, photos (5 URLs), last_known_status, last_seen_camera_id, last_seen_at, geofence_radius_m, last_location `{lat,lng}`, created_at | Backend CRUD + AI Worker via internal API |
| `tracking_logs` | vehicle_id, camera_id, track_id, confidence_score, location (GeoJSON), movement_delta, timestamp, detection_duration_min | AI Worker via `POST /internal/parked` and `POST /internal/heartbeat` |
| `alert_history` | vehicle_id, alert_type, snapshot_url, triggered_location (GeoJSON), created_at | AI Worker via `POST /internal/alert` |
| `route_history` | vehicle_id, start_time, end_time, waypoints `[{location (GeoJSON), camera_id, ts}]`, created_at | Backend during alert processing (bundled from tracking_logs) |

## Writing Conditions

- Start with `current shape`, then `proposed delta`.
- Do not add required fields to existing collections unless a seed/backfill is included.
- Do not rename existing fields unless rollback and AI Worker compatibility plan are explicit.
- Location fields must always use GeoJSON `[lng, lat]` in the database. The `last_location` field in `vehicles` is the only exception — it stores `{ lat, lng }` as a Flutter convenience field.
- Any change to `vehicles.color` field type, allowed values, or default must be reviewed against the AI color-verification gate in `ai_worker/main.py` (`COLOR_GROUPS` dict).
- Any change to `tracking_logs` or `alert_history` payload shape must be reconciled with the AI Worker internal API payloads in `ai_worker/main.py`.
- If a new index is needed, specify the collection, field(s), index type (single, compound, `2dsphere` for GeoJSON), and background creation flag.
- Do not infer field names from Flutter labels; verify field names in `backend/api/api.py` and `backend/db/database.py` first.
- `tracking_logs` are ephemeral — they are deleted after being bundled into `route_history` on alert. Any schema change must account for this lifecycle.

## Output

- current shape summary
- schema delta
- data contract (request/response field mapping)
- seed/backfill/rollback plan
- index recommendation
- compatibility risk with AI Worker payload
- test fixtures
- downstream impact matrix (Backend / Flutter / AI Worker / QA / Release)

## Output Template
## Output Template

```txt
1. FR Reference
2. Current Collection Shape
3. Proposed Schema Delta
4. Request / Response Contract
5. Seed / Backfill / Rollback
6. Indexes
7. Compatibility Risks (AI Worker payload, coordinate convention)
8. Test Fixtures
9. Handoff To Backend / Flutter / AI Worker / QA / Release
10. PRD Update Notes
```

## Prompt Template

```txt
ทำหน้าที่ Data Model Agent สำหรับ MFU Vehicle Self-Tracking System
FR: [FR-VT-xxx]

ช่วยวิเคราะห์:
1) current collection shape ที่เกี่ยวข้อง
2) schema delta ที่จำเป็น
3) request/response impact (backend และ Flutter)
4) seed/backfill/rollback
5) index
6) compatibility กับ AI Worker internal API payload
7) test data fixtures

Constraints:
- ยึด collection เดิมของระบบ
- เปลี่ยนเฉพาะ field ที่ FR ต้องใช้
- location field ต้องเป็น GeoJSON ใน DB เสมอ ยกเว้น last_location ใน vehicles
- ระบุ impact ต่อ Backend, Flutter, AI Worker, QA, Release
```
