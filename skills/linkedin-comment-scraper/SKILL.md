---
name: linkedin-comment-scraper
description: Use when a user provides a LinkedIn post URL and wants to extract every commenter (full name, headline, profile URL, company, comment text) for outreach, lead generation, or analysis via the Apify actor harvestapi/linkedin-post-comments.
---

# LinkedIn Comment Scraper

## Overview

Extracts every commenter from a single LinkedIn post with profile enrichment data using the Apify actor `harvestapi/linkedin-post-comments`. The core principle: always override the actor's default `maxItems` cap, then deduplicate and filter null profiles before saving structured output.

## When to use

- User provides a LinkedIn post URL and asks to scrape, extract, or list commenters
- Building a lead list from people who commented on a specific post
- Pulling comment text + commenter profiles for outreach personalization
- Called as a sub-step by the `linkedin-comment-to-outreach` orchestrator

## When NOT to use

- Scraping reactions/likes on a post — use `linkedin-reaction-scraper` instead
- Private posts behind a login wall the actor cannot reach
- Paginated feeds, search results, or full-profile scrapes (different actors)
- Bulk-scraping many posts in a loop without rate-limit consideration

## Prerequisites

- Apify MCP server connected with the `mcp__apify__*` tools available
- `APIFY_TOKEN` environment variable set (see `../SETUP.md` for configuration)
- A valid, public LinkedIn post URL
- Write access to a local `./output/` directory for the result file

## Quick Reference

- *Input:* Public LinkedIn post URL (`/posts/`, `/feed/update/urn:li:activity:`, or `/feed/update/urn:li:ugcPost:`)
- *Output file:* `./output/linkedin_commenters.json`
- *Apify actor:* `harvestapi/linkedin-post-comments`
- *Default `maxItems` pitfall:* Actor defaults to *20* — ALWAYS override to 500+ or comments will be silently truncated
- *MCP tools used:* `mcp__apify__fetch-actor-details`, `mcp__apify__call-actor`

## The Workflow

### Step 1: Validate the LinkedIn Post URL

Accept any of these URL formats:
- `https://www.linkedin.com/posts/username_activity-ID`
- `https://www.linkedin.com/feed/update/urn:li:activity:ID`
- `https://www.linkedin.com/feed/update/urn:li:ugcPost:ID`

If the user provides a shortened or redirect URL, resolve it first via WebFetch.

### Step 2: Fetch Actor Details

```
Use: mcp__apify__fetch-actor-details
Actor: harvestapi/linkedin-post-comments
```

This confirms the actor exists and returns the input schema. Key input fields:
- `urls` (array of strings) -- LinkedIn post URLs to scrape
- `maxItems` (number) -- Maximum results to return. DEFAULTS TO 20. Always override.

### Step 3: Run a Test Scrape (maxItems: 20)

**Always test first** to validate the URL works and data structure is correct:

```
Use: mcp__apify__call-actor
Actor: harvestapi/linkedin-post-comments
Input: { "urls": ["THE_URL"], "maxItems": 20 }
```

Verify output fields are populated: `fullName`, `headline`, `profileUrl`, `comment`,
`companyName`, `reactions`.

### Step 4: Run Full Scrape (maxItems: 500+)

Once test passes, scrape everything:

```
Use: mcp__apify__call-actor
Actor: harvestapi/linkedin-post-comments
Input: { "urls": ["THE_URL"], "maxItems": 500 }
```

**CRITICAL:** The default `maxItems` is 20. Posts with 100+ comments WILL be truncated
unless you explicitly set this higher. Always set to at least 500.

### Step 5: Process and Deduplicate

1. Parse the Apify output dataset
2. **Remove null profiles** -- entries with null/empty `profileUrl` are deleted accounts
3. **Deduplicate by `profileUrl`** -- same person can comment multiple times
4. Normalize fields:
   - `fullName` -- keep as-is
   - `headline` -- keep as-is
   - `profileUrl` -- normalize to `https://www.linkedin.com/in/username` format
   - `companyName` -- if null, try to extract from headline (e.g., "CPA at Firm Name")
   - `comment` -- the comment text
   - `reactions` -- number, default 0

### Step 6: Save and Report

Save processed data to `./output/linkedin_commenters.json`.

Report to user:
- Total comments scraped (raw)
- Unique commenters (after dedup)
- Records removed (null profiles)
- Sample of first 5 names

## Composio Fallback (Optional Path)

If the founder doesn't have a direct Apify MCP connection but does have Composio.dev MCP installed, route through Composio. One Composio subscription replaces the four separate API setups (Apify, Airtable, Apollo, Instantly).

*Detection (do this first if the direct path is missing or fails):*
- Check whether `mcp__composio__COMPOSIO_SEARCH_TOOLS` is exposed in the current session
- If yes, treat Composio as the fallback transport for this skill

