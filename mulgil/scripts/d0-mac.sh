#!/usr/bin/env bash
# d0-mac.sh — 물길 D0(§5.0 2·3·4번) 맥 쪽 자동화.
#
#   bash d0-mac.sh            설치·Syncthing 설정 (멱등. 몇 번 돌려도 같은 결과)
#   bash d0-mac.sh accept     폰이 연결을 요청하면 수락하고 mulgil-phone 폴더에 넣는다
#   bash d0-mac.sh status     폰 lastSeen·연결 방식·폴더 상태/에러
#   bash d0-mac.sh check      inbox m4a의 creation_time 판정(D0 2번) + 6시간 내 도착 건수(D0 3번)
#   bash d0-mac.sh help
#
# 옵션(환경변수):
#   D0_DRY_RUN=1      할 일만 출력하고 아무것도 바꾸지 않는다 (setup)
#   D0_YES=1          확인 질문에 모두 yes (accept)
#   D0_TOL=90         check 판정 허용 오차(초)
#   D0_WINDOW_H=6     check 도착 집계 창(시간)
#   MULGIL_INBOX      기본 ~/Mulgil/inbox/phone
#
# macOS 기본 bash 3.2 에서 돌아가도록 연관 배열·mapfile·${x,,} 를 쓰지 않는다.
# 설계: docs/mulgil-design.md §5.0, §5.1, §5.2, §5.9-4(릴레이 끔)

set -euo pipefail

FOLDER_ID="${MULGIL_FOLDER_ID:-mulgil-phone}"
FOLDER_LABEL="물길 폰 녹음"
INBOX="${MULGIL_INBOX:-$HOME/Mulgil/inbox/phone}"
MULGIL_HOME="${MULGIL_HOME:-$HOME/Mulgil}"
VERSION_KEEP="10"
TOL="${D0_TOL:-90}"
WINDOW_H="${D0_WINDOW_H:-6}"
KST_OFFSET=32400   # 9h. 로컬 시각을 UTC(Z)로 잘못 적은 경우를 잡는다
BREW_PKGS="syncthing ffmpeg jq"

ST_KEY=""
ST_BASE=""

# ───────────────────────── 출력 ─────────────────────────
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*" >&2; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

is_dry() { [[ "${D0_DRY_RUN:-0}" == "1" ]]; }
run() {
  if is_dry; then say "  (dry-run) $*"; else "$@"; fi
}

confirm() { # confirm "질문" → 0/1
  if [[ "${D0_YES:-0}" == "1" ]]; then return 0; fi
  local a=""
  printf '  %s [y/N] ' "$1"
  read -r a </dev/tty || a=""
  case "$a" in y|Y|yes|YES|ㅛ) return 0 ;; *) return 1 ;; esac
}

# ───────────────────── 플랫폼 차이 (BSD/GNU) ─────────────────────
is_gnu_date() { date --version >/dev/null 2>&1; }
is_gnu_stat() { stat --version >/dev/null 2>&1; }

file_mtime() { # 초
  if is_gnu_stat; then stat -c %Y "$1"; else stat -f %m "$1"; fi
}
file_arrival() { # 이 맥에 파일이 생긴 시각. macOS=birth time, 없으면 ctime
  local b
  if is_gnu_stat; then
    b=$(stat -c %W "$1" 2>/dev/null || echo 0)
    if [[ -z "$b" || "$b" == "0" || "$b" == "-" ]]; then b=$(stat -c %Z "$1"); fi
  else
    b=$(stat -f %B "$1" 2>/dev/null || echo 0)
    if [[ -z "$b" || "$b" == "0" ]]; then b=$(stat -f %c "$1"); fi
  fi
  printf '%s\n' "$b"
}
fmt_local() { # epoch → "11-23 14:05:09" (로컬 시간대)
  if is_gnu_date; then date -d "@$1" '+%m-%d %H:%M:%S'; else date -r "$1" '+%m-%d %H:%M:%S'; fi
}

