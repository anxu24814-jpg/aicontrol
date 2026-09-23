// 聊天页加载与刷新编排域（2026-08-31 附件上传接线时自 ChatPage 拆出——该页附件接线
// 必超 400 红线，按防屎山「域级最小拆分」迁「连接解析/历史拉取/页面刷新」域，方法体
// 原样搬迁行为不变，@State 写经 refs 回调——ChatSendCtrl 同款拆法先例）。
// · reloadConn：连接 = resolveActiveConnection 四级兜底链解析（2026-09-05 起会话页所选
//   > 会话所属助手绑定 > 全局默认 > 首个启用模型，中途不停——本域负责先查会话行归属
//   助手〔口径与注入链 ChatPromptState 一致〕再传入）；全链落空写 errorText 覆盖层
//（不静默）。
// · loadHistory：会话消息只读拉取 → 数据源一次性重建 + 进页直达底部末条（2026-09-06
//   jumpToBottomAt，原 scrollEdge 回底见 ChatFollowController 注释）；失败写 errorText。
//   ★ 2026-09-15 预览第三轮：重建后链式装配附件简报（attachBriefsFor——按 id 归并
//   赋值，气泡渲染面）；loadOlder 前插批同链装配。
// · refreshPage：「更多」菜单与错误覆盖层「重试」同动作——清错误态 + DB 就绪守卫 +
//   重读连接 + 重拉历史（未就绪跳过读库，保持「初始化失败」提示原样）。
// · loadOlder（2026-08-31 任务 D 触顶翻页）：游标前查一页更早消息 → dataSource.prepend
//   头部前插；到底（空页/短页）置 olderExhausted 终止翻页（有界）；失败 toast + 上抛
//   （ChatOlderCtrl 据此跳过锚点恢复）。触发/锚点/防抖在 ChatOlderCtrl，提示行 UI 在
//   ChatPageContent。
import { AiConnection } from '../../common/providers/AiTypes';
import {
  ConversationOverride, MessageRow, QUERY_TAIL_LIMIT, queryAttachmentsForMessages,
  queryConversationOverride, queryMessagesBefore, queryRecentMessages
} from '../../common/store/ChatDb';
import { MessageVariant, parseMessageVariants } from '../../common/store/MessageVariantDb';
import { MessageAttachmentRow } from '../../common/store/AttachmentDb';
import { briefsFromRows } from '../../common/AttachmentUtil';
import { queryUsageByConversation, UsageEventRow } from '../../common/store/UsageStatsDb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ASSISTANT_DEFAULT_ID, queryConversationAssistantId } from '../../common/store/AssistantDb';
import { ActiveConnectionInfo, resolveActiveConnection } from '../../common/store/ProviderDb';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { ChatFollowController } from './ChatFollowController';
import { loadConversationSuggestions } from '../../common/SuggestGen';

// 页面侧读写集（@State 写必须回页面经回调；普通引用直持有——ChatSendRefs 同款）
export interface ChatPageLoadRefs {
  dataSource: ChatDataSource;
  follow: ChatFollowController;
  dbReady: () => boolean;
  conversationId: () => string;
  // 连接解析结果回写（conn 普通成员——2026-08-31 任务 E 起服务商名/配置态两镜像随状态
  // 胶囊取消退役；2026-09-09 connModel 标题栏镜像随模型入口换位退役〔现为返回键右侧
  // 「模型」胶囊，一百八十二→二百一十六〕）
  setConnInfo: (info: ActiveConnectionInfo | null) => void;
  setError: (text: string) => void;
  // 动作时错误提示（loadOlder 查询失败——消息流在场，errorText 覆盖层不适用，走 toast）
  toast: (message: string) => void;
  // 会话有效归属助手（2026-09-05 四级兜底链②级输入；页面转发 sendCtrl.boundAssistantId
  // = 面板覆盖 ?? 当前助手 ?? 默认助手——仅无行会话〔懒创建/隐私〕在归属行查询为 null
  // 时消费；有行会话行走 DB 值不经此）
  effectiveAssistantId: () => string;
  // 无行会话的会话级覆盖（2026-09-10 会话级覆盖层笔：会话还没落行时用户在会话内改的
  // 模型选择只存页面内存，本处作 DB 回读不到的兜底；行存在 = DB 为准，本值不参与）
  memoryOverride: () => ConversationOverride | null;
  // 流式追加缓冲复位（2026-09-11 笔 3：全量重建前清节流缓冲——实现 = ChatSendCtrl
  // resetAppendBuffer；本域不反向依赖发送域，经 refs 回调上行）
  resetAppendBuffer: () => void;
  // 历史加载收尾通知（2026-09-18 自检轮补算点）：loadHistory 全链完成（成败两路都到，
  // 挂在 catch 之后）后触发——会话页上下文圆环的确定性补算点。进页初算与 setConnInfo
  // 重算都不等历史重建完成（reloadConn/loadHistory/初算三条异步链并发赛跑），reloadConn
  // 先完成时圆环停在仅固定开销的小值且再无刷新点（onShown 首显被 dbReady 守卫跳过）；
  // 本点保证「历史就绪后必有一次重算」。无消费方时零开销（同 onRoundSettled 形制）
  onHistorySettled?: () => void;
  // 沙箱 filesDir（2026-09-15 预览第三轮：附件简报装配拼绝对路径用——相对路径红线只对
  // 入库生效，运行时渲染消费绝对路径；页面闭包现读 host context）
  filesDir: () => string;
}

