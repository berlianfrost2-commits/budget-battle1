-- BUDGET BATTLE — skema database + logika server (Supabase / PostgreSQL)
-- Jalankan sekali di Supabase: SQL Editor → tempel seluruh isi file → Run.
-- Semua aturan penting (waktu, budget, nilai, bot, ranking) berjalan di server.

create extension if not exists pgcrypto;

-- ================= TABEL =================
create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  avatar int not null default 0,
  xp int not null default 0,
  level int not null default 1,
  coins int not null default 100,
  pvp_wins int not null default 0,
  pvp_losses int not null default 0,
  bot_wins int not null default 0,
  bot_losses int not null default 0,
  rank_points int not null default 1000,
  is_admin boolean not null default false,
  banned boolean not null default false,
  last_seen timestamptz default now(),
  created_at timestamptz not null default now()
);

create table if not exists categories (
  id text primary key, name text not null, color text default '#888888',
  sort int default 0, active boolean not null default true
);

create table if not exists themes (
  id text primary key,
  category_id text not null references categories on delete cascade,
  budget bigint not null check (budget in (500000,1000000,10000000,100000000)),
  name text not null,
  required_tags text[] not null default '{}',
  difficulty int not null default 1,
  active boolean not null default true
);

create table if not exists items (
  id text primary key,
  category_id text not null references categories on delete cascade,
  budget bigint not null,
  name text not null,
  tag text not null,
  price bigint not null check (price > 0),
  quality int not null check (quality between 1 and 100),
  color text not null default '#cccccc',
  shape text not null default 'rect',
  image_url text,
  active boolean not null default true
);

create table if not exists settings (key text primary key, value jsonb not null);

create table if not exists matches (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('pvp','bot')),
  code text unique,
  category_id text not null references categories,
  budget bigint not null,
  theme_id text references themes,
  duration_sec int not null,
  status text not null default 'waiting' check (status in ('waiting','playing','finished','cancelled')),
  ranked boolean not null default false,
  p1 uuid not null references profiles,
  p2 uuid references profiles,
  bot_level text check (bot_level in ('easy','normal','hard','expert')),
  p1_build jsonb not null default '[]',
  p2_build jsonb not null default '[]',
  p1_score jsonb, p2_score jsonb,
  winner text,
  created_at timestamptz not null default now(),
  started_at timestamptz, ends_at timestamptz, finished_at timestamptz
);
create index if not exists matches_wait_idx on matches(status, mode, category_id, budget, duration_sec);
create index if not exists matches_p1_idx on matches(p1);
create index if not exists matches_p2_idx on matches(p2);

create table if not exists reports (
  id bigserial primary key, reporter uuid references profiles, target uuid references profiles,
  match_id uuid references matches, reason text, created_at timestamptz default now(), handled boolean default false
);

-- ================= KEAMANAN (RLS) =================
alter table profiles enable row level security;
alter table categories enable row level security;
alter table themes enable row level security;
alter table items enable row level security;
alter table settings enable row level security;
alter table matches enable row level security;
alter table reports enable row level security;

create or replace function is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

drop policy if exists p_profiles_read on profiles;
create policy p_profiles_read on profiles for select using (true);
drop policy if exists p_cat_read on categories;
create policy p_cat_read on categories for select using (active or is_admin());
drop policy if exists p_cat_admin on categories;
create policy p_cat_admin on categories for all using (is_admin()) with check (is_admin());
drop policy if exists p_theme_read on themes;
create policy p_theme_read on themes for select using (active or is_admin());
drop policy if exists p_theme_admin on themes;
create policy p_theme_admin on themes for all using (is_admin()) with check (is_admin());
drop policy if exists p_item_read on items;
create policy p_item_read on items for select using (active or is_admin());
drop policy if exists p_item_admin on items;
create policy p_item_admin on items for all using (is_admin()) with check (is_admin());
drop policy if exists p_settings_read on settings;
create policy p_settings_read on settings for select using (true);
drop policy if exists p_settings_admin on settings;
create policy p_settings_admin on settings for all using (is_admin()) with check (is_admin());
drop policy if exists p_reports_insert on reports;
create policy p_reports_insert on reports for insert with check (reporter = auth.uid());
drop policy if exists p_reports_admin on reports;
create policy p_reports_admin on reports for select using (is_admin());
-- matches: TIDAK ada akses langsung. Semua lewat fungsi di bawah (agar tidak bisa dicurangi).

