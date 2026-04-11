# SSH 客户端配置管理功能设计文档

**日期**：2026-04-10  
**状态**：已确认，待实现  
**目标文件**：`vps_tools.sh`

---

## 一、功能概述

为 `vps_tools.sh` 新增 **SSH 客户端配置管理**功能，供用户在本机（开发电脑）管理连接远端服务器的 `~/.ssh/config` 条目。该功能不需要 root 权限。

---

## 二、菜单集成

### 主菜单

在现有菜单末尾追加：

```
12) SSH 客户端配置管理
```

`main()` 中对应：

```bash
12) do_ssh_config || true ;;
```

`read -rp` 提示更新为 `[0-12]`。

### SSH 配置子菜单

```
━━━━━━━━━━ SSH 客户端配置管理 ━━━━━━━━━━
 1) 列出所有 Host
 2) 添加 / 更新 Host
 3) 删除 Host
 0) 返回主菜单
```

---

## 三、函数规划

| 函数名 | 职责 |
|---|---|
| `_ssh_cfg_list` | 解析并展示 `~/.ssh/config` 中所有 Host 块 |
| `_ssh_cfg_host_exists` | 检查指定 Host 别名是否已存在，返回 0/1 |
| `_ssh_cfg_remove_host` | 从配置文件中精确删除指定 Host 块 |
| `_ssh_cfg_write_block` | 向配置文件追加一个格式化的 Host 块 |
| `_ssh_cfg_gen_key` | 交互式生成密钥对，输出私钥路径 |
| `_ssh_cfg_import_key` | 导入用户提供的私钥（路径或粘贴内容） |
| `do_ssh_config` | 子菜单主循环 |

命名风格与现有 `_desktop_*`、`_fw_*`、`_nft_*` 保持一致。

---

## 四、添加 / 更新 Host 流程

### 交互步骤

```
[1/6] Host 别名     → 输入（如 my-vps）
[2/6] HostName      → 输入 IP 或域名
[3/6] User          → 输入，默认 root
[4/6] Port          → 输入，默认 22
[5/6] ProxyCommand  → 是否启用？[y/N]
                      启用则写入：
                      ProxyCommand nc -X 5 -x 127.0.0.1:6153 %h %p
[6/6] IdentityFile  → 三选一：
      1) 生成新密钥对
      2) 提供路径
      3) 粘贴密钥内容
```

### IdentityFile 子流程

**选项 1 — 生成新密钥对**

- 选择密钥类型：`ed25519` / `rsa-4096` / `ecdsa-521`
- 保存路径默认：`~/.ssh/<Host别名>`
- 询问是否设置密钥密码？`[y/N]`
- 生成后打印公钥内容，提示用户复制到服务器

**选项 2 — 提供路径**

- 输入私钥文件路径（如 `~/.ssh/id_rsa`）
- 校验文件是否存在

**选项 3 — 粘贴密钥内容**

- 提示粘贴私钥内容（多行，以空行结束）→ 保存到 `~/.ssh/<Host别名>`，`chmod 600`
- 提示粘贴公钥内容（单行）→ 保存到 `~/.ssh/<Host别名>.pub`，`chmod 644`

### 已存在同名 Host 的处理

检测到重复 Host 时：

```
⚠ Host "my-vps" 已存在，是否覆盖？[y/N]:
```

用户确认后：先调用 `_ssh_cfg_remove_host` 删除旧块，再追加新块。

### 写入的配置块格式

```
Host <别名>
    HostName <IP或域名>
    User <用户名>
    Port <端口>
    IdentitiesOnly yes
    IdentityFile <路径>
    ProxyCommand nc -X 5 -x 127.0.0.1:6153 %h %p   # 仅启用时写入
```

---

## 五、列出所有 Host

解析 `~/.ssh/config`，以表格形式展示：

```
━━━━━━━━━━ 已配置的 SSH Host ━━━━━━━━━━

 # │ Host 别名     │ HostName          │ User │ Port │ 代理
───┼───────────────┼───────────────────┼──────┼──────┼─────
 1 │ my-vps        │ 1.2.3.4           │ root │ 2222 │ ✓
 2 │ dev-server    │ dev.example.com   │ root │ 22   │ ✗

共 2 条配置
```

- 若 `~/.ssh/config` 不存在或无 Host 条目，输出"暂无配置"
- 仅展示本工具写入的 Host 块（即含 `IdentitiesOnly yes` 的块），其他已有条目保留但不展示，避免误操作

---

## 六、删除 Host

```
[1/2] 请输入要删除的 Host 别名: my-vps
[2/2] 确认删除 Host "my-vps"？[y/N]:
      ✓ 已删除 Host "my-vps"
```

删除逻辑：

- 精确匹配 `^Host <别名>$`（防止误匹配 `Host my-vps-2`）
- 删除从该行到下一个 `^Host ` 行（不含）或文件末尾之间的所有内容
- 操作前备份：`~/.ssh/config.bak.<timestamp>`

---

## 七、错误处理

| 场景 | 处理方式 |
|---|---|
| `~/.ssh/config` 不存在 | 添加时自动创建，`chmod 600` |
| `~/.ssh/` 目录不存在 | 自动创建，`chmod 700` |
| 输入的私钥路径不存在 | 报错提示，重新输入 |
| Host 别名包含空格或特殊字符 | 校验拒绝，提示合法格式 |
| 密钥生成失败 | 显示错误信息，返回子菜单 |

---

## 八、不在范围内

- 编辑已有 Host 的单个字段（覆盖即可满足需求）
- 管理 `~/.ssh/known_hosts`
- 同步公钥到远端服务器（`ssh-copy-id`）
- 测试连通性（`ssh -T`）
