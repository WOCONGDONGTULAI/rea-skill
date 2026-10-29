# Evidence、对比与验证

## 1. Evidence 的基本形态

产出 Evidence 的工具在 MCP 的 `structuredContent` 和 CLI JSON 里**直接返回完整 Evidence 记录**。

- 操作数据在 `normalized_result` 里。
- 引用时用 `evidence_id` 作为稳定引用。
- **保留 authority、limitations、coverage 和残留未知。**
- 结果不完整或分页时，只在剩余数据对任务重要时继续取；
  **不要**为了读一个已经内联返回的结果而去取 bundle 或资源。
- 完整的 `inspect_binary_layout` 或 `analyze_javascript_application` Evidence 已经保留时，
  用 `inspect_analysis_view` 取摘要、一节/符号/模块或稳定页，**而不是重复生产者**。

## 2. 各工具的 summary + view 配方

### inspect_artifact（归档清单）

```json
{"detail": "summary", "view": {"kind": "inventory", "collection": "occurrences", "logical_paths": ["package.json", "main.js"]}}
```

省略 `logical_paths` 分页全部；`[]` 不选。其他集合：`nodes`、`edges`、`integrity_contradictions`。
**把 `source_complete` 和分页耗尽分开。**

### 原生过程/名字/字符串清单

```json
{"detail": "summary", "view": {"kind": "native-inventory", "offset": 0, "limit": 32, "fields": ["value"]}}
```

搜索工具保留已有的 pattern/mode/case/document 选择。
省略 `fields` 取完整记录；选中的行保留 `record.address` 和 `source_index`。
选 `value` 保留它的字符串/解码限定。
父 Evidence ID 加 source index 保留同址的多个候选。
**只按需翻 `coverage.next_offset`；耗尽保留的行不建立完整的程序发现。**

### 原生导出表

```json
{"detail": "summary"}
```

然后：

```json
{"view": {"kind": "native-exports", "collection": "exports", "names": ["selected_name"], "fields": ["name"], "offset": 0, "limit": 32}}
```

同名版本和别名都会保留；用 `source_index` 配合父 ID 保持稳定身份。
`collection: "issues"` 翻解释失败。
**页覆盖描述的是选中的保留行；`summary.coverage` 描述的才是源表。空的局部页不证明不存在。**

CLI：`inspect-native-exports --detail summary --evidence_output PATH` 保存完整 bundle，
后续用 `inspect-analysis-view --evidence-bundle PATH` 请求。

## 3. 未知项跟踪

用 `record_unknown` 跟踪用户调查里未解决的问题，写明还需要的权威来源或环境。
提供支持证据和矛盾证据的 ID。它直接更新会话注册表。
用 `update_unknown` 配当前修订号；遇到 stale revision 就重读，**不要**盲目重试。
只有合格���观察证据才能验证一个解决。

## 4. 对比工具

**声称等价或缺失时，必须用完整、兼容的页集合。**

| 工具 | 对比什么 | 注意事项 |
| --- | --- | --- |
| `compare_artifacts` | 清单页（出现路径、内容、元数据、图关系） | 每侧写 `{"kind": "retained-evidence", "evidence_id": ...}` 或 `{"kind": "evidence-file", "path": ..., "evidence_id": ...}`，不要重发 Evidence。 |
| `compare_functions` | 明确的函数 Evidence，不是模糊的整二进制匹配 | 它**拒绝** `analyze_function` 的摘要回复；传摘要的 `parent_evidence_id`（作为 `retained-evidence` 引用）或完整 dossier。 |
| `compare_bundles` | 规范 bundle 成员和未知历史 | — |
| `find_changed_behavior` | 组合已有对比 | **静态差异是候选，不是因果证明。** |
| `build_call_path` | 调用路径 | 需要同一产物/provider 的明确函数 dossier；**前沿不完整时缺失是 unknown。** |
| `correlate_static_and_runtime` | 静态与运行时关联 | 用明确映射；匹配模式是**假设，不是因果**。 |
| `verify_reconstruction` | 有限的类型化规范 | 通过**只覆盖声明的可比声明**，不是全局等价。 |

## 5. 网络捕获的视图

### api-surface

在保留的 `inspect_web_network_capture` HAR Evidence 上用 `view: {kind: "api-surface"}`，
按 method、origin 和 path 模板分组已观测到的请求行。

