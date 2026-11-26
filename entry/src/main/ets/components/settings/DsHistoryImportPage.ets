// DeepSeek 历史导入页（DS 全家桶接入批 S5①）：数据与同步页「导入 DeepSeek 对话」入口卡 push
// 的三级页——选包 → 校验预览（会话/消息/图片计数 + 坏点分档呈报）→ 确认应用（图化落库新会话）。
// · 三态单页（'select' → 'preview'）照 MemoryImportPage 骨架：校验结果是页内上下文，「返回
//   重来」一次赋值即可，不退栈再进。
// · 解析句柄生命周期（成对释放红线）：dsParseArchiveZip 成功把解压临时目录 rootDir 交还本页
//   ——退出路径全集都清：应用成功/失败、返回重来、离开页面（aboutToDisappear）三处
//   releaseParsed；唯一例外 = 应用在途离页（apply 仍要读包内图片，释放权交 apply 的回执两路，
//   见 aboutToDisappear 注释）。校验失败的目录在解析函数内部自清（见 DsHistoryZip 文件头）。
// · alive 守卫（1712 销毁守卫同族）：aboutToDisappear 置 false，异步回调回来先判——已离开
//   不写 UI 不提示不 pop；**数据层意图照常完成**（导入中的会话继续落库、广播照发、临时文件
//   与解析目录照清——清理属资源对账，不受守卫拦截）。
// · 选包链照 DataSyncPage.doImport 先例：DocumentViewPicker maxSelectNumber=1 → copyFileExact
//   fd 链中转沙箱 → finally unlink 临时 zip；执行段遮罩 + 拦返回（BusyOverlay 单源），选包
//   交互段不盖遮罩。
// · 页级块一律挂 CARD_PANEL_WIDTH（宿主滚动列无左右 padding，写 '100%' 会贴屏缘）；内容区
//   页面文字键走 fallbackButton* 四件套双态（主键 primary=true 强调蓝，次钮坐 page_bg 用
//   fallbackButtonBgOffCard 白底——MemoryImportPage 同款）。
// · 滚动容器显式 scrollBar(BarState.Off)（宪法统一笔）；弹层零自绘（本页无对话框，toast 走
//   UIContext 形态）；面向用户文案规约（无冒号分号括号连环）。
// · 子页 pop 必带 result（坑17 口径）：应用成功 pop({ saved: true })；本页无保存动作的返回
//   不带 result。
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import { ROUTE_DS_HISTORY_IMPORT_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_DS_IMPORT } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_HEADER_GAP,
  cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { InfoCard } from '../InfoCard';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonBgOffCard, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { copyFileExact } from '../../common/ImageEditUtil';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { dsParseArchiveZip, dsReleaseParsedZip } from '../../common/chat/DsHistoryZip';
// 纯映射面（S1 拆分件）：呈报类型与节点上限常量与解析侧同源
import { DS_IMPORT_MAX_NODES, DsParseReport, DsParsedZip } from '../../common/chat/DsHistoryParse';
import { applyDsHistoryImport, DsImportApplyResult } from '../../common/store/DsHistoryImportApply';

const STAGE_SELECT: string = 'select';
const STAGE_PREVIEW: string = 'preview';

