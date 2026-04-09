---
name: cold-email-sequence
description: Use when writing a 3-email cold outreach sequence, drip campaign, or multi-step prospect email copy, including downstream of any lead enrichment step that produced a list of cold contacts needing personalized opener, follow-up, and breakup emails.
---

# Cold Email Sequence Writer

## Overview

Cold emails win when the subject line is personalized to a real trigger, the body is short and specific, and the CTA is low-friction. This skill co-creates a 3-email sequence with the user one email at a time using the James Shields cold email framework, locking each draft before moving to the next so voice, social proof, and offer all stay tight.

> James Shields cold email framework: a widely used outbound playbook that emphasizes trigger-based subjects, three-sentence bodies, irresistible no-strings offers, and one-word reply CTAs in place of demo bookings.

## When to use

- Writing a brand new cold outreach sequence for a list of prospects
- Downstream of any lead enrichment step (Apollo, Hunter, Clay, etc.) that produced contacts ready for outreach
- Building a 3-step drip campaign (opener, follow-up, breakup)
- Refreshing tired cold email copy with a proven framework
- The user says "write a sequence", "cold email", "outreach emails", "write the emails", or "email campaign copy"

## When NOT to use

- Warm leads who already know the sender — use a direct one-off email instead
- Lifecycle, onboarding, or nurture flows for existing users — use `marketing-skills:email-sequences`
- Transactional emails (receipts, password resets, notifications)
- Post-call follow-ups — use `sales-skills:follow-up-emails`
- Long-form newsletters or content emails — use `marketing-skills:newsletter`

## Prerequisites

- Context on the target audience
- The product/offer being pitched
- Social proof or case studies (with real numbers)
- The source/trigger connecting the sender to these leads

## The Framework: James Shields Cold Email Rules

### Rule 1: Personalize the Subject, Not the Body
- Subject references the trigger (post, event, comment)
- Body uses `{{firstName}}` only

### Rule 2: Three Sentences + PS
- S1: Context/trigger (why you are emailing)
- S2: What you built / the offer
- S3: Social proof (specific numbers)
- PS: Soft opt-out

### Rule 3: Irresistible Offer
- Free access, no strings
- "I just want honest feedback"
- No demo, no call, no commitment

### Rule 4: Low-Friction CTA
- Reply with one word: "I'm in"
- NOT "book a call" or "schedule a demo"

### Rule 5: No Fluff
- No em dashes (use periods)
- No "I hope this finds you well"
- No bullet points or formatting *in the email output* (this rule applies to what you send to prospects, not to this skill doc)
- Write like texting a colleague

## The Workflow

### Step 1: Gather Inputs

1. **Trigger/source**: What connects the sender to these leads?
2. **Product**: One-line description
3. **Social proof**: Case study with numbers
4. **Offer**: The free/low-friction offer
5. **CTA**: Reply word (default: "I'm in")
6. **Sender**: First name only
7. **Existing draft**: Any copy to work from?

### Step 2: Email 1 — The Opener (Day 0)

```
Subject: [personalized to trigger, lowercase, casual]

Hey {{firstName}},

[1 sentence: I saw your {trigger}. Brief validation.]

[1-2 sentences: What I built. Concrete.]

[1-2 sentences: Social proof. Specific numbers.]

[1 sentence: The offer. Free, no strings.]

[CTA: Reply "I'm in" and I'll {action}.]

[Name]

PS [Soft opt-out]
```

**Present to user. Refine until approved. Do NOT proceed until locked.**

### Step 3: Email 2 — The Follow-Up (Day 3)

```
Subject: (same thread — blank)

Hey {{firstName}},

[1 sentence: Follow up. Acknowledge inbox noise.]

[2 sentences: NEW social proof. Different client, different numbers.]

[1 sentence: Restate offer.]

[Same CTA.]

[Name]
```

- Shorter than Email 1 (no PS)
- NEW social proof (never repeat)
- Same CTA

