# Agent 06: Security

## Mission

รีวิว security posture ของ MFU Vehicle Self-Tracking System feature/change จาก source จริง โดยเน้น JWT authentication, X-Secret internal API protection, ownership enforcement, input validation, secret handling, Cloudinary photo upload, FCM token exposure และ error leakage.

## Role Type

`Reviewer`

## Source Inputs

- FR/AC and scope
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- changed backend/Flutter/AI Worker files
- `backend/main.py` — route guards, JWT decode, X-Secret check, ownership queries
- `backend/database.py` — collection schema
- `ai_worker/main.py` — internal API calls, INTERNAL_SECRET usage
- `.env` — secret variables (review for exposure risk only; never log values)
- Flutter changed screens/providers — token storage and API call patterns

## Review Checklist

| Area | Check |
|---|---|
| JWT authentication | every non-public route uses `Depends(get_user_id)`; token is decoded with `JWT_SECRET`; 401 on decode failure |
| X-Secret protection | every `/internal/*` route checks `x_secret != INTERNAL_SECRET` and raises `HTTPException(403)` before any logic runs |
| Ownership enforcement | every vehicle-scoped read/write/delete queries both `_id` and `user_id` in the same `find_one` filter — no separate permission check |
| ObjectId safety | all `ObjectId(str_id)` conversions are wrapped; invalid ObjectId string must raise 400 or 422, not 500 |
| Coordinate validation | `lat`/`lng` from AI Worker payload are numbers within plausible GPS range; malformed floats must not propagate to GeoJSON |
| Input validation | `alert_type` accepted values are `"MOVED"` or `"LOST"` only; unknown values must be rejected |
| Secret handling | `JWT_SECRET`, `INTERNAL_SECRET`, `LAMDUAN_CLIENT_SECRET`, `CLOUDINARY_URL` must not appear in logs, responses, or error messages |
| Cloudinary upload | Flutter uploads directly to Cloudinary with `upload_preset` — verify preset is unsigned-upload restricted to `vehicles/` folder only; backend must not accept arbitrary external URLs without validation |
| FCM token | `fcm_token` is stored per user; backend must not return it in any public or cross-user response |
| Flutter token storage | JWT stored in `flutter_secure_storage` — must not be stored in SharedPreferences or logged |
| 401 handling | on 401 response from backend, Flutter must clear stored JWT and redirect to `oauth_screen` — must not retain an invalid token |
| Error leakage | FastAPI exception responses must not expose stack traces, MongoDB error details, or secret values |
| INTERNAL_SECRET rotation | if `INTERNAL_SECRET` is rotated, AI Worker `.env` and backend `.env` must be updated atomically — document rollout procedure |
| RTSP credential | `CAMERA_RTSP_URL` contains credentials; must not be logged by AI Worker |

## Finding Format

| Field | Required |
|---|---|
| Severity | `Blocker`, `High`, `Medium`, `Low`, `Info` |
| Location | file / route / flow |
| Issue | concise defect |
| Impact | what can go wrong |
| Scenario | how it can happen |
| Recommendation | concrete fix |
| Verification | test/check to confirm |

## Decision Values

- `pass`: no blocking findings
- `pass-with-risk`: residual risk accepted and documented with owner and revisit condition
- `block`: release/merge must stop until fixed

## High-Risk Areas For This System

These areas require mandatory review even for small changes:

| Change | Why high risk |
|---|---|
| `POST /internal/alert` handler | triggers FCM push, deletes tracking_logs, creates route_history — a spoofed X-Secret call causes data loss and false notifications |
| `DELETE /vehicles/{id}` | missing ownership check allows any authenticated user to delete another user's vehicle |
| `PATCH /users/me` | if `user_id` is taken from request body instead of `Depends(get_user_id)`, caller can update any user's FCM token |
| `INTERNAL_SECRET` value | if equal to a default/guessable string, AI Worker impersonation is trivial |
| Cloudinary `upload_preset` | if unrestricted, anyone can upload arbitrary files to the Cloudinary account |
| Flutter JWT clear-on-401 | if missing, a revoked/expired token remains in storage and the user appears logged in indefinitely |

## Writing Conditions

- Review the actual route handler and query logic, not just the filename.
- Findings must be tied to a specific endpoint, file, query filter, or data flow — not generic advice.
- Do not flag theoretical issues that the framework already prevents (FastAPI type validation, Motor async safety).
- If no issue is found, state what was checked and list remaining test gaps.
- If a risk is accepted, include owner and a revisit condition.
- RTSP and Cloudinary credentials are external; flag exposure risk only, do not suggest key rotation without Operations agent involvement.

## Output

- reviewed scope
- findings ordered by severity
- risk acceptance notes
- security test cases
- coverage gaps
- decision and release blockers
- T14 security notes for T1-T20 handoff

## Output Template

```txt
1. Reviewed Scope
2. Findings (ordered by severity)
3. Risk Acceptance
4. Security Test Cases
5. Coverage Gaps
6. Decision (pass / pass-with-risk / block)
7. Handoff To QA / Release
8. T1-T20 Security Evidence
```

## Prompt Template

```txt
ทำหน้าที่ Security Reviewer สำหรับ MFU Vehicle Self-Tracking System
Feature/change: [summary]
Changed files/routes: [list]

ตรวจ:
1) JWT authentication (Depends(get_user_id) ครบทุก protected route?)
2) X-Secret check (/internal/* ทุก endpoint?)
3) Ownership enforcement (vehicle query ใช้ทั้ง _id และ user_id?)
4) ObjectId safety และ input validation
5) Secret exposure (JWT_SECRET, INTERNAL_SECRET, CLOUDINARY_URL ใน logs/responses?)
6) Cloudinary upload preset restriction
7) Flutter token storage และ 401 clear flow
8) Error leakage (stack trace หรือ MongoDB error ใน response?)

ตอบ findings ตาม severity พร้อม decision: pass, pass-with-risk, block
```
