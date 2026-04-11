# SSH 客户端配置管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `vps_tools.sh` 中新增菜单选项 12，提供带子菜单的 SSH 客户端 `~/.ssh/config` 管理功能（列出/添加更新/删除 Host 条目）。

**Architecture:** 在 `vps_tools.sh` 中新增 6 个纯辅助函数（`_ssh_cfg_*`，接受 `config_file` 参数以支持测试）和 2 个交互函数（`_ssh_cfg_do_add`、`_ssh_cfg_do_delete`），加上子菜单主循环 `do_ssh_config`。全部函数插入在 `show_menu()` 之前，命名风格与现有 `_desktop_*`、`_fw_*` 保持一致。测试文件 `tests/test_ssh_config_helpers.sh` 覆盖所有可测辅助函数及静态集成检查。

**Tech Stack:** Bash, awk, ssh-keygen, grep

---

## 文件结构

| 操作 | 文件 | 说明 |
|------|------|------|
| 修改 | `vps_tools.sh` | 插入全部新函数；更新 `show_menu()` 和 `main()` |
| 新建 | `tests/test_ssh_config_helpers.sh` | 辅助函数单元测试 + 静态集成检查 |
| 修改 | `README.md` | 功能总览 + 菜单功能说明追加第 12 项 |

新函数插入位置：`vps_tools.sh` 第 2749 行（`show_menu()` 定义之前）。

---

### Task 1: `_ssh_cfg_host_exists` 和 `_ssh_cfg_write_block` + 测试

**Files:**
- Modify: `vps_tools.sh`（在 `show_menu()` 前插入）
- Create: `tests/test_ssh_config_helpers.sh`

- [ ] **Step 1: 创建测试文件骨架并写第一批失败测试**

新建 `tests/test_ssh_config_helpers.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./vps_tools.sh

assert_ok() {
  local fn="$1"; shift
  if "$fn" "$@"; then
    printf 'PASS: %s %s\n' "$fn" "$*"
  else
    printf 'FAIL: %s %s\n' "$fn" "$*" >&2; exit 1
  fi
}

assert_fail() {
  local fn="$1"; shift
  if "$fn" "$@"; then
    printf 'FAIL: %s %s should fail\n' "$fn" "$*" >&2; exit 1
  else
    printf 'PASS: %s %s failed as expected\n' "$fn" "$*"
  fi
}

assert_contains() {
  local pattern="$1"
  local input="$2"
  local label="$3"
  if grep -q "$pattern" <<< "$input"; then
    printf 'PASS: %s contains "%s"\n' "$label" "$pattern"
  else
    printf 'FAIL: %s does not contain "%s"\n' "$label" "$pattern" >&2
    printf 'actual output:\n%s\n' "$input" >&2
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1"
  local input="$2"
  local label="$3"
  if grep -q "$pattern" <<< "$input"; then
    printf 'FAIL: %s should NOT contain "%s"\n' "$label" "$pattern" >&2
    exit 1
  else
    printf 'PASS: %s does not contain "%s"\n' "$label" "$pattern"
  fi
}

# 所有测试使用同一个临时目录，EXIT 时统一清理
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── _ssh_cfg_host_exists 测试 ────────────────────────────────
tmpconf="${TMPDIR_TEST}/config1"
touch "$tmpconf"

# 空文件：任何 host 都找不到
assert_fail _ssh_cfg_host_exists "$tmpconf" "my-vps"

# 写入一个 Host 块
cat > "$tmpconf" <<'EOF'
Host my-vps
    HostName 1.2.3.4
    User root
    Port 2222
    IdentitiesOnly yes
    IdentityFile ~/.ssh/my-vps
EOF

assert_ok   _ssh_cfg_host_exists "$tmpconf" "my-vps"
assert_fail _ssh_cfg_host_exists "$tmpconf" "other-vps"
# 不能误匹配前缀子串
assert_fail _ssh_cfg_host_exists "$tmpconf" "my"

printf 'ssh_cfg_host_exists checks passed\n'

# ── _ssh_cfg_write_block 测试 ────────────────────────────────
tmpconf2="${TMPDIR_TEST}/config2"
touch "$tmpconf2"

# 不启用代理
_ssh_cfg_write_block "$tmpconf2" "dev" "10.0.0.1" "ubuntu" "22" "~/.ssh/dev" "0"
out="$(cat "$tmpconf2")"
assert_contains "^Host dev$"              "$out" "write_block Host"
assert_contains "HostName 10.0.0.1"       "$out" "write_block HostName"
assert_contains "User ubuntu"             "$out" "write_block User"
assert_contains "Port 22"                 "$out" "write_block Port"
assert_contains "IdentitiesOnly yes"      "$out" "write_block IdentitiesOnly"
assert_contains "IdentityFile ~/.ssh/dev" "$out" "write_block IdentityFile"
assert_not_contains "ProxyCommand"        "$out" "write_block no ProxyCommand when use_proxy=0"

# 启用代理
_ssh_cfg_write_block "$tmpconf2" "proxy-vps" "5.6.7.8" "root" "22" "~/.ssh/proxy" "1"
out2="$(cat "$tmpconf2")"
assert_contains "ProxyCommand nc -X 5 -x 127.0.0.1:6153 %h %p" "$out2" "write_block ProxyCommand"

printf 'ssh_cfg_write_block checks passed\n'
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1 | head -5
```

