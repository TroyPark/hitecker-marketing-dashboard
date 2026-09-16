-- ============================================================
--  02. 구역 잠금 + 사업 운영 상태
--  SQL Editor 에 붙여넣고 실행하세요. 여러 번 실행해도 안전합니다.
-- ============================================================

-- ── 사업 운영 상태 ───────────────────────────────────────────
-- 종료한 사업은 경영 대시보드에서 빠진다. 데이터는 그대로 남는다.
alter table brands add column if not exists active boolean not null default true;

-- ── 구역 잠금 (미디어 믹스 · 데이터 입력) ────────────────────
--  비밀번호는 평문으로 두지 않는다. bcrypt 해시만 저장하고,
--  대조는 서버(함수 안)에서 한다. 테이블 자체는 아무도 읽을 수 없다.

create extension if not exists pgcrypto with schema extensions;

create table if not exists section_locks (
  section       text primary key,          -- 'mix' | 'input'
  password_hash text not null,
  updated_at    timestamptz default now(),
  updated_by    uuid references auth.users(id)
);

-- RLS 는 켜고 정책은 하나도 만들지 않는다.
-- → 로그인 사용자도 이 테이블을 직접 읽거나 쓸 수 없다. 아래 두 함수로만 접근한다.
alter table section_locks enable row level security;
revoke all on table section_locks from anon, authenticated;

-- 대조: 맞으면 true. 해시도 비밀번호도 클라이언트로 나가지 않는다.
create or replace function public.verify_section_password(p_section text, p_password text)
returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from section_locks
    where section = p_section
      and password_hash = crypt(p_password, password_hash)
  );
$$;

-- 설정: editor 이상 또는 service_role 만
create or replace function public.set_section_password(p_section text, p_password text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_editor() then
    raise exception '권한이 없습니다';
  end if;
  if length(p_password) < 6 then
    raise exception '비밀번호는 6자 이상이어야 합니다';
  end if;
  insert into section_locks (section, password_hash, updated_by)
  values (p_section, extensions.crypt(p_password, extensions.gen_salt('bf')), auth.uid())
  on conflict (section) do update
    set password_hash = excluded.password_hash,
        updated_at = now(),
        updated_by = excluded.updated_by;
end $$;

revoke all on function public.verify_section_password(text, text) from public, anon;
revoke all on function public.set_section_password(text, text)    from public, anon;
grant execute on function public.verify_section_password(text, text) to authenticated;
grant execute on function public.set_section_password(text, text)    to authenticated;

-- 비밀번호는 여기에 적지 않는다. 실행 후 아래 중 하나로 설정한다.
--   · 앱 관리자 화면 (예정)
--   · SQL Editor:  select set_section_password('mix', '원하는비밀번호');
--   · 스크립트:    python scripts/set_lock.py mix 원하는비밀번호
