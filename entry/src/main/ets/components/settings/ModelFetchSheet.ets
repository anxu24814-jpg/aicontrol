// 获取模型半模态（决明：「获取模型」改弹半模态勾选同步，不再直接入库）：清单 = 探针实际结果
//（每次获取即时拉取不缓存）；行卡 = 项目多选卡同款（Checkbox hitTestBehavior(None) 纯视觉坑5，
// 整行点击切换）；初始勾选 = 库中已有行，勾选态即「保存后在库」目标态。右上勾保存 → 同步落库：
// 勾选未入库 = 插入（默认 chat/无能力）、已入库未勾选 = 删除（deleteModel，会话级覆盖由它级联清）；
// API 清单外手动添加的行不在本清单，保存零触碰。完成后 onSaved 上行并关闭。数据一次性（关闭即弃）；
// 删除即清行，无孤儿；同步幂等（失败行仍在可重试）。
// 壳 = 规范-半模态面板与卡片布局全套：bindSheet 宿主挂根 + HdsNavigation MODAL +
// sheetTitleBarOptions（GRADIENT_BLUR + 右上保存勾）+ List clip(false) 穿透 + 容器无边距
//（行卡自 CARD_PANEL_WIDTH）+ detents [MEDIUM, LARGE]（选择器类）。
// · 关闭确认：勾选有未保存改动时，各路关闭（xmark / 下拉 / 侧滑返回 / 系统返回 / 点蒙层）都先问
//   「放弃这次勾选？」，无改动直接关。本件只上行脏态（onDirtyChange，同步直调）与关闭意图
//   （onDismiss），判据与确认在宿主 ProviderModelsPanel.requestCloseFetch（两路单源）。
// · 长列表 = List + Repeat.virtualScroll（V1 壳保勾选/保存/脏态链，渲染拆同文件 @ComponentV2 件 +
//   构造处桥接，规范 §4.6）：键只写 modelId，勾选圈随桥接 flags 整组替换 + @Param 刷新；说明行经
//   头槽挂首行；尾部让位进末行 padding + offset 轨；0 行分支壳侧 Scroll 兜底；scroller 绑标题栏模糊。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { deleteModel, insertModel } from '../../common/store/ProviderDb';
import { PROVIDER_EDIT_ID_KEY } from './ProviderKeysPanel';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetPanelOptions, sheetTitleBarOptions, SheetDetents } from '../chat/KimiSheetCommon';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';

// 半模态行：modelId 展示名 + rowId（库行主键，'' = 未入库）+ inDb（已在库 = 初始勾选态）
export interface FetchSheetRow {
  modelId: string;
  rowId: string;
  inDb: boolean;
}

// 脏态判据（零依赖纯函数——断言脚本剥 import 后 node 可直跑）：任一行勾选态与库态镜像不一致 =
// 有未保存改动（save 成功已把 rows[].inDb 同步为目标态，故保存后自动归零）；flags 未播种 =
// 无改动可丢（面板打开前的一次性窗口）
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
  // 关闭上行（xmark——宿主走关闭请求统一收口：脏态先确认再关；手势关闭走 bindSheet onWillDismiss 同调）
  onDismiss: () => void = () => {
  };
  // 脏态上行：勾选态与库态镜像是否不一致，宿主存普通成员供关闭请求判据。必须同步直调（不得节流、
  // 不得放进异步回调、不得漏播种初值）——宿主判据停在旧值时，一动勾选就被当「无改动」静默丢弃
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

  // 说明行（头槽——非空分支挂 V2 首行、空分支直挂；选中计数随勾选实时刷新）
  @Builder
  CountLine() {
    Text('已选 ' + this.flags.filter((f: boolean): boolean => f).length + ' / ' +
      this.rows.length + '。保存后勾选模型入库，取消勾选的已添加模型将移除')
      .fontSize(13)
      .fontColor(cardDescColor())
      .width(CARD_PANEL_WIDTH)
  }

  // 列表内容（0 行壳侧 Scroll 兜底——Repeat 无行可挂；>0 行走渲染域件）
  @Builder
  RowsContent() {
    if (this.rows.length === 0) {
      Scroll(this.listScroller) {
        Column({ space: 10 }) {
          this.CountLine()
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
    } else {
      FetchSheetRows({
        rows: UIUtils.enableV2Compatibility(this.rows),
        flags: UIUtils.enableV2Compatibility(this.flags),
        appColorMode: this.appColorMode,
        scroller: this.listScroller,
        headSlot: (): void => {
          this.CountLine()
        },
        onToggle: (index: number): void => {
          this.toggleRow(index);
        }
      })
        .width('100%')
        .height('100%')
    }
  }

  build() {
    // 根容器撑满（否则内容贴左）；clip(false) = 滚动内容穿透标题栏背后，GRADIENT_BLUR 才有内容可透
    Column() {
      HdsNavigation() {
        this.RowsContent()
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

// 模型清单渲染域（同文件同域——壳引渲染件单向）：List + Repeat.virtualScroll（V2），数据源与勾选集
// 壳侧桥接；键只写 modelId（勾选圈随 flags 整组替换 + @Param 刷新）；头槽挂首行；尾让位 = 末行
// padding 24 + offset 轨 24；逐行保真层 Column 居中（ListItem 交叉轴默认贴左的既有 bug 修正）
@ComponentV2
struct FetchSheetRows {
  // 模型清单（壳侧构造处桥接传入——Repeat 懒加载要求数据源具 V2 观察能力）
  @Param rows: FetchSheetRow[] = [];
  // 勾选态（index 对齐 rows——桥接数组整组替换刷新勾选圈）
  @Param flags: boolean[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 首行头槽（说明行——壳侧 V1 Builder，计数随 flags 刷新）
  @BuilderParam headSlot: () => void;
  // 滚动控制器（壳侧实例经参数传入——HdsNavigation bindToScrollable 标题渐变模糊绑定）
  @Param scroller: Scroller = new Scroller();
  // 勾选切换上行（index 形态——壳侧 toggleRow 同拍直调脏态上行）
  @Event onToggle: (index: number) => void = () => {
  };

  // 多选行卡（会话多选同款：Checkbox 纯视觉 hitTest None——坑5，整行点击；Button(Normal) 包裹 =
  // 官方原生按压蒙层）；卡底 Column + 四周 padding 4 让蒙层距卡外圈 4vp，壳 padding 16/13 → 12/9
  // 回添，几何零位移
  @Builder
  ModelRow(ri: RepeatItem<FetchSheetRow>) {
    Column() {
      Button() {
        Row({ space: 12 }) {
          Text(ri.item.modelId)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Checkbox()
            .select(this.flags.length > ri.index ? this.flags[ri.index] : false)
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.onToggle(ri.index);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(4)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  build() {
    List({ space: 10, scroller: this.scroller }) {
      Repeat<FetchSheetRow>(this.rows)
        .each((ri: RepeatItem<FetchSheetRow>) => {
          ListItem() {
            // 首行 = 头槽（说明行）+ 首卡；保真层居中；末行带尾部让位（原尾行 24 等价）
            Column({ space: 10 }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              this.ModelRow(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: ri.index === this.rows.length - 1 ? 24 : 0 })
          }
        })
        // 键 = modelId（身份唯一；勾选态不塞键——flags 桥接整组替换刷新）
        .key((row: FetchSheetRow): string => row.modelId)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .contentEndOffset(24)
    // 模型清单单服务商有界（通常 ≤ 百级），5 为屏内缓冲（按页设值非全局口径）
    .cachedCount(5)
  }
}
