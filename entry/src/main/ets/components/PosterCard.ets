import { TitleItem } from '../model/Models';
import { Theme } from '../ui/Theme';
import { fmtCount } from '../ui/Utils';

@Component
export struct PosterCard {
  item: TitleItem = { title_id: 0, name: '', slug: '', cover_url: '' };
  cardWidth: number = 106;
  showMeta: boolean = true;
  onOpen: (item: TitleItem) => void = (item: TitleItem) => {};

  build() {
    Column() {
      Stack() {
        Image(this.item.cover_url)
          .width(this.cardWidth)
          .height(this.cardWidth * 1.42)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .backgroundColor(Theme.BG_CARD)
          .draggable(false)
        if (this.item.is_completed) {
          Text('完结')
            .fontSize(9)
            .fontColor(Theme.TEXT)
            .backgroundColor('rgba(0,0,0,0.55)')
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin(4)
            .alignSelf(ItemAlign.End)
            .align(Alignment.BottomEnd)
        }
      }
      .width(this.cardWidth)
      .height(this.cardWidth * 1.42)

      if (this.showMeta) {
        Text(this.item.name)
          .fontSize(13)
          .fontColor(Theme.TEXT)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.cardWidth)
          .margin({ top: 6 })
          .height(34)
        Text((fmtCount(this.item.view_count) || ' ') + (this.item.view_count ? ' 播放' : ''))
          .fontSize(11)
          .fontColor(Theme.TEXT_DIM)
          .width(this.cardWidth)
      }
    }
    .onClick(() => {
      this.onOpen(this.item);
    })
  }
}
