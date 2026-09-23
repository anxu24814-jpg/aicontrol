// Cube markdown_hybrid 渲染器的 aicontrol 适配版（2026-09-02 阶段 5）：源 = chatcube
// components/ChatMarkdownHybridRenderer.ets（333 行，MIT——溯源与许可证声明同目录
// DisplaySyncTypewriter.ets 头注释；markdown_hybrid 包本体 Apache-2.0 已核）。
// 使命 = K1 闪屏根治：@lidary/markdown 全量重解析 × 打字机 30Hz 揭示 = 每秒约 30 次
// 全文重解析（调研档 §5.5 断点 2 预言）；CJMarkdown incrementalAnalysis 增量解析只重解析
// 追加部分。骨架保真（CJMarkdown 用法/config 签名缓存重建/插件开关集/ForEach renderKey
// 深浅切换重建）；对照 Cube 原件的裁剪与适配（台账登记）：
// 1. 色值：Cube 品牌米黄色系（themeMarkdown* 十余键）→ aicontrol 官方灰白观感双套硬编码
//    （华为官方色板系：正文近黑/近白、链接华为蓝、代码底灰）；
// 2. 参数面最小化：去 compact/字号缩放/latex 字号覆盖/标题色覆盖/全屏开关/复制回调族/
//    Cube 排版工具依赖（MarkdownTypographyUtils 未随迁——aicontrol 无该体系，字号取
//    ChatMessageItem 同档 15fp 基准内联计算）；
// 3. isInputEnded 恒 true + incrementalAnalysis 恒 true：aicontrol 消息内存态无流式标志
//    （ChatMessage 无 status 字段），增量解析对静态内容同样正确（首解析后无追加零开销）；
//    ★ 复制手势已关（2026-09-18 消息复制优化笔 setIsOnCopy(false)，见 buildConfig 内注）——
//    原口径「恒开复制手势 = 与 @lidary 行为一致」随之作废；
// 4. 代码块复制/全屏图标：不设自定义 $r 资源（Cube 引用自家 media）——用组件默认。
// 5. AI 标识（2026-09-10 合规上架笔）：Cube 的「复制回调族」原样不迁，但本适配层自设
//    两枚复制回调（setTextCopyCallback / setCodeCopyCallback）——复制动作后把剪贴板
//    重写为「原文 + 显式标识」（法规：复制/导出带走的 AI 生成内容须带显式标识；文案与
//    拼接单一来源 = common/AiDisclosure）。本视图仅助手消息使用（ChatMessageItem 的
//    assistant 分支），无需按角色区分是否 AI 内容。
import { CJMarkdown, LatexMathColorFormat, MarkdownConfiguration, MarkdownPlugin,
  MarkdownTheme } from '@cangjie-tpc/markdown_hybrid';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { withAiContentLabel } from '../../../common/AiDisclosure';

// 深浅双套官方观感色（ARGB；CJMarkdown theme 需数字色——@r 资源色不适配，双套切换由
// renderSignature 重建承接）
interface MdPalette {
  text: number;
  title: number;
  link: number;
  codeBg: number;
  codeText: number;
  quoteBg: number;
  tableBg: number;
  tableHeaderBg: number;
  tableAltBg: number;
  tableBorder: number;
}

const LIGHT_PALETTE: MdPalette = {
  text: 0xE6000000, title: 0xE6000000, link: 0xFF007DFF,
  codeBg: 0xFFF1F1F1, codeText: 0xE6000000, quoteBg: 0xFFF5F5F5,
  tableBg: 0xFFFFFFFF, tableHeaderBg: 0xFFF1F1F1, tableAltBg: 0xFFFAFAFA,
  tableBorder: 0xFFE0E0E0
};

