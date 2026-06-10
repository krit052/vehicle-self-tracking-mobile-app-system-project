# MFU Vehicle Self-Tracking System — Agent Operating Model

อัปเดตจาก source repo `vehicle-self-tracking-mobile-app` วันที่ 2026-06-10

เอกสารชุดนี้คือ operating manual สำหรับใช้ agents พัฒนาและดูแล MFU Vehicle Self-Tracking System. ทุก agent ต้องยึด `docs/AI-WORKFLOW.md`, source code ปัจจุบัน, FastAPI routes จริง, Flutter screens จริง, MongoDB collections จริง และ AI Worker pipeline จริง ไม่ใช่ prompt ทั่วไป.

## Source Documents

| Source | Purpose |
|---|---|
| `docs/AI-WORKFLOW.md` | workflow, gates, T1-T20, no-guessing/test/PRD rules |
| `docs/prd/PRD-VehicleTracking.md` | product requirement baseline |
| `SETUP.md` | installation, manual and Docker deployment |
| `Vehicle_tracking_simple.md` | design reference (source code wins on conflict) |
| `backend/api/api.py` | FastAPI route truth |
| `backend/db/database.py` | MongoDB collection schema |
| `backend/cctv/seed_camera.py` | camera seed (run once) |
| `ai_worker/detector.py` | YOLOv11 + ByteTrack + PaddleOCR pipeline |
| `ai_worker/tracker.py` | StationaryTracker state machine |
| `ai_worker/main.py` | AI Worker main loop, homography, color gate, internal API calls |
| `frontend/lib/main.dart` | Flutter navigation truth |
| `frontend/lib/screens/` | Flutter screen files |
| `frontend/pubspec.yaml` | Flutter dependencies |
| `docker-compose.yml` | container services for Docker deploy |
| `.env` | runtime secrets and config (never commit) |

## Agent List

| Agent | File | Type | Primary output |
|---|---|---|---|
| Orchestrator | `agent-00-orchestrator.md` | Control | execution flow, task plan, owners, dependency graph |
| Product Owner | `agent-01-product-owner.md` | Planner | FR-VT-xxx, AC, scope, traceability |
| Data Model | `agent-02-data-model.md` | Planner | collection schema/contract/seed/index/rollback |
| Backend | `agent-03-backend.md` | Implementer | FastAPI routes/guards/Motor ops/pytest |
| Flutter App | `agent-04-frontend.md` | Implementer | screens/providers/Dio calls/widgets/flutter test |
| AI Worker | `agent-05-ai-worker` | Implementer | detector/tracker/main loop/internal API calls/offline smoke |
| Security | `agent-06-security.md` | Reviewer | security findings and pass/pass-with-risk/block |
| QA/UAT | `agent-07-qa-uat.md` | Reviewer | test matrix, MongoDB evidence, defect list |
| Release/Ops | `agent-08-release-ops.md` | Planner | release checklist, .env, Docker, smoke, rollback |

## Default Execution Flow

```txt
User Requirement
  -> Orchestrator
  -> Product Owner
  -> Data Model
  -> Backend + Flutter + AI Worker
  -> Security
  -> QA/UAT
  -> Release/Ops
  -> Production
```

Backend and Flutter may run in parallel only after Product Owner and Data Model have locked:

- route/API contract (`{ lat, lng }` coordinate convention confirmed)
- request/response shape
- MongoDB collection/field impact
- JWT and X-Secret auth scope
- test data assumptions

AI Worker changes must lock the `/internal/*` payload shape before Backend or Flutter parallel work starts.

## When To Call Each Agent

| Work type | Required agents |
|---|---|
| New vehicle tracking feature | Orchestrator, PO, Data Model, Backend, Flutter, AI Worker if detection changes, Security, QA, Release |
| Backend-only route fix | Orchestrator, Backend, Security if JWT/X-Secret/ownership affected, QA |
| Flutter-only UI fix | Orchestrator, Flutter, QA, Security if token storage or coordinate handling touched |
| AI Worker detection/threshold change | Orchestrator, PO, AI Worker, Backend if internal API changes, Security, QA |
| Homography calibration update | Orchestrator, AI Worker, QA (on-site at E1 required) |
| MongoDB schema change | Orchestrator, PO, Data Model, Backend, AI Worker if payload affected, QA, Release |
| Internal API (`/internal/*`) change | Orchestrator, PO, Data Model, AI Worker, Backend, Security, QA |
| `.env` / secret change | Orchestrator, Security, Release |
| Docker / deployment change | Orchestrator, Release |
| Docs only | Orchestrator + reviewer as needed |

## Global Rules For All Agents