*Fallback workflow:*

1. Discover slugs and verify connection: call `mcp__composio__COMPOSIO_SEARCH_TOOLS` with `use_case: "scrape comments from a LinkedIn post URL using an Apify actor"` and `session: { generate_id: true }`. Save the returned `session_id` for subsequent meta calls.
2. If the response shows the `apify` toolkit is NOT connected, call `mcp__composio__COMPOSIO_MANAGE_CONNECTIONS` with `toolkits: ["apify"]` and the same `session_id`. Show the returned `redirect_url` to the user as a clickable markdown link.
3. Immediately follow with `mcp__composio__COMPOSIO_WAIT_FOR_CONNECTIONS` to poll until the connection becomes Active. Do not ask the user to confirm.
4. Once connected, run the equivalent of Step 4 above using the Composio slug:
   - Slug: `APIFY_RUN_ACTOR_SYNC`
   - Input: `{ "actor_id": "harvestapi/linkedin-post-comments", "input": { "urls": ["THE_URL"], "maxItems": 500 } }`
5. Continue with Steps 5-6 of the standard workflow exactly as written (filter null `profileUrl`, dedupe by `profileUrl`, save to `./output/linkedin_commenters.json`).

*Tool slug equivalents:*

- `mcp__apify__fetch-actor-details` -> `APIFY_GET_ACTOR`
- `mcp__apify__call-actor` -> `APIFY_RUN_ACTOR_SYNC` (waits for completion, returns dataset inline)
- `mcp__apify__get-actor-output` -> `APIFY_ACTOR_RUN_GET` (only needed for async runs)

*Output difference:* `APIFY_RUN_ACTOR_SYNC` returns the dataset items inline in the response body — no separate dataset fetch step needed. Parse items directly from the response.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Only 20 results returned | The actor's default `maxItems` is 20 — explicitly set `maxItems: 500` or higher on every call. |
| Null LinkedIn URLs in output | Filter them out. They represent deleted or deactivated accounts. |
| `companyName` is null | Parse it from the `headline` field (split on " at "). |
| Duplicate commenters in final list | Deduplicate by `profileUrl` — the same person can leave multiple comments. |
| Skipping the test scrape | Run the 20-item probe first; catches bad URLs before burning a full run. |
| Using a redirect/shortened URL | Resolve to the canonical `linkedin.com/posts/...` URL with WebFetch first. |
| Long scrapes look "stuck" | 200+ comments typically takes 2-3 minutes — that is normal, do not abort. |

## Output Schema

```json
[
  {
    "fullName": "Jane Smith, CPA",
    "headline": "Senior Accountant at Smith Advisory",
    "profileUrl": "https://www.linkedin.com/in/janesmith",
    "companyName": "Smith Advisory",
    "comment": "This is amazing! I need to try this.",
    "reactions": 3
  }
]
```

File saved to: `./output/linkedin_commenters.json`

## Example

Input URL: `https://www.linkedin.com/posts/example-author_post-id`

1. Validate the URL — it matches the `/posts/` pattern, no resolution needed.
2. Call `mcp__apify__fetch-actor-details` for `harvestapi/linkedin-post-comments` and confirm the `urls` + `maxItems` schema.
3. Test scrape: `mcp__apify__call-actor` with `{ "urls": ["https://www.linkedin.com/posts/example-author_post-id"], "maxItems": 20 }`. Verify the first row has `fullName`, `profileUrl`, and `comment` populated.
4. Full scrape: same call with `maxItems: 500`. Wait ~2 minutes for 180 comments.
5. Process: 180 raw rows → drop 6 null-profile rows → dedupe by `profileUrl` → 168 unique commenters.
6. Save to `./output/linkedin_commenters.json`.

Sample first 3 rows:

```json
[
  {
    "fullName": "Jane Smith, CPA",
    "headline": "Senior Accountant at Smith Advisory",
    "profileUrl": "https://www.linkedin.com/in/janesmith",
    "companyName": "Smith Advisory",
    "comment": "This is amazing! I need to try this.",
    "reactions": 3
  },
  {
    "fullName": "Alex Rivera",
    "headline": "Founder at Rivera Tax Group",
    "profileUrl": "https://www.linkedin.com/in/alexrivera",
    "companyName": "Rivera Tax Group",
    "comment": "Saving this for next quarter.",
    "reactions": 1
  },
  {
    "fullName": "Morgan Lee",
    "headline": "Tax Manager at Lee & Co",
    "profileUrl": "https://www.linkedin.com/in/morganlee",
    "companyName": "Lee & Co",
    "comment": "Have you tried this with multi-state filings?",
    "reactions": 0
  }
]
```

Report back: *180 raw / 168 unique / 6 removed / saved to `./output/linkedin_commenters.json`*.