**格式匹配是推断，不是处理器身份或 schema。**
分组页引用父记录序号；声称完整前先看记录覆盖和排除项。**不重放任何请求。**

schema 广告了 `include_query_parameter_names` 时，选它拿到不同的已观测参数名和原始记录序号。
**query 值被省略**；名字既不建立必需参数，也不建立完整的服务端 schema。
要精确 URL 保留原始父 Evidence。

### environment-manifest

在同一份保留的 HAR Evidence 上用 `view: {kind: "environment-manifest"}`，
把主 origin 的请求行投影成带路径模板、参数、已观测 query 名、无值 body 形状和记录指针的具名工具。

只在记录的标识符需要时才开 `template_rules`；
**每个模板、参数和合并的兄弟都是推断**，不复制任何 header、cookie 或 body 值，
三个声明的未知项保持未解决。

### environment-state

用 `view: {kind: "environment-state"}` 配 manifest 的 `template_rules`，提取那些读操作观察到的数据：
实体类型和身份字段、带记录值的实体、文档，以及逐工具的渲染计划（对照录制检查过）。

**状态只来自第一次相关写之前的读**；类型、身份和列表成员归属都是推断。
视图还给每个改变状态的工具一个写计划，**只有当后续记录的读确认了它的效果且无矛盾时才被服务**。

`rea environment-serve manifest.json --evidence capture.json` 在启动时派生该状态，
从状态回答读工具，服务写计划被允许的那些（每个都把效果应用到状态上），
并在 `/agentenv` 上服务 `data/reset`、`data/add`、`data/get`；
其他写工具不被服务，每个计划在 `reason` 里说明原因。

状态无法派生时（或目录超过发现预算时），它改为回放 —— 带 `--replay-only` 或状态不可用时。
停止文档的 `state` 成员是 `{"served": true, "evidence_id": ...}`、
`{"served": false, "reason": "replay-only"}` 或 `{"served": false, "reason": "unavailable", "code": ..., "message": ...}`。

### environment-coverage

用 `view: {kind: "environment-coverage"}` 配同样的规则，看一个从捕获构建的环境**会服务什么**：
哪些读工具从状态回答或被回放（附原因），哪些写工具被服务或被扣留（附下一步该录什么的提示）。

**它不**应用 serve 时的目录和状态大小检查。
`rea environment-build <capture.har> <dir>` 一步完成检查、投影和导出，打印同样的覆盖，
或者在 bundle 服务回放时打印 `null`。

## 6. 进程捕获的退出语义

进程捕获是**可选的行为证据，不是安全沙箱**。

- V3 捕获**不能**升级到 V4；重跑原始场景。
- 区分 root 退出和后代结算；任务需要时要求新鲜度。
- 超时但必须写最终报告的目标需要 `finalization_ms`：
  REA 给捕获的 root 发 SIGTERM，继续观察，只在间隔结束还没退出时发一次 SIGKILL。
- `exit.finalization.signals` 列出每次尝试及其投递结果；
  观察到的退出信号留在 `exit.signal`，**每次 deadline 退出时 `exit.code` 都是 null**，
  自己退出的 finalizer 的退出码在 `exit.finalization.exit_code`（信号退出或没观察到退出时为 null）。

## 7. 修改限额

`update_analysis_settings` 改运行中 REA 服务器里的策划默认值。

它**不会**编辑客户端注册、延长客户端工具调用期限，或重算从 `rea setup` 推导出的超时值。
看运行中服务器的默认值用 `inspect_analysis_settings`；`rea doctor` 检查启动配置，**观察不到**另一个进程的运行时覆盖。

运行时默认值只影响新工作；**显式的单次调用参数优先级更高**，必须直接改。
Reset 恢复启动值。更新在目标 close/open 后仍在，REA 重启后消失。

## 参考

[MCP 契约](https://github.com/morluto/rea/blob/main/docs/mcp-contracts.md) ·
[CLI 与 Evidence](https://github.com/morluto/rea/blob/main/docs/cli.md) ·
[重建就绪度](https://github.com/morluto/rea/blob/main/docs/reconstruction-readiness.md) ·
[重建覆盖](https://github.com/morluto/rea/blob/main/docs/reconstruction-coverage.md)
