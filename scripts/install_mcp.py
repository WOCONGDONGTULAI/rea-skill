#!/usr/bin/env python3
"""把 REA MCP 服务器注册到 WorkBuddy 和/或 OpenClaw。

REA 自带的 `rea setup` 不支持 WorkBuddy 和 OpenClaw，所以这两个平台要手写注册。
本脚本会自动备份现有配置，只增改 REA 那一条，不动其他条目。

用法:
    python3 install_mcp.py                 # 预览（默认，不写文件）
    python3 install_mcp.py --apply         # 实际写入
    python3 install_mcp.py --apply --target workbuddy
    python3 install_mcp.py --apply --target openclaw
    python3 install_mcp.py --apply --use-global   # 用已全局安装的 rea 而非 npx
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SERVER_NAME = "rea"

# REA package.json 的 engines 字段要求
REQUIRED_NODE = (22, 23, 4)
ALT_NODE_MAJORS = (24, 26)


def log(msg=""):
    print(msg)


def detect_node():
    """返回 (路径, 版本元组, 原始版本字符串) 或 (None, None, None)。"""
    exe = shutil.which("node")
    if not exe:
        return None, None, None
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, timeout=10
        ).stdout.strip()
    except Exception:
        return exe, None, None
    ver = out.lstrip("v")
    try:
        parts = tuple(int(x) for x in ver.split(".")[:3])
        while len(parts) < 3:
            parts += (0,)
    except ValueError:
        return exe, None, ver
    return exe, parts, ver


def node_ok(parts):
    """检查是否满足 ^22.23.4 || ^24.22.1 || >=26.12.1"""
    if parts is None:
        return True, "未知版本，跳过检查"
    major, minor, patch = parts
    if major == 22:
        ok = (minor, patch) >= (23, 4)
        return ok, "需要 22.23.4+，当前 %d.%d.%d" % parts
    if major == 24:
        ok = (minor, patch) >= (22, 1)
        return ok, "需要 24.22.1+，当前 %d.%d.%d" % parts
    if major >= 26:
        ok = (major, minor, patch) >= (26, 12, 1)
        return ok, "需要 26.12.1+，当前 %d.%d.%d" % parts
    return False, "当前 %d.%d.%d 不在受支持范围（22.23.4+ / 24.22.1+ / 26.12.1+）" % parts


def find_global_rea():
    """找全局安装的 rea 可执行文件。"""
    exe = shutil.which("rea")
    if exe and os.path.isabs(exe):
        return exe
    return None


def find_npx():
    """找 npx 可执行文件的绝对路径。"""
    exe = shutil.which("npx")
    if exe and os.path.isabs(exe):
        return exe
    return None


def build_server_entry(node_exe, use_global):
    """构造 MCP server 定义。

    注意：`-y` 是 npx 的参数，不是 node 的参数。
    用 node 直接启动时必须指向 REA 的入口脚本，不能带 `-y`。

    优先用 npx 的绝对路径 —— MCP 客户端从桌面 App 启动时可能继承到与终端
    不同的 PATH，终端里跑得通不代表客户端能拉起 npx。
    """
    if use_global:
        rea = find_global_rea()
        if rea:
            # rea 是 npm shim，会自己找 node。直接用它最省事。
            return {"command": rea, "args": ["mcp"]}
    npx = find_npx()
    if npx:
        return {"command": npx, "args": ["-y", "rea-agents@latest", "mcp"]}
    # 找不到 npx 绝对路径时退回相对命令
    return {"command": "npx", "args": ["-y", "rea-agents@latest", "mcp"]}


def backup(path):
    if not path.exists():
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = path.with_suffix(path.suffix + f".bak-{stamp}")
    shutil.copy2(path, bak)
    return bak


def load_json(path):
    if not path.exists():
        return {}
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"  ! {path} 不是合法 JSON（{exc}），已跳过该文件", file=sys.stderr)
        return None


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def apply_workbuddy(entry, apply):
    path = Path.home() / ".workbuddy" / "mcp.json"
    log("--- WorkBuddy ---")
    log(f"  配置路径: {path}")
    data = load_json(path)
    if data is None:
        return False
    servers = data.get("mcpServers")
    if not isinstance(servers, dict):
        servers = {}
    old = servers.get(SERVER_NAME)
    if old == entry:
        log("  已存在且完全一致，无需改动。")
        return False
    servers[SERVER_NAME] = entry
    data["mcpServers"] = servers
    if not apply:
        log(f"  [预览] 将写入 mcpServers.{SERVER_NAME}:")
        log("  " + json.dumps(entry, ensure_ascii=False))
        return True
    bak = backup(path)
    if bak:
        log(f"  已备份: {bak}")
    write_json(path, data)
    log("  已写入。")
    log("  提醒：在连接器管理页右上角的自定义连接器入口，点「信任」才会启用。")
    return True


def apply_openclaw(entry, apply):
    path = Path.home() / ".openclaw" / "openclaw.json"
    log("--- OpenClaw ---")
    log(f"  配置路径: {path}")
    data = load_json(path)
    if data is None:
        return False
    mcp = data.get("mcp")
    if not isinstance(mcp, dict):
        mcp = {}
    servers = mcp.get("servers")
    if not isinstance(servers, dict):
        servers = {}
    old = servers.get(SERVER_NAME)
    if old == entry:
        log("  已存在且完全一致，无需改动。")
        return False
    servers[SERVER_NAME] = entry
    mcp["servers"] = servers
    data["mcp"] = mcp
    if not apply:
        log(f"  [预览] 将写入 mcp.servers.{SERVER_NAME}:")
        log("  " + json.dumps(entry, ensure_ascii=False))
        return True
    bak = backup(path)
    if bak:
        log(f"  已备份: {bak}")
    write_json(path, data)
    log("  已写入。")
    log("  提醒：OpenClaw 用 mcp.servers（不是 mcpServers），并需重启/重连 Gateway。")
    return True


def main():
    ap = argparse.ArgumentParser(description="注册 REA MCP 服务器")
    ap.add_argument("--apply", action="store_true", help="实际写入（默认只预览）")
    ap.add_argument(
        "--target",
        choices=["workbuddy", "openclaw", "both"],
        default="both",
        help="目标平台，默认两个都处理",
    )
    ap.add_argument(
        "--use-global",
        action="store_true",
        help="优先用已全局安装的 rea 命令，而非 npx",
    )
    args = ap.parse_args()

    log("=== REA MCP 注册 ===")
    log(f"模式: {'实际写入' if args.apply else '预览（加 --apply 生效）'}")
    log()

    node_exe, parts, raw = detect_node()
    if node_exe:
        log(f"Node: {node_exe} (v{raw})")
        ok, why = node_ok(parts)
        if not ok:
            log(f"  ! 版本低于 REA 声明的要求：{why}")
            log("  ! npm 会打印 EBADENGINE 警告，但实测仍可运行（REA 6.8.0 在 22.22.2 下正常启动）。")
            log("  ! 若后续出现异常，升级 Node 到 22.23.4+ 可消除这个不确定性。")
            log()
    else:
        log("! 没找到 node。请先安装 Node.js。")
        log()

    entry = build_server_entry(node_exe, args.use_global)
    log("MCP server 定义:")
    log("  " + json.dumps(entry, ensure_ascii=False))
    log()

    changed = False
    if args.target in ("workbuddy", "both"):
        changed |= apply_workbuddy(entry, args.apply)
        log()
    if args.target in ("openclaw", "both"):
        changed |= apply_openclaw(entry, args.apply)
        log()

    if not args.apply:
        log("以上为预览。确认无误后加 --apply 执行。")
    elif changed:
        log("完成。请重启对应客户端使 MCP 生效。")
    else:
        log("无需改动。")


if __name__ == "__main__":
    main()