export class ChatPageLoadCtrl {
  private refs: ChatPageLoadRefs;

  constructor(refs: ChatPageLoadRefs) {
    this.refs = refs;
  }

  // 连接配置自加载（push 即新实例）：先查会话行归属助手（三态——非 '' = 显式绑定；
  // '' = 内置默认助手；null〔懒创建新会话/隐私会话无行〕= 有效归属 =
  // refs.effectiveAssistantId，口径与注入链 ChatPromptState.load 完全一致），再查会话级
  // 覆盖（2026-09-10：DB 值 ?? 无行时页面内存覆盖），最后交 resolveActiveConnection 四级
  // 兜底链解析；行查询失败降级 null = 走有效归属/内存覆盖（可用性优先——异常路径不阻断
  // 连接）；全链落空提示不静默
  reloadConn(): void {
    const cid: string = this.refs.conversationId();
    let rowOverride: ConversationOverride | null = null;
    queryConversationOverride(cid)
      .catch((): ConversationOverride | null => null)
      .then((ov: ConversationOverride | null): Promise<string | null> => {
        rowOverride = ov; // null = 无行（或读失败）→ 下面用页面内存覆盖兜底
        return queryConversationAssistantId(cid).catch((): string | null => null);
      })
      .then((rowId: string | null): Promise<ActiveConnectionInfo | null> => {
        const ownerId: string = rowId !== null && rowId !== '' ? rowId :
          (rowId === null ? this.refs.effectiveAssistantId() : ASSISTANT_DEFAULT_ID);
        const ov: ConversationOverride | null = rowOverride !== null ? rowOverride :
          this.refs.memoryOverride();
        return resolveActiveConnection(ownerId,
          ov !== null ? ov.modelProviderId : '', ov !== null ? ov.modelId : '');
      })
      .then((info: ActiveConnectionInfo | null): void => {
        this.refs.setConnInfo(info);
      })
      .catch((e: Object): void => {
        this.refs.setError('连接配置读取失败：' + (e as Error).message);
      });
  }

  loadHistory(): void {
    // 全量重建前复位追加缓冲（★ 2026-09-11 笔 3：旧窗口增量作废 + 档位回快档）
    this.refs.resetAppendBuffer();
    queryRecentMessages(this.refs.conversationId())
      .then((rows: MessageRow[]): Promise<void> => this.attachUsageMeta(rows)
        // 附件简报装配（2026-09-15 预览第三轮）：链在 attachUsageMeta 之后 = 重建必然
        // 已完成（findMessage 按 id 命中新消息，竞态零面）；装配失败在方法内 hilog 留痕
        // 不阻断（附件泡缺席即标注回退显示，同导入/老数据形态）
        .then((): void => {
          this.attachBriefsFor(rows);
          // 回放链推荐问题装配（2026-09-19 推荐问题功能）：attachBriefs 装配先例同位——
          // 读会话行 suggestions 列挂末条助手消息（@Observed 对象级观察驱动刷新）；链内
          // 顺序与简报装配同层（重建已完成，按 kind 倒序定位无竞态）；loadOlder 前插批
          // 不挂（显示面只有末条，前插的是更早消息）
          this.attachSuggestionsFor();
        }))
      .catch((e: Object): void => {
        this.refs.setError('历史消息读取失败：' + (e as Error).message);
      })
      .then((): void => {
        // 收尾通知挂在 catch 之后 = 成败两路都到（查询失败走 setError，历史为空时补算
        // 按空历史算固定开销段，语义不变）；见 ChatPageLoadRefs.onHistorySettled 注释
        if (this.refs.onHistorySettled !== undefined) {
          this.refs.onHistorySettled();
        }
      });
  }

