# 安装、注册与 provider 配置

本文只在你**确实**需要连接 REA 时读。目标、问题和上下文始终放在第一位。

## 1. 前置条件

| 项目 | 要求 | 说明 |
| --- | --- | --- |
| Node.js | 声明要求 `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1` | 低于此版本时 npm 只打印 `EBADENGINE` 警告。**实测 22.22.2 下 REA 6.8.0 能正常启动并完成 MCP 握手**，不是硬性阻断；但建议升级以消除不确定性。 |
| npm | 随 Node 附带 | 用 `npx` 免全局安装 |
| 平台 | macOS / Linux / Windows | 部分能力仅限 Linux（见第 5 节） |

检查：

```bash
node --version
npm --version
```

**Linux 额外前置**：Ghidra、JADX、固件工具启动和静态 JS/Electron 分析需要 REA 的 `PATH` 上有兼容 procps 的 `ps`（用于进程归属检查）。

## 2. 三种安装形态

### A. npx 免安装（推荐先用这个试）

```bash
npx -y rea-agents@latest --help
npx -y rea-agents@latest analyze-javascript-application /abs/path/to/app --json
```

无需全局安装、无需 MCP 注册。适合「一次性静态 JS 分析」。

**注意**：npx 每次调用可能重新解析包，版本会漂移。长期使用建议走形态 B 或 C。

### B. 全局安装 CLI

```bash
npm install --global rea-agents
rea --help
rea --version
```

更新：

```bash
rea update          # 或 rea --update
```

Bun 全局更新需要 Bun 1.2.17+。`rea update` 之后建议重跑一次 setup 刷新 agent 注册和 skill。

### C. MCP 服务器（agent 使用的方式）

```bash
npx rea-agents setup
```

`setup` 会为受支持的客户端注册 MCP 服务器并安装配套工作流说明，**会先展示改动计划并要求确认**，并对已有配置做备份。完成后需要重启 agent。

**`setup` 支持的客户端**：`claude_code`、`claude_desktop`、`codex`、`cursor`、`gemini_cli`、`windsurf`、`devin`、`opencode`、`antigravity`、`copilot_cli`、`commandcode`、`qwen_code`、`vscode`、`trae`、`grok_build`、`omp`、`pi`、`hermes`、`qoder`、`droid`、`zcode`、`dsh`、`freebuff`、`grok_bot`。

> **WorkBuddy 和 OpenClaw 不在上表中。** 对这两个平台必须手写注册，见第 3 节。

## 3. 手动注册 MCP

### WorkBuddy

配置文件：`~/.workbuddy/mcp.json`，`mcpServers` 键：

```json
{
  "mcpServers": {
    "rea": {
      "command": "npx",
      "args": ["-y", "rea-agents@latest", "mcp"],
      "env": {}
    }
  }
}
```

已全局安装 REA 时，用绝对路径更稳定（避免 `npx` 每次解析版本）：

```json
{
  "mcpServers": {
    "rea": {
      "command": "/usr/local/bin/node",
      "args": ["/usr/local/lib/node_modules/rea-agents/scripts/rea.mjs", "mcp"],
      "env": {}
    }
  }
}
```

写完后在 WorkBuddy 的连接器管理页右上角找到自定义连接器入口，对新服务器点「信任」才会启用。**新 MCP 不会自动激活。**

### OpenClaw

配置文件：`~/.openclaw/openclaw.json`，注意键是 `mcp.servers`（**不是** `mcpServers`）：

```json
{
  "mcp": {
    "servers": {
      "rea": {
        "command": "npx",
        "args": ["-y", "rea-agents@latest", "mcp"]
      }
    }
  }
}
```

也可以用 CLI：

```bash
openclaw mcp add rea --command npx --arg -y --arg rea-agents@latest --arg mcp
openclaw mcp status --verbose
openclaw mcp doctor rea --probe
```

### 一次性注册两个平台

本仓库提供了脚本：

```bash
python3 scripts/install_mcp.py              # 预览将要写入的内容
python3 scripts/install_mcp.py --apply      # 实际写入（自动备份原文件）
```

脚本会检测 Node 版本、检测已安装的 REA（全局 / npx）、备份现有配置，并把 REA 合并进已有的 `mcpServers` / `mcp.servers`（不动其他条目）。

### 传输方式

- **stdio（默认）**：MCP 客户端拉起子进程，通过 stdin/stdout 通信。WorkBuddy 与 OpenClaw 的注册都走这个。
- **streamable HTTP**：`rea mcp --http --port 8765`。绑定 loopback 之外需要 `MCP_ALLOWED_HOSTS` 或 `--allowed-hosts`（逗号分隔的主机名/IP，不带 URL 和端口）。不同 `Host` 或浏览器 `Origin` 返回 403，缺失 `Origin` 接受。只服务一个客户端，同时连接会互相顶替。

## 4. 环境变量

按需设置，不要一次全上。

