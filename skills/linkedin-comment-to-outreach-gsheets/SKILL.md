---
name: linkedin-comment-to-outreach-gsheets
description: Use when the user provides a LinkedIn post URL and wants to run the full pipeline from commenters to a live cold outreach campaign on Instantly, storing leads in Google Sheets instead of Airtable. Triggers on phrases like "linkedin comment to outreach gsheets", "scrape and email with sheets", "linkedin pipeline google sheets", or any request combining LinkedIn post scraping with cold email outreach where Google Sheets is the storage layer. Also use when the user explicitly asks for the Google Sheets version of the linkedin-to-outreach pipeline.
---

# LinkedIn Comment to Outreach Pipeline (Google Sheets)

## Overview

End-to-end orchestrator: LinkedIn post URL in, paused Instantly cold email campaign out. Leads are stored in Google Sheets (not Airtable), enriched via Apollo + Hunter.io fallback, sequenced, and loaded into Instantly. Every external tool call goes through Composio first when available. Every phase maximizes parallelism to finish faster without cutting corners.

One key difference from the Airtable version: Google Sheets can write hundreds of rows in a single API call, so Phase 2 collapses from "4 parallel batch-loading agents" to one bulk write. That time savings compounds.

Another difference: when total enrichment (Apollo + Hunter.io) returns fewer than 20 leads with verified emails, the sequence-writing phase runs on autopilot -- no interactive review, just write all 3 emails and move straight to Instantly. For 20+ leads, the user co-writes each email as usual.

**Hunter.io fallback:** After Apollo enrichment, contacts that matched a person but have no email are sent to Hunter.io's Email Finder in parallel (8 concurrent threads). This typically recovers 10-20% of the missing emails, boosting total email coverage by 5-15 percentage points. Only contacts with company info are searched -- Hunter requires a company or domain to work.

## When to use

- User provides a LinkedIn post URL and wants to reach out to its commenters via Google Sheets
- User asks to "run the linkedin pipeline with sheets", "scrape and email", or "linkedin comment to outreach gsheets"
- User wants the complete path from a LinkedIn post to a live Instantly campaign, stored in Google Sheets
- User needs commenters scraped, stored in Sheets, enriched with Apollo, sequenced, and loaded into Instantly in one flow

## When NOT to use

- Targeting people who *reacted* to a post (use `linkedin-reaction-to-outreach` instead)
- User specifically wants Airtable (use `linkedin-comment-to-outreach` instead)
- Just scraping commenters with no outreach (use `linkedin-comment-scraper` directly)
- Just enriching an existing list (use `apollo-enrichment` directly)
- Just writing a cold email sequence without a lead source (use `cold-email-sequence` directly)
- Just creating an Instantly campaign from leads you already have (use `instantly-campaign` directly)

## Prerequisites

- **Composio toolkits connected:** `googlesheets`, `apollo`, `hunter`, `instantly`
- **Apify MCP server:** Connected with `mcp__apify__*` tools available (Composio fallback: `APIFY_RUN_ACTOR_SYNC`)
- **User input needed for Phase 4 (if 20+ leads):** Social proof, product description, CTA preferences, sender name

Before starting, verify each Composio toolkit is connected. If any is missing, use `composio link <toolkit> --no-wait` and present the redirect URL to the user. Do all missing connections in parallel -- don't chain them sequentially.

## Core Principles

### 1. Composio First

For every external tool call, try the Composio tool slug first. Fall back to MCP or direct API only if Composio fails or the toolkit isn't connected. This applies universally:

| Service | Composio slug (primary) | Fallback |
|---------|------------------------|----------|
| Apify | `APIFY_RUN_ACTOR_SYNC` | `mcp__apify__call-actor` |
| Google Sheets | `GOOGLESHEETS_*` (see slug table below) | None -- Sheets IS the chosen platform |
| Apollo | `APOLLO_PEOPLE_ENRICHMENT` (parallel single calls) | `APOLLO_BULK_PEOPLE_ENRICHMENT` (less reliable) |
| Hunter.io | `HUNTER_EMAIL_FINDER` (parallel single calls) | None -- Hunter IS the fallback |
| Instantly | `INSTANTLY_*` (see slug table below) | Direct REST API via curl |

### 2. Maximum Parallelism

Within every phase, run independent operations concurrently. Between phases, pre-fetch data for the next phase whenever possible. Specific opportunities are called out in each phase below.

