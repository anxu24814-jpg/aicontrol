// 键值井（表单重构 UI 提案 W1 项，决明拍板采纳）：职责一句话 =「一组键值对重复行的容器
// 单源」——同一组「键 → 值」只占**一个**视觉容器，不再是一行两个独立输入框 + 底部一条
// 通栏添加键。判据唯一来源 = docs/规范-列表卡片与组卡.md §4.12（改形态先读该节）。
// · 治什么：`请求头 / 自定义 Body / 参数 / 余额请求头` 四处都是「一行两个输入框 + 通栏添加键」，
//   同一组数据被拆成 N 个独立框，页面被切碎。井 = 整组共用一个浅灰容器，键｜竖线｜值 + 行尾圆删。
// · 判据：一组「键 → 值」重复行**≥1 行恒用井**，不因只有一行就退化成散框（沿 §1.1「数据行组卡
//   行数由数据决定，不换形」判例）。不是键值对的重复行（如「时段 → 起始/结束」三元）不套井。
// · 行键纪律（硬红线，源头上踩过）：行的键必须绑到**值对象本身**（本件用私有 Map<对象引用, uid>
//   懒分配），**不得用下标**——删中间行后余行 key 不变会让 TextInput 复用显示旧行内容、onChange
//   闭包捕获已移出数组的旧对象，编辑丢失且保存落库与 UI 不一致（ProviderHeadersPanel /
//   BalanceHeadersCard 头注释同款前科）。HeaderPair 是共享 wire 类型且 serializeHeaderPairs
//   整体 JSON.stringify 落库，**不得在类型上加 uid 字段**（会随保存写进库列），故只能走组件私有 Map。
// · 井内输入不套输入井：行内 TextInput / TextArea 背景恒透明——井底 + 输入井底双层会出灰斑；
//   焦点态不自绘（走官方默认焦点表现，井容器不加 focus 描边）。★ 配套约束「内距不能为 0」
//  （真机反馈「光标被切成弧形」实锤）：官方输入组件自带圆角，背景刷透明只是去掉灰块、组件
//   仍按自己圆角裁内容，内距全 0 时文字与光标起点落在弧线里——故左右输入内距恒 10（井容器
//   左 6 + 输入左 10 = 16，与卡内其他内容左缘对齐），上下 4。刷透明只解决观感，内距才解决裁切。
// · 两种行型（同一口井，不是两种控件）：
//   ① 单行行型（请求头 / 参数 / 余额头）= 键 39% ｜ 1vp 竖线 ｜ 值 + 行尾圆删，行高 40；
//   ② 多行行型（自定义 Body 的 JSON 值）= 上排「键 + 圆删」、下排值 TextArea——值本身需要多行
//      编辑，塞进 40vp 单行会毁掉长 JSON 的可用性；容器仍是同一口井。
// · 添加行：**井外独立一行**（真机反馈「把蓝键移出来」——原在井底读作「井的一个格子」且切断
//   容器感；移出后井是纯数据容器、添加键是卡内推进键）。键形制 = 行内文字键四件套的**淡彩
//   次级档**（fallbackButton*Tinted，字色即主蓝），与全工程「添加」族同档——**不新开无底彩字键**
//   （无底彩字键是已否决形态，见 docs/规范-行内按钮与光感.md §1）；与井间距 8。
// · 井底 = `Theme.wellBg`（与 fallbackGrayBg 分开单源：那个是全站灰键底，同一灰度在卡内大
//   面积上读作脏灰）+ 0.5vp `cardBorderColor` 描边交代边界——不靠灰度硬撑容器感。
// · 不加第 N 层嵌套（井里再嵌井）、不在井内放除「键 / 值 / 删」以外的控件、不给井加投影。
// · 单源：本件是唯一实现；后续消费方按同一接口接入（禁各自再写一套）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../common/providers/AiTypes';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../common/AppPreferences';
import { cardBorderColor, wellBg } from '../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBgTinted, fallbackButtonFontTinted,
  fallbackButtonMaterialTinted, fallbackButtonStateEffect
} from '../common/ImmersiveLevel';

// 井内单行行高（vp；规范 §4.12「行高 36~40」取上限——TextInput 官方默认高约 40，
// 取同值使输入框与行同高、不产生竖向留白）
const WELL_ROW_HEIGHT: number = 40;
// 键列占比（%）：键名多为短标识、值常为长串，键窄值宽；39% 为提案原值
const KEY_COL_PERCENT: string = '39%';
// 键值之间的竖向分隔线高（vp）：行高 40 的 40% = 16，读作「分隔」而非「分割整行」
const WELL_DIVIDER_HEIGHT: number = 16;
// 行尾圆删键热区（vp）：28 = 官方最小触控区下限内（图标 16 + 两侧 6）
const WELL_DELETE_SIZE: number = 28;
// 多行行型的值区高度（vp）：约 3 行 JSON 文本，再长可内部滚动
const WELL_MULTILINE_VALUE_HEIGHT: number = 76;