# ISO8601 → epoch. 실패·빈값이면 빈 문자열
# 예: 2026-11-23T05:12:34.000000Z (ffprobe) / 2026-11-23 05:12:34 / 1904-01-01T00:00:00.000000Z
#     2026-11-23T14:10:00+09:00 (Syncthing /rest/stats/device lastSeen 은 로컬 오프셋을 붙인다)
iso_to_epoch() {
  local s="${1:-}" base rest off=0 hh mm e
  s="${s/ /T}"
  base="${s:0:19}"; rest="${s:19}"
  [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || { printf '\n'; return 0; }
  if [[ "$rest" == .* ]]; then  # 소수 초 버림
    rest="${rest#.}"
    while [[ "$rest" == [0-9]* ]]; do rest="${rest#?}"; done
  fi
  case "$rest" in
    ''|Z|z) off=0 ;;
    [+-][0-9][0-9]:[0-9][0-9]|[+-][0-9][0-9][0-9][0-9])
      hh="${rest:1:2}"; mm="${rest: -2}"
      off=$(( 10#$hh * 3600 + 10#$mm * 60 ))
      if [[ "$rest" == -* ]]; then off=$(( -off )); fi ;;
    *) printf '\n'; return 0 ;;
  esac
  if is_gnu_date; then
    e=$(date -u -d "${base/T/ }" +%s 2>/dev/null) || e=""
  else
    e=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) || e=""
  fi
  if [[ -z "$e" ]]; then printf '\n'; return 0; fi
  printf '%s\n' "$(( e - off ))"
}

# ───────────────────────── 파싱 함수 (리눅스에서 단위 시험) ─────────────────────────

# ffprobe -show_entries format=duration:format_tags=creation_time -of default=noprint_wrappers=1
# 의 출력(stdin) → "duration_초(정수)|creation_time 원문" 한 줄
#   duration=3125.482000
#   TAG:creation_time=2026-11-23T05:12:34.000000Z
parse_ffprobe() {
  local line dur="" ct="" cr=$'\r'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%"$cr"}"
    case "$line" in
      duration=*)          if [[ -z "$dur" ]]; then dur="${line#duration=}"; fi ;;
      TAG:creation_time=*) if [[ -z "$ct" ]]; then ct="${line#TAG:creation_time=}"; fi ;;
      creation_time=*)     if [[ -z "$ct" ]]; then ct="${line#creation_time=}"; fi ;;
    esac
  done
  case "$dur" in ''|N/A) dur="" ;; *) dur="${dur%%.*}" ;; esac
  [[ "$dur" =~ ^[0-9]+$ ]] || dur=""
  printf '%s|%s\n' "$dur" "$ct"
}

abs() { local v="$1"; if (( v < 0 )); then v=$(( -v )); fi; printf '%s\n' "$v"; }

# classify_ctime <ctime_epoch|빈값> <mtime> <duration> [tol]
# → "판정 d_start d_save"   (d_* = creation_time − 추정값, 초)
#   none       creation_time 없음·0·1904 등 1971 이전
#   start      creation_time ≈ mtime − duration (녹음 시작 시각)
#   save       creation_time ≈ mtime            (저장 시각)
#   start+9h / save+9h   로컬 시각이 UTC(Z)로 적힌 경우(±9시간 어긋남)
#   ambiguous  duration ≤ 2·tol 이라 시작/저장을 구분할 수 없음
#   other      어느 것과도 맞지 않음
classify_ctime() {
  local ct="${1:-}" mt="$2" dur="${3:-}" tol="${4:-$TOL}"
  if [[ -z "$ct" ]] || (( ct < 31536000 )); then
    printf 'none - -\n'; return 0
  fi
  [[ -n "$dur" ]] || dur=0
  local start_est=$(( mt - dur ))
  local ds=$(( ct - start_est )) dv=$(( ct - mt ))
  local ads adv
  ads=$(abs "$ds"); adv=$(abs "$dv")
  if (( dur <= 2 * tol )) && (( ads <= tol || adv <= tol )); then
    printf 'ambiguous %s %s\n' "$ds" "$dv"; return 0
  fi
  if (( ads <= tol && ads <= adv )); then printf 'start %s %s\n' "$ds" "$dv"; return 0; fi
  if (( adv <= tol )); then printf 'save %s %s\n' "$ds" "$dv"; return 0; fi
  local k
  for k in "$KST_OFFSET" "-$KST_OFFSET"; do
    if (( $(abs $(( ds - k ))) <= tol )); then printf 'start+9h %s %s\n' "$ds" "$dv"; return 0; fi
    if (( $(abs $(( dv - k ))) <= tol )); then printf 'save+9h %s %s\n' "$ds" "$dv"; return 0; fi
  done
  printf 'other %s %s\n' "$ds" "$dv"
}

