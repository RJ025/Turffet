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
