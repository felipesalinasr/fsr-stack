---
name: linkedin-reaction-scraper
description: Use when the user wants to extract everyone who reacted (liked, celebrated, etc.) to a specific LinkedIn post for outreach, lead generation, or audience analysis, or pastes a LinkedIn post URL with intent like "scrape reactions", "who liked this post", or "get reactors". Returns full enriched profiles via Apify.
---

# LinkedIn Reaction Scraper

## Overview

Extract every person who reacted to a LinkedIn post with full profile enrichment (experience, education, location, skills) using the Apify actor `harvestapi/linkedin-post-reactions`. Reactions yield 5-10x more leads than comments and ship richer profile data out of the box.

## When to use

- User pastes a LinkedIn post URL and asks to scrape reactors, likers, or people who engaged with the post
- User wants broad audience capture from a viral or high-engagement post
- User needs enriched lead data (location, current company, title) without an immediate Apollo pass
- A parent skill (e.g. `linkedin-reaction-to-outreach`) calls this as the first stage of a pipeline

## When NOT to use

- User wants commenters instead of reactors -> use `linkedin-comment-scraper`
- The post is private, deleted, or behind a login wall the actor cannot reach
- User only needs people who wrote a comment (engagement quality > volume)
- The target is a LinkedIn profile, company page, or search result rather than a single post

## Prerequisites

- Apify MCP server connected (`mcp__apify__*` tools available)
- `APIFY_TOKEN` environment variable set on the host. See `../SETUP.md` for installation and credential setup.
- A valid LinkedIn post URL (or one that can be resolved via WebFetch)

## Quick Reference

- Input: LinkedIn post URL (`/posts/...`, `/feed/update/urn:li:activity:ID`, or `/feed/update/urn:li:ugcPost:ID`)
- Output file: `./output/linkedin_reactors.json`
- Apify actor: `harvestapi/linkedin-post-reactions`
- Critical pitfall: `maxItems` defaults to *10*. ALWAYS override to 500+ or you will silently truncate the dataset.
- Required mode: `profileScraperMode: "main"` (full profiles). `"short"` returns minimal data.

## Why Reactions vs Comments

| Feature | Comments Scraper | Reactions Scraper |
|---------|-----------------|-------------------|
| Data richness | Name, headline, comment text | Full profile: experience, education, skills, certs |
| Volume | Fewer (only people who commented) | More (likes are 5-10x more common than comments) |
| Profile fields | Basic (name, headline, company, profileUrl) | Rich (location, experience history, education, certifications, skills, connections count, about) |
| Apollo needed? | Yes -- must enrich for emails | Still needed for emails, but company/title/location already available |
| Best for | Engaged leads (took time to comment) | Broad audience capture, richer lead data |

## The Workflow

### Step 1: Validate the LinkedIn Post URL

Accept any of these URL formats:
- `https://www.linkedin.com/posts/username_slug-activity-ID-XXXX`
- `https://www.linkedin.com/feed/update/urn:li:activity:ID`
- `https://www.linkedin.com/feed/update/urn:li:ugcPost:ID`

Strip UTM parameters (`?utm_source=...`) -- they work but are unnecessary noise.

If the user provides a shortened or redirect URL, resolve it first via WebFetch.

### Step 2: Fetch Actor Details

```
Use: mcp__apify__fetch-actor-details
Actor: harvestapi/linkedin-post-reactions
```

Key input fields:
- `posts` (array of strings) -- LinkedIn post URLs to scrape
- `maxItems` (number) -- Maximum results. **DEFAULTS TO 10.** Always override.
- `profileScraperMode` (string) -- `"short"` (basic) or `"main"` (full profile). **Always use `"main"`.**
- `reactionTypeFilter` (string) -- Filter by reaction type: `LIKE`, `PRAISE`, `EMPATHY`, `APPRECIATION`, `INTEREST`, `ENTERTAINMENT`, or `ALL`. Default: all types.

### Step 3: Run a Test Scrape (maxItems: 20)

**Always test first** to validate the URL works and data structure is correct:

```
Use: mcp__apify__call-actor
Actor: harvestapi/linkedin-post-reactions
Input: { "posts": ["THE_URL"], "maxItems": 20, "profileScraperMode": "main" }
```

Verify output fields populated:
- `actor.name`, `actor.headline`, `actor.linkedinUrl`
- `actor.location.parsed` (city, state, country)
- `actor.currentPosition` (company, title)
- `actor.experience` (full history)
- `reactionType` (LIKE, PRAISE, etc.)

