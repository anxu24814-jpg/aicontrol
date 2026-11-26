// Node 运行验证页（2026-11-23 鸿蒙 Node 运行时门 1 笔引入；门 2 U1 笔最小接线：
// 落位 / 启动 / 单请求改走 common/nodeexec 的 NodeRuntime / NodeBridge——本页不再自持
// 落位与端口轮询逻辑，rawfile 四件字节对账、endpoint 读取、token 握手、冷启残留处置都
// 收敛到 nodeexec 域）。六步状态直读（nodeEngine.status()）与探针脚本回显保留。
// · 三常量（NODE_PROBE_ENABLED / NODE_PROBE_TITLE / NODE_PROBE_SCRIPT）随本页走（任务书
//   门 2 §0 代决：推翻门 1 书「迁走」预定，留作诊断 UI 契约）；`import nodeEngine from
//   'libnodeengine.so'` 是 assert-app-domain 2245 组判据，删掉即红。
// 门 2 U1 行为面：启动后 endpoint 显示所选通道（交付态 tcp）；执行探针在 prepare 未就绪
// 时如实呈现 not-ready / prepare-failed（执行域内核归 S3，诊断面收口归 S4）。
// · 门 2 U4a 诊断面收口：执行探针改走执行域进口 `executeNodeCode`（lane 外准备 + 串行 lane +
//   会话 worker），并新增执行域状态（`queryNodeStatus`）与取消（`cancelNodeForConversation`）
//   两个诊断键——保存的 `bridgeRequest` 不再由本页消费（执行域请求唯一发送口 =
//   NodeScheduler → requestNodeBridge）。探针会话 id 是固定诊断串，不对应真实会话行。
// · 自包 PageShell 壳；无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../common/PageShell';
import { codeFontFamilyNow } from '../common/ChatFont';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../common/ImmersiveLevel';
import nodeEngine from 'libnodeengine.so';
import { ensureNodeRuntimePlacement, isNodeProcessStarted, NODE_HOME_DIR_NAME,
  nodeRuntimeHomePath, peekNodeEndpoint, startNodeRuntime, NodeRuntimeStartOutcome }
  from '../common/nodeexec/NodeRuntime';
// 执行域进口（门 2 U4a 诊断面收口）：探针执行 / 取消 / 状态三键全部直调调度器——lane、代次
// 与槽位释放逻辑单点在 NodeScheduler，探针页不另写排队
import { cancelNodeForConversation, executeNodeCode, queryNodeStatus, NodeExecReceipt,
  NodeExecRequest, NodeLaneAdmitContext, NodeStatusReceipt } from '../common/nodeexec/NodeScheduler';

// 探针入口构建期开关（照 Python 探针页先例：常态 false 不进产物；真机验证轮临时翻 true
// 重构建，验证完复位 false——2026-11-23 开闸轮翻 true 出验证包，门 1 九项真机通过后本笔
// 复位 false；需复测时再翻）
export const NODE_PROBE_ENABLED: boolean = false;

// 门 1 临时入口行文案（探针页标题与入口共用单源——改文案两处自动一致）
export const NODE_PROBE_TITLE: string = 'Node 运行验证';

// 探针页固定诊断脚本（任务书 U3-5：四行固定判据——版本、平台、算式、fs 写读回环；
// 第五行 = worker 线程冒烟。输出走执行域注入的 print（console 捕获同源），不依赖 console
// 全局。S1 单元 prepare 未就绪时该脚本提交会被如实拒——执行语义归 S3）
export const NODE_PROBE_SCRIPT: string = [
  'print(\'version\', process.version)',
  'print(\'platform\', process.platform)',
  'print(\'calc\', 6 * 7)',
  'const fs = require(\'node:fs\')',
  'const path = require(\'node:path\')',
  'const probePath = path.join(process.env.HOME, \'probe-io.txt\')',
  'fs.writeFileSync(probePath, \'node-ok\')',
  'print(\'fs\', fs.readFileSync(probePath, \'utf8\'))',
  'try {',
  '  const { Worker } = require(\'node:worker_threads\')',
  '  const sab = new SharedArrayBuffer(4)',
  '  const arr = new Int32Array(sab)',
  "  const w = new Worker(\"const { workerData } = require('node:worker_threads'); const a = new Int32Array(workerData); Atomics.store(a, 0, 42); Atomics.notify(a, 0);\", { eval: true, workerData: sab })",
  "  w.on('error', function () {})",
  "  print('worker', Atomics.wait(arr, 0, 0, 5000), Atomics.load(arr, 0))",
  '  w.terminate()',
  '} catch (e) {',
  "  print('worker error', e && e.message ? e.message : String(e))",
  '}'
].join('\n');

