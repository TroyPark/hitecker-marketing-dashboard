-- ============================================================
--  04. 사업 · 매체 코드 변경 허용
--  SQL Editor 에 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
--
--  brands.code / platforms.code 는 실적 테이블이 참조하는 기본키다.
--  그냥 바꾸면 외래키 위반이 난다. ON UPDATE CASCADE 를 걸어
--  코드를 바꾸면 해당 사업·매체의 모든 행이 함께 따라오게 한다.
-- ============================================================

-- ad_daily
alter table ad_daily drop constraint if exists ad_daily_brand_fkey;
alter table ad_daily add constraint ad_daily_brand_fkey
  foreign key (brand) references brands(code) on update cascade;

alter table ad_daily drop constraint if exists ad_daily_platform_fkey;
alter table ad_daily add constraint ad_daily_platform_fkey
  foreign key (platform) references platforms(code) on update cascade;

-- business_daily
alter table business_daily drop constraint if exists business_daily_brand_fkey;
alter table business_daily add constraint business_daily_brand_fkey
  foreign key (brand) references brands(code) on update cascade;

-- budgets
alter table budgets drop constraint if exists budgets_brand_fkey;
alter table budgets add constraint budgets_brand_fkey
  foreign key (brand) references brands(code) on update cascade;

alter table budgets drop constraint if exists budgets_platform_fkey;
alter table budgets add constraint budgets_platform_fkey
  foreign key (platform) references platforms(code) on update cascade;

-- 확인: 아래 다섯 줄이 모두 CASCADE 여야 정상
select tc.table_name, kcu.column_name, rc.update_rule
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and kcu.column_name in ('brand', 'platform')
order by tc.table_name, kcu.column_name;
