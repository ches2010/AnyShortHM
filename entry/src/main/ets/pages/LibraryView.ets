import { router, promptAction } from '@kit.ArkUI';
import { TitleItem, HistoryItem } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { getString } from '../store/AppStore';
import { Theme } from '../ui/Theme';
import { PosterCard } from '../components/PosterCard';

@Component
export struct LibraryView {
  @Prop @Watch('onChanged') langVersion: string = 'zh-Hans';
  @StorageProp('user_version') @Watch('onChanged') userVersion: number = 0;
  @State segIndex: number = 0;
  @State history: HistoryItem[] = [];
  @State favs: TitleItem[] = [];
  @State loading: boolean = false;
  @State hasUser: boolean = false;

  aboutToAppear(): void {
    this.refreshAll();
  }

  onChanged(): void {
    this.refreshAll();
  }

  private refreshAll(): void {
    getString('dtv_user', '').then((v: string) => {
      this.hasUser = v !== '';
    });
    this.loadHistory();
    this.loadFavs();
  }

  private loadHistory(): void {
    this.loading = true;
    ApiService.history(currentLang(), '', 24)
      .then((page) => {
        this.history = page.data ?? [];
        this.loading = false;
      })
      .catch((e: Error) => {
        this.loading = false;
      });
  }

  private loadFavs(): void {
    ApiService.favorites(currentLang(), '', 24)
      .then((page) => {
        this.favs = page.data ?? [];
      })
      .catch((e: Error) => {
        this.favs = [];
      });
  }

  private openDetailById(id: number, name: string, slug: string): void {
    router.pushUrl({ url: 'pages/DetailPage', params: { id: id, name: name, slug: slug } });
  }

  @Builder
  private historyList() {
    if (this.history.length === 0) {
      Column() {
        Text(this.loading ? t('loading') : t('empty')).fontSize(14).fontColor(Theme.TEXT_DIM).margin({ top: 80 })
      }.width('100%')
    } else {
      List({ space: 12 }) {
        ForEach(this.history, (h: HistoryItem, idx: number) => {
          ListItem() {
            Row() {
              Image(h.cover_url ?? '')
                .width(64).height(90)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .backgroundColor(Theme.BG_CARD)
              Column() {
                Text(h.name ?? '').fontSize(15).fontColor(Theme.TEXT).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(h.episode_no ? ('看到第 ' + h.episode_no + ' 集') : '')
                  .fontSize(12).fontColor(Theme.TEXT_DIM).margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })

              Text('›').fontSize(20).fontColor(Theme.TEXT_DIM)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => {
              this.openDetailById(h.title_id ?? 0, h.name ?? '', h.slug ?? '');
            })
          }
        }, (h: HistoryItem, idx: number) => 'h' + (h.title_id ?? 0) + '_' + (h.episode_no ?? 0) + '_' + idx)
      }
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private favList() {
    if (!this.hasUser) {
      Column() {
        Text(t('login_required')).fontSize(14).fontColor(Theme.TEXT_DIM).margin({ top: 60 })
        Button(t('login'))
          .margin({ top: 16 })
          .backgroundColor(Theme.ACCENT)
          .fontColor(Theme.TEXT)
          .onClick(() => {
            router.pushUrl({ url: 'pages/LoginWebPage' });
          })
      }.width('100%')
    } else if (this.favs.length === 0) {
      Column() {
        Text(t('empty')).fontSize(14).fontColor(Theme.TEXT_DIM).margin({ top: 80 })
      }.width('100%')
    } else {
      Grid() {
        ForEach(this.favs, (item: TitleItem, idx: number) => {
          GridItem() {
            PosterCard({
              item: item,
              cardWidth: 108,
              onOpen: (it: TitleItem) => this.openDetailById(it.title_id, it.name, it.slug)
            })
          }
        }, (item: TitleItem, idx: number) => 'f' + item.title_id + '_' + idx)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(12)
      .rowsGap(16)
      .width('100%')
      .padding(16)
    }
  }

  build() {
    Column() {
      Text(t('nav_library'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')
        .padding({ left: 16, top: 14, bottom: 8 })

      // 分段：历史 / 收藏
      Row() {
        Text(t('history'))
          .fontSize(14)
          .fontColor(this.segIndex === 0 ? Theme.ACCENT : Theme.TEXT_DIM)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.segIndex === 0 ? Theme.ACCENT_SOFT : Color.Transparent)
          .onClick(() => { this.segIndex = 0; })
        Text(t('favorites'))
          .fontSize(14)
          .fontColor(this.segIndex === 1 ? Theme.ACCENT : Theme.TEXT_DIM)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.segIndex === 1 ? Theme.ACCENT_SOFT : Color.Transparent)
          .margin({ left: 8 })
          .onClick(() => { this.segIndex = 1; })
        Blank()
        if (!this.hasUser) {
          Text(t('login') + ' ›').fontSize(13).fontColor(Theme.ACCENT)
            .onClick(() => { router.pushUrl({ url: 'pages/LoginWebPage' }); })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })

      if (this.segIndex === 0) {
        Scroll() { this.historyList() }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
      } else {
        Scroll() { this.favList() }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
