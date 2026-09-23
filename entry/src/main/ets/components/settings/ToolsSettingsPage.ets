// 工具调用设置二级页（2026-09-10 决明指令：设置页记忆卡下「联网搜索+工具调用」两行主卡
// 第二行）。自包 PageShell 壳，无标题栏菜单键；无编辑无保存动作 → 返回无参 pop 不挂 onPop
//（坑17 口径）。
// ★ 2026-09-18 七百五十五节承载首张全局工具卡「网页高危操作确认」（内置浏览器第二道
// 降压阀，04 专题档 §五·2 预留位，决明拍板「拍板按你」）：标题 + 说明小字 + SegmentBar
// 两段（每次确认/自动通过），形制照 MemoryPage 读取方式分段卡先例——说明小字在操作行上方
//（宪法「功能设置卡布局次序」条），消费侧只传 items/selectedIndex。写键即时持久化
//（@StorageLink 一写即落盘）。
// ★ 2026-09-18 七百五十六节：决明指令去掉 2026-09-10 的空占位说明卡（其「指路助手编辑页」
// 语义已由帮助中心「工具调用」条目承载）——页内只留高危确认卡一张。
// ★ 2026-09-20 HTTP 请求独立域笔：新增第二张全局工具卡「HTTP 写操作确认」（http_request
// 自联网搜索卡拆出为独立工具卡后的确认档控制面；决明勾选「写方法确认档」）——两卡同页并列，
// 形制与状态链逐条同源（各持一键、互不影响），09-18「页内只留一张」口径随本笔扩为两张。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { PREF_BROWSE_AUTO_APPROVE_KEY, PREF_HTTP_WRITE_AUTO_APPROVE_KEY,
  isBrowseAutoApproveEnabled, isHttpWriteAutoApproveEnabled } from '../../common/AppPreferences';
import { SETTING_TITLE_BROWSE_CONFIRM, SETTING_TITLE_HTTP_CONFIRM,
  SETTING_TITLE_TOOLS } from '../../common/SettingSearch';
import { SegmentBar } from '../SegmentBar';

@Component
export struct ToolsSettingsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 自动通过档持久键（写即持久化；@Watch 补正分段下标——备份导入等第二写键方在途时 UI 随键
  // 同步，MemoryPage 读取方式卡同款契约）
  @StorageLink(PREF_BROWSE_AUTO_APPROVE_KEY) @Watch('onAutoApproveChanged') browseAutoApprove: boolean =
    isBrowseAutoApproveEnabled();
  @State @Watch('onSegIndexChanged') segIndex: number = 0;
  // HTTP 写操作确认档持久键（2026-09-20 HTTP 请求独立域笔：http_request 自联网搜索拆出后
  // 的第二张全局工具卡；状态与回调三条与上面浏览卡逐条同形，键不同、互不影响）
  @StorageLink(PREF_HTTP_WRITE_AUTO_APPROVE_KEY) @Watch('onHttpAutoApproveChanged') httpWriteAutoApprove: boolean =
    isHttpWriteAutoApproveEnabled();
  @State @Watch('onHttpSegIndexChanged') httpSegIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 每次确认（默认）/ 1 = 自动通过，勿乱调）
  private approveItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '每次确认' },
    { text: '自动通过' }
  ]);
  // HTTP 写操作分段选项（同上顺序契约）
  private httpApproveItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '每次确认' },
    { text: '自动通过' }
  ]);

  aboutToAppear(): void {
    this.segIndex = this.browseAutoApprove ? 1 : 0;
    this.httpSegIndex = this.httpWriteAutoApprove ? 1 : 0;
  }

  // 用户点分段 → 写持久键（下标 0 = 每次确认 / 1 = 自动通过；同值不回写防递归）
  private onSegIndexChanged(): void {
    const value: boolean = this.segIndex === 1;
    if (value !== this.browseAutoApprove) {
      this.browseAutoApprove = value;
    }
  }

  // 第二写键方（备份导入恢复）→ 补正分段下标（@StorageLink 自动响应）
  private onAutoApproveChanged(): void {
    const idx: number = this.browseAutoApprove ? 1 : 0;
    if (idx !== this.segIndex) {
      this.segIndex = idx;
    }
  }

  // HTTP 写操作档：用户点分段 → 写持久键（同值不回写防递归）
  private onHttpSegIndexChanged(): void {
    const value: boolean = this.httpSegIndex === 1;
    if (value !== this.httpWriteAutoApprove) {
      this.httpWriteAutoApprove = value;
    }
  }

  // HTTP 写操作档：第二写键方（备份导入恢复）→ 补正分段下标
  private onHttpAutoApproveChanged(): void {
    const idx: number = this.httpWriteAutoApprove ? 1 : 0;
    if (idx !== this.httpSegIndex) {
      this.httpSegIndex = idx;
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 网页高危操作确认卡（2026-09-18 七百五十五节）——说明小字在操作行上方
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_BROWSE_CONFIRM)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('助手改动网页数据的操作前会先征求同意。切到自动通过后不再询问，密码输入始终禁止。确认卡上的「本会话内允许」只对当次会话的这个工具免询问，重启应用或切换会话后恢复询问。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.approveItems,
              selectedIndex: $segIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .width(CARD_PANEL_WIDTH)
        // HTTP 写操作确认卡（2026-09-20 HTTP 请求独立域笔）——形制与上卡逐条同源：说明小字
        // 在操作行上方，写键即时持久化；只影响写方法（POST/PUT/DELETE/PATCH），读取类
        //（GET/HEAD/OPTIONS）不受本档影响
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_HTTP_CONFIRM)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('助手调用接口发送数据前会先征求同意。切到自动通过后不再询问。确认卡上的「本会话内允许」只对当次会话的这个工具免询问，重启应用或切换会话后恢复询问。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.httpApproveItems,
              selectedIndex: $httpSegIndex
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .width(CARD_PANEL_WIDTH)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: SETTING_TITLE_TOOLS,
      content: (): void => {
        this.Content()
      }
    })
  }
}
