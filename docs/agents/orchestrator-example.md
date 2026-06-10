# Orchestrator Example: AI Worker Snapshot Capture on Alert

## Scenario

Requirement:

เมื่อ AI Worker ตรวจพบว่ารถเคลื่อนที่ (MOVED) หรือหายจากกล้อง (LOST) ให้บันทึก frame ณ ขณะนั้น อัปโหลดไป Cloudinary แล้วส่ง `snapshot_url` พร้อมกับ `POST /internal/alert` เพื่อให้ Flutter แสดงรูปภาพในหน้า notifications_screen.

Source areas:

- AI Worker: `ai_worker/main.py` — alert event handling
- Backend: `backend/api/api.py` — `POST /internal/alert` (รับ `snapshot_url` อยู่แล้ว)
- Flutter: `frontend/lib/screens/notifications_screen.dart` — แสดง snapshot image
- Data Model: `alert_history.snapshot_url` field (มีอยู่แล้ว แต่ปัจจุบัน `""`)
- Security: Cloudinary upload_preset restriction, URL validation
- Workflow: `docs/AI-WORKFLOW.md`
- PRD: `docs/prd/PRD-VehicleTracking.md`

## 1. Requirement Summary

Goal:

- ให้ alert ทุกครั้งมีรูปภาพ frame จากกล้อง ณ จุดเกิดเหตุ เพื่อยืนยันว่ารถเคลื่อนที่จริง

In scope:

- AI Worker captures OpenCV frame at MOVED/LOST event
- AI Worker uploads frame to Cloudinary (via `cloudinary` Python SDK or `requests` multipart)
- `snapshot_url` sent in `POST /internal/alert` payload
- Backend stores URL in `alert_history.snapshot_url` (handler already accepts field — verify no change needed)
- Flutter displays snapshot image in `notifications_screen` notification list item

Out of scope:

- Video recording or multi-frame capture
- Flutter image viewer / zoom screen
- Changing other alert fields or FCM notification body
- HEARTBEAT or PARKED snapshot capture

## 2. Agent Execution Flow

```txt
Orchestrator
  -> Product Owner (FR-VT-007)
  -> Data Model (confirm alert_history.snapshot_url contract, Cloudinary upload pattern)
  -> AI Worker + Backend in parallel (after contract locked)
  -> Flutter (after AI Worker + Backend confirm payload)
  -> Security (Cloudinary preset, URL validation)
  -> QA/UAT
  -> Release/Ops
```

AI Worker and Backend may run in parallel after Data Model confirms:
- `alert_history.snapshot_url` is a Cloudinary `secure_url` string
- Backend `POST /internal/alert` handler needs no change (field already optional)
- Cloudinary upload uses `upload_preset` restricted to `vehicles/` folder

Flutter starts after AI Worker confirms exact URL shape returned from Cloudinary.

## 3. Task List

| Task ID | Task | Owner | Depends On | Output |
|---|---|---|---|---|
| VT-SNAP-001 | Define FR/AC, scope, Cloudinary constraint | Product Owner | Requirement | FR-VT-007 + AC |
| VT-SNAP-002 | Confirm snapshot_url contract, upload preset, backend pass-through | Data Model | VT-SNAP-001 | contract note |
| VT-SNAP-003 | Add frame capture + Cloudinary upload in AI Worker at MOVED/LOST | AI Worker | VT-SNAP-002 | ai_worker/main.py updated |
| VT-SNAP-004 | Verify POST /internal/alert backend handler — no change needed or update | Backend | VT-SNAP-002 | confirmed or updated main.py |
| VT-SNAP-005 | Display snapshot image in notifications_screen | Flutter | VT-SNAP-003, VT-SNAP-004 | notifications_screen updated |
| VT-SNAP-006 | Review Cloudinary preset, URL validation, secret exposure | Security | VT-SNAP-003, VT-SNAP-004 | findings/decision |
| VT-SNAP-007 | Execute AC and regression tests | QA/UAT | VT-SNAP-006 | pass/fail + MongoDB evidence |
| VT-SNAP-008 | Release checklist — .env, Cloudinary SDK in requirements, smoke | Release/Ops | VT-SNAP-007 | release checklist |
| VT-SNAP-009 | Complete T1-T20 and PRD update | Orchestrator | VT-SNAP-007 | final handoff |

## 4. Traceability

| Goal | FR | Internal API | Backend collection | Flutter screen | Test |
|---|---|---|---|---|---|
| Capture snapshot at alert | FR-VT-007 | `POST /internal/alert` + `snapshot_url` field | `alert_history.snapshot_url` | `notifications_screen` | AI Worker offline smoke + Flutter notification display |
| No regression on alerts without snapshot | FR-VT-005 | same endpoint, `snapshot_url` optional | existing `alert_history` docs unaffected | same screen, empty snapshot handled | existing alert regression |

