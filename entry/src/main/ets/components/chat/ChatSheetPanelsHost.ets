// 半模态七面板装配宿主（自 ChatPage 域级最小拆出，宪法 1200 硬线债档兑现）。域定义：
// **半模态七面板的装配宿主**——model / prompt / context / compress / editAssistant /
// stats / status 七形态按 kind 分派装配（面板本体、开启写序与手势关闭路由各在原位：面板件
// 七枚 / ChatSheetCtrl / ChatCompressCtrl）。
// · 与「整段抽出 = 纯转发转接壳」判例不冲突：该判例弃的是约 25 参数纯转发形态；本件持有
//   装配体与 kind 分派，页面回调经 refs 单口上行（编排体留页面），非只转发，反碎片③不违。
//   bindSheet 挂载与档位分发仍留 ChatPage build()（坑64 姿势不变）；面板族复用页面根唯一
//   bindSheet，不新增挂载点（注册表义务不触发）。
// · 反碎片三问：①职责 = 七面板装配分派；②不并入 = ChatQueueHost 是排队域、ChatFullInputHost
//   是全屏输入域、七面板是被装配本体（并入即宿主与被宿主倒置）、ChatPage 是页面壳（本件自
//   它拆出）；③非转接壳 = kind 分派 + 各面板参数装配与 refs 供给是实质逻辑。
// · kind 必须 @Prop（照 ChatQueueHost）：面板开启中换形态（如 context 面板压缩卡入口切
//   compress）只更换 sheetKind，bindSheet 挂载点与内容树不重建（关闭动画期内容恒在）——
//   普通成员会冻结在首建值，@Prop 随父 state 刷新即换分支。
// · 参数面：值参 kind / bottomInset / editAssistantInit（面板每次打开重建实例，创建后不变）；
//   @Link usage（页面 $ctxUsage 同链转传，本件内再 $usage 下发两用量面板）；compressCtrl
//   实例直传（页面恒传，非空无缺省）；refs 闭包（读口 = 页面 @State / 成员现读，写上行编排
//   体留页面——onPromptOverride 与 onSkillDesignated 的编排体在页面闭包内原样保留，本件零
//   编排重排）。
// · 零行为变化：七分支体自 ChatPage SheetHost 原样搬迁，仅引用改经 refs / 参数机械替换。
import { AiConnection } from '../../common/providers/AiTypes';
import { ChatStatusSource } from '../../common/chat/ChatPromptState';
import { ModelPickerSheet } from './ModelPickerSheet';
import { ChatPromptSheet } from './ChatPromptSheet';
import { ContextUsageSheet } from './ContextUsageSheet';
import { CompressPreviewSheet } from './CompressPreviewSheet';
import { EditAssistantSheet } from './EditAssistantSheet';
import { SessionStatsSheet } from './SessionStatsSheet';
import { ChatStatusSheet } from './ChatStatusSheet';
import { ChatCompressCtrl } from './ChatCompressCtrl';
import { ChatMessage } from './ChatMessageCompose';
import { ContextUsage } from './ChatContextUsage';
import { FilePickKind } from './AttachmentPickCtrl';
import { AttachmentListRow } from '../../common/store/AttachmentDb';

// 页面供给面（宿主注入；读口全部闭包延迟求值——禁值参快照；写上行编排体留页面，本件零编排）
export interface ChatSheetPanelsRefs {
  // ── 读口（页面 @State / 普通成员现读）──
  conversationId: () => string;
  conn: () => AiConnection | null;
  sending: () => boolean;
  modelLabel: () => string;
  providerLabel: () => string;
  thinkingValue: () => string;
  designatedSkillId: () => string;
  designatedSkillName: () => string;
  allMessages: () => ChatMessage[];
  clipLimit: () => number;
  statusSource: () => ChatStatusSource;
  boundAssistantId: () => string;
  promptOverrideId: () => string;
  // ── 写上行 / 编排（状态真相与编排体在页面）──
  onPickModel: (providerId: string, modelId: string) => void;
  onPromptOverride: (promptId: string, assistantId: string) => void;
  onSkillDesignated: (skillId: string, skillName: string) => void;
  onPickAttachment: (kind: FilePickKind) => void;
  // 重发文件行点击上行（★ 2026-10-31 附件重发笔：「会话设置」面板五——复制已发附件或工作区
  // 文件入列，编排体在页面闭包落 AttachmentPickCtrl.addCopiedFromFile，返回是否入列）。
  // ★ 同日重发降级笔：多带来源两参（workspacePath 非空 = 工作区段、sourceRow 非空 = 附件段）
  onReissuePicked: (name: string, srcRelPath: string, workspacePath: string,
    sourceRow: AttachmentListRow | null) => Promise<boolean>;
  // 联网卡两动作（★ 2026-10-30 联网项迁出笔——点引擎 = 全局当前引擎 + 本会话联网开，落
  // pickWebEngine；「关闭」= 本会话覆盖 '0'，落 pickWebSearch(false)。编排体在页面闭包）
  onWebEnginePick: (engineId: string) => void;
  onWebClose: () => void;
  onEditAssistantDraft: (text: string) => void;
  onSubmitEditMessage: (text: string) => Promise<boolean>;
  onEditAssistantClose: () => void;
  onCloseSheet: () => void;
}

