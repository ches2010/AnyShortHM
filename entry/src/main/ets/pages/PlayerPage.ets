import { router, promptAction, window } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { http } from '@kit.NetworkKit';
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
  @State position: number = 0;
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
  private reported: boolean = false;
  private dragging: boolean = false;
  private titleId: number = 0;
  private titleName: string = '';
  private slug: string = '';
  private cues: SubCue[] = [];
  private resumePosMs: number = 0;

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
    this.persistProgress();
    if (this.landscape) {
      window.getLastWindow(appContext()).then((w: window.Window) => {
        w.setPreferredOrientation(window.Orientation.PORTRAIT).catch((e: Error) => {});
      }).catch((e: Error) => {});
      this.landscape = false;
    }
  }

  aboutToDisappear(): void {
    this.persistProgress();
    this.releasePlayer();
  }

  private persistProgress(): void {
    if (this.titleId > 0 && this.position > 3000) {
      saveLocalProgress(this.titleId, this.currentEpNo, this.position);
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
        this.loading = false;
        const url: string = pd.selected?.url ?? ((pd.streams !== undefined && pd.streams.length > 0) ? pd.streams[0].url : '');
        if (url === '') {
          this.errMsg = 'no stream url';
          return;
        }
        if (this.surfaceReady) {
          this.startPlayer(url);
        } else {
          this.pendingUrl = url;
        }
        this.loadSubtitles();
      })
      .catch((e: Error) => {
        this.loading = false;
        this.errMsg = e.message;
      });
  }

  private startPlayer(url: string): void {
    this.releasePlayer();
    media.createAVPlayer()
      .then((p: media.AVPlayer) => {
        this.avPlayer = p;
        p.on('stateChange', (state: string) => {
          if (state === 'initialized') {
            p.surfaceId = this.xcController.getXComponentSurfaceId();
            p.prepare().catch((e: Error) => {});
          } else if (state === 'prepared') {
            this.duration = p.duration;
            if (this.resumePosMs > 5000 && this.resumePosMs < p.duration - 5000) {
              p.seek(this.resumePosMs).catch((e: Error) => {});
              promptAction.showToast({ message: t('continue_watch'), duration: 1500 });
            }
            this.resumePosMs = 0;
            p.play().catch((e: Error) => {});
          } else if (state === 'playing') {
            this.playing = true;
          } else if (state === 'paused') {
            this.playing = false;
          } else if (state === 'completed') {
            this.playing = false;
            this.autoNext();
          }
        });
        p.on('timeUpdate', (time: number) => {
          if (!this.dragging) {
            this.position = time;
          }
          this.updateCue(time);
          if (!this.reported && time > 10000) {
            this.reported = true;
            ApiService.saveProgress(this.currentEpId).catch((e: Error) => {});
          }
        });
        p.on('error', (e: Error) => {
          this.playing = false;
          this.errMsg = e.message;
        });
        p.url = url;
      })
      .catch((e: Error) => {
        this.errMsg = e.message;
      });
  }

  private releasePlayer(): void {
    if (this.avPlayer !== null) {
      const p = this.avPlayer;
      this.avPlayer = null;
      p.release().catch((e: Error) => {});
    }
  }

  private togglePlay(): void {
    if (this.avPlayer === null) {
      return;
    }
    if (this.playing) {
      this.avPlayer.pause().catch((e: Error) => {});
    } else {
      this.avPlayer.play().catch((e: Error) => {});
    }
  }

  private seekTo(ms: number): void {
    if (this.avPlayer !== null) {
      this.avPlayer.seek(ms).catch((e: Error) => {});
    }
  }

  private toggleMute(): void {
    this.muted = !this.muted;
    if (this.avPlayer !== null) {
      this.avPlayer.setVolume(this.muted ? 0 : 1).catch((e: Error) => {});
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
    this.position = 0;
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
      // 视频区
      Stack() {
        XComponent({ id: 'as_player_surface', type: 'surface', controller: this.xcController })
          .width('100%')
          .height('100%')
          .onClick(() => this.togglePlay())

        if (this.loading) {
          LoadingProgress().width(40).height(40).color(Theme.ACCENT)
        }

        if (this.errMsg !== '') {
          Column() {
            Text('播放失败').fontSize(14).fontColor(Theme.TEXT)
            Text(this.errMsg).fontSize(11).fontColor(Theme.TEXT_DIM).margin({ top: 4 })
            Button(t('retry')).fontSize(12).margin({ top: 10 })
              .backgroundColor(Theme.ACCENT).fontColor(Theme.TEXT)
              .onClick(() => this.loadPlay())
          }
        }

        // 顶栏
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
          Text(this.muted ? '🔇' : '🔊').fontSize(16).margin({ right: 14 }).onClick(() => this.toggleMute())
          Text(this.landscape ? '↙' : '↗').fontSize(16).onClick(() => this.toggleFullscreen())
        }
        .width('100%')
        .padding({ left: 12, right: 14, top: 10 })
        .align(Alignment.Top)

        // 中央播放按钮
        if (!this.playing && !this.loading && this.errMsg === '') {
          Text('▶')
            .fontSize(48)
            .fontColor('rgba(255,255,255,0.85)')
            .onClick(() => this.togglePlay())
        }

        // 字幕
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

        // 底部控制条
        Column() {
          Slider({
            value: Math.min(this.position, this.duration > 0 ? this.duration : 1),
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
            Text(fmtTime(this.position)).fontSize(10).fontColor(Theme.TEXT_DIM)
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
        // 集数横条
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
            }, (ep: EpisodeItem) => 'chip' + ep.episode_id)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(42)

        // 快捷上/下一集
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
              }, (ep: EpisodeItem) => 'panel' + ep.episode_id)
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
