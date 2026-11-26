// 系统提示词独立页（库页不显示、独立页管理、内置默认可改可重置、底部「重置/保存」两键）。
// · 文字层级：提示/说明性文本灰（cardDescColor），卡内标题 16fp Medium 主色（cardTitleColor
//   ——2026-11-01 板块标题改档笔随卡内小节标题档归一）；
//   两页同规（AssistantPromptPage 同步，防同版式跨页字体色跳变）。
// · 存储 = prompt_templates.isGlobal=1 唯一行（PromptTemplateDb 唯一真源，注入链零改动——
//   系统提示词行 = 注入基座兜底；会话提示词 > 助手提示词 > 系统提示词 三级回退）。
// · 形态：说明 + 内容多行（320vp，留空 = 不注入）+ 变量插入条（PromptVariableStrip 收在内容卡
//   底栏；官方胶囊 + 显式实色 + 原生按压，不接沉浸光感，豁免同族见该件头注释；数据源
//   PROMPT_VARIABLES 单源；有光标插入到光标处，无光标追加末尾）+ 底部「重置/保存」按钮条。
// · 底部键条 = 吸底悬浮、条透明不挂材质（内容滚到条后透出）；按钮走 fallbackButton* 四件套
//   双态：实底态重置 = 卡外面白底 fallbackButtonBgOffCard（本页无卡体，键条坐 page_bg 灰底）、
//   保存 = emphasize 蓝底 + stateEffect(true)；光感态透传原 resolvedButton* 材质光感。
// · 系统提示词取消身份/位置配置：保存/重置写固定 system+head+0；说明行与内容卡同宽
//   CARD_PANEL_WIDTH（勿 width('100%')），外层 Column 默认居中（勿加 alignSelf(Start)）。
// · 「重置」= 内容回 SYSTEM_PROMPT_DEFAULT + 注入三列回 system/head/0；「保存」= updateTemplate
//   → toast + pop 带 result（坑17）。右上角无菜单键（标题栏 checkmark 键不用——底部键取代）。
// · 表单重构：变量区收进内容卡底栏，内容块改实色卡片并加字数计数；变量集、光标位插入与
//   保存链零改。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_SYSTEM_PROMPT } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, SECTION_GAP, cardBg, cardDescColor, cardTitleColor, CARD_SECTION_TITLE_FONTSIZE, CARD_RADIUS } from '../../common/Theme';
import { bindKeyboardAvoidArea, KEYBOARD_CARD_TAIL, KeyboardCardScroller } from '../../common/KeyboardCardScroll';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgOffCard,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import {
  PROMPT_GLOBAL_ID, queryGlobalTemplate, SYSTEM_PROMPT_DEFAULT,
  TEMPLATE_CONTENT_MAX, updateTemplate
} from '../../common/store/PromptTemplateDb';
import {
  INJECT_POSITION_HEAD, INJECT_ROLE_SYSTEM
} from '../../common/providers/RequestInject';
import {
  appendVariableToken, hasVolatileTimeTokens, insertVariableToken,
  PromptInsertResult, PromptVariableInfo, PROMPT_VOLATILE_TIME_HINT
} from '../../common/providers/PromptVariables';
import { InfoHintButton } from '../InfoHintButton';
import { InfoCard } from '../InfoCard';
import { PromptVariableStrip } from '../PromptVariableStrip';

