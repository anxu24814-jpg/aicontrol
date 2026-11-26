// 模型价格卡（费用估计）：输入/缓存输入/输出三价 + 谷时开关与谷时价（一套谷时价 + 段
// 列表，每段自带起止与适用周几）。纯草稿编辑 + 回调上行——状态归属宿主页（保存链消费
// onDraftChange 上行的序列化草稿）；结构与解析单一来源 = common/store/CostStatsCalc.ets
//（本卡只产草稿不落库不解析脏值）。说明小字置于操作行上方（宪法「功能设置卡布局次序」
// 条）；文案过「面向用户文案写作规约」；价格单位 = 元/百万 tokens。
// 折叠（决明指令）：collapsible = true 时标题行可点切换收起/展开（收起只留主副标题，形制
// 照 `docs/规范-列表卡片与组卡.md` §4.2 + animateTo 动画，见 FOLD_ANIM_MS）；收起态
// @StorageLink 绑 PREF_PRICE_CARD_COLLAPSED_KEY 持久化（决明要求「收起一次、以后都是收起」，
// 有意偏离 §4.2「不持久化」口径）；标题行不带按压蒙层（裸 Row + .onClick——折叠类卡整卡
// 非热区）。价格模板编辑页复用本卡但不传 collapsible（恒展开）。套用刷新通道见 applyJson 注释。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  ModelPriceConfig, ValleySegment, VALLEY_SEGMENT_MAX,
  parsePriceConfig, serializePriceConfig
} from '../../common/store/CostStatsCalc';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY, PREF_PRICE_CARD_COLLAPSED_KEY } from '../../common/AppPreferences';
import {
  CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor, selectChipBg,
  selectChipBorderColor, selectChipTextColor, wellBg, CARD_RADIUS
} from '../../common/Theme';

// 价格草稿上行结构：json = 序列化草稿（'' = 全空未配置）；complete = 草稿完整（输入/
// 输出价成对、谷时段至少选一天且三价齐备、非空项均非负）——父保存链对 complete=false
// 整体拦截 toast，防半份配置静默落库；hint = 拦截原因文案（'' = 未拦截）
export interface PriceDraftState {
  json: string;
  complete: boolean;
  hint: string;
}

// 谷时段草稿：segId 与 rev 仅 UI 用（不入库）——段行 ForEach 键的身份与**版本**两成分
//（rev = 纪元号每改自增，细则见 build 内键注释）；start/end = 草稿最近选值（allDay 时
// 序列化统一写 00:00/00:00，草稿值保留，关掉全天即回原时段）；days 沿用显示序布尔数组
interface ValleySegDraft {
  segId: number;
  rev: number;
  start: string;
  end: string;
  allDay: boolean;
  days: boolean[];
}

// 谷时日多选码表（显示序一~日；码 = Date.getDay() 口径 0=周日…6=周六——与
// CostStatsCalc.ValleySegment.days 同口径）
const WEEKDAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const WEEKDAY_CODES: number[] = [1, 2, 3, 4, 5, 6, 0];

// 新建谷时段默认值；全天段的库内落点 = 起止相等
const SEG_START_DEFAULT: string = '00:30';
const SEG_END_DEFAULT: string = '08:30';
const ALLDAY_HM: string = '00:00';

// 折叠展开动画时长（官方 FAQ faqs-arkui-769 折叠示例同值 300ms；curve 取同族先例
// EaseInOut。★ ChatToolCard 原 animateBody 先例已随显式高度链真机修复退役）
const FOLD_ANIM_MS: number = 300;

// 价格输入行入参：**按引用传递**（真机坑：值参快照下 TextInput.text 恒取首帧值，手输走
// 组件内部缓冲照常显示 →「敲得进去、回填看不见」——保存重进后正常价三栏空白）。官方
//《@Builder装饰器》规则：按值传递时状态变量变化不引起 @Builder 内 UI 刷新；按引用传递
// 只在「单参数 + 直传对象字面量」时生效，多参数不支持。★ 类型用 class（官方样例形制）；
// ★ 调用点必须直传对象字面量（传变量或加第二个参数都退回按值传递，sse-assert 留钉）；
// 字段默认值仅因 ArkTS 类字段须初始化——字面量仍须补齐四字段（缺一编译错），无静默失败面。
class PriceFieldParam {
  label: string = '';
  text: string = '';
  placeholder: string = '';
  onEdit: (value: string) => void = (): void => {
  };
}

