// 获取模型半模态（2026-08-31 领导指令：「获取模型」改弹半模态勾选同步——不再直接入库）：
// 清单 = 探针实际结果（API 返回全量模型，每次获取即时拉取不缓存）；行卡 = 项目多选卡同款
//（左模型名 + 右官方勾选圈 hitTestBehavior(None) 纯视觉——坑5，整行点击切换，键含选中态）；
// **初始勾选 = 库中已有行**，勾选态即「保存后在库」目标态；右上勾保存 → 同步落库：勾选未
// 入库 = 插入（默认 chat/无能力，同旧获取模型默认）、已入库未勾选 = 删除（deleteModel +
// 〔删除分支不再清任何"当前选择"状态——2026-09-10 会话级覆盖层笔：全局 active 键退役，
// 会话级覆盖由 deleteModel 内级联清〕）；**API 清单外手动添加
// 的行不在本清单，保存零触碰**。完成后 onSaved 上行（面板 reload + 顶卡纪元）并关闭。
// 数据生命周期：清单/勾选态一次性（关闭即弃，无堆积）；删除即清行，无孤儿（insert 失败无
// 行、delete 失败行仍在可重试——同步幂等）。
// 壳 = 规范-半模态面板与卡片布局全套：bindSheet 宿主挂根 + HdsNavigation MODAL +
// sheetTitleBarOptions（GRADIENT_BLUR 静止渐变模糊 + 右上保存勾）+ List clip(false) 穿透 +
// 容器无边距（行卡自 CARD_PANEL_WIDTH，防双重收窄）+ detents [MEDIUM, LARGE]（选择器类）。
// ★ 2026-09-23 关闭确认（半模态关闭确认笔）：勾选有未保存改动时，三路关闭（标题栏 xmark /
// 下拉 / 侧滑返回 / 系统返回 / 点蒙层）都先问「放弃这次勾选？」；无改动直接关（看一眼就退的
// 路径零摩擦）。本件只负责把脏态上行（onDirtyChange，同步直调）与关闭意图上行（onDismiss），
// 判据与确认在宿主 ProviderModelsPanel.requestCloseFetch（两路单源）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { deleteModel, insertModel } from '../../common/store/ProviderDb';
import { PROVIDER_EDIT_ID_KEY } from './ProviderKeysPanel';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetPanelOptions, sheetTitleBarOptions, SheetDetents } from '../chat/KimiSheetCommon';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

// 半模态行：modelId 展示名 + rowId（库行主键，'' = 未入库）+ inDb（已在库 = 初始勾选态）
export interface FetchSheetRow {
  modelId: string;
  rowId: string;
  inDb: boolean;
}

// 脏态判据（零依赖纯函数——断言脚本剥 import 后 node 可直跑）：存在任一行的勾选态与库态镜像
// 不一致 = 有未保存的勾选改动；保存成功时 save() 已把 rows[].inDb 同步成目标态，故保存后自动
// 归零。flags 未播种（长度与 rows 不符）= 无改动可丢（面板打开前的一次性窗口）
export function hasFetchSheetChanges(flags: boolean[], rows: FetchSheetRow[]): boolean {
  if (flags.length !== rows.length) {
    return false;
  }
  for (let i = 0; i < rows.length; i++) {
    if (flags[i] !== rows[i].inDb) {
      return true;
    }
  }
  return false;
}