# conclude <start> <save> <none> <start9> <save9> <other> <ambiguous> → 결론 1줄 (§5.0-2 분기)
conclude() {
  local s=$1 v=$2 n=$3 s9=$4 v9=$5 o=$6 a=$7
  local decided=$(( s + v + n + s9 + v9 + o ))
  if (( decided == 0 )); then
    if (( a > 0 )); then
      say "결론: 판정 보류 — 녹음이 너무 짧다(≤$(( 2 * TOL ))초). $(( 2 * TOL / 60 + 1 ))분 이상 녹음을 다시 넣고 check 하라."
    else
      say "결론: 판정 보류 — 판정할 m4a가 없다."
    fi
    return 0
  fi
  if (( s == decided )); then
    say "결론: creation_time = 녹음 시작 시각 → 시각 1순위로 creation_time을 그대로 쓴다 (§5.0-2)."
  elif (( v == decided )); then
    say "결론: creation_time = 저장 시각 → 시작 = creation_time − duration (§5.0-2)."
  elif (( n == decided )); then
    say "결론: creation_time 없음/0/1904 → 시작 = mtime − duration (§5.0-2)."
  elif (( s9 == decided )); then
    say "결론: creation_time = 시작 시각이지만 로컬시각을 UTC로 적음(+9h) → −9h 보정 후 사용. 설계에 없는 분기라 기록 필요."
  elif (( v9 == decided )); then
    say "결론: creation_time = 저장 시각이지만 로컬시각을 UTC로 적음(+9h) → −9h 보정 후 −duration. 설계에 없는 분기라 기록 필요."
  else
    say "결론: 혼재(시작 $s·저장 $v·없음 $n·+9h $(( s9 + v9 ))·불일치 $o) → creation_time을 믿지 말고 mtime − duration을 쓴다. 표를 설계 문서에 붙여 둔다."
  fi
}

# config.xml 파싱
xml_apikey() { sed -n 's:.*<apikey>\([^<]*\)</apikey>.*:\1:p' "$1" | head -n 1; }
xml_gui_address() { sed -n '/<gui[ >]/,/<\/gui>/ s:.*<address>\([^<]*\)</address>.*:\1:p' "$1" | head -n 1; }
xml_gui_tls() {
  if sed -n '/<gui[ >]/p' "$1" | head -n 1 | grep -q 'tls="true"'; then echo https; else echo http; fi
}
# 0.0.0.0:8384 / [::]:8384 / :8384 → 127.0.0.1:8384
normalize_addr() {
  local a="$1" port="${1##*:}"
  case "$a" in
    0.0.0.0:*|\[::\]:*|:*|'') printf '127.0.0.1:%s\n' "${port:-8384}" ;;
    *) printf '%s\n' "$a" ;;
  esac
}

# Syncthing config.xml 후보 (2.x 기준. macOS 기본은 ~/Library/Application Support/Syncthing,
# 리눅스 1.27+/2.x 는 $XDG_STATE_HOME/syncthing, 구버전 ~/.config/syncthing)
st_config_candidates() {
  if [[ -n "${STHOMEDIR:-}" ]]; then printf '%s\n' "$STHOMEDIR/config.xml"; fi
  if [[ -n "${STCONFDIR:-}" ]]; then printf '%s\n' "$STCONFDIR/config.xml"; fi
  printf '%s\n' \
    "$HOME/Library/Application Support/Syncthing/config.xml" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml"
}
st_find_config() {
  local c
  while IFS= read -r c; do
    if [[ -f "$c" ]]; then printf '%s\n' "$c"; return 0; fi
  done < <(st_config_candidates)
  return 1
}

# ───────────────────────── Syncthing REST ─────────────────────────
# 새 터미널에서 brew shellenv 가 안 잡혀 있어도 jq·ffprobe 를 찾도록 (중복 추가 안 함)
add_brew_path() {
  local t
  for t in /opt/homebrew/bin /usr/local/bin; do
    case ":$PATH:" in *":$t:"*) ;; *) if [[ -d "$t" ]]; then PATH="$PATH:$t"; fi ;; esac
  done
}
st_init() {
  local cfg t
  add_brew_path
  for t in curl jq; do
    command -v "$t" >/dev/null 2>&1 || die "$t 이 없다 → 먼저 'bash $0' (brew install jq)"
  done
  cfg=$(st_find_config) || die "Syncthing config.xml을 못 찾았다. 'brew services start syncthing' 후 다시 실행. 찾은 경로: $(st_config_candidates | tr '\n' ' ')"
  ST_KEY=$(xml_apikey "$cfg")
  [[ -n "$ST_KEY" ]] || die "config.xml에 apikey가 없다: $cfg"
  local addr
  addr=$(normalize_addr "$(xml_gui_address "$cfg")")
  ST_BASE="$(xml_gui_tls "$cfg")://$addr"
  # 자체 서명 인증서 무시(-k)는 루프백일 때만. 다른 호스트면 인증서 검증을 그대로 둔다
  case "$addr" in
    127.*|localhost:*|\[::1\]:*) ST_INSECURE="-k" ;;
    *) ST_INSECURE="" ; warn "GUI 주소가 루프백이 아니다($addr). TLS 검증을 끄지 않는다." ;;
  esac
}
ST_INSECURE="-k"

