import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ColorMetrics, KeyboardAvoidMode, window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_FIXED, IMMERSIVE_LEVEL_KEY } from '../common/ImmersiveLevel';
import { PREF_DATA_APPROVE_MODE_KEY, CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY, NET_PROXY_MODE_SYSTEM, NET_PROXY_TYPE_HTTP, NET_READ_TIMEOUT_MINUTES_DEFAULT, PASTE_THRESHOLD_DEFAULT, PREF_AUTO_RETRY_KEY, PREF_BG_REPLY_NOTIFY_KEY, PREF_BG_SESSION_ONLY_KEY, PREF_BROWSE_APPROVE_MODE_KEY, PREF_BROWSE_AUTO_APPROVE_KEY, PREF_CODE_WORKBENCH_MODE_KEY, PREF_CODE_WORKBENCH_ENGINE_KEY, PREF_CTX_FACTOR_KEY, CODE_WORKBENCH_MODE_STANDARD, CODE_WORKBENCH_ENGINE_AUTO, HTTP_TIMEOUT_CEILING_MS_DEFAULT, HTTP_HOST_INTERVAL_MS_DEFAULT, PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY, PREF_BODY_CARD_COLLAPSED_KEY, PREF_HEADERS_CARD_COLLAPSED_KEY, PREF_HTTP_APPROVE_MODE_KEY, PREF_HTTP_HOST_INTERVAL_MS_KEY, PREF_HTTP_TIMEOUT_CEILING_MS_KEY, PREF_HTTP_WRITE_AUTO_APPROVE_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_INPUT_EXPANDED_KEY, PREF_TEXT_IMAGE_FETCH_KEY, PREF_KEYBOARD_SEND_KEY, PREF_LAUNCH_NEW_CHAT_KEY, PREF_CODE_AUTO_COLLAPSE_KEY,
PREF_CODE_LINE_NUMBERS_KEY, PREF_HTML_BLOCK_RENDER_KEY, PREF_CHAT_LOADING_OVERLAY_KEY, PREF_LONG_MSG_COLLAPSE_KEY, PREF_ASSISTANT_BUBBLE_KEY, PREF_SVG_PREVIEW_KEY, PREF_MERMAID_INLINE_KEY, PREF_LOADED_KEY, PREF_NET_PROXY_ADDR_KEY, PREF_NET_PROXY_BYPASS_KEY, PREF_NET_PROXY_MODE_KEY, PREF_NET_PROXY_TYPE_KEY, PREF_NET_PROXY_USER_KEY, PREF_NET_READ_TIMEOUT_MIN_KEY, PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY, PREF_PHOTO_SAVE_GALLERY_KEY, PREF_PHOTO_EDIT_KEY, PREF_PRICE_CARD_COLLAPSED_KEY, PREF_DS_DOC_SERVER_KEY, PREF_DS_OFFICIAL_WEB_KEY, PREF_DS_TITLE_MODE_KEY, PREF_DS_SAFETY_CHECK_KEY, PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY, PREF_SEARCH_ENGINE_KEY, PREF_SEARCH_FETCH_ENGINE_KEY, PREF_SEARCH_RESULT_COUNT_KEY, PREF_SEARCH_TIMEOUT_SEC_KEY, PREF_HOLDING_FOLLOW_KEY, PREF_NEW_SESSION_ENTRY_KEY, NEW_SESSION_ENTRY_TAB_BAR, PREF_SESSION_CARD_GRID_KEY, PREF_WORKSPACE_SORT_KEY, PREF_STREAM_FOLLOW_KEY, PREF_PREVIEW_JS_KEY, PREF_TAB_SWITCH_ANIM_KEY, PREF_THINK_EXPAND_KEY, PREF_TIME_REMINDER_KEY, PREF_TIME_REMINDER_MINUTES_KEY, PREF_TOOL_STEP_LIMIT_KEY, PREF_USER_AGENT_KEY, TIME_REMINDER_DEFAULT, PREF_DEFAULT_PERMISSION_MODE_KEY, PREF_CHAT_PERMISSION_MODES_KEY, PREF_HOME_LAYOUT_KEY, HOME_LAYOUT_TABS, PREF_LAST_CONV_ID_KEY, PREF_THINKING_SLIDER_KEY } from '../common/AppPreferences';
import { WS_SORT_CUSTOM } from '../common/WorkspaceUtil';
import { CODE_HTTP_HOST_MODE_ALLOWLIST, PREF_CODE_HTTP_HOST_MODE_KEY,
  PREF_CODE_HTTP_HOSTS_KEY, PREF_CODE_HTTP_WRITE_KEY,
  PREF_HTTP_CREDENTIALS_CFG_KEY,
  PREF_HTTP_ALLOWLIST_CARD_COLLAPSED_KEY,
  PREF_HTTP_ALLOWED_HOSTS_KEY, PREF_HTTP_TASKS_KEY } from '../common/AppPreferencesHttp';
import { PREF_AUTO_RETRY_CFG_KEY } from '../common/AppPreferencesRetry';
// 旧三域审批档 → 默认权限档一次性折算（2026-11-09 三档归一笔记）：只在默认档为空时执行，
// 折算后旧键退为只读墓碑（persistProp 与备份表仍保留，代码面无写点）
import { migrateLegacyApproveModes } from '../common/chat/PermissionMode';
// Web 服务域键族与网络基座（★ 2026-10-22 Web 服务与 WebUI 双端直播施工总案 U2：偏好键四件
// 落 AppPreferencesWeb 叶子〔主件 AppPreferences 含引用批在途改动禁动，照 AppPreferencesHttp
// 域拆分先例〕；manager 为惰性单例——模块级 export const 形制，不持 UI 组件引用）
import { PREF_WEB_SERVICE_ENABLE_KEY, PREF_WEB_SERVICE_PORT_KEY, PREF_WEB_SERVICE_PASSCODE_KEY,
  PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY, WEB_SERVICE_PORT_DEFAULT,
  isWebServiceEnabled } from '../common/AppPreferencesWeb';
import { webServiceManager } from '../common/web/WebServiceManager';
import { attachWebStaticContext } from '../common/web/TcpHttpStaticCarrier';
import { ALL_SEARCH_ENGINE_IDS } from '../common/search/SearchEngineRegistry';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_BODY_NAME_KEY,
  PREF_FONT_BODY_PATH_KEY, PREF_FONT_CODE_KEY, PREF_FONT_CODE_NAME_KEY,
  PREF_FONT_CODE_PATH_KEY, PREF_FONT_LIB_KEY, PREF_FONT_SESSION_ONLY_KEY,
  migrateLegacyFontSelectionNow } from '../common/ChatFont';
import { applyAppFontOnLaunch, ensureSelectedFontsRegistered } from '../common/ChatFontLoader';
import { SEARCH_RESULT_COUNT_DEFAULT, SEARCH_TIMEOUT_SECONDS_DEFAULT } from '../common/search/SearchLimits';
import { TOOL_STEP_LIMIT_DEFAULT } from '../common/providers/ToolLimits';
import { EDIT_BLUR_PCT_KEY, EDIT_CROP_STATE_KEY, EDIT_MASK_PCT_KEY } from '../common/ImageEditUtil';
import { warmBgCacheForColdStart } from '../common/BgCache';
// 一级页签列表首查预热（2026-10-24 首切闪修复笔）：助手/对话两页签读取链与冷启动快照单源
import { homeListWarmup } from '../common/store/HomeListWarmup';
import { PREF_REQ_LOG_KEY } from '../common/ReqLog';
import { RECENT_USE_KEY, SEARCH_HISTORY_KEY } from '../common/SettingSearch';
import { SESSION_RECENT_CONV_KEY, SESSION_SEARCH_HISTORY_KEY } from '../common/SessionSearch';
import { ensureCrashWatcher, pruneLogFiles, teardownCrashWatcher } from '../components/LogPageDataSource';
import { sweepAttachDir } from '../common/AttachmentUtil';
import { sweepExportTemp } from '../common/store/ExportImport';
import { initChatDb, sharedRdbStore, whenReady } from '../common/store/ChatDb';
// 模型选择启动对账（2026-10-27 停用即解绑笔）：8 功能槽 + 助手绑定 + 会话级覆盖的历史
// 悬空/停用绑定一律清成未选择（幂等，见该件头注释）
import { reconcileModelBindings } from '../common/store/ModelBindingReconcile';
// 后台回复保活与通知域（★ 2026-10-16 解耦笔5 域④ U10）：onBackground/onForeground 两钩子
// 分发（环节 B 发通知 / 拍板 3 回前台撤销）——本件只转发，账本全在彼件
import { chatBgReply } from '../common/chat/ChatBgReply';
// 重启续答·列表标记重建（★ 2026-10-16 重启续答冻结修复笔）：等待会话 id 读口
//（ChatGraphCommandSource）与运行时恢复集（ChatSessionRuntime）在启动链组合——两件互不
// import（防模块环，坑50），合成点在本件（先例 = buildAttachmentGraphCleanup 同因）
import { graphAwaitingConversationIds } from '../common/chat/ChatGraphCommandSource';
import { chatSessionRuntime } from '../common/chat/ChatSessionRuntime';
import { syncTemplateTools } from '../common/providers/HttpTemplate';
import { syncMcpTools } from '../common/providers/McpTools';
import { initAttachmentStore, reconcileAttachments,
  AttachmentGraphCleanup } from '../common/store/AttachmentDb';
import { buildAttachmentGraphCleanup } from '../common/store/GraphTransfer';
import { initLocationAccess } from '../common/providers/ToolLocation';
import { initCalendarAccess } from '../common/providers/ToolCalendar';
import { initWorkspaceStore, reconcileWorkspace } from '../common/store/WorkspaceDb';
import { initWorkspaceTmpStore } from '../common/store/WorkspaceDbTmp';
// Python 运行时域 ctx 捕获（门 4）：rawfile 三件 zip 落位需要 context
import { initPyRuntimeStore, removeTreeAsync, sweepLegacyPyRuntimeDirs } from '../common/pyexec/PyRuntime';
// Node 运行时域 ctx 捕获（门 2）：exec_node 执行器无组件环境，落位 rawfile 四件与 endpoint
// 读取都要 filesDir——onCreate 注入先于任何 Node 调用；运行区懒建（首用落位）。NODE_HOME_DIR_NAME
// 供冷启旧版本清扫跳过当前版本目录
import { initNodeRuntimeStore, NODE_HOME_DIR_NAME } from '../common/nodeexec/NodeRuntime';
// ★ 2026-10-07 代码工作台笔H：模拟 Shell 资产域 ctx 捕获（rawfile/shell 三件读取）
import { attachShellAssetContext } from '../common/codeexec/ShellScript';
import { ensureProvidersMigrated } from '../common/store/ProviderDb';
import { migrateProviderKeyPools } from '../common/store/ProviderKeyDb';
import { ensurePromptGlobal } from '../common/store/PromptTemplateDb';
import { ensureBuiltinSkills, notifySkillSeedKeyRegistered } from '../common/store/SkillDb';
import { SKILL_BUILTIN_SEEDED_KEY, SKILL_PENDING_JOIN_KEY } from '../common/SkillBuiltinDefs';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID,
  ensureDefaultAssistant } from '../common/store/AssistantDb';
import { DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY,
  APPROVAL_ENABLED_KEY, APPROVAL_MODEL_KEY, APPROVAL_PROVIDER_KEY, FUNCTIONAL_THINKING_KEY,
  OCR_ENABLED_KEY, OCR_ENGINE_KEY, OCR_MODEL_KEY, OCR_PREFER_SYSTEM_KEY, OCR_PROVIDER_KEY,
  SUGGEST_ENABLED_KEY, SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY,
  TITLE_ENABLED_KEY, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY } from '../common/store/ProviderDb';
