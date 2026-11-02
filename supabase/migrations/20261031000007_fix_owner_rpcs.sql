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
