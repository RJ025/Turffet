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
