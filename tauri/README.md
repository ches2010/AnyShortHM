# AnyShort Tauri（重构版）

AnyShort 鸿蒙客户端的 **Tauri 2 + Vue 3** 重构实现。

- 前端：Vue 3 + TypeScript + Vite（无 UI 框架，手写深色主题）
- 后端：Rust（Tauri 2），HTTP 走 `tauri-plugin-http`（在 Rust 侧发请求，规避 WebView CORS）
- 播放：WebView 内 HTML5 `<video>`（ArkWeb / Chromium 自带 H.264·AAC 解码）
- 目标平台：HarmonyOS NEXT（arm64-v8a，测试机 Mate 80）+ 桌面（开发调试）

## 功能

- 首页：热门推荐横滑、分类 Rail、查看全部
- 搜索：防抖搜索 + 结果网格 + 分页
- 详情：海报/简介/标签/剧集网格、收藏、评分
- 播放：清晰度切换（保留进度）、倍速、±10 秒、上/下集、进度拖动、静音、全屏、
  字幕（WEBVTT 叠加）、看 10 秒上报进度、本地续播
- 我的：观看历史、收藏（需登录）
- 中英双语切换

## 开发

```bash
npm install
npm run dev            # 浏览器调试（API 需可跨域，或用桌面 Tauri 调试）
npm run tauri dev      # 桌面运行（推荐，走 Rust HTTP 无 CORS 问题）
```

## 构建

- 桌面：`npm run tauri build`
- 鸿蒙 HAP：见 [docs/OHOS_BUILD.md](docs/OHOS_BUILD.md)

## 与旧 ArkTS 工程的关系

仓库根目录的 `entry/`、`AppScope/` 是早期的 ArkTS + ArkUI 原生实现（含 IJK 内核），
`tauri/` 是本次 Tauri 重构版本。两套工程独立构建：

| 版本 | 技术栈 | 播放内核 | 构建方式 |
|---|---|---|---|
| 旧版（根目录） | ArkTS + ArkUI | @ohos/ijkplayer（FFmpeg） | `build-hap.yml`（harmonyos-ci 镜像） |
| 新版（tauri/） | Tauri 2 + Vue 3 | WebView `<video>`（可选接 IJK） | `build-tauri-web.yml`（前端验证）+ 本地 flutter... 见文档 |

> 新版鸿蒙 HAP 需要专用工具链（tauri-cli open-harmony 分支 + ohos-rs + Rust ohos target），
> 当前 CI 只做前端构建验证，HAP 由本地/专用 Runner 构建。

## 目录

```
tauri/
  index.html
  src/                  # Vue 前端
    api.ts              # /v1 API 客户端（Rust HTTP）
    store.ts i18n.ts router.ts utils.ts
    views/              # Home Search Detail Player Library Login
    components/PosterCard.vue
  src-tauri/            # Rust 侧
    Cargo.toml          # 含 open-harmony patch 说明
    tauri.conf.json
    capabilities/default.json
    src/lib.rs          # 插件注册 + 命令
  docs/OHOS_BUILD.md
```
