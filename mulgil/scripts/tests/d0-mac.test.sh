#!/usr/bin/env bash
# d0-mac.sh 단위 시험 — 리눅스에서 실행 (macOS 전용 부분은 가짜 curl·D0_ALLOW_NONMAC 로 대신한다)
#   bash tests/d0-mac.test.sh
# shellcheck disable=SC1007,SC2317,SC2034,SC1091  # 시험 파일: 가짜 curl·서브셸 내 전역 재지정은 의도된 것
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../d0-mac.sh"
# shellcheck source=../d0-mac.sh
D0_LIB=1 source "$SCRIPT"
set +e   # 시험 본체는 실패를 직접 센다

PASS=0; FAIL=0
eq() { # eq 이름 기대 실제
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL %s\n  기대: %q\n  실제: %q\n' "$1" "$2" "$3"; fi
}
has() { # has 이름 부분문자열 실제
  if [[ "$3" == *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL %s\n  포함 기대: %s\n  실제: %s\n' "$1" "$2" "$3"; fi
}

# ── parse_ffprobe ──
eq "ffprobe 기본" "3125|2026-11-23T05:12:34.000000Z" \
  "$(printf 'duration=3125.482000\nTAG:creation_time=2026-11-23T05:12:34.000000Z\n' | parse_ffprobe)"
eq "ffprobe CRLF·순서 반대" "61|2026-11-23T05:12:34.000000Z" \
  "$(printf 'TAG:creation_time=2026-11-23T05:12:34.000000Z\r\nduration=61.9\r\n' | parse_ffprobe)"
eq "ffprobe 태그 없음" "42|" "$(printf 'duration=42.000000\n' | parse_ffprobe)"
eq "ffprobe N/A" "|" "$(printf 'duration=N/A\n' | parse_ffprobe)"
eq "ffprobe 1904" "10|1904-01-01T00:00:00.000000Z" \
  "$(printf 'duration=10.5\nTAG:creation_time=1904-01-01T00:00:00.000000Z\n' | parse_ffprobe)"
eq "ffprobe 마지막 줄 개행 없음" "7|x" "$(printf 'duration=7.1\nTAG:creation_time=x' | parse_ffprobe)"
eq "ffprobe 첫 값 우선" "5|a" "$(printf 'duration=5\nduration=9\nTAG:creation_time=a\nTAG:creation_time=b\n' | parse_ffprobe)"

# ── iso_to_epoch ──
eq "iso Z+소수" "1763874754" "$(iso_to_epoch 2025-11-23T05:12:34.000000Z)"
eq "iso 공백" "1763874754" "$(iso_to_epoch '2025-11-23 05:12:34')"
eq "iso 빈값" "" "$(iso_to_epoch '')"
eq "iso 쓰레기" "" "$(iso_to_epoch 'garbage')"
has "iso 1904 음수" "-2082844800" "$(iso_to_epoch 1904-01-01T00:00:00.000000Z)"
eq "iso +09:00 (Syncthing lastSeen)" "1763874754" "$(iso_to_epoch 2025-11-23T14:12:34+09:00)"
eq "iso 소수+오프셋" "1763874754" "$(iso_to_epoch 2025-11-23T14:12:34.3256277+09:00)"
eq "iso -0500" "1763874754" "$(iso_to_epoch 2025-11-23T00:12:34-0500)"
eq "iso 잘못된 꼬리" "" "$(iso_to_epoch 2025-11-23T05:12:34junk)"

# ── classify_ctime ── mtime=종료 B+100000, duration=3000 → 시작 B+97000
B=1790000000; M=$((B+100000)); D=3000
eq "시작"       "start 10 -2990"      "$(classify_ctime $((B+97010)) $M $D 90)"
eq "저장"       "save 3005 5"         "$(classify_ctime $((B+100005)) $M $D 90)"
eq "없음"       "none - -"            "$(classify_ctime '' $M $D 90)"
eq "0"          "none - -"            "$(classify_ctime 0 $M $D 90)"
eq "1904"       "none - -"            "$(classify_ctime -2082844800 $M $D 90)"
eq "시작+9h"    "start+9h 32400 29400" "$(classify_ctime $((B+97000+32400)) $M $D 90)"
eq "저장-9h"    "save+9h -29400 -32400" "$(classify_ctime $((B+100000-32400)) $M $D 90)"
eq "짧은 녹음"  "ambiguous 120 60"      "$(classify_ctime $((B+60)) $B 60 90)"
eq "불일치"     "other 1000 -2000"    "$(classify_ctime $((B+98000)) $M $D 90)"
eq "duration 빈값 → 구분 불가" "ambiguous 0 0"         "$(classify_ctime $B $B '' 0)"

# ── conclude ──
has "결론 시작" "creation_time을 그대로" "$(conclude 3 0 0 0 0 0 0)"
has "결론 저장" "creation_time − duration" "$(conclude 0 3 0 0 0 0 1)"
has "결론 없음" "mtime − duration" "$(conclude 0 0 3 0 0 0 0)"
has "결론 +9h" "−9h 보정" "$(conclude 0 0 0 2 0 0 0)"
has "결론 혼재" "혼재" "$(conclude 2 1 0 0 0 0 0)"
has "결론 짧음" "너무 짧다" "$(conclude 0 0 0 0 0 0 3)"

# ── config.xml 파싱 ──
T=$(mktemp -d)
cat > "$T/config.xml" <<'XML'
<configuration version="51">
    <folder id="default" label="Default Folder" path="/x" type="sendreceive">
        <device id="AAAA" introducedBy=""></device>
    </folder>
    <device id="AAAA" name="mac" compression="metadata">
        <address>dynamic</address>
    </device>
    <gui enabled="true" tls="false" sendBasicAuthPrompt="false">
        <address>127.0.0.1:8384</address>
        <apikey>abcDEF123-xyz</apikey>
        <theme>default</theme>
    </gui>
</configuration>
XML
eq "apikey" "abcDEF123-xyz" "$(xml_apikey "$T/config.xml")"
eq "gui address (device address 무시)" "127.0.0.1:8384" "$(xml_gui_address "$T/config.xml")"
eq "tls false" "http" "$(xml_gui_tls "$T/config.xml")"
sed 's/tls="false"/tls="true"/' "$T/config.xml" > "$T/tls.xml"
eq "tls true" "https" "$(xml_gui_tls "$T/tls.xml")"
eq "addr 0.0.0.0" "127.0.0.1:8384" "$(normalize_addr 0.0.0.0:8384)"
eq "addr [::]" "127.0.0.1:9000" "$(normalize_addr '[::]:9000')"
eq "addr 그대로" "127.0.0.1:8384" "$(normalize_addr 127.0.0.1:8384)"

# config 후보 탐색 (리눅스 2.x 경로)
eq "config 탐색 XDG_STATE" "$T/home/.local/state/syncthing/config.xml" \
  "$(mkdir -p "$T/home/.local/state/syncthing" && cp "$T/config.xml" "$T/home/.local/state/syncthing/" && HOME="$T/home" XDG_STATE_HOME= XDG_CONFIG_HOME= STHOMEDIR= STCONFDIR= st_find_config)"
eq "config 탐색 macOS 우선" "$T/home/Library/Application Support/Syncthing/config.xml" \
  "$(mkdir -p "$T/home/Library/Application Support/Syncthing" && cp "$T/config.xml" "$T/home/Library/Application Support/Syncthing/" && HOME="$T/home" XDG_STATE_HOME= STHOMEDIR= STCONFDIR= st_find_config)"

# ── JSON ──
eq "pending tsv" $'PHONE-ID\tGalaxy S24\t192.168.0.5:22000\t2026-11-23T05:00:00Z' \
  "$(printf '{"PHONE-ID":{"time":"2026-11-23T05:00:00Z","name":"Galaxy S24","address":"192.168.0.5:22000"}}' | pending_devices_tsv)"
eq "pending 빈" "" "$(printf '{}' | pending_devices_tsv)"
eq "pending 이름 없음 → - (열 밀림 방지)" $'P\t-\t1.2.3.4:22000\t-' \
  "$(printf '{"P":{"name":"","address":"1.2.3.4:22000"}}' | pending_devices_tsv)"
is_device_id ABCDEFG-ABCDEFG-ABCDEFG-ABCDEFG-ABCDEFG-ABCDEFG-ABCDEFG-ABCDEF2; eq "device id 형식 ok" 0 $?
is_device_id 'ABC/../x'; eq "device id 형식 거부" 1 $?
INBOX=/in; eq "folder new" "mulgil-phone receiveonly true simple 10 0 /in ME" \
  "$(folder_json_new ME | jq -r '"\(.id) \(.type) \(.ignoreDelete) \(.versioning.type) \(.versioning.params.keep) \(.versioning.params.cleanoutDays) \(.path) \(.devices[0].deviceID)"')"
eq "folder patch: devices·path 안 건드림" "false false receiveonly" \
  "$(folder_json_patch | jq -r '"\(has("devices")) \(has("path")) \(.type)"')"

# ── 가짜 Syncthing으로 accept/status ──
export D0_ALLOW_NONMAC=1 D0_YES=1
FAKE="$T/fake"; mkdir -p "$FAKE"; : > "$FAKE/log"
printf '{"PHONE-ID":{"time":"2026-11-23T05:00:00Z","name":"Galaxy","address":"192.168.0.5:22000"}}' > "$FAKE/pending"
printf '{"id":"mulgil-phone","path":"/in","type":"receiveonly","ignoreDelete":true,"versioning":{"type":"simple"},"devices":[{"deviceID":"MAC-ID"}]}' > "$FAKE/folder"
curl() { # 마지막 인자가 URL. 메서드·경로·본문을 로그에 남긴다
  local m=GET body="" url=""
  while (( $# )); do
    case "$1" in -X) m="$2"; shift 2 ;; --data-binary) body="$2"; shift 2 ;; -H|--max-time) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac
  done
  local p="${url#http://127.0.0.1:8384}"
  printf '%s %s %s\n' "$m" "$p" "$body" >> "$FAKE/log"
  case "$m $p" in
    "GET /rest/system/ping") echo '{"ping":"pong"}' ;;
    "GET /rest/system/status") echo '{"myID":"MAC-ID"}' ;;
    "GET /rest/config/folders/mulgil-phone") cat "$FAKE/folder" ;;
    "PATCH /rest/config/folders/mulgil-phone") jq -c --argjson b "$body" '. + $b' "$FAKE/folder" > "$FAKE/f2" && mv "$FAKE/f2" "$FAKE/folder" ;;
    "GET /rest/cluster/pending/devices") cat "$FAKE/pending" ;;
    "GET /rest/cluster/pending/folders") echo '{"abcd-1234":{"offeredBy":{}}}' ;;
    "GET /rest/config/devices/PHONE-ID") [[ -f "$FAKE/dev" ]] && cat "$FAKE/dev" || return 22 ;;
    "POST /rest/config/devices") printf '%s' "$body" > "$FAKE/dev" ;;
    "GET /rest/config/devices") printf '[{"deviceID":"MAC-ID","name":"mac"},%s]' "$(cat "$FAKE/dev")" ;;
    "GET /rest/stats/device") echo '{"PHONE-ID":{"lastSeen":"2026-11-23T14:10:00+09:00","lastConnectionDurationS":10}}' ;;
    "GET /rest/system/connections") echo '{"connections":{"PHONE-ID":{"connected":true,"type":"tcp-server","isLocal":true,"address":"192.168.0.5:22000"}}}' ;;
    "GET /rest/config/options") echo '{"relaysEnabled":false}' ;;
    "GET /rest/db/status?folder=mulgil-phone") echo '{"state":"idle","globalFiles":3,"localFiles":3,"needFiles":0,"errors":0,"pullErrors":0,"error":""}' ;;
    "GET /rest/folder/errors?folder=mulgil-phone") echo '{"folder":"mulgil-phone","errors":[{"path":"a.m4a","error":"permission denied"}]}' ;;
    *) return 22 ;;
  esac
}
FH="$T/home"; rm -rf "$FH/Library"   # 리눅스 경로의 config.xml 사용
out=$(HOME="$FH"; MULGIL_HOME="$T/mh"; INBOX="$T/inbox-empty"; cmd_accept 2>&1)
has "accept: 수락" "기기 추가" "$out"
has "accept: 폴더 공유" "이 기기와 공유" "$out"
has "accept: 다른 폴더 ID 경고" "abcd-1234" "$out"
eq  "accept: 폴더 devices" "MAC-ID,PHONE-ID" "$(jq -r '[.devices[].deviceID]|join(",")' "$FAKE/folder")"
out=$(HOME="$FH"; MULGIL_HOME="$T/mh"; INBOX="$T/inbox-empty"; cmd_accept 2>&1)
has "accept: 멱등(이미 등록)" "이미 등록된 기기" "$out"
has "accept: 멱등(이미 공유)" "이미 공유됨" "$out"
eq  "accept: 중복 없음" "MAC-ID,PHONE-ID" "$(jq -r '[.devices[].deviceID]|join(",")' "$FAKE/folder")"
out=$(HOME="$FH"; INBOX="$T/inbox-empty"; cmd_status 2>&1)
has "status: 연결" "Galaxy (PHONE-I…)  연결됨  tcp-server  LAN" "$out"
has "status: lastSeen 오프셋 해석" "분 전)" "$out"
has "status: 폴더" "상태=idle" "$out"
has "status: 파일 에러" "a.m4a: permission denied" "$out"
has "status: 녹음 0 경고" "m4a 0건" "$out"
unset -f curl

