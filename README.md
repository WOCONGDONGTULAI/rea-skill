# REA 逆向工程 Skill

把 [REA](https://github.com/morluto/rea) 的逆向能力打包成一份 [Agent Skills](https://agentskills.io) 标准的技能包，
让 WorkBuddy 和 OpenClaw 都能直接调用。

REA 是一个 MCP 服务器兼 CLI，把「已发布的产物」变成可检索的证据：原生二进制、Electron/JS 打包应用、
Android APK、.NET 托管程序集、固件、模型文件、浏览器与网络抓包，并能从录制流量构建 AgentEnv 智能体环境。

## 为什么需要这份 Skill

REA 官方自带一个技能包，但它面向 Claude Code / Codex：

- 里面的连接恢复流程讲的是 `rea setup --client codex`、Codex 的 `tool_timeout_sec`、Codex 的审批策略。
- **`rea setup` 根本不支持 WorkBuddy 和 OpenClaw**（它只支持 20+ 个客户端，这两个不在列表里）。

这份 Skill 把官方的领域知识保留下来，把「客户端专属」的部分换成 WorkBuddy / OpenClaw 的实际做法，
并补上了两个平台的手写 MCP 注册流程。

## 安装

### 1. 装 REA 本体

```bash
npm install --global rea-agents
rea --help
```

或者不装，用 npx 兜底：`npx -y rea-agents@latest --help`

> **Node 版本要求**：`^22.23.4 || ^24.22.1 || >=26.12.1`。
> 低于此版本时 npm 只打印 `EBADENGINE` 警告 —— 实测 22.22.2 下 REA 6.8.0 能正常启动并完成 MCP 握手，不是硬性阻断。
> 用 `bash scripts/rea_doctor.sh` 检查。
>
> **注册格式注意**：`command` 必须是 `npx`，`-y` 是 npx 的参数 —— 不能写成 `command: "node", args: ["-y", ...]`，`node -y` 不是有效用法。

### 2. 注册 MCP

```bash
python3 scripts/install_mcp.py           # 预览
python3 scripts/install_mcp.py --apply   # 写入（自动备份原配置）
```

脚本会：

- 检查 Node 版本并给出明确提示
- 探测已全局安装的 REA（用 `rea mcp`）或退回到 npx
- 备份现有的 `~/.workbuddy/mcp.json` 和 `~/.openclaw/openclaw.json`
- 只增改 `rea` 那一条，不动其他条目

**写完记得重启客户端：**

- WorkBuddy：连接器管理页右上角的自定义连接器入口 → 对 `rea` 点「信任」。新 MCP 不会自动激活。
- OpenClaw：重启或重连 Gateway。注意键是 `mcp.servers`，**不是** `mcpServers`。

### 3. 装技能

**WorkBuddy**（用户级，所有项目可用）：

```bash
git clone https://github.com/WOCONGDONGTULAI/rea-skill.git ~/.workbuddy/skills/rea-reverse-engineering
```

**OpenClaw**（共享托管）：

```bash
git clone https://github.com/WOCONGDONGTULAI/rea-skill.git ~/.openclaw/skills/rea-reverse-engineering
```

或者让 OpenClaw 直接从 Git 仓库装：

```bash
openclaw skills install git:WOCONGDONGTULAI/rea-skill
```

> 两个平台用的是同一套 SKILL.md 标准，**同一份文件两边都能用**，不用改。
> 技能在会话启动时加载，中途安装的要**新开一个会话**才生效。

### 4. 验证

```bash
bash scripts/rea_doctor.sh
bash scripts/rea_doctor.sh --provider ghidra   # 附带 provider 检查
```

## 用起来

装好之后，直接用自然语言提需求即可，技能会被自动触发：

- 「这个 Electron app 的登录逻辑是怎么实现的？」
- 「帮我反编译这个 exe，看看它调了哪些 API」
- 「对比一下这两个版本的路由有什么变化」
- 「这个 APK 用了什么框架？有没有 JNI 绑定？」
- 「把这个测试网站录制成一个 RL 环境」

## 目录结构

```
rea-skill/
├── SKILL.md                              # 核心：路由表 + 工作原则
├── references/
│   ├── setup-and-connect.md              # 安装、MCP 注册、provider 配置
│   ├── connection-and-recovery.md        # 连接故障与 deadline 排查
│   ├── native-and-artifacts.md           # 原生二进制、托管程序集、归档、内嵌元数据
│   ├── javascript-applications.md        # ASAR / Electron / JS 应用分析
│   ├── runtime-observation.md            # 插桩、调试器、浏览器/Electron 观测、抓包
│   ├── android-applications.md           # Android APK
│   ├── evidence-workflows.md             # Evidence 分页、对比、验证
│   └── environments.md                   # AgentEnv 智能体环境
└── scripts/
    ├── install_mcp.py                    # 一键注册 MCP 到 WorkBuddy / OpenClaw
    └── rea_doctor.sh                     # 环境体检
```

## 设计原则

这个 Skill 围绕 REA 的证据契约构建，几条不变的原则：

1. **摘要优先** —— 大目标先 `detail: "summary"`，再用 `parent_evidence_id` 翻页，别重复跑分析。
2. **分清观察、推断、未知** —— 每个结论都要标注是哪一类，引用 Evidence ID，保留限制和覆盖范围。
3. **「没找到」≠「不存在」** —— 保留搜索边界，说明覆盖到哪了。
4. **静态分析不假装看到了执行** —— 运行时观测要显式声明，它真的跑了目标。
5. **修连接不要靠重装软件** —— REA 从不安装 Node、Java、Ghidra、JADX 等。

## 相关链接

- [REA 上游仓库](https://github.com/morluto/rea) · [官网](https://rea.tools/)
- [npm 包 `rea-agents`](https://www.npmjs.com/package/rea-agents)
- [上游文档目录](https://github.com/morluto/rea/tree/main/docs)
- [OpenClaw Skills 文档](https://docs.openclaw.ai/zh-CN/tools/skills)

## License

MIT。上游 REA 也是 MIT（[morluto/rea](https://github.com/morluto/rea)）。