期望输出：`vps_tools.sh: ...: _ssh_cfg_host_exists: command not found` 或 `source` 成功后直接失败。

- [ ] **Step 3: 在 `vps_tools.sh` 第 2749 行前插入注释块和两个函数**

在 `show_menu() {` 这一行之前插入：

```bash
# ============================================================
#  12) SSH 客户端配置管理  — 辅助函数
# ============================================================

# 检查 config 文件中是否存在指定 Host 别名（精确匹配，不误匹配前缀）
# 参数：config_file host
_ssh_cfg_host_exists() {
  local config_file="$1"
  local host="$2"
  [[ -f "$config_file" ]] || return 1
  awk -v h="$host" '$1=="Host" && $2==h {found=1} END{exit !found}' "$config_file"
}

# 向 config 文件追加一个格式化的 Host 块
# 参数：config_file host hostname user port key_path use_proxy(0|1)
_ssh_cfg_write_block() {
  local config_file="$1"
  local host="$2"
  local hostname="$3"
  local user="$4"
  local port="$5"
  local key_path="$6"
  local use_proxy="$7"

  local ssh_dir
  ssh_dir="$(dirname "$config_file")"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  [[ ! -f "$config_file" ]] && { touch "$config_file"; chmod 600 "$config_file"; }

  {
    echo ""
    echo "Host ${host}"
    echo "    HostName ${hostname}"
    echo "    User ${user}"
    echo "    Port ${port}"
    echo "    IdentitiesOnly yes"
    echo "    IdentityFile ${key_path}"
    [[ "$use_proxy" == "1" ]] && echo "    ProxyCommand nc -X 5 -x 127.0.0.1:6153 %h %p"
  } >> "$config_file"
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
```

期望：所有行均以 `PASS:` 开头，末尾打印：
```
ssh_cfg_host_exists checks passed
ssh_cfg_write_block checks passed
```

- [ ] **Step 5: 提交**

```bash
git add vps_tools.sh tests/test_ssh_config_helpers.sh
git commit -m "feat: add _ssh_cfg_host_exists and _ssh_cfg_write_block helpers"
```

---

### Task 2: `_ssh_cfg_remove_host` + 测试

**Files:**
- Modify: `vps_tools.sh`
- Modify: `tests/test_ssh_config_helpers.sh`

- [ ] **Step 1: 在测试文件末尾追加失败测试**

