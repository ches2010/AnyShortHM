# AnyShortHM — AnyShort 鸿蒙原生客户端

将 https://anyshort.net/zh-Hans/ （AnyShort 短剧字幕站）移植为 HarmonyOS / OpenHarmony
原生应用（ArkTS + ArkUI，Stage 模型，API 12 / HarmonyOS NEXT）。

移植方式为 **ArkUI 原生重写**（非 WebView 壳）：直接调用站点公开的 `/v1` REST API，
播放内核使用 **IJK（@ohos/ijkplayer，FFmpeg 软解）** 播放 CDN 直链 mp4。

## 仓库结构（两套实现）

| 目录 | 说明 | 构建 |
|---|---|---|
| `entry/` `AppScope/` `hvigor/` | ArkTS + ArkUI 原生实现（IJK 内核） | `.github/workflows/build-hap.yml` → HAP + Beta Release |
| `tauri/` | **Tauri 2 + Vue 3 重构版** | `.github/workflows/build-tauri-web.yml` → 前端构建验证（云 Runner） |
|  | 同上，鸿蒙 HAP | `.github/workflows/build-tauri-hap.yml` → Tauri HAP（self-hosted Runner） |

Tauri 版鸿蒙 HAP 需要专用工具链（tauri-cli feat/open-harmony + ohos-rs + Rust ohos target），
步骤见 [tauri/docs/OHOS_BUILD.md](tauri/docs/OHOS_BUILD.md)。

## 功能

- 首页：Banner 轮播、热门推荐（spotlight）、分类 Rail 横滑列表、下拉刷新
- 搜索：防抖搜索 + 搜索建议 + 结果网格 + 分页加载
- 详情：海报/简介/标签/评分/剧集网格（分页）、收藏、五星评分
- 播放：**IJK 内核**（FFmpeg，兼容性强）、清晰度切换（保持进度）、倍速、±10 秒、
  上/下集、选集面板、进度条拖动、静音、全屏按视频方向自适应（竖屏沉浸/横屏旋转）、
  观看 10 秒后上报进度、本地续播（seek）
- 我的：观看历史（设备维度）、我的收藏（需登录）
- 登录：Google OAuth，经 ArkWeb 承载 `/v1/auth/google/start`，回跳后重新握手
- 多语言：简体中文 / English（右上角浮球切换）

## 目录结构

```
AnyShortHM/
  AppScope/app.json5
  build-profile.json5          # 兼容 API 12 (5.0.0(12))
  entry/
    src/main/module.json5      # requestPermissions: INTERNET
    src/main/ets/
      entryability/EntryAbility.ets
      model/Models.ets         # /v1 数据模型
      net/ApiClient.ets        # HTTP + 会话握手 + 401 自动重握手
      net/ApiService.ets       # 全部业务端点
      store/AppStore.ets       # preferences（device_id/token/语言/本地进度）
      i18n/L10n.ets            # zh-Hans / en 词典
      ui/Theme.ets, ui/Utils.ets
      components/PosterCard.ets
      pages/Index.ets          # 底部 Tabs：首页/搜索/我的
      pages/HomeView.ets
      pages/SearchView.ets
      pages/LibraryView.ets
      pages/DetailPage.ets
      pages/PlayerPage.ets     # AVPlayer + XComponent
      pages/BrowseListPage.ets # “查看全部”
      pages/LoginWebPage.ets   # Google OAuth（ArkWeb）
```

## 构建运行

### 方式一：GitHub Actions（已跑通）

仓库内置 `.github/workflows/build-hap.yml`，push / PR / 手动触发均可构建，
**无需本地 DevEco Studio**。使用 [harmonyos-ci](https://github.com/DaLongZhuaZi/harmonyos-ci)
工具链镜像（内嵌 command-line-tools + HarmonyOS SDK）：

- 触发：push 到 `main`、PR、或在 Actions 页面 `Run workflow`
- 产物：Actions run 页面底部的 `hap-unsigned` artifact（解压得 `entry-default-unsigned.hap`）
- artifact 保留 14 天

> CI 产出为**未签名** HAP：安装前需用 DevEco Studio 的自动签名或 `hap-sign-tool` 重新签名。
> `strip_signing.py` 会在构建前剥离本机签名配置（本仓库当前无签名配置，脚本自动跳过）。

### 方式二：本地 DevEco Studio

1. DevEco Studio 5.0+ 打开工程根目录（首次会自动同步 hvigor）。
2. `File > Settings > Signing Configs` 登录华为账号并勾选自动签名（调试）。
3. 选择模拟器或真机，Run 即可安装 entry 的 HAP。
4. 命令行构建 HAP：
   ```
   hvigorw assembleHap --mode module -p product=default
   # 产物：entry/build/default/outputs/default/entry-default-signed.hap
   ```
5. 手动安装：`hdc install entry-default-signed.hap`

## 自动发布 Release

工作流在 `main` 分支构建成功后，会自动创建/更新 **Beta 1.0.0** 预发布：

| 项 | 值 |
|---|---|
| Tag | `v1.0.0-beta.1` |
| Release 名称 | `Beta 1.0.0 (v1.0.0-beta.1)` |
| 标记 | prerelease（预发布） |
| 附件 | `entry-default-unsigned.hap`（未签名） |

- 触发条件：`push` 到 `main`、或手动 `workflow_dispatch`
- 重复触发会**更新同一个 Release**（同名 tag 复用，不产生堆积）
- PR 只构建、不发布

**升级版本号**需改两处：
1. `.github/workflows/build-hap.yml` 的 `env.RELEASE_TAG` / `env.RELEASE_NAME`
2. `AppScope/app.json5` 的 `versionName`（如 `1.1.0-beta.1`）

## 配置

- API 地址：`ets/net/ApiClient.ets` 中 `API_BASE`（默认 https://anyshort.net/v1）。
- 视频流地址由服务端下发（带过期时间），应用不做任何破解/绕过。

## 已知边界

- Google 登录依赖站点的 OAuth 流程，需真机可访问 accounts.google.com。
- 字幕接口当前多数剧集返回空数组，字幕渲染已实现但可能无数据。
- 金币解锁（gating=free_n 之后的集数）仅提示“需解锁”，未实现内购。
- 工程已通过 GitHub Actions（HarmonyOS API 26 工具链镜像）实际编译。
- 引入 IJK 后 HAP 体积约 **27 MB**（仅 arm64-v8a 的 FFmpeg 系列 .so）。
  工作流会在构建前删除 `x86_64` native 库（`oh_modules/*/libs/x86_64`），
  只保留真机 ABI arm64-v8a（测试机型 Mate 80）。
  若需在模拟器运行，请手动恢复 x86_64（或注释掉 workflow 的「仅保留 arm64-v8a」步骤）。
- 依赖：`@ohos/ijkplayer@2.0.13`（ohpm），其 native 库由包内 `libs/` 提供，
  构建时随 HAP 打入，无需额外 NDK 编译。
