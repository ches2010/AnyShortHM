# AnyShortHM — AnyShort 鸿蒙原生客户端

将 https://anyshort.net/zh-Hans/ （AnyShort 短剧字幕站）移植为 HarmonyOS / OpenHarmony
原生应用（ArkTS + ArkUI，Stage 模型，API 12 / HarmonyOS NEXT）。

移植方式为 **ArkUI 原生重写**（非 WebView 壳）：直接调用站点公开的 `/v1` REST API，
视频通过 AVPlayer 播放 CDN 直链 mp4/HLS。

## 功能

- 首页：Banner 轮播、热门推荐（spotlight）、分类 Rail 横滑列表、下拉刷新
- 搜索：防抖搜索 + 搜索建议 + 结果网格 + 分页加载
- 详情：海报/简介/标签/评分/剧集网格（分页）、收藏、五星评分
- 播放：AVPlayer 播放（多清晰度取 selected 流）、上/下集、选集面板、
  进度条拖动、静音、横竖屏切换、观看 10 秒后向服务端上报进度、本地续播（seek）
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

1. DevEco Studio 5.0+ 打开工程根目录（首次会自动同步 hvigor）。
2. `File > Settings > Signing Configs` 登录华为账号并勾选自动签名（调试）。
3. 选择模拟器或真机，Run 即可安装 entry 的 HAP。
4. 命令行构建 HAP：
   ```
   hvigorw assembleHap --mode module -p product=default
   # 产物：entry/build/default/outputs/default/entry-default-signed.hap
   ```
5. 手动安装：`hdc install entry-default-signed.hap`

## 配置

- API 地址：`ets/net/ApiClient.ets` 中 `API_BASE`（默认 https://anyshort.net/v1）。
- 视频流地址由服务端下发（带过期时间），应用不做任何破解/绕过。

## 已知边界

- Google 登录依赖站点的 OAuth 流程，需真机可访问 accounts.google.com。
- 字幕接口当前多数剧集返回空数组，字幕渲染已实现但可能无数据。
- 金币解锁（gating=free_n 之后的集数）仅提示“需解锁”，未实现内购。
- 本工程未经过 DevEco 实际编译验证，接口名以官方 API 参考为准。
