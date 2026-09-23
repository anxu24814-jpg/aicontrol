// 聊天消息数据源（2026-08-29 对话页 UI 对齐任务 1 自 dshinhm 同名文件骨架改造）：
// LazyForEach 的 IDataSource 单一事实源 + @Observed/@Track messageCount 空态驱动——
// 这两件「消息列表渲染基建」语义与 dshinhm 原样（@Track 字段经 @ObjectLink 订阅驱动
// 空态/错误态分支；键恒定 + 原地改字段 + @Observed→@ObjectLink 对象级观察刷新，二三四改
// 稳定键拍板语义）。kap 支路全部不迁：transcript 回放重建（rebuildFromTranscript/
// prependTranscriptItems/collectTurn/frameToMessage）、frameId 寻址增量（liveFrameIndex/
// upsertFrame/appendToFrame）、用户消息端点还原、retry 三方法（addRetryRow/removeRetryRow/
// findUserText——将来接重试功能时随错误处理逻辑一并迁）——aicontrol 数据流
// = ChatDb 尾部查询回放 + 页面侧 OpenAI 流式编排（appendThrottle/权威全量串在页面，
// 任务书拍板「接线不动」），本类只做容器 + 通知，不生成 id（DB 消息 id 与视图 id 同源
// nextMessageId，由页面统一生成）。
// ★ 2026-08-31 任务 D 触顶翻页：prepend 前插支路 + 翻页态（olderLoading/olderExhausted
// @Track——头部提示行两态驱动）+ seq 单键游标 oldestCursor（重建/前插时维护；2026-09-21
// 笔 3 切序单键化：原 createdAt+rowid 双键随读取权威切 seq 退役）——dshinhm
// 形态按 aicontrol 模型重写（ChatOlderCtrl / ChatPageLoadCtrl.loadOlder 消费）。
// 增量通知语义（原样）：尾部追加 notifyAdd / 清空与回放重建 notifyReload / 原地改字段
// 不通知（@Observed set 自驱动，键恒定 LazyForEach 无需重建——二三四改结论）。
// ★ 2026-09-06 空态分层：「加载中」≠「空会话」——@Track historyLoaded 标记历史加载已
// 完成（rebuildFromHistory 置 true / clear 复位），空态引导层判定 = messageCount===0 且
// historyLoaded（ChatPageContent）；加载中显示纯背景，进页转场动画中不再闪现引导页。
// 数据有界：消息窗口受 QUERY_TAIL_LIMIT（50）+ 进行中回合上限约束；页面级数据源，
// 页面销毁即释放，无全局持有。
import { MessageCursor, MessageRow, QUERY_TAIL_LIMIT } from '../../common/store/ChatDb';
import { parseMessageVariants } from '../../common/store/MessageVariantDb';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';

// role='tool' 行 content JSON 载荷（与 ChatToolRoundCtrl.ToolEventRecord 同构——库行单一真源）
interface ToolRowRecord {
  toolCallId?: string;
  name?: string;
  argsJson?: string;
  result?: string;
  isError?: boolean;
}

// 工具行 → 工具卡消息合成（回放路径；坏 JSON/缺键回 null 跳过——容错不炸历史重建）。
// 展示字段与流式路径（ChatSendCtrl 工具卡构造）同形制：input/output 存原串（展开区全文），
// 摘要行存紧凑预览，error 态 text 带错误摘要（warning 行渲染）
function toolCardFromRow(row: MessageRow): ChatMessage | null {
  let record: ToolRowRecord | null = null;
  try {
    record = JSON.parse(row.content) as ToolRowRecord;
  } catch (e) {
    return null;
  }
  if (record === null || typeof record.toolCallId !== 'string' || typeof record.name !== 'string') {
    return null;
  }
  const argsJson: string = typeof record.argsJson === 'string' ? record.argsJson : '{}';
  const result: string = typeof record.result === 'string' ? record.result : '';
  const isError: boolean = record.isError === true;
  const msg: ChatMessage = newChatMessage(row.id, 'tool', isError ? previewLine(result, 60) : '',
    record.name, isError ? 'error' : 'done');
  msg.toolCallId = record.toolCallId;
  msg.toolInputJson = argsJson;
  msg.toolInputText = previewLine(argsJson, 40);
  msg.toolOutputJson = result;
  msg.toolDisplayText = previewLine(result, 60);
  return msg;
}

