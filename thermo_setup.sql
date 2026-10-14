-- =====================================================================
-- ThermoDen + ThermoGen - database setup for BOTH websites (run once)
-- Supabase dashboard -> SQL Editor -> New query -> paste -> Run
-- Safe to re-run. Both sites share one Supabase project; every row is tagged with its site.
--
-- It creates: the admin list, the inbox (contact forms and chat), email subscribers, cookie-free page-view
-- counts, "Insights" articles (public once published), server-side rate limits, and 4 starter articles saved as drafts.
-- Then add yourself as an administrator (see the last section).
-- =====================================================================

-- 1. Administrators --------------------------------------------------------------------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;
drop policy if exists "Admins can see their own row" on public.admins;
create policy "Admins can see their own row" on public.admins for select using (user_id = auth.uid());

-- Runs with the caller's own permissions (SECURITY INVOKER): true only for people listed in public.admins.
create or replace function public.is_admin() returns boolean
language sql stable security invoker set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- 2. Private area for rate limiting (not reachable through the public API) -----------------
create schema if not exists private;
revoke all on schema private from public;

create table if not exists private.settings (key text primary key, value text not null);
insert into private.settings (key, value) values ('ip_salt', gen_random_uuid()::text) on conflict (key) do nothing;

create table if not exists private.rate_limits (
  id bigint generated always as identity primary key,
  bucket text not null,
  ip_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_limits_lookup_idx on private.rate_limits (bucket, ip_hash, created_at desc);
alter table private.rate_limits enable row level security;
alter table private.settings    enable row level security;
revoke all on private.rate_limits, private.settings from public, anon, authenticated;

create or replace function private.client_ip_hash() returns text
language plpgsql stable security definer set search_path = private, public as $$
declare h json; ip text; salt text;
begin
  begin h := current_setting('request.headers', true)::json; exception when others then h := null; end;
  ip := nullif(btrim(split_part(coalesce(h->>'cf-connecting-ip', h->>'x-forwarded-for', ''), ',', 1)), '');
  if ip is null then return null; end if;                       -- unknown caller: never lock everyone out
  select value into salt from private.settings where key = 'ip_salt';
  return md5(ip || coalesce(salt, ''));
end $$;

create or replace function private.enforce_rate_limit(p_bucket text, p_max int, p_window interval) returns void
language plpgsql security definer set search_path = private, public as $$
declare r text := coalesce(current_setting('role', true), ''); iph text; n int;
begin
  if r not in ('anon', 'authenticated') then return; end if;    -- SQL editor, service role and scripts are never limited
  if r = 'authenticated' and public.is_admin() then return; end if;
  iph := private.client_ip_hash();
  if iph is null then return; end if;
  select count(*) into n from private.rate_limits where bucket = p_bucket and ip_hash = iph and created_at > now() - p_window;
  if n >= p_max then
    raise exception 'rate_limited' using errcode = 'P0001', hint = 'Too many requests. Please try again later.';
  end if;
  insert into private.rate_limits (bucket, ip_hash) values (p_bucket, iph);
  if random() < 0.02 then delete from private.rate_limits where created_at < now() - interval '1 day'; end if;
end $$;
revoke all on function private.client_ip_hash() from public, anon, authenticated;
revoke all on function private.enforce_rate_limit(text, int, interval) from public, anon, authenticated;

-- 3. Inbox: contact-form messages and chat questions ------------------------------------------
create table if not exists public.inquiries (
  id           uuid primary key default gen_random_uuid(),
  site         text not null check (site in ('thermoden', 'thermogen')),
  source       text not null default 'form' check (source in ('form', 'chat')),
  topic        text check (char_length(topic) <= 80),
  name         text check (char_length(name) <= 120),
  email        text check (char_length(email) <= 254 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$'),
  organization text check (char_length(organization) <= 160),
  role         text check (char_length(role) <= 120),
  message      text not null check (char_length(message) between 3 and 3000),
  consent      boolean not null default false,
  status       text not null default 'New' check (status in ('New', 'In discussion', 'NDA sent', 'NDA signed', 'Closed')),
  admin_notes  text check (char_length(admin_notes) <= 4000),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists inquiries_site_status_idx on public.inquiries (site, status, created_at desc);
alter table public.inquiries enable row level security;

-- Visitors can send a message but never read any. Form messages need a name, an email and consent; chat questions need neither.
drop policy if exists "Anyone can send an inquiry" on public.inquiries;
create policy "Anyone can send an inquiry" on public.inquiries for insert
  to anon, authenticated
  with check (
    status = 'New' and admin_notes is null
    and created_at between now() - interval '5 minutes' and now() + interval '5 minutes'
    and ((source = 'form' and name is not null and email is not null and consent = true) or source = 'chat')
  );
drop policy if exists "Admins read inquiries" on public.inquiries;
create policy "Admins read inquiries" on public.inquiries for select using (public.is_admin());
drop policy if exists "Admins update inquiries" on public.inquiries;
create policy "Admins update inquiries" on public.inquiries for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins delete inquiries" on public.inquiries;
create policy "Admins delete inquiries" on public.inquiries for delete using (public.is_admin());

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists inquiries_touch on public.inquiries;
create trigger inquiries_touch before update on public.inquiries for each row execute function public.touch_updated_at();

-- 4. Email subscribers ---------------------------------------------------------------------
create table if not exists public.subscribers (
  id         uuid primary key default gen_random_uuid(),
  site       text not null check (site in ('thermoden', 'thermogen')),
  email      text not null check (char_length(email) <= 254 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$'),
  consent    boolean not null check (consent = true),
  created_at timestamptz not null default now()
);
create unique index if not exists subscribers_site_email_uniq on public.subscribers (site, lower(email));
alter table public.subscribers enable row level security;
drop policy if exists "Anyone can subscribe" on public.subscribers;
create policy "Anyone can subscribe" on public.subscribers for insert to anon, authenticated with check (consent = true);
drop policy if exists "Admins read subscribers" on public.subscribers;
create policy "Admins read subscribers" on public.subscribers for select using (public.is_admin());
drop policy if exists "Admins delete subscribers" on public.subscribers;
create policy "Admins delete subscribers" on public.subscribers for delete using (public.is_admin());

-- 5. Insights (articles): public once Published, written in the admin screen ------------------
create table if not exists public.insights (
  id           uuid primary key default gen_random_uuid(),
  site         text not null check (site in ('thermoden', 'thermogen')),
  title        text not null check (char_length(title) between 3 and 140),
  category     text not null check (char_length(category) between 2 and 40),
  summary      text not null check (char_length(summary) between 3 and 300),
  body         text not null check (char_length(body) between 3 and 20000),
  status       text not null default 'Draft' check (status in ('Draft', 'Published')),
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists insights_site_status_idx on public.insights (site, status, published_at desc);
alter table public.insights enable row level security;
drop policy if exists "Public reads published insights" on public.insights;
create policy "Public reads published insights" on public.insights for select using (status = 'Published');
drop policy if exists "Admins read all insights" on public.insights;
create policy "Admins read all insights" on public.insights for select using (public.is_admin());
drop policy if exists "Admins insert insights" on public.insights;
create policy "Admins insert insights" on public.insights for insert to authenticated with check (public.is_admin());
drop policy if exists "Admins update insights" on public.insights;
create policy "Admins update insights" on public.insights for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins delete insights" on public.insights;
create policy "Admins delete insights" on public.insights for delete using (public.is_admin());

create or replace function public.insights_before_write() returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if new.status = 'Published' and new.published_at is null then new.published_at := now(); end if;
  if new.status = 'Draft' then new.published_at := null; end if;
  return new;
end $$;
drop trigger if exists insights_write on public.insights;
create trigger insights_write before insert or update on public.insights for each row execute function public.insights_before_write();

-- 6. Cookie-free page views ------------------------------------------------------------------
create table if not exists public.page_views (
  id         bigint generated always as identity primary key,
  site       text not null check (site in ('thermoden', 'thermogen')),
  path       text not null check (path ~ '^/[a-z-]{0,30}$'),
  referrer   text check (char_length(referrer) <= 200),
  session_id text not null check (char_length(session_id) between 8 and 64),
  created_at timestamptz not null default now()
);
create index if not exists page_views_site_created_idx on public.page_views (site, created_at desc);
alter table public.page_views enable row level security;
drop policy if exists "Anyone can log a page view" on public.page_views;
create policy "Anyone can log a page view" on public.page_views for insert
  to anon, authenticated
  with check (
    created_at between now() - interval '5 minutes' and now() + interval '5 minutes'
    and not public.is_admin()                                   -- visits made while signed in as admin are never counted
  );
drop policy if exists "Admins read page views" on public.page_views;
create policy "Admins read page views" on public.page_views for select using (public.is_admin());
drop policy if exists "Admins delete page views" on public.page_views;
create policy "Admins delete page views" on public.page_views for delete using (public.is_admin());

-- Admin-only traffic summary for one site (SECURITY INVOKER: only admins get data back)
create or replace function public.traffic_summary(p_site text, p_days int default 30) returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare since_ts timestamptz := now() - make_interval(days => greatest(1, least(p_days, 365))); result jsonb;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  select jsonb_build_object(
    'total_views',     (select count(*) from public.page_views where site = p_site and created_at >= since_ts),
    'unique_visitors', (select count(distinct session_id) from public.page_views where site = p_site and created_at >= since_ts),
    'subscribers',     (select count(*) from public.subscribers where site = p_site),
    'new_inquiries',   (select count(*) from public.inquiries where site = p_site and status = 'New'),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'views', v) order by d)
        from (select (created_at at time zone 'utc')::date as d, count(*) as v from public.page_views
              where site = p_site and created_at >= since_ts group by 1) x), '[]'::jsonb),
    'by_path', coalesce((select jsonb_agg(jsonb_build_object('path', path, 'views', v) order by v desc)
        from (select path, count(*) as v from public.page_views where site = p_site and created_at >= since_ts
              group by 1 order by 2 desc limit 12) x), '[]'::jsonb),
    'by_referrer', coalesce((select jsonb_agg(jsonb_build_object('ref', r, 'views', v) order by v desc)
        from (select coalesce(nullif(referrer, ''), 'Direct / unknown') as r, count(*) as v from public.page_views
              where site = p_site and created_at >= since_ts group by 1 order by 2 desc limit 10) x), '[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke execute on function public.traffic_summary(text, int) from public, anon;
grant  execute on function public.traffic_summary(text, int) to authenticated;

-- 7. Server-side rate limits per visitor address (stored only as a salted hash, deleted after a day) --------
create or replace function private.rl_inquiries()   returns trigger language plpgsql security definer set search_path = private, public as $$
begin perform private.enforce_rate_limit('inquiry', 8, interval '1 hour');   return new; end $$;
create or replace function private.rl_subscribers() returns trigger language plpgsql security definer set search_path = private, public as $$
begin perform private.enforce_rate_limit('subscribe', 5, interval '1 hour'); return new; end $$;
revoke all on function private.rl_inquiries(), private.rl_subscribers() from public, anon, authenticated;
drop trigger if exists rl_inquiries on public.inquiries;
create trigger rl_inquiries before insert on public.inquiries for each row execute function private.rl_inquiries();
drop trigger if exists rl_subscribers on public.subscribers;
create trigger rl_subscribers before insert on public.subscribers for each row execute function private.rl_subscribers();

-- 8. Starter articles, saved as DRAFTS so you can read and edit them before publishing -------------------
insert into public.insights (site, title, category, summary, body, status)
select v.site, v.title, v.category, v.summary, v.body, 'Draft'
from (values
 ('thermoden', 'Keep research records that stand up to review', 'Research practice',
  'Six notebook habits that help with publication, funding audits and, when you are protecting an invention, showing when the work was done.',
  E'Good records are the cheapest insurance a research project can buy. These habits take minutes and pay off for years.\n\n## Six habits\n\n- Use a bound, numbered notebook, or a validated electronic notebook that keeps an edit history.\n- Date and sign every entry. If you can, have a colleague read and sign it too.\n- Record failures as carefully as successes. Selective records look like selective science.\n- Log exact quantities, concentrations, temperatures and durations. Vague notes cannot be repeated.\n- Never erase. Strike through with a single line, so the original stays readable.\n- Photograph readings and set-ups with a visible date.\n\n## Why it matters\n\nFunders, journals and collaborators all ask the same question: can someone else repeat this? If you are protecting an invention, dated records also help show when the work was done.\n\nThis is general guidance, not legal advice. Ask a patent attorney how it applies to your situation.'),
 ('thermoden', 'Before you present your results: a checklist for early-stage inventors', 'Research practice',
  'Public talks, papers and grant applications can affect your options for protecting an invention. A short checklist of what to settle first.',
  E'Many early-stage teams discover too late that telling the world about an idea can limit their ability to protect it. In many countries, publishing or presenting an invention before filing can end your chance of a patent. A few places allow a short grace period, and the rules differ, so check before you disclose.\n\n## A short checklist\n\n- Write down exactly what you did, with dates, before you talk about it publicly.\n- Search existing patents and papers to see whether your idea is already described.\n- Talk to a patent attorney before presenting, publishing or submitting a grant application that describes methods in detail. Many universities offer a free first conversation.\n- Use a signed non-disclosure agreement before sharing technical detail with a partner.\n- Know your alternatives: patents, trade secrets and publication all protect different things.\n- Remember that a low-cost provisional application can lock in a filing date. In the United States the government fee is $65 for micro entities, $130 for small entities and $325 for large entities (USPTO fee schedule, effective January 2025), and professional preparation costs more. Confirm current fees before you plan.\n\nThis is general information, not legal advice.'),
 ('thermogen', 'What extremophile research can and cannot deliver', 'Science explainers',
  'Microbes that live in hot, acidic, mineral-rich water are a real source of new biology. Here is what that realistically means for products and timelines.',
  E'Extremophiles are organisms that thrive where most life cannot, such as very hot, acidic or metal-rich water. Their proteins and genes have to stay stable under harsh conditions, which makes them a rich source of material for biotechnology.\n\n## What it can deliver\n\n- New enzymes and genetic parts that partners can test and build on.\n- Well-documented data and strain collections for research.\n- Early leads in the search for new antimicrobial compounds.\n\n## What it cannot do quickly\n\n- Medicines take a decade or more from discovery to approval, and most candidates do not make it.\n- Many extremophiles are hard to grow in a lab, so some of the work depends on sequencing rather than cultures.\n- Therapeutic-grade DNA is made to strict, defined standards, so natural sequences are a starting point for discovery, not a finished product.\n\nOur plan is built around these limits. We aim to produce validated early results and data that partners can take further.'),
 ('thermogen', 'How we approach access and benefit-sharing', 'Company news',
  'Working with natural resources from the Caribbean means working with the people and institutions that look after them.',
  E'Samples from natural sites belong to a place and its people. Our approach starts with that idea.\n\n## Our principles\n\n- Ask first. We work only with the permission of the relevant authorities and landowners.\n- Share the benefits. Where our work produces value, we aim to share it fairly with host communities and institutions.\n- Build local capacity. We prefer partnerships that train and equip regional scientists.\n- Document everything. Clear records make it possible to show where material came from and under what terms.\n\nThe details of each arrangement depend on the country and the site. We will publish updates here as our partnerships develop.')
) as v(site, title, category, summary, body)
where not exists (select 1 from public.insights i where i.site = v.site and i.title = v.title);

-- 9. Make yourself an administrator ------------------------------------------------------------
-- First create your login: Authentication -> Users -> Add user (email + password; tick "Auto Confirm User").
-- Then run this with your email (remove the two leading dashes):
--
--   insert into public.admins (user_id) select id from auth.users where email = 'you@example.com' on conflict do nothing;
--
-- Also: Authentication -> Providers -> Email -> turn OFF "Allow new users to sign up".
