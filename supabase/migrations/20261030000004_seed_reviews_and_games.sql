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