import { ocrAttachContext } from '../common/OcrEngine';
import { OCR_PROMPT_KEY } from '../common/providers/OcrVisionApi';
import { TITLE_PROMPT_KEY } from '../common/TitleGen';
import { APPROVAL_PROMPT_KEY } from '../common/providers/ApprovalGate';
import { SUGGEST_PROMPT_KEY } from '../common/SuggestGen';
import { MEMORY_AUTO_KEY, MEMORY_ENABLED_KEY, MEMORY_MODEL_KEY, MEMORY_PROMPT_KEY,
  MEMORY_PROVIDER_KEY, MEMORY_READ_MODE_DEFAULT, MEMORY_READ_MODE_KEY } from '../common/MemoryGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROMPT_KEY,
  MEMORY_OPT_PROVIDER_KEY } from '../common/MemoryOpt';
import { MEMORY_IMPORT_PROMPT_KEY } from '../common/MemoryImport';
import { COMPRESS_MODEL_KEY, COMPRESS_PROMPT_KEY, COMPRESS_PROVIDER_KEY } from '../common/CompressGen';
import {
  APP_FOREGROUND_KEY, notifyProactiveKeysRegistered, onAppForeground,
  PROACTIVE_SENT_AT_KEY
} from '../common/ProactiveGen';
import { PROACTIVE_UNREAD_CONV_KEY, PENDING_SHARES_KEY, PENDING_SHARES_TICK_KEY,
  PENDING_SHARE_INCOMING_KEY, PendingSharedItem } from '../common/AppBroadcastKeys';
// ★ 2026-09-27 架构收口笔1：六枚持久键改自零 import 叶子引（原自 ProactiveGen——与设置白名单
// ToolPref 反向共享，落叶子后消环；键名与缺省值单一来源见该件头注释）
import {
  PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY, PROACTIVE_ENABLED_KEY,
  PROACTIVE_INTERVAL_DEFAULT, PROACTIVE_INTERVAL_HOURS_KEY,
  PROACTIVE_QUIET_MAX_DEFAULT, PROACTIVE_QUIET_MAX_KEY
} from '../common/ProactiveConfig';
import { notifyPresetSeedKeyRegistered, PROVIDER_PRESETS_SEEDED_KEY, seedProviderPresets } from '../common/store/ProviderPresetSeed';
import { retireOverseasBuiltinProviders } from '../common/store/ProviderPresetRetire';
import { convergeDuplicateBuiltinProviders } from '../common/store/ProviderBuiltinDedup';
import { loadProxyPassword } from '../common/store/KeyStore';
import { setCachedProxyPassword } from '../common/providers/RequestIdentity';
// 首启隐私政策同意（2026-10-23 合规整改笔）：键与存量迁移判定单源 = 零 import 叶子
import { migratePrivacyConsentForExistingUsers, PREF_PRIVACY_AGREED_KEY } from '../common/PrivacyConsent';

const DOMAIN = 0x0000;

