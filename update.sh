#!/bin/bash
# Installs or updates kyrr, run by Panel.qml in Omarchy's floating terminal so
# every step shows: the newest release and its checksum from GitHub, checked
# before anything runs. kyrr then takes over from a running one in the
# background, and the menu runs its first-run setup.
#
#   update.sh install   kyrr only
#   update.sh update    kyrr, then this plugin, then the shell restarts to load it
#
# It is a file of its own so tests/update-flow.test.sh can run it with stub
# commands.

case ${1:-} in
install | update) mode=$1 ;;
*)
  echo "usage: update.sh install|update" >&2
  exit 2
  ;;
esac

releases=https://github.com/heast13/kyrr/releases/latest/download/
plugin_id=io.github.heast13.kyrr
plugin_url=https://github.com/heast13/omarchy-kyrr.git

# The steps run in a subshell, so a failed one still ends in Omarchy's done
# message with its code, and the download folder always goes.
d=$(mktemp -d)
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
[ $r -eq 0 ] && [ "$mode" = update ] || exit $r

# An update of an installed kyrr brings this menu along, in the same window.
# `omarchy plugin update` cannot fast-forward a checkout with local changes
# or a detached head, and `omarchy plugin add` refuses a plugin that is
# installed, so the plugin is then removed and cloned again, provided GitHub
# answers (else the working copy would be lost for nothing) and it is not a
# link to a development checkout.
plugin_dir=~/.config/omarchy/plugins/$plugin_id
omarchy plugin update "$plugin_id" --yes || {
  echo "Updating the plugin did not work, fetching it again."
  [ ! -L "$plugin_dir" ] && git ls-remote "$plugin_url" HEAD >/dev/null &&
    omarchy plugin remove "$plugin_id" --yes &&
    omarchy plugin add "$plugin_url" --yes --enable
} || {
  echo "kyrr is updated, but this menu plugin is not: run 'omarchy plugin update $plugin_id'," >&2
  echo "or 'omarchy plugin add $plugin_url --enable' if it is gone." >&2
  exit 1
}

# The shell restarts to load it, detached and after two seconds so the window
# can still say it is done.
setsid -f sh -c 'sleep 2; omarchy-restart-shell' >/dev/null 2>&1
