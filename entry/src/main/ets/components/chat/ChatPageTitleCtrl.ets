// 聊天页标题栏两态的会话标题数据供给域（2026-11-15 自 ChatPage 域级最小拆分）。
// 职责一句话：按 conversationId 反查会话行标题并写 CHAT_TITLE_TEXT_KEY 广播键，供官方
// stackBuilder 覆盖层判「新会话胶囊态 / 有标题两行态」并取主标题文案。
// · 为何新开而非并入：ChatPageLoad 是历史装载编排域（标题反查不是装载链）、
//   ChatTitleMenuFactory 是纯常量零状态域（本件持有并发令牌与销毁守卫），并入任一都会
//   混职责；本件只依赖 store 只读口 + 常量，不反向依赖页面组件（层级单向）。
// · 刷新四路 = 进页早查（refreshIfReady，isReady 门；预置命中时退为校正）/ 历史装载收尾
//   （DB 就绪首查兜底）/ onShown（改名回栈重显）/ CONV_TITLE_TICK_KEY（占位升级、AI 标题
//   写回），四路都走同一 refresh 单入口。
// · 预置通道（2026-11-15 反馈二笔）：异步反查永远晚于首帧——列表/搜索页点卡时
//   seedTitlePreset 已同步落两键（标题 + 属主会话 id），本件 adoptPreset 进页比对属主：
//   一致 = 首帧保留预置标题（两行态即达），refreshIfReady 随后校正 DB 真值；不一致
//   （新建/残留/分享拉起）= 写 '' 清残留回胶囊态。
// · 无行新会话写 '' = 胶囊态；失败 fail-safe 回落 ''（P0-1 留痕不静默，不谎报旧标题）。
// · 并发与寿命：seq 令牌防先发后到覆写，markDeparted 防退页迟到回写（成对释放口径）。
import { hilog } from '@kit.PerformanceAnalysisKit';
// isReady 别名引 ChatDb 单一初始化源（早查就绪门；共享句柄未就绪即抛错的防线在 requireStore）
import { isReady as isChatDbReady } from '../../common/store/ChatDb';
import { queryConversationTitlesByIds } from '../../common/store/ChatDbReadSearch';
import { CHAT_TITLE_PRESET_CONV_KEY, CHAT_TITLE_TEXT_KEY } from './ChatTitleMenuFactory';

export class ChatTitleSupplyCtrl {
  private readonly conversationId: () => string;
  private titleSeq: number = 0;
  private departed: boolean = false;

  constructor(conversationId: () => string) {
    this.conversationId = conversationId;
  }

  // 进页采纳预置（2026-11-15 反馈二笔升级自 clear）：预置属主键与本页会话一致 = 点卡播种
  // 在场，保留广播键现值——首帧直接渲染两行态，异步反查只做校正；不一致（新建/残留/分享）
  // = 写 '' 清残留（只写不删、写空串值非删键，无坑15 竞态），回胶囊态待反查。
  adoptPreset(): void {
    const owner: string | undefined = AppStorage.get<string>(CHAT_TITLE_PRESET_CONV_KEY);
    if (owner !== undefined && owner === this.conversationId()) {
      return;
    }
    AppStorage.setOrCreate<string>(CHAT_TITLE_TEXT_KEY, '');
  }

  // 进页早查（2026-11-15 真机反馈笔；反馈二笔后定位）：DB 已就绪立即反查——预置命中时
  // 退为校正层（比对播种值与 DB 真值，几 ms 级），无预置路径（主动消息/命令链直达）仍是
  // 首个标题来源；未就绪（冷启动直达）静默让位历史装载收尾首查兜底，不在此打「数据库
  // 未就绪」warn 噪音。查询失败仍由 refresh 的 catch 留痕回落（P0-1 不静默）。
  refreshIfReady(): void {
    if (!isChatDbReady()) {
      return;
    }
    this.refresh();
  }

  // 退页守卫（与 refresh 的异步 then/catch 成对）
  markDeparted(): void {
    this.departed = true;
  }

  // 标题反查（IN 集一次查回，P1-2 轻量）；写 AppStorage 广播键而非页面 @State —— 覆盖层
  // 经官方 titleBar napi 消费，@Prop 透传不保刷新（坑16 正解 = @StorageProp 自订阅）
  refresh(): void {
    const seq: number = ++this.titleSeq;
    const cid: string = this.conversationId();
    queryConversationTitlesByIds([cid])
      .then((titles: Map<string, string>): void => {
        if (this.departed || seq !== this.titleSeq) {
          return;
        }
        AppStorage.setOrCreate<string>(CHAT_TITLE_TEXT_KEY, titles.get(cid) ?? '');
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatPageTitle', '会话标题反查失败：%{public}s',
          (e as Error).message);
        if (!this.departed && seq === this.titleSeq) {
          AppStorage.setOrCreate<string>(CHAT_TITLE_TEXT_KEY, '');
        }
      });
  }
}