### Step 4: Run Full Scrape (maxItems: 500+)

Once test passes, scrape everything:

```
Use: mcp__apify__call-actor
Actor: harvestapi/linkedin-post-reactions
Input: { "posts": ["THE_URL"], "maxItems": 500, "profileScraperMode": "main" }
```

**CRITICAL:** The default `maxItems` is 10. Posts with 100+ reactions WILL be truncated
unless you explicitly set this higher. Always set to at least 500.

**For posts with 500+ reactions:** Set `maxItems` to the expected count. Viral posts can have
thousands of reactions. Ask the user if they want all or a cap.

### Step 5: Process and Deduplicate

1. Parse the Apify output dataset (use `get-actor-output` if needed for pagination)
2. **Remove null profiles** -- entries with null/empty `actor.linkedinUrl` are deleted accounts
3. **Deduplicate by `actor.linkedinUrl`** -- same person can react to reposts
4. Normalize and extract fields:

```python
{
    "fullName": item["actor"]["name"],
    "firstName": item["actor"]["firstName"],
    "lastName": item["actor"]["lastName"],
    "headline": item["actor"]["headline"],
    "profileUrl": item["actor"]["linkedinUrl"],
    "companyName": item["actor"]["currentPosition"][0]["companyName"] if item["actor"].get("currentPosition") else None,
    "jobTitle": item["actor"]["currentPosition"][0].get("position") if item["actor"].get("currentPosition") else item["actor"].get("position"),
    "city": item["actor"]["location"]["parsed"]["city"] if item["actor"].get("location", {}).get("parsed") else None,
    "state": item["actor"]["location"]["parsed"]["state"] if item["actor"].get("location", {}).get("parsed") else None,
    "country": item["actor"]["location"]["parsed"]["country"] if item["actor"].get("location", {}).get("parsed") else None,
    "connectionsCount": item["actor"].get("connectionsCount"),
    "about": item["actor"].get("about"),
    "reactionType": item["reactionType"],
    "verified": item["actor"].get("verified", False),
    "premium": item["actor"].get("premium", False),
    "openToWork": item["actor"].get("openToWork", False)
}
```

5. **Extract company from headline** if `currentPosition` is null:
   - "CPA at Smith Advisory" -> companyName: "Smith Advisory"
   - "Senior Accountant | Deloitte" -> companyName: "Deloitte"

### Step 6: Save and Report

Save processed data to `./output/linkedin_reactors.json`.

Report to user:
- Total reactions scraped (raw)
- Unique reactors (after dedup)
- Records removed (null profiles)
- Reaction type breakdown (X likes, Y celebrates, etc.)
- Sample of first 5 names with titles
- Note: Full profile data available (experience, education, skills) -- richer than comment scraper

## Data Schema (Full Output from Actor)

Each reactor record contains:

```json
{
  "reactionType": "LIKE",
  "postId": "urn:li:ugcPost:...",
  "actor": {
    "name": "Jane Doe",
    "firstName": "Jane",
    "lastName": "Doe",
    "headline": "Example Role | Example Company",
    "linkedinUrl": "https://www.linkedin.com/in/example-profile",
    "publicIdentifier": "example-profile",
    "location": {
      "linkedinText": "Example City, Example State, United States",
      "parsed": {
        "city": "Example City",
        "state": "Example State",
        "country": "United States",
        "countryCode": "US"
      }
    },
    "currentPosition": [
      { "companyName": "Example Company LLC", "dateRange": { "start": { "month": 1, "year": 2024 } } }
    ],
    "experience": [ ],
    "education": [ ],
    "certifications": [ ],
    "skills": [ { "name": "Tax planning & preparation" } ],
    "connectionsCount": 239,
    "followerCount": 251,
    "about": "...",
    "verified": true,
    "premium": false,
    "openToWork": false
  }
}
```

## Composio Fallback (Optional Path)

If the founder is on Composio.dev MCP instead of the direct Apify MCP, route this skill through Composio. Same Apify actor, same input — only the transport changes.

*Detection:*
- `mcp__composio__COMPOSIO_SEARCH_TOOLS` is available in the session
- The direct `mcp__apify__*` tools are missing or error on first call

*Fallback workflow:*

