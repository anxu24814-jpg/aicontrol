// 「运行日志」三级页（「更多信息」页入口）：应用内查看自身报错 + 崩溃与运行异常记录，无需
// 连接电脑 DevEco。
//
// 原理（官方文档查证 + 本地 SDK d.ts 核实）：
// ① 报错日志：hilog.setOutputType(PRIVATE_SANDBOX_WITH_CONSOLE)（@since 26.0.0）让应用
//    hilog/console 日志落盘到应用私有沙箱，getLogFile 拿日志文件、fs 读内容后按行过滤
//    WARN/ERROR/FATAL 级别——只显示报错与警告。页面显示尾部 MAX_ERROR_LINES 行（防长文本
//    渲染卡顿），**导出取近 7 天全量留存**。
// ② 系统事件：HiAppEvent（官方当前推荐，FaultLogger.query 已 deprecated since 18）——七类
//    系统事件（分类表与取舍见 LogPageDataSource 头注释）系统自动记录、无需权限，应用
//    addWatcher 订阅拿到 AppEventPackageHolder，刷新时 takeNext() 拉取事件包。官方注意：
//    崩溃后应用已退出，需**再次启动应用**才能取到事件；未回调的事件在下次启动 addWatcher
//    后回调。拉到的记录进进程级有界缓存（LogPageDataSource），页面退出清显示但缓存不清
//   ——同一次运行内可反复查看。
//
// 交互（决明定稿）：不自动刷新——仅点标题栏右上角「更多」菜单（刷新 / 分享导出 / 清除运行
// 日志）才读取并显示。**退出本页即清空已刷新内容**（决明要求）：页面文本只在本页停留期间
// 留存，防长文本状态随进入次数越积越多。「清除运行日志」**二次确认**后清除（危险动作前置
// 确认口径），清除面含沙箱文件与页内事件缓存；说明行四行（报错口径 / 事件口径 / 占用口径 /
// 隐私承诺）。
//
// 文件拆分（按职责拆四份，红线见 AGENTS.md 防屎山节）：
// - LogPage.ets（本文件）：页面外壳——@State、生命周期、刷新/导出/清除调度、标题栏、确认弹窗
// - LogPageContent.ets：内容区 UI——说明文案/空态/事件区块与报错区块/分段胶囊悬浮层/菜单锚点
// - LogPageDataSource.ets：数据层——订阅/分流/缓存/日志读取过滤/占用统计与修剪/导出写文件
// - LogPageMoreMenu.ets：「更多」菜单——openMenu 内容构建与弹出（无状态弹窗 UI）
// 拆分规则：@State 与生命周期只在主文件；内容区组件靠 @Prop/@Link 接收数据、配色与档位
// 自订阅 AppStorage；数据层参数进、返回值/异常出，不碰 UI 不发 toast；后续加功能先判
// 归属再落文件，主文件再触红线须继续拆。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { envInfoLine } from '../common/EnvInfo';
import {
  IMMERSIVE_LEVEL_KEY,
  overlayMaterial,
  resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_RUN_LOG } from '../common/SettingSearch';
import { ConfirmDialog } from './chat/ConfirmDialog';
import {
  blockShownInTab,
  clearSystemEventCache,
  errorShownInTab,
  exportLogsToSandbox,
  fetchErrorLogLines,
  fetchSystemEvents,
  getCrashHolder,
  LOG_TAB_ALL,
  logUsageText,
  MAX_ERROR_LINES,
  pruneLogFiles,
  sandboxLogUsage,
  SysEventBlock,
  SysEventCounts,
  sysEventBlocks,
  sysEventCounts
} from './LogPageDataSource';
import { LogMoreMenuHost, MoreMenuCallbacks, LOG_MORE_MENU_ANCHOR_ID } from './LogPageMoreMenu';
import { LOG_TAB_ITEMS, LogPageContent } from './LogPageContent';
import { PageTopSegmentBand } from './SegmentBar';

