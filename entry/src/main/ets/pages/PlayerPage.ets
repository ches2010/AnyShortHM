import { router, promptAction, window } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlayData, EpisodeItem, SubtitleTrack, SubCue } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { appContext, getLocalProgress, saveLocalProgress } from '../store/AppStore';
import { Theme } from '../ui/Theme';
import { fmtTime } from '../ui/Utils';

const SPEEDS: number[] = [1.0, 1.25, 1.5, 2.0];

@Entry
@Component
struct PlayerPage {
  @State loading: boolean = true;
  @State errMsg: string = '';
  @State playing: boolean = false;
  @State posMs: number = 0;
  @State duration: number = 0;
  @State muted: boolean = false;
  @State landscape: boolean = false;
  @State currentEpNo: number = 1;
  @State currentEpId: number = 0;
  @State showEpPanel: boolean = false;
  @State showQuality: boolean = false;
  @State currentCue: string = '';
  @State playData: PlayData | null = null;
  @State episodes: EpisodeItem[] = [];
  @State statusBarHeight: number = 0;
  @State speed: number = 1.0;
  // 视频显示尺寸（按真实视频比例等比 contain）
  @State boxW: number = 0;
  @State boxH: number = 0;
  @State viewW: number = 0;
  @State viewH: number = 0;
  @State videoW: number = 540;
  @State videoH: number = 960;
  // 清晰度
  @State qualities: string[] = [];
  @State curQuality: string = '';

