// 提示词编辑页（2026-08-30 提示词注入新建；管理页 push，param = 模板 id 字符串：
// '' = 新增 / 其他 = 模板编辑——两形态；★ 2026-08-31 系统提示词独立（不再经本页——
// SystemPromptPage 独立页管理，库页亦不显示，见 PromptTemplateDb 头注释）；标题恒
// 「编辑提示词」（领导追加指令：新建态不显示「新增提示词」））：
// 名称 + 内容（多行 TextArea——提示词可长，InputDialog 单行不够用）两输入 + 标题栏
// 「保存」键（照 ProviderDetailPage 保存链姿势：加载完成闸 → 校验非空 → insert/update → toast
// + pop，失败显式提示）；保存走 updateTemplate——引用跟随即时生效：所有引用会话下次发送用新版。
// ★ 2026-09-13 两改（同族统一 + O-13）：①查不到行原「按新增处理」只提示不改 editId（保存必抛
// 后端 0 行错、承诺与行为相反）→ 改退栈回库页；②读失败 catch 不置加载闸 → 保存链首拦
//（未加载完的空壳表单落库会覆盖既有行；闸形制照 BalanceConfigPage 先例）。
// ★ 2026-08-30 注入配置：内容输入框下方挂 PromptInjectConfig（身份/位置/深度三配置，
// 按钮弹菜单官方材质——组合语义与协议适配见 RequestInject/PromptInjectConfig 头注释）；
// 保存随行落库（insert/update 新签名），脏值钳位默认（system+head+0 = 现状行为）。
// ★ 2026-09-01 文本层级定稿：两板块标题「名称」「内容」黑（cardTitleColor——与
// SystemPromptPage/AssistantPromptPage 同规），说明性文本（placeholder/页尾「提示词将
// 在每条消息…」说明行）灰（cardDescColor）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PROMPT_EDIT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE } from '../../common/Theme';
import {
  insertTemplate, queryTemplate,
  TEMPLATE_CONTENT_MAX, TEMPLATE_NAME_MAX, updateTemplate
} from '../../common/store/PromptTemplateDb';
import {
  INJECT_POSITION_HEAD, INJECT_ROLE_ASSISTANT, INJECT_ROLE_SYSTEM
} from '../../common/providers/RequestInject';
import {
  PromptInjectConfig, sanitizeInjectDepth, sanitizeInjectPosition, sanitizeInjectRole
} from './PromptInjectConfig';
import { ConfigurationConstant } from '@kit.AbilityKit';

function promptSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function promptSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

// 注入配置脏值钳位（模块级共享在 PromptInjectConfig.ets——编辑页/系统提示词页两处消费；
// 页面侧另有 sanitizeRoleValue/PositionValue/DepthValue 带身份联动双保险）

