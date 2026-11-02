-- >>> 20261030000001_init_schema.sql
-- =============================================================================
-- Turffet: initial schema (client app v1)
-- =============================================================================
-- Notes
--  * All local times are interpreted in Asia/Kolkata (IST).
--  * Double-booking is prevented by an exclusion constraint on bookings.
--  * Writes to bookings / games / reviews go through SECURITY DEFINER RPCs so
--    that every business rule is enforced on the server.
-- =============================================================================

create extension if not exists postgis with schema extensions;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pgcrypto with schema extensions;

set search_path = public, extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type public.skill_level as enum ('beginner', 'intermediate', 'advanced');
create type public.booking_status as enum ('confirmed', 'checked_in', 'completed', 'cancelled', 'no_show');
create type public.game_status as enum ('open', 'full', 'closed');
create type public.join_status as enum ('pending', 'accepted', 'declined', 'withdrawn');

-- -----------------------------------------------------------------------------
-- Settings & secrets
-- -----------------------------------------------------------------------------
create table public.app_settings (
  id boolean primary key default true check (id),
  cancellation_window_minutes int not null default 120,
  max_slots_per_booking int not null default 3,
  max_bookings_per_day int not null default 2,
  booking_horizon_days int not null default 14,
  -- No-show strikes need owner check-ins (owner portal). Keep OFF until then.
  strikes_enabled boolean not null default false,
  strike_limit int not null default 3,
  strike_block_days int not null default 14,
  reminder_minutes_before int not null default 120
);
insert into public.app_settings default values;

create table private.app_secrets (
  name text primary key,
  value text not null
);
insert into private.app_secrets (name, value)
values ('qr_signing_key', encode(extensions.gen_random_bytes(32), 'hex'));

-- -----------------------------------------------------------------------------
-- Catalogue
-- -----------------------------------------------------------------------------
create table public.sports (
  id text primary key,
  name text not null,
  emoji text not null,
  sort_order int not null default 0
);

create table public.amenities (
  id text primary key,
  name text not null,
  icon text not null,           -- lucide icon name used by the client
  sort_order int not null default 0
);

create table public.turfs (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  area text not null,
  city text not null default 'Delhi NCR',
  address text not null,
  lat double precision not null,
  lng double precision not null,
  location extensions.geography(Point, 4326),
  phone text,
  whatsapp text,
  cover_image text,
  rules text[] not null default '{}',
  slot_minutes int not null default 60 check (slot_minutes in (30, 60, 90, 120)),
  rating_avg numeric(2,1) not null default 0,
  rating_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index turfs_location_idx on public.turfs using gist (location);

create or replace function public.set_turf_location()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.location := st_setsrid(st_makepoint(new.lng, new.lat), 4326)::geography;
  return new;
end $$;
create trigger turfs_set_location before insert or update of lat, lng on public.turfs
  for each row execute function public.set_turf_location();

create table public.turf_photos (
  id uuid primary key default gen_random_uuid(),
  turf_id uuid not null references public.turfs(id) on delete cascade,
  url text not null,
  sort_order int not null default 0
);
create index on public.turf_photos (turf_id);

create table public.turf_amenities (
  turf_id uuid not null references public.turfs(id) on delete cascade,
  amenity_id text not null references public.amenities(id),
  primary key (turf_id, amenity_id)
);

create table public.operating_hours (
  turf_id uuid not null references public.turfs(id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),  -- 0 = Sunday
  open_time time not null,
  close_time time not null,     -- may be '24:00'
  primary key (turf_id, day_of_week),
  check (close_time > open_time)
);

create table public.courts (
  id uuid primary key default gen_random_uuid(),
  turf_id uuid not null references public.turfs(id) on delete cascade,
  name text not null,
  size_label text,              -- e.g. '5-a-side', 'Full court'
  surface text,                 -- e.g. 'Artificial grass'
  base_price int not null check (base_price >= 0),   -- INR per slot
  max_players int not null default 14 check (max_players > 0),
  is_active boolean not null default true,
  sort_order int not null default 0
);
create index on public.courts (turf_id);

create table public.court_sports (
  court_id uuid not null references public.courts(id) on delete cascade,
  sport_id text not null references public.sports(id),
  primary key (court_id, sport_id)
);

-- Time-based pricing (off-peak / happy hour / weekend peak).
create table public.pricing_rules (
  id uuid primary key default gen_random_uuid(),
  turf_id uuid not null references public.turfs(id) on delete cascade,
  court_id uuid references public.courts(id) on delete cascade,   -- null = all courts
  days_of_week int[] not null,
  start_time time not null,
  end_time time not null,
  price int not null check (price >= 0),
  label text,
  is_offpeak boolean not null default false,
  check (end_time > start_time)
);
create index on public.pricing_rules (turf_id);

-- -----------------------------------------------------------------------------
-- Users
-- -----------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  email text,
  avatar_url text,
  preferred_sports text[] not null default '{}',
  skill_level public.skill_level,
  onboarded boolean not null default false,
  strikes int not null default 0,
  booking_blocked_until timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, phone, email, full_name)
  values (new.id, new.phone, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create table public.favourites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  turf_id uuid not null references public.turfs(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, turf_id)
);

-- -----------------------------------------------------------------------------
-- Bookings
-- -----------------------------------------------------------------------------
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  qr_token text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  turf_id uuid not null references public.turfs(id),
  court_id uuid not null references public.courts(id),
  sport_id text not null references public.sports(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  players_count int not null check (players_count > 0),
  total_price int not null,
  status public.booking_status not null default 'confirmed',
  note text,
  cancelled_at timestamptz,
  cancel_reason text,
  checked_in_at timestamptz,
  reminder_sent_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  constraint bookings_no_overlap exclude using gist (
    court_id with =, time_range with &&
  ) where (status in ('confirmed', 'checked_in'))
);
create index on public.bookings (user_id, starts_at desc);
create index on public.bookings (turf_id, starts_at);

-- -----------------------------------------------------------------------------
-- Find players / open games
-- -----------------------------------------------------------------------------
create table public.open_games (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  host_id uuid not null references public.profiles(id) on delete cascade,
  turf_id uuid not null references public.turfs(id),
  sport_id text not null references public.sports(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  spots_total int not null check (spots_total > 0),
  skill_level public.skill_level,
  note text,
  status public.game_status not null default 'open',
  created_at timestamptz not null default now()
);
create index on public.open_games (status, starts_at);

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.open_games(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text,
  status public.join_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (game_id, user_id)
);

-- -----------------------------------------------------------------------------
-- Reviews
-- -----------------------------------------------------------------------------
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  turf_id uuid not null references public.turfs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);
create index on public.reviews (turf_id, created_at desc);

create or replace function public.refresh_turf_rating()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_turf uuid := coalesce(new.turf_id, old.turf_id);
begin
  update turfs t set
    rating_avg = coalesce((select round(avg(rating)::numeric, 1) from reviews where turf_id = v_turf), 0),
    rating_count = (select count(*) from reviews where turf_id = v_turf)
  where t.id = v_turf;
  return null;
end $$;
create trigger reviews_refresh_rating after insert or update or delete on public.reviews
  for each row execute function public.refresh_turf_rating();

-- -----------------------------------------------------------------------------
-- Notifications (in-app inbox + web push queue)
-- -----------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  url text,
  read_at timestamptz,
  push_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.notifications (user_id, created_at desc);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create or replace function public.notify(
  p_user uuid, p_type text, p_title text, p_body text, p_url text default null)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, type, title, body, url)
  values (p_user, p_type, p_title, p_body, p_url);
$$;
revoke execute on function public.notify(uuid, text, text, text, text) from public, anon, authenticated;

-- =============================================================================
-- Row Level Security
-- =============================================================================
alter table public.app_settings enable row level security;
alter table public.sports enable row level security;
alter table public.amenities enable row level security;
alter table public.turfs enable row level security;
alter table public.turf_photos enable row level security;
alter table public.turf_amenities enable row level security;
alter table public.operating_hours enable row level security;
alter table public.courts enable row level security;
alter table public.court_sports enable row level security;
alter table public.pricing_rules enable row level security;
alter table public.profiles enable row level security;
alter table public.favourites enable row level security;
alter table public.bookings enable row level security;
alter table public.open_games enable row level security;
alter table public.join_requests enable row level security;
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;

-- Public catalogue (read-only for everyone)
create policy "public read" on public.app_settings for select using (true);
create policy "public read" on public.sports for select using (true);
create policy "public read" on public.amenities for select using (true);
create policy "public read" on public.turfs for select using (is_active);
create policy "public read" on public.turf_photos for select using (true);
create policy "public read" on public.turf_amenities for select using (true);
create policy "public read" on public.operating_hours for select using (true);
create policy "public read" on public.courts for select using (is_active);
create policy "public read" on public.court_sports for select using (true);
create policy "public read" on public.pricing_rules for select using (true);
create policy "public read" on public.reviews for select using (true);

-- Profiles: own row only; only "safe" columns are updatable
create policy "own profile read" on public.profiles for select to authenticated using (id = auth.uid());
create policy "own profile update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from anon, authenticated;
grant update (full_name, avatar_url, preferred_sports, skill_level, onboarded) on public.profiles to authenticated;

-- Favourites
create policy "own favourites" on public.favourites for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Bookings: read own; writes only via RPC
create policy "own bookings read" on public.bookings for select to authenticated using (user_id = auth.uid());

-- Open games: visible to signed-in users; writes via RPC
create policy "games read" on public.open_games for select to authenticated using (true);

-- Join requests: requester or host
create policy "join requests read" on public.join_requests for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.open_games g where g.id = game_id and g.host_id = auth.uid())
);

-- Notifications: own
create policy "own notifications read" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "own notifications update" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Push subscriptions: own
create policy "own push subs" on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Realtime for the in-app notification inbox
alter publication supabase_realtime add table public.notifications;


-- >>> 20261030000002_rpc_and_rules.sql
-- =============================================================================
-- Turffet: RPCs, business rules, realtime, reminders
-- =============================================================================
set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function public.fmt_ist(p_ts timestamptz)
returns text language sql immutable set search_path = public as $$
  select to_char(p_ts at time zone 'Asia/Kolkata', 'Dy DD Mon, FMHH12:MI AM');
$$;

-- -----------------------------------------------------------------------------
-- Discover: nearby turfs with filters
-- -----------------------------------------------------------------------------
create or replace function public.nearby_turfs(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_km double precision default 60,
  p_sport text default null,
  p_max_price int default null,
  p_search text default null,
  p_amenities text[] default null,
  p_offpeak_only boolean default false
)
returns table (
  id uuid, slug text, name text, area text, address text,
  lat double precision, lng double precision, cover_image text,
  rating_avg numeric, rating_count int, distance_km double precision,
  min_price int, offpeak_price int, sports text[], amenities text[],
  opens_at time, closes_at time
)
language sql stable security invoker set search_path = public, extensions as $$
  with t as (
    select tf.*,
      case when p_lat is null or p_lng is null then null
           else st_distance(tf.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0
      end as dist
    from turfs tf
    where tf.is_active
  )
  select
    t.id, t.slug, t.name, t.area, t.address, t.lat, t.lng, t.cover_image,
    t.rating_avg, t.rating_count,
    round(t.dist::numeric, 1)::double precision,
    (select min(c.base_price) from courts c where c.turf_id = t.id and c.is_active),
    (select min(pr.price) from pricing_rules pr where pr.turf_id = t.id and pr.is_offpeak),
    array(select distinct cs.sport_id from courts c join court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active order by 1),
    array(select ta.amenity_id from turf_amenities ta where ta.turf_id = t.id order by 1),
    (select min(oh.open_time) from operating_hours oh where oh.turf_id = t.id),
    (select max(oh.close_time) from operating_hours oh where oh.turf_id = t.id)
  from t
  where (t.dist is null or t.dist <= p_radius_km)
    and (p_sport is null or exists (
          select 1 from courts c join court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active and cs.sport_id = p_sport))
    and (p_max_price is null or exists (
          select 1 from courts c where c.turf_id = t.id and c.is_active and c.base_price <= p_max_price)
         or exists (select 1 from pricing_rules pr where pr.turf_id = t.id and pr.price <= p_max_price))
    and (p_search is null or p_search = '' or t.name ilike '%' || p_search || '%' or t.area ilike '%' || p_search || '%')
    and (p_amenities is null or cardinality(p_amenities) = 0
         or p_amenities <@ array(select ta.amenity_id from turf_amenities ta where ta.turf_id = t.id))
    and (not p_offpeak_only or exists (select 1 from pricing_rules pr where pr.turf_id = t.id and pr.is_offpeak))
  order by t.dist asc nulls last, t.rating_avg desc, t.name;
$$;

-- -----------------------------------------------------------------------------
-- Pricing for one slot (court-specific rule beats turf-wide rule)
-- -----------------------------------------------------------------------------
create or replace function public.slot_price(p_court_id uuid, p_start timestamptz)
returns table (price int, label text, is_offpeak boolean)
language sql stable set search_path = public as $$
  select coalesce(r.price, c.base_price), r.label, coalesce(r.is_offpeak, false)
  from courts c
  cross join lateral (select (p_start at time zone 'Asia/Kolkata') as ts) lt
  left join lateral (
    select pr.price, pr.label, pr.is_offpeak
    from pricing_rules pr
    where pr.turf_id = c.turf_id
      and (pr.court_id is null or pr.court_id = c.id)
      and extract(dow from lt.ts)::int = any (pr.days_of_week)
      and lt.ts::time >= pr.start_time
      and lt.ts::time < pr.end_time
    order by (pr.court_id is not null) desc, pr.price asc
    limit 1
  ) r on true
  where c.id = p_court_id;
$$;

-- -----------------------------------------------------------------------------
-- Slot grid for a turf on a given (IST) date
-- -----------------------------------------------------------------------------
create or replace function public.get_turf_slots(p_turf_id uuid, p_date date)
returns table (
  court_id uuid, starts_at timestamptz, ends_at timestamptz,
  price int, label text, is_offpeak boolean, is_available boolean, is_mine boolean
)
language sql stable security definer set search_path = public as $$
  with t as (select * from turfs where id = p_turf_id and is_active),
  oh as (
    select o.* from operating_hours o join t on t.id = o.turf_id
    where o.day_of_week = extract(dow from p_date)::int
  ),
  s as (
    select c.id as court_id,
           (g at time zone 'Asia/Kolkata') as starts_at,
           (g at time zone 'Asia/Kolkata') + make_interval(mins => t.slot_minutes) as ends_at
    from t
    join oh on true
    join courts c on c.turf_id = t.id and c.is_active
    cross join lateral generate_series(
      p_date + oh.open_time,
      p_date + oh.close_time - make_interval(mins => t.slot_minutes),
      make_interval(mins => t.slot_minutes)
    ) g
  )
  select s.court_id, s.starts_at, s.ends_at, sp.price, sp.label, sp.is_offpeak,
         (s.starts_at > now() and b.id is null) as is_available,
         coalesce(b.user_id = auth.uid(), false) as is_mine
  from s
  cross join lateral public.slot_price(s.court_id, s.starts_at) sp
  left join lateral (
    select bk.id, bk.user_id from bookings bk
    where bk.court_id = s.court_id
      and bk.status in ('confirmed', 'checked_in')
      and bk.time_range && tstzrange(s.starts_at, s.ends_at, '[)')
    limit 1
  ) b on true
  order by s.court_id, s.starts_at;
$$;

-- -----------------------------------------------------------------------------
-- Create booking
-- -----------------------------------------------------------------------------
create or replace function public.create_booking(
  p_court_id uuid,
  p_sport_id text,
  p_starts_at timestamptz,
  p_slots int,
  p_players int,
  p_looking_for int default 0,
  p_skill public.skill_level default null,
  p_note text default null
)
returns public.bookings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_set app_settings;
  v_profile profiles;
  v_court courts;
  v_turf turfs;
  v_end timestamptz;
  v_local timestamp;
  v_local_end timestamp;
  v_total int := 0;
  v_price int;
  v_count int;
  v_code text;
  v_id uuid := gen_random_uuid();
  v_key text;
  v_booking bookings;
  v_looking int := coalesce(p_looking_for, 0);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into v_set from app_settings limit 1;
  select * into v_profile from profiles where id = v_uid;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  if v_profile.booking_blocked_until is not null and v_profile.booking_blocked_until > now() then
    raise exception 'BOOKING_BLOCKED';
  end if;

  select * into v_court from courts where id = p_court_id and is_active;
  if not found then raise exception 'COURT_NOT_FOUND'; end if;
  select * into v_turf from turfs where id = v_court.turf_id and is_active;
  if not found then raise exception 'TURF_NOT_FOUND'; end if;

  if not exists (select 1 from court_sports where court_id = p_court_id and sport_id = p_sport_id) then
    raise exception 'SPORT_NOT_SUPPORTED';
  end if;
  if p_slots is null or p_slots < 1 or p_slots > v_set.max_slots_per_booking then
    raise exception 'TOO_MANY_SLOTS';
  end if;
  if p_players is null or p_players < 1 or v_looking < 0 or p_players + v_looking > v_court.max_players then
    raise exception 'INVALID_PLAYERS';
  end if;
  if p_starts_at <= now() then raise exception 'SLOT_IN_PAST'; end if;
  if p_starts_at > now() + make_interval(days => v_set.booking_horizon_days) then
    raise exception 'TOO_FAR_AHEAD';
  end if;

  v_end := p_starts_at + make_interval(mins => v_turf.slot_minutes * p_slots);
  v_local := p_starts_at at time zone 'Asia/Kolkata';
  v_local_end := v_end at time zone 'Asia/Kolkata';

  -- must be inside operating hours and aligned to the slot grid
  if not exists (
    select 1 from operating_hours oh
    where oh.turf_id = v_turf.id
      and oh.day_of_week = extract(dow from v_local)::int
      and v_local >= v_local::date + oh.open_time
      and v_local_end <= v_local::date + oh.close_time
      and (extract(epoch from (v_local - (v_local::date + oh.open_time))) / 60)::int % v_turf.slot_minutes = 0
  ) then
    raise exception 'OUTSIDE_HOURS';
  end if;

  -- per-day limit (anti-hoarding, since there is no payment yet)
  select count(*) into v_count from bookings
  where user_id = v_uid and status in ('confirmed', 'checked_in')
    and (starts_at at time zone 'Asia/Kolkata')::date = v_local::date;
  if v_count >= v_set.max_bookings_per_day then raise exception 'DAILY_LIMIT'; end if;

  -- price is always computed on the server
  for i in 0 .. p_slots - 1 loop
    select sp.price into v_price
    from slot_price(p_court_id, p_starts_at + make_interval(mins => v_turf.slot_minutes * i)) sp;
    v_total := v_total + v_price;
  end loop;

  -- short human code (no ambiguous characters)
  loop
    v_code := '';
    for i in 1 .. 6 loop
      v_code := v_code || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from bookings where code = v_code);
  end loop;

  -- signed QR token: TFT1.<booking id>.<code>.<hmac>
  select value into v_key from private.app_secrets where name = 'qr_signing_key';

  begin
    insert into bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                          starts_at, ends_at, players_count, total_price, note)
    values (
      v_id, v_code,
      'TFT1.' || v_id || '.' || v_code || '.' ||
        substr(encode(hmac(v_id::text || '.' || v_code, v_key, 'sha256'), 'hex'), 1, 24),
      v_uid, v_turf.id, p_court_id, p_sport_id, p_starts_at, v_end, p_players, v_total, p_note)
    returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;

  if v_looking > 0 then
    insert into open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at,
                            spots_total, skill_level, note)
    values (v_booking.id, v_uid, v_turf.id, p_sport_id, p_starts_at, v_end,
            v_looking, p_skill, p_note);
  end if;

  perform notify(v_uid, 'booking_confirmed', 'Booking confirmed ✅',
    v_turf.name || ' · ' || fmt_ist(p_starts_at) || ' · Code ' || v_code,
    '/bookings/' || v_booking.id);

  return v_booking;
end $$;

