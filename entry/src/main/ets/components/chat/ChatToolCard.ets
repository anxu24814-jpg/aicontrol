// 工具步骤标题与专用内容。图标进入共享标题热区，正文独立缩进保持文字左沿。
// 审批与作答常显；原文切换、格式化与复制归 ChatToolRawPanel，段壳只负责背景和几何连线。
// 退役史防回游：chart_display 图表卡已随「图表正文化」整块退役（渲染件 = ChatToolChartCard、
// 判据单源 = ToolChart.chartDisplaySpec；单一渲染位 = 正文，本件无图表渲染位）。
// 本件处软引导区（技术债务清单按文件建档）；新块一律抽独立件——diff 先例 ChatToolDiffBlock
//（路由单源 toolDiffForCard，本件零内联解析）、摘要行先例 ChatToolSummaryRow。
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { cardBorderColor, cardDescColor, cardTitleColor, badgeBg,
  SEGMENT_ROW_PAD_R, SEGMENT_BODY_PAD_L } from '../../common/Theme';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';
import { ChatToolRawPanel } from './ChatToolRawPanel';
import { ChatToolDiffBlock, ToolDiffView, toolDiffForCard,
  TOOL_DIFF_MAX_ROWS_PER_SIDE, TOOL_DIFF_MAX_ROW_CHARS } from './ChatToolDiffBlock';
import { ChatToolSummaryRow } from './ChatToolSummaryRow';
import { toolTitle, toolRegistry } from '../../common/providers/ToolTypes';
import { SearchResultItemPayload } from '../../common/providers/ToolWebSearch';
import { isTemplateToolName } from '../../common/providers/HttpTemplate';
import { ToolEntry } from '../../common/providers/ToolContracts';
import { TOOL_BROWSE_ACT, TOOL_EDIT_SYSTEM_PROMPT, TOOL_HTTP_REQUEST,
  TOOL_MANAGE_KNOWLEDGE, TOOL_MANAGE_MEMORY, TOOL_MANAGE_PROMPTS, TOOL_SEARCH_WEB,
  TOOL_SCRAPE_WEB, TOOL_SET_FUNCTIONAL_MODEL,
  TOOL_WORKSPACE_DELETE, TOOL_CREATE_CALENDAR_EVENT, TOOL_UPDATE_CALENDAR_EVENT,
  TOOL_DELETE_CALENDAR_EVENT, TOOL_MANAGE_PROVIDERS, TOOL_MANAGE_MODELS, TOOL_MANAGE_BALANCE,
  TOOL_MOUNT_WRITE, TOOL_MOUNT_COPY_IN, TOOL_MOUNT_DELETE,
  TOOL_EXEC_NODE, TOOL_EXEC_PYTHON }
  from '../../common/providers/ToolIds';
import { CONFIRM_RESULT_AI_ALLOWED, CONFIRM_RESULT_AI_DENIED } from '../../common/providers/ToolContracts';
import { fileIo as fs } from '@kit.CoreFileKit';
import { openSystemPreview } from '../../common/AttachmentUtil';
import { AiImagePart } from '../../common/providers/AiTypes';
import { formatWorkspaceSize } from '../../common/WorkspaceUtil';
import { workspaceFilesDir } from '../../common/store/WorkspaceDb';
import { ChatMessage, isAskAwaiting, isAskCard, isConfirmAwaiting, isConfirmDone,
  isConfirmIrreversible, isStepAwaitingUser, toolStepIcon } from './ChatMessageCompose';
import { AskQuestion, ChatAskUserCard, parseQuestions } from './ChatAskUserCard';
import { askAnsweredOfDraft } from './ChatDockTitles';
import { ChatBrowseConfirmCard } from './ChatBrowseConfirmCard';
import { ChatToolInstallCard, isNodeInstallCard } from './ChatToolInstallCard';
import { ChatStepTitleRow } from './ChatStepTitleRow';
import { launchExternalLink } from '../../common/ExternalLink';

// 提问卡回执行载荷（toolOutputJson 的 answers[] 逐项；selectedOptions 仅解析备用——渲染面
// 按组合答案整串上屏不单独消费；skipped 决定答案行文案，旧 payload 缺键按缺省降级）
interface AskAnswerRow {
  id: string;
  question: string;
  answer: string;
  selectedOptions: string[];
  skipped: boolean;
}

// ★ 笔 7 下载产物行载荷：http_request 回执 saved 键的展示面快照（产物真身恒 workspace_files
// 表；path 为工作区相对路径，预览时由卡面拼 filesDir）
interface SavedFileRow {
  name: string;
  kind: string;
  size: number;
  path: string;
}

// 工具卡展开区最大高度（vp）：有界红线——超长 output 区内滚动，不撑爆消息流
const TOOL_DETAIL_MAX_HEIGHT: number = 240;

// 工具卡展开/收起动画时长（ms；官方 FAQ faqs-arkui-769 折叠示例同值 300ms）。本卡是条件
// 渲染式折叠（无内容盒解耦），动画只插值高度与箭头旋转（折叠动画先例，见 toggleExpanded）
const TOOL_FOLD_ANIM_MS: number = 300;