| 变量 | 作用 |
| --- | --- |
| `REA_MCP_INPUT_SCHEMA_PROFILE` | `full` 时用完整输入 schema（含字段说明和嵌套校验）。默认 `compact`，省上下文。工具集和校验不变。 |
| `REA_MCP_MAX_RESPONSE_BYTES` | 提高 MCP 响应缓冲上限（默认 10 MiB）。provider 捕获上限是另一回事，抬这个不会抬 provider 上限。 |
| `REA_MCP_TOOL_FAMILIES` | 限制暴露的工具族，减少工具数量。 |
| `REA_GHIDRA_STARTUP_TIMEOUT_MS` | 大二进制时抬 Ghidra 启动期限（默认 330 秒）。 |
| `REA_HOPPER_STARTUP_TIMEOUT_MS` | 同上，Hopper。 |
| `REA_JADX_OPERATION_TIMEOUT_MS` | JADX 单次操作期限（默认 120000 ms）。 |
| `REA_JADX_HEAP_MIB` | JVM 堆大小。 |
| `REA_ASAR_MAX_HEADER_BYTES` | ASAR header 准入上限（默认 16 MiB，最大 256 MiB）。 |
| `REA_OBJDUMP_COMMAND` / `REA_GDB_COMMAND` / `REA_RIZIN_COMMAND` | 指定 objdump / GDB / Rizin 可执行文件路径，默认搜 `PATH`。 |
| `REA_TSHARK_COMMAND` / `REA_SIGROK_COMMAND` / `REA_WABT_BIN_DIRECTORY` | 网络包、信号波形、WASM 工具的指定路径。 |
| `REA_CAPTURE_DECODER_OLD_GENERATION_MIB` | HAR/SAZ/qlog 老生代堆（默认 192 MiB，下限 8，最大 16384）。 |

注意：修改**服务器启动环境**里的变量需要重启 REA 进程才生效；
改**运行环境变量**则可以用 `update_analysis_settings` 热改（见 evidence-workflows.md）。

## 5. provider 配置

原生反编译需要一个 provider。REA **不安装**任何 provider。

| provider | 平台 | 说明 |
| --- | --- | --- |
| Hopper | macOS | 商业反编译器。setup 可选安装（需明确批准），Windows 不可用。 |
| Ghidra | 全平台 | 需 Java + Ghidra 12.x（>=12.1）。Linux 支持 16 位 DOS、MIPS/PPC/RISC-V 等。 |
| IDA | 全平台 | 用 `mrexodia/ida-pro-mcp`。传原始输入二进制 + `provider_id: "ida"`，**不要**传 `.idb`/`.i64`。 |
| Kuna | 全平台 | 需 `REA_KUNA_COMMAND`。全程序导出缓存，支持伪代码/汇编/过程查询。 |
| objdump / Rizin | 需自带 | 离线检查，不开反汇编器数据库。 |
| JADX | Android | 需自备 headless JADX MCP JAR 0.7.1 + Java 17+，`REA_JADX_MCP_JAR` 指定 JAR 路径。 |

发现 Ghidra：`GHIDRA_INSTALL_DIR` 未设置时，REA 会在 `PATH` 上找 `ghidra` / `ghidraRun`，通过 realpath 确认它属于一棵带应用元数据和 headless 启动器的 Ghidra 树。显式设置的 `GHIDRA_INSTALL_DIR` **总是优先**，即使它无效 —— REA 会报那个错，而不是悄悄换一个。

检查 provider：

```bash
rea doctor --provider ghidra --json
rea doctor --provider jadx --json
rea doctor --json
```

**doctor 的 provider 检查是宿主级**的，反映的是运行 doctor 那个 shell 的环境，可能与客户端给插件服务器的环境不同。

### 平台能力速查

- **仅 Linux**：持久 GDB 会话、Rizin 调试会话（依赖 `/proc` 验证进程归属）。
- **仅 macOS**：`observe_native_calls`（LLDB）、`observe_native_ui`（需 macOS 14+ 和屏幕录制/辅助功能权限）。
- **仅 Linux**：TShark 抓包分析（需 util-linux `prlimit`）、sigrok 波形解码、固件解包（Binwalk/Unblob）。
- **macOS/Linux**：进程捕获（macOS 还需 `xcrun`/Swift 做归属检查）。

## 6. 连通性自检

```bash
rea mcp doctor --json      # 用当前 shell 的运行时测试生产 MCP 适配器
rea doctor --json          # 全量体检
```

**doctor 通过但客户端连不上**，说明问题在客户端的启动环境或注册，不在 REA。看客户端的启动报错。

客户端从桌面 App / IDE / 服务启动时，可能继承到和终端不同的 `PATH`。
`/abs/path/to/rea-agents` **不能**自己找到解释器 —— npm 启动器的 `#!/usr/bin/env node` 仍会搜 `PATH` 找 Node。
终端里跑得通，不代表客户端能拉起来。

## 7. 卸载

```bash
rea uninstall
```

手动注册的条目不会被 `rea doctor` / `rea uninstall` 看到（它们只读 setup 拥有的用户级注册），需要自己从配置文件里移除。

## 参考

上游文档：
[安装](https://github.com/morluto/rea/blob/main/docs/installation.md) ·
[CLI 与 Evidence](https://github.com/morluto/rea/blob/main/docs/cli.md) ·
[MCP 契约](https://github.com/morluto/rea/blob/main/docs/mcp-contracts.md) ·
[客户端配置](https://github.com/morluto/rea/blob/main/docs/client-configuration.md)
