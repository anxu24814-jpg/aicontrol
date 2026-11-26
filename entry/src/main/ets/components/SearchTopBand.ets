// 页顶搜索框「标题栏下方带」承载形态（三库页搜索框承载笔）：官方《设置自定义区域》
// bottomBuilder 承载页顶吸顶搜索框——内容区件在 API 26 不出材质（《沉浸光感简介》生效范围），
// 迁入标题栏生效区即恢复沉浸光感（真机实测：两自定义区都在生效区内）。承载几何与
// PageTopSegmentBand（SegmentBar.ets）同构：① 水平居中；② 带内下移 inset——带顶 = 标题栏下沿，
// 不是 topPad（topPad 含蒙层下延 16vp，Theme SEGMENT_BAR_BAND_TOP_INSET 注释）；③ 整带命中透传
// （hitTest Transparent：带体不挡下方列表拖动，搜索框自身仍可点输入）。**搜索框本体形制与三库页
// 内容区 SearchSection 同形**（官方 Search + $$ 双向绑定 + 高 40——恰等于 SEGMENT_BAR_HEIGHT，
// 壳侧 bandParams 带高算式原样可用零新常量；**宽单源在外层 Column**——CARD_PANEL_WIDTH 挂
// Column、Search 本体 100% 填充，与 PageTopSegmentBand 同构，渲染宽 = 行卡屏宽 −32 一致；
// 首版两处双挂 calc 百分比嵌套两次框缩 32，真机反馈后改本形）。
// ★ 材质 = 恒光感（标题栏内输入族先例 SearchPage / SessionSearchPage 同档同参，interactive
// false；**无视内容区能力位**——带在生效区内，同 PageTopSegmentBand materialPinned
// 旁路口径：「无」档经 resolvedUiMaterial 归一 Material.empty + 透明底，与 SearchPage 同链）。
// ★ 2026-11-03 搜索框族调厚笔（决明报障：强档下 THIN 透材质叠标题栏 EXQUISITE + 常显蒙层
// 发暗晕染、设置页假框映入板块标题蓝字——背板模糊无法屏蔽颜色，唯一减法 = 调厚稀释透出）：
// 真框基准 REGULAR→THICK、openOnly 假框基准→ULTRA_THICK（初版两档拍板：真框提一档、假框提
// 两档）。★ 同日第二笔（决明真机复验「其他搜索框材质没变化、设置页假框才对」）：真框提一档后
// 强档生效 REGULAR，与假框生效档 THICK 差一档、观感几乎无变化——拍板真框一并上 ULTRA_THICK，
// 全族同基准同生效档（强档生效 THICK），「统一」按生效档落地而非按基准偏移。
// ★ 2026-11-05 搜索框族调薄笔（决明「统一调薄/透一档」）：全族基准 ULTRA_THICK → THICK
//（强档 −1 偏移下生效 REGULAR），四处同改——本件真框与假框 + SearchPage + SessionSearchPage。
// 沿革 = 11-03 两笔把全族收敛到 ULTRA_THICK 后，决明点名反向调薄一档；仍全族同基准同生效档，
// 禁单件私调。
// 使用处 = 四页（会话提示词 / 技能库 / 知识库三库页 + 记忆库页）+ 设置页两宿主（页签形态
// HomeNavigation 与侧栏设置二级页 SettingsPageHost，均 openOnly 假框档）
// 组件内 @Builder 包一层交给 PageShell.titleBarBottom（坑30：builder 必须是组件内 @Builder）；
// 与内容区搜索框**互斥渲染**（禁双份——内容区回退路径已随 2026-10-31 撤 HDS 回退兜底笔退役，
// 本件为唯一承载）。★ 记忆库页的差别 = 其页首搜索框原在「记忆条目」板块头**下方**，
// 迁带即与该板块头换位（板块头成内容区首项、框落在其上方带内）；三库页框原即内容区首项。
// ★ openOnly 假框档（设置页两宿主带内框专用，2026-11-02 笔）：true = 渲染不可输入不可获焦的假框
//（不绑词、focusable(false) 防点击弹键盘），整框点击走 onOpen 直达搜索二级页——设置页两宿主
// 搜索入口「顶部带内假框 ⇄ 下滑收带后右上角键」互斥切换的顶部形态。假框不是输入框，
// placeholder 为纯引导文案（与 SearchPage 二级页占位同词「搜索设置项」）；@Link keyword 契约
// 不变（openOnly 档由挂载方传哑位 @State 满足契约，本件不消费）。既有四库页真框消费方零变化。
// 消费方接线与二选一形锚 = assert-ui-shape 68 组「搜索带接线」钉；材质档位登记 =
// assert-feature-domain 66 组搜索框族 THICK 表（2026-11-05 调薄笔：全族同基准同生效档）。
import { uiMaterial } from '@kit.ArkUI';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_BAND_TOP_INSET, SEGMENT_BAR_HEIGHT } from '../common/Theme';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';