@Component
export struct ChatToolCard {
  // @ObjectLink + @Watch 双钩子认领（官方 ts-state-management-watch 示例同形）：
  // aboutToAppear 接首帧即等待的提问卡，@Watch 接确认卡「先落 running 行、预检后才写
  // toolConfirmText」的后到等待态。@ObjectLink 的 @Watch 依赖父刷新、晚一拍，故作答路径
  // 由托管位同帧释放，本钩子只兜外部停止/换源等场景。
  @ObjectLink @Watch('onMsgChanged') msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 正文字体两键 @StorageProp 自订阅：卡内文字随正文字体即时变化（标题由 ChatStepTitleRow
  // 自订阅；原始面板 ChatToolRawPanel 自判，不在此列）
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 提问卡作答进度（ChatAskUserCard 作答变化时上行，头行进度徽章的 n；总数 N 现算不双份存）
  @State askAnswered: number = 0;
  // 步骤详情开启上行（仅用户关→开时调用——段容器据此提升段展开意愿「视为正在阅读」并取消进页旧校正）
  onDetailOpened: () => void = (): void => {
  };
  // ask_user 答案上行（ChatMessageItem 透传 → ChatPage → ToolRuntime.resolveAsk）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  // browse_act 高危确认上行（ChatMessageItem 透传 → ChatPage → ChatSendCtrl.resolveBrowseConfirm）
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  // 输入位托管认领上行（等待态到达 → ChatProcessStep → Segment → ChatPageContent.claimAskDock）
  onAwaitingStep: (msg: ChatMessage) => void = (msg: ChatMessage): void => {};
  // 模板重发上行（msgId + 工具名 + 卡上原入参 JSON——ChatMessageItem → ChatPageContent →
  // ChatPage → ChatSendCtrl 重发编排域）
  onResend: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};
  // 改参数重发上行（同链——现查模板行开编辑对话框，确认后走 onResend 执行）
  onEditResend: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {};

  // 工具展示名（函数名 → 中文卡题；未注册函数名原样——自定义/未知工具可读性兜底）
  private toolDisplayName(): string {
    return toolTitle(this.msg.toolName);
  }

  // 正文字体家族串（推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // ── 模板重发入口判据 ──
  // 仅模板工具卡（slug 注册名）且模板仍在注册表（已删除模板经 syncTemplateTools 注销后卡上
  // 不出键）；普通 http_request 卡不做重发（方案范围 = 模板卡）
  private resendEntry(): ToolEntry | null {
    if (!isTemplateToolName(this.msg.toolName)) {
      return null;
    }
    const entry: ToolEntry | undefined = toolRegistry.get(this.msg.toolName);
    return entry !== undefined ? entry : null;
  }

  // 有参数模板才出「改参数」键（schema properties 键数 > 0；坏 JSON 防御不出编辑键只出重发键）
  private hasTemplateParams(): boolean {
    const entry: ToolEntry | null = this.resendEntry();
    if (entry === null) {
      return false;
    }
    try {
      const parsed = JSON.parse(entry.parametersJson) as Record<string, Object>;
      const props: Object | undefined = parsed['properties'];
      if (typeof props !== 'object' || props === null) {
        return false;
      }
      return Object.keys(props as Record<string, Object>).length > 0;
    } catch (e) {
      return false;
    }
  }

  // 工具卡是否有可展开详情（无详情不挂点击——防「可点感」死交互）。
  // 判据覆盖**所有将被收起隐藏的非空信息**：输入/输出原串、inputText/displayText、msg.text
  // 错误、进度/待办/任务/子代理、图片、产物文件、来源引文——任意一项非空即可展开（旧「短于
  // 40 字符便无展开价值」阈值已移除；信息不删除，只换到展开后显示）
  private toolHasDetail(): boolean {
    const inputJson: string = this.msg.toolInputJson ?? '';
    const outputJson: string = this.msg.toolOutputJson ?? '';
    const inputText: string = this.msg.toolInputText ?? '';
    const displayText: string = this.msg.toolDisplayText ?? '';
    return inputJson !== '' || outputJson !== '' || inputText !== '' || displayText !== '' ||
      this.msg.text !== '' || this.msg.toolProgressPercent !== undefined ||
      this.msg.toolProgressText !== undefined || this.msg.toolTodoId !== undefined ||
      this.msg.toolTaskId !== undefined || this.msg.toolAgentSummary !== undefined ||
      this.msg.toolMediaParts !== undefined || this.savedFile() !== null ||
      this.toolSearchRefs().length > 0;
  }

  // 详情意愿 = msg.detailExpanded（页面寿命，列表项回收重建不丢；首次缺省 = 收起 false）
  private detailExpanded(): boolean {
    return this.msg.detailExpanded === true;
  }

  // 专用交互/回执区（确认回执行 / 提问作答 / 提问回执 / 确认等待）——**常显**，不进折叠
  private dedicatedVisible(): boolean {
    return (this.confirmDone() &&
      (!this.confirmAiJudged() || this.confirmAiReceiptText() !== '')) ||
      this.askDone() ||
      ((this.askAwaiting() || this.confirmAwaiting()) && this.msg.dockOwned !== true);
  }

  // 折叠详情区（普通卡与确认卡完成态；★ 域①：提问卡任何态不提供展开；专用交互态不渲染详情）
  private detailVisible(): boolean {
    // 等待态（含被底部托管的卡）恒不显折叠详情：托管时只留头行，不能因 dedicated 收起
    // 而误开详情区（判据不看 dockOwned，只看「是否仍在等用户」）
    return this.detailExpanded() && this.toolHasDetail() && !this.askAwaiting() &&
      !this.confirmAwaiting() && !this.askDone() && !this.askCancelled();
  }

  // 卡体（标题行之下）是否存在——分割线显隐（普通卡 = 仅展开详情；专用卡 = 交互/回执区）
  private bodyVisible(): boolean {
    return this.dedicatedVisible() || this.detailVisible();
  }

  // 工具结果附件的图片部分（只收 mime 前缀 image/ 的项；application/pdf 不渲染——判据写在渲染前）
  private toolMediaImages(): AiImagePart[] {
    const parts: AiImagePart[] | undefined = this.msg.toolMediaParts;
    if (parts === undefined) {
      return [];
    }
    const images: AiImagePart[] = [];
    for (const part of parts) {
      if (part.mimeType.startsWith('image/')) {
        images.push(part);
      }
    }
    return images;
  }

  // 搜索类工具结果 → 引文列表（result JSON 的 results[] 解析；坏 JSON/非搜索工具回空数组
  // 不渲染。回放路径 toolOutputJson 同源，历史消息引文卡自动可用。记忆化见下方记忆化注释）
  private toolSearchRefs(): SearchResultItemPayload[] {
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === this.refsCacheJson) {
      return this.refsCacheList;
    }
    const refs: SearchResultItemPayload[] = this.parseSearchRefs(outputJson);
    this.refsCacheJson = outputJson;
    this.refsCacheList = refs;
    return refs;
  }

  private parseSearchRefs(outputJson: string): SearchResultItemPayload[] {
    if (this.msg.toolName !== TOOL_SEARCH_WEB && this.msg.toolName !== TOOL_SCRAPE_WEB) {
      return [];
    }
    if (outputJson === '') {
      return [];
    }
    try {
      const parsed = JSON.parse(outputJson) as Record<string, Object>;
      const raw: Object = parsed['results'];
      if (!Array.isArray(raw)) {
        return [];
      }
      const refs: SearchResultItemPayload[] = [];
      const items: object[] = raw as object[];
      for (const item of items) {
        const rec = item as Record<string, Object>;
        refs.push({
          index: typeof rec['index'] === 'number' ? rec['index'] as number : 0,
          id: typeof rec['id'] === 'string' ? rec['id'] as string : '',
          title: typeof rec['title'] === 'string' ? rec['title'] as string : '',
          url: typeof rec['url'] === 'string' ? rec['url'] as string : '',
          snippet: typeof rec['snippet'] === 'string' ? rec['snippet'] as string : ''
        });
      }
      return refs;
    } catch (e) {
      return [];
    }
  }

  // 引文点击 → 系统打开（统一出口 launchExternalLink = openLink 官方推荐路径；失败静默
  //——URL 打开非关键路径，不打断阅读）
  private openRefUrl(url: string): void {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, url);
    } catch (e) {
      // 静默（拿不到宿主 context 的边缘形态）
    }
  }

  // ── 解析记忆化：build 判据链一次渲染会重复取各解析（savedFile/toolSearchRefs/askAnswers/
  // askQuestions/diff）多次，流式期 toolState 每次原地更新都整批重跑 JSON.parse。解析结果
  // 是各自输入串的纯函数（toolName 每卡恒定），键取对应 JSON 串即可安全复用——串变即失效
  // 重算，缓存恒与入参一致零陈旧面（宪法渲染克制条：构建函数内不高耗操作）
  private savedCacheJson: string = '';
  private savedCacheRow: SavedFileRow | null = null;
  private refsCacheJson: string = '';
  private refsCacheList: SearchResultItemPayload[] = [];
  private askAnswersCacheJson: string = '';
  private askAnswersCacheRows: AskAnswerRow[] = [];
  private askQuestionsCacheJson: string = '';
  private askQuestionsCacheList: AskQuestion[] = [];
  // 变更 diff 视图缓存：toolName / inputJson / outputJson 全在键——任一变化即失效重算，零陈旧面
  private diffCacheTool: string = '';
  private diffCacheInputJson: string = '';
  private diffCacheOutputJson: string = '';
  private diffCacheView: ToolDiffView | null = null;

  // ★ 笔 7 下载产物：http_request 回执 saved 键 → 类型化载荷；坏 JSON/缺键/非本工具一律
  // 回 null 零渲染（老会话回执无 saved 键零回归）。回放路径同源，历史消息产物行自动可用
  private savedFile(): SavedFileRow | null {
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === this.savedCacheJson) {
      return this.savedCacheRow;
    }
    const row: SavedFileRow | null = this.parseSavedFile(outputJson);
    this.savedCacheJson = outputJson;
    this.savedCacheRow = row;
    return row;
  }

  private parseSavedFile(outputJson: string): SavedFileRow | null {
    if (this.msg.toolName !== TOOL_HTTP_REQUEST) {
      return null;
    }
    if (outputJson === '') {
      return null;
    }
    try {
      const parsed = JSON.parse(outputJson) as Record<string, Object>;
      const raw: Object | undefined = parsed['saved'];
      if (typeof raw !== 'object' || raw === null) {
        return null;
      }
      const rec = raw as Record<string, Object>;
      const name: Object | undefined = rec['name'];
      const kind: Object | undefined = rec['kind'];
      const size: Object | undefined = rec['size'];
      const path: Object | undefined = rec['path'];
      if (typeof name !== 'string' || typeof path !== 'string' || path === '') {
        return null;
      }
      return {
        name: name,
        kind: typeof kind === 'string' ? kind : 'other',
        size: typeof size === 'number' ? size : 0,
        path: path
      };
    } catch (e) {
      return null;
    }
  }

  // 产物行预览绝对路径（缩略图 Image 直吃；filesDir 未捕获回空串零渲染）
  private savedFilePath(): string {
    const saved: SavedFileRow | null = this.savedFile();
    if (saved === null) {
      return '';
    }
    const filesDir: string = workspaceFilesDir();
    return filesDir === '' ? '' : filesDir + '/' + saved.path;
  }

  // 产物行点击 → 系统预览；文件被删（工作区生命周期独立于会话，此态可达）toast 指引——
  // 不静默无响应（P0-1）
  private openSavedFile(saved: SavedFileRow): void {
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return;
    }
    const absPath: string = filesDir + '/' + saved.path;
    try {
      fs.accessSync(absPath);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '文件已从文件工作区删除' });
      return;
    }
    openSystemPreview(this.getUIContext(), saved.name, absPath);
  }

  // 退役防回游：卡体判据（toolHasBody）已退役——显隐由 dedicatedVisible + detailVisible
  // 两判据合取覆盖（摘要字段已并入 toolHasDetail、确认两谓词在 dedicated 分支），勿再引入。

  // ── 专属卡头判据（两族四态；判据本体单源在 ChatMessageCompose，本件薄委托）──
  private confirmAwaiting(): boolean {
    return isConfirmAwaiting(this.msg);
  }

  private confirmDone(): boolean {
    return isConfirmDone(this.msg);
  }

  // 确认档位是否不可逆（undefined = 写操作档兜底——老数据/跳过预检的历史卡不因缺字段错显红档）
  private confirmLevelIrreversible(): boolean {
    return isConfirmIrreversible(this.msg);
  }

  // ── 审批模型闸回执判据：result 落审批闸两值即 ai 回执（无人工参与，写点 =
  // ChatToolRoundCtrl.runApprovalOrConfirm 审批分支）。卡头状态位与回执行首行都按本判据
  // 分流（禁散写字面量——两岸共引 ToolContracts 常量）──
  private confirmAiAllowed(): boolean {
    return this.msg.toolConfirmResult === CONFIRM_RESULT_AI_ALLOWED;
  }

  private confirmAiDenied(): boolean {
    return this.msg.toolConfirmResult === CONFIRM_RESULT_AI_DENIED;
  }

  private confirmAiJudged(): boolean {
    return this.confirmAiAllowed() || this.confirmAiDenied();
  }

  // ai 回执状态位文案（aiAllowed 执行中窗口区分「已允许，执行中」；aiDenied 恒终态）
  private confirmAiStatusText(): string {
    if (this.confirmAiAllowed()) {
      return this.msg.toolState === 'running' ? '审批模型已允许，执行中' : '审批模型已允许';
    }
    return '审批模型已拒绝';
  }

  // ai 回执行首行文本（aiDenied = 审批理由，空理由给缺省句——理由缺失也要可感知；aiAllowed
  // = 理由原文，空则调用点不渲染本行——卡头状态位已表达）
  private confirmAiReceiptText(): string {
    const reason: string = this.msg.toolConfirmReason ?? '';
    if (this.confirmAiDenied()) {
      return reason !== '' ? reason : '审批模型拒绝本次调用，未返回理由';
    }
    return reason;
  }

  // 作答是否「已允许」（回执行状态位文案判据）
  private confirmApproved(): boolean {
    return this.msg.toolConfirmResult === 'approved';
  }

  // 本会话内允许（★ 会话级免询问的自动路径不产生回执、从未显示确认卡，本谓词只服务
  //「用户按了第三键」这一种作答）
  private confirmSessionApproved(): boolean {
    return this.msg.toolConfirmResult === 'session';
  }

  // 是否提问卡（工具名判据——两种态共用，展开面与专属头分支同源）
  private askCard(): boolean {
    return isAskCard(this.msg);
  }

  // 提问卡（等待）：running 即等作答（问题列表在场与否交卡体兜底提示）
  private askAwaiting(): boolean {
    return isAskAwaiting(this.msg);
  }

  // 提问卡（回执）：已结束 ＋ 结果能解析出 answers 数组（解析失败 = 回执不成立，退回普通
  // 工具卡——不炸渲染，§5.3）
  private askDone(): boolean {
    return this.askCard() && this.msg.toolState !== 'running' && this.askAnswers().length > 0;
  }

  // 提问卡（中止）：★ 域①——停止/销毁把等待中的 ask 卡置 cancelled，渲染「提问已中止」：
  // 不显示答案输入面（挂起已取消，作答无处续跑）也不显「出错」；中止载荷无 answers，
  // askDone 天然不成立
  private askCancelled(): boolean {
    return this.askCard() && this.msg.toolState === 'cancelled';
  }

  // 卡头标题·确认卡（标题自 ChatBrowseConfirmCard 上移本件；browse_act 与网络请求两支
  // 逐字不动——124 组配对钉锚面）。
  // 判据 = 末尾三元 fallback 只属 http_request 家族（含模板工具——isTemplateToolName 同返
  // 该支），其余 preflight 工具一律显式分支；**新增 preflight 工具时此处必须同步加名**
  //（124 组「十四题逐位 + 全量 preflight 覆盖」关系钉；漏加 = 卡头误显网络请求文案，
  // M2/M3 笔已两度复现）
  private confirmTitle(): string {
    if (this.msg.toolName === TOOL_MANAGE_MEMORY) {
      return '助手请求删除记忆';
    }
    if (this.msg.toolName === TOOL_MANAGE_KNOWLEDGE) {
      return '助手请求删除知识库条目';
    }
    if (this.msg.toolName === TOOL_EDIT_SYSTEM_PROMPT) {
      return '助手请求修改系统提示词';
    }
    if (this.msg.toolName === TOOL_MANAGE_PROMPTS) {
      return '助手请求改动会话提示词';
    }
    if (this.msg.toolName === TOOL_SET_FUNCTIONAL_MODEL) {
      return '助手请求设置功能模型';
    }
    if (this.msg.toolName === TOOL_CREATE_CALENDAR_EVENT) {
      return '助手请求创建日程';
    }
    if (this.msg.toolName === TOOL_UPDATE_CALENDAR_EVENT) {
      return '助手请求修改日程';
    }
    if (this.msg.toolName === TOOL_DELETE_CALENDAR_EVENT) {
      return '助手请求删除日程';
    }
    if (this.msg.toolName === TOOL_WORKSPACE_DELETE) {
      return '助手请求删除工作区条目';
    }
    if (this.msg.toolName === TOOL_MANAGE_PROVIDERS) {
      return '助手请求改动服务商配置';
    }
    if (this.msg.toolName === TOOL_MANAGE_MODELS) {
      return '助手请求改动模型配置';
    }
    if (this.msg.toolName === TOOL_MANAGE_BALANCE) {
      return '助手请求改动余额配置';
    }
    if (this.msg.toolName === TOOL_MOUNT_WRITE) {
      return '助手请求写入挂载文件';
    }
    if (this.msg.toolName === TOOL_MOUNT_COPY_IN) {
      return '助手请求复制文件到挂载';
    }
    if (this.msg.toolName === TOOL_MOUNT_DELETE) {
      return '助手请求删除挂载文件';
    }
    // 两执行域确认卡标题（门 2 同域补缺：Python 既有预检此前落网络请求兜底支，Node 新接；
    // 124 组逐字配对钉锚面——改文案须同步断言期望表。★ 门 3 U2：exec_node 的 install
    // 动作细分独立标题，判据 = 工具名 + 入参 action，单源 isNodeInstallCard）
    if (this.msg.toolName === TOOL_EXEC_NODE && isNodeInstallCard(this.msg)) {
      return '助手请求安装 npm 包';
    }
    if (this.msg.toolName === TOOL_EXEC_NODE) {
      return '助手请求运行 Node 代码';
    }
    if (this.msg.toolName === TOOL_EXEC_PYTHON) {
      return '助手请求运行 Python 代码';
    }
    return this.msg.toolName === TOOL_BROWSE_ACT ? '助手请求操作网页' : '助手请求发送网络请求';
  }

  // 卡头标题·提问卡（单题 / 多题两态；题数 = 入参 questions 现算，与进度徽章的 N 同源）
  private askTitle(): string {
    return this.askQuestions().length > 1 ? '助手想跟你确认几个问题' : '助手想跟你确认一下';
  }

  // 提问卡题目列表（parseQuestions 单源 = ChatAskUserCard 导出；记忆化——等待期每次输入
  // 上行都整卡 rebuild，解析不重跑）
  private askQuestions(): AskQuestion[] {
    const inputJson: string = this.msg.toolInputJson ?? '';
    if (inputJson === this.askQuestionsCacheJson) {
      return this.askQuestionsCacheList;
    }
    const questions: AskQuestion[] = parseQuestions(inputJson);
    this.askQuestionsCacheJson = inputJson;
    this.askQuestionsCacheList = questions;
    return questions;
  }

  // 提问卡答案列表（回执行数据源 = 结果 JSON 的 answers[]；坏 JSON/非数组/缺键 → 空数组，
  // 回执行判据随之不成立。记忆化同上）
  private askAnswers(): AskAnswerRow[] {
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (outputJson === this.askAnswersCacheJson) {
      return this.askAnswersCacheRows;
    }
    const rows: AskAnswerRow[] = this.parseAskAnswers(outputJson);
    this.askAnswersCacheJson = outputJson;
    this.askAnswersCacheRows = rows;
    return rows;
  }

  private parseAskAnswers(outputJson: string): AskAnswerRow[] {
    if (outputJson === '') {
      return [];
    }
    let rows: object[] | undefined = undefined;
    try {
      const parsed = JSON.parse(outputJson) as Record<string, Object>;
      const raw: Object = parsed['answers'];
      if (Array.isArray(raw)) {
        rows = raw as object[];
      }
    } catch (e) {
      return [];
    }
    if (rows === undefined) {
      return [];
    }
    const result: AskAnswerRow[] = [];
    for (const item of rows) {
      const rec = item as Record<string, Object>;
      if (typeof rec['id'] === 'string' && typeof rec['question'] === 'string') {
        const answerRaw: Object = rec['answer'];
        const selectedRaw: Object = rec['selected_options'];
        const selected: string[] = [];
        if (Array.isArray(selectedRaw)) {
          const options: Object[] = selectedRaw as Object[];
          for (const option of options) {
            if (typeof option === 'string') {
              selected.push(option as string);
            }
          }
        }
        result.push({
          id: rec['id'] as string,
          question: rec['question'] as string,
          answer: typeof answerRaw === 'string' ? answerRaw as string : '',
          selectedOptions: selected,
          // 缺省 false 兼容旧 payload（旧版无本字段，真值只有 true 一种写法）
          skipped: rec['skipped'] === true
        });
      }
    }
    return result;
  }

  // 变更 diff 视图：解析分派单源在 ChatToolDiffBlock.toolDiffForCard（本件零内联解析，
  // 见头注释）；无 diff 工具自然 null。记忆化三键全等才命中，任一串变即失效重算
  private toolDiff(): ToolDiffView | null {
    const toolName: string = this.msg.toolName;
    const inputJson: string = this.msg.toolInputJson ?? '';
    const outputJson: string = this.msg.toolOutputJson ?? '';
    if (toolName === this.diffCacheTool && inputJson === this.diffCacheInputJson &&
      outputJson === this.diffCacheOutputJson) {
      return this.diffCacheView;
    }
    const view: ToolDiffView | null = toolDiffForCard(toolName, inputJson, outputJson,
      TOOL_DIFF_MAX_ROWS_PER_SIDE, TOOL_DIFF_MAX_ROW_CHARS);
    this.diffCacheTool = toolName;
    this.diffCacheInputJson = inputJson;
    this.diffCacheOutputJson = outputJson;
    this.diffCacheView = view;
    return view;
  }

  // 进度徽章文案（§3.3）：全答完改「已回答」（投稿前态——用户填齐但未点提交）
  private askProgressText(): string {
    const total: number = this.askQuestions().length;
    return this.askAnswered >= total ? '已回答' : '已答 ' + this.askAnswered + ' / ' + total;
  }

  // 展开可点判据（确认卡两态照通用头判据保留可展开；提问卡两态都不提供展开——其卡体已含
  // 全部信息，防死交互。通用路径下本判据 == toolHasDetail，行为零变化）
  private headExpandable(): boolean {
    return this.toolHasDetail() && !this.askCard();
  }

  // 展开切换（有详情才响应——防死交互）。★ 折叠动画先例：切换包进 UIContext.animateTo
  //（宪法禁全局 animateTo；官方 FAQ faqs-arkui-769 折叠示例做法 + 300ms 时长），高度与箭头
  // 旋转随之插值；本卡是条件渲染式折叠，内容不随高度形变（官方 FAQ faqs-arkui-1400：布局类
  // 改变宽高的动画，内容直接到终点状态）。仅关→开时上行 onDetailOpened（段意愿提升——用户
  // 正在阅读）；关详情只收自身、不发上行（段级收回只走「收起」键——决明修正）
  // ★ 2026-11-05 收起方向直写（与段级/思考详情同笔同判据）：条件渲染内容在写入同帧卸载，
  // 高度插值只会把卡片留成空盒并把下方正文顶住 300ms——收起直写，内容与高度同帧落
  private toggleExpanded(): void {
    if (!this.headExpandable()) {
      return;
    }
    const next: boolean = !this.detailExpanded();
    if (!next) {
      this.msg.detailExpanded = false;
      return;
    }
    this.getUIContext().animateTo({ duration: TOOL_FOLD_ANIM_MS, curve: Curve.EaseInOut },
      (): void => {
        this.msg.detailExpanded = true;
      });
    this.onDetailOpened();
  }

  aboutToAppear(): void {
    // 详情意愿首次初始化（唯一写点；已明确 true/false 不被组件重建覆盖——msg 由数据源持有）
    if (this.msg.detailExpanded === undefined) {
      this.msg.detailExpanded = false;
    }
    // 首帧即等待（ask_user 常态）：@Watch 不补发首帧，必须在这里认领一次
    this.onMsgChanged();
  }

  private onMsgChanged(): void {
    if (isStepAwaitingUser(this.msg) && this.msg.dockOwned !== true) {
      this.onAwaitingStep(this.msg);
    }
    // 托管期流内只剩头行、没有子卡实例上报 onProgress：进度徽章的 n 改由 msg.askDraft
    // 现算（判据单源 = askAnsweredOfDraft，与托管位细条同源，禁两处各写）
    if (this.msg.dockOwned === true && this.askAwaiting()) {
      this.askAnswered = askAnsweredOfDraft(this.msg.askDraft, this.askQuestions().length);
    }
  }

  // ── 输入 / 输出分区 ──
  // 原串判据：输入 = toolInputJson、输出 = toolOutputJson（非空即用原串，不再重复截断预览；
  // 空时才用 fallback 串 toolInputText / toolDisplayText——完整可用值）；分区渲染判据 =
  // 原串或 fallback 非空；复制目标 = 原串优先、缺时用 fallback 串
  private inputRaw(): string {
    return this.msg.toolInputJson ?? '';
  }

  private inputFallback(): string {
    return this.msg.toolInputText ?? '';
  }

  private outputRaw(): string {
    return this.msg.toolOutputJson ?? '';
  }

  private outputFallback(): string {
    return this.msg.toolDisplayText ?? '';
  }

  private errorVisible(): boolean {
    const errorText: string = this.msg.text;
    return errorText !== '' && errorText !== this.inputRaw() && errorText !== this.outputRaw() &&
      errorText !== this.inputFallback() && errorText !== this.outputFallback();
  }

  // ── 标题行右槽（ChatStepTitleRow 的 slot：状态位 / 徽章 / 行内键；行首语义符号在过程壳图标列）──

  // 确认卡右槽：档位徽章 + 状态位（12fp 次要色，不配转圈——转圈语义留给真在跑的执行）；
  // ai 路径前置分流——文案区分「审批模型已允许（执行中）」与「已拒绝」，不与人工三态混用
  @Builder
  ConfirmHeadSlot() {
    Row({ space: 6 }) {
      this.ConfirmLevelBadge()
      Text(this.confirmDone() ? (this.confirmAiJudged() ? this.confirmAiStatusText() :
        (this.confirmSessionApproved() ? '本会话内已允许' :
        (this.confirmApproved() ? '已允许一次' : '已拒绝'))) : '等你的确认')
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
    }
  }

  // 提问卡右槽：进度徽章（仅等待态；题数解析失败 0 不挂徽章）+ 状态位；★ 域①中止态显
  //「提问已中止」中性文案（不再等待也不算已回答）
  @Builder
  AskHeadSlot() {
    Row({ space: 6 }) {
      if (this.askAwaiting() && this.askQuestions().length > 0) {
        this.AskProgressBadge()
      }
      Text(this.askCancelled() ? '提问已中止' :
        (this.askAwaiting() ? '等你回答' : '已回答'))
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
    }
  }

  // 通用工具卡右槽：状态位（执行中/出错/已中止/完成）+ 模板重发双键（行内图标键形制——
  // 无底 TEXTUAL + font_secondary；Button 拦截点击不触发整卡展开）。原样重发恒出，改参数键
  // 仅参数模板出。★ 域① cancelled 分支：中止是状态不是失败——中性色 stop 符号「已中止」
  //（非警告色三角「出错」）
  @Builder
  GenericHeadSlot() {
    Row({ space: 8 }) {
      if (this.msg.toolState === 'running' && !this.askCard() && !this.confirmAwaiting()) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(cardDescColor())
        Text('执行中…')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      } else if (this.msg.toolState === 'cancelled') {
        SymbolGlyph($r('sys.symbol.stop_circle'))
          .fontSize(14)
          .fontColor([cardDescColor()])
        Text('已中止')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      } else if (this.msg.toolState === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(14)
          .fontColor([$r('sys.color.ohos_id_color_warning')])
        Text('出错')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor($r('sys.color.ohos_id_color_warning'))
      } else {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([cardDescColor()])
        Text('完成')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
      }
      if (this.resendEntry() !== null) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.onResend(this.msg.id, this.msg.toolName, this.msg.toolInputJson ?? '{}');
        })
      }
      if (this.hasTemplateParams()) {
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.onEditResend(this.msg.id, this.msg.toolName, this.msg.toolInputJson ?? '{}');
        })
      }
    }
  }

  // 标题行三选一：确认卡 / 提问卡命中即共享标题行 + 专属右槽，未命中走通用（可展开性与箭头由共享行统一给出）
  @Builder
  ConfirmHead() {
    ChatStepTitleRow({
      icon: toolStepIcon(this.msg),
      title: this.confirmTitle(),
      expandable: this.headExpandable(),
      expanded: this.detailExpanded(),
      onToggle: (): void => {
        this.toggleExpanded();
      },
      slot: (): void => {
        this.ConfirmHeadSlot();
      }
    })
  }

  @Builder
  AskHead() {
    ChatStepTitleRow({
      icon: toolStepIcon(this.msg),
      title: this.askTitle(),
      expandable: this.headExpandable(),
      expanded: this.detailExpanded(),
      onToggle: (): void => {
        this.toggleExpanded();
      },
      slot: (): void => {
        this.AskHeadSlot();
      }
    })
  }

  @Builder
  GenericHead() {
    ChatStepTitleRow({
      icon: toolStepIcon(this.msg),
      title: this.toolDisplayName(),
      expandable: this.headExpandable(),
      expanded: this.detailExpanded(),
      onToggle: (): void => {
        this.toggleExpanded();
      },
      slot: (): void => {
        this.GenericHeadSlot();
      }
    })
  }

  // 档位徽章（★ 自绘·已拍板；11fp Medium + 内距 10/5 + 圆角 6——2026-10-25 反馈二笔由 999
  // 胶囊改圆角矩形，与全站状态徽标同形。写操作档 = badgeBg 灰底 + 次要色字；不可逆档 =
  // 危险红实底 + 恒白字）
  @Builder
  ConfirmLevelBadge() {
    if (this.confirmLevelIrreversible()) {
      Text('不可撤销')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(6)
        .backgroundColor($r('app.color.dialog_confirm_red'))
    } else {
      Text('写操作')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(6)
        .backgroundColor(badgeBg(this.appColorMode))
    }
  }

  // 进度徽章（提问卡等待态；几何同档位徽章，取色零新色——底 badgeBg、字次要色）
  @Builder
  AskProgressBadge() {
    Text(this.askProgressText())
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.resolveBodyFamily())
      .fontColor(cardDescColor())
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  // 确认回执行体首行：答题后说明串仍在（结果内容仍需可查——帮助条目已承诺可在展开区核对）。
  // ai 路径首行 = 审批理由（人工路径 = 原主因句 toolConfirmText——ai 路径该字段恒空，两源不混）
  @Builder
  ConfirmReceiptRow() {
    Text(this.confirmAiJudged() ? this.confirmAiReceiptText() : (this.msg.toolConfirmText ?? ''))
      .fontSize(14)
      .fontFamily(this.resolveBodyFamily())
      .fontColor(cardTitleColor())
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  // 提问卡回执行卡体：逐题 = 题干 14fp 主色 + 答案行 13fp（实走强调色、跳过与空答案显
  //「已跳过」次要色）；★ 笔 B：上屏的是组合答案（点选与补写同屏可见，不另渲染 chips）；
  // 不渲染摘要行与展开区——信息 = 结果 JSON 本身，已由回执完整呈现、零丢失
  @Builder
  AskReceiptBody() {
    Column({ space: 10 }) {
      ForEach(this.askAnswers(), (row: AskAnswerRow): void => {
        Column({ space: 4 }) {
          Text(row.question)
            .fontSize(14)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .width('100%')
          Text(row.skipped || row.answer.trim() === '' ? '已跳过' : row.answer)
            .fontSize(13)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(row.skipped || row.answer.trim() === '' ? cardDescColor() :
              $r('sys.color.ohos_id_color_emphasize'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (row: AskAnswerRow): string => row.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 8 })
  }

  // 摘要行（12fp 次要色单行——内容为预组合串，无刷新需求）
  @Builder
  ToolSummaryRow(content: string) {
    Row() {
      Text(content)
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  // 进度/产物状态 → 错误 → 图片/文件/来源专用块 → 输入输出切换面板；一个 Scroll 沿用
  // TOOL_DETAIL_MAX_HEIGHT（超长内容区内滚动，不撑爆消息流）
  @Builder
  DetailBody() {
    Scroll() {
      Column({ space: 6 }) {
        // ① 进度 / 产物状态（存在才渲染；12fp 与状态文字同档）
        if (this.msg.toolProgressPercent !== undefined) {
          this.ToolSummaryRow('进度 ' + Math.round(this.msg.toolProgressPercent) + '%')
        } else if (this.msg.toolProgressText !== undefined) {
          this.ToolSummaryRow(this.msg.toolProgressText)
        }
        if (this.msg.toolTodoId !== undefined) {
          this.ToolSummaryRow('todo:' + this.msg.toolTodoId)
        }
        if (this.msg.toolTaskId !== undefined) {
          this.ToolSummaryRow('任务 ' + this.msg.toolTaskId)
        }
        if (this.msg.toolAgentSummary !== undefined) {
          this.ToolSummaryRow('子代理 ' + this.msg.toolAgentSummary)
        }
        // ★ 笔 7 下载产物摘要行（产物持久，删除会话不影响）
        if (this.savedFile() !== null) {
          this.ToolSummaryRow('已存入工作区 ' + (this.savedFile() as SavedFileRow).name)
        }
        // ② 错误（msg.text；与输入/输出全文逐字相同只显示一次——见 errorVisible）
        if (this.errorVisible()) {
          Text(this.msg.text)
            .fontSize(12)
            .fontFamily(this.resolveBodyFamily())
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width('100%')
        }
        // ③ 图片 / 文件 / 来源专用块（既有展示链与点击链原样保留，不被原始内容取代）
        // ★ 笔D「图片」小节：base64 data URI 直渲（SDK image.d.ts 实核支持；缩略图纯展示
        // 不挂点击，看大图去工作区）；几何沿用产物行异族档（56 + 圆角 8 + Cover，138 组钉
        // 自证异族形态），多张 Flex wrap 换行。
        // ★ 键含 data.length：同编码器 JPEG 头部约前 24 字节恒同，仅前缀键单卡多图必撞
        //（官方重复键行为未定义）；mediaParts 无 id 字段，content 派生键是唯一形态
        if (this.toolMediaImages().length > 0) {
          Text('图片')
            .fontSize(11)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.toolMediaImages(), (part: AiImagePart): void => {
              Image('data:' + part.mimeType + ';base64,' + part.data)
                .width(56)
                .height(56)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            }, (part: AiImagePart): string => part.mimeType + '#' + part.data.length +
              '#' + part.data.substring(0, 32))
          }
          .width('100%')
        }
        // ★ 笔 7 下载产物区：缩略图/图标行 + 名称 + 大小，点击系统预览读工作区文件
        //（11fp 标题档照「来源」形制）
        if (this.savedFile() !== null) {
          Text('文件')
            .fontSize(11)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .width('100%')
          // 几何刻意错开头行族（138 组钉：头部三行属 48/space 8/6 形态——产物行取 56 缩略图 + space 4 自证异族）
          Row({ space: 4 }) {
            if ((this.savedFile() as SavedFileRow).kind === 'image') {
              Image(this.savedFilePath())
                .width(56)
                .height(56)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            } else {
              SymbolGlyph((this.savedFile() as SavedFileRow).kind === 'doc' ?
                $r('sys.symbol.doc_text') : $r('sys.symbol.doc_plaintext'))
                .fontSize(20)
                .fontColor([cardDescColor()])
            }
            Column({ space: 2 }) {
              Text((this.savedFile() as SavedFileRow).name)
                .fontSize(13)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(formatWorkspaceSize((this.savedFile() as SavedFileRow).size) +
                ' · 已存入文件工作区')
                .fontSize(11)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardDescColor())
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .onClick((): void => {
            this.openSavedFile(this.savedFile() as SavedFileRow);
          })
        }
        // 引文卡：搜索类结果编号引文列表——编号圆点 + 标题 + 摘要 + URL，点行开浏览器
        if (this.toolSearchRefs().length > 0) {
          Text('来源')
            .fontSize(11)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .width('100%')
          ForEach(this.toolSearchRefs(), (ref: SearchResultItemPayload): void => {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(String(ref.index))
                  .fontSize(11)
                  .fontFamily(this.resolveBodyFamily())
                  .fontColor(cardDescColor())
                  .constraintSize({ minWidth: 16 })
                Text(ref.title !== '' ? ref.title : ref.url)
                  .fontSize(13)
                  .fontFamily(this.resolveBodyFamily())
                  .fontColor(cardTitleColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              if (ref.snippet !== '') {
                Text(ref.snippet)
                  .fontSize(11)
                  .fontFamily(this.resolveBodyFamily())
                  .fontColor(cardDescColor())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              Text(ref.url)
                .fontSize(10)
                .fontFamily(this.resolveBodyFamily())
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .onClick((): void => {
              if (ref.url !== '') {
                this.openRefUrl(ref.url);
              }
            })
          }, (ref: SearchResultItemPayload): string => ref.url + '#' + ref.index)
        }
        // 变更 diff：红绿行级展开（同位「存在才渲染 + 11fp 小节标题」形态）；路由与解析
        // 单源在 ChatToolDiffBlock.toolDiffForCard；全文原文仍走原始面板
        if (this.toolDiff() !== null) {
          Text('变更')
            .fontSize(11)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardTitleColor())
            .width('100%')
          ChatToolDiffBlock({ diff: this.toolDiff() as ToolDiffView })
        }
        ChatToolRawPanel({ msg: this.msg })
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 8, bottom: 8 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .constraintSize({ maxHeight: TOOL_DETAIL_MAX_HEIGHT })
  }

  build() {
    // 步骤内容列（壳给出 gutter 与统一内距）：标题行 +（有卡体时）分割线 + 常显交互/回执区
    // + 折叠详情区。渲染位 = ChatProcessSegment.ChatProcessStep 的 tool 分支。
    // ★ 状态收敛：**普通工具收起 = 标题行 + 一行结果摘要**（图标 + 工具名 + 状态 + 箭头，
    // 摘要行只对 done/error 终态且摘要非空时出现；不显进度详情、todo/任务 id、子代理摘要、
    // 下载摘要、分割线或空卡体留白；详细信息换到展开后显示，字段不删除）；确认/提问专用分支
    // 常显不随之收起——等待作答/审批的步骤必须常显，任何折叠规则都不能隐藏必需交互。
    // ★ 2026-11-12 偏好开关批：「工具卡显示结果摘要」偏好整键退役、收起态**恒显**摘要
    //（原默认关 = 纯标题的口径作废），判据只剩卡片形态与终态
    Column() {
      if (this.confirmAwaiting() || this.confirmDone()) {
        this.ConfirmHead()
      } else if (this.askAwaiting() || this.askDone() || this.askCancelled()) {
        this.AskHead()
      } else {
        this.GenericHead()
      }
      // 收起态摘要行：整块在 ChatToolSummaryRow 独立件，本件仅终态预判减挂载（运行中/中止/
      // 确认/提问卡不实例化；件内自判展开态与摘要空串——摘要恒显示，无开关闸）
      if (this.msg.toolState === 'done' || this.msg.toolState === 'error') {
        ChatToolSummaryRow({ msg: this.msg })
      }
      if (this.bodyVisible()) {
        Column() {
        // 标题行与卡体分割线（1vp cardBorderColor；与标题文字同左沿）
        Divider()
          .strokeWidth(1)
          .color(cardBorderColor(this.appColorMode))

        // ── 常显交互 / 回执区（专用分支；绝不整体包进折叠开关）──
        // 确认回执行首行：作答后说明串仍在（写点不清空）；ai 路径理由为空时不渲染首行
        //（空 Text 占位行不出现），aiDenied 恒渲染
        if (this.confirmDone() &&
          (!this.confirmAiJudged() || this.confirmAiReceiptText() !== '')) {
          this.ConfirmReceiptRow()
        }
        // ask_user 交互区（running 态专属——done 后走回执行区）：问题渲染 + 文本作答 +
        // 整卡提交，答案经 onAskSubmit 上行续跑模型
        if (this.askAwaiting()) {
          // 已被底部托管位接管 = 流内只留头行，不再挂第二份可作答卡体
          if (this.msg.dockOwned !== true) {
          ChatAskUserCard({
            msg: this.msg,
            onSubmit: (callId: string, answerJson: string): void => {
              this.onAskSubmit(callId, answerJson);
            },
            // 作答进度上行：输入与清空都报（answered = 有答案题数）
            onProgress: (answered: number, total: number): void => {
              this.askAnswered = answered;
            }
          })
          }
        } else if (this.askDone()) {
          // 提问卡回执行（笔 A §5.3）：逐题题干 ＋ 答案行
          this.AskReceiptBody()
        } else if (this.confirmAwaiting()) {
          // 高危确认区（running 且带确认说明串才渲染；ask 分支在前位先行拦截；读向动作与
          // 已作答卡不渲染，见 ChatBrowseConfirmCard 头注释）：允许一次/拒绝双键，
          // 作答经 onBrowseConfirm 上行续跑工具轮。install 动作走专属卡（逐条清单 + 固定
          // registry + 无第三键，判据单源 isNodeInstallCard）
          if (this.msg.dockOwned !== true) {
          if (isNodeInstallCard(this.msg)) {
            ChatToolInstallCard({
              msg: this.msg,
              onSubmit: (callId: string, approved: boolean): void => {
                this.onBrowseConfirm(callId, approved);
              }
            })
          } else {
            ChatBrowseConfirmCard({
              msg: this.msg,
              onSubmit: (callId: string, approved: boolean): void => {
                this.onBrowseConfirm(callId, approved);
              }
            })
          }
          }
        }

        // ── 折叠详情区（普通卡与确认卡完成态；专用交互态不渲染）──
        if (this.detailVisible()) {
          this.DetailBody()
        }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // 正文/交互列左沿 = 行内容补距 + gutter + 文本左距（与标题行同左沿；蒙层收窄笔随形，
        // 见 common/Theme 注释）
        .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