# ── check: 실제 ffmpeg로 만든 m4a ──
if command -v ffmpeg >/dev/null 2>&1; then
  IN="$T/inbox"; mkdir -p "$IN/.stversions"
  now=$(date +%s)
  mk() { # 이름 길이(초) creation_time(epoch|빈값) mtime(epoch)
    local meta=()
    if [[ -n "$3" ]]; then meta=(-metadata "creation_time=$(date -u -d "@$3" +%Y-%m-%dT%H:%M:%S.000000Z)"); fi
    ffmpeg -v error -y -f lavfi -i "anullsrc=r=16000:cl=mono" -t "$2" -c:a aac "${meta[@]}" "$IN/$1"
    touch -d "@$4" "$IN/$1"
  }
  # 시작 시각 기록형 3건
  mk "음성 001.m4a" 300 $((now-3600-300)) $((now-3600))
  mk "음성 002.m4a" 400 $((now-1800-400)) $((now-1800))
  mk "음성 003.m4a" 200 $((now-600-200)) $((now-600))
  cp "$IN/음성 001.m4a" "$IN/.stversions/old.m4a"; : > "$IN/.syncthing.x.m4a.tmp"
  out=$(INBOX="$IN"; cmd_check 2>&1)
  has "check: 시작 결론" "creation_time = 녹음 시작 시각" "$out"
  has "check: 6시간 3건(.stversions·tmp 제외)" "최근 6시간 3건 / 전체 3건" "$out"
  # 저장 시각형으로 바꿔 보기
  rm -f "$IN"/*.m4a
  mk "s1.m4a" 300 $((now-100)) $((now-100))
  mk "s2.m4a" 300 $((now-200)) $((now-200))
  out=$(INBOX="$IN"; cmd_check 2>&1)
  has "check: 저장 결론" "creation_time = 저장 시각" "$out"
  rm -f "$IN"/*.m4a
  mk "n1.m4a" 300 "" $((now-100))
  out=$(INBOX="$IN"; cmd_check 2>&1)
  has "check: 태그 없음 결론" "mtime − duration" "$out"
  printf '%s\n' "$out" | sed 's/^/    | /' | head -8
else
  echo "SKIP check e2e (ffmpeg 없음)"
fi

rm -rf "$T"
printf '\n통과 %d · 실패 %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
