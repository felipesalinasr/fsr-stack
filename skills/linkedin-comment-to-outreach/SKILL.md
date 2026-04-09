---
name: linkedin-comment-to-outreach
description: Use when the user provides a LinkedIn post URL and wants to run the full pipeline from commenters to a live cold outreach campaign on Instantly, including phrases like "linkedin comment to outreach", "scrape and email", "run the linkedin pipeline", or "outreach from linkedin commenters".
---

# LinkedIn Comment to Outreach Pipeline

## Overview

End-to-end orchestrator that takes a single LinkedIn post URL and produces a fully loaded, paused Instantly cold email campaign. The core principle: chain 5 focused sub-skills with a user checkpoint between each phase so the operator stays in control while the heavy lifting is automated.

## When to use

- User provides a LinkedIn post URL and wants to reach out to its commenters
- User asks to "run the linkedin pipeline", "scrape and email", or "linkedin comment to outreach"
- User wants a complete path from a LinkedIn post to a live Instantly campaign
- User needs commenters scraped, stored in Airtable, enriched with Apollo, sequenced, and loaded into Instantly in one flow

## When NOT to use

- Targeting people who *reacted* to a post (use `linkedin-reaction-to-outreach` instead)
- Just scraping commenters with no outreach (use `linkedin-comment-scraper` directly)
- Just enriching an existing list (use `apollo-enrichment` directly)
- Just writing a cold email sequence without a lead source (use `cold-email-sequence` directly)
- Just creating an Instantly campaign from leads you already have (use `instantly-campaign` directly)

## Prerequisites

- **MCP tools:** Apify, Airtable, Apollo.io
- **API key:** `INSTANTLY_API_KEY` environment variable (see `../SETUP.md`)
- **Airtable base:** Existing base ID (user provides or we discover via `list_bases`)
- **User input needed for Phase 4:** Social proof, product description, CTA preferences, sender name

## The Pipeline

```
LinkedIn Post URL
       |
       v
[1. linkedin-comment-scraper]  -- Apify scrape, deduplicate
       |
       v
[2. airtable-lead-loader]     -- Create table, batch load records
       |
       v
[3. apollo-enrichment]        -- Bulk email lookup, update Airtable, create contacts
       |
       v
[4. cold-email-sequence]      -- Co-write 3 emails with user (interactive)
       |
       v
[5. instantly-campaign]       -- Create campaign, load leads, configure accounts
       |
       v
Campaign ready for review (paused)
```

### Phase 1: Scrape (Skill: linkedin-comment-scraper)

**Input:** LinkedIn post URL from user
**Output:** `./output/linkedin_commenters.json`

1. Validate the LinkedIn post URL
2. Test scrape with `maxItems: 20`
3. Full scrape with `maxItems: 500`
4. Deduplicate by `profileUrl`, remove null profiles
5. Save to `./output/linkedin_commenters.json`

**Checkpoint:** Report to user: "Scraped X unique commenters from [Author]'s post. Proceeding to Airtable."

### Phase 2: Store (Skill: airtable-lead-loader)

**Input:** `./output/linkedin_commenters.json`, Airtable Base ID
**Output:** Airtable table populated, record IDs saved

1. List Airtable bases, confirm with user
2. Create table: "LinkedIn Commenters - [Author Name]"
3. Include all fields: scrape data + enrichment fields + outreach tracking
4. Batch load via parallel agents (4 agents for speed)
5. Verify load count

**Checkpoint:** Report: "Loaded X records into Airtable. Starting Apollo enrichment."

### Phase 3: Enrich (Skill: apollo-enrichment)

**Input:** Airtable Base ID, Table ID
**Output:** Airtable updated with emails, Apollo contacts created

1. Pull all records from Airtable
2. Batch into groups of 10 for Apollo bulk match
3. Run enrichment via parallel agents
4. Update Airtable records with email, company, title, location
5. Create Apollo contacts under label: "LinkedIn Comments - [Author] Post"
6. Re-fetch records with emails, save to `./output/apollo_contacts.json`

**Checkpoint:** Report: "Found emails for X out of Y people (Z% match rate). X contacts ready for outreach."

### Phase 4: Write (Skill: cold-email-sequence)

**Input:** User context (product, social proof, trigger), contact count
**Output:** `{campaign-name}-sequence.md`

This is the **interactive step**. Work with the user one email at a time:

1. Gather inputs: trigger, product, social proof, CTA, sender name
2. Draft Email 1 (Day 0) -- present, refine, lock
3. Draft Email 2 (Day 3) -- present, refine, lock
4. Draft Email 3 (Day 7) -- present, refine, lock
5. Save complete sequence to file

**Key rules:**
- James Shields framework (personalize subject not body, 3 sentences + PS, low-friction CTA)
- No em dashes, no exclamation points, no formatting
- Each email approved before moving to next
- NEW social proof for each email (never repeat)

**Checkpoint:** "Sequence locked. Ready to load into Instantly."

### Phase 5: Launch (Skill: instantly-campaign)

