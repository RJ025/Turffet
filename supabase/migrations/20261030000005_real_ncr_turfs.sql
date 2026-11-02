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