### 3. Auto-Mode for Small Lists

If Apollo enrichment returns fewer than 20 leads with verified emails, skip the interactive email-writing review. Write all 3 emails using the James Shields framework and the context gathered in Phase 1, then proceed directly to Instantly. The user reviews the final campaign in Instantly's dashboard instead of approving each email in chat.

## The Pipeline

```
LinkedIn Post URL
       |
       v
[Phase 1: SCRAPE]           -- Apify via MCP or Composio, deduplicate
       |
       v
[Phase 2: STORE]            -- Create Google Sheet, bulk write all rows
       |
       v
[Phase 3: ENRICH (Apollo)]  -- Apollo parallel single enrichment, batch-update Sheet
       |                       (pre-fetch Instantly accounts here)
       v
[Phase 3.5: ENRICH (Hunter)]-- Hunter.io fallback for contacts Apollo missed emails on
       |                       (parallel single calls, 8 threads, update Sheet)
       v
[Phase 4: WRITE]            -- Co-write 3 emails (or auto-write if <20 leads)
       |
       v
[Phase 5: LAUNCH]           -- Create Instantly campaign, load leads, leave paused
       |
       v
Campaign ready for review (paused)
```

---

## Phase 1: Scrape

Uses the same logic as `linkedin-comment-scraper`. MCP Apify tools are preferred here because they handle async polling and large result sets better than the Composio sync actor runner.

### Parallel block A (run together):
- Validate the LinkedIn post URL format
- Discover Apify actor details (`mcp__apify__fetch-actor-details` for `harvestapi/linkedin-post-comments`)

### CRITICAL: Apify field names

The actor input uses `posts` (NOT `urls`) as the field name. The actor output uses different field names than what you might expect. Always map them:

| Actor returns | We normalize to |
|---------------|----------------|
| `name` | `fullName` |
| `position` | `headline` |
| `linkedinUrl` | `profileUrl` |
| `comment` | `comment` (same) |
| `companyName` | `companyName` (same, but often null -- extract from `position`) |
| `reactions` | `reactions` (same) |

### Then: Test scrape
Run a test scrape with `maxItems: 20` to validate the URL works and confirm the data shape.

```
MCP (preferred): mcp__apify__call-actor
  actor: "harvestapi/linkedin-post-comments"
  input: { "posts": ["THE_URL"], "maxItems": 20 }

Composio fallback: composio execute APIFY_RUN_ACTOR_SYNC -d '{
  "actor_id": "harvestapi/linkedin-post-comments",
  "input": { "posts": ["THE_URL"], "maxItems": 20 }
}'
```

Verify output has data and check which field names the actor is returning (map according to the table above).

### Then: Full scrape
Once test passes, immediately run the full scrape with `maxItems: 1000`. Do not treat the test count as the final number.

### Then: Process
1. Map actor field names to normalized names (see table above)
2. Extract `companyName` from `position`/`headline` when null (look for " at ", " @ ", " en " patterns)
3. Remove entries with null/empty `profileUrl` (deleted accounts)
4. Deduplicate by `profileUrl`
5. Save to `./output/linkedin_commenters.json` using the normalized field names

**Checkpoint:** "Scraped X unique commenters from [Author]'s post. Moving to Google Sheets."

---

## Phase 2: Store to Google Sheets

Google Sheets can write hundreds of rows in a single API call -- no batching, no parallel agents needed. This phase should take under 30 seconds for typical scrapes.

### Step 1: Create a new spreadsheet

```
composio execute GOOGLESHEETS_CREATE_GOOGLE_SHEET1 -d '{
  "title": "LinkedIn Commenters - [Author Name]"
}'
```

Save the returned `spreadsheet_id` and `spreadsheet_url`.

### Step 1.5: Discover the actual tab name

Newly created Google Sheets use locale-dependent default tab names: "Sheet1" (English), "Hoja 1" (Spanish), "Feuille 1" (French), etc. You MUST discover the actual name before writing data.

```
composio execute GOOGLESHEETS_GET_SHEET_NAMES -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}"
}'
```

Save the first sheet name (e.g. "Hoja 1") and use it in ALL subsequent range references instead of hardcoding "Sheet1". This is the #1 cause of "range not found" errors.

### Step 2: Write headers + all data in one call

Build a 2D array: row 0 is headers, rows 1-N are the data.

