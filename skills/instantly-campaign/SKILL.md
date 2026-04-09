---
name: instantly-campaign
description: Use when launching a cold email sequence on Instantly.ai, loading leads into an Instantly campaign, connecting an Instantly account, or running the final stage of a cold-email pipeline that hands off to Instantly's v2 REST API.
---

# Instantly Campaign Setup

## Overview

One-shot campaign creation against the Instantly v2 REST API. Always create the campaign paused so a human can review before sending. Watch out for two non-obvious quirks: the timezone enum (Instantly rejects some standard IANA names and `America/Dawson` does NOT follow Pacific DST), and the ampersand body bug (Instantly silently drops any email body containing `&`).

## When to use

- User wants to launch an email sequence on Instantly.ai
- User wants leads bulk-loaded into an existing or new Instantly campaign
- Downstream of `cold-email-sequence` once copy is approved
- Final stage of `linkedin-comment-to-outreach` or `linkedin-reaction-to-outreach`
- User says "set up on instantly", "create instantly campaign", "load into instantly", "instantly sequence", or "send from instantly"

## When NOT to use

- NOT for warm-up management or mailbox warming workflows
- NOT for transactional or one-off emails (use Gmail/SMTP instead)
- NOT when the campaign already exists and only needs leads added — call the leads endpoint directly
- NOT for editing live campaigns mid-send (pause first, then patch)

## Prerequisites

- *One of these two credential paths* (resolved automatically at runtime — see "Credential Resolution" below):
  - *Direct:* `INSTANTLY_API_KEY` env var set (see `../SETUP.md` for how to retrieve it from the Instantly dashboard: Settings > Integrations > API), OR
  - *Composio:* Composio.dev MCP installed with the `instantly` toolkit connected
- Paid Instantly plan (free tier does not expose v2 API)
- Email sequence copy ready (output of `cold-email-sequence` skill, or supplied by user)
- Lead data with verified emails (output of `apollo-enrichment` skill, or CSV)
- At least one connected sending account inside Instantly

## Quick Reference

- *API base URL*: `https://api.instantly.ai/api/v2`
- *Auth header*: `Authorization: Bearer {API_KEY}`
- *Required env var*: `INSTANTLY_API_KEY`
- *Critical gotchas*: timezone enum quirk (use `America/Vancouver` for Pacific, NOT `America/Dawson`); ampersand body bug (replace all `&` before POST)
- *Default schedule*: Mon-Fri, 08:00-17:00, 50 leads/day, 5 min gap, paused on creation

## API Basics

- Base URL: `https://api.instantly.ai/api/v2`
- Auth: `Authorization: Bearer {API_KEY}`
- Content-Type: `application/json`
- Use v2 ONLY. v1 returns `ERR_AUTH_FAILED` with v2 keys.

## Credential Resolution (Run This BEFORE Step 1)

Before touching any Instantly endpoint, resolve which credential path to use. This is a hard gate — do not proceed to Step 1 until one of these paths is live.

*Decision tree:*

1. *Check for direct API key.* Is `INSTANTLY_API_KEY` set in the environment?
   - *Yes* → use the *Direct Path*. Jump to "The Workflow" below (Step 1).
   - *No* → continue to step 2.

2. *Check for Composio MCP.* Is the `mcp__composio__COMPOSIO_SEARCH_TOOLS` tool available in this session?
   - *No* → jump to step 5 (last-resort chat paste).
   - *Yes* → continue to step 3.

3. *Check if the Instantly toolkit is already connected in Composio.* Call `mcp__composio__COMPOSIO_SEARCH_TOOLS` with `use_case: "create a cold email campaign in Instantly and bulk-add leads"` and `session: { generate_id: true }`. Save the `session_id`. Inspect the response for the `instantly` toolkit connection status.
   - *Active* → use the *Composio Path*. Jump to "Composio Path (Alternative to Direct API Key)" below.
   - *Not connected* / *401 on test call* → continue to step 4.

4. *Prompt the user to connect Instantly via Composio.* Call `mcp__composio__COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["instantly"]` (add `reinitiate_all: true` if the connection exists but is stale). Take the `redirect_url` from the response and surface it to the user as a clickable link:
   > "Composio is installed but the Instantly toolkit isn't connected. Click here to authorize it: `{redirect_url}`. I'll wait and pick up automatically once you're done. If you'd rather not use Composio, tell me and I'll take the API key directly in chat as a last resort."
   Then poll `mcp__composio__COMPOSIO_WAIT_FOR_CONNECTIONS` until the connection goes Active. Once Active, proceed down the *Composio Path*. If the user explicitly declines Composio, jump to step 5.

