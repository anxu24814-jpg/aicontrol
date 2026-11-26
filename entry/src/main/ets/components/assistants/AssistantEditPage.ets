// 助手编辑页：**纯分区导航枢纽**——页序 = 助手详情卡 → 模型与提示词组卡 → 工具调用卡 →
// 内容三域组卡 → 连接组卡 → 高级设定卡；七项分区功能全部真卡、无占位项。
// · 模型与提示词组卡 = 域件 AssistantModelCard（卡头 + 模型/思考强度/提示词三行值行，行本身
//   即入口；绑定即时落库不经保存键；摘要与返回重拉链由域件自持，本页不持 prompt 状态）。
// · 内容三域组卡（记忆/技能/知识库；决明「记忆技能知识库改为组卡1」）与连接组卡（MCP/
//   HTTP 凭据/脚本联网域名三行；域件 AssistantConnGroupCard，决明「mcp 移出工具调用，mcp
//   和脚本联网组成组卡」——原「HTTP 与脚本联网」组卡并入 MCP 行并更名）均为组卡，跳转行
//   带箭头（§3.2「跳转行默认带箭头」——箭头曾按旧令全撤、后经决明反馈恢复，勿再撤）。
// ★ 详情卡：三态头像（首字/文字/图片，编码单源 AvatarSpec.ets）+ 编辑角标热区（弹「更换
// 头像」半模态）+ 状态 chip 行五项（模型/记忆/工具/技能/知识库，共享件 AssistantCardParts）
// + 右上角改名键（弹对话框即时落库；与头像热区是两件事、两个入口）。内置默认助手照显详情卡
// 但不渲染改名键（名恒定禁改）、提示词行进只读页，头像照常可换。（内置控制台助手已整体退役
// ——判定收回默认助手单值，各卡全员渲染。）
// ★ 按钮区退役（领导指令）：底部删除/保存整体退役——一级页有删除、各设置页按项自带保存，
// 名称修改经重命名对话框即时落库（InputDialog 自带空值校验/同值静默跳过）。
// ★ 新建态退役：新建走列表页对话框（确认 insert 落行、取消不落行），本页恒编辑态（只从点
// 列表卡进入；空参 push = 异常路径弹回）。取参：push param = 助手 id（AssistantPage 点卡 push）。
// ★ 高级设定卡：进二级页 AssistantAdvancedPage（采样参数/上下文与输出两行卡 → 各三级页，
// 参数落 assistants.advancedParams JSON 列）；卡面副行 = '默认'/'已自定义'，onPop 重拉。
// 刷新链（规范-数据存储获取刷新方案）：本页无保存动作——返回经 **onBackPressed 拦截 →
// pop({saved:true})** 触发列表页 onPop reload（坑17「无保存动作的完成返回」标准姿势；覆盖
// 重命名后的名称刷新，未改动返回 reload 幂等无害）；各子页 pop 带 result → 重拉对应摘要；
// 组卡以单例纪元键重建（见 contentGroupKey）；HTTP 组卡与提示词摘要自带链（域件内）。
// ★ 工具调用/高级设定两卡壳 = **Button 包壳**（`.type(ButtonType.Normal)`，stateEffect 默认
// true = 官方原生按压蒙层）——裸 Row 点击无按压反馈是历史遗留；形制先例 = ChatSessionRows /
// GroupSettingCard 行卡（卡宽/圆角/底色三件挂 Button，内边距留在内层 Row）。
// ★ 组卡刷新责任在调用方（GroupSettingCard 头注释）：items 为普通成员入参，故内容三域组卡
// 走 ForEach([contentGroupKey()]) 单例纪元键——键含三行摘要，任一变动即整卡重建拉新值。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import {
  ROUTE_ASSISTANT_ADVANCED_PAGE, ROUTE_ASSISTANT_EDIT_PAGE, ROUTE_ASSISTANT_KNOWLEDGE_PAGE,
  ROUTE_ASSISTANT_MEMORY_PAGE, ROUTE_ASSISTANT_SKILL_PAGE, ROUTE_ASSISTANT_TOOLS_PAGE
} from '../../common/RouteNames';
import { AssistantModelCard } from './AssistantModelCard';
import { AssistantConnGroupCard } from './AssistantConnGroupCard';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, DETAIL_CARD_TITLE_FONTSIZE, CARD_RADIUS
} from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  ASSISTANT_DEFAULT_ID, ASSISTANT_NAME_MAX,
  AssistantRow, queryAssistant, updateAssistantAvatar, updateAssistantName
} from '../../common/store/AssistantDb';
import {
  AVATAR_KIND_IMAGE, AVATAR_KIND_TEXT, AVATAR_TEXT_MAX, AVATAR_URL_MAX, avatarKind, avatarValue,
  cleanAvatarTempFiles, deleteAvatarFile, imageAvatar, isValidAvatarText, isValidAvatarUrl,
  newAvatarFileName, newAvatarTempFileName, sanitizeAvatarText, textAvatar
} from '../../common/AvatarSpec';
import { copyFileExact, decodeScaled, saveJpg } from '../../common/ImageEditUtil';
import { MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { parseEnabledToolIds, ToolGroup } from '../../common/providers/ToolTypes';
// 卡显示态判定单源（工具计数口径）
import { toolGroupAllOn, visibleToolGroups } from '../../common/providers/ToolCardView';
import { TOOL_SEARCH_WEB } from '../../common/providers/ToolIds';
import { parseEnabledKnowledgeIds } from '../../common/KnowledgeText';
import { parseEnabledSkillIds } from '../../common/SkillText';
import { InputDialog } from '../chat/InputDialog';
import { sheetPanelOptions, sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_GREEN, SETTING_ICON_ORANGE, SETTING_ICON_PURPLE, SettingRowIcon } from '../GroupSettingCard';
import { AssistantAvatar, AssistantChip, AssistantEditParam } from './AssistantCardParts';

// （历史：占位分区机制已整体退役——占位清单/占位页随知识库转真卡一并删除，勿再引入占位项）

@Component
export struct AssistantEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 助手名称（详情卡展示 + 重命名对话框初值；改名即时落库后本状态同步刷新）
  @State private name: string = '';
  // 模型显示名不在本页：模型绑定域整块在 AssistantModelCard，绑定名经 onModelLabelChange
  // 上行；提示词摘要与跳转链同在域件（该件第三行），本页不持 prompt 状态。
  // 高级设定卡副行摘要（advancedParams 列空/非空 → '默认'/'已自定义'；onPop 重拉）
  @State private advancedSummary: string = '默认';
  // 工具卡副行摘要：按**用户可见入口**（工具页分类卡）计数报「已开卡数/卡总数」——底层逐件
  // id 数不上屏（卡口径统一，七百三十二节决明口径）；联网态前缀恒报实际态（联网是唯一在别处
  // 还有闸的工具〔只剩会话级联网开关〕须一眼可见，勿写「默认」）。工具页返回经 onPop 重拉；
  // 初值 '' 待 aboutToAppear 回填。
  @State private toolsSummary: string = '';
  // 记忆行摘要（内容组卡副行）：作用域 + memoryInject/memorySink 两开关布尔映射；onPop 重拉
  @State private memorySummary: string = '注入开 · 沉淀开';
  // 技能行摘要：skills 列解析计数 → '已启用 N 个技能' / '未启用'；onPop 重拉
  @State private skillSummary: string = '未启用';
  // 知识库行摘要：knowledge 列解析计数 → '已启用 N 个知识库' / '未启用'；onPop 重拉
  @State private knowledgeSummary: string = '未启用';
  // ── 头像与 chip 行（详情卡总览层；分区卡/组卡行是明细层，chip 与摘要允许重叠）──
  // 头像编码原串（AvatarSpec 形态；更换后直写刷新——单元素 ForEach 键变重建，见 DetailCard）
  @State private avatar: string = '';
  // chip 文本数组（rebuildChips 先算后赋一次刷新；ForEach 键 = 文本本身）
  @State private chips: string[] = [];
  // chip 数据源普通成员（不驱动 UI——坑16 家族分工：普通中间量 + @State 收口，刷新责任在 rebuildChips）
  private modelName: string = '';
  private toolsOn: number = 0;
  private toolsTotal: number = 0;
  private memoryInjectOn: boolean = true;
  private skillCount: number = 0;
  private knowledgeCount: number = 0;
  // ── 「更换头像」半模态 ──
  // 面板开关（bindSheet 挂页面根；与触发键〔详情卡头像〕同组件位）
  @State @Watch('onSheetVisibleChanged') private avatarSheetShow: boolean = false;
  // ── 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：关闭后
  // 离场动效在途期内再开，直接写 true 会被吞或被框架收尾回写压回——在途期只记开意图，动效
  // 结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 面板标题栏材质与恢复键双态订阅（沉浸光感总档 + 内容区回退两键——恢复键四件套消费）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 页面存活守卫：选图/换形象各异步链收尾前判 alive，离页即放弃（删本轮 temp/dest 文件、不
  // 落库、不 toast、不关面板；兼挡销毁后 getUIContext 边界）——四路收尾（settleAvatar 与
  // 三路失败 toast）同判
  private alive: boolean = false;
  // 换形象在途闸（四路统一）：快速连点会起两条链并发写库致 settle 倒挂、相册链互删文件 = 孤儿
  // + 误删当前图；finally 复位防闸卡死
  private avatarBusy: boolean = false;
  // 编辑对象行 id（本页恒编辑态——空参 push = 异常路径弹回）
  private rowId: string = '';
  // 重命名对话框控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private renameCtrl: CustomDialogController | null = null;
  // 头像文字/链接输入弹窗控制器（★ 组件成员位同坑7——半模态展开时叠 CustomDialog 先例）
  private textAvatarCtrl: CustomDialogController | null = null;
  private urlAvatarCtrl: CustomDialogController | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 图标外观恒彩色 + 圆角矩形——颜色/形状偏好已退役、行为固化为不可关闭，工具调用/高级设定
  // 两张自绘卡不再订阅任何开关，也不再有单色裸符号态

  aboutToAppear(): void {
    this.alive = true;
    // push 参数（getParamByName 取末条）：AssistantEditParam（列表卡 push，id 必非空；空/缺参
    // = 异常路径弹回）
    const params: Array<AssistantEditParam> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_EDIT_PAGE) as Array<AssistantEditParam>;
    const param: AssistantEditParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param.id === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param.id;
    // 首帧种子：读库前直赋 avatar/name——进页首帧即真头像与名称，防读库空窗 '?' 占位跳变；
    // DB 复核同值不触发单元素 ForEach 键变重建（键 = 'a|' + 头像串 + '|' + name）
    this.avatar = param.avatar;
    this.name = param.name;
    // 读时联结：默认助手 prompt = 系统提示词当前值（分区摘要即时同步）
    queryAssistant(param.id)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.advancedSummary = row.advancedParams === '' ? '默认' : '已自定义';
        this.avatar = row.avatar;
        this.refreshToolsSummary(row.tools);
        this.refreshMemorySummary(row);
        this.refreshSkillSummary(row.skills);
        this.refreshKnowledgeSummary(row.knowledge);
        // 模型绑定名不在本页重读（AssistantModelCard 自持绑定链经 onModelLabelChange 上行）；
        // 此处只兜底一次 chip 合并刷新（幂等）
        this.rebuildChips();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  aboutToDisappear(): void {
    // 离页 = 放弃在途更换（各链 await 点判 alive；此处只置守卫位，文件清理由在途链自完成——
    // 本钩子时机可能与 await 交错，不在此抢删）
    this.alive = false;
  }

  // 内置助手判定（内置默认助手名恒定禁改——详情卡不渲染改名键；提示词行只读。控制台助手
  // 已整体退役，判定收回默认助手单值）
  private isBuiltin(): boolean {
    return this.rowId === ASSISTANT_DEFAULT_ID;
  }

  // 当前深浅模式（两张自绘卡的图标色对随模式切换）
  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // ── chip 行（详情卡总览层，形制对齐一级页助手卡 chip）──

  // chip 重算（先算后赋一次刷新；控制台裁剪已随控制台退役删除，全员五枚）
  private rebuildChips(): void {
    const list: string[] = ['模型 ' + (this.modelName !== '' ? this.modelName : '未设置')];
    list.push('记忆 ' + (this.memoryInjectOn ? '开' : '关'));
    list.push('工具 ' + this.toolsOn + '/' + this.toolsTotal);
    list.push('技能 ' + this.skillCount);
    list.push('知识库 ' + this.knowledgeCount);
    this.chips = list;
  }

  // ── 「更换头像」半模态与四路换形象编排（数据链 = AvatarSpec 编码单源 +
  // updateAssistantAvatar 单列 UPDATE + 本地文件清理）──

  // 面板开关与关闭入口（规范 §1 硬约束：标题栏 xmark 与 onWillDismiss 两路同调本方法；本面板
  // 不加关闭确认——点选即落库属负面清单「点一下就落库的」）
  private openAvatarSheet(): void {
    this.requestOpen();
  }

  // 关闭-再开协调（机制见字段注释）：开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.avatarSheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.avatarSheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；用户
  // 关闭必经 requestCloseAvatar（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.avatarSheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 换形象落库收尾三路同调）：先清开意图 + 置动效在途位，再写可见性
  private requestCloseAvatar(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.avatarSheetShow = false;
  }

  // 现查库值头像串（旧文件删除判据——★ 禁链开头缓存值：连点两次换图时缓存值会让第一张图
  // 成孤儿；行不存在 = '' 不删）
  private async queryAvatarSpec(): Promise<string> {
    const row: AssistantRow | null = await queryAssistant(this.rowId);
    return row !== null ? row.avatar : '';
  }

  // 本轮文件清理（选图链失败/放弃路径——不留孤儿；单文件删除失败仅日志）
  private discardFiles(paths: string[]): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return;
    }
    for (const p of paths) {
      if (p === '') {
        continue;
      }
      try {
        if (fs.accessSync(p)) {
          fs.unlinkSync(p);
        }
      } catch (e) {
        hilog.error(0xD5A4, 'AssistantEditPage', 'discard avatar file failed: %{public}s, %{public}s', p, JSON.stringify(e));
      }
    }
  }

  // 换形象成功收尾（四路共用）：删旧本地文件（写库前现查的旧值）→ 状态更新 → toast →
  // 关面板（filesDir 拿不到时跳过删文件不阻断，下次再清）。★ alive 前置：离页后写库照常
  // 完成（已确认意图），但状态刷新/toast/关面板经已销毁页的 getUIContext 一律放弃；孤儿文件
  // 由下次换形象（写库前现查旧值即删）或删助手级联清理自愈
  private settleAvatar(oldSpec: string, newSpec: string, message: string): void {
    if (!this.alive) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context !== undefined) {
      deleteAvatarFile(context.filesDir, oldSpec);
    }
    this.avatar = newSpec;
    this.getUIContext().getPromptAction().showToast({ message: message });
    this.requestCloseAvatar();
  }

  // 从相册选择（任一步失败即中止并 toast，不留半成品）：清临时残留 → 系统选图（取消静默）→
  // 拷中转 → 采样解码 512 → 存 jpg → 校验转 URI → 写库前现查旧值 → 写库 → 删旧文件/中转 →
  // 状态更新 → toast → 关面板。★ 两道防线：在途闸防连点双链互删文件；alive 守卫每个 await
  // 回来后判——离页即放弃（删本轮文件、不落库、不 toast、不关面板）
  private async pickAvatarImage(): Promise<void> {
    if (this.avatarBusy) {
      return;
    }
    this.avatarBusy = true;
    let tempPath: string = '';
    let destPath: string = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        throw new Error('host context unavailable');
      }
      // 先清上一轮取消/失败残留的临时文件（有界 ≤1）
      cleanAvatarTempFiles(context.filesDir);
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return; // 用户取消：静默，不提示、不关面板
      }
      if (!this.alive) {
        return;
      }
      tempPath = context.filesDir + '/' + newAvatarTempFileName();
      // fd 级拷贝（禁 fs.copy 直传媒体 URI——真机报「路径或文件不存在」在案）
      copyFileExact(result.photoUris[0], tempPath);
      const pm: image.PixelMap = await decodeScaled(tempPath, 512, true);
      destPath = context.filesDir + '/' + newAvatarFileName(this.rowId);
      try {
        await saveJpg(pm, destPath);
      } finally {
        pm.release(); // 成对释放（官方）
      }
      fs.statSync(destPath);
      // 存 file:// URI 而非纯路径（纯路径 Image 静默加载失败——BackgroundPanel 真机教训）
      const destUri: string = fileUri.getUriFromPath(destPath);
      const newSpec: string = imageAvatar(destUri);
      const oldSpec: string = await this.queryAvatarSpec();
      if (!this.alive) {
        this.discardFiles([tempPath, destPath]);
        return;
      }
      await updateAssistantAvatar(this.rowId, newSpec);
      this.settleAvatar(oldSpec, newSpec, '已更换形象');
      this.discardFiles([tempPath]);
    } catch (err) {
      this.discardFiles([tempPath, destPath]);
      if (!this.alive) {
        return;
      }
      const code: number | undefined = (err as BusinessError).code;
      hilog.error(0xD5A4, 'AssistantEditPage', 'avatar pick failed: %{public}s', JSON.stringify(err));
      this.getUIContext().getPromptAction().showToast({
        message: '形象更换失败' + (code !== undefined ? ' ' + code : '')
      });
    } finally {
      this.avatarBusy = false;
    }
  }

  // 文字/链接/恢复三路写库编排统一收口：与相册链同款两道防线——avatarBusy 在途闸（调用方
  // 入口判 + 本方法 finally 复位——失败也复位防闸卡死）+ settleAvatar 与失败 toast 的 alive
  // 判（写库本身是用户已确认意图照常完成，只放弃 UI 动作）。防的是三路与在途相册链并发时
  // 两路 settle 次序倒挂（界面头像与库值短暂错位，重进自愈）与离页后摸已销毁页
  private async commitAvatarUpdate(newSpec: string, message: string,
    failPrefix: string): Promise<void> {
    this.avatarBusy = true;
    try {
      const oldSpec: string = await this.queryAvatarSpec();
      await updateAssistantAvatar(this.rowId, newSpec);
      this.settleAvatar(oldSpec, newSpec, message);
    } catch (e) {
      if (!this.alive) {
        return; // 离页放弃失败 toast（getUIContext 边界同 settle；失败态重进页面自见）
      }
      this.getUIContext().getPromptAction().showToast({
        message: failPrefix + '：' + (e as Error).message
      });
    } finally {
      this.avatarBusy = false;
    }
  }

  // 文字与表情输入弹窗（组件成员位构造；maxLength = 码元上限，够 2 个代理对字符；空值由
  // InputDialog 自带校验拦下）
  private openTextAvatarDialog(): void {
    this.textAvatarCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '文字与表情',
        initialText: avatarKind(this.avatar) === AVATAR_KIND_TEXT ? avatarValue(this.avatar) : '',
        placeholder: '例如 🐧 或 助手名首字',
        confirmLabel: '确定',
        maxLength: AVATAR_TEXT_MAX * 2,
        onConfirm: (text: string): void => {
          this.applyTextAvatar(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.textAvatarCtrl.open();
  }

  private applyTextAvatar(raw: string): void {
    // ★ 超长先拦：sanitize 的契约是按码点截断到上限——先清洗后复核会把超长输入截成 2 码点
    // 使复核恒过、截断值静默落库。故对原始输入先判码点数（trim 后 Array.from 按码点计，与
    // isValidAvatarText 同口径），超限即拦；sanitize 退为剔控制字符的清洗兜底，复核保留为
    // 最后一道门
    if (Array.from(raw.trim()).length > AVATAR_TEXT_MAX) {
      this.getUIContext().getPromptAction().showToast({ message: '最多 2 个字符' });
      return;
    }
    const text: string = sanitizeAvatarText(raw);
    if (!isValidAvatarText(text)) {
      this.getUIContext().getPromptAction().showToast({ message: '最多 2 个字符' });
      return;
    }
    // 在途闸（与相册链互斥——判与置之间无 await，单线程下原子；静默 return 照既有语义，
    // 闸在 commitAvatarUpdate 内 finally 复位）
    if (this.avatarBusy) {
      return;
    }
    this.commitAvatarUpdate(textAvatar(text), '已更换形象', '形象保存失败');
  }

  // 输入链接弹窗（URL 形态；明文 http 允许——与服务商地址口径一致，图片不涉密钥）
  private openUrlAvatarDialog(): void {
    this.urlAvatarCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '输入链接',
        initialText: avatarKind(this.avatar) === AVATAR_KIND_IMAGE ? avatarValue(this.avatar) : '',
        placeholder: '例如 https://example.com/logo.png',
        confirmLabel: '确定',
        maxLength: AVATAR_URL_MAX,
        onConfirm: (text: string): void => {
          this.applyUrlAvatar(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.urlAvatarCtrl.open();
  }

  private applyUrlAvatar(raw: string): void {
    // 不做可达性预取（P1-2 轻量——失效由渲染兜底回首字）
    if (!isValidAvatarUrl(raw)) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 http 或 https 开头的图片地址' });
      return;
    }
    // 在途闸（同 applyTextAvatar——与在途相册链互斥）
    if (this.avatarBusy) {
      return;
    }
    this.commitAvatarUpdate(imageAvatar(raw.trim()), '已更换形象', '形象保存失败');
  }

  // 恢复默认（写 '' → 删旧本地文件 → 收尾）。不置灰恒可点：值已是 '' 时点击幂等（写空串 +
  // 删文件均无害，toast 如实报）——.enabled(false) 全仓仅一处先例且按钮禁用不改色，看着仍
  // 像可点却点不动是观感歧义；真灰须自绘字色撞「禁自绘」条。在途闸（四路统一——与在途相册链互斥）
  private restoreDefaultAvatar(): void {
    if (this.avatarBusy) {
      return;
    }
    this.commitAvatarUpdate('', '已恢复默认形象', '恢复失败');
  }

  // 面板行数据（icon 为实锤符号；对象字面量在类型化返回值方法内，非 build 内）
  private avatarSheetRows(): GroupEntryItem[] {
    const rows: GroupEntryItem[] = [
      {
        icon: $r('sys.symbol.face_smiling'),
        label: '文字与表情',
        secondary: '输入 1 到 2 个字符或表情',
        onClick: (): void => {
          this.openTextAvatarDialog();
        }
      },
      {
        icon: $r('sys.symbol.picture'),
        label: '从相册选择',
        secondary: '使用本机图片',
        onClick: (): void => {
          this.pickAvatarImage();
        }
      },
      {
        icon: $r('sys.symbol.link'),
        label: '输入链接',
        secondary: '使用网络图片地址',
        onClick: (): void => {
          this.openUrlAvatarDialog();
        }
      }
    ];
    return rows;
  }

  // 重命名（详情卡右上角编辑键弹对话框——即时落库不经保存键；InputDialog 自带空值 toast
  // 留窗/同值静默跳过；失败 toast 不静默；列表刷新 = 返回时 pop 带 result → onPop reload）
  private openRenameDialog(): void {
    this.renameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名助手',
        initialText: this.name,
        placeholder: '如 翻译助手、代码顾问',
        confirmLabel: '确认',
        maxLength: ASSISTANT_NAME_MAX,
        onConfirm: (text: string): void => {
          updateAssistantName(this.rowId, text)
            .then((): void => {
              this.name = text;
              this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
            })
            .catch((e: Object): void => {
              this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
            });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.renameCtrl.open();
  }

  // （提示词摘要/跳转与模型设置二级页均已退役——链路在 AssistantModelCard 域件内自持）

  // 高级设定页跳转（onPop 重拉摘要——坑17 契约；只刷 advancedSummary，其余状态独立）
  private openAdvancedPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_ADVANCED_PAGE, this.rowId, (): void => {
      this.refreshAdvancedSummary();
    });
  }

  // 工具页跳转（onPop 重拉摘要——坑17 契约；只刷 toolsSummary，其余状态独立）
  private openToolsPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_TOOLS_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row): void => {
          if (row !== null) {
            this.refreshToolsSummary(row.tools);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '工具摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 工具卡摘要计算（入参 = tools 列原串，'' = 默认集合，解析在 ToolTypes）：报可见卡中已开
  // 张数（卡口径统一〔七百三十二节〕——底层 id 数不上屏）；「卡是否已开」判定走 ToolCardView
  // 单源（toolGroupAllOn，与工具页卡开关同口径：联网压制件不进分母，压制判据单维〔候选集合
  // 是否含联网搜索〕；应用管理卡进全员分母）
  private refreshToolsSummary(toolsJson: string): void {
    const ids: string[] = parseEnabledToolIds(toolsJson);
    const web: string = ids.includes(TOOL_SEARCH_WEB) ? '联网开' : '联网关';
    const groups: ToolGroup[] = visibleToolGroups();
    let on: number = 0;
    for (const group of groups) {
      if (toolGroupAllOn(group, ids)) {
        on++;
      }
    }
    this.toolsSummary = web + ' · ' + on + '/' + groups.length + ' 项启用';
    // chip 计数同存（赋值行与开体一字未改，只在链尾追加落点）
    this.toolsOn = on;
    this.toolsTotal = groups.length;
    this.rebuildChips();
  }

  // 记忆卡摘要计算：前置作用域段（'助手记忆'/'全局记忆'，脏值兜底全局）+ 两开关布尔映射
  private refreshMemorySummary(row: AssistantRow): void {
    const scope: string = row.memoryScope === MEMORY_SCOPE_ASSISTANT ? '助手记忆' : '全局记忆';
    this.memorySummary = scope + ' · ' + (row.memoryInject ? '注入开' : '注入关') + ' · ' +
      (row.memorySink ? '沉淀开' : '沉淀关');
    this.memoryInjectOn = row.memoryInject;
    this.rebuildChips();
  }

  // 技能卡摘要计算（入参 = skills 列原串，'' = 空集合 = 未启用；解析在 SkillText——与 tools
  // 列语义相反，故不复用工具计数口径）
  private refreshSkillSummary(skillsJson: string): void {
    const count: number = parseEnabledSkillIds(skillsJson).length;
    this.skillSummary = count === 0 ? '未启用' : '已启用 ' + count + ' 个技能';
    this.skillCount = count;
    this.rebuildChips();
  }

  // 助手技能页跳转（onPop 重拉摘要——坑17 契约；只刷 skillSummary，其余状态独立）
  private openSkillPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_SKILL_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row: AssistantRow | null): void => {
          if (row !== null) {
            this.refreshSkillSummary(row.skills);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '技能摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 知识库卡摘要计算（入参 = knowledge 列原串，'' = 空集合 = 未启用；解析在 KnowledgeText，
  // 与 skills 列同义、与 tools 列相反）
  private refreshKnowledgeSummary(knowledgeJson: string): void {
    const count: number = parseEnabledKnowledgeIds(knowledgeJson).length;
    this.knowledgeSummary = count === 0 ? '未启用' : '已启用 ' + count + ' 个知识库';
    this.knowledgeCount = count;
    this.rebuildChips();
  }

  // 助手知识库页跳转（onPop 重拉摘要——坑17 契约；只刷 knowledgeSummary，其余状态独立）
  private openKnowledgePage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_KNOWLEDGE_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row: AssistantRow | null): void => {
          if (row !== null) {
            this.refreshKnowledgeSummary(row.knowledge);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({
            message: '知识库摘要刷新失败：' + (e as Error).message
          });
        });
    });
  }

  // 助手记忆页跳转（onPop 重拉摘要——坑17 契约；只刷 memorySummary，其余状态独立）
  private openMemoryPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_MEMORY_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row): void => {
          if (row !== null) {
            this.refreshMemorySummary(row);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '记忆摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 高级设定卡摘要重读（advancedParams 空 = 默认，非空 = 已自定义——细摘要在二级页，本卡只
  // 报状态。读取失败 toast 不静默 P0-1。★ 只刷 advancedSummary——高级设定两页只写
  // advancedParams 列不动 tools，勿在此挂 refreshToolsSummary〔工具摘要有自己的刷新链〕）
  private refreshAdvancedSummary(): void {
    queryAssistant(this.rowId)
      .then((row): void => {
        if (row !== null) {
          this.advancedSummary = row.advancedParams === '' ? '默认' : '已自定义';
        }
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '高级设定摘要读取失败：' + (e as Error).message });
      });
  }

  // ── 内容三域组卡（记忆 / 技能 / 知识库；决明「记忆技能知识库改为组卡1」）──

  // 组卡重建键（恒单例纪元键——键含三行全部摘要，任一变动即键变 → 组卡整体重建拉新副行；
  // 组卡刷新责任在调用方，GroupSettingCard 头注释）
  private contentGroupKey(): string {
    return this.memorySummary + '|' + this.skillSummary + '|' + this.knowledgeSummary;
  }

  // 组卡行数据（三入口行：图标 + 标题 + 摘要副行；跳转行带箭头〔§3.2，曾按旧令全撤后经决明
  // 反馈恢复，勿再撤〕；已核验符号名 memory_module / wand_and_stars / bookshelf。本卡三行
  // 统一绿（卡内主色并列取首行）；工具卡橙 / 高级设定紫。对象字面量在类型化返回值方法内，非 build 内）
  private contentGroupItems(): GroupEntryItem[] {
    const rows: GroupEntryItem[] = [
      {
        icon: $r('sys.symbol.memory_module'),
        iconBg: SETTING_ICON_GREEN,
        label: '记忆',
        secondary: this.memorySummary,
        chevron: true,
        onClick: (): void => {
          this.openMemoryPage();
        }
      },
      {
        icon: $r('sys.symbol.wand_and_stars'),
        iconBg: SETTING_ICON_GREEN,
        label: '技能',
        secondary: this.skillSummary,
        chevron: true,
        onClick: (): void => {
          this.openSkillPage();
        }
      },
      {
        icon: $r('sys.symbol.bookshelf'),
        iconBg: SETTING_ICON_GREEN,
        label: '知识库',
        secondary: this.knowledgeSummary,
        chevron: true,
        onClick: (): void => {
          this.openKnowledgePage();
        }
      }
    ];
    return rows;
  }

  // 助手详情卡：三态头像 + 编辑角标热区 + 状态 chip 行五项（chip 是总览层，与分区卡摘要允许
  // 重叠）+ 改名键（与头像热区是两件事、两个入口）。★ 头像刷新链 = 单元素 ForEach 键变重建，
  // 键 = 'a|' + 头像串 + '|' + name——**键必须覆盖本件消费的全部可变入参**（spec 与
  // fallbackText 双源）：键只含头像串时默认态（'' 恒定）读库完成不改键 → 头像件不重建 →
  // fallbackText 冻结在首帧空值，重进编辑页显示 '?'；name 入键同收「改名后首字不刷新」同族。
  // 共享件入参普通成员禁 @Prop，坑16 家族。无参 @Builder 内直读 this.name/this.chips
  //（坑16 家族——值参传递快照不刷新）
  @Builder
  DetailCard() {
    Row({ space: 12 }) {
      // 头像（整块热区 + 右下角编辑角标——点击任意位置弹「更换头像」半模态）
      ForEach([this.avatar], (_spec: string) => {
        AssistantAvatar({ spec: this.avatar, fallbackText: this.name, editable: true,
          onEditClick: (): void => {
            this.openAvatarSheet();
          }
        })
      }, (_spec: string): string => 'a|' + _spec + '|' + this.name)
      Column({ space: 4 }) {
        Text(this.name)
          .fontSize(DETAIL_CARD_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // chip 行（Flex wrap——长模型名/窄屏自动换行不裁切；键 = 文本本身）
        Flex({ wrap: FlexWrap.Wrap,
          space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) } }) {
          ForEach(this.chips, (text: string) => {
            AssistantChip({ text: text })
          }, (text: string): string => text)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 右上角改名键（★ 内置助手不渲染——名恒定禁改；头像照常可换）
      if (!this.isBuiltin()) {
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.openRenameDialog();
        })
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  // （模型/记忆/技能/知识库四张分区卡壳已退役——模型卡在域件 AssistantModelCard，记忆/技能/
  // 知识库并为一张组卡（行数据见 contentGroupItems），勿在本页重建这四段 Builder）

  // 工具调用分区卡（icon wrench_and_screwdriver；★ 动态摘要行——无参 @Builder 内直读
  // this.toolsSummary〔坑16 值参快照勿改〕；点击进工具页，摘要随 onPop 重拉）
  @Builder
  ToolsCard() {
    // ★ 蒙层边距统一（规范《列表卡片与组卡》蒙层边距节）：卡底 Column 承卡壳三件套 + 四周
    // padding 4，按压蒙层距卡外圈 4vp；蒙层圆角 = 卡圆角；★ 禁 Button margin 写法（组卡头
    // 注释真机实锤）
    Column() {
      Button() {
        Row({ space: 12 }) {
          // 图标恒彩色 + 圆角矩形（偏好键已退役、行为固化为不可关闭）——单色裸符号分支已删除；
          // 图标左缘 16 = 上内距 16 同心、标题左缘 66 与组卡行同线
          // ★ 图形本体统一走 GroupSettingCard 的 SettingRowIcon（全仓彩底图标唯一实现，底形
          // 圆角矩形由该函数内部固化）；本卡是「整行一张卡」，同心基准 = 视觉内距 16（卡底
          // 4 + 行 12），故偏移传 0
          SettingRowIcon($r('sys.symbol.wrench_and_screwdriver'), SETTING_ICON_ORANGE, this.isDarkMode(), 0)
          Column({ space: 4 }) {
            Text('工具调用')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Text(this.toolsSummary)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          // 行尾收口箭头（20fp 次要色 + 右缘 4，与组卡跳转行同源——§3.2「跳转行默认带箭头」）
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([cardDescColor()])
            .margin({ right: 4 })
        }
        .width('100%')
        // 左内距 12 = 视觉 16（卡底 4 + 行 12，与上内距同——图标中心与卡圆角同心）
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openToolsPage();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS) // 卡角 = CARD_RADIUS（20）
    .padding(4)
  }

  // 高级设定分区卡（形制同 ToolsCard；icon gearshape；★ 动态摘要行——无参 @Builder 内直读
  // this.advancedSummary〔坑16 值参快照勿改〕；点击进二级页，摘要随 onPop 重拉）
  @Builder
  AdvancedCard() {
    // 蒙层边距统一：同 ToolsCard（卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp）
    Column() {
      Button() {
        Row({ space: 12 }) {
          // 图标恒彩色 + 圆角矩形（偏好键已退役、行为固化为不可关闭）——单色裸符号分支已删除；
          // 形制同 ToolsCard（视觉左内距 16 / space 12），走 SettingRowIcon、偏移 0
          SettingRowIcon($r('sys.symbol.gearshape'), SETTING_ICON_PURPLE, this.isDarkMode(), 0)
          Column({ space: 4 }) {
            Text('高级设定')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Text(this.advancedSummary)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          // 行尾收口箭头（同 ToolsCard——§3.2「跳转行默认带箭头」）
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([cardDescColor()])
            .margin({ right: 4 })
        }
        .width('100%')
        // 左内距 12 = 视觉 16（同 ToolsCard 同心口径）
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openAdvancedPage();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS) // 卡角 = CARD_RADIUS（20）
    .padding(4)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 助手详情卡（内置助手同样显示但无改名键——恒显卡）──
        this.DetailCard()

        // ── 模型与提示词组卡（域件：卡头 + 三行值行；绑定名经 onModelLabelChange 上行喂
        //   chip 行，本页不另查库）──
        AssistantModelCard({
          assistantId: this.rowId,
          pathStack: this.pathStack,
          bottomPad: this.bottomPad,
          onModelLabelChange: (label: string): void => {
            this.modelName = label;
            this.rebuildChips();
          }
        })

        // ── 工具调用卡 ──
        this.ToolsCard()
        // ── 内容三域组卡 + HTTP 组卡 + 高级设定卡（控制台不渲染守卫已随控制台退役删除——
        //   全员渲染）──
        // 内容三域组卡（单例纪元键承载刷新——键含三行摘要，任一变动即整卡重建拉新副行）
        ForEach([this.contentGroupKey()], (_key: string) => {
          GroupSettingCard({ items: this.contentGroupItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
        }, (key: string): string => key)
        // 连接组卡（域件；MCP/HTTP 凭据/脚本联网域名三行摘要与返回重拉链在域件内）
        AssistantConnGroupCard({ assistantId: this.rowId, pathStack: this.pathStack })
        // 高级设定卡（分区末位）
        this.AdvancedCard()
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

  // 「更换头像」半模态面板（壳形制照 ModelPickerSheet：HdsNavigation MODAL +
  // sheetTitleBarOptions + hideBackButton + 底部安全区延伸；挂点判据三条 = 合法树内〔PageShell
  // 返回体〕/ 页面根不在 ForEach 行内不做条件销毁 / avatarSheetShow 与触发键〔详情卡头像〕
  // 同组件位）。内容固定不滚动不包 Scroll（无滚动容器即不涉 clip(false)）；容器不设左右
  // 边距——组卡自收 CARD_PANEL_WIDTH，恢复键同宽对齐。档位不传 = 默认 [MEDIUM, LARGE] 半屏起。
  // 本面板不加关闭确认（点选即落库属负面清单）；requestCloseAvatar 两路同调
  @Builder
  AvatarSheetHost() {
    HdsNavigation() {
      Column({ space: CARD_SPACING }) {
        GroupSettingCard({ items: this.avatarSheetRows() })
        // 「恢复默认」= 键不是卡（内容区四件套次钮形制——SystemPromptPage 恢复键同源）
        Button('恢复默认')
          .width(CARD_PANEL_WIDTH)
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.restoreDefaultAvatar();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 12, bottom: this.bottomPad + 16 })
    }
    .titleBar(sheetTitleBarOptions('更换头像', '', (): void => {
      this.requestCloseAvatar();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: '助手编辑',
      // 右上角无菜单键（纯导航枢纽——保存/重命名/删除均有各自交互位）
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17「无保存动作」姿势——列表页 onPop reload；未改动返回
        // reload 幂等无害）。默认系统转场（跨页一镜到底已退役，见 AssistantCardParts
        // 「共享元素退役说明」节）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
      // 「更换头像」半模态（坑64 姿势声明式挂页面根；关闭链四件 = 可见性 `$$` 双向 +
      // onWillDismiss 内 action.dismiss() 放行后收口 requestCloseAvatar〔标题栏 xmark 同调，
      // 两路单源〕+ 第四参 onDisappear 补开〔关闭-再开协调，见字段注释〕；官方契约见
      // KimiSheetCommon 注释）
      .bindSheet($$this.avatarSheetShow, this.AvatarSheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseAvatar();
        }, undefined, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}
