// 消息重新生成编排域（2026-09-20 消息重新生成·多版本保留；域级最小拆分自 ChatSendCtrl.ets
// 迁出 + ChatPage.switchMessageVariantUi 收编——ChatSendCtrl 本笔越 1200 硬线，本笔新增的
// 重试域整域外迁〔宪法「新增功能域不论行数一律先拆」〕）。域定义一句话：**同槽位多版本**
// 的全部编排——末轮重试（retryLast 就地替换重答，旧回答保进 variants）+ 版本切换
//（switchVariant 换选中版）+ 工具轮中间收尾/终态收尾的版本组装（takeVariantPayloadFor /
// applyFinalVariant）。存储读写口在 common/store/MessageVariantDb.ets（域件）；发送编排
//（复位段/组装段/轮次发起）经 ChatRetryHost 回接宿主 ChatSendCtrl——**禁第二条请求链**
//（组装与发送共用宿主 assembleRound/startRound，两消费方钉在 assert-app-domain 95 组）。
// 沿革：重试真链 2026-09-14 落地（44e89bc）→ 2026-09-15 撤链（594 节）→ 2026-09-20 复活
// 取回并升级多版本（决明「执行方案，拍板按推荐来」——方案档 docs/方案-消息重新生成-
// 20260920.md）。账本口径拍板：重试消耗照常落账（账本与消息生命周期解耦，统计页全量
// 求和）；帮助中心「消息格式」条有说明句。
//
// ★★ 2026-09-20 真机验收修复笔（四现象 → 四修，决明报障原话：「点重试后正文仍在、思考消失
// 并重新生成但结束后仍是原来的，界面内回放切换两版也不变，退出消息页再重进就变了」+
//「带工具调用的消息重试后工具记录还在、有时不知有没有重试成功、根本不显示回放切换键」）：
//  ①正文/切版 UI 不刷新（根因 = 渲染器，非本域）：两个正文渲染器（CJMarkdown 增量解析 /
//    @lidary）对「内容被整体替换（非前缀）」不重解析——重试清空重答与换版整段替换后，
//    屏上停在上一次已解析内容，退出重进（组件重建）才正确。修 = ChatMessage.renderEpoch
//    渲染纪元：本域两处写点（retryLast 清空、switchVariant 换版）自增，渲染侧按「id#纪元」
//    作 ForEach 键整组件重建（见 ChatMessageCompose.renderEpoch 注释）。流式追加不动键。
//  ②工具轮重试残留（根因 = 清理范围）：原只清理「目标行自己的思考块 + 其后的工具卡」，
//    而工具轮的中间行与工具卡都在目标行**之前** → 旧过程整段残留、且目标行位置在旧工具卡
//    之后，新轮只能追加在其后 → 新旧过程交错。修 = 本轮残留整轮清扫（ChatDataSource.
//    cleanRoundResidue 返回 removedIds + toolRound）。
//  ③工具轮重试后切换键不可达（根因 = 版本挂错行）：终态行在工具轮形态下是新行，旧答案
//    保在目标行 variants 里而目标行失 tail（判据 tail && N>1）→ 入口不可达。修 = 工具轮
//    形态改「目标行整行作废 + 新建承载行」：旧答案经版本基线迁到承载行，终态收尾以
//    baseVariants + 终版落在**末条**（恒 tail）→ 切换键可达（见下 baseVariants/roundVariants
//    双层注释）。
//  ④首版边界（保留）：仅末条可重试；历史轮分支不做。
import { AiConnection } from '../../common/providers/AiTypes';
import { advanceRetryTimestamps, deleteMessagesBy, insertMessage, nextMessageId,
  nextRowCreatedAt, MessageRow } from '../../common/store/ChatDb';
import { nextRowSeq } from '../../common/store/MessageSeqDb';
import { finalizeMessageVariant, MessageVariant, MessageVariantRow,
  parseMessageVariants, queryMessageVariantRow, serializeMessageVariants,
  switchMessageVariant } from '../../common/store/MessageVariantDb';
import { clearConversationSuggestions } from '../../common/SuggestGen';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { RoundResidue } from './ChatDataSource';
import { MessageVariantPayload } from './ChatToolRoundCtrl';
import { ChatSendRefs } from './ChatSendCtrl';

// 终态收尾组装载荷（applyFinalVariant 产物）：variants 全量 JSON（已含终版）/ active 选中
// 下标（= 终版）/ count 版本总数——宿主据此走五列落库与内存投影
export interface VariantFinalizePayload {
  variants: string;
  active: number;
  count: number;
}