Headers (15 columns):
```
Full Name | Comment | LinkedIn Profile URL | Headline | Company | Job Title | Source Post URL | Scraped Date | Reactions | Lead Status | Email | Phone | City | State | Country
```

Map each record from `./output/linkedin_commenters.json`:
- `Full Name` = `fullName`
- `Comment` = `comment`
- `LinkedIn Profile URL` = `profileUrl`
- `Headline` = `headline`
- `Company` = `companyName`
- `Source Post URL` = the original LinkedIn post URL
- `Scraped Date` = today's date (YYYY-MM-DD)
- `Reactions` = `reactions` (default 0)
- `Lead Status` = "New"
- Leave `Job Title`, `Email`, `Phone`, `City`, `State`, `Country` empty (enrichment fills these)

**CRITICAL Composio field name:** This endpoint uses **snake_case** `value_input_option`, NOT camelCase.

```
composio execute GOOGLESHEETS_VALUES_UPDATE -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}",
  "range": "{TAB_NAME}!A1:O{ROW_COUNT+1}",
  "values": [[headers], [row1], [row2], ...],
  "value_input_option": "RAW"
}'
```

The `values` parameter MUST be a native JSON array (2D array of arrays), NOT a JSON string. Example:
```json
"values": [["Full Name", "Comment", ...], ["Jane Doe", "Great post!", ...]]
```

### Step 3: Verify

```
composio execute GOOGLESHEETS_VALUES_GET -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}",
  "range": "{TAB_NAME}!A1:O5"
}'
```

Confirm row count matches expected. Save `{SPREADSHEET_ID}` and `{TAB_NAME}` for Phase 3.

**Checkpoint:** "Loaded X records into Google Sheets. Starting Apollo enrichment."

Share the spreadsheet URL with the user so they can follow along.

---

## Phase 3: Enrich

Use parallel single Apollo enrichment calls (NOT bulk endpoint). The bulk endpoint (`APOLLO_BULK_PEOPLE_ENRICHMENT`) has proven unreliable when run in parallel -- it returns 0 matches for most batches. Single enrichment (`APOLLO_PEOPLE_ENRICHMENT`) at 8 concurrent threads gives 90-95% person match rates.

### Step 1: Read all rows from Google Sheets

```
composio execute GOOGLESHEETS_VALUES_GET -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}",
  "range": "{TAB_NAME}!A2:O{LAST_ROW}"
}'
```

Parse into records with row numbers (needed for targeted updates later).

### Parallel block B (run together):
- **Pre-fetch Instantly accounts** -- `composio execute INSTANTLY_LIST_ACCOUNTS`. Save the result for Phase 5. This runs during enrichment so it's ready when we need it.
- **Optionally check Apollo credit headroom** -- `composio execute APOLLO_VIEW_API_USAGE_STATS`

### Step 2: Run parallel single Apollo enrichment

For each person, call `APOLLO_PEOPLE_ENRICHMENT` individually. Run up to 8 calls concurrently using background agents or threaded execution.

Build each call:
```
composio execute APOLLO_PEOPLE_ENRICHMENT -d '{
  "first_name": "Firstname",
  "last_name": "Lastname",
  "organization_name": "Company",
  "linkedin_url": "https://www.linkedin.com/in/username"
}'
```

**Important field names for single endpoint:**
- Use `organization_name` (NOT `company_name` -- that's the bulk endpoint's field)
- Do NOT set `reveal_phone_number: true` -- it requires a `webhook_url` and will error without one

Name splitting: split `fullName` on the FIRST space only. "Jane Smith, CPA" becomes first: "Jane", last: "Smith, CPA".

**Why single over bulk:** In live testing, the bulk endpoint returned 0 matches for most parallel batches (likely rate-limited or session-conflicted), while single endpoint with 8 concurrent threads returned 95% person match and 61% email match on 103 LATAM contacts. The single approach is both more reliable and gives better visibility into per-person results.

Expected match rates:
- Person match: 85-95%
- Email found: 50-70% (US/EU), 40-60% (LATAM/emerging markets)
- A 30-50% no-email rate is normal for B2B -- report it, don't retry.

Collect results into `./output/apollo_contacts.json`:
```json
{
  "row": 7,
  "email": "jane@co.com",
  "email_status": "verified",
  "title": "Project Manager",
  "city": "City",
  "state": "State",
  "country": "Country",
  "organization": "Company Name",
  "first_name": "Jane",
  "last_name": "Smith",
  "matched": true
}
```

