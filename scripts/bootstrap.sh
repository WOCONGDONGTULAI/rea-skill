#!/usr/bin/env bash
# REA 逆向工程技能 —— 新机 / 换机一键安装
#
# 做完三件事：装技能本体 → 注册 MCP → 跑环境体检。
# 可重复执行：已安装的会原地 git pull 更新，不会重复克隆。
#
# 用法：
#   bash scripts/bootstrap.sh                 # 自动判断（WorkBuddy 必装，OpenClaw 存在才装）
#   bash scripts/bootstrap.sh --target both   # 两个平台都装
#   bash scripts/bootstrap.sh --dry-run       # 只看会做什么，不落盘
#   bash scripts/bootstrap.sh --no-mcp        # 只装技能，不碰 MCP 配置
#
# 刚从别的机器过来、本机还没有任何东西时，可以直接：
#   curl -fsSL https://raw.githubusercontent.com/WOCONGDONGTULAI/rea-skill/main/scripts/bootstrap.sh | bash
# （raw 可能有 CDN 缓存；拿不到最新就用 git clone 的方式）

set -uo pipefail

REPO_URL="${REA_SKILL_REPO:-https://github.com/WOCONGDONGTULAI/rea-skill.git}"
SKILL_NAME="rea-reverse-engineering"

TARGET="auto"
DRY=0
DO_MCP=1

log()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }

usage() {
    sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --target)  TARGET="${2:-}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --no-mcp)  DO_MCP=0; shift ;;
        -h|--help) usage 0 ;;
        *) bad "未知参数: $1"; usage 1 ;;
    esac
done

case "$TARGET" in
    auto|workbuddy|openclaw|both) ;;
    *) bad "--target 只能是 auto / workbuddy / openclaw / both"; exit 1 ;;
esac

[ "$DRY" = "1" ] && log "（dry-run：只打印，不写文件）"

# ---------- 1. 基本依赖 ----------
step "1/4 检查依赖"

HAVE_GIT=0
if command -v git >/dev/null 2>&1; then HAVE_GIT=1; ok "git $(git --version | awk '{print $3}')"; else warn "没有 git，将改用 tarball 下载（后续无法 git pull 更新）"; fi

PY=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -n "$PY" ]; then ok "$PY $($PY --version 2>&1 | awk '{print $2}')"; else bad "没有 python3 —— MCP 注册脚本需要它，请先安装"; fi

if command -v npx >/dev/null 2>&1; then
    ok "npx 在 PATH 中"
else
    warn "PATH 里没有 npx —— MCP 注册会退回相对命令，客户端启动时可能找不到"
fi

if command -v node >/dev/null 2>&1; then
    NODE_V="$(node --version 2>/dev/null | tr -d v)"
    ok "node v$NODE_V"
    # REA 声明 ^22.23.4 || ^24.22.1 || >=26.12.1
    MAJ="${NODE_V%%.*}"
    REST="${NODE_V#*.}"
    MIN="${REST%%.*}"
    if [ "$MAJ" = "22" ] && [ "$MIN" -lt 23 ]; then
        warn "低于 REA 声明的 22.23.4 —— 只会有 EBADENGINE 警告，实测仍可运行"
    fi
else
    bad "没有 node —— REA 跑不起来，请先装 Node.js"
fi

# ---------- 2. 决定装到哪 ----------
step "2/4 目标平台"

WB_DIR="$HOME/.workbuddy/skills/$SKILL_NAME"
OC_DIR="$HOME/.openclaw/skills/$SKILL_NAME"

want_wb=0
want_oc=0
case "$TARGET" in
    workbuddy) want_wb=1 ;;
    openclaw)  want_oc=1 ;;
    both)      want_wb=1; want_oc=1 ;;
    auto)
        want_wb=1
        if [ -d "$HOME/.openclaw" ]; then
            want_oc=1
        else
            warn "本机没有 ~/.openclaw，跳过 OpenClaw（要装可加 --target both）"
        fi
        ;;
esac

[ "$want_wb" = "1" ] && log "  WorkBuddy → $WB_DIR"
[ "$want_oc" = "1" ] && log "  OpenClaw  → $OC_DIR"
if [ "$want_wb" = "0" ] && [ "$want_oc" = "0" ]; then bad "没有选中任何平台"; exit 1; fi

