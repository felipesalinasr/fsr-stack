# Setup Guide — LinkedIn → Outreach Skill Bundle

This bundle turns any LinkedIn post URL into a fully loaded, paused Instantly cold email
campaign in about 30 minutes. Before you run it, wire up the following credentials.

---

## 1. Prerequisites

| Tool | What it does | Plan needed |
|------|--------------|-------------|
| **Claude Code** | Runs the skills | Any |
| **Apify** | Scrapes LinkedIn commenters / reactors | Free tier works to start |
| **Airtable** | Stores leads + tracks status | Free tier works |
| **Apollo.io** | Finds verified business emails | Paid (needed for bulk enrichment) |
| **Instantly.ai** | Sends the cold emails | Paid (Growth plan or higher) |

---

## 1b. Alternative Install: Composio.dev (One Connection)

If you'd rather not set up four separate API accounts, you can run the entire pipeline through a single **Composio.dev** MCP connection. Composio brokers all four services (Apify, Airtable, Apollo, Instantly) under one auth umbrella — pay once, connect once, run everywhere.

When to pick this path:
- You already have a Composio.dev subscription
- You want a single auth flow instead of four separate dashboards
- You're comfortable with Composio holding the credentials server-side

How to install:

1. Sign up at https://composio.dev and install the Composio MCP server in Claude Code (`claude mcp add composio`)
2. From any Claude session, ask: `Connect Composio toolkits: apify, airtable, apollo, instantly`
3. Claude will return a redirect link for each toolkit — click through and authorize
4. Once all 4 show "Active", skip ahead to section 5 (Set Up an Airtable Base) — the rest of the setup applies normally

Notes:
- Composio holds the API keys, so you do NOT need `APIFY_TOKEN`, `AIRTABLE_API_KEY`, or `INSTANTLY_API_KEY` in your `.env`. Apollo OAuth still works either way.
- Each skill auto-detects which transport is connected. If the direct MCPs are present, they take priority — Composio is the fallback.
- Throughput is the same on both paths. Composio's wrapper for Airtable bulk insert (`AIRTABLE_CREATE_RECORDS`, 10 per call) is actually faster than the direct MCP's 1-record-at-a-time `create_record`.
- Connection refresh: if a Composio toolkit returns 401, ask Claude to `Manage Composio connections with reinitiate_all` to rotate the underlying credential.

---

## 2. Get Your API Keys

### Apify token
1. Go to https://console.apify.com/account/integrations
2. Copy the **Personal API token** (starts with `apify_api_...`)
3. Save it as `APIFY_TOKEN`

### Airtable Personal Access Token (PAT)
1. Go to https://airtable.com/create/tokens
2. Click **Create new token**
3. Scopes needed: `data.records:read`, `data.records:write`, `schema.bases:read`, `schema.bases:write`
4. Access: add the base you want the leads to land in
5. Copy the token (starts with `pat...`)
6. Save it as `AIRTABLE_API_KEY`

### Apollo.io
- Apollo.io connects via **OAuth** through the Claude MCP server — no env var needed.
- On first run, Claude will prompt you to authorize the connection.
- You must be on a plan that includes the **People Bulk Match** endpoint (usually Basic and up).

### Instantly.ai API key
1. Log in to https://app.instantly.ai
2. Settings → Integrations → API
3. Click **Generate API Key** (use v2, not v1)
4. Copy the key (base64-encoded, ends with `==`)
5. Save it as `INSTANTLY_API_KEY`

---

## 3. Configure Environment Variables

Copy the example file and fill in your real keys:

```bash
cp .env.example .env
```

Then edit `.env`:

```
APIFY_TOKEN=apify_api_your_token_here
AIRTABLE_API_KEY=pat_your_token_here
INSTANTLY_API_KEY=your_instantly_key_here
```

**NEVER commit `.env` to git.** It is already listed in `.gitignore`. Double-check before every push.

---

## 4. Configure MCP Servers

The skills depend on three MCP servers. Copy the example config:

```bash
cp mcp-servers.example.json mcp-servers.json
```

