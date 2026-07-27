# FSR-Stack — Felipe's Skill Collection

A curated, production-grade skill bundle for Claude Code. This is the first drop: a complete LinkedIn-to-Cold-Outreach pipeline. More skills coming.

## What It Does

Turn a single LinkedIn post URL into a fully loaded, paused cold email campaign in Instantly.ai. The bundle orchestrates scraping, enrichment, copywriting, and campaign setup end-to-end so you can go from "that post looks like my ICP" to "review and launch" without switching tools or writing glue code.

Built for Claude Code. Drop the skills in, configure four API keys, invoke one command, get a campaign.

## Value Proposition

Manual process (what founders and SDRs do today):
- Scroll LinkedIn post, copy commenter names into a sheet (30-60 min)
- Hunt for emails one by one in Apollo or Hunter (1-2 hours)
- Write three personalized emails from scratch (1-2 hours)
- Build the campaign in Instantly, paste copy, upload CSV, configure schedule (30-45 min)
- Total: 3 to 6 hours per campaign, and the copy usually sounds generic by email 2

With this bundle:
- Paste the post URL. Answer five questions about your offer. Review the three emails as they are drafted.
- Total: 30 to 60 minutes per campaign, ~80% of it spent on the copy (the part that actually matters)
- Net time savings: 2 to 5 hours per campaign

Use cases where this earns its keep:
- Conference follow-ups. A speaker posts their deck, 400 people react, you reach every qualified attendee in under an hour.
- Viral post prospecting. Competitor or thought leader drops a post that hits your ICP dead center. You do not read 300 comments manually.
- Niche audience outreach. CPAs who reacted to a tax planning post. Founders who commented on a fundraising thread. Whatever the niche, the pipeline does not care.
- Repeatable weekly motion. Pick 3 posts a week from your ICP's feed. Run the pipeline. Build pipeline.

## Pipeline Diagram

```
LinkedIn Post URL
     |
     v
[1. Scraper]   -- Apify extracts commenters or reactors (with full profiles)
     |
     v
[2. Store]     -- Save leads to Airtable, OR Google Sheets (the -gsheets variant)
     |
     v
[3. Apollo]    -- Bulk match to find verified emails + enrich company/title/location
     |
     v
[4. Sequence]  -- Co-write a 3-email sequence (James Shields framework)
     |
     v
[5. Instantly] -- Create a paused campaign with all leads and sending accounts loaded
     |
     v
Paused campaign, ready for human review
```

## What's Inside

Three orchestrator skills (end-to-end pipelines):

- `linkedin-comment-to-outreach` -- For people who COMMENTED on a post. Higher intent (commenting takes effort), lower volume. Best for small, high-quality lists. Stores leads in Airtable.
- `linkedin-comment-to-outreach-gsheets` -- Same commenter pipeline, but stores leads in **Google Sheets** instead of Airtable. Pick this if you'd rather work in a spreadsheet than set up an Airtable base.
- `linkedin-reaction-to-outreach` -- For people who REACTED to a post. Higher volume (5-10x more reactors than commenters) and richer profile data (experience, education, skills pulled directly in the scrape). Best for broader audience plays.

Eight individual skills (the pipeline steps, usable standalone):

- `linkedin-comment-scraper` -- Apify actor `harvestapi/linkedin-post-comments`. Extracts fullName, headline, profileUrl, company, comment text, reaction counts.
- `linkedin-reaction-scraper` -- Apify actor `harvestapi/linkedin-post-reactions` with `profileScraperMode: "main"`. Returns full LinkedIn profiles: experience history, education, skills, certifications, location, connections count.
- `xquik-x-tweet-scraper`: Bounded X searches, timelines, lists, posts, and conversations through the Xquik Apify Actor.
- `xquik-x-follower-scraper`: Bounded X audience relations, public profile filters, deduplication, and overlap through the Xquik Apify Actor.
- `airtable-lead-loader` -- Creates a new table with the full pipeline schema (lead tracking + enrichment + outreach status). Batch-loads records using parallel agents to work around Airtable's 1-record-per-call limit.
- `apollo-enrichment` -- Uses Apollo.io `apollo_people_bulk_match` (batches of 10) to find verified emails. Expected match rate: 50-70%. Updates Airtable, creates Apollo contacts under a named label for CRM workflows.
- `cold-email-sequence` -- Co-writes a 3-email sequence using the James Shields framework: personalized subject (not body), 3 sentences plus PS, irresistible offer, low-friction CTA. Interactive -- locks each email with you before moving to the next.
- `instantly-campaign` -- Creates the campaign via Instantly REST API v2, handles the known bugs (timezone enum restrictions, the ampersand body-drop bug), loads up to 1000 leads per call, attaches all sending accounts. Always leaves the campaign paused for human review.