**Input:** Sequence file, `./output/apollo_contacts.json`, `INSTANTLY_API_KEY`
**Output:** Paused Instantly campaign with all leads loaded

1. Read `INSTANTLY_API_KEY` from environment (see `../SETUP.md`)
2. List connected email accounts
3. Create campaign with all 3 email steps
4. **Sanitize bodies** -- remove all `&` characters (Instantly bug)
5. Verify all step bodies are non-empty
6. Bulk load leads (up to 1000 per call)
7. Attach all sending accounts
8. Leave campaign PAUSED

**Final report to user:**
- Campaign name and status (paused)
- Number of leads loaded
- Sending accounts
- Schedule (Mon-Fri, 8-5 Pacific, `America/Vancouver` -- handles DST automatically)
- "Review in Instantly dashboard. Say 'go' when ready to launch."

## Quick Reference

| Phase | Sub-skill | Input | Output |
|-------|-----------|-------|--------|
| 1 | linkedin-comment-scraper | LinkedIn post URL | `./output/linkedin_commenters.json` |
| 2 | airtable-lead-loader | commenters JSON, base ID | Airtable table populated |
| 3 | apollo-enrichment | Airtable base + table ID | `./output/apollo_contacts.json`, Apollo contacts |
| 4 | cold-email-sequence | User context, contact count | `{campaign-name}-sequence.md` |
| 5 | instantly-campaign | sequence file, contacts JSON, `INSTANTLY_API_KEY` | Paused Instantly campaign |

**Timing expectations:**

| Phase | Duration |
|-------|----------|
| 1. Scrape | 2-5 minutes (Apify run time) |
| 2. Store | 3-10 minutes (parallel agent loading) |
| 3. Enrich | 5-15 minutes (Apollo calls + Airtable updates) |
| 4. Write | 10-30 minutes (interactive with user) |
| 5. Launch | 2-5 minutes (API calls) |
| **Total** | **~30-60 minutes** |

## Common Mistakes

| Phase | Failure mode | Fix |
|-------|--------------|-----|
| 1. Scrape | Only 20 results returned | Re-run with `maxItems: 500` |
| 1. Scrape | Invalid LinkedIn URL | Verify with user, try WebFetch to resolve canonical URL |
| 2. Store | Token limit on `list_records` | Save records to file, parse with jq/Python |
| 2. Store | Batch limit exceeded | Split into chunks of 10 |
| 3. Enrich | Low match rate (<40%) | Normal for some audiences. Proceed with what you have. |
| 3. Enrich | Cached data missing emails | Re-fetch from Airtable after enrichment completes |
| 4. Write | User wants major changes | Rewrite from scratch, do not patch |
| 5. Launch | Empty body on Instantly side | Ampersand in text. Strip all `&` characters before upload. |
| 5. Launch | Timezone rejected by Instantly | Use `America/Vancouver` for Pacific (handles DST automatically) |

## Example

A worked walkthrough using placeholder inputs:

1. **User:** "Run the linkedin pipeline on `https://www.linkedin.com/posts/janedoe_example-activity-12345`"
2. **Phase 1:** Scrape commenters via Apify. Result: 187 unique commenters saved to `./output/linkedin_commenters.json`. Report: "Scraped 187 unique commenters from Jane Doe's post. Proceeding to Airtable."
3. **Phase 2:** Create Airtable table "LinkedIn Commenters - Jane Doe" in base `appXXXXXXXXXXXXXX`, batch load 187 records via 4 parallel agents. Report: "Loaded 187 records into Airtable. Starting Apollo enrichment."
4. **Phase 3:** Bulk match 187 records via Apollo in batches of 10. Find emails for 92 people (49% match rate). Update Airtable, create Apollo contacts under label "LinkedIn Comments - Jane Doe Post", save 92 verified leads to `./output/apollo_contacts.json`. Report: "Found emails for 92 out of 187 people (49% match rate). 92 contacts ready for outreach."
5. **Phase 4:** Interactively co-write 3-email sequence with user. Gather: trigger ("Jane's post on RevOps"), product ("Taxflow"), social proof, CTA, sender name. Draft, refine, and lock each email. Save to `jane-doe-revops-sequence.md`. Report: "Sequence locked. Ready to load into Instantly."
6. **Phase 5:** Read `INSTANTLY_API_KEY` from env. Create campaign "LinkedIn - Jane Doe RevOps", strip all `&` characters from bodies, load all 92 leads in one bulk call, attach all connected sending accounts, leave PAUSED. Schedule: Mon-Fri 8-5 Pacific (`America/Vancouver`).
7. **Final report:** Campaign name, status (paused), 92 leads loaded, sending accounts, schedule, and "Review in Instantly dashboard. Say 'go' when ready to launch."

## Output

- Airtable table with all commenters + enrichment data
- Apollo contacts under named label
- Email sequence file in workspace
- Instantly campaign (paused) with 3 email steps, all leads loaded, all sending accounts attached, ready to activate on user command