// 内容区顶留白让位算式单源（消费方四页共用，勿各写一份）：
// 带顶 = 标题栏下沿（topPad − 蒙层下延 16），框底 = 带顶 + 带内下移 8 + 内容高（缺省 40）=
// topPad + 32；首项再让出 gap ⇒ contentStartOffset / 内容 padding top =
// (topPad − 8) + contentHeight + gap。**gap 取分段承载先例间距 28**（AppearancePage /
// DataSyncPage 同款「胶囊底 + 28」；首版取列表卡间距 10 真机反馈观感过短，改齐先例；
// Math.max 防零 topPad 回退形态负值，DataSyncPage 同款守卫）。**仅 HDS 路径消费**——回退路径
// 框仍在内容区，让位为零（调用侧按 hdsAvailable 分派，本函数不自判）。
// ★ 第三参 contentHeight（工作区层级面包屑笔扩入）：两行档（面包屑 + 分段胶囊）由工作区页
// 传 WORKSPACE_BAND_CONTENT_HEIGHT（88 = 40 + 8 + 40）⇒ 让位 = (topPad − 8) + 88 + gap；
// 缺省值保持 SEGMENT_BAR_HEIGHT，既有消费方零变化
export function searchBandContentTop(topPad: number, gap: number,
  contentHeight: number = SEGMENT_BAR_HEIGHT): number {
  return Math.max(topPad - SEGMENT_BAR_BAND_TOP_INSET, 0) + contentHeight + gap;
}

// 设置页收带阈值（vp；决明拍板「滚过一带高才收」）：带高算式单源引 Theme 两常量
//（带内下移 8 + 框高 40 = 48，PageShell titleBarBottom 同款带），禁另算。消费方 = 页签形态
// HomeNavigation 与侧栏设置二级页 SettingsPageHost 两处滚动状态机（A 档接收带，规范-搜索交互 §6）
export const SETTINGS_BAND_HIDE_OFFSET: number = SEGMENT_BAR_BAND_TOP_INSET + SEGMENT_BAR_HEIGHT;

// 设置页收带状态机单源（onDidScroll 高频回调直调，两宿主共用）：offsetY > 48 ⇒ 收带、右上
// 搜索键出现；offsetY ≤ 24（阈值一半滞后带）⇒ 复位；中间区保持现态防 48 边界轻滚抖动。
// 返回下一态、不写状态——宿主只在变化时写 @State（重复写同值触发无意义重渲染，性能红线）
export function nextSettingsBandHidden(offsetY: number, currentHidden: boolean): boolean {
  if (offsetY > SETTINGS_BAND_HIDE_OFFSET) {
    return true;
  }
  if (offsetY <= SETTINGS_BAND_HIDE_OFFSET / 2) {
    return false;
  }
  return currentHidden;
}

@Component
export struct SearchTopBand {
  // 搜索词（@Link 与页面 @State 双向同步——$$ 绑定活到带上；PageTopSegmentBand selectedIndex
  // 同构。页面侧 onInput 内仍显式回写同值，$$ 万一不生效时兜底，三页原 SearchSection 同款双写。
  // openOnly 假框档不消费本词——挂载方传哑位 @State 仅满足 @Link 必传契约）
  @Link keyword: string;
  // 占位文案（三库页各异：名称或内容 / 名称、描述或正文 / 书名或条目内容；设置页假框档 =
  // 「搜索设置项」与二级页同词——页侧传入）
  placeholder: string = '';
  // 过滤上行（输入即回调——页面侧 applyFilter / refreshSearch 单源，本件不知有「过滤」这件事；
  // openOnly 假框档不可输入、永不回调）
  onInput: (value: string) => void = (value: string): void => {
  };
  // 假框档开关（true = 不可输入不可获焦假框，整框点击 onOpen 直达；默认 false = 真框，
  // 四库页消费形态不变——语义见文件头 openOnly 条）
  openOnly: boolean = false;
  // 假框档整框点击回调（openOnly 档必接——设置页两宿主传 pushSearch 直达搜索二级页）
  onOpen: () => void = (): void => {
  };
  // 带内下移量（vp）：与分段承载同默认 8 = 框底与带底齐平（带高 = inset + 40，bandParams 算式）
  inset: number = SEGMENT_BAR_BAND_TOP_INSET;
  // 沉浸光感档位（AppStorage 自订阅——「无」档归一 Material.empty，SearchPage 同链免逐页透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  build() {
    Row() {
      Column() {
        if (this.openOnly) {
          // 假框档：不绑 value（无可输入态）、focusable(false) 断获焦链（防点击弹键盘）；
          // 整框 onClick 直达二级页。几何与真框同源（40 高 + 100% 填充）；材质与真框同基准
          //（THICK 强档生效 REGULAR——2026-11-05 调薄笔全族统一，见文件头）
          Search({ placeholder: this.placeholder })
            .backgroundColor(Color.Transparent)
            .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
              this.immersiveLevel, false))
            .focusable(false)
            .width('100%')
            .height(40)
            .onClick((): void => {
              this.onOpen();
            })
        } else {
          // 真框档基准 THICK（强档生效 REGULAR——2026-11-05 调薄笔与假框同档统一，见文件头）
          Search({ value: $$this.keyword, placeholder: this.placeholder })
            .backgroundColor(Color.Transparent)
            .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
              this.immersiveLevel, false))
            // 宽单源在 Column（CARD_PANEL_WIDTH，分段承载同构）——Search 本体 100% 填充；
            // 首版 Search 与 Column 双挂 calc 百分比嵌套两次（框宽缩 32 不与行卡对齐）后改本形
            .width('100%')
            .height(40)
            .onChange((value: string): void => {
              this.onInput(value);
            })
        }
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .padding({ top: this.inset })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
