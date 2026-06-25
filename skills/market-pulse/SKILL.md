---
name: market-pulse
description: "Live, fully bilingual lodging market intelligence for a hotel's city (English and Spanish, auto-selected from the user's language). Given a destination and dates, it blends the competing supply across Airbnb, Booking.com, Expedia/Hotels.com, Vrbo and Hostelworld into a branded Google Sheet command center, a sortable comp set with price and occupancy heat maps, a day-by-day demand calendar, a voice-of-guest read, a rate-parity tab (same property across channels with verify links and capture dates), and a one-screen summary that ends in three concrete moves. Built for hotels and hotel associations who want to understand and out-position the short-term-rental and OTA competition. Also triggers on Spanish requests like 'pulso de mercado', 'set competitivo', 'lectura de tarifas', or 'reporte de mercado STR'."
version: 4
category: market-intelligence
featured: yes
integrations: [googlesheets, apify, googledrive]
image: bar-chart
license: MIT
---

## What this does

Produces a branded, multi-source Google Sheet command center (7 tabs) plus a
one-screen brief for a hotel or short-term-rental host about the competition in
its own market. It blends Airbnb + Booking.com + Expedia/Hotels.com + Vrbo +
Hostelworld, and adds a revenue-management layer (pricing actions, a Your-property
scorecard, and a researched demand-drivers calendar). Answers what a revenue
manager actually asks: *How much supply competes with me? What are they charging
across channels? How booked are they? What do guests love and complain about?
What should I do with my rate this week?*

Every read ends with three concrete, do-this-week moves, not a dashboard. Built for
hotels and short-term-rental hosts (e.g. a Medellín hosts association) who want to
out-position the OTA and STR competition.

## Language (automatic and bilingual)

This skill is fully bilingual (English and Spanish) and selects the output language
**automatically** from how the user writes. There is no setting to flip.

- **Mirror the user.** Detect the language of the user's chat messages and deliver
  EVERYTHING in that same language: your chat replies, the markdown brief, and every
  visible string in the Google Sheet (tab names, headers, section labels, categorical
  values like Type and Signal, captions, and the recommendations).
- Write in Spanish, get Spanish. Write in English, get English. If the user switches
  languages mid conversation, follow their latest message. Fall back to English only
  when the language is genuinely ambiguous.
- An explicit request always wins. If the user says "give it to me in English" (or
  Spanish), honor that over auto-detection.
- **Keep data language-neutral.** Numbers, prices, dates, URLs, and spreadsheet
  formulas stay identical in any language. Only the human-readable text changes.
- When delivering in Spanish, present the deliverable as **"Pulso de Mercado"** and use
  the tab names and glossary in the **Spanish output reference** section at the end so
  wording stays consistent. For any other language, follow the same principle: translate
  every visible string, leave data and formulas intact.

## When to use

- A hotel or hotel association wants a read on the Airbnb / short-term-rental
  competition in a city.
- Someone asks for a "market pulse", "comp set", "competitive rate read",
  "STR market report", "what's Airbnb doing in my market", or the Spanish equivalents
  ("pulso de mercado", "set competitivo", "lectura de tarifas", "reporte de mercado STR").
- As the live demo of what an agent can do for a hospitality audience, in either language.

## Data source

The Airbnb supply read comes from a vetted, no-login Airbnb read source (this
build uses the Anakin **Wire** catalog, Airbnb slug `airbnb`; swap in your own
Airbnb data connector if you use a different one). These are pre-built read
actions. Confirm the action list at runtime with `wire_catalog(slug="airbnb")` in
case ids change, then run actions with `wire_action`. Known actions (all
`auth_mode: none`, 1 credit each):

- `ab_location_search` - resolve a free-text place to a clean location.
- `ab_search_listings` - paginated supply with price, rating, reviews, badges, neighborhood. Params: `query`, `checkin`, `checkout`, `adults`, `currency`, `cursor` (for next page).
- `ab_listing_details` - one listing's full description, photos, location, reviews summary.
- `ab_listing_availability` - day-by-day bookable calendar for a listing (the demand signal). Params: `listing_id`, `month`, `year`, `count`, `currency`.
- `ab_listing_reviews` - paginated guest reviews with rating, date, text. Params: `listing_id`, `limit`, `sort_by` ("recent" or "best").

