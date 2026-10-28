#!/bin/bash
# Runs update.sh against stub commands (curl, omarchy, git, setsid, ...) in a
# temporary HOME and checks what it called, in what order. Nothing is
# installed and nothing leaves the machine.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin" "$work/fuse" "$work/tools"
log=$work/calls.log

# The only real commands update.sh may reach, so the machine running the
# test (a FUSE package, say) cannot change the outcome.
for tool in bash sh mktemp rm sha256sum mkdir install mv cat cut awk dirname env; do
  ln -s "$(command -v $tool)" "$work/tools/$tool"
done

# Stubs: each writes one line to the call log. Behaviour is switched by
# FAKE_* variables, per case.
stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$work/bin/$1"
  chmod +x "$work/bin/$1"
}

stub curl '
echo "curl $*" >>"$FAKE_LOG"
[ -z "${FAKE_CURL_FAIL:-}" ] || exit 22
for a in "$@"; do url=$a; done
name=${url##*/}
case $name in
*.sha256)
  if [ -n "${FAKE_BAD_SUM:-}" ]; then sum=$(echo tampered | sha256sum | cut -d" " -f1)
  else sum=$(sha256sum kyrr-x86_64.AppImage | cut -d" " -f1); fi
  echo "$sum  kyrr-x86_64.AppImage" >"$name" ;;
*) echo "fake kyrr" >"$name" ;;
esac'
stub omarchy '
echo "omarchy $*" >>"$FAKE_LOG"
case "$1 $2" in
"plugin update") [ -z "${FAKE_UPDATE_FAIL:-}" ] ;;
"plugin remove") [ -z "${FAKE_REMOVE_FAIL:-}" ] ;;
"plugin add") [ -z "${FAKE_ADD_FAIL:-}" ] ;;
esac'
stub git 'echo "git $*" >>"$FAKE_LOG"; [ -z "${FAKE_GITHUB_DOWN:-}" ]'
stub setsid 'echo "setsid $*" >>"$FAKE_LOG"'
printf '#!/bin/bash\nexit 0\n' >"$work/fuse/fusermount3"
chmod +x "$work/fuse/fusermount3"
stub omarchy-restart-shell 'echo "omarchy-restart-shell" >>"$FAKE_LOG"'

fails=0
fail() {
  echo "FAIL  $case_name: $1"
  echo "      calls: $(tr '\n' '|' <"$log")"
  fails=$((fails + 1))
}

# run <name> <mode> [VAR=value ...]: a fresh HOME (prepared by `prep`, if
# the case defines one), then update.sh <mode>.
prep() { :; }
run() {
  case_name=$1 mode=$2
  shift 2
  rm -rf "${work:?}/home" "$log"
  mkdir -p "$work/home"
  : >"$log"
  prep
  out=$(env -i PATH="$work/bin:${FUSE_DIR-$work/fuse}:$work/tools" HOME="$work/home" TMPDIR="$work" FAKE_LOG="$log" "$@" \
    bash "$root/update.sh" "$mode" 2>&1)
  code=$?
  prep() { :; }
}

called() { grep -q -- "$1" "$log"; }
expect_called() { called "$1" || fail "expected a call matching: $1"; }
expect_not_called() { ! called "$1" || fail "unexpected call matching: $1"; }
expect_code() { [ "$code" -eq "$1" ] || fail "exit code $code, expected $1 (output: $out)"; }
# The calls in this order, other lines between them allowed.
expect_order() {
  local at=0 pattern line
  for pattern in "$@"; do
    line=$(awk -v p="$pattern" -v from="$at" 'NR > from && index($0, p) { print NR; exit }' "$log")
    [ -n "$line" ] || { fail "expected '$pattern' after line $at"; return; }
    at=$line
  done
}
expect_kyrr() { [ "$(cat "$work/home/.local/bin/kyrr" 2>/dev/null)" = "fake kyrr" ] || fail "kyrr was not installed"; }
expect_no_kyrr() { [ ! -e "$work/home/.local/bin/kyrr" ] || fail "kyrr was installed"; }
expect_clean_tmp() { ! compgen -G "$work/tmp.*" >/dev/null || fail "download folder left behind"; }