const DARK_PALETTE: MdPalette = {
  text: 0xE6FFFFFF, title: 0xE6FFFFFF, link: 0xFF0A7DFF,
  codeBg: 0xFF262626, codeText: 0xE6FFFFFF, quoteBg: 0xFF2E2E2E,
  tableBg: 0xFF1D1D1D, tableHeaderBg: 0xFF2E2E2E, tableAltBg: 0xFF252525,
  tableBorder: 0xFF474747
};

// 正文字号基准（ChatMessageItem @lidary 渲染同档——15fp 族内联推导）
const BASE_TEXT_SIZE: number = 15;

@ComponentV2
export struct CubeMarkdownView {
  // Markdown 文本（V2 @Param——V1 父组件（ChatMessageItem）build 重跑时联动更新，
  // @lidary Markdown 同款嵌法）
  @Param content: string = '';
  // 深色模式（签名输入——切换触发 ForEach renderKey 变化整组件重建 = CJMarkdown 唯一
  // 可靠的主题刷新姿势，Cube 同款）
  @Param darkMode: boolean = false;

  private cachedConfig: MarkdownConfiguration | null = null;
  private cachedSignature: string = '';
  private cachedPlugin: MarkdownPlugin | null = null;

  // 渲染签名（config 缓存键 + ForEach renderKey 双用——本适配面唯一变量 = 深浅色）
  private renderSignature(): string {
    return this.darkMode ? 'dark' : 'light';
  }

  private buildConfig(): MarkdownConfiguration {
    const palette: MdPalette = this.darkMode ? DARK_PALETTE : LIGHT_PALETTE;
    const config: MarkdownConfiguration = new MarkdownConfiguration();
    const theme: MarkdownTheme = new MarkdownTheme();
    // 上下文（Cube 原版姿势——资源解析依赖；缺置是阶段 5 首轮正文空白的嫌疑之一）
    const hostContext: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext !== undefined && hostContext !== null) {
      theme.setContext(hostContext);
    }
    const textSize: number = BASE_TEXT_SIZE;
    const lineHeight: number = 22;
    const codeSize: number = Math.max(textSize - 1, 10);
    const blockSpacing: number = 6;

    theme.setIsMarkdownParserSync(false);
    theme.setIsCodeBlockParserSync(false);
    // ★ 2026-09-18 消息复制优化笔（决明「退役直接消息上复制功能，改为长按弹出半模态」）：
    // 渲染器逐段长按复制退役（isOnCopy = 「是否打开长按复制粘贴」，d.ets:1253 实锤语义；
    // 原 true 值本行改 false——逐段 Text 各自可选是「一次只能选中一段」的病根，复制统一
    // 收敛到气泡长按的「消息全文」面板〔自由跨段落选择〕，气泡层长按手势因此腾空
    //〔ChatMessageItem 助手分支〕）。两枚复制回调保留：代码块复制图标若独立于本开关
    //（编译包无法静态核，真机验证项——图标失效则走面板复制，登记观察项）；文本回调随
    // 选择关闭天然不触发
    theme.setIsOnCopy(false);
    theme.setBlockFirstTopMargin(0);
    theme.setBlockLastBottomMargin(0);
    theme.setBlockTopAndBottomMargins(blockSpacing);
    theme.setOpenGestureSwipe(false);