```bash
# ── _ssh_cfg_remove_host 测试 ────────────────────────────────
tmpconf3="${TMPDIR_TEST}/config3"

cat > "$tmpconf3" <<'EOF'
Host vps-a
    HostName 1.1.1.1
    User root
    Port 22
    IdentitiesOnly yes
    IdentityFile ~/.ssh/vps-a

Host vps-b
    HostName 2.2.2.2
    User root
    Port 2222
    IdentitiesOnly yes
    IdentityFile ~/.ssh/vps-b
EOF

_ssh_cfg_remove_host "$tmpconf3" "vps-a"

# vps-a 已删除
assert_fail _ssh_cfg_host_exists "$tmpconf3" "vps-a"
# vps-b 仍存在
assert_ok   _ssh_cfg_host_exists "$tmpconf3" "vps-b"
# 备份文件存在
ls "${tmpconf3}.bak."* >/dev/null 2>&1 || { printf 'FAIL: backup not found\n' >&2; exit 1; }
printf 'PASS: backup file created\n'

# 删除不存在的 host 不报错
_ssh_cfg_remove_host "$tmpconf3" "nonexistent"
printf 'PASS: remove nonexistent host is no-op\n'

printf 'ssh_cfg_remove_host checks passed\n'
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1 | tail -5
```

期望：`_ssh_cfg_remove_host: command not found`。

- [ ] **Step 3: 在 `vps_tools.sh` 的 `_ssh_cfg_write_block` 函数后插入**

```bash
# 从 config 文件中删除指定 Host 块（操作前自动备份）
# 参数：config_file host
_ssh_cfg_remove_host() {
  local config_file="$1"
  local host="$2"
  [[ -f "$config_file" ]] || return 0

  local backup="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$config_file" "$backup"

  awk -v h="$host" '
    /^Host[[:space:]]/ && $2 == h { skip=1; next }
    /^Host[[:space:]]/             { skip=0 }
    !skip                          { print }
  ' "$backup" > "$config_file"
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
```

期望：所有已有测试继续通过，新增 `ssh_cfg_remove_host checks passed`。

- [ ] **Step 5: 提交**

```bash
git add vps_tools.sh tests/test_ssh_config_helpers.sh
git commit -m "feat: add _ssh_cfg_remove_host helper"
```

---

### Task 3: `_ssh_cfg_list` + 测试

**Files:**
- Modify: `vps_tools.sh`
- Modify: `tests/test_ssh_config_helpers.sh`

- [ ] **Step 1: 在测试文件末尾追加失败测试**

```bash
# ── _ssh_cfg_list 测试 ───────────────────────────────────────
tmpconf4="${TMPDIR_TEST}/config4"
touch "$tmpconf4"

# 空文件显示暂无配置
list_out="$(_ssh_cfg_list "$tmpconf4")"
assert_contains "暂无配置" "$list_out" "list empty config"

# 写入两个 Host 块（一个启用代理，一个不启用）
_ssh_cfg_write_block "$tmpconf4" "vps1" "1.1.1.1" "root"   "2222" "~/.ssh/vps1" "1"
_ssh_cfg_write_block "$tmpconf4" "vps2" "2.2.2.2" "ubuntu" "22"   "~/.ssh/vps2" "0"

list_out="$(_ssh_cfg_list "$tmpconf4")"
assert_contains "vps1"        "$list_out" "list shows vps1"
assert_contains "1.1.1.1"     "$list_out" "list shows HostName of vps1"
assert_contains "✓"           "$list_out" "list shows proxy mark"
assert_contains "vps2"        "$list_out" "list shows vps2"
assert_contains "✗"           "$list_out" "list shows no-proxy mark"
assert_contains "共 2 条配置" "$list_out" "list shows count"

# 不含 IdentitiesOnly yes 的普通 Host 块不应出现在列表中
cat >> "$tmpconf4" <<'EOF'

Host unmanaged
    HostName 9.9.9.9
    User root
    Port 22
EOF
list_out="$(_ssh_cfg_list "$tmpconf4")"
assert_not_contains "unmanaged" "$list_out" "list ignores blocks without IdentitiesOnly yes"
assert_contains "共 2 条配置"   "$list_out" "list count unchanged after unmanaged block"

printf 'ssh_cfg_list checks passed\n'
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1 | tail -5
```

