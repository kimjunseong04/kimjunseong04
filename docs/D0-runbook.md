# D0 런북 — 11/23(월)~24(화), 사람 손이 필요한 단계만

설계 근거: `docs/mulgil-design.md` §5.0(D0) · §5.2(Galaxy G1) · §5.5(Google OAuth) · §10.1(첫 이틀).
D0 1단계 게이트에서 끝낼 것은 **§5.0 0번(캘린더 감사) · 1번(OAuth 로그인 준비) · 2번(녹음 시각)** 이다.
3·4번(녹음 도착·Syncthing-Fork 생존)은 **설정과 첫 시험만** 하고 12/9까지 소크로 돌린다.

맥 쪽은 스크립트 하나(`mulgil/scripts/d0-mac.sh`)가 하고, 이 문서는 **폰과 Google 콘솔에서 사람이 눌러야 하는 것**만 순서대로 적는다.
전부 합쳐 약 60분: 맥 5분 · 폰 20분 · 콘솔 10분 · 감사 15분 · 녹음 시험(대기 포함) 반나절.

> 메뉴 이름은 One UI·앱 버전에 따라 조금 다를 수 있다. 못 찾으면 **설정 앱 상단 검색**에 굵게 쓴 낱말을 넣는다.

---

## ① 맥 — 명령 1줄 (5분)

저장소를 맥에 받아 둔 상태에서:

```bash
bash mulgil/scripts/d0-mac.sh
```

- [ ] 실행하면 먼저 **할 일 목록**을 출력한다. 미리 보기만 하려면 `D0_DRY_RUN=1 bash mulgil/scripts/d0-mac.sh`
- [ ] Homebrew가 없으면 설치할지 묻는다(맥 암호 1회). `syncthing ffmpeg jq` 설치, `brew services start syncthing`(로그인 시 자동 시작)
- [ ] `~/Mulgil/inbox/phone` 생성, Syncthing 폴더 `mulgil-phone` = **받기 전용 · 삭제 무시(ignoreDelete) · Simple 버전 관리**, **릴레이 끔**(§5.9-4)
- [ ] 끝에 **맥 Device ID**가 크게 찍히고 클립보드에도 복사된다(`~/Mulgil/mac-device-id.txt`에도 저장)
- [ ] 폰에서 QR로 읽으려면: 출력된 웹 UI 주소(`http://127.0.0.1:8384`) → 오른쪽 위 **작업 > ID 보기**

몇 번 다시 돌려도 같은 결과다(멱등). 다른 Syncthing 폴더·기기는 건드리지 않는다. 단 **릴레이 끔은 Syncthing 전역 옵션**이라 이 맥의 다른 기기 연결에도 적용된다(LAN·직접 연결만 남는다).

| 하위 명령 | 언제 |
|---|---|
| `bash mulgil/scripts/d0-mac.sh accept` | 폰에서 맥을 추가한 직후 (연결 요청 수락 + 폴더 공유) |
| `bash mulgil/scripts/d0-mac.sh status` | 폰 lastSeen · 연결 종류(`tcp-*`/`quic-*`/`relay-*`)와 `LAN`/`WAN` · 폴더 상태·에러 · inbox 건수 |
| `bash mulgil/scripts/d0-mac.sh check` | 녹음 3건 도착 후 (⑤ 참고) |

---

## ② 폰(Galaxy) — 20분

### ②-1 Syncthing-Fork 설치: **F-Droid 빌드 하나로 정한다**