# ---------- 3. 安装 / 更新技能 ----------
# 关键：脚本自己就在技能目录里时，不要去复制或删除自身
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd || echo "")"

fetch_to() {
    # fetch_to <目标目录>  —— 已存在则更新，否则全新获取
    local dir="$1"
    local parent
    parent="$(dirname "$dir")"
    mkdir -p "$parent" || return 1

    if [ -d "$dir/.git" ]; then
        if [ "$HAVE_GIT" = "1" ]; then
            if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then ok "已更新（git pull）"; else warn "git pull 失败，保留现有版本继续"; fi
        else
            warn "目录存在但不是 git 仓库，且没有 git，跳过更新"
        fi
        return 0
    fi

    if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
        warn "$dir 已存在且不是 git 仓库 —— 不覆盖，请先自行移走"
        return 0
    fi

    if [ "$HAVE_GIT" = "1" ]; then
        if git clone --depth 1 --quiet "$REPO_URL" "$dir" 2>/dev/null; then ok "已克隆"; return 0; fi
        warn "git clone 失败，改用 tarball"
    fi

    # tarball 兜底
    local tmp
    tmp="$(mktemp -d 2>/dev/null || echo "/tmp/rea-skill-$$")"
    mkdir -p "$tmp"
    local url="https://codeload.github.com/${REPO_URL#https://github.com/}"
    url="${url%.git}/tar.gz/refs/heads/main"
    if curl -fsSL "$url" -o "$tmp/s.tar.gz" 2>/dev/null && tar xzf "$tmp/s.tar.gz" -C "$tmp" 2>/dev/null; then
        mkdir -p "$dir"
        # shellcheck disable=SC2046
        ( cp -R "$tmp"/rea-skill-main/. "$dir"/ ) 2>/dev/null && ok "已下载解压" || { bad "解压失败"; rm -rf "$tmp"; return 1; }
        rm -rf "$tmp"
        return 0
    fi
    bad "获取失败：需要能访问 GitHub"
    rm -rf "$tmp"
    return 1
}

# ---------- 4. MCP 注册 ----------
register_mcp() {
    local dir="$1" tg="$2"
    local script="$dir/scripts/install_mcp.py"
    if [ ! -f "$script" ]; then bad "找不到 $script"; return 1; fi
    if [ -z "$PY" ]; then bad "没有 python3，跳过注册"; return 1; fi
    if [ "$DRY" = "1" ]; then log "  [dry-run] 将执行: $PY $script --apply --target $tg"; return 0; fi
    "$PY" "$script" --apply --target "$tg"
}

INSTALLED=""
for pair in "$want_wb:$WB_DIR:workbuddy:WorkBuddy" "$want_oc:$OC_DIR:openclaw:OpenClaw"; do
    [ -z "$pair" ] && continue
    w="${pair%%:*}"; rest="${pair#*:}"
    dir="${rest%%:*}"; rest2="${rest#*:}"
    tg="${rest2%%:*}"; label="${rest2#*:}"
    [ "$w" = "1" ] || continue

    step "3/4 安装技能 → $label"
    if [ -n "$SELF_DIR" ] && [ "$SELF_DIR" = "$dir" ]; then
        ok "当前就运行在这个目录，跳过克隆"
    else
        if [ "$DRY" = "1" ]; then log "  [dry-run] 将安装到 $dir"; else fetch_to "$dir" || continue; fi
    fi
    INSTALLED="$INSTALLED $tg"
done

if [ "$DO_MCP" = "1" ]; then
    step "4/4 注册 MCP"
    for tg in $INSTALLED; do
        case "$tg" in
            workbuddy) register_mcp "$WB_DIR" workbuddy ;;
            openclaw)  register_mcp "$OC_DIR" openclaw ;;
        esac
    done
else
    step "4/4 注册 MCP（已跳过）"
    log "  之后可手动执行：$PY <技能目录>/scripts/install_mcp.py --apply"
fi

# ---------- 收尾 ----------
step "完成"
log "接下来必须手动做两件事，否则技能不会生效："
log "  1. WorkBuddy：完全退出并重启（Cmd+Q，不是关窗口）→「连接器」→「+ 添加 MCP」"
log "     在「MCP 服务管理」里找到 rea → 点「信任」，圆点变绿才算启用"
log "  2. 新开会话 —— 技能在会话启动时加载，中途装的不生效"
log ""
log "环境体检：bash <技能目录>/scripts/rea_doctor.sh"
