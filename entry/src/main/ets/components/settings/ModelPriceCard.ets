// 模型价格卡（2026-09-10 费用估计，方案-费用估计-20260910；照 ModelCapsCard 域级拆分
// 先例自 ModelEditPage 拆出。2026-09-11 谷时多时段笔：谷时配置由「一套时段 + 适用周几」
// 扩为「一套谷时价 + 段列表」，每段自带起止与适用周几——段行列表形态见 build 内注释；
// 同日价格模板笔加套用刷新通道〔applyJson/applyTick 两 @Link，见成员区注释〕）：
// 输入/缓存输入/输出三价 + 谷时开关与谷时第二套价（时间选择 = 官方 TimePickerDialog·
// UIContext 形态）。纯草稿编辑 + 回调上行——状态归属宿主页（保存链消费
// onDraftChange 上行的序列化草稿，随标题栏勾键统一落库）。
// 结构与解析单一来源 = common/store/CostStatsCalc.ets（本卡只产草稿不落库不解析脏值）。
// 说明小字置于输入行上方（宪法「功能设置卡布局次序」条）；文案过「面向用户文案写作
// 规约」。价格单位 = 元/百万 tokens（人民币，美元计价服务商手算折算填入）。
// ★ 2026-09-17 决明指令「模型能力页价格卡加收起展开，展开态太长了，可收起为短卡，不显示
// 价格只展示主副标题」：卡头改标题行（标题 + 行尾折叠箭头）——collapsible = true 时整行可点
// 切换收起/展开，收起态只留主副标题两行，三价与谷时区整体条件渲染隐藏。折叠形制照
// `docs/规范-列表卡片与组卡.md` §4.2 组头折叠（条件渲染 + 箭头翻转 + animateTo 切换——原
// 「无动画、要动画另立调研」的旧口径已被同日折叠动画笔作废，见 FOLD_ANIM_MS 与标题行注释）。
// ★ 同日记忆笔（决明报障「收起状态保存后无法记忆」）：收起态由卡内
// @State 改 **@StorageLink 绑 PREF_PRICE_CARD_COLLAPSED_KEY 持久化**——此处有意偏离 §4.2
// 「展开态为页面级 @State，不持久化」口径，按决明的要求做到「收起一次、以后都是收起」。
// 价格模板编辑页复用本卡但**不传 collapsible**（恒展开：该页主用途即编辑价格，折叠无意义）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  ModelPriceConfig, ValleySegment, VALLEY_SEGMENT_MAX,
  parsePriceConfig, serializePriceConfig
} from '../../common/store/CostStatsCalc';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { PREF_PRICE_CARD_COLLAPSED_KEY } from '../../common/AppPreferences';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

// 价格草稿上行结构：json = 序列化草稿（'' = 全空未配置）；complete = 草稿完整（输入价
// 与输出价成对、开启谷时后每个谷时段至少选择一天且谷时三价齐备、所有非空项均为非负数字）
// ——父保存链对 complete=false 整体拦截 toast，防半份配置静默落库；hint = 拦截原因
//（complete=false 时子侧给出具体文案供保存链 toast 直显，'' = 未拦截）
export interface PriceDraftState {
  json: string;
  complete: boolean;
  hint: string;
}

// 谷时段草稿：segId 与 rev 仅 UI 用（不入库）——段行 ForEach 键的身份与**版本**两成分
//（见 build 内键注释：rev = 纪元号，每次改动自增，靠「键变重建」把行内属性刷新出来）；
// start/end = 草稿时间的最近选值（allDay 为真时序列化统一写 00:00/00:00，草稿值保留，
// 关掉全天即可回到原时段）；days 沿用显示序布尔数组
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

// 新建谷时的默认段（与旧版单段默认值一致，行为不变）；全天段的库内落点 = 起止相等
const SEG_START_DEFAULT: string = '00:30';
const SEG_END_DEFAULT: string = '08:30';
const ALLDAY_HM: string = '00:00';

// 折叠展开动画时长（2026-09-17 折叠动画笔；官方 FAQ faqs-arkui-769「如何实现简单列表折叠和
// 展开」示例同值 300ms；curve 取项目同族先例（ChatMessageItem.animateBody /
// ChatInputBar.setExpanded）的 EaseInOut）
const FOLD_ANIM_MS: number = 300;