@Component
export struct KeyValueWell {
  // 键值行数组（父页 / 卡内 @State 持有，@Link 双向直写——落库时机仍归调用方，本件不碰 IO）
  @Link rows: HeaderPair[];
  // 键输入占位（两处文案不同：请求头「Header 名，例如 X-Api-Source」/ Body「Body 键，顶层字段名」）
  keyPlaceholder: string = '';
  // 值输入占位
  valuePlaceholder: string = '';
  // 添加行文案（含前置＋号，由调用方给全：'＋ 添加请求头'）
  addLabel: string = '';
  // 键 / 值输入长度上限（输入有界红线；两处不同——Body 的 JSON 值放宽容纳对象形态）
  keyMaxLength: number = 100;
  valueMaxLength: number = 500;
  // 行型开关：false = 单行行型（键｜竖线｜值）；true = 多行行型（键行 + 值 TextArea）
  multiline: boolean = false;
  // 值按密文输入（单行行型；官方密码键盘 + 显隐眼）——头值 / 密钥一类敏感值用；
  // 缺省 false = 明文（请求头里也有非敏感值，不该一律打码）
  valueSecret: boolean = false;
  // 空态提示（井内一行灰字；空串 = 不显示——调用方无空态文案时给 ''）
  emptyHint: string = '';
  // ── 行级状态标注（@Prop 数组 = 父侧整组替换即刷）──
  // 场景：编辑态回填行的「值不回显」三态（已保存 / 值缺失 / 未设置）必须逐行显示，否则用户
  // 无从判断「留空保持原值」是否还有值可保。本件只负责**显示**，判据与文案仍归调用方。
  // 传空数组 = 全无标注（多数消费面即此）。
  @Prop rowMark: string[] = [];
  // 行级标注是否走警示色（下标对齐 rowMark；越界按 false）
  @Prop rowMarkWarn: boolean[] = [];
  // 行删除后的伴随回调（可选）：本件已自行 splice(rows)，调用方的平行数组在此同步裁剪；
  // MCP 编辑页的 rowFromDb / rowHasAssetValue / oldValues 三组即此用法
  onRowRemoved: (index: number) => void = (index: number): void => {
  };
  // 添加行（可选）：默认实现 = 尾部追加空行（空行保存时由调用方丢弃，不在这里拦，允许先填
  // 一半再补）。调用方给了自己的实现就由调用方负责追加——需要「上限拦截 + toast」这类自定义
  // 逻辑时用（MCP 请求头 ≤5 组即此用法；本件不内置上限，各域上限单源在各自常量）
  onAddRow: () => void = (): void => {
    const blank: HeaderPair = { k: '', v: '' };
    this.rows.push(blank);
  };
  // 任一格编辑之后（可选）：占位自动发现一类「改一个值要重算别处派生」的消费面用
  //（HttpTemplatePage 的 syncParamDiscover）；缺省空实现
  onRowEdited: () => void = (): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（井底 wellBg 随档叠 alpha——即时面显式订阅，档位变化即刷；与卡底同源，
  // 见 Theme.alphaHexPrefix 注释）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 行键 uid 仓（对象引用 → 运行时自增 id；Map 随组件生命周期释放，行删除遗留条目个位数级
  // 不清理——表单行有界。键纪律见头注释）
  private rowUids: Map<HeaderPair, number> = new Map();
  private rowUidSeq: number = 0;

  private uidOf(pair: HeaderPair): number {
    const known: number | undefined = this.rowUids.get(pair);
    if (known !== undefined) {
      return known;
    }
    this.rowUidSeq++;
    this.rowUids.set(pair, this.rowUidSeq);
    return this.rowUidSeq;
  }

  private removeRow(index: number): void {
    this.rows.splice(index, 1);
    this.onRowRemoved(index);
  }

  // 行级标注（越界 / 空数组 → ''；调用方给几个就显示几个）
  private markOf(index: number): string {
    return index < this.rowMark.length ? this.rowMark[index] : '';
  }

  private markWarnOf(index: number): boolean {
    return index < this.rowMarkWarn.length ? this.rowMarkWarn[index] : false;
  }

  // 井容器底（井与空态同源；随卡底透明度档）
  private wellBgColor(): string {
    return wellBg(this.appColorMode, this.cardAlphaLevel);
  }