@Component
export struct DsHistoryImportPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 三态单页（见文件头）
  @State private stage: string = STAGE_SELECT;
  // 校验在途闸（选包 + 解析全程；预览/应用键同禁用防连点）
  @State private parsing: boolean = false;
  // 应用在途闸（apply 逐会话事务，连点会嵌套写串行链排队重复导入；在途禁用两键）
  @State private importing: boolean = false;
  // 校验呈报面（预览态计数与分档说明行；null = 无有效校验结果）
  @State private report: DsParseReport | null = null;
  // 解析句柄（rootDir 所有权在本页——三处退出路径 releaseParsed，见文件头；非 UI 驱动
  // 普通成员，UI 只读 report）
  private parsed: DsParsedZip | null = null;
  // 页面存活守卫（见文件头）
  private alive: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    this.alive = true;
  }

  aboutToDisappear(): void {
    // 离开 = 放弃本次导入：复位三态与在途闸防残留 + 释放解析句柄（离开时预览持有的临时
    // 目录必须清——资源对账不受 alive 守卫拦截，见文件头）。
    // ★ 2026-11-14 自检轮修：导入在途时不在此释放——applyDsHistoryImport 逐会话复制包内
    // 图片，根目录被提前删掉会让后续会话全部「源图片在本机已找不到」整会话回滚；释放权
    // 交给 apply 的 then/catch（两路都已调 releaseParsed，幂等）。真实场景 = 遮罩确认离页
    // 后导入仍在后台继续（数据层意图照常完成的承诺靠本分支守住）
    this.alive = false;
    if (!this.importing) {
      this.releaseParsed();
    }
    this.report = null;
    this.stage = STAGE_SELECT;
    this.parsing = false;
    this.importing = false;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 会话列表刷新广播（坑3 计数器口径，照 DataSyncPage 同款）
  private broadcastSessionReload(): void {
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }

  // 解析句柄释放（幂等——置 null 防二次释放）
  private releaseParsed(): void {
    if (this.parsed !== null) {
      dsReleaseParsedZip(this.parsed);
      this.parsed = null;
    }
  }

  // ── 选包 + 校验（主键）──

  private startSelectParse(): void {
    if (this.parsing || this.importing) {
      return; // 在途兜底防连点
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.parsing = true;
    const tempZip: string = ctx.cacheDir + '/ds_import_upload_tmp.zip';
    const runParse = async (): Promise<void> => {
      // 选包（交互段不盖遮罩——DataSyncPage 同口径）
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (uris.length === 0) {
        return; // 用户取消
      }
      // uri 字符串直传 fs 不可靠——统一走 copyFileExact 的 fd 链路中转沙箱（先例同款）
      copyFileExact(uris[0], tempZip);
      // 校验段遮罩（解压 + 解析大包非瞬返；盖浮层 + 拦返回）
      const busyToken: number = bumpBusyOverlay('正在校验备份包');
      try {
        const result: DsParsedZip = await dsParseArchiveZip(ctx, tempZip);
        // ★ alive 守卫：已离开即丢弃结果——但临时目录必须清（资源对账）
        if (!this.alive) {
          dsReleaseParsedZip(result);
          return;
        }
        this.releaseParsed(); // 防御性兜底（正常流预览态持有至应用/返回重来）
        this.parsed = result;
        this.report = result.archive.report;
        this.stage = STAGE_PREVIEW;
      } finally {
        releaseBusyOverlay(busyToken);
      }
    };
    runParse()
      .catch((e: Object): void => {
        // 校验失败留在选择态可重选（解析目录失败路径内部自清；中文拒收信息直呈）
        if (this.alive) {
          this.toast((e as Error).message);
        }
      })
      .finally((): void => {
        this.parsing = false;
        try {
          fs.unlinkSync(tempZip);
        } catch (e) {
          // 不存在 = 目标状态
        }
      });
  }

  // 返回重来（回选择态；解析句柄与呈报面同清）
  private backToSelect(): void {
    if (this.importing) {
      return; // 在途闸兜底
    }
    this.releaseParsed();
    this.report = null;
    this.stage = STAGE_SELECT;
  }

  // ── 应用（主键「导入 N 个会话」）：失败留在原态可重试，成功 pop 带回执 ──

  private doApply(): void {
    if (this.importing || this.parsing) {
      return; // 在途兜底防连点
    }
    if (this.parsed === null || this.report === null) {
      return; // 预览键已禁用，此处兜底
    }
    const planned: number = this.report.sessionCount;
    this.importing = true;
    // 执行段遮罩 + 拦返回（finally 归还令牌；落库写入不受离开影响——alive 守卫只拦 UI 面）
    const busyToken: number = bumpBusyOverlay('正在导入');
    applyDsHistoryImport(this.parsed)
      .then((result: DsImportApplyResult): void => {
        this.importing = false;
        // 刷新广播不受 alive 拦截（数据层意图已完成——列表须反映实况）
        this.broadcastSessionReload();
        this.releaseParsed(); // 会话已入库，解析临时目录使命结束
        if (!this.alive) {
          return; // 已离开页面：库已写入、广播已发，不提示不 pop
        }
        const failedTip: string = result.failedSessions > 0 ?
          '，' + result.failedSessions + ' 个会话未导入' : '';
        this.toast('已导入 ' + result.appliedSessions + ' 个会话' + failedTip);
        this.stage = STAGE_SELECT;
        this.report = null;
        this.pathStack.pop({ saved: true }); // 坑17：子页 pop 必带 result
      })
      .catch((e: Object): void => {
        this.importing = false;
        // 部分成功也可能已写库——刷新照发（DataSyncPage 同口径）
        this.broadcastSessionReload();
        this.releaseParsed();
        if (!this.alive) {
          return;
        }
        // 回选择态重新开始（逐会话事务非原子，失败后重试同一预览会重复导入已成功会话）
        this.report = null;
        this.stage = STAGE_SELECT;
        this.toast('导入失败：' + (e as Error).message);
      })
      .finally((): void => {
        releaseBusyOverlay(busyToken);
      });
  }

  // 预览分档说明行（坏点计数与成功计数严格分账——只呈报非零项，全零 = 无说明行）。
  // ★ 二期 S1 真保真：联网过程片段不再丢弃（已保留计数正呈报），零正文节点也不再丢行
  //（「跳过无正文的消息」计数器随之下线）
  private previewNotes(): string[] {
    const r: DsParseReport | null = this.report;
    const notes: string[] = [];
    if (r === null) {
      return notes;
    }
    if (r.preservedToolFragments > 0) {
      notes.push('联网过程 ' + r.preservedToolFragments + ' 段已保留');
    }
    if (r.badSessions > 0) {
      notes.push('跳过无法解析的会话 ' + r.badSessions + ' 个');
    }
    if (r.oversizedSessions > 0) {
      notes.push('有 ' + r.oversizedSessions + ' 个会话超过 ' + DS_IMPORT_MAX_NODES +
        ' 个消息节点上限，未导入（最大 ' + r.oversizedMaxNodes + ' 个节点）');
    }
    if (r.brokenChainSessions > 0) {
      notes.push('有 ' + r.brokenChainSessions + ' 个会话的消息树不完整，只导入能接上的部分');
    }
    if (r.missingCurrentSessions > 0) {
      // 自检轮分账：整会话跳过 ≠ 部分导入（旧文案把两者并进上一行，用户找不到被跳过的会话）
      notes.push('有 ' + r.missingCurrentSessions + ' 个会话找不到当前停留的消息，未导入');
    }
    if (r.badMessageRows > 0) {
      notes.push('跳过无法解析的消息 ' + r.badMessageRows + ' 行');
    }
    if (r.duplicateMessageRows > 0) {
      notes.push('跳过编号重复的消息 ' + r.duplicateMessageRows + ' 行');
    }
    if (r.droppedFragments > 0) {
      notes.push('跳过仍不支持的内容片段 ' + r.droppedFragments + ' 段');
    }
    if (r.missingImages > 0) {
      notes.push('缺失图片 ' + r.missingImages + ' 张');
    }
    if (r.missingSessionFiles > 0) {
      notes.push('索引中列出而包内没有的会话 ' + r.missingSessionFiles + ' 个');
    }
    return notes;
  }

  // ── UI 件 ──

  // 选择态：说明卡 → 主键（校验中禁用 + 状态行）
  @Builder
  SelectStage() {
    InfoCard({
      title: SETTING_TITLE_DS_IMPORT,
      text: '把 DeepSeek 官方导出的对话备份包导入本应用。导入前先校验并显示会话、消息与图片的数量，确认后会以新会话加入会话列表，不覆盖现有会话。'
    })
    Button('选择 DeepSeek 导出包')
      .width(CARD_PANEL_WIDTH)
      .enabled(!this.parsing && !this.importing)
      .fontColor(fallbackButtonFont(this.contentFallback, true))
      .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .onClick((): void => {
        this.startSelectParse();
      })
    if (this.parsing) {
      Text('正在校验')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
  }

  // 预览态：校验结果卡 → 分档说明行 → 口径说明卡 → 底部双键（间距三档照 MemoryImportPage）
  @Builder
  PreviewStage() {
    Column({ space: SECTION_HEADER_GAP }) {
      SectionHeader({
        title: '校验结果',
        hint: ''
      })
      Column({ space: 6 }) {
        Text('可导入会话 ' + (this.report !== null ? this.report.sessionCount : 0) + ' 个')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text('消息 ' + (this.report !== null ? this.report.messageCount : 0) + ' 行')
          .fontSize(14)
          .fontColor(cardDescColor())
          .width('100%')
        Text('图片 ' + (this.report !== null ? this.report.imageCount : 0) + ' 张')
          .fontSize(14)
          .fontColor(cardDescColor())
          .width('100%')
        ForEach(this.previewNotes(), (note: string) => {
          Text(note)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }, (note: string): string => note)
      }
      .alignItems(HorizontalAlign.Start)
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(CARD_RADIUS)
      InfoCard({ text: '导入会以新会话加入会话列表，不覆盖也不合并现有会话。' })
    }
    .width('100%')

    Row({ space: 10 }) {
      Button('返回重来')
        .layoutWeight(1)
        .enabled(!this.importing)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.backToSelect();
        })
      Button('导入 ' + (this.report !== null ? this.report.sessionCount : 0) + ' 个会话')
        .layoutWeight(1)
        .enabled(!this.importing && this.report !== null && this.report.sessionCount > 0)
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.doApply();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(VerticalAlign.Center)
    if (this.importing) {
      Text('正在导入')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        if (this.stage === STAGE_PREVIEW) {
          this.PreviewStage()
        } else {
          this.SelectStage()
        }
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

  build() {
    PageShell({
      title: SETTING_TITLE_DS_IMPORT,
      // 执行段返回拦截（BusyOverlay 单源——校验/导入中弹确认，离开 = 撤遮罩 + pop，
      // alive 守卫作废结果，临时资源由 aboutToDisappear 收口）
      onBackPressed: (): boolean => {
        return confirmLeaveBusyPage(this.getUIContext(), (): void => {
          this.pathStack.pop();
        });
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