// 价格输入行入参（**按引用传递**，2026-09-11 自「四参值参」改造——真机报障「设置谷价与正常
// 价，保存后重进正常价三栏空白、谷价还在」即本坑）：官方《@Builder装饰器：自定义构建函数》
// 参数传递规则逐字——①「按值传递时，状态变量的改变不会引起 @Builder 函数内的 UI 刷新」；
// ②「按引用传递只在传入一个参数且该参数直接传入对象字面量时生效，有多个参数时不支持」。值参
// 快照下 TextInput.text 恒取首帧值（此后用户手输走组件内部缓冲照常显示）→ **敲得进去、回填
// 看不见**；谷价三栏因在 if(valleyOn) 分支内、迟于 refill 才创建（创建时参数已是回填值）而幸免。
// ★ 参数类型用 class 而非 interface：官方样例一律以 class 承载按引用传递（照 2026-09-10
//   SearchEngineDetailPage.InlineBtnOpts 先例，不自行变体）；★ 调用点必须直传对象字面量（传
//   变量或加第二个参数都退回按值传递，sse-assert 留钉）；字段给默认值仅因 ArkTS 类字段须初始化
//   ——对象字面量仍须补齐四字段（缺一即编译错），故无「漏传 onEdit 致输入无效」的静默失败面。
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
  // 只覆盖首帧，行数据晚到靠本口）。★ 通道 = @Link（2026-09-11 费用估计全链路自检轮归正）：
  // 本卡挂在 PageShell.content（@BuilderParam）之内，宪法「UI 弹层与上下文一律 UIContext
  // 形态」同节的刷新黑名单明令「@BuilderParam content 内组件 @Prop 下发热点」——坑16 家族
  // 两度真机实锤（服务商卡徽章、思考档位选项集「conn 异步就绪后首帧冻结」）；@Link 是规范
  // §3 指定正解，本仓同位置先例 = StatGrid / SegmentBar / SliderValueCard。本卡对 priceJson
  // 只读不写（单向语义靠约定，非 @Prop 的框架强制）
  @Link @Watch('onJsonChange') priceJson: string;
  // 套用刷新通道（2026-09-11 价格模板笔；载荷 + 自增纪元两参，缺一不可）：
  // · applyJson = 待套用的价格 JSON 串（宿主「套模板」时先写它）；applyTick = 自增纪元
  //   （宿主再自增它触发本卡 @Watch → onApplyTick → refillFromJson 整组回填）。
  // · ★ 为何必须两参而不能直接赋 priceJson：priceJson 的既有语义 = 行 price_config 原文
  //   （编辑态异步回填用，本卡对它只读），用户手改草稿不写回它——「套模板 A → 手改成 B
  //   → 再点模板 A」时 priceJson 从 A 改成 A = 同值，@Watch('onJsonChange') 不触发 →
  //   界面毫无反应（静默失败，「点了没反应」家族形态）；自增纪元保证「每次点击键必变 →
  //   必重跑 → 必回填」，同时不改 priceJson 的语义。也禁改用 AppStorage tick 广播键
  //   （坑16 家族：tick 广播在 push 页内不触发）——@Link + @Watch 是本仓同位置已真机
  //   验证的通道。
  // · 模板编辑页（PriceTemplateEditPage）无套用入口，两参恒空值占位；下方 applyJson !== ''
  //   守卫保证占位永不触发回填。
  @Link applyJson: string;
  @Link @Watch('onApplyTick') applyTick: number;
  // 草稿上行回调（任一字段变更后携最新序列化草稿与完整性上行；父持最新值供保存链）
  onDraftChange: (draft: PriceDraftState) => void = () => {
  };
  // 折叠能力开关（2026-09-17 决明指令；默认 false = 存量两宿主行为不变）：true = 标题行
  // 带折叠箭头且整行可点切换（模型编辑页——五卡同列，谷时多段时本卡占屏很高）；false =
  // 恒展开、标题行无箭头（价格模板编辑页）。★ 折叠纯 UI 态，与草稿链零耦合——收起期间
  // 输入行虽销毁，值仍在卡内 @State（TextInput onChange 逐字符上行），展开重建即回填
  collapsible: boolean = false;
  @State private inputText: string = '';
  @State private cachedText: string = '';
  @State private outputText: string = '';
  @State private valleyOn: boolean = false;
  // 谷时段列表（@State 整组替换刷新——ModelCapsCard 同姿势；草稿增减/任一字段变更都换新
  // 数组新对象，不原地改）
  @State private valleySegs: ValleySegDraft[] = [];
  @State private vInputText: string = '';
  @State private vCachedText: string = '';
  @State private vOutputText: string = '';
  // 收起态（2026-09-17 折叠笔；★ 同日记忆笔改持久键，见 collapsible 成员注释）。
  // @StorageLink 双向绑定 = 用户点标题行收起/展开**即写即落盘**（AppStorage → persistProp
  // 已注册），重进编辑页/重启应用保持——决明报障「收起状态保存后无法记忆」的修复即此一行；
  // 缺省 false = 默认展开（persistProp 注册缺省同源，存量行为零回归）。★ 通道选 @StorageLink
  // 而非 @State + 手动写：双向语义天然成对（读写同键），且本卡挂 PageShell.content 内
  // （@BuilderParam），@StorageLink 属规范 §3 指定正解通道族（与主题/光感两 @StorageProp 同源）。
  // ★ 非 private：与 BackgroundPanel/AppearancePage 等 @StorageLink 先例同形
  @StorageLink(PREF_PRICE_CARD_COLLAPSED_KEY) collapsed: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
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

  // 行数据晚到（编辑态 queryModels 异步完成 → 父赋 priceJson）→ 草稿回填
  private onJsonChange(): void {
    this.refillFromJson(this.priceJson);
  }

  // 套用纪元自增（宿主点模板 chip → 先写 applyJson 再自增 applyTick）→ 载荷非空才整组
  // 回填（空串守卫：模板编辑页占位绑定恒 '' 不触发；refillFromJson 内部草稿整组替换 +
  // emitDraft 上行，宿主 priceDraft 随之同步为模板串）
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

  // 段列表回填：days 按显示序码表还原（缺省 = 存量每天配置 → 全选）；起止相等 = 全天形态
  //（旧形态「起止相等 = 全天」的界面表达，回填即点亮「全天」键；起止值原样保留，不把
  // 库内 08:00~08:00 抹成 00:00~00:00，保持只是打开编辑页时的零漂移）
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

  // 行 price_config → 草稿域（未配置 = 全空草稿 + 一段默认谷时；cachedInput 未挂键回空）。
  // ★回填即上行草稿（2026-09-10 自检轮 P1 修复）：refill 不发 onDraftChange 时父侧
  // priceDraft 停在初值空串——编辑已配置价格的模型不碰价格卡直接保存会把库中价格清空
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

  // 草稿 → 序列化上行（完整性与结构单源在 CostStatsCalc；本方法只组草稿并判完整性，
  // 拦截分支各带具体 hint 供保存链 toast 直显）：三价全空 = 未配置（''）；任一非空项
  // 非法或输入输出不成对 = incomplete；谷时同构 + 每段至少一天（2026-09-11 决明拍板：
  // 全不选拦截保存，防把谷价整个关掉还不自知）
  private emitDraft(): void {
    const input: number | null = toPriceNumber(this.inputText);
    const cached: number | null = toPriceNumber(this.cachedText);
    const output: number | null = toPriceNumber(this.outputText);
    const mainEmpty: boolean = this.inputText.trim() === '' && this.cachedText.trim() === '' &&
      this.outputText.trim() === '';
    if (mainEmpty) {
      // 主三价全空 = 未配置（谷时残值不单独成配置——serialize 侧无主价不成 JSON）。★ 但
      // 谷时开关开着且谷时三价有值时**拦截**（2026-09-11 全链路自检轮 O1，决明拍板「拦截」）：
      // 此前静默发空 JSON → 保存链照常落库 '' → 用户刚填的谷价配置无声消失（违 P0-1
      // 「禁止静默失败」）。hint 同时给出两条出路，保证「就是要清空价格配置」的意图不被堵死
      if (this.valleyOn && (this.vInputText.trim() !== '' || this.vCachedText.trim() !== '' ||
        this.vOutputText.trim() !== '')) {
        this.onDraftChange({ json: '', complete: false,
          hint: '未填写输入价格与输出价格时谷时优惠价不生效。若要清空价格配置，请关闭「谷时优惠价」，或把谷时各价一并清空' });
        return;
      }
      this.onDraftChange({ json: '', complete: true, hint: '' });
      return;
    }
    // 非法数字（非数字/负数）或输入输出不成对 = 拦截态
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
      // 段草稿 → 段结构：全天段统一落 00:00/00:00（起止相等的既有全天语义，兼容旧值）；
      // 其余段用草稿选值。days = 显示序布尔 → getDay 码数组
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

  // 谷时日勾选（@State 数组整组替换刷新；跨午夜段周几按段开始日算——判定侧语义）
  private toggleSegDay(index: number, dayIndex: number): void {
    const next: ValleySegDraft = this.cloneSeg(this.valleySegs[index]);
    next.days[dayIndex] = !next.days[dayIndex];
    this.replaceSeg(index, next);
  }

  // 「全天」键（选项类胶囊，非 Toggle——与周几 chips 同族形制）。★关闭时回落守卫：
  // 起止相等仍是全天语义，若原样留着 = 「界面上全天关了、库里还是全天」（本笔最易漏的
  // 一条），故关闭时起止相等即回落到默认时段
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

  // 段起/止选择（官方 TimePickerDialog·UIContext 形态——全局版 `TimePickerDialog.show` 自
  // API 18 起 @deprecated，@useinstead 指向 UIContext.showTimePickerDialog；useMilitaryTime
  // 固定 true，d.ts 保证 hour[0-23]/minute[0-59] → 两位补零恒产合法 'HH:mm'）
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
        // 选成同一时刻 = 判定层的全天形态 → 同步点亮「全天」键，防「界面看着不是全天、
        // 库里判成全天」的反向错位（与关闭全天的回落守卫同族，两头都堵）
        if (next.start === next.end) {
          next.allDay = true;
        }
        this.replaceSeg(index, next);
      }
    });
  }

  // 收起判定（未启用折叠能力时恒 false = 恒展开；build 内消费——标题行箭头朝向与卡体
  // 条件渲染同源本判据，两处不得各写一份）
  private isCollapsed(): boolean {
    return this.collapsible && this.collapsed;
  }

  // 数字输入行（标签左置定宽 + 输入框填充；NUMBER_DECIMAL 键盘——价格小数必需）。★ 参数按
  // 引用传递（单一对象字面量，见 PriceFieldParam 注释）——勿改回多参值传：值参 @Builder 是
  // 首帧快照，refill 回填不刷新，表现为「保存重进后正常价三栏空白」
  @Builder
  PriceField(param: PriceFieldParam) {
    Row({ space: 8 }) {
      Text(param.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(112)
      TextInput({ placeholder: param.placeholder, text: param.text })
        .type(InputType.NUMBER_DECIMAL)
        .layoutWeight(1)
        .onChange((value: string): void => {
          param.onEdit(value);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 10 }) {
      // 标题行（2026-09-17 折叠笔）：collapsible 时行尾带折叠箭头且整行可点切换。箭头
      // rotate 双态与卡体条件渲染同源 isCollapsed()；形制照规范 §4.2 组头折叠与聊天页
      // 工具卡先例（展开 = 箭头朝上「点我收起」）；切换带 300ms 动画（同日动画笔，见下）
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
        // 未启用折叠能力的宿主（价格模板编辑页）点击为 no-op——无箭头故无可发现性。
        // ★ 2026-09-17 折叠动画笔：切换包进 animateTo（官方 FAQ faqs-arkui-769 折叠示例
        // 做法 + 该示例 300ms 时长；UIContext 形态——宪法禁全局 animateTo，同族先例
        // ChatMessageItem.animateBody / ChatInputBar.setExpanded）。高度与箭头旋转随之插值。
        // ★ 官方背景知识（FAQ faqs-arkui-1400）明示「布局类改变宽高的动画，内容都是直接
        // 到终点状态」——内容不会随高度形变，观感与是否达标以真机为准
        if (this.collapsible) {
          this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
            (): void => {
              this.collapsed = !this.collapsed;
            });
        }
      })
      // 说明小字置于输入行上方（先说明后操作——宪法「功能设置卡布局次序」条）。★ 恒显示：
      // 收起态 = 主标题 + 副标题两行短卡（决明口径「不显示价格只展示主副标题」）
      Text('按服务商定价填写，单位为元每百万 tokens。留空表示未配置，未配置的模型不计入费用估计。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 操作区（三价 + 谷时开关与谷时区）：收起态整体隐藏。草稿链零耦合——输入行销毁期间
      // 值仍在各 @State，展开重建即按当前值回填（TextInput onChange 逐字符上行）
      if (!this.isCollapsed()) {
        this.PriceField({
          label: '输入价格', text: this.inputText, placeholder: '例如 2',
          onEdit: (value: string): void => {
            this.inputText = value;
            this.emitDraft();
          }
        })
        this.PriceField({
          label: '缓存输入价格', text: this.cachedText, placeholder: '留空按输入价格计',
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
          // 段行列表（2026-09-11 拍板④：每段自带适用周几与起止，一天多段也能表达）。每段
          // 一块两行——①「时段 N」+ 周几 chips + 行尾删除键（行内图标键：SymbolGlyph 无底
          // TEXTUAL + font_secondary，宪法「行内操作按钮官方形制」条）；②「时间」+ 起止两键
          // + 「全天」胶囊（选项类，照周几 chips 同族形制，不接光感）
          // ★键 = segId + 纪元号 rev + 位序，三个成分缺一不可（真机报障后定稿——原写「segId +
          // 位序」时 chips 与「全天」点了没反应）：
          //  ①segId 保身份（段对象被克隆替换后仍是同一行，不因引用变化丢行态）；
          //  ②rev 是**刷新通道**——行内属性读的是 ForEach 项参数 seg（普通对象，非 @State），
          //    键不变时框架复用组件、不重跑 itemGenerator，重赋 valleySegs 新引用只让 ForEach
          //    重新 diff，于是行内 fontColor/backgroundColor/条件渲染/按钮标签全被冻住 → 表现为
          //    「点不动」。改一处就换一个 rev，键变 → 行重建 → 新 seg 值上屏（规范 §3「键变重建」
          //    主通道；先例 AssistantToolsPage toggleEpoch / PreferencesPage 恒单例纪元键）；
          //  ③位序管位移——itemGenerator 闭包捕获的 index 不随数组变化重算，删中间段后后续段的
          //    「时段 N」标签与增删回调会整体错位（坑16 家族）。
          // ★走 cloneSeg 的改动路径已全部带上 rev（勾日/全天/选时间/添加/重填）；新增段内改动
          // 路径时也必须经 cloneSeg，否则该路径静默「点了没反应」
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
                      .fontColor(seg.days[dayIndex] ?
                        $r('sys.color.ohos_id_color_emphasize') : cardDescColor())
                      // chips 几何对齐 ModelCapsCard 范式（12/12/6/6 + 圆角 14 + 间距 8/8
                      // ——2026-09-12 UI 同形异构归一笔 2，原 11/11/5/5 + 13 + 6/6）
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .backgroundColor(seg.days[dayIndex] ?
                        $r('sys.color.comp_background_secondary') : cardBg(this.appColorMode))
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
                  .fontColor(seg.allDay ?
                    $r('sys.color.ohos_id_color_emphasize') : cardDescColor())
                  // chips 几何对齐 ModelCapsCard 范式（同上笔 2；单选项无 margin 不加）
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor(seg.allDay ?
                    $r('sys.color.comp_background_secondary') : cardBg(this.appColorMode))
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
          // 添加时段（本卡主操作键——内容区双态 primary=true 官方强调蓝 + 恒白字；2026-09-11
          // 决明「添加时段键改蓝底」；到上限置灰 + 说明小字不变——上限引计算层常量，防
          // 「界面 6 段、解析 8 段」双源漂移）
          Button('添加时段')
            .fontSize(14)
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback,
              this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback,
              this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback,
              this.immersiveLevel))
            .width('100%')
            .enabled(this.valleySegs.length < VALLEY_SEGMENT_MAX)
            .onClick((): void => {
              this.addSeg();
            })
          if (this.valleySegs.length >= VALLEY_SEGMENT_MAX) {
            Text('最多添加 ' + VALLEY_SEGMENT_MAX + ' 个时段，删除后可再添加')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          // 谷时价全段共用（拍板①）——先说明后操作，且防「每段各配一套价」的误读
          Text('以下价格对所有时段生效')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          this.PriceField({
            label: '谷时输入价格', text: this.vInputText, placeholder: '例如 1',
            onEdit: (value: string): void => {
              this.vInputText = value;
              this.emitDraft();
            }
          })
          this.PriceField({
            label: '谷时缓存输入价格', text: this.vCachedText, placeholder: '留空按谷时输入价格计',
            onEdit: (value: string): void => {
              this.vCachedText = value;
              this.emitDraft();
            }
          })
          this.PriceField({
            label: '谷时输出价格', text: this.vOutputText, placeholder: '例如 4',
            onEdit: (value: string): void => {
              this.vOutputText = value;
              this.emitDraft();
            }
          })
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