期望：`_ssh_cfg_list: command not found`。

- [ ] **Step 3: 在 `vps_tools.sh` 的 `_ssh_cfg_remove_host` 函数后插入**

```bash
# 读取 config 文件，以表格形式展示所有受管 Host（含 IdentitiesOnly yes 的块）
# 参数：config_file
_ssh_cfg_list() {
  local config_file="${1:-$HOME/.ssh/config}"

  if [[ ! -f "$config_file" ]] || [[ ! -s "$config_file" ]]; then
    echo "      暂无配置"
    return 0
  fi

  local rows
  rows=$(awk '
    /^Host[[:space:]]/ {
      if (cur != "" && identonly) {
        px = has_proxy ? "✓" : "✗"
        print cur "|" cur_hn "|" cur_user "|" cur_port "|" px
      }
      cur=$2; cur_hn="-"; cur_user="-"; cur_port="-"; identonly=0; has_proxy=0
      next
    }
    /^[[:space:]]*HostName[[:space:]]/           { cur_hn=$2 }
    /^[[:space:]]*User[[:space:]]/               { cur_user=$2 }
    /^[[:space:]]*Port[[:space:]]/               { cur_port=$2 }
    /^[[:space:]]*IdentitiesOnly[[:space:]]+yes/ { identonly=1 }
    /^[[:space:]]*ProxyCommand[[:space:]]/       { has_proxy=1 }
    END {
      if (cur != "" && identonly) {
        px = has_proxy ? "✓" : "✗"
        print cur "|" cur_hn "|" cur_user "|" cur_port "|" px
      }
    }
  ' "$config_file")

  if [[ -z "$rows" ]]; then
    echo "      暂无配置"
    return 0
  fi

  echo ""
  printf ' %-3s │ %-15s │ %-20s │ %-6s │ %-6s │ %s\n' "#" "Host 别名" "HostName" "User" "Port" "代理"
  echo "────┼─────────────────┼──────────────────────┼────────┼────────┼─────"

  local i=1
  while IFS='|' read -r h hn u p px; do
    printf ' %-3s │ %-15s │ %-20s │ %-6s │ %-6s │ %s\n' "$i" "$h" "$hn" "$u" "$p" "$px"
    (( i++ )) || true
  done <<< "$rows"

  echo ""
  echo "共 $((i-1)) 条配置"
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
```

- [ ] **Step 5: 提交**

```bash
git add vps_tools.sh tests/test_ssh_config_helpers.sh
git commit -m "feat: add _ssh_cfg_list helper"
```

---

### Task 4: `_ssh_cfg_gen_key` 和 `_ssh_cfg_import_key` + 测试

**Files:**
- Modify: `vps_tools.sh`
- Modify: `tests/test_ssh_config_helpers.sh`

- [ ] **Step 1: 在测试文件末尾追加失败测试**

