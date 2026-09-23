// 助手提示词二级页（2026-09-01 助手编辑页分区化——编辑页改「名称 + 六分区列表卡」枢纽后，
// 提示词配置自编辑页表单独立成本页；取参：push param = 助手 id，编辑页「提示词」卡 push）。
// 文字层级同 SystemPromptPage 定稿口径（2026-09-01：提示性文本灰 cardDescColor / 板块标题
// 黑 cardTitleColor——「点击插入变量」「内容」两处标题 + 默认只读分支「提示词（与系统提示词
// 同步，只读）」均已黑，说明行/placeholder 保持灰）。
// · 用户手建助手 = SystemPromptPage 同款形态（领导口径「参考已有系统提示词页」）：说明行 +
//   内容多行（320vp，★2026-09-04 留空 = 回退系统提示词注入）+ 变量插入区（★ 2026-09-07
//   与内容框上下互换——下移居内容框之下；「点击插入变量」小标题 + Grid 3 列 Button 卡，
//   数据源 = PromptVariables PROMPT_VARIABLES 单源——改变量两页自动同步；卡 = 内容区
//   官方胶囊按钮（2026-09-07 拍板不接光感；官方灰阶实色 + 原生按压，四连真机依据见
//   SystemPromptPage 同款注释））+
//   底部悬浮「保存」键条（半透明材质随沉浸光感总档，会话页输入栏/SystemPromptPage
//   同款光感；助手无内置默认提示词 → 无「恢复」键，单键）。保存 = updateAssistantPrompt
//   单列落库 → toast + pop 带 result（坑17——编辑页 onPop 重拉提示词摘要行）；不保存退出
//   = 草稿自然丢弃（服务商编辑页统一保存语义同口径）。
// · 内置默认助手（反馈轮 3 定稿逻辑自原 AssistantEditPage 只读分支**原样迁移，语义不改**）：
//   整页只读——说明行（指引 设置 > 系统提示词）+ 内容展示框（Text 非输入态，内容经
//   queryAssistant 读时联结 = 系统提示词当前值，每次进页即拉零缓存）；取消输入/变量卡/
//   保存（默认卡分支不渲染）；只读页无保存动作 = 返回无参 pop 不触发 onPop（预期语义）。
//   ★ 内置控制台助手（2026-09-05 控制台助手）同只读口径：说明行与标题文案分支区分
//   （readonlyHint/readonlyTitle），内容 = AssistantDb 读时联结的内置路由提示词常量。
// 协议适配：助手注入恒 system/head/0 固定配置（ChatPromptState.ASSISTANT_INJECT），本页仅
// 落库提示词文本——注入与协议方言适配（连续同角色 merge 守卫 / Gemini 末条 user 等）在既有
// 链路 ChatPromptState/RequestCompose，本页零改动（引用跟随：保存后引用会话下次发送生效）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_PROMPT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE, usageAccentColor } from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import {
  ASSISTANT_CONSOLE_ID, ASSISTANT_DEFAULT_ID, ASSISTANT_PROMPT_MAX, queryAssistant,
  updateAssistantPrompt
} from '../../common/store/AssistantDb';
import {
  appendVariableToken, PROMPT_VARIABLES, PromptVariableInfo
} from '../../common/providers/PromptVariables';

