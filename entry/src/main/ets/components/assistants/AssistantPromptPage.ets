// 助手提示词二级页：编辑页「提示词」行 push，param = 助手 id。文字层级同 SystemPromptPage
// 定稿口径（提示性文本灰 cardDescColor / 卡内标题 16fp Medium 主色——2026-11-01 板块标题改档
// 笔随卡内小节标题档归一）。
// · 用户手建助手 = SystemPromptPage 同款形态（领导口径「参考已有系统提示词页」）：说明行 +
//   内容多行（320vp，★ 留空 = 回退系统提示词注入）+ 变量插入区（居内容框之下；「点击插入
//   变量」小标题 + 数据源 = PromptVariables PROMPT_VARIABLES 单源——改变量两页自动同步；
//   卡 = 内容区官方胶囊按钮，拍板不接光感——官方灰阶实色 + 原生按压）+ 底部悬浮「保存」
//   键条（半透明材质随沉浸光感总档；助手无内置默认提示词 → 无「恢复」键，单键）。保存 =
//   updateAssistantPrompt 单列落库 → toast + pop 带 result（坑17——编辑页 onPop 重拉提示词
//   摘要行）；不保存退出 = 草稿自然丢弃（与服务商编辑页统一保存语义同口径）。
// · 内置默认助手（定稿逻辑自原 AssistantEditPage 只读分支**原样迁移，语义不改**）：整页
//   只读——说明行（指引 设置 > 系统提示词）+ 内容展示框（Text 非输入态，内容经
//   queryAssistant 读时联结 = 系统提示词当前值，每次进页即拉零缓存）；取消输入/变量卡/
//   保存（默认卡分支不渲染）；只读页无保存动作 = 返回无参 pop 不触发 onPop（预期语义）。
// 协议适配：助手注入恒 system/head/0 固定配置（ChatPromptState.ASSISTANT_INJECT），本页仅
// 落库提示词文本——注入与协议方言适配（连续同角色 merge 守卫 / Gemini 末条 user 等）在既有
// 链路 ChatPromptState/RequestCompose，本页零改动（保存后引用会话下次发送生效）。
// ★ 表单重构批 6：变量插入区自独立板块收进内容卡底栏（共用件 PromptVariableStrip，胶囊
// 单行横滑、底色取卡面灰）；内容块改实色卡片并加字数计数。**变量集、只追加语义与保存链
// 零改**，纯 UI 重排。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_PROMPT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardDescColor, cardTitleColor, CARD_SECTION_TITLE_FONTSIZE, CARD_RADIUS } from '../../common/Theme';
import { bindKeyboardAvoidArea, KEYBOARD_CARD_TAIL, KeyboardCardScroller } from '../../common/KeyboardCardScroll';
import { InfoCard } from '../InfoCard';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import {
  ASSISTANT_DEFAULT_ID, ASSISTANT_PROMPT_MAX, queryAssistant,
  updateAssistantPrompt
} from '../../common/store/AssistantDb';
import {
  appendVariableToken, hasVolatileTimeTokens,
  PromptVariableInfo, PROMPT_VOLATILE_TIME_HINT
} from '../../common/providers/PromptVariables';
import { InfoHintButton } from '../InfoHintButton';
import { PromptVariableStrip } from '../PromptVariableStrip';