Then edit `mcp-servers.json` and inject your tokens where indicated. It should reference the
env vars from step 3, not hardcoded values.

### Apify MCP
```json
"apify": {
  "command": "npx",
  "args": ["-y", "@apify/actors-mcp-server"],
  "env": { "APIFY_TOKEN": "${APIFY_TOKEN}" }
}
```

### Airtable MCP
```json
"airtable": {
  "command": "npx",
  "args": ["-y", "airtable-mcp-server"],
  "env": { "AIRTABLE_API_KEY": "${AIRTABLE_API_KEY}" }
}
```

### Apollo.io MCP
Connect via the Claude desktop app — Settings → Connectors → Add Apollo.io. It uses OAuth,
so you will click through a browser auth flow once.

---

## 5. Set Up an Airtable Base

Create a new base (or reuse an existing one) in Airtable. You do not need to create tables
manually — the `airtable-lead-loader` skill will create them for you with the correct schema.

Just grab the **Base ID** (starts with `app...`). You can find it at
https://airtable.com/api → pick your base → see the URL.

Have this Base ID ready when you run the pipeline. Claude will ask for it in Phase 2.

---

## 6. Connect Sending Accounts to Instantly

Before running the pipeline, make sure you have at least one warmed email account connected
to Instantly:

1. Instantly → Email Accounts → Add New
2. Connect via Google OAuth, Microsoft OAuth, or SMTP/IMAP
3. Let it warm up for 2-4 weeks before heavy sending
4. Set a conservative daily limit (25-50 per account to start)

Multiple accounts are better — Instantly rotates automatically.

---

## 7. Test the Setup

Run a dry run of Phase 1 to confirm Apify credentials work:

```
User: "Scrape the commenters from https://www.linkedin.com/posts/..."
```

You should see the `linkedin-comment-scraper` skill trigger, Apify start a run, and
results saved to `./output/linkedin_commenters.json`. If you get an auth error, double-check
`APIFY_TOKEN`.

---

## 8. Run the Full Pipeline

Once all the above is wired up, kick off the full flow:

```
User: "Run the LinkedIn to outreach pipeline on https://linkedin.com/posts/..."
```

Claude will orchestrate all 5 phases: scrape → Airtable → Apollo → write emails → Instantly.
Expect 30-60 minutes end to end, with an interactive checkpoint during Phase 4 (Write) where
you co-author the 3-email sequence.

The campaign lands **paused** in Instantly for your review. Activate it manually when you
are ready.

---

## Security Hygiene

- **Rotate keys quarterly**, or immediately if you think one has leaked.
- **Never paste keys into the chat** — Claude will ask for them via env vars only.
- **Use a password manager** (1Password, Bitwarden) to store and fetch the keys.
- **Add `gitleaks` pre-commit hooks** if you fork this repo — see the included
  `.gitleaks.toml` and `.git/hooks/pre-commit` as a template.
- **Monitor usage** on all four dashboards (Apify, Airtable, Apollo, Instantly) for
  anomalous activity.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Apify returns only 10 results | `maxItems` defaults to 10. The skill sets 500 automatically. If you see 10, re-run. |
| Airtable batch fails with token limit | Use parallel sub-agent loading (already in the skill). |
| Apollo match rate under 40% | Normal for some audiences. Proceed with what you have. |
| Instantly body shows empty after create | You have an `&` in the text. Replace every `&` with `+` or `and`. |
| Instantly timezone rejected | Pacific uses `America/Vancouver` (DST-correct), NOT `America/Los_Angeles`. `America/Dawson` drifts 1hr in summer — see `instantly-campaign/SKILL.md`. |
| Pipeline stalls in Phase 4 | That phase is interactive. Respond to Claude's prompts to lock each email. |
| Composio toolkit returns 401 | Stored credential expired. Run `Manage Composio connections with reinitiate_all` for that toolkit. |

---

## You're Ready

When `.env`, `mcp-servers.json`, an Airtable Base ID, and at least one warmed Instantly
sending account are all in place, you are good to go.

For the full pipeline overview, see `README.md` in this directory. For individual skill
details, see each skill's `SKILL.md`.
