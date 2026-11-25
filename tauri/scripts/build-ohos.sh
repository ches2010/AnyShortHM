#!/usr/bin/env bash
# 使用 HUAWEI command-line-tools (hvigorw / ohpm / hdc + SDK) 构建 Tauri 版鸿蒙 HAP (未签名)。
#
# 构建主体是 hvigor: 读取 AppScope/app.json5 与 build-profile.json5,
# 把前端产物注入 entry 的 resources/rawfile, 最终产出 entry-default.hap。
# Rust (ohos-rs 交叉编译) 与 tauri-cli(ohos) 为可选路径, 由 BUILD_MODE 选择。
#
# 用法:
#   bash scripts/build-ohos.sh
#   BUILD_MODE=hvigor bash scripts/build-ohos.sh
#   OHOS_PROJECT_DIR=/path/to/ohos-app bash scripts/build-ohos.sh
#
# 环境变量:
#   OHOS_HOME          command-line-tools 根目录 (默认自动探测)
#   OHOS_SDK_HOME      SDK 目录 (默认 $OHOS_HOME/sdk/default/openharmony)
#   OHOS_SIGNING_JSON  签名配置 JSON 数组; 不设则输出未签名 HAP
#   OHOS_PROJECT_DIR   壳工程目录 (hvigor 模式, 默认 ../ohos-shell)
#   OUT_DIR            产物目录, 默认 ../dist-tauri
#   BUILD_MODE         auto | hvigor | tauri, 默认 auto
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${OUT_DIR:-$ROOT/../dist-tauri}"
TAURI_TARGET="aarch64-unknown-linux-ohos"

log()  { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

log "0/6 定位 HUAWEI command-line-tools"

OHT=""
for cand in "${OHOS_HOME:-}" "${COMMANDLINE_TOOL_DIR:-}" "${COMMANDLINE_TOOLS_HOME:-}" \
            "$HOME/command-line-tools" "$HOME/CommandLineTools" \
            "/opt/command-line-tools" "/opt/ohos-clt" "/usr/local/command-line-tools"; do
  if [ -n "$cand" ] && [ -d "$cand" ]; then
    if [ -x "$cand/bin/hvigorw" ] || [ -x "$cand/command-line-tools/bin/hvigorw" ]; then
      OHT="$cand"
      break
    fi
  fi
done

if [ -z "$OHT" ]; then
  if has hvigorw; then
    OHT="$(dirname "$(dirname "$(command -v hvigorw)")")"
    echo "未设 OHOS_HOME, 从 PATH 反推: $OHT"
  else
    die "未找到 HUAWEI command-line-tools。
  下载: https://developer.huawei.com/consumer/cn/download/
  解压后: export OHOS_HOME=/path/to/command-line-tools
          export PATH=\$OHOS_HOME/bin:\$PATH
  内含 hvigorw / ohpm / codelinter / hstack / hdc 与 SDK。"
  fi
fi
OHT="$(cd "$OHT" && pwd)"
echo "OHOS_HOME=$OHT"

CLT_BIN=""
for cand in "$OHT/bin" "$OHT/command-line-tools/bin" "$OHT/tools/bin" "$OHT/lib/bin"; do
  if [ -d "$cand" ]; then
    if [ -x "$cand/hvigorw" ] || [ -f "$cand/hvigorw.js" ]; then
      CLT_BIN="$cand"
      break
    fi
  fi
done
if [ -z "$CLT_BIN" ]; then
  die "在 $OHT 下找不到 hvigorw (已尝试 bin, command-line-tools/bin, tools/bin, lib/bin)
  请确认压缩包解压完整, 或把 OHOS_HOME 指向包含 bin/hvigorw 的那层目录。"
fi
export PATH="$CLT_BIN:$PATH"
echo "CLT_BIN=$CLT_BIN"

has ohpm    || die "找不到 ohpm (应在 $CLT_BIN)"
has hvigorw || die "找不到 hvigorw (应在 $CLT_BIN)"
has node    || die "找不到 node: command-line-tools 依赖 Node.js, 请先安装并加入 PATH"

NODE_V="$(node -v)"
echo "node: $NODE_V"
case "$NODE_V" in
  v1[89].*|v2[0-9].*) : ;;
  *) warn "command-line-tools 建议 Node 18+, 当前 $NODE_V 可能不被 hvigor 支持" ;;