-- -----------------------------------------------------------------------------
-- Cancel booking (free until the cancellation window)
-- -----------------------------------------------------------------------------
create or replace function public.cancel_booking(p_booking_id uuid, p_reason text default null)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_set app_settings;
  v_b bookings;
  v_turf_name text;
  r record;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_set from app_settings limit 1;

  select * into v_b from bookings where id = p_booking_id and user_id = auth.uid() for update;
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.status <> 'confirmed' then raise exception 'NOT_CANCELLABLE'; end if;
  if v_b.starts_at - now() < make_interval(mins => v_set.cancellation_window_minutes) then
    raise exception 'CANCELLATION_WINDOW_PASSED';
  end if;

  update bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason
  where id = p_booking_id returning * into v_b;

  select name into v_turf_name from turfs where id = v_b.turf_id;

  for r in
    select jr.user_id from join_requests jr join open_games g on g.id = jr.game_id
    where g.booking_id = v_b.id and jr.status in ('pending', 'accepted')
  loop
    perform notify(r.user_id, 'game_cancelled', 'Game cancelled',
      'The host cancelled the game at ' || v_turf_name || ' (' || fmt_ist(v_b.starts_at) || ').', '/games');
  end loop;
  update open_games set status = 'closed' where booking_id = v_b.id;

  perform notify(v_b.user_id, 'booking_cancelled', 'Booking cancelled',
    v_turf_name || ' · ' || fmt_ist(v_b.starts_at), '/bookings/' || v_b.id);

  return v_b;
end $$;

-- -----------------------------------------------------------------------------
-- Reviews
-- -----------------------------------------------------------------------------
create or replace function public.get_turf_reviews(p_turf_id uuid, p_limit int default 20)
returns table (id uuid, rating int, comment text, created_at timestamptz, reviewer_name text, sport_id text)
language sql stable security definer set search_path = public as $$
  select r.id, r.rating, r.comment, r.created_at,
         coalesce(nullif(split_part(p.full_name, ' ', 1), ''), 'Player'),
         b.sport_id
  from reviews r
  join profiles p on p.id = r.user_id
  join bookings b on b.id = r.booking_id
  where r.turf_id = p_turf_id
  order by r.created_at desc
  limit p_limit;
$$;

create or replace function public.submit_review(p_booking_id uuid, p_rating int, p_comment text default null)
returns public.reviews
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_r reviews;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_b from bookings where id = p_booking_id and user_id = auth.uid();
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  -- v1: allowed after the slot ends (owner check-in comes with the owner portal)
  if v_b.status in ('cancelled', 'no_show') or v_b.ends_at > now() then
    raise exception 'REVIEW_NOT_ALLOWED';
  end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'INVALID_RATING'; end if;
  insert into reviews (booking_id, turf_id, user_id, rating, comment)
  values (v_b.id, v_b.turf_id, auth.uid(), p_rating, nullif(trim(p_comment), ''))
  on conflict (booking_id) do update set rating = excluded.rating, comment = excluded.comment
  returning * into v_r;
  return v_r;
end $$;

-- -----------------------------------------------------------------------------
-- Find players / open games
-- -----------------------------------------------------------------------------
create or replace function public.list_games(
  p_lat double precision default null,
  p_lng double precision default null,
  p_sport text default null,
  p_mine boolean default false
)
returns table (
  id uuid, booking_id uuid, turf_id uuid, turf_name text, turf_area text, turf_cover text,
  sport_id text, starts_at timestamptz, ends_at timestamptz,
  spots_total int, spots_filled int, players_count int, total_price int,
  skill_level public.skill_level, note text, status public.game_status,
  host_name text, is_host boolean, my_status public.join_status, distance_km double precision
)
language sql stable security definer set search_path = public, extensions as $$
  select g.id, g.booking_id, t.id, t.name, t.area, t.cover_image,
         g.sport_id, g.starts_at, g.ends_at,
         g.spots_total,
         (select count(*)::int from join_requests jr where jr.game_id = g.id and jr.status = 'accepted'),
         b.players_count, b.total_price,
         g.skill_level, g.note, g.status,
         coalesce(nullif(split_part(hp.full_name, ' ', 1), ''), 'Player'),
         g.host_id = auth.uid(),
         mj.status,
         case when p_lat is null or p_lng is null then null
              else round((st_distance(t.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0)::numeric, 1)::double precision
         end
  from open_games g
  join turfs t on t.id = g.turf_id
  join bookings b on b.id = g.booking_id
  join profiles hp on hp.id = g.host_id
  left join join_requests mj on mj.game_id = g.id and mj.user_id = auth.uid()
  where auth.uid() is not null
    and g.ends_at > now()
    and (p_sport is null or g.sport_id = p_sport)
    and (
      (p_mine and (g.host_id = auth.uid() or mj.status in ('pending', 'accepted')))
      or (not p_mine and g.status = 'open' and g.starts_at > now())
    )
  order by g.starts_at;
$$;

create or replace function public.get_game_detail(p_game_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_g open_games;
  v_is_host boolean;
  v_my join_requests;
  v_host profiles;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_g from open_games where id = p_game_id;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;
  v_is_host := v_g.host_id = v_uid;
  select * into v_my from join_requests where game_id = p_game_id and user_id = v_uid;
  select * into v_host from profiles where id = v_g.host_id;

  select jsonb_build_object(
    'id', v_g.id,
    'status', v_g.status,
    'sport_id', v_g.sport_id,
    'starts_at', v_g.starts_at,
    'ends_at', v_g.ends_at,
    'spots_total', v_g.spots_total,
    'skill_level', v_g.skill_level,
    'note', v_g.note,
    'is_host', v_is_host,
    'my_request', case when v_my.id is null then null
                       else jsonb_build_object('id', v_my.id, 'status', v_my.status) end,
    'host', jsonb_build_object(
      'name', coalesce(nullif(v_host.full_name, ''), 'Player'),
      'skill_level', v_host.skill_level,
      'phone', case when v_my.status = 'accepted' then v_host.phone end
    ),
    'booking', (
      select jsonb_build_object('players_count', b.players_count, 'total_price', b.total_price,
                                'court_name', c.name, 'size_label', c.size_label)
      from bookings b join courts c on c.id = b.court_id where b.id = v_g.booking_id
    ),
    'turf', (
      select jsonb_build_object('id', t.id, 'slug', t.slug, 'name', t.name, 'area', t.area,
                                'address', t.address, 'lat', t.lat, 'lng', t.lng, 'cover_image', t.cover_image)
      from turfs t where t.id = v_g.turf_id
    ),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', coalesce(nullif(split_part(p.full_name, ' ', 1), ''), 'Player'),
               'skill_level', p.skill_level) order by jr.responded_at)
      from join_requests jr join profiles p on p.id = jr.user_id
      where jr.game_id = p_game_id and jr.status = 'accepted'
    ), '[]'::jsonb),
    'requests', case when v_is_host then coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', jr.id, 'status', jr.status, 'message', jr.message, 'created_at', jr.created_at,
               'name', coalesce(nullif(p.full_name, ''), 'Player'),
               'skill_level', p.skill_level,
               'phone', case when jr.status = 'accepted' then p.phone end)
             order by jr.created_at)
      from join_requests jr join profiles p on p.id = jr.user_id
      where jr.game_id = p_game_id and jr.status <> 'withdrawn'
    ), '[]'::jsonb) else null end
  ) into v_result;

  return v_result;
end $$;

create or replace function public.request_join(p_game_id uuid, p_message text default null)
returns public.join_requests
language plpgsql security definer set search_path = public as $$
declare v_g open_games; v_r join_requests; v_name text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_g from open_games where id = p_game_id for update;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;
  if v_g.host_id = auth.uid() then raise exception 'CANNOT_JOIN_OWN_GAME'; end if;
  if v_g.status <> 'open' or v_g.starts_at <= now() then raise exception 'GAME_NOT_OPEN'; end if;

  select * into v_r from join_requests where game_id = p_game_id and user_id = auth.uid();
  if found then
    if v_r.status = 'declined' then raise exception 'REQUEST_DECLINED'; end if;
    if v_r.status in ('pending', 'accepted') then return v_r; end if;
    update join_requests set status = 'pending', message = p_message, created_at = now(), responded_at = null
    where id = v_r.id returning * into v_r;
  else
    insert into join_requests (game_id, user_id, message) values (p_game_id, auth.uid(), p_message)
    returning * into v_r;
  end if;

  select coalesce(nullif(full_name, ''), 'A player') into v_name from profiles where id = auth.uid();
  perform notify(v_g.host_id, 'join_request', 'New join request 🙋',
    v_name || ' wants to join your game on ' || fmt_ist(v_g.starts_at), '/games/' || v_g.id);
  return v_r;
end $$;

create or replace function public.respond_join(p_request_id uuid, p_accept boolean)
returns public.join_requests
language plpgsql security definer set search_path = public as $$
declare v_r join_requests; v_g open_games; v_filled int; v_turf text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_r from join_requests where id = p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  select * into v_g from open_games where id = v_r.game_id for update;
  if v_g.host_id <> auth.uid() then raise exception 'NOT_HOST'; end if;
  if v_r.status <> 'pending' then raise exception 'REQUEST_NOT_PENDING'; end if;

  select count(*) into v_filled from join_requests where game_id = v_g.id and status = 'accepted';
  if p_accept and v_filled >= v_g.spots_total then raise exception 'GAME_FULL'; end if;

  update join_requests set status = case when p_accept then 'accepted'::join_status else 'declined'::join_status end,
         responded_at = now()
  where id = p_request_id returning * into v_r;

  if p_accept and v_filled + 1 >= v_g.spots_total then
    update open_games set status = 'full' where id = v_g.id;
  end if;

  select name into v_turf from turfs where id = v_g.turf_id;
  if p_accept then
    perform notify(v_r.user_id, 'join_accepted', 'You''re in! 🎉',
      'Your request to play at ' || v_turf || ' on ' || fmt_ist(v_g.starts_at) || ' was accepted.', '/games/' || v_g.id);
  else
    perform notify(v_r.user_id, 'join_declined', 'Request declined',
      'The host couldn''t fit you in at ' || v_turf || ' this time.', '/games');
  end if;
  return v_r;
end $$;

create or replace function public.withdraw_join(p_game_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_r join_requests; v_g open_games; v_name text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_r from join_requests where game_id = p_game_id and user_id = auth.uid();
  if not found or v_r.status not in ('pending', 'accepted') then raise exception 'REQUEST_NOT_FOUND'; end if;
  select * into v_g from open_games where id = p_game_id for update;
  update join_requests set status = 'withdrawn', responded_at = now() where id = v_r.id;
  if v_r.status = 'accepted' then
    if v_g.status = 'full' and v_g.starts_at > now() then
      update open_games set status = 'open' where id = v_g.id;
    end if;
    select coalesce(nullif(full_name, ''), 'A player') into v_name from profiles where id = auth.uid();
    perform notify(v_g.host_id, 'join_withdrawn', 'Player dropped out',
      v_name || ' can no longer make it on ' || fmt_ist(v_g.starts_at) || '. Your game is open again.', '/games/' || v_g.id);
  end if;
end $$;

create or replace function public.set_game_open(p_game_id uuid, p_open boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_g open_games; v_filled int;
begin
  select * into v_g from open_games where id = p_game_id for update;
  if not found or v_g.host_id <> auth.uid() then raise exception 'NOT_HOST'; end if;
  select count(*) into v_filled from join_requests where game_id = v_g.id and status = 'accepted';
  update open_games set status = case
      when not p_open then 'closed'::game_status
      when v_filled >= v_g.spots_total then 'full'::game_status
      else 'open'::game_status end
  where id = p_game_id;
end $$;

-- -----------------------------------------------------------------------------
-- Realtime: broadcast availability changes per turf (public channel)
-- -----------------------------------------------------------------------------
create or replace function public.broadcast_availability()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform realtime.send(
    jsonb_build_object('court_id', new.court_id, 'starts_at', new.starts_at, 'status', new.status),
    'availability', 'turf-' || new.turf_id::text, false);
  return null;
exception when others then
  return null;   -- realtime is best-effort; never block a booking
end $$;
create trigger bookings_broadcast after insert or update of status on public.bookings
  for each row execute function public.broadcast_availability();

-- -----------------------------------------------------------------------------
-- Web push dispatch (Edge Function `send-push`, called through pg_net)
-- -----------------------------------------------------------------------------
do $$ begin
  create extension if not exists pg_net;
exception when others then raise notice 'pg_net unavailable: %', sqlerrm;
end $$;

create or replace function public.dispatch_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text;
begin
  select value into v_url from private.app_secrets where name = 'push_function_url';
  select value into v_secret from private.app_secrets where name = 'push_webhook_secret';
  if v_url is null or v_secret is null then return null; end if;
  if not exists (select 1 from push_subscriptions where user_id = new.user_id) then return null; end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
  return null;
exception when others then
  return null;
end $$;
create trigger notifications_dispatch_push after insert on public.notifications
  for each row execute function public.dispatch_push();

-- -----------------------------------------------------------------------------
-- Maintenance: reminders, completing past bookings, (optional) no-show strikes
-- -----------------------------------------------------------------------------
create or replace function public.run_maintenance()
returns void language plpgsql security definer set search_path = public as $$
declare v_set app_settings; r record; p record;
begin
  select * into v_set from app_settings limit 1;

  -- Reminders
  for r in
    select b.*, t.name as turf_name from bookings b join turfs t on t.id = b.turf_id
    where b.status = 'confirmed' and b.reminder_sent_at is null
      and b.starts_at > now()
      and b.starts_at <= now() + make_interval(mins => v_set.reminder_minutes_before)
  loop
    perform notify(r.user_id, 'booking_reminder', 'Game time soon ⏰',
      r.turf_name || ' at ' || to_char(r.starts_at at time zone 'Asia/Kolkata', 'FMHH12:MI AM') ||
      '. Show your QR (code ' || r.code || ') at the venue.', '/bookings/' || r.id);
    for p in
      select jr.user_id from join_requests jr join open_games g on g.id = jr.game_id
      where g.booking_id = r.id and jr.status = 'accepted'
    loop
      perform notify(p.user_id, 'game_reminder', 'Game time soon ⏰',
        r.turf_name || ' at ' || to_char(r.starts_at at time zone 'Asia/Kolkata', 'FMHH12:MI AM') || '.',
        '/games');
    end loop;
    update bookings set reminder_sent_at = now() where id = r.id;
  end loop;

  -- Past bookings
  if v_set.strikes_enabled then
    for r in
      update bookings set status = 'no_show'
      where status = 'confirmed' and ends_at < now() - interval '30 minutes'
      returning user_id
    loop
      update profiles set strikes = strikes + 1,
        booking_blocked_until = case when strikes + 1 >= v_set.strike_limit
                                     then now() + make_interval(days => v_set.strike_block_days)
                                     else booking_blocked_until end
      where id = r.user_id;
    end loop;
    update bookings set status = 'completed' where status = 'checked_in' and ends_at < now();
  else
    update bookings set status = 'completed'
    where status in ('confirmed', 'checked_in') and ends_at < now();
  end if;

  -- Close games that have started
  update open_games set status = 'closed' where status <> 'closed' and starts_at <= now();
end $$;
revoke execute on function public.run_maintenance() from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('turffet-maintenance', '*/5 * * * *', 'select public.run_maintenance()');
exception when others then raise notice 'pg_cron unavailable: %', sqlerrm;
end $$;

-- -----------------------------------------------------------------------------
-- Grants for RPCs
-- -----------------------------------------------------------------------------
revoke execute on function public.create_booking(uuid, text, timestamptz, int, int, int, public.skill_level, text) from anon;
revoke execute on function public.cancel_booking(uuid, text) from anon;
revoke execute on function public.submit_review(uuid, int, text) from anon;
revoke execute on function public.request_join(uuid, text) from anon;
revoke execute on function public.respond_join(uuid, boolean) from anon;
revoke execute on function public.withdraw_join(uuid) from anon;
revoke execute on function public.set_game_open(uuid, boolean) from anon;


-- >>> 20261030000003_seed_catalogue.sql
-- =============================================================================
-- Turffet: catalogue + sample Delhi NCR turfs
-- (Sample data until the owner portal exists. Phone numbers are placeholders.)
-- =============================================================================
set search_path = public, extensions;

insert into public.sports (id, name, emoji, sort_order) values
  ('football',   'Football',   '⚽', 1),
  ('cricket',    'Box Cricket','🏏', 2),
  ('badminton',  'Badminton',  '🏸', 3),
  ('pickleball', 'Pickleball', '🏓', 4),
  ('tennis',     'Tennis',     '🎾', 5),
  ('basketball', 'Basketball', '🏀', 6),
  ('volleyball', 'Volleyball', '🏐', 7)
on conflict (id) do nothing;

insert into public.amenities (id, name, icon, sort_order) values
  ('parking',          'Parking',          'car',            1),
  ('floodlights',      'Floodlights',      'lightbulb',      2),
  ('washroom',         'Washroom',         'bath',           3),
  ('changing_room',    'Changing room',    'shirt',          4),
  ('drinking_water',   'Drinking water',   'glass-water',    5),
  ('shower',           'Shower',           'shower-head',    6),
  ('cafe',             'Café / snacks',    'coffee',         7),
  ('equipment_rental', 'Equipment rental', 'package',        8),
  ('seating',          'Seating area',     'armchair',       9),
  ('first_aid',        'First aid',        'cross',         10),
  ('cctv',             'CCTV',             'cctv',          11),
  ('air_conditioned',  'Air conditioned',  'snowflake',     12),
  ('wifi',             'Wi-Fi',            'wifi',          13)
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Temporary seeding helper
-- -----------------------------------------------------------------------------
create or replace function pg_temp.seed_turf(d jsonb) returns void
language plpgsql as $$
declare
  v_turf uuid;
  v_court uuid;
  c jsonb;
  r jsonb;
  s text;
  i int := 0;
  dow int;
begin
  insert into public.turfs (slug, name, description, area, address, lat, lng, phone, whatsapp,
                            cover_image, rules, slot_minutes)
  values (d->>'slug', d->>'name', d->>'desc', d->>'area', d->>'address',
          (d->>'lat')::float8, (d->>'lng')::float8, d->>'phone', d->>'phone',
          d->'photos'->>0,
          array(select jsonb_array_elements_text(coalesce(d->'rules', '[]'::jsonb))),
          coalesce((d->>'slot')::int, 60))
  returning id into v_turf;

  for s in select jsonb_array_elements_text(d->'photos') loop
    insert into public.turf_photos (turf_id, url, sort_order) values (v_turf, s, i);
    i := i + 1;
  end loop;

  for s in select jsonb_array_elements_text(d->'amenities') loop
    insert into public.turf_amenities (turf_id, amenity_id) values (v_turf, s);
  end loop;

  for dow in 0..6 loop
    insert into public.operating_hours (turf_id, day_of_week, open_time, close_time)
    values (v_turf, dow,
            case when dow in (0, 6) then coalesce(d->>'weekend_open', d->>'open') else d->>'open' end::time,
            (d->>'close')::time);
  end loop;

  i := 0;
  for c in select * from jsonb_array_elements(d->'courts') loop
    insert into public.courts (turf_id, name, size_label, surface, base_price, max_players, sort_order)
    values (v_turf, c->>'name', c->>'size', c->>'surface', (c->>'price')::int, (c->>'max')::int, i)
    returning id into v_court;
    i := i + 1;

    for s in select jsonb_array_elements_text(c->'sports') loop
      insert into public.court_sports (court_id, sport_id) values (v_court, s);
    end loop;

    -- pricing rules are defined as % of the court's base price
    for r in select * from jsonb_array_elements(coalesce(d->'pricing', '[]'::jsonb)) loop
      insert into public.pricing_rules (turf_id, court_id, days_of_week, start_time, end_time, price, label, is_offpeak)
      values (v_turf, v_court,
              array(select jsonb_array_elements_text(r->'days')::int),
              (r->>'start')::time, (r->>'end')::time,
              (round((c->>'price')::numeric * (100 - (r->>'pct')::int) / 100 / 10) * 10)::int,
              r->>'label',
              (r->>'pct')::int > 0);
    end loop;
  end loop;
end $$;

-- Common pricing patterns
-- weekday mornings / afternoons are discounted, weekend evenings are premium.
do $$
declare
  football_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"06:00","end":"09:00","pct":35,"label":"Happy Hour"},
    {"days":[1,2,3,4,5],"start":"12:00","end":"16:00","pct":30,"label":"Afternoon Deal"},
    {"days":[0,6],"start":"18:00","end":"23:00","pct":-15,"label":"Weekend Prime"}
  ]';
  cricket_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"07:00","end":"10:00","pct":30,"label":"Early Bird"},
    {"days":[1,2,3,4,5],"start":"13:00","end":"17:00","pct":35,"label":"Afternoon Deal"},
    {"days":[0,6],"start":"17:00","end":"23:00","pct":-10,"label":"Weekend Prime"}
  ]';
  racquet_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"10:00","end":"16:00","pct":40,"label":"Midday Deal"},
    {"days":[0,1,2,3,4,5,6],"start":"21:00","end":"23:00","pct":20,"label":"Late Night"}
  ]';
  mixed_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"06:00","end":"09:00","pct":30,"label":"Happy Hour"},
    {"days":[1,2,3,4,5],"start":"11:00","end":"16:00","pct":35,"label":"Afternoon Deal"}
  ]';
  std_rules jsonb := '["Turf/non-marking shoes only, no metal studs","Please arrive 10 minutes before your slot","No smoking, alcohol or food on the playing area","Show your Turffet QR at the reception"]';
  court_rules jsonb := '["Non-marking shoes are mandatory","Max 4 players per court","Please arrive 10 minutes before your slot","Show your Turffet QR at the reception"]';