### Step 3: After all enrichment completes, run these in parallel:

**Parallel block C (run together):**

**C1 -- Batch-update Google Sheet:**
Build update ranges targeting specific cells for each enriched row. Use `GOOGLESHEETS_UPDATE_VALUES_BATCH` to update all rows in as few calls as possible.

**CRITICAL: This endpoint uses camelCase** `valueInputOption` (opposite of `GOOGLESHEETS_VALUES_UPDATE` which uses snake_case). Composio is inconsistent between these two endpoints.

```
composio execute GOOGLESHEETS_UPDATE_VALUES_BATCH -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}",
  "data": [
    { "range": "{TAB_NAME}!F{row}:O{row}", "values": [["Job Title", "", "email@co.com", "phone", "City", "State", "Country"]] },
    ...
  ],
  "valueInputOption": "RAW"
}'
```

Update these columns per enriched row:
- `F` (Job Title) = Apollo `title`
- `J` (Lead Status) = "Enriched"
- `K` (Email) = Apollo `email`
- `L` (Phone) = Apollo phone (if available)
- `M` (City), `N` (State), `O` (Country) = Apollo location

**C2 -- Create Apollo contacts in bulk:**
For records with emails, create contacts under label `LinkedIn Comments - {Author} Post`:

```
composio execute APOLLO_CREATE_BULK_CONTACTS -d '{
  "contacts": [
    {
      "first_name": "Jane",
      "last_name": "Smith",
      "email": "jane@co.com",
      "organization_name": "Co",
      "title": "CFO",
      "label_names": ["LinkedIn Comments - {Author} Post"]
    },
    ...
  ]
}'
```

If `APOLLO_CREATE_BULK_CONTACTS` is unavailable, fall back to individual `APOLLO_CREATE_CONTACT` calls in parallel.

### Step 4: Re-fetch enriched records

Read back the enriched rows from Sheets (do NOT use cached pre-enrichment data):

```
composio execute GOOGLESHEETS_VALUES_GET -d '{
  "spreadsheet_id": "{SPREADSHEET_ID}",
  "range": "{TAB_NAME}!A1:O{LAST_ROW}"
}'
```

Filter for rows where Email (column K) is not empty. Save to `./output/apollo_contacts.json`.

Count the leads with emails from Apollo. Report the Apollo results, then immediately proceed to Phase 3.5.

**Checkpoint:** "Apollo found emails for X out of Y people (Z% match rate). Running Hunter.io on the remaining contacts..."

---

## Phase 3.5: Enrich (Hunter.io Fallback)

For every contact Apollo matched but returned no email for, try Hunter.io's Email Finder. This typically recovers 10-20% of missing emails. Only contacts with company info (from Apollo's `organization` or the original LinkedIn `companyName`) can be searched -- Hunter requires a company name or domain.

### Step 1: Identify candidates

From `./output/apollo_contacts.json`, filter for records where:
- `email` is empty/null
- AND either `organization` (from Apollo) or `companyName` (from original LinkedIn data in `./output/linkedin_commenters.json`) is non-empty

Build the search list with company from Apollo first, falling back to LinkedIn headline extraction.

### Step 2: Run parallel Hunter.io Email Finder

For each candidate, call `HUNTER_EMAIL_FINDER` individually. Run up to 8 calls concurrently using threaded execution (same pattern as Apollo Phase 3).

Build each call:
```
composio execute HUNTER_EMAIL_FINDER -d '{
  "first_name": "Firstname",
  "last_name": "Lastname",
  "company": "Company Name",
  "max_duration": 10
}'
```

**Important notes:**
- Use `company` (NOT `domain`) when you only have the company name. Hunter resolves the domain internally.
- If you have a known domain, prefer `domain` over `company` for better accuracy.
- `max_duration` ranges 3-20 seconds. Default 10 is a good balance.
- A successful response can still return `email: null` -- this is a valid no-match, not an error.
- Only accept results with `score >= 50` to avoid low-confidence guesses.

Name splitting: same rule as Apollo -- split `fullName` on the FIRST space only.

**Why parallel single calls:** Same rationale as Apollo. Hunter has no reliable bulk endpoint via Composio. Individual calls at 8 concurrent threads give the best throughput and visibility into per-person results.

