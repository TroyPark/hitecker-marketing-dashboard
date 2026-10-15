-- ============================================================
--  06. 커스텀 지표(열) — 사업별로 광고 실적에 열 추가
--  SQL Editor 에 붙여넣고 실행. 여러 번 실행해도 안전.
--
--  정적 사이트라 브라우저에서 ALTER TABLE 을 못 한다.
--  커스텀 열 값은 ad_daily.extra(JSONB)에 담고,
--  열 목록은 metrics 마스터로 관리한다. 지표는 '사업별'로 다르다.
-- ============================================================

alter table ad_daily add column if not exists extra jsonb not null default '{}'::jsonb;

create table if not exists metrics (
  code       text not null,              -- extra 안의 키 (영문·숫자·밑줄)
  label      text not null,              -- 화면 표기명
  brand      text references brands(code) on update cascade,
  sort       int default 0,
  active     boolean not null default true,
  created_at timestamptz default now()
);

-- 이전(전역) 버전에서 올라온 경우를 대비: brand 컬럼 보강 후 (brand, code) 로 PK 재설정
alter table metrics add column if not exists brand text references brands(code) on update cascade;
delete from metrics where brand is null;         -- 사업 없는 옛 지표는 제거(테스트 데이터)
alter table metrics drop constraint if exists metrics_pkey;
alter table metrics add primary key (brand, code);

alter table metrics enable row level security;
grant select, insert, update, delete on metrics to authenticated;
revoke all on metrics from anon;

drop policy if exists metrics_read  on metrics;
drop policy if exists metrics_write on metrics;
create policy metrics_read  on metrics for select to authenticated using (true);
create policy metrics_write on metrics for all to authenticated
  using (public.is_editor()) with check (public.is_editor());