esac

if has java; then
  echo "java: $(java -version 2>&1 | head -n1)"
else
  warn "找不到 java: hvigor 打包 HAP 需要 JDK 17+, 请设置 JAVA_HOME"
fi

log "1/6 定位 OHOS SDK"
SDK=""
for cand in "${OHOS_SDK_HOME:-}" "$OHT/sdk/default/openharmony" "$OHT/sdk" \
            "${OHOS_NDK_HOME:-}" "$HOME/Library/OpenHarmony/Sdk" "/opt/ohos-sdk"; do
  if [ -n "$cand" ] && [ -d "$cand" ]; then SDK="$cand"; break; fi
done
if [ -n "$SDK" ] && [ -d "$SDK/ets" ]; then
  export OHOS_SDK_HOME="$SDK"
  echo "OHOS_SDK_HOME=$SDK"
  if [ -d "$SDK/native" ]; then echo "  native     已就绪"; else warn "  native 缺失(原生库构建会失败)"; fi
  if [ -d "$SDK/toolchains" ]; then echo "  toolchains 已就绪"; else warn "  toolchains 缺失"; fi
else
  warn "未自动定位 SDK, 交由 hvigor-config.json5 / local.properties 解析"
fi

log "2/6 前端依赖与构建"
if [ -f package-lock.json ] && [ ! -d node_modules ]; then
  npm ci
else
  npm install
fi
npm run build
if [ ! -f dist/index.html ]; then die "前端构建无产物(dist/index.html 缺失)"; fi
echo "dist 大小: $(du -sh dist | cut -f1)"

BUILD_MODE="${BUILD_MODE:-auto}"
BUILD_MODE_NAME="${BUILD_MODE_NAME:-debug}"
if [ "$BUILD_MODE" = "auto" ]; then
  if has cargo && cargo tauri ohos --help >/dev/null 2>&1; then
    BUILD_MODE="tauri"
  else
    BUILD_MODE="hvigor"
  fi
fi
echo "BUILD_MODE=$BUILD_MODE"

log "3/6 准备鸿蒙工程"
if [ "$BUILD_MODE" = "tauri" ]; then
  OHOS_DIR="src-tauri/gen/ohos"
  if [ -d "$OHOS_DIR" ]; then
    echo "已存在 $OHOS_DIR, 跳过 init"
  else
    cargo tauri ohos init
  fi
else
  OHOS_DIR="${OHOS_PROJECT_DIR:-$ROOT/../ohos-shell}"
  # 相对路径转绝对路径（OHOS_PROJECT_DIR 允许传相对路径）
  if [ -d "$OHOS_DIR" ]; then OHOS_DIR="$(cd "$OHOS_DIR" && pwd)"; fi
  if [ ! -d "$OHOS_DIR" ]; then
    die "找不到鸿蒙壳工程: $OHOS_DIR
  两种做法:
   1) 装 tauri-cli(feat/open-harmony) 并用 BUILD_MODE=tauri, 由 cargo tauri ohos init 生成;
   2) 把仓库根目录的 ArkTS 工程作为壳: 设 OHOS_PROJECT_DIR 为仓库根目录绝对路径 (需含 AppScope, build-profile.json5, entry/)
  壳工程只负责承载 WebView 与 rawfile, 前端产物由本脚本注入。"
  fi
fi
if [ ! -d "$OHOS_DIR/entry/src/main" ]; then
  die "壳工程缺少 entry/src/main, 无法注入前端产物: $OHOS_DIR"
fi

