---
name: apollo-enrichment
description: Use when LinkedIn commenter or reaction records exist in Airtable and need verified B2B emails, company info, titles, and locations before cold outreach, or when running downstream of the airtable-lead-loader skill in a LinkedIn-to-outreach pipeline.
---

# Apollo Enrichment

## Overview

Apollo bulk people match returns the highest match rate for B2B email enrichment. The core principle: batch records in groups of 10, run matches in parallel, write results back to Airtable, then re-fetch records before any downstream step uses them. Never trust cached pre-enrichment data after an update.

## When to use

- Airtable records have been loaded (typically by `airtable-lead-loader`) and need email enrichment
- You have LinkedIn profile URLs or name + company pairs and need verified B2B emails
- Running the enrichment layer of a LinkedIn-to-outreach pipeline
- Need to create Apollo contacts under a campaign label after enrichment

## When NOT to use

- Targeting consumer contacts (Apollo is B2B only)
- Records already contain valid emails (skip enrichment, go straight to outreach)
- No LinkedIn URL AND no company name available (match rate collapses to near zero)
- Looking up a single person ad-hoc (use `apollo_people_match` directly instead)

## Prerequisites

- Apollo.io MCP server connected via OAuth at `https://mcp.apollo.io/`. Authentication flows through claude.ai, so no API key or environment variable is required on the local machine. See `../SETUP.md` for connection steps.
- Airtable MCP available with records already loaded (from `airtable-lead-loader`)
- Airtable Base ID and Table ID known (referenced below as `{BASE_ID}` and `{TABLE_ID}`)
- Local `./output/` directory exists for intermediate JSON files

## The Workflow

### Step 1: Pull Records from Airtable

```
Use: mcp__airtable__list_records
baseId: {BASE_ID}
tableId: {TABLE_ID}
maxRecords: 200
```

Large outputs exceed token limit and auto-save to file. Extract with Python:

```bash
cat /path/to/output.txt | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = [{'id': r['id'], 'name': r['fields'].get('Full Name',''),
            'linkedin': r['fields'].get('LinkedIn Profile URL',''),
            'company': r['fields'].get('Company','')}
           for r in data['records']]
json.dump(records, open('./output/records_for_enrichment.json','w'))
print(f'Extracted {len(records)} records')
"
```

### Step 2: Prepare Apollo Bulk Match Batches

`apollo_people_bulk_match` accepts a maximum of 10 people per call.

Build match entries:
```json
{
  "first_name": "Firstname",
  "last_name": "Lastname",
  "organization_name": "Example Advisory",
  "linkedin_url": "https://www.linkedin.com/in/exampleprofile"
}
```

Name splitting: split `fullName` on the FIRST space only. A name like `Firstname Lastname, CPA` becomes `first: "Firstname"`, `last: "Lastname, CPA"`.

Split into batches of 10.

### Step 3: Run Bulk Match (Parallel Agents)

Use up to 4 parallel background agents for speed:

```
Use: apollo_people_bulk_match
details: [ ...up to 10 entries... ]
```

Key fields returned:
- `email` — verified email (null if no match)
- `organization.name` — company
- `title` — job title
- `city`, `state`, `country` — location
- `phone_numbers` — array

Expected match rate: 50-70%.

### Step 4: Update Airtable with Enriched Data

```
Use: mcp__airtable__update_records
baseId: {BASE_ID}
tableId: {TABLE_ID}
records: [
  {
    "id": "RECORD_ID",
    "fields": {
      "Email": "person@example.com",
      "Company": "Example Advisory",
      "Job Title": "Senior Role",
      "City": "City", "State": "State", "Country": "Country",
      "Lead Status": "Enriched"
    }
  }
]
```

Max 10 records per `update_records` call. Batch accordingly.

### Step 5: Create Apollo Contacts with Label

For records with emails, create Apollo contacts:

```
Use: apollo_contacts_create
first_name: "Firstname"
last_name: "Lastname"
email: "person@example.com"
organization_name: "Example Advisory"
title: "Senior Role"
label_names: ["LinkedIn Comments - {Author} Post"]
```

Use `run_dedupe: true`. Batch across parallel agents for 100+ contacts. The label naming convention `LinkedIn Comments - {Author} Post` is required so downstream skills can target the cohort.

### Step 6: Re-fetch Records with Emails

CRITICAL: Do NOT use cached pre-enrichment data. Re-fetch from Airtable:

```
Use: mcp__airtable__list_records
filterByFormula: "Email != ''"
```

Save to `./output/apollo_contacts.json` for campaign loading.

### Step 7: Report

- Total processed
- Emails found (match rate %)
- No-match count
- Apollo contacts created
- Label name for campaigns

## Quick Reference