**Present to user. Refine until approved.**

### Step 4: Email 3 — The Breakup (Day 7)

```
Subject: (same thread)

Hey {{firstName}},

Last one from me on this.

[1 sentence: Tool is live. Others using it.]

[1 sentence: Final CTA.]

[1 sentence: I won't email again.]

[Name]
```

- 4 sentences MAX
- "I won't email again" creates urgency
- No new pitch

**Present to user. Refine until approved.**

### Step 5: Save Complete Sequence

Save to the current working directory as `{campaign-name}-sequence.md` with all 3 emails, timing, contact list info, and send-from address.

## Quick Reference

| Email | Day | Length | Subject | Goal |
|-------|-----|--------|---------|------|
| 1 Opener | 0 | 3 sentences + PS | Personalized to trigger, lowercase | Hook + offer + proof |
| 2 Follow-up | 3 | 3-4 sentences | Blank (same thread) | NEW social proof, restate offer |
| 3 Breakup | 7 | 4 sentences MAX | Blank (same thread) | Urgency, "won't email again" |

**Formatting rules (output emails):** no em dashes, no exclamation points in body, no bold/italic/bullets, lowercase subject, short paragraphs (1-2 sentences), `{{firstName}}` for personalization, first-name-only signature.

**Output file:** `{campaign-name}-sequence.md` — ready to load into your sending platform (Instantly, Smartlead, Lemlist, Apollo, etc.).

## Common Mistakes

| Mistake | Why it kills the sequence | Fix |
|---|---|---|
| Long subject lines (6+ words, title case) | Looks like marketing, not a person | Lowercase, 2-4 words, references the trigger |
| Multiple CTAs in one email | Splits attention, lowers reply rate | One CTA per email, always the same reply word |
| Repeating social proof across emails | Wastes the second touch | Email 2 must use a NEW client and NEW numbers |
| "Just checking in" / "bumping this" | Reads as desperate filler | Acknowledge inbox noise once, then deliver new value |
| Booking links in Email 1 | Friction kills cold replies | Reply CTA only — links come after they say "I'm in" |
| Breaking the 3-sentence rule | Long emails get skimmed and trashed | Cut until each sentence is load-bearing |
| Em dashes, exclamation points, bullets | Looks AI-generated or markety | Plain text, periods only, write like a text message |

## Examples

These are fully written sample emails for a fictional company called **Acme Analytics** selling a free Slack analytics teardown. Replace `{firstName}`, the trigger, and the proof with the real campaign data.

### Example Email 1 — Opener (Day 0)

```
Subject: your post on slack sprawl

Hey {{firstName}},

Saw your post about every team spinning up its own Slack channel and nobody knowing where decisions live. Same pattern at every 200+ person company we look at.

I built a free teardown at Acme Analytics that maps your top 50 channels, flags the dead ones, and shows where decisions are actually getting made. Takes about 10 minutes to run.

We did this for the ops team at Northwind last month and they killed 38% of their channels in a week.

No call, no demo, no pitch. I just want to see if it holds up on a bigger Slack workspace.

Reply "I'm in" and I'll send the teardown link.

Felipe

PS If this is not your problem right now, just reply "not now" and I'll go away.
```

### Example Email 2 — Follow-Up (Day 3)

```
Subject: (blank — same thread)

Hey {{firstName}},

Following up once in case my last note got buried.

Ran the same teardown for a 400-person fintech yesterday. They found 12 abandoned project channels and one private channel where their old CTO was still pinned as admin.

Still free, still no call.

Reply "I'm in" and I'll send the link.

Felipe
```

### Example Email 3 — Breakup (Day 7)

```
Subject: (blank — same thread)

Hey {{firstName}},

Last one from me on this.

The teardown is live and four ops leads ran it this week.

If you want yours, reply "I'm in" today.

I won't email again after this.

Felipe
```