## Inputs (ask only if missing)

1. **City / destination** (required) - e.g. "Medellín, Colombia".
2. **Date window** (required) - check-in and check-out. If the user is vague, default to a representative 3-night stay roughly 6-8 weeks out and say which dates you used.
3. **Guests** (optional, default 2 adults).
4. **Currency** (optional, default USD; for Colombia COP is also fine if asked).
5. **Neighborhood focus** (optional) - if they name an area, filter the read to it.
6. **Output language** (automatic) - the deliverable matches the user's chat language by default (see the Language section). Only override if the user explicitly asks for a specific language.

Ask any clarifying question in the user's language, and only for a genuinely missing required input. Otherwise pick the sensible default, state it, and proceed.

## Procedure

1. **Search supply.** Call `ab_search_listings` with the city + dates + guests + currency. Page 1-2 with `cursor` to get a healthy sample (aim for 30-50 listings). Capture per listing: name, neighborhood (`property_type`), price (note the qualifier - prices are usually "for N nights", so normalize to per-night = price / nights), rating, review_count, badges (Superhost / Guest favourite), listing_id, lat/lon.

2. **Crunch the market.** From the sample compute and keep:
   - Supply count in the sample.
   - Per-night rate distribution: min, median, average, max. Always normalize the multi-night price to per-night using the stay length.
   - Neighborhood breakdown (count + median rate per neighborhood).
   - Quality mix: share that are Superhost or Guest-favourite; rating distribution.

3. **Get a demand + occupancy signal.** Call `ab_listing_availability` for a set of ESTABLISHED listings (high review counts) over a NEAR-TERM window (the next ~30 days) - NOT far-future months. Far-out dates read as "available" only because bookings have not landed yet, so a far window badly understates occupancy. Occupancy proxy = booked share (days where `available=false`) per listing; report the **median** across the sample (robust to outliers). Flag listings that sit fully/mostly open despite high review counts as likely dormant or host-blocked (note them; they drag the median down). Airbnb "unavailable" = booked OR host-blocked, so this is an apparent-occupancy proxy, not audited occupancy - label it as such. Build the day-by-day market demand curve from the same calendars for the Rate Calendar, and call out tight vs. soft windows.

