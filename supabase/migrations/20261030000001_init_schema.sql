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
