---
name: linkedin-reaction-to-outreach
description: Use when the user wants to turn LinkedIn post reactors (likes, celebrates, loves) into a paused Instantly cold email campaign, mentions a "reactions pipeline", asks to "scrape reactions and email them", or pastes a LinkedIn post URL with intent to reach the people who reacted. Orchestrates five sub-skills (reaction scraping, Airtable loading, Apollo enrichment, sequence writing, Instantly setup) and produces a paused campaign ready for review.
---

# LinkedIn Reaction-to-Outreach Pipeline

## Overview

Convert every reactor on a LinkedIn post into a paused, ready-to-launch Instantly cold email campaign by chaining five sub-skills in a single deterministic pipeline. Reactor profiles arrive richer than commenter profiles, so this orchestrator favors volume plays where company, title, and location data are already in the scrape.

## When to use

- A LinkedIn post URL is provided with intent to reach the people who reacted (liked, celebrated, loved, etc.)
- The user asks for a "reactions pipeline", "outreach from reactions", or "scrape reactions and email them"
- Volume matters more than per-lead intensity (reactors are 5-10x larger than commenters)
- The user wants full LinkedIn profile data (experience, education, skills) loaded into Airtable

## When NOT to use

- Use `linkedin-comment-to-outreach` when the target audience is *commenters* on a post (smaller, higher-intent list)
- Use `linkedin-reaction-scraper` directly when the user only wants the raw reactor data and no downstream pipeline
- Use `instantly-campaign` directly when leads already exist in Apollo or Airtable and only the campaign step is needed
- Skip this skill for one-off lead lookups, ABM research, or anything not anchored to a LinkedIn post URL

## The Pipeline

```
LinkedIn Post URL
       |
       v
[1. linkedin-reaction-scraper]  -- Apify scrape, full profiles, deduplicate
       |
       v
[2. airtable-lead-loader]      -- Create table, batch load records
       |
       v
[3. apollo-enrichment]         -- Bulk email lookup, update Airtable, create contacts
       |
       v
[4. cold-email-sequence]       -- Co-write 3 emails with user (interactive)
       |
       v
[5. instantly-campaign]        -- Create campaign, load leads, configure accounts
       |
       v
Campaign ready for review (paused)
```

---

## Why Reactions vs Comments Pipeline

| Dimension | Comments Pipeline | Reactions Pipeline (this one) |
|-----------|------------------|-------------------------------|
| Volume | Lower (commenting takes effort) | Higher (liking is easy, 5-10x more people) |
| Profile data from scrape | Basic: name, headline, profileUrl | Rich: full experience, education, skills, certs, location |
| Apollo dependency | High -- need Apollo for company, title, location | Lower -- company, title, location already in scrape data |
| Lead quality signal | Strong (took time to write) | Moderate (one-click action) |
| Best for | Smaller, high-intent lists | Broader audience capture, volume plays |

---

## Prerequisites

- **MCP tools:** Apify, Airtable, Apollo.io
- **API key:** Instantly API key (user provides or stored)
- **Airtable base:** Existing base ID (user provides or we find it)
- **User input needed for Step 4:** Social proof, product description, CTA preferences

---

## The Workflow

### Phase 1: Scrape Reactions (Skill: linkedin-reaction-scraper)

**Input:** LinkedIn post URL from user
**Output:** `./output/linkedin_reactors.json`

1. Validate the LinkedIn post URL (any format accepted)
2. Strip UTM parameters
3. Test scrape with `maxItems: 20`, `profileScraperMode: "main"`
4. Verify rich data fields populated: `actor.name`, `actor.headline`, `actor.currentPosition`, `actor.location.parsed`, `actor.experience`
5. Full scrape with `maxItems: 500` (increase for viral posts)
6. Process results:
   - Remove null profiles (deleted/deactivated accounts)
   - Deduplicate by `actor.linkedinUrl`
   - Extract company from `headline` if `currentPosition` is null
   - Parse reaction type breakdown
7. Save to `./output/linkedin_reactors.json`

