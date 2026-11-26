// 上下文用量半模态面板（拍板 P3/P5~P8）：面板内容件（不含 bindSheet——宿主 ChatPage 页面
// 根唯一挂载点，坑64 姿势；规范-半模态 §8「面板内容件」先例）。形制 = KimiFullInputSheet/
// ModelPickerSheet 同款三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions 5 参规格 +
// bindToScrollable 滚动感知 + 底部安全区延伸），滚动容器 clip(false)（规范 §2——渐变模糊
// 要有内容可透）。
// ★ 2026-10-29 首卡改版笔：总览卡（环 + 百分比大字 + 缓存命中行 + 已用/上限行）整块迁出
// 独立件 ContextUsageOverviewCard（本件曾越 1200 硬线）——新形制 = 环 76/7 + 占比嵌环心 +
// 右列（已用/上限 · 缓存命中率）+ 三列构成（缓存输入 / 未缓存输入 / 输出，计费口径绝对数，
// 带口径行隔离）。本件此后只承载明细卡、构成卡、压缩卡与清空卡；首卡形制与口径判据的唯一
// 来源在新件头注释（含「上轮实际」「本会话累计」两卡已移入 SessionStatsSheet、原底部说明行
// 已移入首卡右上角信息气泡等沿革——两处退役的负向钉见 assert-ui-shape）。
// · 明细卡——逐段行（分项符号 + 标签左·数值右，UsageRow 形制）+「其他」兜底段（差值 >1%
//   才出，P8）+ 空闲行；窗口未知（windowTokens 0）整卡不显（P4：只显已用数）。
//   ★ 2026-11-07 口径切换笔：卡头右上角加「占已用/占窗口」分段胶囊（SegmentBar 紧凑档，
//   形制照对话页图表卡「图表/表格」）——切换行内百分比的分母；占已用时空闲不显百分比
//  （空闲不属于已用，强行相除会读出 >100%），占窗口维持旧口径。下标进 ForEach 行键防冻结。
// ★ 0 与未知区分（§5，Cherry #19965）：hasData false 或 usage null 显「暂无/正在统计」，
// 禁渲染 0%。数据经 @Link 下发（页面活算落地自动刷新；重算进行中保留旧值不清空，
// Cline #3861 反面）。可加总红线（§3.4）：明细各行 + 其他 = 已用，加空闲 = 上限。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { SegmentBar } from '../SegmentBar';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont,
  fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  cardBg, cardBorderColor, cardDescColor, cardTitleColor, wellBg,
  CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS, SEGMENT_BAR_COMPACT_HEIGHT
} from '../../common/Theme';
import { ContextSegment, tokenShort } from '../../common/TokenEstimate';
import { compressibleReady, estimateCompressSaving } from '../../common/CompressGen';
import { queryBoundaryCreatedAt } from '../../common/store/CompressDb';
// ★ deleteGraphSummary 随摘要写口迁 ChatGraphCommandSource（本件改接线）
import { deleteGraphSummary } from '../../common/chat/ChatGraphCommandSource';
import { conversationGraphBranch, conversationWritableRoute,
  readLatestSummaryRow, readPathSummaryInput, RequestSummaryInput,
  ROUTE_GRAPH } from '../../common/chat/ChatContextSource';
import { isClearAtHead, readLatestClearRow } from '../../common/chat/ContextClear';
import { pickClearAnchor, ClearAnchor } from './ChatCompressCtrl';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { MessageRow } from '../../common/store/ChatDb';
import { ContextUsage, LastRoundUsage } from './ChatContextUsage';
import { InjectSectionView } from '../../common/chat/InjectSections';
import { ContextUsageOverviewCard } from './ContextUsageOverviewCard';
import { ChatMessage } from './ChatMessageCompose';
import { sheetTitleBarOptions } from './KimiSheetCommon';
// ★ 请求历史解耦笔：压缩素材换读口（预算内全段可压——与实发同读口同预算，五处同源；
// 降级/解耦关 = 窗口旧口径）
import { readRequestHistoryRows, RequestHistoryReadResult }
  from '../../common/chat/RequestHistorySource';
import { resolveReadRows } from '../../common/chat/RequestHistoryBudget';
import { chatMessagesFromRows } from './ChatMessageProjection';
import { REQUEST_HISTORY_DECOUPLE_ENABLED } from '../../common/Theme';

// 「其他」兜底段出列门槛（P8：差值占上限 >1% 才列——可见噪声与可加总的折中）
const OTHER_SEGMENT_MIN_PCT: number = 0.01;
// 明细卡口径胶囊容器宽（vp）：官方 CapsuleSegmentButtonV2 不吃 width，宽度由外层定宽容器约束
//（图表卡卡头同款先例，见 ChatToolChartCard.ets）。紧凑档选项字号 10fp、背板边距 3vp，三字
// 选项「占已用 / 占窗口」每格需 ≥ 3×10 + 文字边距 8 = 38vp ⇒ 容器 ≥ 82vp，取 96 留余量；
// 高度恒引 SEGMENT_BAR_COMPACT_HEIGHT（勿写死，档几何单源在 SegmentBar 紧凑档）
const DETAIL_PCT_SEGMENT_WIDTH: number = 96;
// 摘要只读井（两卡方案 A）：正文定高内部滚动，卡高不随摘要长度增长；井几何照《规范-列表
// 卡片与组卡》§4.17 长文本只读井——wellBg + 12 圆角 + 0.5vp 发丝边 + 内距 12
const SUMMARY_SCROLL_HEIGHT: number = 160;
const SUMMARY_WELL_RADIUS: number = 12;