// 输出区高度上限（固定数值——宪法「渲染克制」条）
const NODE_PROBE_OUTPUT_HEIGHT: number = 320;

// 探针会话标识（诊断用固定串，不对应真实会话行）：conversationId 与 sessionId 同值——执行域
// 以会话为隔离单位，bootstrap 每 sessionId 一个长期 worker；取消键只作用于本会话
const PROBE_CONVERSATION_ID: string = 'node-probe';
const PROBE_SESSION_ID: string = 'node-probe';
// 执行域状态行与取消状态行的空态文案（不造数）
const NODE_PROBE_STATUS_IDLE: string = '未查询';
const NODE_PROBE_CANCEL_IDLE: string = '未发送';

// 引擎状态（契约同构：types/libnodeengine/index.d.ts 的 NodeEngineStatus）
interface NodeEngineStatus {
  threadAlive: boolean;
  shimInstalled: boolean;
  crashHandlerInstalled: boolean;
  envSet: boolean;
  dlopened: boolean;
  dlerror: string;
  startSymbol: boolean;
  nodeStarted: boolean;
  shimHits: number;
}

@Component
export struct NodeRuntimeProbePage {
  // 页面存活守卫（1712 纪律，照 PyRuntimeProbePage 先例）：置位后迟到异步回调不写状态
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 阶段状态行（运行区落位 / 启动 / 端点等待 / 就绪）
  @State phaseText: string = '尚未启动';
  // 六步里程碑状态行（status() 摘要直读）
  @State statusText: string = '状态未读取';
  // 探针执行状态行
  @State runStatusText: string = '未运行';
  // 执行域状态行（queryNodeStatus：通道 / 准备态 / workers / 版本 / 内存）
  @State execStatusText: string = NODE_PROBE_STATUS_IDLE;
  // 取消诊断状态行（cancelNodeForConversation 只递增本会话代次并转 bootstrap cancel）
  @State cancelStatusText: string = NODE_PROBE_CANCEL_IDLE;
  // 输出区文本（stdout 与错误拼合回显，等宽字）
  @State outputText: string = '';
  @State startBusy: boolean = false;
  @State runBusy: boolean = false;
  @State statusBusy: boolean = false;
  // UI 上下文（aboutToAppear 捕获——落位与启动都要显式传，U4 前不走 store 注入）
  private uiCtx: common.Context | undefined = undefined;
  // 启动曲线三段（门 1 取证口径延续）：t0 = start 调用前，t1 = 端点就绪，t2 = 首回执
  private startAtMs: number = 0;
  private readyAtMs: number = 0;
  private firstReplyAtMs: number = 0;
  // 运行区落位 promise（aboutToAppear 发起——NodeRuntime 单飞外壳承担并发）
  private placementPending: Promise<string> | null = null;