@Component
export struct ModelFetchSheet {
  // 所属服务商（@StorageProp 订阅——content 通道 @Prop 冻结坑，KeysPanel 键常量注释）
  @StorageProp(PROVIDER_EDIT_ID_KEY) providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 半模态标题栏材质随沉浸光感总档
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 清单（宿主拉取成功后构造传入；打开期间不变——普通成员）
  rows: FetchSheetRow[] = [];
  // 同步完成上行（宿主 reload + 顶卡纪元 + 关闭面板）
  onSaved: () => void = () => {
  };
  // 关闭上行（xmark——宿主走关闭请求统一收口：脏态先确认再关；手势关闭路径走 bindSheet
  // onWillDismiss 同调宿主同一方法）
  onDismiss: () => void = () => {
  };
  // 脏态上行（2026-09-23 半模态关闭确认笔）：勾选态与库态镜像是否不一致，宿主存普通成员供
  // 关闭请求判据。★ 必须**同步直调**（不得节流、不得放进异步回调，也不得只在切换时上行而
  // 漏播种初值）——宿主判据停在旧值时，用户一动勾选就会被当「无改动」静默丢弃
  onDirtyChange: (dirty: boolean) => void = () => {
  };
  // 勾选态（index 对齐 rows；整组替换驱动键变重建刷新勾选圈——状态最小化）
  @State private flags: boolean[] = [];
  @State private saving: boolean = false;
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.flags = this.rows.map((row: FetchSheetRow): boolean => row.inDb);
    // 播种后立上行初值（未播种的宿主成员恒 false —— 一动勾选即被当无改动）
    this.onDirtyChange(hasFetchSheetChanges(this.flags, this.rows));
  }

  private toggleRow(index: number): void {
    const next: boolean[] = this.flags.slice();
    next[index] = !next[index];
    this.flags = next;
    // 与上一行同拍直调（见 onDirtyChange 注释）
    this.onDirtyChange(hasFetchSheetChanges(this.flags, this.rows));
  }

  // 保存（右上勾）：同步落库（幂等——中断重进重新获取再保存即可）；守卫 saving/providerId
  private async save(): Promise<void> {
    if (this.saving || this.providerId === '') {
      return;
    }
    this.saving = true;
    let added: number = 0;
    let removed: number = 0;
    try {
      for (let i = 0; i < this.rows.length; i++) {
        if (this.flags[i] && !this.rows[i].inDb) {
          await insertModel(this.providerId, this.rows[i].modelId, '', 'chat', '');
          this.rows[i].inDb = true; // 内存态同步——失败重试时跳过已插入行（防重复堆积）
          added++;
        }
      }
      for (let i = 0; i < this.rows.length; i++) {
        if (!this.flags[i] && this.rows[i].inDb) {
          await deleteModel(this.rows[i].rowId);
          this.rows[i].inDb = false;
          removed++;
        }
      }
      this.getUIContext().getPromptAction().showToast({
        message: added + removed > 0 ? '已同步：新增 ' + added + ' 个，移除 ' + removed + ' 个' : '清单未变化'
      });
      this.onSaved();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '同步失败，可重试：' + (e as Error).message });
    } finally {
      this.saving = false;
    }
  }

  build() {
    // 根容器撑满（否则内容贴左——bug 实锤修正）；滚动层 = Scroll + Column alignItems
    // Center（List 的 ListItem 交叉轴默认 start 会贴左，同 bug 弃用）；clip(false) =
    // 滚动内容穿透标题栏背后，GRADIENT_BLUR 才有内容可透（规范 2 节）
    Column() {
      HdsNavigation() {
        Scroll(this.listScroller) {
          Column({ space: 10 }) {
            // 说明行（对齐卡缘 16；选中计数随勾选实时刷新）
            Text('已选 ' + this.flags.filter((f: boolean): boolean => f).length + ' / ' +
              this.rows.length + '。保存后勾选模型入库，取消勾选的已添加模型将移除')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
            ForEach(this.rows, (row: FetchSheetRow, index: number) => {
              // 多选行卡（会话多选同款：Checkbox 纯视觉 hitTestBehavior None——坑5，整行点击；
              // Button(Normal) 包裹 = 官方原生按压蒙层，2026-09-12 UI 同形异构归一笔 1）
              Button() {
                Row({ space: 12 }) {
                  Text(row.modelId)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(cardTitleColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Checkbox()
                    .select(this.flags[index])
                    .hitTestBehavior(HitTestMode.None)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
              .type(ButtonType.Normal)
              .width(CARD_PANEL_WIDTH)
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(16)
              .onClick((): void => {
                this.toggleRow(index);
              })
            }, (row: FetchSheetRow, index: number): string =>
              row.modelId + '|' + (this.flags[index] ? '1' : '0') + '|' + index)
            // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条）
            Row()
              .width('100%')
              .height(24)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      }
      .titleBar(sheetTitleBarOptions('获取模型', '', (): void => {
        this.onDismiss();
      }, this.immersiveLevel, (): void => {
        this.save();
      }))
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .bindToScrollable([this.listScroller])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