@Component
export struct LogPage {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 沉浸光感整体档位（AppStorage 共享，驱动标题栏材质）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 顶部留白（vp，HomeNavigation PageMap 传入）：HDS 路径内容区延伸到标题栏背后
  // （渐变模糊蒙层透出滚动内容），语义与 InfoPage/AppearancePage 的 topPad 一致；回退路径传 0
  topPad: number = 0;
  // 系统事件区块（驱动 UI：仅刷新触发更新）——崩溃/冻屏/告警/终止/卡顿/资源/超时七类按
  // 分类表出块，空类不出现（LogPageDataSource.sysEventBlocks 单源，页面只负责显示与档位过滤）
  @State eventBlocks: SysEventBlock[] = [];
  // 报错日志文本（驱动 UI）：hilog 沙箱过滤 WARN/ERROR/FATAL 行（尾部 MAX_ERROR_LINES 行）
  @State errorText: string = '';
  // 统计行（驱动 UI）：空态提示 / 各类条数与报错行数
  @State logMeta: string = '';
  // 沙箱日志占用行（驱动 UI）：进页修剪与刷新时各更新一次（2026-09-27 P1-6 增）
  @State usageText: string = '';
  // 顶部分段分类选中项（官方 CapsuleSegmentButtonV2）：0 全部 / 1 崩溃 / 2 异常 / 3 报错
  //（档位常量与过滤判据单源在 LogPageDataSource——此前档位硬编码散在页面与内容区各一份）
  @State logTab: number = LOG_TAB_ALL;