Expected recovery rates:
- 10-20% of Apollo no-email contacts will get an email from Hunter
- Overall pipeline email coverage typically jumps 5-15 percentage points
- LATAM/emerging market recovery rates may be lower (5-10%)

Collect results into `./output/hunter_results.json`:
```json
{
  "idx": 15,
  "row": 17,
  "fullName": "Jane Smith",
  "email": "jane@company.com",
  "score": 85,
  "source": "hunter",
  "profileUrl": "https://www.linkedin.com/in/janesmith"
}
```

### Step 3: Merge results and update Sheet + Apollo

**3a -- Merge into apollo_contacts.json:**
For each Hunter result with an email, update the corresponding record in `./output/apollo_contacts.json` to add the email (mark `email_source: "hunter"` to distinguish from Apollo-found emails).

**3b -- Batch-update Google Sheet:**
Same pattern as Phase 3 Step 3 C1. For each newly found email, update:
- `J` (Lead Status) = "Enriched (Hunter)"
- `K` (Email) = Hunter email

Use `GOOGLESHEETS_UPDATE_VALUES_BATCH` with **camelCase** `valueInputOption`.

**3c -- Create Apollo contacts for new emails:**
Add newly found contacts to Apollo using `APOLLO_CREATE_BULK_CONTACTS` (max 100 per batch, no `label_names` at root level -- put inside each contact object).

Run 3b and 3c in parallel.

### Step 4: Final count

Re-count total emails (Apollo + Hunter). This combined count determines whether Phase 4 runs in auto-mode or interactive mode.

**Checkpoint:** "Hunter.io recovered X additional emails. Total: Y out of Z people now have emails (W% combined match rate). Y contacts ready for outreach."

---

## Phase 4: Write Email Sequence

### Auto-mode (fewer than 20 leads with emails)

Small lists don't justify a multi-round interactive review. Write all 3 emails yourself using the James Shields framework:

1. Gather context from earlier phases: the trigger (the LinkedIn post), the author, the audience profile (from headlines/companies), and any product/offer info from the sales context.
2. If product, social proof, and offer are not in the sales context, ask the user ONE consolidated question with all missing items.
3. Write all 3 emails (Day 0 opener, Day 3 follow-up, Day 7 breakup) following the rules in `cold-email-sequence`.
4. Save to `{campaign-name}-sequence.md`.
5. Show the user the complete sequence and say: "Wrote 3 emails for your X leads. Loading into Instantly now. You can tweak the copy in the Instantly dashboard before activating."

### Interactive mode (20+ leads with emails)

Follow the `cold-email-sequence` skill procedure exactly: gather inputs, draft Email 1, get approval, draft Email 2, get approval, draft Email 3, get approval, save.

**James Shields rules (both modes):**
- Personalize subject (not body), lowercase, 2-4 words
- 3 sentences + PS per email
- Low-friction CTA ("Reply 'I'm in'"), never a booking link
- No em dashes, no exclamation points, no formatting
- NEW social proof for each email (never repeat)
- Follow-up subjects: empty string (same thread)

**Checkpoint (interactive only):** "Sequence locked. Ready to load into Instantly."

---

## Phase 5: Launch on Instantly

### Step 1: Resolve credentials

Try Composio first:
1. Is the `instantly` Composio toolkit connected? (If you already ran `INSTANTLY_LIST_ACCOUNTS` in Phase 3, you know the answer.)
2. If not connected, use `composio link instantly --no-wait` and present the redirect URL.
3. If Composio unavailable, check `INSTANTLY_API_KEY` env var.
4. Last resort: ask for the API key in chat (ephemeral, session-only, never written to disk).

### Step 2: Create campaign

Sanitize ALL email bodies first -- replace every `&` character with "and" (Instantly silently drops bodies containing `&`).

**CRITICAL Composio/Instantly field notes:**
- Do NOT include `delay_unit` in sequence steps -- the Composio schema doesn't support it. The `delay` field is already in days.
- Timezone: pick one appropriate for the audience. Not all IANA timezone strings work with Composio's Instantly integration. Known working: `America/New_York`, `America/Chicago`, `America/Denver`, `America/Los_Angeles`, `America/Bogota`, `America/Sao_Paulo`, `Europe/London`, `Europe/Berlin`. Known rejected: `America/Vancouver`. When in doubt, use the major city timezone closest to the audience.
- Follow-up email subjects: use empty string `""` to thread under the original subject.

