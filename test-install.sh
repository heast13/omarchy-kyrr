#!/bin/bash
# Test install for the rebuild (goes again before it reaches main): kyrr from
# the build "kyrr-linux.zip" in ~/Downloads, the widget from the branch
# "rebuild". Run it again after each new build.
set -euo pipefail

zip=$(ls -t "$HOME"/Downloads/kyrr-linux*.zip 2>/dev/null | head -n1 || true)
[[ -n $zip ]] || { echo "kyrr-linux.zip fehlt in ~/Downloads."; exit 1; }

echo "== kyrr aus $zip"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$zip" -d "$tmp"
app=$(ls "$tmp"/kyrr-*-x86_64.AppImage | head -n1)
mkdir -p "$HOME/.local/bin"
install -m 755 "$app" "$HOME/.local/bin/kyrr.new"
mv -f "$HOME/.local/bin/kyrr.new" "$HOME/.local/bin/kyrr"

echo "== Plugin, Zweig rebuild"
dir="$HOME/.config/omarchy/plugins/io.github.heast13.kyrr"
if [[ ! -d $dir/.git ]]; then
  omarchy plugin add https://github.com/heast13/omarchy-kyrr.git --yes
fi
git -C "$dir" fetch -q origin rebuild
git -C "$dir" checkout -q -B rebuild FETCH_HEAD
omarchy plugin enable io.github.heast13.kyrr >/dev/null 2>&1 || true
omarchy-restart-shell >/dev/null 2>&1 || true

echo "== kyrr starten"
sleep 2
setsid -f "$HOME/.local/bin/kyrr" --replace --background >/dev/null 2>&1
echo "Fertig. Klick auf das kyrr-Symbol rechts oben in der Leiste."
