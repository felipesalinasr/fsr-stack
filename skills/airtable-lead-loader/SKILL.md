---
name: airtable-lead-loader
description: Use when a LinkedIn commenter or reaction scrape has just produced a JSON file of leads that need to be persisted to Airtable, when downstream skills (apollo-enrichment, instantly-campaign) require structured records with stable IDs, or when the user says "load into airtable", "store leads in airtable", or "create airtable table for commenters".
---

# Airtable Lead Loader

## Overview

One Airtable table, full pipeline schema, batched inserts via parallel agents. This skill creates a single table sized for the entire scrape-to-outreach pipeline (scraping fields + enrichment fields + outreach status), then loads the scraped JSON in parallel batches that respect Airtable's 10-record-per-call hard cap.

## When to use

- Right after `linkedin-comment-scraper` or `linkedin-reaction-scraper` produces a leads JSON file
- The user wants leads stored in Airtable for tracking, enrichment, or outreach
- A downstream skill (apollo-enrichment, instantly-campaign) needs Airtable record IDs
- The phrases "add to airtable", "load into airtable", "store leads in airtable", or "create airtable table for commenters" appear

## When NOT to use

- Updating existing Airtable records with enrichment data — use the apollo-enrichment update flow instead
- Inserting a single record manually — call `mcp__airtable__create_record` directly
- Loading non-LinkedIn data (CRM exports, conference attendees, etc.) — the schema here is LinkedIn-specific
- The target base does not yet exist — create the base in Airtable first, then run this skill

## Prerequisites

- Airtable MCP server is connected and `mcp__airtable__*` tools are available
- `AIRTABLE_API_KEY` environment variable is set (see `../SETUP.md` for installation)
- Upstream skill (`linkedin-comment-scraper` or `linkedin-reaction-scraper`) has produced `./output/linkedin_commenters.json`
- An Airtable base exists; obtain its ID from the user or via `mcp__airtable__list_bases`

## The Workflow

### Step 1: Identify the Target Base

```
Use: mcp__airtable__list_bases
```

Ask user which base to use or locate the relevant one. Record the `baseId` (referred to below as `{BASE_ID}`).

### Step 2: Create the Table with Full Schema

Create a table with all fields needed for the full pipeline (scraping + enrichment + outreach):

```
Use: mcp__airtable__create_table
baseId: {BASE_ID}
name: "LinkedIn Commenters - [Post Author Name]"
fields:
  - name: "Full Name", type: "singleLineText"
  - name: "Comment", type: "multilineText"
  - name: "LinkedIn Profile URL", type: "url"
  - name: "Headline", type: "singleLineText"
  - name: "Company", type: "singleLineText"
  - name: "Job Title", type: "singleLineText"
  - name: "Source Post URL", type: "url"
  - name: "Scraped Date", type: "date", options: { dateFormat: { name: "iso" } }
  - name: "Reactions on Comment", type: "number", options: { precision: 0 }
  - name: "Lead Status", type: "singleSelect", options: { choices: ["New", "Enriched", "Contacted", "Replied", "Not Interested"] }
  - name: "Email", type: "email"
  - name: "Phone", type: "phoneNumber"
  - name: "City", type: "singleLineText"
  - name: "State", type: "singleLineText"
  - name: "Country", type: "singleLineText"
```

**IMPORTANT:** Save the returned `tableId` (referred to below as `{TABLE_ID}`) and ALL `fieldId` values from the response.

### Step 3: Map Scraped Data to Airtable Fields

Load `./output/linkedin_commenters.json` and map each record:

```python
{
  "Full Name": record["fullName"],
  "Comment": record["comment"],
  "LinkedIn Profile URL": record["profileUrl"],
  "Headline": record["headline"],
  "Company": record["companyName"],
  "Source Post URL": "THE_ORIGINAL_POST_URL",
  "Scraped Date": "YYYY-MM-DD",
  "Reactions on Comment": record["reactions"],
  "Lead Status": "New"
}
```

### Step 4: Batch Load Records (Use Parallel Agents)

Airtable `create_record` creates ONE record per call. For 100+ records, use parallel agents:

**Strategy:**
1. Split records into 4 batches
2. Save each to `./output/airtable_batch_N.json`
3. Spawn 4 parallel background agents
4. Each calls `mcp__airtable__create_record` for every record in its batch

**Agent prompt template:**
```
You have access to Airtable MCP tools. Load records into Airtable.
Base ID: {BASE_ID}
Table ID: {TABLE_ID}
Records file: ./output/airtable_batch_N.json

For each record, call mcp__airtable__create_record with baseId, tableId,
and the fields object. Report total loaded when done.
```

### Step 5: Verify Load

```
Use: mcp__airtable__list_records
baseId: {BASE_ID}
tableId: {TABLE_ID}
maxRecords: 5
```

Confirm records loaded. Report total count.

## Quick Reference

- **Input file:** `./output/linkedin_commenters.json` (from `linkedin-comment-scraper` or `linkedin-reaction-scraper`)
- **Required env var:** `AIRTABLE_API_KEY`
- **MCP tools used:** `mcp__airtable__list_bases`, `mcp__airtable__create_table`, `mcp__airtable__create_record`, `mcp__airtable__list_records`
- **Batch size limit:** 10 records per call (Airtable hard cap on batched ops)
- **Parallelism:** 4 background agents, one per batch file
- **Output file:** `./output/airtable_record_ids.json` (record IDs keyed by name for downstream updates)