# st_api METHOD PATH [JSON] → 본문. 실패하면 비0
# API 키는 argv(ps 로 보임) 대신 stdin 설정(-K -)으로 넘긴다
st_api() {
  local m="$1" p="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    printf 'header = "X-API-Key: %s"\n' "$ST_KEY" |
      curl -fsS ${ST_INSECURE:+"$ST_INSECURE"} --max-time 15 -K - -X "$m" -H 'Content-Type: application/json' \
        --data-binary "$body" "$ST_BASE$p"
  else
    printf 'header = "X-API-Key: %s"\n' "$ST_KEY" |
      curl -fsS ${ST_INSECURE:+"$ST_INSECURE"} --max-time 15 -K - -X "$m" "$ST_BASE$p"
  fi
}

st_wait() { # API가 살아날 때까지 최대 60초
  local i=0
  while (( i < 30 )); do
    if st_find_config >/dev/null 2>&1; then
      st_init
      if st_api GET /rest/system/ping >/dev/null 2>&1; then return 0; fi
    fi
    sleep 2; i=$(( i + 1 ))
  done
  die "Syncthing API 응답 없음(60초). 'brew services info syncthing' 와 \$(brew --prefix)/var/log/syncthing.log 를 확인."
}

st_my_id() { st_api GET /rest/system/status | jq -r '.myID'; }
st_folder_exists() { st_api GET "/rest/config/folders/$FOLDER_ID" >/dev/null 2>&1; }

# 폴더 설정 JSON (POST 신규용). receiveonly + ignoreDelete + simple versioning(무기한 보관)
folder_json_new() { # $1 = 내 device id
  jq -n --arg id "$FOLDER_ID" --arg label "$FOLDER_LABEL" --arg path "$INBOX" \
        --arg me "$1" --arg keep "$VERSION_KEEP" '{
    id: $id, label: $label, path: $path, type: "receiveonly",
    ignoreDelete: true, fsWatcherEnabled: true, rescanIntervalS: 3600,
    devices: [ { deviceID: $me } ],
    versioning: { type: "simple", params: { keep: $keep, cleanoutDays: "0" },
                  cleanupIntervalS: 3600, fsPath: "", fsType: "basic" }
  }'
}
# PATCH 갱신용 (devices·path 는 건드리지 않는다)
folder_json_patch() {
  jq -n --arg label "$FOLDER_LABEL" --arg keep "$VERSION_KEEP" '{
    label: $label, type: "receiveonly", ignoreDelete: true,
    versioning: { type: "simple", params: { keep: $keep, cleanoutDays: "0" },
                  cleanupIntervalS: 3600, fsPath: "", fsType: "basic" }
  }'
}

# ───────────────────────── 하위 명령 ─────────────────────────
need_mac() {
  if [[ "$(uname -s)" != "Darwin" && "${D0_ALLOW_NONMAC:-0}" != "1" ]]; then
    die "macOS 전용 스크립트다 (uname=$(uname -s))."
  fi
}

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then ok "Homebrew 있음: $(command -v brew)"; return 0; fi
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then eval "$("$b" shellenv)"; ok "Homebrew 있음: $b (PATH에 추가)"; return 0; fi
  done
  warn "Homebrew가 없다. 공식 설치 스크립트를 실행하면 맥 암호를 한 번 묻는다."
  if is_dry; then say "  (dry-run) Homebrew 설치"; return 0; fi
  if confirm "지금 Homebrew를 설치할까?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [[ -x "$b" ]]; then eval "$("$b" shellenv)"; break; fi
    done
    command -v brew >/dev/null 2>&1 || die "Homebrew 설치 후에도 brew가 없다. 새 터미널에서 다시 실행."
  else
    die "Homebrew 없이 진행할 수 없다. https://brew.sh 참고."
  fi
}

