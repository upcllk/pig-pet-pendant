#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo '请在 macOS 上执行此脚本，其他系统不能编译 AppKit。' >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo '未找到 swiftc。请先执行 xcode-select --install 安装 Apple Command Line Tools。' >&2
  exit 1
fi
APP="$PWD/dist/PigPendant.app"
TARGET="$(uname -m)-apple-macosx12.0"
mkdir -p "$PWD/dist"
BUILD_DIR="$(mktemp -d "$PWD/dist/.build.XXXXXX")"
PREFERENCES_BACKUP=""
PREFERENCES_EXISTED=false
SMOKE_DOMAIN=""
domain_exists() {
  local domains
  domains="$(defaults domains)" || return
  printf '%s\n' "$domains" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -Fx "$1" >/dev/null
}
restore_and_cleanup() {
  local result=$?
  if [[ -n "$PREFERENCES_BACKUP" ]]; then
    if [[ "$PREFERENCES_EXISTED" == true ]]; then
      defaults import local.pigpendant.mac "$PREFERENCES_BACKUP" || result=1
    elif domain_exists local.pigpendant.mac; then
      defaults delete local.pigpendant.mac || result=1
    fi
  fi
  if [[ -n "$SMOKE_DOMAIN" ]]; then
    "$VALIDATION_APP/Contents/MacOS/PigPendant" --cleanup-preferences --preferences-suite "$SMOKE_DOMAIN" || result=1
  fi
  rm -rf "$BUILD_DIR"
  exit "$result"
}
trap restore_and_cleanup EXIT
SOURCES=()
while IFS= read -r -d '' source; do
  SOURCES+=("$source")
done < <(find PigPendant -name '*.swift' -type f -print0)
swiftc -O -target "$TARGET" -framework AppKit -framework AudioToolbox -framework CoreAudio -framework Foundation -framework ImageIO "${SOURCES[@]}" -o "$BUILD_DIR/PigPendant"
plutil -lint PigPendant/Info.plist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp PigPendant/Info.plist "$APP/Contents/Info.plist"
cp PigPendant/Resources/pig.png "$APP/Contents/Resources/pig.png"
cp PigPendant/Resources/balloon.png "$APP/Contents/Resources/balloon.png"
cp PigPendant/Resources/net-pig.png "$APP/Contents/Resources/net-pig.png"
cp PigPendant/Resources/bamboo-pig.png "$APP/Contents/Resources/bamboo-pig.png"
cp PigPendant/Resources/hanging-pig.png "$APP/Contents/Resources/hanging-pig.png"
cp PigPendant/Resources/ghost-pig.png "$APP/Contents/Resources/ghost-pig.png"
cp PigPendant/Resources/status-pig.png "$APP/Contents/Resources/status-pig.png"
cp PigPendant/Resources/status-pig-spin.gif "$APP/Contents/Resources/status-pig-spin.gif"
mv "$BUILD_DIR/PigPendant" "$APP/Contents/MacOS/PigPendant"
chmod +x "$APP/Contents/MacOS/PigPendant"
# 使用 ad-hoc 本地签名；没有 Apple Developer 账号也可以自用。
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
cmp PigPendant/Resources/pig.png "$APP/Contents/Resources/pig.png"
cmp PigPendant/Resources/balloon.png "$APP/Contents/Resources/balloon.png"
cmp PigPendant/Resources/net-pig.png "$APP/Contents/Resources/net-pig.png"
cmp PigPendant/Resources/bamboo-pig.png "$APP/Contents/Resources/bamboo-pig.png"
cmp PigPendant/Resources/hanging-pig.png "$APP/Contents/Resources/hanging-pig.png"
cmp PigPendant/Resources/ghost-pig.png "$APP/Contents/Resources/ghost-pig.png"
cmp PigPendant/Resources/status-pig.png "$APP/Contents/Resources/status-pig.png"
cmp PigPendant/Resources/status-pig-spin.gif "$APP/Contents/Resources/status-pig-spin.gif"
ARCHIVE="$PWD/dist/PigPendant-macOS-$(uname -m).zip"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/PigPendant.zip"
mv "$BUILD_DIR/PigPendant.zip" "$ARCHIVE"
printf '\n✅ 编译完成：%s\n' "$APP"
printf '应用压缩包：%s\n' "$ARCHIVE"
printf '启动命令：open "%s"\n' "$APP"
if [[ "${1:-}" == "--test" ]]; then
  if domain_exists local.pigpendant.mac; then
    BACKUP="$PWD/dist/test-preferences-$(date +%Y%m%d-%H%M%S)-$$.plist"
    defaults export local.pigpendant.mac "$BACKUP"
    PREFERENCES_EXISTED=true
    PREFERENCES_BACKUP="$BACKUP"
  else
    PREFERENCES_BACKUP="$PWD/dist/test-preferences-$(date +%Y%m%d-%H%M%S)-$$.absent"
    printf 'Preference domain did not exist before testing.\n' > "$PREFERENCES_BACKUP"
  fi
  swift run --scratch-path "$PWD/dist/swiftpm" -c release -Xswiftc -enable-testing PigPendantCoreChecks
  TEST_SOURCES=()
  while IFS= read -r -d '' source; do
    TEST_SOURCES+=("$source")
  done < <(find Tests/Smoke -name '*.swift' -type f -print0)
  VALIDATION_APP="$PWD/dist/PigPendantValidation.app"
  ditto "$APP" "$VALIDATION_APP"
  swiftc -O -D TESTING -target "$TARGET" -framework AppKit -framework AudioToolbox -framework CoreAudio -framework Foundation -framework ImageIO \
    "${SOURCES[@]}" "${TEST_SOURCES[@]}" Tests/Core/PhysicsTests.swift -o "$BUILD_DIR/PigPendantValidation"
  mv "$BUILD_DIR/PigPendantValidation" "$VALIDATION_APP/Contents/MacOS/PigPendant"
  codesign --force --sign - "$VALIDATION_APP"
  codesign --verify --strict "$VALIDATION_APP"
  SMOKE_DOMAIN="local.pigpendant.smoke-tests.$(uuidgen)"
  "$VALIDATION_APP/Contents/MacOS/PigPendant" --smoke-test --preferences-suite "$SMOKE_DOMAIN"
fi
