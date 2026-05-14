# Activity Properties Reference

Complete property reference for all four activity object types. Use with `hubspot objects create --type <type>`.

---

## Calls (`--type calls`)

| Property | Type | Required | Notes |
|---|---|---|---|
| hs_call_title | string | No | Display name for the call |
| hs_call_body | string | No | Call notes / summary |
| hs_call_duration | number | No | Duration in **milliseconds** — 60000 = 1 min, 3600000 = 1 hr |
| hs_call_direction | enumeration | No | `INBOUND` or `OUTBOUND` |
| hs_call_status | enumeration | No | See enum values below |
| hs_call_disposition | string | No | Outcome code — portal-specific, configure in HubSpot settings |
| hs_timestamp | number | Yes | Unix timestamp in **milliseconds** — required for timeline placement |

**hs_call_status enum values:**
`BUSY` `CALLING_CRM_USER` `CANCELED` `COMPLETED` `CONNECTING` `FAILED` `IN_PROGRESS` `MISSED` `NO_ANSWER` `QUEUED` `RINGING`

The most common value for a completed outbound call: `COMPLETED`.

---

## Notes (`--type notes`)

| Property | Type | Required | Notes |
|---|---|---|---|
| hs_note_body | string | Yes | Note content — HTML tags are supported (e.g., `<b>`, `<ul>`, `<li>`) |
| hs_timestamp | number | Yes | Unix timestamp in **milliseconds** — sets the note's date on the timeline |

Notes are the simplest activity type. They have no enum fields.

---

## Meetings (`--type meetings`)

| Property | Type | Required | Notes |
|---|---|---|---|
| hs_meeting_title | string | No | Meeting name |
| hs_meeting_body | string | No | Meeting notes / agenda |
| hs_meeting_start_time | number | No | Unix timestamp in **milliseconds** |
| hs_meeting_end_time | number | No | Unix timestamp in **milliseconds** |
| hs_meeting_outcome | enumeration | No | See enum values below |
| hs_meeting_location | string | No | Physical address or video call URL |
| hs_timestamp | number | Yes | Unix timestamp in **milliseconds** — used as the primary timeline timestamp |

**hs_meeting_outcome enum values:**
`SCHEDULED` `COMPLETED` `RESCHEDULED` `NO_SHOW` `CANCELLED`

---

## Tasks (`--type tasks`)

| Property | Type | Required | Notes |
|---|---|---|---|
| hs_task_subject | string | Yes | Task title — displayed in the CRM task queue |
| hs_task_body | string | No | Task notes / instructions |
| hs_task_status | enumeration | No | See enum values below |
| hs_task_priority | enumeration | No | `LOW` `MEDIUM` `HIGH` |
| hs_task_type | enumeration | No | `TODO` `CALL` `EMAIL` |
| hs_timestamp | number | Yes | **Due date** as Unix timestamp in **milliseconds** |

**hs_task_status enum values:**
`NOT_STARTED` `IN_PROGRESS` `COMPLETED` `DEFERRED` `WAITING`

**hs_task_type usage:**
- `CALL` — shows a phone icon, surfaces in call queues
- `EMAIL` — shows an email icon, links to compose if contact email is set
- `TODO` — generic task

---

## Timestamp Reference

All activity timestamps are Unix time in **milliseconds** (not seconds).

```bash
# Current time in milliseconds

# macOS (no %3N support — append 000 to seconds)
NOW_MS=$(date +%s)000

# Linux (native millisecond support)
NOW_MS=$(date +%s%3N)

# Verify: should be a 13-digit number
echo $NOW_MS
```

**Compute a future due date (e.g., 7 days from now):**

```bash
# macOS — 7 days from now in milliseconds
DUE_MS=$(( $(date -v+7d +%s) * 1000 ))

# Linux — 7 days from now in milliseconds
DUE_MS=$(( $(date -d '7 days' +%s) * 1000 ))
```

**Convert a specific date/time to milliseconds:**

```bash
# macOS — specific date
DUE_MS=$(( $(date -j -f "%Y-%m-%d" "2025-06-30" +%s) * 1000 ))

# Linux — specific date
DUE_MS=$(( $(date -d "2025-06-30" +%s) * 1000 ))
```

**Common duration values for hs_call_duration:**

| Duration | Milliseconds |
|---|---|
| 1 minute | 60000 |
| 5 minutes | 300000 |
| 15 minutes | 900000 |
| 30 minutes | 1800000 |
| 1 hour | 3600000 |

---

## Association Targets

After creating any activity, associate it immediately. Unassociated activities are invisible in the CRM.

| Activity type | Associate to |
|---|---|
| calls | contacts, deals, companies, tickets |
| notes | contacts, deals, companies, tickets |
| meetings | contacts, deals, companies |
| tasks | contacts, deals, companies |

```bash
hubspot associations create --from <type>:<activity_id> --to <target_type>:<target_id>
```