@Component
export struct ChatSheetPanelsHost {
  // 当前形态（七值封闭于 ChatSheetCtrl 开启写序——页面传 sheetKind；@Prop 理由见头注释）
  @Prop kind: string = 'model';
  // 底部系统导航条高（透传面板底部留白兜底）
  bottomInset: number = 0;
  // 上下文用量（页面 $ctxUsage 同链 @Link 转传——活算落地自动刷新，重算中保留旧值）
  @Link usage: ContextUsage | null;
  // 编辑消息面板初值快照（打开时播种，面板重建实例后不变）
  editAssistantInit: string = '';
  // 压缩接线域实例（收口直调，单源在彼件；@Require 必填——页面恒传，免缺省占位实例）
  @Require compressCtrl: ChatCompressCtrl;
  // 页面供给闭包（缺省全空实现——页面构造恒全量注入）
  refs: ChatSheetPanelsRefs = {
    conversationId: (): string => '',
    conn: (): AiConnection | null => null,
    sending: (): boolean => false,
    modelLabel: (): string => '',
    providerLabel: (): string => '',
    thinkingValue: (): string => '',
    designatedSkillId: (): string => '',
    designatedSkillName: (): string => '',
    allMessages: (): ChatMessage[] => [],
    clipLimit: (): number => 0,
    statusSource: (): ChatStatusSource => ({
      promptSourceKind: 'none', promptSourceName: '', skillIds: [],
      memoryInjectEnabled: false, memoryScope: '', knowledgeAutoInjectEnabled: false
    }),
    boundAssistantId: (): string => '',
    promptOverrideId: (): string => '',
    onPickModel: (_providerId: string, _modelId: string): void => {
    },
    onPromptOverride: (_promptId: string, _assistantId: string): void => {
    },
    onSkillDesignated: (_skillId: string, _skillName: string): void => {
    },
    onPickAttachment: (_kind: FilePickKind): void => {
    },
    onReissuePicked: (_name: string, _srcRelPath: string, _workspacePath: string,
      _sourceRow: AttachmentListRow | null): Promise<boolean> =>
      Promise.resolve(false),
    onWebEnginePick: (_engineId: string): void => {
    },
    onWebClose: (): void => {
    },
    onEditAssistantDraft: (_text: string): void => {
    },
    onSubmitEditMessage: (_text: string): Promise<boolean> => Promise.resolve(false),
    onEditAssistantClose: (): void => {
    },
    onCloseSheet: (): void => {
    }
  };

