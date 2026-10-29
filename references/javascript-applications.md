# JavaScript 与 Electron 应用产物

## 1. 静态分析入口

对操作者提供的 ASAR 或解压目录，直接用 `analyze_javascript_application`。

**已知源码路径时**：schema 广告了 `source_paths` 就选精确的已清点路径，比如 `["package.json", "main.js", "preload.js"]`。
支撑用的 manifest 和 source map 要显式包含；**依赖不会被隐式分析**。
REA 保留完整的产物清单和身份，但只读取和分析选中的文件。
结果和摘要记录 `source_selection`；范围外的文件及其关系保持 unknown，
**部分应用覆盖不意味着选中的源码分析失败**。

CLI 用重复的 `--source-path`，太长用 `--source-paths-json` 传 JSON 文件。
省略选择表示完整应用分析；`source_paths: []` 是**非法值**，不是「不筛选」。
`detail: "summary"` 减少投递量，本身**不减少**分析工作量。

### ASAR header 准入

默认 16 MiB / 16777216 字节。准入错误会指明 `asar.max_header_bytes` 及其边界（最大 256 MiB）。
用 `update_analysis_settings` 设置该设置、`action: "set"` 和足够字节，然后重试**同一个**完整归档请求。
不需要检查或重启 REA。`REA_ASAR_MAX_HEADER_BYTES` 给未来的 REA 进程做种子。
`source_paths`、`detail`、`max_heap_mb` 都**不能**绕过或抬升 header 准入。

### 资源与超时

- `max_heap_mb`（默认 1024 MiB）和 `analysis_timeout_ms`（默认 300000 ms）选的是隔离源码分析器的老生代堆和每源期限。
  它们**不**改变 MCP 进程堆或客户端的工具期限。
- Bun 承载的 REA 不强制堆选择；Windows 上它改为把分析器的已提交内存限制为该值加 512 MiB 运行时保留。
- 精确的 `#alias` 说明符通过导入方所在包的 `imports` 映射解析到包内文件；嵌套 `node_modules` 包用自己的映射。
  通配、递归和外部包导入目标保持未解析。

## 2. 源码恢复（需要 Wakaru）

需要对打包后的 JavaScript 恢复**可读源码**时，用 `recover_javascript_sources`，传绝对 `path` 且**省略** `output_directory`。
相关的运行时/共享/懒加载文件通过 `additional_paths` 提供，然后一起分析返回的 `analysis_input` 目录。

每个输入保留自己的快照、摘要和字节范围来源；**输入和恢复出的代码都不会被执行**。
需要调用方在 Linux x64 上提供 Wakaru。

## 3. 摘要优先 + 保留证据

体积未知或很大时先 `detail: "summary"`，它返回一个 `inspect_analysis_view` Evidence 记录，
并带一个指向完整保留应用分析的 `normalized_result.parent_evidence_id`。
source map 内容是这次静态分析的一部分。
**读完发现、覆盖、限制和未知，再跟进具体的未答问题。**

旧服务端没有 `detail` 时，完整应用 Evidence 会内联返回（当它放得下时）。

## 4. 不返回应用图的清单路线

schema 支持 `view` 时：

```json
{
  "detail": "summary",
  "view": {"kind": "javascript-routes", "collection": "routes", "fields": ["path", "confidence"], "limit": 20}
}
```

同一个视图也适用于 `analyze_web_bundle` 的已选捕获源。
完整源 Evidence 被保留，用它的 `parent_evidence_id` 配 `inspect_analysis_view` 取
`summary`、`routes`、`occurrences`、`sources` 或 `unknowns`。

**静态模式、推断的部署基址、启发式系统分类和不可用的源，永远不构成路由可达性或完整路由分母的证明。**

端点观测和推断事实用 `analyze_web_bundle`：

```json
{"detail": "summary", "view": {"kind": "web-bundle", "collection": "endpoints", "limit": 32}}
```

完整源 Evidence 被保留，后续从保留的父证据读 `endpoints`、`inferences`、`summary` 页。
筛选后再请求细节；保留 `source_index` 配合父 ID 和集合，需要溯源时请求 `location` 或 `basis`。
**分页耗尽不代表生产者完整**：检查 `completeness`、结构化的 `source_unknowns` 和限制。
端点候选仍是**推断**，不是确认的网络行为。

## 5. 读模块而不重复分析