## 5. Dependency Graph

```txt
Requirement
  -> PO: FR/AC + Cloudinary upload constraint
  -> Data Model: snapshot_url field contract + upload_preset decision
  -> AI Worker: frame capture + Cloudinary upload at MOVED/LOST
  -> Backend: POST /internal/alert snapshot_url pass-through (verify or update)
  -> Flutter: image widget in notifications_screen
  -> Security: Cloudinary preset + URL validation review
  -> QA: alert_history.snapshot_url populated + Flutter display + no regression
  -> Release: CLOUDINARY_URL in .env + cloudinary SDK in ai_worker/requirements.txt
```

## 6. Risks And Controls

| Type | Description | Control | Owner |
|---|---|---|---|
| Risk | Cloudinary upload adds latency before `POST /internal/alert` fires | upload async or skip on timeout | AI Worker |
| Risk | Cloudinary upload_preset unrestricted — anyone can upload to account | restrict preset to `vehicles/` folder in Cloudinary dashboard | Security |
| Risk | snapshot_url is an arbitrary external URL in `POST /internal/alert` payload | backend should validate URL is a Cloudinary domain before storing | Backend + Security |
| Risk | existing `alert_history` docs have `snapshot_url: ""` — Flutter must handle empty | Flutter image widget must treat `""` as no image, not a broken image | Flutter |
| Risk | frame captured is dark (night/fog) — low-quality snapshot | add same brightness check before capture; skip snapshot if mean < 60 | AI Worker |
| Decision | `snapshot_url` is optional in internal API payload | keep field optional; backend uses `payload.get("snapshot_url", "")` | Backend |
| Decision | Cloudinary SDK vs raw requests multipart | use `cloudinary` Python SDK if already in requirements; otherwise `requests` multipart | AI Worker |

## 7. Security Review Focus

- Cloudinary `upload_preset` must be restricted to `vehicles/` folder — not unrestricted public upload
- Backend `POST /internal/alert` must validate `snapshot_url` domain is Cloudinary before storing
- `CLOUDINARY_URL` (contains API key and secret) must not appear in logs or error responses
- `snapshot_url` returned in `GET /alerts` — confirm it is only returned to vehicle owner (ownership check already in place)
- X-Secret check in `POST /internal/alert` must fire before any Cloudinary URL is stored

## 8. QA Matrix

| Case | Precondition | Steps | Expected |
|---|---|---|---|
| MOVED alert with snapshot | Vehicle parked, registered, AI Worker running with `.mp4` | AI Worker detects MOVED event | `alert_history.snapshot_url` is a valid Cloudinary URL; Flutter shows image |
| LOST alert with snapshot | Same | AI Worker detects LOST event | Same |
| Missing CLOUDINARY_URL | `CLOUDINARY_URL` absent from `.env` | AI Worker fires alert | Alert still fires without snapshot_url (graceful degradation); `snapshot_url` is `""` |
| Dark frame snapshot | Mean brightness < 60 at alert moment | — | Snapshot skipped; `snapshot_url` is `""` |
| Flutter empty snapshot | `alert_history.snapshot_url == ""` | Open notifications_screen | No broken image shown; placeholder or nothing |
| Ownership: other user's alert | User B requests alerts | `GET /alerts` | User B cannot see User A's alerts or snapshot URLs |
| Regression: PARKED/HEARTBEAT | Normal parking events | AI Worker PARKED/HEARTBEAT | No snapshot triggered; `tracking_logs` unaffected |

## 9. Release Checklist

- `CLOUDINARY_URL` present in `.env` with correct credentials
- `cloudinary` Python package added to `ai_worker/requirements.txt` (or upload via `requests` — confirm approach)
- Cloudinary `upload_preset` configured in Cloudinary dashboard to restrict folder to `vehicles/`
- AI Worker offline smoke: MOVED event fires → Cloudinary URL present in `alert_history.snapshot_url`
- Flutter: `notifications_screen` tested with real snapshot URL and empty string
- Backend: `POST /internal/alert` handler verified to accept optional `snapshot_url`
- Smoke: sign in → trigger mock MOVED → open notifications → snapshot visible
- Rollback: if Cloudinary upload fails, alert must still fire — verify graceful degradation
- PRD update: add snapshot capture to FR-VT-005 and alert_history table
- T1-T20 handoff complete

## 10. Orchestrator Summary Output

```txt
Status: ready for implementation after Data Model confirms snapshot_url contract and Cloudinary upload_preset decision
Parallel allowed: AI Worker + Backend after contract is locked
Flutter starts: after AI Worker confirms Cloudinary secure_url shape
Security gate: required (Cloudinary preset + URL validation)
QA gate: required (MongoDB snapshot_url evidence + Flutter display)
Release gate: required (.env, requirements.txt, Cloudinary dashboard config)
```
