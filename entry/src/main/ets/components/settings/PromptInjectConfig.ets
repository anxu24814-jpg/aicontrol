// 提示词注入配置域件（2026-08-30 注入身份/位置/深度配置；提示词编辑页「内容」输入框下方
// 装配——照领导拍板「分按钮点击弹菜单、选项放菜单、均官方材质」）：
// · 两行内功能键（2026-09-02 沉浸光感化 + 2026-09-03 内容区回退双态：光感态 = resolvedButton
//   四件套——材质 REGULAR 基准 + 按压形变/触点光效 + 官方浅灰配色，随沉浸光感总档，无
//   光感档回退官方灰底；实底态 = fallbackButton* 官方实底（内容区非弹窗组件材质不生效时
//   兜底，CONTENT_FALLBACK_KEY 驱动）；不覆盖官方默认形状/字号——「选项」但功能单选键，
//   走功能键形制，非 chips）：「注入身份」
//   （弹菜单：系统身份/用户身份/AI 回复身份）+「注入位置」（弹菜单：系统提示位/最新
//   用户消息前/深度 1~4）；
// · 菜单 = 官方 openMenu 编程式（照 PromptTemplateMenu/AppMenuHost 先例：ComponentContent
//   成对 init/dispose、弹出前 rebuild、锚点 = 按钮自身 .id（编辑页单实例固定 id）、REGULAR
//   官方材质随沉浸光感总档、选中项 symbolEndIcon 勾选 checkmark）；
// · 联动（组合语义 = RequestInject.composeSendMessages 注释）：身份 system → 位置恒
//   head（位置键禁用 + 官方 disabled 视觉）；身份 assistant → 位置不含「最新用户消息前」
//   （= 深度 0 = 注入成末条：Anthropic=prefill 合法但 Gemini 末条必须 user 会 400 且跨
//   模型行为不一致）→ 仅深度 1~4，选中 assistant 时 depth=0 自动钳位为 1；
// · 取值上行两回调（父页 @State 持有，保存链落库用）；配置组合语义/协议适配见 RequestInject。
import { ComponentContent, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppMenuHost } from '../../common/AppMenuHost';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import { cardDescColor, menuDividerColor } from '../../common/Theme';
import {
  INJECT_DEPTH_MAX, INJECT_POSITION_DEPTH, INJECT_POSITION_HEAD,
  INJECT_ROLE_ASSISTANT, INJECT_ROLE_SYSTEM, INJECT_ROLE_USER
} from '../../common/providers/RequestInject';

// 锚点 id（编辑页单实例，固定 id 即可——勿加模板 id 后缀）
export const PROMPT_INJECT_ROLE_ANCHOR_ID: string = 'promptInjectRoleBtn';
export const PROMPT_INJECT_POSITION_ANCHOR_ID: string = 'promptInjectPositionBtn';

// 注入配置脏值钳位（模块级，回填/保存链共用——2026-08-31 自 PromptEditPage 提取：
// 编辑页与系统提示词页两处消费，P2-4 消重复；默认值 = 现状注入行为）
export function sanitizeInjectRole(raw: string): string {
  return raw === INJECT_ROLE_USER || raw === INJECT_ROLE_ASSISTANT ? raw : INJECT_ROLE_SYSTEM;
}

export function sanitizeInjectPosition(raw: string): string {
  return raw === INJECT_POSITION_DEPTH ? raw : INJECT_POSITION_HEAD;
}

export function sanitizeInjectDepth(raw: number): number {
  if (isNaN(raw) || raw < 0 || raw > INJECT_DEPTH_MAX) {
    return 0;
  }
  return raw;
}

// 注入位置档显示（head/depth 两档 + 深度参数——label 与合成共用）
function roleLabelOf(role: string): string {
  if (role === INJECT_ROLE_USER) {
    return '用户身份';
  }
  if (role === INJECT_ROLE_ASSISTANT) {
    return 'AI 回复身份';
  }
  return '系统身份';
}

function positionLabelOf(position: string, depth: number): string {
  if (position === INJECT_POSITION_HEAD) {
    return '系统提示位';
  }
  return depth <= 0 ? '最新用户消息前' : '深度 ' + depth;
}

// ── 注入身份菜单 ──
export interface InjectRoleMenuCallbacks {
  role: string;
  onPick: (role: string) => void;
}

