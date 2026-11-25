# AnyShort → HarmonyOS 移植报告

日期：2026-11-25 · 源：https://anyshort.net/zh-Hans/ · 目标：HarmonyOS NEXT（API 12）

## 1. 源项目分析

| 项 | 结论 |
|---|---|
| 技术栈 | 自研 SPA：服务端渲染首屏 HTML + ES Module 前端（app.js 为 History API 路由），Tailwind 风格原子类 |
| 数据层 | 同源公开 REST API `/v1`（nginx 反代 public-api），JWT 会话握手 + 401 自动刷新 |
| 播放 | 自托管 THEOplayer，mp4/HLS 直链（TikTok CDN），带过期时间 |
| 账号 | Google OAuth（全页跳转，session cookie），未登录按 device_id 记录进度 |
| 多语言 | 25 种语言，路径前缀 `/{lang}/` |
| 其他 | 广告系统（preroll/popunder）、SEO SSR、wrapper.js（第三方 WebView 壳支持） |

## 2. 实测 API 端点（2026-11-25 验证）

- `POST /v1/auth/session` `{platform, device_id?}` → `{access_token, refresh_token, expires_in:1800, device_id, user}`
- `GET /v1/home?lang=` → `data:{spotlight{items[]}, rails[{title,kind,ref,items[],next}], banners[], popular_sort}`
- `GET /v1/browse?sort=newest|popular&cursor=&limit=` → `{data[], page{limit,has_more,next}}`
- `GET /v1/search?q=&lang=&cursor=` → 同上
- `GET /v1/suggest?q=&lang=` → `data: string[]`
- `GET /v1/titles/{id}?lang=` → 详情（tags/gating/rating/subtitle_languages/...）
- `GET /v1/titles/{id}/episodes?lang=&cursor=` → `{data:[{episode_id,episode_no,locked,access}], page}`
- `GET /v1/episodes/{eid}/play?lang=&sub_lang=` → `{selected{url,quality,protocol}, streams[], sub_langs[]}`
- `GET /v1/episodes/{eid}/subtitles?lang=` → `data:[]`（当前样本为空）
- `POST /v1/watch/progress` `{episode_id}`；`GET /v1/watch/progress?title_ids=`
- `GET /v1/history`、`GET/POST/DELETE /v1/favorites`、`PUT /v1/titles/{id}/rating`
- `GET /v1/collections/{id}`（manual rail）、Google 登录 `GET /v1/auth/google/start?next=`

## 3. 移植路线

**方案 B：ArkUI 原生重写**（Web 应用 + 规范 JSON API + 直链播放，原生体验最优）。
未采用 ArkWeb 壳方案（方案 A），仅在 Google OAuth 登录使用 Web 组件承载跳转流程。

## 4. 能力映射

| Web 侧 | 鸿蒙侧 |
|---|---|
| fetch + Bearer + sessionStorage | @kit.NetworkKit http + preferences 持久化 device_id/token |
| History API 路由 | @ohos.router 页面路由 + 底部 Tabs |
| THEOplayer `<video>` | AVPlayer + XComponent(surface)，mp4 直链 |
| localStorage 进度 | preferences（`t{titleId}` → {ep,posMs,ts}）续播 seek |
| Google OAuth 跳转 | ArkWeb Web 组件加载 `/v1/auth/google/start`，onPageEnd 检测回跳后重新握手 |
| i18n.js 25 语 | L10n.ets 词典（zh-Hans/en，可扩展） |
| toast / 加载态 | promptAction.showToast / LoadingProgress |

## 5. 已实现 / 未实现

已实现：首页、搜索、详情+剧集、播放（上下集/进度/续播/字幕管线/横屏）、
查看全部、历史、收藏、评分、Google 登录、双语切换、会话握手与 401 重试。

未实现 / 边界：
- 金币解锁付费集（仅提示，不涉及支付）；
- 25 种语言全量词典（保留 zh-Hans/en，结构可扩展）；
- 广告系统（有意不移植）；
- 平板/折叠屏大屏适配仅声明 deviceTypes，未做专项布局；
- 字幕当前站点数据为空，VTT 解析管线已就绪待数据。