```
composio execute INSTANTLY_CREATE_CAMPAIGN -d '{
  "name": "LinkedIn - {Author} {Topic}",
  "campaign_schedule": {
    "schedules": [{
      "name": "Weekday Schedule",
      "timing": { "from": "08:00", "to": "17:00" },
      "days": { "0": true, "1": true, "2": true, "3": true, "4": true, "5": false, "6": false },
      "timezone": "America/New_York"
    }]
  },
  "sequences": [{
    "steps": [
      { "type": "email", "delay": 0,
        "variants": [{ "subject": "subject line", "body": "Email 1 body" }] },
      { "type": "email", "delay": 3,
        "variants": [{ "subject": "", "body": "Email 2 body" }] },
      { "type": "email", "delay": 4,
        "variants": [{ "subject": "", "body": "Email 3 body" }] }
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
}'
```

**Delay math:** Delays are RELATIVE to the previous step, not absolute from Day 0. So for Day 0 / Day 3 / Day 7: step 1 delay=0, step 2 delay=3, step 3 delay=4 (because 3+4=7).

Save the returned campaign `id`. Verify all step bodies are non-empty (ampersand check).

### Step 2.5: Verify the campaign was created correctly

```
composio execute INSTANTLY_GET_CAMPAIGN -d '{
  "id": "{CAMPAIGN_ID}"
}'
```

**CRITICAL:** This endpoint uses `id` as the parameter name, NOT `campaign_id`. Check that all 3 email step bodies are populated and the schedule/timezone look correct.

### Parallel block D (run together):

**D1 -- Bulk load leads:**
```
composio execute INSTANTLY_ADD_LEADS_BULK -d '{
  "campaign_id": "{CAMPAIGN_ID}",
  "leads": [
    { "email": "j@co.com", "first_name": "Jane", "last_name": "Smith", "company_name": "Co" },
    ...
  ]
}'
```
Max 1000 leads per call. Check `leads_uploaded` and `invalid_email_count`.

**D2 -- Attach all sending accounts:**
If the campaign was created with only one account, patch to include all:
```
composio execute INSTANTLY_UPDATE_CAMPAIGN -d '{
  "campaign_id": "{CAMPAIGN_ID}",
  "email_list": ["email1@...", "email2@...", "email3@..."]
}'
```

### Step 3: Leave paused

NEVER auto-activate. Campaign starts paused.

**Final report to user:**
- Campaign name and status (paused)
- Number of leads loaded
- Sending accounts attached
- Schedule: Mon-Fri, 8:00-17:00 in the audience's timezone
- Google Sheet URL for reference
- "Review in Instantly dashboard. Say 'go' when ready to launch."

To activate when user approves:
```
composio execute INSTANTLY_ACTIVATE_CAMPAIGN -d '{ "campaign_id": "{CAMPAIGN_ID}" }'
```

---

## Composio Tool Slug Reference

| Service | Action | Composio slug | Key gotchas |
|---------|--------|---------------|-------------|
| Apify | Get actor info | `APIFY_GET_ACTOR` | |
| Apify | Run actor (sync) | `APIFY_RUN_ACTOR_SYNC` | Input field is `posts` not `urls` |
| Sheets | Create spreadsheet | `GOOGLESHEETS_CREATE_GOOGLE_SHEET1` | |
| Sheets | Get tab names | `GOOGLESHEETS_GET_SHEET_NAMES` | Always call after create -- tab name is locale-dependent |
| Sheets | Write/update values | `GOOGLESHEETS_VALUES_UPDATE` | Uses **snake_case**: `value_input_option` |
| Sheets | Batch update | `GOOGLESHEETS_UPDATE_VALUES_BATCH` | Uses **camelCase**: `valueInputOption` |
| Sheets | Append rows | `GOOGLESHEETS_SPREADSHEETS_VALUES_APPEND` | |
| Sheets | Read values | `GOOGLESHEETS_VALUES_GET` | |
| Apollo | Single enrichment | `APOLLO_PEOPLE_ENRICHMENT` | **Preferred.** Uses `organization_name`. No `reveal_phone_number`. |
| Apollo | Bulk enrichment | `APOLLO_BULK_PEOPLE_ENRICHMENT` | Unreliable in parallel -- use single instead. Uses `company_name`. |
| Apollo | Bulk create contacts | `APOLLO_CREATE_BULK_CONTACTS` | |
| Apollo | Check credits | `APOLLO_VIEW_API_USAGE_STATS` | |
| Hunter | Email finder | `HUNTER_EMAIL_FINDER` | Uses `company` (not `domain`) when only name known. `max_duration` 3-20s. Score >= 50 to accept. |
| Hunter | Check credits | `HUNTER_ACCOUNT_INFORMATION` | `searches.available`/`used` for quota. |
| Instantly | List accounts | `INSTANTLY_LIST_ACCOUNTS` | |
| Instantly | Get campaign | `INSTANTLY_GET_CAMPAIGN` | Uses `id` (NOT `campaign_id`) |
| Instantly | Create campaign | `INSTANTLY_CREATE_CAMPAIGN` | No `delay_unit` in steps. Timezone must be a major city. |
| Instantly | Update campaign | `INSTANTLY_UPDATE_CAMPAIGN` | |
| Instantly | Bulk add leads | `INSTANTLY_ADD_LEADS_BULK` | |
| Instantly | Activate campaign | `INSTANTLY_ACTIVATE_CAMPAIGN` | |