- Follow `docs/AI-WORKFLOW.md` before role-specific instructions.
- Use source code as source of truth — `backend/api/api.py` for routes, `ai_worker/` for detection, `frontend/lib/` for screens.
- Do not guess route, collection field, coordinate shape, or behavior from names alone.
- Verify FastAPI route exists in `backend/api/api.py` before implementing a Flutter Dio call.
- Every JWT-protected route must use `Depends(get_user_id)`; every internal route must check `x_secret != INTERNAL_SECRET`.
- Every vehicle-scoped read/write/delete must query both `_id` and `user_id` in the same `find_one` filter.
- Backend returns `{ lat, lng }` to Flutter — never raw GeoJSON. Verify this convention before implementing any location feature.
- AI Worker must be tested with `VIDEO_SOURCE=test_footage.mp4` before connecting to live RTSP.
- Preserve existing route/request/response behavior unless the FR explicitly changes it.
- Keep handoffs evidence-based: file path, endpoint, collection field, screen name, test command, risk.
- Separate `decision`, `assumption`, `risk`, `blocker`, and `open question`.
- Do not turn agent output into vague advice — every output must be executable by the next role.
- Use T1-T20 format for change docs and handoffs.
- Update `docs/prd/PRD-NewSystem.md` when behavior, API, screen, collection, AI Worker parameter, or release contract changes.
- Run scoped tests/verification before marking implementation done.

## System Source Map For Agents

| Domain | Backend source | AI Worker source | Flutter source |
|---|---|---|---|
| Auth / JWT | `backend/api/api.py` — `POST /auth/login`, `get_user_id` | — | `login_screen.dart`, `oauth_screen.dart` |
| User settings / FCM | `backend/api/api.py` — `PATCH /users/me` | — | `home_screen.dart` (on app open) |
| Vehicle CRUD | `backend/api/api.py` — `/vehicles` routes | `main.py` — `find_vehicle()`, color gate | `vehicle_profile_screen.dart`, `add_vehicle_screen.dart`, `edit_vehicle_screen.dart` |
| Live location / map | `backend/api/api.py` — `GET /vehicles/{id}/location` | `main.py` — `POST /internal/parked`, homography | `live_tracking_screen.dart` |
| Route history / polyline | `backend/api/api.py` — `GET /vehicles/{id}/routes*` | `main.py` — `POST /internal/alert` bundles tracking_logs | `route_history_screen.dart`, `route_detail_screen.dart` |
| Alerts / FCM push | `backend/api/api.py` — `GET /alerts`, `POST /internal/alert` | `main.py` — MOVED/LOST events | `notifications_screen.dart` |
| AI detection pipeline | `backend/api/api.py` — `/internal/*` handlers | `detector.py`, `tracker.py`, `main.py` | — |
| Camera registry | `backend/api/api.py` — `GET /cameras`, `seed_camera.py` | `main.py` — `CAMERA_ID` env var | — |
| Deploy / ops | `backend/Dockerfile`, `docker-compose.yml` | `ai_worker/Dockerfile` | `frontend/pubspec.yaml`, APK build |

## Shared Handoff Contract

Every handoff must include:

1. Scope reference: goal, FR-VT-xxx, module, source files, assumptions
2. Contract: FastAPI route, screen, collection field, `{ lat, lng }` convention, auth type
3. Decisions: what has been locked and why (especially internal API payload shape)
4. Dependencies: upstream artifacts, seed, `.env` keys, AI model file, test data
5. Risks and gaps: security, coordinate convention, AI Worker offline-only test, Cloudinary URL, FCM delivery
6. Evidence: code refs, collection field names, test commands, MongoDB query results
7. Next owner: who can act next and what ready condition they need

## Definition Of Ready

A task is ready for implementation only when it has:

- clear FR-VT-xxx and AC
- source area and files identified (route, collection, screen, AI Worker stage)
- API/internal API contract locked
- auth scope confirmed (JWT / X-Secret / public)
- coordinate convention confirmed for location features
- seed/`.env` dependencies identified
- test plan (including AI Worker offline smoke if applicable)
- release/rollback impact if relevant
- source evidence recorded in T1-T4

## Definition Of Done

A task is done only when it has:

- implementation or doc change complete
- `pytest` / `flutter analyze` / AI Worker offline smoke run — or explicit reason not run
- security and ownership impact reviewed
- docs updated when behavior/contract/collection/threshold changes
- release notes and rollback steps when production behavior changes
- T1-T20 handoff completed

## Working Assets

- `../AI-WORKFLOW.md` — master AI workflow and gates
- `../templates/T1-T20-change-document.md` — required change documentation template
- `orchestrator-example.md` — end-to-end example: AI Worker snapshot capture on alert
- `sprint-task-template.md` — reusable task/sprint/handoff template

## Quick Prompt

```txt
ทำงานตาม MFU Vehicle Self-Tracking System agent workflow
Requirement: [describe request]
Source docs:
- docs/AI-WORKFLOW.md
- docs/prd/PRD-NewSystem.md
- docs/agents/README.md
- backend/api/api.py
- backend/db/database.py
- ai_worker/main.py
- frontend/lib/main.dart

เริ่มที่ Orchestrator แล้วส่งต่อ agent ที่จำเป็น
ต้องระบุ route, collection, screen, internal API payload, coordinate convention, test, release impact และ evidence จาก source
```