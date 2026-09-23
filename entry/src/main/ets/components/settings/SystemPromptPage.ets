// 系统提示词独立页（2026-08-31 领导指令：系统提示词与会话提示词「分开」——库页不显示、
// 独立页管理、内置默认可更改可重置、右上角勾取消改底部「恢复/保存」两按钮）：
// · **文字层级（2026-09-01 领导指令，本页定稿口径）：提示性/说明性文本灰色
//   （cardDescColor——首行说明、placeholder、变量卡副行「发送前替换…」等），功能/布局/
//   板块级标题黑色（cardTitleColor——「点击插入变量」「内容」两处板块标题）；两类分治
//   层级立辨，两页同规（AssistantPromptPage 同款同步，防同版式跨页字体色跳变）；
// · 存储 = prompt_templates.isGlobal=1 唯一行（PromptTemplateDb——唯一真源不变，零 DB
//   迁移；注入链 ChatSendCtrl.loadPromptState 零改动——系统提示词行 = 注入基座兜底，
//   ★2026-09-04 归属与注入解耦：会话提示词 > 助手提示词 > 系统提示词 三级回退）；
// · 形态：说明 + 内容多行 + 变量插入区（★ **2026-09-07 领导指令：变量插入区与内容框上下
//   互换**——内容框上移居首、变量区下移（2026-09-01 旧版序「内容框下移上增变量区」作废）。
//   变量卡 = 官方胶囊按钮（★ 2026-09-07 决明拍板：**不接沉浸光感**——历轮真机四连：
//   缺省 ROUNDED_RECTANGLE 大矩形 / Material.empty 双层蒙层 / 光感透明底无按钮底 /
//   无背景默认强调蓝；终版 = 显式官方灰阶实色 app.color.comp_fallback_gray + 原生按压 +
//   显式 Capsule——依据见 Content 内注释；
//   「选项 chips 无按压光感」豁免自本卡起不适用，其余 chips 照旧），
//   字色 = 用量统计页主蓝（usageAccentColor，2026-09-07 决明「变量卡蓝色统一为用量统计
//   页色值」——原淡蓝定稿退役）、版式 3 列 11/10fp 不变——版式依据见 Content
//   内注释）；数据源 = PromptVariables.PROMPT_VARIABLES 单源（助手页同款，改变量自动
//   同步两处）；点击 = 追加 token 到内容末尾（v1 简化，同助手页 insertVariable——cursor
//   位插入为调研档增强项）+ 内容多行（留空 = 不注入——placeholder 明示；★ 2026-09-01
//   领导「长度增大」220→320vp）+ **底部「恢复/保存」按钮条**（★ 2026-09-01 领导反馈
//   「按钮排分割线、页面透不出来 → 参考会话页底部内容可通过输入框透出」定稿：按钮条 =
//   悬浮底部、条透明不挂材质——内容滚到条后透出，无实色分割带；条内按钮官方灰底行内形制）；
//   ★ 2026-09-03 内容区回退双态：按钮走 fallbackButton* 四件套（新规范下普通内容区材质
//   不生效）——实底态（默认，外观页开关 contentFallback=true）= 恢复=tertiary 灰底、
//   保存=emphasize 蓝底 + stateEffect(true) 原生按压；光感态 = 透传原 resolvedButton*
//   材质光感（随沉浸光感总档）。官方语义色自动深浅反色。
//   ★ 2026-08-31 领导追加：系统提示词**取消身份/位置（注入配置）功能**——页面不再挂 PromptInjectConfig，
//   保存/恢复写固定默认 system+head+0（同注入链默认行为）；说明行与内容卡同宽
//   CARD_PANEL_WIDTH（勿 width('100%')——左右横宽不对实锤；外层 Column 默认
//   alignItems=Center 居中——勿加 alignSelf(Start)，左右不居中实锤）；
// · 「恢复」= 内容回内置默认 SYSTEM_PROMPT_DEFAULT + 注入三列回 system/head/0（可重置）；
// · 「保存」= updateTemplate（prompt-global 行）→ toast + pop 带 result（坑17：保存
//   pop 必带）；
// · 右上角无菜单键 = 「勾取消」（PageShell menuHds/menuNav 不传 = 默认 null/[] 无菜单；
//   标题栏 checkmark 保存键在本页不用——底部「保存」按钮取代）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_SYSTEM_PROMPT } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE, usageAccentColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import {
  PROMPT_GLOBAL_ID, queryGlobalTemplate, SYSTEM_PROMPT_DEFAULT,
  TEMPLATE_CONTENT_MAX, updateTemplate
} from '../../common/store/PromptTemplateDb';
import {
  INJECT_POSITION_HEAD, INJECT_ROLE_SYSTEM
} from '../../common/providers/RequestInject';
import {
  appendVariableToken, PROMPT_VARIABLES, PromptVariableInfo
} from '../../common/providers/PromptVariables';