  // 六步里程碑状态（status() 返回 JSON 串直读；解析失败如实报错不造数）
  private refreshStatus(): void {
    let raw: string = '';
    try {
      raw = nodeEngine.status();
    } catch (e) {
      this.statusText = '状态读取失败，' + (e as Error).message;
      return;
    }
    try {
      const st: NodeEngineStatus = JSON.parse(raw) as NodeEngineStatus;
      const items: string[] = [];
      items.push(st.threadAlive ? '线程在' : '线程停');
      items.push(st.shimInstalled ? 'SIGSYS 已装' : 'SIGSYS 未装');
      items.push(st.crashHandlerInstalled ? '崩溃处理器已装' : '崩溃处理器未装');
      items.push(st.envSet ? '环境变量已设' : '环境变量未设');
      items.push(st.dlopened ? 'libnode 已载' : 'libnode 未载');
      items.push(st.startSymbol ? 'Start 符号已取' : 'Start 符号未取');
      items.push(st.nodeStarted ? 'Node 已启动' : 'Node 未启动');
      if (st.shimHits > 0) {
        items.push('shim 命中 ' + st.shimHits);
      }
      this.statusText = items.join('，');
      if (st.dlerror !== '') {
        this.statusText += '。错误 ' + st.dlerror;
      }
    } catch (e) {
      this.statusText = '状态串解析失败，原始内容 ' + raw;
    }
  }

  // 启动：等运行区落位 → NodeRuntime 启动编排（冷启残留处置 / 运行中恢复）→ 刷新状态
  private doStart(): void {
    if (this.startBusy) {
      return;
    }
    if (this.placementPending === null) {
      this.phaseText = '运行区文件未准备就绪，请重进本页';
      return;
    }
    this.startBusy = true;
    this.phaseText = '启动 Node 运行时';
    this.placementPending.then((): Promise<NodeRuntimeStartOutcome> => {
      if (this.departed) {
        return Promise.reject(new Error('页面已离开'));
      }
      this.startAtMs = Date.now();
      this.readyAtMs = 0;
      this.firstReplyAtMs = 0;
      return startNodeRuntime(this.uiCtx);
    }).then((outcome: NodeRuntimeStartOutcome): void => {
      if (this.departed) {
        return;
      }
      this.readyAtMs = Date.now();
      const channelText: string = outcome.endpoint.channel === 'uds'
        ? 'UDS socket'
        : '回环端口 ' + (outcome.endpoint.port !== undefined ? outcome.endpoint.port : 0);
      this.phaseText = '已就绪，通道 ' + outcome.endpoint.channel + '，' + channelText
        + (this.startAtMs > 0 ? '（t0→t1 ' + (this.readyAtMs - this.startAtMs) + ' ms）' : '');
      this.refreshStatus();
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.phaseText = '启动失败，' + e.message;
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.startBusy = false;
    });
  }

  // 执行回执渲染（执行域字段有什么显什么——如实呈现，不造数；events 只显头 5 行防挤占）
  private renderProbeReply(receipt: NodeExecReceipt): void {
    const parts: string[] = [];
    parts.push(receipt.ok ? '完成' : '失败');
    if (receipt.errorKind !== undefined) {
      parts.push('调度 ' + receipt.errorKind);
    }
    if (receipt.error !== undefined && receipt.error !== '') {
      parts.push('错误 ' + receipt.error);
    }
    parts.push('耗时 ' + receipt.elapsedMs + ' ms');
    if (receipt.workerStartMs > 0) {
      parts.push('worker 首启 ' + receipt.workerStartMs + ' ms');
    }
    if (receipt.sessionReset !== '') {
      parts.push('会话重置 ' + receipt.sessionReset);
    }
    if (receipt.evictedSessionIds.length > 0) {
      parts.push('淘汰 ' + receipt.evictedSessionIds.join('、'));
    }
    if (receipt.savedNames.length > 0) {
      parts.push('save ' + receipt.savedNames.join('、'));
    }
    if (receipt.nodeVersion !== '') {
      parts.push('版本 ' + receipt.nodeVersion);
    }
    if (receipt.platform !== '') {
      parts.push('平台 ' + receipt.platform);
    }
    parts.push('后台操作 ' + receipt.backgroundOps);
    if (receipt.memory !== undefined) {
      parts.push('rss ' + Math.round(receipt.memory.rss / 1048576) + ' MB');
      parts.push('heap ' + Math.round(receipt.memory.heapUsed / 1048576) + ' MB');
    }
    if (this.startAtMs > 0 && this.readyAtMs > 0) {
      if (this.firstReplyAtMs === 0) {
        this.firstReplyAtMs = Date.now();
      }
      parts.push('t0→t2 ' + (this.firstReplyAtMs - this.startAtMs) + ' ms');
      parts.push('t1→t2 ' + (this.firstReplyAtMs - this.readyAtMs) + ' ms');
    }
    if (receipt.cwd !== '') {
      parts.push('cwd ' + receipt.cwd);
    }
    this.runStatusText = parts.join('，');
    const out: string[] = [];
    if (receipt.stdout !== '') {
      out.push(receipt.stdout + (receipt.stdoutTruncated ? '\n（本轮输出已按上限截断）' : ''));
    }
    if (receipt.stderr !== '') {
      out.push(receipt.stderr);
    }
    if (receipt.error !== undefined && receipt.error !== '') {
      out.push('错误 ' + receipt.error);
    }
    if (receipt.events.length > 0) {
      const shown: string[] = receipt.events.slice(0, 5);
      const more: number = receipt.eventsTotal - shown.length;
      out.push('安全记录：\n' + shown.join('\n') +
        (more > 0 ? '\n另有 ' + more + ' 条未显示。' : ''));
    }
    this.outputText = out.length > 0 ? out.join('\n') : '暂无输出';
  }

