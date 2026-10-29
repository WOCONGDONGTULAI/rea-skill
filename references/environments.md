# 从活应用构建 AgentEnv 智能体环境

## 这是什么

一个 **AgentEnv bundle** 是一整个可部署的文件夹：它的 MCP 工具**只根据一次应用录制**来回答，
并且只服务那次录制**确认过**的写操作。

工作流：录制应用一次（`capture_browser_scenario`）→ 检查这个环境**会服务什么** →
如果提示指出了缺口就再录一次 → 用 `export_environment_bundle` 写出 bundle。

用户已经有 HAR 时，跳过录制，直接走
[导出](#导出与交付)（`inspect_web_network_capture`），
或用 `rea environment-build <capture.har> <dir>`。

## 录制前

**只对用户声明为「一次性」或「为此专门播种」的实例录制**：
每个写步骤都会创建、编辑或删除它的数据。
**用户没有这么说时，任何带写的场景都要先问。**
REA **不会**启动、播种或重置应用。

**凭证来自用户指名的环境变量。** 每个声明为场景 secret：`{secret_id, environment_variable}`；
该变量必须在 REA MCP 服务器启动时的环境里已设置。
**绝不索要聊天里的密码。** 声明的 secret 在捕获记录时会被脱敏。

**先测绘应用**：用 `inspect_web_page`（布局重要时加 `capture_web_screenshot`）——
登录表单的定位器，以及用户要求列和编辑的实体背后的 API 调用。

`inspect_web_page` **不能登录**。要看登录后的页面，
跑一个短的 `capture_browser_scenario` 完成登录并打开它们，
用 `"capture": {"after_each_step": ["accessibility"]}`（要标记用 `"dom"`）。
读某一步的树用 `inspect_analysis_view`：

```json
{"view": {"kind": "browser-scenario", "collection": "text", "step_index": 0, "artifact": "accessibility", "offset": 0, "limit": 2048}}
```

用 `offset` 翻页。捕获选项**只有** `after_each_step`、`at_end`、`events`、`network` 和 `limits`。

## 录制一个环境能学到写操作的会话

**一次 `capture_browser_scenario` 记录整个会话。** 从这个形状开始，
换成应用自己的定位器、路径和 header：

```json
{
  "browser": {"mode": "launch", "executable_path": "/usr/bin/chromium"},
  "start_url": {"url": "http://127.0.0.1:3000/login"},
  "secrets": [
    {"secret_id": "admin_password", "environment_variable": "APP_PASSWORD"}
  ],
  "capture": {
    "network": {"request_body": true, "response_body": true, "header_values": true}
  },
  "actions": [
    {
      "step_id": "user",
      "action": "fill",
      "timeout_ms": 15000,
      "locator": {"kind": "css", "selector": "input[name=username]"},
      "value": {"source": "literal", "value": "admin"}
    },
    {
      "step_id": "password",
      "action": "fill",
      "timeout_ms": 15000,
      "locator": {"kind": "css", "selector": "input[name=password]"},
      "value": {"source": "secret", "secret_id": "admin_password"}
    },
    {
      "step_id": "sign-in",
      "action": "press",
      "timeout_ms": 15000,
      "locator": {"kind": "css", "selector": "input[name=password]"},
      "key": "Enter"
    },
    {
      "step_id": "signed-in",
      "action": "wait_for",
      "timeout_ms": 15000,
      "locator": {"kind": "css", "selector": "nav a[href='/settings']"},
      "state": "visible"
    },
    {
      "step_id": "folders-1",
      "action": "request",
      "timeout_ms": 15000,
      "method": "GET",
      "path": "/api/folders",
      "expected_status": [200]
    },
    {
      "step_id": "new-folder-1",
      "action": "click",
      "timeout_ms": 15000,
      "locator": {"kind": "role", "role": "button", "name": "New folder"}
    },
    {
      "step_id": "folder-title-1",
      "action": "fill",
      "timeout_ms": 15000,
      "locator": {"kind": "css", "selector": "input[name=title]"},
      "value": {"source": "literal", "value": "Scratch folder 1"}
    },
    {
      "step_id": "create-folder-1",
      "action": "click",
      "timeout_ms": 15000,
      "locator": {"kind": "role", "role": "button", "name": "Create"},
      "save_response": {
        "method": "POST",
        "path": "/api/folders",
        "save": [{"name": "folder_1", "json_pointer": "/id"}]
      }
    },
    {
      "step_id": "read-folder-1",
      "action": "request",
      "timeout_ms": 15000,
      "method": "GET",
      "path": "/api/folders/{saved:folder_1}"
    }
  ]
}
```

**`save_response` 是关键**：它把创建响应的 `/id` 存成 `folder_1`，
之后可以用 `{saved:folder_1}` 引用。**没有这一步，环境学不到写操作的关联效果。**

每个动作都需要 `step_id`（在捕获和后续步骤里保持唯一）、`action` 和 `timeout_ms`。
定位器用 `kind` + 对应的选择器字段（`css` / `role` / `text` / `xpath` 等）。
值可以是 `{"source": "literal", "value": "..."}` 或 `{"source": "secret", "secret_id": "..."}`。

**录制顺序很重要**：环境的状态来自**第一次相关写之前的读**。
所以要**先读列表，再写，再读回**，这样写计划才能被后续的读确认。

## 导出与交付

`export_environment_bundle` 写出 bundle。写出前先检查覆盖：

```json
{"view": {"kind": "environment-coverage"}}
```

覆盖视图告诉你哪些读工具从状态回答、哪些被回放、哪些写工具被服务或被扣留，
以及**下一步该录什么**的提示。**它不**应用 serve 时的目录和状态大小检查。

用户已有 HAR 时：

```bash
rea environment-build ./session.har ./my-env --name my-env --json
agent-env run ./my-env
```

`environment-build` 一步完成检查、投影和导出，并打印同样的覆盖（bundle 服务回放时打印 `null`）。
它导出一个带基础测试的可运行环境，用来检查它能启动并响应。

用它配你的 RL 框架：定义任务目标、加奖励检查、跑训练。

### 提供环境清单和捕获

```bash
rea environment-serve manifest.json --evidence capture.json --port 8765
```

manifest 的 `parent_evidence_id` **必须**等于 evidence 文件的 `evidence_id`；
不等就在绑定前拒绝（`invalid_request`）。

服务前，它用 manifest 的 `template_rules` 派生捕获的 `environment-state` 视图（和 `inspect_analysis_view` 一样），
并从它服务：读工具的视图由状态支撑时从活状态回答；
写工具**只在捕获的后续读确认了效果**的地方被服务；
`/agentenv` 服务 `data/reset`、`data/add` 和 `data/get`。

状态无法派生时（不可派生，或目录超过发现预算），
它记一条带错误码和消息的警告并改为回放。`--replay-only` 强制回放。
回放时每个 manifest 工具重放它引用的保留捕获记录，`/agentenv` 对每个方法回 JSON-RPC `-32601`。

`--host` 和 `--port` 的解析顺序：标志 → `MCP_HOST`/`MCP_PORT` → `127.0.0.1` 和临时端口。
非 loopback 绑定需要 `MCP_ALLOWED_HOSTS`，主机名规则和 Host/Origin 门控与 `rea mcp --http` 相同。

## 给 RL 用的提示模板

```text
用 REA 从我的测试网页应用 http://127.0.0.1:3000 构建一个 RL 环境。
覆盖文件夹的列出、创建、重命名和删除。你可以创建和删除测试文件夹。
不要动已有数据。
保存在名为 my-env 的文件夹里。检查哪些操作能用，并告诉我怎么运行。
```

## 文档

[Agent 环境](https://github.com/morluto/rea/blob/main/docs/agent-environments.md) ·
[环境快速开始](https://github.com/morluto/rea/blob/main/docs/agent-environments-quickstart.md)
