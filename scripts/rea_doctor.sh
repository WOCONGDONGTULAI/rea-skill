#!/usr/bin/env bash
# REA 环境体检 —— 检查 Node 版本、REA 安装、MCP 注册、provider 可用性。
#
# 用法:
#   bash rea_doctor.sh              # 全量检查
#   bash rea_doctor.sh --provider ghidra   # 附带 provider 检查
#
# 纯读操作，不修改任何配置。

set -uo pipefail

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
DIM=$'\033[0;2m'
NC=$'\033[0m'

pass() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$NC" "$1"; }
fail() { printf '%s✗%s %s\n' "$RED" "$NC" "$1"; }
info() { printf '%s  %s%s\n' "$DIM" "$1" "$NC"; }

echo "=== REA 环境体检 ==="
echo

# --- Node 版本 ---
echo "[Node]"
if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version | sed 's/^v//')
  info "路径: $(command -v node)"
  info "版本: $NODE_VER"
  # REA 要求 ^22.23.4 || ^24.22.1 || >=26.12.1
  MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  MINOR=$(echo "$NODE_VER" | cut -d. -f2)
  PATCH=$(echo "$NODE_VER" | cut -d. -f3)
  OK=0
  if [ "$MAJOR" = "22" ] && [ "$MINOR" -gt 23 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" = "22" ] && [ "$MINOR" = "23" ] && [ "$PATCH" -ge 4 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" = "24" ] && [ "$MINOR" -gt 22 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" = "24" ] && [ "$MINOR" = "22" ] && [ "$PATCH" -ge 1 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" -gt 26 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" = "26" ] && [ "$MINOR" -gt 12 ] 2>/dev/null; then OK=1; fi
  if [ "$MAJOR" = "26" ] && [ "$MINOR" = "12" ] && [ "$PATCH" -ge 1 ] 2>/dev/null; then OK=1; fi
  if [ "$OK" = "1" ]; then
    pass "Node 版本满足 REA 要求"
  else
    fail "Node 版本不满足要求（需要 22.23.4+ / 24.22.1+ / 26.12.1+），npx rea-agents 会失败"
  fi
else
  fail "未找到 node —— REA 无法启动"
fi
echo

# --- REA 安装 ---
echo "[REA 安装]"
if command -v rea >/dev/null 2>&1; then
  pass "已全局安装: $(command -v rea)"
  info "版本: $(rea --version 2>/dev/null | head -1)"
else
  warn "未找到全局 rea 命令（可用 npx -y rea-agents@latest 兜底）"
fi
if command -v npm >/dev/null 2>&1; then
  info "npm: $(npm --version 2>/dev/null) @ $(command -v npm)"
fi
echo

# --- MCP 注册 ---
echo "[MCP 注册]"
WB_CFG="$HOME/.workbuddy/mcp.json"
if [ -f "$WB_CFG" ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c "
import json,sys
d=json.load(open('$WB_CFG'))
sys.exit(0 if 'rea' in d.get('mcpServers',{}) else 1)
" 2>/dev/null; then
    pass "WorkBuddy 已注册 rea ($WB_CFG)"
  else
    warn "WorkBuddy 配置存在但没有 rea 条目 ($WB_CFG)"
  fi
else
  info "没有 WorkBuddy MCP 配置 ($WB_CFG)"
fi

OC_CFG="$HOME/.openclaw/openclaw.json"
if [ -f "$OC_CFG" ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c "
import json,sys
d=json.load(open('$OC_CFG'))
sys.exit(0 if 'rea' in d.get('mcp',{}).get('servers',{}) else 1)
" 2>/dev/null; then
    pass "OpenClaw 已注册 rea ($OC_CFG)"
  else
    warn "OpenClaw 配置存在但没有 rea 条目（注意用 mcp.servers 键）($OC_CFG)"
  fi
else
  info "没有 OpenClaw 配置 ($OC_CFG)"
fi
echo

# --- REA 自身 doctor ---
echo "[REA doctor]"
if command -v rea >/dev/null 2>&1; then
  if rea doctor --json >/tmp/rea-doctor-$$.json 2>/dev/null; then
    pass "rea doctor 执行完成"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import json
try:
    d=json.load(open('/tmp/rea-doctor-$$.json'))
    h=d.get('healthy')
    if h is None: h=d.get('result',{}).get('healthy')
    print('  healthy =', h)
    for k in ('providerInspections','checks'):
        v=d.get(k) or d.get('result',{}).get(k)
        if isinstance(v,dict):
            for name,info in v.items():
                st=info.get('status') if isinstance(info,dict) else None
                if st and st not in ('ok','healthy','pass'):
                    print(f'  · {name}: {st}')
except Exception as e:
    pass
" 2>/dev/null
    fi
  else
    warn "rea doctor 返回非零（查看 rea doctor --json 的输出）"
  fi
  rm -f /tmp/rea-doctor-$$.json
else
  info "跳过（需要全局 rea 命令）"
fi
echo

# --- provider ---
if [ "${1:-}" = "--provider" ] && [ -n "${2:-}" ]; then
  echo "[provider: $2]"
  if command -v rea >/dev/null 2>&1; then
    if rea doctor --provider "$2" --json >/tmp/rea-prov-$$.json 2>/dev/null; then
      pass "provider '$2' 检查完成（详见 JSON 输出）"
    else
      fail "provider '$2' 不可用或检查失败"
      cat /tmp/rea-prov-$$.json 2>/dev/null | head -40
    fi
    rm -f /tmp/rea-prov-$$.json
  else
    info "跳过（需要全局 rea 命令）"
  fi
  echo
fi

echo "=== 完成 ==="