```bash
# ── _ssh_cfg_gen_key 测试 ────────────────────────────────────
keydir="${TMPDIR_TEST}/keys"
mkdir -p "$keydir"

_ssh_cfg_gen_key "${keydir}/test_ed25519" "ed25519" ""
[[ -f "${keydir}/test_ed25519" ]]     || { printf 'FAIL: ed25519 private key not created\n' >&2; exit 1; }
[[ -f "${keydir}/test_ed25519.pub" ]] || { printf 'FAIL: ed25519 public key not created\n'  >&2; exit 1; }
perm="$(stat -c '%a' "${keydir}/test_ed25519")"
[[ "$perm" == "600" ]] || { printf 'FAIL: private key perms should be 600, got %s\n' "$perm" >&2; exit 1; }
printf 'PASS: _ssh_cfg_gen_key ed25519 creates key pair with 600 permissions\n'

_ssh_cfg_gen_key "${keydir}/test_rsa" "rsa" ""
[[ -f "${keydir}/test_rsa" ]] || { printf 'FAIL: rsa private key not created\n' >&2; exit 1; }
printf 'PASS: _ssh_cfg_gen_key rsa creates key files\n'

_ssh_cfg_gen_key "${keydir}/test_ecdsa" "ecdsa" ""
[[ -f "${keydir}/test_ecdsa" ]] || { printf 'FAIL: ecdsa private key not created\n' >&2; exit 1; }
printf 'PASS: _ssh_cfg_gen_key ecdsa creates key files\n'

assert_fail _ssh_cfg_gen_key "${keydir}/bad" "invalid_type" ""

printf 'ssh_cfg_gen_key checks passed\n'

# ── _ssh_cfg_import_key 测试 ─────────────────────────────────
priv='-----BEGIN OPENSSH PRIVATE KEY-----
dummyprivkeydata
-----END OPENSSH PRIVATE KEY-----'
pub='ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQABAAAA dummy@test'

_ssh_cfg_import_key "${keydir}/imported" "$priv" "$pub"

[[ -f "${keydir}/imported" ]]     || { printf 'FAIL: imported private key file not created\n' >&2; exit 1; }
[[ -f "${keydir}/imported.pub" ]] || { printf 'FAIL: imported public key file not created\n'  >&2; exit 1; }

priv_perm="$(stat -c '%a' "${keydir}/imported")"
pub_perm="$(stat -c '%a'  "${keydir}/imported.pub")"
[[ "$priv_perm" == "600" ]] || { printf 'FAIL: private key perms %s (expected 600)\n' "$priv_perm" >&2; exit 1; }
[[ "$pub_perm"  == "644" ]] || { printf 'FAIL: public key perms %s (expected 644)\n'  "$pub_perm"  >&2; exit 1; }

grep -q "dummyprivkeydata"  "${keydir}/imported"     || { printf 'FAIL: private key content mismatch\n' >&2; exit 1; }
grep -q "AAAAB3NzaC1yc2E"  "${keydir}/imported.pub" || { printf 'FAIL: public key content mismatch\n'  >&2; exit 1; }
printf 'PASS: _ssh_cfg_import_key saves files with correct permissions and content\n'

printf 'ssh_cfg_import_key checks passed\n'
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1 | tail -5
```

期望：`_ssh_cfg_gen_key: command not found`。

- [ ] **Step 3: 在 `vps_tools.sh` 的 `_ssh_cfg_list` 函数后插入两个函数**

```bash
# 生成 SSH 密钥对
# 参数：key_path key_type(ed25519|rsa|ecdsa) passphrase(空字符串=无密码)
_ssh_cfg_gen_key() {
  local key_path="$1"
  local key_type="$2"
  local passphrase="$3"

  local key_dir
  key_dir="$(dirname "$key_path")"
  mkdir -p "$key_dir"
  chmod 700 "$key_dir"

  case "$key_type" in
    ed25519) ssh-keygen -q -t ed25519      -f "$key_path" -N "$passphrase" -C "" ;;
    rsa)     ssh-keygen -q -t rsa -b 4096  -f "$key_path" -N "$passphrase" -C "" ;;
    ecdsa)   ssh-keygen -q -t ecdsa -b 521 -f "$key_path" -N "$passphrase" -C "" ;;
    *)       echo -e "      ${C_RED}✗ 未知密钥类型: ${key_type}${C_RESET}" >&2; return 1 ;;
  esac
}

# 将用户粘贴的密钥内容保存到文件（自动设置权限）
# 参数：key_path privkey_content pubkey_content
_ssh_cfg_import_key() {
  local key_path="$1"
  local privkey_content="$2"
  local pubkey_content="$3"

  local key_dir
  key_dir="$(dirname "$key_path")"
  mkdir -p "$key_dir"
  chmod 700 "$key_dir"

  printf '%s\n' "$privkey_content" > "$key_path"
  chmod 600 "$key_path"

  printf '%s\n' "$pubkey_content" > "${key_path}.pub"
  chmod 644 "${key_path}.pub"
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
```

- [ ] **Step 5: 提交**

```bash
git add vps_tools.sh tests/test_ssh_config_helpers.sh
git commit -m "feat: add _ssh_cfg_gen_key and _ssh_cfg_import_key helpers"
```

