// 提示词编辑页：管理页 push，param = 模板 id（'' = 新增 / 其他 = 编辑，两形态）；标题恒
// 「编辑提示词」。名称 + 内容两输入 + 标题栏保存键（加载完成闸 → 校验非空 → insert/update →
// toast + pop，失败显式提示）；保存走 updateTemplate，引用跟随即时生效。
// · 查不到行 = 退栈回库页（原「按新增处理」只提示不改 editId，保存必抛 0 行错、承诺与行为
//   相反）；读失败不置加载闸 → 保存首拦（未加载完的空壳表单落库会覆盖既有行）。
// · 注入配置（PromptInjectConfig）随行落库；脏值钳位（system 强制 head、assistant 深度 ≠ 0、
//   depth 0~4），任何来源的脏值都不入库。系统提示词已独立页，不经本页。
// · 文本层级：卡内标题 16fp Medium 主色（cardTitleColor——2026-11-01 板块标题改档笔随卡内
//   小节标题档归一），说明性文本灰（cardDescColor）。
// · 变量插入：PromptVariableStrip 收在内容卡底栏（三页共用），变量集与替换逻辑零改；有光标
//   按光标索引插入并回位，无光标追加末尾（AssistantPromptPage 未跟，只追加）。
// · 2026-10-25 表单重构：名称 / 内容 / 注入方式三个裸板块改实色卡片，变量集与插入语义零改。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PROMPT_EDIT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_SECTION_TITLE_FONTSIZE, CARD_RADIUS } from '../../common/Theme';
import { bindKeyboardAvoidArea, KeyboardCardScroller } from '../../common/KeyboardCardScroll';
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
import {
  appendVariableToken, hasVolatileTimeTokens, insertVariableToken,
  PromptInsertResult, PromptVariableInfo, PROMPT_VOLATILE_TIME_HINT
} from '../../common/providers/PromptVariables';
import { InfoHintButton } from '../InfoHintButton';
import { InfoCard } from '../InfoCard';
import { PromptVariableStrip } from '../PromptVariableStrip';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';

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

// 注入配置脏值钳位（共享在 PromptInjectConfig.ets；页面侧另有带身份联动的三值双保险）

