# 连接与任务恢复

只在**观察到**连接、命令、审批或 provider 阻塞时读本文。始终把用户的目标和问题放在第一位。说明是什么阻止了操作、下一步做什么；修好后继续调查。

## 1. 按观察到的故障选补救方式

| 观察到的现象 | 含义与下一步 |
| --- | --- |
| 会话里没有 REA 工具 | 检查注册：`rea doctor --client <id> --json`。装技能本身**不**注册 MCP。WorkBuddy / OpenClaw 见 setup-and-connect.md 第 3 节。 |
| 注册缺失 / 格式错误 / 陈旧 | 准备一份有范围的 setup 计划，带备份，只应用已授权的改动。 |
| 注册对齐但没连上工具 | 重启 / 重连客户端。doctor 只查注册，**无法**建立连接。 |
| MCP 连接断开 | 只在「安全可重复」或「确定没开始」时重试该调用一次。若可能已经改过目标，或再失败一次，告知用户并请其重启 MCP 客户端。 |
| REA 起不来（连接建立失败） | 重试一次，然后告知用户并请其重启 MCP 客户端。**不要**重试一个返回同样不变结果的启动失败。 |
| 客户端提示需要审批但策略是 never | 客户端在 REA 执行前就拒绝了。这是客户端策略，**不是** REA 就绪问题。不要为此装引擎或重跑 setup。 |
| 返回 `provider_unavailable` 或工具条目不可用 | 读该操作的 provider 诊断，或 `binary_session.result.tool_availability`。完整工具目录**不代表**每个操作都可用。 |
| 子 shell 里 `rea` 找不到 / Node 不兼容 | 查实际 shell 的 PATH 和启动器。前缀安装可能不在登录 shell 的 PATH 里，这**不**说明 MCP 注册坏了。 |
| 客户端超时但没有 REA 结果 | 宿主 deadline 先到了。看第 2 节区分客户端 deadline 与服务器 deadline。 |

静态 JS 和普通 ZIP 清单**不需要** Hopper 或 Ghidra。HAR 检查是离线的，不需要活浏览器。
原生反编译、Android 分析、固件解包各有自己的自带前置条件。
**能回答一部分问题的证据就用，明确把不可用的证据单独列出来。不要拿另一个目标顶替。**
普通 shell 工具（`strings`、`file` 等）的输出要**标注为普通 shell 观察**，只有真正的 REA 输出才算 REA Evidence。

## 2. 区分客户端 deadline 和服务器 deadline

宿主消息如 `timed out awaiting tools/call` 且没有 REA 结果，表示**客户端的 deadline 在结果到达前到期**。
它**不**表示 REA 跑完了、取消成功或资源已释放。

- **不要重复同样的分析。**
- 不要发明一个不存在的 Evidence 引用。
- 客户端 deadline 应覆盖执行、取消/清理和响应投递。在 Codex 里是 `mcp_servers.<server-id>.tool_timeout_sec`（**秒**，不是 `startup_timeout_sec`）。
- 改客户端配置只在授权范围内做，保留无关条目和备份。

反过来，REA 返回 `provider_timeout` 意味着**服务器/provider**到了自己的 deadline：
按 `remediation.action` 走，复用可访问的部分 Evidence，解决报告中的不完整清理再重试。
**只有当 remediation 明确建议时才改请求字段或 `REA_*` 设置。**
「提到某个控制项不能抬这个限制」**不等于**建议去改它。

静态 JS 分析用 `analysis_timeout_ms`（CLI: `rea analyze-javascript-application <path> --analysis-timeout-ms <ms>`），
单位是**毫秒**，控制每个源文件的启动/分析/传输期限。默认值 1024 MiB 堆 + 300000 ms。
`detail: "summary"` 只减少**投递**量，不减少分析工作量。省略 `source_paths` 表示全部分析，`[]` 是非法值。

## 3. 恢复阶梯

跟着返回的 remediation 走。