// 用量五值快照（组装版本的输入——宿主轮次累积器局部快照传入，防收尾清零错位）；**件内可见
// 即可**（宿主按对象字面量传参、不引类型名——2026-09-20 自检回收「只加出口的 export」）。
// ★ 2026-09-23 首字耗时笔：四值扩五值（+ firstTokenMs），类型名同笔自 VariantUsageQuad 改
// 为 VariantUsageSnapshot（Quad 对五值即失实）；五值全部随版各自成快照，切版各显各版
interface VariantUsageSnapshot {
  prompt: number;
  completion: number;
  durationMs: number;
  cached: number;
  firstTokenMs: number;
}

// 宿主接口：重试域引用的宿主编排能力（ChatSendCtrl implements，全部薄直通或抽段方法）
export interface ChatRetryHost {
  isDisposed(): boolean;              // this.disposed（销毁闸）
  // 重试流式复位段（宿主私有态集中地——liveAssistantId/liveThinkingId/两个全量串/
  // cube.rebuild/setSending(true)/forceToBottom，方法体见宿主）
  beginRetryStreaming(msgId: string): void;
  // 重试组装段（宿主私有链：记忆块 → 技能上下文 → assembleRound → 工具轮重置 → 三中转
  // 键 → 轮次用量清零 → startRound；守卫 disposed/sending 在段首——方法体见宿主）
  launchRetryRound(conn: AiConnection): void;
}

export class ChatRetryCtrl {
  private refs: ChatSendRefs;
  private host: ChatRetryHost;
  // 版本态（域私有），**双层数组**（2026-09-20 真机修复笔）：
  //  · roundVariantId = 本轮版本承载行 id（'' = 非重试轮）——无工具轮形态 = 重试目标行
  //    自身（就地重答）；工具轮形态 = 新建承载行（目标行整行作废，见 retryLast）
  //  · baseVariants = 重试开始时的版本基线（**终态收尾用**）——半截版不入此列
  //  · roundVariants = 推进中的数组（**工具轮中间收尾保底写库用**，含半截版）——中途进程
  //    被杀时库内 = [旧答案, 半截版]，重进会话可切回旧答案；正常收尾走 baseVariants + 终版，
  //    半截版自然被覆盖（不污染最终版本列表）
  // 消费点三：retryLast 基线构建 / takeVariantPayloadFor 工具轮中间收尾 / applyFinalVariant
  // 终态收尾；宿主轮首与收尾经 resetRound 清零（新发送轮不是重试轮）
  private baseVariants: MessageVariant[] = [];
  private roundVariants: MessageVariant[] = [];
  private roundVariantId: string = '';

  constructor(refs: ChatSendRefs, host: ChatRetryHost) {
    this.refs = refs;
    this.host = host;
  }

  // 版本态清零（宿主 dispatchSend 轮首与 finishStream 收尾双调——新发送轮/收尾后非重试态）
  resetRound(): void {
    this.baseVariants = [];
    this.roundVariants = [];
    this.roundVariantId = '';
  }