    theme.setParagraphTextSize(textSize);
    theme.setParagraphTextLineHeight(lineHeight);
    theme.setParagraphTextColor(palette.text);
    theme.setParagraphTopMargins(0);
    theme.setParagraphBottomMargins(0);
    // 标题族（1~3 为主消费档，4~6 收敛——官方观感无六级强层级需求）
    theme.setHeadingTextSize1(textSize + 7);
    theme.setHeadingTextSize2(textSize + 5);
    theme.setHeadingTextSize3(textSize + 3);
    theme.setHeadingTextSize4(textSize + 1);
    theme.setHeadingTextSize5(textSize);
    theme.setHeadingTextSize6(textSize);
    theme.setHeadingTextLineHeight1(lineHeight + 10);
    theme.setHeadingTextLineHeight2(lineHeight + 8);
    theme.setHeadingTextLineHeight3(lineHeight + 6);
    theme.setHeadingTextLineHeight4(lineHeight + 2);
    theme.setHeadingTextLineHeight5(lineHeight);
    theme.setHeadingTextLineHeight6(lineHeight);
    theme.setHeadingTextColor(palette.title);
    theme.setHeadingTextColor1(palette.title);
    theme.setHeadingTextColor2(palette.title);
    theme.setHeadingTextColor3(palette.title);
    theme.setHeadingTextColor4(palette.title);
    theme.setHeadingTextColor5(palette.title);
    theme.setHeadingTextColor6(palette.title);
    theme.setHeadingBreakColor(palette.tableBorder);
    theme.setHeadingTopMargins(blockSpacing);
    theme.setHeadingBottomMargins(Math.max(Math.round(textSize * 0.35), 4));

    theme.setLinkColor(palette.link);
    theme.setLinkSize(textSize);
    theme.setLinkLineHeight(lineHeight);
    theme.setLinkBackGroupColor(0x00000000);
    theme.setIsLinkUnderlined(false);

    theme.setBlockQuoteColor(palette.link);
    theme.setBlockQuoteBackGroupColor(palette.quoteBg);
    theme.setBlockQuoteWidth(3);
    theme.setBlockQuoteLeftMargin(10);
    theme.setBlockQuoteRightMargin(0);
    theme.setBlockQuoteTopAndBottomMargins(6);

    // 列表族
    theme.setBlockOrderedAndBulletTopAndBottomMargins(2);
    theme.setBlockLeftMargin(8);
    theme.setBlockRightMargin(0);
    theme.setOrderedListItemPrefixBold(false);
    theme.setOrderedListItemColor(palette.text);
    theme.setOrderedListItemSize(textSize);
    theme.setOrderedListItemLineHeight(lineHeight);
    theme.setBulletListItemColor(palette.text);
    theme.setBulletListItemSize(5);
    theme.setBulletListItemLineHeight(lineHeight);

    // 行内修饰
    theme.setStrikethroughColor(palette.text);
    theme.setUnderlineColor(palette.text);
    theme.setSubTextColor(palette.text);
    theme.setSubTextSize(Math.max(Math.round(textSize * 0.72), 8));
    theme.setSupTextColor(palette.text);
    theme.setSupTextSize(Math.max(Math.round(textSize * 0.72), 8));

    // 代码块族
    theme.setCodeTextColor(palette.codeText);
    theme.setCodeBackgroundColor(palette.codeBg);
    theme.setCodeTextSize(codeSize);
    theme.setCodeTypeface('monospace');
    theme.setCodeBlockTextColor(palette.codeText);
    theme.setCodeBlockTypeTextColor(palette.codeText);
    theme.setCodeBlockTypeTextPadding(4);
    theme.setCodeBlockBackgroundColor(palette.codeBg);
    theme.setCodeMultilineMargin(10);
    theme.setCodeBlockTypeface('monospace');
    theme.setCodeBlockTextSize(codeSize);
    theme.setCodeBlockLineHeight(lineHeight);
    theme.setCodeBlockRadius(8);
    theme.setCodeBlockLineNumberHide(false);
    theme.setCodeBlockIconTextHide(false);
    theme.setIsSeparateCodeBlock(false);

    // 表格族
    theme.setTableCellPadding(8);
    theme.setTableBorderColor(palette.tableBorder);
    theme.setTableBorderWidth(1);
    theme.setTableOddRowBackgroundColor(palette.tableBg);
    theme.setTableEvenRowBackgroundColor(palette.tableAltBg);
    theme.setTableHeaderRowBackgroundColor(palette.tableHeaderBg);
    theme.setTableTitleTextColor(palette.title);
    theme.setTableTitleTextSize(textSize);
    theme.setTableTextLineHeight(lineHeight);
    theme.setTableTitleLineHeight(lineHeight);
    theme.setTableContentTextColor(palette.text);
    theme.setTableContentTextSize(textSize);
    theme.setTableContentTextLineHeight(lineHeight);
    theme.setTableRadius(6);
    theme.setTableScrollBarShow(false);
    theme.setTableScrollBarColor(palette.tableBorder);

