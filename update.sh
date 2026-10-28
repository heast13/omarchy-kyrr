#!/bin/bash
# Installs or updates kyrr, run by Panel.qml in Omarchy's floating terminal so
# every step shows: the newest release and its checksum from GitHub, checked
# before anything runs. kyrr then takes over from a running one in the
# background, and the menu runs its first-run setup.
#
#   update.sh install   kyrr only
#   update.sh update    kyrr, then this plugin, then the shell restarts to load it
#   update.sh plugin    this plugin only (a new menu, kyrr as it is), then the shell restarts
#
# It is a file of its own so tests/update-flow.test.sh can run it with stub
# commands.

case ${1:-} in
install | update | plugin) mode=$1 ;;
*)
  echo "usage: update.sh install|update|plugin" >&2
  exit 2
  ;;
esac

releases=https://github.com/heast13/kyrr/releases/latest/download/
plugin_id=io.github.heast13.kyrr

# The steps run in a subshell, so a failed one still ends in Omarchy's done
# message with its code, and the download folder always goes.
r=0
if [ "$mode" != plugin ]; then
  d=$(mktemp -d) || exit 1
  (
    set -e
    cd "$d"
    curl -fLO "${releases}kyrr-x86_64.AppImage"
    curl -fLO "${releases}kyrr-x86_64.AppImage.sha256"
    sha256sum -c kyrr-x86_64.AppImage.sha256
    mkdir -p ~/.local/bin
    install -m 755 kyrr-x86_64.AppImage ~/.local/bin/kyrr.new
    mv -f ~/.local/bin/kyrr.new ~/.local/bin/kyrr
    command -v fusermount3 >/dev/null || command -v fusermount >/dev/null ||
      echo 'kyrr needs FUSE (package fuse3) to start.'
    setsid -f ~/.local/bin/kyrr --replace --background >/dev/null 2>&1
  )
  r=$?
  rm -rf "$d"
fi
[ $r -eq 0 ] && [ "$mode" != install ] || exit $r

# An update of an installed kyrr brings this menu along, in the same window;
# a new menu on its own (`plugin`) comes the same way.
# `omarchy plugin update` cannot fast-forward a checkout with local changes
# or a detached head; the checkout is then set to the newest commit in place,
# so the plugin stays enabled and keeps its place in the bar, and a commit
# that Omarchy refuses is undone again. Removing and adding it would lose
# both, and leave no menu at all when the add fails. A link to a development
# checkout stays as it is.
export GIT_TERMINAL_PROMPT=0
plugin_dir=~/.config/omarchy/plugins/$plugin_id
fetch_again() {
  [ ! -L "$plugin_dir" ] && [ -d "$plugin_dir/.git" ] || return 1
  echo "Updating the plugin did not work, fetching it again."
  git -C "$plugin_dir" fetch --quiet origin HEAD &&
    git -C "$plugin_dir" reset --quiet --hard FETCH_HEAD || return 1
  omarchy plugin validate "$plugin_dir" && return 0
  git -C "$plugin_dir" reset --quiet --hard ORIG_HEAD
  return 1
}
omarchy plugin update "$plugin_id" --yes || fetch_again || {
  case ${LANG:-}:$mode in
  de*:plugin) echo "Das Menü konnte nicht aktualisiert werden. Es läuft wie bisher weiter." >&2 ;;
  de*) echo "kyrr ist aktuell, aber das Menü konnte nicht aktualisiert werden. Es läuft wie bisher weiter." >&2 ;;
  *:plugin) echo "The menu could not be updated. It keeps working as before." >&2 ;;
  *) echo "kyrr is up to date, but the menu could not be updated. It keeps working as before." >&2 ;;
  esac
  exit 1
}

# The shell restarts to load it, detached and after two seconds so the window
# can still say it is done.
setsid -f sh -c 'sleep 2; omarchy-restart-shell' >/dev/null 2>&1