url=https://github.com/heast13/kyrr/releases/latest/download
id=io.github.heast13.kyrr
repo=https://github.com/heast13/omarchy-kyrr.git

run "install" install
expect_code 0
expect_order "curl -fLO $url/kyrr-x86_64.AppImage" "curl -fLO $url/kyrr-x86_64.AppImage.sha256" "setsid -f $work/home/.local/bin/kyrr --replace --background"
expect_kyrr
expect_not_called "omarchy "
expect_not_called "omarchy-restart-shell"
expect_clean_tmp

FUSE_DIR="" run "install without FUSE says so" install
expect_code 0
echo "$out" | grep -q "needs FUSE" || fail "no FUSE note"
expect_kyrr
run "install with FUSE stays quiet" install
echo "$out" | grep -q "needs FUSE" && fail "FUSE note although fusermount3 is there"

run "update" update
expect_code 0
expect_kyrr
expect_order "setsid -f $work/home/.local/bin/kyrr" "omarchy plugin update $id --yes" "omarchy-restart-shell"
expect_not_called "omarchy plugin remove"
expect_not_called "omarchy plugin add"
expect_clean_tmp

run "update, plugin update fails: cloned again, shell restarts" update FAKE_UPDATE_FAIL=1
expect_code 0
expect_kyrr
expect_order "omarchy plugin update $id --yes" "git ls-remote $repo" "omarchy plugin remove $id --yes" "omarchy plugin add $repo --yes --enable" "omarchy-restart-shell"

run "update, plugin update fails and GitHub is down: plugin kept" update FAKE_UPDATE_FAIL=1 FAKE_GITHUB_DOWN=1
expect_code 1
expect_kyrr
expect_not_called "omarchy plugin remove"
expect_not_called "omarchy-restart-shell"
echo "$out" | grep -q "kyrr is updated, but this menu plugin is not" || fail "no line about the plugin"

run "update, plugin update and add both fail: one clear line, no restart" update FAKE_UPDATE_FAIL=1 FAKE_ADD_FAIL=1
expect_code 1
expect_kyrr
expect_order "omarchy plugin remove $id --yes" "omarchy plugin add $repo --yes --enable"
expect_not_called "omarchy-restart-shell"
[ "$(echo "$out" | grep -c "kyrr is updated, but this menu plugin is not")" = 1 ] || fail "not exactly one line about the plugin"

# A link to a development checkout is never removed.
prep() {
  mkdir -p "$work/home/.config/omarchy/plugins" "$work/dev"
  ln -s "$work/dev" "$work/home/.config/omarchy/plugins/$id"
}
run "update, plugin is a development link: left alone" update FAKE_UPDATE_FAIL=1
expect_code 1
expect_not_called "omarchy plugin remove"
expect_not_called "omarchy-restart-shell"

run "checksum mismatch: kyrr untouched, nothing else" update FAKE_BAD_SUM=1
[ "$code" -ne 0 ] || fail "exit code 0 on a checksum mismatch"
expect_no_kyrr
expect_not_called "setsid"
expect_not_called "omarchy"
expect_clean_tmp

prep() {
  mkdir -p "$work/home/.local/bin"
  echo "old kyrr" >"$work/home/.local/bin/kyrr"
}
run "checksum mismatch keeps the kyrr that was there" update FAKE_BAD_SUM=1
[ "$code" -ne 0 ] || fail "exit code 0 on a checksum mismatch"
[ "$(cat "$work/home/.local/bin/kyrr")" = "old kyrr" ] || fail "the old kyrr was replaced"
[ ! -e "$work/home/.local/bin/kyrr.new" ] || fail "kyrr.new left behind"

run "download fails: nothing else" update FAKE_CURL_FAIL=1
[ "$code" -ne 0 ] || fail "exit code 0 on a failed download"
expect_no_kyrr
expect_not_called "setsid"
expect_not_called "omarchy"
expect_clean_tmp

run "install, download fails" install FAKE_CURL_FAIL=1
[ "$code" -ne 0 ] || fail "exit code 0 on a failed download"
expect_no_kyrr

run "unknown mode" bogus
expect_code 2
expect_not_called "curl"

if [ "$fails" -gt 0 ]; then
  echo "$fails update flow check(s) failed"
  exit 1
fi
echo "update flow: all cases pass"