## Also Inside: Market Pulse (English and Spanish)

`market-pulse`: live lodging market intelligence for any city, delivered as a branded, multi tab Google Sheet plus a one screen brief. Built for hotels and short term rental hosts who want to understand and out position the Airbnb and OTA competition in their own market.

It blends competing supply across Airbnb, Booking.com, Expedia and Hotels.com, Vrbo, and Hostelworld, then builds a seven tab command center: a comp set with price and occupancy heat maps, a day by day demand calendar, a voice of guest read, a rate parity tab with verify links and capture dates, revenue actions, and a researched demand drivers calendar. Every read ends in three concrete moves, not a dashboard.

Fully bilingual, automatically. Ask in English and the whole deliverable comes back in English. Ask in Spanish (a "pulso de mercado") and it comes back in Spanish: tabs, labels, and all. The skill matches whatever language you write in. It needs a web data layer (Apify plus a no login Airbnb read source), Google Sheets, and a live web search tool connected.

Invoke it with, for example: `give me a market pulse for Medellin for three nights in late July`, or `haz un pulso de mercado de Medellin para fin de julio`.

## Quick Start

See SETUP.md for full installation steps.

### Install in Houston (no terminal needed)

Houston is a desktop app that runs these skills for you — no command line required.

1. In Houston, open your agent's Skills.
2. Add the skills from this repo: download or clone the repo, then drop each folder from `skills/` into your agent's skills (or just ask your Houston agent to "install the skills from github.com/felipesalinasr/fsr-stack").
3. Connect the apps the pipeline needs (Apify, Apollo, Instantly, and Airtable or Google Sheets) from the Integrations tab. Houston brokers these through Composio, so it's one connect flow per app — no API keys to copy.
4. Just tell your agent what you want, e.g. `run the linkedin comment pipeline on this post: [your LinkedIn post URL]` (add "use google sheets" for the spreadsheet variant).

### Install in Claude Code

Fast path:
1. Install Claude Code
2. Clone this repo: `git clone https://github.com/felipesalinasr/fsr-stack.git`
3. Copy the skills: `mkdir -p ~/.claude/skills && cp -r fsr-stack/skills/* ~/.claude/skills/`
4. Get API keys for Apify, Airtable, Apollo.io, and Instantly.ai — OR connect Composio.dev MCP and skip the 4 individual setups (see `SETUP.md` section 1b)
5. Invoke from any Claude Code session: `run the linkedin comment pipeline on this URL: [your LinkedIn post URL]`

## Two Install Paths

You can run this bundle two ways:

- **Direct MCP setup (4 connections):** Install the Apify, Airtable, and Apollo MCP servers individually and put `APIFY_TOKEN`, `AIRTABLE_API_KEY`, and `INSTANTLY_API_KEY` in `.env`. Apollo connects via OAuth through claude.ai. See SETUP.md section 2.
- **Composio.dev (1 connection):** Install only the Composio MCP server and authorize the four toolkits (`apify`, `airtable`, `apollo`, `instantly`) once. No env vars needed for the four pipeline services. See SETUP.md section 1b.

Both paths run the same skills with identical results. The skills detect which transport is connected and route automatically — direct MCPs take priority, Composio is the fallback.

## Requirements

- Claude Code installed
- Apify account (free tier works for testing; paid needed for volume)
- Airtable account (free tier works)
- Apollo.io account (paid plan required for email export)
- Instantly.ai account (paid plan required to send)
- ~30-60 minutes to run end-to-end per campaign (most of it in email copywriting)

## Security

Never commit `.env` or `mcp-servers.json` with real credentials. The workspace `.gitignore` already excludes them. See SETUP.md for the pre-commit hook that prevents accidental leaks.

## License

MIT -- free to use, modify, and share.

## Credits

Built by Felipe Salinas at Taxflow. Cold email copy framework credited to James Shields.