## 6. 构建验证（GitHub Actions）

仓库 ches2010/AnyShortHM 已接入 `.github/workflows/build-hap.yml`，使用
`ghcr.io/dalongzhuazi/harmonyos-ci:api26r`（command-line-tools 26.0.0.821，
HarmonyOS 26.0.0 / API 26 正式版，SDK 内嵌）在 ubuntu-latest 容器内构建。

- 运行结果：**success**（run #17，commit 4a66ec6，耗时约 1 分 51 秒）
- 产物：`entry-default-unsigned.hap`，390,281 字节（artifact `hap-unsigned`）
- 编译期：ERROR 0，WARN 45（全部为 router.pushUrl/back/getParams、
  promptAction.showToast 的 deprecated 提示，不影响运行）

CI 调试中修复的问题（可供同类工程参考）：
1. `run:` 内联标量含 `": "` 导致 workflow YAML 解析失败 → 改块标量。
2. commandline-tools 2.0.0.2（API 9 时代）的 sdkmgr 无 `toolchains:12` 包 → 改用
   内嵌 SDK 的 API 26 工具链镜像，不再依赖 sdkmgr。
3. 缺 `hvigor/hvigor-config.json5` → hvigorw 无法启动。
4. `build-profile.json5` 的 `targets[].applyToDefaultProduct` 被新版 schema 拒绝 → 删除。
5. `main_pages.json` 放错到 `src/main/profile/` → 必须在 `src/main/resources/base/profile/`。
6. ArkTS 严格模式：`FontWeight.ExtraBold`/`Text.italic()` 不存在、`DotIndicator` 需 `new`、
   ForEach 键函数漏 `idx` 参数、`tabIndex`/`position` 与组件基类属性重名需改名、
   `preferences` 是默认导出、`?？{}` 空对象字面量需显式接口类型、AVPlayer 部分方法
   返回 void 不能链 `.catch`（改用 ignore() 兼容封装）。

## 7. 运行时问题修复（真机反馈）

**症状**：播放页黑屏，进度条 `00:00 / 00:00`，中央显示播放按钮，无任何错误提示。

**根因**：`XComponent` 漏写 `.onLoad()` 回调 → `surfaceReady` 恒为 `false` →
`loadPlay()` 拿到的流地址一直挂在 `pendingUrl`，`AVPlayer` 从未被创建
（因此既无画面也无 error 事件，duration 恒为 0）。

**修复**（entry/src/main/ets/pages/PlayerPage.ets）：
1. 补 `XComponent.onLoad`，Surface 就绪后立即启动 pending 播放请求；
2. `getXComponentSurfaceId()` 为空时延迟 150ms 重试绑定，避免早期空值；
3. 多码流回退：候选列表按 h264 → 其他 mp4 排序，播放失败或超时自动换下一个源；
4. 12 秒超时保护：未进入 prepared 则换源，全部失败时把原因显示到界面上
   （不再一直黑屏），并提供「重试」；
5. `player.url` 赋值包 try/catch；`ignore()` 兼容 void / Promise 两种返回并记录日志；
6. 中央播放按钮由 emoji 字符改为 Circle + Path 矢量绘制；静音/全屏改为文字按钮
   （新增 L10n 键：mute / unmute / fullscreen / exit_full / play_failed / player_fail）。

验证：修复后 CI 构建通过（run #21，commit 4a256bd），产物 401,661 字节。

### 播放页 UI 适配（真机反馈二）

**症状**：标题栏与进度条错位、重叠在画面中部；顶部未做沉浸式；下方剧集区留大片空白；
操作组件仅有静音/全屏。

**根因**：`Stack` 内给子组件加的 `.align()` 不生效，所有浮层被 Stack 默认居中，
导致顶部栏、进度条全部落到画面中心。

