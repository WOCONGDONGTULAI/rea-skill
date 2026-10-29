# Android 应用产物

## 1. 入口

用连接服务器广告的 Android 工具。仓库 main 和 npm 4.1.0 包含这一族。
**装技能本身不能给旧服务器加上它** —— 旧服务端直接没有这些工具。

从 `inspect_android_package` 开始，传调用方的 APK 路径，拿包身份、manifest 声明、覆盖情况和 inline Evidence。

然后按需要：

| 工具 | 用途 |
| --- | --- |
| `search_android_classes` | 找候选类 |
| `inspect_android_class` | 看一个类的成员 |
| `inspect_android_method` | 反编译一个方法 |
| `trace_android_references` | 找入向静态引用 |

**每次调用都自带自己的 APK 路径和明确的选择器**，不要先开原生会话。

方法有歧义时，**从类清单里选 `overload_index`**，不要猜。

## 2. JNI 绑定

发现 `inspect_android_jni_bindings`。选择原始 DEX 类/方法身份和可选的描述符、ABI 或逻辑库路径。

优先 `detail: "summary"`；完整 Evidence 保留在 `android-jni` 视图里，可分页 `declarations`、`libraries`、`candidates` 或 `binding` 行，带精确字段。

**全局的 native-pair 歧义在类选择后依然存在。**
保留 slot/重定位来源和源码覆盖：matched 只表示观察到的候选存在；**部分扫描不建立唯一性，也不证明缺失**。

这读 DEX/ELF 字节，**不**把 APK 加载进反编译器，**不**执行目标代码。
**运行时注册和加载保持未知。**

## 3. R8/ProGuard 混淆映射

R8/ProGuard 发布构建带 `mapping.txt` 时，把绝对 `mapping_path` 传给 `inspect_android_class` 或 `inspect_android_method`。

优先 `detail: "summary"`，拿归一化的符号或选中的方法体，**不重复**原始类元数据。
完整 Evidence 保留在链接的父 ID 下，可以导出；CLI summary 投递需要 `--evidence_output`。
省略或用 complete detail 会保留完整内联响应。

**继续按观察到的名字选择**；单独的 `mapping` 块在检查 DEX 类型和原型后，
把每个符号报告为 `mapped`、`ambiguous` 或 `unmapped`。

**REA 不验证这个 mapping 属于该 APK 的构建。**

## 4. 前置条件与宿主

- 需要**单独提供** headless JADX MCP JAR **0.7.1** 和 **Java 17 或更新**。
- `REA_JADX_MCP_JAR` 选择 JAR 的绝对路径；`JAVA_HOME` 可选 Java。
- 用 `rea doctor --provider jadx --json` 检查 JADX 配置并拿到缺失前置的补救建议。
- **Java 和 headless JADX MCP JAR 都是调用方自带的**；REA setup **不**安装也不配置它们。
- 配置就绪**不**等于对某个特定 APK 的分析能成功。

**平台**：Linux 和 macOS 用 POSIX 的 owned-process 边界。
Windows x64 需要匹配的打包原生控件，用自有 Job Object 和双向 stdio。
**每个宿主都需要完整 JDK，包含 `jdk.compiler`**；Windows 用 `JAVA_HOME` 选 `bin\java.exe`。

- 调用使用单个 worker 和 provider 期限。
- `REA_JADX_HEAP_MIB` 选 JVM 堆，`REA_JADX_OPERATION_TIMEOUT_MS` 选单次操作期限
  （整数毫秒，1 到 2147483647，默认 120000）。
- 改运行中 MCP 服务器上的那个期限：用 `update_analysis_settings` 设 `jadx.operation_timeout_ms`，
  然后在工作与清理稳定后重试。**新接受的操作用覆盖值；已接受的工作保留它的预算。**
  改启动环境需要新进程。
- **MCP 客户端的工具超时也要允许所选的期限。**
- **APK 从不启动，也不需要模拟器。**

## 5. 证据边界

- **manifest 条目和反编译文本是静态观察，不是执行，也不是策略强制执行。**
- 入向引用是**恢复出的静态关系**；反射、动态加载和未解析的调用保持未知。
- 保留产物摘要、位置、诊断信息和不完整覆盖。

## 6. APK 签名

`inspect_apk_signature` 处理明确的本地 APK（或 ZIP/AAB）签名。

优先它的 summary 或选定的 signer/digest/lineage 页；保留完整 Evidence，
后续用 `inspect_analysis_view` kind `apk-signature` 取跟进。

它报告：

- 存在哪些签名方案（v1 JAR、v2、v3、v3.1）
- 每个签名者证书的 SHA-256 指纹（v1 也包含，从它的 PKCS#7 块算）
- v3 key 轮换谱系
- source stamp
- 每个签名摘要是否仍与字节匹配（自一致性）

**这是身份和完整性判断，不是信任或真实性裁决。**

## 7. 归档成员 vs 代码分析

要**归档成员清单**而不是代码分析：用 `open_binary` + `inspect_artifact`。

## 8. 文档

[Android 分析](https://github.com/morluto/rea/blob/main/docs/android-analysis.md) ·
[APK 签名](https://github.com/morluto/rea/blob/main/docs/apk-signature.md) ·
[APK 工具资源分析](https://github.com/morluto/rea/blob/main/docs/apktool-resource-analysis.md) ·
[ADB 设备分析](https://github.com/morluto/rea/blob/main/docs/adb-device-analysis.md) ·
[Harmony 分析](https://github.com/morluto/rea/blob/main/docs/harmony-analysis.md)
