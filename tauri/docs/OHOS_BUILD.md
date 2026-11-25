# 鸿蒙（HarmonyOS NEXT）构建指南

Tauri 官方尚未合并鸿蒙支持，需使用官方 `feat/open-harmony` 分支 + `ohos-rs` 工具链。
以下流程基于官方分支与社区真机验证整理（Mate 80 / API 12+）。

## 1. 环境

| 组件 | 说明 |
|---|---|
| DevEco Studio | HarmonyOS NEXT 版本（含 SDK、hvigor、hdc） |
| command-line-tools | 与 DevEco 同版本（提供 hvigorw / ohpm / hdc） |
| Rust | 1.77+，`rustup target add aarch64-unknown-linux-ohos` |
| ohos-rs | `cargo install ohos-rs`（或按其 README 安装） |
| tauri-cli（鸿蒙分支） | `cargo install --git https://github.com/tauri-apps/tauri --branch feat/open-harmony tauri-cli` |
| Node.js | 20+（前端构建） |

环境变量（示例，按本机路径调整）：

```bash
export OHOS_NDK_HOME=$HOME/command-line-tools/sdk/default/openharmony
export PATH=$OHOS_NDK_HOME/toolchains:$PATH
```

## 2. 启用 open-harmony 依赖

编辑 `src-tauri/Cargo.toml`，取消注释：

```toml
[patch.crates-io]
tauri = { git = "https://github.com/tauri-apps/tauri", branch = "feat/open-harmony" }
tauri-build = { git = "https://github.com/tauri-apps/tauri", branch = "feat/open-harmony" }
wry = { git = "https://github.com/tauri-apps/wry", branch = "feat/open-harmony" }
tao = { git = "https://github.com/tauri-apps/tao", branch = "feat/open-harmony" }
```

> 分支名/仓库以官方仓库当前状态为准（该分支基于 v2.11.x 维护，尚未合入主线）。

## 3. 生成 ohos 平台工程

```bash
cd tauri
npm install
cargo tauri ohos init      # 生成 ohos/ 目录（ArkTS 壳 + XComponent 承载 WebView）
```

生成后 `tauri.conf.json` 的 `identifier`/`productName` 会写入 ohos 壳的 `module.json5`。

## 4. 构建

```bash
# 1) 前端
npm run build

# 2) Rust（arm64-v8a）
cargo build --release --target aarch64-unknown-linux-ohos

# 3) 打包 HAP
cd ohos
hvigorw assembleHap --mode module -p product=default --no-daemon
```

产物：`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`

签名（调试）：DevEco Studio → Project Structure → Signing Configs 自动签名，
或使用 `hap-sign-tool` + 调试证书。

安装：

```bash
hdc install entry-default-signed.hap
```

## 5. 已知坑

1. **CORS**：WebView 内直接 `fetch('https://anyshort.net/v1')` 会被跨域拦截；
   本项目已改用 `tauri-plugin-http`（Rust 侧请求），capabilities 里配置了允许域。
2. **视频播放**：ArkWeb 的 `<video>` 走系统解码，支持 H.264/AAC 的 mp4 直链；
   若站点某剧集返回 H.265/特殊封装，需回退到 IJK（见下）。
3. **全屏**：ArkWeb 对 `requestFullscreen` 支持有限，必要时改用 ArkTS 侧
   `window.setPreferredOrientation(LANDSCAPE)` + 系统栏隐藏。
4. **登录**：Google OAuth 需外部浏览器 + 回跳；Tauri 里通常用
   `tauri-plugin-opener` 打开系统浏览器，再用 deep link 回调。
5. **HAP 体积**：Tauri 壳 + Rust 产物约 8~12MB（远小于 ArkTS+FFmpeg 的 27MB）。

## 6. 可选：接入 IJK 内核

Flutter/Tauri 生态均无现成 IJK 鸿蒙插件，需自写：

