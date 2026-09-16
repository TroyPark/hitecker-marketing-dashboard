# -*- coding: utf-8 -*-
"""Ads RAW Data.xlsx → Supabase 초기 적재.

엑셀의 wide 73컬럼을 (날짜 × 매체) long 행으로 풀어서 ad_daily 에 upsert 한다.
Supabase CLI 없이 REST 로만 동작한다.

사용법:
    pip install openpyxl requests
    # .env 를 만들거나 환경변수로 넘긴다
    set SUPABASE_URL=https://xxxx.supabase.co
    set SUPABASE_SERVICE_KEY=eyJ...            # service_role 키 (절대 커밋 금지)
    python scripts/migrate.py "Ads RAW Data.xlsx"
    python scripts/migrate.py "Ads RAW Data.xlsx" --dry-run   # 적재 없이 검증만
"""
import argparse, json, os, sys, io, pathlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

METRIC_MAP = {
    "Impressions":      "impressions",
    "Clicks":           "clicks",
    "Adcost":           "adcost",
    "Conversion":       "conversions",
    "Conversion value": "conv_value",
}
# CTR / CPC / CPA / ROAS 는 파생지표라 저장하지 않는다 (뷰에서 계산)
SKIP_METRICS = {"CTR", "CPC", "CPA", "ROAS"}
CHUNK = 500


def load_env():
    """루트의 .env 를 읽어 환경변수에 채운다 (이미 있으면 건드리지 않음)."""
    p = pathlib.Path(".env")
    if not p.exists():
        return
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def parse_workbook(path):
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
    rows, problems = {}, []

    for ws in wb.worksheets:
        if not ws.title.startswith("(RAW)"):
            continue
        it = ws.iter_rows(values_only=True)
        header = list(next(it))
        if not header or str(header[0]).upper() != "DATE":
            problems.append(f"{ws.title}: A1이 DATE가 아님 — 건너뜀")
            continue

        # 헤더가 {브랜드}_{플랫폼}_{캠페인}_{지표} 인지 확인
        cols = []
        for j, h in enumerate(header[1:], 1):
            if h is None:
                cols.append(None); continue
            parts = str(h).split("_")
            if len(parts) < 4:
                cols.append(None); problems.append(f"{ws.title}: 해석 불가 헤더 '{h}'"); continue
            metric = "_".join(parts[3:])
            cols.append((parts[0], f"{parts[1]}_{parts[2]}", metric))

        sheet_brand = ws.title[len("(RAW)"):]
        header_brands = {c[0] for c in cols if c}
        if header_brands and sheet_brand not in header_brands:
            problems.append(
                f"{ws.title}: 시트명({sheet_brand})과 헤더 접두사({', '.join(header_brands)})가 다릅니다. "
                f"헤더 기준으로 적재합니다.")

        for r in it:
            if r[0] is None:
                continue
            date = r[0].strftime("%Y-%m-%d") if hasattr(r[0], "strftime") else str(r[0])[:10]
            for j, col in enumerate(cols, 1):
                if col is None:
                    continue
                brand, platform, metric = col
                if metric in SKIP_METRICS:
                    continue
                field = METRIC_MAP.get(metric)
                if field is None:
                    continue
                v = r[j]
                if v is None or v == "-" or v == "":     # 미집행일은 0이 아니라 빈 값
                    continue
                if not isinstance(v, (int, float)):
                    problems.append(f"{date} {brand}_{platform}_{metric}: 숫자가 아님 ({v!r})")
                    continue
                rows.setdefault((date, brand, platform), {})[field] = round(float(v), 4)

    out = []
    for (date, brand, platform), vals in rows.items():
        if not any(vals.values()):
            continue
        out.append({"date": date, "brand": brand, "platform": platform,
                    "impressions": int(vals.get("impressions", 0)),
                    "clicks": int(vals.get("clicks", 0)),
                    "adcost": vals.get("adcost", 0),
                    "conversions": vals.get("conversions", 0),
                    "conv_value": vals.get("conv_value", 0)})
    out.sort(key=lambda r: (r["date"], r["brand"], r["platform"]))
    return out, problems


def upsert(url, key, table, rows, conflict):
    import requests
    endpoint = f"{url.rstrip('/')}/rest/v1/{table}?on_conflict={conflict}"
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    done = 0
    for i in range(0, len(rows), CHUNK):
        chunk = rows[i:i + CHUNK]
        resp = requests.post(endpoint, headers=headers, data=json.dumps(chunk), timeout=60)
        if resp.status_code >= 300:
            raise SystemExit(f"업로드 실패 ({resp.status_code}): {resp.text[:500]}")
        done += len(chunk)
        print(f"  {done}/{len(rows)}행")
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx", nargs="?", default="Ads RAW Data.xlsx")
    ap.add_argument("--dry-run", action="store_true", help="적재하지 않고 검증 결과만 출력")
    ap.add_argument("--out", help="변환 결과를 JSON 파일로 저장")
    args = ap.parse_args()

    load_env()
    rows, problems = parse_workbook(args.xlsx)

    brands = sorted({r["brand"] for r in rows})
    dates = sorted({r["date"] for r in rows})
    print(f"파일     : {args.xlsx}")
    print(f"변환 행수 : {len(rows):,}")
    print(f"사업     : {', '.join(brands) or '(없음)'}")
    print(f"기간     : {dates[0] if dates else '-'} ~ {dates[-1] if dates else '-'}")
    print(f"광고비 합 : {sum(r['adcost'] for r in rows):,.0f}원")
    if problems:
        print("\n확인 필요:")
        for p in dict.fromkeys(problems[:20]):
            print("  -", p)
        if len(problems) > 20:
            print(f"  ... 외 {len(problems) - 20}건")

    if args.out:
        pathlib.Path(args.out).write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        print(f"\n{args.out} 에 저장했습니다.")

    if args.dry_run:
        print("\n--dry-run: 업로드하지 않았습니다.")
        return

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_KEY 가 없습니다. .env 를 만들거나 환경변수로 넘기세요.")

    print(f"\n{url} 로 업로드합니다...")
    n = upsert(url, key, "ad_daily", rows, "date,brand,platform")
    print(f"완료: ad_daily {n:,}행 upsert")


if __name__ == "__main__":
    main()
