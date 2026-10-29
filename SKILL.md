---
name: rea-reverse-engineering
description: 用 REA（MCP 服务器 + CLI）逆向分析原生二进制、Electron/JavaScript 应用、Android APK、.NET 托管程序集、固件镜像、模型文件、浏览器与网络抓包，并从录制流量构建 AgentEnv 智能体环境。当需要回答「这个 app 某功能怎么实现的」「反编译这个 exe」「对比两个版本差异」「扒出前端路由」「这个 APK 用了什么框架」「把网站录制成 RL 环境」等只能通过成品产物或运行时证据回答的问题时使用。普通源码仓库的架构分析不要使用本技能。
agent_created: true
metadata:
  version: "1"
  upstream: "https://github.com/morluto/rea"
  upstream_package: "rea-agents"
---

# REA 逆向工程

REA 是一个 MCP 服务器兼 CLI，把「已发布的产物」变成可检索的证据：原生二进制、Electron/JS 打包应用、APK、.NET 程序集、固件、模型文件、浏览器与网络抓包。

**何时用**：结论必须依赖已发布的二进制或安装包、反编译结果、用户要求的运行时证据，或与「源码无法证明的行为」的对比。
**何时不用**：分析一个完整的源码仓库时，用普通仓库工具即可，不要跑 REA 的 readiness/provider 命令。

## 一、连接前先判断，不要每次都诊断

安装本技能只提供说明，**不会**注册 MCP 服务器、不安装分析引擎、也不给已在运行的 agent 加工具。

按这个顺序判断，避免把时间浪费在重复 setup 上：

1. **当前会话里有 REA 工具吗？** 有就直接开工，不要先跑 doctor。
2. **没有工具** → 读 [references/setup-and-connect.md](references/setup-and-connect.md)，按其中的注册流程处理。
3. **注册存在但连不上** → 读 [references/connection-and-recovery.md](references/connection-and-recovery.md)，按阶梯排查。

关键事实（省得重复踩）：

- `rea setup` **不支持 WorkBuddy / OpenClaw**，只支持 Claude Code、Codex、Cursor 等 20+ 个客户端。对这两个平台必须**手写 MCP 注册**，本仓库的 `scripts/install_mcp.py` 就是干这个的。
- REA setup **从不**安装或升级 Node.js、npm、Homebrew、Java、Ghidra、IDA、JADX、Kuna、Binwalk、Unblob。用已有环境，不要为了修 MCP 注册去装无关软件。
- REA 要求 Node `^22.23.4 || ^24.22.1 || >=26.12.1`。版本太低时 `npx rea-agents` 会直接失败。
- 静态 JS 分析和普通 ZIP 清单**不需要**任何原生引擎，这是最稳的入口。

### 没有 MCP 时的 CLI 兜底

MCP 不可用时，对操作者提供的 JS 目录或 ASAR：

```bash
npx -y rea-agents@latest analyze-javascript-application /absolute/path/to/app --json
```

这条命令不需要 MCP 注册，也不需要原生引擎。返回的 Evidence 要和 MCP 结果一样认真读。
CLI 兜底**不代表** MCP 已配置好；原生分析任务仍然需要对应引擎。

## 二、按目标类型路由（第一步选对工具）

从用户给的目标出发选第一个工具。`open_binary` 用于活动目标（原生/归档）的工作流；target-free 工具各自带自己的路径参数，不需要先开会话。

| 用户给的目标 | 第一个工具 |
| --- | --- |
| ASAR 或解压后的 JS/Electron 目录 | `analyze_javascript_application` |
| 归档/包成员清单（ZIP/APK/IPA/MSIX、DMG、PyInstaller 可执行） | `open_binary` + `inspect_artifact` |
| Apple app 的 plist / Interface Builder / 资源目录 / keyed archive | `open_bundle_resources` |
| Android APK 的代码、类、方法、引用 | `inspect_android_package` |
| 托管 PE/CLI 程序集（.NET） | `inspect_managed_artifact` |
| 固件镜像 | `inspect_firmware_regions`（未广告时用 `extract_firmware`） |
| ESP32 系 app/bootloader 镜像（`0xE9` magic） | `inspect_artifact`（不带 provider） |
| .NET NativeAOT PE/ELF | 原生 Ghidra 分析 |
| 原生程序行为、实时调用、插桩、命令运行副作用 | [runtime-observation.md](references/runtime-observation.md) 的原生运行时工作流 |
| 用户已打开的浏览器页面 | `list_browser_targets` |
| 需要 agent 自己去点/输/跳转的浏览器动作 | `capture_browser_scenario` |
| 已有的 HAR / SAZ / pcap 抓包 | `inspect_web_network_capture` |
| 用户已打开的 Electron 运行时 | `list_electron_targets` |
| 抓包字段发现（先搜再选） | `inspect_packet_fields` |
| 录制的逻辑/信号波形 | `decode_signal_recording` |
| 明确的本地 WASM 产物 | `inspect_wasm_artifact` |
| APK 签名（v1/v2/v3/v3.1、证书指纹、key 轮换） | `inspect_apk_signature` |
| EVM 字节码载体 | `inspect_evm_interface` |
| Go 编译信息 / 模块 / 构建设置 | `inspect_go_binary` |
| GGUF / safetensors 模型声明 | `inspect_model_artifact` |
| Unity IL2CPP `global-metadata.dat` | `inspect_il2cpp_metadata` |
| Rust cargo-auditable 依赖元数据 | `inspect_rust_binary` |
| PE Authenticode 证书表 | `inspect_pe_certificates` |
| PE 导入表 / 延迟加载表 | `inspect_pe_imports` |
| PE TLS 回调 / Load Config | `inspect_pe_load_config` |
| ELF note 表（build-id / ABI tag） | `inspect_elf_notes` |
| Apple `.ips` 崩溃报告 | `inspect_apple_ips` |
| Linux 内核模块元数据 | `inspect_kernel_module` |
| CPython 3.7–3.13 `.pyc` | `inspect_python_pyc` |
| Erlang BEAM `.beam` | `inspect_erlang_beam` |
| 本地 SQLite 快照 | `inspect_sqlite_database` |
| Linux ELF 离线布局/符号/重定位 | `inspect_binary_layout` |
| Linux x86-64 ELF core dump | `inspect_recorded_crash` |
| PE 资源树 / 静态图标 | `inspect_pe_resources` |
| PE 导出表 / ELF 动态符号导出 | `inspect_native_exports` |
| 原生可执行文件、库或分析数据库 | `open_binary`，然后直接用聚焦分析工具 |
| Web 应用的 AgentEnv 智能体环境 | [environments.md](references/environments.md) |

