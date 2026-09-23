// 知识库条目编辑页（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.5③）：
// 条目三字段（名称 / 关键词 / 正文）与附件文件的新建与编辑——param = KnowledgeEditParam
//（bookId + entryId，'' = 新建）。
// ★ 2026-09-23 知识库文件笔：整页由「单页单卡表单」改**三段分段胶囊**（条目 / 正文 / 文件），
// 骨架照 SkillEditPage（Stack 叠〔内容滚动层 + 分段胶囊悬浮固定层〕，胶囊吸顶不随内容滚，参数
// 单源在 SegmentBar）。原「不做分段页签：只有三个字段，分段是纯噪声」的判断随本次新增第三段
// （文件）而失效——三段里第三段与前两段是**异构内容**（字段 / 长文 / 附件清单），分段才有收益。
// · ★ 新建态两段（条目 / 正文）：附件要挂在条目行上，尚未落库时没有可配对象——第三段整段
//   不出现，而不是「出现了但空」（SkillEditPage 同款口径）。落库后仍 pop 回清单页，附件在
//   重进编辑页时配。
// · 标题栏「保存」单键（checkmark；HDS 官方菜单数组 + 回退 nav 数组两条路径都给）——**保存
//   的是条目三字段**，附件在自己的编辑页里即时落库（两处职责不串）。
// · 保存链：加载闸（编辑态必须读回行后才许保存——未加载完落库会把空表单覆盖既有行，
//   SkillEditPage 的 O-13 闸同款）→ 名称校验（去空格为空即 toast 并中断，P0-1 不静默）
//   → **重名拦截**（2026-09-21 知识库第二笔下本：同书同名 toast 拦截不落库，判定单源 =
//   KnowledgeText.knowledgeTitleTaken）→ insert（source='user'）/ update（0 行 affected 由
//   KnowledgeDb 抛中文错）→ toast「已保存」→ pop({ saved: true }) 触发书详情页 onPop 重拉。
// · 关键词字段是**可选**的（仅参与检索加权与展示，不接触发逻辑）；正文也允许为空
//   （条目至少有个名字就能在清单里看见并按名称命中）。
// · 附件链（2026-09-23 知识库文件笔）：文件卡列出本条目附件（件名 + 字数 + 行内编辑/删除图标
//   键）+ 「新建文件」「上传文件」并排胶囊双键；上传 = DocumentViewPicker 免权限选择器 → 读
//   UTF-8（KnowledgePack.readPickedKnowledgeFileText 带字节粗拦与乱码判拒）→ 校验 → **带初值
//   进文件编辑页**让用户先过目再存（SkillEditPage 同款审阅哲学）。件名查重与件数上限两道硬拒
//   在 KnowledgeDb 写入侧（本页只做入口拦截与文案）。
// · 卡内说明分层（2026-09-23 文案收束 + 同日字段标签补正）：多句的机制说明（是什么 / 为什么）
//   收进卡标题行右端 ⓘ 气泡（InfoHintButton 单源复用），卡面只留「输入时就用得到」的短句与
//   **字段标签行**。★ 标签 ≠ 说明，收说明时不可连标签一起收：多字段卡（条目的名称 / 关键词）
//   每个输入框头顶一个 13fp 灰标签（「标签在上 + 整宽输入框」，两字段各包一层 Column space 6），
//   单字段卡（正文 / 附件文件）由卡标题承载标签——两者合起来 = 每个输入框都有**恒可见**的字段名
//   （占位符在框内一有内容就不显示，只靠它认字段，编辑态两个框就分不清了）。形制先例 =
//   ProviderConfigPanel.FieldInput「名称 / Base URL」、BalanceConfigPage.BalanceField、
//   ModelEditPage 基础卡「模型 ID / 模型名称」，口径见 SearchEngineDetailPage 头注释「表单形制：
//   卡标题即字段标签（标签在上 + 整宽输入框）」。正面依据另有《规范-列表卡片与组卡》§4.3
//   「长说明文字一律收入板块头气泡，板块面只留标题」；宪法「功能设置卡布局次序」约束的是
//   「说明小字垫在操作按钮行下方」，不适用于输入框的字段标签与字段说明。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { SegmentButtonV2Items, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_EDIT_PAGE, ROUTE_KNOWLEDGE_FILE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE,
  SEGMENT_BAR_HEIGHT
} from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  broadcastKnowledgeList, deleteEntryFile, insertEntry, KnowledgeEntryInput,
  KnowledgeEntryRow, KnowledgeFileRow, queryEntries, queryEntry,
  queryEntryFiles, toEntryItems, updateEntry
} from '../../common/store/KnowledgeDb';
import { pickedKnowledgeName, readPickedKnowledgeFileText } from '../../common/KnowledgePack';
import {
  KNOWLEDGE_CONTENT_MAX, KNOWLEDGE_FILE_CONTENT_MAX, KNOWLEDGE_FILE_EXTS,
  KNOWLEDGE_FILE_MAX_COUNT, KNOWLEDGE_KEYWORDS_MAX,
  KNOWLEDGE_TITLE_MAX, KnowledgeFileValidation, knowledgeTitleTaken,
  validateKnowledgeFileArgs
} from '../../common/KnowledgeText';
import { KnowledgeEditParam } from './KnowledgeBookPage';
import { KnowledgeFileEditParam } from './KnowledgeFileEditPage';
import { InfoHintButton } from '../InfoHintButton';
import { ConfirmDialog } from '../chat/ConfirmDialog';

