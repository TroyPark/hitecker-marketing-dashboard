-- ============================================================
--  하이테커 마케팅 대시보드 · Supabase 스키마
--  Supabase 대시보드 > SQL Editor 에 통째로 붙여넣고 실행하세요.
--  여러 번 실행해도 안전합니다 (if not exists / on conflict).
-- ============================================================

-- ── 1. 마스터 (엑셀 SQL값 시트) ──────────────────────────────
create table if not exists brands (
  code    text primary key,
  name_ko text not null,
  sort    int  default 0
);

create table if not exists platforms (
  code          text primary key,
  name_ko       text not null,
  channel       text,
  campaign_type text,
  sort          int default 0
);

insert into brands (code, name_ko, sort) values
  ('Learnershigh', '내일하이', 1),
  ('KFO',          'KFO',     2),
  ('Oracle',       '오라클',   3),
  ('Knewdeal',     'K-뉴딜',   4)
on conflict (code) do update set name_ko = excluded.name_ko, sort = excluded.sort;

insert into platforms (code, name_ko, channel, campaign_type, sort) values
  ('Naver_brand',         '네이버 브랜드검색', 'Naver',  'brand',         1),
  ('Naver_sa',            '네이버 파워링크',   'Naver',  'sa',            2),
  ('Naver_powercontents', '네이버 파워컨텐츠', 'Naver',  'powercontents', 3),
  ('Google_SA',           '구글 검색광고',     'Google', 'SA',            4),
  ('Google_display',      '구글 디스플레이',   'Google', 'display',       5),
  ('Meta_sponsored',      '메타 스폰서드',     'Meta',   'sponsored',     6),
  ('Google_demandGen',    '구글 디멘드젠',     'Google', 'demandGen',     7),
  ('Google_pmax',         '구글 P-Max',       'Google', 'pmax',          8)
on conflict (code) do update set name_ko = excluded.name_ko, sort = excluded.sort;

-- ── 2. 광고 실적 ─────────────────────────────────────────────
-- 실측치 5개만 저장한다. CTR/CPC/CPA/ROAS 는 조회 시 계산한다
-- (일별 파생지표를 평균내면 틀린 값이 나오기 때문).
create table if not exists ad_daily (
  date        date   not null,
  brand       text   not null references brands(code),
  platform    text   not null references platforms(code),
  impressions bigint  default 0,
  clicks      bigint  default 0,
  adcost      numeric default 0,
  conversions numeric default 0,
  conv_value  numeric default 0,
  updated_at  timestamptz default now(),
  updated_by  uuid references auth.users(id),
  primary key (date, brand, platform)      -- 재업로드 시 upsert 키
);
create index if not exists ad_daily_brand_date_idx on ad_daily (brand, date desc);

-- ── 3. 사업 실적 (admin의 실제 가입 / 결제 / 매출) ───────────
create table if not exists business_daily (
  date       date not null,
  brand      text not null references brands(code),
  signups    int     default 0,
  orders     int     default 0,
  revenue    numeric default 0,
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  primary key (date, brand)
);
create index if not exists business_daily_brand_date_idx on business_daily (brand, date desc);

-- ── 4. 월별 예산 (매체 단위) ─────────────────────────────────
-- 사업 예산은 따로 두지 않는다. 매체별 금액의 합이 곧 사업 예산이다.
create table if not exists budgets (
  month      date not null,                 -- 항상 매월 1일로 정규화해서 넣는다
  brand      text not null references brands(code),
  platform   text not null references platforms(code),
  amount     numeric not null default 0,
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  primary key (month, brand, platform)
);
create index if not exists budgets_brand_month_idx on budgets (brand, month desc);

-- ── 5. 업로드 이력 ───────────────────────────────────────────
create table if not exists upload_logs (
  id          bigserial primary key,
  uploaded_at timestamptz default now(),
  user_id     uuid references auth.users(id),
  filename    text,
  brand       text,
  row_count   int,
  note        text
);

-- ── 6. 사용자 프로필 / 역할 ──────────────────────────────────
create table if not exists profiles (
  id    uuid primary key references auth.users(id) on delete cascade,
  email text,
  role  text not null default 'viewer' check (role in ('admin','editor','viewer')),
  created_at timestamptz default now()
);

