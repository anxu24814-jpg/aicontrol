// 技能附件编辑页（2026-09-13 技能层笔 2，方案 §3.1——倾向方案「独立小编辑页」落地）：
// 技能编辑页文件组卡「新建文件/上传文件」与行内编辑键 push，param = SkillFileEditParam。
// · 新建/编辑共页：fileId '' = 新建（可带 draft 初值——上传链把选择器读到的内容带进来让用户
//   过目后再存）；非空 = 编辑该件（回填内容，可改名）。
// · 校验走 SkillText.validateSkillFileArgs（件名空/超长/扩展名不在白名单、内容空/超限全拒），
//   同名件由 SkillDb 写入侧硬拒（件名是模型取件的唯一定位键，同名即歧义）——两处分工：
//   格式问题本地先说清，库内冲突由库层判。
// · 编辑态底部「删除文件」红字键（PriceTemplateEditPage 同款形制 + 同源色）。
// · 保存/删除成功 pop({ saved: true })（坑17）→ 技能编辑页文件组卡 onPop 重拉。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_SKILL_FILE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE
} from '../../common/Theme';
import {
  deleteSkillFile, insertSkillFile, querySkillFile, SkillFileRow, updateSkillFile
} from '../../common/store/SkillDb';
import {
  SKILL_FILE_CONTENT_MAX, SKILL_FILE_EXTS, SKILL_FILE_NAME_MAX, SkillFileValidation,
  validateSkillFileArgs
} from '../../common/SkillText';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';

// push 参数（技能编辑页构造：skillId 必填；fileId '' = 新建；draft* 仅新建态初值用）
export interface SkillFileEditParam {
  skillId: string;
  fileId: string;
  draftName: string;
  draftContent: string;
}

function fileSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function fileSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

@Component
export struct SkillFileEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属技能 id 与编辑对象 id（构造后不变——坑30）
  private skillId: string = '';
  private fileId: string = '';
  @State private name: string = '';
  @State private content: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 删除确认弹窗（坑7：组件成员位构造）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除文件',
      message: '删除后无法恢复，助手加载该技能时也不再看到这个文件。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_SKILL_FILE_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last === null || typeof last !== 'object') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少技能参数' });
      this.pathStack.pop();
      return;
    }
    const param: SkillFileEditParam = last as SkillFileEditParam;
    this.skillId = param.skillId;
    this.fileId = param.fileId;
    if (this.skillId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少技能参数' });
      this.pathStack.pop();
      return;
    }
    if (this.fileId === '') {
      // 新建：带 draft 初值（上传链）或空表单
      this.name = param.draftName;
      this.content = param.draftContent;
      return;
    }
    querySkillFile(this.fileId)
      .then((row: SkillFileRow | null): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '文件不存在，按新建处理' });
          this.fileId = '';
          return;
        }
        this.name = row.name;
        this.content = row.content;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '文件读取失败：' + (e as Error).message });
      });
  }

  private save(): void {
    const v: SkillFileValidation = validateSkillFileArgs(this.name, this.content);
    if (!v.ok) {
      this.getUIContext().getPromptAction().showToast({ message: v.error });
      return;
    }
    const chain: Promise<void> = this.fileId === '' ?
      insertSkillFile(this.skillId, v.name, v.content).then((): void => {
      }) : updateSkillFile(this.fileId, this.skillId, v.name, v.content);
    chain
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  private doDelete(): void {
    deleteSkillFile(this.fileId)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 12 }) {
          Text('文件')
            .fontSize(SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(cardTitleColor())
            .width('100%')
          // 两字段各配恒可见标签行（2026-09-23 字段标签笔；形制与三处先例见规范《列表卡片与
          // 组卡》§4.5，知识与技能两文件页同款同源）：占位符一填内容就不再显示，只靠它认不了
          // 字段；「内容」框占位符原以「纯文本内容。」起头，标签已给字段名故去该前缀（纯文本
          // 这条限制仍由卡底格式说明承载，信息零丢失）
          Column({ space: 6 }) {
            Text('名称')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({ placeholder: '例如 数据字典.md', text: this.name })
              .width('100%')
              .maxLength(SKILL_FILE_NAME_MAX)
              .onChange((value: string): void => {
                this.name = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Column({ space: 6 }) {
            Text('内容')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextArea({
              placeholder: '助手加载技能后，可按文件名取用这份内容。',
              text: this.content
            })
              .width('100%')
              .height(240)
              .maxLength(SKILL_FILE_CONTENT_MAX)
              .onChange((value: string): void => {
                this.content = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Text(this.content.length + ' / ' + SKILL_FILE_CONTENT_MAX)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
            .textAlign(TextAlign.End)
          Text('只支持纯文本文件，例如 ' + SKILL_FILE_EXTS.join('、') +
            '。不支持脚本与二进制文件，也请勿写入口令、密钥等敏感信息。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(14)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // 删除键（编辑态；PriceTemplateEditPage 底部红字键同款形制与同源色）
        if (this.fileId !== '') {
          Button('删除文件')
            .fontSize(15)
            .fontColor($r('app.color.dialog_confirm_red'))
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
            .width(CARD_PANEL_WIDTH)
            .padding({ top: 13, bottom: 13 })
            .onClick((): void => {
              this.confirmCtrl.open();
            })
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
  }

  build() {
    PageShell({
      title: '编辑文件',
      menuHds: fileSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: fileSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