  build() {
    if (this.kind === 'model') {
      ModelPickerSheet({
        // 打勾/使用中徽章 = 本会话当前生效值（conn 即解析链结果：会话覆盖 ?? 助手绑定 ??
        // 全局默认 ?? 首个启用）——原读全局 active 的键已退役（那是「会话内选择写成全局
        // 默认」的根因通道）
        selProviderId: this.refs.conn()?.providerId ?? '',
        selModelId: this.refs.conn()?.model ?? '',
        onPick: (providerId: string, modelId: string): void => {
          this.refs.onPickModel(providerId, modelId);
        },
        onClose: (): void => {
          this.refs.onCloseSheet();
        },
        bottomInset: this.bottomInset
      })
    } else if (this.kind === 'prompt') { // 会话设置半模态（原「附件与提示词」，2026-10-30 更名）
      ChatPromptSheet({ conversationId: this.refs.conversationId(), bottomInset: this.bottomInset,
        assistantBound: this.refs.boundAssistantId(),
        promptBound: this.refs.promptOverrideId(),
        // 「技能」卡第四子态播种：designateId 播种行开关初态、designateName 供技能卡右侧值；
        // onSkillDesignated 回上两值 = 内存态直接落，不落库不关面板
        designateId: this.refs.designatedSkillId(),
        designateName: this.refs.designatedSkillName(),
        onPick: (kind: FilePickKind): void => { this.refs.onPickAttachment(kind); },
        // 重发文件行点击（★ 2026-10-31 附件重发笔）：透传页面闭包，返回值（是否入列）原样
        // 回落子面板驱动「已加入」态
        onReissuePicked: (name: string, srcRelPath: string, workspacePath: string,
          sourceRow: AttachmentListRow | null): Promise<boolean> =>
          this.refs.onReissuePicked(name, srcRelPath, workspacePath, sourceRow),
        // 联网卡两动作（★ 2026-10-30 联网项迁出笔——编排体在页面闭包，本件零编排）
        onWebEnginePick: (engineId: string): void => {
          this.refs.onWebEnginePick(engineId);
        },
        onWebClose: (): void => {
          this.refs.onWebClose();
        },
        onSkillDesignated: (skillId: string, skillName: string): void => {
          this.refs.onSkillDesignated(skillId, skillName);
        },
        onPromptChanged: (promptId: string, assistantId: string): void => {
          this.refs.onPromptOverride(promptId, assistantId);
        },
        onClose: (): void => { this.refs.onCloseSheet(); } }) // 同 bindSheet 内切换选词
    } else if (this.kind === 'context') {
      // 上下文用量（数据经 $ctxUsage 绑定——活算落地自动刷新，重算中保留旧值；压缩卡 refs
      // 闭包供给消息流/截尾限/流式态，域体在 CompressPreviewSheet / CompressGen / CompressDb）
      ContextUsageSheet({
        usage: $usage,
        conversationId: this.refs.conversationId(),
        allMessages: (): ChatMessage[] => this.refs.allMessages(),
        clipLimit: (): number => this.refs.clipLimit(),
        sending: (): boolean => this.refs.sending(),
        onCompress: (): void => {
          this.compressCtrl.open();
        },
        onSummaryDeleted: (summaryIds: string[]): void => {
          this.compressCtrl.summaryDeleted(summaryIds);
        },
        // 上下文清空两键上行：动作本体与库写入全在 ChatCompressCtrl——本页只接两行薄口
        //（返回值 = 是否确有一次写入，面板据此重载状态行）
        onClearContext: (): Promise<boolean> => this.compressCtrl.clearContext(),
        onClearRevoked: (): Promise<boolean> => this.compressCtrl.revokeClear(),
        onClose: (): void => { this.refs.onCloseSheet(); },
        bottomInset: this.bottomInset
      })
    } else if (this.kind === 'compress') {
      // 压缩预览（用量面板压缩卡入口；三态与落库见 CompressPreviewSheet——采用上行与关闭
      // 确认都交 compressCtrl）
      CompressPreviewSheet({
        refs: {
          conversationId: (): string => this.refs.conversationId(),
          allMessages: (): ChatMessage[] => this.refs.allMessages(),
          conn: (): AiConnection | null => this.refs.conn(),
          // 压缩素材读口的预算来源（与实发同口径，同 ContextUsageSheet.clipLimit 供给）
          clipLimit: (): number => this.refs.clipLimit()
        },
        onRequestClose: (): void => {
          this.compressCtrl.requestClose();
        },
        onDraftState: (hasDraft: boolean): void => {
          this.compressCtrl.setDraftState(hasDraft);
        },
        onAdoptState: (adopting: boolean): void => {
          this.compressCtrl.setAdoptState(adopting);
        },
        onAdopted: (rowId: string, summaryText: string, coversToSeq: number): void => {
          this.compressCtrl.adopt(rowId, summaryText, coversToSeq);
        },
        bottomInset: this.bottomInset
      })
    } else if (this.kind === 'editAssistant') {
      // 编辑消息面板（两角色共用——保存按在编节点分流）
      EditAssistantSheet({
        initial: this.editAssistantInit,
        bottomInset: this.bottomInset,
        onDraftChange: (text: string): void => {
          this.refs.onEditAssistantDraft(text);
        },
        onSave: (text: string): Promise<boolean> => this.refs.onSubmitEditMessage(text),
        onClose: (): void => {
          this.refs.onEditAssistantClose();
        }
      })
    } else if (this.kind === 'stats') {
      // 会话统计（标题栏更多菜单入口；usage 同 $ctxUsage 链，消息/附件统计面板自装载）
      SessionStatsSheet({
        usage: $usage,
        conversationId: this.refs.conversationId(),
        onClose: (): void => { this.refs.onCloseSheet(); },
        bottomInset: this.bottomInset
      })
    } else if (this.kind === 'status') {
      // 会话状态（输入栏「状态」chip 入口；只读总览，零回写零副作用）。数据 = 页面 @State
      // 现读 + 注入侧整包快照（组装单源在 ChatPromptState）+ 面板自拉；refs 闭包延迟求值
      //（子件不反向 import 宿主，坑50 环规避）
      ChatStatusSheet({
        refs: {
          modelLabel: (): string => this.refs.modelLabel(),
          providerLabel: (): string => this.refs.providerLabel(),
          thinkingValue: (): string => this.refs.thinkingValue(),
          designatedSkillName: (): string => this.refs.designatedSkillName(),
          statusSource: (): ChatStatusSource => this.refs.statusSource()
        },
        onClose: (): void => { this.refs.onCloseSheet(); },
        bottomInset: this.bottomInset
      })
    }
  }
}