@Component
export struct AssistantPromptPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private content: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（驱动底部保存键条材质，SystemPromptPage 同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 编辑对象行 id（编辑页分区卡仅编辑态渲染才可进本页——无新建态，空参 = 异常路径弹回）
  private rowId: string = '';

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_PROMPT_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    // 读时联结：默认助手返回的 prompt = 系统提示词当前值（AssistantDb.syncDefaultPrompt）
    queryAssistant(param)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.content = row.prompt;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '提示词读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 内置助手只读判定（2026-09-05 控制台助手扩展：默认/控制台均整页只读——说明行与标题
  // 文案按助手区分，内容均经 queryAssistant 读时联结零缓存）
  private isReadonly(): boolean {
    return this.rowId === ASSISTANT_DEFAULT_ID || this.rowId === ASSISTANT_CONSOLE_ID;
  }

  // 只读分支说明行文案（默认 = 恒同步系统提示词去设置页管理；控制台 = 内置帮助指引）
  private readonlyHint(): string {
    if (this.rowId === ASSISTANT_CONSOLE_ID) {
      return '控制台助手的提示词是应用内置的帮助指引，发送时注入，只读不可修改。';
    }
    return '默认助手的提示词与「系统提示词」恒同步，发送时按系统提示词注入。修改请前往 设置 > 系统提示词。';
  }

  // 只读分支内容标题文案
  private readonlyTitle(): string {
    if (this.rowId === ASSISTANT_CONSOLE_ID) {
      return '提示词，内置指引，只读';
    }
    return '提示词，与系统提示词同步，只读';
  }

  // 保存（仅用户手建分支可达）：单列落库（0 行 throw 假成功防御在存储域）→ toast +
  // pop 带 result（编辑页 onPop 重拉摘要，坑17）
  private save(): void {
    const content: string = this.content.trim();
    updateAssistantPrompt(this.rowId, content)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 变量卡点按：追加 token 到内容末尾（appendVariableToken 单一来源——末尾空白不补空格，
  // SystemPromptPage 同函数）
  private insertVariable(info: PromptVariableInfo): void {
    this.content = appendVariableToken(this.content, info.token);
  }

  @Builder
  Content() {
    if (this.isReadonly()) {
      // ── 内置助手（默认/控制台）：只读展示（默认助手 = 反馈轮 3 领导指令原样迁移——提示词
      // 恒与系统提示词同步、本页禁改；控制台助手 = 2026-09-05 同口径只读，内容为内置帮助
      // 指引。仅说明行 + 内容展示框，取消输入/变量卡/保存；内容经读时联结，每次进页即拉
      // 零缓存）──
      Scroll() {
        Column({ space: 12 }) {
          Text(this.readonlyHint())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
          Column({ space: 6 }) {
            Text(this.readonlyTitle())
              .fontSize(SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
              .width('100%')
            Text(this.content !== '' ? this.content : '系统提示词当前为空，发送时不注入')
              .fontSize(15)
              .fontColor(this.content !== '' ? cardTitleColor() : cardDescColor())
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
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
    } else {
      // ── 用户手建助手：SystemPromptPage 同款形态（说明 + 内容 + 变量插入区 + 底部悬浮
      // 保存键条——Stack(alignContent Bottom)：滚动区全高 + 键条悬浮底部、条透明不挂
      // 材质（2026-09-02 决明反馈「无背后蒙层」：原 THIN 半透明条被误读为蒙层——光感由
      // 按钮自身 fallbackButtonMaterial 承担，背后内容透出；
      // 滚动内容底部 padding 让位条高 = 12 + 40 + bottomPad + 16，与键条两处同改）──
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: 12 }) {
            Text('会话提示词注入开启时优先使用注入模板。关闭时使用本助手的提示词，未设置则回退系统提示词。支持下方变量的发送前替换。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)

            Column({ space: 6 }) {
              Text('内容')
                .fontSize(SECTION_TITLE_FONTSIZE)
                .fontWeight(FontWeight.Bold)
                .fontColor(cardTitleColor())
                .width('100%')
              TextArea({ placeholder: '输入助手提示词，留空则使用系统提示词', text: this.content })
                .width('100%')
                .height(320)
                .maxLength(ASSISTANT_PROMPT_MAX)
                .onChange((value: string): void => {
                  this.content = value;
                })
            }
            .width(CARD_PANEL_WIDTH)
            .alignItems(HorizontalAlign.Start)

            // 变量插入区（SystemPromptPage 同款：3 列等宽 Button 卡——token 11fp/label
            // 10fp 用量统计主蓝（usageAccentColor——2026-09-07 决明「统一为用量统计页色值」，
            // 原淡蓝 variableLabelColor 退役；两页变量卡同源同版式，
            // 颜色须一致防跳变）；卡 = 官方胶囊按钮（2026-09-07 拍板不接光感；官方灰阶实色，
            // 四连真机依据见 SystemPromptPage 同款注释；「选项类 chips 无按压光感」豁免
            // 自本卡起不适用，其余 chips 照旧））
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
              .height('auto')
              .width('100%')
            }
            .width(CARD_PANEL_WIDTH)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          // 底部让位保存键条（条高 = 12 + 40 + bottomPad + 16——与键条两处同改）
          .padding({ top: this.topPad, bottom: this.bottomPad + 68 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        // 底部保存键条（吸底悬浮 + 半透明材质——SystemPromptPage/会话页输入栏同款；助手无
        // 内置默认提示词故无「恢复」键；条不设 backgroundColor（材质铁律））
        // 2026-09-02 光感化 + 2026-09-03 内容区回退双态：保存 = 主操作键（primary=true 官方
        // 强调蓝 + 恒白字，SystemPromptPage「保存」同构）；光感态 = resolvedButton* 原材质光感
        // （随沉浸光感总档，无光感档回退官方灰底）；实底态 = fallbackButton* 官方实底
        // （contentFallback 开关切换即刷，坑16）
        Column() {
          Row({ space: 12 }) {
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
        // ——按钮自身 fallbackButtonMaterial 已带光感（实底态空材质 + 官方实底），直接悬浮
        // 固定底部；条透明
        .padding({ top: 12, bottom: this.bottomPad + 16 })
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    PageShell({
      title: '提示词',
      // 右上角无菜单键（SystemPromptPage 同款口径——底部「保存」承担动作）
      content: (): void => {
        this.Content();
      }
    })
  }
}