cmd_setup() {
  need_mac
  say "d0-mac.sh — 물길 D0 맥 설정. 할 일:"
  say "  1. Homebrew 확인 (없으면 설치 여부를 묻는다)"
  say "  2. brew install: $BREW_PKGS  (이미 있으면 건너뜀)"
  say "  3. brew services start syncthing  (로그인 시 자동 시작되는 LaunchAgent)"
  say "  4. mkdir -p $INBOX"
  say "  5. Syncthing REST API로:"
  say "     - 맥 Device ID 출력 + $MULGIL_HOME/mac-device-id.txt 저장"
  say "     - 폴더 '$FOLDER_ID' = 받기 전용(receiveonly), ignoreDelete=true, Simple 버전 관리(keep $VERSION_KEEP, 자동 삭제 없음)"
  say "     - 릴레이 끔(relaysEnabled=false, §5.9-4). 글로벌 디스커버리는 그대로"
  say "  바꾸지 않는 것: 기존 다른 Syncthing 폴더·기기, Google 계정, 폰"
  is_dry && say "  ※ D0_DRY_RUN=1 — 실제로는 아무것도 바꾸지 않는다"

  step "1/5 Homebrew"
  ensure_brew

  step "2/5 패키지"
  local p
  for p in $BREW_PKGS; do
    if command -v brew >/dev/null 2>&1 && brew list --formula "$p" >/dev/null 2>&1; then
      ok "$p 이미 설치됨"
    else
      run brew install "$p"
    fi
  done

  step "3/5 Syncthing 상주"
  # pipefail + grep -q 조합은 SIGPIPE 로 오판할 수 있어 값을 먼저 받아 비교한다
  local svc=""
  if command -v brew >/dev/null 2>&1; then
    svc=$(brew services list 2>/dev/null | awk '$1=="syncthing"{print $2; exit}') || svc=""
  fi
  case "$svc" in
    started) ok "syncthing 서비스 이미 실행 중" ;;
    ''|none|stopped) run brew services start syncthing ;;
    *) warn "syncthing 서비스 상태=$svc → 재시작"; run brew services restart syncthing ;;
  esac

  step "4/5 수신 폴더"
  if [[ -d "$INBOX" ]]; then ok "$INBOX 있음"; else run mkdir -p "$INBOX"; fi

  step "5/5 Syncthing 설정"
  if is_dry; then
    say "  (dry-run) REST: GET /rest/system/status, POST|PATCH /rest/config/folders[/$FOLDER_ID], PATCH /rest/config/options"
    return 0
  fi
  st_wait
  local me
  me=$(st_my_id)
  [[ -n "$me" && "$me" != "null" ]] || die "Device ID를 읽지 못했다."
  mkdir -p "$MULGIL_HOME"
  printf '%s\n' "$me" > "$MULGIL_HOME/mac-device-id.txt"

  if st_folder_exists; then
    local cur_path
    cur_path=$(st_api GET "/rest/config/folders/$FOLDER_ID" | jq -r '.path')
    if [[ "$cur_path" != "$INBOX" ]]; then
      warn "기존 '$FOLDER_ID' 경로가 $cur_path 이다. 경로는 바꾸지 않는다(데이터 보호). 바꾸려면 Syncthing 웹 UI에서 폴더를 지우고 다시 실행."
    fi
    st_api PATCH "/rest/config/folders/$FOLDER_ID" "$(folder_json_patch)" >/dev/null
    ok "폴더 '$FOLDER_ID' 갱신 (receiveonly, ignoreDelete, simple versioning)"
  else
    st_api POST /rest/config/folders "$(folder_json_new "$me")" >/dev/null
    ok "폴더 '$FOLDER_ID' 생성 → $INBOX"
  fi
  st_api PATCH /rest/config/options '{"relaysEnabled": false}' >/dev/null
  ok "릴레이 끔"

  # 검증: 실제로 들어간 값을 다시 읽어 확인
  local got
  got=$(st_api GET "/rest/config/folders/$FOLDER_ID" | jq -r '"\(.type) ignoreDelete=\(.ignoreDelete) versioning=\(.versioning.type)"')
  [[ "$got" == "receiveonly ignoreDelete=true versioning=simple" ]] || die "폴더 설정 확인 실패: $got"
  ok "확인: $got"

  say ""
  say "══════════════════════════════════════════════════════════════════"
  say " 맥 Device ID (폰 Syncthing-Fork에 '기기 추가'로 입력):"
  say ""
  say "   $me"
  say ""
  say " 폰에서 폴더를 만들 때 '폴더 ID'를 반드시  $FOLDER_ID  로 바꾼다."
  say " 같은 Wi-Fi에서 폰이 맥을 추가하면 →  bash $0 accept"
  say " 웹 UI: $ST_BASE  (Device ID QR도 여기 '작업 > ID 보기')"
  say "══════════════════════════════════════════════════════════════════"
  if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$me" | pbcopy && ok "Device ID를 클립보드에 복사했다"; fi
}

