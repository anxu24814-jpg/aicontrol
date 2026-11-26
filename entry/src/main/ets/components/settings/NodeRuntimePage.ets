// Node 运行环境管理页（2026-11-24 鸿蒙 Node 运行时门 4，任务书-鸿蒙Node运行时门4产品面与发布
// -20261124 §6 S2；母方案 = docs/方案-鸿蒙内置Node运行环境-20261120.md §2.6）：正式设置页——
// 运行环境状态与占用回显 +「检查环境」键（幂等拉起运行区，再点无副作用）+ 已装包只读清单 +
// 卡三维护（清空安装包 / 重建运行区 / 重启应用）。入口 = 工具调用页「Node 运行环境」行，紧跟
//「Python 运行环境」行（push 无参，路由 ROUTE_NODE_RUNTIME_PAGE）。
// 形制照同目录 PyRuntimePage.ets（自包 PageShell 壳 + 卡壳四件套 CARD_PANEL_WIDTH / padding(16) /
// cardBg / CARD_RADIUS；首卡 hero 深色渐变，常量取 Theme）。两处与 Python 页刻意不同：
//   ① 危险两键按《规范-行内按钮与光感》§1「危险文字键」档走灰底红字（dialog_confirm_red）——
//      Python 页两键仍是默认字色，属存量档位偏差，本笔不动它（不在白名单），同语义键以规范为准。
//   ② 置位待重启后首卡徽标改显「待重启」——运行区可能已被删，再挂「已就绪」是失真读数。
// 域逻辑单源 common/nodeexec/NodeAdmin.ets（路径 / 占用 / 清单 / 清空 / 重建 / 待重启旗），本页只做
// 用户面编排。★ 进页不自动启动运行时（不调 ensure / start）：只读状态与两项占用，拉起交给
//「检查环境」键。未启动再只读探查运行区是否已释放——已释放呈「待启动」，未释放呈「未启动」
//（两者都不拉起引擎；不区分会把已释放的运行区说成未释放，与 Python 页进页口径不一致）。
// 危险动作确认弹窗 = UIContext promptAction.showDialog（宪法 UIContext 形态；ChatMoreMenu /
// ProviderDetailPage 同形制先例），确认键危险红。departed 守卫照 PyRuntimePage 先例（上下文显式取
// getHostContext；置位后迟到异步回调不写状态、不碰 UI）。
// 无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。版本串原文照显（技术内容不受文案规约）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PageShell } from '../../common/PageShell';
import { codeFontFamilyNow } from '../../common/ChatFont';
import { CARD_PANEL_WIDTH, CARD_RADIUS, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, HERO_CARD_ACTION_HEIGHT, HERO_CARD_BADGE_BG, HERO_CARD_BADGE_TEXT,
  HERO_CARD_COPY_MIN_HEIGHT, HERO_CARD_DANGER, HERO_CARD_DIVIDER, HERO_CARD_LABEL,
  HERO_CARD_SUCCESS, HERO_CARD_TEXT, HERO_CARD_TEXT_DIM, heroCardColors,
  heroCardMidColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { SETTING_TITLE_NODE_RUNTIME } from '../../common/SettingSearch';
import { isNodeProcessStarted, nodeRuntimePlaced } from '../../common/nodeexec/NodeRuntime';
import { prepareRuntimeOnce } from '../../common/nodeexec/NodeSchedulerCore';
import { NodeStatusReceipt, queryNodeStatus } from '../../common/nodeexec/NodeScheduler';
import { nodeInstallInFlight } from '../../common/nodeexec/NodeInstallScheduler';
import { NODE_INSTALL_QUOTA_BYTES, NodeClearResult, NodeInstalledList,
  NodeInstalledPackage, NodeRebuildResult, nodeClearInstallArea, nodeInstalledPackages,
  nodeInstallUsageBytesAsync, nodeNeedsRestart, nodeRebuildRuntimeArea, nodeRestartPageNote,
  nodeRuntimeUsageBytesAsync } from '../../common/nodeexec/NodeAdmin';

// 清空 / 重建两种域件结果的共用读法（页面只取 ok 与 note 两个共有字段）
type NodeAdminOutcome = NodeClearResult | NodeRebuildResult;

// 清空安装包被安装挡住时的提示（点击时与确认返回后共用一句）
const NODE_INSTALL_BUSY_TOAST: string = '正在安装，请稍后再清理。';

// 运行态五值文案（徽标；另派生一个「待重启」见 stateBadgeText）。「待启动」= 运行区已释放但
// 引擎未在本进程启动（冷启后常态），与「未启动」（运行区未释放）分列——原二者同显「未启动」，
// 主视觉又统一说「运行环境未释放」，把已释放的运行区说成未释放
const NODE_STATE_IDLE: string = '未启动';
const NODE_STATE_RELEASED: string = '待启动';
const NODE_STATE_PREPARING: string = '准备中';
const NODE_STATE_READY: string = '已就绪';
const NODE_STATE_FAILED: string = '运行异常';
// 待重启态徽标（管理页清空 / 重建后置位，重启自然复位）
const NODE_STATE_NEEDS_RESTART: string = '待重启';
// 已装包列表显示条数封顶——条数随安装无界增长，行卡轻走组卡 ForEach（《规范-列表卡片与组卡》§2
// 容器选型表：设置类组卡 = Scroll + Column + ForEach），封顶守「长列表不全量创建」性能红线；
// 超出部分列汇总行，完整清单以安装区为准
const INSTALLED_LIST_MAX_ROWS: number = 200;
// 重启目标回退常量（want 的 bundleName / abilityName 优先取上下文 abilityInfo；取不到才用——
// 硬编码先例 = ChatBgReply.ets 的 bundleName / abilityName 两字段）
const NODE_RESTART_FALLBACK_BUNDLE_NAME: string = 'com.jueming.aicontrol.chat';
const NODE_RESTART_FALLBACK_ABILITY_NAME: string = 'EntryAbility';

// 占用数值（MB 一位小数——首卡主视觉大数字只吃数值，单位「MB」由卡内固定文案承担；
// 不走 formatWorkspaceSize，理由同 PyRuntimePage）
function formatNodeMbValue(bytes: number): string {
  return (bytes / (1024 * 1024)).toFixed(1);
}

@Component
export struct NodeRuntimePage {
  // 页面存活守卫（1712 纪律）：置位后迟到异步回调不写状态、不碰 UI；promise 照常 resolve 不吞
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 运行态（首卡徽标；四值 = NODE_STATE_*）
  @State runtimeState: string = NODE_STATE_IDLE;
  // 失败原因（仅「运行异常」态有值；主视觉文字态显示，徽标不重复）
  @State failNote: string = '';
  // 版本串（「检查环境」或进页读到就绪后回显，等宽字；形如 Node v24.22.3 · npm 11.19.1）
  @State versionText: string = '';
  // 运行区占用字节（-1 = 未统计或统计失败，如实展示）
  @State runtimeUsageBytes: number = -1;
  // 安装区占用字节（-1 = 未统计或统计失败）
  @State installUsageBytes: number = -1;
  // 占用统计在跑（异步面——状态行旁显示统计中；★ 禁同步遍历，数千件递归 stat 会卡进页转场帧）
  @State usageBusy: boolean = false;
  // 占用统计世代号：发起时自增作废在途统计，仅最新世代可回填（防迟到读数覆盖）
  private usageEpoch: number = 0;
  // 「检查环境」在跑（期间禁重复触发键——准备单飞在 Core，此处只管 UI 互斥）
  @State checkBusy: boolean = false;
  // 已装包清单（显示用，已按条数封顶截取；进页现读 / 清空后重读）
  @State installed: NodeInstalledPackage[] = [];
  // 已装包总数（封顶前的真实条数，供汇总行用）
  @State installedTotal: number = 0;
  // 清单读不出的原因（非空 = 清单不可用，如实显示，不把读不出说成没装包）
  @State installedParseError: string = '';
  // 清空 / 重建执行中（期间两危险键禁用，进度行显示）
  @State actionBusy: boolean = false;
  // 进度文本（busy 时随进度行显示）
  @State actionNote: string = '';
  // 待重启态（进页读 NodeAdmin 进程旗 + 本页清空 / 重建完成后置位；置位后「检查环境」与两危险键
  // 禁用、「重启应用」键出现）
  @State needsRestart: boolean = false;
  // 待重启提示行文案（域件给出——成功句或残留句；删除途中退页再进来读到的还是同一句）
  @State restartNote: string = '';
  // 已点过「重启应用」（点击后禁键，防连点；调用抛错时复位让用户能重试）
  @State restartRequested: boolean = false;

  aboutToAppear(): void {
    // 进页现读进程旗与已装清单（清单是单个 JSON 文件的同步读，量级同 Python 页读安装记录）
    this.needsRestart = nodeNeedsRestart();
    this.restartNote = nodeRestartPageNote();
    this.refreshInstalled();
    this.refreshUsage(true);
    if (this.needsRestart) {
      return; // 待重启态不查状态——运行区可能已删，读数以提示行为准
    }
    // 只读状态：未启动时再探一次运行区是否已释放（nodeRuntimePlaced 纯读 `.ready` 与八件尺寸，
    // 不落位、不启动、不写盘）。已释放给「待启动」——用户只需点检查把引擎拉起来，不必担心重新
    // 释放；未释放才给「未启动」。两条都不发请求、不拉起运行时
    if (!isNodeProcessStarted()) {
      this.runtimeState = nodeRuntimePlaced() ? NODE_STATE_RELEASED : NODE_STATE_IDLE;
      return;
    }
    this.refreshStatus();
  }

  // 状态读取（只读：queryNodeStatus 不启动运行时、不进 lane）
  private refreshStatus(): void {
    queryNodeStatus().then((status: NodeStatusReceipt): void => {
      if (this.departed) {
        return;
      }
      this.applyStatus(status);
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.runtimeState = NODE_STATE_FAILED;
      this.failNote = e.message;
    });
  }

  // 状态回执落状态行（prepare 取值域与 Node 侧 runtime-setup 状态契约同源：running / ready / failed）
  private applyStatus(status: NodeStatusReceipt): void {
    const parts: string[] = [];
    if (status.nodeVersion !== undefined && status.nodeVersion !== '') {
      parts.push('Node ' + status.nodeVersion);
    }
    if (status.npmVersion !== undefined && status.npmVersion !== '') {
      parts.push('npm ' + status.npmVersion);
    }
    if (parts.length > 0) {
      this.versionText = parts.join(' · ');
    }
    if (!status.ok) {
      this.runtimeState = NODE_STATE_FAILED;
      this.failNote = status.error !== undefined && status.error !== '' ? status.error : '状态读取失败';
      return;
    }
    if (status.prepare === 'failed') {
      this.runtimeState = NODE_STATE_FAILED;
      this.failNote = status.prepareError !== undefined && status.prepareError !== ''
        ? status.prepareError : '内置运行环境准备失败';
      return;
    }
    this.runtimeState = status.prepare === 'ready' ? NODE_STATE_READY : NODE_STATE_PREPARING;
    this.failNote = '';
  }

  // 已装清单重读（进页 / 清空完成后调用；整体换引用触发 @State 刷新）
  private refreshInstalled(): void {
    const list: NodeInstalledList = nodeInstalledPackages();
    this.installedParseError = list.parseError;
    this.installedTotal = list.packages.length;
    this.installed = list.packages.length > INSTALLED_LIST_MAX_ROWS
      ? list.packages.slice(0, INSTALLED_LIST_MAX_ROWS) : list.packages;
  }

  // 占用统计（异步面，fire-and-forget；世代号防迟到读数覆盖——检查流开始时自增即作废在途统计）。
  // includeRuntime = false 用于只动了安装区的场景（清空后），不重扫运行区两千来个文件。
  // 域件内部单件失败按 0 跳过不抛；这里的 catch 只兜异常，读数保持 -1 如实展示
  private refreshUsage(includeRuntime: boolean): void {
    this.usageBusy = true;
    const epoch: number = ++this.usageEpoch;
    const reads: Promise<number>[] = [
      nodeInstallUsageBytesAsync().then((bytes: number): number => {
        if (!this.departed && epoch === this.usageEpoch) {
          this.installUsageBytes = bytes >= 0 ? bytes : -1;
        }
        return bytes;
      })
    ];
    if (includeRuntime) {
      reads.push(nodeRuntimeUsageBytesAsync().then((bytes: number): number => {
        if (!this.departed && epoch === this.usageEpoch) {
          this.runtimeUsageBytes = bytes >= 0 ? bytes : -1;
        }
        return bytes;
      }));
    }
    Promise.all(reads).catch((): void => {
      // 占用未知：读数留 -1，页面显示统计中，不造数
    }).finally((): void => {
      if (!this.departed && epoch === this.usageEpoch) {
        this.usageBusy = false;
      }
    });
  }

  // 检查环境：准备单飞（落位 + 启动，幂等——已启动直接读回当前端点）→ 读状态 → 重发占用统计。
  // needsRestart 态拒查——运行区可能已删，拉起会让它在本进程重新落位，绕过「重启后生效」设计
  private doCheck(): void {
    if (this.checkBusy) {
      return;
    }
    if (nodeNeedsRestart()) {
      // 旗可能由另一页面实例置位（设置搜索与本页可双开），本页状态还没跟上——就地同步为
      // 待重启态再拒，防「检查环境」不经重启就重落运行区（绕过「重启后生效」设计）
      this.needsRestart = true;
      this.restartNote = nodeRestartPageNote();
      return;
    }
    this.checkBusy = true;
    this.usageEpoch += 1; // 检查流接管状态行——进页发起的在途占用统计一律作废
    this.runtimeState = NODE_STATE_PREPARING;
    this.failNote = '';
    prepareRuntimeOnce().then((): Promise<NodeStatusReceipt> => queryNodeStatus())
      .then((status: NodeStatusReceipt): void => {
        if (this.departed) {
          return;
        }
        this.applyStatus(status);
        this.refreshUsage(true);
      }).catch((e: Error): void => {
        if (this.departed) {
          return;
        }
        this.runtimeState = NODE_STATE_FAILED;
        this.failNote = e.message;
        this.usageBusy = false; // 进页统计已被作废而失败分支不重发——显式收标志，防常驻
      }).finally((): void => {
        if (!this.departed) {
          this.checkBusy = false;
        }
      });
  }

  // 危险动作确认（UIContext promptAction.showDialog 形态）。返回是否点了确认键；弹窗异常 = 显式
  // toast 不静默吞（宁可不执行）。确认键危险红——两动作都是破坏性操作
  private async confirmDanger(title: string, message: string, confirmLabel: string): Promise<boolean> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: title,
        message: message,
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: confirmLabel, color: $r('app.color.dialog_confirm_red') }
        ]
      });
      return choice.index === 1;
    } catch (e) {
      if (!this.departed) {
        this.getUIContext().getPromptAction().showToast({ message: '确认框未弹出，请重试' });
      }
      return false;
    }
  }

  // 清空 / 重建共通骨架：确认 → 执行前守卫复查 → 执行 → 锁页 + 重读清单与占用 → 失败 toast →
  // busy 复位；departed 后一律不写状态。锁页读域件的旗而不硬置——域件在上下文未注入时直接回失败
  // 且不置旗，页面不进待重启态（那时什么都没删）。guard = 执行前复查（回 false = 已提示并中止）
  private async runDangerAction(title: string, message: string, confirmLabel: string,
    guard: () => boolean, action: () => Promise<NodeAdminOutcome>, busyNote: string,
    refreshRuntimeUsage: boolean): Promise<void> {
    const confirmed: boolean = await this.confirmDanger(title, message, confirmLabel);
    if (!confirmed || this.departed) {
      return;
    }
    if (!guard()) {
      return;
    }
    this.actionBusy = true;
    this.actionNote = busyNote;
    try {
      const outcome: NodeAdminOutcome = await action();
      if (this.departed) {
        return;
      }
      this.needsRestart = nodeNeedsRestart();
      this.restartNote = nodeRestartPageNote();
      if (!outcome.ok) {
        this.getUIContext().getPromptAction().showToast({ message: outcome.note });
      }
      this.refreshInstalled();
      this.refreshUsage(refreshRuntimeUsage);
    } catch (e) {
      if (!this.departed) {
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      }
    } finally {
      if (!this.departed) {
        this.actionBusy = false;
        this.actionNote = '';
      }
    }
  }

  // 安装是否空闲（清空安装包的执行前提——安装进行中清空会删到装了一半的安装区）。
  // 在飞则 toast 并回 false；点击时与确认返回后各查一次（确认卡弹出期间助手仍可能发起安装）
  private installIdleNow(): boolean {
    if (nodeInstallInFlight()) {
      this.getUIContext().getPromptAction().showToast({ message: NODE_INSTALL_BUSY_TOAST });
      return false;
    }
    return true;
  }

  private doClear(): void {
    if (this.actionBusy || this.needsRestart) {
      return;
    }
    if (!this.installIdleNow()) {
      return;
    }
    this.runDangerAction('清空安装包',
      '将删除本机已装的全部包与安装记录，不删会话内容与文件工作区。正在运行的 Node 会话可能中途失败。' +
        '完成后需重启应用，重启会中断正在进行的对话。',
      '清空', (): boolean => this.installIdleNow(),
      (): Promise<NodeAdminOutcome> => nodeClearInstallArea(), '正在清空安装包', false);
  }

  private doRebuild(): void {
    if (this.actionBusy || this.needsRestart) {
      return;
    }
    this.runDangerAction('重建运行区',
      '将删除整个 Node 运行区，重启应用后自动重新释放，已装的包保留。正在运行的 Node 会话可能中途失败。' +
        '完成后需重启应用，重启会中断正在进行的对话。',
      '重建', (): boolean => true,
      (): Promise<NodeAdminOutcome> => nodeRebuildRuntimeArea(), '正在重建运行区', true);
  }

  // 重启应用（官方 ApplicationContext.restartApp，API 12 起）：重启进程并回到应用，清空 / 重建在新
  // 进程里自然生效。约束 = 主线程调用、应用须有焦点、3 秒内不可重复（官方指南《应用重启》）——
  // 前台点按满足前两条，连点由 restartRequested 挡；失败（如 16000064 重启过频）toast 中文原因并
  // 复位键，守卫保留
  private doRestart(): void {
    if (this.restartRequested) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '应用上下文不可用，请手动退出应用后重新打开' });
      return;
    }
    const bundleName: string = ctx.abilityInfo.bundleName !== ''
      ? ctx.abilityInfo.bundleName : NODE_RESTART_FALLBACK_BUNDLE_NAME;
    const abilityName: string = ctx.abilityInfo.name !== ''
      ? ctx.abilityInfo.name : NODE_RESTART_FALLBACK_ABILITY_NAME;
    this.restartRequested = true;
    try {
      ctx.getApplicationContext().restartApp({ bundleName: bundleName, abilityName: abilityName });
    } catch (e) {
      this.restartRequested = false;
      const err = e as BusinessError;
      const reason: string = err.code !== undefined ? '，错误码 ' + err.code : '';
      this.getUIContext().getPromptAction().showToast({
        message: '重启应用失败' + reason + '，请手动退出应用后重新打开'
      });
    }
  }

  // ── 首卡展示派生（纯读函数，不持状态）──

  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 徽标文案：待重启态优先于一切读数
  private stateBadgeText(): string {
    return this.needsRestart ? NODE_STATE_NEEDS_RESTART : this.runtimeState;
  }

  // 徽标点色：已就绪浅绿 / 运行异常浅红 / 其余（未启动、待启动、准备中、待重启）灰白
  private stateDotColor(): string {
    if (this.needsRestart) {
      return HERO_CARD_TEXT_DIM;
    }
    if (this.runtimeState === NODE_STATE_READY) {
      return HERO_CARD_SUCCESS;
    }
    return this.runtimeState === NODE_STATE_FAILED ? HERO_CARD_DANGER : HERO_CARD_TEXT_DIM;
  }

  // 主视觉是否走大数字分支：已就绪、非检查中、且有运行区读数（旧读数不许顶在其他态的徽标下面）
  private showUsageNumber(): boolean {
    return this.runtimeUsageBytes >= 0 && this.runtimeState === NODE_STATE_READY
      && !this.checkBusy && !this.needsRestart;
  }

  // 主视觉文字态（与大数字同槽；不重复徽标已说的字）
  private visualLabel(): string {
    if (this.needsRestart) {
      return this.restartNoteText();
    }
    if (this.checkBusy) {
      return '正在准备运行环境';
    }
    if (this.runtimeState === NODE_STATE_FAILED) {
      return this.failNote !== '' ? this.failNote : '运行环境不可用';
    }
    // 已释放未启动：占用统计与本态展示无关（大数字只归已就绪），故排在 usageBusy 之前，
    // 免进页统计期间先闪一句「正在统计占用」再跳回本句
    if (this.runtimeState === NODE_STATE_RELEASED) {
      return '运行环境已释放，点检查启动';
    }
    if (this.usageBusy && this.runtimeUsageBytes < 0) {
      return '正在统计占用';
    }
    return '运行环境未释放';
  }

  private visualLabelColor(): string {
    return this.runtimeState === NODE_STATE_FAILED && !this.needsRestart ? HERO_CARD_DANGER : HERO_CARD_TEXT;
  }

  // 待重启提示行（域件给的成功句或残留句；域件没落下提示时兜底一句）
  private restartNoteText(): string {
    return this.restartNote !== '' ? this.restartNote : '重启应用后生效';
  }

  // 口径行是否回显版本串（读到过就显示，等宽字）
  private showVersionCaption(): boolean {
    return this.versionText !== '';
  }

  // 口径行说明句（版本串缺位时消费）：待重启态指路重启（此时检查键已禁用，不能再讲首检），
  // 运行异常指路重试，已释放讲重复检查不重拷，其余（未释放）才讲首检
  private captionHint(): string {
    if (this.needsRestart) {
      return '重启应用后再检查运行环境';
    }
    if (this.runtimeState === NODE_STATE_FAILED) {
      return '可再次检查重试';
    }
    if (this.runtimeState === NODE_STATE_RELEASED) {
      return '重复检查无副作用，不会重新释放运行区';
    }
    return '首次检查会释放内置运行环境，重复检查无副作用';
  }

  // 安装区占用行（常显；读数未知时如实说统计中）
  private installUsageText(): string {
    if (this.installUsageBytes < 0) {
      return '安装区占用统计中';
    }
    return '安装区 ' + formatNodeMbValue(this.installUsageBytes) + ' MB，上限 '
      + (NODE_INSTALL_QUOTA_BYTES / (1024 * 1024)) + ' MB';
  }

  // 卡二说明行（清单读得出时带总数）
  private installedSummaryText(): string {
    if (this.installedParseError !== '') {
      return '已安装的包由助手在对话里安装，清单以安装区为准';
    }
    return '共 ' + this.installedTotal + ' 个，清单以安装区为准';
  }

  private installedOverflowCount(): number {
    return this.installedTotal > this.installed.length ? this.installedTotal - this.installed.length : 0;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 首卡「运行环境」（hero 深色渐变，形制 = PyRuntimePage 首卡：标签 + 状态徽标 → 主视觉 →
        // 口径行 → 安装区占用行 → 细线 → 文字动作行）
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('运行环境')
              .fontSize(13)
              .fontColor(HERO_CARD_LABEL)
            Blank()
            Row({ space: 5 }) {
              Column()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.stateDotColor())
              Text(this.stateBadgeText())
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(HERO_CARD_BADGE_TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(22)
            .padding({ left: 8, right: 8 })
            .borderRadius(6)
            .backgroundColor(HERO_CARD_BADGE_BG)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 主视觉：已就绪且有占用读数 = 大数字 + 单位；其余态 = 文字态包同高块并底对齐（块高恒定，
          // 切态时卡高不跳）
          if (this.showUsageNumber()) {
            Row({ space: 5 }) {
              Text(formatNodeMbValue(this.runtimeUsageBytes))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(HERO_CARD_TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('MB')
                .fontSize(13)
                .fontColor(HERO_CARD_TEXT_DIM)
                .margin({ bottom: 5 })
            }
            .width('100%')
            .constraintSize({ minHeight: HERO_CARD_COPY_MIN_HEIGHT })
            .alignItems(VerticalAlign.Bottom)
          } else {
            Row() {
              Text(this.visualLabel())
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.visualLabelColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .constraintSize({ minHeight: HERO_CARD_COPY_MIN_HEIGHT })
            .alignItems(VerticalAlign.Bottom)
          }
          // 口径行说明在动作行上方（宪法「功能设置卡布局次序」条）：版本串等宽回显；未读到时按态
          // 给说明句（普通字体——等宽只给技术串）
          if (this.showVersionCaption()) {
            Text(this.versionText)
              .fontSize(12)
              .fontFamily(codeFontFamilyNow())
              .fontColor(HERO_CARD_TEXT_DIM)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else {
            Text(this.captionHint())
              .fontSize(13)
              .fontColor(HERO_CARD_TEXT_DIM)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          Text(this.installUsageText())
            .fontSize(12)
            .fontColor(HERO_CARD_TEXT_DIM)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Divider()
            .strokeWidth(0.5)
            .color(HERO_CARD_DIVIDER)
            .margin({ top: 4 })
          // 卡内检查键（深卡无实底键——图标 + 文字；busy 与待重启态降不透明度，守卫在 doCheck 内）
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(16)
              .fontColor([HERO_CARD_TEXT])
            Text(this.checkBusy ? '检查中' : '检查环境')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(HERO_CARD_TEXT)
          }
          .width('100%')
          .height(HERO_CARD_ACTION_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .opacity(this.checkBusy || this.needsRestart ? 0.6 : 1)
          .onClick((): void => {
            this.doCheck();
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(heroCardMidColor(this.isDarkMode()))
        .linearGradient({
          angle: 135,
          colors: heroCardColors(this.isDarkMode())
        })
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // 卡二「已安装的包」——安装区 package-lock.json 第一层包的只读清单（行 = 名称@版本；
        // 键覆盖行内全部可变展示成分——列表键纪律）
        Column({ space: 10 }) {
          Text('已安装的包')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text(this.installedSummaryText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          if (this.installedParseError !== '') {
            Text(this.installedParseError)
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          } else if (this.installedTotal === 0) {
            Text('还没有安装任何包，让助手在对话里安装后这里会列出来')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          } else {
            Column({ space: 8 }) {
              ForEach(this.installed, (pkg: NodeInstalledPackage) => {
                Text(pkg.name + '@' + pkg.version)
                  .fontSize(13)
                  .fontColor(cardTitleColor())
                  .width('100%')
              }, (pkg: NodeInstalledPackage): string => pkg.name + '@' + pkg.version)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            if (this.installedOverflowCount() > 0) {
              Text('另有 ' + this.installedOverflowCount() + ' 个未列出')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 卡三「维护」——说明小字在按钮行上方（先说明后操作）→ 待重启提示行 → 进度行 → 危险两键
        // → 待重启后出现的「重启应用」键
        Column({ space: 10 }) {
          Text('维护')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('清空安装包会删除本机已装的全部包与安装记录，不删会话内容与文件工作区。重建运行区会删除运行环境，重启应用后重新释放，已装的包保留。两个动作都需要重启应用才生效，重启会中断正在进行的对话。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          if (this.needsRestart) {
            Text(this.restartNoteText())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          if (this.actionBusy) {
            Row({ space: 6 }) {
              Text(this.actionNote)
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              LoadingProgress()
                .width(14)
                .height(14)
                .color(cardDescColor())
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .width('100%')
          // 危险两键：灰底次钮档 + 危险红字（规范 §1「危险文字键」；字色由红覆盖，不再调字体件）
          Button('清空安装包')
            .width('100%')
            .fontColor($r('app.color.dialog_confirm_red'))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .enabled(!this.actionBusy && !this.needsRestart)
            .onClick((): void => {
              this.doClear();
            })
          Button('重建运行区')
            .width('100%')
            .fontColor($r('app.color.dialog_confirm_red'))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .enabled(!this.actionBusy && !this.needsRestart)
            .onClick((): void => {
              this.doRebuild();
            })
          // 「重启应用」键：待重启后出现，卡内文字动作行（与「检查环境」同形：图标 + 文字）；
          // 无底 TEXTUAL 带官方按压反馈，强调色。待重启期间恒可点——只防同页连点
          if (this.needsRestart) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_emphasize')])
                Text('重启应用')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_emphasize'))
              }
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .width('100%')
            .height(HERO_CARD_ACTION_HEIGHT)
            .enabled(!this.restartRequested)
            .opacity(this.restartRequested ? 0.4 : 1)
            .onClick((): void => {
              this.doRestart();
            })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
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
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_NODE_RUNTIME,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