// 标题栏「保存」单键（checkmark；SkillEditPage / MemoryEditPage 同款形制）
function knowledgeSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function knowledgeSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

@Component
export struct KnowledgeEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属库 id 与编辑对象 id（'' = 新建）；构造后不变（坑30）
  private bookId: string = '';
  private entryId: string = '';
  // 表单三字段（@State 驱动输入回显）
  @State private title: string = '';
  @State private keywords: string = '';
  @State private content: string = '';
  // 附件文件清单（仅编辑态加载——新建态尚无条目行可挂文件，见文件头）
  @State private files: KnowledgeFileRow[] = [];
  // 分段页签选中项（0 条目 / 1 正文 / 2 文件——@State 驱动面板切换）
  @State private segIndex: number = 0;
  // 加载完成闸（★ SkillEditPage 的 O-13 闸同款）：.catch 只 toast 而页面仍停在「编辑态空
  // 表单」——此时用户填写保存会走 updateEntry(this.entryId) 命中真实行并覆盖其内容。
  // 闸 = 未加载完成不许落库；新建态无待读行、显式置真；读成功置真；读失败保持假 = 保存链
  // 首拦一道显式提示（不弹出用户，返回重进即可重读）。普通成员即可（不驱动 UI 勿 @State）
  private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 文件卡双键胶囊的双态入参（内容区回退函数族，口径见 common/ImmersiveLevel.ets 头注释）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 分段页签选项（两套预建实例，build 内按 entryId 择一）：编辑态三段；新建态两段（附件要
  // 挂在条目行上，没行就没有这一页，见文件头）。段数在本页生命周期内恒不变（entryId 构造后
  // 不变，坑30），故非响应式成员即可
  private tabItemsEdit: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '条目' },
    { text: '正文' },
    { text: '文件' }
  ]);
  private tabItemsNew: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '条目' },
    { text: '正文' }
  ]);
  // 行内删除附件的目标行与确认弹窗（成员位控制器——坑7 约束）
  private fileDeleteTarget: KnowledgeFileRow | null = null;
  private fileConfirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除文件',
      message: '删除后无法恢复。助手读取这条条目时也不再看到这个文件。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doRemoveFile();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_KNOWLEDGE_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last === null) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少条目参数' });
      this.pathStack.pop();
      return;
    }
    const param = last as KnowledgeEditParam;
    this.bookId = param.bookId;
    this.entryId = param.entryId;
    if (this.entryId === '') {
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」，不拦新建）
      return;
    }
    queryEntry(this.entryId)
      .then((row: KnowledgeEntryRow | null): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '条目不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.title = row.title;
        this.keywords = row.keywords;
        this.content = row.content;
        this.loaded = true;
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '条目读取失败：' + (e as Error).message
        });
      });
  }

  // 附件清单重拉（文件编辑页保存/删除返回后经 onPop 调；失败 toast 不静默 P0-1）
  private reloadFiles(): void {
    if (this.entryId === '') {
      this.files = [];
      return;
    }
    queryEntryFiles(this.entryId)
      .then((rows: KnowledgeFileRow[]): void => {
        this.files = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '附件读取失败：' + (e as Error).message });
      });
  }

  // 文件编辑页跳转（新建/编辑共用；pop 带 result → 重拉清单，坑17）
  private openFilePage(fileId: string, draftName: string, draftContent: string): void {
    const param: KnowledgeFileEditParam = { entryId: this.entryId, fileId: fileId,
      draftName: draftName, draftContent: draftContent };
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_FILE_EDIT_PAGE, param, (): void => {
      this.reloadFiles();
    });
  }

  // 上传文件：DocumentViewPicker 免权限选择器（SkillEditPage.uploadFile 同款机制）→ 读 UTF-8
  //（带字节粗拦与乱码判拒）→ 校验 → **带初值进文件编辑页**而不是直接入库——用户先过目再存。
  // 扩展名白名单在读取前后各判一次：校验那一判当场给中文原因（别让用户填一半才被告知格式不对）
  private async uploadFile(): Promise<void> {
    if (this.files.length >= KNOWLEDGE_FILE_MAX_COUNT) {
      this.getUIContext().getPromptAction().showToast({
        message: '每个条目最多附 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个文件，请先删除不再需要的文件'
      });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 上传 = 单文件动作（后续只取 uris[0]）：不设 maxSelectNumber 时系统面板默认多选，
      // 多选件除首个外静默丢失——SkillEditPage / DataSyncPage 同款守卫
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const name: string = pickedKnowledgeName(uris[0]);
      const text: string = readPickedKnowledgeFileText(uris[0]);
      const v: KnowledgeFileValidation = validateKnowledgeFileArgs(name, text);
      if (!v.ok) {
        this.getUIContext().getPromptAction().showToast({ message: v.error });
        return;
      }
      this.openFilePage('', v.name, v.content);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '读取文件失败：' + (e as Error).message });
    }
  }

  // 行内删除附件（先记目标再弹确认——不可逆操作与库页删除行同款两段式）
  private removeFile(row: KnowledgeFileRow): void {
    this.fileDeleteTarget = row;
    this.fileConfirmCtrl.open();
  }

  private doRemoveFile(): void {
    const target: KnowledgeFileRow | null = this.fileDeleteTarget;
    if (target === null) {
      return;
    }
    this.fileDeleteTarget = null;
    deleteEntryFile(target.id)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 保存（校验 → 重名拦截 → 落库 → 广播 → 带 result 返回）
  private save(): void {
    // 加载完成闸（未加载完 = 表单是空初值，落库即覆盖既有行——SkillEditPage 同款理由）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({
        message: '条目未加载完成，暂不能保存，请返回重进'
      });
      return;
    }
    const trimmedTitle: string = this.title.trim();
    if (trimmedTitle === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写条目名称' });
      return;
    }
    const input: KnowledgeEntryInput = {
      title: trimmedTitle,
      keywords: this.keywords.trim(),
      content: this.content.trim()
    };
    // 重名拦截（决策 8：同一本书内条目标题唯一）——**新建与编辑两态同判**，编辑态排除自身 id
    // （改回原名不算重名）。判定单源 = KnowledgeText.knowledgeTitleTaken（工具侧 manage_knowledge
    // 同用，禁本页另写一套比较逻辑）；命中即 toast 并**中断**，不落库
    queryEntries(this.bookId)
      .then((entries: KnowledgeEntryRow[]): void => {
        if (knowledgeTitleTaken(toEntryItems(entries), trimmedTitle, this.entryId)) {
          this.getUIContext().getPromptAction().showToast({
            message: '已有同名条目，换一个名称再试。'
          });
          return;
        }
        this.persist(input);
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '保存失败：' + (e as Error).message
        });
      });
  }

  // 落库（新增 / 编辑两路；source 只在新增时定——'user' = 用户从本页写，与助手经
  // manage_knowledge 写入的 'assistant' 区分，照技能库内置标同思路）
  private persist(input: KnowledgeEntryInput): void {
    const chain: Promise<void> = this.entryId === '' ?
      insertEntry(this.bookId, input, 'user').then((): void => {
      }) : updateEntry(this.entryId, input);
    chain
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        broadcastKnowledgeList();
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  @Builder
  CardTitleRow(title: string) {
    Text(title)
      .fontSize(SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Bold)
      .fontColor(cardTitleColor())
      .width('100%')
  }

  // ── 第一段：条目（名称 + 关键词）──
  // 两字段各配恒可见标签行（FieldInput 同构，理由与先例见文件头「卡内说明分层」条——占位符
  // 填了内容就不显示，只靠它认字段，编辑态两个框分不清哪个是哪个）。说明分三层：①机制说明
  //（一条写一个知识点 / 名称权重最高 / 命中读的是正文）收进标题行右端 ⓘ 气泡；②标签留在卡面；
  // ③关键词那一句**必须留在卡面**不进气泡——KnowledgeText 的通用格式导出只收带关键词的条目，
  // 「留空合法」这条得在看得见的地方讲清
  @Builder
  EntryCard() {
    Column({ space: 12 }) {
      Row() {
        Text('条目')
          .fontSize(SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '一条写一个知识点。名称是清单里的标题，也是检索权重最高的字段。助手命中时读到的是这条条目的正文。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Column({ space: 6 }) {
        Text('名称')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextInput({ placeholder: '例如 TCP 三次握手', text: this.title })
          .width('100%')
          .maxLength(KNOWLEDGE_TITLE_MAX)
          .onChange((value: string): void => {
            this.title = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: 6 }) {
        Text('关键词')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextInput({ placeholder: '例如 TCP、握手、三次握手', text: this.keywords })
          .width('100%')
          .maxLength(KNOWLEDGE_KEYWORDS_MAX)
          .onChange((value: string): void => {
            this.keywords = value;
          })
        Text('多个关键词用顿号或逗号分隔。留空则只按名称与正文检索。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 第二段：正文 ──
  @Builder
  ContentCard() {
    Column({ space: 10 }) {
      this.CardTitleRow('正文')
      TextArea({ placeholder: '写下这条知识的正文，助手命中后会读到全文', text: this.content })
        .width('100%')
        .height(240)
        .maxLength(KNOWLEDGE_CONTENT_MAX)
        .onChange((value: string): void => {
          this.content = value;
        })
      Text(this.content.length + ' / ' + KNOWLEDGE_CONTENT_MAX)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
        .textAlign(TextAlign.End)
      Text('正文是纯文本，写清术语含义、规则或背景即可。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 第三段：附件文件组卡（仅编辑态可达）──
  // 行 = 件名 + 字数 + 两个行内图标键（编辑 / 删除）；下方「新建文件」「上传文件」并排胶囊
  // 双键（行内图标键形制与 SkillsEditPage 文件卡逐字同源）。标题行右端 ⓘ 气泡承载格式支持
  // 说明（卡面只留标题与操作，说明按需展开——InfoHintButton 单源复用勿另起气泡件）
  @Builder
  FilesCard() {
    Column({ space: 10 }) {
      Row() {
        Text('附件文件')
          .fontSize(SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '支持 ' + KNOWLEDGE_FILE_EXTS.join('、') + '，单个文件不超过 ' +
            KNOWLEDGE_FILE_CONTENT_MAX + ' 字，最多 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.files.length === 0) {
        Text('还没有附件文件。附件是随条目一起给助手取用的参考资料，例如术语表、字段说明。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.files, (row: KnowledgeFileRow) => {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(row.name)
                .fontSize(15)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(row.content.length + ' 字')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openFilePage(row.id, '', '');
            })
            Button() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.removeFile(row);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 键含 id + 件名 + 字数（行上屏的内容有哪几项，键就得含哪几项：改名而字数不变时
          // 键不变会让 ForEach 不重建该行，列表里显示的还是旧名——坑16 家族）
        }, (row: KnowledgeFileRow): string => row.id + '|' + row.name + '|' +
          String(row.content.length))
      }
      // ── 附件双键（并排胶囊；两键同形制 = 等宽次钮，不设主次——两件事都是「加一份」）──
      Row({ space: 10 }) {
        Button('新建文件')
          .fontSize(14)
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            if (this.files.length >= KNOWLEDGE_FILE_MAX_COUNT) {
              this.getUIContext().getPromptAction().showToast({
                message: '每个条目最多附 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个文件'
              });
              return;
            }
            this.openFilePage('', '', '');
          })
        Button('上传文件')
          .fontSize(14)
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.uploadFile();
          })
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。
  // 骨架 = SkillEditPage 同款吸顶穿透：Stack 叠〔内容滚动层 + 分段胶囊悬浮固定层〕——滚动层
  // 从屏幕顶开始，顶部留白 = 胶囊悬浮位（topPad−8 钳位 0）+ 胶囊总高 SEGMENT_BAR_HEIGHT +
  // 间距 28；胶囊层恒驻标题栏下沿、不随内容滚。
  // 三段面板按 segIndex 单渲染（一页一板块）：切换 = 该段销毁、目标段重建——表单值全在父页
  // @State，重建时以当前值重新构造输入件，来回切不丢内容；文件清单同理（@State files）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 12 }) {
          if (this.segIndex === 0) {
            this.EntryCard()
          } else if (this.segIndex === 1) {
            this.ContentCard()
          } else {
            // 第三段（文件）只在编辑态可达——新建态页签只两段，segIndex 到不了 2
            this.FilesCard()
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28,
          bottom: this.bottomPad + 24
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // ── 分段胶囊悬浮固定层（Stack 顶层后声明在上）：位置 = 标题栏下沿 + 蒙层渐隐边缘
      // 8vp（回退路径 topPad=0 钳位 0）；本层仅悬浮定位与宽度约束，胶囊参数在 SegmentBar
      Column() {
        SegmentBar({
          items: this.entryId === '' ? this.tabItemsNew : this.tabItemsEdit,
          selectedIndex: $segIndex
        })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: Math.max(this.topPad - 8, 0) })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: this.entryId === '' ? '新建条目' : '编辑条目',
      menuHds: knowledgeSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: knowledgeSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
