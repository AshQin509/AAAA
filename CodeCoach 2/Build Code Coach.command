#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ./scripts/build-app.sh; then
    echo "完成：请打开 build 文件夹中的 CodeCoach.app。"
else
    echo "构建失败。请确认已安装 Xcode 或 Command Line Tools，详见 README。"
fi
read -r -p "按回车关闭…"
