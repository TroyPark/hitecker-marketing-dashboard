# -*- coding: utf-8 -*-
"""구역 잠금 비밀번호 설정.

    python scripts/set_lock.py mix "비밀번호"
    python scripts/set_lock.py input "비밀번호"
    python scripts/set_lock.py --check mix "비밀번호"    # 대조만

비밀번호는 서버에서 bcrypt 로 해시돼 저장된다. 평문은 어디에도 남지 않는다.
"""
import os, sys, io, json, pathlib, requests

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

for line in pathlib.Path(".env").read_text(encoding="utf-8").splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

URL = os.environ["SUPABASE_URL"].rstrip("/")
SVC = os.environ["SUPABASE_SERVICE_KEY"]
H = {"apikey": SVC, "Authorization": f"Bearer {SVC}", "Content-Type": "application/json"}

args = sys.argv[1:]
check = "--check" in args
args = [a for a in args if a != "--check"]
if len(args) != 2:
    raise SystemExit(__doc__)
section, pw = args
if section not in ("mix", "input"):
    raise SystemExit("section 은 mix 또는 input 이어야 합니다")

fn = "verify_section_password" if check else "set_section_password"
r = requests.post(f"{URL}/rest/v1/rpc/{fn}", headers=H,
                  data=json.dumps({"p_section": section, "p_password": pw}), timeout=30)
if r.status_code >= 300:
    try:
        msg = r.json().get("message") or r.json().get("hint") or r.text
    except Exception:
        msg = r.text
    raise SystemExit(f"실패 ({r.status_code}): {msg[:300]}\n"
                     f"→ supabase/section_locks.sql 을 먼저 실행했는지 확인하세요.")
print(f"{section}: " + ("대조 결과 " + ("일치" if r.json() is True else "불일치") if check else "설정 완료"))
