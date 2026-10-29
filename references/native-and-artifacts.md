# 原生、托管与打包产物

本文覆盖原生二进制、.NET 托管程序集、归档包，以及大量「有专用内嵌元数据」的文件类型。

## 通用原则

这类工具大多是 **target-free** 的：直接传本地绝对路径，不需要 `open_binary`，不启动反汇编器，不需要 provider。

**但结论边界依然严格：**

- 缺失的记录是 **unknown**，不是「不存在」的证明。
- 「没有导入表目录」= 观察到**没有那张表**，不等于这个镜像从未通过别的表导入过 API。
- 「没有 security 目录」= 观察到**没有那张表**，不等于这个镜像在所有目录意义上都未签名。
- 保留产物 SHA-256、文件范围、哈希和原始拼写。
- 托管声明的元数据**不能**自证其真实性。

## 1. 活动目标：原生分析

原生可执行文件、库或分析数据库：先 `open_binary`，再直接用聚焦分析工具。
需要元数据或清单上下文时调 `binary_overview`（若所选 provider 提供）。

**provider 选择**：已有 IDA MCP 配置时，用 `open_binary` + 原始输入二进制 + `provider_id: "ida"`，
**不要**传 `.idb`/`.i64` 数据库。

- **legacy attached** 模式按 SHA-256 绑定已打开的 GUI 输入，数据库保持打开。
- **modern headless** 模式创建并关闭自有私有数据库，不保存。

迁移到独立 IDA MCP 插件时，**显式替换**上游注册 —— modern mrexodia 工具不属于 native profile。
native attachment 保留数据库但**不提供直接调用者**；开箱即用请查会话可用性。
IDA 不提供 `binary_overview`，开箱后直接用 `analyze_function`、伪代码或函数/字符串搜索。

**Kuna**（配置了 `REA_KUNA_COMMAND`）：`provider_id: "kuna"` 从 Kuna 缓存的全程序导出回答过程列表、查找、伪代码、汇编和 `analyze_function`。
调用者/被调用者用会话共享的**无函数体图**；`xrefs` 返回精确地址的入边并过滤转发别名。
这些查询**不触发** C 导出。间接调用目标仍是 unknown，会让关系覆盖变得不完整。
参考缓存在关闭时失效；新的 CLI 进程会重走一遍原生引用遍历。
伪代码和汇编的 `raw_result.source` 会给出缓存的 `.c`/`.asm` 文件和字节范围，**可以直接搜这个文件**而不用逐函数调用。
不支持类型化引用、CFG、裸内存工具和标注。

**Ghidra 启动超时**（大目标）：见第 9 节的 deadline 恢复，别急着放弃深度分析或重复冷导入。

## 2. 发布版本对比

关闭会话前先导出每个目标的 `list_procedures` Evidence —— close 会清掉会话记录。
两个目标都收集完后再导入两份 bundle，或直接提供可移植的 inline Evidence。

`match_native_functions` 配对唯一精确名，并在提供时配对完整观察到的函数体字节。
复用 `list_names`、`procedure_info`、`read_bytes` 和既有的 `analyze_function` dossier 作为 `left_observations`/`right_observations`。
**MCP 的 `analyze_function` 摘要回复贡献的是它的 `parent_evidence_id`（作为 `retained-evidence` 引用），不是摘要本身。**

**不要为了匹配而反编译每一个函数。** 摘要保留了父 ID，用 `inspect_analysis_view` 的 `function-matches` 集合 `matches` 和 `functions` 查。
选列、批量 ID、逐条翻页；别名保持未解析状态。未配对的观察**不证明**新增或删除。

匹配表示被拒绝时，看 `details.limit`，用 `update_analysis_settings` 抬 `native.matching_representation_bytes` 后重试**未改动的** MCP 请求。
CLI 启动种子：`REA_NATIVE_MATCHING_REPRESENTATION_BYTES`。默认 96 MiB，策略范围 1 byte 到 1 GiB。
**保持完整清单：拆分清单会改变全局的名字/函数体唯一性。**