begin
  -- ============================ GURUGRAM ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','kickoff-arena-sector-29','name','Kickoff Arena','area','Sector 29, Gurugram',
    'address','Plot 12, Leisure Valley Road, Sector 29, Gurugram, Haryana 122001',
    'lat',28.4683,'lng',77.0634,'phone','+919810000101',
    'desc','Premium FIFA-grade artificial grass with two floodlit pitches right next to Leisure Valley. Popular with corporate leagues on weeknights.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/football-closeup.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","cafe","equipment_rental","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Pitch A","size":"5-a-side","surface":"Artificial grass","price":1400,"max":12,"sports":["football"]},
      {"name":"Pitch B","size":"7-a-side","surface":"Artificial grass","price":2200,"max":16,"sports":["football"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','the-box-cricket-co-golf-course-road','name','The Box Cricket Co.','area','Golf Course Road, Gurugram',
    'address','Sector 54, Near Rapid Metro, Golf Course Road, Gurugram, Haryana 122011',
    'lat',28.4390,'lng',77.1030,'phone','+919810000102',
    'desc','Two netted box-cricket arenas with bowling machine on request. Great for office matches and birthday games.',
    'photos','["/images/turfs/box-cricket.jpg","/images/turfs/cricket-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating"]'::jsonb,
    'open','07:00','close','24:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Box 1","size":"8 vs 8","surface":"Artificial turf","price":1500,"max":16,"sports":["cricket"]},
      {"name":"Box 2","size":"6 vs 6","surface":"Artificial turf","price":1200,"max":12,"sports":["cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','smash-hub-sector-57','name','Smash Hub Badminton','area','Sector 57, Gurugram',
    'address','Basement 1, Sushant Lok III, Sector 57, Gurugram, Haryana 122003',
    'lat',28.4220,'lng',77.0790,'phone','+919810000103',
    'desc','Four BWF-approved synthetic mat courts with anti-glare lighting and full air conditioning.',
    'photos','["/images/turfs/badminton.jpg"]'::jsonb,
    'amenities','["parking","washroom","drinking_water","air_conditioned","equipment_rental","changing_room"]'::jsonb,
    'open','06:00','close','23:00','rules',court_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Court 1","size":"Doubles","surface":"Synthetic mat","price":500,"max":4,"sports":["badminton"]},
      {"name":"Court 2","size":"Doubles","surface":"Synthetic mat","price":500,"max":4,"sports":["badminton"]},
      {"name":"Court 3","size":"Doubles","surface":"Synthetic mat","price":500,"max":4,"sports":["badminton"]},
      {"name":"Court 4","size":"Doubles","surface":"Wooden","price":600,"max":4,"sports":["badminton"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','skyline-sports-rooftop-cyber-city','name','Skyline Sports Rooftop','area','DLF Cyber City, Gurugram',
    'address','Rooftop, Tower C, DLF Cyber City Phase 2, Gurugram, Haryana 122002',
    'lat',28.4950,'lng',77.0890,'phone','+919810000104',
    'desc','A multi-sport rooftop with skyline views: football, box cricket and pickleball under one roof. After-work favourite.',
    'photos','["/images/turfs/multisport-rooftop.jpg","/images/turfs/football-night.jpg","/images/turfs/pickleball.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","shower","cafe","cctv","wifi"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Rooftop Pitch","size":"5-a-side","surface":"Artificial grass","price":1800,"max":12,"sports":["football","cricket"]},
      {"name":"Pickleball Court","size":"Doubles","surface":"Acrylic hard court","price":800,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','sohna-road-turf-park','name','Sohna Road Turf Park','area','Sector 49, Gurugram',
    'address','Near Omaxe City Centre, Sohna Road, Sector 49, Gurugram, Haryana 122018',
    'lat',28.4130,'lng',77.0430,'phone','+919810000105',
    'desc','Spacious open-air turf with separate football and cricket boxes and plenty of parking.',
    'photos','["/images/turfs/football-day.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","seating","first_aid"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Football Turf","size":"6-a-side","surface":"Artificial grass","price":1200,"max":14,"sports":["football"]},
      {"name":"Cricket Box","size":"7 vs 7","surface":"Artificial turf","price":1300,"max":14,"sports":["cricket"]}
    ]'::jsonb));

  -- ============================ DELHI ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','hauz-khas-football-turf','name','Hauz Khas Football Turf','area','Hauz Khas, South Delhi',
    'address','Behind Deer Park, Hauz Khas Village, New Delhi, Delhi 110016',
    'lat',28.5494,'lng',77.2001,'phone','+919810000106',
    'desc','Cozy 5-a-side cage turf in the heart of South Delhi with excellent lighting for late-night games.',
    'photos','["/images/turfs/football-closeup.jpg","/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["floodlights","washroom","drinking_water","equipment_rental","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[{"name":"Main Cage","size":"5-a-side","surface":"Artificial grass","price":1600,"max":12,"sports":["football"]}]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','saket-sports-box','name','Saket Sports Box','area','Saket, South Delhi',
    'address','Press Enclave Marg, near Select Citywalk, Saket, New Delhi, Delhi 110017',
    'lat',28.5245,'lng',77.2066,'phone','+919810000107',
    'desc','Versatile box that converts between football and box cricket. A short walk from Select Citywalk.',
    'photos','["/images/turfs/cricket-day.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","cafe","seating"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[{"name":"Sports Box","size":"6-a-side","surface":"Artificial grass","price":1400,"max":14,"sports":["football","cricket"]}]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','dwarka-turf-zone','name','Dwarka Turf Zone','area','Sector 12, Dwarka',
    'address','Pocket 4, near Sector 12 Metro Station, Dwarka, New Delhi, Delhi 110075',
    'lat',28.5921,'lng',77.0460,'phone','+919810000108',
    'desc','West Delhi''s largest turf with a full 7-a-side pitch and a smaller 5-a-side cage.',
    'photos','["/images/turfs/football-day.jpg","/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","shower","first_aid"]'::jsonb,
    'open','05:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Big Pitch","size":"7-a-side","surface":"Artificial grass","price":1800,"max":16,"sports":["football"]},
      {"name":"Cage","size":"5-a-side","surface":"Artificial grass","price":1200,"max":12,"sports":["football"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','rohini-champions-arena','name','Rohini Champions Arena','area','Sector 10, Rohini',
    'address','Near Rithala Metro, Sector 10, Rohini, New Delhi, Delhi 110085',
    'lat',28.7158,'lng',77.1150,'phone','+919810000109',
    'desc','Affordable community turf for cricket and football with weekend tournaments.',
    'photos','["/images/turfs/box-cricket.jpg","/images/turfs/cricket-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","seating"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[{"name":"Arena","size":"7-a-side","surface":"Artificial turf","price":1100,"max":14,"sports":["cricket","football"]}]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','lajpat-pickleball-club','name','Lajpat Pickleball Club','area','Lajpat Nagar, South Delhi',
    'address','Rooftop, Central Market, Lajpat Nagar II, New Delhi, Delhi 110024',
    'lat',28.5677,'lng',77.2433,'phone','+919810000110',
    'desc','Three cushioned pickleball courts with paddle rentals. Beginners welcome, with coaching on weekends.',
    'photos','["/images/turfs/pickleball.jpg"]'::jsonb,
    'amenities','["floodlights","washroom","drinking_water","equipment_rental","seating","cafe"]'::jsonb,
    'open','06:00','close','23:00','rules',court_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Court 1","size":"Doubles","surface":"Cushioned acrylic","price":700,"max":4,"sports":["pickleball"]},
      {"name":"Court 2","size":"Doubles","surface":"Cushioned acrylic","price":700,"max":4,"sports":["pickleball"]},
      {"name":"Court 3","size":"Doubles","surface":"Cushioned acrylic","price":700,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','rajouri-garden-hoops','name','Rajouri Garden Hoops','area','Rajouri Garden, West Delhi',
    'address','J Block Community Centre, Rajouri Garden, New Delhi, Delhi 110027',
    'lat',28.6415,'lng',77.1209,'phone','+919810000111',
    'desc','Outdoor basketball with a freshly painted full court and a half court for 3x3.',
    'photos','["/images/turfs/basketball.jpg"]'::jsonb,
    'amenities','["floodlights","washroom","drinking_water","seating"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Full Court","size":"5 vs 5","surface":"Acrylic hard court","price":1200,"max":12,"sports":["basketball"]},
      {"name":"Half Court","size":"3 vs 3","surface":"Acrylic hard court","price":700,"max":8,"sports":["basketball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','mayur-vihar-sports-hub','name','Mayur Vihar Sports Hub','area','Mayur Vihar Phase 1, East Delhi',
    'address','Pocket 2, near Mayur Vihar Metro, Phase 1, New Delhi, Delhi 110091',
    'lat',28.6040,'lng',77.2940,'phone','+919810000112',
    'desc','Indoor badminton courts and an outdoor tennis court, great for early-morning regulars.',
    'photos','["/images/turfs/badminton.jpg","/images/turfs/tennis.jpg"]'::jsonb,
    'amenities','["parking","washroom","drinking_water","changing_room","equipment_rental"]'::jsonb,
    'open','05:00','close','23:00','rules',court_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Badminton 1","size":"Doubles","surface":"Synthetic mat","price":450,"max":4,"sports":["badminton"]},
      {"name":"Badminton 2","size":"Doubles","surface":"Synthetic mat","price":450,"max":4,"sports":["badminton"]},
      {"name":"Tennis Court","size":"Doubles","surface":"Hard court","price":800,"max":4,"sports":["tennis"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','pitampura-turf-club','name','Pitampura Turf Club','area','Pitampura, North Delhi',
    'address','Near Netaji Subhash Place, Pitampura, New Delhi, Delhi 110034',
    'lat',28.6990,'lng',77.1390,'phone','+919810000113',
    'desc','Neighbourhood 5-a-side turf with regular evening pick-up games.',
    'photos','["/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["floodlights","washroom","drinking_water","parking"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[{"name":"Turf","size":"5-a-side","surface":"Artificial grass","price":1100,"max":12,"sports":["football"]}]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','vasant-kunj-tennis-and-turf','name','Vasant Kunj Tennis & Turf','area','Vasant Kunj, South Delhi',
    'address','Sector C, near Ambience Mall, Vasant Kunj, New Delhi, Delhi 110070',
    'lat',28.5200,'lng',77.1580,'phone','+919810000114',
    'desc','Two tennis courts and a 5-a-side turf surrounded by greenery.',
    'photos','["/images/turfs/tennis.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","shower","cafe"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Tennis Court 1","size":"Doubles","surface":"Hard court","price":900,"max":4,"sports":["tennis"]},
      {"name":"Tennis Court 2","size":"Doubles","surface":"Clay","price":1000,"max":4,"sports":["tennis"]},
      {"name":"Football Turf","size":"5-a-side","surface":"Artificial grass","price":1500,"max":12,"sports":["football"]}
    ]'::jsonb));

  -- ============================ NOIDA / GHAZIABAD / FARIDABAD ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','noida-goal-factory-sector-18','name','Noida Goal Factory','area','Sector 18, Noida',
    'address','Near Atta Market, Sector 18, Noida, Uttar Pradesh 201301',
    'lat',28.5700,'lng',77.3260,'phone','+919810000115',
    'desc','Two professional football pitches minutes from Sector 18 Metro, with league nights every Wednesday.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/football-closeup.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","cafe","equipment_rental","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Pitch 1","size":"5-a-side","surface":"Artificial grass","price":1300,"max":12,"sports":["football"]},
      {"name":"Pitch 2","size":"7-a-side","surface":"Artificial grass","price":2000,"max":16,"sports":["football"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','sector-62-cricket-box','name','Sector 62 Cricket Box','area','Sector 62, Noida',
    'address','Block C, Institutional Area, Sector 62, Noida, Uttar Pradesh 201309',
    'lat',28.6270,'lng',77.3650,'phone','+919810000116',
    'desc','Twin cricket boxes in Noida''s IT hub. Lunch-hour games are half the weekend price.',
    'photos','["/images/turfs/cricket-day.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental"]'::jsonb,
    'open','07:00','close','24:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Box A","size":"8 vs 8","surface":"Artificial turf","price":1200,"max":16,"sports":["cricket"]},
      {"name":"Box B","size":"8 vs 8","surface":"Artificial turf","price":1200,"max":16,"sports":["cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','greater-noida-west-arena','name','Greater Noida West Arena','area','Gaur City, Greater Noida West',
    'address','Gaur City 1, Sector 4, Greater Noida West, Uttar Pradesh 201318',
    'lat',28.6080,'lng',77.4300,'phone','+919810000117',
    'desc','Big multi-sport ground for the Noida Extension crowd: football, cricket and beach-style volleyball.',
    'photos','["/images/turfs/multisport-rooftop.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","seating","first_aid"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Main Turf","size":"7-a-side","surface":"Artificial grass","price":1000,"max":16,"sports":["football","cricket"]},
      {"name":"Volleyball Court","size":"6 vs 6","surface":"Sand","price":600,"max":12,"sports":["volleyball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','indirapuram-smashers','name','Indirapuram Smashers','area','Indirapuram, Ghaziabad',
    'address','Shakti Khand 2, Indirapuram, Ghaziabad, Uttar Pradesh 201014',
    'lat',28.6460,'lng',77.3690,'phone','+919810000118',
    'desc','Air-conditioned badminton hall plus two pickleball courts. Family-friendly and spotless.',
    'photos','["/images/turfs/badminton.jpg","/images/turfs/pickleball.jpg"]'::jsonb,
    'amenities','["parking","washroom","drinking_water","air_conditioned","equipment_rental","seating","cctv"]'::jsonb,
    'open','06:00','close','23:00','rules',court_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Badminton 1","size":"Doubles","surface":"Wooden","price":400,"max":4,"sports":["badminton"]},
      {"name":"Badminton 2","size":"Doubles","surface":"Wooden","price":400,"max":4,"sports":["badminton"]},
      {"name":"Pickleball 1","size":"Doubles","surface":"Acrylic","price":600,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','faridabad-sports-village','name','Faridabad Sports Village','area','Sector 21, Faridabad',
    'address','Near Sector 21C Market, Faridabad, Haryana 121001',
    'lat',28.4280,'lng',77.3060,'phone','+919810000119',
    'desc','A green, spacious venue with a 7-a-side football pitch and a cricket box.',
    'photos','["/images/turfs/football-day.jpg","/images/turfs/cricket-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","first_aid"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Football Pitch","size":"7-a-side","surface":"Artificial grass","price":1500,"max":16,"sports":["football"]},
      {"name":"Cricket Box","size":"7 vs 7","surface":"Artificial turf","price":1200,"max":14,"sports":["cricket"]}
    ]'::jsonb));
end $$;


-- >>> 20261030000004_seed_reviews_and_games.sql
-- =============================================================================
-- Turffet: seed sample player profiles, reviews & open games in Delhi NCR
-- =============================================================================
set search_path = public, extensions;

do $$
declare
  u1 uuid := '00000000-0000-4000-8000-000000000001';
  u2 uuid := '00000000-0000-4000-8000-000000000002';
  u3 uuid := '00000000-0000-4000-8000-000000000003';
  t record;
  v_court uuid;
  v_sport text;
  v_booking uuid;
  v_start timestamptz;
  v_end timestamptz;
  idx int := 0;
  comments text[] := array[
    'Top-notch FIFA grade grass and bright floodlights. Zero glare at night!',
    'Booked the weekday Happy Hour slot at 35% off. Super smooth QR check-in at reception.',
    'Well maintained pitch, clean washrooms and plenty of parking space.',
    'Great bounce on the turf for box cricket. Stumps and soft balls were available.',
    'Best place in the neighbourhood for after-work 5v5 games.'
  ];
begin
  -- Create 3 sample players in auth.users -> triggers handle_new_user() into profiles
  insert into auth.users (id, instance_id, aud, role, email, phone, raw_user_meta_data, created_at, updated_at)
  values
    (u1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'aarav.demo@turffet.app', '919999999999', '{"full_name":"Aarav Mehta"}'::jsonb, now(), now()),
    (u2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'kabir.demo@turffet.app', '919000000000', '{"full_name":"Kabir Verma"}'::jsonb, now(), now()),
    (u3, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'neha.demo@turffet.app',  '919811111111', '{"full_name":"Neha Kapoor"}'::jsonb, now(), now())
  on conflict (id) do nothing;

  update public.profiles set full_name = 'Aarav Mehta', skill_level = 'intermediate', preferred_sports = '{football,cricket}', onboarded = true where id = u1;
  update public.profiles set full_name = 'Kabir Verma', skill_level = 'advanced',     preferred_sports = '{football,pickleball}', onboarded = true where id = u2;
  update public.profiles set full_name = 'Neha Kapoor', skill_level = 'intermediate', preferred_sports = '{badminton,pickleball,tennis}', onboarded = true where id = u3;

  -- Seed past completed bookings + reviews across all turfs so ratings are populated
  for t in select * from public.turfs order by created_at loop
    idx := idx + 1;
    select c.id, cs.sport_id into v_court, v_sport
    from public.courts c
    join public.court_sports cs on cs.court_id = c.id
    where c.turf_id = t.id
    order by c.sort_order limit 1;

    if v_court is not null then
      v_start := date_trunc('day', now() - make_interval(days => (idx % 5) + 2)) + interval '19 hours';
      v_end   := v_start + interval '1 hour';
      v_booking := gen_random_uuid();

      if not exists (select 1 from public.bookings where court_id = v_court and starts_at = v_start) then
        insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                     starts_at, ends_at, players_count, total_price, status)
        values (
          v_booking,
          'SEED' || lpad(idx::text, 2, '0'),
          'TFT1.' || v_booking || '.SEED' || lpad(idx::text, 2, '0') || '.seed',
          case when idx % 2 = 0 then u1 else u2 end,
          t.id, v_court, v_sport, v_start, v_end, 10, 1200, 'completed'
        );

        insert into public.reviews (booking_id, turf_id, user_id, rating, comment)
        values (
          v_booking, t.id,
          case when idx % 2 = 0 then u1 else u2 end,
          case when idx % 3 = 0 then 4 else 5 end,
          comments[1 + (idx % array_length(comments, 1))]
        )
        on conflict (booking_id) do nothing;
      end if;
    end if;
  end loop;

  -- Seed 3 upcoming Open Games for "Find Players"
  -- 1) Kickoff Arena, Gurugram (Tomorrow 7 PM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'kickoff-arena-sector-29' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '19:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    if not exists (select 1 from public.bookings where court_id = t.court_id and starts_at = v_start) then
      v_booking := gen_random_uuid();
      insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                   starts_at, ends_at, players_count, total_price, status, note)
      values (v_booking, 'OPEN01', 'TFT1.' || v_booking || '.OPEN01.demo', u2, t.turf_id, t.court_id,
              'football', v_start, v_end, 7, 1400, 'confirmed', 'Friendly 5v5 game after work. Turf shoes required!');
      insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
      values (v_booking, u2, t.turf_id, 'football', v_start, v_end, 3, 'intermediate', 'Friendly 5v5 game after work. Turf shoes required!');
    end if;
  end if;

  -- 2) Hauz Khas Football Turf, South Delhi (Tomorrow 8 PM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'hauz-khas-football-turf' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '20:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    if not exists (select 1 from public.bookings where court_id = t.court_id and starts_at = v_start) then
      v_booking := gen_random_uuid();
      insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                   starts_at, ends_at, players_count, total_price, status, note)
      values (v_booking, 'OPEN02', 'TFT1.' || v_booking || '.OPEN02.demo', u1, t.turf_id, t.court_id,
              'football', v_start, v_end, 8, 1600, 'confirmed', 'Need 2 players for cage 5-a-side under floodlights.');
      insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
      values (v_booking, u1, t.turf_id, 'football', v_start, v_end, 2, 'intermediate', 'Need 2 players for cage 5-a-side under floodlights.');
    end if;
  end if;

  -- 3) Lajpat Pickleball Club, South Delhi (Tomorrow 8 AM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'lajpat-pickleball-club' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '08:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    if not exists (select 1 from public.bookings where court_id = t.court_id and starts_at = v_start) then
      v_booking := gen_random_uuid();
      insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                   starts_at, ends_at, players_count, total_price, status, note)
      values (v_booking, 'OPEN03', 'TFT1.' || v_booking || '.OPEN03.demo', u3, t.turf_id, t.court_id,
              'pickleball', v_start, v_end, 2, 700, 'confirmed', 'Morning doubles session! Extra paddles available at the court.');
      insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
      values (v_booking, u3, t.turf_id, 'pickleball', v_start, v_end, 2, 'beginner', 'Morning doubles session! Extra paddles available at the court.');
    end if;
  end if;
end $$;

-- Allow anonymous users to browse open games too (joining still requires auth)
drop policy if exists "games read" on public.open_games;
create policy "games read" on public.open_games for select using (true);

create or replace function public.list_games(
  p_lat double precision default null,
  p_lng double precision default null,
  p_sport text default null,
  p_mine boolean default false
)
returns table (
  id uuid, booking_id uuid, turf_id uuid, turf_name text, turf_area text, turf_cover text,
  sport_id text, starts_at timestamptz, ends_at timestamptz,
  spots_total int, spots_filled int, players_count int, total_price int,
  skill_level public.skill_level, note text, status public.game_status,
  host_name text, is_host boolean, my_status public.join_status, distance_km double precision
)
language sql stable security definer set search_path = public, extensions as $$
  select g.id, g.booking_id, t.id, t.name, t.area, t.cover_image,
         g.sport_id, g.starts_at, g.ends_at,
         g.spots_total,
         (select count(*)::int from join_requests jr where jr.game_id = g.id and jr.status = 'accepted'),
         b.players_count, b.total_price,
         g.skill_level, g.note, g.status,
         coalesce(nullif(split_part(hp.full_name, ' ', 1), ''), 'Player'),
         coalesce(g.host_id = auth.uid(), false),
         mj.status,
         case when p_lat is null or p_lng is null then null
              else round((st_distance(t.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0)::numeric, 1)::double precision
         end
  from open_games g
  join turfs t on t.id = g.turf_id
  join bookings b on b.id = g.booking_id
  join profiles hp on hp.id = g.host_id
  left join join_requests mj on mj.game_id = g.id and mj.user_id = auth.uid()
  where g.ends_at > now()
    and (p_sport is null or g.sport_id = p_sport)
    and (
      (p_mine and auth.uid() is not null and (g.host_id = auth.uid() or mj.status in ('pending', 'accepted')))
      or (not p_mine and g.status = 'open' and g.starts_at > now())
    )
  order by g.starts_at;
$$;

create or replace function public.get_game_detail(p_game_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_g open_games;
  v_is_host boolean;
  v_my join_requests;
  v_host profiles;
  v_result jsonb;
begin
  select * into v_g from open_games where id = p_game_id;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;
  v_is_host := coalesce(v_g.host_id = v_uid, false);
  if v_uid is not null then
    select * into v_my from join_requests where game_id = p_game_id and user_id = v_uid;
  end if;
  select * into v_host from profiles where id = v_g.host_id;

  select jsonb_build_object(
    'id', v_g.id,
    'status', v_g.status,
    'sport_id', v_g.sport_id,
    'starts_at', v_g.starts_at,
    'ends_at', v_g.ends_at,
    'spots_total', v_g.spots_total,
    'skill_level', v_g.skill_level,
    'note', v_g.note,
    'is_host', v_is_host,
    'my_request', case when v_my.id is null then null
                       else jsonb_build_object('id', v_my.id, 'status', v_my.status) end,
    'host', jsonb_build_object(
      'name', coalesce(nullif(v_host.full_name, ''), 'Player'),
      'skill_level', v_host.skill_level,
      'phone', case when v_my.status = 'accepted' then v_host.phone end
    ),
    'booking', (
      select jsonb_build_object('players_count', b.players_count, 'total_price', b.total_price,
                                'court_name', c.name, 'size_label', c.size_label)
      from bookings b join courts c on c.id = b.court_id where b.id = v_g.booking_id
    ),
    'turf', (
      select jsonb_build_object('id', t.id, 'slug', t.slug, 'name', t.name, 'area', t.area,
                                'address', t.address, 'lat', t.lat, 'lng', t.lng, 'cover_image', t.cover_image)
      from turfs t where t.id = v_g.turf_id
    ),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', coalesce(nullif(split_part(p.full_name, ' ', 1), ''), 'Player'),
               'skill_level', p.skill_level) order by jr.responded_at)
      from join_requests jr join profiles p on p.id = jr.user_id
      where jr.game_id = p_game_id and jr.status = 'accepted'
    ), '[]'::jsonb),
    'requests', case when v_is_host then coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', jr.id, 'status', jr.status, 'message', jr.message, 'created_at', jr.created_at,
               'name', coalesce(nullif(p.full_name, ''), 'Player'),
               'skill_level', p.skill_level,
               'phone', case when jr.status = 'accepted' then p.phone end)
             order by jr.created_at)
      from join_requests jr join profiles p on p.id = jr.user_id
      where jr.game_id = p_game_id and jr.status <> 'withdrawn'
    ), '[]'::jsonb) else null end
  ) into v_result;

  return v_result;
end $$;


-- >>> 20261030000005_real_ncr_turfs.sql
-- =============================================================================
-- Turffet: Replace sample turfs with 19 REAL Delhi NCR sports turfs & arenas
-- =============================================================================
set search_path = public, extensions;

-- Clear previous seed bookings/turfs so we can insert real Delhi NCR venues cleanly
truncate table public.join_requests, public.open_games, public.reviews, public.bookings,
               public.favourites, public.pricing_rules, public.court_sports, public.courts,
               public.operating_hours, public.turf_amenities, public.turf_photos, public.turfs cascade;

create or replace function pg_temp.seed_turf(d jsonb) returns void
language plpgsql as $$
declare
  v_turf uuid;
  v_court uuid;
  c jsonb;
  r jsonb;
  s text;
  i int := 0;
  dow int;
begin
  insert into public.turfs (slug, name, description, area, address, lat, lng, phone, whatsapp,
                            cover_image, rules, slot_minutes)
  values (d->>'slug', d->>'name', d->>'desc', d->>'area', d->>'address',
          (d->>'lat')::float8, (d->>'lng')::float8, d->>'phone', d->>'phone',
          d->'photos'->>0,
          array(select jsonb_array_elements_text(coalesce(d->'rules', '[]'::jsonb))),
          coalesce((d->>'slot')::int, 60))
  returning id into v_turf;

  for s in select jsonb_array_elements_text(d->'photos') loop
    insert into public.turf_photos (turf_id, url, sort_order) values (v_turf, s, i);
    i := i + 1;
  end loop;

  for s in select jsonb_array_elements_text(d->'amenities') loop
    insert into public.turf_amenities (turf_id, amenity_id) values (v_turf, s);
  end loop;

  for dow in 0..6 loop
    insert into public.operating_hours (turf_id, day_of_week, open_time, close_time)
    values (v_turf, dow,
            case when dow in (0, 6) then coalesce(d->>'weekend_open', d->>'open') else d->>'open' end::time,
            (d->>'close')::time);
  end loop;

  i := 0;
  for c in select * from jsonb_array_elements(d->'courts') loop
    insert into public.courts (turf_id, name, size_label, surface, base_price, max_players, sort_order)
    values (v_turf, c->>'name', c->>'size', c->>'surface', (c->>'price')::int, (c->>'max')::int, i)
    returning id into v_court;
    i := i + 1;

    for s in select jsonb_array_elements_text(c->'sports') loop
      insert into public.court_sports (court_id, sport_id) values (v_court, s);
    end loop;

    for r in select * from jsonb_array_elements(coalesce(d->'pricing', '[]'::jsonb)) loop
      insert into public.pricing_rules (turf_id, court_id, days_of_week, start_time, end_time, price, label, is_offpeak)
      values (v_turf, v_court,
              array(select jsonb_array_elements_text(r->'days')::int),
              (r->>'start')::time, (r->>'end')::time,
              (round((c->>'price')::numeric * (100 - (r->>'pct')::int) / 100 / 10) * 10)::int,
              r->>'label',
              (r->>'pct')::int > 0);
    end loop;
  end loop;
end $$;

do $$
declare
  football_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"06:00","end":"09:00","pct":35,"label":"Happy Hour"},
    {"days":[1,2,3,4,5],"start":"12:00","end":"16:00","pct":30,"label":"Afternoon Deal"},
    {"days":[0,6],"start":"18:00","end":"23:00","pct":-15,"label":"Weekend Prime"}
  ]';
  cricket_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"07:00","end":"10:00","pct":30,"label":"Early Bird"},
    {"days":[1,2,3,4,5],"start":"13:00","end":"17:00","pct":35,"label":"Afternoon Deal"},
    {"days":[0,6],"start":"17:00","end":"23:00","pct":-10,"label":"Weekend Prime"}
  ]';
  racquet_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"10:00","end":"16:00","pct":40,"label":"Midday Deal"},
    {"days":[0,1,2,3,4,5,6],"start":"21:00","end":"23:00","pct":20,"label":"Late Night"}
  ]';
  mixed_pricing jsonb := '[
    {"days":[1,2,3,4,5],"start":"06:00","end":"09:00","pct":30,"label":"Happy Hour"},
    {"days":[1,2,3,4,5],"start":"11:00","end":"16:00","pct":35,"label":"Afternoon Deal"}
  ]';
  std_rules jsonb := '["Turf/non-marking shoes only, no metal studs","Please arrive 10 minutes before your slot","No smoking, alcohol or food on the playing area","Show your Turffet QR at the reception"]';
  court_rules jsonb := '["Non-marking shoes are mandatory","Max 4 players per court","Please arrive 10 minutes before your slot","Show your Turffet QR at the reception"]';
begin
  -- ============================ GURUGRAM ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','spada-arena-sushant-lok-gurugram','name','SPADA Arena | Sushant Lok','area','Sushant Lok Phase 1, Sector 43, Gurugram',
    'address','Excelsior American School, Block C2, Sushant Lok Phase I, Sector 43, Golf Course Road, Gurugram, Haryana 122002',
    'lat',28.4575,'lng',77.0825,'phone','+919167405982',
    'desc','Flagship FIFA-quality artificial turf facility on Golf Course Road with pro-grade LED floodlights, 5v5 and 7v7 football setups, and box cricket.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/football-closeup.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","cafe","equipment_rental","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Turf A (5v5)","size":"5-a-side","surface":"FIFA Artificial Grass","price":1500,"max":12,"sports":["football","cricket"]},
      {"name":"Turf B (7v7)","size":"7-a-side","surface":"FIFA Artificial Grass","price":2400,"max":16,"sports":["football","cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','gallant-play-arena-south-city-1','name','Gallant Play Arena | South City 1','area','Sector 41, South City 1, Gurugram',
    'address','K.R. Mangalam World School, E-Block, South City I, Sector 41 (Near Huda City Centre), Gurugram, Haryana 122001',
    'lat',28.4562,'lng',77.0628,'phone','+919958677005',
    'desc','Gallant Sports multi-sport arena featuring shock-pad artificial football turf, box cricket enclosure, synthetic basketball court and tennis.',
    'photos','["/images/turfs/multisport-rooftop.jpg","/images/turfs/football-day.jpg","/images/turfs/basketball.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","first_aid","seating","cctv"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Main Football & Cricket Turf","size":"6-a-side","surface":"FIFA shock-pad grass","price":1600,"max":14,"sports":["football","cricket"]},
      {"name":"Basketball Court","size":"5 vs 5","surface":"Synthetic acrylic","price":1000,"max":12,"sports":["basketball"]},
      {"name":"Tennis Court","size":"Doubles","surface":"Synthetic hard court","price":800,"max":4,"sports":["tennis"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','sportslane-arena-sector-58-gurugram','name','SportsLane Arena | Sector 58','area','Sector 58, Golf Course Ext. Road, Gurugram',
    'address','Behind Ireo Grand Arch, Ghatta Kanarpur, Sector 58 (Near Sector 55-56 Metro), Gurugram, Haryana 122011',
    'lat',28.4148,'lng',77.1115,'phone','+919818070700',
    'desc','Dedicated racquet sports facility featuring indoor air-conditioned BWF-approved wooden badminton courts and outdoor cool-top pickleball & tennis courts.',
    'photos','["/images/turfs/badminton.jpg","/images/turfs/pickleball.jpg","/images/turfs/tennis.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","air_conditioned","equipment_rental","cafe"]'::jsonb,
    'open','06:00','close','23:00','rules',court_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Badminton Court 1","size":"Doubles","surface":"BWF Wooden + Mat","price":550,"max":4,"sports":["badminton"]},
      {"name":"Badminton Court 2","size":"Doubles","surface":"BWF Wooden + Mat","price":550,"max":4,"sports":["badminton"]},
      {"name":"Pickleball Court 1","size":"Doubles","surface":"Cool-top Acrylic","price":750,"max":4,"sports":["pickleball"]},
      {"name":"Pickleball Court 2","size":"Doubles","surface":"Cool-top Acrylic","price":750,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','playall-sports-arena-sector-62-gurugram','name','PlayAll Sports Arena | Sector 62','area','Sector 62, Golf Course Ext., Gurugram',
    'address','CRPF Road, near HBR Chowk, Ullahawas, Sector 62, Gurugram, Haryana 122102',
    'lat',28.4089,'lng',77.0912,'phone','+919310096119',
    'desc','One of Gurugram’s busiest box cricket and 6-a-side football venues with high-roof netting, uniform bounce, and late-night floodlit slots.',
    'photos','["/images/turfs/box-cricket.jpg","/images/turfs/cricket-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Box Arena 1","size":"8 vs 8","surface":"Artificial turf","price":1400,"max":16,"sports":["cricket","football"]},
      {"name":"Box Arena 2","size":"7 vs 7","surface":"Artificial turf","price":1200,"max":14,"sports":["cricket","football"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','claygrounds-dlf-phase-3-gurugram','name','ClayGrounds | DLF Phase 3','area','DLF Phase 3 (Near Cyber City), Gurugram',
    'address','Rabindranath World School, W-10 Road, U Block, DLF Phase 3, Sector 24, Gurugram, Haryana 122002',
    'lat',28.4918,'lng',77.0942,'phone','+917827860783',
    'desc','Minutes from DLF Cyber City and Moulsari Avenue Metro. Popular for after-office 5v5 football and corporate box cricket games.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","first_aid"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"5v5 Turf","size":"5-a-side","surface":"Artificial grass","price":1500,"max":12,"sports":["football","cricket"]}
    ]'::jsonb));

  -- ============================ SOUTH & CENTRAL DELHI ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','siri-fort-sports-complex-hauz-khas','name','Siri Fort Sports Complex (DDA)','area','Siri Fort / Hauz Khas, South Delhi',
    'address','August Kranti Marg, near Asian Games Village, Siri Fort, New Delhi, Delhi 110049',
    'lat',28.5535,'lng',77.2165,'phone','+911126496657',
    'desc','Premier DDA multi-sport complex in South Delhi with floodlit synthetic tennis courts, indoor badminton halls, basketball courts and mini-football turf.',
    'photos','["/images/turfs/tennis.jpg","/images/turfs/badminton.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","shower","cafe","first_aid","seating"]'::jsonb,
    'open','06:00','close','22:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Mini Football Turf","size":"5-a-side","surface":"Synthetic turf","price":1400,"max":12,"sports":["football"]},
      {"name":"Synthetic Tennis Court","size":"Doubles","surface":"Acrylic hard court","price":700,"max":4,"sports":["tennis"]},
      {"name":"Indoor Badminton Court","size":"Doubles","surface":"Wooden","price":500,"max":4,"sports":["badminton"]},
      {"name":"Basketball Court","size":"5 vs 5","surface":"Outdoor synthetic","price":900,"max":12,"sports":["basketball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','claygrounds-deep-vk-vasant-kunj','name','ClayGrounds | Vasant Kunj (Deep VK)','area','Sector D, Vasant Kunj, South Delhi',
    'address','Deep Public School, Pocket 2, Sector D, Vasant Kunj, New Delhi, Delhi 110070',
    'lat',28.5246,'lng',77.1558,'phone','+917827860783',
    'desc','South Delhi’s go-to 5v5 and 7v7 turf arena in Vasant Kunj with fresh artificial grass and bright night floodlights.',
    'photos','["/images/turfs/football-closeup.jpg","/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Turf 1 (5v5)","size":"5-a-side","surface":"Artificial grass","price":1500,"max":12,"sports":["football","cricket"]},
      {"name":"Turf 2 (7v7)","size":"7-a-side","surface":"Artificial grass","price":2200,"max":16,"sports":["football","cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','claygrounds-defence-colony-lajpat','name','ClayGrounds | Defence Colony','area','Defence Colony / Lajpat Nagar, South Delhi',
    'address','Chetna Marg, near Defence Colony Club & Lajpat Nagar Metro, New Delhi, Delhi 110024',
    'lat',28.5733,'lng',77.2325,'phone','+917827509127',
    'desc','Central-South Delhi cage football turf and community pickleball courts with paddle rentals and weekend mixers.',
    'photos','["/images/turfs/pickleball.jpg","/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","cafe"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',racquet_pricing,
    'courts','[
      {"name":"Football Cage","size":"5-a-side","surface":"Artificial grass","price":1600,"max":12,"sports":["football"]},
      {"name":"Pickleball Court 1","size":"Doubles","surface":"Acrylic hard court","price":800,"max":4,"sports":["pickleball"]},
      {"name":"Pickleball Court 2","size":"Doubles","surface":"Acrylic hard court","price":800,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','claygrounds-chhatarpur-south-delhi','name','ClayGrounds x District Play | Chhatarpur','area','Chhatarpur / Saket, South Delhi',
    'address','Satbari, SSN Marg (10 mins from Chhatarpur Metro), South Delhi, New Delhi, Delhi 110074',
    'lat',28.4902,'lng',77.1812,'phone','+917827860783',
    'desc','Open-air multi-sport turf surrounded by greenery on SSN Marg. Ideal for 6v6 football and high-ceiling box cricket.',
    'photos','["/images/turfs/cricket-day.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","seating","first_aid"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Main Arena","size":"6-a-side","surface":"Artificial grass","price":1400,"max":14,"sports":["football","cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','gallant-play-arena-greater-kailash','name','Gallant Play Arena | Greater Kailash II','area','Greater Kailash II (GK-2), South Delhi',
    'address','K.R. Mangalam World School, S-Block, Greater Kailash II, New Delhi, Delhi 110048',
    'lat',28.5328,'lng',77.2435,'phone','+919958677005',
    'desc','Premium South Delhi venue by Gallant Sports offering FIFA-grade turf for 5v5 football, box cricket, and synthetic outdoor basketball.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/basketball.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","first_aid","cctv"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"GK Turf","size":"5-a-side","surface":"FIFA Artificial Grass","price":1700,"max":12,"sports":["football","cricket"]},
      {"name":"Basketball Court","size":"5 vs 5","surface":"Acrylic hard court","price":1100,"max":12,"sports":["basketball"]}
    ]'::jsonb));

  -- ============================ WEST & NORTH DELHI ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','play-360-football-and-cricket-dwarka','name','Play 360 Football & Cricket | Dwarka','area','Sector 12 / Goyla, Dwarka',
    'address','Near Sector 12 Metro & Goyla Dairy Road, Dwarka, New Delhi, Delhi 110075',
    'lat',28.5918,'lng',77.0412,'phone','+919958677005',
    'desc','West Delhi’s premier Dual-Sport turf with floodlights, dugout seating lounge, shower rooms and café.',
    'photos','["/images/turfs/football-day.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","shower","cafe","seating"]'::jsonb,
    'open','05:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"7v7 Championship Pitch","size":"7-a-side","surface":"Artificial grass","price":1800,"max":16,"sports":["football","cricket"]},
      {"name":"5v5 Cage","size":"5-a-side","surface":"Artificial grass","price":1200,"max":12,"sports":["football","cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','drive-or-kick-arena-dwarka-sector-19','name','Drive Or Kick Arena | Dwarka Sector 19','area','Sector 19B, Dwarka',
    'address','OPG World School Campus, Sector 19B, Dwarka, New Delhi, Delhi 110075',
    'lat',28.5784,'lng',77.0492,'phone','+919811509127',
    'desc','Well-maintained multi-sport turf in Sector 19 Dwarka hosting regular evening box cricket leagues and weekend football pickup games.',
    'photos','["/images/turfs/cricket-day.jpg","/images/turfs/football-night.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Main Turf","size":"6-a-side","surface":"Artificial turf","price":1300,"max":14,"sports":["cricket","football"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','gallant-play-arena-vikaspuri-west-delhi','name','Gallant Play Arena | Vikaspuri','area','Vikaspuri / Rajouri Garden, West Delhi',
    'address','K.R. Mangalam World School, H-Block, Vikaspuri, New Delhi, Delhi 110018',
    'lat',28.6388,'lng',77.0736,'phone','+919958677005',
    'desc','Full multi-sport arena serving West Delhi (Vikaspuri, Janakpuri & Rajouri Garden) with football turf, basketball and badminton.',
    'photos','["/images/turfs/basketball.jpg","/images/turfs/football-night.jpg","/images/turfs/badminton.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","first_aid","cctv"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Football & Cricket Turf","size":"6-a-side","surface":"FIFA Artificial Grass","price":1300,"max":14,"sports":["football","cricket"]},
      {"name":"Basketball Court","size":"5 vs 5","surface":"Acrylic hard court","price":900,"max":12,"sports":["basketball"]},
      {"name":"Badminton Court","size":"Doubles","surface":"Synthetic mat","price":450,"max":4,"sports":["badminton"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','playall-arena-rohini-sector-13','name','PlayAll Arena | Rohini Sector 13','area','Sector 13, Rohini, North Delhi',
    'address','Maharaja Aggrasain Public School Campus, Sector 13 (Near Rohini West Metro), New Delhi, Delhi 110085',
    'lat',28.7192,'lng',77.1265,'phone','+919310096119',
    'desc','North Delhi PlayAll centre featuring a high-netted box cricket & football turf alongside indoor badminton courts.',
    'photos','["/images/turfs/box-cricket.jpg","/images/turfs/badminton.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Turf Arena","size":"7-a-side","surface":"Artificial turf","price":1200,"max":14,"sports":["cricket","football"]},
      {"name":"Badminton Court 1","size":"Doubles","surface":"Synthetic mat","price":450,"max":4,"sports":["badminton"]}
    ]'::jsonb));

  -- ============================ NOIDA, INDIRAPURAM & FARIDABAD ============================
  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','arena-44-the-box-zone-noida-sector-44','name','Arena 44 (The Box Zone) | Sector 44','area','Sector 44 (Near Sector 18), Noida',
    'address','Mahamaya Northern United Sports Arena, Block B, Sector 44 (5 mins from Botanical Garden Metro), Noida, Uttar Pradesh 201301',
    'lat',28.5562,'lng',77.3398,'phone','+919310096119',
    'desc','Premium Noida multi-sport complex offering dedicated Pickleball courts, Box Cricket, Football and Badminton.',
    'photos','["/images/turfs/pickleball.jpg","/images/turfs/football-night.jpg","/images/turfs/box-cricket.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","cafe","equipment_rental","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"Main Turf (Football & Cricket)","size":"6-a-side","surface":"Artificial grass","price":1400,"max":14,"sports":["football","cricket"]},
      {"name":"Pickleball Court 1","size":"Doubles","surface":"Acrylic hard court","price":700,"max":4,"sports":["pickleball"]},
      {"name":"Pickleball Court 2","size":"Doubles","surface":"Acrylic hard court","price":700,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','claygrounds-ims-noida-sector-62','name','ClayGrounds | Noida Sector 62','area','Sector 62, Noida',
    'address','IMS Law College Campus, A-8B, Block A, Industrial Area, Sector 62, Noida, Uttar Pradesh 201309',
    'lat',28.6219,'lng',77.3658,'phone','+917827860783',
    'desc','Right inside Noida Sector 62’s tech hub. Popular for weekday lunch-hour deals and evening corporate 6v6 football & box cricket.',
    'photos','["/images/turfs/football-night.jpg","/images/turfs/cricket-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","first_aid"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"IMS Turf","size":"6-a-side","surface":"Artificial grass","price":1300,"max":14,"sports":["football","cricket"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','playall-sports-complex-noida-sector-73','name','PlayAll Sports Complex | Sector 73','area','Sector 73, Noida',
    'address','Near Noida Pet Clinic, Sarfabad, Sector 73 (Near Sector 51 Metro), Noida, Uttar Pradesh 201307',
    'lat',28.5845,'lng',77.3862,'phone','+919310096119',
    'desc','Flagship PlayAll Noida facility with twin box-cricket/football turfs, BWF indoor badminton courts, and outdoor pickleball.',
    'photos','["/images/turfs/multisport-rooftop.jpg","/images/turfs/badminton.jpg","/images/turfs/pickleball.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","equipment_rental","seating","cctv"]'::jsonb,
    'open','06:00','close','24:00','rules',std_rules,'pricing',cricket_pricing,
    'courts','[
      {"name":"Box Turf 1","size":"7 vs 7","surface":"Artificial turf","price":1200,"max":14,"sports":["cricket","football"]},
      {"name":"Badminton Court 1","size":"Doubles","surface":"Synthetic mat","price":450,"max":4,"sports":["badminton"]},
      {"name":"Pickleball Court","size":"Doubles","surface":"Acrylic","price":650,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','play-maximus-indirapuram-ghaziabad','name','Play Maximus | Indirapuram','area','Ahinsa Khand 1, Indirapuram, Ghaziabad',
    'address','Presidium School, A-16, Near Indirapuram Habitat Centre, Ahinsa Khand 1, Indirapuram, Ghaziabad, Uttar Pradesh 201014',
    'lat',28.6412,'lng',77.3728,'phone','+919810844880',
    'desc','Indirapuram’s largest sports arena right next to Habitat Centre, featuring 7v7 football, 7v7 box cricket and pickleball.',
    'photos','["/images/turfs/football-day.jpg","/images/turfs/box-cricket.jpg","/images/turfs/pickleball.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","drinking_water","equipment_rental","seating","first_aid"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',mixed_pricing,
    'courts','[
      {"name":"7v7 Arena","size":"7-a-side","surface":"Artificial grass","price":1400,"max":16,"sports":["football","cricket"]},
      {"name":"Pickleball Court","size":"Doubles","surface":"Acrylic hard court","price":600,"max":4,"sports":["pickleball"]}
    ]'::jsonb));

  perform pg_temp.seed_turf(jsonb_build_object(
    'slug','playall-arena-faridabad-sector-86','name','PlayAll Arena | Faridabad Sector 86','area','Sector 86, Greater Faridabad',
    'address','Near Omaxe Heights, Sector 86, Greater Faridabad, Haryana 121002',
    'lat',28.4095,'lng',77.3452,'phone','+919310096119',
    'desc','Spacious PlayAll facility in Greater Faridabad for 6v6 football and box cricket with floodlights and equipment rental.',
    'photos','["/images/turfs/cricket-day.jpg","/images/turfs/football-day.jpg"]'::jsonb,
    'amenities','["parking","floodlights","washroom","changing_room","drinking_water","first_aid"]'::jsonb,
    'open','06:00','close','23:00','rules',std_rules,'pricing',football_pricing,
    'courts','[
      {"name":"Main Turf","size":"6-a-side","surface":"Artificial grass","price":1200,"max":14,"sports":["cricket","football"]}
    ]'::jsonb));
end $$;

-- Re-seed reviews and 3 open games on the real Delhi NCR venues
do $$
declare
  u1 uuid := '00000000-0000-4000-8000-000000000001';
  u2 uuid := '00000000-0000-4000-8000-000000000002';
  u3 uuid := '00000000-0000-4000-8000-000000000003';
  t record;
  v_court uuid;
  v_sport text;
  v_booking uuid;
  v_start timestamptz;
  v_end timestamptz;
  idx int := 0;
  comments text[] := array[
    'Top-notch FIFA grade grass and bright floodlights. Zero glare at night!',
    'Booked the weekday Happy Hour slot at 35% off. Super smooth QR check-in at reception.',
    'Well maintained pitch, clean washrooms and plenty of parking space.',
    'Great bounce on the turf for box cricket. Stumps and soft balls were available.',
    'Best place in the neighbourhood for after-work 5v5 games.'
  ];
begin
  for t in select * from public.turfs order by created_at loop
    idx := idx + 1;
    select c.id, cs.sport_id into v_court, v_sport
    from public.courts c
    join public.court_sports cs on cs.court_id = c.id
    where c.turf_id = t.id
    order by c.sort_order limit 1;

    if v_court is not null then
      v_start := date_trunc('day', now() - make_interval(days => (idx % 5) + 2)) + interval '19 hours';
      v_end   := v_start + interval '1 hour';
      v_booking := gen_random_uuid();

      insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                   starts_at, ends_at, players_count, total_price, status)
      values (
        v_booking,
        'SEED' || lpad(idx::text, 2, '0'),
        'TFT1.' || v_booking || '.SEED' || lpad(idx::text, 2, '0') || '.seed',
        case when idx % 2 = 0 then u1 else u2 end,
        t.id, v_court, v_sport, v_start, v_end, 10, 1200, 'completed'
      );

      insert into public.reviews (booking_id, turf_id, user_id, rating, comment)
      values (
        v_booking, t.id,
        case when idx % 2 = 0 then u1 else u2 end,
        case when idx % 3 = 0 then 4 else 5 end,
        comments[1 + (idx % array_length(comments, 1))]
      );
    end if;
  end loop;

  -- 1) SPADA Arena | Sushant Lok, Gurugram (Tomorrow 7 PM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'spada-arena-sushant-lok-gurugram' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '19:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    v_booking := gen_random_uuid();
    insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                 starts_at, ends_at, players_count, total_price, status, note)
    values (v_booking, 'OPEN01', 'TFT1.' || v_booking || '.OPEN01.demo', u2, t.turf_id, t.court_id,
            'football', v_start, v_end, 7, 1500, 'confirmed', 'Friendly 5v5 game after work at SPADA Sushant Lok. Turf shoes required!');
    insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
    values (v_booking, u2, t.turf_id, 'football', v_start, v_end, 3, 'intermediate', 'Friendly 5v5 game after work at SPADA Sushant Lok. Turf shoes required!');
  end if;

  -- 2) ClayGrounds | Vasant Kunj (Deep VK), South Delhi (Tomorrow 8 PM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'claygrounds-deep-vk-vasant-kunj' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '20:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    v_booking := gen_random_uuid();
    insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                 starts_at, ends_at, players_count, total_price, status, note)
    values (v_booking, 'OPEN02', 'TFT1.' || v_booking || '.OPEN02.demo', u1, t.turf_id, t.court_id,
            'football', v_start, v_end, 8, 1500, 'confirmed', 'Need 2 players for 5-a-side at ClayGrounds Vasant Kunj.');
    insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
    values (v_booking, u1, t.turf_id, 'football', v_start, v_end, 2, 'intermediate', 'Need 2 players for 5-a-side at ClayGrounds Vasant Kunj.');
  end if;

  -- 3) Arena 44 (The Box Zone) | Noida Sector 44 (Tomorrow 8 AM IST)
  select tf.id as turf_id, c.id as court_id into t
  from public.turfs tf join public.courts c on c.turf_id = tf.id
  where tf.slug = 'arena-44-the-box-zone-noida-sector-44' and c.name like 'Pickleball%' order by c.sort_order limit 1;

  if t.turf_id is not null then
    v_start := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '08:00') at time zone 'Asia/Kolkata';
    v_end   := v_start + interval '1 hour';
    v_booking := gen_random_uuid();
    insert into public.bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                                 starts_at, ends_at, players_count, total_price, status, note)
    values (v_booking, 'OPEN03', 'TFT1.' || v_booking || '.OPEN03.demo', u3, t.turf_id, t.court_id,
            'pickleball', v_start, v_end, 2, 700, 'confirmed', 'Morning pickleball doubles at Arena 44! Extra paddles available.');
    insert into public.open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at, spots_total, skill_level, note)
    values (v_booking, u3, t.turf_id, 'pickleball', v_start, v_end, 2, 'beginner', 'Morning pickleball doubles at Arena 44! Extra paddles available.');
  end if;
end $$;


-- >>> 20261031000006_owner_portal.sql
-- =============================================================================
-- Turffet: Owner portal
--   * owners (profiles.is_owner) can list & manage their own turfs
--   * per-sport player limits on courts
--   * % based deals (happy hour / peak surcharge)
--   * owner bookings, QR check-in, no-shows, walk-in / blocked slots
--   * photo storage bucket
-- =============================================================================
set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Schema changes
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_owner boolean not null default false,
  add column if not exists business_name text,
  add column if not exists business_phone text;

grant update (business_name, business_phone) on public.profiles to authenticated;

alter table public.turfs
  add column if not exists owner_id uuid references public.profiles(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();
create index if not exists turfs_owner_idx on public.turfs (owner_id);

-- max players for a specific sport on a court (null = court capacity)
alter table public.court_sports
  add column if not exists max_players int check (max_players is null or max_players > 0);

-- deals can be a fixed price OR a % adjustment (positive = discount, negative = surcharge)
alter table public.pricing_rules alter column price drop not null;
alter table public.pricing_rules
  add column if not exists discount_pct int check (discount_pct is null or discount_pct between -90 and 90);
do $$ begin
  alter table public.pricing_rules add constraint pricing_rules_value_chk
    check (price is not null or discount_pct is not null);
exception when duplicate_object then null;
end $$;

-- where a booking came from
alter table public.bookings
  add column if not exists source text not null default 'app'
    check (source in ('app', 'walk_in', 'blocked'));

-- -----------------------------------------------------------------------------
-- RLS: owners can see their own (possibly hidden) turfs & courts
-- -----------------------------------------------------------------------------
drop policy if exists "owner read own turfs" on public.turfs;
create policy "owner read own turfs" on public.turfs for select to authenticated
  using (owner_id = auth.uid());

drop policy if exists "owner read own courts" on public.courts;
create policy "owner read own courts" on public.courts for select to authenticated
  using (exists (select 1 from public.turfs t where t.id = turf_id and t.owner_id = auth.uid()));

-- -----------------------------------------------------------------------------
-- Storage bucket for turf photos (public read, owners upload into <uid>/...)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('turf-photos', 'turf-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true;

do $$ begin
  drop policy if exists "turf photos upload own folder" on storage.objects;
  create policy "turf photos upload own folder" on storage.objects for insert to authenticated
    with check (bucket_id = 'turf-photos' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists "turf photos delete own" on storage.objects;
  create policy "turf photos delete own" on storage.objects for delete to authenticated
    using (bucket_id = 'turf-photos' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists "turf photos read" on storage.objects;
  create policy "turf photos read" on storage.objects for select
    using (bucket_id = 'turf-photos');
exception when others then raise notice 'storage policies: %', sqlerrm;
end $$;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function public.rule_price(p_base int, p_price int, p_pct int)
returns int language sql immutable as $$
  select coalesce(p_price, (round(p_base * (100 - coalesce(p_pct, 0)) / 100.0 / 10) * 10)::int);
$$;

create or replace function public.slugify(p text)
returns text language sql immutable as $$
  select trim(both '-' from lower(regexp_replace(coalesce(p, ''), '[^a-zA-Z0-9]+', '-', 'g')));
$$;

create or replace function public.gen_booking_code()
returns text language plpgsql volatile set search_path = public as $$
declare v text;
begin
  loop
    v := '';
    for i in 1 .. 6 loop
      v := v || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from bookings where code = v);
  end loop;
  return v;
end $$;

create or replace function public.sign_booking(p_id uuid, p_code text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select 'TFT1.' || p_id || '.' || p_code || '.' ||
         substr(encode(hmac(p_id::text || '.' || p_code,
                            (select value from private.app_secrets where name = 'qr_signing_key'),
                            'sha256'), 'hex'), 1, 24);
$$;
revoke execute on function public.sign_booking(uuid, text) from public, anon, authenticated;

create or replace function public.is_turf_owner(p_turf uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from turfs where id = p_turf and owner_id = auth.uid());
$$;

-- -----------------------------------------------------------------------------
-- Pricing now supports % rules
-- -----------------------------------------------------------------------------
create or replace function public.slot_price(p_court_id uuid, p_start timestamptz)
returns table (price int, label text, is_offpeak boolean)
language sql stable set search_path = public as $$
  select coalesce(rule_price(c.base_price, r.price, r.discount_pct), c.base_price), r.label, coalesce(r.is_offpeak, false)
  from courts c
  cross join lateral (select (p_start at time zone 'Asia/Kolkata') as ts) lt
  left join lateral (
    select pr.price, pr.discount_pct, pr.label, pr.is_offpeak
    from pricing_rules pr
    where pr.turf_id = c.turf_id
      and (pr.court_id is null or pr.court_id = c.id)
      and extract(dow from lt.ts)::int = any (pr.days_of_week)
      and lt.ts::time >= pr.start_time
      and lt.ts::time < pr.end_time
    order by (pr.court_id is not null) desc, rule_price(c.base_price, pr.price, pr.discount_pct) asc
    limit 1
  ) r on true
  where c.id = p_court_id;
$$;

create or replace function public.nearby_turfs(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_km double precision default 60,
  p_sport text default null,
  p_max_price int default null,
  p_search text default null,
  p_amenities text[] default null,
  p_offpeak_only boolean default false
)
returns table (
  id uuid, slug text, name text, area text, address text,
  lat double precision, lng double precision, cover_image text,
  rating_avg numeric, rating_count int, distance_km double precision,
  min_price int, offpeak_price int, sports text[], amenities text[],
  opens_at time, closes_at time
)
language sql stable security invoker set search_path = public, extensions as $$
  with t as (
    select tf.*,
      case when p_lat is null or p_lng is null then null
           else st_distance(tf.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0
      end as dist
    from turfs tf
    where tf.is_active
      and exists (select 1 from courts c where c.turf_id = tf.id and c.is_active)
  ),
  offp as (
    select pr.turf_id, min(rule_price(c.base_price, pr.price, pr.discount_pct)) as price
    from pricing_rules pr
    join courts c on c.turf_id = pr.turf_id and c.is_active and (pr.court_id is null or pr.court_id = c.id)
    where pr.is_offpeak
    group by pr.turf_id
  )
  select
    t.id, t.slug, t.name, t.area, t.address, t.lat, t.lng, t.cover_image,
    t.rating_avg, t.rating_count,
    round(t.dist::numeric, 1)::double precision,
    (select min(c.base_price) from courts c where c.turf_id = t.id and c.is_active),
    o.price,
    array(select distinct cs.sport_id from courts c join court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active order by 1),
    array(select ta.amenity_id from turf_amenities ta where ta.turf_id = t.id order by 1),
    (select min(oh.open_time) from operating_hours oh where oh.turf_id = t.id),
    (select max(oh.close_time) from operating_hours oh where oh.turf_id = t.id)
  from t
  left join offp o on o.turf_id = t.id
  where (t.dist is null or t.dist <= p_radius_km)
    and (p_sport is null or exists (
          select 1 from courts c join court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active and cs.sport_id = p_sport))
    and (p_max_price is null
         or exists (select 1 from courts c where c.turf_id = t.id and c.is_active and c.base_price <= p_max_price)
         or coalesce(o.price, 999999) <= p_max_price)
    and (p_search is null or p_search = '' or t.name ilike '%' || p_search || '%' or t.area ilike '%' || p_search || '%')
    and (p_amenities is null or cardinality(p_amenities) = 0
         or p_amenities <@ array(select ta.amenity_id from turf_amenities ta where ta.turf_id = t.id))
    and (not p_offpeak_only or o.price is not null)
  order by t.dist asc nulls last, t.rating_avg desc, t.name;
$$;

-- -----------------------------------------------------------------------------
-- create_booking: per-sport player limits, only app bookings count to daily limit
-- -----------------------------------------------------------------------------
create or replace function public.create_booking(
  p_court_id uuid,
  p_sport_id text,
  p_starts_at timestamptz,
  p_slots int,
  p_players int,
  p_looking_for int default 0,
  p_skill public.skill_level default null,
  p_note text default null
)
returns public.bookings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_set app_settings;
  v_profile profiles;
  v_court courts;
  v_turf turfs;
  v_cap int;
  v_end timestamptz;
  v_local timestamp;
  v_local_end timestamp;
  v_total int := 0;
  v_price int;
  v_count int;
  v_code text;
  v_id uuid := gen_random_uuid();
  v_booking bookings;
  v_looking int := coalesce(p_looking_for, 0);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into v_set from app_settings limit 1;
  select * into v_profile from profiles where id = v_uid;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  if v_profile.booking_blocked_until is not null and v_profile.booking_blocked_until > now() then
    raise exception 'BOOKING_BLOCKED';
  end if;

  select * into v_court from courts where id = p_court_id and is_active;
  if not found then raise exception 'COURT_NOT_FOUND'; end if;
  select * into v_turf from turfs where id = v_court.turf_id and is_active;
  if not found then raise exception 'TURF_NOT_FOUND'; end if;

  select coalesce(cs.max_players, v_court.max_players) into v_cap
  from court_sports cs where cs.court_id = p_court_id and cs.sport_id = p_sport_id;
  if not found then raise exception 'SPORT_NOT_SUPPORTED'; end if;

  if p_slots is null or p_slots < 1 or p_slots > v_set.max_slots_per_booking then
    raise exception 'TOO_MANY_SLOTS';
  end if;
  if p_players is null or p_players < 1 or v_looking < 0 or p_players + v_looking > v_cap then
    raise exception 'INVALID_PLAYERS';
  end if;
  if p_starts_at <= now() then raise exception 'SLOT_IN_PAST'; end if;
  if p_starts_at > now() + make_interval(days => v_set.booking_horizon_days) then
    raise exception 'TOO_FAR_AHEAD';
  end if;

  v_end := p_starts_at + make_interval(mins => v_turf.slot_minutes * p_slots);
  v_local := p_starts_at at time zone 'Asia/Kolkata';
  v_local_end := v_end at time zone 'Asia/Kolkata';

  if not exists (
    select 1 from operating_hours oh
    where oh.turf_id = v_turf.id
      and oh.day_of_week = extract(dow from v_local)::int
      and v_local >= v_local::date + oh.open_time
      and v_local_end <= v_local::date + oh.close_time
      and (extract(epoch from (v_local - (v_local::date + oh.open_time))) / 60)::int % v_turf.slot_minutes = 0
  ) then
    raise exception 'OUTSIDE_HOURS';
  end if;

  select count(*) into v_count from bookings
  where user_id = v_uid and source = 'app' and status in ('confirmed', 'checked_in')
    and (starts_at at time zone 'Asia/Kolkata')::date = v_local::date;
  if v_count >= v_set.max_bookings_per_day then raise exception 'DAILY_LIMIT'; end if;

  for i in 0 .. p_slots - 1 loop
    select sp.price into v_price
    from slot_price(p_court_id, p_starts_at + make_interval(mins => v_turf.slot_minutes * i)) sp;
    v_total := v_total + v_price;
  end loop;

  v_code := gen_booking_code();

  begin
    insert into bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id,
                          starts_at, ends_at, players_count, total_price, note, source)
    values (v_id, v_code, sign_booking(v_id, v_code), v_uid, v_turf.id, p_court_id, p_sport_id,
            p_starts_at, v_end, p_players, v_total, p_note, 'app')
    returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;

  if v_looking > 0 then
    insert into open_games (booking_id, host_id, turf_id, sport_id, starts_at, ends_at,
                            spots_total, skill_level, note)
    values (v_booking.id, v_uid, v_turf.id, p_sport_id, p_starts_at, v_end,
            v_looking, p_skill, p_note);
  end if;

  perform notify(v_uid, 'booking_confirmed', 'Booking confirmed ✅',
    v_turf.name || ' · ' || fmt_ist(p_starts_at) || ' · Code ' || v_code,
    '/bookings/' || v_booking.id);

  return v_booking;
end $$;

-- Reviews: on owner-managed turfs only checked-in players can review
create or replace function public.submit_review(p_booking_id uuid, p_rating int, p_comment text default null)
returns public.reviews
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_r reviews; v_owned boolean;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_b from bookings where id = p_booking_id and user_id = auth.uid() and source = 'app';
  if not found then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.status in ('cancelled', 'no_show') or v_b.ends_at > now() then
    raise exception 'REVIEW_NOT_ALLOWED';
  end if;
  select owner_id is not null into v_owned from turfs where id = v_b.turf_id;
  if v_owned and v_b.checked_in_at is null then raise exception 'REVIEW_NEEDS_CHECKIN'; end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'INVALID_RATING'; end if;
  insert into reviews (booking_id, turf_id, user_id, rating, comment)
  values (v_b.id, v_b.turf_id, auth.uid(), p_rating, nullif(trim(p_comment), ''))
  on conflict (booking_id) do update set rating = excluded.rating, comment = excluded.comment
  returning * into v_r;
  return v_r;
end $$;

-- -----------------------------------------------------------------------------
-- Owner notifications on new / cancelled app bookings
-- -----------------------------------------------------------------------------
create or replace function public.notify_owner_on_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_turf text; v_court text; v_player text;
begin
  if new.source <> 'app' then return null; end if;
  select t.owner_id, t.name into v_owner, v_turf from turfs t where t.id = new.turf_id;
  if v_owner is null or v_owner = new.user_id then return null; end if;
  select name into v_court from courts where id = new.court_id;
  select coalesce(nullif(full_name, ''), 'A player') into v_player from profiles where id = new.user_id;

  if tg_op = 'INSERT' then
    perform notify(v_owner, 'owner_new_booking', 'New booking 🎉',
      v_player || ' booked ' || v_court || ' · ' || fmt_ist(new.starts_at) || ' · ' || new.players_count || ' players',
      '/owner/bookings');
  elsif new.status = 'cancelled' and old.status = 'confirmed' and auth.uid() = new.user_id then
    perform notify(v_owner, 'owner_booking_cancelled', 'Booking cancelled',
      v_player || ' cancelled ' || v_court || ' · ' || fmt_ist(new.starts_at) || '. The slot is open again.',
      '/owner/bookings');
  end if;
  return null;
end $$;
drop trigger if exists bookings_notify_owner on public.bookings;
create trigger bookings_notify_owner after insert or update of status on public.bookings
  for each row execute function public.notify_owner_on_booking();

-- -----------------------------------------------------------------------------
-- Owner registration
-- -----------------------------------------------------------------------------
create or replace function public.register_owner(p_full_name text, p_business_name text, p_business_phone text)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v profiles;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(trim(p_business_name), '') = '' then raise exception 'BUSINESS_NAME_REQUIRED'; end if;
  update profiles set
    is_owner = true,
    business_name = trim(p_business_name),
    business_phone = nullif(trim(p_business_phone), ''),
    full_name = case when coalesce(trim(p_full_name), '') <> '' then trim(p_full_name) else full_name end,
    onboarded = true
  where id = auth.uid()
  returning * into v;
  return v;
end $$;

-- -----------------------------------------------------------------------------
-- Owner: create / update a turf (atomic, replaces children)
-- -----------------------------------------------------------------------------
create or replace function public.owner_save_turf(p jsonb)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid := nullif(p->>'id', '')::uuid;
  v_active boolean := coalesce((p->>'is_active')::boolean, false);
  c jsonb;
  s jsonb;
  d jsonb;
  h jsonb;
  v_court uuid;
  v_keymap jsonb := '{}'::jsonb;
  v_keep uuid[] := '{}';
  v_court_key text;
  i int := 0;
  v_hours int := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists (select 1 from profiles where id = v_uid and is_owner) then raise exception 'NOT_OWNER'; end if;
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'NAME_REQUIRED'; end if;
  if (p->>'lat') is null or (p->>'lng') is null then raise exception 'LOCATION_REQUIRED'; end if;

  if v_active then
    if coalesce(trim(p->>'address'), '') = '' then raise exception 'ADDRESS_REQUIRED'; end if;
    if jsonb_array_length(coalesce(p->'courts', '[]'::jsonb)) = 0 then raise exception 'COURT_REQUIRED'; end if;
  end if;

  if v_id is null then
    insert into turfs (slug, name, description, area, address, lat, lng, phone, whatsapp,
                       rules, slot_minutes, is_active, owner_id)
    values (
      slugify(p->>'name') || '-' || substr(md5(random()::text), 1, 5),
      trim(p->>'name'), nullif(trim(p->>'description'), ''),
      coalesce(nullif(trim(p->>'area'), ''), 'Delhi NCR'),
      coalesce(nullif(trim(p->>'address'), ''), 'Address pending'),
      (p->>'lat')::float8, (p->>'lng')::float8,
      nullif(trim(p->>'phone'), ''), nullif(trim(coalesce(p->>'whatsapp', p->>'phone')), ''),
      array(select jsonb_array_elements_text(coalesce(p->'rules', '[]'::jsonb))),
      coalesce((p->>'slot_minutes')::int, 60), v_active, v_uid)
    returning id into v_id;
  else
    if not exists (select 1 from turfs where id = v_id and owner_id = v_uid) then
      raise exception 'TURF_NOT_FOUND';
    end if;
    update turfs set
      name = trim(p->>'name'),
      description = nullif(trim(p->>'description'), ''),
      area = coalesce(nullif(trim(p->>'area'), ''), 'Delhi NCR'),
      address = coalesce(nullif(trim(p->>'address'), ''), 'Address pending'),
      lat = (p->>'lat')::float8,
      lng = (p->>'lng')::float8,
      phone = nullif(trim(p->>'phone'), ''),
      whatsapp = nullif(trim(coalesce(p->>'whatsapp', p->>'phone')), ''),
      rules = array(select jsonb_array_elements_text(coalesce(p->'rules', '[]'::jsonb))),
      slot_minutes = coalesce((p->>'slot_minutes')::int, 60),
      is_active = v_active,
      updated_at = now()
    where id = v_id;
  end if;

  -- photos (first = cover)
  delete from turf_photos where turf_id = v_id;
  insert into turf_photos (turf_id, url, sort_order)
  select v_id, x.url, x.ord - 1
  from jsonb_array_elements_text(coalesce(p->'photos', '[]'::jsonb)) with ordinality as x(url, ord);
  update turfs set cover_image = p->'photos'->>0 where id = v_id;

  -- amenities
  delete from turf_amenities where turf_id = v_id;
  insert into turf_amenities (turf_id, amenity_id)
  select distinct v_id, a.value
  from jsonb_array_elements_text(coalesce(p->'amenities', '[]'::jsonb)) a
  where a.value in (select id from amenities);

  -- operating hours
  delete from operating_hours where turf_id = v_id;
  for h in select * from jsonb_array_elements(coalesce(p->'hours', '[]'::jsonb)) loop
    if not coalesce((h->>'closed')::boolean, false) then
      if (h->>'close_time')::time <= (h->>'open_time')::time and (h->>'close_time') not like '24%' then
        raise exception 'INVALID_HOURS';
      end if;
      insert into operating_hours (turf_id, day_of_week, open_time, close_time)
      values (v_id, (h->>'day_of_week')::int, (h->>'open_time')::time, (h->>'close_time')::time);
      v_hours := v_hours + 1;
    end if;
  end loop;
  if v_active and v_hours = 0 then raise exception 'HOURS_REQUIRED'; end if;

  -- courts (upsert by id so existing bookings stay valid)
  for c in select * from jsonb_array_elements(coalesce(p->'courts', '[]'::jsonb)) loop
    if coalesce(trim(c->>'name'), '') = '' then raise exception 'COURT_NAME_REQUIRED'; end if;
    if coalesce((c->>'base_price')::int, -1) < 0 then raise exception 'COURT_PRICE_REQUIRED'; end if;
    if coalesce((c->>'max_players')::int, 0) < 1 then raise exception 'COURT_CAPACITY_REQUIRED'; end if;

    v_court := nullif(c->>'id', '')::uuid;
    if v_court is not null and exists (select 1 from courts where id = v_court and turf_id = v_id) then
      update courts set
        name = trim(c->>'name'),
        size_label = nullif(trim(c->>'size_label'), ''),
        surface = nullif(trim(c->>'surface'), ''),
        base_price = (c->>'base_price')::int,
        max_players = (c->>'max_players')::int,
        is_active = true,
        sort_order = i
      where id = v_court;
    else
      insert into courts (turf_id, name, size_label, surface, base_price, max_players, sort_order)
      values (v_id, trim(c->>'name'), nullif(trim(c->>'size_label'), ''), nullif(trim(c->>'surface'), ''),
              (c->>'base_price')::int, (c->>'max_players')::int, i)
      returning id into v_court;
    end if;

    v_keep := v_keep || v_court;
    v_court_key := coalesce(nullif(c->>'key', ''), v_court::text);
    v_keymap := v_keymap || jsonb_build_object(v_court_key, v_court::text, v_court::text, v_court::text);

    delete from court_sports where court_id = v_court;
    for s in select * from jsonb_array_elements(coalesce(c->'sports', '[]'::jsonb)) loop
      insert into court_sports (court_id, sport_id, max_players)
      values (v_court, s->>'sport_id',
              least(nullif(s->>'max_players', '')::int, (c->>'max_players')::int))
      on conflict (court_id, sport_id) do nothing;
    end loop;
    if not exists (select 1 from court_sports where court_id = v_court) then
      raise exception 'COURT_SPORT_REQUIRED';
    end if;
    i := i + 1;
  end loop;

  -- removed courts: delete if never booked, otherwise hide
  update courts set is_active = false
  where turf_id = v_id and not (id = any (v_keep))
    and exists (select 1 from bookings b where b.court_id = courts.id);
  delete from courts
  where turf_id = v_id and not (id = any (v_keep))
    and not exists (select 1 from bookings b where b.court_id = courts.id);

  -- deals / pricing rules
  delete from pricing_rules where turf_id = v_id;
  for d in select * from jsonb_array_elements(coalesce(p->'deals', '[]'::jsonb)) loop
    if jsonb_array_length(coalesce(d->'days_of_week', '[]'::jsonb)) = 0 then continue; end if;
    if (d->>'end_time')::time <= (d->>'start_time')::time and (d->>'end_time') not like '24%' then
      raise exception 'INVALID_DEAL_TIME';
    end if;
    insert into pricing_rules (turf_id, court_id, days_of_week, start_time, end_time,
                               price, discount_pct, label, is_offpeak)
    values (
      v_id,
      case when coalesce(d->>'court_key', '') = '' then null
           else (v_keymap->>(d->>'court_key'))::uuid end,
      array(select jsonb_array_elements_text(d->'days_of_week')::int),
      (d->>'start_time')::time, (d->>'end_time')::time,
      nullif(d->>'price', '')::int,
      nullif(d->>'discount_pct', '')::int,
      nullif(trim(d->>'label'), ''),
      coalesce((d->>'is_offpeak')::boolean, true)
    );
  end loop;

  return v_id;
end $$;

create or replace function public.owner_set_turf_active(p_turf_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_turf_owner(p_turf_id) then raise exception 'TURF_NOT_FOUND'; end if;
  if p_active then
    if not exists (select 1 from courts where turf_id = p_turf_id and is_active) then raise exception 'COURT_REQUIRED'; end if;
    if not exists (select 1 from operating_hours where turf_id = p_turf_id) then raise exception 'HOURS_REQUIRED'; end if;
  end if;
  update turfs set is_active = p_active, updated_at = now() where id = p_turf_id;
end $$;

create or replace function public.owner_delete_turf(p_turf_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_turf_owner(p_turf_id) then raise exception 'TURF_NOT_FOUND'; end if;
  if exists (select 1 from bookings where turf_id = p_turf_id) then
    -- keep history: just hide it
    update turfs set is_active = false, updated_at = now() where id = p_turf_id;
  else
    delete from turfs where id = p_turf_id;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Owner dashboard
-- -----------------------------------------------------------------------------
create or replace function public.owner_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_dow int := extract(dow from v_today)::int;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  with my as (select * from turfs where owner_id = v_uid),
  b as (
    select bk.* from bookings bk join my on my.id = bk.turf_id
    where bk.status in ('confirmed', 'checked_in', 'completed')
  ),
  capacity as (
    -- bookable court-minutes today across my live turfs
    select coalesce(sum(extract(epoch from (oh.close_time - oh.open_time)) / 60
                        * (select count(*) from courts c where c.turf_id = my.id and c.is_active)), 0) as mins
    from my join operating_hours oh on oh.turf_id = my.id and oh.day_of_week = v_dow
    where my.is_active
  ),
  today as (
    select count(*) as n,
           coalesce(sum(total_price) filter (where source = 'app' or source = 'walk_in'), 0) as revenue,
           count(*) filter (where status = 'checked_in' or checked_in_at is not null) as checked_in,
           coalesce(sum(extract(epoch from (ends_at - starts_at)) / 60), 0) as mins
    from b where (starts_at at time zone 'Asia/Kolkata')::date = v_today
  ),
  week as (
    select count(*) as n, coalesce(sum(total_price) filter (where source <> 'blocked'), 0) as revenue
    from b where starts_at >= (v_today - 6)::timestamp at time zone 'Asia/Kolkata'
             and starts_at < (v_today + 1)::timestamp at time zone 'Asia/Kolkata'
  )
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'today_bookings', today.n,
      'today_revenue', today.revenue,
      'today_checked_in', today.checked_in,
      'today_occupancy_pct', case when capacity.mins > 0 then round(today.mins * 100.0 / capacity.mins) else 0 end,
      'week_bookings', week.n,
      'week_revenue', week.revenue,
      'upcoming', (select count(*) from b where starts_at > now() and status = 'confirmed')
    ),
    'turfs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', my.id, 'slug', my.slug, 'name', my.name, 'area', my.area,
        'cover_image', my.cover_image, 'is_active', my.is_active,
        'rating_avg', my.rating_avg, 'rating_count', my.rating_count,
        'courts', (select count(*) from courts c where c.turf_id = my.id and c.is_active),
        'sports', array(select distinct cs.sport_id from courts c join court_sports cs on cs.court_id = c.id
                        where c.turf_id = my.id and c.is_active),
        'min_price', (select min(base_price) from courts c where c.turf_id = my.id and c.is_active),
        'deals', (select count(*) from pricing_rules pr where pr.turf_id = my.id and pr.is_offpeak),
        'today_bookings', (select count(*) from b where b.turf_id = my.id
                             and (b.starts_at at time zone 'Asia/Kolkata')::date = v_today),
        'upcoming', (select count(*) from b where b.turf_id = my.id and b.starts_at > now() and b.status = 'confirmed')
      ) order by my.created_at)
      from my
    ), '[]'::jsonb),
    'next_bookings', coalesce((
      select jsonb_agg(x order by x->>'starts_at') from (
        select jsonb_build_object(
          'id', bk.id, 'code', bk.code, 'starts_at', bk.starts_at, 'ends_at', bk.ends_at,
          'players_count', bk.players_count, 'total_price', bk.total_price, 'status', bk.status,
          'source', bk.source, 'turf_name', t.name, 'court_name', c.name, 'sport_id', bk.sport_id,
          'player_name', coalesce(nullif(pf.full_name, ''), 'Player')
        ) as x
        from bookings bk
        join turfs t on t.id = bk.turf_id and t.owner_id = v_uid
        join courts c on c.id = bk.court_id
        join profiles pf on pf.id = bk.user_id
        where bk.status = 'confirmed' and bk.ends_at > now()
        order by bk.starts_at
        limit 6
      ) q
    ), '[]'::jsonb)
  ) into v_result
  from today, week, capacity;

  return v_result;
end $$;

-- -----------------------------------------------------------------------------
-- Owner bookings list
-- -----------------------------------------------------------------------------
create or replace function public.owner_list_bookings(
  p_from timestamptz, p_to timestamptz, p_turf_id uuid default null
)
returns table (
  id uuid, code text, turf_id uuid, turf_name text, court_id uuid, court_name text,
  sport_id text, starts_at timestamptz, ends_at timestamptz, players_count int, total_price int,
  status public.booking_status, source text, note text, player_name text, player_phone text,
  checked_in_at timestamptz, created_at timestamptz, open_spots int
)
language sql stable security definer set search_path = public as $$
  select b.id, b.code, t.id, t.name, c.id, c.name, b.sport_id, b.starts_at, b.ends_at,
         b.players_count, b.total_price, b.status, b.source, b.note,
         case when b.source = 'app' then coalesce(nullif(p.full_name, ''), 'Player') else coalesce(b.note, 'Walk-in') end,
         case when b.source = 'app' then coalesce(p.phone, p.email) end,
         b.checked_in_at, b.created_at,
         (select g.spots_total from open_games g where g.booking_id = b.id and g.status <> 'closed')
  from bookings b
  join turfs t on t.id = b.turf_id and t.owner_id = auth.uid()
  join courts c on c.id = b.court_id
  join profiles p on p.id = b.user_id
  where b.starts_at < p_to and b.ends_at > p_from
    and (p_turf_id is null or b.turf_id = p_turf_id)
  order by b.starts_at, c.sort_order;
$$;

-- -----------------------------------------------------------------------------
-- QR / code lookup + check-in
-- -----------------------------------------------------------------------------
create or replace function public.owner_lookup_booking(p_input text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_in text := trim(coalesce(p_input, ''));
  v_parts text[];
  v_id uuid;
  v_b bookings;
  v_reason text := null;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  if v_in like 'TFT1.%' then
    v_parts := string_to_array(v_in, '.');
    if array_length(v_parts, 1) <> 4 then raise exception 'INVALID_QR'; end if;
    begin
      v_id := v_parts[2]::uuid;
    exception when others then raise exception 'INVALID_QR';
    end;
    if sign_booking(v_id, v_parts[3]) <> v_in then raise exception 'INVALID_QR'; end if;
    select * into v_b from bookings where id = v_id and code = v_parts[3];
  else
    select * into v_b from bookings where code = upper(regexp_replace(v_in, '[^A-Za-z0-9]', '', 'g'));
  end if;

  if v_b.id is null or not is_turf_owner(v_b.turf_id) then raise exception 'BOOKING_NOT_FOUND'; end if;

  if v_b.status = 'cancelled' then v_reason := 'BOOKING_CANCELLED';
  elsif v_b.status = 'no_show' then v_reason := 'MARKED_NO_SHOW';
  elsif v_b.checked_in_at is not null then v_reason := 'ALREADY_CHECKED_IN';
  elsif now() < v_b.starts_at - interval '60 minutes' then v_reason := 'TOO_EARLY';
  elsif now() > v_b.ends_at then v_reason := 'BOOKING_ENDED';
  end if;

  return (
    select jsonb_build_object(
      'id', v_b.id, 'code', v_b.code, 'status', v_b.status, 'source', v_b.source,
      'starts_at', v_b.starts_at, 'ends_at', v_b.ends_at,
      'players_count', v_b.players_count, 'total_price', v_b.total_price, 'note', v_b.note,
      'sport_id', v_b.sport_id, 'checked_in_at', v_b.checked_in_at,
      'turf_name', t.name, 'court_name', c.name, 'size_label', c.size_label,
      'player_name', coalesce(nullif(p.full_name, ''), 'Player'),
      'player_phone', coalesce(p.phone, p.email),
      'joined_players', (select count(*) from open_games g join join_requests jr on jr.game_id = g.id
                         where g.booking_id = v_b.id and jr.status = 'accepted'),
      'can_check_in', v_reason is null,
      'reason', v_reason
    )
    from turfs t, courts c, profiles p
    where t.id = v_b.turf_id and c.id = v_b.court_id and p.id = v_b.user_id
  );
end $$;

create or replace function public.owner_check_in(p_booking_id uuid)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_turf text;
begin
  select * into v_b from bookings where id = p_booking_id for update;
  if not found or not is_turf_owner(v_b.turf_id) then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.status = 'cancelled' then raise exception 'BOOKING_CANCELLED'; end if;
  if v_b.checked_in_at is not null then raise exception 'ALREADY_CHECKED_IN'; end if;
  if v_b.status not in ('confirmed', 'completed', 'no_show') then raise exception 'NOT_CHECKABLE'; end if;
  if now() < v_b.starts_at - interval '60 minutes' then raise exception 'TOO_EARLY'; end if;
  if now() > v_b.ends_at + interval '2 hours' then raise exception 'BOOKING_ENDED'; end if;

  update bookings set status = case when ends_at < now() then 'completed'::booking_status else 'checked_in'::booking_status end,
                      checked_in_at = now()
  where id = p_booking_id returning * into v_b;

  select name into v_turf from turfs where id = v_b.turf_id;
  if v_b.source = 'app' then
    perform notify(v_b.user_id, 'checked_in', 'Checked in ✅',
      'Welcome to ' || v_turf || '! Have a great game.', '/bookings/' || v_b.id);
  end if;
  return v_b;
end $$;

create or replace function public.owner_mark_no_show(p_booking_id uuid)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_set app_settings; v_turf text;
begin
  select * into v_set from app_settings limit 1;
  select * into v_b from bookings where id = p_booking_id for update;
  if not found or not is_turf_owner(v_b.turf_id) then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.source <> 'app' then raise exception 'NOT_APP_BOOKING'; end if;
  if v_b.checked_in_at is not null then raise exception 'ALREADY_CHECKED_IN'; end if;
  if v_b.status not in ('confirmed', 'completed') then raise exception 'NOT_CHECKABLE'; end if;
  if now() < v_b.starts_at + interval '10 minutes' then raise exception 'TOO_EARLY_NO_SHOW'; end if;
  if now() > v_b.ends_at + interval '24 hours' then raise exception 'BOOKING_ENDED'; end if;

  update bookings set status = 'no_show' where id = p_booking_id returning * into v_b;

  if v_set.strikes_enabled then
    update profiles set strikes = strikes + 1,
      booking_blocked_until = case when strikes + 1 >= v_set.strike_limit
                                   then now() + make_interval(days => v_set.strike_block_days)
                                   else booking_blocked_until end
    where id = v_b.user_id;
  end if;

  select name into v_turf from turfs where id = v_b.turf_id;
  perform notify(v_b.user_id, 'no_show', 'Marked as no-show',
    'You were marked absent for ' || v_turf || ' · ' || fmt_ist(v_b.starts_at) ||
    '. Please cancel in advance if plans change. Repeated no-shows block booking.', '/bookings/' || v_b.id);
  return v_b;
end $$;

create or replace function public.owner_cancel_booking(p_booking_id uuid, p_reason text default null)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare v_b bookings; v_turf text; r record;
begin
  select * into v_b from bookings where id = p_booking_id for update;
  if not found or not is_turf_owner(v_b.turf_id) then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.status <> 'confirmed' then raise exception 'NOT_CANCELLABLE'; end if;
  if v_b.source = 'app' and v_b.starts_at <= now() then raise exception 'NOT_CANCELLABLE'; end if;

  update bookings set status = 'cancelled', cancelled_at = now(),
                      cancel_reason = coalesce(nullif(trim(p_reason), ''), 'Cancelled by venue')
  where id = p_booking_id returning * into v_b;

  if v_b.source = 'app' then
    select name into v_turf from turfs where id = v_b.turf_id;
    perform notify(v_b.user_id, 'venue_cancelled', 'Venue cancelled your booking',
      v_turf || ' · ' || fmt_ist(v_b.starts_at) || ' was cancelled by the venue' ||
      coalesce(': ' || nullif(trim(p_reason), ''), '.') || ' Sorry for the inconvenience!', '/bookings/' || v_b.id);
    for r in
      select jr.user_id from join_requests jr join open_games g on g.id = jr.game_id
      where g.booking_id = v_b.id and jr.status in ('pending', 'accepted')
    loop
      perform notify(r.user_id, 'game_cancelled', 'Game cancelled',
        'The game at ' || v_turf || ' (' || fmt_ist(v_b.starts_at) || ') was cancelled by the venue.', '/games');
    end loop;
    update open_games set status = 'closed' where booking_id = v_b.id;
  end if;
  return v_b;
end $$;

-- Walk-in bookings & blocked slots (maintenance / offline customers)
create or replace function public.owner_block_slots(
  p_court_id uuid,
  p_starts_at timestamptz,
  p_slots int,
  p_source text default 'blocked',
  p_note text default null,
  p_players int default 1,
  p_price int default null
)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_court courts; v_turf turfs; v_end timestamptz; v_local timestamp; v_local_end timestamp;
  v_total int := 0; v_price int; v_code text; v_id uuid := gen_random_uuid(); v_b bookings;
  v_sport text;
begin
  select * into v_court from courts where id = p_court_id and is_active;
  if not found or not is_turf_owner(v_court.turf_id) then raise exception 'COURT_NOT_FOUND'; end if;
  select * into v_turf from turfs where id = v_court.turf_id;
  if p_source not in ('walk_in', 'blocked') then raise exception 'INVALID_SOURCE'; end if;
  if p_slots is null or p_slots < 1 or p_slots > 24 then raise exception 'TOO_MANY_SLOTS'; end if;

  v_end := p_starts_at + make_interval(mins => v_turf.slot_minutes * p_slots);
  if v_end <= now() then raise exception 'SLOT_IN_PAST'; end if;
  v_local := p_starts_at at time zone 'Asia/Kolkata';
  v_local_end := v_end at time zone 'Asia/Kolkata';
  if not exists (
    select 1 from operating_hours oh
    where oh.turf_id = v_turf.id and oh.day_of_week = extract(dow from v_local)::int
      and v_local >= v_local::date + oh.open_time and v_local_end <= v_local::date + oh.close_time
  ) then raise exception 'OUTSIDE_HOURS'; end if;

  if p_source = 'walk_in' then
    if p_price is not null then v_total := p_price;
    else
      for i in 0 .. p_slots - 1 loop
        select sp.price into v_price
        from slot_price(p_court_id, p_starts_at + make_interval(mins => v_turf.slot_minutes * i)) sp;
        v_total := v_total + v_price;
      end loop;
    end if;
  end if;

  select sport_id into v_sport from court_sports where court_id = p_court_id order by sport_id limit 1;
  v_code := gen_booking_code();

  begin
    insert into bookings (id, code, qr_token, user_id, turf_id, court_id, sport_id, starts_at, ends_at,
                          players_count, total_price, note, source)
    values (v_id, v_code, sign_booking(v_id, v_code), auth.uid(), v_turf.id, p_court_id, v_sport,
            p_starts_at, v_end, greatest(coalesce(p_players, 1), 1), v_total,
            coalesce(nullif(trim(p_note), ''), case when p_source = 'walk_in' then 'Walk-in' else 'Blocked' end),
            p_source)
    returning * into v_b;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;
  return v_b;
end $$;

-- -----------------------------------------------------------------------------
-- Maintenance: no automatic no-shows (owners mark them explicitly)
-- -----------------------------------------------------------------------------
create or replace function public.run_maintenance()
returns void language plpgsql security definer set search_path = public as $$
declare v_set app_settings; r record; p record;
begin
  select * into v_set from app_settings limit 1;

  for r in
    select b.*, t.name as turf_name from bookings b join turfs t on t.id = b.turf_id
    where b.status = 'confirmed' and b.source = 'app' and b.reminder_sent_at is null
      and b.starts_at > now()
      and b.starts_at <= now() + make_interval(mins => v_set.reminder_minutes_before)
  loop
    perform notify(r.user_id, 'booking_reminder', 'Game time soon ⏰',
      r.turf_name || ' at ' || to_char(r.starts_at at time zone 'Asia/Kolkata', 'FMHH12:MI AM') ||
      '. Show your QR (code ' || r.code || ') at the venue.', '/bookings/' || r.id);
    for p in
      select jr.user_id from join_requests jr join open_games g on g.id = jr.game_id
      where g.booking_id = r.id and jr.status = 'accepted'
    loop
      perform notify(p.user_id, 'game_reminder', 'Game time soon ⏰',
        r.turf_name || ' at ' || to_char(r.starts_at at time zone 'Asia/Kolkata', 'FMHH12:MI AM') || '.',
        '/games');
    end loop;
    update bookings set reminder_sent_at = now() where id = r.id;
  end loop;

  update bookings set status = 'completed'
  where status in ('confirmed', 'checked_in') and ends_at < now() - interval '30 minutes';

  update open_games set status = 'closed' where status <> 'closed' and starts_at <= now();
end $$;
revoke execute on function public.run_maintenance() from public, anon, authenticated;

-- Owner portal exists now: owner-reported no-shows count as strikes
update public.app_settings set strikes_enabled = true;

-- Grants
revoke execute on function public.register_owner(text, text, text) from anon;
revoke execute on function public.owner_save_turf(jsonb) from anon;
revoke execute on function public.owner_set_turf_active(uuid, boolean) from anon;
revoke execute on function public.owner_delete_turf(uuid) from anon;
revoke execute on function public.owner_dashboard() from anon;
revoke execute on function public.owner_list_bookings(timestamptz, timestamptz, uuid) from anon;
revoke execute on function public.owner_lookup_booking(text) from anon;
revoke execute on function public.owner_check_in(uuid) from anon;
revoke execute on function public.owner_mark_no_show(uuid) from anon;
revoke execute on function public.owner_cancel_booking(uuid, text) from anon;
revoke execute on function public.owner_block_slots(uuid, timestamptz, int, text, text, int, int) from anon;


-- >>> 20261031000007_fix_owner_rpcs.sql
-- =============================================================================
-- Fix & align all Owner Portal RPC signatures and return types with Frontend
-- =============================================================================
set search_path = public, extensions;

-- 1. Drop old overloads to avoid PostgREST ambiguity
drop function if exists public.owner_save_turf(jsonb);
drop function if exists public.owner_dashboard();
drop function if exists public.owner_list_bookings(timestamptz, timestamptz, uuid);
drop function if exists public.owner_list_bookings(text, text, uuid);
drop function if exists public.owner_lookup_booking(text);
drop function if exists public.owner_check_in(uuid);
drop function if exists public.owner_check_in(uuid, text);
drop function if exists public.owner_block_slots(uuid, timestamptz, int, text, text, int, int);
drop function if exists public.owner_block_slots(uuid, text, timestamptz, int, int, text, int, text);

-- 2. owner_save_turf(p_payload jsonb) -> jsonb { id, slug, name }
create or replace function public.owner_save_turf(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_active boolean := coalesce((p_payload->>'is_active')::boolean, true);
  v_slug text;
  v_name text := trim(coalesce(p_payload->>'name', ''));
  c jsonb;
  s jsonb;
  d jsonb;
  h jsonb;
  v_court uuid;
  v_keymap jsonb := '{}'::jsonb;
  v_keep uuid[] := '{}';
  v_court_key text;
  v_target_court uuid;
  i int := 0;
  v_hours int := 0;
  v_hours_arr jsonb;
  v_rules_arr jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  -- Ensure the signed-in user has a profile and is marked as an owner automatically
  insert into public.profiles (id, full_name, is_owner, onboarded)
  values (v_uid, 'Turf Owner', true, true)
  on conflict (id) do update set is_owner = true, onboarded = true;

  if v_name = '' then raise exception 'NAME_REQUIRED'; end if;
  if (p_payload->>'lat') is null or (p_payload->>'lng') is null then raise exception 'LOCATION_REQUIRED'; end if;

  if v_active then
    if coalesce(trim(p_payload->>'address'), '') = '' then raise exception 'ADDRESS_REQUIRED'; end if;
    if jsonb_array_length(coalesce(p_payload->'courts', '[]'::jsonb)) = 0 then raise exception 'COURT_REQUIRED'; end if;
  end if;

  if v_id is null then
    v_slug := slugify(v_name) || '-' || substr(md5(random()::text), 1, 5);
    insert into public.turfs (
      slug, name, description, area, city, address, lat, lng, phone, whatsapp,
      cover_image, rules, slot_minutes, is_active, owner_id
    )
    values (
      v_slug,
      v_name,
      nullif(trim(p_payload->>'description'), ''),
      coalesce(nullif(trim(p_payload->>'area'), ''), 'Delhi NCR'),
      coalesce(nullif(trim(p_payload->>'city'), ''), 'Delhi NCR'),
      coalesce(nullif(trim(p_payload->>'address'), ''), 'Address pending'),
      (p_payload->>'lat')::float8,
      (p_payload->>'lng')::float8,
      nullif(trim(p_payload->>'phone'), ''),
      nullif(trim(coalesce(p_payload->>'whatsapp', p_payload->>'phone')), ''),
      coalesce(nullif(trim(p_payload->>'cover_image'), ''), p_payload->'photos'->>0),
      array(select jsonb_array_elements_text(coalesce(p_payload->'rules', '[]'::jsonb))),
      coalesce((p_payload->>'slot_minutes')::int, 60),
      v_active,
      v_uid
    )
    returning id, slug into v_id, v_slug;
  else
    if not exists (select 1 from public.turfs where id = v_id and owner_id = v_uid) then
      raise exception 'NOT_OWNER';
    end if;
    update public.turfs set
      name = v_name,
      description = nullif(trim(p_payload->>'description'), ''),
      area = coalesce(nullif(trim(p_payload->>'area'), ''), 'Delhi NCR'),
      city = coalesce(nullif(trim(p_payload->>'city'), ''), 'Delhi NCR'),
      address = coalesce(nullif(trim(p_payload->>'address'), ''), 'Address pending'),
      lat = (p_payload->>'lat')::float8,
      lng = (p_payload->>'lng')::float8,
      phone = nullif(trim(p_payload->>'phone'), ''),
      whatsapp = nullif(trim(coalesce(p_payload->>'whatsapp', p_payload->>'phone')), ''),
      cover_image = coalesce(nullif(trim(p_payload->>'cover_image'), ''), p_payload->'photos'->>0, cover_image),
      rules = array(select jsonb_array_elements_text(coalesce(p_payload->'rules', '[]'::jsonb))),
      slot_minutes = coalesce((p_payload->>'slot_minutes')::int, 60),
      is_active = v_active,
      updated_at = now()
    where id = v_id
    returning slug into v_slug;
  end if;

  -- Photos
  delete from public.turf_photos where turf_id = v_id;
  insert into public.turf_photos (turf_id, url, sort_order)
  select v_id, x.url, x.ord - 1
  from jsonb_array_elements_text(coalesce(p_payload->'photos', '[]'::jsonb)) with ordinality as x(url, ord)
  where trim(x.url) <> '';

  if p_payload->'photos'->>0 is not null then
    update public.turfs set cover_image = p_payload->'photos'->>0 where id = v_id;
  end if;

  -- Amenities
  delete from public.turf_amenities where turf_id = v_id;
  insert into public.turf_amenities (turf_id, amenity_id)
  select distinct v_id, a.value
  from jsonb_array_elements_text(coalesce(p_payload->'amenities', '[]'::jsonb)) a
  where a.value in (select id from public.amenities);

  -- Operating Hours (accepts either operating_hours or hours)
  v_hours_arr := coalesce(p_payload->'operating_hours', p_payload->'hours', '[]'::jsonb);
  delete from public.operating_hours where turf_id = v_id;
  for h in select * from jsonb_array_elements(v_hours_arr) loop
    if not coalesce((h->>'closed')::boolean, false) then
      if (h->>'close_time')::time <= (h->>'open_time')::time and (h->>'close_time') not like '24%' then
        raise exception 'INVALID_HOURS';
      end if;
      insert into public.operating_hours (turf_id, day_of_week, open_time, close_time)
      values (v_id, (h->>'day_of_week')::int, (h->>'open_time')::time, (h->>'close_time')::time)
      on conflict (turf_id, day_of_week) do update
        set open_time = excluded.open_time, close_time = excluded.close_time;
      v_hours := v_hours + 1;
    end if;
  end loop;
  if v_active and v_hours = 0 then raise exception 'HOURS_REQUIRED'; end if;

  -- Courts & Per-Sport Max Players
  for c in select * from jsonb_array_elements(coalesce(p_payload->'courts', '[]'::jsonb)) loop
    if coalesce(trim(c->>'name'), '') = '' then raise exception 'COURT_REQUIRED'; end if;

    begin
      v_court := nullif(c->>'id', '')::uuid;
    exception when others then
      v_court := null;
    end;

    if v_court is not null and exists (select 1 from public.courts where id = v_court and turf_id = v_id) then
      update public.courts set
        name = trim(c->>'name'),
        size_label = nullif(trim(c->>'size_label'), ''),
        surface = nullif(trim(c->>'surface'), ''),
        base_price = greatest(coalesce((c->>'base_price')::int, 1000), 100),
        max_players = greatest(coalesce((c->>'max_players')::int, 10), 2),
        is_active = true,
        sort_order = i
      where id = v_court;
    else
      insert into public.courts (turf_id, name, size_label, surface, base_price, max_players, sort_order)
      values (
        v_id,
        trim(c->>'name'),
        nullif(trim(c->>'size_label'), ''),
        nullif(trim(c->>'surface'), ''),
        greatest(coalesce((c->>'base_price')::int, 1000), 100),
        greatest(coalesce((c->>'max_players')::int, 10), 2),
        i
      )
      returning id into v_court;
    end if;

    v_keep := v_keep || v_court;
    v_court_key := coalesce(nullif(c->>'key', ''), v_court::text);
    v_keymap := v_keymap || jsonb_build_object(v_court_key, v_court::text, v_court::text, v_court::text);

    delete from public.court_sports where court_id = v_court;
    for s in select * from jsonb_array_elements(coalesce(c->'sports', '[]'::jsonb)) loop
      insert into public.court_sports (court_id, sport_id, max_players)
      values (
        v_court,
        s->>'sport_id',
        greatest(coalesce(nullif(s->>'max_players', '')::int, (c->>'max_players')::int, 10), 2)
      )
      on conflict (court_id, sport_id) do update set max_players = excluded.max_players;
    end loop;

    if not exists (select 1 from public.court_sports where court_id = v_court) then
      raise exception 'COURT_SPORT_REQUIRED';
    end if;
    i := i + 1;
  end loop;

  -- Deactivate or delete removed courts
  update public.courts set is_active = false
  where turf_id = v_id and not (id = any (v_keep))
    and exists (select 1 from public.bookings b where b.court_id = courts.id);
  delete from public.courts
  where turf_id = v_id and not (id = any (v_keep))
    and not exists (select 1 from public.bookings b where b.court_id = courts.id);

  -- Pricing Rules / Happy Hour Deals (accepts pricing_rules or deals)
  v_rules_arr := coalesce(p_payload->'pricing_rules', p_payload->'deals', '[]'::jsonb);
  delete from public.pricing_rules where turf_id = v_id;
  for d in select * from jsonb_array_elements(v_rules_arr) loop
    if jsonb_array_length(coalesce(d->'days_of_week', '[]'::jsonb)) = 0 then continue; end if;
    if (d->>'end_time')::time <= (d->>'start_time')::time and (d->>'end_time') not like '24%' then
      continue;
    end if;

    v_target_court := null;
    if coalesce(d->>'court_key', '') <> '' and (v_keymap ? (d->>'court_key')) then
      v_target_court := (v_keymap->>(d->>'court_key'))::uuid;
    elsif coalesce(d->>'court_id', '') <> '' and (v_keymap ? (d->>'court_id')) then
      v_target_court := (v_keymap->>(d->>'court_id'))::uuid;
    end if;

    insert into public.pricing_rules (
      turf_id, court_id, days_of_week, start_time, end_time,
      price, discount_pct, label, is_offpeak
    )
    values (
      v_id,
      v_target_court,
      array(select jsonb_array_elements_text(d->'days_of_week')::int),
      (d->>'start_time')::time,
      (d->>'end_time')::time,
      nullif(d->>'price', '')::int,
      nullif(d->>'discount_pct', '')::int,
      coalesce(nullif(trim(d->>'label'), ''), 'Happy Hour'),
      coalesce((d->>'is_offpeak')::boolean, true)
    );
  end loop;

  return jsonb_build_object('id', v_id, 'slug', v_slug, 'name', v_name);
end $$;

-- 3. owner_dashboard() -> matches OwnerDashboardData
create or replace function public.owner_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_dow int := extract(dow from v_today)::int;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  with my as (select * from public.turfs where owner_id = v_uid),
  b as (
    select bk.* from public.bookings bk join my on my.id = bk.turf_id
    where bk.status in ('confirmed', 'checked_in', 'completed')
  ),
  capacity as (
    select coalesce(sum(extract(epoch from (oh.close_time - oh.open_time)) / 60
                        * (select count(*) from public.courts c where c.turf_id = my.id and c.is_active)), 0) as mins
    from my join public.operating_hours oh on oh.turf_id = my.id and oh.day_of_week = v_dow
    where my.is_active
  ),
  today as (
    select count(*) as n,
           coalesce(sum(total_price) filter (where source in ('app', 'walk_in')), 0) as revenue,
           count(*) filter (where status = 'checked_in' or checked_in_at is not null) as checked_in,
           coalesce(sum(extract(epoch from (ends_at - starts_at)) / 60), 0) as mins
    from b where (starts_at at time zone 'Asia/Kolkata')::date = v_today
  ),
  week as (
    select count(*) as n,
           coalesce(sum(total_price) filter (where source <> 'blocked'), 0) as revenue
    from b where (starts_at at time zone 'Asia/Kolkata')::date between (v_today - 6) and v_today
  )
  select jsonb_build_object(
    'today', v_today::text,
    'turfs_count', (select count(*) from my),
    'today_bookings', today.n,
    'today_checked_in', today.checked_in,
    'today_revenue', today.revenue,
    'week_revenue', week.revenue,
    'today_occupancy_pct', case when capacity.mins > 0 then round(today.mins * 100.0 / capacity.mins) else 0 end,
    'turfs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', my.id,
        'slug', my.slug,
        'name', my.name,
        'area', my.area,
        'address', my.address,
        'lat', my.lat,
        'lng', my.lng,
        'cover_image', my.cover_image,
        'is_active', my.is_active,
        'rating_avg', my.rating_avg,
        'rating_count', my.rating_count,
        'slot_minutes', my.slot_minutes,
        'courts_count', (select count(*) from public.courts c where c.turf_id = my.id and c.is_active),
        'min_price', (select min(base_price) from public.courts c where c.turf_id = my.id and c.is_active),
        'deals_count', (select count(*) from public.pricing_rules pr where pr.turf_id = my.id and pr.is_offpeak),
        'sports', array(
          select distinct cs.sport_id
          from public.courts c
          join public.court_sports cs on cs.court_id = c.id
          where c.turf_id = my.id and c.is_active
        ),
        'today_bookings', (
          select count(*) from b
          where b.turf_id = my.id and (b.starts_at at time zone 'Asia/Kolkata')::date = v_today
        )
      ) order by my.created_at desc)
      from my
    ), '[]'::jsonb),
    'upcoming_bookings', coalesce((
      select jsonb_agg(x order by x->>'starts_at') from (
        select jsonb_build_object(
          'id', bk.id,
          'code', bk.code,
          'turf_id', t.id,
          'turf_name', t.name,
          'court_name', c.name,
          'sport_id', bk.sport_id,
          'starts_at', bk.starts_at,
          'ends_at', bk.ends_at,
          'players_count', bk.players_count,
          'total_price', bk.total_price,
          'status', bk.status,
          'source', bk.source,
          'note', bk.note,
          'checked_in_at', bk.checked_in_at,
          'player_name', case when bk.source = 'app' then coalesce(nullif(pf.full_name, ''), 'Player') else coalesce(bk.note, 'Walk-in') end,
          'player_phone', case when bk.source = 'app' then coalesce(pf.phone, pf.email) else null end
        ) as x
        from public.bookings bk
        join public.turfs t on t.id = bk.turf_id and t.owner_id = v_uid
        join public.courts c on c.id = bk.court_id
        join public.profiles pf on pf.id = bk.user_id
        where bk.status in ('confirmed', 'checked_in') and bk.ends_at > now()
        order by bk.starts_at
        limit 10
      ) q
    ), '[]'::jsonb)
  ) into v_result
  from today, week, capacity;

  return v_result;
end $$;

-- 4. owner_list_bookings(p_from text, p_to text, p_turf_id uuid default null)
create or replace function public.owner_list_bookings(
  p_from text,
  p_to text,
  p_turf_id uuid default null
)
returns table (
  id uuid,
  code text,
  qr_token text,
  turf_id uuid,
  turf_name text,
  court_id uuid,
  court_name text,
  court_size text,
  sport_id text,
  starts_at timestamptz,
  ends_at timestamptz,
  players_count int,
  total_price int,
  status public.booking_status,
  source text,
  note text,
  checked_in_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz,
  player_name text,
  player_phone text
)
language sql stable security definer set search_path = public as $$
  select
    b.id,
    b.code,
    b.qr_token,
    t.id as turf_id,
    t.name as turf_name,
    c.id as court_id,
    c.name as court_name,
    c.size_label as court_size,
    b.sport_id,
    b.starts_at,
    b.ends_at,
    b.players_count,
    b.total_price,
    b.status,
    b.source,
    b.note,
    b.checked_in_at,
    b.cancelled_at,
    b.created_at,
    case when b.source = 'app' then coalesce(nullif(p.full_name, ''), 'Player') else coalesce(b.note, 'Walk-in') end as player_name,
    case when b.source = 'app' then coalesce(p.phone, p.email) else null end as player_phone
  from public.bookings b
  join public.turfs t on t.id = b.turf_id and t.owner_id = auth.uid()
  join public.courts c on c.id = b.court_id
  join public.profiles p on p.id = b.user_id
  where (b.starts_at at time zone 'Asia/Kolkata')::date >= coalesce(nullif(p_from, '')::date, (now() at time zone 'Asia/Kolkata')::date)
    and (b.starts_at at time zone 'Asia/Kolkata')::date <= coalesce(nullif(p_to, '')::date, (now() at time zone 'Asia/Kolkata')::date + 14)
    and (p_turf_id is null or b.turf_id = p_turf_id)
  order by b.starts_at asc, c.sort_order asc;
$$;

-- 5. owner_lookup_booking(p_query text) -> matches OwnerLookupBookingResult
create or replace function public.owner_lookup_booking(p_query text)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_in text := trim(coalesce(p_query, ''));
  v_parts text[];
  v_id uuid;
  v_b public.bookings;
  v_sig_valid boolean := true;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  if v_in like 'TFT1.%' then
    v_parts := string_to_array(v_in, '.');
    if array_length(v_parts, 1) <> 4 then raise exception 'INVALID_QR'; end if;
    begin
      v_id := v_parts[2]::uuid;
    exception when others then
      raise exception 'INVALID_QR';
    end;
    v_sig_valid := (sign_booking(v_id, v_parts[3]) = v_in);
    select * into v_b from public.bookings where id = v_id;
  else
    select * into v_b
    from public.bookings
    where code = upper(regexp_replace(v_in, '[^A-Za-z0-9]', '', 'g'));
  end if;

  if v_b.id is null or not is_turf_owner(v_b.turf_id) then
    raise exception 'BOOKING_NOT_FOUND';
  end if;

  return (
    select jsonb_build_object(
      'id', v_b.id,
      'code', v_b.code,
      'qr_token', v_b.qr_token,
      'signature_valid', v_sig_valid,
      'status', v_b.status,
      'source', v_b.source,
      'starts_at', v_b.starts_at,
      'ends_at', v_b.ends_at,
      'players_count', v_b.players_count,
      'total_price', v_b.total_price,
      'sport_id', v_b.sport_id,
      'note', v_b.note,
      'checked_in_at', v_b.checked_in_at,
      'turf', jsonb_build_object(
        'id', t.id,
        'name', t.name,
        'area', t.area,
        'address', t.address
      ),
      'court', jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'size_label', c.size_label,
        'max_players', c.max_players
      ),
      'player', jsonb_build_object(
        'id', p.id,
        'name', coalesce(nullif(p.full_name, ''), 'Player'),
        'phone', coalesce(p.phone, p.email),
        'skill_level', p.skill_level
      )
    )
    from public.turfs t, public.courts c, public.profiles p
    where t.id = v_b.turf_id and c.id = v_b.court_id and p.id = v_b.user_id
  );
end $$;

-- 6. owner_check_in(p_booking_id uuid, p_qr_token text default null)
create or replace function public.owner_check_in(
  p_booking_id uuid,
  p_qr_token text default null
)
returns public.bookings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_b public.bookings;
  v_turf text;
begin
  select * into v_b from public.bookings where id = p_booking_id for update;
  if not found or not is_turf_owner(v_b.turf_id) then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_b.status = 'cancelled' then raise exception 'NOT_CANCELLABLE'; end if;
  if v_b.checked_in_at is not null then raise exception 'ALREADY_CHECKED_IN'; end if;

  if p_qr_token is not null and p_qr_token like 'TFT1.%' then
    if sign_booking(v_b.id, v_b.code) <> trim(p_qr_token) then
      raise exception 'INVALID_QR';
    end if;
  end if;

  update public.bookings
  set status = case when ends_at < now() then 'completed'::public.booking_status else 'checked_in'::public.booking_status end,
      checked_in_at = now()
  where id = p_booking_id
  returning * into v_b;

  select name into v_turf from public.turfs where id = v_b.turf_id;
  if v_b.source = 'app' then
    perform notify(
      v_b.user_id,
      'checked_in',
      'Checked in ✅',
      'Welcome to ' || v_turf || '! Have a great game.',
      '/bookings/' || v_b.id
    );
  end if;
  return v_b;
end $$;

-- 7. owner_block_slots(...)
create or replace function public.owner_block_slots(
  p_court_id uuid,
  p_sport_id text,
  p_starts_at timestamptz,
  p_slots int,
  p_players int default 2,
  p_source text default 'walk_in',
  p_price int default null,
  p_note text default null
)
returns public.bookings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_court public.courts;
  v_turf public.turfs;
  v_end timestamptz;
  v_local timestamp;
  v_local_end timestamp;
  v_total int := 0;
  v_price int;
  v_code text;
  v_id uuid := gen_random_uuid();
  v_b public.bookings;
  v_sport text;
begin
  select * into v_court from public.courts where id = p_court_id and is_active;
  if not found or not is_turf_owner(v_court.turf_id) then raise exception 'COURT_NOT_FOUND'; end if;
  select * into v_turf from public.turfs where id = v_court.turf_id;
  if p_source not in ('walk_in', 'blocked') then p_source := 'walk_in'; end if;
  if p_slots is null or p_slots < 1 or p_slots > 24 then raise exception 'TOO_MANY_SLOTS'; end if;

  v_end := p_starts_at + make_interval(mins => v_turf.slot_minutes * p_slots);
  v_local := p_starts_at at time zone 'Asia/Kolkata';
  v_local_end := v_end at time zone 'Asia/Kolkata';

  if p_source = 'walk_in' then
    if p_price is not null then
      v_total := p_price;
    else
      for i in 0 .. p_slots - 1 loop
        select sp.price into v_price
        from slot_price(p_court_id, p_starts_at + make_interval(mins => v_turf.slot_minutes * i)) sp;
        v_total := v_total + coalesce(v_price, v_court.base_price);
      end loop;
    end if;
  end if;

  v_sport := coalesce(
    nullif(trim(p_sport_id), ''),
    (select sport_id from public.court_sports where court_id = p_court_id order by sport_id limit 1),
    'football'
  );
  v_code := gen_booking_code();

  begin
    insert into public.bookings (
      id, code, qr_token, user_id, turf_id, court_id, sport_id,
      starts_at, ends_at, players_count, total_price, note, source
    )
    values (
      v_id,
      v_code,
      sign_booking(v_id, v_code),
      auth.uid(),
      v_turf.id,
      p_court_id,
      v_sport,
      p_starts_at,
      v_end,
      greatest(coalesce(p_players, 1), 1),
      v_total,
      coalesce(nullif(trim(p_note), ''), case when p_source = 'walk_in' then 'Walk-in booking' else 'Blocked slot' end),
      p_source
    )
    returning * into v_b;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;
  return v_b;
end $$;

-- 8. Grants & PostgREST schema reload
revoke execute on function public.owner_save_turf(jsonb) from anon;
grant execute on function public.owner_save_turf(jsonb) to authenticated;

revoke execute on function public.owner_dashboard() from anon;
grant execute on function public.owner_dashboard() to authenticated;

revoke execute on function public.owner_list_bookings(text, text, uuid) from anon;
grant execute on function public.owner_list_bookings(text, text, uuid) to authenticated;

revoke execute on function public.owner_lookup_booking(text) from anon;
grant execute on function public.owner_lookup_booking(text) to authenticated;

revoke execute on function public.owner_check_in(uuid, text) from anon;
grant execute on function public.owner_check_in(uuid, text) to authenticated;

revoke execute on function public.owner_block_slots(uuid, text, timestamptz, int, int, text, int, text) from anon;
grant execute on function public.owner_block_slots(uuid, text, timestamptz, int, int, text, int, text) to authenticated;

notify pgrst, 'reload schema';


-- >>> 20261101000008_only_owner_registered_turfs.sql
-- =============================================================================
-- Remove all pre-seeded / non-owner turfs and enforce that ONLY turfs
-- registered via the Turf Owner Portal (owner_id IS NOT NULL) are shown.
-- =============================================================================
set search_path = public, extensions;

-- 1. Delete all dependent records and turfs that were pre-seeded (owner_id is null)
delete from public.open_games
where turf_id in (select id from public.turfs where owner_id is null);

delete from public.reviews
where turf_id in (select id from public.turfs where owner_id is null);

delete from public.bookings
where turf_id in (select id from public.turfs where owner_id is null);

delete from public.favourites
where turf_id in (select id from public.turfs where owner_id is null);

delete from public.turfs where owner_id is null;

-- 2. Update RLS policy on public.turfs so public/player queries only see
--    active turfs that belong to a registered owner (owner_id is not null),
--    while owners can still read their own turfs.
drop policy if exists "public read active turfs" on public.turfs;
create policy "public read active turfs" on public.turfs for select
  using ((is_active and owner_id is not null) or owner_id = auth.uid());

-- 3. Update nearby_turfs RPC to strictly require tf.owner_id is not null
create or replace function public.nearby_turfs(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_km double precision default 60,
  p_sport text default null,
  p_max_price int default null,
  p_search text default null,
  p_amenities text[] default null,
  p_offpeak_only boolean default false
)
returns table (
  id uuid, slug text, name text, area text, address text,
  lat double precision, lng double precision, cover_image text,
  rating_avg numeric, rating_count int, distance_km double precision,
  min_price int, offpeak_price int, sports text[], amenities text[],
  opens_at time, closes_at time
)
language sql stable security invoker set search_path = public, extensions as $$
  with t as (
    select tf.*,
      case when p_lat is null or p_lng is null then null
           else st_distance(tf.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) / 1000.0
      end as dist
    from public.turfs tf
    where tf.is_active
      and tf.owner_id is not null
      and exists (select 1 from public.courts c where c.turf_id = tf.id and c.is_active)
  ),
  offp as (
    select pr.turf_id, min(rule_price(c.base_price, pr.price, pr.discount_pct)) as price
    from public.pricing_rules pr
    join public.courts c on c.turf_id = pr.turf_id and c.is_active and (pr.court_id is null or pr.court_id = c.id)
    where pr.is_offpeak
    group by pr.turf_id
  )
  select
    t.id, t.slug, t.name, t.area, t.address, t.lat, t.lng, t.cover_image,
    t.rating_avg, t.rating_count,
    round(t.dist::numeric, 1)::double precision,
    (select min(c.base_price) from public.courts c where c.turf_id = t.id and c.is_active),
    o.price,
    array(select distinct cs.sport_id from public.courts c join public.court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active order by 1),
    array(select ta.amenity_id from public.turf_amenities ta where ta.turf_id = t.id order by 1),
    (select min(oh.open_time) from public.operating_hours oh where oh.turf_id = t.id),
    (select max(oh.close_time) from public.operating_hours oh where oh.turf_id = t.id)
  from t
  left join offp o on o.turf_id = t.id
  where (t.dist is null or t.dist <= p_radius_km)
    and (p_sport is null or exists (
          select 1 from public.courts c join public.court_sports cs on cs.court_id = c.id
          where c.turf_id = t.id and c.is_active and cs.sport_id = p_sport))
    and (p_max_price is null
         or exists (select 1 from public.courts c where c.turf_id = t.id and c.is_active and c.base_price <= p_max_price)
         or coalesce(o.price, 999999) <= p_max_price)
    and (p_search is null or p_search = '' or t.name ilike '%' || p_search || '%' or t.area ilike '%' || p_search || '%')
    and (p_amenities is null or cardinality(p_amenities) = 0
         or p_amenities <@ array(select ta.amenity_id from public.turf_amenities ta where ta.turf_id = t.id))
    and (not p_offpeak_only or o.price is not null)
  order by t.dist asc nulls last, t.rating_avg desc, t.name;
$$;

-- 4. Allow owners to cleanly delete their turf and its child records
create or replace function public.owner_delete_turf(p_turf_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_turf_owner(p_turf_id) then raise exception 'TURF_NOT_FOUND'; end if;
  delete from public.open_games where turf_id = p_turf_id;
  delete from public.reviews where turf_id = p_turf_id;
  delete from public.bookings where turf_id = p_turf_id;
  delete from public.favourites where turf_id = p_turf_id;
  delete from public.turfs where id = p_turf_id;
end $$;

notify pgrst, 'reload schema';
