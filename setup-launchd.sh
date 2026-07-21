#!/bin/bash
# setup-launchd.sh — runCLAUDErun 대체: 순정 macOS launchd로 briefing(9시)·notify(10시) 등록
#
# runCLAUDErun의 "바깥 claude가 스크립트를 백그라운드로 던지고 세션 종료 → 미완주" 문제를 근본 제거.
# launchd는 스크립트를 직접 자식 프로세스로 실행하고 완주까지 붙잡는다. 슬립 중 예정시각이 지나면
# 깨어날 때 자동으로 놓친 잡을 실행한다.
# 모던 macOS에선 레거시 launchctl load/unload가 StartCalendarInterval을 안정적으로 안 건다 →
# launchctl bootstrap/bootout(gui 도메인) 사용.
#
# ⚠️ 반드시 그 Mac의 "GUI 로그인 세션 안 Terminal"에서 실행할 것(키체인·launchd gui 도메인 필요).
#
# 사용법:
#   chmod +x setup-launchd.sh
#   ./setup-launchd.sh          # 설치/갱신
#   ./setup-launchd.sh test     # 프로덕션 무관 셀프테스트(launchd가 잡을 완주하는지)
#   ./setup-launchd.sh status   # 상태 확인
#   ./setup-launchd.sh remove   # 제거
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LA="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"
BRIEF="com.claudenews.briefing"
NOTIFY="com.claudenews.notify"
ACTION="${1:-install}"

la_load()   { launchctl bootout "$DOMAIN" "$1" 2>/dev/null || true; launchctl bootstrap "$DOMAIN" "$1"; }
la_unload() { launchctl bootout "$DOMAIN" "$1" 2>/dev/null || true; }

status() {
  echo "=== launchd 상태 ==="
  launchctl list 2>/dev/null | grep -E "claudenews|PID" || echo "  (등록된 claudenews 잡 없음)"
  echo "=== plist 파일 ==="
  ls -la "$LA/$BRIEF.plist" "$LA/$NOTIFY.plist" 2>/dev/null || echo "  (plist 없음)"
}

remove() {
  for L in "$BRIEF" "$NOTIFY"; do
    la_unload "$LA/$L.plist"
    rm -f "$LA/$L.plist"
    echo "removed: $L"
  done
  echo "→ macOS 설정 > 일반 > 로그인 항목 및 확장 프로그램 > '백그라운드에서 허용'의 잔여 bash 항목은 재부팅 시 정리됨."
}

write_plist() {   # $1=label $2=script $3=hour $4=minute
  cat > "$LA/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>WorkingDirectory</key><string>$REPO</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>exec ./$2</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>$3</integer>
    <key>Minute</key><integer>$4</integer>
  </dict>
  <key>StandardOutPath</key><string>$REPO/logs/launchd-$1.out</string>
  <key>StandardErrorPath</key><string>$REPO/logs/launchd-$1.err</string>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST
}

install() {
  mkdir -p "$LA" "$REPO/logs"
  chmod +x "$REPO"/run-briefing.sh "$REPO"/run-notify.sh "$REPO"/generate.sh "$REPO"/publish.sh "$REPO"/notify.sh 2>/dev/null || true
  write_plist "$BRIEF" run-briefing.sh 9 0
  write_plist "$NOTIFY" run-notify.sh 10 0
  for L in "$BRIEF" "$NOTIFY"; do
    la_load "$LA/$L.plist"
    echo "loaded: $L  ($REPO)"
  done
  echo ""
  echo "✅ 설치 완료. 매일 09:00 briefing, 10:00 notify(평일)."
  echo "   ⚠️ runCLAUDErun의 briefing/notify 태스크는 이제 비활성화하세요(중복 방지)."
  echo "   ⚠️ Mac 잠자기 방지(Amphetamine 또는 pmset) 유지 필요."
  echo "   ℹ️ 설정 > 로그인 항목에 'bash' 백그라운드 항목 2개가 보이는 건 정상(briefing·notify 잡)."
  echo ""
  status
}

selftest() {
  # 프로덕션 무관 검증: launchd가 예약시각에 잡을 실행하고 "끝까지 완주"하는지 확인.
  # 실제 briefing 대신 45초짜리 무해한 잡(마커만 기록). generate/publish/git/src 미접촉.
  local L="com.claudenews.selftest"
  local MARKER="$REPO/logs/launchd-selftest.marker"
  local JOB="$REPO/logs/launchd-selftest-job.sh"
  mkdir -p "$REPO/logs"; rm -f "$MARKER"
  cat > "$JOB" <<JOBEOF
#!/bin/bash
echo "START \$(date '+%F %T')" > "$MARKER"
sleep 45
echo "END \$(date '+%F %T')" >> "$MARKER"
JOBEOF
  chmod +x "$JOB"
  local TH TM
  TH=$(date -v+2M +%H); TM=$(date -v+2M +%M)
  cat > "$LA/$L.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$L</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$JOB</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$((10#$TH))</integer><key>Minute</key><integer>$((10#$TM))</integer></dict>
  <key>StandardOutPath</key><string>$REPO/logs/launchd-selftest.out</string>
  <key>StandardErrorPath</key><string>$REPO/logs/launchd-selftest.err</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST
  la_load "$LA/$L.plist"
  echo "테스트 잡 예약: ${TH}:${TM} (캘린더 트리거 + 45초 완주 검증). 프로덕션 무관 — 마커만 기록."
  echo "최대 ~3.5분 대기 중..."
  local ok=0 i
  for i in $(seq 1 42); do
    if grep -q END "$MARKER" 2>/dev/null; then ok=1; break; fi
    sleep 5
  done
  echo ""
  if [ "$ok" -eq 1 ] && grep -q START "$MARKER" 2>/dev/null; then
    echo "✅ 통과: launchd가 예약시각에 잡을 실행하고 45초를 끝까지 완주함(START+END 마커)."
    echo "   → runCLAUDErun의 '백그라운드로 던지고 종료' 실패가 launchd에선 발생하지 않음을 확인."
    sed 's/^/     /' "$MARKER"
  else
    echo "❌ 실패: END 마커 없음(완주 못 함). GUI 로그인 세션 Terminal인지·logs/launchd-selftest.err·예약시각 경과 확인."
    sed 's/^/     /' "$MARKER" 2>/dev/null || echo "     (마커 없음 = 트리거 자체 실패)"
  fi
  la_unload "$LA/$L.plist"
  rm -f "$LA/$L.plist" "$JOB" "$MARKER" "$REPO/logs/launchd-selftest.out" "$REPO/logs/launchd-selftest.err"
  echo "테스트 정리 완료(실제 잡·콘텐츠·라이브 무영향). 설정의 잔여 bash 항목은 재부팅 시 정리됨."
}

case "$ACTION" in
  install) install ;;
  status)  status ;;
  test)    selftest ;;
  remove)  remove ;;
  *) echo "usage: $0 [install|status|test|remove]"; exit 1 ;;
esac
