# Activity Properties — Quick Reference

Property names and enum values for `hubspot objects create --type {calls|notes|meetings|tasks}`. Kept here because `hubspot properties list --type calls` is noisy (~80 props) and `hubspot properties get` does not expose enum option values today — so the values below are not otherwise discoverable from the CLI. Verify against the portal if a value is rejected.

## calls

| Property | Type | Notes |
|---|---|---|
| `hs_call_title` | string | |
| `hs_call_body` | string (HTML ok) | |
| `hs_call_direction` | enum | `INBOUND` `OUTBOUND` |
| `hs_call_status` | enum | `BUSY` `CALLING_CRM_USER` `CANCELED` `COMPLETED` `CONNECTING` `FAILED` `IN_PROGRESS` `MISSED` `NO_ANSWER` `QUEUED` `RINGING` |
| `hs_call_duration` | number | Milliseconds (60000 = 1 min) |
| `hs_call_disposition` | string | Portal-defined outcome code |
| `hs_timestamp` | number | **Required.** Unix ms — when the call happened |

## notes

| Property | Type | Notes |
|---|---|---|
| `hs_note_body` | string (HTML ok) | **Required.** |
| `hs_timestamp` | number | **Required.** Unix ms |

## meetings

| Property | Type | Notes |
|---|---|---|
| `hs_meeting_title` | string | |
| `hs_meeting_body` | string (HTML ok) | |
| `hs_meeting_outcome` | enum | `SCHEDULED` `COMPLETED` `RESCHEDULED` `NO_SHOW` `CANCELLED` |
| `hs_meeting_start_time` | number | Unix ms |
| `hs_meeting_end_time` | number | Unix ms |
| `hs_meeting_location` | string | Address or video URL |
| `hs_timestamp` | number | **Required.** Unix ms — primary timeline timestamp |

## tasks

| Property | Type | Notes |
|---|---|---|
| `hs_task_subject` | string | **Required.** Title in the task queue |
| `hs_task_body` | string | |
| `hs_task_status` | enum | `NOT_STARTED` `IN_PROGRESS` `COMPLETED` `DEFERRED` `WAITING` |
| `hs_task_priority` | enum | `LOW` `MEDIUM` `HIGH` |
| `hs_task_type` | enum | `TODO` `CALL` `EMAIL` |
| `hs_timestamp` | number | **Required.** Unix ms — **due date** for tasks |

## Association targets

| Activity | Valid `--to` types |
|---|---|
| calls | contacts, deals, companies, tickets |
| notes | contacts, deals, companies, tickets |
| meetings | contacts, deals, companies |
| tasks | contacts, deals, companies |
