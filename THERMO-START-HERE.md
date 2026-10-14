# ThermoDen and ThermoGen: start here

Two separate websites that point to each other, one shared database, and one confidential planning workbook.

| What | Where it goes |
|---|---|
| `thermoden/` (index.html, team/ photos, _headers, .htaccess, robots.txt) | The **ThermoDen** website (consulting company) |
| `thermogen/` (same files) | The **ThermoGen** website (R&D company) |
| `thermo_setup.sql` | Supabase SQL Editor (run **once** for both sites) |
| `ThermoGen_Opportunity_Projections_CONFIDENTIAL.xlsx` | Stays with you. Never upload it, never email it outside the company. |
| `_source-for-developers/` | Optional. Only needed if a developer wants to rebuild the pages. |

Use `_headers` on Netlify or Cloudflare Pages, or `.htaccess` on Apache. Use one, not both.

## Set up in about 30 minutes
1. **Supabase:** create a project at supabase.com. SQL Editor > New query > paste `thermo_setup.sql` > Run.
2. **Your admin login:** Authentication > Users > Add user (your email and a long, unique password, tick *Auto Confirm User*). Then in the SQL Editor run the `insert into public.admins ...` line shown at the bottom of `thermo_setup.sql`, with your email.
3. **Lock sign-ups:** Authentication > Providers > Email > turn **off** "Allow new users to sign up". Turn on two-step login for your account if your plan offers it.
4. **Edit the SETTINGS block** at the top of the script in **each** `index.html` (open it in any text editor):
   - `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Project Settings > API; use the *anon public* key, never `service_role`)
   - `THERMODEN_URL` and `THERMOGEN_URL`: the real web addresses, so each site links to the other correctly
   - `ADMIN_PATH`: a secret word of your own (your admin page is `yoursite/#/` plus that word; bookmark it)
   - `SITE_OPERATOR` and `CONTACT_EMAIL`: shown on the Privacy and Terms pages (signed in as admin, those pages remind you until you fill them in)
   - `PHOTO_DENVER` and `PHOTO_JAMILLE`: already set to the photos from your slide deck in the `team/` folder. To change a picture, replace the file and keep its name (set the setting to `""` to show initials instead)
   - `PATENT_FILED`: leave `false` until a patent application has actually been filed
5. **Upload** each folder to its own host. Hard-refresh (Ctrl+Shift+R) and press F12 > Console: there should be no red "blocked" messages.
6. **Test:** send a message on each site, then sign in at your admin address and find it in the Inbox.
7. **Launch:** while you test, both pages carry `noindex` so search engines stay away. When you are ready, delete the `<meta name="robots" ...>` line near the top of each `index.html`.

## What each site has
- **Both:** Home, Founders, About, Insights (articles you write in the admin), Contact (with an NDA/partner-access request on ThermoGen and an introductory-call request on ThermoDen), Privacy, Terms, an **Ask a question** chat at the bottom right, email sign-up, and a private admin screen.
- **ThermoDen:** a "What do you need help with?" finder, eight services, and an Outlook page with sourced figures. It links to ThermoGen in the header, footer, Home and About.
- **ThermoGen:** an interactive core sample on the home page (each layer opens one program), Programs, and a **Projections** page (sourced charts, a four-stage roadmap with decision gates, three scenarios, risks and sources). It links back to ThermoDen.
- **Admin (each site, its own data):** Inbox (status: New / In discussion / NDA sent / NDA signed / Closed; private notes; reply by email; CSV), Insights editor (draft, publish, unpublish), Subscribers (CSV, copy emails), Traffic (cookie-free; your own visits are never counted).

## Security (same approach as Isle Connect)
Strict browser security policy with no third-party scripts, fonts or trackers; the database library is pinned and checked with an integrity hash; no cookies; per-visitor rate limits enforced in the database on messages, chat and sign-ups; honeypots and validation on every form; hashed (never raw) addresses for rate limiting; your visits excluded from traffic in both the page and the database; visitors can never read messages, subscribers or drafts; admin address hidden and protected by real database rules, not just the hidden address. Tested on a real PostgreSQL (60 checks) and in a simulated browser (216 checks).

## What I kept proprietary
Nothing on either public site names an organism, describes a method or protocol, gives a concentration, or mentions a patent candidate. Your documents say public disclosure before filing can end patent rights, so I also kept **sargassum out of ThermoGen entirely** (pairing it with hot-spring microbes is your first patent candidate). ThermoDen mentions sargassum only as sourced regional context for environmental-monitoring consulting. Ask your patent attorney before changing either choice.

## What I fixed (full list on the workbook's `Corrections_Log` sheet)
- "Patent Pending" removed (no application is filed yet); wording is now "IP strategy in development", with a switch for later.
- "~0 prior studies" and "1st to access" removed: your own proposals cite a published survey.
- "$14B plasmid market" replaced by sourced ranges: about $5B to $8.5B plasmid-only, about $15B to $39B with viral vectors.
- Claims such as "we have developed a platform" were reworded to match the concept and planning stage.
- Selling natural plasmids for gene therapy was reframed (therapeutic plasmids need defined, manufacturing-grade sequences) toward data, strains, genetic parts, enzymes and collaborations.
- The USPTO provisional fee was corrected from about $350 to **$65 / $130 / $325** (micro / small / large), and attorney costs were added.
- Contact addresses (including a personal one) and the third-party email service were replaced by a private inbox.

## What I could not do, and what is left for you
- **LinkedIn:** it blocks automated reading, so Denver's page is built from his resume, with a link to his profile.
- **Jamille's bio** uses only what was already on your old site. Add her education and experience in the `FOUNDERS` list in the script, or send them to me.
- **Photos** come from your slide deck. Denver's is a clean headshot. Jamille's is small and blurry (about 200 pixels, from a screenshot), so replace `team/jamille.jpg` with a sharper photo, ideally 600 x 600 pixels or larger, keeping the same file name. Both photos will now be public on the websites.
- **Domains and emails** are placeholders until you set them.
- **Legal review:** the Privacy and Terms pages are plain-language templates built from what the sites do. Have a lawyer read them.
- **Everything is tested against a stand-in database, not your live Supabase.** Do the test in step 6.
- Please verify the citations and cost figures in your original Hot Springs 2 and 5 documents before reusing them. I could not confirm them.

## What I used from your slide deck, and what I left out
**Used:** the two founder photos; your tagline, "Where the Earth's heat becomes tomorrow's medicine", as ThermoGen's headline; the three program focus lines and icons (DNA, capsule, leaf); and the deck's four-step "hot spring to shelf" flow, now "From hot spring to partner" on the Programs page.

**Left out on purpose:** the deck still carries claims that your own documents contradict, so I did not repeat them on the sites. These are "$14B" as a single plasmid-market figure, "~0 prior studies", "1st to access this territory", and "Patent applications in progress" (your patent guide shows none filed yet). I also left out the two email addresses and the "Confidential overview" label. Please correct the deck itself before you send it to investors. I can prepare corrected slide text or a corrected deck if you want.

**Names:** the deck writes "JnBaptiste"; your resume and old website write "Jn. Baptiste". I used the resume's spelling. Tell me which you prefer and I will make every page match.
