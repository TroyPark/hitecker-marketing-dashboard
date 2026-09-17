-- ============================================================
--  03. 환불 분리
--  SQL Editor 에 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
--
--  매출(revenue) 과 환불(refund) 을 따로 넣는다.
--  최종매출은 저장하지 않는다 — revenue - refund 로 언제나 계산한다.
--  (환불이 나중에 정정되면 저장해 둔 최종매출이 어긋나기 때문)
-- ============================================================

alter table business_daily
  add column if not exists refund numeric not null default 0;

-- 음수로 들어오는 실수를 막는다
alter table business_daily drop constraint if exists business_daily_refund_nonneg;
alter table business_daily add constraint business_daily_refund_nonneg check (refund >= 0);

-- 조회용 뷰: 최종매출과 환불률을 여기서 계산한다
create or replace view v_business_daily as
select
  date, brand, signups, orders, revenue, refund,
  revenue - refund                    as net_revenue,
  refund / nullif(revenue, 0)         as refund_rate,
  (revenue - refund) / nullif(orders, 0) as aov
from business_daily;

alter view v_business_daily set (security_invoker = on);
grant select on v_business_daily to authenticated;

-- 사업 단위 합산 뷰도 최종매출 기준으로 바꾼다
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
  coalesce(b.refund, 0)      as refund,
  coalesce(b.revenue, 0) - coalesce(b.refund, 0) as net_revenue,
  a.adcost / nullif(b.orders, 0) as cac,
  (coalesce(b.revenue, 0) - coalesce(b.refund, 0)) / nullif(a.adcost, 0) as roas
from (
  select date, brand, sum(impressions) impressions, sum(clicks) clicks,
         sum(adcost) adcost, sum(conversions) conversions
  from ad_daily group by date, brand
) a
full join business_daily b on a.date = b.date and a.brand = b.brand;

alter view v_brand_daily set (security_invoker = on);
grant select on v_brand_daily to authenticated;

-- 확인: 결과가 0행이어야 정상
select c.relname as "security_invoker 꺼진 뷰"
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v'
  and coalesce((select option_value from pg_options_to_table(c.reloptions)
                where option_name = 'security_invoker'), 'false') <> 'true';
