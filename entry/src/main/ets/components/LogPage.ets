// 「运行日志」三级页（「更多信息」页入口）：应用内查看自身报错 + 崩溃日志，无需连接电脑 DevEco。
//
// 原理（官方文档 2026-08-21 查证，本地 SDK d.ts 核实）：
// ① 报错日志：hilog.setOutputType(PRIVATE_SANDBOX_WITH_CONSOLE)（@since 26.0.0 Beta）让应用
//    hilog/console 日志落盘到应用私有沙箱（getOutputDir() = /data/storage/el2/log/hiapplog/），
//    getLogFile(latestSeconds) 拿日志文件、fs 读内容后按行过滤 WARN/ERROR/FATAL 级别
//    （hilog 行格式级别为单字母独立 token）——只显示报错与警告，不再显示 INFO 调试日志。
// ② 崩溃日志：HiAppEvent（官方当前推荐，FaultLogger.query 已 deprecated since 18）——
//    APP_CRASH（应用崩溃）/ APP_FREEZE（应用冻屏）是系统事件，系统自动记录，应用 addWatcher
//    订阅（appEventFilters: OS 域 + 事件名）拿到 AppEventPackageHolder，刷新时 takeNext() 拉取
//    事件包（data 为事件 JSON 数组，含崩溃原因/堆栈全文）。官方注意：崩溃事件系统捕获维测日志
//    典型 30s 内完成、极端 2min——崩溃后重启应用可能需稍后刷新重试才能取到。
//
// 交互（2026-08-21 决明定稿）：不自动刷新——仅点击标题栏右上角「更多」按钮
// （官方标题栏按钮 dot_grid_2x2，点击弹官方全局菜单 openMenu：刷新 / 分享导出 /
// 清空沙箱日志〔2026-09-04 增〕）
// 才读取并显示当前报错与崩溃日志；报错/警告只显示尾部 500 行（MAX_ERROR_LINES，
// 见 LogPageDataSource.ets）。**退出本页即清空已刷新内容**（aboutToDisappear，
// 2026-08-21 决明要求）：日志只在本页停留期间留存，再次进入回到空白待刷新状态，
// 防长文本状态随进入次数越积越多（组件 pop 销毁本就会释放，显式清空是转场/缓存路径
// 的双保险）。
//
// 文件拆分（2026-08-21，本文件 526 行超 400 行红线后按职责拆四份，红线见 AGENTS.md
// 防屎山节）：
// - LogPage.ets（本文件）：页面外壳——@State、生命周期、刷新/导出调度、标题栏
// - LogPageContent.ets：内容区 UI——说明文案/空态/日志区块/分段胶囊悬浮层/菜单锚点
// - LogPageDataSource.ets：数据层——崩溃订阅注册/日志读取过滤/导出写文件（纯函数无 UI 状态）
// - LogPageMoreMenu.ets：「更多」菜单——openMenu 内容构建与弹出（无状态弹窗 UI）
// 拆分规则：@State 与生命周期只在主文件；内容区组件靠 @Prop/@Link 接收数据、配色与档位
// 自订阅 AppStorage；数据层参数进、返回值/异常出，不碰 UI 不发 toast；后续加功能先判
// 归属再落文件，主文件再触 400 行红线须继续拆。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import {
  IMMERSIVE_LEVEL_KEY,
  resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_RUN_LOG } from '../common/SettingSearch';
import {
  exportLogsToSandbox,
  fetchCrashLogs,
  fetchErrorLogLines,
  getCrashHolder,
  pruneLogFiles
} from './LogPageDataSource';
import { LogMoreMenuHost, MoreMenuCallbacks, LOG_MORE_MENU_ANCHOR_ID } from './LogPageMoreMenu';
import { LogPageContent } from './LogPageContent';

// 崩溃记录最大显示条数（2026-08-22 定稿 10 条）：单条崩溃事件 JSON 含原因/堆栈全文可达
// 数 KB，多次崩溃后全量 join 成大文本渲染——与报错侧 MAX_ERROR_LINES 展示上限对称；
// 截断仅作用于 UI 文本（元信息计数仍全量；系统侧每类型 10 条上限 + takeNext 消费式拉取
// 不受影响）
const MAX_CRASH_SHOW: number = 10;

