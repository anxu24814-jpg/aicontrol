import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY } from '../common/ImmersiveLevel';
import { PASTE_THRESHOLD_DEFAULT, PREF_AUTO_RETRY_KEY, PREF_BG_SESSION_ONLY_KEY, PREF_BIOMETRIC_FACE_KEY, PREF_BROWSE_AUTO_APPROVE_KEY, PREF_CTX_FACTOR_KEY, PREF_HTTP_WRITE_AUTO_APPROVE_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_KEYBOARD_SEND_KEY, PREF_LAUNCH_NEW_CHAT_KEY, PREF_LOADED_KEY, PREF_PASTE_AS_FILE_KEY, PREF_PASTE_AS_FILE_THRESHOLD_KEY, PREF_PRICE_CARD_COLLAPSED_KEY, PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY, PREF_SEARCH_ENGINE_KEY, PREF_SEARCH_SERVICE_ENABLED_KEY, PREF_SESSION_ICON_KEY, PREF_SESSION_TIME_KEY, PREF_STREAM_ENGINE_KEY, PREF_STREAM_FOLLOW_KEY, PREF_TAB_SWITCH_ANIM_KEY, PREF_THINK_EXPAND_KEY } from '../common/AppPreferences';
import { ALL_SEARCH_ENGINE_IDS } from '../common/search/SearchEngineRegistry';
import { EDIT_BLUR_PCT_KEY, EDIT_CROP_STATE_KEY, EDIT_MASK_PCT_KEY } from '../common/ImageEditUtil';
import { PREF_REQ_LOG_KEY } from '../common/ReqLog';
import { RECENT_USE_KEY, SEARCH_HISTORY_KEY } from '../common/SettingSearch';
import { SESSION_RECENT_CONV_KEY, SESSION_SEARCH_HISTORY_KEY } from '../common/SessionSearch';
import { ensureCrashWatcher, pruneLogFiles, teardownCrashWatcher } from '../components/LogPageDataSource';
import { sweepAttachDir } from '../common/AttachmentUtil';
import { sweepExportTemp } from '../common/store/ExportImport';
import { initChatDb, sharedRdbStore } from '../common/store/ChatDb';
import { initAttachmentStore, reconcileAttachments } from '../common/store/AttachmentDb';
import { ensureProvidersMigrated } from '../common/store/ProviderDb';
import { migrateProviderKeyPools } from '../common/store/ProviderKeyDb';
import { ensurePromptGlobal } from '../common/store/PromptTemplateDb';
import { ensureBuiltinSkills, notifySkillSeedKeyRegistered } from '../common/store/SkillDb';
import { SKILL_BUILTIN_SEEDED_KEY, SKILL_PENDING_JOIN_KEY } from '../common/SkillBuiltinDefs';
import { ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, CONSOLE_TOOLS_SEEDED_KEY,
  ensureConsoleAssistant, ensureDefaultAssistant, notifyConsoleToolsKeyRegistered } from '../common/store/AssistantDb';
import { DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY,
  OCR_ENABLED_KEY, OCR_ENGINE_KEY, OCR_MODEL_KEY, OCR_PREFER_SYSTEM_KEY, OCR_PROVIDER_KEY,
  SUGGEST_ENABLED_KEY, SUGGEST_MODEL_KEY, SUGGEST_PROVIDER_KEY,
  TITLE_MODEL_KEY, TITLE_PROVIDER_KEY } from '../common/store/ProviderDb';
import { ocrAttachContext } from '../common/OcrEngine';
import { OCR_PROMPT_KEY } from '../common/providers/OcrVisionApi';
import { TITLE_PROMPT_KEY } from '../common/TitleGen';
import { SUGGEST_PROMPT_KEY } from '../common/SuggestGen';
import { MEMORY_AUTO_KEY, MEMORY_ENABLED_KEY, MEMORY_MODEL_KEY, MEMORY_PROMPT_KEY,
  MEMORY_PROVIDER_KEY, MEMORY_READ_MODE_DEFAULT, MEMORY_READ_MODE_KEY } from '../common/MemoryGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROMPT_KEY,
  MEMORY_OPT_PROVIDER_KEY } from '../common/MemoryOpt';