target-free 工具的细则（每个的证据边界、限制、CLI 等价命令）见
[references/native-and-artifacts.md](references/native-and-artifacts.md)。

**用户只说「我的 app」而没给名字、路径或已选定的目标时，先问是哪个 app**，不要自己去猜路径，也不要拿示例 app 顶替。

**不要调用未广告的工具。** 用 `binary_session` 传 `{}` 查 `result.tool_availability`，里面给出每个操作的可用性、原因和客户端要求。分组里的 `names` 展开后就是完整的工具清单。

## 三、摘要优先，再取细节

从默认结果开始，用它的 inline Evidence 和图上下文。

**体积未知或很大的目标**（JS 应用、ELF 布局），第一步就用 `"detail": "summary"`，再用返回的 `parent_evidence_id` 调 `inspect_analysis_view` 取需要的页。

MCP 下 `analyze_function` 默认就是摘要，完整 dossier 保留在 `parent_evidence_id` 下按需分页。要 `detail: "complete"` 的场合只有一种：dossier 必须内联传递时（比如 `build_call_path` 需要）。

不要重复同一次分析，也不要重复一个已被拒绝的调用，除非输入变了或阻塞点被解决了。**只在返回结果留下了具体疑问时**才做跟进。

客户端可能把成功结果截断而不报错。看到截断提示就把该预览当作不完整处理，用 `parent_evidence_id` 取小视图，或导出完整记录。**不要把截断预览当规范 JSON 解析，也不要为了复现同一个显示而重跑生产者。**

JS 应用的大图上做双向 trace 会炸开无关的包含关系 —— 先读 [javascript-applications.md](references/javascript-applications.md) 的模块视图和 trace 配方。

## 四、结论必须分清三类

每一个结论都要区分 **观察（observation）**、**推断（inference）** 和 **未知（unknown）**：

- 引用 Evidence ID，保留 limitations 和不完整覆盖。
- **绝不暗示静态分析观察到了执行过程。**
- 运行时请求会真的执行声明的目标和生命周期，不要扩大目标和动作范围。
- 「表里没找到」不等于「不存在」—— 保留搜索边界，说明覆盖范围。

## 五、跨模块的复杂调查：分阶段

请求跨越多个功能或子系统时，走这套流程：

1. 把请求拆成问题清单，每个问题标明需要什么证据。
2. 查当前会话、产物身份、已保存的分析数据库和既有证据，**复用匹配状态**，不要开重复会话。
3. 从最小有用的概览或清单开始，按假设批量相关操作，只在证据留下具体缺口时扩展。
4. 同时检查相关打包资源和配置 —— 用格式感知的清单和解析器，不要只凭文件名、字符串或布局推断行为。
5. 用结论所需的那类证据来佐证。静态证据答不了、且宿主运行时和 OS 权限都具备时，才上运行时观测。
6. 拆成互相独立的问题。问题之间无依赖且有并行 worker 时，分配互不重叠的范围，让每个返回来源、结论和未解缺口。
7. 维护一份简洁的**发现台账**：每个结论 ↔ Evidence ID、置信度/证据类型、搜索边界、剩余未知。

收尾前回到最初的问题清单，逐条标记为 已回答 / 部分回答 / 未解决。**有必须回答的问题还悬着，就不要把这次调查说成「完成」。**

## 六、按需只读对应的参考文档

| 需要做的事 | 读这个 |
| --- | --- |
| 安装、注册 MCP、配置 provider、连通性排查 | [setup-and-connect.md](references/setup-and-connect.md) |
| 原生二进制、托管程序集、归档、解包、各类内嵌元数据 | [native-and-artifacts.md](references/native-and-artifacts.md) |
| ASAR、解压 JS、功能追踪、版本对比 | [javascript-applications.md](references/javascript-applications.md) |
| Android APK 的声明、类、方法、静态引用 | [android-applications.md](references/android-applications.md) |
| 原生插桩/调试器/进程捕获、浏览器与 Electron 观测 | [runtime-observation.md](references/runtime-observation.md) |
| Evidence 分页、对比、残留未知、验证 | [evidence-workflows.md](references/evidence-workflows.md) |
| Web 应用的 AgentEnv bundle | [environments.md](references/environments.md) |

## 七、收尾

用平实语言解释发现，并绑定到返回的证据上。用户要求动手实现时，用常规编码工具，并把**观察到的行为**和**你的设计选择**分开说明。

调查结束时用 `close_binary` 关掉已打开的原生会话。