5. *Last resort — accept the API key in chat.* Only reach this step when no env var is set AND (Composio is unavailable OR the user refused Composio). Ask the user:
   > "Both automated paths are off the table. As a last resort, paste your Instantly v2 API key here and I'll use it just for this session. Two things to know: (1) the key will live in the chat transcript for this conversation — rotate it at https://app.instantly.ai/app/settings/integrations/api-keys when we're done if you care about that, (2) I won't write it to disk or any env file. Paste it now or tell me to stop."
   Once pasted:
   - Hold the key in memory only for the lifetime of this session. Substitute it wherever `{API_KEY}` appears in the Direct Path `curl` calls.
   - Do NOT write the key to `.env`, `mcp-servers.json`, `.astronaut-state/`, or any file on disk.
   - Do NOT echo the key back to the user in any response — refer to it as `{API_KEY}` or `[redacted]`.
   - If the user refuses, STOP and tell them exactly what's missing with no further retries until they come back with a credential.

*Rules:*

- NEVER fall back silently. If no credential path is live, tell the user exactly what's missing and what their options are.
- Env var and Composio are preferred over chat-paste. Chat-paste is LAST RESORT only — never offer it in step 2 or 3 unless Composio is actually unreachable.
- When the user pastes a key, treat it as ephemeral session-only credential. No disk writes. No re-echoing in responses.
- Cache the resolution for the duration of the session. Don't re-check on every step.

## The Workflow

### Step 1: Verify API Key and List Accounts

```bash
curl -s -X GET "https://api.instantly.ai/api/v2/accounts" \
  -H "Authorization: Bearer {API_KEY}"
```

Returns connected email accounts. Save for `email_list`.

### Step 2: Create the Campaign

```bash
POST /api/v2/campaigns
```

```json
{
  "name": "Campaign Name",
  "campaign_schedule": {
    "schedules": [{
      "name": "Weekday Schedule",
      "timing": { "from": "08:00", "to": "17:00" },
      "days": { "0": true, "1": true, "2": true, "3": true, "4": true, "5": false, "6": false },
      "timezone": "America/Vancouver"
    }]
  },
  "sequences": [{
    "steps": [
      { "type": "email", "delay": 0, "delay_unit": "days",
        "variants": [{ "subject": "subject line", "body": "Email 1" }] },
      { "type": "email", "delay": 3, "delay_unit": "days",
        "variants": [{ "subject": "", "body": "Email 2" }] },
      { "type": "email", "delay": 4, "delay_unit": "days",
        "variants": [{ "subject": "", "body": "Email 3" }] }
    ]
  }],
  "email_list": ["sender@domain.com"],
  "stop_on_reply": true,
  "text_only": true,
  "link_tracking": false,
  "open_tracking": true,
  "daily_limit": 50,
  "daily_max_leads": 50,
  "email_gap": 5,
  "random_wait_max": 10
}
```

*Timezone enum* — Instantly's API rejects some standard IANA names. Known-working substitutes:

- *Pacific*: try `America/Vancouver` or `America/Tijuana` first (both Pacific w/ DST, behave identically to `America/Los_Angeles`). If rejected, fall back to `America/Dawson`. WARNING: `America/Dawson` is Yukon and observes permanent MST since 2020 — it does NOT follow US Pacific DST. During Pacific DST (March-Nov), a campaign scheduled "9 AM" will actually send at 10 AM Pacific. Accept this only if DST drift is tolerable.
- *Eastern*: use `America/Detroit` (observes Eastern DST normally, safe substitute for `America/New_York`)
- *Central*: `America/Chicago` (works as-is)
- *Mountain*: `America/Boise` (works as-is)
- Verify accepted values against current Instantly API docs before launching a live campaign.

*Ampersand body bug* — Instantly SILENTLY DROPS any body containing `&`. Returns empty string `""` with no error. Replace ALL ampersands before sending:

- `P&L` -> `P+L` or `Profit and Loss`
- `X & Y` -> `X and Y`

*Delay logic* — Relative to previous step:

- Email 1 (Day 0): delay 0
- Email 2 (Day 3): delay 3
- Email 3 (Day 7): delay 4 (3 + 4 = 7)

*Other rules*:

- Follow-up subjects: empty string `""` for same-thread replies
- `sequences` array: only first element used; put all steps in one object
- Variables: `{{firstName}}`, `{{lastName}}`, `{{companyName}}`, `{{email}}`

### Step 3: Verify Campaign

Check response:

- `id` — save Campaign UUID
- All step bodies non-empty (ampersand check)
- `email_list` has all accounts
- `status: 0` (paused)

If body is empty, PATCH or delete and recreate.

### Step 4: Bulk Load Leads

```bash
POST /api/v2/leads/add
```

```json
{
  "campaign_id": "UUID",
  "leads": [
    { "email": "j@co.com", "first_name": "Jane", "last_name": "Smith", "company_name": "Co" }
  ],
  "skip_if_in_workspace": false,
  "verify_leads_on_import": false
}
```