---

### Task 5: 交互函数 `_ssh_cfg_do_add`、`_ssh_cfg_do_delete` 和 `do_ssh_config`

**Files:**
- Modify: `vps_tools.sh`

- [ ] **Step 1: 在 `vps_tools.sh` 的 `_ssh_cfg_import_key` 函数后插入 `_ssh_cfg_do_add`**

```bash
# 交互式添加或覆盖一个 Host 条目
# 参数：config_file
_ssh_cfg_do_add() {
  local config_file="$1"

  echo -e "\n${C_BOLD_WHITE}━━━━━━━━━━ 添加 / 更新 Host ━━━━━━━━━━${C_RESET}\n"

  # [1/6] Host 别名
  local host
  read -rp "      [1/6] Host 别名: " host
  if [[ -z "$host" || "$host" =~ [[:space:]] ]]; then
    echo -e "      ${C_RED}✗ Host 别名不能为空或含空格${C_RESET}"; return 1
  fi

  # 检查重复，确认覆盖
  if _ssh_cfg_host_exists "$config_file" "$host"; then
    local overwrite
    read -rp "      ⚠ Host \"${host}\" 已存在，是否覆盖？[y/N]: " overwrite
    if ! [[ "$overwrite" =~ ^[Yy]$ ]]; then
      echo "      已取消"; return 0
    fi
    _ssh_cfg_remove_host "$config_file" "$host"
    echo -e "      ${C_GREEN}✓ 已删除旧配置${C_RESET}"
  fi

  # [2/6] HostName
  local hostname
  read -rp "      [2/6] HostName (IP 或域名): " hostname
  [[ -z "$hostname" ]] && { echo -e "      ${C_RED}✗ HostName 不能为空${C_RESET}"; return 1; }

  # [3/6] User
  local user
  read -rp "      [3/6] User [默认 root]: " user
  user="${user:-root}"

  # [4/6] Port
  local port
  read -rp "      [4/6] Port [默认 22]: " port
  port="${port:-22}"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo -e "      ${C_RED}✗ 端口无效，请输入 1-65535 之间的数字${C_RESET}"; return 1
  fi

  # [5/6] ProxyCommand
  local use_proxy="0"
  local proxy_ans
  read -rp "      [5/6] 是否启用代理 (ProxyCommand nc -X 5 -x 127.0.0.1:6153)？[y/N]: " proxy_ans
  [[ "$proxy_ans" =~ ^[Yy]$ ]] && use_proxy="1"

  # [6/6] IdentityFile
  echo "      [6/6] IdentityFile 方式："
  echo "            1) 生成新密钥对"
  echo "            2) 提供私钥文件路径"
  echo "            3) 粘贴密钥内容"
  local key_choice
  read -rp "      请选择 [1-3]: " key_choice

  local default_key_path="$HOME/.ssh/${host}"
  local key_path

  case "$key_choice" in
    1)
      echo "      选择密钥类型："
      echo "            1) ed25519（推荐）"
      echo "            2) rsa-4096"
      echo "            3) ecdsa-521"
      local type_choice key_type
      read -rp "      请选择 [1-3，默认 1]: " type_choice
      case "${type_choice:-1}" in
        1) key_type="ed25519" ;;
        2) key_type="rsa" ;;
        3) key_type="ecdsa" ;;
        *) echo -e "      ${C_RED}✗ 无效选项${C_RESET}"; return 1 ;;
      esac

      read -rp "      保存路径 [默认 ${default_key_path}]: " key_path
      key_path="${key_path:-$default_key_path}"

      local passphrase="" pass_ans
      read -rp "      是否设置密钥密码？[y/N]: " pass_ans
      if [[ "$pass_ans" =~ ^[Yy]$ ]]; then
        read -rsp "      请输入密码: " passphrase; echo ""
      fi

      _ssh_cfg_gen_key "$key_path" "$key_type" "$passphrase"
      echo -e "      ${C_GREEN}✓ 密钥已生成: ${key_path}${C_RESET}\n"
      echo -e "      ${C_CYAN}公钥内容（请复制到目标服务器 ~/.ssh/authorized_keys）：${C_RESET}"
      cat "${key_path}.pub"
      echo ""
      ;;
    2)
      read -rp "      请输入私钥文件路径: " key_path
      key_path="${key_path:-$default_key_path}"
      # 展开 ~ 符号
      key_path="${key_path/#\~/$HOME}"
      if [[ ! -f "$key_path" ]]; then
        echo -e "      ${C_RED}✗ 文件不存在: ${key_path}${C_RESET}"; return 1
      fi
      ;;
    3)
      read -rp "      保存路径 [默认 ${default_key_path}]: " key_path
      key_path="${key_path:-$default_key_path}"

      echo "      请粘贴私钥内容（以单独的空行结束输入）："
      local privkey_lines="" line
      while IFS= read -r line; do
        [[ -z "$line" ]] && break
        privkey_lines+="${line}"$'\n'
      done
      privkey_lines="${privkey_lines%$'\n'}"

      echo "      请粘贴公钥内容（单行，以 ssh-* 开头）："
      local pubkey_line
      read -r pubkey_line

      _ssh_cfg_import_key "$key_path" "$privkey_lines" "$pubkey_line"
      echo -e "      ${C_GREEN}✓ 密钥已保存: ${key_path}${C_RESET}"
      ;;
    *)
      echo -e "      ${C_RED}✗ 无效选项${C_RESET}"; return 1
      ;;
  esac

  _ssh_cfg_write_block "$config_file" "$host" "$hostname" "$user" "$port" "$key_path" "$use_proxy"
  echo -e "\n      ${C_GREEN}✓ Host \"${host}\" 已写入 ${config_file}${C_RESET}\n"
}
```