  // 执行探针（直调执行域进口：lane 外准备 + 串行 lane + 会话 worker 全由 NodeScheduler 编排；
  // cwd 取运行区目录——探针不写本会话临时区，避免诊断数据混进真实会话目录）
  private doRun(): void {
    if (this.runBusy) {
      return;
    }
    const homeDir: string = nodeRuntimeHomePath() !== '' ? nodeRuntimeHomePath() :
      (this.uiCtx !== undefined ? this.uiCtx.filesDir + '/' + NODE_HOME_DIR_NAME : '');
    if (homeDir === '') {
      this.runStatusText = '应用上下文不可用，无法执行';
      return;
    }
    this.runBusy = true;
    this.runStatusText = '执行中';
    this.outputText = '';
    const req: NodeExecRequest = {
      conversationId: PROBE_CONVERSATION_ID,
      sessionId: PROBE_SESSION_ID,
      code: NODE_PROBE_SCRIPT,
      onLaneAdmitted: async (): Promise<NodeLaneAdmitContext> => {
        return { cwd: homeDir };
      }
    };
    executeNodeCode(req).then((receipt: NodeExecReceipt): void => {
      if (this.departed) {
        return;
      }
      this.renderProbeReply(receipt);
      this.refreshStatus();
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.runStatusText = '失败，' + e.message;
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.runBusy = false;
    });
  }

  // 执行域状态查询（只读：不启动运行时、不进 lane）
  private doQueryStatus(): void {
    if (this.statusBusy) {
      return;
    }
    this.statusBusy = true;
    this.execStatusText = '查询中';
    queryNodeStatus().then((st: NodeStatusReceipt): void => {
      if (this.departed) {
        return;
      }
      if (!st.ok) {
        this.execStatusText = '查询失败，' + (st.error !== undefined ? st.error : '未知原因');
        return;
      }
      const parts: string[] = [];
      parts.push('通道 ' + (st.channel !== undefined && st.channel !== '' ? st.channel : '未知'));
      parts.push('准备 ' + (st.prepare !== undefined && st.prepare !== '' ? st.prepare : '未知'));
      if (st.prepareError !== undefined && st.prepareError !== '') {
        parts.push('准备错误 ' + st.prepareError);
      }
      parts.push('worker ' + (st.workers !== undefined ? st.workers : 0) + ' 个');
      if (st.nodeVersion !== undefined && st.nodeVersion !== '') {
        parts.push('Node ' + st.nodeVersion);
      }
      if (st.npmVersion !== undefined && st.npmVersion !== '') {
        parts.push('npm ' + st.npmVersion);
      }
      if (st.memory !== undefined) {
        parts.push('rss ' + Math.round(st.memory.rss / 1048576) + ' MB');
      }
      this.execStatusText = parts.join('，');
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.execStatusText = '查询失败，' + e.message;
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.statusBusy = false;
    });
  }