log "3.5/6 注入前端产物到 rawfile"
RAWFILE="$OHOS_DIR/entry/src/main/resources/rawfile"
mkdir -p "$RAWFILE"
find "$RAWFILE" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -R dist/. "$RAWFILE"/
if [ ! -f "$RAWFILE/index.html" ]; then die "前端产物未写入 rawfile"; fi
COUNT=$(find "$RAWFILE" -type f | wc -l | tr -d " ")
echo "已注入 dist -> $RAWFILE ($COUNT 个文件)"

log "4/6 处理签名配置"
BP="$OHOS_DIR/build-profile.json5"
if [ ! -f "$BP" ]; then die "缺少 build-profile.json5: $BP"; fi
if [ -n "${OHOS_SIGNING_JSON:-}" ]; then
  echo "使用 OHOS_SIGNING_JSON 写入签名配置(产出已签名 HAP)"
  python3 - "$BP" "$OHOS_SIGNING_JSON" <<PYEOF
import re, sys
bp, sign = sys.argv[1], sys.argv[2]
s = open(bp, encoding="utf-8").read()
pat = r'"signingConfigs"\s*:\s*\[.*?\]'
if re.search(pat, s, flags=re.S):
    s = re.sub(pat, '"signingConfigs": ' + sign, s, count=1, flags=re.S)
else:
    s = re.sub(r'"(app\s*:\s*\{)', r'\1\n    "signingConfigs": ' + sign + ',', s, count=1)
open(bp, "w", encoding="utf-8").write(s)
print("signingConfigs 已写入")
PYEOF
else
  echo "未设置 OHOS_SIGNING_JSON, 清空签名配置以产出未签名 HAP"
  python3 - "$BP" <<PYEOF
import re, sys
bp = sys.argv[1]
s = open(bp, encoding="utf-8").read()
pat = r'"signingConfigs"\s*:\s*\[.*?\]'
if re.search(pat, s, flags=re.S):
    s = re.sub(pat, '"signingConfigs": []', s, count=1, flags=re.S)
else:
    s = re.sub(r'"(app\s*:\s*\{)', r'\1\n    "signingConfigs": [],', s, count=1)
open(bp, "w", encoding="utf-8").write(s)
print("signingConfigs 已清空")
PYEOF
fi

log "5/6 ohpm 依赖 + hvigorw assembleHap"
( cd "$OHOS_DIR" && ohpm install --all )

HV=( assembleHap --mode module -p product=default -p buildMode="${BUILD_MODE_NAME}" --no-daemon )
if [ -n "${OHOS_MODULE:-}" ]; then
  HV+=( -p "module=${OHOS_MODULE}" )
fi
if [ -n "${OHOS_HVIGOR_EXTRA:-}" ]; then
  for extra in $OHOS_HVIGOR_EXTRA; do HV+=( "$extra" ); done
fi
echo ">> hvigorw ${HV[*]}"
( cd "$OHOS_DIR" && hvigorw "${HV[@]}" )

log "6/6 收集 HAP"
rm -rf "$OUT"
mkdir -p "$OUT"
# hvigor 产物: entry/build/<mode>/outputs/<target>/*.hap (含 entry-default-signed.hap 等)
find "$OHOS_DIR" -type f -name "*.hap" -path "*/outputs/*" \
  -not -path "*/node_modules/*" -exec cp -v {} "$OUT/" \; 2>/dev/null || true
# 兜底: oh_modules 等其它位置的 .hap
if [ -z "$(ls -A "$OUT" 2>/dev/null)" ]; then
  find "$OHOS_DIR" -type f -name "*.hap" -not -path "*/node_modules/*" \
    -exec cp -v {} "$OUT/" \; 2>/dev/null || true
fi
if [ -z "$(ls -A "$OUT" 2>/dev/null)" ]; then
  die "未找到 .hap 产物, 检查 hvigorw 输出与 $OHOS_DIR/entry/build/ 目录"
fi

# arm64-only: 删掉 x86_64 原生库目录(与 ArkTS 版一致的做法)
find "$OUT" -type d -name x86_64 -print -exec rm -rf {} + 2>/dev/null || true

ls -lh "$OUT"
echo "DONE: $OUT"
