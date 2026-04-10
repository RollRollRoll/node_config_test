#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./vps_tools.sh

assert_ok() {
  local fn="$1"
  shift
  if "$fn" "$@"; then
    printf 'PASS: %s %s\n' "$fn" "$*"
  else
    printf 'FAIL: %s %s\n' "$fn" "$*" >&2
    exit 1
  fi
}

assert_fail() {
  local fn="$1"
  shift
  if "$fn" "$@"; then
    printf 'FAIL: %s %s should fail\n' "$fn" "$*" >&2
    exit 1
  else
    printf 'PASS: %s %s failed as expected\n' "$fn" "$*"
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'PASS: %s => %s\n' "$label" "$actual"
  else
    printf 'FAIL: %s expected=%s actual=%s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_ok _fail2ban_should_enable ""
assert_ok _fail2ban_should_enable "y"
assert_ok _fail2ban_should_enable "Y"
assert_ok _fail2ban_should_enable "yes"
assert_fail _fail2ban_should_enable "n"
assert_fail _fail2ban_should_enable "no"
assert_fail _fail2ban_should_enable "maybe"

jail="$(_fail2ban_render_sshd_jail 2202)"
grep -q '^\[sshd\]$' <<<"$jail"
grep -q '^enabled = true$' <<<"$jail"
grep -q '^port = 2202$' <<<"$jail"
grep -q '^maxretry = 5$' <<<"$jail"
grep -q '^findtime = 10m$' <<<"$jail"
grep -q '^bantime = 1h$' <<<"$jail"
printf 'jail rendering checks passed\n'

tmpbin="$(mktemp -d)"
trap 'rm -rf "$tmpbin"' EXIT

printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpbin/apt-get"
chmod +x "$tmpbin/apt-get"
(PATH="$tmpbin"; assert_eq "apt" "$(_fail2ban_detect_package_manager)" "detect apt")
rm -f "$tmpbin/apt-get"

printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpbin/dnf"
chmod +x "$tmpbin/dnf"
(PATH="$tmpbin"; assert_eq "dnf" "$(_fail2ban_detect_package_manager)" "detect dnf")
rm -f "$tmpbin/dnf"

printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpbin/yum"
chmod +x "$tmpbin/yum"
(PATH="$tmpbin"; assert_eq "yum" "$(_fail2ban_detect_package_manager)" "detect yum")
rm -f "$tmpbin/yum"

(PATH="$tmpbin"; assert_eq "unknown" "$(_fail2ban_detect_package_manager)" "detect unknown")

printf 'ssh fail2ban helper checks passed\n'

grep -q '_setup_fail2ban_for_ssh()' ./vps_tools.sh
grep -q '\[7/7\] 配置 fail2ban' ./vps_tools.sh
grep -q '是否安装并启用 fail2ban 防暴力破解？\[Y/n\]:' ./vps_tools.sh
grep -q '_setup_fail2ban_for_ssh "$new_port"' ./vps_tools.sh

printf 'ssh fail2ban integration static checks passed\n'

grep -q '可选安装并启用 `fail2ban` 防暴力破解' ./README.md

printf 'ssh fail2ban readme checks passed\n'