@Component
export struct PromptEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新增；其他 = 模板 id）——构造后不变（坑30）；系统提示词已独立页化
  // （SystemPromptPage），不再走本页
  editId: string = '';
  @State private name: string = '';
  @State private content: string = '';
  // 注入配置（钳位值默认 system+head+0 = 现状行为；回填/保存链自带钳位）
  @State private injectRole: string = INJECT_ROLE_SYSTEM;
  @State private injectPosition: string = INJECT_POSITION_HEAD;
  @State private injectDepth: number = 0;
  // 加载完成闸（★ O-13 修复，同族四页统一）：加载未完成（含读失败 catch）时表单是空初值，
  // 落库会走 updateTemplate(this.editId) 命中真实行覆盖其名称/内容/注入配置——未置真即保存
  // 被首拦（形制与理由照 BalanceConfigPage 的 loaded 闸先例）。新建态无待读行显式置真。
  // 本字段原为只写不读（无消费方），本笔起为保存闸的唯一消费点——不再是死写点
  @State private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // param 解析（照 ProviderDetailPage 守卫：null/非串一律 '' = 新增）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_PROMPT_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const pid: string = typeof last === 'string' ? last : '';
    this.editId = pid;
    if (pid !== '') {
      // 编辑态：回填名称/内容/注入配置（系统提示词行同此——固定 id 查行；★ 2026-09-13 同族
      // 统一修复：查不到原「按新增处理」只提示不改 editId，保存必抛后端 0 行错、承诺与行为
      // 相反，同技能/记忆编辑页形态——改退栈回库页，形制照 ProviderDetailPage 同行守卫）
      queryTemplate(pid)
        .then((row): void => {
          if (row === null) {
            this.getUIContext().getPromptAction().showToast({ message: '提示词不存在或已删除' });
            this.pathStack.pop();
            return;
          }
          this.name = row.name;
          this.content = row.content;
          // 回填种子化（与 UI 联动同口径：system 强制 head；assistant 排除深度 0）
          const role: string = sanitizeInjectRole(row.injectRole);
          const position: string =
            role === INJECT_ROLE_SYSTEM ? INJECT_POSITION_HEAD : sanitizeInjectPosition(row.injectPosition);
          let depth: number = sanitizeInjectDepth(row.injectDepth);
          if (role === INJECT_ROLE_ASSISTANT && depth === 0) {
            depth = 1;
          }
          this.injectRole = role;
          this.injectPosition = position;
          this.injectDepth = depth;
          this.loaded = true;
        })
        .catch((e: Object): void => {
          // 读取失败：不置加载闸（保持未完成）→ 保存被首拦，封死空壳覆盖既有行（见成员位注释）
          this.getUIContext().getPromptAction().showToast({ message: '模板读取失败：' + (e as Error).message });
        });
    } else {
      this.loaded = true;
    }
  }

  // 注入配置脏值钳位（默认 = 现状行为；位置 depth 时深度钳位 0~4；身份 system 时位置
  // 强制 head——与 UI 联动语义一致，任何来源的脏值都不入库；基础钳位在
  // PromptInjectConfig 共享函数，页面侧补身份联动）
  private sanitizeRoleValue(): string {
    return sanitizeInjectRole(this.injectRole);
  }

  private sanitizePositionValue(): string {
    const role: string = this.sanitizeRoleValue();
    if (role === INJECT_ROLE_SYSTEM) {
      return INJECT_POSITION_HEAD;
    }
    return sanitizeInjectPosition(this.injectPosition);
  }

  private sanitizeDepthValue(): number {
    let d: number = sanitizeInjectDepth(this.injectDepth);
    // assistant 身份不含深度 0（= 注入成末条，Gemini 拒 + 跨模型不一致——域件联动口径）
    if (this.sanitizeRoleValue() === INJECT_ROLE_ASSISTANT && d === 0) {
      d = 1;
    }
    return d;
  }

  private save(): void {
    // 加载完成闸（未加载完 = 表单是空初值，落库即覆盖既有行；闸的形状与理由照 BalanceConfigPage
    // 先例；O-13 修复）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '提示词未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const name: string = this.name.trim();
    const content: string = this.content.trim();
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '名称不能为空' });
      return;
    }
    const role: string = this.sanitizeRoleValue();
    const position: string = this.sanitizePositionValue();
    const depth: number = this.sanitizeDepthValue();
    const done: () => void = (): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      // ★ 2026-08-30 修复：pop 必须带 result——官方 onPop 触发条件（navigation.d.ts 原文
      // 「triggered only when the result parameter is set in pop」）；无参 pop() 不触发库页
      // onPop reload → 保存后回列表不刷新（ProviderDetailPage.pop({ saved: true }) 同日
      // 同款定稿先例；保存成功才 pop，result 仅作触发标记）
      this.pathStack.pop({ saved: true });
    };
    if (this.editId === '') {
      insertTemplate(name, content, role, position, depth)
        .then((): void => {
          done();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    } else {
      updateTemplate(this.editId, name, content, role, position, depth)
        .then((): void => {
          done();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Text('名称')
            .fontSize(SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(cardTitleColor())
            .width('100%')
          TextInput({ placeholder: '例如 翻译助理、代码专家', text: this.name })
            .width('100%')
            .maxLength(TEMPLATE_NAME_MAX)
            .onChange((value: string): void => {
              this.name = value;
            })
        }
        .width(CARD_PANEL_WIDTH)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          Text('内容')
            .fontSize(SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(cardTitleColor())
            .width('100%')
          TextArea({ placeholder: '输入人设或指令，留空则不注入', text: this.content })
            .width('100%')
            .height(220)
            .maxLength(TEMPLATE_CONTENT_MAX)
            .onChange((value: string): void => {
              this.content = value;
            })
          // 注入配置面板（身份/位置/深度——按钮弹菜单官方材质；组合语义见域件头注释；
          // 与 UI 联动同口径钳位亦在保存链兜底）
          PromptInjectConfig({
            role: this.injectRole,
            injectPosition: this.injectPosition,
            depth: this.injectDepth,
            onRoleChanged: (role: string): void => {
              this.injectRole = role;
              // 联动：身份 system → 位置强制 head；assistant → 深度 0 钳位 1（域件口径）
              if (role === INJECT_ROLE_SYSTEM) {
                this.injectPosition = INJECT_POSITION_HEAD;
              } else if (role === INJECT_ROLE_ASSISTANT && this.injectDepth === 0) {
                this.injectDepth = 1;
              }
            },
            onPositionChanged: (position: string, depth: number): void => {
              this.injectPosition = position;
              this.injectDepth = depth;
            }
          })
          Text('提示词将在每条消息发送时注入请求。会话选中本模板后，后续修改将即时跟随。')
            .fontSize(11)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .alignItems(HorizontalAlign.Start)
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
      title: '编辑提示词',
      menuHds: promptSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: promptSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
