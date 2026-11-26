// 技能编辑页（自包 PageShell 壳；技能库页「＋新建」与行卡点击 push）：三段分段胶囊（技能 / 正文 /
// 文件），胶囊经标题栏下方带承载（PageTopSegmentBand），吸顶不随内容滚；胶囊参数在 SegmentBar
// 单源，本页只传 items/selectedIndex。
// · 新建态两段（技能 / 正文）：附件要挂在技能行上，尚未落库时第三段整段不出现（而不是「出现了
//   但空」）；落库后 pop 回库页，附件在重进编辑页时配。
// · param = 技能 id（'' = 新建）；编辑态回填四字段，查不到退栈回库页并提示；读失败（catch）不置
//   加载闸 ⇒ 保存链首拦，封死「空壳覆盖既有行」（O-13 修复）。
// · 保存 = validateSkillArgs 校验归位（名称/正文空或超限 → toast 不落库）→ insertSkill（库满
//   throw = 第二道闸）或 updateSkill（0 行 throw）→ toast + pop({ saved: true })（坑17：pop 必带
//   result 才触发库页刷新）。
// · 「预览」= 静态正文渲染（ChatMarkdownBody，受控绑 previewBindingId）；不改正文与保存链。
// · 两导出与删除键均已移出本页——入口挂技能库行卡右侧菜单（SkillRowMenu）；本页只留编辑面。
// · 内置行（source='builtin'）：可查看正文与预览、可配附件，保存被预拦截（save 首拦 toast +
//   DB updateSkill 首行 throw 双道）；附件新增在 SkillDb.insertSkillFile 首行独立拦。
// · 附件双键并排胶囊：`fallbackButton*` 四件套双态（两键均 primary=false，等宽 layoutWeight(1)）。
// · 身份卡字段标签 = 恒可见标签行（13fp 灰标签 + Column space 6）+ 机制说明收卡标题行 ⓘ 气泡
//   ——占位符一填内容就不显示，只靠它认不了字段（形制见规范《列表卡片与组卡》§4.5/§4.3，先例 =
//   KnowledgeEditPage 条目卡）。技能头（当前名称 + 取用说明）在身份卡顶部，内置
//   行带「内置」徽标（isBuiltin 因此为 @State）。★ 自定义图标已退役（2026-11-02 决明拍板）——
//   旧图标候选网格与头部图标块整段撤除，skills.icon 列墓碑化见 SkillDb 头注释。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_SKILL_EDIT_PAGE, ROUTE_SKILL_FILE_EDIT_PAGE } from '../../common/RouteNames';
import { pickedFileName, readPickedSkillFile } from '../../common/SkillPack';
import { SkillFileEditParam } from './SkillFileEditPage';
import {
  CARD_PANEL_WIDTH, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  CARD_SECTION_TITLE_FONTSIZE, SEGMENT_BAR_HEIGHT, wellBg, CARD_RADIUS
} from '../../common/Theme';
import { PageTopSegmentBand } from '../SegmentBar';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  deleteSkillFile, insertSkill, querySkill, querySkillFiles, SkillFileRow,
  SkillInput, SkillRow, updateSkill
} from '../../common/store/SkillDb';
import {
  SKILL_CONTENT_MAX, SKILL_DESC_MAX, SKILL_FILE_CONTENT_MAX, SKILL_FILE_EXTS,
  SKILL_FILE_MAX_COUNT, SKILL_NAME_MAX,
  SkillArgsValidation, SkillFileValidation, validateSkillArgs, validateSkillFileArgs
} from '../../common/SkillText';
import {
  SKILL_FILE_ROW_MENU_ID_PREFIX, SkillFileRowMenuCallbacks, SkillFileRowMenuHost
} from './SkillRowMenu';
import { InfoHintButton } from '../InfoHintButton';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { ChatMarkdownBody } from '../chat/ChatMarkdownBody';
import { nextMarkdownBindingId } from '../../common/markdown/MarkdownDocumentModel';
import { markdownScrollToAnchorInViewport } from '../chat/markdown/MarkdownAnchorScroll';