@Component
export struct SystemPromptPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private content: string = '';
  // 加载完成闸：queryGlobalTemplate 未回填时 content 是空初值，此窗内保存会把空串写进
  // prompt-global 行 = 系统提示词被清空（与 PromptEditPage O-13 同族）。读失败 catch 已置
  // loaded = true（按内置默认显示，所见即所存）
  @State private loaded: boolean = false;
  // 变量插入光标位：普通成员不进 @State（不驱动 UI）；controller 是官方光标 API 载体
  private contentCtrl: TextAreaController = new TextAreaController();
  private caretIndex: number = -1;
  // 编辑态：驱动编辑器压短（聚焦时 320 → 160）——键盘弹起后整张内容卡（含卡内变量条）
  // 才能收进键盘上沿之上（2026-11-05 键盘遮挡笔）
  @State private editing: boolean = false;
  private caretTimer: number = -1;
  // 页面滚动器 + 卡底定位器（2026-11-05 两千一百零二）：聚焦后按实测位置把内容卡底边——
  // 含卡底变量条的说明行——滚到吸底键条上沿之上（算式与时序单源 = KeyboardCardScroll）
  private pageScroller: Scroller = new Scroller();
  // 底部让位 = 吸底键条高（条上内距 12 + 按钮 40 + 条下内距 bottomPad+16）
  private cardScroll: KeyboardCardScroller = new KeyboardCardScroller(this.pageScroller);
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位 + 内容区回退开关（按钮双态 = fallbackButton* 四件套——实底态强制官方实色 /
  // 光感态随沉浸光感总档；AppStorage 订阅式切换即刷，坑16 正解）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    // 键盘上沿缓读绑定（进程内单次；卡底定位要它兜住「页面底边略低于键盘上沿」那一档）
    bindKeyboardAvoidArea(this.getUIContext());
    queryGlobalTemplate()
      .then((row): void => {
        if (this.departed) {
          return;
        }
        this.content = row.content;
        // 整体换文：旧光标索引作废（用户若在回填前已点入内容框，索引对应的是旧文本）
        this.caretIndex = -1;
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 读取失败：按内置默认显示（页面仍可编辑保存——兜底不静默，Toast 明示）
        this.getUIContext().getPromptAction().showToast({ message: '系统提示词读取失败：' + (e as Error).message + '（已按内置默认显示）' });
        this.content = SYSTEM_PROMPT_DEFAULT;
        this.caretIndex = -1;
        this.loaded = true;
      });
  }

  // 保存（prompt-global 行，名称固定「系统提示词」；注入三列恒默认 system+head+0）
  private save(): void {
    // 加载完成闸（未回填完 = content 是空初值，落库即清空——见成员位注释）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '系统提示词未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const content: string = this.content.trim();
    updateTemplate(PROMPT_GLOBAL_ID, '系统提示词', content,
      INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
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

  // 重置内置默认（内容回内置 + 注入三列回默认；行名不动）
  private reset(): void {
    // 加载完成闸（与 save() 同形同理由——重载在途点重置会先落默认值，加载 then 后到再把
    // 旧值刷回内容框 = 所见非所存；底部「重置」键无条件渲染。读失败分支已置真，不受影响）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '系统提示词未加载完成，暂不能重置，请返回重进' });
      return;
    }
    updateTemplate(PROMPT_GLOBAL_ID, '系统提示词', SYSTEM_PROMPT_DEFAULT,
      INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.content = SYSTEM_PROMPT_DEFAULT;
        // 整体换文：旧光标索引作废并清在途回位定时器，防新内容上按旧索引插入或回位
        this.caretIndex = -1;
        if (this.caretTimer >= 0) {
          clearTimeout(this.caretTimer);
          this.caretTimer = -1;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已重置为内置默认' });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '重置失败：' + (e as Error).message });
      });
  }

  // 变量卡点按：有光标按索引插入并回位；无光标走 appendVariableToken 追加末尾（同 AssistantPromptPage）
  private insertVariable(info: PromptVariableInfo): void {
    // 闸只认最后一次光标位（caretIndex）：失焦后点按仍应插到光标处，不得静默退化追加
    //（2026-11-05 浮条笔，与 PromptEditPage 同口径）
    if (this.caretIndex < 0) {
      this.content = appendVariableToken(this.content, info.token);
      return;
    }
    const result: PromptInsertResult = insertVariableToken(this.content, info.token, this.caretIndex);
    // 先记账新光标再改 text：连续点按变量时下一次插入仍接在本 token 之后，不退回旧索引
    this.caretIndex = result.caret;
    this.content = result.content;
    this.scheduleCaretRestore(result.caret);
  }

  // 程序化改 text 后光标会回末尾，且同帧 caretPosition 不生效，故 0ms 后置光标；onChange
  // 若有待回位任务会续排一次。定时器成对释放：aboutToDisappear 清。
  private scheduleCaretRestore(caret: number): void {
    if (this.caretTimer >= 0) {
      clearTimeout(this.caretTimer);
    }
    this.caretTimer = setTimeout((): void => {
      this.caretTimer = -1;
      if (this.departed) {
        return;
      }
      // 失焦态 caretPosition 不生效，只在编辑态回位；插入位置由 caretIndex 记账承接
      //（2026-11-05 浮条笔，与 PromptEditPage 同口径）
      if (this.editing) {
        this.contentCtrl.caretPosition(caret);
      }
    }, 0);
  }

  // 聚焦定位交给 KeyboardCardScroller（卡底实测位置 → 滚到吸底键条上沿之上，2026-11-05
  // 两千一百零二）；不再 scrollEdge 滚到底——本页卡是滚动内容最后一块，滚到底只能让卡底
  // 齐平键条上沿，变量条的说明行仍会被键条压住

  @Builder
  Content() {
    // 底部按钮条 = 会话页输入栏同款 Stack(alignContent Bottom)：滚动区全高 + 条悬浮底部、
    // 条透明不挂材质（内容滚到条后透出）；滚动内容底部 padding 让位条高。条内按钮 = 官方
    // 实底行内形制（内容区回退双态，见头注释；原「resolvedButton 四件套 + 材质条」废弃）。
    // 让位常量 = 条上内边距 12 + 按钮 40 + 条下内边距 (bottomPad+16)——改条高须两处同改
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll(this.pageScroller) {
        // 板块间 SECTION_GAP（Theme 三档常量）
        Column({ space: SECTION_GAP }) {
          // 说明卡 = InfoCard 单源件
          InfoCard({ text: '未开启会话提示词注入且助手未设置提示词时自动注入。开启会话级提示词后不注入。' })

          // ── 内容卡（编辑器 + 变量插入底栏）──
          Column({ space: 12 }) {
            // 标题行 + 计数 + volatile 时间变量气泡（内容含 {{time}}/{{datetime}} 时条件出现——
            // 分钟粒度变量每轮替换会打断提示词缓存，文案单源 PROMPT_VOLATILE_TIME_HINT）
            Row({ space: 8 }) {
              Text('内容')
                .fontSize(CARD_SECTION_TITLE_FONTSIZE)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .layoutWeight(1)
              if (hasVolatileTimeTokens(this.content)) {
                InfoHintButton({ text: PROMPT_VOLATILE_TIME_HINT })
              }
              Text(this.content.length + ' / ' + TEMPLATE_CONTENT_MAX)
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            TextArea({
              placeholder: '输入系统提示词，留空则不注入',
              text: this.content,
              controller: this.contentCtrl
            })
              .width('100%')
              // 内容框高度两档（2026-11-05 键盘遮挡笔）：静止 320 保持原形态；编辑态压到 160，
              // 键盘占屏后整张内容卡（含卡内变量条）才收得进键盘上沿之上
              .height(this.editing ? 160 : 320)
              .maxLength(TEMPLATE_CONTENT_MAX)
              .onChange((value: string): void => {
                this.content = value;
                // 程序化插入待回位：若本次变化由状态赋值触发，续排一次让光标在渲染落地后归位
                if (this.caretTimer >= 0) {
                  this.scheduleCaretRestore(this.caretIndex);
                }
              })
              // 光标/选区变化记账（选区存在时取末端 = 插入点）；回位定时器在途时忽略中间态
              //（程序化改 text 会把光标先甩到末尾，回调可能先报尾部，不能覆盖目标索引）
              .onTextSelectionChange((_selectionStart: number, selectionEnd: number): void => {
                if (this.caretTimer >= 0) {
                  return;
                }
                this.caretIndex = selectionEnd;
              })
              // 官方定义：输入框有光标即编辑态，否则非编辑态——正是「内容里有没有显示光标」判据
              .onEditChange((isEditing: boolean): void => {
                this.editing = isEditing;
                // 键盘避让切官方 RESIZE（聊天页输入栏同款处方）：RESIZE_WITH_CARET 下本页
                // 高度不压缩，键盘盖住页面——吸底「重置/保存」条与卡底说明行都停在原位被遮
                // （2026-11-05 两千一百零四真机实锤：视口高 813vp = 全高）
                this.getUIContext().setKeyboardAvoidMode(isEditing ?
                  KeyboardAvoidMode.RESIZE : KeyboardAvoidMode.RESIZE_WITH_CARET);
                // 压短编辑框 + 卡底定位随编辑态起停（底部让位 = 吸底键条高；2026-11-05）
                this.cardScroll.setEditing(isEditing, this.bottomPad + 68);
              })
            // 变量插入条（三页共用 PromptVariableStrip，变量集仍是 PromptVariables 单源）
            PromptVariableStrip({
              label: '点击插入变量',
              hint: '发送前替换为实际值。点按插入到光标处，未显示光标时追加到末尾',
              onPick: (info: PromptVariableInfo): void => {
                this.insertVariable(info);
              }
            })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
          // 卡底实测上报（定位器据此算「卡底超出可视底缘多少」；2026-11-05 两千一百零二）
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.cardScroll.onCardArea(newArea);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        // 底部让位按钮条（条高 = 12 + 40 + bottomPad + 16——与按钮条两处同改）；编辑态再补
        // KEYBOARD_CARD_TAIL——卡下方只有这一让位，不补就滚不到「卡底留白在键条上沿之上」
        .padding({
          top: this.topPad,
          bottom: this.bottomPad + 68 + (this.editing ? KEYBOARD_CARD_TAIL : 0)
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      // 视口实测上报（键盘压缩页面后视口高变化即触发卡底定位；2026-11-05 两千一百零二）
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.cardScroll.onViewportArea(newArea);
      })

      // ── 底部操作键条（吸底悬浮 + 条透明——内容滚到条后透出）──
      // 内容区回退双态：实底态 = 重置为卡外面白底 fallbackButtonBgOffCard（本页无卡体，键条
      // 坐 page_bg 灰底，灰键不显形）/ 保存 = emphasize 蓝底 + 恒白字 + stateEffect(true)；
      // 光感态 = fallbackButton* 透传原 resolvedButton* 材质。条不设 backgroundColor（透明悬浮，
      // 交互区 = 按钮本体）
      Column() {
        Row({ space: 12 }) {
          // 次操作：卡外面白底（浅白/深灰）+ 原生按压（AGENTS.md 行内按钮官方形制）
          Button('重置')
            .layoutWeight(1)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick((): void => {
              this.reset();
            })
          // 「保存」= 主操作：官方强调蓝底 + 恒白字 + 原生按压（与次钮同族，primary=true）
          Button('保存')
            .layoutWeight(1)
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick((): void => {
              this.save();
            })
        }
        .width(CARD_PANEL_WIDTH)
      }
      .width('100%')
      // 按钮条不挂材质（原 THIN 半透明条被误读为蒙层）——按钮自身官方实底直接悬浮；
      // 条透明，内容滚到条后透出（交互区 = 按钮本体）
      .padding({ top: 12, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_SYSTEM_PROMPT,
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 光标回位定时器成对释放：页面退出后不得再碰已释放的 TextArea
    if (this.caretTimer >= 0) {
      clearTimeout(this.caretTimer);
      this.caretTimer = -1;
    }
    // 卡底定位器成对释放（命中即页面已退，迟到回调不得再碰 Scroller）
    this.cardScroll.dispose();
    // 键盘避让模式兜底恢复：聚焦中被返回时窗口级模式会留在 RESIZE，与 onEditChange 成对复原
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
  }
}