用实际返回的父 ID，同一连接上作为 `source.evidence_id`：

```json
{
  "source": {"kind": "retained-evidence", "evidence_id": "ev_ACTUAL_PARENT_ID"},
  "view": {"kind": "page", "collection": "modules", "offset": 0, "limit": 16}
}
```

模块页只返回 node ID、路径和角色；选一个有用的页大小，需要下一页时跟 `coverage.next_offset`。

按**精确 `node_id`** 和记录的角色选中条目：

```json
{
  "source": {"kind": "retained-evidence", "evidence_id": "ev_ACTUAL_PARENT_ID"},
  "view": {"kind": "item", "collection": "modules", "selector": {"node_id": "jag_node_ACTUAL_NODE_ID"}}
}
```

模块页包含 asset、bundled 和 source 模块角色，所以**一个路径可能对应多个条目**。
只在唯一性已建立时用 `selector.path`；返回的 node ID 让你不必清点完整清单来证明唯一性。
有歧义时，从页面或错误的候选里选匹配的 node ID。

条目暴露该模块节点的记录观察、身份、哈希、导出和源码范围；
它**不**包含每个子语法观察、相关边或原始源文件。**条目里缺少某个事实，不构成整个应用中缺失的证据。**

### 只要规范身份和保留的源码范围计数

```json
{
  "source": {"kind": "retained-evidence", "evidence_id": "ev_ACTUAL_PARENT_ID"},
  "view": {
    "kind": "javascript",
    "collection": "modules",
    "projection": "references",
    "where": {"path": "main.js", "kind": "javascript-module"},
    "offset": 0,
    "limit": 16
  }
}
```

筛选匹配精确保留字符串；省略筛选包含所有值，`path: null` 表示路径不可用，`path: ""` 表示记录的空路径。
行保留规范 `identity` 和不同的观察支撑状态（在 `basis` 里）。
`retained_source_range_count` 数的是保留的源码范围观察，**不是**运行时导入或唯一引用点。

### 精确的文件/原生元数据或处理缺口

```json
{
  "detail": "summary",
  "view": {
    "kind": "javascript-facts",
    "where": {"paths": ["package.json"]},
    "property_keys": ["name", "operation", "analysis_status"],
    "limit": 32
  }
}
```

行保留规范 node/observation 身份和原始 Evidence。路径匹配 Evidence 的产物路径/源码范围位置；
缺失属性保持省略，源码覆盖与分页耗尽是**分开的**。
名字未知时用 `include_available_property_keys: true`，它按返回的观察列出原始键（不含未选中的值）。

## 6. 只追剩下的那个问题

在父应用 Evidence 上用 `trace_application_feature`，传一个字面 node ID、路由、字符串、API、IPC 通道、模块或原生导出。
`incoming` 是指向种子的关系，`outgoing` 是离开它的，`both` 是两者都需要时。

**trace 遍历包含包含关系**，所以即使很窄的种子也会扩展出很多节点；双向 trace 可能到达无关的兄弟模块。
模块的条目或页面在观察已经回答问题时**更合适**。
**不要把到达的所有节点都当成该功能的参与者。**

有保留的父证据就用它，或提供完整 Evidence 内联。
只在 Hopper/Ghidra Evidence 的产物摘要**完全匹配**时才包含它们。

## 7. 恢复过大的显示

过大的响应会报 `resource_constraint` 且 `details.resource: "transport"`。
用 `details.reported_limits.evidence_reference` 配 `inspect_analysis_view` 取摘要、一个模块或稳定的模块身份页。
`export_evidence_bundle` 把完整规范会话写到调用方选择的文件。

**客户端可能在文本信封里截断成功结果，而没有 REA `resource_constraint`。**
把截断提示或不完整 JSON 当**显示限制**处理；**不要**声称审查过完整记录。
用已知父 ID 取更小的视图，或在会话还开着时导出完整 Evidence。
父 ID 从预览里丢了，就用之前的分析摘要或明确的台账条目恢复它；
**不要发明 ID，也不要为了复现同一个显示而重跑分析。**

BrowserWindow 偏好、preload 和 contextBridge 表面、IPC 注册、utility 进程和原生绑定请求都是**静态语法观察**。
**只有唯一的精确字面 IPC 通道匹配**支持推断配对。动态或有歧义的通道保持未解析。
请求的 `.node` 成员**不是**已验证的原生导出。
**绝不声称静态分析得出的运行时可达性、注册、默认值或策略强制执行。**