  private avPlayer: media.AVPlayer | null = null;
  private xcController: XComponentController = new XComponentController();
  private surfaceReady: boolean = false;
  private pendingUrl: string = '';
  private candidates: string[] = [];
  private candIndex: number = 0;
  private reported: boolean = false;
  private dragging: boolean = false;
  private titleId: number = 0;
  private titleName: string = '';
  private slug: string = '';
  private cues: SubCue[] = [];
  private resumePosMs: number = 0;
  private pendingSeekMs: number = 0;
  private startTimer: number = -1;
  private qualityUrls: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    this.titleId = p['titleId'] ? Number(p['titleId']) : 0;
    this.titleName = p['titleName'] ? String(p['titleName']) : '';
    this.slug = p['slug'] ? String(p['slug']) : '';
    this.currentEpId = p['episodeId'] ? Number(p['episodeId']) : 0;
    this.currentEpNo = p['episodeNo'] ? Number(p['episodeNo']) : 1;
    this.initWindow();
    this.loadEpisodes();
    this.loadPlay();
    getLocalProgress(this.titleId).then((lp) => {
      if (lp !== null && lp.ep === this.currentEpNo && lp.posMs > 5000) {
        this.resumePosMs = lp.posMs;
      }
    });
  }

  onPageHide(): void {
    this.clearStartTimer();
    this.persistProgress();
    this.restoreWindow();
    this.landscape = false;
  }

  aboutToDisappear(): void {
    this.clearStartTimer();
    this.persistProgress();
    this.releasePlayer();
  }

  // ---------- 窗口 / 全面屏 ----------

  private initWindow(): void {
    window.getLastWindow(appContext())
      .then((w: window.Window) => {
        const area: window.AvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusBarHeight = px2vp(area.topRect.height);
        w.setWindowLayoutFullScreen(true).catch((e: Error) => {});
      })
      .catch((e: Error) => {});
  }

  private restoreWindow(): void {
    window.getLastWindow(appContext())
      .then((w: window.Window) => {
        const bars: Array<'status' | 'navigation'> = ['status', 'navigation'];
        w.setWindowSystemBarEnable(bars).catch((e: Error) => {});
        w.setPreferredOrientation(window.Orientation.PORTRAIT).catch((e: Error) => {});
      })
      .catch((e: Error) => {});
  }

  private toggleFullscreen(): void {
    window.getLastWindow(appContext())
      .then((w: window.Window) => {
        if (!this.landscape) {
          w.setPreferredOrientation(window.Orientation.LANDSCAPE)
            .then(() => {
              const hide: Array<'status' | 'navigation'> = [];
              w.setWindowSystemBarEnable(hide).catch((e: Error) => {});
              this.landscape = true;
            })
            .catch((e: Error) => {});
        } else {
          w.setPreferredOrientation(window.Orientation.PORTRAIT)
            .then(() => {
              const bars: Array<'status' | 'navigation'> = ['status', 'navigation'];
              w.setWindowSystemBarEnable(bars).catch((e: Error) => {});
              this.landscape = false;
            })
            .catch((e: Error) => {});
        }
      })
      .catch((e: Error) => {});
  }

  // ---------- 视频尺寸（等比 contain） ----------

  private calcVideoSize(): void {
    if (this.boxW <= 0 || this.boxH <= 0 || this.videoW <= 0 || this.videoH <= 0) {
      return;
    }
    const vr: number = this.videoW / this.videoH;
    const br: number = this.boxW / this.boxH;
    if (vr <= br) {
      this.viewH = this.boxH;
      this.viewW = this.boxH * vr;
    } else {
      this.viewW = this.boxW;
      this.viewH = this.boxW / vr;
    }
  }

  // ---------- 播放数据 ----------

  private persistProgress(): void {
    if (this.titleId > 0 && this.posMs > 3000) {
      saveLocalProgress(this.titleId, this.currentEpNo, this.posMs);
    }
  }

  private loadEpisodes(): void {
    ApiService.episodes(this.titleId, currentLang(), '', 200)
      .then((page) => {
        this.episodes = page.data ?? [];
      })
      .catch((e: Error) => {});
  }

  private buildQualityMap(pd: PlayData): void {
    this.qualityUrls = new Map<string, string>();
    const arr: string[] = [];
    if (pd.streams) {
      for (const s of pd.streams) {
        if (s.quality && s.codec === 'h264' && !this.qualityUrls.has(s.quality)) {
          this.qualityUrls.set(s.quality, s.url);
        }
      }
      for (const s of pd.streams) {
        if (s.quality && !this.qualityUrls.has(s.quality)) {
          this.qualityUrls.set(s.quality, s.url);
        }
      }
    }
    this.qualityUrls.forEach((v: string, k: string) => {
      arr.push(k);
    });
    arr.sort((a: string, b: string) => parseInt(b) - parseInt(a));
    this.qualities = arr;
    const selQ: string = pd.selected && pd.selected.quality ? pd.selected.quality : '';
    this.curQuality = selQ !== '' ? selQ : (arr.length > 0 ? arr[0] : '');
  }

  private loadPlay(): void {
    this.loading = true;
    this.errMsg = '';
    ApiService.play(this.currentEpId, currentLang(), '')
      .then((pd: PlayData) => {
        this.playData = pd;
        this.buildQualityMap(pd);
        this.candidates = buildCandidates(pd);
        this.candIndex = 0;
        this.loading = false;
        if (this.candidates.length === 0) {
          this.errMsg = t('player_fail');
          return;
        }
        this.tryStart();
        this.loadSubtitles();
      })
      .catch((e: Error) => {
        this.loading = false;
        this.errMsg = e.message;
      });
  }

  private tryStart(): void {
    if (this.candIndex >= this.candidates.length) {
      this.loading = false;
      this.errMsg = t('player_fail');
      return;
    }
    const url: string = this.candidates[this.candIndex];
    if (!this.surfaceReady) {
      this.pendingUrl = url;
      return;
    }
    this.startPlayer(url);
  }

  private startPlayer(url: string): void {
    this.releasePlayer();
    this.errMsg = '';
    this.loading = true;
    if (this.pendingSeekMs <= 0) {
      this.playing = false;
      this.posMs = 0;
      this.duration = 0;
    }
    media.createAVPlayer()
      .then((p: media.AVPlayer) => {
        this.avPlayer = p;
        p.on('stateChange', (state: string) => {
          if (state === 'initialized') {
            this.bindSurface(p);
            ignore(p.prepare());
          } else if (state === 'prepared') {
            this.clearStartTimer();
            this.duration = p.duration;
            if (this.pendingSeekMs > 1000) {
              ignore(p.seek(this.pendingSeekMs));
              this.pendingSeekMs = 0;
            } else if (this.resumePosMs > 5000 && this.resumePosMs < p.duration - 5000) {
              ignore(p.seek(this.resumePosMs));
              promptAction.showToast({ message: t('continue_watch'), duration: 1500 });
              this.resumePosMs = 0;
            }
            ignore(p.play());
            if (this.speed !== 1.0) {
              ignore(p.setSpeed(this.speed));
            }
          } else if (state === 'playing') {
            this.playing = true;
            this.loading = false;
          } else if (state === 'paused') {
            this.playing = false;
          } else if (state === 'completed') {
            this.playing = false;
            this.autoNext();
          }
        });
        p.on('videoSizeChange', (width: number, height: number) => {
          if (width > 0 && height > 0) {
            this.videoW = width;
            this.videoH = height;
            this.calcVideoSize();
          }
        });
        p.on('timeUpdate', (time: number) => {
          if (!this.dragging) {
            this.posMs = time;
          }
          this.updateCue(time);
          if (!this.reported && time > 10000) {
            this.reported = true;
            ApiService.saveProgress(this.currentEpId).catch((e: Error) => {});
          }
        });
        p.on('error', (e: BusinessError) => {
          this.playing = false;
          this.loading = false;
          this.clearStartTimer();
          const msg: string = e && e.message ? e.message : 'player error';
          if (this.candIndex + 1 < this.candidates.length) {
            this.candIndex++;
            this.startPlayer(this.candidates[this.candIndex]);
          } else {
            this.errMsg = msg;
          }
        });
        try {
          p.url = url;
        } catch (e) {
          this.loading = false;
          this.errMsg = (e as Error).message;
          return;
        }
        this.armStartTimer();
      })
      .catch((e: Error) => {
        this.loading = false;
        this.errMsg = e.message;
      });
  }

  private bindSurface(p: media.AVPlayer): void {
    const sid: string = this.xcController.getXComponentSurfaceId();
    if (sid !== '') {
      p.surfaceId = sid;
      return;
    }
    setTimeout(() => {
      const sid2: string = this.xcController.getXComponentSurfaceId();
      if (sid2 !== '' && this.avPlayer === p) {
        p.surfaceId = sid2;
      }
    }, 150);
  }

  private armStartTimer(): void {
    this.clearStartTimer();
    this.startTimer = setTimeout(() => {
      if (this.duration <= 0 && this.errMsg === '' && !this.playing) {
        this.nextCandidateOrFail();
      }
    }, 12000);
  }

  private clearStartTimer(): void {
    if (this.startTimer >= 0) {
      clearTimeout(this.startTimer);
      this.startTimer = -1;
    }
  }

  private nextCandidateOrFail(): void {
    this.releasePlayer();
    if (this.candIndex + 1 < this.candidates.length) {
      this.candIndex++;
      this.tryStart();
    } else {
      this.loading = false;
      this.errMsg = t('player_fail');
    }
  }

  private releasePlayer(): void {
    if (this.avPlayer !== null) {
      const p = this.avPlayer;
      this.avPlayer = null;
      ignore(p.release());
    }
  }

  // ---------- 操作 ----------

  private togglePlay(): void {
    if (this.avPlayer === null) {
      this.tryStart();
      return;
    }
    if (this.playing) {
      ignore(this.avPlayer.pause());
    } else {
      ignore(this.avPlayer.play());
    }
  }

  private seekTo(ms: number): void {
    if (this.avPlayer !== null) {
      ignore(this.avPlayer.seek(ms));
    }
  }

  private seekBy(deltaMs: number): void {
    if (this.avPlayer === null) {
      return;
    }
    let target: number = this.posMs + deltaMs;
    if (target < 0) {
      target = 0;
    }
    if (this.duration > 0 && target > this.duration) {
      target = this.duration;
    }
    this.posMs = target;
    this.seekTo(target);
  }

  private cycleSpeed(): void {
    let idx: number = 0;
    for (let i = 0; i < SPEEDS.length; i++) {
      if (Math.abs(SPEEDS[i] - this.speed) < 0.01) {
        idx = i;
        break;
      }
    }
    idx = (idx + 1) % SPEEDS.length;
    this.speed = SPEEDS[idx];
    if (this.avPlayer !== null) {
      ignore(this.avPlayer.setSpeed(this.speed));
    }
  }

  private toggleMute(): void {
    this.muted = !this.muted;
    if (this.avPlayer !== null) {
      ignore(this.avPlayer.setVolume(this.muted ? 0 : 1));
    }
  }

  private switchQuality(q: string): void {
    this.showQuality = false;
    if (q === this.curQuality) {
      return;
    }
    const url: string = this.qualityUrls.get(q) ?? '';
    if (url === '') {
      return;
    }
    this.curQuality = q;
    this.pendingSeekMs = this.posMs > 1000 ? this.posMs : 0;
    this.candidates = [url];
    this.candIndex = 0;
    this.startPlayer(url);
    promptAction.showToast({ message: t('quality') + ': ' + q, duration: 1200 });
  }

  private switchEpisode(ep: EpisodeItem): void {
    if (ep.locked === true) {
      promptAction.showToast({ message: t('episode_locked'), duration: 1600 });
      return;
    }
    this.persistProgress();
    this.currentEpId = ep.episode_id;
    this.currentEpNo = ep.episode_no;
    this.reported = false;
    this.cues = [];
    this.currentCue = '';
    this.posMs = 0;
    this.duration = 0;
    this.pendingSeekMs = 0;
    this.showEpPanel = false;
    this.loadPlay();
  }

  private autoNext(): void {
    for (const ep of this.episodes) {
      if (ep.episode_no === this.currentEpNo + 1) {
        this.switchEpisode(ep);
        return;
      }
    }
  }

  private gotoEp(no: number): void {
    for (const ep of this.episodes) {
      if (ep.episode_no === no) {
        this.switchEpisode(ep);
        return;
      }
    }
    promptAction.showToast({ message: t('no_more'), duration: 1400 });
  }

  private loadSubtitles(): void {
    this.cues = [];
    this.currentCue = '';
    ApiService.subtitles(this.currentEpId, currentLang())
      .then((tracks: SubtitleTrack[]) => {
        let url: string = '';
        for (const tr of tracks) {
          const u = tr.url ?? tr.vtt_url ?? tr.file ?? '';
          if (u !== '') {
            url = u;
            break;
          }
        }
        if (url === '') {
          return;
        }
        const req = http.createHttp();
        req.request(url, { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING })
          .then((resp) => {
            this.cues = parseVtt(resp.result as string);
            req.destroy();
          })
          .catch((e: Error) => { req.destroy(); });
      })
      .catch((e: Error) => {});
  }

  private updateCue(ms: number): void {
    if (this.cues.length === 0) {
      if (this.currentCue !== '') {
        this.currentCue = '';
      }
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < this.cues.length; i++) {
      if (ms >= this.cues[i].startMs && ms <= this.cues[i].endMs) {
        idx = i;
        break;
      }
      if (this.cues[i].startMs > ms) {
        break;
      }
    }
    const newText: string = idx >= 0 ? this.cues[idx].text : '';
    if (newText !== this.currentCue) {
      this.currentCue = newText;
    }
  }

  // ---------- 图标 ----------

  @Builder
  private iconSpeaker() {
    Stack({ alignContent: Alignment.Center }) {
      Circle().width(34).height(34).fill('rgba(0,0,0,0.45)')
      Shape() {
        Path()
          .commands('M3 8 L6 8 L10 4 L10 18 L6 14 L3 14 Z')
          .fill(Color.White)
        if (this.muted) {
          Path()
            .commands('M13 6 L19 16')
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(1.8)
        } else {
          Path()
            .commands('M13 6 Q16 11 13 16')
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(1.8)
          Path()
            .commands('M15.5 3.5 Q19.5 11 15.5 18.5')
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(1.4)
        }
      }
      .width(22)
      .height(22)
      .viewPort({ x: 0, y: 0, width: 22, height: 22 })
    }
    .width(34)
    .height(34)
    .margin({ right: 8 })
    .onClick(() => this.toggleMute())
  }

  @Builder
  private iconFullscreen() {
    Stack({ alignContent: Alignment.Center }) {
      Circle().width(34).height(34).fill('rgba(0,0,0,0.45)')
      Shape() {
        if (this.landscape) {
          Path()
            .commands('M7 0 L7 7 L0 7 M13 0 L13 7 L20 7 M20 13 L13 13 L13 20 M0 13 L7 13 L7 20')
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(1.8)
        } else {
          Path()
            .commands('M0 7 L0 0 L7 0 M13 0 L20 0 L20 7 M20 13 L20 20 L13 20 M7 20 L0 20 L0 13')
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(1.8)
        }
      }
      .width(20)
      .height(20)
      .viewPort({ x: 0, y: 0, width: 20, height: 20 })
    }
    .width(34)
    .height(34)
    .onClick(() => this.toggleFullscreen())
  }

  @Builder
  private playIcon(size: number) {
    Stack() {
      Circle().width(size).height(size).fill('rgba(0,0,0,0.45)')
      if (this.playing) {
        Row({ space: size * 0.10 }) {
          Rect().width(size * 0.12).height(size * 0.36).fill(Color.White).radius(1)
          Rect().width(size * 0.12).height(size * 0.36).fill(Color.White).radius(1)
        }
      } else {
        Path()
          .commands('M0 0 L0 ' + (size * 0.36) + ' L' + (size * 0.30) + ' ' + (size * 0.18) + ' Z')
          .fill(Color.White)
          .margin({ left: size * 0.06 })
      }
    }
    .width(size)
    .height(size)
    .onClick(() => this.togglePlay())
  }

  @Builder
  private topBar() {
    Row() {
      Text('‹')
        .fontSize(26)
        .fontColor(Theme.TEXT)
        .onClick(() => { router.back(); })
      Text(this.titleName + ' · ' + t('ep_short') + this.currentEpNo)
        .fontSize(14)
        .fontColor(Theme.TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 10 })
        .layoutWeight(1)
      this.iconSpeaker()
      this.iconFullscreen()
    }
    .width('100%')
    .padding({
      left: 12,
      right: 12,
      top: this.landscape ? 8 : this.statusBarHeight + 6,
      bottom: 8
    })
  }

  @Builder
  private bottomBar() {
    Column() {
      Slider({
        value: Math.min(this.posMs, this.duration > 0 ? this.duration : 1),
        min: 0,
        max: this.duration > 0 ? this.duration : 1,
        step: 500
      })
        .selectedColor(Theme.ACCENT)
        .trackColor('rgba(255,255,255,0.35)')
        .blockColor(Theme.TEXT)
        .width('100%')
        .onChange((v: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin) {
            this.dragging = true;
          } else if (mode === SliderChangeMode.End) {
            this.dragging = false;
            this.seekTo(v);
          }
        })

      Row() {
        Text(fmtTime(this.posMs)).fontSize(11).fontColor(Theme.TEXT)
        Blank()
        if (this.qualities.length > 0) {
          Text(this.curQuality.toUpperCase())
            .fontSize(11)
            .fontColor(Theme.TEXT)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor('rgba(0,0,0,0.45)')
            .borderRadius(6)
            .onClick(() => { this.showQuality = true; })
        }
        Text(this.speed.toFixed(2) + 'x')
          .fontSize(11)
          .fontColor(Theme.TEXT)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(6)
          .margin({ left: 8 })
          .onClick(() => this.cycleSpeed())
        Blank()
        Text(fmtTime(this.duration)).fontSize(11).fontColor(Theme.TEXT)
      }
      .width('100%')
      .padding({ top: 2 })

      Row({ space: 18 }) {
        Text(t('prev_ep'))
          .fontSize(12)
          .fontColor(Theme.TEXT)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(8)
          .onClick(() => this.gotoEp(this.currentEpNo - 1))
        Text('-10s')
          .fontSize(12)
          .fontColor(Theme.TEXT)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(8)
          .onClick(() => this.seekBy(-10000))
        this.playIcon(52)
        Text('+10s')
          .fontSize(12)
          .fontColor(Theme.TEXT)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(8)
          .onClick(() => this.seekBy(10000))
        Text(t('next_ep'))
          .fontSize(12)
          .fontColor(Theme.TEXT)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('rgba(0,0,0,0.45)')
          .borderRadius(8)
          .onClick(() => this.gotoEp(this.currentEpNo + 1))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 10, bottom: 8 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, bottom: 6 })
  }

  build() {
    Column() {
      // 视频区：按真实视频比例等比居中显示
      Stack({ alignContent: Alignment.Center }) {
        XComponent({ id: 'as_player_surface', type: 'surface', controller: this.xcController })
          .width(this.viewW > 0 ? this.viewW + 'vp' : '100%')
          .height(this.viewH > 0 ? this.viewH + 'vp' : '100%')
          .onLoad(() => {
            this.surfaceReady = true;
            if (this.pendingUrl !== '') {
              const u: string = this.pendingUrl;
              this.pendingUrl = '';
              this.startPlayer(u);
            }
          })
          .onClick(() => this.togglePlay())

        if (this.loading) {
          LoadingProgress().width(40).height(40).color(Theme.ACCENT)
        }

        if (this.errMsg !== '') {
          Column() {
            Text(t('play_failed')).fontSize(14).fontColor(Theme.TEXT)
            Text(this.errMsg)
              .fontSize(11)
              .fontColor(Theme.TEXT_DIM)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
              .padding({ left: 24, right: 24 })
            Button(t('retry'))
              .fontSize(12)
              .margin({ top: 12 })
              .backgroundColor(Theme.ACCENT)
              .fontColor(Theme.TEXT)
              .onClick(() => this.loadPlay())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }

        // 顶部控制层
        Column() {
          this.topBar()
          Blank()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        // 中央播放/暂停（暂停时）
        if (!this.playing && !this.loading && this.errMsg === '') {
          this.playIcon(68)
        }

        // 字幕
        if (this.currentCue !== '') {
          Column() {
            Blank()
            Text(this.currentCue)
              .fontSize(15)
              .fontColor(Theme.TEXT)
              .backgroundColor('rgba(0,0,0,0.55)')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .maxLines(2)
              .margin({ bottom: 118 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .hitTestBehavior(HitTestMode.Transparent)
        }

        // 底部控制层
        Column() {
          Blank()
          this.bottomBar()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height(this.landscape ? '100%' : '62%')
      .backgroundColor('#000000')
      .onAreaChange((oldV: Area, newV: Area) => {
        let w: number = 0;
        let h: number = 0;
        if (typeof newV.width === 'number') {
          w = newV.width;
        }
        if (typeof newV.height === 'number') {
          h = newV.height;
        }
        if (w > 0 && h > 0) {
          this.boxW = w;
          this.boxH = h;
          this.calcVideoSize();
        }
      })

      // 剧集区
      if (!this.landscape) {
        Column() {
          Row() {
            Text(t('episodes')).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT)
            Blank()
            Text(t('all_episodes') + ' ›').fontSize(12).fontColor(Theme.TEXT_DIM)
              .onClick(() => { this.showEpPanel = true; })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 10 })

          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.episodes, (ep: EpisodeItem, idx: number) => {
                Text(t('ep_prefix') + ep.episode_no + t('ep_suffix'))
                  .fontSize(12)
                  .fontColor(ep.episode_no === this.currentEpNo ? Theme.TEXT : Theme.TEXT_DIM)
                  .backgroundColor(ep.episode_no === this.currentEpNo ? Theme.ACCENT : Theme.BG_CARD)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .opacity(ep.locked ? 0.5 : 1)
                  .onClick(() => this.switchEpisode(ep))
              }, (ep: EpisodeItem, idx: number) => 'chip' + ep.episode_id)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(42)

          Row({ space: 12 }) {
            Button(t('prev_ep'))
              .fontSize(13)
              .fontColor(Theme.TEXT)
              .backgroundColor(Theme.BG_CARD)
              .layoutWeight(1)
              .onClick(() => this.gotoEp(this.currentEpNo - 1))
            Button(t('next_ep'))
              .fontSize(13)
              .fontColor(Theme.TEXT)
              .backgroundColor(Theme.ACCENT)
              .layoutWeight(1)
              .onClick(() => this.gotoEp(this.currentEpNo + 1))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6 })

          Blank()

          Text('数据来自 anyshort.net')
            .fontSize(10)
            .fontColor(Theme.TEXT_DIM)
            .opacity(0.55)
            .margin({ bottom: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }

      // 选集面板
      if (this.showEpPanel) {
        Column() {
          Column() {
            Row() {
              Text(t('episodes')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT)
              Blank()
              Text('✕').fontSize(16).fontColor(Theme.TEXT_DIM)
                .onClick(() => { this.showEpPanel = false; })
            }
            .width('100%')
            .margin({ bottom: 12 })

            Grid() {
              ForEach(this.episodes, (ep: EpisodeItem, idx: number) => {
                GridItem() {
                  Text(ep.locked ? '🔒' + ep.episode_no : String(ep.episode_no))
                    .fontSize(13)
                    .fontColor(ep.episode_no === this.currentEpNo ? Theme.TEXT : Theme.TEXT_DIM)
                    .width('100%')
                    .height(38)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .backgroundColor(ep.episode_no === this.currentEpNo ? Theme.ACCENT : Theme.BG_CARD)
                    .onClick(() => this.switchEpisode(ep))
                }
              }, (ep: EpisodeItem, idx: number) => 'panel' + ep.episode_id)
            }
            .columnsTemplate('repeat(5, 1fr)')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
            .height(320)
          }
          .width('100%')
          .padding(16)
          .borderRadius({ topLeft: 16, topRight: 16 })
          .backgroundColor(Theme.BG_SOFT)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.showEpPanel = false; })
      }

      // 清晰度面板
      if (this.showQuality) {
        Column() {
          Column() {
            Row() {
              Text(t('quality')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT)
              Blank()
              Text('✕').fontSize(16).fontColor(Theme.TEXT_DIM)
                .onClick(() => { this.showQuality = false; })
            }
            .width('100%')
            .margin({ bottom: 8 })

            ForEach(this.qualities, (q: string, idx: number) => {
              Row() {
                Text(q.toUpperCase())
                  .fontSize(14)
                  .fontColor(q === this.curQuality ? Theme.ACCENT : Theme.TEXT)
                Blank()
                if (q === this.curQuality) {
                  Text('✓').fontSize(14).fontColor(Theme.ACCENT)
                }
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .border({ width: { bottom: 1 }, color: Theme.DIVIDER })
              .onClick(() => this.switchQuality(q))
            }, (q: string, idx: number) => 'q_' + q)
          }
          .width('100%')
          .padding(16)
          .borderRadius({ topLeft: 16, topRight: 16 })
          .backgroundColor(Theme.BG_SOFT)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.showQuality = false; })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

// 候选播放地址：优先 h264/mp4，其余码流作为回退
function buildCandidates(pd: PlayData): string[] {
  const out: string[] = [];
  const sel = pd.selected;
  if (sel && sel.url) {
    out.push(sel.url);
  }
  if (pd.streams) {
    for (const s of pd.streams) {
      if (s.codec === 'h264' && out.indexOf(s.url) < 0) {
        out.push(s.url);
      }
    }
    for (const s of pd.streams) {
      if (out.indexOf(s.url) < 0) {
        out.push(s.url);
      }
    }
  }
  return out;
}

// 兼容 void / Promise 返回的调用
function ignore(p: Promise<void> | void): void {
  try {
    if (p) {
      (p as Promise<void>).catch(() => {});
    }
  } catch (e) {
    console.error('player call failed: ' + (e as Error).message);
  }
}

// 解析 WEBVTT 字幕
function parseVtt(text: string): SubCue[] {
  const cues: SubCue[] = [];
  const lines = text.split(/\r?\n/);
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const arrow = line.indexOf('-->');
    if (arrow > 0) {
      const startMs = vttTimeToMs(line.slice(0, arrow));
      const endMs = vttTimeToMs(line.slice(arrow + 3));
      i++;
      const buf: string[] = [];
      while (i < lines.length && lines[i].trim() !== '' && lines[i].indexOf('-->') < 0) {
        buf.push(lines[i].trim());
        i++;
      }
      if (buf.length > 0) {
        const cue: SubCue = { startMs: startMs, endMs: endMs, text: buf.join(' ') };
        cues.push(cue);
      }
    } else {
      i++;
    }
  }
  return cues;
}

function vttTimeToMs(s: string): number {
  const m = /(\d+):(\d+):(\d+)[.,](\d+)/.exec(s.trim());
  if (m === null) {
    return 0;
  }
  return Number(m[1]) * 3600000 + Number(m[2]) * 60000 + Number(m[3]) * 1000 + Number(m[4]);
}