-- 가입 즉시 viewer 프로필 생성 (권한 승격은 admin이 수동으로)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, role) values (new.id, new.email, 'viewer')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ── 7. 조회용 뷰 (파생지표는 전부 여기서 계산) ───────────────
-- 주의: 뷰는 기본적으로 "소유자 권한"으로 돌아서 밑에 깔린 테이블의 RLS를 그냥 통과한다.
-- 아래에서 security_invoker 를 켜 두지 않으면 RLS를 아무리 걸어도 뷰로 다 새어 나간다.
create or replace view v_ad_daily as
select
  date, brand, platform, impressions, clicks, adcost, conversions, conv_value,
  clicks::numeric   / nullif(impressions, 0) as ctr,
  adcost            / nullif(clicks, 0)      as cpc,
  adcost            / nullif(conversions, 0) as cpa,
  conv_value        / nullif(adcost, 0)      as roas_ad
from ad_daily;

create or replace view v_brand_daily as
select
  coalesce(a.date, b.date)   as date,
  coalesce(a.brand, b.brand) as brand,
  coalesce(a.impressions, 0) as impressions,
  coalesce(a.clicks, 0)      as clicks,
  coalesce(a.adcost, 0)      as adcost,
  coalesce(a.conversions, 0) as conversions,
  coalesce(b.signups, 0)     as signups,
  coalesce(b.orders, 0)      as orders,
  coalesce(b.revenue, 0)     as revenue,
  a.adcost  / nullif(b.orders, 0)  as cac,
  b.revenue / nullif(a.adcost, 0)  as roas
from (
  select date, brand, sum(impressions) impressions, sum(clicks) clicks,
         sum(adcost) adcost, sum(conversions) conversions
  from ad_daily group by date, brand
) a
full join business_daily b on a.date = b.date and a.brand = b.brand;

-- 뷰를 "호출자 권한"으로 돌린다 → 뷰에도 RLS가 그대로 적용된다
alter view v_ad_daily    set (security_invoker = on);
alter view v_brand_daily set (security_invoker = on);

-- ── 8. RLS ───────────────────────────────────────────────────
-- GitHub Pages 는 정적 호스팅이라 anon key 가 번들에 노출된다.
-- 데이터를 지키는 건 오직 이 정책들이다. 반드시 켜 둘 것.
alter table ad_daily       enable row level security;
alter table business_daily enable row level security;
alter table budgets        enable row level security;
alter table upload_logs    enable row level security;
alter table profiles       enable row level security;
alter table brands         enable row level security;
alter table platforms      enable row level security;

create or replace function public.is_editor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('admin','editor'));
$$;

do $$
declare t text;
begin
  foreach t in array array['ad_daily','business_daily','budgets','upload_logs','brands','platforms'] loop
    execute format('drop policy if exists %I_read on %I', t, t);
    execute format('drop policy if exists %I_write on %I', t, t);
    execute format(
      'create policy %I_read on %I for select to authenticated using (true)', t, t);
    execute format(
      'create policy %I_write on %I for all to authenticated using (public.is_editor()) with check (public.is_editor())', t, t);
  end loop;
end $$;

drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for select to authenticated
  using (id = auth.uid() or public.is_editor());
-- profiles 에는 insert/update/delete 정책을 일부러 만들지 않는다.
-- 역할 승격은 SQL Editor 나 service_role 로만 가능하다 (스스로 admin 이 될 수 없다).

-- ── 9. 권한 최소화 ───────────────────────────────────────────
-- Supabase 는 public 스키마의 테이블에 anon / authenticated 권한을 자동으로 붙인다.
-- 비로그인(anon)은 이 앱에서 아무것도 볼 필요가 없으므로 권한 자체를 회수한다.
-- (RLS 로도 막히지만, 권한까지 없애 두면 정책 실수 한 번으로 새어 나가지 않는다)
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all routines  in schema public from anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on routines  from anon;

-- 로그인 사용자에게 필요한 만큼만 부여한다 (실제 통제는 위의 RLS 정책)
grant usage on schema public to authenticated;
grant select, insert, update, delete on
  ad_daily, business_daily, budgets, upload_logs to authenticated;
grant select on brands, platforms, profiles, v_ad_daily, v_brand_daily to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ── 10. 확인 ─────────────────────────────────────────────────
-- RLS 가 안 켜진 public 테이블이 있으면 여기서 잡힌다. 결과가 0행이어야 정상.
select relname as "RLS 꺼진 테이블"
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

-- 소유자 권한으로 도는 뷰(RLS 우회)가 있으면 여기서 잡힌다. 결과가 0행이어야 정상.
select c.relname as "security_invoker 꺼진 뷰"
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v'
  and coalesce((select option_value from pg_options_to_table(c.reloptions)
                where option_name = 'security_invoker'), 'false') <> 'true';
