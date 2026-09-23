// 存储管理页（2026-09-09 附件全量落盘第二轮·存储管理页，任务书-存储管理页-20260909）：
// 设置页「存储管理」卡 push——六分类占用展示 + 可安全清理入口。官方《存储空间使用与文件
// 生命周期管理》V1【应当】条落地：应用内清理入口 / 统计与系统一致 / 清理范围与统计范围一致。
// · 卡1「存储占用」= 内容卡（控件非行形态，规范 §1.1「选择/内容卡」）：大数字（总占用 =
//   appSize + dataSize）+ 图区（占比条 ↔ 环形图，卡右上角切换键）+ 六分类明细行（序与段色
//   同源 = common/StorageStats.storageCategories / categoryBytes 单源，页面不另写顺序表）；
//   ★ 图区切换（2026-09-09 决明指令「存储管理是否也可以加上类似的功能？这应该已有成熟实现，
//   可以复用吧」）：默认占比条（官方 DataPanel 线性型），点右上角键切 components/stats/
//   RingChart（自 UsageRankRing 渲染层提炼的通用环形件，两页共用；环段恒 6 段 ≤ DataPanel
//   上限 9，无需「其余」聚合；不传中心文字——总占用由卡内大数字承载，环心重复且 formatBytes
//   文本过长会压环，2026-09-09 真机反馈修复）——RingChart 入参为普通成员，经键含数值与
//   色模式的 ForEach 下发（规范 §3 主通道「键变重建」，先例 PreferencesPage 恒单例纪元键）；
// · 卡2「可安全清理」= 内容卡：说明小字在按钮行上方（宪法「功能设置卡布局次序」）+ 三行
//   只读明细（应用临时文件 / 残留附件文件 / 运行日志）+ 主键「清理」（三项皆无可清时置灰，
//   下方状态提示行「暂无可清理内容」——任务书 §2.2 指定位置）；说明小字明示清理范围与卡1
//   「缓存」的扣减关系（2026-09-21 存储清理口径对齐笔）；
// · 卡3「会话附件」= 单条目入口卡（2026-09-15 附件管理列表笔，决明指令「会话附件的卡在
//   安全清理下面吧？」）：整卡可点 push 附件管理页——形态判据 = 列表卡片规范 §1.1「先判
//   行形态再数行数」（1 行跳转入口 = 单条目入口卡），HdsListItemCard + canIUse 自检、
//   无 HDS 回退自制白底卡（照 AboutPageCards 先例）；卡宽 CARD_PANEL_WIDTH（宿主 Scroll
//   无左右 16vp padding 口径，规范 §4.3）；不带数字——件数/占用已由卡1「对话附件」行承载，
//   重复即冗余且多一次聚合查询；卡1 六分类行形态零变化（仍只读明细，不加键不可点）；
// · 卡4「浏览器数据」= 内容卡（2026-09-21 存储清理口径对齐笔，危险操作靠下；同日「浏览器
//   数据口径修正笔」改域）：「共占用」一行只读明细 + 独立「清除」键 + 二次确认——浏览器
//   数据（Cookie / 站点数据 / 缓存）属官方术语的「可清理数据」而非「可清理缓存」，清了各
//   网站登录态失效、须重新登录，故不得并入「清理」主键（用户点「清理」不预期登录态消失）；
//   ★ 域 = 应用级 cache 下 web 子目录（官方 FAQ 指认的 Web 数据根），显示与清除同域：显示
//   = scanWebDataBytes（web 递归字节），清除 = cleanWebData 三官方 API（removeAllCache +
//   deleteAllData + clearAllCookiesSync）。同日修正前的实况 = 显示读 files 下 `__arkweb`、
//   清除落在 cache/web——两处各自自洽、数字永不动（决明真机报障「toast 说已清理，卡内数据
//   与顶部总数据都不变」），本笔把两侧一并钉到 cache/web 上；键可点判据 = 统计成功即可清
//   （**不得**写成 webBytes > 0——该值扫描失败时按 0 计，拿它置灰会让键恒灰、用户永远清
//   不了）；清除失败只走 toast，不置 loadFailed（页面级失败态单源在 load() 三条路径）；
//   builder 定义位置固定在 Content() 之后（68 组入口卡切片按 AttachmentCard → Content 取
//   段，插进该缝误红）；
// · 刷新链（规范 §3 白名单内）：aboutToAppear 首载 + onShown 重进现读（坑25 定稿「onShown
//   是可靠姿势，含 pop 返回」；首显与 aboutToAppear 同帧双触发由 loading 重入守卫去重）+
//   右上角手动刷新键（2026-09-09 决明指令，规范 §3 白名单第 4 条「手动刷新键」同族）+
//   清理完成后重载——无 tick 广播、无出页清空；
// · 加载态：官方【推荐】「加载完成前展示加载态或留空，不显 0」——大数字与分类值留空显
//   「正在统计…」，防误判「无可清理」；官方三值取不到时三项显「—」、自扫四项照常（取数
//   留痕在 StorageStats 侧），本页不白屏；
// · 失败态（2026-09-09 补，决明「统计失败后一直停在正在统计」）：三条失败路径同置
//   loadFailed——catch / 取不到上下文 / 库未就绪；置位后大数字显「统计失败」、卡2 状态行
//   显「统计失败，请重试」、主键置灰（旧 preview 不再承载可清理判定）；**下一次尝试开始即
//   复位**（含点刷新键重试——先回「正在统计…」再出结果）。官方「加载态不误导」的反面 =
//   失败后长期显加载态，让用户一直等；
// · 明细行 ForEach 键含内容与段色（键 = key + '|' + 文本 + '|' + 段色）——@Builder 值参按
//   快照渲染，键变重建是唯一可靠刷新通道（规范 §3 主通道「键变重建」；坑16 家族）；
//   ★ 段色入键（2026-09-09 二轮自检修）：圆点色走值参快照，键只含文本时深浅色切换不重建
//   ——占比条是属性绑定会随色模式变，圆点却停旧色，同屏不一致；
// · toast 统一入口（2026-09-21 告警收口笔）：本页七处提示统一走 showToast(message) 单入口
//   （P2-4 重复提取）——裸 getUIContext().getPromptAction() 调用点收成一处（入口自身），
//   构建期「Function may throw exceptions」告警随之降到基线之下；★ 只提取、不接光感材质
//   （全工程 toast 调用点带 systemMaterial 的属少数派，本页保持零视觉变化，材质化属另笔
//   光感对齐）；
// · 无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）；页面骨架照 UsageStatsPage（卡宽
//   CARD_PANEL_WIDTH / 间距 CARD_SPACING / Scroll 顶对齐坑18）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdsListItemCard, SuffixTextAndArrow } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ATTACHMENT_MANAGE_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_STORAGE } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, CARD_SPACING, badgeBg, cardBg, cardDescColor, cardTitleColor,
  usageAccentColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { CleanPreview, CleanResult, StorageBreakdown, StorageCategory, categoryBytes, cleanCache,
  cleanOrphanAttachments, cleanSandboxLogs, cleanWebData, formatBytes, officialDependentKeys,
  readStorageBreakdown, scanCleanables, storageCategories } from '../../common/StorageStats';