- Max 1000 leads per call
- Check: `leads_uploaded`, `invalid_email_count`, `remaining_in_plan`

### Step 5: Add All Sending Accounts

```bash
PATCH /api/v2/campaigns/{id}
Body: { "email_list": ["email1@...", "email2@...", "email3@..."] }
```

Instantly rotates across all accounts automatically.

### Step 6: Leave Paused for Review

NEVER auto-activate. Campaign starts paused (status 0).

Tell user:

- Campaign ready for review
- N leads loaded
- Sending accounts configured
- "Say the word and I'll activate"

Activate when approved:

```bash
POST /api/v2/campaigns/{id}/activate
```

## Recommended Settings

- `text_only`: `true` — feels personal
- `link_tracking`: `false` — hurts deliverability
- `open_tracking`: `true` — useful, low impact
- `stop_on_reply`: `true` — don't email responders
- `daily_limit`: `50` — conservative start
- `email_gap`: `5` — 5 min between sends
- `random_wait_max`: `10` — looks human

## Composio Path (Alternative to Direct API Key)

When Credential Resolution routes you here, every step in "The Workflow" above still runs — you just execute each REST call via a Composio tool slug instead of `curl`. Composio holds the Instantly API credential server-side so no env var is needed on this side.

*How to run a step:*

Call `mcp__composio__COMPOSIO_MULTI_EXECUTE_TOOL` with the `session_id` from the discovery call, the matching slug, and the same JSON body you would have sent to the REST endpoint. Responses come back in the same shape Instantly returns over REST.

*Tool slug equivalents:*

- `GET /api/v2/accounts` -> `INSTANTLY_LIST_ACCOUNTS`
- `POST /api/v2/campaigns` -> `INSTANTLY_CREATE_CAMPAIGN`
- `GET /api/v2/campaigns/{id}` -> `INSTANTLY_GET_CAMPAIGN`
- `PATCH /api/v2/campaigns/{id}` -> `INSTANTLY_UPDATE_CAMPAIGN`
- `POST /api/v2/leads/add` -> `INSTANTLY_ADD_LEADS_BULK`
- `POST /api/v2/campaigns/{id}/activate` -> `INSTANTLY_ACTIVATE_CAMPAIGN`
- `GET /api/v2/campaigns/{id}/sending_status` -> `INSTANTLY_GET_CAMPAIGN_SENDING_STATUS`

*Runtime 401 recovery:* If a Composio tool call returns 401 mid-workflow (token expired, key rotated), jump back to Credential Resolution step 4 — call `COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["instantly"]` and `reinitiate_all: true`, surface the new `redirect_url`, wait for re-auth, then retry the failed step.

*Identical gotchas:* Both the timezone enum quirk and the ampersand body bug live inside Instantly's API itself, not in the transport. Sanitize all `&` characters and use `America/Vancouver` for Pacific regardless of which path you call.

*Pause-by-default still applies:* `INSTANTLY_CREATE_CAMPAIGN` returns `status: 0` (paused) just like the direct REST path. Never auto-call `INSTANTLY_ACTIVATE_CAMPAIGN` without explicit user approval.

## Common Mistakes

- *Empty body after creation* — `&` in text. Remove all ampersands.
- *Timezone rejected* — use allowed IANA values from the list above.
- *v1 API auth fails* — use `/api/v2/` only.
- *Follow-ups not threading* — subject must be `""` on follow-up steps.
- *PATCH does not fix body* — delete and recreate the campaign.
- *Using `America/Dawson` for Pacific year-round* — drifts 1 hour during DST. Use `America/Vancouver` instead.
- *Auto-activating after creation* — always leave paused for human review.

## Example

User asks: "Launch the Series A founders sequence on Instantly with these 200 leads."

1. Verify accounts: `GET /api/v2/accounts` returns 3 connected mailboxes.
2. Sanitize copy: scan all 3 email bodies for `&` and replace (`R&D` -> `R and D`).
3. Create campaign with the payload above, substituting:
   - `name`: `"Series A Founders — April 2026"`
   - `email_list`: the 3 sender addresses from step 1
   - `body` for Email 1: `"Hey {{firstName}}, saw {{companyName}} just closed your Series A..."`
   - `subject`: `"quick question, {{firstName}}"`
   - `timezone`: `"America/Vancouver"` (Pacific with proper DST)
4. Response returns campaign UUID `abc-123`. Verify all 3 step bodies are non-empty.
5. Bulk load: `POST /api/v2/leads/add` with `campaign_id: "abc-123"` and the 200-lead array. Check `leads_uploaded: 200`.
6. PATCH campaign to attach all 3 sender accounts.
7. Report back: "Campaign abc-123 created, paused, 200 leads loaded across 3 senders. Say the word and I will activate."

## Output

- Campaign created and paused on Instantly
- All leads loaded
- All sending accounts attached
- Campaign ID saved for activation