# 폴더 devices 목록에 기기를 넣는다(이미 있으면 그대로)
folder_add_device() {
  local dev="$1" cur new
  cur=$(st_api GET "/rest/config/folders/$FOLDER_ID")
  if printf '%s' "$cur" | jq -e --arg d "$dev" '.devices | map(.deviceID) | index($d)' >/dev/null; then
    ok "폴더 '$FOLDER_ID'에 이미 공유됨"; return 0
  fi
  new=$(printf '%s' "$cur" | jq -c --arg d "$dev" '{devices: (.devices + [{deviceID: $d}])}')
  st_api PATCH "/rest/config/folders/$FOLDER_ID" "$new" >/dev/null
  ok "폴더 '$FOLDER_ID'를 이 기기와 공유"
}

# /rest/cluster/pending/devices JSON(stdin) → "id<TAB>name<TAB>address<TAB>time" 줄
# 빈 값은 "-" 로 채운다: 탭은 IFS 공백 문자라 read 가 연속 탭을 하나로 합쳐 열이 밀리기 때문
pending_devices_tsv() { jq -r 'def nz: if . == null or . == "" then "-" else tostring end;
  to_entries[] | [.key, (.value.name | nz), (.value.address | nz), (.value.time | nz)] | @tsv'; }

# Syncthing Device ID 형식: 7자 x 8묶음, base32(A-Z, 2-7)
is_device_id() { [[ "$1" =~ ^[A-Z2-7]{7}(-[A-Z2-7]{7}){7}$ ]]; }

cmd_accept() {
  need_mac
  st_init
  st_api GET /rest/system/ping >/dev/null 2>&1 || die "Syncthing이 응답하지 않는다. 먼저 'bash $0' 실행."
  st_folder_exists || die "폴더 '$FOLDER_ID'가 없다. 먼저 'bash $0' 실행."
  local want="${1:-}" rows id name addr t n=0 me
  me=$(st_my_id)

  if [[ -n "$want" ]]; then
    want=$(printf '%s' "$want" | tr '[:lower:]' '[:upper:]')
    is_device_id "$want" || die "Device ID 형식이 아니다: $want (예: XXXXXXX-XXXXXXX-...-XXXXXXX, 8묶음)"
    rows=$(printf '%s\t%s\t%s\t%s\n' "$want" "phone" "(직접 입력)" "-")
  else
    rows=$(st_api GET /rest/cluster/pending/devices | pending_devices_tsv)
  fi
  if [[ -z "$rows" ]]; then
    say "대기 중인 연결 요청이 없다."
    say "  · 폰 Syncthing-Fork > 기기 > + 에 맥 Device ID($(cat "$MULGIL_HOME/mac-device-id.txt" 2>/dev/null || echo '?'))를 넣었는가"
    say "  · 폰과 맥이 같은 Wi-Fi이고 폰 앱이 '실행 중'인가 (Wi-Fi 조건 확인)"
    say "  · 1분 뒤 다시: bash $0 accept   (폰 ID를 알면: bash $0 accept <폰-ID>)"
    return 0
  fi

  while IFS=$'\t' read -r id name addr t; do
    [[ -n "$id" ]] || continue
    if [[ "$id" == "$me" ]]; then continue; fi
    if [[ "$name" == "-" ]]; then name=""; fi
    say ""
    say "연결 요청: ${name:-이름없음}  ($addr  $t)"
    say "  ID: $id"
    if st_api GET "/rest/config/devices/$id" >/dev/null 2>&1; then
      ok "이미 등록된 기기"
    else
      if ! confirm "이 기기를 내 폰으로 수락할까?"; then say "  건너뜀"; continue; fi
      st_api POST /rest/config/devices "$(jq -n --arg d "$id" --arg nm "${name:-phone}" \
        '{deviceID: $d, name: $nm, addresses: ["dynamic"], autoAcceptFolders: false, introducer: false}')" >/dev/null
      ok "기기 추가"
    fi
    folder_add_device "$id"
    n=$(( n + 1 ))
  done <<EOF
$rows
EOF

  # 폰이 다른 폴더 ID로 공유했으면 알려 준다
  local pf
  pf=$(st_api GET /rest/cluster/pending/folders 2>/dev/null | jq -r --arg f "$FOLDER_ID" 'to_entries[] | select(.key != $f) | .key' || true)
  if [[ -n "$pf" ]]; then
    warn "폰이 다른 폴더 ID로 공유 중: $(printf '%s' "$pf" | tr '\n' ' ')"
    warn "폰에서 그 폴더를 지우고, 폴더 ID를 '$FOLDER_ID'로 다시 만들어라 (다른 ID는 맥이 받지 않는다)."
  fi
  if (( n > 0 )); then say ""; say "다음: 녹음 1건 후 'bash $0 status' 로 연결·폴더 상태 확인."; fi
  return 0
}

cmd_status() {
  need_mac
  st_init
  st_api GET /rest/system/ping >/dev/null 2>&1 || die "Syncthing이 응답하지 않는다 ('brew services restart syncthing')."
  local me devs stats conns now
  me=$(st_my_id)
  devs=$(st_api GET /rest/config/devices)
  stats=$(st_api GET /rest/stats/device)
  conns=$(st_api GET /rest/system/connections)
  now=$(date +%s)

  step "기기"
  jq -rn --arg me "$me" --argjson devs "$devs" --argjson stats "$stats" --argjson conns "$conns" '
    $devs[] | select(.deviceID != $me) | .deviceID as $id |
    ($conns.connections[$id] // {}) as $c |
    def nz: if . == null or . == "" then "-" else tostring end;
    [ (.name | nz), ($id[0:7]),
      (if $c.connected then "연결됨" else "끊김" end),
      ($c.type | nz),
      (if $c.connected | not then "-" elif $c.isLocal then "LAN" else "WAN" end),
      ($c.address | nz),
      ($stats[$id].lastSeen | nz) ] | @tsv' |
  while IFS=$'\t' read -r name sid st typ lan addr seen; do
    local age="-" se
    se=$(iso_to_epoch "$seen")
    if [[ -n "$se" ]] && (( se > 31536000 )); then age="$(( (now - se) / 60 ))분 전"; fi
    say "  $name ($sid…)  $st  $typ  $lan  $addr  lastSeen=$seen ($age)"
    case "$typ" in *relay*) warn "릴레이 경유 연결 — §5.9-4 위반. 'bash $0' 를 다시 실행해 릴레이를 끈다." ;; esac
  done
  if [[ "$(printf '%s' "$devs" | jq --arg me "$me" '[.[] | select(.deviceID != $me)] | length')" == "0" ]]; then
    warn "등록된 폰이 없다 → bash $0 accept"
  fi
  local relay
  relay=$(st_api GET /rest/config/options | jq -r '.relaysEnabled')
  say "  relaysEnabled=$relay"

  step "폴더 $FOLDER_ID"
  if ! st_folder_exists; then warn "폴더 없음 → bash $0"; return 0; fi
  st_api GET "/rest/db/status?folder=$FOLDER_ID" | jq -r '
    "  상태=\(.state // "-")  전체 파일=\(.globalFiles // "-")  로컬=\(.localFiles // "-")  받을 것=\(.needFiles // "-")  에러=\(.errors // 0)  pullErrors=\(.pullErrors // 0)" +
    (if (.error // "") != "" then "\n  폴더 에러: \(.error)" else "" end)'
  local errs
  errs=$(st_api GET "/rest/folder/errors?folder=$FOLDER_ID" | jq -r '(.errors // [])[] | "  ✗ \(.path): \(.error)"' || true)
  if [[ -n "$errs" ]]; then say "$errs"; else ok "파일 에러 없음"; fi

  step "inbox"
  local cnt last=0 f a
  cnt=0
  while IFS= read -r -d '' f; do
    cnt=$(( cnt + 1 )); a=$(file_arrival "$f"); if (( a > last )); then last=$a; fi
  done < <(list_m4a)
  if (( cnt == 0 )); then
    warn "m4a 0건. 폰이 '연결됨'인데 0이면 폰의 '모든 파일 접근' 권한이나 녹음 저장 경로를 의심(§5.2 (b))."
  else
    say "  m4a ${cnt}건, 마지막 도착 $(fmt_local "$last") ($(( (now - last) / 60 ))분 전)"
  fi
}

list_m4a() { # NUL 구분
  [[ -d "$INBOX" ]] || return 0
  find "$INBOX" -type f \( -iname '*.m4a' \) -not -path '*/.stversions/*' -not -name '.syncthing.*' -print0
}

cmd_check() {
  need_mac
  command -v ffprobe >/dev/null 2>&1 || die "ffprobe 없음 → brew install ffmpeg"
  [[ -d "$INBOX" ]] || die "$INBOX 없음 → 먼저 'bash $0'"
  local now cut f out dur ct ce mt ar cls ds dv
  local c_s=0 c_v=0 c_n=0 c_s9=0 c_v9=0 c_o=0 c_a=0 total=0 recent=0
  now=$(date +%s); cut=$(( now - WINDOW_H * 3600 ))

  say "D0 2번(녹음 시각) · 3번(도착) 판정 — 허용 오차 ±${TOL}초, 도착 창 ${WINDOW_H}시간"
  say "  시작추정 = mtime − duration.  Δ시작 = creation_time − 시작추정,  Δ저장 = creation_time − mtime"
  say ""
  printf '%-28s %6s  %-14s %-14s %-14s %8s %8s  %-9s %s\n' \
    "파일" "길이s" "creation_time" "mtime(종료)" "도착" "Δ시작" "Δ저장" "판정" "도착지연"
  while IFS= read -r -d '' f; do
    total=$(( total + 1 ))
    out=$(ffprobe -v error -show_entries format=duration:format_tags=creation_time \
            -of default=noprint_wrappers=1 "$f" 2>/dev/null | parse_ffprobe)
    dur="${out%%|*}"; ct="${out#*|}"
    ce=$(iso_to_epoch "$ct")
    mt=$(file_mtime "$f"); ar=$(file_arrival "$f")
    read -r cls ds dv <<<"$(classify_ctime "$ce" "$mt" "${dur:-0}" "$TOL")"
    case "$cls" in
      start) c_s=$(( c_s + 1 )) ;; save) c_v=$(( c_v + 1 )) ;; none) c_n=$(( c_n + 1 )) ;;
      start+9h) c_s9=$(( c_s9 + 1 )) ;; save+9h) c_v9=$(( c_v9 + 1 )) ;;
      ambiguous) c_a=$(( c_a + 1 )) ;; *) c_o=$(( c_o + 1 )) ;;
    esac
    if (( ar >= cut )); then recent=$(( recent + 1 )); fi
    local ctd="${ct:--}"
    if [[ -n "$ce" ]] && (( ce > 31536000 )); then ctd=$(fmt_local "$ce"); fi
    local name; name=$(basename "$f")
    if (( ${#name} > 28 )); then name="${name:0:25}..."; fi
    printf '%-28s %6s  %-14s %-14s %-14s %8s %8s  %-9s %s\n' \
      "$name" "${dur:-?}" "$ctd" "$(fmt_local "$mt")" "$(fmt_local "$ar")" "$ds" "$dv" "$cls" "$(( (ar - mt) / 60 ))분"
  done < <(list_m4a)

  say ""
  if (( total == 0 )); then
    say "m4a가 없다. 폰에서 녹음 후 'bash $0 status' 로 연결부터 확인."
    return 0
  fi
  conclude "$c_s" "$c_v" "$c_n" "$c_s9" "$c_v9" "$c_o" "$c_a"
  if (( c_a > 0 && c_a < total )); then
    warn "${c_a}건은 너무 짧아(≤$(( 2 * TOL ))초) 판정에서 뺐다. 결론은 나머지 $(( total - c_a ))건 기준."
  fi
  say "도착(D0 3번): 최근 ${WINDOW_H}시간 ${recent}건 / 전체 ${total}건 — 테스트 녹음 3건이 모두 보여야 통과. 1건이라도 없으면 G2 전환(§5.3)."
  say "mtime(종료) 열이 폰에서 정지를 누른 시각과 1분 안으로 맞는지 메모와 대조하라."
}

cmd_help() {
  cat <<'USAGE'
d0-mac.sh — 물길 D0 맥 쪽 자동화
  bash d0-mac.sh          설치·Syncthing 설정 (멱등)
  bash d0-mac.sh accept   폰 연결 요청 수락 → mulgil-phone 폴더 공유   (accept <폰-ID> 도 됨)
  bash d0-mac.sh status   폰 lastSeen·연결 방식·폴더 상태/에러·inbox 건수
  bash d0-mac.sh check    m4a creation_time 판정(D0 2번) + 6시간 내 도착 건수(D0 3번)
환경변수: D0_DRY_RUN=1  D0_YES=1  D0_TOL=90  D0_WINDOW_H=6  MULGIL_INBOX=~/Mulgil/inbox/phone
USAGE
}

main() {
  local c="${1:-setup}"
  add_brew_path
  [[ $# -gt 0 ]] && shift
  case "$c" in
    setup)  cmd_setup ;;
    accept) cmd_accept "$@" ;;
    status) cmd_status ;;
    check)  cmd_check ;;
    help|-h|--help) cmd_help ;;
    *) cmd_help; die "알 수 없는 명령: $c" ;;
  esac
}

# 시험(tests/d0-mac.test.sh)은 D0_LIB=1 로 source 해서 함수만 읽는다
if [[ "${D0_LIB:-0}" != "1" ]]; then main "$@"; fi
