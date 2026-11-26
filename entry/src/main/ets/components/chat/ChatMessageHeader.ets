// 消息时间与轮头身份的显示零件单源（决明拍板）——①用户消息时间行（仅时间、右对齐，挂消息
// 最上；渲染点在 ChatMessageItem 用户分支，本件只出格式化函数）；②助手轮头行（头像 + 模型
// 名，挂本轮**首个上屏项**——载体 = ChatMessageItem（msg.headHost）或 ChatProcessSegment
//（item.head），两载体互斥、一轮只挂一处）。改判史：轮头行的独立时间行已退役——时间迁入
// 回答卡右上角常驻卡头行（渲染点 = ChatMessageItem 助手气泡分支，仅每轮回答卡显示）；
// formatMsgTime 仍为本件单源导出，两消费点共用，时间取值仍 = msg.createdAt（轮起始时刻：
// 实时链派发时写入、回放链 alignRoundStartTimes 归一）。
// · 尺寸口径（拍板定稿，真机可整组微调一档）：模型名 14fp 主文字色（比正文 16fp 略小一档）；
//   头像 32vp；时间格式 = 全量含秒 `YYYY-MM-DD HH:mm:ss` 本地时区（免相对格式跨天刷新与
//   时区边界）；头部只显示模型名，不带服务商后缀。
// · 跨 LazyForEach 的会话级数据（助手名称/头像编码/模型名兜底）走 AppStorage 广播键 +
//   @StorageProp 自订阅——头行组件位于 LazyForEach 展示项内，页级 @State 按值下发到此位置
//   会冻结（坑16 家族），键信道 = 既有正解先例。写点唯一 = ChatPage（setConnInfo /
//   onPageShown），见各键注释。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AssistantAvatar } from '../assistants/AssistantCardParts';
import { AssistantRow, queryAssistant } from '../../common/store/AssistantDb';
import { cardTitleColor } from '../../common/Theme';

// ── 会话级助手身份三键 ──
// 写点 = ChatPage（setConnInfo 连接重解析点写模型名兜底 + 异步解析有效归属助手的名称/头像
// 编码；onPageShown 补刷——子页改助手后返回即新值）。同值重复写不触发刷新（框架语义天然
// 去抖）；只写不删（坑15 竞态口径同族——进页首帧读缺省空串即零头行数据，解析到达后自订阅刷新）
export const CHAT_HEAD_AVATAR_KEY: string = 'chatHeadAvatar';
export const CHAT_HEAD_NAME_KEY: string = 'chatHeadName';
export const CHAT_HEAD_MODEL_KEY: string = 'chatHeadModel';

// 消息时间戳（全量含秒，本地时区；免「今天/昨天」相对格式的跨天刷新与时区边界）。<=0 /
// 非有限值回 ''——调用方按无值隐藏。格式化落点单源 = 本件（两消费点共用，禁第二份实现）
export function formatMsgTime(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) {
    return '';
  }
  const d: Date = new Date(ms);
  const pad = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
    pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

// 会话助手身份发布（本域数据入口；ChatPage 两调用点 = setConnInfo / onPageShown，页面只留
// 薄接线）：模型名兜底键同步写 + 有效归属助手（由调用方以 boundIdOf 闭包提供）的名称/头像
// 编码异步解析写。异步回填守卫 = 归属未再变（同 id 才落值——切助手竞态防旧值覆盖新值）；
// 查不到（已删防御）写空 = 头行首字兜底 '?'。dbReady 前查询失败仅日志——whenReady 链的
// reloadConn → setConnInfo 会再解析兜底
export function refreshChatHeadInfo(boundIdOf: () => string, modelLabel: string): void {
  AppStorage.setOrCreate<string>(CHAT_HEAD_MODEL_KEY, modelLabel);
  const id: string = boundIdOf();
  if (id === '') {
    AppStorage.setOrCreate<string>(CHAT_HEAD_NAME_KEY, '');
    AppStorage.setOrCreate<string>(CHAT_HEAD_AVATAR_KEY, '');
    return;
  }
  queryAssistant(id).then((row: AssistantRow | null): void => {
    if (boundIdOf() !== id) {
      return;
    }
    AppStorage.setOrCreate<string>(CHAT_HEAD_NAME_KEY, row !== null ? row.name : '');
    AppStorage.setOrCreate<string>(CHAT_HEAD_AVATAR_KEY, row !== null ? row.avatar : '');
  }).catch((e: Object): void => {
    hilog.warn(0xD5A4, 'ChatMessageHeader', 'assistant head resolve failed: %{public}s',
      (e as Error).message);
  });
}

// 助手轮头行（头像 + 模型名；左对齐随气泡左缘——宿主的左右内距照各载体既有布局，本件
// 不自带边距）。模型名为空只藏该行，仅剩头像（防御形态）
@Component
export struct ChatRoundHeader {
  // 轮级模型名（'' = 回退会话当前模型名兜底键）
  @Prop modelLabel: string = '';
  // 会话级助手身份（@StorageProp 自订阅；写点在 ChatPage，见键注释）
  @StorageProp(CHAT_HEAD_AVATAR_KEY) @Watch('syncHeadIdentity') avatarSpecIn: string = '';
  @StorageProp(CHAT_HEAD_NAME_KEY) @Watch('syncHeadIdentity') assistantNameIn: string = '';
  @StorageProp(CHAT_HEAD_MODEL_KEY) modelFallback: string = '';
  // 助手身份镜像（@State）：AssistantAvatar 入参为普通成员——存储装饰器变量不可直传普通
  // 成员（ArkTS 编译门实锤），且普通成员不随父刷新。镜像值 + 下方单元素 ForEach 键变重建
  // = 共享件「刷新责任在调用方」正解姿势（先例 = 编辑页 DetailCard 键 = 头像串 + 名称）
  @State private avatarSpec: string = '';
  @State private assistantName: string = '';

  // @Watch 首帧不触发——进组件先同步一次广播键现值（页面写点先于/后于本件挂载两序都收敛）
  aboutToAppear(): void {
    this.syncHeadIdentity();
  }

  private syncHeadIdentity(): void {
    this.avatarSpec = this.avatarSpecIn;
    this.assistantName = this.assistantNameIn;
  }

  // 显示用模型名（轮级真值 > 会话当前模型名兜底 > 空隐藏）
  private displayModelLabel(): string {
    return this.modelLabel !== '' ? this.modelLabel : this.modelFallback;
  }

  build() {
    Row({ space: 8 }) {
      ForEach([this.avatarSpec], (_spec: string): void => {
        AssistantAvatar({ spec: this.avatarSpec, fallbackText: this.assistantName,
          avatarSize: 32 })
      }, (_spec: string): string => 'h|' + this.avatarSpec + '|' + this.assistantName)
      Column({ space: 2 }) {
        if (this.displayModelLabel() !== '') {
          Text(this.displayModelLabel())
            .fontSize(14)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