1. Discover slugs and check connection: call `mcp__composio__COMPOSIO_SEARCH_TOOLS` with `use_case: "scrape reactions/likes from a LinkedIn post URL using an Apify actor"` and `session: { generate_id: true }`. Save the `session_id`.
2. If the `apify` toolkit isn't connected, call `mcp__composio__COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["apify"]` and surface the `redirect_url` as a clickable link.
3. Poll with `mcp__composio__COMPOSIO_WAIT_FOR_CONNECTIONS` until Active.
4. Run the equivalent of Steps 3 and 4 using the Composio slug:
   - Slug: `APIFY_RUN_ACTOR_SYNC`
   - Input: `{ "actor_id": "harvestapi/linkedin-post-reactions", "input": { "posts": ["THE_URL"], "maxItems": 500, "profileScraperMode": "main" } }`
5. Continue with Steps 5-6 of the standard workflow as written.

*Tool slug equivalents:*

- `mcp__apify__fetch-actor-details` -> `APIFY_GET_ACTOR`
- `mcp__apify__call-actor` -> `APIFY_RUN_ACTOR_SYNC`
- `mcp__apify__get-actor-output` -> `APIFY_ACTOR_RUN_GET`

*Output difference:* `APIFY_RUN_ACTOR_SYNC` returns dataset items inline. The shape of each `actor.*` field is identical to the direct path — the parser in Step 5 works unchanged.

*Long-run note:* Composio's sync wrapper has a 300-second timeout. If a viral post with 1000+ reactions exceeds that, switch to async: call `APIFY_RUN_ACTOR` (no sync), capture the run ID, then poll `APIFY_ACTOR_RUN_GET` until status is `SUCCEEDED`, then read the dataset.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Only 10 results returned | Default `maxItems` is 10. Always set to 500+. |
| Null LinkedIn URLs in output | Filter out. These are deleted/deactivated accounts. |
| `currentPosition` is null | Parse company from `headline` field. |
| Some posts return 0 results | Post may be private, deleted, or too old. Try `urn:li:activity:ID` format. |
| Using `profileScraperMode: "short"` | Returns minimal data. Always use `"main"` for full profiles. |
| Surprise on long runs | 500+ reactions with `"main"` mode = 3-5 minutes. Normal. |
| Duplicate reactors across reposts | Same person reacts to original + repost. Deduplicate by `actor.linkedinUrl`. |
| UTM parameters in URL | Strip them. They work but add noise. |
| Hardcoding `/tmp/...` paths | Use `./output/linkedin_reactors.json` so it works on Windows and CI. |

## Reaction Types

| Type | LinkedIn Icon | Meaning |
|------|--------------|---------|
| LIKE | Thumbs up | Standard like |
| PRAISE | Clapping hands | Celebrate |
| EMPATHY | Heart | Love |
| APPRECIATION | Lightbulb | Insightful |
| INTEREST | Thinking face | Curious |
| ENTERTAINMENT | Laughing face | Funny |

Use `reactionTypeFilter` to target specific engagement types.

## Example

User pastes: `https://www.linkedin.com/posts/example-user_launch-activity-7100000000000000000-AbCd?utm_source=share`

1. Strip the `?utm_source=share` -> clean URL.
2. Call `mcp__apify__fetch-actor-details` for `harvestapi/linkedin-post-reactions` to confirm the input schema.
3. Test run with `{ "posts": ["<clean URL>"], "maxItems": 20, "profileScraperMode": "main" }`. Inspect a record like:
   - `actor.name`: "Jane Doe"
   - `actor.currentPosition[0].companyName`: "Example Company LLC"
   - `actor.location.parsed.city`: "Example City"
4. Full run with `{ "posts": ["<clean URL>"], "maxItems": 500, "profileScraperMode": "main" }`.
5. Filter null `linkedinUrl`, dedupe by `linkedinUrl`, normalize fields, save to `./output/linkedin_reactors.json`.
6. Report: "Scraped 412 raw reactions -> 387 unique reactors after dedup. 312 LIKE, 48 PRAISE, 27 EMPATHY. Saved to ./output/linkedin_reactors.json. Ready to hand off to airtable-lead-loader."

## Output

- File: `./output/linkedin_reactors.json` -- all reactors with enriched profiles
- Ready for `airtable-lead-loader` skill (map reactor fields to Airtable schema)
- Richer data than comment scraper -- may reduce Apollo enrichment needs for company/title/location
- Emails still require Apollo enrichment
