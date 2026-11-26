// 「消息字体」段（「字体」三级页整页承载，原为「外观显示」页内嵌段——不跳页；决明拍板参照外部样页只取布局不取配色）：
//   ⓪字体展示卡（段首，无节标题）：正文 + 代码样字合入一张只读展示卡，定高 280 内部纵向滚动（2026-11-09
//     卡底改 Theme.paperCardBg 纸黄 + CARD_RADIUS 无描边，样字仍走主文字色）；样字放大（正文 20fp/行高 34、代码 14fp/行高 20），卡内 13fp
//     灰标签「正文 / 代码」左对齐 + 0.5vp 分割线分节；Scroll 嵌在外观页外层滚动 = edgeEffect None +
//     nestedScroll SELF_ONLY（内层到顶/到底后不把余量递给外层页面，展示框内滚动与页面滚动分流）
//   ①正文字体：选择组卡（默认/衬线/仿宋/等宽/已导入字体…，行数随库变，行尾官方勾）——行标题以对应字体
//     渲染自证（GroupEntryItem.labelFontFamily）；进页先注册全部选项字体，未选中档跨重启也即时自证
//   ②代码字体：选择组卡（默认/JetBrains Mono/已导入字体…）——行标题同上自证
//   ③自定义字体：管理卡（说明小字 + 导入键 + 已导入列表，每行名 + 行尾删除图标键）
//   ④字体范围分段行卡（管理卡节之后，SettingSegmentRowCard 单源件）：左标题副标 + 右置分段
//     （仅会话页 / 全应用）——默认「仅会话页」（现状）；选「全应用」= 正文档经
//     ApplicationContext.setFont 下发应用级槽位全局生效，代码字体不随开关（单槽位被正文档占用，
//     恒会话页内）。启动链下发见 EntryAbility applyAppFontOnLaunch；运行时切换/切档/删除复位
//     在本件随开关态即时下发
// ★ 为什么从分段胶囊改组卡（真机 bug 根因）：卡内 CapsuleSegmentButtonV2 在光感环境下（未设材质实例默认
// THIN）具备「选中项背景跟随手指拖拽」官方行为——拖过「自定义」档触发回调风暴，旧设计「落自定义档且未
// 导入」自动拉起文件选择器且无在途闸 → 一次按住叠出多层选择器。组卡点行 = 纯 onClick；旧「选中即自动
// 拉起」设计整体删除（自定义字体 = 列表具名行；导入只由管理卡导入键触发）；导入链加在途闸 importing。
// ★ 数据模型 = 多字体共享库（ChatFont.ets 头注释）：导入一次正文/代码两域都可选；组卡行数据 = 内置档 +
// 库项（bodyFontRows/codeFontRows 单源）；刷新走「调用方键变重建」（GroupSettingCard.items 普通成员，
// 坑57 正解——外层 ForEach 键含选中值 + 库 JSON）。预览样字 = 公版文本（决明拍板弃歌词引用）；「等宽」
// 正文档与代码默认档走系统通用族名 monospace（真机探针项，不生效则经回退链落默认字体）。
// 字体来源：内置三款 OFL 开源字体（衬线 = Noto Serif SC / 仿宋 = 朱雀仿宋 / 代码 = JetBrains Mono，
// rawfile/fonts/ 随包）；导入 = DocumentViewPicker 免权限选择器 → fd 级拷入沙箱 filesDir/fonts/ →
// loadFontSyncWithCheck 校验（失败删半截件 + 明确报错）→ 入库（重名自动加序号）；删除 = ConfirmDialog
// 确认（坑7 成员位）→ 若正被选中先复位默认 → 移库项 → 删文件。写侧即时落盘无保存动作（@StorageLink
// 双向：选行 = 先注册成功后写键，注册失败不落选择；导入/删除同拍入库）；页内无返回语义（并入段落，无 pop）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CARD_PANEL_WIDTH, CARD_SPACING, SECTION_GAP, SECTION_HEADER_GAP, SECTION_TITLE_FONTSIZE, cardBg, cardBorderColor,  cardDescColor, cardTitleColor, paperCardBg, CARD_RADIUS } from '../../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial } from '../../common/ImmersiveLevel';
import { SETTING_TITLE_FONT_BODY, SETTING_TITLE_FONT_CODE,
  SETTING_TITLE_FONT_CUSTOM, SETTING_TITLE_FONT_SESSION_ONLY } from '../../common/SettingSearch';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, FONT_CUSTOM_DIR, FONT_CUSTOM_FILE_PREFIX,
  FONT_CUSTOM_PREFIX, FONT_LIB_MAX, FontLibEntry, PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY,
  PREF_FONT_LIB_KEY, PREF_FONT_SESSION_ONLY_KEY, bodyFontFamily, bodyFontRows, codeFontFamily,
  codeFontRows, displayNameOfFileName, fileNameOf, parseFontLib, serializeFontLib,
  uniqueLibName } from '../../common/ChatFont';