@Component
export struct ContextUsageSheet {
  // 页面存活守卫（销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；
  // 写库等数据层意图照常完成
  private departed: boolean = false;
  // 最近一次活算产物（页面 @State 经 $ 绑定——活算落地自动刷新；null = 首开计算中占位）
  @Link usage: ContextUsage | null;
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  // ── 上下文压缩卡供给（任务书 §3.1）：面板此前无任何动作按钮，本卡是唯一动作面。refs
  // 闭包由宿主 ChatPage 注入（子件不反向 import 宿主）──
  // conversationId = 本次会话的持久标识；**空串 = 无持久会话**（隐私会话零落痕模式由宿主
  // 传 ''）⇒ 压缩卡整卡不渲染 + 状态装载整块跳过——摘要必须落库才成立，本模式无行可落、
  // 写库又破零留痕红线（★ 自检轮补：原实现宿主无条件带 id、卡照渲染且键可点，落库路径可达）
  conversationId: string = '';
  allMessages: () => ChatMessage[] = () => [];
  clipLimit: () => number = () => 0;
  // 流式态快照（置灰三条件之一；回调现读 = 弹出后每次重算）
  sending: () => boolean = () => false;
  // 打开压缩预览面板（宿主切 sheetKind='compress'——本面板随之收起，同宿主单面板多形态）
  onCompress: () => void = () => {
  };
  // 摘要删除完成上行（宿主移除流内提示行 + 刷新用量）
  onSummaryDeleted: (summaryIds: string[]) => void = () => {
  };
  // 清空动作上行：宿主 ChatPage 接 ChatCompressCtrl.clearContext / revokeClear——两方法返回
  //「是否确有一次写入」，面板据此重载状态行；动作本体、库写入、流内维护与 toast 全在
  // 控制器，本面板只发令与重载
  onClearContext: () => Promise<boolean> =
    (): Promise<boolean> => Promise.resolve(false);
  onClearRevoked: () => Promise<boolean> =
    (): Promise<boolean> => Promise.resolve(false);
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 压缩卡自持状态（开面板时装载；采用/删除后宿主重开面板自然重载）
  @State private summaryRow: MessageRow | null = null;
  @State private boundaryAt: number = 0;
  @State private savedTokens: number = 0;
  @State private readyToCompress: boolean = false;
  @State private summaryExpanded: boolean = false;
  // 分段明细百分比口径（0 = 占已用 / 1 = 占窗口，与 detailPctItems 顺序同源）：面板内视图态，
  // 不持久化——重开面板回占已用（同图表卡「图表/表格」视图态口径）。★ 下标还进 ForEach 行
  // 键：行内百分比是本态的可变展示成分，键不含它则切换后行静默冻结（坑44/80 家族）
  @State private detailPctIndex: number = 0;
  // 口径选项（顺序 = 下标映射；UI 字符串与 HelpContent「上下文用量」条目逐字一致）
  private detailPctItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '占已用' },
    { text: '占窗口' }
  ]);
  // 清空卡自持状态：清空边界行 + 其覆盖点时刻 + 当前分界锚号（活跃路径最后一条可证消息的
  // seq；-1 = 无可清空内容。置灰判据用状态位而非渲染期扫描：面板 build 不重复遍历消息流）
  @State private clearRow: MessageRow | null = null;
  @State private clearAt: number = 0;
  @State private clearAnchorSeq: number = -1;
  // 撤销键门槛：清空行是否仍是分支 head——清空后发了任何新内容（消息 / 再清空 / 采用压缩）
  // head 前移，撤销键不显示（决明拍板：发消息前的清空才许后悔，之后清空固定不可撤）；撤销
  // 动作另有控制器与域件两道守卫兜面板停留旧状态
  @State private clearRevocable: boolean = false;
  // ★ 自检轮删：原 @State boundaryInput（库直查边界的暂存）三处只写不读——@State 只用于
  //「会变化且驱动 UI」的变量（宪法性能红线·状态最小化），边界值按需现取现用
  // 墓碑/坏库态（修复 A-3）：非 graph 可写路由（旧格式墓碑 / graph 空分支坏库）时压缩键置灰
  // 且理由走墓碑短句——原置灰三判据在墓碑会话全落「历史还短」，把用户引去查不存在的「历史」
  // 问题（项目自有红线形态：不能把库/会话态问题报成内容问题）
  @State private tombstoned: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 无持久会话（隐私会话/空引用）⇒ 压缩卡不渲染，状态装载整块跳过（零查询零估算）
    if (this.conversationId === '') {
      return;
    }
    this.reloadCompressState();
  }

  // 压缩卡状态装载（面板打开时一次）：摘要行 + 边界时间 + 节省量 + 可压判定。★ 节省量与摘要
  // 行同批：估算经 pathSummary 补位口吃库直查行——图摘要节点滑出读窗后内存窗口无 summary
  // 行，只吃窗口两链恒等、面板恒报「节省约 0 tokens」；补位后与请求组装侧（ChatHistoryBuilder
  // 同参）同源。读失败降级「未压缩」态不炸面板，warn 留痕在本函数 catch（域件未自留痕，C8
  // 已核正为真实口径并补 warn）
  private reloadCompressState(): void {
    const anchor: ClearAnchor | null = pickClearAnchor(this.allMessages());
    this.clearAnchorSeq = anchor !== null ? anchor.seq : -1;
    const convId: string = this.conversationId;
    if (convId === '') {
      // 无持久会话（压缩卡整卡不渲染）：零查询，估算仍按窗口算一次保持状态口径
      this.readyToCompress = compressibleReady(this.allMessages());
      this.savedTokens = estimateCompressSaving(this.allMessages(), this.clipLimit());
      this.summaryRow = null;
      this.clearRow = null;
      this.clearRevocable = false;
      this.boundaryAt = 0;
      this.clearAt = 0;
      return;
    }
    // 墓碑判读（修复 A-3）：与写侧路由同判据（无行 = 未出生可写 graph，不误伤新会话）；读
    // 异常按墓碑处理（判据不可靠时不放行，fail-closed 同各写入口口径）
    conversationWritableRoute(convId)
      .catch((_e: Object): string => 'blocked')
      .then((route: string): void => {
        if (this.departed) {
          return;
        }
        this.tombstoned = route !== ROUTE_GRAPH;
      });
    // 边界装载（摘要/清空同权，库直查口与请求组装侧同源）——节省量与可压判定共吃本口
    //（原本地手搓 pathSummary 对象会漏 kind 且是第二份边界口径，改走 readPathSummaryInput
    // 单一读口）。★ 请求历史解耦笔：判定与节省量的素材源在边界就绪后解析——解耦开 = 读口
    // 预算内全段（与实发同读口同预算，更早历史可压；读口失败降级窗口旧口径）；解耦关 =
    // 窗口旧口径（逐字同旧链）
    const estimateWithWindow = (boundary: RequestSummaryInput | null): void => {
      this.readyToCompress = compressibleReady(this.allMessages(), boundary);
      this.savedTokens = estimateCompressSaving(this.allMessages(), this.clipLimit(), boundary);
    };
    const estimateWithSource = (boundary: RequestSummaryInput | null): void => {
      if (!REQUEST_HISTORY_DECOUPLE_ENABLED) {
        estimateWithWindow(boundary);
        return;
      }
      conversationGraphBranch(convId)
        .then((branchId: string): Promise<RequestHistoryReadResult> =>
          readRequestHistoryRows(convId, branchId, resolveReadRows(this.clipLimit()), null))
        .catch((_e: Object): null => null)
        .then((read: RequestHistoryReadResult | null): void => {
          if (this.departed) {
            return;
          }
          if (read === null) {
            estimateWithWindow(boundary);
            return;
          }
          const source: ChatMessage[] = chatMessagesFromRows(read.rows);
          this.readyToCompress = compressibleReady(source, boundary);
          this.savedTokens = estimateCompressSaving(source, this.clipLimit(), boundary);
        });
    };
    readPathSummaryInput(convId)
      .then((boundary: RequestSummaryInput | null): void => {
        if (this.departed) {
          return;
        }
        estimateWithSource(boundary);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        estimateWithSource(null);
        hilog.warn(0xD5A0, 'ContextUsageSheet',
          '边界读取失败，节省量按无边界估算：%{public}s', (e as Error).message);
      });
    readLatestSummaryRow(convId)
      .then((row: MessageRow | null): void => {
        if (this.departed) {
          return;
        }
        this.summaryRow = row;
        this.boundaryAt = 0;
        if (row !== null && row.coversToSeq !== undefined) {
          queryBoundaryCreatedAt(convId, row.coversToSeq)
            .then((at: number): void => {
              if (this.departed) {
                return;
              }
              this.boundaryAt = at;
            })
            .catch((e: Object): void => {
              if (this.departed) {
                return;
              }
              this.boundaryAt = 0;
              // 同族未报现场一并留痕：边界时间读失败 = 状态行少时间部分，不炸面板
              hilog.warn(0xD5A0, 'ContextUsageSheet',
                '摘要边界时间读取失败（状态行按无时间显示）：%{public}s', (e as Error).message);
            });
        }
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.summaryRow = null;
        hilog.warn(0xD5A0, 'ContextUsageSheet',
          '摘要行读取失败，压缩卡按未压缩降级：%{public}s', (e as Error).message);
      });
    // 清空卡状态装载：有无清空边界 + 覆盖点时刻（读口径与摘要卡同族）+ 撤销门槛位
    //（清空行仍是 head 才可撤）
    readLatestClearRow(convId)
      .then((row: MessageRow | null): void => {
        if (this.departed) {
          return;
        }
        this.clearRow = row;
        this.clearAt = 0;
        this.clearRevocable = false;
        if (row !== null) {
          if (row.coversToSeq !== undefined) {
            queryBoundaryCreatedAt(convId, row.coversToSeq)
              .then((at: number): void => {
                if (this.departed) {
                  return;
                }
                this.clearAt = at;
              })
              .catch((e: Object): void => {
                if (this.departed) {
                  return;
                }
                this.clearAt = 0;
                hilog.warn(0xD5A0, 'ContextUsageSheet',
                  '清空边界时间读取失败（状态行按无时间显示）：%{public}s', (e as Error).message);
              });
          }
          isClearAtHead(convId, row.id)
            .then((revocable: boolean): void => {
              if (this.departed) {
                return;
              }
              this.clearRevocable = revocable;
            })
            .catch((_e: Object): void => {
              if (this.departed) {
                return;
              }
              this.clearRevocable = false; // 判据读不到时按不可撤（宁可不撤不可误撤）
            });
        }
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.clearRow = null;
        this.clearRevocable = false;
        hilog.warn(0xD5A0, 'ContextUsageSheet',
          '清空行读取失败，清空卡按未清空降级：%{public}s', (e as Error).message);
      });
  }

  // 压缩键置灰判据（★ A-3 增首条：墓碑/坏库会话无可读路径，键禁用——理由走墓碑短句；原三
  // 条件在墓碑会话全落「历史还短」误报）：①会话态不可写 ②流式进行中 ③窗口未知 ④可压段不足
  private compressDisabled(): boolean {
    return this.tombstoned || this.sending() || this.winTokens() <= 0 || !this.readyToCompress;
  }

  // 置灰原因一行（文案规约：分句句号、无冒号分号连环）
  private compressDisabledReason(): string {
    if (this.tombstoned) {
      return TOMBSTONE_TOAST_TEXT;
    }
    if (this.sending()) {
      return '回复进行中，结束后可压缩';
    }
    if (this.winTokens() <= 0) {
      return '该模型未配置上下文窗口，暂不能压缩';
    }
    return '历史还短，暂时不用压缩';
  }

  // ── 压缩卡状态明细（2026-10-26 两卡方案 A）：状态词进卡头徽标，明细按「节省量 / 覆盖
  //    范围 / 兜底句」分行——旧单行拼接在长摘要下会把三档信息挤成一句，徽标也读不出主次 ──
  // 节省量主行（仅有摘要时渲染；边界时间已被删回 0 不凑时间——任务书 §3.1）
  private summarySavedText(): string {
    return '节省约 ' + tokenShort(this.savedTokens) + ' tokens';
  }

  // 覆盖范围行（边界可证才出；不可证时由 12fp 兜底句单独交代）
  private summaryBoundaryText(): string {
    return this.boundaryAt > 0 ? '覆盖 ' + this.formatBoundaryTime() + ' 之前的内容' : '';
  }

  // P3-旧摘要拍板值：覆盖边界不可证的摘要明确提示——保留可读文本、禁止其自动裁剪历史
  //（读侧 fail-open 不裁），只影响该摘要、不猜测边界
  private summaryUncertain(): boolean {
    return this.summaryRow !== null && this.summaryRow.coversToSeq === undefined;
  }

  // ★ 摘要覆盖范围整个落在清空点之前 ⇒ 本次请求只认清空边界，这份摘要已作废（仍可读、
  // 可删）——如实表态，不让面板继续报「已压缩」装作生效（判据 = 清空边界 seq ≥ 摘要覆盖
  // 上界；两值同坐标系：messages.seq）
  private summaryObsoletedByClear(): boolean {
    if (this.summaryRow === null) {
      return false;
    }
    const clearTo: number = this.clearRow !== null ? (this.clearRow.coversToSeq ?? -1) : -1;
    const summaryTo: number = this.summaryRow.coversToSeq ?? -1;
    return clearTo >= 0 && summaryTo >= 0 && clearTo >= summaryTo;
  }

  // 清空覆盖时刻行（读到行但边界值缺 = 档案行，由下方兜底句交代）
  private clearBoundaryText(): string {
    return this.clearAt > 0 ? '覆盖 ' + this.formatAt(this.clearAt) + ' 之前的内容' : '';
  }

  private clearBoundaryUncertain(): boolean {
    return this.clearRow !== null && this.clearRow.coversToSeq === undefined;
  }

  // 空态/禁用原因行符号（方案 A）：会话态/窗口配置问题用感叹号圆，等待类用时钟，没有可动
  // 对象用减号圆——符号只做语义提示，色恒为次要色（不新造色档）
  private compressReasonSymbol(): Resource {
    if (this.tombstoned) {
      return $r('sys.symbol.exclamationmark_circle');
    }
    if (this.sending()) {
      return $r('sys.symbol.clock');
    }
    if (this.winTokens() <= 0) {
      return $r('sys.symbol.exclamationmark_circle');
    }
    return $r('sys.symbol.clock');
  }

  private clearReasonSymbol(): Resource {
    if (this.tombstoned) {
      return $r('sys.symbol.exclamationmark_circle');
    }
    if (this.sending()) {
      return $r('sys.symbol.clock');
    }
    return $r('sys.symbol.minus_circle');
  }

  // 清空键置灰判据（同压缩键三态家族，另加「已清且分界未前移」一态）：①会话态不可写
  // ②流式进行中 ③无可清空内容 ④已有清空边界且其覆盖上界不早于当前分界点（期间无新消息，
  // 重复清空不动库——与控制器 runClear 守卫同判，这里是它的前置可视形态）
  private clearDisabled(): boolean {
    if (this.tombstoned || this.sending() || this.clearAnchorSeq <= 0) {
      return true;
    }
    return this.clearRow !== null && (this.clearRow.coversToSeq ?? 0) >= this.clearAnchorSeq;
  }

  private clearDisabledReason(): string {
    if (this.tombstoned) {
      return TOMBSTONE_TOAST_TEXT;
    }
    if (this.sending()) {
      return '回复进行中，结束后可清空';
    }
    if (this.clearAnchorSeq <= 0) {
      return '还没有可清空的内容';
    }
    return '之后还没有新消息，无需重复清空';
  }

  // 清空 / 撤销清空：动作落库、流内分隔条维护与 toast 全在控制器，本面板只发令；返回
  // true = 确有一次写入，重载状态行（清空后覆盖范围/时刻、撤销后回未清空）。
  // then 首行 departed 判（1712 族）：动作承诺在控制器侧完成，重载写 7 个 @State 前判
  // 销毁——迟到回调不碰已销毁面板
  private requestClear(): void {
    this.onClearContext().then((done: boolean): void => {
      if (this.departed) {
        return;
      }
      if (done) {
        this.reloadCompressState();
      }
    });
  }

  private requestRevokeClear(): void {
    this.onClearRevoked().then((done: boolean): void => {
      if (this.departed) {
        return;
      }
      if (done) {
        this.reloadCompressState();
      }
    });
  }

  // 边界时间（SessionStatsSheet 同款本地格式化：YYYY-MM-DD HH:mm）
  private formatBoundaryTime(): string {
    return this.formatAt(this.boundaryAt);
  }

  private formatAt(at: number): string {
    const d: Date = new Date(at);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
      pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  // 删除摘要（破坏性动作 → 官方对话框二次确认；确认 → 删行（事务 + 附件级联）→ 上行宿主
  // 移除流内提示行并刷新用量——下一次请求回到全文）
  private async confirmDeleteSummary(): Promise<void> {
    const row: MessageRow | null = this.summaryRow;
    if (row === null) {
      return;
    }
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: '删除摘要？',
        message: '删除后下一次请求回到全文，上下文占用会回升',
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '删除', color: $r('sys.color.font_primary') }
        ]
      });
      if (choice.index !== 1) {
        return;
      }
    } catch (e) {
      return; // 弹窗异常不删（宁可不删不可误删）
    }
    try {
      // 路径感知删除：graph 会话走图侧**软删**（路径上全部摘要 binding 一并失效——只删最新
      // 会让旧档案摘要复活顶上，与「回到全文」不符；返回失效集）；legacy 批删支已随线性写
      // 路径退役——无分支（旧格式墓碑 / 坏库态）fail-closed 拒删呈报（文案单源在
      // ChatBranchPolicy）
      const branchId: string = await conversationGraphBranch(this.conversationId);
      let removedIds: string[] = [];
      if (branchId !== '') {
        removedIds = await deleteGraphSummary(this.conversationId, row.id);
      } else {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: TOMBSTONE_TOAST_TEXT });
        return;
      }
      if (this.departed) {
        return;
      }
      this.summaryRow = null;
      this.boundaryAt = 0;
      this.savedTokens = 0;
      this.onSummaryDeleted(removedIds);
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({
        message: '删除失败：' + (e as Error).message });
    }
  }

  // ── 空安全读取口（@Link 可空对象，闭包/插值处禁裸取——统一经本组方法）──
  private winTokens(): number {
    return this.usage !== null ? this.usage.windowTokens : 0;
  }

  private usedTokens(): number {
    return this.usage !== null ? this.usage.usedTokens : 0;
  }

  private segList(): ContextSegment[] {
    return this.usage !== null ? this.usage.segments : [];
  }

  private otherTokens(): number {
    return this.usage !== null ? this.usage.otherTokens : 0;
  }

  // 待发附件未处理完：解析中/识别中的件文本侧尚未计入——true 才显明细卡提示行
  //（false = 零噪声不显）
  private attachPending(): boolean {
    return this.usage !== null && this.usage.attachPending;
  }

  // ★ 首字均值（平均首字耗时）本件不承载：曾短暂落本面板总览卡，同日二次改判迁「会话统计」
  // 面板 Token 用量卡末行（决明拍板）——本件与首字面的唯一关系回到既有的「气泡弹层按条显示」
  // 分段符号映射（分项行前小图标，语义对应——名称经 SDK sysResource 符号表实名核对；
  // 集中一函数 = 键集演进单点，未知键兜底问号圆）
  private segSymbol(key: string): Resource {
    if (key === 'prompt') {
      return $r('sys.symbol.gearshape');
    }
    if (key === 'skills') {
      return $r('sys.symbol.wand_and_stars');
    }
    if (key === 'memory') {
      return $r('sys.symbol.book_pages');
    }
    if (key === 'knowledge') {
      // v51 知识触发笔：知识注入段（符号 = 闪电 = 关键词命中触发语义，工程已用实名）
      return $r('sys.symbol.bolt');
    }
    if (key === 'tools') {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    // 工具定义分组段（占用可见笔）：面板把「工具定义」拆为「工具·内置」+
    // 「工具·MCP·<服务器名>」多段——符号照 'tools' 档（同族拆段不分色，来源差异在 label）
    if (key === 'tools_builtin' || key === 'tools_mcp') {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    if (key === 'user') {
      return $r('sys.symbol.person');
    }
    if (key === 'assistant') {
      return $r('sys.symbol.text_bubble_left_2');
    }
    if (key === 'toolResults') {
      return $r('sys.symbol.list_checkmark');
    }
    if (key === 'draft') {
      return $r('sys.symbol.square_and_pencil');
    }
    if (key === 'reserved') {
      return $r('sys.symbol.hourglass');
    }
    // 「其他」= 命名段和与总量的差值兜底段（省略号圆；★「其余 N 段」合并段已随小值段合并
    // 退役删除〔决明拍板〕，见 TokenEstimate 退役注）
    if (key === 'other') {
      return $r('sys.symbol.ellipsis_circle');
    }
    if (key === 'free') {
      return $r('sys.symbol.minus_circle');
    }
    return $r('sys.symbol.questionmark_circle');
  }

  // 百分比分母：占已用 = 已用总量，回答「已用被谁占了」；占窗口 = 窗口上限，回答「窗口
  // 被谁占了」（原实现恒占窗口，本笔把窗口口径保留为可切回的第二态）。分母 ≤0 时不显百分比，
  // 不渲染 NaN / Infinity（0 与未知区分，§5）
  private pctBaseTokens(): number {
    return this.detailPctIndex === 0 ? this.usedTokens() : this.winTokens();
  }

  // 行内百分比后缀：空闲是窗口余量、不属于已用，占已用口径下不显百分比——否则会读出
  //「空闲 ÷ 已用 >100%」这种无意义的数。占窗口口径下空闲照常显，与首卡占比互补
  private detailPctSuffix(tokens: number, key: string): string {
    const base: number = this.pctBaseTokens();
    if (base <= 0 || (this.detailPctIndex === 0 && key === 'free')) {
      return '';
    }
    return ' · ' + Math.round(tokens * 100 / base) + '%';
  }

  // 口径说明小字（随态）：本卡无操作按钮行，说明垫底不构成「说明小字垫在按钮下方」形态
  private detailPctNote(): string {
    return this.detailPctIndex === 0 ? '按已用总量计算，空闲不参与。' :
      '按上下文窗口计算，含空闲。';
  }

  // 明细行（分项符号 + 标签左·数值右，UsageRow 形制：标签次要色、数值主色加粗；符号 =
  // segSymbol 映射 14vp 同色）。百分比后缀按口径态算——调用点逐字保持不变，ForEach 行键已含
  // 口径下标（切换即整行重建），条件渲染的「其他 / 空闲」两行随父 build 重跑刷新
  @Builder
  DetailRow(label: string, tokens: number, key: string) {
    Row({ space: 6 }) {
      SymbolGlyph(this.segSymbol(key))
        .fontSize(14)
        .fontColor([cardDescColor()])
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(tokenShort(tokens) + this.detailPctSuffix(tokens, key))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  @Builder
  DetailCard() {
    Column({ space: 10 }) {
      // 卡头行：标题 + 右上角口径分段胶囊（紧凑档，形制照图表卡「图表/表格」视图切换先例；
      // 选项序 = 占已用 → 占窗口，默认占已用——各段在已用里的构成加起来可读成整体）
      Row() {
        Text('分段明细')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Column() {
          SegmentBar({
            items: this.detailPctItems,
            selectedIndex: $detailPctIndex,
            compact: true
          })
        }
        .width(DETAIL_PCT_SEGMENT_WIDTH)
        .height(SEGMENT_BAR_COMPACT_HEIGHT)
        .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 12 }) {
        ForEach(this.segList(), (seg: ContextSegment) => {
          this.DetailRow(seg.label, seg.tokens, seg.key)
        }, (seg: ContextSegment): string =>
          // 键含 label + 口径下标（坑44/80：工具定义分组段的 label 是可变展示成分——服务器名
          // 随绑定变、超预算尾注随预算态变，tokens 恰不变时键不含 label 即行冻结；行内百分比
          // 随口径态变，下标不进键则切换后百分比静默冻结而数值照旧）
          seg.key + '|' + seg.label + '|' + seg.tokens + '|' + this.detailPctIndex)
        // 「其他」兜底段（P8：差值 >1% 才出——协议包装/图片折算误差的可归因落点，可加总
        // 红线：各行相加能对上总数，Claude Code #18241 同屏矛盾的反面）
        if (this.otherTokens() * 1.0 / this.winTokens() > OTHER_SEGMENT_MIN_PCT) {
          this.DetailRow('其他', this.otherTokens(), 'other')
        }
        // 空闲行（已用超窗时钳 0 不显负）
        if (this.winTokens() - this.usedTokens() > 0) {
          this.DetailRow('空闲', this.winTokens() - this.usedTokens(), 'free')
        }
        // 待发附件提示行：有件尚未处理完（解析中/识别中）时该部分文本侧未计入——不说破
        // 会被读成面板漏算（「估算漏算而不说明」同族）；长句随状态条件渲染留在板块内
        //（规范-列表卡片与组卡「状态提示」条：优于藏进气泡），13fp 次要色 = 本面板说明
        // 小字既有形制
        if (this.attachPending()) {
          Text('有附件尚未处理完，未计入用量。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        // 当前口径说明（随态小字；本卡无操作按钮行，说明垫底不构成「按钮下方 footer」形态）
        Text(this.detailPctNote())
          .fontSize(12)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // ── 请求构成卡（注入链治理 P3-b）：「本次请求」的 system 注入构成只读卡——数据源 =
  // beginRound 定格的同一份段视图（usage.injectSections 经 ContextUsage 回指，「面板与实发
  // 一致」纪律，禁第二条计算链；null / 空段 = 未有发送轮定格或零注入，整卡不显）。三行块 =
  // 段行（label + 稳定/波动〔+ 已降级，同源 usage.degradedKeys〕+ 字符与估算）+ 工具定义
  // 占用行（复用既有活算 tools 分段）+ 上轮缓存比值行（lastUsage，>0 才显——「缓存行 >0
  // 才显」零噪声口径）+ P2 到顶说明行（overBudgetAfter，六级降级仍超预算时显）+ 断点说明
  // 小字（Anthropic 显式断点只覆盖稳定段——稳定段字符合计即断点位置，其他协议无显式断点）──
  @Builder
  InjectRow(label: string, hint: string, value: string, key: string) {
    Row({ space: 6 }) {
      SymbolGlyph(this.segSymbol(key))
        .fontSize(14)
        .fontColor([cardDescColor()])
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Text(hint)
        .fontSize(12)
        .fontColor(cardDescColor())
      Blank()
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  @Builder
  InjectCard() {
    Column({ space: 10 }) {
      Text('本次请求构成')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 12 }) {
        ForEach(this.injectSectionList(), (sec: InjectSectionView) => {
          this.InjectRow(sec.label, this.injectSectionHint(sec),
            sec.chars + ' 字 · 约 ' + sec.tokens, sec.key)
        }, (sec: InjectSectionView): string =>
          // 键含全可变展示成分（坑44/80 家族：chars/tokens 随降级与轮次变；★ R2：「已降级」
          // 后缀由 usage.degradedKeys 派生——降级前后某段 chars 恰不变时键同即行冻结（后缀
          // 静默不动），降级位一并入键）
          sec.key + '|' + sec.label + '|' + sec.cacheHint + '|' + sec.chars + '|' + sec.tokens +
          (this.usage !== null && this.usage.degradedKeys.indexOf(sec.key) >= 0 ? '|d' : ''))
        // 工具定义占用（复用既有活算分段——工具·内置/MCP 分组即彼处列段，此处只给合计位；
        // 符号 = segSymbol 的 tools 默认档）
        if (this.toolsSegmentTokens() > 0) {
          this.InjectRow('工具定义', '声明', tokenShort(this.toolsSegmentTokens()), 'tools')
        }
        // 上轮缓存比值（逐轮口径 = P3-a 撤销依据的自然延伸；>0 才显）
        if (this.lastCacheRatio() !== '') {
          this.InjectRow('上轮缓存命中', '比值', this.lastCacheRatio(), 'other')
        }
        // P2 到顶说明（六级降级后仍超预算 = fail-open 照发，本句把「已超预算仍发送」显式
        // 告知；kill-switch 关 = 恒空不显）
        if (this.overBudgetNote() !== '') {
          Text(this.overBudgetNote())
            .fontSize(12)
            .fontColor(cardDescColor())
            .width('100%')
        }
        Text('稳定段在前，波动段在后。Anthropic 协议的显式缓存断点只覆盖稳定段，'
          + '其他协议无显式断点。')
          .fontSize(12)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 构成段列表（构成卡）：usage 判空收口（@Builder 内不跨上下文判空——ArkTS 严格空检）
  private injectSectionList(): InjectSectionView[] {
    if (this.usage === null || this.usage.injectSections === null) {
      return [];
    }
    return this.usage.injectSections;
  }

  // 段提示（构成卡）：缓存提示 + P2 降级标记（同源 = beginRound 定格的 degradedKeys，
  // 与实发同一份降级结果；未降级段维持「稳定 / 波动」两态）
  private injectSectionHint(sec: InjectSectionView): string {
    const base: string = sec.cacheHint === 'dynamic' ? '波动' : '稳定';
    if (this.usage !== null && this.usage.degradedKeys.indexOf(sec.key) >= 0) {
      return base + ' · 已降级';
    }
    return base;
  }

  // 到顶说明（构成卡）：六级降级后仍超预算 = fail-open 照发（空串 = 不显行）
  private overBudgetNote(): string {
    return this.usage !== null && this.usage.overBudgetAfter ?
      '注入内容降级后仍超出预算，已按当前内容发送。' : '';
  }

  // 工具定义合计（构成卡）：既有活算分段里 tools 族（key 以 'tools' 开头——含分组段）
  // 的 token 求和，不新增估算
  private toolsSegmentTokens(): number {
    if (this.usage === null) {
      return 0;
    }
    let total: number = 0;
    for (const seg of this.usage.segments) {
      if (seg.key.indexOf('tools') === 0) {
        total += seg.tokens;
      }
    }
    return total;
  }

  // 上轮缓存比值（构成卡）：lastUsage 有值且 prompt > 0 时回百分比串，否则 ''（不显行）
  private lastCacheRatio(): string {
    const last: LastRoundUsage | null = this.usage !== null ? this.usage.lastUsage : null;
    if (last === null || last.promptTokens <= 0 || last.cachedTokens <= 0) {
      return '';
    }
    return Math.min(100, Math.round(last.cachedTokens * 100 / last.promptTokens)) + '%';
  }

  // 空态/禁用原因行（方案 A）：12fp 次要色 + 13vp 同色符号，位置在动作位上方——不再渲染
  // 禁用主键（禁用蓝底白字会被读成「可点但坏了」，有原因句就不需要灰键占位）
  @Builder
  ReasonRow(symbol: Resource, text: string) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(13)
        .fontColor([cardDescColor()])
      Text(text)
        .fontSize(12)
        .fontColor(cardDescColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 删除摘要键（两处装配共用：可重新压缩时与主键并列；压缩禁用时独居——删除不走压缩前置
  // 判据，能力照旧）。破坏性动作不做红色自绘，形制照既有次钮档
  @Builder
  DeleteSummaryKey() {
    Button('删除摘要')
      .fontColor(fallbackButtonFont(this.contentFallback, false))
      .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .layoutWeight(1)
      .onClick((): void => {
        this.confirmDeleteSummary();
      })
  }

  // 摘要只读井（方案 A）：wellBg + 12 圆角 + 0.5vp 发丝边 + 内距 12；正文定高内部滚动，
  // 卡片不再随摘要长度无限变高。★ 内层 SELF_ONLY = 到顶/到底不把余量交给外层半模态——
  // 外层面板不得被摘要滚动带着动，更不能误触拖拽关闭（先例 = ChatFontSection 展示卡
  // 「不把余量交给外层」；坑18：Scroll 默认 Center 对齐，短内容须 TopStart 顶对齐）
  @Builder
  SummaryWell() {
    Column() {
      Scroll() {
        Text(this.summaryRow !== null ? this.summaryRow.content : '')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
      .height(SUMMARY_SCROLL_HEIGHT)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY
      })
    }
    .width('100%')
    .padding(12)
    .borderRadius(SUMMARY_WELL_RADIUS)
    .backgroundColor(wellBg(this.appColorMode))
    .border({ width: 0.5, color: cardBorderColor(this.appColorMode) })
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 上下文压缩卡（卡内次序照宪法「功能设置卡布局次序」条：状态明细 → 说明小字 → 操作
  //    行）。★ 两卡方案 A：标题行右置状态徽标（未压缩弱化 / 已压缩强调）、状态明细分行、
  //    空态不渲染禁用主键改原因行、摘要正文进定高内滚井——动作可用性矩阵与旧版逐态一致，
  //    只改呈现 ──
  @Builder
  CompressCard() {
    Column({ space: 10 }) {
      // 标题行：标题吃满余宽 + 状态徽标右置（徽标 text/tone 是普通成员，父状态变化不自动
      // 刷新——按 summaryRow 两态分支重建，坑16 家族）
      Row({ space: 8 }) {
        Text('上下文压缩')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        if (this.summaryRow === null) {
          StatusBadge({ text: '未压缩', tone: BadgeTone.WEAK })
        } else {
          StatusBadge({ text: '已压缩', tone: BadgeTone.EMPHASIS })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 线→内容 12 = 外层 10 + 2（方案 A 三档间距：标题→线 10 / 线→内容 12 / 内容→动作 14）
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
        .margin({ bottom: 2 })
      // ① 状态明细：无摘要 = 零明细行（徽标已交代「未压缩」）；有摘要 = 节省量 + 覆盖范围 +
      // 两条 12fp 兜底（不可证边界 / 已被清空覆盖）+ 摘要折叠区
      if (this.summaryRow !== null) {
        Column({ space: 10 }) {
          Text(this.summarySavedText())
            .fontSize(13)
            .fontColor(cardTitleColor())
          if (this.summaryBoundaryText() !== '') {
            Text(this.summaryBoundaryText())
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          if (this.summaryUncertain()) {
            Text('这份摘要覆盖范围无法确定，未自动裁剪历史')
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          if (this.summaryObsoletedByClear()) {
            Text('已被清空覆盖，不再生效')
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          // 展开/收起整行点击保留；展开后正文进定高内滚井
          Row() {
            Text(this.summaryExpanded ? '收起摘要' : '展开摘要')
              .fontSize(13)
              .fontColor(cardTitleColor())
            Blank()
            SymbolGlyph(this.summaryExpanded ? $r('sys.symbol.chevron_up') :
              $r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([cardDescColor()])
          }
          .width('100%')
          .onClick((): void => {
            this.summaryExpanded = !this.summaryExpanded;
          })
          if (this.summaryExpanded) {
            this.SummaryWell()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      // ② 说明小字（操作行上方——布局次序条）
      Text('压缩只影响之后发送的内容，原消息仍保存在本机会话里')
        .fontSize(13)
        .fontColor(cardDescColor())
      // ③ 动作区（内容→动作 14 = 外层 10 + 4）：可用 = 主键（有摘要时并删除键）；禁用 =
      // 原因行在上 + 有摘要时仍保留删除键（删除能力照旧）
      Column({ space: 10 }) {
        if (this.compressDisabled()) {
          this.ReasonRow(this.compressReasonSymbol(), this.compressDisabledReason())
        }
        if (!this.compressDisabled()) {
          Row({ space: 10 }) {
            // 分支渲染（可用才渲染）后 enabled 已是恒真死条件，R5 删
            Button(this.summaryRow === null ? '压缩上下文' : '重新压缩')
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.onCompress();
              })
            if (this.summaryRow !== null) {
              this.DeleteSummaryKey()
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else if (this.summaryRow !== null) {
          Row({ space: 10 }) {
            this.DeleteSummaryKey()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 4 })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // ── 上下文清空卡（卡内次序照宪法「功能设置卡布局次序」条：状态明细 → 说明小字 → 操作
  //    行）。★ 两卡方案 A：标题行右置状态徽标（未清空弱化 / 已清空强调）、覆盖时刻分行、
  //    空态不渲染禁用主键改原因行、清空键降为淡彩次级（本卡成本为零且可撤销，压缩键才是
  //    推进型主键）──
  // 与压缩卡的分工：清空是**零成本本地动作**（不发请求、不删消息、清空后未发新内容前可
  // 撤销），压缩要花一次模型调用产出摘要；两者共用「当前上下文起点」这一语义（最新边界胜出）
  @Builder
  ClearCard() {
    Column({ space: 10 }) {
      // 标题行：徽标按 clearRow 两态分支重建（StatusBadge 普通成员不自刷，坑16 家族）
      Row({ space: 8 }) {
        Text('上下文清空')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        if (this.clearRow === null) {
          StatusBadge({ text: '未清空', tone: BadgeTone.WEAK })
        } else {
          StatusBadge({ text: '已清空', tone: BadgeTone.EMPHASIS })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 线→内容 12 = 外层 10 + 2（方案 A 三档间距）
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
        .margin({ bottom: 2 })
      // ① 状态明细：无清空 = 零明细行；已清空 = 覆盖时刻 + 不可证边界兜底句
      if (this.clearRow !== null) {
        Column({ space: 10 }) {
          if (this.clearBoundaryText() !== '') {
            Text(this.clearBoundaryText())
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          if (this.clearBoundaryUncertain()) {
            Text('边界范围无法确定，未裁剪历史')
              .fontSize(12)
              .fontColor(cardDescColor())
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      // ② 说明小字（操作行上方——布局次序条）
      Text('清空只影响之后发送的内容，原消息仍保存在本机会话里')
        .fontSize(13)
        .fontColor(cardDescColor())
      // ③ 动作区（内容→动作 14 = 外层 10 + 4）：可撤销 = 只露撤销键（不渲染禁用清空，也不
      // 重复「无需重复清空」）；可用 = 淡彩次级；其余 = 原因行。两者都不删数据，不做二次确认
      Column({ space: 10 }) {
        if (this.clearRow !== null && this.clearRevocable) {
          Row({ space: 10 }) {
            Button('撤销清空')
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.requestRevokeClear();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else if (!this.clearDisabled()) {
          Row({ space: 10 }) {
            // 同压缩键：分支渲染下 enabled 恒真，R5 删（样式函数第三参 true = 可用态）
            Button('清空上下文')
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.requestClear();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          this.ReasonRow(this.clearReasonSymbol(), this.clearDisabledReason())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 4 })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          // 首卡独立成件（2026-10-29 首卡改版笔）：主件曾越 1200 硬线，首卡按域级最小拆分
          // 迁出 ContextUsageOverviewCard（2026-11-09 起 = 40fp 占比大字 + 右两排 + 线性
          // 进度条 + 口径行与三列构成；环退役后仅输入条消费 ContextUsageRing）
          ContextUsageOverviewCard({ usage: $usage })
          // 明细卡仅窗口已知（P4：未知时不显占比与分段条，引导去配置）
          if (this.usage !== null && this.usage.hasData && this.usage.windowTokens > 0) {
            this.DetailCard()
          }
          // 请求构成卡（注入链治理 P3-b）：明细卡之后、动作卡之前——有发送轮定格段视图
          // 才显（null / 空段 = 零注入或未发送过）
          if (this.usage !== null && this.usage.injectSections !== null &&
            this.usage.injectSections.length > 0) {
            this.InjectCard()
          }
          // 压缩卡在 DetailCard 之后——动作面殿后。★ 无持久会话（隐私会话零落痕模式由宿主
          // 传 ''）压缩卡与清空卡同条件整卡不渲染：摘要/边界行同样必须落库才成立
          //（写库破零留痕红线）
          if (this.conversationId !== '') {
            this.CompressCard()
            this.ClearCard()
          }
          // 退役防回游：「上轮实际」「本会话累计」两卡已移入会话统计面板 SessionStatsSheet
          //（负向钉见 assert-ui-shape 会话统计组）；口径说明行已移入首卡右上角信息气泡
          //（负向钉见 assert-ui-shape 122 组——旧 Text 三元形态零回流）
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；Row 空占位——
          // Blank 在部分容器下编译 10905201，规范-半模态 §2 先例用 Row）
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('上下文用量', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