  // 行尾圆删键（无底 TEXTUAL 图标键——行内图标键档，禁垫四件套，见规范 §1 第 1 行）
  @Builder
  DeleteKey(index: number) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .width(WELL_DELETE_SIZE)
    .height(WELL_DELETE_SIZE)
    .onClick((): void => {
      this.removeRow(index);
    })
  }

  // 单行行型：键 39% ｜ 竖线 ｜ 值 ｜ 圆删（行级标注存在时，行下方追加一行 11fp 小字）
  @Builder
  SingleLineRow(pair: HeaderPair, index: number) {
    Column({ space: 2 }) {
      Row() {
        TextInput({ placeholder: this.keyPlaceholder, text: pair.k })
          .maxLength(this.keyMaxLength)
          .fontColor($r('sys.color.font_secondary'))
          .backgroundColor(Color.Transparent)
          // 左 10 让文字与光标出离自身圆角弧（见头注释），井容器左 6 合计 16 与卡内左缘对齐
          .padding({ left: 10, right: 6 })
          .width(KEY_COL_PERCENT)
          .onChange((value: string): void => {
            pair.k = value;
            this.onRowEdited();
          })
        // 键值分隔竖线（cardBorderColor 同族——与卡内分割线同色同源，深浅自动跟随）
        Column()
          .width(1)
          .height(WELL_DIVIDER_HEIGHT)
          .backgroundColor(cardBorderColor(this.appColorMode))
        TextInput({ placeholder: this.valuePlaceholder, text: pair.v })
          .type(this.valueSecret ? InputType.Password : InputType.Normal)
          .showPasswordIcon(this.valueSecret)
          .maxLength(this.valueMaxLength)
          .backgroundColor(Color.Transparent)
          .padding({ left: 10, right: 4 })
          .layoutWeight(1)
          .onChange((value: string): void => {
            pair.v = value;
            this.onRowEdited();
          })
        this.DeleteKey(index)
      }
      .width('100%')
      .height(WELL_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
      // 行级状态标注（非明文状态，如「已保存 / 值缺失」）：值缺失走系统警示色，其余走次要字色
      if (this.markOf(index) !== '') {
        Text(this.markOf(index))
          .fontSize(11)
          .fontColor(this.markWarnOf(index) ? $r('sys.color.ohos_id_color_warning') :
            $r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 10, right: 36, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 多行行型：上排「键 + 圆删」、下排值 TextArea（容器仍是同一口井）
  @Builder
  MultiLineRow(pair: HeaderPair, index: number) {
    Column({ space: 2 }) {
      Row() {
        TextInput({ placeholder: this.keyPlaceholder, text: pair.k })
          .maxLength(this.keyMaxLength)
          .fontColor($r('sys.color.font_secondary'))
          .backgroundColor(Color.Transparent)
          .padding({ left: 10, right: 6 })
          .layoutWeight(1)
          .onChange((value: string): void => {
            pair.k = value;
            this.onRowEdited();
          })
        this.DeleteKey(index)
      }
      .width('100%')
      .height(WELL_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
      TextArea({ placeholder: this.valuePlaceholder, text: pair.v })
        .maxLength(this.valueMaxLength)
        .height(WELL_MULTILINE_VALUE_HEIGHT)
        .width('100%')
        .backgroundColor(Color.Transparent)
        // ★ 上下留 4：原四向全 0 时文字直接顶到 TextArea 自带圆角弧线上（背景刷透明后弧线
        // 仍在），首行与末行被读作「被切」；左右 10/4 与单行行型的键值同缘
        .padding({ left: 10, right: 4, top: 4, bottom: 4 })
        .onChange((value: string): void => {
          pair.v = value;
          this.onRowEdited();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 8 })
  }

  build() {
    // 结构 = 上「井」（纯数据容器）+ 下「添加键」（推进动作，井外独立一行）。两件间距 8；
    // 井内不再有任何按钮行之外的元素，读取关系 = 「这些是我已有的键值」/「这里再加一条」。
    Column({ space: 8 }) {
      // ── 井：行区（内距 2/2/12/6）+ 灰底 + 描边 ──
      Column() {
        if (this.rows.length === 0 && this.emptyHint !== '') {
          Text(this.emptyHint)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ top: 10, bottom: 10 })
        }
        ForEach(this.rows, (pair: HeaderPair, index: number) => {
          if (this.multiline) {
            this.MultiLineRow(pair, index)
          } else {
            this.SingleLineRow(pair, index)
          }
        }, (pair: HeaderPair): string => 'kv' + this.uidOf(pair))
      }
      .width('100%')
      // ★ 内距 4/6/12/8（真机反馈「第二排圆角截断文字」修正）：底部 6 + 行高 40 内文字居中
      // 留的 12 = 18 > 井圆角 12，末排彻底出弧；右侧 8 同理护住行尾圆删键（宽 28、贴右缘）
      .padding({ top: 4, bottom: 6, left: 6, right: 8 })
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.wellBgColor())
      .borderRadius(12)
      // 0.5vp 发丝描边：井底取浅灰后靠灰度撑不住边界（#F1F3F5 vs 白卡仅 1.11），描边是
      // 容器的「边」而非「阴影」——与 §1.4 否决的抬升卡投影无关
      .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })

      // ── 添加键（井外，全宽；键形制 = 行内文字键淡彩次级档）──
      Button(this.addLabel)
        .fontSize(14)
        // 左右内距护住胶囊两端弧：官方 Button 为 Capsule 形（圆角 = 高/2），长标签在窄屏
        // 或系统字号放大时两端会顶到弧线——内距是布局属性，不改官方形状
        .padding({ left: 12, right: 12 })
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .width('100%')
        .onClick((): void => {
          this.onAddRow();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