---

## Timing Expectations

| Phase | Duration | Notes |
|-------|----------|-------|
| 1. Scrape | 2-5 min | MCP Apify handles async polling automatically |
| 2. Store | ~30 sec | One bulk write -- include tab name discovery |
| 3. Enrich (Apollo) | 5-15 min | 8 concurrent single Apollo calls. Sheet batch-update adds ~30s. |
| 3.5. Enrich (Hunter) | 3-8 min | 8 concurrent Hunter calls on Apollo no-email contacts. Typically 10-20% recovery. |
| 4. Write | 1-2 min (auto) / 10-30 min (interactive) | Auto-mode skips interactive review for small lists |
| 5. Launch | 1-3 min | Instantly accounts pre-fetched during Phase 3 |
| **Total** | **~13-30 min (auto) / ~23-60 min (interactive)** | |

---

## Common Mistakes

| Phase | Failure mode | Fix |
|-------|--------------|-----|
| 1 | Zero results: used `urls` instead of `posts` | Apify actor field is `posts`. Always check actor input schema. |
| 1 | Only 20 results returned | Actor defaults `maxItems` to 20. Always override to 1000. |
| 1 | Field names don't match expected | Actor returns `name`/`position`/`linkedinUrl`, not `fullName`/`headline`/`profileUrl`. Map them. |
| 1 | Invalid LinkedIn URL | Validate format, resolve redirects via WebFetch. |
| 2 | "Range not found" error | Tab name is locale-dependent ("Hoja 1", "Feuille 1", etc.). Discover with `GOOGLESHEETS_GET_SHEET_NAMES`. |
| 2 | `value_input_option` error | `GOOGLESHEETS_VALUES_UPDATE` uses **snake_case**. `GOOGLESHEETS_UPDATE_VALUES_BATCH` uses **camelCase**. They're inconsistent. |
| 2 | `values` rejected | Must be a native JSON array, not a stringified array. |
| 2 | 403 on sheet creation | Google Sheets Composio scopes may be insufficient. Re-link with `composio link googlesheets --no-wait`. |
| 2 | Values array not rectangular | Pad empty cells with `""`. Every row must have 15 columns. |
| 3 | Bulk Apollo returns 0 matches | Bulk endpoint is unreliable in parallel. Switch to single `APOLLO_PEOPLE_ENRICHMENT` with 8 concurrent threads. |
| 3 | Apollo errors on `reveal_phone_number` | Don't set this flag -- it requires a `webhook_url`. |
| 3 | Apollo field name mismatch | Single uses `organization_name`. Bulk uses `company_name`. Different schemas. |
| 3 | Low email match rate (<50%) | Normal for LATAM/emerging market audiences. Person match is still 85-95%. Proceed. |
| 3 | Cached data missing emails | Always re-fetch from Sheets after updates. Never trust pre-enrichment data. |
| 3.5 | Hunter returns `email: null` with `successful: true` | Valid no-match. Don't retry -- Hunter has no data for this person. |
| 3.5 | Low Hunter score (<50) | Discard. Low-confidence guesses bounce and hurt sender reputation. |
| 3.5 | Hunter 429 rate limit | Credits exhausted for billing period. Cannot retry. Report partial results and continue pipeline. |
| 3.5 | No company info for contact | Cannot search Hunter without company or domain. Skip these contacts silently. |
| 3.5 | Hunter returns duplicate of Apollo email | Deduplicate by email before updating Sheet. Apollo result takes precedence. |
| 4 | User wants major rewrite (interactive) | Rewrite from scratch, don't patch. |
| 5 | Empty body on Instantly side | Ampersand in text. Strip ALL `&` characters before upload. |
| 5 | `delay_unit` error | Composio's Instantly schema doesn't include `delay_unit`. Just use `delay` (already in days). |
| 5 | Timezone rejected | Not all IANA zones work. Use major city timezones (see list in Phase 5). `America/Vancouver` is rejected. |
| 5 | `INSTANTLY_GET_CAMPAIGN` fails | Parameter is `id`, NOT `campaign_id`. |
| 5 | Composio Instantly 401 | Token expired. Re-link: `composio link instantly --no-wait`. |