  // 末轮重试（就地替换重答——不新增 user 消息、复位既有 assistant 行重新走响应段）：
  // 守卫四条（流式中/隐私会话/目标非末条/连接未配置——前三者底栏判据前置理论不可达，
  // 防御性呈报不静默）→ 本轮残留整轮清扫（思考块 / 工具卡 / 中间行 / 本轮 notice；尾巴缝：
  // 被中止工具卡 DB 行同步删，防重进会话旧卡复现）→ 形态分流（★ 2026-09-20 真机修复笔）：
  //  · 无工具轮形态 = 现状就地重答：目标行四清（text 清空 = 历史组装自动截断到该轮 user
  //    〔空内容跳过〕；usage 清 undefined 防旧值残留；streaming 置真回生成中；thinkAbove
  //    复位防孤立缺角）+ 渲染纪元推进（正文渲染器整组件重建，修「正文不动」）→ 版本基线
  //    构建并**写库保底**（旧答案入 variants[0]——此后中途停止/进程被杀旧答案不丢；读/写
  //    失败降级无版本模式 + toast 不静默，重试主链不阻断 = 旧就地替换行为）+ 时间推进
  //    （★ 2026-09-20 会话统计时间修复笔：该行 createdAt 与会话 updatedAt 同推——重答是
  //    一次新活动，统计面板「最后活跃 / 时间跨度」与会话列表时间须随之前进）
  //  · 工具轮形态 = 整轮作废 + 重建承载行：目标行在新轮位置之前（旧工具卡之后），就地
  //    重答会让新旧过程交错且版本挂错行 → 目标行整行作废（内存 + DB 同步删；旧答案经版本
  //    基线 roundVariants 保在承载行 variants 里，数据不丢——★ 2026-09-20 自检修复：承载行
  //    占位落库**完成之后**同拍保底写库，被杀不再丢旧答案），新建 assistant 承载行落库
  //    （status=streaming，createdAt 走单调分配器保回放序）作为本轮载流目标
  // → 宿主组装段发起。中断口径：销毁/被杀 = DB 停在保底态重进自愈（两形态同口径——库内 =
  // 旧答案 + 版本基线、屏上 = 空流式行）；失败/停止 = 空文本/半截照样入版为最新版（可切回旧版）
  retryLast(msgId: string): void {
    if (this.refs.sending()) {
      this.refs.toast('请等待当前回复结束再重试');
      return;
    }
    if (this.refs.privateMode()) {
      return; // 底栏判据前置不可达；隐私会话零留痕口径不走重试链
    }
    const target: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
    if (target === null || target.kind !== 'assistant' || target.tail !== true) {
      this.refs.toast('仅最后一条回复可重试');
      return;
    }
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null) {
      this.refs.toast('请先在「设置 > 服务商管理」完善服务商（接口地址、密钥与模型）');
      return;
    }
    // 旧答案用量快照（复位/删行前取内存值——账本末条口径）：仅在「行 variants 为空」（首次
    // 重试）时用作基线版用量；多次重试各版用量已在 DB variants 内自带
    const baseTokens: number = target.usageTokens ?? 0;
    const baseCompletion: number = target.usageCompletionTokens ?? 0;
    const baseDurationMs: number = target.usageDurationMs ?? 0;
    const baseCached: number = target.usageCachedTokens ?? 0;
    // 首字耗时同族快照（2026-09-23 首字耗时笔）：0 = 该版无首字（升级前的老轮次/未产出）
    const baseFirstTokenMs: number = target.usageFirstTokenMs ?? 0;
    // 本轮残留整轮清扫（内存同步 + 库行随 deletedIds 上交；工具轮形态标记 toolRound 见
    // ChatDataSource.cleanRoundResidue 注释）
    const residue: RoundResidue = this.refs.dataSource.cleanRoundResidue(msgId);
    if (residue.removedIds.length > 0 && this.refs.dbReady()) {
      deleteMessagesBy(residue.removedIds)
        .catch((e: Object): void => {
          this.refs.toast('清理已中止工具记录失败：' + (e as Error).message);
        });
    }
    // 异步窗口闸：读版本 → 分支 → 发起期间禁重复进入（置真后下面 then 的 !sending() 判据
    // 转为「用户中途停止 / 页面销毁」语义；beginRetryStreaming 内同值置真幂等）
    this.refs.setSending(true);
    queryMessageVariantRow(msgId)
      .catch((e: Object): MessageVariantRow | null => {
        this.refs.toast('版本信息读取失败，本次重试不保留旧回答');
        return null;
      })
      .then((row: MessageVariantRow | null): void => {
        if (this.host.isDisposed() || !this.refs.sending()) {
          return;
        }
        // 版本基线（读失败/行不在库 = 降级无版本模式——收尾走三列 finalizeMessage 原路径）
        const base: MessageVariant[] = row !== null ? parseMessageVariants(row.variants) : [];
        if (row !== null && base.length === 0) {
          base.push({ content: row.content, reasoning: row.reasoning,
            tokens: baseTokens, completion: baseCompletion,
            durationMs: baseDurationMs, cached: baseCached, firstTokenMs: baseFirstTokenMs });
        }
        // 当前显示版在基线中的下标（投影自洽恒 = row.active；不一致见下方补版）；0 兜底
        let curIdx: number = 0;
        // ★ 2026-09-20 修复笔·投影自洽补版：真机存量里存在「content 被三列收尾覆盖、variants
        // 未同步」的行（本笔前的包五列收尾恒不生效，重试过的行都是该形态：content = 重试后的
        // 新答案，variants 只有重试前那一版）——直接拿这种行的旧 variants 当基线，会把用户正
        // 看着的那一版从版本列表里静默挤掉。故「投影列所指版本不在列表中」时补一版（内容取
        // 投影列、用量取内存快照）并以下标指向它；正常行 content === variants[row.active] →
        // 不补、下标即 row.active，零行为变化
        if (row !== null && base.length > 0) {
          const idx: number = Math.min(Math.max(row.active, 0), base.length - 1);
          if (base[idx].content === row.content) {
            curIdx = idx;
          } else {
            base.push({ content: row.content, reasoning: row.reasoning,
              tokens: baseTokens, completion: baseCompletion,
              durationMs: baseDurationMs, cached: baseCached, firstTokenMs: baseFirstTokenMs });
            curIdx = base.length - 1;
          }
        }
        this.roundVariants = base;
        this.baseVariants = base.slice(); // 终态收尾读本列（中途保底推进只动 roundVariants）
        let holderId: string = msgId;
        if (residue.toolRound) {
          // 工具轮形态：目标行整行作废 + 新建承载行（旧答案经 baseVariants 保在承载行
          // variants 里——★ 2026-09-20 自检修复：承载行占位落库后同拍保底写库，占位行
          // 不再裸奔，见下方保底写注释）
          this.refs.dataSource.removeMessageIds([msgId]);
          if (this.refs.dbReady()) {
            deleteMessagesBy([msgId])
              .catch((e: Object): void => {
                this.refs.toast('清理上一版回答失败：' + (e as Error).message);
              });
          }
          const holder: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
          holder.streaming = true;
          this.refs.dataSource.push(holder);
          holderId = holder.id;
          this.roundVariantId = row !== null && base.length > 0 ? holder.id : '';
          if (this.refs.dbReady()) {
            const convId: string = this.refs.conversationId();
            const holderRow: MessageRow = {
              id: holder.id, conversationId: convId, role: 'assistant',
              content: '', reasoning: '', status: 'streaming', createdAt: nextRowCreatedAt(),
              // seq 与 createdAt 同址铸造（★ 2026-09-21 消息存储机制改造笔 2 D1 红线：行对象
              // 构造当场取号）；本行是工具轮重试的**新承载行**，恒为会话末条号（旧目标行已
              // 随删、其旧号作废不复用）——终版答案落在末条，切换键（tail）随之可达
              seq: nextRowSeq(convId)
            };
            // 内存行同址回填库序号（理由全文 = ChatMessage.rowSeq 字段注释）
            holder.rowSeq = holderRow.seq;
            // ★ 2026-09-20 自检修复（工具轮承载行保底写库）：本笔原实现只插占位行（content ''
            // 七列、不带 variants/variant_active），而目标行已在上方随删——首次流收尾（settle
            // 半截版带写）之前进程被杀时，库里旧答案已删、承载行又不带版本 → 旧答案永久丢失
            // （与本域头注释「旧答案任何路径不丢 / 被杀 = DB 停在保底态重进自愈」相悖）。
            // 修法 = 占位落库**完成之后**同拍补保底写，语义对齐无工具轮形态（下方 else 支
            // 「版本保底写库」）的保底写
            //（库内 = 旧答案 且 content === variants[active]，屏上仍是空流式行）。**顺序不可
            // 并**：UPDATE 若先于 INSERT 执行会更新 0 行、保底静默落空（故串在 insert 的 then
            // 里，insert 失败即整段跳过）。row === null（读失败降级无版本模式）= 无基线可保，
            // 直接跳过走三列收尾；写失败只 toast **不清版本态**——基线留着，后续 settle /
            // finishStream 仍会把旧答案连同新版本写进库（此处 resetRound 反把该兜底关掉）
            insertMessage(holderRow)
              .then((): Promise<void> => {
                if (row === null) {
                  return Promise.resolve();
                }
                return finalizeMessageVariant(holder.id, row.content, row.reasoning, row.status,
                  serializeMessageVariants(base), curIdx)
                  .catch((e: Object): void => {
                    this.refs.toast('版本保底写入失败，中途退出可能丢失旧回答：'
                      + (e as Error).message);
                  });
              })
              .catch((e: Object): void => {
                this.refs.toast('新版回答占位落库失败：' + (e as Error).message);
              });
          }
        } else {
          // 无工具轮形态：目标行四清 + 渲染纪元推进 + 版本保底写库（现状口径）
          // ★ 2026-09-23 首字耗时笔随形：清空面补 usageFirstTokenMs（第五个用量 meta 字段）——
          // 漏清即「新一轮产出前弹层仍显示上一轮的首字耗时」的旧值残留（其余四值同族先例）
          target.text = '';
          target.usageTokens = undefined;
          target.usageCompletionTokens = undefined;
          target.usageDurationMs = undefined;
          target.usageCachedTokens = undefined;
          target.usageFirstTokenMs = undefined;
          target.streaming = true;
          // 思考行已随本轮清扫移除——上缘直角标记复位（不置假则新一轮无思考时气泡顶部缺角）
          target.thinkAbove = false;
          // 渲染纪元推进（正文渲染器整组件重建——修「重试后正文停在旧内容」，见字段注释）
          target.renderEpoch = (target.renderEpoch ?? 0) + 1;
          this.roundVariantId = row !== null ? msgId : '';
          // 版本保底写库（旧答案入 variants[0]；写失败降级重试主链不阻断）；dbReady 假 /
          // 读失败（row null）跳过——上方不 return（发起段必须跑，降级无版本模式）。
          // ★ 2026-09-20 修复笔：选中下标随投影走（原恒写 0）——二次及以后重试时 base 已含
          // 多版、row.content 是**当前选中版**，恒写 0 会让「content = variants[active]」投影
          // 不变式破（中途被杀重进显示「正文是第 2 版而计数 1/2」）；下标 = curIdx（投影自洽
          // 时即 row.active、补版时即末位）；首轮 base 仅 1 版 → 0 与 curIdx 同值，零行为变化
          if (row !== null && this.refs.dbReady()) {
            finalizeMessageVariant(msgId, row.content, row.reasoning, row.status,
              serializeMessageVariants(base), curIdx)
              .catch((e: Object): void => {
                this.refs.toast('版本保底写入失败，本次重试不保留旧回答');
                this.resetRound();
              });
            // ★ 2026-09-20 会话统计时间修复笔：重试推进时间——行 createdAt（统计面板
            //「最后活跃 / 时间跨度」）与会话 updatedAt（会话列表时间）双推（存储口
            // advanceRetryTimestamps）；缺它则重试后两处时间都停在**首次生成**时刻（真机
            // 报障「重试的消息一直跟随第一次的时间」）。与保底写各自 catch——一条失败不吞另一条
            advanceRetryTimestamps(this.refs.conversationId(), msgId, nextRowCreatedAt())
              .catch((e: Object): void => {
                this.refs.toast('会话时间更新失败：' + (e as Error).message);
              });
          }
        }
        clearConversationSuggestions(this.refs.conversationId());
        this.host.beginRetryStreaming(holderId);
        this.host.launchRetryRound(conn);
      });
  }

  // 工具轮中间收尾的版本载荷组装（宿主 ChatToolRoundHost.takeVariantPayloadFor 委托）：
  // 命中本轮承载行的 settle → 半截版（content/reasoning 为 settle 侧已快照的本轮值、usage 为
  // 宿主轮次累积——settle 时第一流 done 已计入）并入**推进数组**并组装五列落库载荷（保底：
  // 半截版入库后进程被杀，重进会话可切回旧答案）；★ 2026-09-20 修复笔：半截版只进
  // roundVariants（推进/保底列），**不入 baseVariants**（终态列）——正常收尾的最终版本列表
  // 不含半截版。非本轮承载行回 null（后续中间轮走三列）
  takeVariantPayloadFor(msgId: string, content: string, reasoning: string,
    usage: VariantUsageSnapshot): MessageVariantPayload | null {
    if (msgId !== this.roundVariantId || this.roundVariants.length === 0) {
      return null;
    }
    this.roundVariants.push({ content: content, reasoning: reasoning,
      tokens: usage.prompt + usage.completion, completion: usage.completion,
      durationMs: usage.durationMs, cached: usage.cached, firstTokenMs: usage.firstTokenMs });
    return { variants: serializeMessageVariants(this.roundVariants),
      active: this.roundVariants.length - 1, count: this.roundVariants.length };
  }

  // 终态收尾组装（宿主 finishStream 委托）：重试轮 → 终版并入 **baseVariants**（重试开始
  // 时的基线）返回五列落库载荷（宿主走五列落库 + 内存投影），并清版本态。★ 2026-09-20
  // 修复笔：判据由「msgId === 重试目标行」放宽为「基线非空」——工具轮形态终态行是新建的
  // 承载行（id 与重试目标行不同），放宽后终版恒落在末条行上，切换键（tail && N>1）随之
  // 可达。非重试轮/基线缺失（读失败降级）回 null 走三列
  applyFinalVariant(msgId: string, content: string, reasoning: string,
    usage: VariantUsageSnapshot): VariantFinalizePayload | null {
    if (this.baseVariants.length === 0) {
      return null;
    }
    this.baseVariants.push({ content: content, reasoning: reasoning,
      tokens: usage.prompt + usage.completion, completion: usage.completion,
      durationMs: usage.durationMs, cached: usage.cached, firstTokenMs: usage.firstTokenMs });
    const payload: VariantFinalizePayload = { variants: serializeMessageVariants(this.baseVariants),
      active: this.baseVariants.length - 1, count: this.baseVariants.length };
    this.resetRound();
    return payload;
  }

  // 版本切换（底栏 ‹ i/N › 切换键上行，自 ChatPage 收编）：读行全量 variants → 越界/同版
  // 守卫（防御——组件 enabled 判据已拦）→ 三列换版（content 投影随 active、variants 真源
  // 不动）→ 内存原地改（正文 text / variantActive / 该版用量快照 / 思考行 text 随版换）。
  // usage 联动口径：切到哪版显示哪版自己的用量（variants 内快照，与重进会话装配同口径）；
  // 后续轮上下文组装读 content 投影 = 所选版（「模型只见选中版答案」由投影设计结构性保证）。
  // ★ 2026-09-20 修复笔：换版 = 非前缀替换，渲染纪元同点推进（正文渲染器整组件重建，修
  //「切换后内容不变、退出重进才变」）；思考行经 @Prop 普通通道无需纪元。
  // 流式中守卫（UI 判据前置不可达——streaming 中底栏不显）
  switchVariant(msgId: string, target: number): void {
    if (this.refs.sending()) {
      this.refs.toast('请等待当前回复结束再切换');
      return;
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return;
    }
    queryMessageVariantRow(msgId)
      .then((row: MessageVariantRow | null): void => {
        if (row === null) {
          return; // 行不在库（理论不可达——底栏消息必经回放/落库在场）
        }
        const list: MessageVariant[] = parseMessageVariants(row.variants);
        if (target < 0 || target >= list.length || target === row.active) {
          return; // 越界/同版（防御——组件 enabled 判据已拦）
        }
        const picked: MessageVariant = list[target];
        switchMessageVariant(msgId, picked.content, picked.reasoning, target)
          .then((): void => {
            // 内存原地改（@Observed 对象级观察自动刷新；与重进会话回放装配同口径）
            const body: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
            if (body !== null) {
              body.text = picked.content;
              body.variantActive = target;
              body.usageTokens = picked.tokens > 0 ? picked.tokens : undefined;
              body.usageCompletionTokens = picked.completion > 0 ? picked.completion : undefined;
              body.usageDurationMs = picked.durationMs > 0 ? picked.durationMs : undefined;
              body.usageCachedTokens = picked.cached > 0 ? picked.cached : undefined;
              // 首字耗时随版换（2026-09-23 首字耗时笔）：>0 才挂（undefined 即不渲染，与
              // durationMs 同款；老变体 JSON 无此键 = 解析 0 = 该版不显示）
              body.usageFirstTokenMs = picked.firstTokenMs > 0 ? picked.firstTokenMs : undefined;
              // 截断尾注随版清空（2026-09-23 输出上限治理笔 2 自检轮补）：该字段是消息级
              // 运行时态、只在 finishStream 挂当前轮的值，而变体快照（MessageVariant）不存
              // 截断态 ⇒ 换版后若无条件保留，会出现「切到内容完整的版本仍显示『被上限
              // 截断』」的假信息（反向则是漏提示）。宁缺勿错：换版即清；变体级截断态要
              // 落库须扩 variants 结构，另立笔（见 docs/变更记录.md 自检轮条目）
              body.truncated = undefined;
              // 渲染纪元推进（换版 = 非前缀替换；键变即整组件重建）
              body.renderEpoch = (body.renderEpoch ?? 0) + 1;
            }
            const think: ChatMessage | null = this.refs.dataSource.findThinkingFor(msgId);
            if (think !== null) {
              // 该版无思考 = 置空（思考行保留空文本折叠形态——不动态增删行，登记观察项）
              think.text = picked.reasoning;
            }
          })
          .catch((e: Object): void => {
            this.refs.toast('切换版本失败：' + (e as Error).message);
          });
      })
      .catch((e: Object): void => {
        this.refs.toast('读取版本失败：' + (e as Error).message);
      });
  }
}
