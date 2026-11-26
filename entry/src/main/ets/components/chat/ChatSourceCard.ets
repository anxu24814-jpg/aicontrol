// DS 搜索来源折叠卡（DS 全家桶二期 S4 #13 自 ChatMessageItem 域级最小拆分迁出，并在新址
// 补两件事：站点徽标 + 长按半模态）。一句话职责 =「一轮回答的引用来源：折叠卡头 + 条目列表」。
// · 为什么拆：ChatMessageItem 剔头 1199 已在 1200 硬线下沿，徽标与长按都要加在条目行上，
//   不拆就必然越线（宪法 1200）。拆出后父件只剩一行组件调用，本件承载全部来源卡逻辑。
// · 数据单源不变：dsSourceEntriesOf（sources ∪ annotations URL 去重），解析记忆化留在本件
//   ——串变即失效重算，缓存恒与入参一致（照原件先例）。
// · 展开意愿不放本件：读写父件的 msg.dsSourcesExpanded（@Observed 属性），父件在改值前先
//   上行钉顶（onToggle 里由父件完成），本件只发「用户点了卡头」这一事实——与拆分前同序。
// · 长按半模态走 UIContext 版 showActionMenu（半模态菜单形态，禁全局 promptAction.*）：标题 +
//   摘要 + 打开原文 / 复制链接。短按仍是打开浏览器（保持既有单键语义不退化）。
import { pasteboard } from '@kit.BasicServicesKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardBg, cardBorderColor, cardDescColor, cardTitleColor, CARD_RADIUS }
  from '../../common/Theme';
import { DsSourceEntry, dsDomainOf, dsSourceEntryAnchorId, dsSourceEntriesOf }
  from './ChatMessageCompose';

@Component
export struct ChatSourceCard {
  // 列载荷原样串（'' = 无来源，本件零渲染）
  @Prop serverToolsJson: string = '';
  // 承载消息 id（锚点 id 与无障碍标识）
  @Prop msgId: string = '';
  // 展开态（= 父件 msg.dsSourcesExpanded；回放行恒 false）
  @Prop expanded: boolean = false;
  // 正文字体家族串（父件算好传入——家族推导单源在 ChatFont，本件禁自行拼串）
  @Prop bodyFamily: string = '';
  @Prop appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Prop cardAlphaLevel: number = 0;
  // 卡头点击上行（父件负责钉顶纠正 + animateTo 改 msg.dsSourcesExpanded）
  onToggle: () => void = () => {};
  // 条目打开上行（父件统一走 launchExternalLink——外链出口单源）
  onOpenUrl: (url: string) => void = (url: string): void => {};

  // 解析记忆化（键 = 列载荷串；串变即重算）
  private cacheJson: string = '';
  private cacheList: DsSourceEntry[] = [];

  private entries(): DsSourceEntry[] {
    const json: string = this.serverToolsJson;
    if (json === '') {
      return [];
    }
    if (json !== this.cacheJson) {
      this.cacheJson = json;
      this.cacheList = dsSourceEntriesOf(json);
    }
    return this.cacheList;
  }

  // 复制链接（长按菜单第二项）
  private copyLink(url: string): void {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data)
        .then((): void => {
          this.toastText('链接已复制');
        })
        .catch((): void => {
          this.toastText('复制失败');
        });
    } catch (e) {
      this.toastText('复制失败');
    }
  }

  private toastText(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // 无 UI 上下文边缘态：静默
    }
  }

  // 长按条目 → 半模态菜单（标题 + 两动作）。★ UIContext 的 PromptAction 只提供
  // showActionMenu（无 showActionSheet——后者是全局 promptAction 命名空间的老 API，项目
  // 红线禁全局形态），故以动作菜单承载半模态语义；条目摘要进标题第二行（空摘要回退 URL）
  private showEntrySheet(entry: DsSourceEntry): void {
    const title: string = entry.title !== '' ? entry.title : entry.url;
    const sub: string = entry.snippet !== '' ? entry.snippet : '';
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: sub !== '' ? title + '\n' + sub : title,
        buttons: [
          { text: '打开原文', color: $r('sys.color.font_primary') },
          { text: '复制链接', color: $r('sys.color.font_primary') }
        ]
      }).then((result): void => {
        if (result.index === 0) {
          this.onOpenUrl(entry.url);
        } else if (result.index === 1) {
          this.copyLink(entry.url);
        }
      }).catch((): void => undefined);
    } catch (e) {
      // 弹层不可用：静默（短按打开原文仍可用）
    }
  }

  build() {
    if (this.entries().length > 0) {
      Column() {
        Row() {
          SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_down') :
            $r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
          Text('DeepSeek 搜索来源 · ' + this.entries().length.toString() + ' 条')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.bodyFamily)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.onToggle();
        })
        if (this.expanded) {
          ForEach(this.entries(), (entry: DsSourceEntry): void => {
            Divider()
              .strokeWidth(0.5)
              .color(cardBorderColor(this.appColorMode))
              .margin({ top: 6, bottom: 6 })
              // 条件渲染根挂 IDENTITY：animateTo 内上下树未配 transition 会被官方加默认
              // OPACITY 淡出，收起时旧条目在动画窗内延留卡外（照拆分前同款处置）
              .transition(TransitionEffect.IDENTITY)
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(entry.number.toString())
                  .fontSize(11)
                  .fontFamily(this.bodyFamily)
                  .fontColor(cardDescColor())
                  .constraintSize({ minWidth: 16 })
                Text(entry.title !== '' ? entry.title : entry.url)
                  .fontSize(13)
                  .fontFamily(this.bodyFamily)
                  .fontColor(cardTitleColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                // 站点徽标（#13）：域名可用才出（纯文本小字 + 次要色，不加底色/圆角——
                // 行内元素禁自绘，与项目「按钮零自绘」同纪律）；域名不可解析则整块不渲染
                if (dsDomainOf(entry.url) !== '') {
                  Text(dsDomainOf(entry.url))
                    .fontSize(10)
                    .fontFamily(this.bodyFamily)
                    .fontColor(cardDescColor())
                    .maxLines(1)
                    .constraintSize({ maxWidth: 96 })
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%')
              if (entry.snippet !== '') {
                Text(entry.snippet)
                  .fontSize(11)
                  .fontFamily(this.bodyFamily)
                  .fontColor(cardDescColor())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              Text(entry.url)
                .fontSize(10)
                .fontFamily(this.bodyFamily)
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .id(dsSourceEntryAnchorId(this.msgId, entry.number))
            .onClick((): void => {
              this.onOpenUrl(entry.url);
            })
            // 长按 → 半模态（#13）；短按仍开原文，两手势互不吞（LongPress 优先）
            .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
              this.showEntrySheet(entry);
            }))
            .transition(TransitionEffect.IDENTITY)
          }, (entry: DsSourceEntry): string => entry.url + '#' + entry.number.toString())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
      .borderRadius(CARD_RADIUS)
      // 展开中间帧不出卡（照拆分前）：clip 按卡圆角轮廓裁超界绘制，只裁绘制不参与测量
      .clip(true)
    }
  }
}
