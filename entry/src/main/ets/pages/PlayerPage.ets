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
  @State currentCue: string = '';
  @State playData: PlayData | null = null;
  @State episodes: EpisodeItem[] = [];

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
  private startTimer: number = -1;

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    this.titleId = p['titleId'] ? Number(p['titleId']) : 0;
    this.titleName = p['titleName'] ? String(p['titleName']) : '';
    this.slug = p['slug'] ? String(p['slug']) : '';
    this.currentEpId = p['episodeId'] ? Number(p['episodeId']) : 0;
    this.currentEpNo = p['episodeNo'] ? Number(p['episodeNo']) : 1;
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
    if (this.landscape) {
      window.getLastWindow(appContext()).then((w: window.Window) => {
        ignore(w.setPreferredOrientation(window.Orientation.PORTRAIT));
      }).catch((e: Error) => {});
      this.landscape = false;
    }
  }

  aboutToDisappear(): void {
    this.clearStartTimer();
    this.persistProgress();
    this.releasePlayer();
  }

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

  private loadPlay(): void {
    this.loading = true;
    this.errMsg = '';
    ApiService.play(this.currentEpId, currentLang(), '')
      .then((pd: PlayData) => {
        this.playData = pd;
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
    this.playing = false;
    this.posMs = 0;
    this.duration = 0;
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
            if (this.resumePosMs > 5000 && this.resumePosMs < p.duration - 5000) {
              ignore(p.seek(this.resumePosMs));
              promptAction.showToast({ message: t('continue_watch'), duration: 1500 });
            }
            this.resumePosMs = 0;
            ignore(p.play());
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

  private toggleMute(): void {
    this.muted = !this.muted;
    if (this.avPlayer !== null) {
      ignore(this.avPlayer.setVolume(this.muted ? 0 : 1));
    }
  }

  private toggleFullscreen(): void {
    window.getLastWindow(appContext())
      .then((w: window.Window) => {
        const target = this.landscape ? window.Orientation.PORTRAIT : window.Orientation.LANDSCAPE;
        w.setPreferredOrientation(target)
          .then(() => { this.landscape = !this.landscape; })
          .catch((e: Error) => {});
      })
      .catch((e: Error) => {});
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

  build() {
    Column() {
      Stack() {
        XComponent({ id: 'as_player_surface', type: 'surface', controller: this.xcController })
          .width('100%')
          .height('100%')
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

        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor(Theme.TEXT)
            .onClick(() => { router.back(); })
          Text(this.titleName + ' · 第' + this.currentEpNo + '集')
            .fontSize(14)
            .fontColor(Theme.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 10 })
            .layoutWeight(1)
          Text(this.muted ? t('unmute') : t('mute'))
            .fontSize(11)
            .fontColor(Theme.TEXT)
            .padding({ left: 7, right: 7, top: 4, bottom: 4 })
            .backgroundColor('rgba(0,0,0,0.4)')
            .borderRadius(8)
            .margin({ right: 8 })
            .onClick(() => this.toggleMute())
          Text(this.landscape ? t('exit_full') : t('fullscreen'))
            .fontSize(11)
            .fontColor(Theme.TEXT)
            .padding({ left: 7, right: 7, top: 4, bottom: 4 })
            .backgroundColor('rgba(0,0,0,0.4)')
            .borderRadius(8)
            .onClick(() => this.toggleFullscreen())
        }
        .width('100%')
        .padding({ left: 12, right: 14, top: 10 })
        .align(Alignment.Top)

        if (!this.playing && !this.loading && this.errMsg === '') {
          Stack() {
            Circle().width(72).height(72).fill('rgba(0,0,0,0.5)')
            Path()
              .commands('M4 0 L4 28 L24 14 Z')
              .fill(Color.White)
          }
          .width(72)
          .height(72)
          .onClick(() => this.togglePlay())
        }

        if (this.currentCue !== '') {
          Text(this.currentCue)
            .fontSize(15)
            .fontColor(Theme.TEXT)
            .backgroundColor('rgba(0,0,0,0.55)')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(6)
            .margin({ bottom: 64 })
            .align(Alignment.Bottom)
            .maxLines(2)
        }

        Column() {
          Slider({
            value: Math.min(this.posMs, this.duration > 0 ? this.duration : 1),
            min: 0,
            max: this.duration > 0 ? this.duration : 1,
            step: 500
          })
            .selectedColor(Theme.ACCENT)
            .trackColor(Theme.BG_CARD)
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
            Text(fmtTime(this.posMs)).fontSize(10).fontColor(Theme.TEXT_DIM)
            Blank()
            Text(fmtTime(this.duration)).fontSize(10).fontColor(Theme.TEXT_DIM)
          }
          .width('100%')
        }
        .padding({ left: 14, right: 14, bottom: 8 })
        .width('100%')
        .align(Alignment.Bottom)
      }
      .width('100%')
      .height(this.landscape ? '100%' : '56%')
      .backgroundColor('#000000')

      if (!this.landscape) {
        Row() {
          Text(t('episodes')).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT)
          Blank()
          Text('选集 ›').fontSize(12).fontColor(Theme.TEXT_DIM)
            .onClick(() => { this.showEpPanel = true; })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.episodes, (ep: EpisodeItem, idx: number) => {
              Text('第' + ep.episode_no + '集')
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

        Row() {
          Button('⏮ ' + t('prev_ep'))
            .fontSize(13).fontColor(Theme.TEXT).backgroundColor(Theme.BG_CARD)
            .onClick(() => this.gotoEp(this.currentEpNo - 1))
          Blank()
          Button(t('next_ep') + ' ⏭')
            .fontSize(13).fontColor(Theme.TEXT).backgroundColor(Theme.ACCENT)
            .onClick(() => this.gotoEp(this.currentEpNo + 1))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
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

// 兼容 void / Promise 返回的调用：Promise 吞掉 rejection，同步异常记录日志
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
