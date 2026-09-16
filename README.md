# 하이테커 마케팅 대시보드

광고 실적과 사업 실적(가입 · 결제 · 매출)을 한 화면에서 본다.
빌드 도구 없이 정적 HTML로 동작하고, 데이터는 Supabase에 둔다.

- 기획 문서: [기획서.md](기획서.md)
- 화면: 경영 대시보드(임원) / 광고 운영(팀장) / 데이터 입력

## 구성

```
index.html                 앱 전체 (단일 파일)
Logo.png
supabase/schema.sql        테이블 · 뷰 · RLS · 마스터 시드
scripts/migrate.py         엑셀 → Supabase 초기 적재
.github/workflows/deploy.yml   main push 시 GitHub Pages 배포
.env.example               필요한 키 목록
```

리포지토리에 올리지 않는 것 (`.gitignore`):
`Ads RAW Data.xlsx` 등 원천 엑셀, 추출 데이터 `data.js`, `.env`, CI가 만드는 `config.js`.

## 처음 세팅

### 1. Supabase

1. [supabase.com](https://supabase.com) 에서 프로젝트를 만든다 (Region: Northeast Asia (Seoul))
2. SQL Editor 에 `supabase/schema.sql` 을 붙여넣고 실행
3. Authentication > Users 에서 팀원 계정을 만든다 (공개 회원가입은 쓰지 않는다)
4. SQL Editor 에서 관리자 지정:
   ```sql
   update profiles set role = 'admin' where email = '본인이메일';
   ```
5. Project Settings > API 에서 아래 세 값을 확인한다
   - Project URL
   - `anon` public 키 — 브라우저에 노출되는 값. RLS로 보호한다
   - `service_role` 키 — RLS를 우회한다. 마이그레이션에만 쓰고 절대 커밋하지 않는다

### 2. 초기 데이터 적재

```powershell
copy .env.example .env      # 값을 채운다
pip install openpyxl requests
python scripts/migrate.py "Ads RAW Data.xlsx" --dry-run   # 검증만
python scripts/migrate.py "Ads RAW Data.xlsx"             # 실제 적재
```

### 3. 배포

1. GitHub 레포에 push
2. Settings > Pages > Source 를 **GitHub Actions** 로
3. Settings > Secrets and variables > Actions > **Variables** 에 등록
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
4. main 에 push 하면 자동 배포된다

## 로컬에서 보기

`index.html` 을 더블클릭한다. `config.local.js` 가 있으면 Supabase에 붙고,
없으면 `data.js` 의 로컬 데이터로 동작한다.

```js
// config.local.js  (gitignore 됨)
window.APP_CONFIG = {
  SUPABASE_URL: "https://xxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJ..."
};
```

## 주의

GitHub Pages 는 정적 호스팅이라 anon 키가 브라우저에 그대로 노출된다.
이건 설계상 정상이고, 데이터를 지키는 건 Supabase 의 RLS 정책이다.
**RLS 를 끈 채로 배포하면 URL 을 아는 사람이 데이터를 전부 조회할 수 있다.**
private 리포지토리여도 Pages 로 배포된 산출물은 공개다.
