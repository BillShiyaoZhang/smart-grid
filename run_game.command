#!/bin/zsh
# Launch from Finder, with the editor installed on this Mac.
cd "${0:A:h}"
if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  exec /Applications/Godot.app/Contents/MacOS/Godot --path "$PWD"
elif command -v godot >/dev/null 2>&1; then
  exec godot --path "$PWD"
elif command -v godot4 >/dev/null 2>&1; then
  exec godot4 --path "$PWD"
else
  print "请先安装 Godot 4.7，或在 Godot 中导入 project.godot 后按 F5 运行。"
  read "REPLY?按回车关闭。"
fi
