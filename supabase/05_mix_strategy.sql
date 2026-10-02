-- ============================================================
--  05. 미디어 믹스 전략 (LLM 어시스턴트 결과 저장)
--  SQL Editor 에 붙여넣고 실행. 여러 번 실행해도 안전.
-- ============================================================

create table if not exists mix_strategy (
  month      date not null,            -- 매월 1일로 정규화
  brand      text not null references brands(code) on update cascade,
  strategy   text not null default '',
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  primary key (month, brand)
);

alter table mix_strategy enable row level security;

grant select, insert, update, delete on mix_strategy to authenticated;
revoke all on mix_strategy from anon;

drop policy if exists mix_strategy_read  on mix_strategy;
drop policy if exists mix_strategy_write on mix_strategy;
create policy mix_strategy_read  on mix_strategy for select to authenticated using (true);
create policy mix_strategy_write on mix_strategy for all to authenticated
  using (public.is_editor()) with check (public.is_editor());