import { applyAppFontGlobal, ensureAllFontOptionsRegistered, prepareFontSelection,
  registerCustomFontPath, resetAppFont } from '../../common/ChatFontLoader';
import { copyFileExact } from '../../common/ImageEditUtil';
import { SettingSegmentRowCard } from '../SegmentBar';

const DOMAIN = 0x0000;
const TAG = 'ChatFontSection';

// 正文预览样字（公版文本——王维《终南别业》名句 + 法语全字母句含变音，顺带检验缺字回退）
const BODY_PREVIEW_TEXT: string = [
  '行到水穷处',
  '坐看云起时',
  'Portez ce vieux whisky',
  'au juge blond qui fume.'
].join('\n');
// 代码样例（ArkTS 节选——缩进 / 模板串 / 注释 / 对齐空格见等宽观感；行宽适配卡内不折行）
const CODE_PREVIEW_TEXT: string = [
  '// 字体选项行构建（节选）',
  'interface FontRow {',
  '  id: string;',
  '  label: string;',
  '}',
  '',
  'function buildRows(lib: FontLibEntry[]): FontRow[] {',
  '  const rows: FontRow[] = [',
  "    { id: 'default', label: '默认' },",
  "    { id: 'serif',   label: '衬线' }",
  '  ];',
  '  for (const entry of lib) {',
  '    rows.push(rowOf(entry));',
  '  }',
  '  return rows;',
  '}'
].join('\n');
// picker 后缀过滤（官方格式「描述|后缀」）
const FONT_PICKER_FILTER: string = '字体文件|.ttf,.otf,.ttc';
// 落盘前二次校验的允许后缀（选择器过滤在部分系统不强制）
const FONT_SUFFIXES: string[] = ['.ttf', '.otf', '.ttc'];

// 选择器 uri 后缀提取（小写含点；取不到回空串 = 不合规）
function fontSuffixOf(uri: string): string {
  const tail: string = uri.substring(uri.lastIndexOf('/') + 1);
  const dot: number = tail.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  return tail.substring(dot).toLowerCase();
}

// 显示名 = uri 尾部文件名（decode 去扩展；取不到回兜底名）
function fontDisplayNameOf(uri: string): string {
  const tail: string = uri.substring(uri.lastIndexOf('/') + 1);
  try {
    const decoded: string = decodeURIComponent(tail);
    if (decoded !== '' && decoded !== '/') {
      return displayNameOfFileName(decoded);
    }
  } catch {
    // 非法编码走兜底
  }
  return '自定义字体';
}