-- ================= PROFIL OTOMATIS SAAT DAFTAR =================
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare uname text := coalesce(nullif(trim(new.raw_user_meta_data->>'username'),''), 'Pemain');
begin
  if exists (select 1 from profiles where username = uname) then
    uname := uname || '_' || substr(new.id::text, 1, 4);
  end if;
  insert into profiles(id, username) values (new.id, uname);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create or replace function update_profile(p_username text, p_avatar int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(trim(p_username)) < 3 or length(p_username) > 20 then raise exception 'Username 3-20 huruf'; end if;
  update profiles set username = trim(p_username), avatar = greatest(0, least(p_avatar, 11)), last_seen = now()
  where id = auth.uid();
end $$;

-- ================= PENILAIAN =================
-- build = [{"item":"id","x":0,"y":0,"color":"#hex"}]
create or replace function score_build(p_build jsonb, p_theme text, p_budget bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  req text[]; n int; uniq int; tags int; colors int; spent bigint; q numeric; zones int; covered int;
  s_cre int; s_aes int; s_theme int; s_eff int; s_comp int; u numeric;
begin
  select required_tags into req from themes where id = p_theme;
  req := coalesce(req, '{}');
  with b as (
    select e->>'item' item_id, coalesce(e->>'color','') color,
           coalesce((e->>'x')::int,0) x, coalesce((e->>'y')::int,0) y
    from jsonb_array_elements(coalesce(p_build,'[]')) e),
  j as (select b.*, i.price, i.quality, i.tag from b join items i on i.id = b.item_id)
  select count(*), count(distinct item_id), count(distinct tag), count(distinct color),
         coalesce(sum(price),0), coalesce(avg(quality),0),
         count(distinct (x/3)::text || '-' || (y/3)::text),
         (select count(*) from unnest(req) t where t in (select tag from j))
  into n, uniq, tags, colors, spent, q, zones, covered from j;

  s_cre := least(30, round(uniq*1.5 + tags*2 + least(colors,6)))::int;
  s_aes := round(25 * (q/100.0) * least(1, 0.4 + zones/10.0))::int;
  s_theme := case when array_length(req,1) is null then 20 else round(20.0*covered/array_length(req,1))::int end;
  u := spent::numeric / p_budget;
  s_eff := case when n = 0 or u > 1 then 0 else round(15 * greatest(0, 1 - abs(u - 0.9)/0.9))::int end;
  s_comp := round(10 * least(1, n/8.0) * (0.5 + 0.5 * case when array_length(req,1) is null then 1 else covered::numeric/array_length(req,1) end))::int;
  if n = 0 then s_cre := 0; s_aes := 0; s_comp := 0; end if;
  return jsonb_build_object('kreativitas',s_cre,'estetika',s_aes,'tema',s_theme,'efisiensi',s_eff,
    'kelengkapan',s_comp,'total',s_cre+s_aes+s_theme+s_eff+s_comp,'spent',spent,'items',n,
    'tag_terpenuhi',covered,'tag_wajib',coalesce(array_length(req,1),0));
end $$;

-- ================= BOT (berjalan di server) =================
create or replace function bot_build(p_cat text, p_budget bigint, p_theme text, p_level text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  req text[]; target numeric; noise numeric; cover boolean; variety boolean; max_n int;
  spent bigint := 0; used_tags text[] := '{}'; used_items text[] := '{}';
  build jsonb := '[]'; k int := 0; it record;
  palette text[] := array['#F43F5E','#3B82F6','#22C55E','#F59E0B','#A855F7','#14B8A6','#FFFFFF','#111827'];
begin
  select required_tags into req from themes where id = p_theme;
  req := coalesce(req,'{}');
  case p_level
    when 'easy'   then target := 0.45 + random()*0.25; noise := 1.0; cover := false; variety := false; max_n := 6;
    when 'normal' then target := 0.80; noise := 0.5; cover := false; variety := true; max_n := 9;
    when 'hard'   then target := 0.90; noise := 0.2; cover := true; variety := true; max_n := 12;
    else               target := 0.95; noise := 0.0; cover := true; variety := true; max_n := 16;
  end case;
  loop
    exit when k >= max_n;
    select * into it from items i
    where i.category_id = p_cat and i.budget = p_budget and i.active
      and spent + i.price <= floor(p_budget * target)
      and (not variety or not (i.id = any(used_items)))
    order by
      case when cover and i.tag = any(req) and not (i.tag = any(used_tags)) then 0 else 1 end,
      case when variety and not (i.tag = any(used_tags)) then 0 else 1 end,
      (i.quality::numeric / sqrt(i.price)) * (1 + noise * (random() - 0.5) * 2) desc
    limit 1;
    exit when not found;
    spent := spent + it.price;
    used_tags := used_tags || it.tag;
    used_items := used_items || it.id;
    build := build || jsonb_build_object('item', it.id,
      'x', (k*5 + (k/12)) % 12, 'y', (k*3 + k/4) % 8,
      'color', case when p_level in ('hard','expert') then palette[1 + (k % array_length(palette,1))] else it.color end);
    k := k + 1;
  end loop;
  return build;
end $$;

-- ================= MATCH =================
create or replace function _start_match(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare m matches; th text;
begin
  select * into m from matches where id = p_id;
  select id into th from themes where category_id = m.category_id and budget = m.budget and active order by random() limit 1;
  if th is null then raise exception 'Belum ada tema untuk kategori & budget ini'; end if;
  update matches set theme_id = th, status = 'playing',
    started_at = now() + interval '5 seconds',
    ends_at = now() + interval '5 seconds' + make_interval(secs => duration_sec)
  where id = p_id;
end $$;

create or replace function _check_params(p_cat text, p_budget bigint, p_dur int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  if (select banned from profiles where id = auth.uid()) then raise exception 'Akun diblokir admin'; end if;
  if p_budget not in (500000,1000000,10000000,100000000) then raise exception 'Budget tidak valid'; end if;
  if not exists (select 1 from categories where id = p_cat and active) then raise exception 'Kategori tidak aktif'; end if;
  if not exists (select 1 from jsonb_array_elements_text((select value from settings where key='durations')) d where d::int = p_dur)
    then raise exception 'Durasi tidak valid'; end if;
end $$;

create or replace function queue_pvp(p_cat text, p_budget bigint, p_dur int) returns uuid
language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  perform _check_params(p_cat, p_budget, p_dur);
  -- batalkan antrean lama milik sendiri
  update matches set status='cancelled' where p1 = auth.uid() and status='waiting';
  select id into mid from matches
   where mode='pvp' and status='waiting' and code is null and category_id=p_cat and budget=p_budget
     and duration_sec=p_dur and p1 <> auth.uid() and created_at > now() - interval '10 minutes'
   order by created_at limit 1 for update skip locked;
  if mid is not null then
    update matches set p2 = auth.uid() where id = mid;
    perform _start_match(mid);
    return mid;
  end if;
  insert into matches(mode, category_id, budget, duration_sec, p1, ranked)
  values ('pvp', p_cat, p_budget, p_dur, auth.uid(), true) returning id into mid;
  return mid;
end $$;

create or replace function create_room(p_cat text, p_budget bigint, p_dur int) returns uuid
language plpgsql security definer set search_path = public as $$
declare mid uuid; c text;
begin
  perform _check_params(p_cat, p_budget, p_dur);
  update matches set status='cancelled' where p1 = auth.uid() and status='waiting';
  loop
    c := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from matches where code = c);
  end loop;
  insert into matches(mode, code, category_id, budget, duration_sec, p1, ranked)
  values ('pvp', c, p_cat, p_budget, p_dur, auth.uid(), false) returning id into mid;
  return mid;
end $$;

create or replace function join_room(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  select id into mid from matches where code = upper(trim(p_code)) and status='waiting' and p1 <> auth.uid() for update;
  if mid is null then raise exception 'Kode room tidak ditemukan atau sudah penuh'; end if;
  update matches set p2 = auth.uid() where id = mid;
  perform _start_match(mid);
  return mid;
end $$;

create or replace function start_bot(p_cat text, p_budget bigint, p_dur int, p_level text) returns uuid
language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  perform _check_params(p_cat, p_budget, p_dur);
  if p_level not in ('easy','normal','hard','expert') then raise exception 'Level bot tidak valid'; end if;
  insert into matches(mode, category_id, budget, duration_sec, p1, bot_level, ranked)
  values ('bot', p_cat, p_budget, p_dur, auth.uid(), p_level, false) returning id into mid;
  perform _start_match(mid);
  return mid;
end $$;

create or replace function cancel_match(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update matches set status='cancelled' where id = p_id and p1 = auth.uid() and status = 'waiting';
end $$;

-- simpan karya (dipanggil berkala = autosave + reconnect). Divalidasi penuh di server.
create or replace function save_build(p_id uuid, p_build jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches; total bigint; bad int; n int;
begin
  select * into m from matches where id = p_id;
  if m.id is null or auth.uid() not in (m.p1, coalesce(m.p2, m.p1)) then raise exception 'Bukan pertandinganmu'; end if;
  if m.status <> 'playing' then raise exception 'Pertandingan tidak sedang berjalan'; end if;
  if now() < m.started_at then raise exception 'Countdown belum selesai'; end if;
  if now() > m.ends_at + interval '3 seconds' then raise exception 'Waktu habis, hasil sudah dikunci'; end if;
  if jsonb_typeof(p_build) <> 'array' then raise exception 'Format salah'; end if;
  n := jsonb_array_length(p_build);
  if n > 60 then raise exception 'Maksimal 60 objek'; end if;
  select count(*) into bad from jsonb_array_elements(p_build) e
    left join items i on i.id = e->>'item' and i.active and i.category_id = m.category_id and i.budget = m.budget
   where i.id is null or coalesce((e->>'x')::int,-1) not between 0 and 11 or coalesce((e->>'y')::int,-1) not between 0 and 7;
  if bad > 0 then raise exception 'Ada objek tidak valid'; end if;
  select coalesce(sum(i.price),0) into total from jsonb_array_elements(p_build) e join items i on i.id = e->>'item';
  if total > m.budget then raise exception 'Pengeluaran melebihi budget'; end if;
  if auth.uid() = m.p1 then update matches set p1_build = p_build where id = p_id;
  else update matches set p2_build = p_build where id = p_id; end if;
  update profiles set last_seen = now() where id = auth.uid();
  return jsonb_build_object('spent', total, 'items', n);
end $$;

create or replace function _reward(p_user uuid, p_win boolean, p_draw boolean, p_mode text, p_ranked boolean) returns void
language plpgsql security definer set search_path = public as $$
declare gxp int; gcoin int;
begin
  gxp := case when p_win then 60 when p_draw then 35 else 25 end;
  gcoin := case when p_win then 30 when p_draw then 15 else 10 end;
  if p_mode = 'bot' then gxp := gxp / 2; gcoin := gcoin / 2; end if;
  update profiles set xp = xp + gxp, coins = coins + gcoin, level = 1 + (xp + gxp) / 200,
    pvp_wins = pvp_wins + case when p_mode='pvp' and p_win then 1 else 0 end,
    pvp_losses = pvp_losses + case when p_mode='pvp' and not p_win and not p_draw then 1 else 0 end,
    bot_wins = bot_wins + case when p_mode='bot' and p_win then 1 else 0 end,
    bot_losses = bot_losses + case when p_mode='bot' and not p_win and not p_draw then 1 else 0 end,
    rank_points = case when p_mode='pvp' and p_ranked then greatest(0, rank_points + case when p_win then 25 when p_draw then 0 else -20 end) else rank_points end
  where id = p_user;
end $$;

-- akhiri pertandingan: hanya bisa setelah waktu server habis. Aman dipanggil berkali-kali.
create or replace function finish_match(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches; s1 jsonb; s2 jsonb; w text; t1 int; t2 int;
begin
  select * into m from matches where id = p_id for update;
  if m.id is null then raise exception 'Tidak ditemukan'; end if;
  if auth.uid() not in (m.p1, coalesce(m.p2, m.p1)) then raise exception 'Bukan pertandinganmu'; end if;
  if m.status = 'playing' and now() >= m.ends_at then
    if m.mode = 'bot' then
      m.p2_build := bot_build(m.category_id, m.budget, m.theme_id, m.bot_level);
    end if;
    s1 := score_build(m.p1_build, m.theme_id, m.budget);
    s2 := score_build(m.p2_build, m.theme_id, m.budget);
    t1 := (s1->>'total')::int; t2 := (s2->>'total')::int;
    -- seri dipecah dengan sisa budget lebih besar
    if t1 = t2 then
      if (s1->>'spent')::bigint < (s2->>'spent')::bigint then w := 'p1';
      elsif (s1->>'spent')::bigint > (s2->>'spent')::bigint then w := 'p2';
      else w := 'draw'; end if;
    elsif t1 > t2 then w := 'p1'; else w := 'p2'; end if;
    update matches set status='finished', finished_at=now(), p2_build=m.p2_build,
      p1_score=s1, p2_score=s2, winner=w where id = p_id;
    perform _reward(m.p1, w='p1', w='draw', m.mode, m.ranked);
    if m.mode = 'pvp' and m.p2 is not null then perform _reward(m.p2, w='p2', w='draw', m.mode, m.ranked); end if;
  end if;
  return get_match(p_id);
end $$;

-- data pertandingan untuk pemain. Karya lawan disembunyikan sampai selesai.
create or replace function get_match(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m matches; me text; opp uuid; o profiles; meprof profiles; th themes; c categories;
begin
  select * into m from matches where id = p_id;
  if m.id is null then raise exception 'Tidak ditemukan'; end if;
  if auth.uid() = m.p1 then me := 'p1'; opp := m.p2;
  elsif auth.uid() = m.p2 then me := 'p2'; opp := m.p1;
  else raise exception 'Bukan pertandinganmu'; end if;
  select * into o from profiles where id = opp;
  select * into meprof from profiles where id = auth.uid();
  select * into th from themes where id = m.theme_id;
  select * into c from categories where id = m.category_id;
  update profiles set last_seen = now() where id = auth.uid();
  return jsonb_build_object(
    'id', m.id, 'mode', m.mode, 'code', m.code, 'status', m.status, 'ranked', m.ranked,
    'category_id', m.category_id, 'category_name', c.name, 'budget', m.budget,
    'theme_id', m.theme_id, 'theme_name', th.name, 'required_tags', to_jsonb(th.required_tags),
    'duration_sec', m.duration_sec, 'bot_level', m.bot_level,
    'server_now', extract(epoch from now()), 'started_at', extract(epoch from m.started_at),
    'ends_at', extract(epoch from m.ends_at), 'me', me, 'winner', m.winner,
    'me_name', meprof.username, 'me_avatar', meprof.avatar,
    'opp_name', case when m.mode='bot' then 'BOT ' || upper(coalesce(m.bot_level,'')) else o.username end,
    'opp_avatar', case when m.mode='bot' then 99 else o.avatar end,
    'opp_online', case when m.mode='bot' then true else coalesce(o.last_seen > now() - interval '15 seconds', false) end,
    'my_build', case when me='p1' then m.p1_build else m.p2_build end,
    'opp_build', case when m.status='finished' then (case when me='p1' then m.p2_build else m.p1_build end) else '[]'::jsonb end,
    'opp_count', jsonb_array_length(case when me='p1' then m.p2_build else m.p1_build end),
    'my_score', case when me='p1' then m.p1_score else m.p2_score end,
    'opp_score', case when me='p1' then m.p2_score else m.p1_score end
  );
end $$;

create or replace function my_active_match() returns uuid language sql stable security definer set search_path = public as $$
  select id from matches where (p1 = auth.uid() or p2 = auth.uid()) and status in ('waiting','playing')
   and coalesce(ends_at, now() + interval '1 hour') > now() - interval '30 seconds'
  order by created_at desc limit 1
$$;

create or replace function my_history() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'finished_at' desc), '[]'::jsonb) from (
    select jsonb_build_object('id', m.id, 'mode', m.mode, 'category', c.name, 'theme', t.name, 'budget', m.budget,
      'finished_at', m.finished_at,
      'result', case when m.winner='draw' then 'SERI'
                     when (m.winner='p1' and m.p1=auth.uid()) or (m.winner='p2' and m.p2=auth.uid()) then 'MENANG' else 'KALAH' end,
      'my_total', case when m.p1=auth.uid() then m.p1_score->>'total' else m.p2_score->>'total' end,
      'opp_total', case when m.p1=auth.uid() then m.p2_score->>'total' else m.p1_score->>'total' end,
      'opponent', case when m.mode='bot' then 'BOT ' || upper(m.bot_level) else
        (select username from profiles where id = case when m.p1=auth.uid() then m.p2 else m.p1 end) end) x
    from matches m join categories c on c.id=m.category_id left join themes t on t.id=m.theme_id
    where (m.p1 = auth.uid() or m.p2 = auth.uid()) and m.status='finished'
    order by m.finished_at desc limit 50) s
$$;

-- papan peringkat: global (rank point ranked PvP), weekly/monthly (kemenangan PvP), per kategori
create or replace function leaderboard(p_kind text, p_category text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r), '[]'::jsonb) from (
    select * from (
      select p.username, p.avatar, p.level, p.rank_points,
        case when p_kind = 'global' then p.rank_points else (
          select count(*) from matches m
          where m.mode='pvp' and m.status='finished'
            and ((m.winner='p1' and m.p1=p.id) or (m.winner='p2' and m.p2=p.id))
            and (p_category is null or m.category_id = p_category)
            and m.finished_at > now() - case p_kind when 'weekly' then interval '7 days'
                                                     when 'monthly' then interval '30 days' else interval '100 years' end)
        end as score
      from profiles p where not p.banned) z
    where score > 0 order by score desc limit 50) r
$$;

-- ================= ADMIN =================
create or replace function admin_ban(p_user uuid, p_ban boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Khusus admin'; end if;
  update profiles set banned = p_ban where id = p_user;
end $$;

-- izin eksekusi
revoke all on function _start_match(uuid), _reward(uuid,boolean,boolean,text,boolean), bot_build(text,bigint,text,text), _check_params(text,bigint,int), handle_new_user() from public, anon, authenticated;
revoke execute on function score_build(jsonb,text,bigint) from anon;