- [ ] **Step 2: 在 `_ssh_cfg_do_add` 后插入 `_ssh_cfg_do_delete`**

```bash
# 交互式删除一个 Host 条目
# 参数：config_file
_ssh_cfg_do_delete() {
  local config_file="$1"

  echo -e "\n${C_BOLD_WHITE}━━━━━━━━━━ 删除 Host ━━━━━━━━━━${C_RESET}\n"

  local host
  read -rp "      [1/2] 请输入要删除的 Host 别名: " host
  [[ -z "$host" ]] && { echo "      已取消"; return 0; }

  if ! _ssh_cfg_host_exists "$config_file" "$host"; then
    echo -e "      ${C_YELLOW}⚠ Host \"${host}\" 不存在${C_RESET}"; return 0
  fi

  local confirm
  read -rp "      [2/2] 确认删除 Host \"${host}\"？[y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    _ssh_cfg_remove_host "$config_file" "$host"
    echo -e "      ${C_GREEN}✓ 已删除 Host \"${host}\"${C_RESET}\n"
  else
    echo "      已取消"
  fi
}
```

- [ ] **Step 3: 在 `_ssh_cfg_do_delete` 后插入 `do_ssh_config`**

```bash
do_ssh_config() {
  local config_file="$HOME/.ssh/config"

  while true; do
    echo ""
    echo -e "${C_CYAN}━━━━━━━━━━ SSH 客户端配置管理 ━━━━━━━━━━${C_RESET}"
    echo " 1) 列出所有 Host"
    echo " 2) 添加 / 更新 Host"
    echo " 3) 删除 Host"
    echo " 0) 返回主菜单"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    local sub
    read -rp "请输入选项 [0-3]: " sub
    echo ""
    case "$sub" in
      1) _ssh_cfg_list "$config_file" ;;
      2) _ssh_cfg_do_add    "$config_file" || true ;;
      3) _ssh_cfg_do_delete "$config_file" || true ;;
      0) return 0 ;;
      *) echo "无效选项，请重新输入" ;;
    esac
  done
}
```