- *Input*: Airtable records with `Full Name`, `LinkedIn Profile URL`, optional `Company`
- *Bulk match endpoint*: `apollo_people_bulk_match`
- *Batch limit*: 10 records per call (hard cap)
- *Match rate*: 50-70% expected
- *Contact creation*: `apollo_contacts_create` with `label_names`
- *Output*: Airtable records updated + `./output/apollo_contacts.json` + Apollo contacts under label `LinkedIn Comments - {Author} Post`

## Composio Fallback (Optional Path)

If the direct Apollo OAuth MCP isn't connected but the founder has Composio.dev MCP available, route through Composio. Same bulk-match logic, identical match rate, different transport.

*Detection:*
- `mcp__composio__COMPOSIO_SEARCH_TOOLS` is available in the session
- The direct `apollo_*` tools (or `mcp__claude_ai_Apollo_io__*`) are missing

*Fallback workflow:*

1. Discover slugs: call `mcp__composio__COMPOSIO_SEARCH_TOOLS` with `use_case: "enrich people by name and company using Apollo.io to find verified emails"` and `session: { generate_id: true }`. Save the `session_id`.
2. If the `apollo` toolkit isn't connected, call `mcp__composio__COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["apollo"]`. Surface the `redirect_url`.
3. Poll with `mcp__composio__COMPOSIO_WAIT_FOR_CONNECTIONS` until Active.
4. Substitute slugs in Steps 3 and 5 of the standard workflow.

*Tool slug equivalents:*

- `apollo_people_match` -> `APOLLO_PEOPLE_ENRICHMENT` (single person)
- `apollo_people_bulk_match` -> `APOLLO_BULK_PEOPLE_ENRICHMENT` (up to 10 per call)
- `apollo_contacts_create` -> `APOLLO_CREATE_CONTACT`
- `apollo_contacts_update` -> `APOLLO_UPDATE_CONTACT`
- `apollo_contacts_search` / `apollo_mixed_people_api_search` -> `APOLLO_PEOPLE_SEARCH`

*Behavioral notes:*

- Both paths consume Apollo credits at the same rate. Composio does NOT rebate credits on no-matches.
- The Composio wrapper does NOT auto-dedupe `APOLLO_CREATE_CONTACT` calls — pass `run_dedupe: true` in the input just like the direct path.
- Match rate (50-70%) is identical because the underlying Apollo endpoint is the same.
- The `label_names` parameter for contact creation is preserved on both paths — keep the convention `LinkedIn Comments - {Author} Post` so downstream skills can target the cohort.

## Common Mistakes

- *Forgetting to re-fetch after update*: Using pre-enrichment cached data downstream causes silent data loss. Always re-fetch from Airtable in Step 6.
- *Exceeding 10-record batch*: `apollo_people_bulk_match` and `mcp__airtable__update_records` both cap at 10. Splitting larger batches client-side is mandatory.
- *Passing partial LinkedIn URLs*: URLs must be the full canonical form `https://www.linkedin.com/in/username`. Stripped or relative URLs drop the match rate hard.
- *Treating null emails as failures*: A 30-50% no-match rate is normal for B2B. Report it, do not retry.
- *Ignoring Apollo company data*: Apollo may return a different company than the one in the input. Trust Apollo's value and overwrite.
- *Bad name splits*: Split on the FIRST space only. Suffixes like `, CPA` belong on the last name.

## Example

Input: 25 LinkedIn commenters loaded by `airtable-lead-loader` into table `{TABLE_ID}` in base `{BASE_ID}`.

1. List records (Step 1) and extract 25 entries to `./output/records_for_enrichment.json`.
2. Build 3 batches: 10, 10, 5. Each entry has `first_name`, `last_name`, `organization_name`, `linkedin_url`.
3. Dispatch 3 parallel agents calling `apollo_people_bulk_match`. Results: 16 of 25 returned an email (64% match rate).
4. Chunk the 16 enriched records into 2 update batches of 10 and 6, then call `mcp__airtable__update_records` twice with `Email`, `Company`, `Job Title`, `City`, `State`, `Country`, and `Lead Status: Enriched`.
5. For each of the 16 enriched records, call `apollo_contacts_create` with `label_names: ["LinkedIn Comments - {Author} Post"]` and `run_dedupe: true`.
6. Re-fetch with `filterByFormula: "Email != ''"` and save the 16 records to `./output/apollo_contacts.json`.
7. Report: 25 processed, 16 emails (64%), 9 no match, 16 Apollo contacts created under label `LinkedIn Comments - {Author} Post`.

## Output

- Airtable updated with emails, company, title, location, and `Lead Status: Enriched`
- Apollo contacts created under the campaign label
- File: `./output/apollo_contacts.json` — enriched records ready for the downstream campaign skill