// 价格文本 → 非负有限数（trim 后空串/非数字/负数/非有限值回 null = 未填或非法——两种态由
// 调用方按「原文非空 && 结果 null」区分）
function toPriceNumber(text: string): number | null {
  const trimmed: string = text.trim();
  if (trimmed === '') {
    return null;
  }
  const n: number = Number(trimmed);
  if (!Number.isFinite(n) || n < 0) {
    return null;
  }
  return n;
}

// 两位补零（TimePickerDialog 产出的 hour/minute 是数字——'HH:mm' 形态统一在本卡收敛）
function twoDigits(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

// 'HH:mm' → 当日 Date（TimePickerDialog selected 入参；拆段构造防字符串解析时区坑）
function hmToDate(hm: string): Date {
  const parts: string[] = hm.split(':');
  const d: Date = new Date();
  d.setHours(Number(parts[0]), Number(parts[1]), 0, 0);
  return d;
}

@Component
export struct ModelPriceCard {
  // 行 price_config 原文（编辑态异步加载后由父赋值；@Watch 触发草稿回填——aboutToAppear
  // 只覆盖首帧）。★ 通道必须 @Link：本卡挂 PageShell.content（@BuilderParam）内，@Prop
  // 下发热点属坑16 家族（两度真机实锤「异步就绪后首帧冻结」），@Link 是规范 §3 指定正解。
  // 本卡对 priceJson 只读不写（单向语义靠约定）
  @Link @Watch('onJsonChange') priceJson: string;
  // 套用刷新通道（载荷 + 自增纪元两参，缺一不可）：applyJson = 待套用价格 JSON（宿主先写
  // 它）；applyTick = 自增纪元（宿主再自增触发 @Watch → onApplyTick → 整组回填）。★ 为何
  // 不能直接赋 priceJson：用户手改草稿不写回它——「套模板 A → 手改成 B → 再点模板 A」时
  // priceJson 同值 A→A，@Watch 不触发 = 静默失败；自增纪元保证键必变必回填。★ 禁改用
  // AppStorage tick 广播键（坑16 家族：push 页内不触发）——@Link + @Watch 是已真机验证通道。
  @Link applyJson: string;
  @Link @Watch('onApplyTick') applyTick: number;
  // 草稿上行回调（任一字段变更后携最新序列化草稿与完整性上行；父持最新值供保存链）
  onDraftChange: (draft: PriceDraftState) => void = () => {
  };
  // 折叠能力开关（默认 false = 恒展开无箭头，价格模板编辑页）：true = 标题行带箭头整行
  // 可点（模型编辑页——五卡同列，谷时多段时本卡占屏很高）。★ 折叠纯 UI 态与草稿链零耦合
  // ——收起期间输入行虽销毁，值仍在卡内 @State（onChange 逐字符上行），展开重建即回填
  collapsible: boolean = false;
  @State private inputText: string = '';
  @State private cachedText: string = '';
  @State private outputText: string = '';
  @State private valleyOn: boolean = false;
  // 谷时段列表（@State 整组替换刷新：增减/字段变更都换新数组新对象，不原地改）
  @State private valleySegs: ValleySegDraft[] = [];
  @State private vInputText: string = '';
  @State private vCachedText: string = '';
  @State private vOutputText: string = '';
  // 收起态：@StorageLink 绑持久键即写即落盘（persistProp 已注册）——重进/重启保持（决明
  // 报障「收起后无法记忆」的修复）；缺省 false = 默认展开零回归。★ @StorageLink 而非
  // @State + 手动写：双向语义天然成对，挂 @BuilderParam content 内属规范 §3 正解通道族；
  // 非 private（@StorageLink 先例同形）
  @StorageLink(PREF_PRICE_CARD_COLLAPSED_KEY) collapsed: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（价格瓦片底 = wellBg 随档叠 alpha——与键值井/灰面同源）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 内容区光感双态（时段起止两键 = 内容区行内文字键，走 fallbackButton* 四件套——
  // 宪法「行内操作按钮官方形制」条；弹窗/面板豁免区才用 resolvedButton*）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 段身份发号（普通成员——不驱动 UI，只有 segId 值本身进键）
  private nextSegId: number = 1;
  // 段纪元发号（普通成员——同上；每次克隆自增 = 该段的键必变，行内容随之重建刷新）
  private nextSegRev: number = 1;

  aboutToAppear(): void {
    this.refillFromJson(this.priceJson);
  }

  // @Watch 入口：行数据晚到（父异步赋 priceJson）→ 草稿回填
  private onJsonChange(): void {
    this.refillFromJson(this.priceJson);
  }

  // 套用纪元自增 → 载荷非空才整组回填（模板编辑页占位恒 '' 不触发；回填后 emitDraft 上行）
  private onApplyTick(): void {
    if (this.applyJson !== '') {
      this.refillFromJson(this.applyJson);
    }
  }

  // 新段（添加键与空配置回填共用；每次现场发号，重填不复用旧号——键恒唯一）
  private newSeg(): ValleySegDraft {
    const seg: ValleySegDraft = {
      segId: this.nextSegId, rev: this.nextSegRev, start: SEG_START_DEFAULT,
      end: SEG_END_DEFAULT, allDay: false, days: [true, true, true, true, true, true, true]
    };
    this.nextSegId++;
    this.nextSegRev++;
    return seg;
  }

  // 段深拷贝（days 为引用类型，必须同步复制——否则新旧段共享同一数组）。★ rev 在此自增：
  // 本卡所有段内改动都经 cloneSeg → 键必变 → 行内属性（chips 勾选态/全天态/起止标签）随之
  // 重建刷新；漏走 cloneSeg 的改动路径会「点了没反应」（见 build 内键注释）
  private cloneSeg(src: ValleySegDraft): ValleySegDraft {
    const seg: ValleySegDraft = {
      segId: src.segId, rev: this.nextSegRev, start: src.start, end: src.end,
      allDay: src.allDay, days: src.days.slice()
    };
    this.nextSegRev++;
    return seg;
  }

  // 换段（整组替换刷新：其余段保持原对象引用，仅目标位换新对象）
  private replaceSeg(index: number, seg: ValleySegDraft): void {
    const next: ValleySegDraft[] = [];
    for (let i = 0; i < this.valleySegs.length; i++) {
      next.push(i === index ? seg : this.valleySegs[i]);
    }
    this.valleySegs = next;
    this.emitDraft();
  }

  // 段列表回填：days 按显示序码表还原（缺省 = 全选）；起止相等 = 全天形态（回填即点亮
  //「全天」键）；起止值原样保留（不抹成 00:00~00:00，打开编辑页零漂移）
  private refillValleySegs(segments: ValleySegment[]): void {
    const drafts: ValleySegDraft[] = [];
    for (const seg of segments) {
      const codes: number[] = seg.days !== undefined ? seg.days : WEEKDAY_CODES;
      const days: boolean[] = WEEKDAY_CODES.map((code: number): boolean => codes.includes(code));
      drafts.push({
        segId: this.nextSegId, rev: this.nextSegRev, start: seg.start, end: seg.end,
        allDay: seg.start === seg.end, days: days
      });
      this.nextSegId++;
      this.nextSegRev++;
    }
    this.valleySegs = drafts;
  }

  // 行 price_config → 草稿域（未配置 = 全空草稿 + 一段默认谷时）。★ 回填即上行草稿：否则
  // 父侧 priceDraft 停在初值空串，编辑已配置价格的模型不碰价格卡直接保存会把库中价格清空
  private refillFromJson(json: string): void {
    const cfg: ModelPriceConfig | null = parsePriceConfig(json);
    if (cfg === null) {
      this.inputText = '';
      this.cachedText = '';
      this.outputText = '';
      this.valleyOn = false;
      this.valleySegs = [this.newSeg()];
      this.vInputText = '';
      this.vCachedText = '';
      this.vOutputText = '';
      this.emitDraft();
      return;
    }
    this.inputText = '' + cfg.input;
    this.cachedText = cfg.cachedInput !== undefined ? '' + cfg.cachedInput : '';
    this.outputText = '' + cfg.output;
    this.valleyOn = cfg.valley !== undefined;
    if (cfg.valley !== undefined) {
      this.refillValleySegs(cfg.valley.segments);
      this.vInputText = '' + cfg.valley.input;
      this.vCachedText = cfg.valley.cachedInput !== undefined ? '' + cfg.valley.cachedInput : '';
      this.vOutputText = '' + cfg.valley.output;
    }
    this.emitDraft();
  }

  // 草稿 → 序列化上行（完整性与结构单源在 CostStatsCalc；拦截分支各带 hint 供保存链
  // toast 直显）：三价全空 = 未配置（''）；非空项非法或输入输出不成对 = incomplete；
  // 谷时同构 + 每段至少一天（拍板：全不选拦截，防把谷价整个关掉还不自知）
  private emitDraft(): void {
    const input: number | null = toPriceNumber(this.inputText);
    const cached: number | null = toPriceNumber(this.cachedText);
    const output: number | null = toPriceNumber(this.outputText);
    const mainEmpty: boolean = this.inputText.trim() === '' && this.cachedText.trim() === '' &&
      this.outputText.trim() === '';
    if (mainEmpty) {
      // 主三价全空 = 未配置（谷时残值不单独成配置——serialize 侧无主价不成 JSON）。★ 但
      // 谷时开关开着且谷时三价有值时**拦截**（决明拍板）：静默发空 JSON 会把用户刚填的
      // 谷价配置无声清掉（违 P0-1「禁止静默失败」）；hint 给两条出路，不堵死「就是要清空」
      if (this.valleyOn && (this.vInputText.trim() !== '' || this.vCachedText.trim() !== '' ||
        this.vOutputText.trim() !== '')) {
        this.onDraftChange({ json: '', complete: false,
          hint: '未填写输入价格与输出价格时谷时优惠价不生效。若要清空价格配置，请关闭「谷时优惠价」，或把谷时各价一并清空' });
        return;
      }
      this.onDraftChange({ json: '', complete: true, hint: '' });
      return;
    }
    // 非法或输入输出不成对 = 拦截态
    if ((this.inputText.trim() !== '' && input === null) ||
      (this.cachedText.trim() !== '' && cached === null) ||
      (this.outputText.trim() !== '' && output === null) ||
      input === null || output === null) {
      this.onDraftChange({ json: '', complete: false,
        hint: '价格须为非负数字，输入价格与输出价格须同时填写' });
      return;
    }
    const cfg: ModelPriceConfig = { input: input, output: output };
    // 显式 0 = 缓存免费（2026-09-11 决明拍板放宽；留空才回退输入价——null 仍不挂键）
    if (cached !== null) {
      cfg.cachedInput = cached;
    }
    let complete: boolean = true;
    let hint: string = '';
    if (this.valleyOn) {
      // 全天段统一落 00:00/00:00（兼容旧值）；其余段用草稿选值；days = 显示序布尔 → getDay 码数组
      const segments: ValleySegment[] = [];
      let daysMissing: boolean = false;
      for (const seg of this.valleySegs) {
        const dayCodes: number[] = WEEKDAY_CODES.filter((_code: number, index: number): boolean =>
          seg.days[index]);
        if (dayCodes.length === 0) {
          daysMissing = true;
        }
        if (seg.allDay) {
          segments.push({ start: ALLDAY_HM, end: ALLDAY_HM, days: dayCodes });
        } else {
          segments.push({ start: seg.start, end: seg.end, days: dayCodes });
        }
      }
      const vInput: number | null = toPriceNumber(this.vInputText);
      const vCached: number | null = toPriceNumber(this.vCachedText);
      const vOutput: number | null = toPriceNumber(this.vOutputText);
      if (daysMissing) {
        complete = false;
        hint = '每个谷时段须至少选择一天';
      } else if ((this.vInputText.trim() !== '' && vInput === null) ||
        (this.vCachedText.trim() !== '' && vCached === null) ||
        (this.vOutputText.trim() !== '' && vOutput === null) ||
        vInput === null || vOutput === null) {
        complete = false;
        hint = '谷时输入与输出价格须同时填写，且为非负数字';
      } else {
        cfg.valley = { input: vInput, output: vOutput, segments: segments };
        if (vCached !== null) {
          cfg.valley.cachedInput = vCached;
        }
      }
    }
    this.onDraftChange({ json: complete ? serializePriceConfig(cfg) : '', complete: complete,
      hint: hint });
  }

  // 谷时日勾选（跨午夜段周几按段开始日算——判定侧语义）
  private toggleSegDay(index: number, dayIndex: number): void {
    const next: ValleySegDraft = this.cloneSeg(this.valleySegs[index]);
    next.days[dayIndex] = !next.days[dayIndex];
    this.replaceSeg(index, next);
  }

  // 「全天」键（选项类胶囊，与周几 chips 同族形制）。★ 关闭时回落守卫：起止相等仍是
  // 全天语义，原样留着 =「界面全天关了、库里还是全天」，故关闭时回落到默认时段
  private toggleSegAllDay(index: number, on: boolean): void {
    const next: ValleySegDraft = this.cloneSeg(this.valleySegs[index]);
    next.allDay = on;
    if (!on && next.start === next.end) {
      next.start = SEG_START_DEFAULT;
      next.end = SEG_END_DEFAULT;
    }
    this.replaceSeg(index, next);
  }

  // 添加/删除段（上限与末段守卫：键置灰之外再加一道，防误触与将来键形制改动穿透）
  private addSeg(): void {
    if (this.valleySegs.length >= VALLEY_SEGMENT_MAX) {
      return;
    }
    const next: ValleySegDraft[] = [];
    for (const seg of this.valleySegs) {
      next.push(seg);
    }
    next.push(this.newSeg());
    this.valleySegs = next;
    this.emitDraft();
  }

  private removeSeg(index: number): void {
    if (this.valleySegs.length <= 1) {
      return;
    }
    const next: ValleySegDraft[] = [];
    for (let i = 0; i < this.valleySegs.length; i++) {
      if (i !== index) {
        next.push(this.valleySegs[i]);
      }
    }
    this.valleySegs = next;
    this.emitDraft();
  }

  // 段起/止选择（UIContext 形态 TimePickerDialog——全局版自 API 18 @deprecated 指向
  // UIContext.showTimePickerDialog；useMilitaryTime 固定 true，d.ts 保证 hour[0-23]/
  // minute[0-59] → 补零恒产合法 'HH:mm'）
  private pickSegTime(index: number, isStart: boolean): void {
    const seg: ValleySegDraft = this.valleySegs[index];
    this.getUIContext().showTimePickerDialog({
      selected: hmToDate(isStart ? seg.start : seg.end),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const hm: string = twoDigits(value.hour) + ':' + twoDigits(value.minute);
        // 取当前态而非弹窗前快照（弹层期间数组若被换过，克隆旧对象会把那笔改动吃掉）
        const next: ValleySegDraft = this.cloneSeg(this.valleySegs[index]);
        if (isStart) {
          next.start = hm;
        } else {
          next.end = hm;
        }
        // 选成同一时刻 = 全天形态 → 同步点亮「全天」键，防「界面非全天、库里判成全天」错位
        if (next.start === next.end) {
          next.allDay = true;
        }
        this.replaceSeg(index, next);
      }
    });
  }

  // 收起判定（未启用折叠时恒 false；箭头朝向与卡体条件渲染同源本判据，不得各写一份）
  private isCollapsed(): boolean {
    return this.collapsible && this.collapsed;
  }

  // 价格瓦片：浅灰圆角块内「标签 + 大字数值 + 单位」（2026-10-25 批 2，形制照决明参考图）。
  // ★ 瓦片给底、输入框刷透明：官方 TextInput 本身就是「灰底圆角壳」，瓦片把同一层壳抬高
  // 一级让标签与单位落进同壳（不新增第二层描边/阴影）；井底 wellBg 与键值井同源随档联动。
  // ★ 参数按引用传递（单一对象字面量，见 PriceFieldParam 注释）——勿改回多参值传（值参
  // 首帧快照，回填不刷新 =「保存重进后三栏空白」）。
  @Builder
  PriceField(param: PriceFieldParam) {
    Column({ space: 4 }) {
      Text(param.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 4 }) {
        TextInput({ placeholder: param.placeholder, text: param.text })
          .type(InputType.NUMBER_DECIMAL)
          // 壳在瓦片这一级（见上），输入框自身透明——两层灰会叠出脏斑
          .backgroundColor(Color.Transparent)
          // 上下内距归零 + 高 34（原 38 叠默认内距把 24fp 数字行盒裁底）；左右 2vp 防落进圆角裁切线
          .padding({ left: 2, right: 2, top: 0, bottom: 0 })
          .height(34)
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          // 占位是提示不是值：跟着 24fp 走会撑成主体，压回 14fp
          .placeholderFont({ size: 14 })
          .layoutWeight(1)
          .onChange((value: string): void => {
            param.onEdit(value);
          })
        Text('元')
          .fontSize(12)
          .fontColor(cardDescColor())
          // 底对齐 + 2vp 底距：与 24fp 数字的视觉底边齐平
          .margin({ bottom: 2 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(wellBg(this.appColorMode, this.cardAlphaLevel))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      // 标题行：collapsible 时行尾折叠箭头 + 整行可点切换；箭头 rotate 与卡体条件渲染同源
      // isCollapsed()（形制照规范 §4.2 组头折叠，展开 = 箭头朝上）。★ 标题行是裸 Row +
      // .onClick、不带按压蒙层（决明「模型价格也去」）：折叠类卡热区只在标题行、整卡非
      // 热区，蒙层与「整卡可点」观感不对位
      Row() {
        Text('模型价格')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        if (this.collapsible) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([cardDescColor()])
            .rotate({ angle: this.isCollapsed() ? 0 : 180 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        // 未启用折叠的宿主点击为 no-op。★ 切换包进 animateTo（官方 FAQ faqs-arkui-769 折叠
        // 示例做法；UIContext 形态，宪法禁全局 animateTo），高度与箭头旋转随之插值。★ FAQ
        // faqs-arkui-1400：布局类改变宽高的动画，内容直接到终点态——不随高度形变，观感以真机为准
        if (this.collapsible) {
          this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
            (): void => {
              this.collapsed = !this.collapsed;
            });
        }
      })
      // 说明小字置于输入行上方（宪法「功能设置卡布局次序」条）。★ 恒显示——收起态 =
      // 主副标题两行短卡；「缓存输入留空按输入价计」自占位挪到本行（三价栅格化后窄格放不下）
      Text('按服务商定价填写，单位为元每百万 tokens。缓存输入留空按输入价计。三价全空表示未配置，不计入费用估计。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 操作区（三价 + 谷时区）：收起态整体隐藏（草稿链零耦合——值仍在各 @State，展开重建即回填）
      if (!this.isCollapsed()) {
        // 三价并排（缓存输入留空语义在卡头说明小字）
        Row({ space: 8 }) {
          this.PriceField({
            label: '输入价格', text: this.inputText, placeholder: '例如 2',
            onEdit: (value: string): void => {
              this.inputText = value;
              this.emitDraft();
            }
          })
          this.PriceField({
            label: '缓存输入', text: this.cachedText, placeholder: '可选',
            onEdit: (value: string): void => {
              this.cachedText = value;
              this.emitDraft();
            }
          })
          this.PriceField({
            label: '输出价格', text: this.outputText, placeholder: '例如 8',
            onEdit: (value: string): void => {
              this.outputText = value;
              this.emitDraft();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        // 谷时开关行（Toggle 双态绑定 @State——非纯视觉，控制谷时配置区显隐）
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('谷时优惠价')
              .fontSize(16)
              .fontColor(cardTitleColor())
            Text('开启后可配置一段或多段低价时段，其余时间用上面的价格')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.valleyOn })
            .onChange((isOn: boolean): void => {
              this.valleyOn = isOn;
              this.emitDraft();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.valleyOn) {
          // 段行列表：每段一块两行——①「时段 N」+ 周几 chips + 行尾删除键（行内图标键：
          // SymbolGlyph 无底 TEXTUAL + font_secondary，宪法「行内操作按钮官方形制」条）；
          // ②「时间」+ 起止两键 + 「全天」胶囊（选项类，照周几 chips 同族形制，不接光感）
          // ★键 = segId + 纪元号 rev + 位序，三成分缺一不可（真机报障定稿——原写「segId +
          // 位序」时 chips 与「全天」点了没反应）：
          //  ①segId 保身份（段克隆替换后仍是同一行，不因引用变化丢行态）；
          //  ②rev 是**刷新通道**——行内属性读的是 ForEach 项参数 seg（普通对象，非 @State），
          //    键不变时框架复用组件不重跑 itemGenerator，行内属性全被冻住 =「点不动」；改一处
          //    就换一个 rev，键变 → 行重建 → 新值上屏（规范 §3「键变重建」主通道）；
          //  ③位序管位移——itemGenerator 闭包捕获的 index 不随数组变化重算，删中间段后后续段
          //    标签与增删回调整体错位（坑16 家族）。
          // ★ 新增段内改动路径必须经 cloneSeg（带上新 rev），否则该路径静默「点了没反应」
          ForEach(this.valleySegs, (seg: ValleySegDraft, index: number) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text('时段 ' + (index + 1))
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width(44)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(WEEKDAY_LABELS, (label: string, dayIndex: number) => {
                    Text(label)
                      .fontSize(13)
                      .fontColor(selectChipTextColor(seg.days[dayIndex], this.appColorMode))
                      // chips 几何对齐 ModelCapsCard 范式（12/12/6/6 + 圆角 14 + 间距 8/8）
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .backgroundColor(selectChipBg(seg.days[dayIndex], this.appColorMode))
                      .border({ width: 1, color: selectChipBorderColor(seg.days[dayIndex]) })
                      .margin({ right: 8, bottom: 8 })
                      .onClick((): void => {
                        this.toggleSegDay(index, dayIndex);
                      })
                  }, (label: string): string => label)
                }
                .layoutWeight(1)
                Button() {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(16)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .enabled(this.valleySegs.length > 1)
                .onClick((): void => {
                  this.removeSeg(index);
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              Row({ space: 8 }) {
                Text('时间')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width(44)
                if (!seg.allDay) {
                  Button(seg.start + ' 起')
                    .fontSize(14)
                    .fontColor(fallbackButtonFont(this.contentFallback, false))
                    .backgroundColor(fallbackButtonBg(this.contentFallback,
                      this.immersiveLevel, false))
                    .systemMaterial(fallbackButtonMaterial(this.contentFallback,
                      this.immersiveLevel, false))
                    .stateEffect(fallbackButtonStateEffect(this.contentFallback,
                      this.immersiveLevel))
                    .layoutWeight(1)
                    .onClick((): void => {
                      this.pickSegTime(index, true);
                    })
                  Button(seg.end + ' 止')
                    .fontSize(14)
                    .fontColor(fallbackButtonFont(this.contentFallback, false))
                    .backgroundColor(fallbackButtonBg(this.contentFallback,
                      this.immersiveLevel, false))
                    .systemMaterial(fallbackButtonMaterial(this.contentFallback,
                      this.immersiveLevel, false))
                    .stateEffect(fallbackButtonStateEffect(this.contentFallback,
                      this.immersiveLevel))
                    .layoutWeight(1)
                    .onClick((): void => {
                      this.pickSegTime(index, false);
                    })
                }
                Text('全天')
                  .fontSize(13)
                  .fontColor(selectChipTextColor(seg.allDay, this.appColorMode))
                      // 几何同周几 chips（单选项无 margin 不加）
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor(selectChipBg(seg.allDay, this.appColorMode))
                  .border({ width: 1, color: selectChipBorderColor(seg.allDay) })
                  .onClick((): void => {
                    this.toggleSegAllDay(index, !seg.allDay);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor(badgeBg(this.appColorMode))
            .alignItems(HorizontalAlign.Start)
          }, (seg: ValleySegDraft, index: number): string => 'vs' + seg.segId + '-' + seg.rev +
            '-' + index)
          // 上限说明置于按钮行**上方**（宪法「功能设置卡布局次序」：先说明后操作）
          if (this.valleySegs.length >= VALLEY_SEGMENT_MAX) {
            Text('最多添加 ' + VALLEY_SEGMENT_MAX + ' 个时段，删除后可再添加')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          // 添加时段（淡彩次级键；到上限置灰；上限引计算层常量，防「界面 6 段、解析 8 段」双源漂移）
          Button('添加时段')
            .fontSize(14)
            .fontColor(fallbackButtonFontTinted(this.contentFallback))
            .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
            .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback,
              this.immersiveLevel))
            .width('100%')
            .enabled(this.valleySegs.length < VALLEY_SEGMENT_MAX)
            .onClick((): void => {
              this.addSeg();
            })
          // 谷时价全段共用——先说明后操作，防「每段各配一套价」误读
          Text('以下价格对所有时段生效')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Row({ space: 8 }) {
            this.PriceField({
              label: '谷时输入', text: this.vInputText, placeholder: '例如 1',
              onEdit: (value: string): void => {
                this.vInputText = value;
                this.emitDraft();
              }
            })
            this.PriceField({
              label: '谷时缓存', text: this.vCachedText, placeholder: '可选',
              onEdit: (value: string): void => {
                this.vCachedText = value;
                this.emitDraft();
              }
            })
            this.PriceField({
              label: '谷时输出', text: this.vOutputText, placeholder: '例如 4',
              onEdit: (value: string): void => {
                this.vOutputText = value;
                this.emitDraft();
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
