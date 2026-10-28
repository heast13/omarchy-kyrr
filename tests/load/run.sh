#!/bin/bash
# The load test: Omarchy's Quickshell types, a bar with this plugin's widget in
# it, a fake kyrr, and a headless sway to show it on. For each screen size the
# menu is opened over Quickshell's IPC and every page of every state in
# states.mjs is looked at: measured (tests/load/shell.qml answers over IPC) and
# photographed. judge.mjs then says whether it passed.
#
# Usage: run.sh <omarchy checkout> <sizes, e.g. 1366x768,1920x1080> <out folder>
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../.." && pwd)
real_plugin=$plugin
omarchy=$(cd "$1" && pwd)
sizes=$2
out=$(mkdir -p "$3" && cd "$3" && pwd)

work=$(mktemp -d)
export HOME=$work/home
export XDG_RUNTIME_DIR=$work/run
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$work/bin" "$out/states"
chmod 700 "$XDG_RUNTIME_DIR"

pids=()
cleanup() {
  local code=$?
  # What the run's page needs to say why it failed.
  if [ "$code" -ne 0 ]; then
    echo "::group::quickshell log (first 40 lines, then the last 30)" >&2
    head -n 40 "$out/qs.log" >&2 || true
    echo "..." >&2
    tail -n 30 "$out/qs.log" >&2 || true
    echo "::endgroup::" >&2
    echo "::group::sway log (last 30 lines)" >&2
    tail -n 30 "$out/sway.log" >&2 || true
    echo "::endgroup::" >&2
  fi
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$work"
}
trap cleanup EXIT