  // 历史回放用量挂载（2026-09-06 用量统计）：批量查本会话账本 → 按 messageId **取最后
  // 一条事件**（createdAt 升序遍历覆盖，后写胜出）→ rebuild 后按 id 原地赋值（@ObjectLink
  // 原地改既有刷新机制，坑16 正解——禁自建广播键）。★ 2026-09-14 消息底栏重试笔改口径
  //（任务书 §2.4-⑧）：原「按消息求和」是早期每流一事件遗留的兜底——重试会产生同一消息
  // 的第二条事件，求和会把两次消耗叠加显示（偏大）；显示语义 = 「这条回答现在的用量」，
  // 取最后一条 = 重试后的最新值；统计页与费用页照旧全量求和（账本语义 = 实际花了多少，
  // 两消费方各自正确）。★ 2026-09-20 消息重新生成·多版本：带 variants 的行改挂**选中版
  // 快照**（variants[active]）——账本末条恒属最新版，切回旧版重进会话时末条会把新版用量
  // 错挂到旧版上；各版快照重试链自带，选中版即所见。账本查询失败静默降级不挂载
  //（meta 属展示增强，不阻断历史加载——历史加载错误态另有通道）
  private attachUsageMeta(rows: MessageRow[]): Promise<void> {
    // 多版本行选中版快照集（variants 非空才解析——绝大多数行 '' 零成本）
    const variantUsageBy: Map<string, MessageVariant> = new Map();
    for (const row of rows) {
      if (row.role === 'assistant' && row.variants !== undefined && row.variants !== '') {
        const list: MessageVariant[] = parseMessageVariants(row.variants);
        const idx: number = row.variantActive ?? 0;
        if (idx >= 0 && idx < list.length) {
          variantUsageBy.set(row.id, list[idx]);
        }
      }
    }
    const rebuildAndMount = (events: UsageEventRow[] | null): void => {
      this.refs.dataSource.rebuildFromHistory(rows); // 一次性重建（思考块合成在源内）
      if (events !== null) {
        const byId: Map<string, UsageEventRow> = new Map();
        for (const ev of events) {
          byId.set(ev.messageId, ev); // 升序遍历覆盖 = 同消息取最后一条
        }
        byId.forEach((ev: UsageEventRow, msgId: string): void => {
          const msg: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
          if (msg !== null && msg.kind === 'assistant' && ev.totalTokens > 0) {
            // 多版本行优先挂选中版快照（口径见方法头注释）；快照零用量（无用量协议/
            // 中断版）= 四字段全 undefined 不渲染
            const pick: MessageVariant | undefined = variantUsageBy.get(msgId);
            if (pick !== undefined) {
              if (pick.tokens > 0) {
                msg.usageTokens = pick.tokens;
                msg.usageCompletionTokens = pick.completion;
                msg.usageDurationMs = pick.durationMs;
                if (pick.cached > 0) {
                  msg.usageCachedTokens = pick.cached;
                }
                // 首字耗时随版（2026-09-23 首字耗时笔）：>0 才挂（老变体 JSON 无此键 = 0 =
                // 该版不显示，诚实缺失不回填）
                if (pick.firstTokenMs > 0) {
                  msg.usageFirstTokenMs = pick.firstTokenMs;
                }
              }
              return;
            }
            msg.usageTokens = ev.totalTokens;
            msg.usageCompletionTokens = ev.completionTokens;
            msg.usageDurationMs = ev.durationMs;
            // 首字耗时（2026-09-23 首字耗时笔）：>0 才挂（升级前的存量账本行 DEFAULT 0 =
            // 无该指标天然不显示；与缓存段同款零噪声口径）
            if (ev.firstTokenMs > 0) {
              msg.usageFirstTokenMs = ev.firstTokenMs;
            }
            // 缓存命中段（2026-09-10）：>0 才挂（undefined 即不渲染）；历史行 DB 默认 0
            // = 升级前的存量轮次天然无段（预期口径——表自 v26 起新记缓存）
            if (ev.cachedTokens > 0) {
              msg.usageCachedTokens = ev.cachedTokens;
            }
          }
        });
      }
      // 进页初始定位直达底部末条（2026-09-06：原 forceToBottom 的 scrollEdge 有「布局
      // 漂移跳滚」与「竞态停顶」两面，见 ChatFollowController.jumpToBottomAt 注释与
      // 官方查证依据）；「更多·刷新」refreshPage 复用本链同点到达——滚底语义与原一致，
      // 仅定位方式按末条下标更精准
      this.refs.follow.jumpToBottomAt(this.refs.dataSource.messageCount - 1);
    };
    return queryUsageByConversation(this.refs.conversationId())
      .then((events: UsageEventRow[]): void => rebuildAndMount(events))
      .catch((): void => rebuildAndMount(null));
  }