## Composio Fallback (Optional Path)

If `mcp__airtable__*` tools aren't connected but the founder has Composio.dev MCP, route through Composio. The data flow is identical — only the transport changes — and Composio's bulk-create endpoint is actually faster than the direct path.

*Detection:*
- `mcp__composio__COMPOSIO_SEARCH_TOOLS` is available in the session
- The direct `mcp__airtable__*` tools are missing or error on first call

*Fallback workflow:*

1. Discover slugs: call `mcp__composio__COMPOSIO_SEARCH_TOOLS` with `use_case: "create an Airtable table and bulk insert lead records into it"` and `session: { generate_id: true }`. Save the `session_id`.
2. If the `airtable` toolkit isn't connected, call `mcp__composio__COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["airtable"]`. Surface the `redirect_url` as a clickable link.
3. Poll with `mcp__composio__COMPOSIO_WAIT_FOR_CONNECTIONS` until Active.
4. Run the same Step 1-5 sequence using the slugs below.

*Tool slug equivalents:*

- `mcp__airtable__list_bases` -> `AIRTABLE_LIST_BASES`
- `mcp__airtable__describe_table` / get_base_schema -> `AIRTABLE_GET_BASE_SCHEMA`
- `mcp__airtable__create_table` -> `AIRTABLE_CREATE_TABLE`
- `mcp__airtable__create_field` -> `AIRTABLE_CREATE_FIELD`
- `mcp__airtable__create_record` -> `AIRTABLE_CREATE_RECORDS` (plural — accepts up to 10 per call)
- `mcp__airtable__list_records` -> `AIRTABLE_LIST_RECORDS`
- `mcp__airtable__update_records` -> `AIRTABLE_UPDATE_MULTIPLE_RECORDS`

*Throughput improvement:* Composio's `AIRTABLE_CREATE_RECORDS` accepts up to 10 records per call, versus the direct MCP's 1-record-per-call `create_record`. On the Composio path, drop the parallel-agent batching strategy from Step 4 and instead chunk records into groups of 10 and call `AIRTABLE_CREATE_RECORDS` sequentially. The 10-per-call hard cap still applies (Airtable API limit, not Composio).

*Same gotchas:* The 10-record cap, ISO date format `YYYY-MM-DD`, and case-sensitive field names all live inside Airtable's API itself. Both transports hit them identically.

## Common Mistakes

- **Batched ops over 10 records.** Airtable rejects any `create_records`/`update_records`/`delete_records` call with more than 10 items. Always chunk.
- **`list_records` output too large for context.** It saves to file automatically — use `jq` or Python to parse rather than dumping into the conversation.
- **Field name casing.** Field names are case-sensitive. Use the exact strings returned by `create_table`, not the schema you submitted.
- **Wrong date format.** Must be ISO `"YYYY-MM-DD"` (e.g., `"2025-01-15"`) and match the `dateFormat` option set on the field.
- **Filtering null values.** Don't drop empty fields — Airtable accepts null/empty and the downstream enrichment skill expects every row to exist.
- **Hardcoding base/table IDs.** Always pass `{BASE_ID}` and `{TABLE_ID}` from the current run; never reuse IDs from a prior session.

## Example

Sample input `./output/linkedin_commenters.json` (3 records):

```json
[
  {"fullName": "Jane Doe", "comment": "Great post!", "profileUrl": "https://linkedin.com/in/janedoe", "headline": "CFO at Acme", "companyName": "Acme", "reactions": 4},
  {"fullName": "John Smith", "comment": "+1", "profileUrl": "https://linkedin.com/in/johnsmith", "headline": "Tax Director", "companyName": "Globex", "reactions": 1},
  {"fullName": "Alex Lee", "comment": "Where can I learn more?", "profileUrl": "https://linkedin.com/in/alexlee", "headline": "Founder", "companyName": "Initech", "reactions": 7}
]
```

Walkthrough:

1. `mcp__airtable__list_bases` — user picks base, returned ID becomes `{BASE_ID}`.
2. `mcp__airtable__create_table` with the full 15-field schema and name `"LinkedIn Commenters - Felipe"`. Capture `{TABLE_ID}` and field IDs.
3. Map all 3 records, setting `Scraped Date` to today as `"YYYY-MM-DD"` and `Lead Status` to `"New"`.
4. Only 3 records → no need to split into 4 batches; write one file `./output/airtable_batch_1.json` and call `mcp__airtable__create_record` three times sequentially.
5. `mcp__airtable__list_records` with `maxRecords: 5` confirms 3 rows present.
6. Write `./output/airtable_record_ids.json` mapping `"Jane Doe" -> recXXX`, `"John Smith" -> recYYY`, `"Alex Lee" -> recZZZ` for the apollo-enrichment skill to consume.

## Output

- Airtable table created and populated with all commenter records
- `{BASE_ID}` and `{TABLE_ID}` recorded for downstream skills
- File: `./output/airtable_record_ids.json` — record IDs with names for updates
