#!/usr/bin/env bash
# 构建 Tauri 版鸿蒙 HAP（未签名）。可在本地直接跑，也可由 CI 调用。
# 依赖：node20+ / npm / rust + aarch64-unknown-linux-ohos target / tauri-cli(feat/open-harmony) / OHOS SDK+NDK / hvigorw
set -euo pipefail

cd "$(dirname "$0")/.."                 # → tauri/
ROOT="$(pwd)"
OUT="${OUT_DIR:-$ROOT/../dist-tauri}"
TAURI_TARGET="${TAURI_TARGET:-aarch64-unknown-linux-ohos}"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

log "0/6 环境检查"
for c in node npm cargo rustc; do has "$c" || die "缺少命令: $c"; done
node -v
cargo -V
if ! rustup target list --installed 2>/dev/null | grep -qx "$TAURI_TARGET"; then
  die "缺少 Rust target: $TAURI_TARGET
  → rustup target add $TAURI_TARGET
  → 若提示该 target 不可用（tier 3），改用 ohos-rs 提供的工具链：https://ohos-rs.dev"
fi
if ! has hvigorw; then warn "未找到 hvigorw：HAP 打包阶段可能失败（需 command-line-tools 并在 PATH）"; fi
if ! has ohpm;    then warn "未找到 ohpm：若 gen/ohos 未装依赖会失败"; fi

log "1/6 定位 OHOS NDK"
NDK=""
for cand in "${OHOS_NDK_HOME:-}" "${OHOS_SDK_HOME:-}/native" \
            "$HOME/command-line-tools/sdk/default/openharmony/native" \
            "/opt/ohos-sdk/native"; do
  if [ -n "$cand" ] && [ -d "$cand" ]; then NDK="$cand"; break; fi
done
if [ -z "$NDK" ]; then
  die "未找到 OHOS NDK，请设置 OHOS_NDK_HOME 指向含 llvm/bin/clang 的 native 目录"
fi
echo "NDK=$NDK"

CLANG="$NDK/llvm/bin/clang"
if [ ! -x "$CLANG" ]; then CLANG="$NDK/llvm/bin/aarch64-linux-ohos-clang"; fi
if [ ! -x "$CLANG" ]; then die "NDK 中未找到 clang：$NDK/llvm/bin/"; fi
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$CLANG"
if [ -x "$NDK/llvm/bin/llvm-ar" ]; then
  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR="$NDK/llvm/bin/llvm-ar"
fi
echo "linker=$CLANG"

log "2/6 前端依赖与构建"
if [ -f package-lock.json ] && [ ! -d node_modules ]; then
  npm ci
else
  npm install
fi
npm run build
if [ ! -f dist/index.html ]; then die "前端构建无产物（dist/index.html 缺失）"; fi

log "3/6 tauri ohos init（幂等）"
if ! cargo tauri --version >/dev/null 2>&1; then
  die "未安装 tauri-cli(OHOS 分支)：
  cargo install --git https://github.com/tauri-apps/tauri --branch feat/open-harmony tauri-cli"
fi
if ! cargo tauri ohos --help >/dev/null 2>&1; then
  die "当前 tauri-cli 不支持 ohos 子命令，需 feat/open-harmony 分支"
fi
if [ -d src-tauri/gen/ohos ]; then
  echo "已存在 src-tauri/gen/ohos，跳过 init"
else
  cargo tauri ohos init
fi

log "4/6 清空本机签名配置（产出未签名 HAP）"
BP="src-tauri/gen/ohos/build-profile.json5"
if [ -f "$BP" ] && grep -q 'signingConfigs' "$BP"; then
  python3 - "$BP" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s2 = re.sub(r'"signingConfigs"\s*:\s*\[[^\]]*\]', '"signingConfigs": []', s, flags=re.S)
if s2 != s:
    open(p, 'w', encoding='utf-8').write(s2)
    print('signingConfigs cleared')
else:
    print('signingConfigs already empty')
PYEOF
fi

log "5/6 构建"
if cargo tauri ohos build --help >/dev/null 2>&1; then
  cargo tauri ohos build
else
  warn "tauri-cli 无 ohos build 子命令，回退手工链路"
  cargo build --manifest-path src-tauri/Cargo.toml --target "$TAURI_TARGET" --release
  ( cd src-tauri/gen/ohos && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon )
fi

log "6/6 收集 HAP"
rm -rf "$OUT"
mkdir -p "$OUT"
find src-tauri/gen/ohos -type f -name '*.hap' -exec cp -v {} "$OUT/" \; 2>/dev/null || true
if [ -z "$(ls -A "$OUT" 2>/dev/null)" ]; then
  find . -type f -name '*.hap' -not -path './node_modules/*' -exec cp -v {} "$OUT/" \; 2>/dev/null || true
fi
if [ -z "$(ls -A "$OUT" 2>/dev/null)" ]; then
  die "未找到 .hap 产物，请检查 gen/ohos 的构建输出"
fi
ls -lh "$OUT"
echo "DONE: $OUT"
