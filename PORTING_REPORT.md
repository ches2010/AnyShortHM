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

## 7. 风险与后续事项

1. ~~本工程未经 DevEco Studio 实际编译~~ → 已通过 CI 实际编译验证（见上节）；
   DevEco Studio 本地编译仍建议在真机验证播放与 OAuth 流程。
2. CDN 视频直链带签名与过期时间（expire_at），过期需重新调用 /play 换取——应用已按
   “每次进入播放页实时获取”实现。
3. OAuth 登录依赖 accounts.google.com 可达性；国内网络环境可能需要用户自行处理。
4. 合规提醒：AnyShort 站点内容版权与商用授权问题需用户自行确认；本移植仅做客户端
   形态转换，未绕过任何访问控制。
