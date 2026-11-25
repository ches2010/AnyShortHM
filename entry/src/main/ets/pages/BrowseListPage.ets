import { router } from '@kit.ArkUI';
import { TitleItem, CollectionData, TitlePage } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { Theme } from '../ui/Theme';
import { PosterCard } from '../components/PosterCard';

@Entry
@Component
struct BrowseListPage {
  @State items: TitleItem[] = [];
  @State loading: boolean = true;
  @State errMsg: string = '';
  @State hasMore: boolean = false;
  private kind: string = 'auto';
  private ref: string = '';
  private listTitle: string = '';
  private cursor: string = '';
  private sort: string = 'popular';

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>;
    this.kind = p['kind'] ? String(p['kind']) : 'auto';
    this.ref = p['ref'] ? String(p['ref']) : '';
    this.listTitle = p['title'] ? String(p['title']) : '';
    if (this.kind === 'auto' && this.ref === 'newest') {
      this.sort = 'newest';
    }
    this.load(true);
  }

  private load(reset: boolean): void {
    this.loading = true;
    this.errMsg = '';
    const cursor: string = reset ? '' : this.cursor;
    if (this.kind === 'manual') {
      ApiService.collection(this.ref, currentLang(), cursor, 18)
        .then((d: CollectionData) => {
          this.applyPage(d.items ?? [], d.next ?? '', reset);
        })
        .catch((e: Error) => this.onErr(e));
    } else {
      ApiService.browse(this.sort, currentLang(), cursor, 18)
        .then((d: TitlePage) => {
          this.applyPage(d.data ?? [], d.page?.next ?? '', reset);
        })
        .catch((e: Error) => this.onErr(e));
    }
  }

  private applyPage(items: TitleItem[], next: string, reset: boolean): void {
    this.items = reset ? items : this.items.concat(items);
    this.cursor = next;
    this.hasMore = next !== '';
    this.loading = false;
  }

  private onErr(e: Error): void {
    this.errMsg = e.message;
    this.loading = false;
  }

  private openDetail(item: TitleItem): void {
    router.pushUrl({ url: 'pages/DetailPage', params: { id: item.title_id, name: item.name, slug: item.slug } });
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.TEXT)
          .onClick(() => { router.back(); })
          .margin({ right: 12 })
        Text(this.listTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 10 })

      if (this.errMsg !== '') {
        Column() {
          Text(t('err_load')).fontSize(15).fontColor(Theme.TEXT)
          Button(t('retry')).margin({ top: 14 }).backgroundColor(Theme.ACCENT).fontColor(Theme.TEXT)
            .onClick(() => this.load(true))
        }.width('100%').padding({ top: 80 })
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.items, (item: TitleItem, idx: number) => {
                GridItem() {
                  PosterCard({
                    item: item,
                    cardWidth: 108,
                    onOpen: (it: TitleItem) => this.openDetail(it)
                  })
                }
              }, (item: TitleItem, idx: number) => item.title_id + '_' + idx)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(12)
            .rowsGap(16)
            .width('100%')
            .padding(16)

            if (this.loading) {
              LoadingProgress().width(30).height(30).color(Theme.ACCENT).margin(16)
            } else if (this.hasMore) {
              Button(t('load_more'))
                .fontSize(13)
                .fontColor(Theme.TEXT_DIM)
                .backgroundColor(Theme.BG_CARD)
                .margin({ bottom: 20 })
                .onClick(() => this.load(false))
            } else {
              Text(t('no_more')).fontSize(11).fontColor(Theme.TEXT_DIM).margin({ top: 6, bottom: 20 })
            }
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
  }
}
