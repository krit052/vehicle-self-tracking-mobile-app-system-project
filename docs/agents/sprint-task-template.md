# MFU Vehicle Self-Tracking System — Sprint Task Template

Use this template for any vehicle tracking feature/change that needs agent handoff.

This template complements `docs/AI-WORKFLOW.md`. Any implementation/change handoff must also complete the T1-T20 format in `docs/templates/T1-T20-change-document.md`.

## 1. Requirement Summary

| Field | Value |
|---|---|
| Module / Feature | |
| Business goal | |
| Source request | |
| In scope | |
| Out of scope | |
| Assumptions | |
| Open questions | |

## 2. Source Evidence

| Area | File / Route / Collection / Screen |
|---|---|
| Backend route | `backend/api/api.py` — route: |
| Collection affected | `backend/db/database.py` — collection: |
| Flutter screen | `frontend/lib/screens/` — screen: |
| Flutter provider/service | `frontend/lib/providers/` or `services/` — file: |
| Internal API payload | `/internal/*` endpoint and fields: |
| Existing tests | |
| Existing docs | |
| AI workflow | `docs/AI-WORKFLOW.md` |
| PRD | `docs/prd/PRD-VehicleTracking.md` |

## 3. Functional Requirements

| FR ID | Requirement | Actor | Auth type | Priority | Notes |
|---|---|---|---|---|---|
| FR-VT-001 | | | JWT / X-Secret / public | Must | |

## 4. Acceptance Criteria

| AC ID | FR ID | Given | When | Then |
|---|---|---|---|---|
| AC-VT-001 | FR-VT-001 | | | |

## 5. Auth And Ownership Matrix

| Feature / Route | Auth type | Ownership check | Notes |
|---|---|---|---|
| | Bearer JWT | `vehicle.user_id == caller` | |
| | X-Secret header | n/a (AI Worker only) | |
| | public | n/a | |

Coordinate convention for location responses:

| Returns location? | Convention |
|---|---|
| yes | `{ lat, lng }` — never raw GeoJSON to Flutter |
| no | n/a |

## 6. Data Contract

### Request

```json
{}
```

### Response

```json
{}
```

### Internal API Payload (if AI Worker involved)

```json
{}
```

### Collection / Schema

| Item | Decision |
|---|---|
| Collection change | yes/no |
| New field | yes/no — field name: |
| Seed/backfill | yes/no |
| Index | yes/no — type (single / compound / 2dsphere): |
| Rollback | |
| AI Worker payload compatibility | yes/no — fields affected: |

## 7. Task List

| Task ID | Task | Agent | Owner | Depends On | Status | Output |
|---|---|---|---|---|---|---|
| VT-001 | Clarify scope and AC | Product Owner | | | pending | FR/AC |
| VT-002 | Confirm collection contract, coordinate convention | Data Model | | VT-001 | pending | contract |
| VT-003 | Backend implementation | Backend | | VT-002 | pending | API/pytest |
| VT-004 | Flutter implementation | Flutter App | | VT-002 | pending | screens/flutter test |
| VT-005 | AI Worker implementation (if detection/tracking changes) | AI Worker | | VT-002 | pending | offline smoke |
| VT-006 | Security review | Security | | VT-003, VT-004, VT-005 | pending | findings |
| VT-007 | QA/UAT | QA/UAT | | VT-006 | pending | MongoDB evidence |
| VT-008 | Release/Ops | Release/Ops | | VT-007 | pending | release plan |
| VT-009 | T1-T20 and PRD/doc update | Orchestrator | | VT-007 | pending | final handoff |

Status values: `pending` · `in_progress` · `blocked` · `done`

Note: VT-003 and VT-004 may run in parallel after VT-002. VT-005 (AI Worker) must lock internal API payload shape before VT-003 or VT-004 start if `/internal/*` is involved.

## 8. Dependency Graph

```txt
Requirement
  -> Product Owner
  -> Data Model
  -> Backend + Flutter App (parallel after contract locked)
  -> AI Worker (if detection/tracking/internal API changes)
  -> Security
  -> QA/UAT
  -> Release/Ops
  -> Production
```

## 9. Risks / Blockers / Assumptions / Decisions

| ID | Type | Description | Impact | Mitigation / Decision | Owner | Status |
|---|---|---|---|---|---|---|
| R-001 | Risk | | | | | open |
| B-001 | Blocker | | | | | open |
| A-001 | Assumption | | | | | open |
| D-001 | Decision | | | | | closed |

Common risk areas for this system:

- `{ lat, lng }` vs GeoJSON convention mismatch between backend and Flutter
- `vehicles.color` change breaks AI color-verification gate
- `/internal/*` payload shape mismatch between AI Worker and backend
- `tracking_logs` ephemeral lifecycle — cleared on alert; changes must account for this
- `CAMERA_ID` in `.env` does not match `cctv_cameras` document
- `VIDEO_SOURCE` left set in production (overrides live RTSP)
- `PIXEL_PTS`/`GPS_PTS` homography not calibrated on-site at E1

## 10. Test Matrix

| Test ID | Type | User / Process | Precondition | Steps | Expected | Status | Evidence |
|---|---|---|---|---|---|---|---|
| TC-001 | functional | authenticated user | | | | pending | |
| TC-002 | negative | unauthenticated / wrong JWT | | | 401 | pending | |
| TC-003 | ownership | different user's vehicle | | | 404 | pending | |
| TC-004 | internal auth | wrong X-Secret | | | 403 | pending | |
| TC-005 | AI Worker event | AI Worker + `.mp4` | | PARKED/MOVED/LOST fires | MongoDB doc created | pending | |
| TC-006 | coordinate | Flutter map screen | | map pin renders | `{ lat, lng }` used, not swapped | pending | |
| TC-007 | regression | existing vehicles/alerts | | unaffected by change | no data loss | pending | |

## 11. Verification Commands

Backend:

```bash
cd backend
pytest
```

AI Worker offline (mandatory before RTSP if ai_worker/ changes):

```bash
cd ai_worker
VIDEO_SOURCE=test_footage.mp4 python main.py
# Verify MongoDB:
#   db.tracking_logs.find({ vehicle_id: ObjectId("...") })
#   db.alert_history.find({ vehicle_id: ObjectId("...") })
#   db.route_history.find({ vehicle_id: ObjectId("...") })
#   db.vehicles.findOne({ _id: ObjectId("...") }, { last_location: 1 })
```

Flutter:

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Smoke (live backend + device):

```bash
# Backend
uvicorn main:app --reload --port 8000
# Check: http://localhost:8000/docs

# Flutter on device
flutter run
# Verify: OAuth -> home -> map pin -> notification
```

## 12. Release Plan

| Step | Owner | Command / Action | Evidence | Rollback |
|---|---|---|---|---|
| Confirm `.env` complete | | check all required keys present | `.env` review | fix missing keys |
| Confirm `CAMERA_ID` seeded | | `db.cctv_cameras.findOne({})` | ObjectId matches `.env` | re-run `backend/cctv/seed_camera.py` |
| Confirm `VIDEO_SOURCE` removed | | check `.env` | absent or commented | comment out |
| AI Worker offline smoke | | `VIDEO_SOURCE=test.mp4 python main.py` | MongoDB docs verified | fix issue, re-smoke |
| Backend deploy | | `uvicorn` or `docker compose up --build backend` | `/docs` loads | revert code + restart |
| AI Worker deploy | | `docker compose up --build ai_worker` | logs show frame processing | revert code + restart |
| Flutter APK distribute | | `flutter build apk --release` | installed on device | revert APK |
| Post-release smoke | | OAuth -> map -> notification | all screens functional | rollback plan below |
| Monitor logs | | `docker compose logs -f backend ai_worker` | no errors after 15 min | escalate to owner |

## 13. Entry / Exit Criteria By Agent

| Agent | Entry | Exit |
|---|---|---|
| Orchestrator | requirement with business intent | flow, tasks, owners, dependency graph |
| Product Owner | requirement summary | FR-VT-xxx, AC, scope, auth/ownership matrix |
| Data Model | locked FR/AC | collection/contract/seed/index/rollback + AI Worker payload compatibility |
| Backend | contract ready | FastAPI routes/JWT guards/Motor ops/pytest |
| Flutter App | API contract ready | screens/providers/Dio calls/flutter analyze/flutter test |
| AI Worker | internal API payload locked | detector/tracker/main loop/offline smoke with MongoDB evidence |
| Security | implementation summary | findings and pass/pass-with-risk/block decision |
| QA/UAT | implementation + security result | test matrix evidence, MongoDB queries, go/no-go |
| Release/Ops | QA/security sign-off | deploy steps, smoke, rollback plan, monitoring checklist |

## 14. Final Handoff Summary

```txt
Feature:
Status:
Changed files:
FastAPI routes changed:
Flutter screens changed:
AI Worker stages changed:
MongoDB collections affected:
Internal API payload changed (yes/no):
Coordinate convention verified (yes/no):
pytest result:
flutter analyze result:
AI Worker offline smoke result:
Security decision:
QA decision:
Release decision:
Open risks:
Next owner:
```