  // 标题栏下方带承载（HDS 路径；选项表与内容区悬浮层共用单源 LOG_TAB_ITEMS，状态同源
  // = 本页 @State logTab）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: LOG_TAB_ITEMS,
      selectedIndex: $logTab
    })
  }
  // 「更多」官方菜单节点宿主（2026-08-30 反馈轮 13 起 AppMenuHost 薄壳——节点生命周期
  // 与弹出组装在基类：init 首建/弹前重建/dispose 成对，普通成员不驱动 UI）
  private moreMenu: LogMoreMenuHost = new LogMoreMenuHost();
  // 清除确认弹窗（构造在组件成员位——坑7 约束；动态文案/回调经 openClearConfirm 重建，
  // 先例 AttachmentManagePage.confirmCtrl / StoragePage.openConfirm；材质走 overlayMaterial）
  private clearConfirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '清除运行日志',
      message: '',
      confirmLabel: '清除',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  // 进页自检修剪：落盘 = 进程级常开（EntryAbility.onCreate 开启
  // PRIVATE_SANDBOX_WITH_CONSOLE，保留控制台输出；原页面级开关已退役——落盘只在页面停留
  // 期间开启导致事发日志不落盘）。进页保留 pruneLogFiles 自检一次：启动自检后新产生的日志
  // 可能已超 2MB 上限，进页修剪兜底（事件驱动非轮询，P1-2）；修剪结果转占用文案上屏，
  // 异常不阻断本页。★ 事件订阅不在本页（M3 拍板 6）：EntryAbility onCreate 经
  // ensureCrashWatcher 进程级注册 / onDestroy 注销（坑33 成对铁律），本页刷新时经
  // getCrashHolder 取共享句柄拉取
  aboutToAppear(): void {
    try {
      this.usageText = logUsageText(pruneLogFiles());
    } catch (err) {
      hilog.error(0xD5A0, 'LogPage', 'prune sandbox logs failed: %{public}s', JSON.stringify(err));
    }
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
        this.openClearConfirm();
      }
    };
  }

  // 页面销毁（pop 出栈）时：① 释放菜单内容节点——ComponentContent 不再使用时必须 dispose()
  //（ComponentContent.d.ts NOTE），否则随进入次数累积泄漏；② 清空已刷新的显示内容（决明
  // 要求，退出即清、再次进入为空白待刷新）。★ 事件**缓存**不清（LogPageDataSource 进程级
  // 留存）：再次刷新仍能看到同一次运行内取到的事件记录
  aboutToDisappear(): void {
    this.departed = true;
    this.moreMenu.dispose();
    this.eventBlocks = [];
    this.errorText = '';
    this.logMeta = '';
    this.usageText = '';
  }

  // 弹出「更多」官方菜单（标题栏按钮 action 触发）：
  // ★ 每次弹出前重建节点——ComponentContent 固化 UI 树不随深浅色切换更新（真机 Bug：浅切
  // 深后「刷新」仍黑色），重建保证菜单按当前主题构建；dispose 释放与新建成对，无泄漏。
  // systemMaterial = 官方菜单沉浸光感（REGULAR 基准，随总档——菜单统一拍板）
  private openMoreMenu(): void {
    this.moreMenu.rebuild(this.getUIContext(), this.moreMenuCallbacks());
    this.moreMenu.show(this.getUIContext(), LOG_MORE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, true));
  }

  // 刷新（仅「更多」菜单触发，不自动刷新）：① 拉取系统事件（消费订阅队列 → 分流入缓存 →
  // 出块）② 读沙箱报错日志（尾部 MAX_ERROR_LINES 行）③ 更新统计行与占用行。失败 toast
  // 提示（不静默失败）
  private refreshLogs(): void {
    try {
      fetchSystemEvents(getCrashHolder());
      this.eventBlocks = sysEventBlocks(true);
      const errorLines: string[] = fetchErrorLogLines(MAX_ERROR_LINES);
      this.errorText = errorLines.join('\n');
      const counts: SysEventCounts = sysEventCounts();
      let meta: string = '';
      if (counts.crash > 0) {
        meta += '崩溃与冻屏 ' + counts.crash + ' 条 · ';
      }
      if (counts.abnormal > 0) {
        meta += '运行异常 ' + counts.abnormal + ' 条 · ';
      }
      this.logMeta = meta + '报错日志 ' + errorLines.length + ' 行';
      this.usageText = logUsageText(sandboxLogUsage());
    } catch (err) {
      hilog.error(0xD5A0, 'LogPage', 'refresh logs failed: %{public}s', JSON.stringify(err));
      this.showToast('读取日志失败，请重试');
    }
  }

  // 导出文本组装（空串 = 当前分类下无可导出内容）：
  // ① 环境信息头（版本/系统/机型/导出时刻/范围——开发者拿到日志的第一问，单源见
  //    common/EnvInfo.envInfoLine）
  // ② 系统事件区块（按当前分类过滤；**完整缓存文本**，每条前置事件时间行）
  // ③ 报错日志（按当前分类过滤；**全量留存**——fetchErrorLogLines(0) 取近 7 天全部 W/E/F
  //    行，不用页面 500 行预览口径）
  private buildExportText(): string {
    const parts: string[] = [];
    parts.push('===== 环境信息 =====\n' + envInfoLine() + '\n导出于 ' + this.nowText() +
      '\n范围 近 7 天完整报错日志与已取到的系统事件记录');
    const blocks: SysEventBlock[] = sysEventBlocks(false);
    for (const block of blocks) {
      if (blockShownInTab(block.group, this.logTab)) {
        parts.push('===== ' + block.title + ' =====\n' + block.text);
      }
    }
    if (errorShownInTab(this.logTab)) {
      const all: string = fetchErrorLogLines(0).join('\n');
      if (all !== '') {
        parts.push('===== 报错日志 =====\n' + all);
      }
    }
    return parts.length > 1 ? parts.join('\n\n') : '';
  }

  // 导出时刻（页面本地时区：YYYY-MM-DD HH:mm:ss）
  private nowText(): string {
    const d: Date = new Date();
    const pad = (n: number): string => (n < 10 ? '0' + n : String(n));
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
      pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
  }

  // 分享/导出日志（官方分享面板 systemShare，@kit.ShareKit @since 11——「保存到本地」由
  // 面板自带操作区〔SAVE_AS_FILE 系统能力〕承担，另有应用分享目标区）。导出前自动刷新
  // 一次（保证最新；事件缓存不随刷新丢失）；在沙箱写临时 TXT（数据层 exportLogsToSandbox，
  // 唯一名 + 自动清理历史导出文件——数据有界），再拉起面板；保存/分享结果由系统面板反馈，
  // 无结果回调需求
  private async exportLogsToFile(): Promise<void> {
    this.refreshLogs();
    const content: string = this.buildExportText();
    if (content === '') {
      this.showToast('当前分类暂无日志可导出');
      return;
    }
    try {
      // 沙箱暂存（返回路径）；文件名 = 路径末段（时间戳唯一名，分享面板标题展示用）
      const path: string = exportLogsToSandbox(
        this.getUIContext().getHostContext() as common.Context, content);
      const fileName: string = path.substring(path.lastIndexOf('/') + 1);
      const record: systemShare.SharedRecord = {
        // txt 文件 = 官方 UTD 纯文本（UniformDataType.PLAIN_TEXT = 'general.plain-text'）
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        // App file URI（fileUri.getUriFromPath 产物）：官方 SharedRecord.uri 注释明示支持
        // App file URI（坑31 的 Image 解码问题不适用于分享面板）
        uri: fileUri.getUriFromPath(path),
        title: fileName,
        label: 'FILE'
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      // options 传空对象 = 官方默认（居中弹出、卡片预览、单选）；面板操作区默认含
      // 「另存为文件/复制/打印」等系统能力 + 应用分享目标
      await controller.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {});
      if (this.departed) {
        return;
      }
    } catch (err) {
      if (this.departed) {
        return;
      }
      hilog.error(0xD5A0, 'LogPage', 'share log file failed: %{public}s', JSON.stringify(err));
      this.showToast('导出失败，请重试');
    }
  }

  // 打开「清除运行日志」确认：文案写明清除范围与不可恢复（含沙箱文件与页内事件记录）；
  // 每次重建 controller 取当前文案与回调，成员位声明兜底（坑7）
  private openClearConfirm(): void {
    this.clearConfirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清除运行日志',
        message: '将删除沙箱内的运行日志文件，并清空本页已取到的系统事件记录。清除后无法恢复。',
        confirmLabel: '清除',
        onConfirm: (): void => {
          this.doClearLogs();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.clearConfirmCtrl.open();
  }

  // 清除执行（确认后调用）：官方 hilog.clean()（@since 26.0.0，「Delete all hilog logs in
  // the sandbox」）删沙箱内全部 hilog 日志文件 + 清进程级事件缓存（两者同属「本页能看到的
  // 记录」，只清其一会出现「清完页面还留着事件」的假象）。★ 先 flush 再 clean：残留缓冲
  // 在删除后回写会产生「清空后又出现日志」的假象；常开落盘下清空后新日志继续追加，无需
  // 重新开启
  private doClearLogs(): void {
    try {
      hilog.flush();
      hilog.clean();
      clearSystemEventCache();
      this.eventBlocks = [];
      this.errorText = '';
      this.logMeta = '';
      this.usageText = logUsageText(sandboxLogUsage());
      this.showToast('运行日志已清除');
    } catch (err) {
      hilog.error(0xD5A0, 'LogPage', 'clear sandbox logs failed: %{public}s', (err as Error).message);
      this.showToast('清除失败，请重试');
    }
  }

  // 本页 toast 统一入口：材质随沉浸光感总档（基准 THICK）。★ 本处是 toast 不是菜单——
  // 第三参保持 false（interactive 只给菜单/胶囊位，勿随菜单一并改 true）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false)
    });
  }

  // 内容区（@Builder：PageShell 的 @BuilderParam 须传 @Builder 方法/lambda 调用，不能
  // lambda 内直接写 UI——ArkTS 箭头函数体不能包含组件构造）
  @Builder
  LogContent() {
    Stack() {
      LogPageContent({
        topPad: this.topPad,
        eventBlocks: this.eventBlocks,
        errorText: this.errorText,
        logMeta: this.logMeta,
        usageText: this.usageText,
        logTab: $logTab
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（见 common/PageShell.ets 头注释）；本页特有：右上角
    //「更多」菜单（menuHds 原样传，见 LogPageMoreMenu.ets）
    PageShell({
      title: SETTING_TITLE_RUN_LOG,
      // 标题栏下方带承载（HDS 路径生效；回退路径壳不消费，LogPageContent 侧已二选一）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
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
      content: () => {
        this.LogContent()
      }
    })
  }
}