## 3. Apple app 资源

用 `open_bundle_resources` 传 app 路径，然后 `inspect_plist`、`decode_interface_builder`、`inspect_asset_catalog`、`inspect_keyed_archive`。

资源会话读取 app 但**不解析** `CFBundleExecutable`，也不启动深层 provider。
保留 `resource_root` 来源、各资源哈希（若报告了）和 null 的可执行文件身份。
**目录路径不是可执行文件摘要。** 二进制分析快照不适用于资源会话。
导出保留的 Evidence 再关闭或换根目录。要转可执行文件分析用 `open_binary`，用 `close_binary` 释放两种会话。

对应的四个 CLI 命令直接接受 app 路径。app 内的归档用 `inspect-keyed-archive APP_PATH RELATIVE_ARCHIVE_PATH`。

## 4. 桌面安装目录

安装目录已知但运行时未知时，用 `inspect_desktop_application` 传绝对路径。
用 `inspect_analysis_view` kind `desktop-application` 读 `files`、`omissions`、`candidates`、`components` 或 `next_probes`。
摘要里的 `probe_issues` 保留计数和有界预览。

用 `has_issues: true` + 字段 `path`、`read_status`、`issues` 直接取精确失败项。
**预览文本是显示数据，`file_id` 才选中完整事实。**
目录快照身份**不是**每个文件内容的摘要。组件路径标记**不证明**运行时存在。

紧凑 CLI 输出：`inspect-desktop-application PATH --detail summary --evidence_output BUNDLE`。

## 5. 各类内嵌元数据工具

以下是 target-free 的，**不需要** `open_binary`、不需要对应语言的安装、不执行目标。

| 工具 | 目标 | 关键点 |
| --- | --- | --- |
| `inspect_go_binary` | 显式本地 ELF/PE/Mach-O | 嵌入式编译器版本、模块/依赖版本、local replacement、构建设置。通用二进制需 `architecture`。缺失记录是 unknown，不是「非 Go」的证明。 |
| `inspect_model_artifact` | GGUF v2/v3、safetensors | header-only 模式**不读权重**，也不建立全文件身份。要全量 SHA-256 必须 `hash: "full"`。视图可分页 `metadata`、`tensors`、派生的 `types`。数组保留类型计数和 8 元素预览。 |
| `inspect_il2cpp_metadata` | Unity `global-metadata.dat`（版本 24/27/29/31/39） | 装配镜像、名字、成员归属、字符串字面量、命名空间、索引范围。用 `inspect_analysis_view` 查 `sections`/`images`/`types`/`methods`/`fields`/`properties`/`events`/`parameters`/`string_literals`。行索引按产物 SHA-256 和集合作用域。无法识别的 magic 可能意味着加密，**不支持**，不是「已解密」。 |
| `inspect_rust_binary` | ELF/PE/thin Mach-O | cargo-auditable crate 列表（`.dep-v0`；Mach-O 是 `__DATA,.dep-v0`）。包顺序、依赖索引和 section 文件范围。rustc commit hash 是从只读路径推断的，**本身不能**识别编译器。 |
| `inspect_pe_certificates` | PE32/PE32+ | Authenticode 证书表、WIN_CERTIFICATE 类型、PKCS#7 签名者和 X.509 身份字段。`subject_key_identifier_hex` 在签名者用该形式时保留。**签名未被验证。** 证书链、时间戳和摘要覆盖都未观察。 |
| `inspect_pe_imports` | PE32/PE32+ | DLL 名、具名/序号函数、ILT/IAT RVA、延迟加载描述符、标准导入表的 pefile 导入哈希。绑定快照和已加载的 IAT 内容未观察。 |
| `inspect_pe_load_config` | PE32/PE32+ | TLS 回调、security cookie、SafeSEH、CFG、EH-continuation、XFG 声明。回调 VA 以十六进制字符串保留。**防护标志缓解措施是 `evidence_kind: "inferred"`，实际强制执行未观察。** |
| `inspect_elf_notes` | ELF32/ELF64 | PT_NOTE / SHT_NOTE 的 owner、类型、descriptor SHA-256、GNU build-id、ABI tag 字段。 |
| `inspect_apple_ips` | Apple `.ips` | 首行元数据、`bug_type`（字符串）、进程和异常事实、无损整数寄存器、usedImages UUID、文档化分类匹配。**只有 `bug_type` 为 `"309"` 才产出崩溃体**，其他类型（含 `"288"` stackshots）不返回崩溃结果。已打开的 Mach-O 和 dSYM UUID 关联未观察。 |
| `inspect_kernel_module` | ELF32/ELF64 可重定位对象 | `.modinfo` 键顺序和重复键、`__versions` CRC 十六进制、section 文件范围、追加签名尾部的 PKCS#7 SHA-256。`struct module` **不**解码（布局随内核版本变）。签名**未**验证。gzip/xz/zstd 容器**不支持** —— 先用外部工具解压成独立文件再检查。 |
| `inspect_python_pyc` | CPython 3.7–3.13 `.pyc` | magic、PEP 552 哈希或 mtime/size、嵌套 code object 名、字节码 SHA-256。**字节码不被反编译**，解码出的头部不证明对应的 `.py` 存在。 |
| `inspect_erlang_beam` | Erlang `.beam` | chunk 名、原子顺序、导出/导入/lambda 表、Code 头。缺失表计数保持 null；已解码的空表算 0。字节码不被执行。 |
| `inspect_managed_artifact` / `inspect_managed_members` | .NET PE/CLI | 元数据和 CIL，**不加载不执行**程序集。先查身份和部署形式再查成员。托管解析器要 PE/CLI 元数据；**不解包 .NET single-file host，也不解码 IL2CPP**。选择限制解码范围，成员引用仍是程序集级清单，输出可能仍很大。 |

