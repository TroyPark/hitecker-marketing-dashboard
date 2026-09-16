# 레포 생성 → push → Pages 켜기 → Supabase 접속 정보 등록까지 한 번에.
# 먼저 `gh auth login` 으로 로그인돼 있어야 합니다.
#
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Repo my-dashboard -Public

param(
  [string]$Repo = "hitecker-marketing-dashboard",
  [switch]$Public
)

$ErrorActionPreference = "Stop"
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

function Step($msg) { Write-Host "`n▸ $msg" -ForegroundColor Cyan }

# ── 사전 확인 ────────────────────────────────────────────────
Step "GitHub 로그인 확인"
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "GitHub 로그인이 필요합니다. 먼저 'gh auth login' 을 실행하세요." }
$owner = (gh api user --jq .login)
Write-Host "  계정: $owner"

if (-not (Test-Path ".env")) { throw ".env 가 없습니다. Supabase 접속 정보가 필요합니다." }
$envMap = @{}
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') { $envMap[$Matches[1].Trim()] = $Matches[2].Trim() }
}
foreach ($k in @("SUPABASE_URL", "SUPABASE_ANON_KEY")) {
  if (-not $envMap[$k]) { throw ".env 에 $k 가 없습니다." }
}

# 비밀값이 커밋에 섞이지 않았는지 확인한다
Step "커밋에 비밀값이 없는지 확인"
$leaked = @("\.env$", "^config\.js$", "^data\.js$", "\.xlsx$") | ForEach-Object {
  git ls-files | Select-String -Pattern $_
}
if ($leaked) { throw "커밋에 들어가면 안 되는 파일이 있습니다: $($leaked -join ', ')" }
Write-Host "  이상 없음"

# ── 레포 ─────────────────────────────────────────────────────
$visibility = if ($Public) { "--public" } else { "--private" }
Step "레포 준비: $owner/$Repo ($(if ($Public) { 'public' } else { 'private' }))"
gh repo view "$owner/$Repo" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  gh repo create "$Repo" $visibility --source . --remote origin --disable-wiki
} else {
  Write-Host "  이미 있음"
  if (-not (git remote 2>$null | Select-String '^origin$')) {
    git remote add origin "https://github.com/$owner/$Repo.git"
  }
}

Step "push"
git push -u origin main

# ── Pages ────────────────────────────────────────────────────
Step "Actions 변수 등록"
gh variable set SUPABASE_URL      --repo "$owner/$Repo" --body $envMap["SUPABASE_URL"]
gh variable set SUPABASE_ANON_KEY --repo "$owner/$Repo" --body $envMap["SUPABASE_ANON_KEY"]
Write-Host "  SUPABASE_URL / SUPABASE_ANON_KEY 등록 완료"

Step "Pages 소스를 GitHub Actions 로 설정"
# 처음이면 POST, 이미 켜져 있으면 PUT 으로 바꾼다
gh api -X POST "repos/$owner/$Repo/pages" -f "build_type=workflow" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  gh api -X PUT "repos/$owner/$Repo/pages" -f "build_type=workflow" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  자동 설정 실패 — Settings > Pages > Source 를 'GitHub Actions' 로 직접 바꿔주세요" -ForegroundColor Yellow
  }
}

Step "배포 실행"
gh workflow run deploy.yml --repo "$owner/$Repo" 2>&1 | Out-Null
Start-Sleep -Seconds 5
gh run list --repo "$owner/$Repo" --limit 3

Write-Host "`n완료. 진행 상황:" -ForegroundColor Green
Write-Host "  gh run watch --repo $owner/$Repo"
Write-Host "  https://$owner.github.io/$Repo/"
