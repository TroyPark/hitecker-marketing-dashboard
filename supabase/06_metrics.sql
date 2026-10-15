-- ============================================================
--  06. 커스텀 지표(열) — 광고 실적에 사용자가 열을 추가
--  SQL Editor 에 붙여넣고 실행. 여러 번 실행해도 안전.
--
--  정적 사이트라 브라우저에서 ALTER TABLE 을 못 한다.
--  그래서 커스텀 열 값은 ad_daily.extra(JSONB)에 담고,
--  열 목록은 metrics 마스터 테이블로 관리한다.
-- ============================================================

alter table ad_daily add column if not exists extra jsonb not null default '{}'::jsonb;

create table if not exists metrics (
  code       text primary key,           -- 영문·숫자·밑줄 (extra 안의 키)
  label      text not null,              -- 화면 표기명
  sort       int default 0,
  active     boolean not null default true,
  created_at timestamptz default now()
);

alter table metrics enable row level security;
grant select, insert, update, delete on metrics to authenticated;
revoke all on metrics from anon;

drop policy if exists metrics_read  on metrics;
drop policy if exists metrics_write on metrics;
create policy metrics_read  on metrics for select to authenticated using (true);
create policy metrics_write on metrics for all to authenticated
  using (public.is_editor()) with check (public.is_editor());
