// 技能编辑页（2026-09-13 技能层笔 1 新建，方案-技能层-20260913 §2.5/§2.6；技能库页「＋
// 新建」与行卡点击 push——自包 PageShell 壳）：
// 信息架构（★ 2026-09-13 分段胶囊笔：方案 §8-1 预告的回改口〔「若决明要 tab 形态，回改面 =
// SkillEditPage 单文件改 SegmentBar；功能集不变」〕执行——原「分组卡分段制」整页 Scroll 改
// 三段页签、一页一板块）：技能（名称 + 触发描述 + 图标）→ 正文（编辑/预览切换）→ 文件
// （仅编辑态；笔 2 加）。骨架 = 服务商编辑页/自检页同款「Stack 叠〔内容滚动层 + 分段胶囊
// 悬浮固定层〕」（胶囊吸顶不随内容滚，内容向上滚时从胶囊背后穿过；胶囊参数在 SegmentBar
// 单源，本页只传 items/selectedIndex）。
// · ★ 新建态两段（技能/正文）：附件要挂在技能行上，尚未落库时没有可配对象——第三段整段
//   不出现，而不是「出现了但空」（原「新建态不出附件卡」口径的分段形态）。落库后仍 pop 回
//   库页，附件在重进编辑页时配。
// · param = 技能 id（'' = 新建；技能库页「＋」push 空参、行卡 push 技能 id）；编辑态回填
//   四字段，**查不到退栈回库页**并提示（原「按新增兜底」形态已随自检观察项 O-11 修复撤销，
//   见 aboutToAppear 内注释）；读失败（catch）不置加载闸 ⇒ 保存链首拦，封死「空壳覆盖既有行」
//   路径（O-13 修复，同族四页统一，见成员位与 save 注释）；
// · 保存 = validateSkillArgs 校验归位（脏测：名称/正文空或超限 → toast 不落库）→ 新增
//   insertSkill（库满 throw = 第二道闸，第一道在库页「＋」）或 updateSkill（0 行 throw）→
//   toast + pop({ saved: true })（坑17：pop 必带 result 才触发库页刷新）；
// · 「预览」切换 = 静态全量 markdown 渲染（聊天页**基态链**——@lidary/markdown 的 Markdown
//   组件；实验态 CubeMarkdownView 是流式增量解析器，与「看一份写好的说明书」无关，故不取）；
// · ★ 两导出（SKILL.md / 技能包）2026-09-13 入口调整笔**移出本页**——原操作卡撤销，入口改挂
//   技能库行卡右侧菜单（SkillRowMenu），导出对象 = 库里已保存行。本页不再有导出代码与分享
//   链；附件格式支持说明同笔从卡底说明行收进标题行气泡（InfoHintButton）。导入是笔 2 ZIP 件
//   的组成部分，本页不做。
// · ★ 删除键去重（同日第二笔）：原底部「删除技能」红字卡与确认弹窗整段撤销——技能库行卡
//   右侧菜单已有同语义项（含同文案的确认弹窗），编辑页再留一个等于同一件事两处入口。本页
//   退出编辑的唯一方式 = 返回键，删技能一律回库页走菜单。
// · ★ 内置行（2026-09-13 会话中创建技能笔）：source='builtin' 的行可进本页查看正文与
//   预览、可配附件查看，但保存被预拦截（save 首拦 toast「内置技能不可修改」+ DB
//   updateSkill 首行 throw 兜底双道）；附件新增在 SkillDb.insertSkillFile 首行独立拦
//  （附件写入不经 updateSkill）。元技能「创建技能」是 seed 单源内容，UI 改动不落库。
// · ★ 附件双键并排胶囊（同日第二笔）：卡内「新建文件/上传文件」由 TEXTUAL 纯文字键改为
//   `fallbackButton*` 四件套双态胶囊（两键均取次钮 primary=false——光感新规范开 = 官方灰底
//   `app.color.comp_fallback_gray`、关 = 无色底透光感材质），形制照 ProviderDetailPage /
//   FunctionalModelPage 卡内双键行先例（Row 并排 + 两键各 layoutWeight(1) 等宽）。
// · ★ 身份卡两框各配框外提示 + 描述框多行化（2026-09-13 同日第三笔，见 IdentityCard 头注释）：
//   名称句新增、描述句原有；描述框由单行 TextInput 改多行 TextArea（竖滚，高 96 < 正文 240）。
//   ★ 2026-09-23 字段标签笔改判（决明「技能同这个改」）：上条「框外提示」退役，改**恒可见
//   标签行** + 两条机制说明收卡标题行 ⓘ 气泡——形制 = 规范《列表卡片与组卡》§4.5/§4.3，
//   同笔先例 = KnowledgeEditPage 条目卡（理由：占位符一填内容就不显示，只靠它认不了字段）。
import { SegmentButtonV2Items, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { Markdown } from '@lidary/markdown';
import { PageShell } from '../../common/PageShell';
import { ROUTE_SKILL_EDIT_PAGE, ROUTE_SKILL_FILE_EDIT_PAGE } from '../../common/RouteNames';
import { pickedFileName, readPickedSkillFile } from '../../common/SkillPack';
import { SkillFileEditParam } from './SkillFileEditPage';
import {
  CARD_PANEL_WIDTH, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  SECTION_TITLE_FONTSIZE, SEGMENT_BAR_HEIGHT
} from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  deleteSkillFile, insertSkill, querySkill, querySkillFiles, SkillFileRow,
  SkillInput, SkillRow, updateSkill
} from '../../common/store/SkillDb';
import {
  SKILL_CONTENT_MAX, SKILL_DESC_MAX, SKILL_FILE_CONTENT_MAX, SKILL_FILE_EXTS,
  SKILL_FILE_MAX_COUNT, SKILL_ICON_CANDIDATES, SKILL_ICON_DEFAULT, SKILL_NAME_MAX,
  SkillArgsValidation, SkillFileValidation, validateSkillArgs, validateSkillFileArgs
} from '../../common/SkillText';
import { skillIconResource } from './SkillIcons';
import { InfoHintButton } from '../InfoHintButton';
import { ConfirmDialog } from '../chat/ConfirmDialog';

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

function skillSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

// SKILL.md 沙箱暂存已随导出链整段迁入 `common/SkillPack.ets`（入口调整笔：导出改挂技能库行卡
// 菜单，页面侧不再持有该链——域件导出符号 = SkillPack.exportSkillMd，返回路径供分享面板用）。

@Component
export struct SkillEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新建；构造后不变——坑30）
  editId: string = '';
  // 表单四字段（@State 驱动输入回显与预览）
  @State private name: string = '';
  @State private description: string = '';
  @State private icon: string = SKILL_ICON_DEFAULT;
  @State private content: string = '';
  // 正文预览开关（false = 编辑态多行输入 / true = 静态全量 markdown 渲染）
  @State private preview: boolean = false;
  // 附件文件清单（笔 2；仅编辑态加载——新建态尚无技能行可挂文件，见 FilesCard 注释）
  @State private files: SkillFileRow[] = [];
  // 分段页签选中项（0 技能 / 1 正文 / 2 文件——@State 驱动面板切换）
  @State private segIndex: number = 0;
  // 加载完成闸（★ O-13 修复，同族四页统一：技能/记忆/提示词/服务商）：.catch（如库未就绪
  // 同步抛）只 toast、页面仍停在「编辑态空表单」——此时用户填写保存会走 updateSkill(this.editId)
  // **命中真实行并覆盖其名称/描述/图标/正文**。闸 = 未加载完成不许落库（形制与理由照
  // BalanceConfigPage 的 loaded 闸先例，其自检轮钉「未加载即落库 = 空值覆盖」）：新建态
  // 无待读行、显式置真；读成功置真；读失败保持假 = 保存链首拦一道显式提示（不弹出用户，
  // 返回重进即可重读），同时封死覆盖路径。普通成员即可（不驱动 UI 勿 @State）
  private loaded: boolean = false;
  // 内置行判定（2026-09-13 会话中创建技能笔）：载入行 source='builtin' 时保存预拦截——
  // 内置技能禁改（元技能正文是 seed 单源内容，UI 改了下次对比也是假象；DB updateSkill
  // 首行 throw 兜底，此处第一道先拦不发起写）。普通成员（不驱动 UI）
  private isBuiltin: boolean = false;
  // 分段页签选项（两套预建实例，build 内按 editId 择一）：编辑态三段；新建态两段（技能/
  // 正文——附件要挂在技能行上，没行就没有这一页，见文件头）。段数在本页生命周期内恒不变
  //（editId 构造后不变，坑30），故非响应式成员即可
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
  // 附件双键胶囊的双态入参（内容区回退函数族，见 common/ImmersiveLevel.ets 头注释：
  // contentFallback = 外观页「光感新规范」开关，默认开 = 官方实底；immersiveLevel = 光感总档）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
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

  aboutToAppear(): void {
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
        if (row === null) {
          // ★ 自检观察项 O-11 修复（2026-09-13 五百二十五节）：原「按新建处理」只清表单、
          // **不改 editId**——页面留在「编辑态」而库里没有这一行，三个后果：①三段页签多出
          // 一个文件页，对该 id 增/传附件会往 skill_files 插一条指向不存在技能的行（级联删件
          // 按 skillId 走，谁也清不到它 = 无主孤儿行）；②用户填完按保存必走 updateSkill →
          // 抛「目标技能不存在（已被删除），保存未生效」，白填一场；③toast 承诺「按新建」
          // 而实现按编辑走，承诺与行为相反。
          // 改为退栈回上页（照 ProviderDetailPage「服务商不存在或已删除」同行守卫同式）——
          // 删技能的入口全仓只有库页一处，退回即见最新列表；库页刷新走 SkillDb 广播键
          //（SkillLibraryPage push 不带 onPop），故裸 pop 即可
          this.getUIContext().getPromptAction().showToast({ message: '技能不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.description = row.description;
        this.icon = row.icon;
        this.content = row.content;
        this.isBuiltin = row.source === 'builtin';
        this.loaded = true; // 闸放行（读成功）
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死空壳覆盖既有行（见成员位注释）
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
        this.files = rows;
      })
      .catch((e: Object): void => {
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

  // 上传文件（方案 §3.1）：DocumentViewPicker 免权限选择器（AttachmentPickCtrl 同款机制）→
  // 读 UTF-8（SkillPack.readPickedSkillFile 带 1MB 粗拦）→ 校验 → **带初值进文件编辑页**
  // 而不是直接入库——用户先过目再存（导入侧同理的审阅哲学，本处是同一份内容的常规路径）。
  // 扩展名白名单在此先判一次：非纯文本当场拒（别让用户填一半才被告知格式不对）
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
      // 上传 = 单文件动作（后续只取 uris[0]）：不设 maxSelectNumber 时系统面板默认多选
      //（d.ts 上限 500），多选件除首个外静默丢失——DataSyncPage.doImport 同款守卫
      //（第 2 轮 P2-2 同族第 4 处，全面自检第 3 轮笔 2 收口）
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
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
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 当前表单 → 校验归位（保存与导出共用同一份判定——两处各判 = 两处漂移面）
  private validated(): SkillArgsValidation {
    return validateSkillArgs(this.name, this.description, this.icon, this.content);
  }

  private save(): void {
    // 加载完成闸（未加载完 = 表单是空初值，落库即覆盖既有行；闸的形状与理由照
    // BalanceConfigPage 先例；O-13 修复）
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
    const input: SkillInput = { name: v.name, description: v.description, icon: v.icon,
      content: v.content };
    const chain: Promise<void> = this.editId === '' ?
      insertSkill(input).then((): void => {
      }) : updateSkill(this.editId, input);
    chain
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 两导出（导出 SKILL.md / 导出技能包）2026-09-13 入口调整笔移出本页——入口改挂技能库行卡
  // 右侧菜单，实现见 SkillLibraryPage.exportRowMd/exportRowPack 与 SkillPack.exportSkillMd；
  // 本页不再持有校验后导出链（validated() 仍为保存唯一入口）

  // 技能删除同日第二笔移出本页（与库页行菜单重）——确认弹窗与删除链一并撤销，删技能回库页
  // 走行卡菜单（SkillLibraryPage.doDelete 含同文案确认与级联后果提示）

  @Builder
  CardTitleRow(title: string) {
    Text(title)
      .fontSize(SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Bold)
      .fontColor(cardTitleColor())
      .width('100%')
  }

  // ── 身份卡（名称 + 触发描述 + 图标候选网格）──
  // ★ 2026-09-13 同日第三笔：两输入框各配**框外提示**（紧贴各自盒下；名称原无提示、描述原提示
  // 与名称盒无提示不对称），且触发描述由单行 TextInput 改多行 TextArea（竖向滚动，同正文卡
  // 形态）——原单行形态超长即横向滚动，写两三句就得来回划，看不到全貌；高度取 96（约四行，
  // 正文 240 的三分之一——描述上限 200 字，用不到正文那么大的框）
  // ★ 2026-09-23 字段标签笔（决明「技能同这个改」）：上条「框外提示」形态退役，改**恒可见
  // 标签行**（13fp 灰标签 + Column space 6，形制与三处先例见规范《列表卡片与组卡》§4.5；
  // 同笔先例 = KnowledgeEditPage 条目卡）——两条机制说明（名称是什么 / 描述怎么写）收进卡标题
  // 行右端 ⓘ 气泡（§4.3）。理由同条目卡：占位符一填内容就不显示，只靠它认不了字段，而旧形态
  // 卡面是「输入框 + 灰字说明」两段一重复（决明对条目卡报的「杂乱」同族）。图标标签随同档
  // 收 14fp → 13fp（一卡内三个字段标签同号）
  @Builder
  IdentityCard() {
    Column({ space: 12 }) {
      Row() {
        Text('技能')
          .fontSize(SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
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
      Column({ space: 6 }) {
        Text('图标')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(SKILL_ICON_CANDIDATES, (item: string) => {
            Button() {
              SymbolGlyph(skillIconResource(item))
                .fontSize(22)
                .fontColor([item === this.icon ? $r('sys.color.ohos_id_color_emphasize') :
                  cardTitleColor()])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .width(44)
            .height(44)
            // 选中态 = 官方强调色描边（只用官方语义色，不自绘色值；未选中 = 零宽边框同描边半径）
            .border({
              width: item === this.icon ? 1 : 0,
              color: $r('sys.color.ohos_id_color_emphasize'),
              radius: 22
            })
            .onClick((): void => {
              this.icon = item;
            })
          }, (item: string): string => item + (item === this.icon ? '_on' : '_off'))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
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
            this.preview = !this.preview;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.preview) {
        // 静态全量 markdown 渲染（聊天页基态链）；空正文给占位提示不渲染空块
        Column() {
          if (this.content.trim() === '') {
            Text('正文为空，先写点什么再预览')
              .fontSize(13)
              .fontColor(cardDescColor())
          } else {
            Markdown({
              content: this.content,
              options: { darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK }
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
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 附件文件组卡（笔 2，方案 §3.1）──
  // 行 = 件名 + 字数 + 两个行内图标键（编辑 / 删除——规范「行内图标键」形制：SymbolGlyph
  // 符号键无底 TEXTUAL + font_secondary）；下方「新建文件」「上传文件」并排胶囊双键（同日次笔
  // 由纯文字键改，见文件头末条）。
  // ★ 标题行右端 ⓘ 气泡（2026-09-13 入口调整笔）：格式支持说明原为卡底灰色说明行，收进气泡
  // ——卡面只留标题与操作，说明按需展开（形制照 SectionHeader.hint 与外观页开关卡标题行，
  // InfoHintButton 单源复用勿另起气泡件）。
  // ★ 新建态（尚未落行）不出本页签：附件要挂在技能行上，先保存技能再配附件——比「允许先攒
  // 文件再随技能一起落库」少一整套草稿状态（P2-4 克制），代价是一句引导小字。分段形态下
  // 由「编辑态三段 / 新建态两段」在页签层直接落地（见文件头），本卡自身不做二态分支
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
          // 键含 id + 件名 + 字数（★ 2026-09-13 真机预演反推补：原键只有 id + 字数——改名而
          // 字数不变（例如「说明.md」→「备注.md」）时键不变 → ForEach 不重建该行 → 列表里
          // 显示的还是旧名。行上屏的内容有哪几项，键就得含哪几项，坑16 家族同一条道理）
        }, (row: SkillFileRow): string => row.id + '|' + row.name + '|' + String(row.content.length))
      }
      // ── 附件双键（并排胶囊；两键同形制 = 等宽次钮，不设主次——两件事都是「加一份」，
      // 分主次会让用户以为其中一个是推荐路径）──
      Row({ space: 10 }) {
        Button('新建文件')
          .fontSize(14)
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
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
  // 骨架 = 服务商编辑页/自检页同款吸顶穿透：Stack 叠〔内容滚动层 + 分段胶囊悬浮固定层〕
  // ——滚动层从屏幕顶开始（HDS 路径内容区延伸到标题栏背后，蒙层透出滚动内容），顶部留白 =
  // 胶囊悬浮位（topPad−8 钳位 0）+ 胶囊总高 SEGMENT_BAR_HEIGHT + 间距 28；胶囊层恒驻标题栏
  // 下沿、不随内容滚。
  // 三段面板按 segIndex 单渲染（一页一板块，不叠卡）：切换 = 该段销毁、目标段重建——表单值
  // 全在父页 @State，重建时以当前值重新构造输入件，来回切不丢内容（@Builder 值参快照与
  // @Prop 冻结两条坑都不涉：本页无值参下发、输入件只有 text + onChange 两参）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 12 }) {
          if (this.segIndex === 0) {
            this.IdentityCard()
          } else if (this.segIndex === 1) {
            this.ContentCard()
          } else {
            // 第三段（文件页）只在编辑态可达——新建态页签只两段，segIndex 到不了 2
            this.FilesCard()
          }
          // 操作卡（两导出）同日首笔撤销、危险操作卡（删除）同日次笔撤销——入口均在技能库
          // 行卡右侧菜单，本页只留编辑面
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
          items: this.editId === '' ? this.tabItemsNew : this.tabItemsEdit,
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
      title: '编辑技能',
      menuHds: skillSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: skillSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
