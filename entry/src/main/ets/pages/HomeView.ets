import { router, promptAction } from '@kit.ArkUI';
import { HomeData, TitleItem, Rail, Banner } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { Theme } from '../ui/Theme';
import { fmtCount } from '../ui/Utils';
import { PosterCard } from '../components/PosterCard';

@Component
export struct HomeView {
  @Prop @Watch('onLangChanged') langVersion: string = 'zh-Hans';
  @State loading: boolean = true;
  @State errMsg: string = '';
  @State refreshing: boolean = false;
  @State home: HomeData | null = null;

  aboutToAppear(): void {
    this.load();
  }

  onLangChanged(): void {
    this.load();
  }

  load(): void {
    this.loading = true;
    this.errMsg = '';
    ApiService.home(currentLang())
      .then((d: HomeData) => {
        this.home = d;
        this.loading = false;
        this.refreshing = false;
      })
      .catch((e: Error) => {
        this.errMsg = e.message;
        this.loading = false;
        this.refreshing = false;
      });
  }

  private openDetail(item: TitleItem): void {
    router.pushUrl({
      url: 'pages/DetailPage',
      params: { id: item.title_id, name: item.name, slug: item.slug }
    });
  }

  private openList(rail: Rail): void {
    router.pushUrl({
      url: 'pages/BrowseListPage',
      params: { kind: rail.kind, ref: rail.ref, title: rail.title }
    });
  }

  @Builder
  private topBar() {
    Row() {
      Text() {
        Span('Any').fontColor(Theme.TEXT)
        Span('Short').fontColor(Theme.ACCENT)
      }
      .fontSize(24)
      .fontWeight(FontWeight.Bold)

      Blank()

      Text(t('app_tagline'))
        .fontSize(11)
        .fontColor(Theme.TEXT_DIM)
        .maxLines(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  private bannerArea(banners: Banner[]) {
    Swiper() {
      ForEach(banners, (b: Banner, idx: number) => {
        Stack() {
          Image(b.image_url)
            .width('100%')
            .height(120)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
            .backgroundColor(Theme.BG_CARD)
          Text(b.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT)
            .padding(10)
            .align(Alignment.BottomStart)
            .maxLines(1)
        }
        .width('100%')
      }, (b: Banner) => b.title + b.image_url)
    }
    .autoPlay(true)
    .interval(4500)
    .loop(true)
    .indicator(new DotIndicator().itemWidth(6).itemHeight(6).selectedColor(Theme.ACCENT).color(Theme.TEXT_DIM))
    .margin({ left: 16, right: 16, top: 4 })
  }

  @Builder
  private spotlightArea(items: TitleItem[]) {
    Column() {
      Text('热门推荐')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .padding({ left: 16, top: 12, bottom: 8 })
      Scroll() {
        Row({ space: 12 }) {
          ForEach(items, (item: TitleItem, idx: number) => {
            Column() {
              Image(item.cover_url)
                .width(168).height(238)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
                .backgroundColor(Theme.BG_CARD)
              Text(item.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(168)
                .margin({ top: 6 })
              Text(fmtCount(item.view_count) + ' 播放 · ' + (item.total_episodes ?? 0) + ' 集')
                .fontSize(11)
                .fontColor(Theme.TEXT_DIM)
                .width(168)
                .margin({ top: 2 })
            }
            .onClick(() => this.openDetail(item))
          }, (item: TitleItem) => 'sp' + item.title_id)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  @Builder
  private railArea(rail: Rail) {
    Column() {
      Row() {
        Text(rail.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Blank()
        Text(t('see_all') + ' ›')
          .fontSize(12)
          .fontColor(Theme.TEXT_DIM)
          .onClick(() => this.openList(rail))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 8 })

      Scroll() {
        Row({ space: 10 }) {
          ForEach(rail.items, (item: TitleItem, idx: number) => {
            PosterCard({
              item: item,
              cardWidth: 106,
              onOpen: (it: TitleItem) => this.openDetail(it)
            })
          }, (item: TitleItem) => rail.kind + rail.ref + '-' + item.title_id)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  @Builder
  private bodyArea() {
    if (this.loading) {
      Column() {
        LoadingProgress().width(44).height(44).color(Theme.ACCENT)
        Text(t('loading')).fontSize(13).fontColor(Theme.TEXT_DIM).margin({ top: 10 })
      }
      .width('100%')
      .padding({ top: 120 })
    } else if (this.errMsg !== '') {
      Column() {
        Text(':(  ' + t('err_load')).fontSize(16).fontColor(Theme.TEXT)
        Text(this.errMsg).fontSize(12).fontColor(Theme.TEXT_DIM).margin({ top: 6 })
        Button(t('retry'))
          .margin({ top: 16 })
          .backgroundColor(Theme.ACCENT)
          .fontColor(Theme.TEXT)
          .onClick(() => this.load())
      }
      .width('100%')
      .padding({ top: 120 })
    } else if (this.home) {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            if (this.home.banners.length > 0) {
              this.bannerArea(this.home.banners)
            }
            this.spotlightArea(this.home.spotlight.items)
            ForEach(this.home.rails, (rail: Rail, idx: number) => {
              this.railArea(rail)
            }, (rail: Rail) => rail.kind + rail.ref)
            Text('数据来自 anyshort.net')
              .fontSize(10)
              .fontColor(Theme.TEXT_DIM)
              .opacity(0.6)
              .padding({ top: 24, bottom: 30 })
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.Top)
      }
      .onRefreshing(() => {
        this.load();
      })
    }
  }

  build() {
    Column() {
      this.topBar()
      this.bodyArea()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