@Component
export struct LogPage {
  // 沉浸光感整体档位（AppStorage 共享，驱动标题栏材质）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 顶部留白（vp，HomeNavigation PageMap 传入）：HDS 路径内容区延伸到标题栏背后
  // （渐变模糊蒙层透出滚动内容），语义与 InfoPage/AppearancePage 的 topPad 一致；回退路径传 0
  topPad: number = 0;
  // 崩溃记录文本（驱动 UI：仅刷新触发更新）：APP_CRASH/APP_FREEZE 事件 JSON
  @State crashText: string = '';
  // 报错日志文本（驱动 UI）：hilog 沙箱过滤 WARN/ERROR/FATAL 行（尾部 MAX_ERROR_LINES 行）
  @State errorText: string = '';
  // 日志元信息（驱动 UI）：空态提示 / 统计信息
  @State logMeta: string = '';
  // 顶部分段分类选中项（2026-08-21 决明需求，官方 CapsuleSegmentButtonV2）：0 全部 / 1 崩溃 / 2 报错
  @State logTab: number = 0;
  // 「更多」官方菜单节点宿主（2026-08-30 反馈轮 13 起 AppMenuHost 薄壳——节点生命周期
  // 与弹出组装在基类：init 首建/弹前重建/dispose 成对，普通成员不驱动 UI）
  private moreMenu: LogMoreMenuHost = new LogMoreMenuHost();

  // 进页自检修剪（2026-09-04 调整）：落盘 = 进程级常开，在 EntryAbility.onCreate 开启
  //（PRIVATE_SANDBOX_WITH_CONSOLE，保留控制台输出——DevEco 里照常可见），本页不再开关
  //（原 aboutToAppear 开 / aboutToDisappear 关的页面级开关已退役——落盘只在页面停留期间
  // 开启导致事发日志不落盘、抓不到问题）。进页保留 pruneLogFiles 自检一次：启动自检后
  // 新产生的日志可能已超 2MB 上限（MAX_LOG_STORAGE_BYTES，见 LogPageDataSource），
  // 进页修剪兜底——事件驱动非轮询（P1-2）。
  // ★ 崩溃事件订阅不在本页（M3 拍板 6，与 dshinhm 页面级注册不同）：EntryAbility onCreate
  // 经 ensureCrashWatcher 进程级注册 / onDestroy 注销（坑33 成对铁律——页面级注册未成对
  // 时进程级订阅随页面进出累积；进程级天然一次一对），本页刷新时经 getCrashHolder 取
  // 共享句柄拉取（见 LogPageDataSource 单例注释）。
  aboutToAppear(): void {
    pruneLogFiles();
    this.moreMenu.init(this.getUIContext(), this.moreMenuCallbacks());
  }

  // 「更多」菜单回调簇（init/open 各传一次——open 每次弹出前重建节点取当前深浅色）
  private moreMenuCallbacks(): MoreMenuCallbacks {
    return {
      onRefresh: (): void => {
        this.refreshLogs();
      },
      onExport: (): void => {
        this.exportLogsToFile();
      },
      onClear: (): void => {
        this.clearSandboxLogs();
      }
    };
  }

  // 页面销毁（pop 出栈）时：① 释放菜单内容节点——官方 SDK 原文要求：ComponentContent 不再
  // 使用时必须 dispose() 解除对后端实体节点的引用，否则前端对象无法释放造成内存泄漏
  // （ComponentContent.d.ts:155-163 NOTE）。本页可多次进入/退出，每次 aboutToAppear
  // 新建节点，不 dispose 会随进入次数累积泄漏；
  // ② 清空已刷新的日志文本——日志只在本页停留期间留存，退出即清、再次进入为空白
  // 待刷新状态（2026-08-21 决明要求，语义见文件头「交互」段）。
  // 落盘不再在此关闭（2026-09-04：常开是设计意图，见 EntryAbility.onCreate 注释）；
  // 崩溃事件订阅也不在此注销（M3 拍板 6：归 EntryAbility onDestroy，与 onCreate 注册成对）
  aboutToDisappear(): void {
    this.moreMenu.dispose();
    this.crashText = '';
    this.errorText = '';
    this.logMeta = '';
  }