**Key differences from comment scraper:**
- Actor: `harvestapi/linkedin-post-reactions` (not `linkedin-post-comments`)
- `profileScraperMode: "main"` gives full profiles -- ALWAYS use this
- Default `maxItems` is 10 (even lower than comment scraper's 20) -- ALWAYS override
- Data nested under `actor` key (not flat like comment scraper)
- `reactionType` field available for filtering (LIKE, PRAISE, EMPATHY, etc.)

**Checkpoint:** Report to user:
- "Scraped X unique reactors from [Author]'s post"
- Reaction breakdown (X likes, Y celebrates, Z loves, etc.)
- "Full profiles captured: experience, education, skills, location"
- "Proceeding to Airtable."

---

### Phase 2: Store (Skill: airtable-lead-loader)

**Input:** `./output/linkedin_reactors.json`, Airtable Base ID
**Output:** Airtable table populated, record IDs saved

1. List Airtable bases, confirm with user
2. Create table: "LinkedIn Reactors - [Author Name]"
3. Expanded 22-field schema -- captures ALL rich data from the reactions scraper:

| # | Field | Airtable Type | Source | Notes |
|---|-------|---------------|--------|-------|
| 1 | Full Name | Single line text | `actor.name` | |
| 2 | First Name | Single line text | `actor.firstName` | |
| 3 | Last Name | Single line text | `actor.lastName` | |
| 4 | Headline | Single line text | `actor.headline` | |
| 5 | LinkedIn URL | URL | `actor.linkedinUrl` | Canonical `/in/slug` URL |
| 6 | Company | Single line text | `actor.currentPosition[0].companyName` | Fallback: parse from headline |
| 7 | Company LinkedIn URL | URL | `actor.currentPosition[0].companyLinkedinUrl` | May be null |
| 8 | Job Title | Single line text | `actor.currentPosition[0].position` | Fallback: first segment of headline |
| 9 | City | Single line text | `actor.location.parsed.city` | |
| 10 | State | Single line text | `actor.location.parsed.state` | |
| 11 | Country | Single line text | `actor.location.parsed.country` | |
| 12 | About | Long text | `actor.about` | Full LinkedIn bio |
| 13 | Experience | Long text | `actor.experience` | Formatted (see below) |
| 14 | Education | Long text | `actor.education` | Formatted (see below) |
| 15 | Top Skills | Single line text | `actor.topSkills` or `actor.skills` | Comma-separated list |
| 16 | Connections | Number | `actor.connectionsCount` | |
| 17 | Followers | Number | `actor.followerCount` | |
| 18 | Reaction Type | Single line text | `reactionType` | LIKE, PRAISE, EMPATHY, APPRECIATION, INTEREST, ENTERTAINMENT |
| 19 | Email | Email | _(empty)_ | Filled by Apollo in Phase 3 |
| 20 | Apollo Match | Checkbox | _(false)_ | Set by Phase 3 |
| 21 | Source | Single line text | Auto | "LinkedIn Reactions - [Post URL slug]" |
| 22 | Profile JSON | Long text | Full `actor` object | Raw JSON backup for data not in other fields |

#### Formatting Complex Fields

**Experience** -- flatten the array into readable text:
```
Senior Accountant @ Deloitte (Jan 2020 - Present, 4 yrs 3 mos)
Staff Accountant @ PwC (Jun 2017 - Dec 2019, 2 yrs 7 mos)
```
Pattern: `{position} @ {companyName} ({startDate.text} - {endDate.text}, {duration})`
One line per role. Most recent first (array is already sorted).

**Education** -- same approach:
```
Master of Science, Accounting @ Colorado State University (2019 - 2022)
Bachelor's, Finance @ Monroe University (2008 - 2013)
```
Pattern: `{degree} @ {schoolName} ({period})`

**Top Skills** -- comma-separated string:
```
Tax Planning, Auditing, Financial Reporting
```
Source: `actor.skills[].name` array. If `actor.topSkills` exists, use that instead.

**Profile JSON** -- store `JSON.stringify(actor)` as a backup. This preserves certifications, volunteering, recommendations, publications, and any other fields not mapped to dedicated columns. Useful for future analysis without re-scraping.

#### Field Mapping Code

Walk every reactor item, pull `actor` plus the first `currentPosition` and `location.parsed`, format `experience` and `education` arrays into newline-joined strings, fall back to parsing the headline for company when `currentPosition` is empty, then emit the 22-field record.

See the `airtable-lead-loader` skill for the full mapping logic and reference implementation.

4. Batch load via parallel agents (4 agents, 10 records per `create_record` call)
5. Verify load count matches scrape count

**Checkpoint:** Report:
- "Loaded X records into Airtable with full profile data"
- "Y have company data, Z have location, W have bios"
- "Experience and education captured for all profiles"
- "Starting Apollo enrichment for emails."


---

### Phase 3: Enrich (Skill: apollo-enrichment)

**Input:** Airtable Base ID, Table ID
**Output:** Airtable updated with emails, Apollo contacts created

1. Pull all records from Airtable
2. Batch into groups of 10 for Apollo `apollo_people_bulk_match`
3. Run enrichment via parallel agents (4 agents)
4. Update Airtable records with:
   - Email (primary purpose of this step)
   - Company (Apollo override if scrape data was parsed from headline)
   - Title (Apollo override if more specific)
   - City, State, Country (Apollo override if scrape had null location)
5. Set `Apollo Match` = true for matched records
6. Create Apollo contacts under label: "LinkedIn Reactions - [Author] Post"
7. Re-fetch records with emails, save to `./output/apollo_contacts.json`

**Note:** Since reactions scraper already provides company/title/location, Apollo enrichment here is primarily for EMAIL addresses. Match rates may be slightly different than comment scraper since we have richer input data for matching.

**Warning:** Apollo has a stale cache bug. After bulk match, always re-fetch from Airtable to get the latest data rather than using the match response directly.

**Checkpoint:** Report: "Found emails for X out of Y people (Z% match rate). X contacts ready for outreach."

---

### Phase 4: Write (Skill: cold-email-sequence)

**Input:** User context (product, social proof, trigger), contact count
**Output:** `{campaign-name}-sequence.md`

This is the **interactive step**. Work with the user one email at a time.

1. Gather inputs from user:
   - **Trigger:** What the LinkedIn post was about (the hook)
   - **Product/offer:** What we're selling
   - **Social proof:** Results, case studies, numbers
   - **CTA:** What's the ask (usually "I'm in" reply)
   - **Sender name:** Who it's from

2. Draft Email 1 (Day 0 -- Opener)
   - Present to user, refine, lock

3. Draft Email 2 (Day 3 -- Follow-up)
   - Present to user, refine, lock

4. Draft Email 3 (Day 7 -- Breakup)
   - Present to user, refine, lock

5. Save complete sequence to `{campaign-name}-sequence.md`

**James Shields Framework Rules:**
- Personalize SUBJECT (reference the post), not the body
- 3 sentences max + PS line
- Low-friction CTA ("just reply 'I'm in'")
- Irresistible offer in PS
- No em dashes (use commas or periods)
- No exclamation points
- No bold/italic/formatting
- No "Hi [Name]" opener -- jump straight in
- NEW social proof per email (never repeat across emails)
- Subject line references the specific post/author they reacted to

**Checkpoint:** "Sequence locked. Ready to load into Instantly."

---

### Phase 5: Launch (Skill: instantly-campaign)

**Input:** Sequence file, `./output/apollo_contacts.json`, Instantly API key
**Output:** Paused Instantly campaign with all leads loaded

1. Get/confirm Instantly API key from the `INSTANTLY_API_KEY` environment variable (see `../SETUP.md` for how to configure). Never hardcode the key in this file.
2. List connected email accounts via `GET /api/v2/accounts`
3. Create campaign:
   - Name: "[Author] Post Reactions - [Product] Outreach"
   - Timezone: `America/Vancouver` (Pacific w/ DST). Instantly rejects `America/Los_Angeles`; Vancouver is the safe substitute. See the `instantly-campaign` skill for the full timezone workaround table.
   - Schedule: Mon-Fri, 8:00 AM - 5:00 PM
   - Daily limit: 25 per account
4. Add 3 email steps with correct delay logic:
   - Email 1: Day 0 (delay: 0)
   - Email 2: Day 3 (delay: 3 -- relative to Email 1)
   - Email 3: Day 7 (delay: 4 -- relative to Email 2, NOT 7)
5. **CRITICAL: Sanitize all email bodies** -- replace every `&` with `+` or "and"
   - The Instantly API silently drops the entire body if it contains `&`
   - No error returned -- body just becomes empty string
   - Test by reading back campaign after creation to verify bodies are non-empty
6. Bulk load leads (up to 1000 per call)
   - Map from `./output/apollo_contacts.json`:
     - `email` → email
     - `firstName` → first_name
     - `lastName` → last_name
     - `companyName` → company_name
7. Attach all sending accounts to the campaign
8. **NEVER auto-activate.** Leave campaign status = 0 (paused)

**Final report to user:**
- Campaign name and ID
- Status: PAUSED
- Number of leads loaded
- Sending accounts attached (list them)
- Schedule: Mon-Fri, 8-5 Pacific
- "Review in your Instantly dashboard. Say 'activate' when ready to launch."

---

## Common Mistakes

| Phase | Common Error | Recovery |
|-------|-------------|----------|
| 1. Scrape | Only 10 results returned | Default `maxItems` is 10. Always set 500+. |
| 1. Scrape | Post returns 0 results | Post may be private/deleted. Try `urn:li:activity:ID` format. |
| 1. Scrape | `profileScraperMode` was "short" | Re-run with `"main"`. Short mode misses experience/education. |
| 2. Store | Airtable batch limit exceeded | Split into chunks of 10 records per `create_record` call. |
| 2. Store | Token limit on `list_records` | Save to file, parse with Python. |
| 3. Enrich | Low match rate (<40%) | Normal for some audiences. Proceed with what's available. |
| 3. Enrich | Stale cache missing emails | Re-fetch from Airtable after enrichment, not from Apollo response. |
| 4. Write | User wants major rewrite | Start email from scratch. Don't patch. |
| 5. Launch | Empty body in Instantly | Ampersand bug. Remove ALL `&` characters from bodies. |
| 5. Launch | Timezone rejected | Use `America/Dawson` (Pacific) or `America/Detroit` (Eastern). |
| 5. Launch | v1 endpoint auth failure | Use v2 endpoints only (`/api/v2/...` with Bearer token). |

---

## Timing Expectations

| Phase | Duration | Notes |
|-------|----------|-------|
| 1. Scrape | 3-8 minutes | `profileScraperMode: "main"` takes longer than comment scraping |
| 2. Store | 3-10 minutes | Parallel agent loading, depends on record count |
| 3. Enrich | 5-15 minutes | Apollo calls + Airtable updates |
| 4. Write | 10-30 minutes | Interactive with user -- cannot be rushed |
| 5. Launch | 2-5 minutes | API calls to Instantly |
| **Total** | **~30-70 minutes** | Slightly longer than comments pipeline due to richer scrape |

---

## Data Flow

```
LinkedIn Post URL
    -> Apify: harvestapi/linkedin-post-reactions (profileScraperMode: "main")
    -> ./output/linkedin_reactors.json (all reactors with full profiles)
    -> Airtable: new table "LinkedIn Reactors - [Author]" (22 fields)
         (pre-filled: name, headline, company, title, city, state, country,
          about, experience, education, skills, connections, followers,
          reaction type, company LinkedIn URL, profile JSON backup)
    -> Apollo: bulk people match (batches of 10) -- primarily for EMAILS
    -> Airtable: updated with emails + Apollo Match flag
    -> Apollo: contacts created with label "LinkedIn Reactions - [Author] Post"
    -> ./output/apollo_contacts.json (email-verified leads)
    -> Sequence file: {campaign-name}-sequence.md (3 emails, James Shields framework)
    -> Instantly: campaign + leads + accounts (API v2)
    -> PAUSED campaign ready for user review
```

---

## Output

At completion, the user has:

1. **Airtable table** -- all reactors with full profile data + email enrichment
2. **Apollo contacts** -- under named label, ready for CRM workflows
3. **Email sequence file** -- 3 locked emails in workspace
4. **Instantly campaign (PAUSED)** with:
   - 3 email steps loaded (bodies verified non-empty)
   - All leads with emails loaded
   - All sending accounts attached
   - Mon-Fri 8-5 Pacific schedule
   - Ready to activate on user command


---

## Quick Reference

| Phase | Sub-skill | Input | Output |
|-------|-----------|-------|--------|
| 1. Scrape | `linkedin-reaction-scraper` | LinkedIn post URL | `./output/linkedin_reactors.json` |
| 2. Store | `airtable-lead-loader` | Reactors JSON + Base ID | Airtable table populated (22 fields) |
| 3. Enrich | `apollo-enrichment` | Airtable Base ID + Table ID | Emails added, `./output/apollo_contacts.json` |
| 4. Write | `cold-email-sequence` | User context (offer, proof, CTA) | `{campaign-name}-sequence.md` |
| 5. Launch | `instantly-campaign` | Sequence file + Apollo contacts JSON | Paused Instantly campaign |

---

## Example

**Input:** `https://www.linkedin.com/posts/jane-doe_tax-strategy-activity-1234567890`

**Walkthrough:**

1. **Scrape** -- run `linkedin-reaction-scraper` with `maxItems: 500`, `profileScraperMode: "main"`. Result: 287 unique reactors saved to `./output/linkedin_reactors.json` with full experience, education, skills, and location.
2. **Store** -- create Airtable table `LinkedIn Reactors - Jane Doe` with 22 fields. Batch-load via 4 parallel agents. Result: 287 records, 268 with company data, 251 with location.
3. **Enrich** -- run Apollo bulk match in batches of 10. Result: 184 emails found (64% match rate), Apollo contacts created under label `LinkedIn Reactions - Jane Doe Post`, refreshed records exported to `./output/apollo_contacts.json`.
4. **Write** -- collect inputs (trigger: tax strategy post, offer: outsourced tax ops, proof: "saved Acme 18 hrs/week"), co-author Email 1, 2, 3 with the user, save to `jane-doe-reactions-sequence.md`.
5. **Launch** -- create Instantly campaign `Jane Doe Post Reactions - Tax Ops Outreach`, timezone `America/Vancouver`, schedule Mon-Fri 8am-5pm, daily limit 25/account, sanitize bodies (strip `&`), bulk-load 184 leads, attach all sending accounts, leave status = 0.

**Final report:** "Campaign `Jane Doe Post Reactions - Tax Ops Outreach` (`cmp_abc123`) is PAUSED with 184 leads loaded across 3 sending accounts. Mon-Fri 8-5 Pacific. Review in Instantly and say `activate` when ready."
