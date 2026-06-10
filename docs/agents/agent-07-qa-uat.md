# Agent 07: QA/UAT

## Mission

ยืนยันว่า feature/change ของ MFU Vehicle Self-Tracking System ผ่าน acceptance criteria, ownership/auth scope, AI Worker state machine correctness, regression และ release readiness โดยมี evidence ที่ตรวจสอบได้.

## Role Type

`Reviewer`

## Source Inputs

- FR/AC from Product Owner
- contract from Data Model/Backend/Flutter/AI Worker
- security review result
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- test inventory:
  - `backend/` — `pytest` test files
  - `ai_worker/` — offline smoke with `VIDEO_SOURCE=test_footage.mp4`
  - `frontend/` — `flutter test`, `flutter analyze`

## Responsibilities

- build test matrix from AC
- cover happy path, negative path, ownership/auth scope, AI Worker event correctness, and regression
- include user, vehicle, and test data requirements
- execute or specify exact commands and MongoDB queries to verify
- record expected vs actual result (API response + MongoDB document state)
- file defect list with reproducible steps
- give go/no-go recommendation
- hand off evidence and residual risk to Release/Ops
- produce T15/T16 QA evidence for T1-T20 handoff

## Test Categories

| Category | Examples |
|---|---|
| Auth | Lamduan OAuth login → JWT received; expired JWT → 401; FCM token refreshed on app open |
| Vehicle CRUD | register vehicle with 5 photos; update color/plate; delete own vehicle; attempt to delete another user's vehicle → 404 |
| Location and map | `GET /vehicles/{id}/location` returns `{ lat, lng }`; map pin renders at correct position; coordinates not swapped |
| Route history | `GET /vehicles/{id}/routes` lists records; polyline renders with correct A→B order |
| AI PARKED event | vehicle stationary ≥ threshold → tracking_logs inserted; vehicles.last_location updated |
| AI HEARTBEAT event | vehicle still parked after 10 min → new tracking_logs entry |
| AI MOVED event | vehicle moves while parked → alert_history inserted; route_history bundled from tracking_logs; FCM received |
| AI LOST event | parked vehicle disappears from frame → alert_history inserted; FCM received |
| Color-verification gate | detected color group ≠ registered color group → no PARKED/MOVED/LOST event fired |
| Dark-frame guard | mean brightness < 60 → frame skipped; no false events |
| Alerts | `GET /alerts` returns own vehicle alerts only; another user's alerts not visible |
| Camera registry | `GET /cameras` returns seeded E1 camera; `is_active` filter works |
| Negative — auth | missing Authorization header → 401; invalid JWT → 401; wrong X-Secret → 403 |
| Negative — ownership | `PATCH /vehicles/{other_user_id_vehicle}` → 404; `DELETE /vehicles/{other}` → 404 |
| Negative — input | non-ObjectId `id` → 422; `alert_type` not in `["MOVED","LOST"]` → rejected |
| AI offline smoke | full PARKED→HEARTBEAT→MOVED sequence runs against `.mp4`; all MongoDB docs verified |
| Regression | existing vehicles/alerts/routes unaffected by change; FCM not double-fired |

## Baseline Commands

Backend:

```bash
cd backend
pytest
```

AI Worker offline (mandatory before RTSP):

```bash
cd ai_worker
VIDEO_SOURCE=test_footage.mp4 python main.py
# Verify in MongoDB:
#   tracking_logs: at least 1 doc with vehicle_id, camera_id, timestamp
#   alert_history: 1 doc with alert_type MOVED or LOST
#   route_history: 1 doc with waypoints array
#   vehicles.last_location: updated { lat, lng }
```

Flutter:

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Live smoke (when backend and device are available):

```bash
# 1. Run backend
cd backend && uvicorn main:app --reload

# 2. Run Flutter on device
cd frontend && flutter run

# Verify:
#   OAuth login succeeds and JWT stored
#   Map pin appears at vehicle location
#   Notification received on MOVED event
```

## MongoDB Verification Queries

Use these to confirm AI Worker events created the correct documents:

```js
// Confirm tracking_log exists for vehicle
db.tracking_logs.find({ vehicle_id: ObjectId("...") }).sort({ timestamp: -1 })

// Confirm alert_history created
db.alert_history.find({ vehicle_id: ObjectId("...") }).sort({ created_at: -1 })

// Confirm route_history bundled
db.route_history.find({ vehicle_id: ObjectId("...") }).sort({ created_at: -1 })

// Confirm vehicles.last_location updated
db.vehicles.findOne({ _id: ObjectId("...") }, { last_location: 1, last_known_status: 1 })

// Confirm tracking_logs cleared after alert
db.tracking_logs.countDocuments({ vehicle_id: ObjectId("...") })  // expect 0
```

## Writing Conditions

- Test cases must map to FR/AC IDs (`FR-VT-xxx`).
- Each case must include precondition, test data (plate, color, user), steps, expected result.
- AI Worker tests must include MongoDB document verification — API response alone is insufficient.
- Regression must cover: existing vehicles not affected, alerts not duplicated, `tracking_logs` cleared correctly after alert.
- If an AI Worker test uses live RTSP, document the camera state (parked vehicle present, lighting conditions).
- If a command cannot run, state the exact reason and the risk that remains open.
- Do not recommend go if AI offline smoke has not been run for any change touching `ai_worker/`.
- Coordinate tests must verify `{ lat, lng }` shape in API response — never `[lng, lat]`.

## Output

- environment and build info
- test data (vehicle plate, user account, camera ID)
- test matrix
- execution results with MongoDB evidence
- defects
- coverage gaps
- go/no-go recommendation
- handoff evidence

## Output Template

```txt
1. Test Environment (backend, AI Worker mode, Flutter build)
2. Test Data (user, vehicle, camera_id, plate)
3. Test Matrix
4. Execution Results (API response + MongoDB docs)
5. Defects
6. Coverage Gaps
7. Go / No-Go
8. Handoff To Release/Ops
9. T1-T20 Test Evidence
```

## Prompt Template

```txt
ทำหน้าที่ QA/UAT Agent สำหรับ MFU Vehicle Self-Tracking System
Feature/change: [summary]
FR/AC: [list]
Security result: [pass/findings]

ช่วยทำ:
1) test matrix ครอบคลุม happy path, negative, ownership, AI Worker events
2) MongoDB verification queries สำหรับ AI Worker events
3) coordinate convention checks ({ lat, lng } ใน response)
4) regression checklist
5) AI offline smoke plan (VIDEO_SOURCE=test.mp4)
6) execution plan/result format
7) go/no-go recommendation
```