1. 在 `ohos` 壳的 ArkTS 侧引入 `@ohos/ijkplayer`（与旧版 `PlayerPage.ets` 逻辑一致）
2. 暴露 `@ohos.arkui...` Channel（Tauri 的 ohos 插件机制 / ArkWeb 的 `registerJavaScriptProxy`）
3. 前端 `Player.vue` 在检测到 H.265 或播放失败时，改为调用原生播放器通道

当前实现默认用 `<video>`，IJK 作为可选增强。

---

## 7. GitHub Actions（self-hosted Runner）

Tauri 的鸿蒙 HAP 需要 OHOS SDK/NDK + Rust `aarch64-unknown-linux-ohos` target + tauri-cli 鸿蒙分支，
标准 `ubuntu-latest` 上没有这些，所以流水线跑在**自建 Runner** 上。

工作流：`.github/workflows/build-tauri-hap.yml`（手动触发 `workflow_dispatch`）。

### 7.1 一次性准备

1. **注册 Runner**：仓库 Settings → Actions → Runners → New self-hosted runner，按提示在构建机安装。
   额外标签填 `ohos`（与工作流输入 `runner_label` 对应）。
2. **构建机安装依赖**：Node 20、npm、Rust、OHOS command-line-tools（`hvigorw` / `ohpm` 在 PATH）、
   JDK 17、`rustup target add aarch64-unknown-linux-ohos`、
   `cargo install --git https://github.com/tauri-apps/tauri --branch feat/open-harmony tauri-cli`。
   预装 tauri-cli 可省掉每次 20~30 分钟的编译。
3. **开启构建**：Settings → Secrets and variables → Actions → Variables，
   新建 `OHOS_RUNNER_ENABLED` = `true`。未设置时只跑预检，跳过 HAP 构建。
4. **NDK**：确保 Runner 环境变量 `OHOS_NDK_HOME` 指向
   `command-line-tools/sdk/default/openharmony/native`。

### 7.2 流水线结构

| Job | Runner | 作用 |
|---|---|---|
| `preflight` | 云 `ubuntu-latest` | `bash -n` 校验脚本、`vue-tsc` 类型检查、前端构建，产物 `tauri-dist` |
| `build` | self-hosted（`ohos`） | 下载前端产物 → 工具链自检 → `tauri/scripts/build-ohos.sh` → 上传 `hap-tauri-unsigned` |
| `release` | 云 `ubuntu-latest` | 可选，`publish_release=true` 时刷新 tag `v1.0.0-beta.1-tauri` 的 Release |

构建逻辑集中在 `tauri/scripts/build-ohos.sh`，本地与 CI 共用同一份，避免两套命令漂移：
定位 NDK → 前端构建 → `cargo tauri ohos init`（幂等）→ 清空签名配置 → 构建 → 收集 HAP。

### 7.3 手动触发

```bash
gh workflow run build-tauri-hap.yml -f runner_label=ohos -f publish_release=true
gh run watch
```

或网页 Actions → Build Tauri HAP (OHOS) → Run workflow。

### 7.4 常见失败

| 现象 | 原因 / 处理 |
|---|---|
| `No runner matching the specified labels` | Runner 未注册或标签不是 `ohos`；改 `runner_label` 输入 |
| `缺少 Rust target: aarch64-unknown-linux-ohos` | 该 target 在部分版本是 tier 3，需 nightly + `-Z build-std`，或改用 ohos-rs 工具链 |
| `未找到 OHOS NDK` | 在 Runner 上设置 `OHOS_NDK_HOME`（指向含 `llvm/bin/clang` 的 native 目录） |
| `当前 tauri-cli 不支持 ohos 子命令` | 装成了稳定版 tauri-cli，需 `feat/open-harmony` 分支 |
| HAP 未产出 | 看 `gen/ohos` 下 `hvigorw` 日志；多为签名配置或 ohpm 依赖缺失 |