log() { echo "[load] $*" >&2; }
# KYRR_BREAK=1 loads a copy of the plugin with a deliberate QML error, to show
# that this test can fail: the judge has to name the error.
if [ -n "${KYRR_BREAK:-}" ]; then
  plugin=$work/plugin
  mkdir -p "$plugin"
  cp "$real_plugin"/*.qml "$real_plugin"/*.js "$real_plugin"/update.sh "$plugin/"
  sed -i '$ d' "$plugin/Panel.qml"
  printf '  Rectangle { color: notDefinedAnywhere }\n}\n' >>"$plugin/Panel.qml"
fi

for name in metrics.jsonl qs.log commands.log run.log; do : >"$out/$name"; done

# ---- Omarchy's side: Commons and Ui next to the test shell, a theme, the font.
cfg=$work/qs
mkdir -p "$cfg"
cp -r "$omarchy/shell/Commons" "$omarchy/shell/Ui" "$cfg/"
cp "$here/shell.qml" "$cfg/"

theme=$HOME/.local/state/omarchy/current/theme
mkdir -p "$theme"
colors=$(find "$omarchy/themes" -name colors.toml -path '*tokyo-night*' | head -n 1)
[ -n "$colors" ] || colors=$(find "$omarchy/themes" -name colors.toml | head -n 1)
cp "$colors" "$theme/colors.toml"

# Omarchy sets its font through fontconfig's monospace, which Style.qml asks for.
mkdir -p "$HOME/.config/fontconfig"
cat >"$HOME/.config/fontconfig/fonts.conf" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias binding="same">
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
</fontconfig>
XML
log "monospace is $(fc-match monospace)"

# Style.qml asks Hyprland for the corner radius and the gaps; there is none.
cat >"$work/bin/hyprctl" <<'SH'
#!/bin/sh
case "$*" in
*rounding*) echo '{"int": 0}' ;;
*gaps_out*) echo '{"css": "10 10 10 10"}' ;;
esac
SH
chmod +x "$work/bin/hyprctl"

node "$here/states.mjs" "$out/states"

# ---- The pieces of a session.
qs() { quickshell -p "$cfg" "$@"; }
# A call that fails is written down, not fatal: judge.mjs reports what is missing.
ipc() { qs ipc call "$@" || log "ipc call $* failed"; }

start_sway() {
  export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
  sway >>"$out/sway.log" 2>&1 &
  sway_pid=$!
  pids+=("$sway_pid")
  for _ in $(seq 50); do
    [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break
    sleep 0.2
  done
  [ -S "$XDG_RUNTIME_DIR/wayland-1" ] || { log "sway did not start"; cat "$out/sway.log"; exit 1; }
  SWAYSOCK=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' | head -n 1)
  export SWAYSOCK
  # Quickshell's IPC only finds instances on the display it is told about.
  export WAYLAND_DISPLAY=wayland-1
  [ "$(swaymsg -t get_outputs | jq length)" -gt 0 ] || swaymsg create_output >/dev/null
  swaymsg "output * resolution $1 position 0 0" >/dev/null
  sleep 1
  log "outputs: $(swaymsg -t get_outputs | jq -c '[.[] | {name, w: .current_mode.width, h: .current_mode.height}]')"
}

stop_sway() {
  kill "$sway_pid" 2>/dev/null || true
  wait "$sway_pid" 2>/dev/null || true
  rm -f "$XDG_RUNTIME_DIR"/wayland-1* "$XDG_RUNTIME_DIR"/sway-ipc.*
}

start_qs() {
  env QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software NO_COLOR=1 \
    KYRR_PLUGIN_DIR="$plugin" KYRR_RUN_LOG="$out/run.log" PATH="$work/bin:$PATH" \
    quickshell -n -p "$cfg" >>"$out/qs.log" 2>&1 &
  qs_pid=$!
  pids+=("$qs_pid")
  local ready=""
  for _ in $(seq 60); do
    kill -0 "$qs_pid" 2>/dev/null || { log "quickshell died"; tail -n 40 "$out/qs.log"; return 1; }
    if metrics | jq -e '.loaded' >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.5
  done
  if [ -z "$ready" ]; then
    log "the widget never loaded"
    qs ipc show >&2 || true
    qs ipc call kyrrtest metrics >&2 || true
    quickshell list --all >&2 || true
    return 1
  fi
}

stop_qs() {
  kill "$qs_pid" 2>/dev/null || true
  wait "$qs_pid" 2>/dev/null || true
}

metrics() {
  local m
  m=$(qs ipc call kyrrtest metrics 2>/dev/null) || m=""
  if [ -n "$m" ]; then echo "$m"; else echo '{"loaded": false}'; fi
}

# Waits until the menu is open, and (if $1 is a pid) shows the state with it.
wait_for() {
  local want=$1 m
  for _ in $(seq 60); do
    m=$(metrics)
    if [ -n "$want" ]; then
      jq -e --argjson pid "$want" '.opened and .running and .pid == $pid and .panel.visible' <<<"$m" >/dev/null 2>&1 && return 0
    else
      jq -e '.opened and .rows > 0' <<<"$m" >/dev/null 2>&1 && return 0
    fi
    sleep 0.25
  done
  log "gave up waiting for the menu (wanted state ${want:-none}): $m"
}

slug() { echo "$1" | tr -c 'A-Za-z0-9\n' '-' | tr -s '-' | sed 's/^-//; s/-$//'; }

# ---- A first run without kyrr: the menu offers to install it.
phase_without_kyrr() {
  local size=$1 m
  log "without kyrr"
  start_qs
  ipc io.github.heast13.kyrr open >/dev/null
  for _ in $(seq 60); do
    m=$(metrics)
    jq -e '.rowIds | index("install")' <<<"$m" >/dev/null 2>&1 && break
    sleep 0.25
  done
  jq -cn --arg size "$size" --argjson m "$m" \
    '{size: $size, variant: "kyrr not installed", page: "main", scenario: "not-installed", metrics: $m}' >>"$out/metrics.jsonl"
  mkdir -p "$out/$size"
  grim "$out/$size/kyrr-not-installed.png"
  ipc kyrrtest activate install >/dev/null
  sleep 0.5
  stop_qs
}

# ---- The fake kyrr: a state file and a socket that writes down what it gets.
start_kyrr() {
  mkdir -p "$XDG_RUNTIME_DIR/kyrr" "$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/bin/kyrr"
  chmod +x "$HOME/.local/bin/kyrr"
  printf '#!/bin/sh\nprintf "%%s\\n" "$(cat)"\n' >"$work/sink.sh"
  chmod +x "$work/sink.sh"
  socat "UNIX-LISTEN:$XDG_RUNTIME_DIR/kyrr.sock,fork,unlink-early" "SYSTEM:$work/sink.sh >> $out/commands.log" &
  pids+=("$!")
  sleep 0.3
}

show_state() {
  local file=$1 id
  # In place, as kyrr writes it; a read in the middle is tried again.
  cat "$out/states/$file" >"$XDG_RUNTIME_DIR/kyrr/state"
  id=$(jq -r '.memos.sheet.id // .memos.list[0].id // empty' "$out/states/$file")
  if [ -n "$id" ]; then
    printf '%s\nMilch, Brot, Eier und Käse. Dazu noch Tomaten, Basilikum und ein Glas Oliven für das Wochenende, wenn alle zu Besuch kommen.\n' "$id" >"$XDG_RUNTIME_DIR/kyrr/sheet"
  fi
}

run_size() {
  local size=$1 first=$2 file pid variant pages page m geometry shot crop
  log "== $size"
  mkdir -p "$out/$size"
  start_sway "$size"
  [ -n "$first" ] && phase_without_kyrr "$size"
  start_kyrr
  start_qs
  # The bar alone, to tell later that a menu was drawn.
  grim "$out/$size/baseline.png"
  while IFS=$'\t' read -r file pid variant pages; do
    log "$size · $variant"
    ipc io.github.heast13.kyrr open >/dev/null
    show_state "$file"
    wait_for "$pid"
    crop=1
    case $variant in "sample as it is" | English) crop=0 ;; esac
    IFS=',' read -r -a list <<<"$pages"
    for page in "${list[@]}"; do
      ipc kyrrtest page "$page" >/dev/null
      sleep 0.6
      m=$(metrics)
      shot=$out/$size/$(slug "$variant")--$(slug "$page").png
      jq -cn --arg size "$size" --arg variant "$variant" --arg page "$page" --argjson pid "$pid" --argjson m "$m" \
        --arg shot "${shot#"$out"/}" --argjson full "$([ "$crop" = 0 ] && echo true || echo false)" \
        '{size: $size, variant: $variant, page: $page, pid: $pid, shot: $shot, full: $full, metrics: $m}' >>"$out/metrics.jsonl"
      geometry=""
      if [ "$crop" = 1 ]; then
        # The card with a margin, kept on the screen.
        geometry=$(jq -r '.panel | select(. != null)
          | ([.x - 12, 0] | max) as $x | ([.y - 12, 0] | max) as $y
          | "\($x),\($y) \([.contentWidth + 24, .screenW - $x] | min)x\([.contentHeight + 24, .screenH - $y] | min)"' <<<"$m" 2>/dev/null) || geometry=""
      fi
      if [ -n "$geometry" ]; then grim -g "$geometry" "$shot" || grim "$shot"; else grim "$shot"; fi
    done
    # The update button of a kyrr that cannot update itself runs update.sh.
    case $variant in *"not installable"*)
      ipc kyrrtest page main >/dev/null
      ipc kyrrtest activate install >/dev/null
      sleep 0.5
      ;;
    esac
  done <"$out/states/plan.tsv"
  stop_qs
  stop_sway
}

first=1
IFS=',' read -r -a size_list <<<"$sizes"
for size in "${size_list[@]}"; do
  run_size "$size" "$first"
  first=""
done

node "$here/judge.mjs" "$out"