### 托管程序的 CLI 流程

```bash
rea inspect-managed-artifact /absolute/path/Assembly.dll --json
rea inspect-managed-members /absolute/path/Assembly.dll --json
rea inspect-managed-members /absolute/path/Assembly.dll --type Example.Parser --json
```

`--type` 用成员检查里出来的**精确 `full_name`**，或已知的声明类型名。省略 `--type` 检查全部成员。

要紧凑输出：

```bash
rea inspect-managed-artifact /abs/Assembly.dll --detail summary --evidence-bundle /abs/bundle.json
```

summary **要求**显式目标路径；已有文件会被保留。之后可以用 `inspect-analysis-view` 从保存的 bundle 里翻页，无需重开程序集。

## 6. 归档与提取

归档/包成员清单（ZIP/APK/IPA/MSIX/AppX、DMG、PyInstaller 可执行）：`open_binary` 传本地路径，用 `inspect_artifact` 读图和发现。

- PyInstaller 的 **CArchive 是应用层**，bootloader 只是原生前缀。
- 大清单先用 `detail: "summary"`，再用保留的清单视图取选定成员字段/分页。
- 完整的小清单可能比多几次调用和 schema 更省。
- 运行时选项是元数据，不是文件。
- 紧凑投递依然会清点并哈希成员。
- `view: {kind: "inventory", collection: "occurrences", logical_paths: [...]}` 按逻辑路径取成员；省略则分页全部。`[]` 表示不选。
  其他清单集合是 `nodes`、`edges`、`integrity_contradictions`。
- **把 `source_complete` 和分页耗尽分开**：部分源 Evidence 里没匹配到，不证明源里不存在。

固件镜像：`inspect_firmware_regions`（未广告时用 `extract_firmware`，需要调用方指定新的绝对输出目录）。这些工具用调用方提供的 Binwalk/Unblob，仅 Linux。

ESP32 系 app/bootloader 镜像（`0xE9` magic）：`inspect_artifact` 不带 provider。

## 7. 离线路径