**修复**（entry/src/main/ets/pages/PlayerPage.ets）：
1. 控件层重构为「全屏 Column + Blank 顶/底对齐」，不再依赖 `.align()`；
2. 控件层设 `hitTestBehavior(HitTestMode.Transparent)`，空白区域点击穿透到视频（单击暂停/播放）；
3. 全面屏：根容器 `expandSafeArea([SYSTEM],[TOP])` + `getWindowAvoidArea(TYPE_SYSTEM)`
   取状态栏高度、`px2vp` 换算后作为顶部栏 padding；全屏时 `setWindowSystemBarEnable([])`
   隐藏系统栏，退出恢复；
4. 新增操作组件：中央播放/暂停、上一集/下一集、快退/快进 10 秒、倍速循环
   （1.0/1.25/1.5/2.0x）、静音、全屏、可拖动进度条、字幕叠加；
5. 剧集区 `layoutWeight(1)` 填充剩余空间并加页脚，消除底部留白；
6. 图标全部改为 Circle/Path/Rect 矢量绘制，避免 emoji 渲染成彩色方块。

验证：CI run #24 构建通过（commit a5194a0），产物 426,957 字节。

### 播放页 UI 二次适配（真机反馈三）

**问题**：竖屏视频比例错误（被拉伸）、静音/全屏为文字按钮、无清晰度选择。

**修复**：
1. 视频等比适配：容器 `onAreaChange` 取实际宽高 + `videoSizeChange` 事件取真实视频尺寸，
   按 contain 算法算出 `viewW/viewH`，XComponent 使用该尺寸居中显示，竖屏 9:16 不再变形
   （注意：该 SDK 的 `AVPlayer` 无 `videoWidth/videoHeight` 属性，必须用 `videoSizeChange` 事件）；
2. 静音/全屏改为矢量图标按钮（`Shape` + `Path`，喇叭/声波/斜线、四角箭头），不再用文字；
3. 新增清晰度选择：解析 `streams` 按 quality 去重并按分辨率降序，底部显示当前档位，
   点击弹出面板切换；切换时记录当前播放位置（`pendingSeekMs`），新码流 prepared 后 seek 回原位置；
4. 视频区高度 58% → 62%，画面更大。

验证：CI run #28 构建通过（commit aa7cb9c）。

### 播放页 UI 三次打磨（真机反馈四）

**问题**：图标偏小、竖屏视频点全屏后旋转横屏导致画面只剩中间一条、竖屏下方剧集区空白。

**修复**：
1. 图标按钮 34vp → **42vp**（图形 24vp），线宽 2~2.2vp，顶部栏 padding 14/12，
   返回箭头 28，标题 15；底部按钮字号/内边距同步放大，视觉更均衡；
2. **全屏按视频方向自适应**：`isPortraitVideo()` 判定（`videoH >= videoW`）——
   竖屏视频全屏 = 沉浸式（不旋转、隐藏系统栏、视频区 100%）；横屏视频全屏 = 旋转横屏 +
   隐藏系统栏；退出时统一恢复竖屏与系统栏；图标随状态切换"进入/退出全屏"；
3. 剧集区由 `layoutWeight(1)` 改为**固定 220vp**（标题 + 横条 + 上/下一集），
   消除此前在部分设备上被压成 0 高度导致的空白；
4. 视频区 60%，字幕上移（距底 164vp）避免与清晰度/倍速叠压。

验证：CI run #30 构建通过（commit 8f71549）。

## 8. 风险与后续事项

1. ~~本工程未经 DevEco Studio 实际编译~~ → 已通过 CI 实际编译验证（见上节）；
   DevEco Studio 本地编译仍建议在真机验证播放与 OAuth 流程。
2. CDN 视频直链带签名与过期时间（expire_at），过期需重新调用 /play 换取——应用已按
   “每次进入播放页实时获取”实现。
3. OAuth 登录依赖 accounts.google.com 可达性；国内网络环境可能需要用户自行处理。
4. 合规提醒：AnyShort 站点内容版权与商用授权问题需用户自行确认；本移植仅做客户端
   形态转换，未绕过任何访问控制。
