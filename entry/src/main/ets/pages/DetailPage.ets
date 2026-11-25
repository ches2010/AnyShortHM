import { router, promptAction } from '@kit.ArkUI';
import { TitleDetail, EpisodeItem, TagItem } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { getString } from '../store/AppStore';
import { Theme } from '../ui/Theme';
import { fmtCount } from '../ui/Utils';

@Entry
@Component
struct DetailPage {
  @State detail: TitleDetail | null = null;
  @State episodes: EpisodeItem[] = [];
  @State loading: boolean = true;
  @State epLoading: boolean = false;
  @State isFav: boolean = false;
  @State myRating: number = 0;
  @State showRate: boolean = false;
  @State epHasMore: boolean = false;
  private epCursor: string = '';
  private titleId: number = 0;
  private titleName: string = '';

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    this.titleId = p['id'] ? Number(p['id']) : 0;
    this.titleName = p['name'] ? String(p['name']) : '';
    this.load();
  }

  onPageShow(): void {
    // 从登录页/播放页返回后静默刷新收藏与评分状态
    if (this.titleId > 0 && this.detail !== null) {
      this.load();
    }
  }

  private load(): void {
    this.loading = this.detail === null;
    ApiService.title(this.titleId, currentLang())
      .then((d: TitleDetail) => {
        this.detail = d;
        this.isFav = d.is_favorite ?? false;
        this.myRating = d.my_rating ?? 0;
        this.loading = false;
        this.loadEpisodes(true);
      })
      .catch((e: Error) => {
        this.loading = false;
        promptAction.showToast({ message: t('err_load'), duration: 1800 });
      });
  }

  private loadEpisodes(reset: boolean): void {
    this.epLoading = true;
    ApiService.episodes(this.titleId, currentLang(), reset ? '' : this.epCursor, 60)
      .then((page) => {
        const arr: EpisodeItem[] = page.data ?? [];
        this.episodes = reset ? arr : this.episodes.concat(arr);
        this.epCursor = page.page?.next ?? '';
        this.epHasMore = page.page?.has_more ?? false;
        this.epLoading = false;
      })
      .catch((e: Error) => {
        this.epLoading = false;
      });
  }

  private toggleFav(): void {
    getString('dtv_user', '').then((v: string) => {
      if (v === '') {
        promptAction.showToast({ message: t('login_required'), duration: 1800 });
        router.pushUrl({ url: 'pages/LoginWebPage' });
        return;
      }
      if (this.isFav) {
        ApiService.removeFavorite(this.titleId)
          .then(() => {
            this.isFav = false;
            promptAction.showToast({ message: '已取消收藏', duration: 1200 });
          })
          .catch((e: Error) => {});
      } else {
        ApiService.addFavorite(this.titleId)
          .then(() => {
            this.isFav = true;
            promptAction.showToast({ message: t('favorited'), duration: 1200 });
          })
          .catch((e: Error) => {});
      }
    });
  }

  private submitRate(score: number): void {
    this.showRate = false;
    ApiService.rate(this.titleId, score)
      .then(() => {
        this.myRating = score;
        promptAction.showToast({ message: '已评分 ' + score + ' 星', duration: 1400 });
      })
      .catch((e: Error) => {
        promptAction.showToast({ message: t('login_required'), duration: 1600 });
      });
  }

  private openPlayer(ep: EpisodeItem): void {
    if (ep.locked === true) {
      promptAction.showToast({ message: t('episode_locked'), duration: 1800 });
      return;
    }
    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        episodeId: ep.episode_id,
        episodeNo: ep.episode_no,
        titleId: this.titleId,
        titleName: this.titleName,
        slug: this.detail?.slug ?? ''
      }
    });
  }

  @Builder
  private metaLine() {
    if (this.detail) {
      Text(
        (this.detail.episode_count ?? 0) + ' 集 · ' +
        (this.detail.is_completed ? t('completed') : t('ongoing')) +
        (this.detail.view_count ? ' · ' + fmtCount(this.detail.view_count) + ' ' + t('views') : '') +
        (this.detail.rating && this.detail.rating.count ? ' · ★ ' + (this.detail.rating.avg ?? 0) : '')
      )
        .fontSize(12)
        .fontColor(Theme.TEXT_DIM)
        .margin({ top: 6 })
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(Theme.TEXT)
            .onClick(() => { router.back(); })
            .margin({ right: 12 })
          Text(this.titleName)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: 12, bottom: 10 })

        if (this.loading) {
          Column() {
            LoadingProgress().width(42).height(42).color(Theme.ACCENT)
            Text(t('loading')).fontSize(13).fontColor(Theme.TEXT_DIM).margin({ top: 10 })
          }.width('100%').padding({ top: 100 })
        } else if (this.detail) {
          Scroll() {
            Column() {
              // 头部：海报 + 信息
              Row() {
                Image(this.detail.cover_url)
                  .width(128)
                  .height(182)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .backgroundColor(Theme.BG_CARD)
                Column() {
                  Text(this.detail.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.TEXT)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  this.metaLine()
                  // 标签
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.detail.tags ?? [], (tg: TagItem, idx: number) => {
                      Text(tg.name)
                        .fontSize(11)
                        .fontColor(Theme.TEXT_DIM)
                        .backgroundColor(Theme.BG_CARD)
                        .borderRadius(6)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .margin({ right: 6, top: 6 })
                    }, (tg: TagItem, idx: number) => 'tag' + tg.tag_id + '_' + idx)
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 14 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 6 })

              // 操作行
              Row() {
                Text(this.isFav ? '♥ ' + t('favorited') : '♡ ' + t('favorite'))
                  .fontSize(13)
                  .fontColor(this.isFav ? Theme.ACCENT : Theme.TEXT)
                  .backgroundColor(Theme.BG_CARD)
                  .borderRadius(18)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .onClick(() => this.toggleFav())

                Text(this.myRating > 0 ? '★ ' + this.myRating : '☆ ' + t('rate'))
                  .fontSize(13)
                  .fontColor(this.myRating > 0 ? Theme.GOLD : Theme.TEXT)
                  .backgroundColor(Theme.BG_CARD)
                  .borderRadius(18)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .margin({ left: 12 })
                  .onClick(() => { this.showRate = true; })

                Blank()

                if (this.detail.gating && this.detail.gating.mode === 'free_n') {
                  Text('前 ' + (this.detail.gating.free_episodes ?? 0) + ' 集免费')
                    .fontSize(11)
                    .fontColor(Theme.TEXT_DIM)
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16 })

              // 简介
              if (this.detail.description) {
                Text(t('description'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.TEXT)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 18, bottom: 6 })
                Text(this.detail.description)
                  .fontSize(13)
                  .fontColor(Theme.TEXT_DIM)
                  .lineHeight(20)
                  .width('100%')
                  .padding({ left: 16, right: 16 })
              }

              // 剧集
              Text(t('episodes') + '（' + (this.detail.episode_count ?? 0) + '）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 18, bottom: 10 })

              Grid() {
                ForEach(this.episodes, (ep: EpisodeItem, idx: number) => {
                  GridItem() {
                    Column() {
                      Text(ep.locked ? '🔒 ' + ep.episode_no : String(ep.episode_no))
                        .fontSize(13)
                        .fontColor(ep.locked ? Theme.TEXT_DIM : Theme.TEXT)
                    }
                    .width('100%')
                    .height(40)
                    .justifyContent(FlexAlign.Center)
                    .borderRadius(8)
                    .backgroundColor(ep.locked ? Theme.BG : Theme.BG_CARD)
                    .border({ width: 1, color: Theme.DIVIDER })
                    .onClick(() => this.openPlayer(ep))
                  }
                }, (ep: EpisodeItem) => 'ep' + ep.episode_id)
              }
              .columnsTemplate('repeat(5, 1fr)')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')
              .padding({ left: 16, right: 16 })

              if (this.epLoading) {
                LoadingProgress().width(26).height(26).color(Theme.ACCENT).margin(12)
              } else if (this.epHasMore) {
                Text(t('load_more'))
                  .fontSize(13)
                  .fontColor(Theme.TEXT_DIM)
                  .padding(14)
                  .onClick(() => this.loadEpisodes(false))
              }

              Text('')
                .height(30)
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)

      // 评分弹层
      if (this.showRate) {
        Column() {
          Column() {
            Text(t('rate')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT).margin({ bottom: 14 })
            Row({ space: 10 }) {
              ForEach([1, 2, 3, 4, 5], (s: number, idx: number) => {
                Text('★')
                  .fontSize(30)
                  .fontColor(s <= this.myRating ? Theme.GOLD : Theme.TEXT_DIM)
                  .onClick(() => { this.myRating = s; })
              }, (s: number) => 'star' + s)
            }
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(13).fontColor(Theme.TEXT_DIM).backgroundColor(Theme.BG_CARD)
                .onClick(() => { this.showRate = false; })
              Button('提交 ' + this.myRating + ' ★')
                .fontSize(13).fontColor(Theme.TEXT).backgroundColor(Theme.ACCENT)
                .onClick(() => this.submitRate(this.myRating))
            }
            .margin({ top: 16 })
          }
          .width('80%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(Theme.BG_SOFT)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.6)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