- **Linux ELF 离线布局/符号/重定位/静态缓解证据**：`inspect_binary_layout`。用调用方提供的 pwntools，不打开反汇编器数据库。保留原始位置和推断/覆盖限制。
- **Linux x86-64 ELF core**：`inspect_recorded_crash`。读每一个记录的线程、原始 note 和源码绑定寄存器，**不开活目标**。历史 PID 不选择活进程。
- **PE 导出表 / ELF 动态符号导出**：`inspect_native_exports`。可移植，不需要活动目标或引擎。支持 `detail: "summary"` + 保留完整表，用 `inspect_analysis_view` kind `native-exports` 查。`collection: "issues"` 翻解释失败。**空的局部页不证明不存在** —— `summary.coverage` 描述的才是源表。
- **PE 资源类型/名/语言树和静态图标**：`inspect_pe_resources`。不透明载荷保留文件范围和 SHA-256。

## 8. SQLite

`inspect_sqlite_database`。需要 Node.js 24.x >=24.15 或 26+ 提供原生 SQLite 限制。

- 先读 schema（默认紧凑清单），需要行时再选一个普通表和 `columns`。
- 默认是选中表的 schema + 20 行；要完整存储 schema 用 `schema_scope: "database"`。
- **保留数据库和已存在的同级 WAL 身份**；行样本会报告截断且顺序未指定。
- **用静止的快照**，不要假设活数据库/WAL 对是被原子复制的。

## 9. Deadline 恢复

Ghidra 启动期限默认 330 秒。对新启动尝试，用 `update_analysis_settings` 改 `ghidra.startup_timeout_ms`。
**改服务器的启动环境则需要新的 REA 进程。**

JS 分析的每个源文件期限用 `analysis_timeout_ms`（毫秒）。
内存受限的分析会保留已完成的静态事实，并报告**部分语义覆盖**和具体的未知范围 —— 这**不**意味着源码有问题。
累积结果耗尽可能在检查完所有文件前停止分析；清单和剩余未知范围能区分这种情况。

## 10. 需要查看对应文档的清单

- [Go 二进制](https://github.com/morluto/rea/blob/main/docs/go-binaries.md)
- [Rust 二进制](https://github.com/morluto/rea/blob/main/docs/rust-binaries.md)
- [IL2CPP 元数据](https://github.com/morluto/rea/blob/main/docs/il2cpp-metadata.md)
- [模型文件](https://github.com/morluto/rea/blob/main/docs/model-artifacts.md)
- [PE 证书](https://github.com/morluto/rea/blob/main/docs/pe-certificates.md) · [PE 导入](https://github.com/morluto/rea/blob/main/docs/pe-imports.md) · [PE Load Config](https://github.com/morluto/rea/blob/main/docs/pe-load-config.md)
- [ELF notes](https://github.com/morluto/rea/blob/main/docs/elf-notes.md)
- [Apple IPS](https://github.com/morluto/rea/blob/main/docs/apple-ips.md)
- [内核模块](https://github.com/morluto/rea/blob/main/docs/kernel-modules.md)
- [CPython pyc](https://github.com/morluto/rea/blob/main/docs/python-pyc.md) · [Erlang BEAM](https://github.com/morluto/rea/blob/main/docs/erlang-beam.md)
- [托管代码分析](https://github.com/morluto/rea/blob/main/docs/managed-code-analysis.md)
- [SQLite](https://github.com/morluto/rea/blob/main/docs/sqlite-databases.md)
- [固件分析](https://github.com/morluto/rea/blob/main/docs/firmware-analysis.md)
- [Python 打包应用](https://github.com/morluto/rea/blob/main/docs/python-packaged-applications.md)
- [桌面应用](https://github.com/morluto/rea/blob/main/docs/desktop-applications.md)
- [Ghidra provider](https://github.com/morluto/rea/blob/main/docs/ghidra-provider.md) · [IDA provider](https://github.com/morluto/rea/blob/main/docs/ida-provider.md) · [Kuna provider](https://github.com/morluto/rea/blob/main/docs/kuna-provider.md)