@Builder
export function InjectRoleMenuBuilder(params: InjectRoleMenuCallbacks) {
  Menu() {
    MenuItem({
      content: '系统身份',
      symbolEndIcon: params.role === INJECT_ROLE_SYSTEM ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
    })
      .onClick(() => {
        params.onPick(INJECT_ROLE_SYSTEM);
      })
    MenuItem({
      content: '用户身份',
      symbolEndIcon: params.role === INJECT_ROLE_USER ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
    })
      .onClick(() => {
        params.onPick(INJECT_ROLE_USER);
      })
    MenuItem({
      content: 'AI 回复身份',
      symbolEndIcon: params.role === INJECT_ROLE_ASSISTANT ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
    })
      .onClick(() => {
        params.onPick(INJECT_ROLE_ASSISTANT);
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

export class InjectRoleMenuHost extends AppMenuHost<InjectRoleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: InjectRoleMenuCallbacks): ComponentContent<InjectRoleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(InjectRoleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: InjectRoleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROMPT_INJECT_ROLE_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ── 注入位置菜单 ──
export interface InjectPositionMenuCallbacks {
  position: string;
  depth: number;
  assistantOnly: boolean; // 身份 assistant：菜单不含「最新用户消息前」（联动见头注释）
  onPick: (position: string, depth: number) => void;
}

@Builder
export function InjectPositionMenuBuilder(params: InjectPositionMenuCallbacks) {
  Menu() {
    MenuItem({
      content: '系统提示位',
      symbolEndIcon: params.position === INJECT_POSITION_HEAD ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
    })
      .onClick(() => {
        params.onPick(INJECT_POSITION_HEAD, 0);
      })
    if (!params.assistantOnly) {
      MenuItem({
        content: '最新用户消息前',
        symbolEndIcon: params.position === INJECT_POSITION_DEPTH && params.depth <= 0 ?
          new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          params.onPick(INJECT_POSITION_DEPTH, 0);
        })
    }
    ForEach(depthItems(params.assistantOnly), (d: number) => {
      MenuItem({
        content: '深度 ' + d,
        symbolEndIcon: params.position === INJECT_POSITION_DEPTH && params.depth === d ?
          new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          params.onPick(INJECT_POSITION_DEPTH, d);
        })
    }, (d: number): string => String(d))
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

function depthItems(assistantOnly: boolean): number[] {
  const items: number[] = [];
  const from: number = assistantOnly ? 1 : 0;
  for (let d = from; d <= INJECT_DEPTH_MAX; d++) {
    items.push(d);
  }
  return items;
}

export class InjectPositionMenuHost extends AppMenuHost<InjectPositionMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: InjectPositionMenuCallbacks): ComponentContent<InjectPositionMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(InjectPositionMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: InjectPositionMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROMPT_INJECT_POSITION_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

@Component
export struct PromptInjectConfig {
  // 当前配置（父页 @State 持有——保存链落库与回填走父；本域件单选改后上行）
  @Prop role: string = INJECT_ROLE_SYSTEM;
  // ★ 命名避坑：不能叫 position——CustomComponent 基类通用属性 position() 冲突
  // （编译 10505001 实锤），改 injectPosition
  @Prop injectPosition: string = INJECT_POSITION_HEAD;
  @Prop depth: number = 0;
  // 上行回调（父页覆写 @State 三字段）
  onRoleChanged: (role: string) => void = (): void => {
  };
  onPositionChanged: (position: string, depth: number) => void = (): void => {
  };
  // 深浅色 + 菜单材质档位（@StorageProp 自订阅——AppMenuHost 弹出时解析）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 菜单节点宿主（init/open/dispose 成对——见 AppMenuHost 头注释）
  private roleMenu: InjectRoleMenuHost = new InjectRoleMenuHost();
  private positionMenu: InjectPositionMenuHost = new InjectPositionMenuHost();

  aboutToAppear(): void {
    this.roleMenu.init(this.getUIContext(), this.roleCallbacks());
    this.positionMenu.init(this.getUIContext(), this.positionCallbacks());
  }

  aboutToDisappear(): void {
    this.roleMenu.dispose();
    this.positionMenu.dispose();
  }

  // 身份回调（简单透传；联动 = 位置键禁用/钳位在父侧由 onRoleChanged 覆写时收口）
  private roleCallbacks(): InjectRoleMenuCallbacks {
    return {
      role: this.role,
      onPick: (role: string): void => {
        this.onRoleChanged(role);
      }
    };
  }

  private positionCallbacks(): InjectPositionMenuCallbacks {
    return {
      position: this.injectPosition,
      depth: this.depth,
      assistantOnly: this.role === INJECT_ROLE_ASSISTANT,
      onPick: (position: string, depth: number): void => {
        this.onPositionChanged(position, depth);
      }
    };
  }

  // 位置键禁用（身份 system 恒 head——组合语义见域件头注释）
  private positionDisabled(): boolean {
    return this.role === INJECT_ROLE_SYSTEM;
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('身份：' + roleLabelOf(this.role))
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .id(PROMPT_INJECT_ROLE_ANCHOR_ID)
          .onClick((): void => {
            this.roleMenu.open(this.getUIContext(), this.roleCallbacks(),
              this.immersiveLevel);
          })
        Button('位置：' + positionLabelOf(this.injectPosition, this.depth))
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .enabled(!this.positionDisabled())
          .id(PROMPT_INJECT_POSITION_ANCHOR_ID)
          .onClick((): void => {
            if (this.positionDisabled()) {
              this.getUIContext().getPromptAction().showToast({ message: '系统身份固定注入系统提示位' });
              return;
            }
            this.positionMenu.open(this.getUIContext(), this.positionCallbacks(),
              this.immersiveLevel);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.role === INJECT_ROLE_ASSISTANT ?
        'AI 回复身份以助手既往回复身份注入，部分模型按 prefill 续写。位置仅深度 1~4。' :
        '系统身份注入系统提示位。用户身份紧邻目标用户消息，位置与深度可配。')
        .fontSize(11)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