// 标题栏「保存」单键（checkmark；MemoryEditPage 同款形制）
function skillSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

// SKILL.md 沙箱暂存随导出链在 common/SkillPack.ets（页面侧不持有）

@Component
export struct SkillEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新建；构造后不变——坑30）
  editId: string = '';
  // 表单三字段（@State 驱动输入回显与预览；icon 已随自定义图标退役）
  @State private name: string = '';
  @State private description: string = '';
  @State private content: string = '';
  // 正文预览开关（false = 编辑态多行输入 / true = 静态正文预览）
  @State private preview: boolean = false;
  // 每次打开铸新展示身份（快速关开合并到同帧时仍须换绑正文，不借 editId 或文本作身份）
  @State private previewBindingId: string = '';
  // 既有正文滚动壳的命令句柄与视口身份（不驱动 UI，不持几何缓存或新增滚动容器）
  private contentScroller: Scroller = new Scroller();
  private markdownViewportId: string = 'skill-markdown-viewport-' + nextMarkdownBindingId();
  // 附件文件清单（仅编辑态加载——新建态尚无技能行可挂文件）
  @State private files: SkillFileRow[] = [];
  // 分段页签选中项（0 技能 / 1 正文 / 2 文件——@State 驱动面板切换）
  @State private segIndex: number = 0;

  // 标题栏下方带承载（几何与带内下移量单源 = 公共件 PageTopSegmentBand）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.editId === '' ? this.tabItemsNew : this.tabItemsEdit,
      selectedIndex: $segIndex
    })
  }
  // 加载完成闸（O-13 修复，同族四页统一）：.catch 只 toast、页面停在「编辑态空表单」——保存会
  // updateSkill 覆盖既有行。未加载完成不许落库；新建态直接置真；普通成员（不驱动 UI 勿 @State）
  private loaded: boolean = false;
  // 内置行判定：载入行 source='builtin' 时保存预拦截（第一道不发起写，DB updateSkill 首行 throw
  // 兜底）；同时驱动身份卡「内置」徽标，故为 @State
  @State private isBuiltin: boolean = false;
  // 分段页签选项（两套预建实例按 editId 择一）：编辑态三段、新建态两段。editId 构造后不变
  //（坑30），故用非响应式成员
  private tabItemsEdit: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '技能' },
    { text: '正文' },
    { text: '文件' }
  ]);
  private tabItemsNew: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '技能' },
    { text: '正文' }
  ]);
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 附件双键胶囊的双态入参（内容区回退函数族，口径见 common/ImmersiveLevel.ets 头注释）：
  // contentFallback 恒 true（能力位，无用户入口）；immersiveLevel = 光感总档
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 附件文件行更多菜单宿主（AppMenuHost 成对 init/dispose）
  private fileMenu: SkillFileRowMenuHost = new SkillFileRowMenuHost();
  // 行内删除附件的目标行与确认弹窗（成员位控制器——坑7 约束）
  private fileDeleteTarget: SkillFileRow | null = null;
  private fileConfirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除文件',
      message: '删除后无法恢复，助手加载该技能时也不再看到这个文件。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doRemoveFile();
      }
    }),
    autoCancel: true
  });

  // 文件行菜单空行（init 只建宿主；每次 open 前 rebuild 真实行，照 McpPage 先例）
  private emptyFileRow(): SkillFileRow {
    return { id: '', skillId: '', name: '', content: '', sortOrder: 0, createdAt: 0 };
  }

  private fileMenuCallbacks(row: SkillFileRow): SkillFileRowMenuCallbacks {
    return {
      item: row,
      onEdit: (item: SkillFileRow): void => {
        this.openFilePage(item.id, '', '');
      },
      onDelete: (item: SkillFileRow): void => {
        this.removeFile(item);
      }
    };
  }

  private openFileMenu(row: SkillFileRow): void {
    this.fileMenu.open(this.getUIContext(), this.fileMenuCallbacks(row), this.immersiveLevel);
  }

  aboutToAppear(): void {
    this.fileMenu.init(this.getUIContext(), this.fileMenuCallbacks(this.emptyFileRow()));
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_SKILL_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const sid: string = typeof last === 'string' ? last : '';
    this.editId = sid;
    if (sid === '') {
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」，不拦新建）
      return; // 新建态：空表单
    }
    querySkill(sid)
      .then((row: SkillRow | null): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          // 行不存在 = 退栈回库页（不留「编辑态空表单 + 无对应行」：会多出文件页、往不存在技能
          // 插附件成孤儿行、保存必抛「目标技能不存在」）。删技能入口全仓只有库页一处，裸 pop 即可
          this.getUIContext().getPromptAction().showToast({ message: '技能不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.description = row.description;
        this.content = row.content;
        this.isBuiltin = row.source === 'builtin';
        this.loaded = true; // 闸放行（读成功）
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死空壳覆盖既有行
        this.getUIContext().getPromptAction().showToast({ message: '技能读取失败：' + (e as Error).message });
      });
  }

  // 附件清单重拉（附件编辑页保存/删除返回后经 onPop 调；失败 toast 不静默 P0-1）
  private reloadFiles(): void {
    if (this.editId === '') {
      this.files = [];
      return;
    }
    querySkillFiles(this.editId)
      .then((rows: SkillFileRow[]): void => {
        if (this.departed) {
          return;
        }
        this.files = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '附件读取失败：' + (e as Error).message });
      });
  }

  // 文件编辑页跳转（新建/编辑共用；pop 带 result → 重拉清单，坑17）
  private openFilePage(fileId: string, draftName: string, draftContent: string): void {
    const param: SkillFileEditParam = { skillId: this.editId, fileId: fileId,
      draftName: draftName, draftContent: draftContent };
    this.pathStack.pushPathByName(ROUTE_SKILL_FILE_EDIT_PAGE, param, (): void => {
      this.reloadFiles();
    });
  }

  // 上传文件：选择器 → UTF-8 读取（SkillPack 带 1MB 粗拦）→ 校验 → 带初值进文件编辑页审阅，
  // 不直接入库。扩展名白名单先判，当场拒（别让用户填一半才被告知格式不对）
  private async uploadFile(): Promise<void> {
    if (this.files.length >= SKILL_FILE_MAX_COUNT) {
      this.getUIContext().getPromptAction().showToast({
        message: '每个技能最多附 ' + SKILL_FILE_MAX_COUNT + ' 个文件，请先删除不再需要的文件'
      });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 单文件动作：不设 maxSelectNumber 时系统面板默认多选，除首个外静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (this.departed) {
        return;
      }
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const name: string = pickedFileName(uris[0]);
      const text: string = readPickedSkillFile(uris[0]);
      const v: SkillFileValidation = validateSkillFileArgs(name, text);
      if (!v.ok) {
        this.getUIContext().getPromptAction().showToast({ message: v.error });
        return;
      }
      this.openFilePage('', v.name, v.content);
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '读取文件失败：' + (e as Error).message });
    }
  }

  // 行内删除附件（先记目标再弹确认——不可逆操作与库页删除行同款两段式）
  private removeFile(row: SkillFileRow): void {
    this.fileDeleteTarget = row;
    this.fileConfirmCtrl.open();
  }

  private doRemoveFile(): void {
    const target: SkillFileRow | null = this.fileDeleteTarget;
    if (target === null) {
      return;
    }
    this.fileDeleteTarget = null;
    deleteSkillFile(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 当前表单 → 校验归位（保存与导出共用同一份判定——两处各判 = 两处漂移面）
  private validated(): SkillArgsValidation {
    return validateSkillArgs(this.name, this.description, this.content);
  }

  private save(): void {
    // 加载完成闸（未加载完即空表单，落库会覆盖既有行；O-13 修复）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '技能未加载完成，暂不能保存，请返回重进' });
      return;
    }
    // 内置行预拦截（第一道——不发起写；DB updateSkill 首行 throw 是第二道，防绕过路径）
    if (this.isBuiltin) {
      this.getUIContext().getPromptAction().showToast({ message: '内置技能不可修改' });
      return;
    }
    const v: SkillArgsValidation = this.validated();
    if (!v.ok) {
      this.getUIContext().getPromptAction().showToast({ message: v.error });
      return;
    }
    const input: SkillInput = { name: v.name, description: v.description,
      content: v.content };
    const chain: Promise<void> = this.editId === '' ?
      insertSkill(input).then((): void => {
      }) : updateSkill(this.editId, input);
    chain
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 两导出已移出本页——入口挂技能库行卡右侧菜单（SkillLibraryPage.exportRowMd/Pack、SkillPack）

  // 删技能已移出本页——入口在库页行卡菜单（SkillLibraryPage.doDelete 含确认与级联提示）

  @Builder
  CardTitleRow(title: string) {
    Text(title)
      .fontSize(CARD_SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardTitleColor())
      .width('100%')
  }

  // ── 身份卡（名称 + 触发描述）──
  // 两输入框各配恒可见标签行（13fp 灰标签 + Column space 6；形制与理由见文件头）；两条机制说明
  // 收卡标题行 ⓘ。触发描述用多行 TextArea（高 96，约四行；描述上限 200 字，用不到正文那么大）
  @Builder
  IdentityCard() {
    Column({ space: 12 }) {
      // 技能头：当前名称 + 取用说明，名称随输入即时更新，内置行带「内置」徽标
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.name !== '' ? this.name : '未命名技能')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('助手会在匹配时自动取用')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.isBuiltin) {
          StatusBadge({ text: '内置', tone: BadgeTone.EMPHASIS })
        }
        InfoHintButton({
          text: '名称是你在技能库里的识别标签，模型看到的技能清单里也会带上它。触发描述写清楚「什么时候该用」，模型靠它决定是否加载本技能。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Column({ space: 6 }) {
        Text('名称')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextInput({ placeholder: '例如 长文写作规范', text: this.name })
          .width('100%')
          .maxLength(SKILL_NAME_MAX)
          .onChange((value: string): void => {
            this.name = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: 6 }) {
        Text('触发描述')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextArea({ placeholder: '当用户需要……时使用本技能', text: this.description })
          .width('100%')
          .height(96)
          .maxLength(SKILL_DESC_MAX)
          .onChange((value: string): void => {
            this.description = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 正文卡（多行编辑 ⇄ 静态全量预览）──
  @Builder
  ContentCard() {
    Column({ space: 10 }) {
      Row() {
        Column() {
          this.CardTitleRow('技能正文')
        }
        .layoutWeight(1)
        Button(this.preview ? '编辑' : '预览')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
          .onClick((): void => {
            if (!this.preview) {
              this.previewBindingId = nextMarkdownBindingId();
            }
            this.preview = !this.preview;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.preview) {
        // 预览无条件走 ChatMarkdownBody（旧调试双闸与 @lidary 入口已退役）
        Column() {
          if (this.content.trim() === '') {
            Text('正文为空，先写点什么再预览')
              .fontSize(13)
              .fontColor(cardDescColor())
          } else {
            ChatMarkdownBody({
              bindingId: this.previewBindingId,
              content: this.content,
              live: false,
              aiContent: false,
              darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
              onAnchor: (id: string): void => {
                // 带顶为topPad-8，目标留在40vp分段胶囊下沿再让8vp。
                markdownScrollToAnchorInViewport(this.getUIContext(), this.contentScroller,
                  id, this.markdownViewportId, Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 8);
              }
            })
          }
        }
        .width('100%')
        .padding(10)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(12)
        .border({ width: 1, color: cardBorderColor(this.appColorMode) })
        .alignItems(HorizontalAlign.Start)
      } else {
        TextArea({
          placeholder: '写清楚这件事该怎么做，例如步骤、格式要求、注意事项。模型加载后按这里的写法执行。',
          text: this.content
        })
          .width('100%')
          .height(240)
          .maxLength(SKILL_CONTENT_MAX)
          .onChange((value: string): void => {
            this.content = value;
          })
        Text(this.content.length + ' / ' + SKILL_CONTENT_MAX)
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
          .textAlign(TextAlign.End)
      }
      Text('正文是给模型看的做法说明，不要写入口令、密钥等敏感信息。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 附件文件组卡（仅编辑态可达）──
  // 行 = 件名 + 字数 + 行尾「更多」菜单键（行内图标键形制：SymbolGlyph 无底 TEXTUAL +
  // font_secondary）；下方「新建文件」「上传文件」并排胶囊双键。格式说明收标题行 ⓘ 气泡。
  // 新建态不出本页签：附件要挂在技能行上，先保存技能再配附件——比「允许先攒文件再随技能一起
  // 落库」少一整套草稿状态（P2-4 克制），代价是一句引导小字
  @Builder
  FilesCard() {
    Column({ space: 10 }) {
      Row() {
        Text('附件文件')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '支持 ' + SKILL_FILE_EXTS.join('、') + '，单个文件不超过 ' + SKILL_FILE_CONTENT_MAX +
            ' 字，最多 ' + SKILL_FILE_MAX_COUNT + ' 个。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.files.length === 0) {
        Text('还没有附件文件。附件是给助手随技能一起取用的参考资料，例如数据字典、示例数据。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.files, (row: SkillFileRow) => {
          Row({ space: 8 }) {
            // 文件图标块（与知识附件页同款；装饰块不是按钮）
            Column() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(18)
                .fontColor([cardDescColor()])
            }
            .width(32)
            .height(32)
            .borderRadius(9)
            .backgroundColor(wellBg(this.appColorMode))
            .justifyContent(FlexAlign.Center)
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
            // 行尾更多键（显式点击打开，不用 bindMenu——转场残留先例见 SkillRowMenu 头注释）
            Button() {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .id(SKILL_FILE_ROW_MENU_ID_PREFIX + row.id)
            .onClick((): void => {
              this.openFileMenu(row);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 键含 id + 件名 + 字数（上屏项全进键：漏项会让 ForEach 不重建行——坑16 家族）
        }, (row: SkillFileRow): string => row.id + '|' + row.name + '|' + String(row.content.length))
      }
      // 附件双键（并排胶囊等宽淡彩；两键都是「加一份」，不设主次——分主次会让用户以为其中一个是
      // 推荐路径）
      Row({ space: 10 }) {
        Button('新建文件')
          .fontSize(14)
          .fontColor(fallbackButtonFontTinted(this.contentFallback))
          .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
          .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            if (this.files.length >= SKILL_FILE_MAX_COUNT) {
              this.getUIContext().getPromptAction().showToast({
                message: '每个技能最多附 ' + SKILL_FILE_MAX_COUNT + ' 个文件'
              });
              return;
            }
            this.openFilePage('', '', '');
          })
        Button('上传文件')
          .fontSize(14)
          .fontColor(fallbackButtonFontTinted(this.contentFallback))
          .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
          .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
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
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。分段胶囊由标题栏
  // 下方带承载（TopSegmentBand），滚动层顶部留白 = 胶囊位（topPad−8 钳位 0）+ SEGMENT_BAR_HEIGHT
  // + 28。三段按 segIndex 单渲染，切换即销毁重建——表单值全在父页 @State，来回切不丢内容
  //（本页无值参下发，输入件只有 text + onChange 两参）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.contentScroller) {
        Column({ space: 12 }) {
          if (this.segIndex === 0) {
            this.IdentityCard()
          } else if (this.segIndex === 1) {
            this.ContentCard()
          } else {
            // 文件段仅编辑态可达（新建态只有两段，segIndex 到不了 2）
            this.FilesCard()
          }
          // 操作卡（两导出）与危险操作卡（删除）均已撤销——入口在技能库行卡右侧菜单，本页只留编辑面
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28,
          bottom: this.bottomPad + 24
        })
      }
      .id(this.markdownViewportId)
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: '编辑技能',
      // 标题栏下方带承载（分段胶囊在此渲染）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      menuHds: skillSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.fileMenu.dispose();
  }
}
