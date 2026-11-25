import { Theme } from '../ui/Theme';
import { HomeView } from './HomeView';
import { SearchView } from './SearchView';
import { LibraryView } from './LibraryView';
import { currentLang, loadLang, setLang, t, LANG_ZH, LANG_EN } from '../i18n/L10n';

@Entry
@Component
struct Index {
  @State tabIndex: number = 0;
  @State lang: string = LANG_ZH;

  aboutToAppear(): void {
    loadLang().then(() => {
      this.lang = currentLang();
    });
  }

  private switchLang(): void {
    const next: string = this.lang === LANG_ZH ? LANG_EN : LANG_ZH;
    setLang(next).then(() => {
      this.lang = next;
    });
  }

  @Builder
  tabItem(labelKey: string, idx: number, glyph: string) {
    Column() {
      Text(glyph)
        .fontSize(20)
        .fontColor(this.tabIndex === idx ? Theme.ACCENT : Theme.TEXT_DIM)
      Text(t(labelKey))
        .fontSize(10)
        .margin({ top: 2 })
        .fontColor(this.tabIndex === idx ? Theme.ACCENT : Theme.TEXT_DIM)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: this.tabIndex }) {
        TabContent() {
          HomeView({ langVersion: this.lang })
        }.tabBar(this.tabItem('nav_home', 0, '⌂'))

        TabContent() {
          SearchView()
        }.tabBar(this.tabItem('nav_search', 1, '⌕'))

        TabContent() {
          LibraryView({ langVersion: this.lang })
        }.tabBar(this.tabItem('nav_library', 2, '☰'))
      }
      .barMode(BarMode.Fixed)
      .barBackgroundColor(Theme.BG_SOFT)
      .backgroundColor(Theme.BG)
      .onChange((i: number) => {
        this.tabIndex = i;
      })

      // 语言切换浮球
      Button(this.lang === LANG_ZH ? '中' : 'EN')
        .width(38)
        .height(38)
        .borderRadius(19)
        .fontSize(13)
        .fontColor(Theme.TEXT)
        .backgroundColor(Theme.BG_CARD)
        .border({ width: 1, color: Theme.DIVIDER })
        .position({ x: '86%', y: '2%' })
        .zIndex(10)
        .onClick(() => this.switchLang())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