4. **Mine the guest voice.** For those same top listings, call `ab_listing_reviews` (sort_by="recent", limit 8-10 each) and also read `ab_listing_details` on 2-3 of them. Extract:
   - **What guests love** - recurring praise themes (location, cleanliness, host responsiveness, safety, value).
   - **What they complain about** - recurring gripes (these are the hotel's openings: parking, noise, no front desk, inconsistent cleaning, tired amenities, "street isn't nice").
   - **How STRs position against hotels** - read the listing descriptions for the angles they push (e.g. "no cleaning/service fees", fast WiFi, AC, self check-in, legal/registered). A hotel needs to know what it's being compared against.

5. **Synthesize the brief** (see format below). Ground every number in the pulled data. If a field is thin or missing (e.g. amenities came back empty), mark it TBD - never invent figures, occupancy, or quotes.

6. **Save and deliver.** Save the brief as a markdown file (for example in a `market-pulse/` output folder) and present it in chat in plain, non-technical language, in the user's language. If the user wants it emailed or sent to Slack, offer that as a next step (discover the channel via your connected tools at runtime).

## Output format (the brief)

Lead with a one-line headline, then these sections, tight (translate the section labels into the user's language):

1. **Market snapshot** - city, dates, supply count, per-night rate range + median, where supply concentrates.
2. **Pricing** - the rate ladder (budget / mid / premium bands) with example listings; where a hotel's rate sits relative to it.
3. **Demand signal** - the occupancy read from the availability calendars; which date windows are tight vs. soft.
4. **How the short-term rentals win** - the positioning angles they push (fees, WiFi, AC, self check-in, location).
5. **What guests love / what they complain about** - two short lists, in guests' own words where useful.
6. **Three moves this week** - concrete, specific to what the data showed (a pricing move, a positioning/marketing move, an operations or amenity move). No filler.

Keep it to roughly one screen. A hotelier should be able to act off it in five minutes.

## Adding the multi-source comp set via Apify

Airbnb alone is only the short-term-rental side. For a revenue-manager-grade view, blend several
sources with Apify actors (a connected Apify account is required). All verified live on Medellín:

- **Booking.com** - `santamaria-automations/booking-com-scraper`. Input: `destination`, `checkin`, `checkout`, `adults`, `currency`, `maxResults`. ~99% success, ~$0.003/hotel. NOTE: `price` is the TOTAL for the stay; divide by nights for a per-night rate.
- **Expedia + Hotels.com** - `memo23/expedia-scraper`. Input: `location`, `searchCheckIn`, `searchCheckOut`, `searchAdults`, `searchCurrency`, `skipReviews:true` (rooms-only = clean price snapshot, no per-review charges), `includeCategoryRatings:true`, `includePropertyDetails:true`, `maxItems`. Returns `pricePerNightValue` (already per-night), `reviewScore` (0-10), `reviewCount`, `neighborhood`, `url`. ~97% success.
- **Vrbo** (vacation rentals) - `one-api/vrbo-scraper`. Input: `search_inputs: ["<city>, <country>"]`, `checkIn`, `checkOut`, `adults`, `pages`, `resultCount`, `sortOrder`. Returns Name, Price (per-night), Summary (type + beds, e.g. "Condo · Sleeps 4 · 2 bedrooms"), Listing URL. IMPORTANT: do NOT use `makework36/vrbo-scraper` - it returns Expedia hotels, not Vrbo rentals.
- **Hostelworld** (budget/hostel floor) - `easyapi/hostelworld-listings-scraper`. Input: `searchUrls`, a Hostelworld wds search URL that REQUIRES the city's internal id: `https://www.hostelworld.com/pwa/wds/s?q=<City>%2C%20<Country>&country=<Country>&city=<City>&type=city&id=<CITYID>&from=YYYY-MM-DD&to=YYYY-MM-DD&guests=2&page=1`. Without the right `id` it returns 0 rows. Resolve the id by fetching the city page `https://www.hostelworld.com/st/hostels/.../<city>/` and reading `id=` from the search links (Medellín = 661). Returns per-night dorm/private prices (USD), `overallRating.overall` (0-100), `numberOfRatings`, security/location sub-scores, free-cancellation. Slower (~100s) and ~68% success - retry if it returns 0.
- **Agoda** - `knagymate/fast-agoda-scraper` (city search). Errored repeatedly in testing (exit 1); treat as unreliable and skip unless it recovers. Its Medellín inventory mostly overlaps Booking/Expedia anyway.
- **Google Hotels** - `johnvc/google-hotels-search-scraper` rejects "MCP" run origin; `solidcode` failed to init. Use an "API" run origin if needed. Booking + Expedia already cover the OTA hotel angle.

Reviews/reputation layer (per-URL, not city search): `knagymate/trip-com-reviews-scraper`, Agoda/Hostelworld reviews, `maxcopell/tripadvisor-reviews`.

**Normalize everything before comparing.** Convert every price to a per-night USD rate (Booking is stay-total → /nights; Expedia/Vrbo/Hostelworld are already per-night). Normalize ratings to one scale in the Comp Set (Airbnb is /5; Expedia score/10 → /2; Hostelworld overall/100 → /20). Add a `Source` column so the room can sort/filter; hotels appearing on both Booking and Expedia give a rate-parity read (same property, two channels).

## Output: the Google Sheet command center

The premium deliverable is a live Google Sheet (via the `googlesheets` toolkit), not just a markdown brief. Build these seven tabs (the first five below, then two revenue-management tabs further down: Revenue Actions and Demand Drivers), plus a Revenue Scorecard block on the Summary tab (it is a block on Summary, not its own tab). Tab and label names below are the English set; when delivering in Spanish use the Spanish output reference at the end:

- **Summary** - title + dates + sample sizes; a **RATE COMPARISON AT A GLANCE** block near the top (one row per category - hostels, hotels, Airbnb, vacation rentals - each showing low / median / high per-night and a monochrome SPARKLINE bar of the median, scaled to the priciest category, so the room instantly sees how segments stack); a "market at a glance" KPI block (competitors tracked, medians by source, whole-market range, occupancy read, tightest/softest dates); a pricing ladder; how the rentals win; voice-of-guest one-liners; and THREE moves.
- **Rate Parity** - same property, different channels. Match listings that appear on 2+ platforms (normalize names: lowercase, strip accents/punctuation, drop generic tokens like "hotel"/"by"/city name) and show the price on each channel plus Low / High / **Gap ($)** / cheapest channel, sorted by gap descending, with a green-to-red gradient on the Gap column. Hotels on Booking vs Expedia give the cleanest OTA-parity read; cross-source matches (Airbnb/Vrbo/Expedia) also surface. Add an **As of** capture-date column (prices are a point-in-time snapshot and drift with demand) and one clickable verify-link column per channel (Airbnb/Booking/Expedia/Vrbo), each a `=HYPERLINK(listingURL,"open ↗")` to the exact dated listing so the user can confirm every rate themselves (blank = not listed on that channel). Keep table captions (takeaway, freshness note) each on their own row in column A so they don't collide; keep the canonical listing URL per row (re-pull from the source dataset's `url` field if it was not captured in the first projection). End with a one-line takeaway (avg gap, biggest gaps, "undercut the priciest channel and push direct").
- **Comp Set** - one row per property across all sources. Columns: Source, Property, Area, Type, Beds, Rate/Night ($), Rating, Reviews, Signal, Occ. 60d, Listing (a `=HYPERLINK(url,"Open ↗")`). Freeze the header, bold dark header, add a basic filter over the table, and apply MIN→PERCENTILE→MAX color-scale conditional formatting to the Rate/Night and Occupancy columns (green→yellow→red).
- **Rate Calendar** - day-by-day market demand (share of sampled units booked) for the forward window, with inline `=SPARKLINE(...,{"charttype","bar";"max",1})` bars. This is the occupancy/demand curve, the most revenue-manager-relevant view.
- **Voice of Guest** - two tables (loves / complaints) with verbatim quotes themed from reviews, each linked to its source listing. Green band for loves, red for complaints.

**Brand & style (a clean, monochrome-first design system).** Monochrome by default: near-black ink `#0d0d0d` on white, muted gray labels `#676767`, light surfaces `#ececec` / `#f9f9f9`. Color is reserved for status only, used on text/dots/heat maps, never as decoration: Success `#00a240`, Info `#0169cc`, Warning `#e0ac00`, Danger `#e02e2a`. Section labels are quiet uppercase, table headers get a light-gray fill, the loves/complaints headings use green/red text. Heat maps run green to yellow to red on the status hexes. Sparkline bars are monochrome ink. **No dashes in any visible text** (no hyphen, en dash, or em dash); reword with commas, "to" for ranges, or spaces. Keep dashes inside link URLs only (they are in the HYPERLINK formula, not the displayed label).

- **Revenue Actions** - pricing recommendations driven by the demand curve + comp medians: Hold/Raise/Discount/Stimulate per date window (color-coded), and a "where to price by segment" table with a value-play rate (just below median).
- **Revenue Scorecard** (block on Summary) - market ADR, occupancy (near-term established-listing median), RevPAR, plus a "Your property" input block (yellow #fff2cc cells, blue text) that computes rate index and RevPAR index vs the market live.
- **Demand Drivers** - the events that move lodging demand in the window, researched live (festivals, concerts, sports, holidays, conferences), each with date, venue, impact (High/Medium/Low, color-coded), why it matters, and a source link. For Medellín the Feria de las Flores (late Jul to early Aug) is the dominant driver. Get this via live web research - the simplest and most accurate path here: a web search + scrape across official event sources (city tourism site, convention center agenda, concert listings, club fixtures). Cite every event with its source URL, and flag unconfirmed dates (league fixtures, or festival date conflicts across sources) rather than inventing precision.

Key Google Sheets actions to drive: create the spreadsheet, add and rename sheets, freeze rows, update values with USER_ENTERED (so HYPERLINK/SPARKLINE render and numbers parse), format cells, set column widths, set a basic filter, and add color-scale + text-keyword conditional formatting rules. (Tool slugs vary by connector; map these to your own Google Sheets integration.)

## Spanish output reference (when delivering in Spanish)

When the user is writing in Spanish, present the deliverable as **"Pulso de Mercado"** and use these so the wording is consistent.

**Tab names (español):** Resumen · Competencia · Calendario de Demanda · Voz del Huésped · Paridad de Tarifas · Acciones de Revenue · Motores de Demanda.

**Glossary (English → Spanish):**

- Source→Fuente, Property→Propiedad, Area→Zona, Type→Tipo, Beds→Camas, Rate/Night→Tarifa/Noche, Rating→Calificación, Reviews→Reseñas, Signal→Señal, Occupancy→Ocupación, Listing→Listado, Cheapest→Más barato, Gap→Brecha, As of→Al día, low/median/high→mín/mediana/máx, listings→listados.
- Types: Flat/Apartment→Apartamento, Studio→Estudio, House→Casa, Condo→Condominio, Hostel→Hostal, "3★ hotel"→"Hotel 3★", Apt/stay→Apto/estadía.
- Signals: Guest favourite→Favorito huéspedes, Superhost→Superanfitrión, Free cancel→Cancela gratis, No prepay→Sin prepago, Prepay only→Solo prepago, Vacation rental→Alquiler vacacional, "Open ↗"→"Abrir ↗".
- Revenue Actions: Hold→Mantener, Raise→Subir, Discount→Bajar, Stimulate→Estimular.
- Demand Drivers impact: High→Alto, Medium→Medio, Low→Bajo.
- Revenue Scorecard: ADR→ADR, Occupancy→Ocupación, RevPAR→RevPAR, "Your nightly rate (edit)"→"Tu tarifa por noche (editar)", "Your occupancy (edit)"→"Tu ocupación (editar)", "Rate index"→"Índice de tarifa", "RevPAR index"→"Índice de RevPAR".
- Event types: festival→Festival, concert→Concierto, sports→Deporte, holiday→Festivo, conference→Congreso.

**Building both language versions of the same sheet (optional):** if a user wants the same sheet in both languages, copy each tab with `sheets.copyTo` (this inherits ALL formatting, widths, frozen rows, heat maps, filters), then translate text IN PLACE: read the grid with `value_render_option=FORMULA` (preserves HYPERLINK URLs and formulas) and write the translated strings back into the SAME cells. Do NOT re-author arrays from column A: several tabs use a thin gutter in column A (content starts in column B), so a fresh array written at A1 shifts everything one column off its formatting. After translating, re-point any TEXT-keyword conditional rules (Action = Subir/Bajar/Estimular, Impact = Alto/Medio/Bajo) to the translated keywords on the correct (gutter-offset) columns, and verify with a cell-level format diff against the source.

## Turning it into a routine

If the user wants this on a schedule (e.g. every Monday for their market), set up a
recurring schedule (for example a weekly job in your scheduler of choice) that
re-runs this skill for a saved city + rolling date window and delivers the brief by
email or Slack, flagging week-over-week changes in rate and occupancy. Get approval
before creating the schedule.

## Pitfalls

- **Prices are per-stay, not per-night.** `ab_search_listings` price usually reads "for N nights". Always divide by the stay length before comparing or quoting a nightly rate.
- **Some fields come back empty** (amenities array, host block can be null on `ab_listing_details`). Don't present empty as zero; mark TBD and lean on the description text instead.
- **Reviews are bilingual** (Spanish + English in Latin America). Read both; theme across languages regardless of the output language.
- **Sample, not census.** The search returns a sample of supply, not every listing. Say "in a sample of N listings", don't claim total market counts.
- **Never invent.** No made-up occupancy %, ADR, quotes, or competitor facts. If the data is thin, say so and pull more pages rather than guessing.
- **Confirm the catalog at runtime** with `wire_catalog(slug="airbnb")` so action ids and params stay current.
- **Stay in one language per delivery.** Once you detect the user's language, keep the entire chat reply, brief, and sheet in that language. Do not mix English and Spanish in the same deliverable unless the user asks for both.
