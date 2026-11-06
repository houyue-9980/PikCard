#!/bin/zsh
# 编译并重新打开拾卡：先编译，再退出正在运行的旧版本（确认真的退出了），最后打开新版本。
# 用法：tools/run-app.sh [启动参数…]
set -e
cd "${0:A:h}/.."

# 编译目录名以 .noindex 结尾：系统不会索引它，编译出来的开发版就不会跑进启动台
xcodebuild -project PikCard.xcodeproj -scheme PikCard -configuration Debug -derivedDataPath build/DerivedData.noindex -quiet build

APP=build/DerivedData.noindex/Build/Products/Debug/PikCard.app
# 只管开发版（build/…/Debug/PikCard.app），不碰装在“应用程序”里的正式版
running() { pgrep -f "Debug/PikCard.app/Contents/MacOS/PikCard" >/dev/null }

if running; then
  osascript -e 'tell application id "io.github.houyue9980.pikcard.dev" to quit' >/dev/null 2>&1 || true
  for i in {1..10}; do running || break; sleep 0.5; done
fi
if running; then
  echo "⚠️ 旧版本还开着（可能有面板没关），请先手动退出拾卡（⌘Q），再运行一次。" >&2
  exit 1
fi

open "$APP" --args "$@"
echo "✅ 已打开新版本"