// 单行紧凑预览（空白压一空格 + 超长截断；与 ChatToolRoundCtrl.compactPreview 同语义——
// 两处各自域内小函数，不跨层共享避免组件域反向依赖）
function previewLine(text: string, maxChars: number): string {
  const line: string = text.replace(/\s+/g, ' ').trim();
  return line.length > maxChars ? line.substring(0, maxChars) + '…' : line;
}

// 本轮残留清理结果（2026-09-20 重试真机修复笔；cleanRoundResidue 产物）：
// removedIds = 已移出消息流的行 id（DB 行由调用方同步删）；toolRound = 本轮是否工具轮
// 形态（区间内存在工具卡或中间 assistant 行——调用方据此走整轮作废路径）
export interface RoundResidue {
  removedIds: string[];
  toolRound: boolean;
}

@Observed
export class ChatDataSource implements IDataSource {
  // 消息总数（@Track 响应式字段，与 messages.length 恒等；空态/错误态分支判定经
  // @ObjectLink 订阅本字段——仅本类变更方法内写，外部只读）
  @Track messageCount: number = 0;
  // 历史加载完成标记（2026-09-06 空态分层）：false = 加载中（空态引导层不显示——进页
  // 首帧 messageCount===0 只代表「尚未加载」非「空会话」）；true = loadHistory 已成功
  // 回放（含空表——确认空会话后才显示引导层）。写点成对 = rebuildFromHistory 置 true /
  // clear() 复位 false；loadHistory 失败路径两方法都不经（保持 false，与错误态分支互斥
  // 推演见 ChatPageContent 空态分支注释）
  @Track historyLoaded: boolean = false;
  // ── 触顶翻页态（2026-08-31 任务 D；@Track——头部提示行「加载更早…/已到顶」两态经
  // @ObjectLink 订阅驱动；写点 = ChatOlderCtrl（loading/attempted）与 rebuild 预判 +
  // ChatPageLoadCtrl.loadOlder（exhausted），rebuild/clear 复位——换会话/刷新重开翻页）──
  @Track olderLoading: boolean = false;
  // 到底标记：初始窗不足一页（< QUERY_TAIL_LIMIT）时 rebuild 预判（免触顶空查询、免
  // 加载行闪现——消息不足一屏触顶即无更多）；翻页查到空页/短页置位；到底后触顶不再查
  @Track olderExhausted: boolean = false;
  // 触达标记：用户至少触顶一次才显示「已到顶」行（防短会话进页即常驻提示行——预判
  // 已知到底但行等首次触达再亮，dshinhm 无此行的差异点）
  @Track olderAttempted: boolean = false;
  // 当前窗口最早行游标（**seq 单键**——2026-09-21 笔 3 单键化：原 createdAt+rowid 双键退役，
  // seq 由写入侧铸造与启动回填保证会话内互异，决胜机制随之失去消费面）；prepend/重建时写入
  // 升序窗口首行（= 最小 seq），尾部 push 不动——翻页查询取游标用
  private oldest: MessageCursor | null = null;
  private listeners: DataChangeListener[] = [];
  private messages: ChatMessage[] = [];

