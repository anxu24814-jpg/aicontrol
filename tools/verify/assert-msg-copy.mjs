// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// assert-msg-copy.mjs — 消息复制面板域断言（2026-09-18 消息复制优化笔立；123 组新组，
// 组号承接 122 组；域件拆分照 assert-ctx-usage 先例，门禁逐件登记）。
// 域内容：A 纯函数直跑（common/MarkdownText.ets 三函数真值表——复制本文件为 .ts 直跑，
// 断言的就是线上同一实现）/ B 长按入口链（ChatMessageItem 两泡挂点 + 守卫 + onCopyText
// 三级链）/ C 面板宿主（ChatPageContent 分支根 bindSheet + detents + 快照语义）/
// D 面板件形态（三件套 + 胶囊双口径 + 可选 Text + AI 标识 + 容器零边距红线 +
// 吸底「复制全文」键条〔2026-09-18 吸底键笔：Stack 底对齐 + 蒙层/尾占位同源 + 剪贴板链〕）/
// E 渲染器逐段复制退役（CubeMarkdownView isOnCopy）。
// 帮助同步钉在 assert-app-domain 95 组 J 段（2026-09-18 随形改写），本件不重复。
import { readFileSync } from 'node:fs';
import { copyFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { check, report, segOf } from './assert-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const ETS123 = path.join(here, '..', '..', 'entry', 'src', 'main', 'ets');
const rd123 = (rel) => readFileSync(path.join(ETS123, rel), 'utf-8');
const code123 = (t) => t.split('\n')
  .map((l) => l.replace(/\r$/, '').replace(/\/\/[^\n]*/g, '')).join('\n');

// ═══ A. 纯函数直跑（MarkdownText）═══
{
  const tmpDir = path.join(here, '.tmp');
  mkdirSync(tmpDir, { recursive: true });
  copyFileSync(path.join(ETS123, 'common', 'MarkdownText.ets'),
    path.join(tmpDir, 'MarkdownText.ts'));
  const { stripMarkdownText, removeTableBlocks, buildCopySheetText } =
    await import('./.tmp/MarkdownText.ts');
  check('123 纯函数-零 import 契约（复制直跑前提，破约即双实现漂移）',
    rd123('common/MarkdownText.ets').split('\n')
      .filter((l) => l.startsWith('import ')).length, 0);
  check('123 剥标记-加粗与标题与引用',
    [stripMarkdownText('**加粗**文字'), stripMarkdownText('# 标题\n正文'),
      stripMarkdownText('> 引用行')], ['加粗文字', '标题\n正文', '引用行']);
  check('123 剥标记-围栏内容原样与语言标签丢弃',
    stripMarkdownText('```ts\nlet a: number = 1;\n```'), 'let a: number = 1;');
  check('123 剥标记-链接取文字与图片丢弃（行尾修剪后）',
    stripMarkdownText('[文字](https://a.b) 与 ![图](x.png)'), '文字 与');
  check('123 剥标记-行内代码内容不被行内剥除波及（占位还原单点）',
    stripMarkdownText('代码 `x**y**` 保留'), '代码 x**y** 保留');
  check('123 剥标记-删除线与转义还原与水平分隔线整行删',
    [stripMarkdownText('~~划线~~'), stripMarkdownText('\\*转义\\*'),
      stripMarkdownText('---\n正文')], ['划线', '*转义*', '正文']);
  check('123 剥标记-单星与单下划线保守不剥（乘式 2*3*4 与 snake_case 防误伤）',
    [stripMarkdownText('2*3*4'), stripMarkdownText('a_b_c')], ['2*3*4', 'a_b_c']);
  check('123 剥标记-无序列表归一「- 」与有序保留与无标记文本原样',
    [stripMarkdownText('* 甲\n- 乙\n1. 丙'), stripMarkdownText('普通中文。\n第二行')],
    ['- 甲\n- 乙\n1. 丙', '普通中文。\n第二行']);
  const tableMd = '前\n| a | b |\n| - | - |\n| 1 | 2 |\n后';
  check('123 表格-剔除单点与块后空行分隔（决明「表格等先不显示在半模态中」）',
    [removeTableBlocks(tableMd), buildCopySheetText(tableMd, false)],
    ['前\n\n后', '前\n\n后']);
  check('123 表格-纯文本口径 = 去表格 + 剥标记复合',
    buildCopySheetText(tableMd + '\n**粗**', true), '前\n\n后\n粗');
  // 2026-09-18 自检轮补（围栏感知）：代码块里展示 md 表格语法或 ASCII 表格时整块被当
  // 正文表格删掉是内容丢失——两口径各自断言「围栏内行不动」与「围栏外照删」的边界
  const fenceTable = '示例：\n```md\n| a | b |\n| - | - |\n```\n结束';
  check('123 表格-围栏内表格行不误删（围栏感知；Markdown 口径原文等价留）',
    [removeTableBlocks(fenceTable), stripMarkdownText(fenceTable)],
    ['示例：\n```md\n| a | b |\n| - | - |\n```\n结束', '示例：\n| a | b |\n| - | - |\n结束']);
}

// ═══ B/C/D/E. 源码形态钉（剥注释源——注释里的同款字样不喂钉，坑38 口径）═══
{
  const item123 = code123(rd123('components/chat/ChatMessageItem.ets'));
  const cont123 = code123(rd123('components/chat/ChatPageContent.ets'));
  const sheet123 = code123(rd123('components/chat/MessageCopySheet.ets'));
  const cube123 = code123(rd123('components/chat/cube/CubeMarkdownView.ets'));

  // ── B. 长按入口链（ChatMessageItem 两泡挂点 + 守卫 + 三级回调）──
  check('123 入口-两泡长按手势恰两处（用户 Markdown 链尾 + 助手气泡体；再多即滥挂）',
    (item123.match(/\.gesture\(LongPressGesture\(\)/g) ?? []).length, 2);
  check('123 入口-守卫三条件（隐私会话零留痕 + 流式闸 + 空文本）与上行链在位',
    [item123.includes('private requestCopySheet(): void {'),
      item123.includes("if (this.privateSession || this.msg.streaming === true || this.msg.text === '') {"),
      item123.includes('this.onCopyText(this.msg.id);'),
      item123.includes('onCopyText: (msgId: string) => void = () => {')].every(Boolean), true);
  check('123 入口-直复制退役零回流（copyMessageText 本件零残留）',
    item123.includes('copyMessageText'), false);
  check('123 入口-ChatPageContent 接线（prop 上行 → openMsgCopySheet 解析）',
    [cont123.includes('onCopyText: (msgId: string): void => {'),
      cont123.includes('this.openMsgCopySheet(msgId);')].every(Boolean), true);
  check('123 入口-解析三守卫（privateSession 早退 + findMessage 空判含流式闸与空文本）',
    [segOf(cont123, 'private openMsgCopySheet(msgId: string): void {',
      'CopySheetBuilder()').includes('if (this.privateSession) {'),
      cont123.includes('const msg: ChatMessage | null = this.dataSource.findMessage(msgId);'),
      segOf(cont123, 'private openMsgCopySheet(msgId: string): void {',
        'CopySheetBuilder()').includes("msg === null || msg.streaming === true || msg.text === ''")].every(Boolean), true);

  // ── C. 面板宿主（ChatPageContent 分支根；规范-半模态 §1 判据三条在字段注释）──
  check('123 宿主-bindSheet 挂本组件根（声明式 + CopySheetBuilder 组件内 @Builder——坑51 红线）',
    [cont123.includes('.bindSheet(this.copySheetShow, this.CopySheetBuilder(), sheetPanelOptions('),
      cont123.includes('CopySheetBuilder() {')].every(Boolean), true);
  check('123 宿主-半屏起双停靠 + onWillDismiss 动画前同步收口（坑73）',
    [cont123.includes('[SheetSize.MEDIUM, SheetSize.LARGE]'),
      (cont123.match(/this\.copySheetShow = false;/g) ?? []).length >= 2].every(Boolean), true);
  check('123 宿主-快照三态（show/text/fromAssistant @State）',
    ['@State private copySheetShow: boolean = false;',
      '@State private copySheetText: string = \'\';',
      '@State private copySheetFromAssistant: boolean = false;'].every((s) => cont123.includes(s)), true);

  // ── D. 面板件形态（三件套 + 胶囊 + 可选 Text + AI 标识）──
  check('123 面板-壳三件套（HdsNavigation MODAL + sheetTitleBarOptions 同源 + 滚动感知 + 安全区）',
    ['sheetTitleBarOptions(', '.titleMode(HdsNavigationTitleMode.MODAL)',
      '.bindToScrollable([this.scroller])', '.ignoreLayoutSafeArea(']
      .every((s) => sheet123.includes(s)), true);
  check('123 面板-滚动容器 clip(false)（规范 §2 渐变模糊前提）',
    sheet123.includes('.clip(false)'), true);
  check('123 面板-口径胶囊（SegmentBar 共用件零参数覆盖 + 两口径下标映射 + 默认纯文本）',
    [sheet123.includes('SegmentBar({'), sheet123.includes("{ text: '纯文本' }"),
      sheet123.includes("{ text: 'Markdown' }"),
      sheet123.includes('buildCopySheetText(this.text, this.modeIdx === 0)')].every(Boolean), true);
  check('123 面板-整条可选 Text（LocalDevice = 跨段落选择载体，LogPageContent 先例口径）',
    sheet123.includes('.copyOption(CopyOptions.LocalDevice)'), true);
  check('123 面板-AI 标识行（助手消息常显，文案单源 AiDisclosure）+ 表格准备单源',
    [sheet123.includes('AI_CONTENT_LABEL'), sheet123.includes('fromAssistant'),
      sheet123.includes("from '../../common/MarkdownText'")].every(Boolean), true);
  check('123 面板-容器零左右边距红线（规范 §3——边距由 CARD_PANEL_WIDTH 卡线自理）',
    sheet123.includes('padding({ left:'), false);

  // ── D2. 吸底「复制全文」键条（2026-09-18 吸底键笔——决明「底部可否加吸底键，不随内容
  // 滚动，内容可滚出下面，点键即复制全文进剪贴板」；形制 = KimiFullInputSheet 同款）──
  const scrollSeg123 = segOf(sheet123, 'Scroll(this.scroller) {', '.align(Alignment.TopStart)');
  // ★ 2026-09-18 自检轮补形锚（原四条判据全为计数/存在性——「只计数不分形」的位置无关钉，
  // 把键带 Transparent 与蒙层 None **对调**后计数不变、全门禁零红〔变异实锤〕，而该缺陷
  // 真机后果 = 键带走 None ⇒ 「复制全文」键整体不可点）。补三条上下文锚：⑤蒙层 None 紧贴
  // 渐变块、⑥键带 Transparent 紧贴键带 padding、⑦三层叠序 Scroll → 蒙层 → 键带（乱序 =
  // 键被 Scroll 或蒙层盖住）。同钉内扩位，check 条数不变。
  check('123 面板-吸底键形态（Stack 底对齐恰一处 + Scroll 占满 + 键带 Transparent 紧贴键带 + 蒙层 None 紧贴渐变 + 三层叠序）',
    [(sheet123.match(/Stack\(\{ alignContent: Alignment\.Bottom \}\)/g) ?? []).length,
      scrollSeg123.includes(".height('100%')"),
      (sheet123.match(/\.hitTestBehavior\(HitTestMode\.Transparent\)/g) ?? []).length,
      (sheet123.match(/\.hitTestBehavior\(HitTestMode\.None\)/g) ?? []).length,
      // ⑤ 蒙层：渐变 colors 末项之后紧跟 None（对调成 Transparent 即红）
      /\$r\('app\.color\.page_bg'\), 1\]\]\s*\}\)\s*\.hitTestBehavior\(HitTestMode\.None\)/
        .test(sheet123),
      // ⑥ 键带：Transparent 之后紧跟键带唯一 padding（对调成 None 即红）
      /\.hitTestBehavior\(HitTestMode\.Transparent\)\s*\.padding\(\{ top: 12, bottom: this\.bottomInset \+ 12 \}\)/
        .test(sheet123),
      // ⑦ 叠序：Scroll 起 → 蒙层渐变 → 键本体；任一被提到前面即红
      sheet123.indexOf('Scroll(this.scroller)') < sheet123.indexOf('.linearGradient(') &&
      sheet123.indexOf('.linearGradient(') < sheet123.indexOf("Button('复制全文')")],
    [1, true, 1, 1, true, true, true]);
  check('123 面板-蒙层与尾占位同源（bottomFadeHeight 两处消费 + 常量单源含安全区——二一九改教训）',
    [(sheet123.match(/\.height\(this\.bottomFadeHeight\(\)\)/g) ?? []).length,
      sheet123.includes('return COPY_BOTTOM_FADE_HEIGHT + this.bottomInset;'),
      sheet123.includes('const COPY_BOTTOM_FADE_HEIGHT: number = 90;')], [2, true, true]);
  check('123 面板-复制全文链（剪贴板写入 + 助手附标识 + 空文本守卫 + 成功/失败两头反馈不静默）',
    [sheet123.includes('pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN'),
      sheet123.includes('this.fromAssistant ? withAiContentLabel(payload) : payload'),
      sheet123.includes("if (payload === '') {"),
      sheet123.includes("showToast({ message: '已复制' })"),
      sheet123.includes("showToast({ message: '复制失败，请重试' })"),
      sheet123.includes("hilog.error(0xD5A0, 'MsgCopySheet'")].every(Boolean), true);
  // （同族补锚：原两条计数判据在「材质挪去条上 / 四件套整体挪走」变异下计数不变仍绿——补③键本体
  // 锚 = `Button('复制全文')` 之后 450 字符内到 backgroundColor 四件套、其后 200 字符内到
  // systemMaterial 材质；两跳任一被打断即红。★ 首版写成「Button 后 600 字符内出现材质调用」
  // ——自检轮变异实锤该窗口过宽（材质挪到条上后仍在 600 内）故收紧为两跳锚）
  check('123 面板-条透明（全件 backgroundColor/systemMaterial 各恰一处且落在键本体；条不垫底不加材料）',
    [(sheet123.match(/\.backgroundColor\(/g) ?? []).length,
      (sheet123.match(/\.systemMaterial\(/g) ?? []).length,
      /Button\('复制全文'\)[\s\S]{0,450}?\.backgroundColor\(fallbackButtonBg\(this\.contentFallback, this\.immersiveLevel, true\)\)[\s\S]{0,200}?\.systemMaterial\(fallbackButtonMaterial\(this\.contentFallback, this\.immersiveLevel, true\)\)/
        .test(sheet123)], [1, 1, true]);
  check('123 面板-吸底键主操作四件套（primary=true 官方强调蓝 + contentFallback 双态订阅）',
    [sheet123.includes('fallbackButtonFont(this.contentFallback, true)'),
      sheet123.includes('fallbackButtonBg(this.contentFallback, this.immersiveLevel, true)'),
      sheet123.includes('fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true)'),
      sheet123.includes('fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel)'),
      sheet123.includes('@StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;')]
      .every(Boolean), true);

  // ── E. 渲染器逐段复制退役（Cube 引擎——「一次只能选中一段」病根）──
  check('123 渲染器-isOnCopy 关断恰一处（长按让位气泡层手势；代码块复制图标独立待真机核）',
    [cube123.match(/theme\.setIsOnCopy\((true|false)\)/g) ?? [],
      cube123.includes('theme.setIsOnCopy(false)')],
    [['theme.setIsOnCopy(false)'], true]);
}

report();
