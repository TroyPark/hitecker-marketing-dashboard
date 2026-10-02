# Edge Function 배포 — mix-strategy (AI 전략 어시스턴트)

Claude(Sonnet 5) 키를 브라우저에 노출하지 않으려는 프록시. 로그인 사용자만 호출.

## 방법 A — Supabase 대시보드 (CLI 설치 불필요, 권장)
1. supabase.com → 프로젝트 → **Edge Functions** → **Create a new function**
2. 이름: `mix-strategy`
3. `supabase/functions/mix-strategy/index.ts` 내용을 그대로 붙여넣고 **Deploy**
4. **Project Settings → Edge Functions → Secrets** (또는 Functions → Manage secrets)
   에서 비밀값 추가: `ANTHROPIC_API_KEY = sk-ant-...`
5. 끝. 앱에서 미디어 믹스 → 🤖 AI 전략 으로 호출됨

## 방법 B — CLI
    npm i -g supabase
    supabase login
    supabase link --project-ref sxbgkjqqosqexvalyjps
    supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
    supabase functions deploy mix-strategy

## 사전 1회: 테이블
SQL Editor 에서 supabase/05_mix_strategy.sql 실행 (전략 저장용).

## 모델 바꾸려면
index.ts 상단 MODEL 상수 ('claude-sonnet-5' → 'claude-opus-5') 수정 후 재배포.