  // ┌──── IDataSource 实现（LazyForEach 契约）────┐
  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): ChatMessage {
    return this.messages[index];
  }

  // 消息流只读全量（2026-09-01「回传历史思考」：ChatHistoryBuilder.buildRequestHistory
  // 输入源——纯函数组装请求历史（含 thinking→assistant reasoning 配对）；只读数组引用，
  // 消息对象本身 @Observed（流式原地改字段），读取不通知不改状态）
  allMessages(): ChatMessage[] {
    return this.messages;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
  // └────────────────────────────────┘

  isEmpty(): boolean {
    return this.messages.length === 0;
  }

  // 清空消息流（页面切换会话/新建时用；键空间 id 不重置——nextMessageId 全局唯一防 key 复用）；
  // 翻页态与游标随窗口一并复位（换会话重开翻页）
  clear(): void {
    this.messages = [];
    this.messageCount = 0;
    this.historyLoaded = false;
    this.olderLoading = false;
    this.olderExhausted = false;
    this.olderAttempted = false;
    this.oldest = null;
    this.notifyReload();
  }

  // 历史回放重建（ChatDb 尾部查询 → 消息流；服务端/本地库为权威，整体重建）：
  // 有 reasoning 的行先补思考块（回放形态 = 思考在回答上方，与流式实时一致——M1 语义）；
  // ★ 2026-09-01「回传历史思考」：思考块 linkId = 正文行 id（发送组装时把思考并回
  // assistant 消息——仅 OpenAI 系，见 ChatSendCtrl.dispatchSend）
  rebuildFromHistory(rows: MessageRow[]): void {
    const rebuilt: ChatMessage[] = [];
    for (const row of rows) {
      if (row.role === 'tool') {
        // 工具行 → 工具卡（2026-09-02；坏行跳过容错）；reasoning 恒空无思考块
        const card: ChatMessage | null = toolCardFromRow(row);
        if (card !== null) {
          rebuilt.push(card);
        }
        continue;
      }
      const body: ChatMessage = newChatMessage(row.id, row.role, row.content);
      // 库序号回填（2026-09-23 上下文压缩）：row.role 直映 kind（'summary' 行即得
      // kind='summary'——持久轻提示行的渲染判据）；rowSeq 供组装侧被压段判据与压缩选段
      if (row.seq !== undefined) {
        body.rowSeq = row.seq;
      }
      if (row.role === 'summary' && row.coversToSeq !== undefined) {
        body.coversToSeq = row.coversToSeq;
      }
      // 多版本装配（DB v36，2026-09-20 消息重新生成）：variants 非空才解析（绝大多数行 ''
      // 零成本）；count/active 进渲染投影（切换键判据），选中版正文即 content 列（投影设计
      //——回放读到的本来就是选中版）
      if (row.variants !== undefined && row.variants !== '') {
        body.variantCount = parseMessageVariants(row.variants).length;
        body.variantActive = row.variantActive ?? 0;
      }
      if (row.reasoning !== '') {
        const think: ChatMessage = newChatMessage('think-' + row.id, 'thinking', row.reasoning);
        think.linkId = row.id;
        // 同泡化标记（2026-09-16）：正文泡上缘切直角与思考半泡拼接——建思考行处成对置位
        body.thinkAbove = true;
        rebuilt.push(think);
      }
      rebuilt.push(body);
    }
    // 末条 assistant 行置 tail（2026-09-14 消息底栏重试键显隐；「其后无任何消息」在回放
    // 形态 = 最后一个 assistant 行——notice 不落库、工具行恒随其 assistant 段落成组）
    for (let i = rebuilt.length - 1; i >= 0; i--) {
      if (rebuilt[i].kind === 'assistant') {
        rebuilt[i].tail = true;
        break;
      }
    }
    this.messages = rebuilt;
    this.messageCount = rebuilt.length;
    this.historyLoaded = true; // 空态分层（2026-09-06）：回放成功含空表——确认空才亮引导层
    this.olderLoading = false;
    this.olderAttempted = false;
    // 初始窗不足一页 = 历史已全量在窗——预判到底（免触顶空查询；行显示另需 olderAttempted）
    this.olderExhausted = rows.length < QUERY_TAIL_LIMIT;
    // 游标 = 窗口最小 seq（升序回放窗首行；NULL 行按 0 兜底 = 翻页回空的有界降级——
    // 理论不可达：启动补号 + 导入即时补号 + 写入点必铸三路兜底，rowid ?? 0 同款防御姿势）
    this.oldest = rows.length > 0 ? { seq: rows[0].seq ?? 0 } : null;
    this.notifyReload();
  }

  // 触顶翻页前插（2026-08-31 任务 D）：早于当前首帧的一页按序头部插入 + 整表
  // notifyReload（头部批量插入逐条 onDataAdd 索引全移，reload 一次成章）；不触尾部
  // flush/append 语义——翻页是只读历史，流式增量逻辑零改（push/insertBefore 原样）。
  // 思考块合成与 rebuildFromHistory 同款（linkId = 正文行 id，2026-09-01 回传契约）；游标
  // 前移到新首行
  prepend(rows: MessageRow[]): void {
    if (rows.length === 0) {
      return;
    }
    const prepended: ChatMessage[] = [];
    for (const row of rows) {
      if (row.role === 'tool') {
        const card: ChatMessage | null = toolCardFromRow(row);
        if (card !== null) {
          prepended.push(card);
        }
        continue;
      }
      const body: ChatMessage = newChatMessage(row.id, row.role, row.content);
      // 库序号回填：同 rebuildFromHistory（翻页前插的也是回放行——缺值会让压缩边界退化）
      if (row.seq !== undefined) {
        body.rowSeq = row.seq;
      }
      if (row.role === 'summary' && row.coversToSeq !== undefined) {
        body.coversToSeq = row.coversToSeq;
      }
      // 多版本装配：同 rebuildFromHistory（variants 非空才解析；content 已是选中版）
      if (row.variants !== undefined && row.variants !== '') {
        body.variantCount = parseMessageVariants(row.variants).length;
        body.variantActive = row.variantActive ?? 0;
      }
      if (row.reasoning !== '') {
        const think: ChatMessage = newChatMessage('think-' + row.id, 'thinking', row.reasoning);
        think.linkId = row.id;
        // 同泡化标记：同 rebuildFromHistory（建思考行处成对置位）
        body.thinkAbove = true;
        prepended.push(think);
      }
      prepended.push(body);
    }
    this.messages = prepended.concat(this.messages);
    this.messageCount = this.messages.length;
    // 游标前移到新首行 seq（升序页首行 = 最小 seq——取末行则游标回跳，翻页重读已载行）
    this.oldest = { seq: rows[0].seq ?? 0 };
    this.notifyReload();
  }

  // 翻页游标只读出口（ChatPageLoadCtrl.loadOlder 查询入参；无窗口 = null 不查）
  oldestCursor(): MessageCursor | null {
    return this.oldest;
  }

  // 尾部追加（用户/助手占位/notice 消息；页面生成 id 后入列）。tail 维护（2026-09-14
  // 消息底栏）：任何新消息入列 = 原末条助手消息不再满足「其后无任何消息」，先清后置
  // （新入列的 assistant 行自己成为 tail；工具轮中间行在后续 tool 卡 push 时自然失 tail，
  // 最终轮收尾由 finishStream 置回）。窗口 ≤ QUERY_TAIL_LIMIT+进行中回合，线性清扫零成本
  push(msg: ChatMessage): void {
    // ★ 2026-09-23 自检轮修复：摘要提示行不参与 tail 维护——它是会话级状态行，不是「其后
    // 又有了新消息」。回放链 rebuildFromHistory 同样把 tail 落在末条 assistant 行（提示行在
    // 其后仍带底栏），两链须一致；否则「采用压缩」瞬间末条回答的底栏（重试/用量/版本切换）
    // 整栏消失到下一轮为止，而重进会话又复现——同态两样
    if (msg.kind !== 'summary') {
      for (const m of this.messages) {
        if (m.tail === true) {
          m.tail = false;
        }
      }
      if (msg.kind === 'assistant') {
        msg.tail = true;
      }
    }
    this.messages.push(msg);
    this.messageCount = this.messages.length;
    this.notifyAdd(this.messages.length - 1);
  }

  // 定位插入（流式思考块懒创建：插在助手占位气泡之前——思考在回答上方；beforeId 须存在）
  insertBefore(beforeId: string, msg: ChatMessage): void {
    const index: number = this.findIndex(beforeId);
    if (index < 0) {
      this.push(msg);
      return;
    }
    this.messages.splice(index, 0, msg);
    this.messageCount = this.messages.length;
    this.notifyAdd(index);
  }

  // 按 id 查消息（流式原地改字段的引用入口；找不到 = null 交调用方守卫）
  findMessage(id: string): ChatMessage | null {
    const index: number = this.findIndex(id);
    return index >= 0 ? this.messages[index] : null;
  }

  // 按正文行 id 查其思考块（2026-09-20 消息重新生成·多版本切换用）：linkId 关联的
  // thinking 行——切换版本时思考文本随版换（找 thinking 行原地改 text）。找不到 = null
  //（该版无思考块 / 未建）交调用方处理
  findThinkingFor(bodyId: string): ChatMessage | null {
    for (const m of this.messages) {
      if (m.kind === 'thinking' && m.linkId === bodyId) {
        return m;
      }
    }
    return null;
  }

  // 本轮残留清理（2026-09-15 重试链原语、同日撤链退役、2026-09-20 重试真链复活取回；
  // ★ 2026-09-20 真机修复笔升级为整轮形态）：返回本轮派生行的 id 集与「是否工具轮形态」。
  // 本轮定义 = 目标行之前最近一条 user 消息之后到列表末尾（目标行恒为末条 assistant，其
  // 后只可能挂尾巴缝工具卡与本轮过程提示行）。移除集合 = 该区间内**除目标行自身外**的全部
  // 行（思考块 / 工具卡 / 中间 assistant 行 / 本轮 notice）——原实现只删「目标行之上自己的
  // 思考块 + 其后的工具卡」，真机实测工具轮残留（旧工具卡在目标行**之前**、中间行整段留下）
  // → 升级为整轮清扫。toolRound 判据 = 区间内存在 tool 行或 assistant 行（工具轮形态 →
  // 调用方走「目标行整行作废 + 重建承载行」路径，见 ChatRetryCtrl.retryLast）。整体
  // notifyReload（有移除才通知）。调用方同步删库行（防「重进会话旧卡复现」）
  cleanRoundResidue(assistantId: string): RoundResidue {
    const targetIdx: number = this.findIndex(assistantId);
    if (targetIdx < 0) {
      return { removedIds: [], toolRound: false };
    }
    // 本轮起点：目标行之前最近一条 user 行之后（窗口内无 user 行 = 从头开始）
    let start: number = 0;
    for (let i = targetIdx - 1; i >= 0; i--) {
      if (this.messages[i].kind === 'user') {
        start = i + 1;
        break;
      }
    }
    const kept: ChatMessage[] = [];
    const removedIds: string[] = [];
    let toolRound: boolean = false;
    for (let i = 0; i < this.messages.length; i++) {
      const m: ChatMessage = this.messages[i];
      // ★ 2026-09-23 自检轮修复：摘要提示行不在整轮残留清理范围内——它不是本轮派生行，而是
      // 会话级状态行（库行亦然）。此前摘要行恒在流末，重试末条回答时会被当「本轮残留」一并
      // 内存移除 + 库行删除（deleteMessagesBy 上交），压缩被静默抹掉且面板退回「未压缩」
      if (i !== targetIdx && i >= start && m.kind !== 'user' && m.kind !== 'summary') {
        if (m.kind === 'tool' || m.kind === 'assistant') {
          toolRound = true;
        }
        removedIds.push(m.id);
        continue;
      }
      kept.push(m);
    }
    if (removedIds.length > 0) {
      this.messages = kept;
      this.messageCount = kept.length;
      this.notifyReload();
    }
    return { removedIds: removedIds, toolRound: toolRound };
  }

  // 按 id 批量移除消息行（2026-09-20 重试真机修复笔：工具轮形态下重试目标行整行作废——
  // 旧答案经版本基线保在新建承载行的 variants 里，行本体不再需要；内存移除在此，DB 行
  // 删除由调用方 deleteMessagesBy 同步）。无命中零通知
  removeMessageIds(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    const kept: ChatMessage[] = [];
    let removed: number = 0;
    for (const m of this.messages) {
      if (ids.indexOf(m.id) >= 0) {
        removed++;
        continue;
      }
      kept.push(m);
    }
    if (removed > 0) {
      this.messages = kept;
      this.messageCount = kept.length;
      this.notifyReload();
    }
  }

  private findIndex(id: string): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private notifyReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  private notifyAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataAdd(index));
  }
}