@Component
export struct PromptEditPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新增；其他 = 模板 id）——构造后不变（坑30）；系统提示词已独立页
  editId: string = '';
  @State private name: string = '';
  @State private content: string = '';
  // 注入配置（钳位值默认 system+head+0 = 现状行为；回填/保存链自带钳位）
  @State private injectRole: string = INJECT_ROLE_SYSTEM;
  @State private injectPosition: string = INJECT_POSITION_HEAD;
  @State private injectDepth: number = 0;
  // 加载完成闸（O-13）：加载未完成（含读失败 catch）时表单是空初值，落库会覆盖真实行；
  // 未置真即保存被首拦（形制照 BalanceConfigPage 的 loaded 闸）。新建态无待读行显式置真
  @State private loaded: boolean = false;
  // 变量插入光标位：普通成员不进 @State（不驱动 UI）；controller 是官方光标 API 载体
  private contentCtrl: TextAreaController = new TextAreaController();
  private caretIndex: number = -1;
  // 编辑态：驱动编辑器压短（见 Content 里的两档高度）——有了它，键盘弹起时整张内容卡
  // （含卡内变量条与说明行）才收得进键盘上沿之上
  @State private editing: boolean = false;
  private caretTimer: number = -1;
  // 页面滚动器 + 卡底定位器（2026-11-05 两千一百零二）：聚焦后按实测位置把内容卡底边——
  // 含卡底变量条的说明行——滚到键盘上沿之上（算式与时序单源 = KeyboardCardScroll）
  private pageScroller: Scroller = new Scroller();
  // 本页无视口底部键条，底部让位传 0
  private cardScroll: KeyboardCardScroller = new KeyboardCardScroller(this.pageScroller);
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // 键盘上沿缓读绑定（进程内单次；卡底定位要它兜住「页面底边略低于键盘上沿」那一档）
    bindKeyboardAvoidArea(this.getUIContext());
    // param 解析（照 ProviderDetailPage 守卫：null/非串一律 '' = 新增）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_PROMPT_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const pid: string = typeof last === 'string' ? last : '';
    this.editId = pid;
    if (pid !== '') {
      // 编辑态：回填名称/内容/注入配置（系统提示词行同此；查不到 = 退栈回库页，
      // 不能按新增处理——保存必抛 0 行错）
      queryTemplate(pid)
        .then((row): void => {
          if (this.departed) {
            return;
          }
          if (row === null) {
            this.getUIContext().getPromptAction().showToast({ message: '提示词不存在或已删除' });
            this.pathStack.pop();
            return;
          }
          this.name = row.name;
          this.content = row.content;
          // 整体换文：旧光标索引作废（用户若在回填前已点入内容框，索引对应的是旧文本）
          this.caretIndex = -1;
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
          if (this.departed) {
            return;
          }
          // 读取失败：不置加载闸（保持未完成）→ 保存被首拦，封死空壳覆盖既有行（见成员位注释）
          this.getUIContext().getPromptAction().showToast({ message: '模板读取失败：' + (e as Error).message });
        });
    } else {
      this.loaded = true;
    }
  }

  // 注入配置脏值钳位（默认 = 现状行为；位置 depth 时深度 0~4；身份 system 时位置强制 head
  // ——与 UI 联动一致，任何来源脏值都不入库；基础钳位在 PromptInjectConfig，页面侧补联动）
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
    // 加载完成闸（未加载完 = 空初值，落库即覆盖既有行；O-13）
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
      // ★ pop 必须带 result——官方 onPop 仅在 pop 带 result 时触发；无参 pop() 不触发库页
      // reload，保存后回列表不刷新（ProviderDetailPage.pop({ saved: true }) 同款先例）
      this.pathStack.pop({ saved: true });
    };
    if (this.editId === '') {
      insertTemplate(name, content, role, position, depth)
        .then((): void => {
          done();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    } else {
      updateTemplate(this.editId, name, content, role, position, depth)
        .then((): void => {
          done();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  // 变量卡点按：有光标按索引插入并回位；无光标走 appendVariableToken 追加末尾（同 AssistantPromptPage）
  private insertVariable(info: PromptVariableInfo): void {
    // 闸只认最后一次光标位（caretIndex），不再要求「当前仍在编辑」：点胶囊或点页面空白都可能
    // 让编辑器失焦，若以 editing 为闸，失焦后的点按会静默退化成「追加末尾」，与「点按插入到
    // 光标处」的承诺相反（2026-11-05 浮条笔；caretIndex 失焦后仍有效）
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
      // 失焦态 caretPosition 不生效（无编辑会话），只在仍处于编辑态时回位；插入位置由
      // 上方 caretIndex 记账承接，连点下一枚变量仍接在本 token 之后（2026-11-05 浮条笔）
      if (this.editing) {
        this.contentCtrl.caretPosition(caret);
      }
    }, 0);
  }

  // 聚焦定位交给 KeyboardCardScroller（卡底实测位置 → 滚到键盘上沿之上，2026-11-05
  // 两千一百零二）；不再 scrollEdge 滚到底——滚到底只保证内容末尾贴底，卡下面还有注入方式卡
  // 与提示卡，会把这整张内容卡推过头

  @Builder
  CardTitleRow(title: string) {
    Text(title)
      .fontSize(CARD_SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardTitleColor())
      .width('100%')
  }

  // 页面内容（三个实色卡片——基本信息 / 内容 / 注入方式；变量插入条在内容卡底栏）
  // 键盘遮挡处置（2026-11-05）：编辑态把编辑框压短，并按卡底实测位置滚到位——整张卡底边
  // 落在键盘上沿之上 8vp，卡内变量胶囊与说明行一并露出。变量条始终与内容同卡，不另起浮层
  // （首版浮条被决明否决：拆成两张卡且挤内容）
  @Builder
  Content() {
    Scroll(this.pageScroller) {
      Column({ space: CARD_SPACING }) {
        // ── 基本信息卡（名称）──
        Column({ space: 12 }) {
          this.CardTitleRow('基本信息')
          Column({ space: 6 }) {
            Row() {
              Text('名称')
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              Text('必填')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            TextInput({ placeholder: '例如 翻译助理、代码专家', text: this.name })
              .width('100%')
              .maxLength(TEMPLATE_NAME_MAX)
              .onChange((value: string): void => {
                this.name = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

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
            placeholder: '输入人设或指令，留空则不注入',
            text: this.content,
            controller: this.contentCtrl
          })
            .width('100%')
            // 编辑态压短（220 → 120）：键盘占屏后整张内容卡（含卡内变量条）要能收进
            // 键盘上沿之上；120 ≈ 五行，够放光标与就近上下文（2026-11-05 键盘遮挡笔）
            .height(this.editing ? 120 : 220)
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
              // 键盘避让切官方 RESIZE（聊天页输入栏同款处方）：本页在 RESIZE_WITH_CARET 下页面
              // 高度不压缩，键盘只是盖在页面上——保存键与卡底都停在原位被遮（2026-11-05
              // 两千一百零四真机第 2 次实锤：视口高仍 813vp = 全高）。切 RESIZE 后页面压到
              // 键盘上沿，卡底定位与吸底键条才有一致的参照面
              this.getUIContext().setKeyboardAvoidMode(isEditing ?
                KeyboardAvoidMode.RESIZE : KeyboardAvoidMode.RESIZE_WITH_CARET);
              // 压短编辑框 + 卡底定位随编辑态起停（2026-11-05 两千一百零二）
              this.cardScroll.setEditing(isEditing, 0);
            })
          // 变量插入条（原独立变量板块收进编辑器底栏；三页共用件，光标位插入规则不变）
          PromptVariableStrip({
            label: '插入变量',
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

        // ── 注入方式卡（身份 / 位置 / 深度三行常显）──
        // ★ 三值 $ 引用下发（原 @Prop 值传在 PageShell.content 内为坑16 家族首帧快照，
        // queryTemplate 异步回填不达 UI——@Link 双向链后回填赋 @State 即达）
        Column({ space: 12 }) {
          this.CardTitleRow('注入方式')
          PromptInjectConfig({
            role: $injectRole,
            injectPosition: $injectPosition,
            depth: $injectDepth,
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
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // 页面级说明（T1 条状提示件已否决，走 InfoCard 单源件）
        InfoCard({ text: '提示词将在每条消息发送时注入请求。会话选中本模板后，后续修改将即时跟随。' })
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
    // 视口实测上报（键盘压缩页面后视口高变化即触发卡底定位；2026-11-05 两千一百零二）
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.cardScroll.onViewportArea(newArea);
    })
  }

  build() {
    PageShell({
      title: '编辑提示词',
      menuHds: promptSaveMenuHds((): void => {
        this.save();
      }),
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
