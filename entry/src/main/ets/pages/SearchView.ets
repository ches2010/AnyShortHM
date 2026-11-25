import { router, promptAction } from '@kit.ArkUI';
import { TitleItem } from '../model/Models';
import { ApiService } from '../net/ApiService';
import { currentLang, t } from '../i18n/L10n';
import { Theme } from '../ui/Theme';
import { PosterCard } from '../components/PosterCard';

@Component
export struct SearchView {
  @State query: string = '';
  @State results: TitleItem[] = [];
  @State suggests: string[] = [];
  @State loading: boolean = false;
  @State hasMore: boolean = false;
  @State searched: boolean = false;
  private nextCursor: string = '';
  private debounceId: number = -1;

  private doSearch(reset: boolean): void {
    const q: string = this.query.trim();
    if (q === '') {
      this.results = [];
      this.suggests = [];
      this.searched = false;
      this.hasMore = false;
      return;
    }
    this.loading = true;
    this.searched = true;
    ApiService.search(q, currentLang(), reset ? '' : this.nextCursor, 20)
      .then((page) => {
        const items: TitleItem[] = page.data ?? [];
        this.results = reset ? items : this.results.concat(items);
        this.nextCursor = page.page?.next ?? '';
        this.hasMore = page.page?.has_more ?? false;
        this.loading = false;
      })
      .catch((e: Error) => {
        this.loading = false;
        promptAction.showToast({ message: t('err_network'), duration: 1800 });
      });
  }

  private loadSuggests(): void {
    const q: string = this.query.trim();
    if (q === '') {
      this.suggests = [];
      return;
    }
    ApiService.suggest(q, currentLang())
      .then((arr: string[]) => {
        this.suggests = arr.slice(0, 8);
      })
      .catch((e: Error) => {
        this.suggests = [];
      });
  }

  private openDetail(item: TitleItem): void {
    router.pushUrl({
      url: 'pages/DetailPage',
      params: { id: item.title_id, name: item.name, slug: item.slug }
    });
  }

  build() {
    Column() {
      // 搜索框
      Row() {
        Text('🔍').fontSize(16).margin({ right: 8 })
        TextInput({ text: this.query, placeholder: t('search_hint') })
          .fontSize(14)
          .fontColor(Theme.TEXT)
          .placeholderColor(Theme.TEXT_DIM)
          .placeholderFont({ size: 14 })
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.query = v;
            if (this.debounceId >= 0) {
              clearTimeout(this.debounceId);
            }
            this.debounceId = setTimeout(() => {
              this.doSearch(true);
              this.loadSuggests();
            }, 400);
          })
          .onSubmit(() => {
            this.doSearch(true);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      if (!this.searched) {
        // 默认：搜索建议
        Column() {
          if (this.suggests.length > 0) {
            Text(t('search_suggest')).fontSize(13).fontColor(Theme.TEXT_DIM).width('100%').padding({ left: 16, bottom: 8 })
            ForEach(this.suggests, (s: string, idx: number) => {
              Text(s)
                .fontSize(14)
                .fontColor(Theme.TEXT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .border({ width: { bottom: 1 }, color: Theme.DIVIDER })
                .onClick(() => {
                  this.query = s;
                  this.doSearch(true);
                })
            }, (s: string) => s + '_' + this.suggests.indexOf(s))
          } else {
            Text(t('search_hint')).fontSize(14).fontColor(Theme.TEXT_DIM).margin({ top: 80 })
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        // 结果网格
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.results, (item: TitleItem, idx: number) => {
                GridItem() {
                  PosterCard({
                    item: item,
                    cardWidth: 108,
                    onOpen: (it: TitleItem) => this.openDetail(it)
                  })
                }
              }, (item: TitleItem) => item.title_id + '_' + this.results.indexOf(item))
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
                .onClick(() => this.doSearch(false))
            } else if (this.results.length === 0) {
              Text(t('empty')).fontSize(14).fontColor(Theme.TEXT_DIM).margin({ top: 60 })
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