@Component
export struct ChatFontSection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（2026-10-25 卡底透明度笔即时面——外观页域字体段三卡）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 内容区按钮族双态参数（按钮四件套消费——契约见 ImmersiveLevel 头注释）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 字体三键 @StorageLink（写即持久化，无保存动作）
  @StorageLink(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageLink(PREF_FONT_CODE_KEY) fontCodeValue: string = FONT_CODE_DEFAULT;
  @StorageLink(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 字体范围开关：true = 仅会话页（默认，现状）/ false = 正文档全局（setFont 应用级槽位）；写即持久化。
  // 分段下标与布尔键双向映射（下标 0 = 仅会话页，互设守卫同值不递归——SettingSegmentRowCard
  // 各消费卡同款姿势；下标→键映射内含应用级槽位下发/恢复副作用，见其注释）
  @StorageLink(PREF_FONT_SESSION_ONLY_KEY) @Watch('onFontSessionOnlyChanged') fontSessionOnly: boolean = true;
  @State @Watch('onFontSessionIndexChanged') fontSessionIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 仅会话页〔键 true〕/ 1 = 全应用〔键 false〕，勿单独乱调）
  private fontSessionItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '仅会话页' },
    { text: '全应用' }
  ]);
  // 导入在途闸（防连点重复拉起选择器/叠加导入——旧胶囊拖动叠层 bug 的修复面之一）
  private importing: boolean = false;
  // 待删字体 id（弹窗异步确认载荷，跨帧存活；onConfirm 回调时机读取）
  private pendingRemoveId: string = '';
  // 删除确认弹窗（坑7：必须组件成员位构造——普通类 open() 静默无效；固定文案预建 controller）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除字体',
      message: '删除后需要重新导入才能再次使用。已选择该字体的消息字体会恢复默认。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.removeFontById(this.pendingRemoveId);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  // 进页注册全部选项字体（行标题「以对应字体自证」的必要一次成本，官方 loadFontSync 无异步形态）；
  // 库上限 FONT_LIB_MAX = 20，registeredAliases 幂等，重复进页不重复加载
  aboutToAppear(): void {
    ensureAllFontOptionsRegistered();
    // 存量键值对齐分段亮位（声明处默认值不代表键实际值——切过全应用的用户进页须亮对段）
    this.fontSessionIndex = this.fontSessionOnly ? 0 : 1;
  }

  // 用户点分段 → 写布尔持久键（互设守卫同值不递归；下标 0 = 仅会话页 = 键 true）。切换即时
  // 下发/恢复应用级槽位（原开关 onChange 语义）；失败 toast 不回滚键值（下次启动按落盘态重发）
  private onFontSessionIndexChanged(): void {
    const sessionOnly: boolean = this.fontSessionIndex === 0;
    if (sessionOnly === this.fontSessionOnly) {
      return;
    }
    this.fontSessionOnly = sessionOnly;
    const appFailure: string = sessionOnly ? resetAppFont(this.hostContext())
      : applyAppFontGlobal(this.hostContext());
    if (appFailure !== '') {
      this.toast(appFailure);
    }
  }

  // 其他写键方（备份导入恢复）→ 补正分段下标
  private onFontSessionOnlyChanged(): void {
    const idx: number = this.fontSessionOnly ? 0 : 1;
    if (idx !== this.fontSessionIndex) {
      this.fontSessionIndex = idx;
    }
  }

  // ── 选择提交（组卡行唯一入口：先注册成功后写键，失败 toast 不落选择）──
  private pickBody(value: string): void {
    if (value === this.fontBodyValue) {
      return;
    }
    const failure: string = prepareFontSelection(value, this.fontLibJson);
    if (failure !== '') {
      this.toast(failure);
      return;
    }
    this.fontBodyValue = value;
    // 全局态同步应用级槽位（正文档换了全局面跟着换；仅会话页态零动作——会话页显式链自订阅即刷）；
    // 失败 toast 但不回滚选择（键已落盘，下次启动重发）
    if (!this.fontSessionOnly) {
      const appFailure: string = applyAppFontGlobal(this.hostContext());
      if (appFailure !== '') {
        this.toast(appFailure);
      }
    }
  }

  private pickCode(value: string): void {
    if (value === this.fontCodeValue) {
      return;
    }
    const failure: string = prepareFontSelection(value, this.fontLibJson);
    if (failure !== '') {
      this.toast(failure);
      return;
    }
    this.fontCodeValue = value;
  }

  // 组卡行数据（内置档 + 库项，行数随库变；行标题族名随行值派生 = 选项字体「自证」）。GroupSettingCard
  // 内部 ForEach 键 = label 不含族名，族名随行值静态不变，无需进键
  private bodyItems(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const row of bodyFontRows(this.fontLibJson)) {
      const rowId: string = row.id;
      items.push({
        label: row.label,
        labelFontFamily: bodyFontFamily(rowId, this.fontLibJson),
        onClick: (): void => {
          this.pickBody(rowId);
        },
        selectedMark: (): boolean => this.fontBodyValue === rowId
      });
    }
    return items;
  }

  private codeItems(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const row of codeFontRows(this.fontLibJson)) {
      const rowId: string = row.id;
      items.push({
        label: row.label,
        labelFontFamily: codeFontFamily(rowId, this.fontLibJson),
        onClick: (): void => {
          this.pickCode(rowId);
        },
        selectedMark: (): boolean => this.fontCodeValue === rowId
      });
    }
    return items;
  }

  // 选择组卡重建键（键含选中值 + 库 JSON：任一变动 → 键变重建拉新行集与新勾位——坑57 正解）
  private bodyCardKey(): string {
    return this.fontBodyValue + '|' + this.fontLibJson;
  }

  private codeCardKey(): string {
    return this.fontCodeValue + '|' + this.fontLibJson;
  }

  // 库项（管理卡列表数据；本组件 @StorageLink 驱动重渲时重算即刷新）
  private libEntries(): FontLibEntry[] {
    return parseFontLib(this.fontLibJson);
  }

  // ── 导入链（选择器 → 沙箱拷贝 → 注册校验 → 入库；在途闸 + 上限收口）──
  private async importFontFile(): Promise<void> {
    if (this.importing) {
      return;
    }
    const lib: FontLibEntry[] = this.libEntries();
    if (lib.length >= FONT_LIB_MAX) {
      this.toast('最多保留 ' + FONT_LIB_MAX.toString() + ' 款自定义字体。请先删除不再使用的字体');
      return;
    }
    this.importing = true;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = [FONT_PICKER_FILTER];
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const sourceUri: string = uris[0];
      const suffix: string = fontSuffixOf(sourceUri);
      if (FONT_SUFFIXES.indexOf(suffix) < 0) {
        this.toast('只支持 ttf、otf 与 ttc 格式的字体文件');
        return;
      }
      const destPath: string = this.copyFontInto(context, sourceUri, suffix);
      const failure: string = registerCustomFontPath(destPath);
      if (failure !== '') {
        // 校验不过（空文件 / 损坏 / 不支持）→ 删半截拷贝件 + 明确报错，不入库
        this.removeFileQuietly(destPath);
        this.toast(failure);
        return;
      }
      // 入库（文件名时间戳 = 库项 id，唯一且跨重启稳定；重名显示名自动加序号）
      const next: FontLibEntry[] = [];
      for (const entry of lib) {
        next.push(entry);
      }
      const name: string = uniqueLibName(fontDisplayNameOf(sourceUri), lib);
      next.push({ id: fileNameOf(destPath), name: name, path: destPath });
      this.fontLibJson = serializeFontLib(next);
      this.toast('已导入 ' + name);
    } catch (error) {
      const failure = error as BusinessError;
      hilog.error(DOMAIN, TAG, '字体导入失败 code=%{public}d msg=%{public}s',
        failure.code, failure.message);
      this.toast('导入字体失败。' + (failure.message ?? ''));
    } finally {
      this.importing = false;
    }
  }

  // 沙箱拷贝（filesDir/fonts/chatfont_<时间戳>.<后缀>）：时间戳文件名 → 库项 id 唯一且稳定
  private copyFontInto(context: common.UIAbilityContext, sourceUri: string, suffix: string): string {
    const dir: string = context.filesDir + '/' + FONT_CUSTOM_DIR;
    try {
      fs.mkdirSync(dir, true);
    } catch (error) {
      // 目录已存在时 mkdirSync(path, true) 仍抛 EEXIST（13900015，真机实测——SkillPack 同款容错）：静默，其余上抛
      const failure = error as BusinessError;
      if (failure.code !== 13900015) {
        throw error as Error;
      }
    }
    const destPath: string = dir + '/' + FONT_CUSTOM_FILE_PREFIX + Date.now().toString() + suffix;
    copyFileExact(sourceUri, destPath);
    return destPath;
  }

  // ── 删除链（确认 → 复位选中 → 移库项 → 删文件；有序：先复位再删，防在册引用失效）──
  private confirmRemoveFont(entry: FontLibEntry): void {
    this.pendingRemoveId = entry.id;
    this.confirmCtrl.open();
  }

  private removeFontById(id: string): void {
    if (id === '') {
      return;
    }
    const customValue: string = FONT_CUSTOM_PREFIX + id;
    // ①正被选中先复位默认（正文/代码各自判）
    let bodyReset: boolean = false;
    if (this.fontBodyValue === customValue) {
      this.fontBodyValue = FONT_BODY_DEFAULT;
      bodyReset = true;
    }
    if (this.fontCodeValue === customValue) {
      this.fontCodeValue = FONT_CODE_DEFAULT;
    }
    // ②移库项
    const next: FontLibEntry[] = [];
    let removedPath: string = '';
    for (const entry of this.libEntries()) {
      if (entry.id === id) {
        removedPath = entry.path;
      } else {
        next.push(entry);
      }
    }
    this.fontLibJson = serializeFontLib(next);
    // ③删文件（不在 = 目标态静默）
    if (removedPath !== '') {
      this.removeFileQuietly(removedPath);
    }
    // ④全局态下正文档被复位 → 应用级槽位同步回默认族名（仅会话页态零动作）
    if (bodyReset && !this.fontSessionOnly) {
      const appFailure: string = applyAppFontGlobal(this.hostContext());
      if (appFailure !== '') {
        this.toast(appFailure);
      }
    }
  }

  private removeFileQuietly(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (error) {
      // 文件已不在 = 目标态达成，静默；其余错误 hilog 留痕不打断
      const failure = error as BusinessError;
      hilog.warn(DOMAIN, TAG, '字体文件删除失败 code=%{public}d msg=%{public}s',
        failure.code, failure.message);
    }
  }

  // 宿主上下文（setFont 下发用；取不到回 null——loader 侧 hilog 留痕并回错误文案，禁静默）
  private hostContext(): common.Context | null {
    const context = this.getUIContext().getHostContext();
    return context !== undefined ? context as common.Context : null;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ── 节标题（卡外左上分组标题：左缘与卡缘对齐。2026-11-01 板块标题改档——14fp 常规字重 +
  // 官方强调蓝，字号引 Theme SECTION_TITLE_FONTSIZE 单源）──
  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(SECTION_TITLE_FONTSIZE)
      .fontColor($r('sys.color.ohos_id_color_emphasize'))
      .width(CARD_PANEL_WIDTH)
      .textAlign(TextAlign.Start)
  }

  // 选择卡片组（外层键变重建 + 行尾勾；卡片壳由共用件提供——原随卡预览卡已退役，两样字上移段首）
  @Builder
  BodyCards() {
    ForEach([this.bodyCardKey()], (_key: string) => {
      GroupSettingCard({ items: this.bodyItems(), dividerLeft: 8 })
    }, (key: string): string => key)
  }

  @Builder
  CodeCards() {
    ForEach([this.codeCardKey()], (_key: string) => {
      GroupSettingCard({ items: this.codeItems(), dividerLeft: 8 })
    }, (key: string): string => key)
  }

  // 字体展示卡（段首）：正文 + 代码样字合入只读纸黄展示卡，定高 280 内部纵向滚动（样字恒超视口——滚动既是排版
  // 收口也是「卡内还有内容」的引导）；family 随三键 @StorageLink 即时重渲，选中款未注册/缺字经回退链落系统
  // 字体；嵌套滚动 = edgeEffect None + nestedScroll SELF_ONLY；样字 20/34 与 14/20，分节 = 灰标签 + 1vp 分割线
  //（纸黄底上 0.5vp 太淡，2026-11-09 批次单独升档；卡底 Theme.paperCardBg 全站仅此一处消费）
  @Builder
  FontShowcaseCard() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          Text('正文')
            .fontSize(13)
            .fontColor(cardDescColor())
          Text(BODY_PREVIEW_TEXT)
            .fontSize(20)
            .lineHeight(34)
            .fontColor(cardTitleColor())
            .fontFamily(bodyFontFamily(this.fontBodyValue, this.fontLibJson))
            .width('100%')
          // 纸黄底上 0.5vp 细线易消失，展示卡内分割线单独升到 1vp（色值仍单源）
          Divider()
            .width('100%')
            .strokeWidth(1)
            .color(cardBorderColor(this.appColorMode))
          Text('代码')
            .fontSize(13)
            .fontColor(cardDescColor())
          Text(CODE_PREVIEW_TEXT)
            .fontSize(14)
            .lineHeight(20)
            .fontColor(cardTitleColor())
            .fontFamily(codeFontFamily(this.fontCodeValue, this.fontLibJson))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(280)
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      // SELF_ONLY = 内层只响应自己，到顶/到底后不把余量交给外层页面（2026-10-19 反馈修正）
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    // 纸黄展示卡底（2026-11-09）：全站第四档淡染、只此一处消费；深色值单独反推，
    // 样字仍走 font_primary/font_secondary 主文字色，不为染色另开字色
    .backgroundColor(paperCardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 管理卡（自拼数据行卡——共用件组卡行尾无行动作键插槽，删除键照 ChatBranchSheet 行内图标键先例：无底 TEXTUAL + font_secondary）
  @Builder
  ManageCard() {
    Column({ space: 12 }) {
      // 说明小字（操作行上方——宪法「功能设置卡布局次序」）
      Text('导入的字体在正文字体与代码字体的列表里都可选用。支持 ttf、otf 与 ttc 格式')
        .fontSize(13)
        .fontColor(cardDescColor())
      Button('导入字体文件')
        .width('100%')
        .fontColor(fallbackButtonFontTinted(this.contentFallback))
        .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel, this.cardAlphaLevel))
        .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.importFontFile();
        })
      // 已导入列表（ForEach 键 = 库项 id + 末行位序标记）。★ 键含位序成分：末行分割线是位置依赖条件渲染，
      // 坑44 同键复用不重跑 itemGenerator——漏位序则导入/删除后分割线定格旧行序（官方口径：index 做条件渲染须进键）
      ForEach(this.libEntries(), (entry: FontLibEntry, index: number) => {
        this.LibRow(entry)
        if (index < this.libEntries().length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
        }
      }, (entry: FontLibEntry, index: number): string =>
        entry.id + (index === this.libEntries().length - 1 ? '|last' : ''))
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 库行（字体名 + 行尾删除图标键——无底 TEXTUAL 禁垫四件套，官方图标键形制）
  @Builder
  LibRow(entry: FontLibEntry) {
    Row({ space: 8 }) {
      Text(entry.name)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .onClick((): void => {
        this.confirmRemoveFont(entry);
      })
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
  }

  // 字体范围分段行卡（SettingSegmentRowCard 单源件）：左标题副标 + 右置分段胶囊，行不可点、
  // 分段为唯一控制面。写 PREF_FONT_SESSION_ONLY_KEY，下标→键映射即时下发/恢复应用级槽位
  //（见 onFontSessionIndexChanged 注释）
  @Builder
  SessionOnlySwitchCard() {
    SettingSegmentRowCard({
      title: SETTING_TITLE_FONT_SESSION_ONLY,
      subtitle: '控制自定义字体的生效页面',
      items: this.fontSessionItems,
      selectedIndex: $fontSessionIndex
    })
  }

  build() {
    // 段内布局：段首展示卡（无节标题）+ 三节 + 范围开关卡（自定义字体节之后）；间距三档走 Theme 常量
    //（板块间 SECTION_GAP / 标题下 SECTION_HEADER_GAP / 卡间 CARD_SPACING，条文 = 列表卡规范）
    Column({ space: SECTION_GAP }) {
      this.FontShowcaseCard()

      Column({ space: SECTION_HEADER_GAP }) {
        this.SectionTitle(SETTING_TITLE_FONT_BODY)
        Column({ space: CARD_SPACING }) {
          this.BodyCards()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Column({ space: SECTION_HEADER_GAP }) {
        this.SectionTitle(SETTING_TITLE_FONT_CODE)
        Column({ space: CARD_SPACING }) {
          this.CodeCards()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Column({ space: SECTION_HEADER_GAP }) {
        this.SectionTitle(SETTING_TITLE_FONT_CUSTOM)
        this.ManageCard()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      this.SessionOnlySwitchCard()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