- **连接断开**：只在安全可重复时重试一次。可能已改过目标，或再次失败 → 告知用户并请其重启 MCP 客户端。**不要**为连接断开本身跑 `rea doctor`。
- **REA 起不来**：重试一次 → 告知用户并请其重启 MCP 客户端。重启后工具仍然缺失，才跑 `rea doctor`。不要重试返回同样结果的启动失败。
- **`cleanup_incomplete`** 或错误详情里有保留的清理 owner：重试**那个具体的清理 owner**。在它确认释放前，不要启动需要这些资源的新工作。重复原调用不等于这个重试。
- **容量不足**（`resource_constraint` 且 `retryable: true`）：等当前准入完成，在报告的限制内重试。**不要**重启 REA 来腾位置。
- **`configuration_invalid`**：在启动 REA 的环境（shell 或 MCP 注册）里改掉指名的设置，然后重启 REA。`rea doctor` 看 `runtime-configuration:` 检查项。注册需要带上新设置时，对该客户端重跑 `rea setup` 再重连。
- **`invalid_request`**：按当前 schema 修正报告出的字段。**不要**重复未改动的调用。

## 4. 客户端审批与 REA 就绪是两件事

REA 工具没有权限授予握手。客户端仍可能要求审批，因为某个操作会创建自有资源、启动 helper 或产生清理副作用。

**已广告的工具或成功的 doctor 结果都不能推翻客户端策略。**
`workspace-write` 本身不能解决 MCP 审批拒绝，`approval_policy = "never"` 也不等于所有 MCP 工具都预批准。

- 有交互审批时，走客户端自己的审批流程。
- 无人值守运行时，如果执行环境允许，就走 CLI 兜底；否则报告被阻塞的操作和需要的审批。
- **不要**重试同一个被拒的调用，不要偷偷放宽审批，不要把 MCP 的副作用描述成只读。

## 5. 修一个可编辑的 REA 限额

如果 `details.limit` 指出了可编辑的设置和边界，直接调 `update_analysis_settings`，
`changes` 里给 `setting`、`action: "set"` 和 `value`。`inspect_analysis_settings` 在这些事实已知时是可选的。

工作与清理稳定后重试同样的输入。运行时默认值只影响**新**工作；显式的单次调用参数优先级更高，必须直接改。Reset 恢复启动值。更新在目标 close/open 后仍在，但 REA 重启后消失。**它们不会**修改宿主 deadline、响应缓冲、注册或固定上限。

## 6. 通过已安装的 CLI 继续

只在启动器失败时检查命令环境：

```bash
command -v rea
command -v node
node --version
rea --version
```

子 shell 丢失了前缀安装时，用已知安装路径的公开启动器配 PATH 上受支持的 Node。
**避免**直接用内部的 `dist/cli.js` 入口，也不要做全局工具链变更。
MCP 可能有自己的有效启动器，即使 shell 解析不到 `rea`。

对操作者提供的 JS 目录或 ASAR：

```bash
rea analyze-javascript-application /absolute/path/to/app --json > app-evidence.json
jq -c '{source: {kind: "inline", evidence: .}, view: {kind: "summary"}}' app-evidence.json > app-view.json
rea inspect-analysis-view app-view.json
```

这些命令**不注册 MCP，也不安装分析引擎**。CLI 的 JS JSON 是完整的，可能非常大 —— 用重定向落盘，不要整个读进上下文。没有 `jq` 就用已有的 JSON 处理器，**不要**为了这个配方专门装一个。
原生 CLI 分析仍然需要对应引擎，且所有 CLI 操作都保留宿主执行权限。

## 7. 工具名与发现

REA 广告的是规范名（如 `binary_session`）。MCP 宿主决定怎么暴露给模型：
`mcp__rea__binary_session` 是**客户端约定**，不是 REA 能强制的。

- 用活跃客户端的工具列表和服务器关联去找操作。
- **有效的注册或已安装的 skill 不能证明这些工具到达了模型。**
- doctor 报告 live-server 身份为 unknown 是正常的 —— 调 `binary_session` 探活才能观察到运行中的服务器身份。
- 客户端可能用同一个前缀暴露多个服务器，前缀通配**不能**隔离 REA 权限。选权限范围前先看客户端实际的工具名和审批规则。

## 参考

[客户端配置与排障](https://github.com/morluto/rea/blob/main/docs/client-configuration.md) ·
[MCP 契约](https://github.com/morluto/rea/blob/main/docs/mcp-contracts.md)