import { isReady, sharedRdbStore } from '../../common/store/ChatDb';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { RingChart } from '../stats/RingChart';
import { ATTACH_MANAGE_TITLE } from './AttachmentManagePage';

// 明细行数据（ArkTS 禁 build 内匿名对象字面量数组——类型化返回值方法；color 空串 = 不画圆点）
interface StorageRowItem {
  key: string;
  label: string;
  text: string;
  color: string;
}

@Component
export struct StoragePage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（2026-09-15 附件管理列表笔补传——卡3 整卡点击 push 附件管理页；本页此前无下级
  // 跳转故不接，PageMap 分支实参同步）
  pathStack: NavPathStack = new NavPathStack();
  // 统计就绪标记（false = 显「正在统计…」，不显 0——官方【推荐】）
  @State private loaded: boolean = false;
  @State private breakdown: StorageBreakdown | null = null;
  @State private preview: CleanPreview | null = null;
  // 清理进行中（主键文案转「清理中…」并置灰）
  @State private cleaning: boolean = false;
  // 统计失败态（true = 显「统计失败」而非永久「正在统计…」；三条失败路径置位、下一次尝试开始复位）
  @State private loadFailed: boolean = false;
  // 图形态切换（2026-09-09 决明指令「存储管理是否也可以加上类似的功能」）：false = 占比条
  // （默认）/ true = 环形图——形制照用量统计页排行卡（卡右上角切换键），会话内态不持久化
  // （与用量页两卡同口径，避免偏好面扩散）
  @State private ringOn: boolean = false;
  // 重入守卫：onShown 首显与 aboutToAppear 同帧双触发时去重（不叠两次目录扫描）
  private loading: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = 1;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 官方 HDS 列表项卡片可用性（卡3 单条目入口卡；syscap 自检——HdsListItemCard 要求
  // HDSComponent.Full，无 HDS 走自制白底卡回退，照 AboutPageCards 先例）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');
  // 清理确认弹窗（构造在组件成员位——坑7 约束；动态文案经 openConfirm 重建，先例
  // ChatSessionList.openDeleteConfirm）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '清理存储',
      message: '',
      confirmLabel: '清理',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.load();
  }

  // 统计 + 可清理预览并行拉取（互不依赖）；失败 toast 明示（P0-1 不静默假成功）并置失败态
  // ——三条失败路径（catch / 取不到上下文 / 库未就绪）任一都不得让页面永久停在「正在统计…」
  private load(): void {
    if (this.loading) {
      return;
    }
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.loadFailed = true;
      this.showToast('无法获取应用上下文');
      return;
    }
    const db: relationalStore.RdbStore | null = this.takeStore();
    if (db === null) {
      this.loadFailed = true;
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    Promise.all([readStorageBreakdown(ctx), scanCleanables(ctx, db)])
      .then((results: [StorageBreakdown, CleanPreview]): void => {
        this.breakdown = results[0];
        this.preview = results[1];
        this.loaded = true;
      })
      .catch((e: Object): void => {
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        this.showToast('存储统计失败，请重试（code ' + err.code + '）');
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 手动刷新（右上角键）：清理中忽略（清理结束自带重载，避免扫到半清理态）；统计中忽略
  // （load 内 loading 守卫会再拦，此处提前返回省一次调用）；失败态下点击即重试（load 开头
  // 复位 loadFailed，页面先回「正在统计…」再出结果）
  private onRefresh(): void {
    if (this.cleaning || this.loading) {
      return;
    }
    this.load();
  }

  // 库句柄（ChatDb 红线「未就绪禁发送」同口径——未就绪 toast 明示并中断，不静默）
  private takeStore(): relationalStore.RdbStore | null {
    if (!isReady()) {
      this.showToast('数据库尚未就绪，请稍后再试');
      return null;
    }
    return sharedRdbStore();
  }

  // 本页 toast 统一入口（P2-4：七处重复调用提取为一条，2026-09-21 告警收口笔）——失败提示
  // 仍逐处显式调用（P0-1 不静默）；只提取、不加材质：全工程 toast 调用点带 systemMaterial
  // 的属少数派（各页光感笔单独接入），本页保持零视觉变化
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 大数字文本：失败显「统计失败」/ 加载中显「正在统计…」/ 官方值缺位显「—」/ 否则格式化总占用
  private totalText(): string {
    if (this.loadFailed) {
      return '统计失败';
    }
    if (!this.loaded || this.breakdown === null) {
      return '正在统计…';
    }
    if (!this.breakdown.officialOk) {
      return '—';
    }
    return formatBytes(this.breakdown.total);
  }

  // 六分类明细行（序 = storageCategories 序；官方值缺位的三项显「—」）
  private rows(): StorageRowItem[] {
    if (this.breakdown === null) {
      return [];
    }
    const values: number[] = categoryBytes(this.breakdown);
    const officialKeys: string[] = officialDependentKeys();
    const categories: StorageCategory[] = storageCategories();
    const rows: StorageRowItem[] = [];
    for (let i = 0; i < categories.length; i++) {
      const needOfficial: boolean = officialKeys.includes(categories[i].key);
      rows.push({
        key: categories[i].key,
        label: categories[i].label,
        text: (!this.breakdown.officialOk && needOfficial) ? '—' : formatBytes(values[i]),
        color: this.segColor(i)
      });
    }
    return rows;
  }

  // 卡2 三行明细（键含文本 → 清理后数字变化即重建，规范 §3 主通道；失败态显「—」不显旧值）
  private cleanRows(): StorageRowItem[] {
    return [
      { key: 'cache', label: '应用临时文件', text: this.cacheText(), color: '' },
      { key: 'orphan', label: '残留附件文件', text: this.orphanText(), color: '' },
      { key: 'log', label: '运行日志', text: this.logText(), color: '' }
    ];
  }

  private cacheText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.cacheBytes);
  }

  private orphanText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.orphanBytes);
  }

  private logText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.logBytes);
  }

  // 卡4 明细「共占用」（浏览器数据域占用——该行显示的是占用，清除即全量，口径同为「显示 = 实删」）
  private webText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.webBytes);
  }

  // 卡4 明细行（与 cleanRows 同走「键含文本」重建通道——清除后占用变化即重建，规范 §3 主通道）
  // 行名 = 「共占用」：该值覆盖整个浏览器数据域（Cookie + 站点数据 + 缓存），非仅网页数据
  private webRows(): StorageRowItem[] {
    return [{ key: 'web', label: '共占用', text: this.webText(), color: '' }];
  }

  // 有无可清理内容（三项皆无可清 = 主键置灰 + 状态提示行）
  private canClean(): boolean {
    return this.preview !== null &&
      (this.preview.cacheBytes > 0 || this.preview.orphanCount > 0 || this.preview.logBytes > 0);
  }

  // 占比段色（与 UsageRankRing.rampColor 同手法：主蓝 ARGB 半透明阶梯，半透明透卡底深浅
  // 自适应；前五段 255→64，末段「其他」= badgeBg 灰——零新增色值）
  private segColor(index: number): string {
    if (index >= 5) {
      return badgeBg(this.appColorMode);
    }
    const alpha: number = Math.round(255 - index * (255 - 64) / 4);
    const hex: string = alpha < 16 ? '0' + alpha.toString(16) : alpha.toString(16);
    return '#' + hex.toUpperCase() + usageAccentColor(this.appColorMode).substring(1);
  }

  private segColors(): string[] {
    const colors: string[] = [];
    for (let i = 0; i < 6; i++) {
      colors.push(this.segColor(i));
    }
    return colors;
  }

  // 环形入环值（六分类恒 6 段 ≤ DataPanel 上限 9，无需「其余」聚合——与用量页 Top8 聚合
  // 语义不同故各自加工；未就绪返回空数组，调用点在统计成功分支内实际恒有值）
  private ringValues(): number[] {
    const b: StorageBreakdown | null = this.breakdown;
    return b === null ? [] : categoryBytes(b);
  }

  // 图形态数据签名（键变重建通道：RingChart 入参为普通成员，父重渲不更新它——规范 §3
  // 主通道；键含数值与色模式，清理后重载/点刷新/深浅色切换均触发重建）
  private ringKey(): string {
    return this.ringValues().join(',') + '|' + this.appColorMode;
  }

  // 清理确认（列三项大小——官方【推荐】「清理前展示可清理内容与大小并确认范围」）
  private openConfirm(): void {
    if (!this.canClean() || this.cleaning) {
      return;
    }
    const preview: CleanPreview | null = this.preview;
    if (preview === null) {
      return;
    }
    const message: string = '将清理临时文件 ' + formatBytes(preview.cacheBytes) +
      '、残留附件文件 ' + preview.orphanCount + ' 个共 ' + formatBytes(preview.orphanBytes) +
      '、运行日志 ' + preview.logCount + ' 份共 ' + formatBytes(preview.logBytes) +
      '。不影响已发送的消息。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清理存储',
        message: message,
        confirmLabel: '清理',
        onConfirm: (): void => {
          this.doClean();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 浏览器数据清除确认（危险操作隔离——ClearAllCookies 会使各网站登录态失效，须二次确认并
  // 明示后果；不复用「清理」主键，用户点「清理」不预期登录态消失）
  private openWebConfirm(): void {
    const preview: CleanPreview | null = this.preview;
    if (preview === null || this.loadFailed) {
      return;
    }
    const message: string = '将清除内置浏览器保存的 Cookie、网页数据与缓存，当前占用 ' +
      formatBytes(preview.webBytes) + '。清除后各网站的登录状态会失效，需要重新登录。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清除浏览器数据',
        message: message,
        confirmLabel: '清除',
        onConfirm: (): void => {
          this.doCleanWeb();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 浏览器数据清除执行：官方三 API 全量清除（removeAllCache + deleteAllData + clearAllCookiesSync，
  // 不硬删目录）→ 重扫如实显示；失败只走 toast，
  // 不置 loadFailed（页面级失败态只由 load() 的三条路径置位——统计成功即可清，清完重扫即
  // 如实反映剩余占用；toast 不报字节数：内核延迟落盘，差值不可信）
  private doCleanWeb(): void {
    const res: CleanResult = cleanWebData();
    this.load();
    this.showToast(res.failed > 0 ? '浏览器数据清除失败，' + res.failed + ' 项未清除' :
      '浏览器数据已清除');
  }

  // 清理执行：临时文件（含浏览器缓存）→ 残留附件文件 → 运行日志旧份（顺序执行，best-effort
  // 不中断）；完成后重载统计，失败直显错误码（取证增强口径）+ 重载保留已完成部分的结果
  private async doClean(): Promise<void> {
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.showToast('无法获取应用上下文');
      return;
    }
    const db: relationalStore.RdbStore | null = this.takeStore();
    if (db === null) {
      return;
    }
    this.cleaning = true;
    try {
      const cacheRes: CleanResult = await cleanCache(ctx);
      const orphanRes: CleanResult = await cleanOrphanAttachments(ctx, db);
      const logRes: CleanResult = cleanSandboxLogs();
      const freed: number = cacheRes.bytes + orphanRes.bytes + logRes.bytes;
      const failed: number = cacheRes.failed + orphanRes.failed + logRes.failed;
      this.load();
      this.showToast(failed > 0 ? '已清理 ' + formatBytes(freed) + '，' + failed + ' 项未清理' :
        '已清理 ' + formatBytes(freed));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.load();
      this.showToast('清理失败（code ' + err.code + '）');
    } finally {
      this.cleaning = false;
    }
  }

  // 卡1 存储占用（内容卡）
  @Builder
  UsageCard() {
    Column({ space: 10 }) {
      // 标题行 + 卡右上角图形态切换键（2026-09-09 新增，形制照用量统计页排行卡 ModelRankCard：
      // 标题 layoutWeight(1) 撑满 + 键落整卡右上角；键形 = TEXTUAL SymbolGlyph 18 +
      // font_secondary。图标示目标形态——占比条态显示环形图标 circle_on_circle，环形态显示
      // 柱状图标 rectangle_3_group，与用量页逐字同款）
      Row() {
        Text('存储占用')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Button() {
          SymbolGlyph(this.ringOn ? $r('sys.symbol.rectangle_3_group') :
            $r('sys.symbol.circle_on_circle'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.ringOn = !this.ringOn;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('应用总占用')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      if (this.loaded && this.breakdown !== null && !this.loadFailed) {
        Text(this.totalText())
          .fontSize(32)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        // 图形态分支（默认占比条——官方 DataPanel 线性型，max: 0 = 按值比例铺满，段色与明细
        // 圆点同源；环形态 = 通用件 RingChart，六分类段序与段色同上。切换转场 = 用量页同款
        // 官方 transition 交叉淡化 250ms EaseOut）
        if (this.ringOn) {
          Column() {
            ForEach([this.ringKey()], (_key: string) => {
              // 不传中心文字（2026-09-09 真机反馈「环内总占用过长与环重叠」）：总占用由卡内
              // 32fp 大数字承载，环心重复且 formatBytes 文本过长——RingChart 两串皆空即不渲染
              RingChart({
                values: this.ringValues(),
                colors: this.segColors(),
                note: '环段按分类顺序，灰色为其他'
              })
            }, (key: string): string => key)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        } else {
          // 占比条：官方 DataPanel 线性型（max: 0 = 按值比例铺满；段色与明细圆点同源）
          DataPanel({ values: categoryBytes(this.breakdown), max: 0, type: DataPanelType.Line })
            .width('100%')
            .height(10)
            .strokeWidth(10)
            .valueColors(this.segColors())
            .trackBackgroundColor(Color.Transparent)
            .closeEffect(true)
            .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        }
        ForEach(this.rows(), (row: StorageRowItem): void => {
          this.CategoryRow(row)
        }, (row: StorageRowItem): string => row.key + '|' + row.text + '|' + row.color)
      } else {
        Text(this.totalText())
          .fontSize(20)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 分类明细行（圆点段色 + 名称 + 右侧数值）
  @Builder
  CategoryRow(row: StorageRowItem) {
    Row({ space: 8 }) {
      Circle({ width: 8, height: 8 })
        .fill(row.color)
      Text(row.label)
        .fontSize(15)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
      Text(row.text)
        .fontSize(15)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 卡2 可安全清理（内容卡；说明小字在按钮行上方——宪法「功能设置卡布局次序」）
  @Builder
  CleanCard() {
    Column({ space: 10 }) {
      Text('可安全清理')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('清理临时文件、应用缓存与运行日志。清理后上方「缓存」的数字会同步减少。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      ForEach(this.cleanRows(), (row: StorageRowItem): void => {
        this.CleanRow(row)
      }, (row: StorageRowItem): string => row.key + '|' + row.text)
      Button(this.cleaning ? '清理中…' : '清理')
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel,
          true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(this.canClean() && !this.cleaning && !this.loadFailed)
        .onClick((): void => {
          this.openConfirm();
        })
      if (this.loadFailed) {
        Text('统计失败，请重试')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      // 空态文案只在统计成功后出（this.loaded 门）——加载中显「暂无可清理内容」与卡1「正在
      // 统计…」同屏矛盾，且违反官方「加载完成前留空，不显 0」；失败态走上一分支
      } else if (this.loaded && !this.canClean() && !this.cleaning) {
        Text('暂无可清理内容')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 清理明细行（只读：名称 + 右侧数值）
  @Builder
  CleanRow(row: StorageRowItem) {
    Row() {
      Text(row.label)
        .fontSize(15)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
      Text(row.text)
        .fontSize(15)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 卡3 会话附件（单条目入口卡，2026-09-15 附件管理列表笔）：整卡可点 push 附件管理页。
  // 副标题不带数字（件数/占用已由卡1「对话附件」行承载——重复即冗余且多一次聚合查询）
  private openAttachManage(): void {
    this.pathStack.pushPathByName(ROUTE_ATTACHMENT_MANAGE_PAGE, null);
  }

  @Builder
  AttachmentCard() {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: ATTACH_MANAGE_TITLE },
          secondaryText: { text: '查看并管理已发送的附件' }
        },
        // 官方「文字 + 箭头」后缀组合（SuffixTextAndArrow——关于页三卡同款）
        suffixItem: new SuffixTextAndArrow({ text: '查看' }),
        cardBorderRadius: 16,
        onClick: () => {
          this.openAttachManage();
        }
      })
      .width(CARD_PANEL_WIDTH)
    } else {
      // 回退：自制白底卡（无 HDS Full 能力；左两行文字 + 右「查看 + chevron」，官方设置
      // 列表视觉——AboutPageCards 回退分支同款）
      Button() {
        Row() {
          Column({ space: 4 }) {
            Text(ATTACH_MANAGE_TITLE)
              .fontSize(16)
              .fontColor(cardTitleColor())
            Text('查看并管理已发送的附件')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('查看')
            .fontSize(13)
            .fontColor(cardDescColor())
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([cardDescColor()])
        }
        .width('100%')
        .padding(16)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .onClick(() => {
        this.openAttachManage();
      })
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        this.UsageCard()
        this.CleanCard()
        // 卡3 会话附件入口卡（2026-09-15 附件管理列表笔；决明指令置于「可安全清理」卡下方）
        this.AttachmentCard()
        // 卡4 浏览器数据（2026-09-21 存储清理口径对齐笔；危险操作靠下）
        this.WebDataCard()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // 卡4 浏览器数据（内容卡，2026-09-21 存储清理口径对齐笔；同日口径修正笔改域）：内置浏览器
  // （ArkWeb）的 Cookie、网页数据与缓存不在「可安全清理」口径内——清了各网站登录态失效、需
  // 重新登录，属「可清理数据」非「可清理缓存」，故独立入口 + 二次确认，不并入「清理」主键
  // （危险操作隔离红线）；「可安全清理」侧的对应动作 = 跳过应用级 cache 下的 web 子目录
  // （StorageStats.cleanCache），两侧同域不重叠。
  // ★ 键可点判据 = 统计成功即可清（不得写成 webBytes > 0：该值在扫描失败或目录不可读时按 0
  // 计，拿它置灰会让键恒灰、用户永远清不了——正是本笔要修的那类「够不着就置灰」缺陷同形）；
  // 清除失败只走 toast，不置 loadFailed（页面级失败态单源在 load() 三条路径）。
  // ★ 本 builder 定义位置固定在 Content() 之后、build() 之前：assert-feature-domain 68 组的
  // 入口卡切片按「AttachmentCard → Content」取段（卡宽恰 2 处、段内零 formatBytes），插进
  // 该缝会连带误红。
  @Builder
  WebDataCard() {
    Column({ space: 10 }) {
      Text('浏览器数据')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('清除内置浏览器保存的 Cookie、网页数据与缓存。清除后各网站的登录状态会失效，需要重新登录。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      ForEach(this.webRows(), (row: StorageRowItem): void => {
        this.CleanRow(row)
      }, (row: StorageRowItem): string => row.key + '|' + row.text)
      Button('清除')
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel,
          true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(this.preview !== null && !this.loadFailed)
        .onClick((): void => {
          this.openWebConfirm();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_STORAGE,
      // 右上角刷新键（2026-09-09 决明指令；规范 §3 白名单第 4 条「手动刷新键」同族）——刷新
      // = 重走 load() 单一路径（readStorageBreakdown + scanCleanables 现读，无缓存层）；菜单
      // 项是普通参数、不随 @State 更新（坑16 家族），故不做状态驱动置灰，守卫写进 onRefresh
      menuHds: {
        value: [{
          content: {
            icon: $r('sys.symbol.arrow_clockwise'),
            action: (): void => {
              this.onRefresh();
            }
          }
        }]
      },
      menuNav: [{
        value: '刷新',
        // 符号资源须走 symbolIcon（`icon` 是图片槽位，Symbol 图标不显示——2026-09-13 全族收口）
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')),
        action: (): void => {
          this.onRefresh();
        }
      }],
      // 页面每次显示重拉（坑25 定稿「onShown 是可靠姿势，含 pop 返回」——栈下层收不到广播
      // 时的兜底；首显与 aboutToAppear 同帧双触发由 load 内 loading 守卫去重）
      onShown: (): void => {
        this.load();
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