## 8. 版本对比

每个版本**各分析一次**，然后调 `compare_application_versions`。
只接受它的摘要、source map、结构指纹或非模块语义匹配。
**模块序号和压缩名不是持久身份。**
只有在完整覆盖对侧时才能报告新增或删除，否则报告 unknown。

问「某个确切导出可调用对象返回的对象形状怎么变了」时，各分析一次然后调
`compare_javascript_export_shapes`，传明确的模块路径和导出名。
用两次分析在同一连接上返回的 ID，或完整内联 Evidence 记录。
变体配对**只**通过工具的唯一精确字面判别式接受。

读 `property_inventory` 和每个变更的 `presence`，再把 `unknown` 当成「没观察到该名字」。
清单会列出**已观察到的**属性名，即使值仍未知，每个配对或未配对变体都有 `source_range`。
数组空洞和被失效的槽位**不是**观察到的属性。
完整的父覆盖会独立于未解析的值报告 presence-only 的 `added`/`removed`。
这是**静态推断，不是运行时行为**。需要运行时语义时，对相关版本跑行为探针。

## 9. 复用应用 Evidence

应用 trace 和对比工具接受完整内联 Evidence 或：

```json
{"kind": "retained-evidence", "evidence_id": "ev_<64 位小写十六进制>"}
```

用于它们的 `application`（或 `left`/`right`）输入。`inspect_analysis_view` 在 `source` 里用同样的保留引用形式。

这是**模板**：必须换成生产者实际返回的 ID。4.1.0 之前的版本只接受完整内联 Evidence。
使用生产者**在同一 MCP 连接**上返回的精确 ID。解析不运行分析也不选 provider；发现保持内联。
原生观察数组仍要完整 Evidence。`close_binary` 会清掉保留引用；
关闭前导出 bundle，或在另一个连接里提供可移植的内联 Evidence。
缺失的引用会包含它的 ID 和恢复指引。

## 10. CLI 大输出的处理

真实应用的完整应用 Evidence 可以有数百 MB。**落盘再投影**：

```bash
rea analyze-javascript-application /absolute/path/to/app --json > app-evidence.json
jq -c '{source: {kind: "inline", evidence: .}, view: {kind: "summary"}}' app-evidence.json > app-view.json
rea inspect-analysis-view app-view.json
```

也可以让请求指向已保存的文件而不是内联：

```json
{"source": {"kind": "evidence-file", "path": "app-evidence.json"}, "view": {"kind": "summary"}}
```

CLI 把相对路径解析到工作目录；MCP 客户端传绝对路径。
REA 读取并认证该文件，然后像保留 Evidence 一样投影。

JSONL 行式输出：

```bash
rea inspect-analysis-view observations-view.json --format jsonl > observations.jsonl
```

对象集合会用一个控制记录结尾：

```json
{
  "$rea": "jsonl/v1",
  "type": "metadata",
  "records": {"path": ["normalized_result", "rows"], "emitted": 2, "source": 10, "filter": "normalized_result.rows[0,2]"},
  "context": {"evidence_id": "ev_…", "normalized_result": {"coverage": {"status": "page", "examined": 10, "total": 100, "next_offset": 10, "exhausted": false}}}
}
```

要一份完整报告或标量字段的脚本用 `--format json`。
顶层数组按源顺序输出元素。对象必须有一个明确的 `rows`、`items`、`records` 或 `occurrences` 数组（直接在顶层或 `page` 下）。
其他选择会被拒绝（错误码 `invalid_request` / `invalid_input`）——分析本身是成功的。
有多个集合时用 `--filter-output` 选一个，例如 `normalized_result.rows`。

## 11. 文档

[JS 应用工作流](https://github.com/morluto/rea/blob/main/docs/javascript-application-workflows.md) ·
[JS 源码恢复](https://github.com/morluto/rea/blob/main/docs/javascript-recovery.md) ·
[JS 路由清单](https://github.com/morluto/rea/blob/main/docs/javascript-route-inventory.md) ·
[JS 产物重建](https://github.com/morluto/rea/blob/main/docs/javascript-artifact-reconstruction.md) ·
[JS 应用图](https://github.com/morluto/rea/blob/main/docs/javascript-application-graph.md)
