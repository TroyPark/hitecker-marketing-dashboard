-- ============================================================
--  07. 사업 실적 커스텀 지표(열) — 사업별
--  SQL Editor 에 붙여넣고 실행. 여러 번 실행해도 안전.
--  (06 의 광고용 metrics 와 같은 구조, business_daily 용)
-- ============================================================

alter table business_daily add column if not exists extra jsonb not null default '{}'::jsonb;

create table if not exists biz_metrics (
  code       text not null,
  label      text not null,
  brand      text references brands(code) on update cascade,
  sort       int default 0,
  active     boolean not null default true,
  created_at timestamptz default now()
);
alter table biz_metrics add column if not exists brand text references brands(code) on update cascade;
delete from biz_metrics where brand is null;
alter table biz_metrics drop constraint if exists biz_metrics_pkey;
alter table biz_metrics add primary key (brand, code);

alter table biz_metrics enable row level security;
grant select, insert, update, delete on biz_metrics to authenticated;
revoke all on biz_metrics from anon;

drop policy if exists biz_metrics_read  on biz_metrics;
drop policy if exists biz_metrics_write on biz_metrics;
create policy biz_metrics_read  on biz_metrics for select to authenticated using (true);
create policy biz_metrics_write on biz_metrics for all to authenticated
  using (public.is_editor()) with check (public.is_editor());