@Component
export struct SystemPromptPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private content: string = '';
  // 加载完成闸（★ 2026-09-14 全面自检第3轮笔4：在案项收口——第 1 轮 §3-E 判死变量
  // 「二选一：接线或删除」，本笔取接线）：queryGlobalTemplate 异步回填未完成时 content
  // 是空初值，此窗内点「保存」会把空串写进 prompt-global 行 = 系统提示词被清空（与
  // PromptEditPage O-13 同族同根因，闸形制照其 :146 先例）。读取失败 catch 已置
  // loaded = true（按内置默认显示，所见即所存，不需闸）。
  @State private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位 + 内容区回退开关（2026-09-03 开关体系恢复：按钮
  // 双态 = fallbackButton* 四件套——实底态（默认）强制官方实色 / 光感态随沉浸光感总档
  //（2026-09-12 分项退役口径）；
  // AppStorage 订阅式切换即刷，坑16 正解，同档位键契约）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    queryGlobalTemplate()
      .then((row): void => {
        this.content = row.content;
        this.loaded = true;
      })
      .catch((e: Object): void => {
        // 读取失败：按内置默认显示（页面仍可编辑保存——兜底不静默，Toast 明示）
        this.getUIContext().getPromptAction().showToast({ message: '系统提示词读取失败：' + (e as Error).message + '（已按内置默认显示）' });
        this.content = SYSTEM_PROMPT_DEFAULT;
        this.loaded = true;
      });
  }

  // 保存（prompt-global 行，名称固定「系统提示词」；注入三列恒默认 system+head+0——
  // 2026-08-31 领导追加取消身份/位置配置，固定默认注入）
  private save(): void {
    // 加载完成闸（未回填完 = content 是空初值，落库即清空系统提示词；形制照
    // PromptEditPage O-13 修复——见成员位注释）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '系统提示词未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const content: string = this.content.trim();
    updateTemplate(PROMPT_GLOBAL_ID, '系统提示词', content,
      INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 恢复内置默认（内容回内置 + 注入三列回默认；行名不动）
  private restore(): void {
    updateTemplate(PROMPT_GLOBAL_ID, '系统提示词', SYSTEM_PROMPT_DEFAULT,
      INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
      .then((): void => {
        this.content = SYSTEM_PROMPT_DEFAULT;
        this.getUIContext().getPromptAction().showToast({ message: '已恢复为内置默认' });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '恢复失败：' + (e as Error).message });
      });
  }

  // 变量卡点按：追加 token 到内容末尾（appendVariableToken 单一来源——2026-09-01 分区化
  // 收敛共用纯函数：末尾空白不补空格；AssistantPromptPage 同函数，防两页漂移）
  private insertVariable(info: PromptVariableInfo): void {
    this.content = appendVariableToken(this.content, info.token);
  }

  @Builder
  Content() {
    // ★ 2026-09-01 领导反馈「参考会话页底部内容可通过输入框透出」：底部按钮条改为会话页
    // 输入栏同款——Stack(alignContent Bottom)：滚动区全高 + 按钮条悬浮底部、条透明
    // 不挂材质（2026-09-02 决明反馈「无背后蒙层」：原 THIN 半透明条被误读为蒙层——条透明，
    // 内容滚到条后透出）；滚动内容底部 padding 让位条高。条内按钮 = 官方实底行内形制
    //（2026-09-03 内容区回退，见头注释；原「resolvedButton 四件套 + 材质条」口径废弃）。
    // 让位常量 = 条上内边距 12 + 按钮 40 + 条下内边距 (bottomPad+16) —— 滚动区 padding
    // bottom 同值（改条高须同步改此处，两处同改）
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 12 }) {
          Text('未开启会话提示词注入且助手未设置提示词时自动注入。开启会话级提示词后不注入。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)

          // 内容多行（★ 2026-09-07 领导指令：与变量插入区上下互换——内容框上移居首）
          Column({ space: 6 }) {
            Text('内容')
              .fontSize(SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .width('100%')
            TextArea({ placeholder: '输入系统提示词，留空则不注入', text: this.content })
              .width('100%')
              // ★ 2026-09-01 领导「内容框长度增大」：220 → 320——滚动区全高 + 按钮条
              // 悬浮，内容再多可滚、按钮恒可见
              .height(320)
              .maxLength(TEMPLATE_CONTENT_MAX)
              .onChange((value: string): void => {
                this.content = value;
              })
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(HorizontalAlign.Start)

          // ── 变量插入区（★ 2026-09-07 领导指令：与内容框上下互换后居其下；变量卡 =
          // 官方胶囊按钮——不接光感、官方灰阶实色（2026-09-07 拍板；四连真机依据见下卡
          // 注释；contentFallback/光感档位仅驱动本页底部键，与本卡无关）；
          // 「选项 chips 无按压光感」豁免自本卡起不适用，其余 chips 照旧）：
          // 数据源 = PromptVariables.PROMPT_VARIABLES 单源（与助手页同源，改变量两处自动
          // 同步）；版式沿用 2026-09-01 真机反馈定稿 Grid **3 列**等宽 + token 11fp/label
          // 10fp 两行（版式依据 = 真机 Pura 80 Pro+ 420vp 宽 → CARD_PANEL_WIDTH 388vp →
          // 3 列 ≈124vp，最长 token {{datetime}} 11 字符 × 11fp ≈121vp 恰好放下（2 列版卡
          // 宽 ~190vp 被否）；窄屏（360vp 级 → ~104vp）由 token maxLines(1) + Ellipsis
          // 兜底不破词）；字色 = 用量统计页主蓝（usageAccentColor——2026-09-07 决明
          // 「统一为用量统计页色值」，深浅分治，见 Theme.ets——按钮壳子内容文本自定色，
          // 不同于行内文字键 label 字色）
          Column({ space: 8 }) {
            Text('点击插入变量')
              .fontSize(SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .width('100%')
            Text('发送前替换为实际值。点按将变量追加到内容末尾')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            Grid() {
              ForEach(PROMPT_VARIABLES, (info: PromptVariableInfo) => {
                GridItem() {
                  Button() {
                    Column({ space: 2 }) {
                      Text(info.token)
                        .fontSize(11)
                        .fontColor(usageAccentColor(this.appColorMode))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(info.label)
                        .fontSize(10)
                        .fontColor(usageAccentColor(this.appColorMode))
                    }
                    .justifyContent(FlexAlign.Center)
                  }
                  // ★ 终拍后真机首观感：「蓝底」——Button(){} 无参自定义内容默认 = 主按钮
                  // 强调蓝（comp_background_emphasize，保存键同族）；改显式官方灰阶实色
                  // app.color.comp_fallback_gray（与底部恢复键/输入框同系灰，深浅分治
                  // 不透明）——「背景显式 + 无 systemMaterial」= 历轮验证过的单层组合；
                  // type(Capsule) 胶囊 + 官方原生按压（stateEffect 默认 true）+ 显式
                  // padding（上下 6 / 水平 4）；字色 = 用量统计主蓝（usageAccentColor，
                  // 2026-09-07 指令统一）；
                  // 光感体系本卡不接——见 Theme 头注释例外
                  .type(ButtonType.Capsule)
                  .width('100%')
                  .padding({ top: 6, bottom: 6, left: 4, right: 4 })
                  .backgroundColor($r('app.color.comp_fallback_gray'))
                  .onClick((): void => {
                    this.insertVariable(info);
                  })
                }
              }, (info: PromptVariableInfo): string => info.token)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            // 高度自适应内容——Grid 不设高度时按父容器撑满（滚动容器语义），显式 auto
            // 让 8 卡 3 列排 3 行自适应（版式受控不悬空）
            .height('auto')
            .width('100%')
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        // 底部让位按钮条（条高 = 12 + 40 + bottomPad + 16——与按钮条两处同改）
        .padding({ top: this.topPad, bottom: this.bottomPad + 68 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // ── 底部操作键条（吸底悬浮 + 条透明——内容滚到条后透出）──
      // 2026-09-03 内容区回退双态：实底态（默认）= 恢复 = 次钮（官方灰阶实色
      // app.color.comp_fallback_gray——深浅分治不透明，见 ImmersiveLevel.fallbackButtonBg
      // 注释）/ 保存 = 主钮（comp_background_emphasize 官方强调蓝 + font_on_primary
      // 恒白字）+ stateEffect(true) 原生按压光感；光感态 = fallbackButton* 透传原
      // resolvedButton* 材质光感。官方语义色自动深浅反色，零自写色值；
      // 条不设 backgroundColor（透明悬浮，交互区 = 按钮本体，条 padding 不含命中区）
      Column() {
        Row({ space: 12 }) {
          // 次操作：官方三级灰底 + 原生按压光感（AGENTS.md 行内按钮官方形制——官方默认
          // 形状/字号/字色；2026-09-03 内容区回退双态：实底/光感见 fallbackButton* 语义）
          Button('恢复')
            .layoutWeight(1)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick((): void => {
              this.restore();
            })
          // 「保存」= 主操作：官方强调蓝底 + font_on_primary 恒白 + 原生按压光感
          //（2026-09-03 内容区回退双态：与次钮同族，primary=true）
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
      // 2026-09-02 决明反馈「无背后蒙层」：按钮条不挂材质（原 THIN 半透明条被误读为蒙层）
      // ——按钮自身官方实底，直接悬浮固定底部；条透明，内容滚到条后透出（交互区 = 按钮
      // 本体，条 padding 不含命中区）
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
}