- [ ] **배포처: F-Droid** — 패키지 `com.github.catfriend1.syncthingfork` (유지자 researchxxl)
  1. 폰 브라우저에서 <https://f-droid.org> → **F-Droid 앱 다운로드** → 설치(“출처를 알 수 없는 앱” 허용 1회)
  2. F-Droid에서 **Syncthing-Fork** 검색 → 설치 (직접 링크: <https://f-droid.org/packages/com.github.catfriend1.syncthingfork/>)
  3. 설치 후 **패키지명을 아래 기록표에 적는다**: 설정 > 애플리케이션 > Syncthing-Fork > (맨 아래) 앱 정보의 패키지명

  **왜 F-Droid인가 (§5.0-3, §5.2):**
  - Play 빌드(`com.github.catfriend1.syncthingandroid`, 게시자 nel0x)는 2026년에 **Play Protect가 v2.1.1.0을 유해 앱으로 표시**했다는 보고가 있다. Play Protect가 앱을 끄면 녹음 경로가 조용히 멈춘다(§5.2 위험 (c)).
  - 프로젝트 GitHub(researchxxl/syncthing-android) README는 빌드 받는 곳으로 **GitHub Releases와 F-Droid만** 안내한다. F-Droid에는 2026년에도 2.1.x 빌드가 올라온다.
  - 두 빌드는 **서명 키가 달라** 나중에 갈아타면 삭제·재설치·재설정이 필요하다. 그러니 처음부터 하나로 고정한다.
  - F-Droid 앱 하나로 업데이트 알림까지 받는다(Obtainium은 앱 하나를 더 설치·설정해야 한다).
- [ ] 같은 기기에 Play 빌드나 GitHub APK를 **섞어 설치하지 않는다**.
- [ ] 설치나 실행 중 **Play Protect 경고**가 뜨면 경고 화면에서 **“그래도 설치” / “앱 유지”**(세부정보 펼치기 안에 있을 수 있다)를 고르고, 그 사실을 기록표에 적는다. Play Protect 자체는 끄지 않는다.

### ②-2 첫 실행 마법사 (권한 3개)

- [ ] **모든 파일 접근 허용** → 켜기 (없으면 녹음 폴더를 못 읽는다. §5.2 위험 (b))
- [ ] **배터리 최적화 무시** → 허용
- [ ] **알림** → 허용 (상주 알림이 있어야 One UI가 덜 죽인다)

### ②-3 맥 추가 → 폴더 공유

- [ ] **기기** 탭 → **+** → Device ID 칸 옆 **QR 아이콘**으로 맥 웹 UI의 QR을 찍는다(또는 ①에서 복사한 ID를 카톡 나와의 채팅으로 보내 붙여넣기)
  - 이름: `mac` · 주소: `dynamic`(기본값 그대로) · 저장
- [ ] 맥에서: `bash mulgil/scripts/d0-mac.sh accept` → 표시된 폰 이름이 맞으면 `y`
  - 이 직후 폰에 **“mac이 폴더 ‘물길 폰 녹음’을 공유하려 한다”** 알림이 뜰 수 있다. **수락하지 말고 무시**한다. 수락하면 폰이 기본 경로에 같은 ID(`mulgil-phone`)의 폴더를 만들어 버려, 아래에서 녹음 폴더를 그 ID로 만들 수 없다. 이미 수락했다면 그 폴더를 폰에서 삭제한 뒤 아래 단계를 한다.
- [ ] **폴더** 탭 → **+**
  - 폴더 라벨: `물길 폰 녹음` (맥 쪽 라벨과 같게. 라벨은 표시용이라 달라도 동작에는 영향 없음)
  - **폴더 ID: `mulgil-phone`** ← 자동 생성된 값을 지우고 반드시 이걸로 바꾼다 (다르면 맥이 받지 않는다. `accept`가 다른 ID를 발견하면 경고한다)
  - 디렉터리: `/storage/emulated/0/Recordings/Voice Recorder` (폴더 선택기에서 내장 메모리 > Recordings > Voice Recorder)
  - 폴더 유형: **보내기 전용(Send Only)**
  - 공유: **mac** 켜기 → 저장
- [ ] 맥에서 `bash mulgil/scripts/d0-mac.sh status` → 폰이 **연결됨**이고 그 줄에 **`LAN`** 이 찍히는지 확인 (연결 종류는 `tcp-client`/`tcp-server`/`quic-client`/`quic-server` 중 하나. `relay-client`/`relay-server`가 보이면 릴레이 경유)

### ②-4 실행 조건 (Syncthing-Fork 설정 > **실행 조건**)

- [ ] **Wi-Fi에서만 실행**: 켬
- [ ] **종량제(데이터 절약) 네트워크에서 실행 안 함**: 켬
- [ ] **특정 Wi-Fi(SSID)로 제한**: **끔** — SSID를 읽으려면 위치 '항상 허용'이 필요하고, 위치를 끄는 순간 동기화가 조용히 멈춘다(§5.2)
- [ ] **충전 중에만 실행**: **끔**

### ②-5 One UI가 앱을 죽이지 못하게 (§5.2 최초 1회 체크리스트)

- [ ] 설정 > 애플리케이션 > Syncthing-Fork > 배터리 > **제한 없음**
- [ ] 설정 > 배터리(또는 디바이스 케어 > 배터리) > **백그라운드 사용 제한** > **절전 예외 앱**(Never sleeping apps) > + > Syncthing-Fork
  - 같은 화면의 “사용하지 않는 앱을 절전 상태로 전환”은 켜져 있어도 되지만, Syncthing-Fork가 절전 앱/깊은 절전 앱 목록에 **없는지** 확인
- [ ] 설정 > 애플리케이션 > Syncthing-Fork > **사용하지 않는 앱 관리**(또는 “앱을 사용하지 않으면 권한 삭제”) → **끔**
- [ ] 음성녹음 앱 > ⋮ > 설정 > 언어 → **자동 언어 감지 끄고 한국어** 고정(메뉴가 없으면 기록표에 “없음”)

### ②-6 캘린더 앱 정리 (§5.0-0, §12 확정 사항)

- [ ] **삼성 캘린더 > ≡ > 톱니(설정) > 새 일정 기본 캘린더(기본 캘린더)** → **Google 계정**의 캘린더로
- [ ] 삼성 캘린더 ≡ 목록에서 **삼성 계정 / 내 휴대전화** 캘린더에 일정이 있는지 본다. 있으면 일정마다 열어서 캘린더를 Google로 바꾸거나 지운다(④ 감사에서 몇 건이었는지 적는다)
- [ ] 설정 > 애플리케이션 > **캘린더**(삼성) > 알림 > **알림 허용 끔** (이중 알림 방지)
- [ ] Play 스토어에서 **Google Calendar** 설치(없다면) → 같은 Google 계정 로그인
- [ ] 설정 > 애플리케이션 > **Calendar**(Google) > 알림 > **알림 허용 켬**
- [ ] Google Calendar 앱 > ≡ > 설정 > 일반 > **이 기기에서 알림 받기**(Notify on this device) 켬

---

## ③ Google Cloud 콘솔 — 10분 (맥 브라우저, **개인 Google 계정**)

오른쪽 위 계정이 **캘린더를 쓰는 개인 계정**인지 먼저 본다(§12: 개인 계정으로 확정, Workspace 차단 위험 없음).

- [ ] **프로젝트 만들기**: <https://console.cloud.google.com/projectcreate>
  - 이름 `mulgil` → 만들기 → 상단 프로젝트 선택기가 `mulgil`인지 확인 (이후 모든 페이지가 이 프로젝트 기준)
- [ ] **Calendar API 사용**: <https://console.cloud.google.com/apis/library/calendar-json.googleapis.com> → **사용**
- [ ] **Tasks API 사용**: <https://console.cloud.google.com/apis/library/tasks.googleapis.com> → **사용**
- [ ] **OAuth 동의 화면(Google 인증 플랫폼)**: <https://console.cloud.google.com/auth/overview> → **시작하기**
  - 앱 정보: 앱 이름 `물길`, 사용자 지원 이메일 = 내 계정
  - 대상: **외부(External)**
  - 연락처 이메일 = 내 계정 → 정책 동의 → 만들기
  - 데이터 액세스(범위)는 **추가하지 않아도 된다**. 앱이 로그인 때 `calendar`·`tasks`를 요청한다(§5.5).
- [ ] **프로덕션 게시**: <https://console.cloud.google.com/auth/audience> → 게시 상태 **테스트 중** → **앱 게시** → 확인
  - [ ] 게시 상태가 **프로덕션 단계(In production)** 인지 **스크린샷**을 남긴다 (§5.0-1: 토큰 발급 **전**과 **후** 두 번 확인)
  - 검증(verification) 제출은 **하지 않는다**. 로그인할 때 “Google에서 확인하지 않은 앱” 경고가 뜨면 **고급 → 물길(으)로 이동(안전하지 않음)** 을 1회 누른다. 테스트 상태의 7일 토큰 만료를 피하는 것이 게시의 목적이다.
- [ ] **데스크톱 클라이언트 만들기**: <https://console.cloud.google.com/auth/clients/create>
  - 애플리케이션 유형: **데스크톱 앱** · 이름 `물길 mac` → 만들기
  - 뜨는 창에서 바로 **JSON 다운로드** (창을 닫으면 secret을 다시 못 받을 수 있다 → 그 경우 클라이언트를 새로 만든다)
- [ ] **JSON 저장** (맥 터미널):

  ```bash
  mkdir -p ~/Mulgil && chmod 700 ~/Mulgil
  set -- ~/Downloads/client_secret_*.json; [ $# -eq 1 ] && [ -f "$1" ] && [ ! -e ~/Mulgil/google-client.json ] \
    && mv "$1" ~/Mulgil/google-client.json && chmod 600 ~/Mulgil/google-client.json && echo OK
  ```

  - `OK`가 안 찍히면: 다운로드 폴더에 `client_secret_*.json`이 0개이거나 2개 이상이거나(옛 파일을 지우고 다시), `~/Mulgil/google-client.json`이 이미 있다(덮어쓰지 않는다. 옛 것을 확인 후 직접 지운다). zsh에서 파일이 0개면 `no matches found`가 뜨고 아무것도 옮기지 않는다.
  - ⚠️ 이 파일 내용을 **채팅·이슈·커밋에 붙이지 않는다.** 앱은 경로(`~/Mulgil/google-client.json`)만 읽는다.
  - (데스크톱 클라이언트의 secret은 구조상 비밀로 취급되지 않지만(§5.5), 그래도 공개 저장소에 올리지 않는다.)

로그인 자체(토큰 발급)는 1단계 앱이 처음 실행될 때 한다. 여기서는 **로그인할 준비**까지만 끝낸다.

---

## ④ 캘린더 충실도 감사 — 15분 (§5.0-0)

**범위: 11/9(월) ~ 11/22(일), 14일.** 타이머 15분을 켜고 시작한다.

1. **5분 — 복원**: 카톡 대화 목록(단톡·1:1)을 위에서부터 훑으며 “실제로 참석했거나 지켜야 했던 것”을 아래 표에 적는다. 수업·회의·동아리·해커톤·마감·약속. 카톡 톡캘린더, LMS 마감, 기억도 근거로 쓴다.
2. **5분 — 대조**: 맥 <https://calendar.google.com> 에서 해당 날짜를 보고 `Google에 있었나`를 채운다. 삼성 캘린더에만 있으면 `삼성/로컬`에 표시.
3. **5분 — 집계·정리**: 아래 식을 계산하고, 삼성 계정/휴대전화 캘린더의 일정을 Google로 옮긴다(②-6).

| # | 날짜 | 무엇 (회의·수업·마감) | 종류 | 근거 (카톡방/기억/LMS/톡캘린더) | Google에 있었나 (Y/N) | 있었다면 어느 캘린더 | 삼성/로컬에만 (Y/N) |
|---|---|---|---|---|---|---|---|
| 1 | 11/ |  |  |  |  |  |  |
| 2 | 11/ |  |  |  |  |  |  |
| 3 | 11/ |  |  |  |  |  |  |
| 4 | 11/ |  |  |  |  |  |  |
| 5 | 11/ |  |  |  |  |  |  |
| 6 | 11/ |  |  |  |  |  |  |
| 7 | 11/ |  |  |  |  |  |  |
| 8 | 11/ |  |  |  |  |  |  |
| 9 | 11/ |  |  |  |  |  |  |
| 10 | 11/ |  |  |  |  |  |  |
| 11 | 11/ |  |  |  |  |  |  |
| 12 | 11/ |  |  |  |  |  |  |
| 13 | 11/ |  |  |  |  |  |  |
| 14 | 11/ |  |  |  |  |  |  |
| 15 | 11/ |  |  |  |  |  |  |
| 16 | 11/ |  |  |  |  |  |  |
| 17 | 11/ |  |  |  |  |  |  |
| 18 | 11/ |  |  |  |  |  |  |
| 19 | 11/ |  |  |  |  |  |  |
| 20 | 11/ |  |  |  |  |  |  |

(모자라면 줄을 늘린다. 반복 수업은 회차마다 한 줄.)

| 집계 | 값 |
|---|---|
| 전체 건수 A |  |
| Google에 있었던 건수 B |  |
| **충실도 = B / A** | % |
| 삼성/로컬에만 있던 건수 |  |
| 톡캘린더에만 있던 건수 |  |

- [ ] **충실도 ≥ 70%** → 1단계 계획 그대로
- [ ] **충실도 < 70%** → 1단계 첫 작업을 **“카톡 → 일정 2탭”** 하나로 바꾸고 첫 주에는 그것만 만든다(§5.0-0)
- [ ] **측정 분모 미리 넣기(§10.1)**: 감사에서 나온 반복 모임(g1-teleop·gomap 주간 셀프 싱크, 동아리 정기 회의, 수업)을 Google Calendar에 **반복 일정**으로 넣는다. 해커톤은 기간 전체를 **종일 일정**으로 감싼다(§11-①)

---

## ⑤ 녹음 3건 시험과 `check` 판정 (§5.0-2·3·4)

### 녹음하기 (오늘 안에, 집 Wi-Fi 기준)

- [ ] 삼성 **음성녹음** 앱으로 3건. **각 4분 이상**(3분(180초) 이하는 허용 오차 ±90초 안에서 시작/저장 구분이 안 돼 `ambiguous`로 빠진다)
  - A: 5분 · B: 4분 · C: 6분 — **일시정지 없이**
- [ ] 녹음마다 폰 시계로 **시작 누른 시각 / 정지 시각 / 저장 탭 시각**을 메모한다(아래 표)
- [ ] 녹음 C를 마친 뒤 폰 화면을 끄고 그대로 둔다 → 2시간 뒤 `status`로 폰이 여전히 **연결됨**인지 본다(§5.0-4 생존 첫 시험)

| 녹음 | 시작 | 정지 | 저장 탭 | 맥 도착(check의 '도착') |
|---|---|---|---|---|
| A |  |  |  |  |
| B |  |  |  |  |
| C |  |  |  |  |

### 맥에서 확인 (녹음 후 6시간 안에)

```bash
bash mulgil/scripts/d0-mac.sh check
```

출력 표의 열:

| 열 | 뜻 |
|---|---|
| `creation_time` | m4a 안의 mvhd 시각(로컬 시간대로 표시). 없거나 0·1904면 `-` |
| `mtime(종료)` | Syncthing이 폰에서 그대로 가져온 수정 시각 = 보통 녹음 종료/저장 시각 |
| `도착` | 이 맥에 파일이 생긴 시각(macOS 파일 생성 시각) |
| `Δ시작` | creation_time − (mtime − duration). 0 근처면 creation_time = **시작** |
| `Δ저장` | creation_time − mtime. 0 근처면 creation_time = **저장** |
| `판정` | `start` / `save` / `none` / `start+9h` / `save+9h`(로컬 시각을 UTC로 적은 경우) / `ambiguous`(너무 짧음) / `other` |
| `도착지연` | 도착 − mtime (분). 폰→맥 동기화 지연 |

**판정 → 설계 분기 (§5.0-2, §5.1 [시각])**

| 결론 줄 | 할 일 |
|---|---|
| creation_time = 녹음 시작 시각 | 시각 1순위 = creation_time 그대로 |
| creation_time = 저장 시각 | 시작 = creation_time − duration |
| creation_time 없음/0/1904 | 시작 = mtime − duration |
| +9h (로컬시각을 UTC로 적음) | 설계에 없는 분기. −9h 보정 규칙을 설계 문서 §5.1에 추가로 적는다 |
| 혼재 | creation_time을 믿지 않고 mtime − duration. 표 전체를 설계 문서에 붙인다 |
| 판정 보류(너무 짧다) | 4분 이상으로 다시 녹음 |

**추가 확인**
- [ ] `mtime(종료)`가 메모한 **정지 또는 저장 탭 시각과 1분 안**인가 → 맞으면 “Syncthing이 mtime을 보존한다”는 G1 선택 근거(§5.2)가 확인된 것
- [ ] 결론 아래 `도착(D0 3번): 최근 6시간 N건` 이 **3건**인가 → **1건이라도 없으면 G2(FolderSync → SFTP, §5.3)로 전환**
- [ ] (학교에서 하루 한 번) `bash mulgil/scripts/d0-mac.sh status` → 폰이 **연결됨 + `LAN`** 인가
  - 학교 Wi-Fi에서 연결이 안 되면 → **“집 Wi-Fi에서만 동기화”로 확정**, 경보 임계 48시간. 릴레이는 켜지 않는다(§5.9-4)
  - 연결 종류에 `relay`가 보이면 `bash mulgil/scripts/d0-mac.sh`를 다시 돌린다(릴레이를 다시 끈다)

### 분기 결정 기록 (§10.1 D0 통과 조건 — 이 표가 채워져야 1단계로 간다)

| 항목 | 결정 | 근거·날짜 |
|---|---|---|
| 캘린더 경로 | Google API / (a) EventKit | 프로덕션 게시 스크린샷, 로그인 성공 여부 |
| 캘린더 충실도 | __ % → 1단계 계획 유지 / 카톡→일정 먼저 | ④ |
| Syncthing-Fork 배포처·패키지명 | F-Droid · `com.github.catfriend1.syncthingfork` | ②-1 |
| 녹음 시각 규칙 | start / save / none / +9h / 혼재 | ⑤ check 결론 |
| 동기화 범위 | 집·학교 모두 / 집 Wi-Fi 전용(임계 48h) | ⑤ status |
| 녹음 앱 언어 고정 | 가능 / 메뉴 없음 | ②-5 |
| 화면 끔 2시간 생존 | 통과 / 실패 → 절전 예외 재점검 | ⑤ |

---

## ⑥ 12/1(화) 토큰 확인 리마인더 (§5.0-1)

토큰은 1단계 앱이 **처음 Google 로그인한 날** 발급된다. 확인일 = **발급일 + 8일**.
11/23에 발급되면 12/1, 1단계 첫날(11/25)에 발급되면 **12/3**이다. 발급일을 아래에 적는다.

- [ ] 토큰 발급일: ____ → 확인일: ____
- [ ] **Google Calendar에 리마인더 넣기 (클릭 1번)** — 12/1 09:00~09:15 KST:
  <https://calendar.google.com/calendar/render?action=TEMPLATE&text=%EB%AC%BC%EA%B8%B8%20D0-1%20%ED%86%A0%ED%81%B0%208%EC%9D%BC%20%ED%99%95%EC%9D%B8&dates=20261201T000000Z/20261201T001500Z&details=%EB%AC%BC%EA%B8%B8%20%EC%95%B1%EC%9D%B4%20%EC%9E%AC%EB%A1%9C%EA%B7%B8%EC%9D%B8%20%EC%97%86%EC%9D%B4%20%EC%9D%BC%EC%A0%95%EC%9D%84%20%EB%B0%9B%EB%8A%94%EC%A7%80%2C%20Google%20%EC%9D%B8%EC%A6%9D%20%ED%94%8C%EB%9E%AB%ED%8F%BC%20%EA%B2%8C%EC%8B%9C%20%EC%83%81%ED%83%9C%EA%B0%80%20%ED%94%84%EB%A1%9C%EB%8D%95%EC%85%98%EC%9D%B8%EC%A7%80%20%ED%99%95%EC%9D%B8.%20invalid_grant%20%EB%A9%B4%20fix%3A%20D0-1>
  (발급일이 11/23이 아니면 열린 화면에서 날짜만 고친다)

**그날 할 것 (5분)**
- [ ] 물길 앱이 **다시 로그인하라는 말 없이** 최근 일정을 받아 오는가 (팝오버에 고장 문구가 없는가)
- [ ] <https://console.cloud.google.com/auth/audience> 게시 상태가 여전히 **프로덕션 단계**인가 (스크린샷 2번째)
- [ ] 결과
  - 정상 → D0-1 통과. 기록표 “캘린더 경로 = Google API” 확정
  - `invalid_grant` / 재로그인 요구 → 동결 예외 **`fix: D0-1`** 로 대체 경로 (a)(macOS 인터넷 계정 + EventKit 읽기 전용) 전환만 허용(§5.5, §10.3). 다른 코드는 손대지 않는다.

---

## 부록: 고장 났을 때 한 줄 처방

| 증상 (`status`) | 처방 |
|---|---|
| 폰 `끊김`, lastSeen이 오래됨 | 폰 Syncthing-Fork가 실행 중인지 → ②-5 절전 예외 다시 확인 |
| 폰 `연결됨`인데 m4a 0건 | 폰의 **모든 파일 접근** 권한이 풀렸는지, 녹음 저장 경로가 바뀌었는지 (§5.2 (b)) |
| 파일 에러 `permission denied` | 맥 `~/Mulgil/inbox/phone` 권한 확인, `bash mulgil/scripts/d0-mac.sh` 재실행 |
| `accept`가 “다른 폴더 ID로 공유 중” | 폰에서 그 폴더를 지우고 폴더 ID `mulgil-phone`으로 다시 만든다 |
| Syncthing API 응답 없음 | `brew services restart syncthing` → 그래도 안 되면 로그 `"$(brew --prefix)/var/log/syncthing.log"` 확인 |
| `status`에 `WAN`(LAN 아님)으로 연결됨 | 학교·공용 Wi-Fi의 기기 간 격리(AP isolation)일 수 있다. 릴레이는 켜지 않는다(§5.9-4) |
