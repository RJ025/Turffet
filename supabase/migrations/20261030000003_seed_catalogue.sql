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