    theme.setThematicBreakColor(palette.tableBorder);
    // LaTeX（流式公式守卫在喂入侧 ChatLatexGuard——未闭合 $ 转义后再进渲染器）
    theme.setLatexDefaultText(true);
    theme.setLatexMathTextSize(textSize + 2);
    theme.setLatexMathTextColor(palette.text);
    theme.setLatexMathBackGroupColor(0x00000000);
    theme.setLatexMathColorFormat(LatexMathColorFormat.COLOR_FORMAT_BGRA_8888);
    theme.setLatexMathBlockCenter(false);
    theme.setIsDark(this.darkMode);

    // AI 显式标识（头部第 5 条）：文本/代码复制回调——复制动作后把剪贴板重写为「原文 +
    // 标识」。组件自带复制与本回调的先后语义未实测，但两态下「后写覆盖」都成立：回调即
    // 处理入口时本写入完成复制，回调仅通知时本写入覆盖组件刚写入的原文
    config.setTextCopyCallback((text: string): void => {
      this.copyWithAiLabel(text);
    });
    config.setCodeCopyCallback((code: string): void => {
      this.copyWithAiLabel(code);
    });

    config.setMarkdownTheme(theme);
    return config;
  }

  // 复制到剪贴板并附显式标识（官方粘贴板姿势同 ModelEditPage.copyModelId）；失败打日志
  // 不静默（P0-1），不弹 toast——避免与组件自带复制反馈重复
  private copyWithAiLabel(text: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, withAiContentLabel(text));
    pasteboard.getSystemPasteboard().setData(data).catch((e: Object): void => {
      hilog.error(0xD5A1, 'CubeMarkdownView', 'copy with ai label failed: %{public}s',
        (e as Error).message);
    });
  }

  private getConfig(): MarkdownConfiguration {
    const signature: string = this.renderSignature();
    if (this.cachedConfig !== null && this.cachedSignature === signature) {
      return this.cachedConfig;
    }
    this.cachedConfig = this.buildConfig();
    this.cachedSignature = signature;
    return this.cachedConfig;
  }

  // 插件开关集（Cube 全集随迁——表格/LaTeX/删除线/任务列表/linkify/html/上下标/toc/脚注）
  private getPlugin(): MarkdownPlugin {
    if (this.cachedPlugin !== null) {
      return this.cachedPlugin;
    }
    const plugin: MarkdownPlugin = new MarkdownPlugin();
    plugin.setIsTablePlugin(true);
    plugin.setIsLatexMathPlugin(true);
    plugin.setIsStrikethroughPlugin(true);
    plugin.setIsTaskListPlugin(true);
    plugin.setIsLinkifyPlugin(true, []);
    plugin.setIsHtmlPlugin(true);
    plugin.setIsSubPlugin(true);
    plugin.setIsSupPlugin(true);
    plugin.setIsTocPlugin(true);
    plugin.setIsFootnotePlugin(true);
    this.cachedPlugin = plugin;
    return plugin;
  }

  build() {
    Column() {
      // renderKey = 渲染签名：深浅色切换 = 整组件重建（CJMarkdown 不响应 config 变化，
      // Cube 同款唯一可靠刷新姿势）
      ForEach([this.renderSignature()], (_renderKey: string) => {
        CJMarkdown({
          content: this.content,
          isInputEnded: true,
          incrementalAnalysis: true,
          useCangjieComponent: true,
          config: this.getConfig(),
          plugin: this.getPlugin()
        })
      }, (renderKey: string): string => renderKey)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
