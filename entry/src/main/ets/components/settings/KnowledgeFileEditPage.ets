// 知识库条目附件编辑页：条目编辑页文件卡「新建文件/上传文件」与行内编辑键 push，param =
// KnowledgeFileEditParam——形制照 SkillFileEditPage 逐段落地，域不同故各持一份。
// · 新建/编辑共页：fileId '' = 新建（可带 draft 初值）；非空 = 编辑该件（回填内容，可改名）。
// · 校验走 KnowledgeText.validateKnowledgeFileArgs（件名空/含换行/超长/扩展名不在白名单、
//   内容空/超限全拒），同名件由 KnowledgeDb.insertEntryFile 写入侧硬拒（件名是模型取件的
//   唯一定位键，同名即歧义）——格式问题本地说清，库内冲突由库层判。
// · 编辑态「危险操作」卡（危险文字键灰底红字四件套，与保存动作拉开距离）；卡头「纯文本」徽标、
//   名称标签「含扩展名」、内容字数在标签行——与技能附件页成对改。
// · 保存/删除成功 pop({ saved: true })（坑17）→ 条目编辑页文件卡 onPop 重拉。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_FILE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_SECTION_TITLE_FONTSIZE, CARD_RADIUS
} from '../../common/Theme';
import {
  deleteEntryFile, insertEntryFile, queryEntryFile, KnowledgeFileRow, updateEntryFile
} from '../../common/store/KnowledgeDb';
import {
  KNOWLEDGE_FILE_CONTENT_MAX, KNOWLEDGE_FILE_EXTS, KNOWLEDGE_FILE_NAME_MAX,
  KnowledgeFileValidation, validateKnowledgeFileArgs
} from '../../common/KnowledgeText';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonMaterial,
  fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { BadgeTone, StatusBadge } from '../StatusBadge';

// push 参数（条目编辑页构造：entryId 必填；fileId '' = 新建；draft* 仅新建态初值用）
export interface KnowledgeFileEditParam {
  entryId: string;
  fileId: string;
  draftName: string;
  draftContent: string;
}

function knowledgeFileSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct KnowledgeFileEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属条目 id 与编辑对象 id（构造后不变——坑30）
  private entryId: string = '';
  private fileId: string = '';
  @State private name: string = '';
  @State private content: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 危险键双态四件套入参（与技能附件页成对改；能力位恒 true = 官方实底）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 删除确认弹窗（坑7：组件成员位构造）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除文件',
      message: '删除后无法恢复。助手读取这条条目时也不再看到这个文件。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_KNOWLEDGE_FILE_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last === null || typeof last !== 'object') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少条目参数' });
      this.pathStack.pop();
      return;
    }
    const param: KnowledgeFileEditParam = last as KnowledgeFileEditParam;
    this.entryId = param.entryId;
    this.fileId = param.fileId;
    if (this.entryId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少条目参数' });
      this.pathStack.pop();
      return;
    }
    if (this.fileId === '') {
      this.name = param.draftName;
      this.content = param.draftContent;
      return;
    }
    queryEntryFile(this.fileId)
      .then((row: KnowledgeFileRow | null): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '文件不存在，按新建处理' });
          this.fileId = '';
          return;
        }
        this.name = row.name;
        this.content = row.content;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '文件读取失败：' + (e as Error).message });
      });
  }

  private save(): void {
    const v: KnowledgeFileValidation = validateKnowledgeFileArgs(this.name, this.content);
    if (!v.ok) {
      this.getUIContext().getPromptAction().showToast({ message: v.error });
      return;
    }
    const chain: Promise<void> = this.fileId === '' ?
      insertEntryFile(this.entryId, v.name, v.content).then((): void => {
      }) : updateEntryFile(this.fileId, this.entryId, v.name, v.content);
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

  private doDelete(): void {
    deleteEntryFile(this.fileId)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 文件卡（卡头 + 名称/内容两字段；字数计数在内容标签行）──
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('文件')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            StatusBadge({ text: '纯文本', tone: BadgeTone.WEAK })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 两字段各配恒可见标签行（与技能附件页成对同源——形制见规范《列表卡片与组卡》§4.5）：
          // 占位符一填内容就不再显示，只靠它认不了字段
          Column({ space: 6 }) {
            Row() {
              Text('名称')
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              Text('含扩展名')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            TextInput({ placeholder: '例如 术语表.md', text: this.name })
              .width('100%')
              .maxLength(KNOWLEDGE_FILE_NAME_MAX)
              .onChange((value: string): void => {
                this.name = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('内容')
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              Text(this.content.length + ' / ' + KNOWLEDGE_FILE_CONTENT_MAX)
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            TextArea({
              placeholder: '助手读取这条条目后，可按文件名取用这份内容。',
              text: this.content
            })
              .width('100%')
              .height(240)
              .maxLength(KNOWLEDGE_FILE_CONTENT_MAX)
              .onChange((value: string): void => {
                this.content = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Text('只支持纯文本文件，例如 ' + KNOWLEDGE_FILE_EXTS.join('、') +
            '。不支持脚本与二进制文件，也请勿写入口令、密钥等敏感信息。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        if (this.fileId !== '') {
          Column({ space: 12 }) {
            Text('危险操作')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width('100%')
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text('删除这个文件')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text('删除后无法恢复。助手读取这条条目时也不再看到这个文件。')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              // 危险文字键（规范 §1：灰底次钮档 bg/material 四件套 + 红字；破坏性动作不入主操作位）
              Button('删除文件')
                .fontColor($r('app.color.dialog_confirm_red'))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .onClick((): void => {
                  this.confirmCtrl.open();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
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
      title: '编辑文件',
      menuHds: knowledgeFileSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