// Node 旧版本运行区目录名判据（与 Node 侧 runtime-setup.sweepOldVersions 同源：只匹配
// node-X.Y.Z-gN；门 1 遗留 node-data 等不匹配，禁误删）
const NODE_LEGACY_DIR_PATTERN: RegExp = /^node-\d+\.\d+\.\d+-g\d+$/;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 系统分享/打开方式拉起探针（同步先行）：getSharedData 异步返回晚于导航壳冷启动判定
    //——此处同步探 want.action 置在途标记，HomeNavigation 的「启动进新对话」判定据此让位
    // 防双推（让位语义见 tryEnterLaunchConversation 注释）
    const shareAction: string = want.action ?? '';
    AppStorage.setOrCreate<boolean>(PENDING_SHARE_INCOMING_KEY,
      shareAction === 'ohos.want.action.sendData' || shareAction === 'ohos.want.action.viewData');
    // 分享/打开方式双入口解析（热启动同链路走 onNewWant）
    this.parseIncomingShare(want);
    // 崩溃事件订阅（与 onDestroy 注销成对——坑33 铁律）：进程级注册，崩溃事件在进程全程被
    // 捕获（含日志页未打开时段）；日志页刷新时经 getCrashHolder 共享句柄 takeNext 拉取
    //（单例见 LogPageDataSource.ets）。hiAppEvent 全局 API 不依赖 UI 上下文
    ensureCrashWatcher();
    // 代理密码预载：Asset 异步读 → RequestIdentity 内存缓存回填——applyEffectiveProxy 是
    // 同步单点收口，密码只能走缓存，预载在 onCreate 最早点发起；失败按未配置处理打日志
    // 不阻断启动（P0-1 留痕），下次启动重试
    loadProxyPassword().then((pw: string): void => {
      setCachedProxyPassword(pw);
    }).catch((e: Object): void => {
      hilog.error(DOMAIN, 'testTag', '代理密码预载失败（下次启动重试）：%{public}s',
        (e as Error).message);
    });
    // 日志沙箱落盘常开（决明拍板）：进程级开启 PRIVATE_SANDBOX_WITH_CONSOLE（本地 d.ts
    // 实锤）——全生命周期日志（含 W/E/F 报错与 INFO 上下文）落盘到应用私有沙箱，出问题后
    // 日志页刷新即可读到事发日志（此前页面级开关导致事发日志不落盘）；WITH_CONSOLE 保留
    // 控制台输出。启动即自检修剪一次（pruneLogFiles：超 2MB 从最旧文件删起，防堆积——进
    // 日志页还会再自检一次）；失败仅打日志不阻断启动（P0-1）
    try {
      hilog.setOutputType(hilog.OutputType.PRIVATE_SANDBOX_WITH_CONSOLE);
      pruneLogFiles();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '日志落盘初始化失败：%{public}s', (err as Error).message);
    }
    // 附件缓存清扫（2026-08-31 附件上传）：crash/页面异常退出残留副本的兜底清理——
    // cacheDir/attachments 整目录扫删；启动时一次，残留量有界 ≤ 附件上限，非轮询
    sweepAttachDir(this.context);
    // 导入导出临时产物清扫：export/backup/download 残留兜底——ExportImport.ets 注释口径
    // 「EntryAbility onCreate 调一次」（自 DataSyncPage.aboutToAppear 迁至此）；启动即清
    sweepExportTemp(this.context);
    // 附件元数据域 ctx 捕获：级联删文件/收敛拼 filesDir 前缀用——先于任何附件文件操作调用
    initAttachmentStore(this.context);
    // 位置工具域 ctx 捕获：执行器无组件环境，运行期授权弹窗（requestPermissionsFromUser）
    // 需要 UIAbilityContext——onCreate 注入先于任何工具调用
    initLocationAccess(this.context);
    // 日程工具域 ctx 捕获：同上——日历工具执行器首步运行期授权（READ/WRITE_CALENDAR 双权
    // 一次申请）需要 UIAbilityContext，onCreate 注入
    initCalendarAccess(this.context);
    // 工作区存储域 ctx 捕获：workspace_files 文件 IO（写/删/清空目录）拼 filesDir 前缀用
    //——先于任何工作区工具调用；工作区不参与启动收敛（无孤儿扫描，与附件域的分叉）
    initWorkspaceStore(this.context);
    // 临时产物区 ctx 捕获：workspace-tmp 目录派生与级联删除拼 filesDir 前缀用——照上行
    // 同形；目录懒建（首次写入方建，此处只捕获）
    initWorkspaceTmpStore(this.context);
    // Python 运行时域 ctx 捕获（门 4）：exec_python 执行器与设置管理页无组件环境，落位
    // rawfile 三件 zip 需要 context——onCreate 注入先于任何 Python 调用；运行区懒建（首用
    // 落位，此处只捕获，不提前拷 zip）
    initPyRuntimeStore(this.context);
    // Python 旧版本运行区清扫（2026-11-14 存储暴涨修复）：目录名随版本串换新，每轮侧载
    // 遗留一套 ~115MB 旧目录且各清理入口均不可见——启动一次列 filesDir 把 python- 前缀且
    // 非当前版本的目录后台递归删（fire-and-forget 不阻塞启动；失败打日志下次启动再清，
    // 有界自愈，照 sweepAttachDir 启动清扫口径）
    sweepLegacyPyRuntimeDirs(this.context).catch((e: Object): void => {
      hilog.error(DOMAIN, 'testTag', 'Python 旧运行区清扫失败（下次启动重试）：%{public}s',
        (e as Error).message);
    });
    // Node 运行时域 ctx 捕获（门 2）：exec_node 执行器与探针页无组件环境，rawfile 四件落位与
    // endpoint 读取都要 filesDir——onCreate 注入先于任何 Node 调用（运行区懒建，此处只捕获，
    // 不提前拷 tar 也不启动 Node）
    initNodeRuntimeStore(this.context);
    // Node 旧版本运行区清扫（门 2 §3.1）：侧载新版后旧 node-X.Y.Z-gN 目录不可达，冷启一次
    // 列 filesDir 后台递归删（只匹配版本名且非当前版本；node-data 等不匹配）。Node 侧
    // runtime-setup 在当前版本就绪后还会再扫一次——本处只是冷启磁盘卫生，两处判据同源。
    // fire-and-forget 不阻塞启动，失败打日志下次启动再清（有界自愈，照 sweepLegacyPyRuntimeDirs）
    this.sweepLegacyNodeRuntimeDirs().catch((e: Object): void => {
      hilog.error(DOMAIN, 'testTag', 'Node 旧运行区清扫失败（下次启动重试）：%{public}s',
        (e as Error).message);
    });
    // 模拟 Shell 资产域 ctx 捕获：rawfile/shell 三件资产经 resourceManager 读取用——照
    // 上行同形（组合根单点先例，OcrPaddle 同族）
    attachShellAssetContext(this.context);
    // Web 静态面资产域 ctx 捕获：rawfile/webui 静态托管经 resourceManager 读取用——照上行
    // 同形；kill-switch 默认关 = 捕获了也零端口监听零行为增量
    attachWebStaticContext(this.context);
    // RDB 异步初始化（任务书红线：EntryAbility 阶段发起；UI 经 whenReady() 等待，未就绪
    // 禁发送，禁在 UI 构建函数里同步等库）。初始化内含 streaming→error 中断恢复。随后
    // 接遗留单连接迁移（providers 空表时把 v1 Asset 连接导入首服务商并设为当前）与多 Key
    // 池迁移（v2 单 key 资产 → 池首条目搬运）——均幂等，失败打日志下次启动重试。
    initChatDb(this.context).then((ok: boolean): void => {
      if (!ok) {
        hilog.error(DOMAIN, 'testTag', 'ChatDb 初始化失败——发送功能将被禁用');
        return;
      }
      // ★ 旧会话墓碑口径：原「存量 legacy 会话启动强迁」编排随迁移机制整件退役删除——旧
      // 格式会话不再迁移，列表可见 + 点进呈墓碑 + 用户长按删除；启动维护链只余下方附件收敛。
      // 附件库盘一致性收敛：孤儿行删行 + 孤儿文件删文件（「行在文件不在」保留行——
      // AttachmentDb 头注释口径）；fire-and-forget 不阻塞首帧，失败留痕下次启动再收敛。
      // 第三参 = 图侧清理判定面，按本机图能力现读构造后注入（AttachmentDb 禁 import 图域件
      //——双向边令类型检查崩坏，构造点在本件侧；构造器能力读异常时恒 resolve 返 null =
      // 空串占位行保护不删，不阻断本收敛）
      buildAttachmentGraphCleanup(sharedRdbStore()).then(
        (graphCleanup: AttachmentGraphCleanup | null): void => {
          reconcileAttachments(this.context, sharedRdbStore(), graphCleanup)
            .catch((e: Object): void => {
              hilog.error(DOMAIN, 'testTag', '附件一致性收敛失败（下次启动重试）：%{public}s',
                (e as Error).message);
            });
        }).catch((e: Object): void => {
        // 构造器断言恒 resolve；本兜底只防「未来改动使然」时整段收敛被静默跳过（P0-1 不静默）
        hilog.error(DOMAIN, 'testTag', '附件收敛判定面构造异常（本次跳过库盘收敛）：%{public}s',
          (e as Error).message);
      });
      // 工作区盘一致性对账（偿还技术债务①）：磁盘为事实源——未登记的文件补录进列表（来源
      // 标「恢复」）、指向已不存在文件的记录清除；fire-and-forget 不阻塞首帧，失败留痕下次
      // 启动再对账；时点在迁移后（initChatDb 内部已完成 v49 迁移，同链天然有序）；与附件
      // 收敛互不干扰（本对账只扫 workspace 目录）
      reconcileWorkspace(sharedRdbStore())
        .catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '工作区一致性对账失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
      // 重启续答·列表标记重建：「生成中」标记是进程内存态（ChatSessionRuntime.sendingFlag
      // 零持久化）——重启后等待会话在列表丢标记，与未重启的离页行为不一致。本步把全库
      // awaiting_input 且有等待行的会话 id 一次性喂给运行时恢复集，作答/放弃落库提交时清标；
      // fire-and-forget 不阻塞首帧（稳态空集零成本），失败打日志下次启动重试
      graphAwaitingConversationIds().then((ids: string[]): void => {
        chatSessionRuntime.primeRestoredAwaiting(ids);
      }).catch((e: Object): void => {
        hilog.error(DOMAIN, 'testTag', '重启待答标记重建失败（下次启动重试）：%{public}s',
          (e as Error).message);
      });
      ensureProvidersMigrated().then((): void => {
        // 内置境外服务商退役：**先于**单 key 池迁移——退役连行带池条目与遗留明文一起删；
        // 若迁移先跑，可能与删除交错给已删行补出孤儿池条目（Asset 无前缀枚举，事后无法
        // 定位）。幂等；失败也照常继续单 key 迁移（两件事互不阻塞）
        retireOverseasBuiltinProviders()
          .catch((e: Object): void => {
            hilog.error(DOMAIN, 'testTag', '内置境外服务商退役失败（下次启动重试）：%{public}s',
              (e as Error).message);
          })
          .then((): void => {
            migrateProviderKeyPools();
          });
        // 重复内置行收敛：跨设备备份导入会在本机 seed 壳外多插一份 builtin=1 同名家（内置
        // id 每台设备随机必不同）且三层删除保护全按标志位拦死——本步按 name+baseUrl 分组
        // 让位收敛，只删多余 builtin=1 行。幂等；位置在 ensureProvidersMigrated 之后 =
        // v52 builtin 列必在
        convergeDuplicateBuiltinProviders().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '重复内置行收敛失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // HTTP 请求模板动态注册同步：库 → 注册表幂等同步（写侧即时同步，本处兜启动首同步
        //——声明追加点 ChatContextUsage.collectTools 同步读注册表，靠本行保证首用前已就绪）；
        // fire-and-forget 失败打日志（库读失败时 sync 内部零动作保旧态）
        syncTemplateTools().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', 'HTTP 模板注册同步失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // MCP 工具注册同步（syncTemplateTools 同款启动兜底）：**从 DB 缓存恢复注册表条目，
        // 不发起网络**——不连接也可声明（缓存快照 = 上次同步的描述/schema；调用时服务器
        // 不可达由 executor 抛错走 error 回执）；同步链写点即时同步，本处保首用前就绪
        syncMcpTools().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', 'MCP 工具注册同步失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 系统提示词行兜底（★ 内置化：无行插内置内容行 / 存量空内容行填充内置——可更改
        // 可重置；幂等，失败打日志下次启动重试——注入解析侧对无全局行另有 GLOBAL_EMPTY_ROW
        // 占位兜底）
        ensurePromptGlobal().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '提示词系统提示词兜底失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 内置默认助手兜底：助手页恒留一张内置默认卡禁删——无行插「默认助手」空提示词行；
        // 幂等，失败下次启动重试
        ensureDefaultAssistant().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '默认助手兜底失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // （内置控制台助手兜底已随控制台合并笔退役——assistant-console 行由 ChatDbMigrate
        // v62 删除，名下会话改指默认助手）
        // 内置技能 seed 与升代：无行才插、标记落后才迁移〔内容刷新/排前/默认助手启用〕；
        // source='builtin' 禁删禁改守卫在 SkillDb 首行；失败下次启动重试
        ensureBuiltinSkills().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '内置技能 seed 失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 预置服务商卡 seed：一次性幂等落库；fire-and-forget 不阻塞首帧。函数体自带注册
        // 门闩——标记键 persistProp 注册完成（下方 loadContent 回调 notify）后才读标记，
        // 防磁盘 '1' 未加载误判重跑回填删卡
        seedProviderPresets().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '预置服务商卡 seed 失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
      });
    });
  }

  // Node 旧版本运行区清扫（门 2 §3.1）：冷启列 filesDir，把「匹配 node-X.Y.Z-gN 且非当前
  // 版本」的目录后台递归删（递归删树复用 pyexec 异步实现，不新增删除逻辑）。当前版本目录与
  // node-data 等非版本名目录一律跳过；目录不存在 = 达成态（removeTreeAsync 内部静默）
  private async sweepLegacyNodeRuntimeDirs(): Promise<void> {
    let names: string[] = [];
    try {
      names = await fs.listFile(this.context.filesDir);
    } catch (e) {
      return; // filesDir 读失败 = 兜底放弃本轮，不抛
    }
    for (const name of names) {
      if (name === NODE_HOME_DIR_NAME || !NODE_LEGACY_DIR_PATTERN.test(name)) {
        continue;
      }
      await removeTreeAsync(this.context.filesDir + '/' + name);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 崩溃订阅注销（与 onCreate 的 ensureCrashWatcher 成对——addWatcher↔removeWatcher
    // 红线；进程即将销毁，一并置空防悬空句柄）
    teardownCrashWatcher();
  }

  // 热启动分享/打开方式拉起：单例 Ability 二次拉起走本回调——分享内容在新 want 里，
  // onForeground 无 want 拿不到（官方 FAQ faqs-share-3 实锤），与 onCreate 冷启动同链路解析
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    this.parseIncomingShare(want);
  }

  // 分享双入口解析：sendData（系统分享面板，getSharedData 取记录集）与 viewData（文件管理器
  // 「打开方式」，want.uri 直取单件）统一落 PENDING_SHARES 桥——路由与消费在 HomeNavigation /
  // 会话页（AttachmentPickCtrl.consumePendingShareInto）。非分享 want 两分支都不命中 = 零动作。
  // 解析失败 hilog 留痕不阻断启动（fail-open：分享链失败只损失本次分享）
  private parseIncomingShare(want: Want): void {
    const action: string = want.action ?? '';
    if (action === 'ohos.want.action.sendData') {
      systemShare.getSharedData(want).then((data: systemShare.SharedData): void => {
        const items: PendingSharedItem[] = [];
        data.getRecords().forEach((record: systemShare.SharedRecord): void => {
          // 文件件优先（uri 与 content 二者至少一个非空——API 契约）；文本/链接件只带
          // content，进输入框
          if (record.uri !== undefined && record.uri !== '') {
            items.push({ uri: record.uri, title: record.title ?? '', utd: record.utd, content: '' });
          } else if (record.content !== undefined && record.content !== '') {
            items.push({ uri: '', title: record.title ?? '', utd: record.utd, content: record.content });
          }
        });
        this.writePendingShares(items);
      }).catch((e: BusinessError): void => {
        hilog.error(DOMAIN, 'testTag', '分享数据解析失败 code %{public}d：%{public}s', e.code, e.message);
      });
    } else if (action === 'ohos.want.action.viewData') {
      const uri: string = want.uri ?? '';
      if (uri === '') {
        return;
      }
      // 「打开方式」无 title 字段——文件名由消费侧从 uri 尾段提取（pickerFileName）
      this.writePendingShares([{ uri: uri, title: '', utd: want.type ?? '', content: '' }]);
    }
  }

  // 桥写入（非空才写）：先写数据后自增 tick——消费侧按 tick 匹配批次，数据恒先于触发在位
  private writePendingShares(items: PendingSharedItem[]): void {
    if (items.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>(PENDING_SHARES_KEY, JSON.stringify(items));
    AppStorage.setOrCreate<number>(PENDING_SHARES_TICK_KEY,
      (AppStorage.get<number>(PENDING_SHARES_TICK_KEY) ?? 0) + 1);
  }

  // 主窗口 stage 引用：深浅色切换时窗口底色重挂需跨方法取主窗——存成员供
  // applyWindowBackground / onConfigurationUpdate 复用。成对纪律（内存红线）：
  // onWindowStageCreate 赋值 ↔ onWindowStageDestroy 置 null，窗体引用不随 Ability 存活期
  // 悬空持有
  private windowStage: window.WindowStage | null = null;

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 主窗引用入成员（与 onWindowStageDestroy 置 null 成对）
    this.windowStage = windowStage;

    try {
      // 窗口全屏布局（HDS 标题栏簇的配套前提，dshinhm 同款配方，见 nav/HomeNavigation.ets
      // 头注释与 MEMORY_DETAIL.md 坑1/坑2）：布局延伸到状态栏/导航条下，避让全靠页面内
      // 显式参数（标题栏 avoidLayoutSafeArea / 页签 barBottomMargin / 页面 topPad·bottomPad）
      windowStage.getMainWindowSync().setWindowLayoutFullScreen(true);
      // 键盘避让模式显式声明（dshinhm 沉淀：系统默认行为随版本漂移，必须显式）：
      // RESIZE_WITH_CARET = 内容区压缩 + 随光标微调，官方《键盘适配完整指南》推荐 RESIZE
      // 家族——聊天页形态（上列表 + 底部输入栏）正是该档适用场景；OFFSET 会把输入栏推出屏、
      // NONE 不避让，均不选
      windowStage.getMainWindowSync().getUIContext()
        .setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
      // 当前颜色模式写入 AppStorage：页面 @StorageProp('appColorMode') 响应式获取——
      // 此前无人写键，深色模式下卡底/胶囊配色停在浅色档（BLOCKED.md 挂账项，已关闭）；
      // 深浅色切换跟随见 onConfigurationUpdate
      const mode: number = this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      AppStorage.setOrCreate<number>('appColorMode', mode);
      // 卡底透明度档位键前置在场（双步法第一步；键与四量单源 = AppPreferences）：
      // loadContent 前只写内存保首帧键在场——落盘由 loadContent 回调内的 persistProp 承接
      //（坑17：早于该时机写不落盘）
      AppStorage.setOrCreate<number>(PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'Failed to init fullscreen/keyboard: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // ── 持久键注册区总口径（下文各键注释不再重复）──
      // · 全部 persistProp 必须在 loadContent 成功回调内：PersistentStorage 与 UI 实例关联，
      //   早于该时机会导致写入不落盘、重启恢复默认值（坑17，官方文档明示）；回调触发时页面
      //   组件尚未实例化，不与 @StorageProp/@StorageLink 初始化抢序。
      // · persistProp 官方语义 = 已存用户值优先于缺省值（缺省只对新装与无本键的旧版升级生效）。
      // · 随偏好备份走的键不逐处标注，归属以 AppPreferences.ets BACKUP_PREF_KEYS /
      //   BACKUP_EXCLUDED_PREF_KEYS 为单一事实源；例外（刻意不随备份/进排除表）就地注明。
      // · 标量类型（string/boolean/number）官方均可持久化，下文不再注。
      // ── 退役偏好键一次性清理（2026-11-12 偏好开关批，2152 节）──
      // 十组显示/行为开关整体退役、行为固化为用户不可关闭：推荐语恒填入输入框、工具卡
      // 恒显结果摘要、本轮改动/消息时间/行内高亮/会话图标/会话时间恒显示、会话恒最新在上、
      // 行卡图标恒彩色圆角矩形，「图标」三级页整页撤除。键常量、persistProp 注册、备份
      // 登记全撤；此处只留墓碑键名清单，把存量设备的落盘旧值一并清掉——旧值不继承、
      // 不做行为迁移。这是十个键名在全仓的唯一落点，防回流负向钉按段切除后再扫
      //（`assert-feature-domain` 54 组：该件其余部分仍受钉守，注册面由同组 A 段全覆盖钉兜住）。
      // 官方依据：developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-752
      // 《PersistentStorage持久化数据无法删除》+ SDK 26 common_ts_ets_api.d.ts:949
      // deleteProp、:443 AppStorage.delete（均 @since 10、非废弃）：deleteProp 删持久化文件
      // 中的键，AppStorage.delete 删进程内残留；本处位于 loadContent 成功回调、页面组件
      // 实例化之前，无 @StorageLink 订阅者，官方所述「有订阅者则删不掉」不适用。
      // 幂等：每次启动无条件跑，键不存在时两调用无副作用；刻意不新增「已清理」持久标记
      // ——为一次清理动作再造一个持久键不划算。
      const RETIRED_PREF_KEYS: string[] = [
        'prefSuggestTapFill', 'prefToolCardSummary', 'prefFileChangesVisible',
        'prefMessageTime', 'prefMarkHighlight', 'prefSessionIcon', 'prefSessionTime',
        'prefSessionOrder', 'prefColorIcons', 'prefIconShape'
      ];
      for (const retiredKey of RETIRED_PREF_KEYS) {
        PersistentStorage.deleteProp(retiredKey);
        AppStorage.delete(retiredKey);
      }
      // 窗口底色对齐 page_bg（机制与依据见 applyWindowBackground 头注释；挂本回调内 = d.ts
      // 时机硬约束〔stage 模型必须 loadContent 生效后调用〕，与 PersistentStorage 同点位先例）
      this.applyWindowBackground();
      // 沉浸光感总档键（dshinhm 同款；★ 分项退役：原「悬浮底栏」「其他控件」两分项键删除
      // ——两处档位恒跟随总档，见 ImmersiveLevel.ets 头注释，已存用户的分项持久化值随键弃用
      // 自然失效无迁移必要）。★ 2026-10-18 光感段整体退役（决明「不提供光感调整，全部光感
      // 维持在强档」）：缺省值 0 → IMMERSIVE_LEVEL_FIXED（4 强）；本键退为固定档能力位，
      // 全站消费方照旧订阅，但写点只剩本处——外观页滑轨卡已退役，工具查询白名单亦无本键
      PersistentStorage.persistProp(IMMERSIVE_LEVEL_KEY, IMMERSIVE_LEVEL_FIXED);
      // 存量归正：旧安装存过 0/2/3 档的用户在此归正到强档——否则其永久停在旧档位且已无
      // 入口改回（persistProp 已注册该键，setOrCreate 即落盘）；备份导入面已把 immersiveLevel
      // 移入排除表，旧备份低档值不会绕开本处归正
      if (AppStorage.get<number>(IMMERSIVE_LEVEL_KEY) !== IMMERSIVE_LEVEL_FIXED) {
        AppStorage.setOrCreate<number>(IMMERSIVE_LEVEL_KEY, IMMERSIVE_LEVEL_FIXED);
      }
      // 内容区「光感新规范」能力位（★ 决明拍板撤该开关卡）：true = 受影响内容区组件按华为
      // 新光感规范走官方标准形态（分段胶囊 A 档、按钮 fallbackButton* 官方实底——新规范下
      // 内容区材质不生效）；false = 原材质光感。该键**已无用户入口、常态恒 true**——保留为
      // 能力位（华为若放开内容区材质，改这一处即可全项目复验光感态；保留理由与复活路径见
      // common/ImmersiveLevel.ets 头注释同键条；消费侧双态见 ImmersiveLevel.ets
      // fallbackButton* 函数族与 components/SegmentBar.ets）
      PersistentStorage.persistProp(CONTENT_FALLBACK_KEY, true);
      // 存量归正：撤卡前把开关关掉、存了 false 的用户在此归正到 true（同上先例）
      if (AppStorage.get<boolean>(CONTENT_FALLBACK_KEY) !== true) {
        AppStorage.setOrCreate<boolean>(CONTENT_FALLBACK_KEY, true);
      }
      // 自定义背景图：「外观显示」页「背景」面板写入沙箱 file:// URI，PageBackground
      // @StorageProp 消费；空 = 默认官方灰底
      PersistentStorage.persistProp('pageBg', '');
      // 壁纸解码预热：pageBg 水合后即刻起解码——抢在页面树构建之前，解码与建树重叠；
      // 机制与「缩短非归零」口径见 BgCache.warmBgCacheForColdStart 头注释
      warmBgCacheForColdStart(this.context.filesDir);
      // 一级页签列表预热：persistProp 全注册后（ACTIVE_ASSISTANT_KEY 已水合——预热查询的
      // 助手过滤读真值）、组件实例化前发起助手/对话两页签首查——与上方壁纸预热同点位；
      // fire-and-forget 不阻塞首帧，机制与规范偏离申报见 HomeListWarmup.ets 头注释
      homeListWarmup.warm();
      // 编辑图片参数记忆三键：模糊/遮罩百分比 + 裁剪状态 [zoomPct, tx, ty]——调整页保存
      // 成功时写入，重进编辑页恢复（键语义见 ImageEditUtil.ets）
      PersistentStorage.persistProp(EDIT_BLUR_PCT_KEY, 0);
      PersistentStorage.persistProp(EDIT_MASK_PCT_KEY, 0);
      PersistentStorage.persistProp(EDIT_CROP_STATE_KEY, [0, 0, 0]);
      // 设置项搜索历史/最近使用：string[] 一维数组可持久化（对象数组禁止）；上限截断在
      // SettingSearch 读写两侧收敛，有界
      PersistentStorage.persistProp(SEARCH_HISTORY_KEY, [] as string[]);
      PersistentStorage.persistProp(RECENT_USE_KEY, [] as string[]);
      // 会话搜索历史/最近进入：键语义与有界口径见 common/SessionSearch.ets 头注释
      PersistentStorage.persistProp(SESSION_SEARCH_HISTORY_KEY, [] as string[]);
      PersistentStorage.persistProp(SESSION_RECENT_CONV_KEY, [] as string[]);
      // 当前服务商/模型两键：聊天页连接解析的持久输入——模型选择面板/删除失效路径写入；
      // 解析侧对失效值自动兜底。全局默认模型两键：发送链四级兜底第③级来源（会话页所选 >
      // 助手绑定 > 全局默认 > 首个启用模型）；'' = 未设置，解析侧对失效值自动降级
      PersistentStorage.persistProp(DEFAULT_PROVIDER_KEY, '');
      PersistentStorage.persistProp(DEFAULT_MODEL_KEY, '');
      // 标题生成两键：AI 会话标题生成的显式开关——'' = 未设置 = 功能未启用静默不生成
      //（决明二次拍板，无会话连接兜底）；解析链独立单级验证（TitleGen），不碰 active/default 四键
      PersistentStorage.persistProp(TITLE_PROVIDER_KEY, '');
      PersistentStorage.persistProp(TITLE_MODEL_KEY, '');
      // 标题生成总开关（缺省 true 开——既有功能加闸，缺省 false 会让存量用户升级即功能消失）；
      // false = 生成链守卫序最前早退零请求（两键配置保留不清理，重开即恢复）；键与缺省值
      // 单源 ProviderDb.TITLE_ENABLED_KEY，消费方 = TitleGen 守卫 + 功能模型页「标题生成」卡
      PersistentStorage.persistProp(TITLE_ENABLED_KEY, true);
      // 审批模型两键：工具调用确认链 LLM 审批闸的显式开关——'' = 未设置 = 功能未启用
      //（确认链照旧弹人工卡，零请求）；解析链单级验证（resolveTitleEndpoint，providers/
      // ApprovalGate 消费），不碰四级连接链
      PersistentStorage.persistProp(APPROVAL_PROVIDER_KEY, '');
      PersistentStorage.persistProp(APPROVAL_MODEL_KEY, '');
      // ①审批提示词定制键（'' = 未定制 = 闸回退内置 APPROVAL_PROMPT_TEMPLATE——清删式恢复
      // 默认语义；保存 = 写全量文本，闸现读即时生效，单源 ApprovalGate）；②审批总开关
      //（缺省 true 开——既有功能加闸不改变存量行为；false = 闸早退回人工卡，与两键不齐
      // 同一 fail-closed 去向，档位与配置保留不写回）
      PersistentStorage.persistProp(APPROVAL_PROMPT_KEY, '');
      PersistentStorage.persistProp(APPROVAL_ENABLED_KEY, true);
      // 会话权限模式应用默认档（2026-11-09 真完全权限笔；同日三档归一笔记开放三档）：
      // 缺省 '' = 未设档，由下方启动迁移按旧三域档最严值一次性折算写定（谨慎/标准/高效）。
      // 用户在设置页选档后写本键；会话内第三键可为本会话单独改档（按会话持久表）。
      PersistentStorage.persistProp(PREF_DEFAULT_PERMISSION_MODE_KEY, '');
      // 会话权限模式按会话持久表（2026-11-09 决明「重启后也记得，每会话绑定」）：JSON 表
      // 「会话 id → 谨慎/标准/高效」，进会话时按 id 回填。刻意不进备份表——键是本地
      // 会话 id（换机无意义），且高效档跨设备静默复现等于替新设备放宽确认策略。
      PersistentStorage.persistProp(PREF_CHAT_PERMISSION_MODES_KEY, '{}');
      // 功能任务思考档位：八条功能模型小任务链共用的全局档——'' = 默认不干预（请求不带
      // 思考字段 = 本键注册前的行为，存量零回归）；归一在消费侧逐链做
      //（TitleApi.resolveFunctionalThinking），非法值与不支持的模型一律落 '' 静默不发
      PersistentStorage.persistProp(FUNCTIONAL_THINKING_KEY, '');
      // OCR 键族：总开关缺省 'true'（开——读侧 OcrEngine.ocrEnabled 对未写仍兜底开）；系统
      // 识别开关键与内置引擎三态键缺省 '' = 未写 = 按旧口径推导（解析单源
      // ProviderDb.resolveOcrEngine；偏好键自此退役为只读兜底）；已选模型两键 '' = 未选；
      // 识别提示词定制键 '' = 未定制 = 识别链回退内置 OCR_PROMPT_TEMPLATE（清删式恢复默认
      // 语义，保存 = 写全量文本现读即时生效，单源 OcrVisionApi）
      PersistentStorage.persistProp(OCR_ENABLED_KEY, 'true');
      PersistentStorage.persistProp(OCR_ENGINE_KEY, '');
      PersistentStorage.persistProp(OCR_PREFER_SYSTEM_KEY, '');
      PersistentStorage.persistProp(OCR_PROVIDER_KEY, '');
      PersistentStorage.persistProp(OCR_MODEL_KEY, '');
      PersistentStorage.persistProp(OCR_PROMPT_KEY, '');
      // 内置识别引擎的资源管理器注入：三模型与字典在 rawfile，common 层拿不到 UIContext
      //——能力上下文是应用级单一真源，与本处 persistProp 注册同属组合根职责；引擎本身
      // 懒加载（首次识别才读模型，见 OcrPaddle 头注释）
      ocrAttachContext(this.context);
      // 标题生成提示词定制：'' = 未定制 = 生成链回退内置 TITLE_PROMPT_TEMPLATE（清删式
      // 恢复默认语义）；保存 = 写全量文本，生成链现读即时生效
      PersistentStorage.persistProp(TITLE_PROMPT_KEY, '');
      // 推荐问题三键 + 提示词定制键：总开关默认 **false 关**（BYOK 成本敏感 + ChatGPT 无
      // 开关扰人教训，每轮多一次请求由用户显式授权）；已选模型两键 '' = 未配置 = 功能未启用
      // 零请求（照标题生成拍板，无兜底不回退，SuggestGen 守卫序单级验证）；suggestPrompt
      // '' = 未定制 = 生成链回退内置 SUGGEST_PROMPT_TEMPLATE（清删式恢复默认语义，单源
      // SuggestGen）
      PersistentStorage.persistProp(SUGGEST_ENABLED_KEY, false);
      PersistentStorage.persistProp(SUGGEST_PROVIDER_KEY, '');
      PersistentStorage.persistProp(SUGGEST_MODEL_KEY, '');
      PersistentStorage.persistProp(SUGGEST_PROMPT_KEY, '');
      // 上下文压缩模型两键 + 提示词定制键：两键 '' = 未配置 = 生成时**回退当前会话的模型**
      //（与 suggest「未配置即停」语义不同——本槽有回退）；compressPrompt '' = 未定制 =
      // 生成链回退内置 COMPRESS_PROMPT_CONTENT（清删式恢复默认语义，单源 CompressGen）
      PersistentStorage.persistProp(COMPRESS_PROVIDER_KEY, '');
      PersistentStorage.persistProp(COMPRESS_MODEL_KEY, '');
      PersistentStorage.persistProp(COMPRESS_PROMPT_KEY, '');
      // 当前助手：助手页签点卡切换的持久选择——历史列表过滤/新会话落行绑定/注入链新会话
      // 回退三处消费；缺省 = 内置默认助手
      PersistentStorage.persistProp(ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID);
      // 存量归正：升级前「当前助手 = 控制台助手」的设备，本键残值 'assistant-console' 在
      // ChatDbMigrate v62 删行后悬空——persistProp 缺省只管键不存在、消费端 ?? 只兜 null，
      // 均兜不住悬空 id；不归正则历史列表按悬空 id 过滤恒空、新会话绑定不存在的助手。
      // id 字面量照 ChatDbMigrate v62 同串（ASSISTANT_CONSOLE_ID 常量已随控制台退役删除）
      if (AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) === 'assistant-console') {
        AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID);
      }
      // （控制台助手工具 seed 检查标记键已随控制台合并笔退役——存量设备磁盘残值无消费者，
      // 无害不清理）
      // 内置技能 seed 升代标记：'' = 从未迁移 / 'N' = 已迁移到第 N 代——标记只挡升代迁移
      // 重跑（只升不降，语义见 SkillBuiltinDefs.ets 头注释），不挡无行兜底插入；判据与失败
      // 不推标记语义见 SkillDb.ensureBuiltinSkills 节头注释
      PersistentStorage.persistProp(SKILL_BUILTIN_SEEDED_KEY, '');
      // 待并入登记：JSON 数组串 = 本机 seed 插入、自动并入尚未落定的内置 id——超限跳过/
      // 抛错时凭它下次启动补跑（语义见 SkillDb.flushPendingAutoEnable）
      PersistentStorage.persistProp(SKILL_PENDING_JOIN_KEY, '[]');
      // 默认展开思考：消费方 = ChatThinkingStep 创建期读初始态
      PersistentStorage.persistProp(PREF_THINK_EXPAND_KEY, false);
      // 键盘发送开关：false = 换行键（默认）/ true = 发送键；消费方 = ChatInputBar 订阅
      PersistentStorage.persistProp(PREF_KEYBOARD_SEND_KEY, false);
      // 输入框常驻展开（决明拍板）：false = 收起态胶囊（默认）/ true = 进页即展开态且失焦
      // 不收起；消费方 = ChatInputBar @StorageProp @Watch
      PersistentStorage.persistProp(PREF_INPUT_EXPANDED_KEY, false);
      // 图片链接作为图片发送：false = 消息里的 Markdown 图链按普通文本发送（默认）/ true =
      // 发送前自动下载图链作为图片附件随本轮请求发给模型；消费方 = TextImageFetch 发送链
      // 早退现读
      PersistentStorage.persistProp(PREF_TEXT_IMAGE_FETCH_KEY, false);
      // ★ 原流式引擎试验开关（PREF_STREAM_ENGINE_KEY）持久注册随 Cube 实验揭示链退役删除；
      // 存量安装的系统存储残留值无害、不再读取。
      // 流式输出自动跟随：true = 输出自动滚底（默认）/ false = 停在当前位置；偏好页开关写、
      // ChatFollowController.maybeFollow 现读（现读 = 切换即时生效）
      PersistentStorage.persistProp(PREF_STREAM_FOLLOW_KEY, true);
      // HTML 预览运行脚本开关（回复显示组卡）：true = 受限预览（html 类）可执行输入 HTML 的
      // 脚本 / false = 照默认剥脚本（缺省，安全优先零回归）；消费方 =
      // MarkdownPreviewCover.aboutToAppear 点开时刻读取一次（预览为点开才建的新实例，天然即时）
      PersistentStorage.persistProp(PREF_PREVIEW_JS_KEY, false);
      // 长代码块自动收起开关（回复显示组卡）：true = 生成结束的长代码块（超过行数阈值）自动
      // 收起为前若干行 + 底部展开条 / false = 保持展开（默认）；消费方 =
      // MarkdownScrollableBlock 终态评估处现读（已终态块评估一次不再重评——重进会话后生效）
      PersistentStorage.persistProp(PREF_CODE_AUTO_COLLAPSE_KEY, false);
      // 代码块行号开关（回复显示组卡）：true = 消息里的 Markdown 代码块、HTML <pre> 代码块
      // 与工具卡 diff 块逐行显示行号（默认）/ false = 不显示；消费方 = MarkdownCodeText /
      // MarkdownHtmlBlockView / ChatToolDiffBlock 渲染期现读（重进会话后生效）
      PersistentStorage.persistProp(PREF_CODE_LINE_NUMBERS_KEY, true);
      // 消息内 HTML 直接渲染开关（回复显示组卡）：true = 消息中的 htmlBlock 走白名单结构
      // 投影 + 原生组件渲染（默认）/ false = 一律按源码文本显示；消费方 =
      // MarkdownScrollableBlock 内容分支现读（已挂载块不即时换渲染——重进会话后生效）
      PersistentStorage.persistProp(PREF_HTML_BLOCK_RENDER_KEY, true);
      // 会话加载动画开关（回复显示组卡）：true = 进入会话历史加载期间消息区显示淡蒙层与
      // 加载动画（默认，治进会话空白感知空窗）/ false = 加载期纯背景；消费方 =
      // ChatPageContent 加载分支订阅（切换后下次进入会话生效）
      PersistentStorage.persistProp(PREF_CHAT_LOADING_OVERLAY_KEY, true);
      // 长消息进页收起开关（★ 双态设计改义；键名沿用免得丢存量用户值）：true = 进入会话时
      // 收起超长消息（默认，进页只付收起条成本）/ false = 进页全部展开，由加载动画与分帧
      // 渐进揭示承担等待；消费方 = ChatMessageItem 折叠判据渲染期现读
      PersistentStorage.persistProp(PREF_LONG_MSG_COLLAPSE_KEY, true);
      // 助手消息气泡开关（回复显示组卡）：true = 助手回复带气泡底色、圆角与内距（默认）/
      // false = 三者撤除、正文贴行沿排列；消费方 = ChatPageContent 进页读一次后下发
      // ChatMessageItem（重进会话后生效）
      PersistentStorage.persistProp(PREF_ASSISTANT_BUBBLE_KEY, true);
      // 思考档位滑轨开关（回复显示组卡，★ 2026-11-25 思考档位滑轨笔）：true = 标题栏「思考」
      // 热区点开滑轨面板（默认）/ false = 旧菜单；消费方 = ChatTitleBarOverlay @StorageProp
      // @Watch 订阅——拨动开关即刻切换形态
      PersistentStorage.persistProp(PREF_THINKING_SLIDER_KEY, true);
      // SVG 预览开关（回复显示组卡）：true = ```svg / 验根为 svg 的 ```xml 代码块给受限预览
      // 入口（默认——点开走受限 Web 壳静态渲染，无脚本、无网络、无文件权限）/ false = 无
      // 预览入口；消费方 = MarkdownScrollableBlock 预览键与 openPreview 守卫现读
      PersistentStorage.persistProp(PREF_SVG_PREVIEW_KEY, true);
      // Mermaid 消息内联渲染开关（回复显示组卡）：true = 已闭合的合法 mermaid 代码块在消息
      // 内直接显示渲染图（默认）/ false = 一律按代码块显示；消费方 = MarkdownScrollableBlock
      // 内容分支现读（重进会话后生效）；渲染失败自动退码，开态最坏观感与关态一致
      PersistentStorage.persistProp(PREF_MERMAID_INLINE_KEY, true);
      // 拍照保存到相册开关（输入与发送组卡）：true = 会话内拍照时照片同时存进系统相册
      //（拍照不传 saveUri，系统相机自动落媒体库并返回临时授权 URI，再 fd 级拷入沙箱供发送）/
      // false = 只落沙箱、相册零痕迹（默认）；消费方 = AttachmentPickCtrl.pick 相机分支现读
      //（拨动即生效）
      PersistentStorage.persistProp(PREF_PHOTO_SAVE_GALLERY_KEY, false);
      // 添加图片时编辑（输入与发送组卡）：true = 「拍照」与「照片」两入口的图片先进待发
      // 图片裁剪页，完成后裁剪产物入列 / false = 直接入列（默认，零回归）。只影响这两个
      // 入口；消费方 = AttachmentPickCtrl.pick 相机与相册分支现读（拨动即生效）
      PersistentStorage.persistProp(PREF_PHOTO_EDIT_KEY, false);
      // 会话页屏幕常亮：true = 进会话页设窗口常亮（退出复位）/ false = 系统息屏（默认）；
      // 键与读值封装单一来源 AppPreferences.ets，消费方 = ChatPage 生命周期
      PersistentStorage.persistProp(PREF_KEEP_SCREEN_ON_KEY, false);
      // 后台回复提醒：true = 切后台时申请短时任务保活当前生成并发回复通知（开关打开时顺带
      // 请求通知授权，被拒回落关）/ false = 不申请不通知（默认 = 最保守）。消费方 =
      // ChatBgReply 两闸现读 + PrefSessionReadPage 开关行。零新增权限——短时任务与通知发布
      // 都不需要声明（官方《短时任务(ArkTS)》「导入模块，无需配置权限」）
      PersistentStorage.persistProp(PREF_BG_REPLY_NOTIFY_KEY, false);
      // 会话宫格视图（内部代号方块卡）：false = 单列列表（默认 = 引入前形态零回归）/ true = 两列宫格；消费方 =
      // ChatSessionList 壳 @StorageProp 订阅（切换即重算）与会话卡片渲染分支
      PersistentStorage.persistProp(PREF_SESSION_CARD_GRID_KEY, false);
      // 智感握姿跟随（偏好设置·会话与阅读组）：true = 会话列表右下悬浮新建键随左右手握持
      // 移到同侧（默认）/ false = 恒右不跟随；消费方 = SessionNewFab @StorageProp @Watch
      // 自订阅（拨关归右）
      PersistentStorage.persistProp(PREF_HOLDING_FOLLOW_KEY, true);
      // 快捷新建键（★ 决明「页签栏旁圆键与会话列表右下悬浮键同关、不能同开」；★ 二改：缺省
      // 由 'off' 改 **'tabBar'**；★ 三改两档化〔2026-10-30 决明「关闭这一项去掉——关掉就
      // 没有落点了」〕）：单键两值 'tabBar'（页签栏旁圆键，默认）/ 'float'（列表右下悬浮键）
      // ——互斥由值域结构性保证；消费方 = HomeNavigation（miniBar 门控）与 ChatSessionList
      //（悬浮键挂载门控）
      PersistentStorage.persistProp(PREF_NEW_SESSION_ENTRY_KEY, NEW_SESSION_ENTRY_TAB_BAR);
      // 文件工作区列表排序：'custom' = 自定义（默认——文件夹拖拽序 + 文件最近更新在前）/
      // 另五档 = 名称 / 时间降升 / 大小降升（六档常量与脏值兜底单源 = WorkspaceUtil「列表
      // 排序方式」段）；消费方 = 管理页现读单源（currentSortMode）+ workspace_list 工具
      // 回执现读（AI 与用户同序）
      PersistentStorage.persistProp(PREF_WORKSPACE_SORT_KEY, WS_SORT_CUSTOM);
      // 背景仅用于会话页：true = 自定义背景只在会话页显示 / false = 全应用生效（默认）；
      // 消费方 = PageBackground 订阅 + sessionPage 参数组合判定
      PersistentStorage.persistProp(PREF_BG_SESSION_ONLY_KEY, false);
      // 页签切换动画：true = 底部页签点击切换带横向滑动动画 / false = 点按直达无过渡
      //（默认 true = 决明拍板开回）；消费方 = HomeNavigation 订阅
      PersistentStorage.persistProp(PREF_TAB_SWITCH_ANIM_KEY, true);
      // 启动进入页面：true = 冷启动直接进入新对话 / false = 进入对话一级页（默认）；消费方 =
      // HomeNavigation.aboutToAppear 现读
      PersistentStorage.persistProp(PREF_LAUNCH_NEW_CHAT_KEY, false);
      // 首页布局（方案-首页布局双形态）：'tabs' 底栏页签（默认 = 引入前形态零回归）/ 'drawer'
      // 侧栏对话形态；消费方 = HomeNavigation 形态分发器（热切换回根重建壳）+ 形态无效偏好
      // 灰化判定（PrefSessionReadPage）；写点 = 偏好与外观页外观卡开关行
      PersistentStorage.persistProp(PREF_HOME_LAYOUT_KEY, HOME_LAYOUT_TABS);
      // 上次打开的会话 id：侧栏形态冷启动落点承接（「启动进入新对话」关 = 打开本键会话）；
      // 写点 = 会话打开链（openSession / 主区换会话）；随备份走
      PersistentStorage.persistProp(PREF_LAST_CONV_ID_KEY, '');
      // 价格卡收起态（决明报障「收起状态保存后无法记忆」）：true = 模型编辑页价格卡默认收起
      // 为短卡 / false = 默认展开；键单一来源 AppPreferences.ets，**不在偏好设置页暴露**
      // ——消费方 = ModelPriceCard @StorageLink 双向绑定（点标题行收起即写即落盘，无需点保存）
      PersistentStorage.persistProp(PREF_PRICE_CARD_COLLAPSED_KEY, false);
      // 服务商编辑页两卡收放态：true = 请求头 / Body 卡收起为标题行短卡 / false = 默认展开；
      // **不在偏好设置页暴露**——消费方 = ProviderHeadersPanel / ProviderBodyPanel
      // @StorageLink 双向绑定
      PersistentStorage.persistProp(PREF_HEADERS_CARD_COLLAPSED_KEY, false);
      PersistentStorage.persistProp(PREF_BODY_CARD_COLLAPSED_KEY, false);
      // 余额请求头卡收放态：同上两口径，消费方 = BalanceHeadersCard（宿主 BalanceConfigPage）
      PersistentStorage.persistProp(PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY, false);
      // 会话上下文用量·校准系数：JSON 数组 [{modelId, factor}] 最近使用在前、上限 20 条；
      // 默认 '' = 空 = 各模型纯估算（k = 1）。键与读写封装单一来源 AppPreferences.ets；
      // 写侧唯一 = 发送链锚点校准点、读侧 = 会话页活算
      PersistentStorage.persistProp(PREF_CTX_FACTOR_KEY, '');
      // 网页高危/HTTP 写操作确认档两键：三档 'ask' = 每次确认 / 'model' = 先问审批模型
      //（缺省档）/ 'auto' = 一律放行；缺省空串 = 未写，现读侧 resolveApproveMode 按旧布尔键
      // 推导（旧 true → auto、旧 false 或未写 → model——下方两旧布尔键自此只读兜底仍随备份）。
      // 消费方 = ToolBrowseAct / ToolHttp 预检现读（切换即时生效，下一个动作按新值）
      PersistentStorage.persistProp(PREF_BROWSE_APPROVE_MODE_KEY, '');
      PersistentStorage.persistProp(PREF_HTTP_APPROVE_MODE_KEY, '');
      // 数据管理操作确认档：缺省空串 = 未写，现读侧推导恒落中间档「先问审批模型」（本域
      // 无旧布尔键，无迁移面）
      PersistentStorage.persistProp(PREF_DATA_APPROVE_MODE_KEY, '');
      // 旧布尔键：退为只读兜底（仅作未写新键时的推导依据，仍随备份走）
      PersistentStorage.persistProp(PREF_BROWSE_AUTO_APPROVE_KEY, false);
      // HTTP 写操作自动通过：true = http_request 写方法不弹确认卡直接发送 / false = 每次弹卡
      // 征求同意（默认）；消费方 = ToolHttp 预检首行现读（执行器侧无第二道判据——本件不带
      // 批准戳）
      PersistentStorage.persistProp(PREF_HTTP_WRITE_AUTO_APPROVE_KEY, false);
      // 工具运行参数两键：工具调用轮数上限（存储值域 0~32，0 = 不限制由 256 硬顶兜底）与
      // 搜索结果条数（1~25）。两值原为 assistants 两列（按助手存），现全局唯一来源 = 本两键；
      // 默认值与值域单源 = ToolLimits / SearchLimits 两叶子模块（本处引其常量，禁写死双源）；
      // 消费方 = ChatPromptState 两 getter 轮首现读（改名下一条消息起生效）+ 设置页工具
      // 调用页两张滑轨卡
      PersistentStorage.persistProp(PREF_TOOL_STEP_LIMIT_KEY, TOOL_STEP_LIMIT_DEFAULT);
      PersistentStorage.persistProp(PREF_SEARCH_RESULT_COUNT_KEY, SEARCH_RESULT_COUNT_DEFAULT);
      // 联网请求超时：存储值 = 秒数（值域 5~60，默认 20 = 旧写死常量同值零回归）；默认值与
      // 值域单源 = SearchLimits 叶子模块（禁写死双源）；消费方 = 联网请求入口（WebSearch 两处
      // + ApiSearchEngines 三引擎，各自取一次快照后形参下传，改值下一个请求生效）+ 设置页
      // 联网搜索页超时卡。★ 与 PREF_NET_READ_TIMEOUT_MIN_KEY（模型请求读超时，分钟级）
      // 刻意分链，两键互不读写
      PersistentStorage.persistProp(PREF_SEARCH_TIMEOUT_SEC_KEY, SEARCH_TIMEOUT_SECONDS_DEFAULT);
      // 网络自动重试：true = 网络原因失败且本轮零产出时自动退避重发（最多 3 次，2/4/8 秒）/
      // false = 不自动重试。★ 默认 true = 有意选择非疏忽（理由见 AppPreferences 键注释）；
      // 消费方 = ChatAutoRetryCtrl 判据
      PersistentStorage.persistProp(PREF_AUTO_RETRY_KEY, true);
      // 自动重试配置 JSON 键：重试判据参数〔状态码集合 / 重试与停止词表 / 退避四参数〕自
      // 编译期常量改为用户可配；'' = 未写 = 全默认 = 行为与改造前逐字节等价（总开关仍是上面
      // 的旧布尔键单一真源，本键只判参数）；解析与默认单源 = AppPreferencesRetry.ets，
      // 消费方 = ChatHostDelegates.autoRetryCfg 现读（轮内锁定）
      PersistentStorage.persistProp(PREF_AUTO_RETRY_CFG_KEY, '');
      // 粘贴长文本转文件：开关 true = 粘贴文本达到阈值时转成 .txt 附件挂进待发附件条 /
      // false = 任何粘贴照常插入（默认 true = 有意选择非疏忽，理由见 AppPreferences 键注释）；
      // 阈值默认 2000 字符，取值 1000~20000 步进 500（域与钳位单源 = AppPreferences 的
      // PASTE_THRESHOLD_* / clampPasteThreshold）；消费方 = ChatInputBar 自订阅
      PersistentStorage.persistProp(PREF_PASTE_AS_FILE_KEY, true);
      PersistentStorage.persistProp(PREF_PASTE_AS_FILE_THRESHOLD_KEY, PASTE_THRESHOLD_DEFAULT);
      // 卡底透明度档位（双步法第二步）：注册持久化并对账存量值——存量 ≠ DEFAULT 时
      // AppStorage 值更新、即时面自动刷到存量档（回调时组件未实例化，不与订阅抢序）；
      // 消费方 = Theme.cardBg / chatBubbleUserBg 缺省读键 + 即时面 @StorageProp 只读订阅；
      // 写点唯一 = 外观页背景段滑轨卡
      PersistentStorage.persistProp(PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT);
      // 时间间隔提醒：开关 true = 对话间隔超阈值时发送组装插一条时间提醒（默认 false——本
      // 功能改变发出去的请求内容，静默生效会让用户困惑，理由见 AppPreferences 键注释）；
      // 阈值默认 60 分钟，取值 15~720 步进 15（域与钳位单源 = AppPreferences 的
      // TIME_REMINDER_* / clampTimeReminderMinutes）；消费方 = ChatSendCtrl.assembleRound
      // 每轮现读
      PersistentStorage.persistProp(PREF_TIME_REMINDER_KEY, false);
      PersistentStorage.persistProp(PREF_TIME_REMINDER_MINUTES_KEY, TIME_REMINDER_DEFAULT);
      // 全局 User-Agent：'' = 用默认（默认值与净化单源 common/providers/RequestIdentity.ets）；
      // 消费方 = 出站请求族兜底写入（聊天/小任务/模型清单/余额/搜索引擎/备份链）+ 网络设置页
      // @StorageLink（写即持久化）
      PersistentStorage.persistProp(PREF_USER_AGENT_KEY, '');
      // 请求读超时档位：分钟档 5/10/20，默认 10 = 现行 600s（存量零回归）；非白名单值读取侧
      // 钳 10（域与钳位单源 = AppPreferences 的 NET_READ_TIMEOUT_MINUTES /
      // clampNetReadTimeoutMinutes）；消费方 = ChatStreamBase 起流前现读 + 网络设置页
      // @StorageLink
      PersistentStorage.persistProp(PREF_NET_READ_TIMEOUT_MIN_KEY, NET_READ_TIMEOUT_MINUTES_DEFAULT);
      // HTTP 工具超时上限档：秒级四档 30s/1m/2m/3m，默认 1 分钟（模型不传 timeout_ms 时
      // 生效值 min(30s, 60s) = 30 秒与放开前逐字一致）；非白名单值读取侧钳默认（域与钳位
      // 单源 = AppPreferences 的 HTTP_TIMEOUT_CEILING_MS / clampHttpTimeoutCeilingMs）。
      // ★ 与上方读超时键刻意分链（本键只封 http_request 工具单次请求；聊天流式链与搜索链
      // 各持己键）；消费方 = ToolHttp 执行器每请求现读 + HTTP 请求设置页 @StorageLink
      PersistentStorage.persistProp(PREF_HTTP_TIMEOUT_CEILING_MS_KEY, HTTP_TIMEOUT_CEILING_MS_DEFAULT);
      // HTTP 工具同域请求间隔档：毫秒四档 关/0.5s/1s/2s，默认 1 秒（有意选择非疏忽——理由
      // 与代价见 AppPreferences 该键注释）；非白名单值读取侧钳默认。★ 只作用于 http_request
      // 出站闸的最小间隔；上游 Retry-After 驱动的熔断不受本键影响
      PersistentStorage.persistProp(PREF_HTTP_HOST_INTERVAL_MS_KEY, HTTP_HOST_INTERVAL_MS_DEFAULT);
      // HTTP 凭据元数据：JSON 串结构化键 {owner:[{id,name,hasValue}]}（owner = 助手 id 或
      // 'global'），'' = 无配置。★ 明文恒不进本键——值只进 Asset（KeyStore saveHttpCredential
      // 族），本键只存名称与标记；名称清单属用户配置非本机痕迹（随备份）
      PersistentStorage.persistProp(PREF_HTTP_CREDENTIALS_CFG_KEY, '');
      // HTTP 域名准入白名单：JSON 数组结构化键（归一 host 列表），'' = 空名单 = 不限（现行
      // 全放行口径零变化，用户主动收紧面）；消费方 = ToolHttp 执行器每请求现读（首跳 URL
      // 白名单判据，HttpPolicy.hostAllowedByWhitelist）+ HTTP 请求设置页「域名准入」卡
      PersistentStorage.persistProp(PREF_HTTP_ALLOWED_HOSTS_KEY, '');
      // HTTP 请求页准入卡收放态：true = 卡收起为标题行短卡 / false = 默认展开；键单一来源
      // AppPreferencesHttp.ets，**不在偏好设置页暴露**——消费方 = HttpRequestSettingsPage
      // @StorageLink 双向绑定（2026-11-11 域名确认档退役后本页只剩这一张可折卡）
      PersistentStorage.persistProp(PREF_HTTP_ALLOWLIST_CARD_COLLAPSED_KEY, false);
      // HTTP 长任务句柄持久化镜像：JSON 数组结构化键，只登记运行中后台任务的最小身份字段
      //（终态即清，镜像恒极小）；消费方 = ToolHttp 句柄表工厂启动恢复（重启前仍 running 的
      // 标 lost）+ 受理/终态两写点；**不随备份走**（进程瞬时态，换机无恢复语义）
      PersistentStorage.persistProp(PREF_HTTP_TASKS_KEY, '');
      // 代理模式三档：'system' = 跟随系统（默认 = 不写 usingProxy 字段，请求行为与接本键前
      // 逐字节一致）/ 'direct' = 直连 / 'custom' = 自定义地址；非三值读取侧钳 'system'
      //（钳位单源 = AppPreferences 的 clampNetProxyMode）；消费方 =
      // RequestIdentity.applyEffectiveProxy 取值侧现读 + 网络设置页 @StorageLink
      PersistentStorage.persistProp(PREF_NET_PROXY_MODE_KEY, NET_PROXY_MODE_SYSTEM);
      // 自定义代理地址：'host:port' 文本，'' = 未填；解析判据单源 =
      // RequestIdentity.parseNetProxyAddr（UI 校验与取值侧同函数），解析失败钳 system 语义
      PersistentStorage.persistProp(PREF_NET_PROXY_ADDR_KEY, '');
      // 代理协议类型：'http' = HTTP 代理（写 usingProxy）/ 'socks5' = SOCKS5 代理（写
      // usingSocks5Proxy，API 26.0.0 原生字段）；非 socks5 读取侧钳 'http'（钳位单源 =
      // AppPreferences.clampNetProxyType）
      PersistentStorage.persistProp(PREF_NET_PROXY_TYPE_KEY, NET_PROXY_TYPE_HTTP);
      // 代理认证账号：明文偏好随备份走。★ 密码刻意不在偏好——只进 Asset
      //（aic.proxy.password，onCreate 预载进 RequestIdentity 缓存，备份凭据块 #5）
      PersistentStorage.persistProp(PREF_NET_PROXY_USER_KEY, '');
      // 代理绕过列表：多行文本，取值侧 splitNetProxyBypassLines 拆行净化后进 exclusionList
      //（平台原生匹配）
      PersistentStorage.persistProp(PREF_NET_PROXY_BYPASS_KEY, '');
      // 请求日志：true = 记录 HTTP 请求日志（请求头已掩码 / 请求体已截断 / 响应码与耗时 /
      // 错误响应体尾部，存内存环形缓冲不落盘）/ false = 不记录（默认——关态 reqLogBegin
      // 首行早退回空 id，全链零开销）。★ 默认关是有意选择非疏忽：日志含对话内容与请求头，
      // 默认开等于无声扩大隐私面。键单一来源 ReqLog.ets（该件刻意零 import），消费方 =
      // ReqLog.reqLogEnabled 现读 + 请求日志页 @StorageLink 绑定开关行；**刻意不随备份走**
      //（BACKUP_EXCLUDED_PREF_KEYS——换机恢复后静默开启一个记录敏感内容的开关是隐私事故）
      PersistentStorage.persistProp(PREF_REQ_LOG_KEY, false);
      // 记忆域两开关：总开关默认 true + 自动整理默认 false = 新装零请求零注入零回归（助手级
      // 两开关在 DB v20 列默认 1，组合叠加后仍零行为变化）；键与缺省值单一来源 MemoryGen.ets，
      // 消费方 = MemoryPage @StorageLink + MemoryGen 守卫 + ChatSendCtrl.buildMemoryBlock
      PersistentStorage.persistProp(MEMORY_ENABLED_KEY, true);
      PersistentStorage.persistProp(MEMORY_AUTO_KEY, false);
      // 记忆提取模型两键 + 提示词定制键（★ 决明指令取消回退：记忆整理独立可配，两键齐 =
      // 用记忆模型，未配置 = 不整理〔不回退标题模型〕）；'' = 未配置/未定制；键与生效口径
      // 单一来源 MemoryGen.ets
      PersistentStorage.persistProp(MEMORY_PROVIDER_KEY, '');
      PersistentStorage.persistProp(MEMORY_MODEL_KEY, '');
      PersistentStorage.persistProp(MEMORY_PROMPT_KEY, '');
      // 记忆导入提示词定制键：'' = 未定制 = 导入链回退内置 MEMORY_IMPORT_PROMPT_TEMPLATE
      //（清删式恢复默认语义）；保存 = 写全量文本，导入链现读即时生效，单源 MemoryImport.ets
      PersistentStorage.persistProp(MEMORY_IMPORT_PROMPT_KEY, '');
      // 记忆读取方式：'inject' 自动注入（默认）/ 'tool' 按需读取——聊天链不注入改为声明
      // search_memory 工具，主动消息链不受影响；消费方 = MemoryPage 分段卡 + ChatSendCtrl
      PersistentStorage.persistProp(MEMORY_READ_MODE_KEY, MEMORY_READ_MODE_DEFAULT);
      // 记忆优化模型两键 + 提示词定制键：对库内已有记忆做去重与改写，独立于提取模型可配，
      // 两键齐 = 启用，未配置 = 不优化（不回退提取模型——隐性付费优于显性配置）；'' = 未
      // 定制 = 生效内置（清删式回退）；三键与生效口径单一来源 MemoryOpt.ets
      PersistentStorage.persistProp(MEMORY_OPT_PROVIDER_KEY, '');
      PersistentStorage.persistProp(MEMORY_OPT_MODEL_KEY, '');
      PersistentStorage.persistProp(MEMORY_OPT_PROMPT_KEY, '');
      // 联网搜索域四键：当前引擎默认 bing_local + 启用清单默认全开（ALL_SEARCH_ENGINE_IDS
      // 单一来源自注册表派生）+ 引擎配置 JSON 默认空串 = 全默认无配置——不配任何引擎时行为
      // 与旧版一致（默认引擎 bing_local 免 key、抓取本地实现免费，零回归红线）；消费方 =
      // ChatSendCtrl 声明过滤 + ToolTypes 执行器经注册表编排。★ 总开关键退役出注册区
      //（控制面撤除、全局恒开——见 AppPreferences 该域注释）
      PersistentStorage.persistProp(PREF_SEARCH_ENGINE_KEY, 'bing_local');
      PersistentStorage.persistProp(PREF_SEARCH_ENABLED_ENGINES_KEY, ALL_SEARCH_ENGINE_IDS);
      PersistentStorage.persistProp(PREF_SEARCH_ENGINE_CFG_KEY, '');
      // 抓取引擎默认 'local'（本地免费抓取；选 DeepSeek 抓取才走 API——失败/缺钥自动回落本地）
      PersistentStorage.persistProp(PREF_SEARCH_FETCH_ENGINE_KEY, 'local');
      // DeepSeek 官方联网档偏好（DS 全家桶接入批 S1；代决 1 = DS 会话默认走官方搜索）：
      // true = 联网开时由官方服务端执行（默认）/ false = 用户改选自带引擎；唯一 UI 写点 =
      // ChatSessionOverrideCtrl.pickWebEngine 分流。键单一来源 AppPreferences.ets
      PersistentStorage.persistProp(PREF_DS_OFFICIAL_WEB_KEY, true);
      // DeepSeek 文档服务端解析（拍板 8 带开关不默认自动）：false = 文档附件照常本地解析
      //（默认 = 现状零回归）/ true = DS 会话文档附件入列即上传服务端解析（S4 接线）；
      // 设置面 = 会话设置面板「文档解析」行卡（仅 DS 会话渲染）
      PersistentStorage.persistProp(PREF_DS_DOC_SERVER_KEY, false);
      // 二期两键（决明 2026-11-14 拍板）：标题三态缺省 'first'、内容安全审核缺省 false
      // ——缺省真源单点在本注册侧，禁在消费方另写缺省字面量
      PersistentStorage.persistProp(PREF_DS_TITLE_MODE_KEY, 'first');
      PersistentStorage.persistProp(PREF_DS_SAFETY_CHECK_KEY, false);
      // 主动消息五持久键（★插入位置铁律 = 全部既有 persistProp 之后、PREF_LOADED_KEY 置 1
      // 之前——该键是「持久键注册完毕」闸信号，排其后即语义错位）：总开关默认 false + 间隔
      // 档默认 24 小时 + 每日最多默认 1 条 + 静默期上限默认 5 分钟 + 发送时刻滚动数组默认空
      // = 新装零请求零落库零回归；四键与缺省值单一来源 ProactiveConfig.ets、发送时刻键仍归
      // ProactiveGen.ets，消费方 = ProactiveGen 守卫/排程 + ProactivePage @StorageLink 三行；
      // APP_FOREGROUND_KEY 运行态键不持久（前后台双向写）
      PersistentStorage.persistProp(PROACTIVE_ENABLED_KEY, false);
      PersistentStorage.persistProp(PROACTIVE_INTERVAL_HOURS_KEY, PROACTIVE_INTERVAL_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_DAILY_LIMIT_KEY, PROACTIVE_DAILY_LIMIT_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_QUIET_MAX_KEY, PROACTIVE_QUIET_MAX_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_SENT_AT_KEY, [] as number[]);
      // 主动消息未读会话：默认 '' = 无未读；写侧 = ProactiveGen 落库，清除侧 =
      // ChatPage.onPageShown；进排除表（本机未读痕迹不随备份走）
      PersistentStorage.persistProp(PROACTIVE_UNREAD_CONV_KEY, '');
      // 脚本工作台三键（★ 总开关 PREF_CODE_WORKBENCH_KEY 随键退役不再注册——可用性全权随
      // 助手级「脚本工作台」卡）；单源与缺省见各键定义件注释
      PersistentStorage.persistProp(PREF_CODE_WORKBENCH_MODE_KEY, CODE_WORKBENCH_MODE_STANDARD);
      PersistentStorage.persistProp(PREF_CODE_HTTP_WRITE_KEY, false);
      PersistentStorage.persistProp(PREF_CODE_WORKBENCH_ENGINE_KEY, CODE_WORKBENCH_ENGINE_AUTO);
      // 脚本联网预授权域名：{ [owner]: [host,…] }，owner = 助手 id 或 'global'（并集生效）；
      // '' = 全禁（fail-closed）；单源 AppPreferencesHttp.ets
      PersistentStorage.persistProp(PREF_CODE_HTTP_HOSTS_KEY, '');
      // 脚本联网域名请求模式：'allowlist' 缺省 = 现状仅已添加（fail-closed）；'any' 短路桥
      // 第⑤步预授权闸、链内安全闸照常；单源 AppPreferencesHttp.ets
      PersistentStorage.persistProp(PREF_CODE_HTTP_HOST_MODE_KEY, CODE_HTTP_HOST_MODE_ALLOWLIST);
      // Web 服务四键：总开关默认 false = kill-switch（关 = 零端口监听零订阅零行为增量，软
      // 回退面）/ 端口默认 8800 固定（WS 面 = 基数+1 派生不单列键）/ 口令默认 ''（首开启
      // 自动生成 6 位数字码）/ 仅本机档默认 false。键单源 AppPreferencesWeb.ets；消费方 =
      // WebServiceManager（kill-switch 闸 + 启停编排）与 WebServiceSettingsPage 启动卡；
      // enable/port/loopbackOnly 三元数据键随备份走，passcode 口令类敏感值进排除表（换机
      // 重生成）
      PersistentStorage.persistProp(PREF_WEB_SERVICE_ENABLE_KEY, false);
      PersistentStorage.persistProp(PREF_WEB_SERVICE_PORT_KEY, WEB_SERVICE_PORT_DEFAULT);
      PersistentStorage.persistProp(PREF_WEB_SERVICE_PASSCODE_KEY, '');
      PersistentStorage.persistProp(PREF_WEB_SERVICE_LOOPBACK_ONLY_KEY, false);
      // 消息字体三键：正文/代码选择值 + 共享字体库 JSON。键与值域、家族串推导、库解析单一
      // 来源 common/ChatFont.ets（零 import 叶子件）；缺省 'default' 与 '' = 全走系统字体，
      // 存量零回归；消费方 = ChatFontSection（写）+ 消息域 V1 宿主自订阅（经 @Param 下发
      // V2 叶件）
      PersistentStorage.persistProp(PREF_FONT_BODY_KEY, FONT_BODY_DEFAULT);
      PersistentStorage.persistProp(PREF_FONT_CODE_KEY, FONT_CODE_DEFAULT);
      PersistentStorage.persistProp(PREF_FONT_LIB_KEY, '');
      // 字体仅用于会话页：true（默认）= 字体只在会话页生效 / false = 正文档经
      // ApplicationContext.setFont 下发应用级槽位，全局未显式指定 fontFamily 的文字跟随；
      // 消费方 = ChatFontLoader.applyAppFontOnLaunch（启动下发，见下方调用）+ ChatFontSection；
      // 代码字体不随本开关（setFont 单槽位被正文档占用）
      PersistentStorage.persistProp(PREF_FONT_SESSION_ONLY_KEY, true);
      // v1 退役四键（迁移过渡只读，下版本删除）：persistProp 保留只为把磁盘旧值载入
      // AppStorage 供下方迁移读取——归备份排除表（一次性迁移素材不随备份）
      PersistentStorage.persistProp(PREF_FONT_BODY_PATH_KEY, '');
      PersistentStorage.persistProp(PREF_FONT_BODY_NAME_KEY, '');
      PersistentStorage.persistProp(PREF_FONT_CODE_PATH_KEY, '');
      PersistentStorage.persistProp(PREF_FONT_CODE_NAME_KEY, '');
      // v1 单槽位数据一次性迁移：旧路径键非空才执行——并入共享字体库、裸 'custom' 值补 id、
      // 值归一，随后清空旧四键（幂等）；必须在 ensure 注册之前（值先归一再按库注册），细节见
      // ChatFont.ets 迁移条
      migrateLegacyFontSelectionNow();
      // 旧三域审批档 → 默认权限档一次性折算：默认档为空才执行（折算后即写定，正常路径
      // 不再出现空串）；取三域最严值 = 安全默认，用户可在设置页一键改宽。放在 PREF_LOADED
      // 置 1 之前——首帧读档即新三档，不出现「一帧迁移态」。细节见 PermissionMode 头注释
      migrateLegacyApproveModes();
      // 选中档字体按需注册：库文件校验（缺失剔除）+ 选中键归一 + 只注册当前选中档，在
      // PREF_LOADED 置 1 之前——回调触发时页面组件尚未实例化，消息页首帧渲染即有正确字体；
      // 选中档不可用（文件缺失/损坏）时内部复位为默认档，细节见 ChatFontLoader 头注释
      ensureSelectedFontsRegistered();
      // 字体范围全局态下发：开关关闭（全局）时把正文档主族名写入 ApplicationContext.setFont
      // 应用级槽位——在字体注册之后（别名先就绪）、PREF_LOADED 置 1 之前（页面组件尚未
      // 实例化，全局首帧即正确字体）；仅会话页态（默认）内部零动作。官方调用时机约束 =
      // loadContent 完成之后，本回调即该时机
      applyAppFontOnLaunch(this.context);
      // 首启隐私政策同意态：false = 未同意 = 首启弹窗（PrivacyConsentGate 订阅）。注册位置
      // 在 PREF_LOADED_KEY 置 1 之前（页面组件尚未实例化，首帧即读到磁盘真值）；存量用户
      // 迁移判定见下方 migratePrivacyConsentForExistingUsers
      PersistentStorage.persistProp(PREF_PRIVACY_AGREED_KEY, false);
      // 偏好键注册完成标记：全部 persistProp 之后置 1——消费方（启动进入页面的冷启动一次性
      // 读值）订阅本键，键变即代表磁盘值已落 AppStorage，不必赌「注册先于组件实例化」的
      // 未验证时序（语义与风险说明见 AppPreferences.PREF_LOADED_KEY）。★ 例外注记：预置服务
      // 商 seed 标记键（PROVIDER_PRESETS_SEEDED_KEY）的 persistProp 在本置 1 之后——该键自带
      // 独立门闩（notifyPresetSeedKeyRegistered，本回调尾放行），不消费本标记，两闸互不依赖
      AppStorage.setOrCreate<number>(PREF_LOADED_KEY, 1);
      // 预置服务商卡 seed 完成标记：'1' = 已 seed 永不重跑（删卡不回填）。注册后立即放行
      // seed 门闩——此时磁盘值已加载进 AppStorage，seed 侧读标记才可靠（时序设计见
      // ProviderPresetSeed.ets 头注释）
      PersistentStorage.persistProp(PROVIDER_PRESETS_SEEDED_KEY, '');
      notifyPresetSeedKeyRegistered();
      // 存量用户隐私同意迁移：预置 seed 标记已落 '1' 的老设备视为已同意、补写本键（升级不
      // 弹窗）；新装设备此刻标记仍是 ''（seed 链异步未完成）→ 保持未同意 → 首启弹窗。必须在
      // 上一行 persistProp 之后读，否则磁盘 '1' 未进 AppStorage 会误判新装而给老用户弹窗。
      // ★ 标记值由本处传参（键名单源 = 上一行常量，叶子件不自持字面量——首版手写键名写错过
      // 一次，见 PrivacyConsent 注释）
      migratePrivacyConsentForExistingUsers(
        AppStorage.get<string>(PROVIDER_PRESETS_SEEDED_KEY) ?? '');
      // 内置技能 seed 标记键注册完成放行（同款门闩——onCreate 迁移链尾的 ensureBuiltinSkills
      // 读标记前必须等磁盘值加载进 AppStorage，防代数误判重跑迁移）
      notifySkillSeedKeyRegistered();
      // 主动消息冷启动闸放行（ProviderPresetSeed 同款门闩）：onForeground 首拍早于本回调，
      // 总开关键未注册时 onAppForeground 挂起待排——主动消息六键 persistProp 已全部注册，
      // 此处放行补排；时序语义见 ProactiveGen.onAppForeground 注释
      notifyProactiveKeysRegistered();
      // 模型选择对账：把「目标已不存在或已停用」的模型选择清成未选择（功能模型 8 槽 + 助手
      // 绑定 + 会话级覆盖），让「停用/删除即回到未选择、复启不回填」的语义对存量数据与漏清
      // 路径也成立。位置 = 全部 persistProp 注册之后（槽位键磁盘值已进 AppStorage，此处清键
      // 不会被随后注册的磁盘值盖回）；库就绪由 whenReady 等待（initChatDb 在 onCreate 并行
      // 发起，不赌先后来序）。幂等，失败留痕下次启动重试
      whenReady().then((ok: boolean): void => {
        if (!ok) {
          return;
        }
        reconcileModelBindings().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '模型选择对账失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
      });
      // Web 服务冷启动自启补挂：loadContent 回调内 persistProp 已把磁盘值载入 AppStorage
      //（含 prefWebServiceEnable），此处补一次自启——onForeground 首拍可能早于本回调、读到
      // 键未注册的缺省 false；state 守卫保证与前台补挂不重复起服
      this.startWebServiceIfEnabled();
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  // 系统深浅色切换时刷新 AppStorage（dshinhm 同款）：页面资源（resources/dark）由框架自动
  // 切换，@StorageProp('appColorMode') 的组件配色由此驱动。★ 必须用回调参数
  // newConfig.colorMode——this.context.config 回调时可能还是旧值（dshinhm 真机沉淀：用旧值
  // 会致深浅色判断滞后一拍）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onConfigurationUpdate, colorMode: %{public}d', newConfig.colorMode);
    const mode: number = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate<number>('appColorMode', mode);
    // 窗口底色深浅跟随重挂：resourceColor 构造后窗口底色不随系统配置自动重涂
    //（ColorMetrics.autoRefresh 对窗口底色的有效性无文档，不赌）——切换时刻重挂为正，
    // 帧级旧档可接受
    this.applyWindowBackground();
  }

  // 窗口底色对齐 page_bg：系统默认窗口底色为浅 #FFF0F0F0 / 深 #FF1A1A1A，与 page_bg 两档
  // 不同——push 转场新页首帧前、冷启动 loadContent 完成到首帧、分屏/窗口瞬变等露底场景呈现
  // 跨档刺眼白闪。本方法把窗口底色设为 page_bg 资源引用（ColorMetrics.resourceColor(
  // $r(...))，深浅两档由框架按当前 colorMode 自动解析，单源 = resources color.json 两文件，
  // 本件禁 hex 字面量双源）。★ 时机硬约束（@ohos.window.d.ts）——stage 模型必须 loadContent
  // 生效之后调用，调用点在 loadContent 成功回调内（非 onWindowStageCreate 预加载 try 块）；
  // 深浅跟随 = loadContent + onConfigurationUpdate 双点位重挂；每次现取 getMainWindowSync
  // 不持 window 实例引用；失败 hilog 留痕不阻断（fail-open 同族：底色失败只损失本缓解，
  // 无功能链依赖）。★ 自定义壁纸场景如实说明：窗口底色是纯色，露底瞬间用户看到的是 page_bg
  // 色块而非壁纸图——观感从「刺眼白闪」收窄为「同色一闪」不消失（稳态各页 PageBackground
  // 铺满 100% 窗口底色不可见，零回归面）
  private applyWindowBackground(): void {
    if (this.windowStage === null) {
      return;
    }
    try {
      this.windowStage.getMainWindowSync()
        .setWindowBackgroundColor(ColorMetrics.resourceColor($r('app.color.page_bg')));
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'Failed to set window background: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    // 主窗引用置 null（与 onWindowStageCreate 赋值成对——内存红线，防悬空持已销毁窗体）
    this.windowStage = null;
  }

  // Web 服务开机自启挂接：prefWebServiceEnable 持久化，但进程重启后 manager 恒 stopped
  //——开关亮而服务停，点一下只会触发 stop，要点两次才能启动。前台与冷启动加载完成两处补挂：
  // 键真且服务恰停在 stopped 才自动 start（kill-switch 语义不变：默认 false 零监听；
  // starting/running/paused 由既有链负责，不重复动作）
  private startWebServiceIfEnabled(): void {
    if (!isWebServiceEnabled() || webServiceManager.currentState() !== 'stopped') {
      return;
    }
    webServiceManager.start().then((result): void => {
      if (!result.ok) {
        hilog.warn(DOMAIN, 'testTag', 'Web 服务自启失败：%{public}s', result.message);
      }
    }).catch((e: Object): void => {
      hilog.warn(DOMAIN, 'testTag', 'Web 服务自启异常：%{public}s', (e as Error).message);
    });
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 前后台运行态键（非持久——AppStorage.setOrCreate 双向写，主动消息守卫②到点判前台用；
    // 本键只表前后台不表页面）
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_KEY, true);
    // Web 服务回前台恢复：暂停态才动作——先 close 残留双栈再重新 listen（冻结期旧连接对象
    // 复用必报 2301103 Connection aborted）；暂停期间 kill-switch 被关 = 不复活落 stopped；
    // 未运行/运行态零动作。fire-and-forget（恢复失败留痕 hilog 不炸前台回调）
    webServiceManager.resume().catch((e: Object): void => {
      hilog.warn(DOMAIN, 'testTag', 'Web 服务回前台恢复失败：%{public}s', (e as Error).message);
    });
    // 进程重启后的自启补挂（resume 只认 paused；stopped 且键真才走 start）
    this.startWebServiceIfEnabled();
    // 主动消息排程入口（fire-and-forget——总开关关时内部零开销返回）
    onAppForeground();
    // 后台回复通知撤销（拍板：回到前台撤销「正在回复」/完成/中断通知——用户已看到界面，
    // 留着是干扰；通知不在场时零动作）
    chatBgReply.onAppForeground();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_KEY, false);
    // Web 服务退后台暂停：退后台 2s 网络冻结 12s 释放——主动 close 双栈优于被杀；运行态才
    // 动作，server_paused 广播体归 U6 注册进 manager 的 pause 回调位。fire-and-forget
    //（暂停失败留痕 hilog 不炸后台回调）
    webServiceManager.pause().catch((e: Object): void => {
      hilog.warn(DOMAIN, 'testTag', 'Web 服务退后台暂停失败：%{public}s', (e as Error).message);
    });
    // 后台回复「正在回复」通知：有活跃生成且开关开且通知授权在才发（条件发布——没有回复
    // 在跑不该出现任何通知；发布失败静默降级不报错）
    chatBgReply.onAppBackground();
  }
}