  // 回放链附件简报装配（2026-09-15 预览第三轮，loadHistory 与 loadOlder 共用）：
  // 收集批内 user 行 id（空集短路零查询——P0-1 错误输入宁可空返回）→ 查附件行 → 按
  // messageId 归并 → **按 id 定位**（禁按下标——思考块合成使消息序与行序不对应）原地
  // 赋值 attachBriefs（@Observed/@ObjectLink 对象级观察驱动气泡渲染）。装配只在加载链
  // 一次完成，build 内零查询零 I/O（性能红线 + 坑57）；失败 hilog 留痕不阻断（附件泡
  // 缺席即标注回退显示）。send 链写点在 ChatSendCtrl——本方法是回放侧唯一写点
  private attachBriefsFor(rows: MessageRow[]): void {
    const ids: string[] = [];
    for (const row of rows) {
      if (row.role === 'user') {
        ids.push(row.id);
      }
    }
    if (ids.length === 0) {
      return;
    }
    queryAttachmentsForMessages(ids)
      .then((attachRows: MessageAttachmentRow[]): void => {
        if (attachRows.length === 0) {
          return;
        }
        const byMsg: Map<string, MessageAttachmentRow[]> = new Map();
        for (const attachRow of attachRows) {
          const list: MessageAttachmentRow[] | undefined = byMsg.get(attachRow.messageId);
          if (list !== undefined) {
            list.push(attachRow);
          } else {
            byMsg.set(attachRow.messageId, [attachRow]);
          }
        }
        const filesDir: string = this.refs.filesDir();
        byMsg.forEach((list: MessageAttachmentRow[], msgId: string): void => {
          const msg: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
          if (msg !== null && msg.kind === 'user') {
            msg.attachBriefs = briefsFromRows(list, filesDir);
          }
        });
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageLoad', '附件简报装配失败（气泡退标注回退显示）：%{public}s',
          (e as Error).message);
      });
  }

  // 回放链推荐问题装配（2026-09-19 推荐问题功能，loadHistory 专用——loadOlder 前插批
  // 不挂）：读会话行 suggestions 列（解析单落点 SuggestGen.loadConversationSuggestions）
  // 挂到末条助手消息（**按 kind 倒序定位，禁按下标**——思考块合成使消息序与行序不对应，
  // attachBriefsFor 同款纪律）；@Observed 对象级观察驱动渲染。空串/解析空 = 不挂
  //（undefined 即不渲染）；失败 hilog 留痕不阻断（建议缺席不炸历史加载——展示增强）。
  // 隐私会话无行恒回 ''，零特判；发送清空后 '' 同不挂
  private attachSuggestionsFor(): void {
    loadConversationSuggestions(this.refs.conversationId())
      .then((items: string[]): void => {
        if (items.length === 0) {
          return;
        }
        const all: ChatMessage[] = this.refs.dataSource.allMessages();
        for (let i = all.length - 1; i >= 0; i--) {
          if (all[i].kind === 'assistant') {
            all[i].suggestions = items;
            break;
          }
        }
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageLoad', '推荐问题装配失败：%{public}s', (e as Error).message);
      });
  }

  // 触顶翻页查询（2026-08-31 任务 D；ChatOlderCtrl.tryLoadOlder 上行）：游标 = 当前窗口
  // 最早行（seq 单键，ChatDataSource 维护；★ 2026-09-21 自检轮补随形——原「createdAt+id 双键」
  // 是 09-19 改键前的口径，与 852 切序一并过时）；空页/短页 = 到底置 olderExhausted
  //（此后触顶不再查询——有界）；空窗口无游标直接收（理论不达——守卫 messageCount===0
  // 先拦）；失败 toast 呈报并上抛（调用方跳过锚点恢复，滚动位置本就不动）
  loadOlder(): Promise<void> {
    const ds: ChatDataSource = this.refs.dataSource;
    const cursor = ds.oldestCursor();
    if (cursor === null) {
      return Promise.resolve();
    }
    return queryMessagesBefore(this.refs.conversationId(), cursor)
      .then((rows: MessageRow[]): void => {
        if (rows.length > 0) {
          ds.prepend(rows);
          // 头部前插使列表项下标平移——进页待校正目标失真即取消（2026-09-06 校正链二稿；
          // 正常路径用户翻历史手势已先清，本行兜异常路径防校正链与翻页锚点互抢拽底）
          this.refs.follow.cancelAlign();
          // 本批前插消息的附件简报装配（2026-09-15 预览第三轮）：同一查询面、另一批 id；
          // prepend 同步完成，查询回来时按 id 命中前插消息
          this.attachBriefsFor(rows);
        }
        if (rows.length < QUERY_TAIL_LIMIT) {
          ds.olderExhausted = true; // 到底（空页/不足一页）
        }
      })
      .catch((e: Object): void => {
        this.refs.toast('更早消息读取失败：' + (e as Error).message);
        throw e as Error;
      });
  }

  // 刷新：清错误态 + 重读连接 + 重拉历史；DB 未就绪时跳过读库动作（防「初始化失败」
  // 提示被「连接配置读取失败」覆盖——竞态修复守卫随迁）
  refreshPage(): void {
    this.refs.setError('');
    if (this.refs.dbReady()) {
      this.reloadConn();
      this.loadHistory();
    }
  }
}
