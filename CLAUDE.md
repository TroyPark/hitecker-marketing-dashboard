# 하이테커 마케팅 대시보드

빌드 없는 정적 SPA(`index.html` 단일 파일) + Supabase. GitHub Pages 자동 배포.

## 접속
- 사이트: https://troypark.github.io/hitecker-marketing-dashboard/
- 레포: TroyPark/hitecker-marketing-dashboard (public)
- Supabase: https://sxbgkjqqosqexvalyjps.supabase.co · 키는 `.env`(로컬)·`config.js`(gitignore)
- 로그인 `marketing@kfo.or.kr` / `gkdlxpzj11!` (admin) · 구역잠금 `akzpxld11!`
- gh 계정 TroyPark, `gh auth setup-git` 완료

## 구조
- `index.html` — 앱 전체(HTML+CSS+JS). 4탭: 경영 대시보드 / 광고 운영 / 미디어 믹스 / 데이터 입력
- 데이터는 `config.js` 있으면 Supabase, 없으면 `data.js`(로컬 목업)로 동작
- `supabase/*.sql` — 01 schema / 02 locks+brand active / 03 refund / 04 rename cascade
- `scripts/` — migrate.py(엑셀→DB), set_lock.py(잠금 비번), deploy.ps1
- 배포: main push → Actions가 config.js 생성 후 Pages 배포

## 테이블 (RLS on, anon 권한 회수됨, 뷰는 security_invoker)
- ad_daily(date,brand,platform) 노출·클릭·광고비·전환·전환매출 — **911행(내일하이만 실데이터)**
- business_daily(date,brand) 가입·결제·매출·refund — **0행**
- budgets(month,brand,platform) 매체별 월예산 — **0행**
- brands/platforms(code) 마스터, brands.active로 종료. upload_logs, profiles, section_locks

## 규칙 (중요)
- **파생지표 저장 안 함**: CTR·CPC·CPA·ROAS·최종매출 전부 조회 시 계산. 일별 평균 금지, 기간 합계에서 재계산
- 최종매출 = 매출 − 환불. ROAS·객단가는 최종매출 기준. 광고운영 ROAS(전환매출)와 경영 ROAS(실매출)는 다른 값
- 색은 사업·매체 등록순 고정(8칸까지, 이후 회색). 이중축 금지
- 미집행/빈값은 `-` 또는 NaN → "데이터 없음". 없는 값 지어내지 않음

## 개발 시 주의 (겪은 것)
- `.ps1`은 UTF-8 **BOM** 필수(PS 5.1 한글 깨짐). gitignore는 줄끝 주석 금지
- index.html 문자열로 자르지 말 것 — 전에 핸들러가 통째로 날아감. 앵커는 유니크하게
- 날짜는 UTF-8 아니라 UTC 계산(KST 하루밀림). 커밋에 .env/config.js/data.js/xlsx 절대 금지
- private 레포는 무료 Pages 불가 → public
- 스크린샷: `python _shot.py` (config.js 제거 후 렌더). 임시파일은 `_*.py`, `_tmp_*` (gitignore)

## 보안 점검됨 (2026-09-17)
anon 전체 401, 로그인 사용자 권한상승·잠금비번 조회 전부 차단, PostgREST 인젝션 안통함.
잔여 리스크는 계정 비번 자체 → Supabase 유출비번 차단 설정 권장(미적용).

## 미완
- 사업실적·예산 데이터 입력 대기(0행). KFO·오라클·K-뉴딜 광고데이터 미확보
- 04_rename_cascade.sql 적용 여부 미확인(사업 코드변경 시 필요, 이름변경은 불필요)
- 탭별 자동 인사이트 문구(제안만 함, 미구현)

상세 이력은 작업일지.md, 기획은 기획서.md.
