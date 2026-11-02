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