import { MEMORY_IMPORT_PROMPT_KEY } from '../common/MemoryImport';
import { COMPRESS_MODEL_KEY, COMPRESS_PROMPT_KEY, COMPRESS_PROVIDER_KEY } from '../common/CompressGen';
import {
  APP_FOREGROUND_KEY, notifyProactiveKeysRegistered, onAppForeground,
  PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY, PROACTIVE_ENABLED_KEY,
  PROACTIVE_INTERVAL_DEFAULT, PROACTIVE_INTERVAL_HOURS_KEY,
  PROACTIVE_QUIET_MAX_DEFAULT, PROACTIVE_QUIET_MAX_KEY, PROACTIVE_SENT_AT_KEY,
  PROACTIVE_UNREAD_CONV_KEY
} from '../common/ProactiveGen';
import { notifyPresetSeedKeyRegistered, PROVIDER_PRESETS_SEEDED_KEY, seedProviderPresets } from '../common/store/ProviderPresetSeed';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 崩溃事件订阅（M3 拍板 6，与 onDestroy 注销成对——坑33 铁律）：进程级注册，崩溃事件
    // 在进程全程被捕获（含日志页未打开时段）；日志页刷新时经 getCrashHolder 共享句柄
    // takeNext 拉取（单例见 LogPageDataSource.ets）。hiAppEvent 全局 API 不依赖 UI 上下文
    ensureCrashWatcher();
    // 日志沙箱落盘常开（2026-09-04 决明拍板）：进程级开启 PRIVATE_SANDBOX_WITH_CONSOLE
    //（@since 26.0.0，本地 d.ts 实锤）——全生命周期日志（含 W/E/F 报错与 INFO 上下文）
    // 落盘到应用私有沙箱（getOutputDir()），出问题后日志页刷新即可读到事发日志（此前
    // 页面级开关导致事发日志不落盘、抓不到）；WITH_CONSOLE 保留控制台输出（DevEco 照常
    // 可见）。启动即自检修剪一次（pruneLogFiles：超 2MB 从最旧文件删起，防堆积——进日志页
    // 还会再自检一次，见 LogPage.aboutToAppear）；失败仅打日志不阻断启动（P0-1）
    try {
      hilog.setOutputType(hilog.OutputType.PRIVATE_SANDBOX_WITH_CONSOLE);
      pruneLogFiles();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '日志落盘初始化失败：%{public}s', (err as Error).message);
    }
    // 附件缓存清扫（2026-08-31 附件上传：crash/页面异常退出残留副本的兜底清理——
    // cacheDir/attachments 整目录扫删；启动时一次，残留量有界 ≤ 附件上限，非轮询）
    sweepAttachDir(this.context);
    // 导入导出临时产物清扫（2026-09-03 第三批③：export/backup/download 残留兜底——
    // ExportImport.ets 注释口径「EntryAbility onCreate 调一次」；★ 2026-09-03 自检
    // 观察⑨ 自 DataSyncPage.aboutToAppear 迁至此，与 sweepAttachDir 并列——启动即清，
    // 残留不再等下次进「数据与同步」页才清）
    sweepExportTemp(this.context);
    // 附件元数据域 ctx 捕获（2026-09-09 附件落盘第一轮）：级联删文件/收敛拼 filesDir
    // 前缀用——先于任何附件文件操作调用（initChatDb 迁移链本身不触附件文件操作，但在
    // 收敛发起前就位即可）
    initAttachmentStore(this.context);
    // RDB 异步初始化（任务书红线：EntryAbility 阶段发起；UI 经 whenReady() 等待，未就绪
    // 禁发送，禁在 UI 构建函数里同步等库）。初始化内含 streaming→error 中断恢复。
    // 2026-08-30 服务商管理域：初始化后接遗留单连接迁移（providers 空表时把 v1 Asset 连接
    // 导入首服务商并设为当前——幂等，失败打日志下次启动重试）。
    // 2026-08-30 多 Key 池：再接 v2 单 key 资产 → 池首条目搬运（池无行且旧资产在才搬，
    // 迁后删旧条目——幂等；失败按家打日志下次启动重试）
    initChatDb(this.context).then((ok: boolean): void => {
      if (!ok) {
        hilog.error(DOMAIN, 'testTag', 'ChatDb 初始化失败——发送功能将被禁用');
        return;
      }
      // 附件库盘一致性收敛（2026-09-09 附件落盘第一轮）：孤儿行删行 + 孤儿文件删文件
      //（「行在文件不在」保留行——AttachmentDb 头注释口径）；fire-and-forget 不阻塞首帧
      //（一次有界全表查询 + 一次目录列举，非轮询），失败留痕下次启动再收敛
      reconcileAttachments(this.context, sharedRdbStore()).catch((e: Object): void => {
        hilog.error(DOMAIN, 'testTag', '附件一致性收敛失败（下次启动重试）：%{public}s',
          (e as Error).message);
      });
      ensureProvidersMigrated().then((): void => {
        migrateProviderKeyPools();
        // 系统提示词行兜底（2026-08-30 提示词注入起；★ 2026-08-31 内置化：无行插内置内容
        // 行 / 存量空内容行填充内置——可更改可重置；幂等，失败打日志下次启动重试——注入
        // 解析侧对无全局行另有 GLOBAL_EMPTY_ROW 占位兜底）
        ensurePromptGlobal().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '提示词系统提示词兜底失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 内置默认助手兜底（2026-09-01 反馈轮 2：助手页恒留一张内置默认卡禁删——无行插
        // 「默认助手」空提示词行；幂等，失败下次启动重试）
        ensureDefaultAssistant().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '默认助手兜底失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 内置控制台助手兜底（2026-09-05 控制台助手：无行插「控制台助手」行——prompt 恒 ''
        // 读时联结内置路由提示词、tools 显式列；存量用户升级首启自动获得；幂等，失败下次
        // 启动重试）
        ensureConsoleAssistant().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '控制台助手兜底失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 内置技能 seed 与升代（2026-09-13 单条 seed；2026-09-19 内置技能首批笔扩为定义单源
        // SkillBuiltinDefs 四条 + 代数标记升代——无行才插、标记落后才迁移〔内容刷新/排前/
        // 默认助手启用〕；source='builtin' 禁删禁改守卫在 SkillDb 首行；失败下次启动重试）
        ensureBuiltinSkills().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '内置技能 seed 失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
        // 预置服务商卡 seed（2026-08-31 二期：12 家 3 启 9 停一次性幂等落库；fire-and-
        // forget 不阻塞首帧。函数体自带注册门闩——标记键 persistProp 注册完成（下方
        // loadContent 回调 notify）后才读标记，防磁盘 '1' 未加载误判重跑回填删卡）
        seedProviderPresets().catch((e: Object): void => {
          hilog.error(DOMAIN, 'testTag', '预置服务商卡 seed 失败（下次启动重试）：%{public}s',
            (e as Error).message);
        });
      });
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 崩溃订阅注销（与 onCreate 的 ensureCrashWatcher 成对——addWatcher↔removeWatcher
    // 红线；进程即将销毁，一并置空防悬空句柄）
    teardownCrashWatcher();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      // 窗口全屏布局（2026-08-29 反馈轮 4 随一级页沉浸光感切换：HDS 标题栏簇的配套前提，
      // dshinhm 同款配方——此前非全屏定稿作废，见 nav/HomeNavigation.ets 头注释与
      // MEMORY_DETAIL.md 坑1/坑2 轮 4 补记）：布局延伸到状态栏/导航条下，避让全靠页面内
      // 显式参数（标题栏 avoidLayoutSafeArea / 页签 barBottomMargin / 页面 topPad·bottomPad）
      windowStage.getMainWindowSync().setWindowLayoutFullScreen(true);
      // 键盘避让模式显式声明（dshinhm 2026-08-22 沉淀：系统默认行为随版本漂移，必须显式）：
      // RESIZE_WITH_CARET = 内容区压缩 + 随光标微调，官方《键盘适配完整指南》推荐 RESIZE
      // 家族——聊天页形态（上列表 + 底部输入栏）正是该档适用场景；OFFSET 会把输入栏推出屏、
      // NONE 不避让，均不选
      windowStage.getMainWindowSync().getUIContext()
        .setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
      // 当前颜色模式写入 AppStorage（2026-08-29 M2c 接线，dshinhm 同款）：页面 @StorageProp
      // ('appColorMode') 响应式获取——此前无人写键，深色模式下卡底/胶囊配色停在浅色档
      //（BLOCKED.md 挂账项，本轮关闭）；深浅色切换跟随见 onConfigurationUpdate
      const mode: number = this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      AppStorage.setOrCreate<number>('appColorMode', mode);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'Failed to init fullscreen/keyboard: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 沉浸光感总档键 + 搜索历史/最近使用两键持久化注册（2026-08-29 M2c，dshinhm 同款；
      // ★ 2026-09-12 分项退役：原「悬浮底栏」「其他控件」两分项键 persistProp 删除——
      // 两处档位恒跟随总档，见 ImmersiveLevel.ets 头注释；已存用户的分项持久化值随键弃用
      // 自然失效，无迁移必要）：★ 必须在 loadContent 成功回调内——PersistentStorage 与
      // UI 实例关联，早于该时机会导致写入不落盘、重启恢复默认值（dshinhm 坑17，官方文档
      // 明示）；回调触发时页面组件尚未实例化，不与 @StorageProp/@StorageLink 初始化抢序。
      // 注册后 AppStorage.set 自动持久化，重启保留
      PersistentStorage.persistProp(IMMERSIVE_LEVEL_KEY, 0);
      // 内容区光感新规范开关（2026-09-03 决明拍板，2026-09-07 更名）：true = 受影响内容区
      // 组件按华为新光感规范走官方标准形态（默认开——新规范下内容区材质不生效，默认走新
      // 效果）；false = 保留原材质光感（对照验收/回滚）；消费侧双态见 common/ImmersiveLevel.ets
      // fallbackButton* 函数族与 components/SegmentBar.ets，外观显示页开关卡 @StorageLink
      // 写入；已存用户值优先（persistProp 语义）
      PersistentStorage.persistProp(CONTENT_FALLBACK_KEY, true);
      // 自定义背景图（2026-08-29 M3，dshinhm 同款）：「外观显示」页「背景」面板写入沙箱
      // file:// URI，PageBackground @StorageProp 消费；空 = 默认官方灰底
      PersistentStorage.persistProp('pageBg', '');
      // 编辑图片参数记忆三键（2026-08-29 M3，dshinhm 同款）：模糊/遮罩百分比 + 裁剪状态
      // [zoomPct, tx, ty]——调整页保存成功时写入，重进编辑页恢复（键语义见 ImageEditUtil.ets）
      PersistentStorage.persistProp(EDIT_BLUR_PCT_KEY, 0);
      PersistentStorage.persistProp(EDIT_MASK_PCT_KEY, 0);
      PersistentStorage.persistProp(EDIT_CROP_STATE_KEY, [0, 0, 0]);
      // 设置项搜索历史/最近使用（2026-08-29 M2c 任务 4，dshinhm 同款）：string[] 一维数组
      // 可持久化（对象数组禁止）；上限截断在 SettingSearch 读写两侧收敛，有界
      PersistentStorage.persistProp(SEARCH_HISTORY_KEY, [] as string[]);
      PersistentStorage.persistProp(RECENT_USE_KEY, [] as string[]);
      // 会话搜索历史/最近进入（2026-09-08 会话搜索记录区，机制对齐设置搜索五环）：键语义
      // 与有界口径见 common/SessionSearch.ets 头注释；同 string[] 一维可持久化
      PersistentStorage.persistProp(SESSION_SEARCH_HISTORY_KEY, [] as string[]);
      PersistentStorage.persistProp(SESSION_RECENT_CONV_KEY, [] as string[]);
      // 当前服务商/模型两键（2026-08-30 服务商管理域）：聊天页连接解析的持久输入——
      // 模型选择面板/删除失效路径写入；string 一维标量可持久化，解析侧对失效值自动兜底
      // 全局默认模型两键（2026-09-05 功能模型页「默认模型」）：发送链四级兜底第③级来源
      //（会话页所选 > 助手绑定 > 全局默认 > 首个启用模型）；'' = 未设置；string 一维标量
      // 可持久化，解析侧对失效值自动降级
      PersistentStorage.persistProp(DEFAULT_PROVIDER_KEY, '');
      PersistentStorage.persistProp(DEFAULT_MODEL_KEY, '');
      // 标题生成两键（2026-09-05 功能模型页「标题生成」卡）：AI 会话标题生成的
      // 显式开关——'' = 未设置 = 功能未启用静默不生成（决明二次拍板，无会话连接兜底）；
      // 解析链独立单级验证（TitleGen），不碰 active/default 四键
      PersistentStorage.persistProp(TITLE_PROVIDER_KEY, '');
      PersistentStorage.persistProp(TITLE_MODEL_KEY, '');
      // OCR 键（2026-09-15 附件 OCR 二期·设置面笔）：总开关缺省 'true'（开——读侧
      // OcrEngine.ocrEnabled 对未写仍兜底开，注册保跨重启）；★ 2026-09-16 系统识别开关化
      // +偏好键（缺省 '' = 未写 = 按旧口径推导——老用户升级零行为变化）；★★ 同日内置引擎
      // 落地 +引擎三态键（缺省 '' = 未写 = 按旧口径推导，解析单源 ProviderDb.resolveOcrEngine；
      // 偏好键自此退役为只读兜底）；已选模型两键 '' = 未选；★ 2026-09-17 识别提示词定制键
      // （'' = 未定制 = 识别链回退内置 OCR_PROMPT_TEMPLATE，清删式恢复默认语义；保存 = 写
      // 全量文本，识别链现读即时生效——与下方标题提示词键同款口径，单源 OcrVisionApi）
      PersistentStorage.persistProp(OCR_ENABLED_KEY, 'true');
      PersistentStorage.persistProp(OCR_ENGINE_KEY, '');
      PersistentStorage.persistProp(OCR_PREFER_SYSTEM_KEY, '');
      PersistentStorage.persistProp(OCR_PROVIDER_KEY, '');
      PersistentStorage.persistProp(OCR_MODEL_KEY, '');
      PersistentStorage.persistProp(OCR_PROMPT_KEY, '');
      // 内置识别引擎的资源管理器注入（2026-09-16 方案-内置PaddleOCR §3.3）：三模型与字典
      // 在 rawfile，common 层拿不到 UIContext——能力上下文是应用级单一真源，与本处 persistProp
      // 注册同属组合根职责；引擎本身懒加载（首次识别才读模型，见 OcrPaddle 头注释）
      ocrAttachContext(this.context);
      // 标题生成提示词定制（2026-09-05 开放编辑）：'' = 未定制 = 生成链回退内置
      // TITLE_PROMPT_TEMPLATE（清删式恢复默认语义）；保存 = 写全量文本，生成链现读即时生效
      PersistentStorage.persistProp(TITLE_PROMPT_KEY, '');
      // 推荐问题三键 + 提示词定制键（2026-09-19 推荐问题功能，任务书-推荐问题-20260919；
      // TITLE_* 同位）：总开关默认 **false 关**（BYOK 成本敏感 + ChatGPT 无开关扰人教训，
      // 每轮多一次请求由用户显式授权——决策 1）；已选模型两键 '' = 未配置 = 功能未启用
      // 零请求（照标题生成拍板，无兜底不回退，SuggestGen 守卫序单级验证）；
      // suggestPrompt '' = 未定制 = 生成链回退内置 SUGGEST_PROMPT_TEMPLATE（清删式恢复默认
      // 语义，保存 = 写全量文本，生成链现读即时生效——与上方标题提示词键同款口径，
      // 单源 SuggestGen）
      PersistentStorage.persistProp(SUGGEST_ENABLED_KEY, false);
      PersistentStorage.persistProp(SUGGEST_PROVIDER_KEY, '');
      PersistentStorage.persistProp(SUGGEST_MODEL_KEY, '');
      PersistentStorage.persistProp(SUGGEST_PROMPT_KEY, '');
      // 上下文压缩模型两键 + 提示词定制键（2026-09-23 任务书-上下文压缩-20260923）：两键
      // '' = 未配置 = 生成时**回退当前会话的模型**（与 suggest「未配置即停」语义不同——本槽
      // 有回退，任务书拍板 8）；compressPrompt '' = 未定制 = 生成链回退内置
      // COMPRESS_PROMPT_CONTENT（清删式恢复默认语义，与上方标题提示词键同款口径，单源 CompressGen）
      PersistentStorage.persistProp(COMPRESS_PROVIDER_KEY, '');
      PersistentStorage.persistProp(COMPRESS_MODEL_KEY, '');
      PersistentStorage.persistProp(COMPRESS_PROMPT_KEY, '');
      // 当前助手（2026-09-01 会话历史绑定助手）：助手页签点卡切换的持久选择——历史列表
      // 过滤/新会话落行绑定/注入链新会话回退三处消费；缺省 = 内置默认助手
      PersistentStorage.persistProp(ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID);
      // 控制台助手工具 seed 检查标记（2026-09-05 迁移复活循环修复方案 B）：'' = 未检查 /
      // '1' = 检查已完成——标记只挡 seed 迁移重跑（用户关闭新工具后列值恰回旧串的场景），
      // 不挡无行兜底插入；判据与失败不写标记语义见 AssistantDb.ensureConsoleAssistant 注释
      PersistentStorage.persistProp(CONSOLE_TOOLS_SEEDED_KEY, '');
      // 内置技能 seed 升代标记（2026-09-19 内置技能首批笔）：'' = 从未迁移 / 'N' = 已迁移到
      // 第 N 代——标记只挡升代迁移重跑（只升不降，语义见 SkillBuiltinDefs.ets 头注释），
      // 不挡无行兜底插入；判据与失败不推标记语义见 SkillDb.ensureBuiltinSkills 节头注释
      PersistentStorage.persistProp(SKILL_BUILTIN_SEEDED_KEY, '');
      // 待并入登记（2026-09-20 D5-3 修复）：JSON 数组串 = 本机 seed 插入、自动并入尚未落定
      // 的内置 id——超限跳过/抛错时凭它下次启动补跑（语义见 SkillDb.flushPendingAutoEnable）
      PersistentStorage.persistProp(SKILL_PENDING_JOIN_KEY, '[]');
      // 偏好设置键（2026-09-01 偏好设置页）：默认展开思考——键与缺省值单一来源
      // AppPreferences.ets，消费方 = ChatThinkingBlock 创建期读初始态；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_THINK_EXPAND_KEY, false);
      // 键盘发送开关（2026-09-03 偏好设置页第 4 项）：false = 换行键（默认）/ true = 发送键；
      // 消费方 = ChatInputBar @StorageProp 订阅；已存用户值优先（persistProp 语义）
      PersistentStorage.persistProp(PREF_KEYBOARD_SEND_KEY, false);
      // 流式引擎选择（2026-09-02 Cube 动效渲染层移植主工程）：false = 原生 / true = Cube
      // 实验引擎；默认 true（真机验收后决明拍板切换）——已存用户值优先（persistProp 语义），
      // 验收期拨过开关的存量安装不受影响；偏好页开关写、ChatSendCtrl 分流点现读
      PersistentStorage.persistProp(PREF_STREAM_ENGINE_KEY, true);
      // 流式输出自动跟随（2026-09-02 偏好设置页）：true = 输出自动滚底（现状）/ false =
      // 停在当前位置；默认 true 行为不变，已存用户值优先（persistProp 语义）；偏好页开关
      // 写、ChatFollowController.maybeFollow 现读（现读 = 切换即时生效）
      PersistentStorage.persistProp(PREF_STREAM_FOLLOW_KEY, true);
      // 会话页屏幕常亮（2026-09-04 偏好设置页第 5 项）：true = 进会话页设窗口常亮（退出
      // 复位）/ false = 系统息屏（默认）；键与读值封装单一来源 AppPreferences.ets，
      // 消费方 = ChatPage 生命周期；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_KEEP_SCREEN_ON_KEY, false);
      // 会话时间显示（2026-09-04 偏好设置页第 6 项）：true = 会话列表卡片显示最后消息
      // 时间（默认，现状）/ false = 只隐藏显示（记录照常落盘）；消费方 = ChatSessionList
      // SessionCardItem @StorageProp 自订阅；已存用户值优先（persistProp 语义）
      PersistentStorage.persistProp(PREF_SESSION_TIME_KEY, true);
      // 会话图标显示（2026-09-19 偏好设置页·阅读与会话组第 3 行）：true = 会话列表卡片
      // 显示左侧消息图标（默认，现状）/ false = 图标不显示，标题左移（纯显示层）；
      // 消费方 = ChatSessionList SessionCardItem @StorageProp 自订阅；已存用户值优先
      //（persistProp 语义）
      PersistentStorage.persistProp(PREF_SESSION_ICON_KEY, true);
      // 生物识别方式（2026-09-05 偏好设置页第 8 项）：true = 人脸（默认，真机实测链路已通）
      // / false = 指纹；消费方 = BiometricGate 认证发起时现读；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_BIOMETRIC_FACE_KEY, true);
      // 背景仅用于会话页（2026-09-05 背景面板新增开关）：true = 自定义背景只在会话页显示
      // / false = 全应用生效（默认，现状零回归）；消费方 = PageBackground @StorageProp
      // 订阅 + sessionPage 参数组合判定；键与缺省值单一来源 AppPreferences.ets
      PersistentStorage.persistProp(PREF_BG_SESSION_ONLY_KEY, false);
      // 页签切换动画（2026-09-08 偏好设置页第 9 项）：true = 底部页签点击切换带横向滑动
      // 动画 / false = 点按直达无过渡（默认 true = 当日决明拍板开回的现状零回归）；
      // 消费方 = HomeNavigation @StorageProp 订阅；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_TAB_SWITCH_ANIM_KEY, true);
      // 启动进入页面（2026-09-08 偏好设置页第 10 项）：true = 冷启动直接进入新对话 / false =
      // 进入对话一级页（会话列表，默认 = 现状零回归）；键与缺省值单一来源 AppPreferences.ets，
      // 消费方 = HomeNavigation.aboutToAppear 现读；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_LAUNCH_NEW_CHAT_KEY, false);
      // 价格卡收起态（2026-09-17 价格卡折叠记忆笔，决明报障「收起状态保存后无法记忆」）：
      // true = 模型编辑页价格卡默认收起为短卡 / false = 默认展开（存量行为零回归）；
      // 键单一来源 AppPreferences.ets，**不在偏好设置页暴露**——消费方 = ModelPriceCard
      // @StorageLink 双向绑定（用户点标题行收起即写即落盘，无需点保存）；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_PRICE_CARD_COLLAPSED_KEY, false);
      // 会话上下文用量·校准系数（2026-09-17 方案-会话上下文用量）：JSON 数组
      // [{modelId, factor}] 最近使用在前、上限 20 条；默认 '' = 空 = 各模型纯估算（k = 1）。
      // 键与读写封装单一来源 AppPreferences.ets；写侧唯一 = 发送链锚点校准点、读侧 = 会话页
      // 活算；随偏好备份走（BACKUP_PREF_KEYS 通用偏好段）。字符串键可持久化
      PersistentStorage.persistProp(PREF_CTX_FACTOR_KEY, '');
      // 浏览高危操作自动通过（2026-09-18 浏览高危确认降压阀笔）：true = browse_act 高危动作
      // 不弹确认卡直接执行 / false = 每次弹卡征求同意（默认 = 现状零回归）；键与读值封装
      // 单一来源 AppPreferences.ets，消费方 = ToolBrowseAct 预检早退 + 执行器高危分支现读
      //（切换即时生效，下一个动作按新值）；随偏好备份走（BACKUP_PREF_KEYS 通用偏好段）；
      // boolean 标量可持久化
      PersistentStorage.persistProp(PREF_BROWSE_AUTO_APPROVE_KEY, false);
      // HTTP 写操作自动通过（2026-09-20 HTTP 请求独立域笔）：true = http_request 写方法
      // 不弹确认卡直接发送 / false = 每次弹卡征求同意（默认 = 现状零回归）；键与读值封装
      // 单一来源 AppPreferences.ets，消费方 = ToolHttp 预检首行现读（切换即时生效，下一个
      // 请求按新值；执行器侧无第二道判据——本件不带批准戳）；随偏好备份走
      //（BACKUP_PREF_KEYS 通用偏好段）；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_HTTP_WRITE_AUTO_APPROVE_KEY, false);
      // 网络自动重试（2026-09-22 聊天自动重试笔）：true = 网络原因失败且本轮零产出时自动
      // 退避重发（最多 3 次，2/4/8 秒）/ false = 不自动重试（手动点底栏重试键的现状）。
      // ★ 默认 true = 有意选择非疏忽（理由见 AppPreferences 键注释）；键与读值封装单一来源
      // AppPreferences.ets，消费方 = ChatAutoRetryCtrl 判据；随偏好备份走
      //（BACKUP_PREF_KEYS 通用偏好段）；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_AUTO_RETRY_KEY, true);
      // 粘贴长文本转文件（2026-09-23 粘贴长文本转文件笔）：开关 true = 粘贴文本达到阈值时
      // 转成 .txt 附件挂进待发附件条 / false = 任何粘贴照常插入（默认 true = 有意选择
      // 非疏忽，理由见 AppPreferences 键注释）；阈值默认 2000 字符，取值 1000~20000 步进
      // 500（域与钳位单源 = AppPreferences 的 PASTE_THRESHOLD_* / clampPasteThreshold）。
      // 两键消费方 = ChatInputBar @StorageProp 自订阅；随偏好备份走
      //（BACKUP_PREF_KEYS 通用偏好段）；boolean 与 number 标量皆可持久化
      PersistentStorage.persistProp(PREF_PASTE_AS_FILE_KEY, true);
      PersistentStorage.persistProp(PREF_PASTE_AS_FILE_THRESHOLD_KEY, PASTE_THRESHOLD_DEFAULT);
      // 请求日志（2026-09-23 请求日志笔）：true = 记录 HTTP 请求日志（请求头已掩码 / 请求体
      // 已截断 / 响应码与耗时 / 错误响应体尾部，存内存环形缓冲不落盘）/ false = 不记录
      //（默认 = 现状零回归——关态 reqLogBegin 首行早退回空 id，全链零开销）。★ 默认关是
      // 有意选择非疏忽：日志含对话内容与请求头，默认开等于无声扩大隐私面。键单一来源
      // ReqLog.ets（该件刻意零 import），消费方 = ReqLog.reqLogEnabled 现读 + 请求日志页
      // @StorageLink 绑定开关行；**刻意不随备份走**（BACKUP_EXCLUDED_PREF_KEYS——换机恢复
      // 后静默开启一个记录敏感内容的开关是隐私事故）；boolean 标量可持久化
      PersistentStorage.persistProp(PREF_REQ_LOG_KEY, false);
      // 记忆域两开关（2026-09-08 记忆域，任务书-记忆域-20260908）：总开关默认 true +
      // 自动整理默认 false = 新装零请求零注入零回归（助手级两开关在 DB v20 列默认 1，
      // 组合叠加后仍零行为变化）；键与缺省值单一来源 MemoryGen.ets，消费方 = MemoryPage
      // @StorageLink（记忆页两开关行）+ MemoryGen 守卫 + ChatSendCtrl.buildMemoryBlock
      PersistentStorage.persistProp(MEMORY_ENABLED_KEY, true);
      PersistentStorage.persistProp(MEMORY_AUTO_KEY, false);
      // 记忆提取模型两键 + 提示词定制键（★ 2026-09-08 先行笔 + 同日决明指令取消回退：
      // 记忆整理独立可配，两键齐 = 用记忆模型，未配置 = 不整理（不回退标题模型）；
      // '' = 未配置/未定制；键与生效口径单一来源 MemoryGen.ets，消费方 = MemoryGen 守卫
      // + 记忆页「立即整理」前置 toast + FunctionalModelPage「记忆提取」卡）
      PersistentStorage.persistProp(MEMORY_PROVIDER_KEY, '');
      PersistentStorage.persistProp(MEMORY_MODEL_KEY, '');
      PersistentStorage.persistProp(MEMORY_PROMPT_KEY, '');
      // 记忆导入提示词定制键（2026-09-22 记忆导入笔）：'' = 未定制 = 导入链回退内置
      // MEMORY_IMPORT_PROMPT_TEMPLATE（清删式恢复默认语义）；保存 = 写全量文本，导入链现读
      // 即时生效——与上方 memoryPrompt 同款口径，单源 MemoryImport.ets
      PersistentStorage.persistProp(MEMORY_IMPORT_PROMPT_KEY, '');
      // 记忆读取方式（2026-09-13 记忆按需读取笔）：'inject' 自动注入（默认 = 现状零回归）/
      // 'tool' 按需读取——聊天链不注入改为声明 search_memory 工具，主动消息链不受影响；
      // 键与缺省值单一来源 MemoryGen.ets，消费方 = MemoryPage 分段卡 + ChatSendCtrl；
      // 随偏好备份走（BACKUP_PREF_KEYS 记忆域）
      PersistentStorage.persistProp(MEMORY_READ_MODE_KEY, MEMORY_READ_MODE_DEFAULT);
      // 记忆优化模型两键 + 提示词定制键（★ 2026-09-11「记忆优化模型」二期：对库内已有记忆
      // 做去重与改写，独立于提取模型可配，两键齐 = 启用，未配置 = 不优化（不回退提取模型
      // ——隐性付费优于显性配置）；★ 同日二期收尾开放提示词编辑，'' = 未定制 = 生效内置
      // （清删式回退）；三键与生效口径单一来源 MemoryOpt.ets，消费方 = MemoryOpt 守卫与
      // 渲染 + 记忆页「优化记忆」前置 toast + FunctionalModelPage「记忆优化」卡）
      PersistentStorage.persistProp(MEMORY_OPT_PROVIDER_KEY, '');
      PersistentStorage.persistProp(MEMORY_OPT_MODEL_KEY, '');
      PersistentStorage.persistProp(MEMORY_OPT_PROMPT_KEY, '');
      // 联网搜索域四键（2026-09-10 多引擎一期）：总开关默认 true + 当前引擎默认 bing_local
      // + 启用清单默认全开（ALL_SEARCH_ENGINE_IDS 单一来源自注册表派生）+ 引擎配置 JSON
      // 默认空串 = 全默认无配置——四键同默认即「不配任何东西」时行为与旧版逐字节一致
      //（零回归红线）；消费方 = ChatSendCtrl 声明过滤 + ToolTypes 执行器经注册表编排
      PersistentStorage.persistProp(PREF_SEARCH_SERVICE_ENABLED_KEY, true);
      PersistentStorage.persistProp(PREF_SEARCH_ENGINE_KEY, 'bing_local');
      PersistentStorage.persistProp(PREF_SEARCH_ENABLED_ENGINES_KEY, ALL_SEARCH_ENGINE_IDS);
      PersistentStorage.persistProp(PREF_SEARCH_ENGINE_CFG_KEY, '');
      // 主动消息五持久键（2026-09-12 主动消息第一笔「触发链底层」；★插入位置铁律 =
      // 全部既有 persistProp 之后、PREF_LOADED_KEY 置 1 之前——该键是「持久键注册完毕」
      // 闸信号，排其后即语义错位，任务书 §1.3）：总开关默认 false + 间隔档默认 24 小时 +
      // 每日最多默认 1 条 + 静默期上限默认 5 分钟〔2026-09-13 静默期滑轨笔〕+ 发送时刻
      // 滚动数组默认空 = 新装零请求零落库零回归；键与缺省值单一来源 ProactiveGen.ets，
      // 消费方 = ProactiveGen 守卫/排程 + ProactivePage @StorageLink 三行；
      // APP_FOREGROUND_KEY 运行态键不持久（前后台双向写）
      PersistentStorage.persistProp(PROACTIVE_ENABLED_KEY, false);
      PersistentStorage.persistProp(PROACTIVE_INTERVAL_HOURS_KEY, PROACTIVE_INTERVAL_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_DAILY_LIMIT_KEY, PROACTIVE_DAILY_LIMIT_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_QUIET_MAX_KEY, PROACTIVE_QUIET_MAX_DEFAULT);
      PersistentStorage.persistProp(PROACTIVE_SENT_AT_KEY, [] as number[]);
      // 主动消息未读会话（2026-09-12 主动消息第二笔「呈现层」）：默认 '' = 无未读；写侧 =
      // ProactiveGen 落库，清除侧 = ChatPage.onPageShown 进会话页；进 AppPreferences 排除表
      //（本机未读痕迹不随备份走）。横幅/命令两键为运行态（AppStorage 不 persist）不在此区
      PersistentStorage.persistProp(PROACTIVE_UNREAD_CONV_KEY, '');
      // 偏好键注册完成标记（2026-09-08 自检轮）：全部 persistProp 之后置 1——消费方（启动
      // 进入页面的冷启动一次性读值）订阅本键，键变即代表磁盘值已落 AppStorage，不必赌
      // 「注册先于组件实例化」的未验证时序（语义与风险说明见 AppPreferences.PREF_LOADED_KEY）。
      // ★ 例外注记（2026-09-14 笔4 注释对拍）：预置服务商 seed 标记键（PROVIDER_PRESETS_
      // SEEDED_KEY）的 persistProp 在本置 1 之后——该键自带独立门闩
      // （notifyPresetSeedKeyRegistered，本回调尾放行），不消费本标记，两闸互不依赖
      AppStorage.setOrCreate<number>(PREF_LOADED_KEY, 1);
      // 预置服务商卡 seed 完成标记（2026-08-31 二期）：'1' = 已 seed 永不重跑（删卡不
      // 回填）。注册后立即放行 seed 门闩——此时磁盘值已加载进 AppStorage，seed 侧读
      // 标记才可靠（时序设计见 ProviderPresetSeed.ets 头注释）
      PersistentStorage.persistProp(PROVIDER_PRESETS_SEEDED_KEY, '');
      notifyPresetSeedKeyRegistered();
      // 控制台助手工具 seed 标记键注册完成放行（ProviderPresetSeed 同款门闩——onCreate
      // 迁移链尾的 ensureConsoleAssistant 读标记前必须等磁盘值加载进 AppStorage，防误判
      // 「未检查」重跑迁移复活用户关闭态）
      notifyConsoleToolsKeyRegistered();
      // 内置技能 seed 标记键注册完成放行（同款门闩——onCreate 迁移链尾的
      // ensureBuiltinSkills 读标记前必须等磁盘值加载进 AppStorage，防代数误判重跑迁移）
      notifySkillSeedKeyRegistered();
      // 主动消息冷启动闸放行（2026-09-13 冷启动排期笔，ProviderPresetSeed 同款门闩）：
      // onForeground 首拍早于本回调，总开关键未注册时 onAppForeground 挂起待排——主动
      // 消息六键 persistProp 已全部注册（插入位置铁律在 PREF_LOADED_KEY 置 1 之前），
      // 此处放行补排；时序语义见 ProactiveGen.onAppForeground 注释
      notifyProactiveKeysRegistered();
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  // 系统深浅色切换时刷新 AppStorage（2026-08-29 M2c 接线，dshinhm 同款）：页面资源
  // （resources/dark）由框架自动切换，@StorageProp('appColorMode') 的组件配色由此驱动。
  // ★ 必须用回调参数 newConfig.colorMode——this.context.config 回调时可能还是旧值
  //（dshinhm 真机沉淀：用旧值会致深浅色判断滞后一拍）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onConfigurationUpdate, colorMode: %{public}d', newConfig.colorMode);
    const mode: number = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate<number>('appColorMode', mode);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 前后台运行态键（2026-09-12 主动消息第一笔：非持久——AppStorage.setOrCreate
    // 双向写，主动消息守卫②到点判前台用；全仓无其他「当前打开会话 id」类运行态先例，
    // 本键只表前后台不表页面）
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_KEY, true);
    // 主动消息排程入口（fire-and-forget——总开关关时内部零开销返回）
    onAppForeground();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppStorage.setOrCreate<boolean>(APP_FOREGROUND_KEY, false);
  }
}