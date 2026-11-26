// 助手快速切换半模态面板（2026-11-16 首页布局双形态笔，方案档 §3.6）：侧栏面板当前助手行
// 点击弹出——助手列表 + 当前高亮 + 底部「管理助手」入口（push 助手二级页）。形状照
// SessionMovePanel（同交互族半模态）：数据自持有（打开即重拉）+ HdsNavigation MODAL 壳 +
// sheetTitleBarOptions 单源标题栏；差异 = 点行动作是「切换当前助手」而非移动会话——动作链
// 与 AssistantPage.switchActive 同源复用（写 ACTIVE_ASSISTANT_KEY + SESSION_LIST_RELOAD_KEY
// 与 CONN_RESOLVE_TICK_KEY 双广播），切换后侧栏列表重拉、主区已开会话不动（会话归属独立，
// 现状语义）。编辑入口拍板（方案档 §3.6）：面板底部固定「管理助手」行走二级页（完整编辑面
// 在助手页，不在窄面板里做编辑）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistants }
  from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { CONN_RESOLVE_TICK_KEY } from '../../common/store/ProviderDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { StatusBadge } from '../StatusBadge';

@Component
export struct AssistantSwitchPanel {
  // 页面存活守卫（退场迟到异步回调不写状态不上行）
  private departed: boolean = false;
  // 底部系统导航条高（vp，宿主注入——面板尾部让位 + 24 固定呼吸）
  @Prop bottomInset: number = 0;
  // 「管理助手」入口上行（宿主 push 助手二级页 + 关面板）
  onManage: () => void = () => {
  };
  // 关闭上行（标题栏 xmark / onWillDismiss 两路同调）
  onClose: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @State private assistants: AssistantRow[] = [];
  // 当前助手 id（ACTIVE_ASSISTANT_KEY 同源；存量 '' 行归默认口径同 AssistantPage）
  @State private currentId: string = ASSISTANT_DEFAULT_ID;
  @State private loaded: boolean = false;
  @State private hintText: string = '';
  // 切换在途（防连点重复广播）
  private switching: boolean = false;
  private bottomPadInset: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.bottomPadInset = this.bottomInset + 24;
    const active: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
    this.currentId = active !== '' ? active : ASSISTANT_DEFAULT_ID;
    queryAssistants()
      .then((rows: AssistantRow[]): void => {
        if (this.departed) {
          return;
        }
        this.assistants = rows;
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = '助手列表读取失败：' + (e as Error).message;
        this.loaded = true;
      });
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 切换当前助手（AssistantPage.switchActive 同链）：同值早退静默；写持久键 + 列表重拉广播
  // + 连接重解析广播（无行会话②级输入变化）+ toast
  private pick(row: AssistantRow): void {
    if (this.switching) {
      return;
    }
    if (this.currentId === row.id) {
      this.onClose();
      return;
    }
    this.switching = true;
    AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, row.id);
    this.currentId = row.id;
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    this.getUIContext().getPromptAction().showToast({ message: '已切换到「' + row.name + '」' });
    this.switching = false;
    this.onClose();
  }

  build() {
    HdsNavigation() {
      List({ space: CARD_SPACING, scroller: this.scroller }) {
        // 说明行（切换影响面：列表过滤与无行新会话归属；已开会话不动——现状语义）
        ListItem() {
          Text('切换后左侧会话列表与新建会话归属跟随所选助手，当前对话不切换')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
            .padding({ left: 4, right: 4 })
        }
        // 空态/失败行（首拉在途不闪空态；失败显示原因不装「暂无助手」）
        if (this.loaded && (this.hintText !== '' || this.assistants.length === 0)) {
          ListItem() {
            Text(this.hintText !== '' ? this.hintText : '暂无助手')
              .fontSize(13)
              .fontColor(this.hintText !== ''
                ? $r('sys.color.ohos_id_color_warning') : cardDescColor())
              .width('100%')
              .padding(16)
          }
        }
        // 助手行卡（SessionMovePanel 同形：person 符号 + 名 + 当前标记；能力摘要精简为
        // 模型名一行——快速切换场景够用，完整卡面在助手页）
        ForEach(this.assistants, (row: AssistantRow) => {
          ListItem() {
            Column() {
              Button() {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.person'))
                    .fontSize(20)
                    .fontColor([cardTitleColor()])
                  Text(row.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(cardTitleColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (this.currentId === row.id) {
                    StatusBadge({ text: '当前' })
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
              .type(ButtonType.Normal)
              .width('100%')
              .padding({ left: 12, right: 12, top: 11, bottom: 11 })
              .backgroundColor(Color.Transparent)
              .borderRadius(CARD_RADIUS)
              .onClick((): void => {
                this.pick(row);
              })
            }
            .width('100%')
            .padding(4)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
          }
        }, (row: AssistantRow): string => row.id + (this.currentId === row.id ? '|cur' : ''))
        // 管理助手入口（方案档 §3.6 编辑入口拍板：固定底部行，push 助手二级页）
        if (this.loaded && this.assistants.length > 0) {
          ListItem() {
            Button() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('管理助手')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_secondary')])
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .type(ButtonType.Normal)
            .width('100%')
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .backgroundColor(Color.Transparent)
            .borderRadius(CARD_RADIUS)
            .onClick((): void => {
              this.onManage();
            })
          }
        }
        // 尾部安全区让位
        ListItem() {
          Row()
            .height(this.bottomPadInset)
        }
      }
      .width('100%')
      .height('100%')
      // 滚动内容穿透标题栏背后（clip(false) 缺省裁剪 = 渐变模糊无内容可透——规范 §2）
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .padding({ top: 20, left: 16, right: 16 })
    }
    .titleBar(sheetTitleBarOptions('切换助手', '选择左侧列表与新建会话归属的助手', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