  // 弹出「更多」官方菜单（标题栏按钮 action 触发）：
  // ★ 每次弹出前重建节点——ComponentContent 固化 UI 树不随深浅色切换更新（2026-08-21
  // 真机 Bug：浅切深后「刷新」仍黑色），重建保证菜单按当前主题构建（见 buildMoreMenuNode
  // 注释）；旧节点弹出已关闭（openMenu 菜单非模态，点按钮即先关旧菜单），dispose 释放
  // 与新建成对，无泄漏。systemMaterial = 官方菜单沉浸光感（THICK 基准，随沉浸光感
  // 总档）
  private openMoreMenu(): void {
    this.moreMenu.rebuild(this.getUIContext(), this.moreMenuCallbacks());
    this.moreMenu.show(this.getUIContext(), LOG_MORE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, true));
  }

  // 刷新日志（仅标题栏右上角「更多」菜单触发，不自动刷新——2026-08-21 决明定稿）：
  // 数据获取走数据层（LogPageDataSource）：① 崩溃记录 takeNext 拉取订阅事件包；
  // ② 报错日志 flush 落盘 → 读时间窗内日志文件过滤 W/E/F 行 → 只留尾部 MAX_ERROR_LINES 行。
  // 失败 toast 提示（不静默失败）
  // ★ keepCrashOnEmpty（2026-09-04 自检发现）：崩溃事件包是 takeNext 消费式——导出前的
  // 自动刷新若再次 takeNext（队列已空）会把已显示的崩溃文本覆盖为空 → 导出丢崩溃记录。
  // true（导出场景）= 无新崩溃时保留已显示内容；false（菜单刷新）= 照旧覆盖（空态语义）
  private refreshLogs(keepCrashOnEmpty: boolean = false): void {
    try {
      // ① 崩溃记录（官方注意：崩溃事件系统生成需 30s~2min，崩溃后立刻刷新可能为空）；
      // 展示只留尾部 MAX_CRASH_SHOW 条（单条 JSON 含堆栈可达数 KB；截断仅作用于 UI 文本，
      // 元信息计数仍用全量 crashLines.length）
      const crashLines: string[] = fetchCrashLogs(getCrashHolder());
      if (crashLines.length > 0 || !keepCrashOnEmpty) {
        this.crashText = crashLines.slice(-MAX_CRASH_SHOW).join('\n\n');
      }

      // ② 报错日志（W/E/F 行过滤 + 尾部行数上限）
      const errorLines: string[] = fetchErrorLogLines();
      this.errorText = errorLines.join('\n');

      // 元信息统计
      const crashCount: number = crashLines.length;
      this.logMeta = crashCount > 0 ? '崩溃记录 ' + crashCount + ' 条 · ' : '';
      this.logMeta += '报错日志 ' + errorLines.length + ' 行';
    } catch (err) {
      console.error('refresh logs failed: ' + JSON.stringify(err));
      this.showToast('读取日志失败，请重试');
    }
  }

  // 当前分类是否显示崩溃/报错区块（2026-08-21 分类过滤；显示侧同规则见
  // LogPageContent.ets）：0 全部 / 1 仅崩溃 / 2 仅报错
  private showCrashBlock(): boolean {
    return this.logTab !== 2 && this.crashText !== '';
  }

  private showErrorBlock(): boolean {
    return this.logTab !== 1 && this.errorText !== '';
  }

  // 分享/导出日志（2026-08-22 由「DocumentViewPicker.save 系统保存对话框」改官方分享面板
  // systemShare，@kit.ShareKit @since 11——官方 d.ts 核实 ShareControllerOptions 的
  // excludedAbilities 注释：SAVE_AS_FILE（另存为文件）等系统能力为面板默认操作区，即「保存
  // 到本地」由面板自带，另有应用分享目标区=分享出去）：内容组织与分段过滤规则不变（logTab：
  // 0 全部=崩溃+报错 / 1 仅崩溃 / 2 仅报错，与 showCrashBlock/showErrorBlock 同逻辑）；
  // 先在沙箱写临时 TXT（数据层 exportLogsToSandbox，唯一名 + 自动清理历史导出文件——数据
  // 有界），再拉起面板；保存/分享结果由系统面板反馈（show 完成=面板关闭），无结果回调需求
  private async exportLogsToFile(): Promise<void> {
    // 导出前自动刷新一次（2026-09-04）：保证导出的是最新报错/崩溃数据（用户可能未刷新
    // 或日志已更新）；★ 传 keepCrashOnEmpty=true——崩溃事件 takeNext 消费式，无新崩溃时
    // 保留已显示的崩溃记录，防导出前刷新覆盖清空（2026-09-04 自检发现并修复）。代价：
    // 此场景统计行不显示崩溃计数（崩溃区块文本保留）——仅记录性差异，不影响导出内容
    this.refreshLogs(true);
    const parts: string[] = [];
    if (this.showCrashBlock()) {
      parts.push('===== 崩溃记录 =====\n' + this.crashText);
    }
    if (this.showErrorBlock()) {
      parts.push('===== 报错日志 =====\n' + this.errorText);
    }
    if (parts.length === 0) {
      this.showToast('当前分类暂无日志可导出');
      return;
    }
    try {
      // 沙箱暂存（返回路径）；文件名 = 路径末段（时间戳唯一名，分享面板标题展示用）
      const path: string = exportLogsToSandbox(this.getUIContext().getHostContext() as common.Context, parts.join('\n\n'));
      const fileName: string = path.substring(path.lastIndexOf('/') + 1);
      const record: systemShare.SharedRecord = {
        // txt 文件 = 官方 UTD 纯文本（uniformTypeDescriptor @kit.ArkData，d.ts 核实
        // UniformDataType.PLAIN_TEXT = 'general.plain-text'）
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        // App file URI（fileUri.getUriFromPath 产物）：官方 SharedRecord.uri 注释明示支持
        // App file URI（坑31 的 Image 解码问题不适用于分享面板，官方支持本 URI 形态）
        uri: fileUri.getUriFromPath(path),
        title: fileName,
        label: 'FILE'
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      // options 传空对象 = 官方默认（居中弹出、卡片预览、单选）；面板操作区默认含
      // 「另存为文件/复制/打印」等系统能力 + 应用分享目标
      await controller.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {});
    } catch (err) {
      console.error('share log file failed: ' + JSON.stringify(err));
      this.showToast('导出失败，请重试');
    }
  }

  // 清空沙箱日志（2026-09-04 新增，「更多」菜单项）：官方 hilog.clean()（@since 26.0.0，
  // 本地 d.ts 核实「Delete all hilog logs in the sandbox」——删除沙箱内全部 hilog 日志
  // 文件）。清空后同步清已显示文本（页面旧数据不再有意义）；崩溃记录来自 hiAppEvent
  // 订阅队列（不在 hilog 沙箱），不受清空影响——菜单文案「清空沙箱日志」语义准确。
  // 常开落盘下清空后新日志继续追加（hilogd 重建文件），无需重新开启
  private clearSandboxLogs(): void {
    try {
      // 先 flush 强制落盘再 clean（2026-09-04 自检补）：残留缓冲在删除后回写会产生
      // 「清空后又出现日志」的假象
      hilog.flush();
      hilog.clean();
      this.crashText = '';
      this.errorText = '';
      this.logMeta = '';
      this.showToast('沙箱日志已清空');
    } catch (err) {
      console.error('clear sandbox logs failed: ' + (err as Error).message);
      this.showToast('清空失败，请重试');
    }
  }

  // 本页 toast 统一入口（重复 4 处提取，P2-4）：材质随沉浸光感总档
  //（基准 THICK，同 BackgroundPanel）。★ 本处是 toast 不是菜单——第三参保持 false
  //（2026-09-18 菜单光感笔口径：interactive 只给菜单/胶囊位，勿随菜单一并改 true）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false)
    });
  }

  // 内容区（@Builder：PageShell 的 @BuilderParam 须传 @Builder 方法/lambda 调用，不能
  // lambda 内直接写 UI——ArkTS 箭头函数体不能包含组件构造；2026-08-21 重构沉淀）
  @Builder
  LogContent() {
    Stack() {
      LogPageContent({
        topPad: this.topPad,
        crashText: this.crashText,
        errorText: this.errorText,
        logMeta: this.logMeta,
        logTab: $logTab
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支，2026-08-21
    // 防屎山提取，见 common/PageShell.ets 头注释）；本页特有：右上角「更多」菜单
    // （HDS 传 menuHds、回退传 menuNav——两体系菜单类型不同，分别原样传；
    // dot_grid_2x2 官方「更多」图标，action 弹官方全局菜单 openMenu，见 LogPageMoreMenu.ets）
    PageShell({
      title: SETTING_TITLE_RUN_LOG,
      menuHds: {
        value: [{
          content: {
            icon: $r('sys.symbol.dot_grid_2x2'),
            action: () => {
              this.openMoreMenu();
            }
          }
        }]
      },
      menuNav: [{
        value: '更多',
        // 符号资源须走 symbolIcon（`icon` 是图片槽位，Symbol 图标不显示——2026-09-13 全族收口，
        // 与工程内其余回退数组同款）
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
        action: () => {
          this.openMoreMenu();
        }
      }],
      content: () => {
        this.LogContent()
      }
    })
  }
}