- [ ] **Step 4: 运行已有测试确认无回归**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
```

期望：全部已有测试通过，无新失败。

- [ ] **Step 5: 提交**

```bash
git add vps_tools.sh
git commit -m "feat: add interactive SSH config functions and do_ssh_config sub-menu"
```

---

### Task 6: 主菜单集成 + 静态测试 + README

**Files:**
- Modify: `vps_tools.sh`（`show_menu`、`main`）
- Modify: `tests/test_ssh_config_helpers.sh`
- Modify: `README.md`

- [ ] **Step 1: 在测试文件末尾追加静态集成检查**

```bash
# ── 静态集成检查 ─────────────────────────────────────────────
grep -q 'do_ssh_config()'      ./vps_tools.sh || { printf 'FAIL: do_ssh_config() not found\n' >&2; exit 1; }
grep -q '_ssh_cfg_do_add()'    ./vps_tools.sh || { printf 'FAIL: _ssh_cfg_do_add() not found\n' >&2; exit 1; }
grep -q '_ssh_cfg_do_delete()' ./vps_tools.sh || { printf 'FAIL: _ssh_cfg_do_delete() not found\n' >&2; exit 1; }
grep -q '12) SSH 客户端配置管理' ./vps_tools.sh || { printf 'FAIL: menu item 12 not found\n' >&2; exit 1; }
grep -q '12) do_ssh_config || true ;;' ./vps_tools.sh || { printf 'FAIL: case 12 not found\n' >&2; exit 1; }
grep -q '请输入选项 \[0-12\]' ./vps_tools.sh || { printf 'FAIL: prompt range not updated\n' >&2; exit 1; }
printf 'menu integration static checks passed\n'

grep -q '12. SSH 客户端配置管理' ./README.md || { printf 'FAIL: README item 12 not found\n' >&2; exit 1; }
printf 'README check passed\n'
```

- [ ] **Step 2: 运行测试确认新增静态检查失败**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1 | tail -10
```

期望：`FAIL: menu item 12 not found` 之类的错误。

- [ ] **Step 3: 更新 `show_menu()` — 追加选项 12**

在 `show_menu()` 函数的 `echo " 11) 安装桌面环境与远程桌面"` 这一行后追加：

```bash
  echo " 12) SSH 客户端配置管理"
```

- [ ] **Step 4: 更新 `main()` — 添加 case 12 并更新提示范围**

将 `read -rp "请输入选项 [0-11]: "` 改为：

```bash
    read -rp "请输入选项 [0-12]: " choice
```

在 `11) require_root && do_desktop_remote_setup || true ;;` 后追加：

```bash
      12) do_ssh_config || true ;;
```

- [ ] **Step 5: 更新 `README.md`**

在 `## 功能总览` 的列表中，`11. 桌面环境与远程桌面安装` 后追加：

```
12. SSH 客户端配置管理
```

在 `### 11. 桌面环境与远程桌面安装` 说明段落之后、`## 注意事项` 之前插入：

```markdown
### 12. SSH 客户端配置管理

管理本机 `~/.ssh/config` 中的远端服务器连接条目，无需 `root` 权限。子菜单提供：

- **列出**所有由本工具管理的 Host（含 `IdentitiesOnly yes` 的条目）
- **添加 / 更新** Host：配置 HostName、User、Port，可选启用 SOCKS5 代理
  （`ProxyCommand nc -X 5 -x 127.0.0.1:6153`）；IdentityFile 支持三种方式：
  生成新密钥对（ed25519 / rsa-4096 / ecdsa-521）、提供已有私钥路径、粘贴私钥和公钥内容
- **删除** Host：精确匹配别名，操作前自动备份 `~/.ssh/config`
```

- [ ] **Step 6: 运行全部测试确认通过**

```bash
bash tests/test_ssh_config_helpers.sh 2>&1
bash tests/test_remote_desktop_helpers.sh 2>&1
bash tests/test_ssh_fail2ban_helpers.sh 2>&1
```

期望：三个测试文件全部只输出 `PASS:` 行，无 `FAIL`。

- [ ] **Step 7: 提交**

```bash
git add vps_tools.sh tests/test_ssh_config_helpers.sh README.md
git commit -m "feat: integrate SSH client config management into main menu (option 12)"
```