---

## Example Walkthrough (from real live test)

1. **User:** "Run the linkedin gsheets pipeline on this Colombia AI Summit post"

2. **Phase 1:** Fetch actor details (MCP). Test scrape 20 items with `posts` field -- works. Full scrape 500 items -- 112 raw, 103 unique after dedup. Map `name`->`fullName`, `position`->`headline`, `linkedinUrl`->`profileUrl`. Save to `./output/linkedin_commenters.json`. Report: "Scraped 103 unique commenters."

3. **Phase 2:** Create Google Sheet "LinkedIn Commenters - Felipe Salinas". Discover tab name: "Hoja 1" (Spanish locale). Write 15-column headers + 103 rows using `value_input_option: "RAW"` (snake_case). Verify first 5 rows. Share sheet URL. Report: "Loaded 103 records into Google Sheets."

4. **Phase 3 (Apollo):** Read 103 rows. Pre-fetch Instantly accounts (parallel). Run 103 parallel single Apollo calls (8 concurrent). Result: 98 person matches (95%), 63 with verified emails (61%). Batch-update Sheet with `valueInputOption: "RAW"` (camelCase). Save 63 contacts to `./output/apollo_contacts.json`. Report: "Apollo found emails for 63 out of 103 people (61%). Running Hunter.io on remaining contacts..."

5. **Phase 3.5 (Hunter.io):** 35 contacts matched by Apollo but had no email. Of those, 28 had company info. Run 28 parallel Hunter.io calls (8 concurrent). Result: 7 new emails found (25% recovery). Batch-update Sheet with Hunter emails (status: "Enriched (Hunter)"). Create Apollo contacts for 7 new leads. Total: 70 out of 103 now have emails (68% combined). Report: "Hunter.io recovered 7 additional emails. Total: 70 contacts ready for outreach."

6. **Phase 4 (interactive, 70 > 20):** Gather context: workshop attendees, Houston product, invite code, social proof (1000 users in 46 countries). Co-write 3 emails: Day 0 (thank you + invite), Day 3 (follow-up), Day 7 (last call). Save to `colombia-ai-summit-sequence.md`.

7. **Phase 5:** Sanitize bodies (strip `&`). Create campaign "LinkedIn - Colombia AI Summit Workshop" with timezone `America/Bogota`. No `delay_unit` in steps. Verify via `INSTANTLY_GET_CAMPAIGN` (parameter: `id`). Load 70 leads (0 invalid). Attach 2 sending accounts. Leave paused.

8. **Final report:** Campaign name, paused, 70 leads (63 Apollo + 7 Hunter), 2 sending accounts, Mon-Fri 8-5 Bogota time, Sheet URL, "Review in Instantly. Say 'go' to launch."

### Auto-mode example (small list)

Same as above, but Phase 3 returns only 10 emails and Phase 3.5 recovers 3 more (13 total). Phase 4 runs in auto-mode: write all 3 emails without review, save sequence file, show user the copy, and move straight to Phase 5. User reviews everything in Instantly's dashboard before activating.

---

## Output

- Google Sheet with all commenters + enrichment data (shared URL)
- Apollo contacts under label `LinkedIn Comments - {Author} Post`
- Email sequence file in workspace: `{campaign-name}-sequence.md`
- Instantly campaign (paused) with 3 email steps, all leads loaded, all sending accounts attached
- `./output/linkedin_commenters.json` -- raw scraped data
- `./output/apollo_contacts.json` -- enriched contacts with emails (includes Hunter.io recoveries marked with `email_source: "hunter"`)
- `./output/hunter_results.json` -- Hunter.io fallback results