  // 取消诊断（只作用于探针会话：排队者当场出队、在跑转 bootstrap cancel 终止该会话 worker；
  // 其他会话不受影响）
  private doCancel(): void {
    cancelNodeForConversation(PROBE_CONVERSATION_ID);
    this.cancelStatusText = '已发送取消（只作用于探针会话，不会影响真实会话）';
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 启动卡——说明小字在操作行上方（宪法「功能设置卡布局次序」条）
        Column({ space: 10 }) {
          Text('启动')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('进入本页会先准备运行区文件，点启动后再起 Node 运行时。重复点启动无副作用。运行时崩溃后需重启应用恢复。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Text(this.phaseText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .fontFamily(codeFontFamilyNow())
            .width('100%')
          Text(this.statusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .fontFamily(codeFontFamilyNow())
            .width('100%')
          Row({ space: 12 }) {
            Button('启动')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.startBusy)
              .onClick((): void => {
                this.doStart();
              })
            Button('刷新状态')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.refreshStatus();
              })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 执行域诊断卡（门 2 U4a：状态查询与取消都直达执行域，不启动运行时、不进 lane）
        Column({ space: 10 }) {
          Text('执行域诊断')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('查询执行域的准备状态与常驻数量，或向探针会话发送取消。两者都不启动运行时，也不占用执行位。取消只作用于探针会话，不影响真实会话。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Text(this.execStatusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .fontFamily(codeFontFamilyNow())
            .width('100%')
          Text(this.cancelStatusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Row({ space: 12 }) {
            Button('查询执行域状态')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.statusBusy)
              .onClick((): void => {
                this.doQueryStatus();
              })
            Button('取消探针会话')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.doCancel();
              })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 执行探针卡
        Column({ space: 10 }) {
          Text('执行探针')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('固定诊断脚本经执行域提交。首次执行会先准备运行区并启动 Node，随后进入串行队列。运行区就绪前会如实提示未就绪，输出显示在下方。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Text(this.runStatusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Button('执行探针')
            .fontSize(15)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.runBusy)
            .onClick((): void => {
              this.doRun();
            })
          // 输出区（可滚动等宽字回显——滚动容器显式 .scrollBar(BarState.Off) 宪法条款）
          Scroll() {
            Column() {
              Text(this.outputText === '' ? '暂无输出' : this.outputText)
                .fontSize(12)
                .fontFamily(codeFontFamilyNow())
                .fontColor(cardDescColor())
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height(NODE_PROBE_OUTPUT_HEIGHT)
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollBar(BarState.Off)
          .padding(8)
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
      title: NODE_PROBE_TITLE,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.phaseText = '应用上下文不可用，无法准备运行区文件';
      return;
    }
    this.uiCtx = ctx;
    this.phaseText = '准备运行区文件';
    this.placementPending = ensureNodeRuntimePlacement(ctx);
    this.placementPending.then((): void => {
      if (this.departed) {
        return;
      }
      // 页面重进恢复：运行时还在本进程内跑 → 直接读回当前 endpoint 显示就绪（node::Start
      // 不二调；端点不可读只等用户点启动走「运行中端点丢失」报错，不自动重启）
      if (isNodeProcessStarted()) {
        const endpoint = peekNodeEndpoint(ctx);
        if (endpoint !== null) {
          this.phaseText = '已就绪，通道 ' + endpoint.channel;
          this.refreshStatus();
          return;
        }
      }
      this.phaseText = '运行区已就绪，点启动';
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.phaseText = '运行区准备失败，' + e.message;
    });
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