@Component
export struct AssistantPromptPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private content: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（驱动底部保存键条材质，SystemPromptPage 同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = 本键官方实底（新规范下内容区材质不生效）；false = 原材质光感；
  // AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 编辑对象行 id（编辑页分区卡仅编辑态渲染才可进本页——无新建态，空参 = 异常路径弹回）
  private rowId: string = '';
  // 编辑态：驱动编辑器压短（聚焦时 320 → 160）——键盘弹起后整张内容卡（含卡内变量条）
  // 才能收进键盘上沿之上（2026-11-05 键盘遮挡笔）
  @State private editing: boolean = false;
  // 页面滚动器 + 卡底定位器（2026-11-05 两千一百零二）：聚焦后按实测位置把内容卡底边——
  // 含卡底变量条的说明行——滚到吸底键条上沿之上（算式与时序单源 = KeyboardCardScroll）
  private pageScroller: Scroller = new Scroller();
  // 底部让位 = 吸底保存键条高（条上内距 12 + 按钮 40 + 条下内距 bottomPad+16）
  private cardScroll: KeyboardCardScroller = new KeyboardCardScroller(this.pageScroller);

  aboutToAppear(): void {
    // 键盘上沿缓读绑定（进程内单次；卡底定位要它兜住「页面底边略低于键盘上沿」那一档）
    bindKeyboardAvoidArea(this.getUIContext());
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
        if (this.departed) {
          return;
        }
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.content = row.prompt;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '提示词读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 内置助手只读判定（内置默认助手整页只读——说明行与标题文案按助手区分，内容经
  // queryAssistant 读时联结零缓存）
  private isReadonly(): boolean {
    return this.rowId === ASSISTANT_DEFAULT_ID;
  }

  // 只读分支说明行文案（默认 = 恒同步系统提示词去设置页管理）
  private readonlyHint(): string {
    return '默认助手的提示词与「系统提示词」恒同步，发送时按系统提示词注入。修改请前往 设置 > 系统提示词。';
  }

  // 只读分支内容标题文案
  private readonlyTitle(): string {
    return '提示词，与系统提示词同步，只读';
  }

  // 保存（仅用户手建分支可达）：单列落库（0 行 throw 假成功防御在存储域）→ toast +
  // pop 带 result（编辑页 onPop 重拉摘要，坑17）
  private save(): void {
    const content: string = this.content.trim();
    updateAssistantPrompt(this.rowId, content)
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

  // 变量卡点按：追加 token 到内容末尾（本页未跟光标位插入，仍只追加；
  // SystemPromptPage/PromptEditPage 有光标时走 insertVariableToken，无光标回退同一函数）
  private insertVariable(info: PromptVariableInfo): void {
    this.content = appendVariableToken(this.content, info.token);
  }

  // 聚焦定位交给 KeyboardCardScroller（卡底实测位置 → 滚到吸底键条上沿之上，2026-11-05
  // 两千一百零二）；不再 scrollEdge 滚到底——本页卡是滚动内容最后一块，滚到底只能让卡底
  // 齐平键条上沿，变量条的说明行仍会被键条压住

  @Builder
  Content() {
    if (this.isReadonly()) {
      // ── 内置助手只读展示：仅说明行 + 内容展示框，取消输入/变量卡/保存；内容经读时
      // 联结，每次进页即拉零缓存 ──
      Scroll() {
        // 块间 SECTION_GAP（Theme 三档常量）
        Column({ space: SECTION_GAP }) {
          // InfoCard 单源件（文案 = readonlyHint() 动态按助手分派）
          InfoCard({ text: this.readonlyHint() })
          Column({ space: SECTION_HEADER_GAP }) {
            Text(this.readonlyTitle())
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
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
          .borderRadius(CARD_RADIUS)
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
      .scrollBar(BarState.Off)
    } else {
      // ── 用户手建助手：SystemPromptPage 同款形态（说明 + 内容 + 变量插入区 + 底部悬浮
      // 保存键条——Stack(alignContent Bottom)：滚动区全高 + 键条悬浮底部、条透明不挂材质
      //（决明反馈「无背后蒙层」——光感由按钮自身承担；滚动内容底部 padding 让位条高，
      // 与键条两处同改）──
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.pageScroller) {
          // 板块间 SECTION_GAP（Theme 三档常量）
          Column({ space: SECTION_GAP }) {
            Text('会话提示词注入开启时优先使用注入模板。关闭时使用本助手的提示词，未设置则回退系统提示词。支持下方变量的发送前替换。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)

            // ── 内容卡（编辑器 + 变量插入底栏）──
            Column({ space: 12 }) {
              // 标题行 + 计数 + volatile 时间变量气泡（内容含
              // {{time}}/{{datetime}} 时条件出现——分钟粒度变量每轮替换会打断提示词缓存，
              // 说明文案单源 PromptVariables.PROMPT_VOLATILE_TIME_HINT）
              Row({ space: 8 }) {
                Text('内容')
                  .fontSize(CARD_SECTION_TITLE_FONTSIZE)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .layoutWeight(1)
                if (hasVolatileTimeTokens(this.content)) {
                  InfoHintButton({ text: PROMPT_VOLATILE_TIME_HINT })
                }
                Text(this.content.length + ' / ' + ASSISTANT_PROMPT_MAX)
                  .fontSize(13)
                  .fontColor(cardDescColor())
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              TextArea({ placeholder: '输入助手提示词，留空则使用系统提示词', text: this.content })
                .width('100%')
                // 内容框高度两档（2026-11-05 键盘遮挡笔）：静止 320 保持原形态；编辑态压到
                // 160，键盘占屏后整张内容卡（含卡内变量条）才收得进键盘上沿之上
                .height(this.editing ? 160 : 320)
                .maxLength(ASSISTANT_PROMPT_MAX)
                .onChange((value: string): void => {
                  this.content = value;
                })
                // 压短编辑框 + 卡底定位随编辑态起停（底部让位 = 吸底保存键条高；2026-11-05）
                .onEditChange((isEditing: boolean): void => {
                  this.editing = isEditing;
                  // 键盘避让切官方 RESIZE（聊天页输入栏同款处方）：RESIZE_WITH_CARET 下页面
                  // 高度不压缩，键盘盖住页面——吸底保存键与卡底都停在原位被遮（2026-11-05）
                  this.getUIContext().setKeyboardAvoidMode(isEditing ?
                    KeyboardAvoidMode.RESIZE : KeyboardAvoidMode.RESIZE_WITH_CARET);
                  this.cardScroll.setEditing(isEditing, this.bottomPad + 68);
                })
              // 变量插入条（原独立变量区收进编辑器底栏；三页共用 PromptVariableStrip。
              // 本页未跟光标位插入仍只追加——行为不变，见 insertVariable 注释）
              PromptVariableStrip({
                label: '点击插入变量',
                hint: '发送前替换为实际值。点按将变量追加到内容末尾',
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
          // 底部让位保存键条（条高 = 12 + 40 + bottomPad + 16——与键条两处同改）；编辑态再补
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

        // 底部保存键条（吸底悬浮；助手无内置默认提示词故无「恢复」键；条不设
        // backgroundColor——材质铁律）。保存 = 主操作键（primary=true 官方强调蓝 + 恒白字）；
        // 内容区回退双态：光感态原材质随沉浸光感总档，实底态 fallbackButton* 官方实底
        //（contentFallback 切换即刷，坑16）
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
        // 决明反馈「无背后蒙层」：按钮条不挂材质，直接悬浮固定底部；条透明
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

  aboutToDisappear(): void {
    this.departed = true;
    // 卡底定位器成对释放：页面退出后迟到回调不得再碰 Scroller
    this.cardScroll.dispose();
    // 键盘避让模式兜底恢复：聚焦中被返回时窗口级模式会留在 RESIZE，与 onEditChange 成对复原
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
  }
}
