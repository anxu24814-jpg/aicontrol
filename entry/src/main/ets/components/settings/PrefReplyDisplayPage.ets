// 偏好设置二级页「回复显示」：一级偏好页第 2 行入口的承载页——三个语义板块（显示 / 渲染 /
// 代码），每板块 = 卡外 SectionHeader（无副标题，subtitle 空串时整行不渲染）+ 一张组卡，
// 标题与卡 SECTION_HEADER_GAP、板块间 SECTION_GAP（Theme 三档常量）。
// ★ 生效时机口径（字段注释只写差异）：多数渲染开关由消费方进页 / 渲染期现读一次，不做运行时
//   广播，拨动后「重进会话后生效」（帮助文案已写明边界）；即时生效或自订阅刷新的例外在各
//   字段注释单列。
// ★ 三板块各持纪元键（见三个 groupKey 注释；坑57 正解）：组卡 items 是普通成员不随父重渲，
//   恒单例 ForEach 以「键含本组开关值」键变重建，Toggle 才能拉新值。
// 页面骨架由 PageShell 提供；开关即时持久化（AppStorage persistProp 键），无保存动作 → 返回
// 走无参 pop、push 不挂 onPop。
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_ORANGE, SETTING_ICON_PURPLE } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { SECTION_GAP, SECTION_HEADER_GAP } from '../../common/Theme';
import { PREF_CODE_AUTO_COLLAPSE_KEY, PREF_CODE_LINE_NUMBERS_KEY, PREF_CHAT_LOADING_OVERLAY_KEY, PREF_HTML_BLOCK_RENDER_KEY, PREF_LONG_MSG_COLLAPSE_KEY, PREF_PREVIEW_JS_KEY, PREF_STREAM_FOLLOW_KEY, PREF_THINK_EXPAND_KEY, PREF_ASSISTANT_BUBBLE_KEY, PREF_THINKING_SLIDER_KEY } from '../../common/AppPreferences';
import { SETTING_TITLE_PREF_REPLY_DISPLAY, SETTING_TITLE_CHAT_LOADING_OVERLAY, SETTING_TITLE_CODE_AUTO_COLLAPSE, SETTING_TITLE_CODE_LINE_NUMBERS, SETTING_TITLE_HTML_BLOCK_RENDER, SETTING_TITLE_LONG_MSG_COLLAPSE, SETTING_TITLE_PREVIEW_JS, SETTING_TITLE_STREAM_FOLLOW, SETTING_TITLE_THINK_EXPAND, SETTING_TITLE_ASSISTANT_BUBBLE, SETTING_TITLE_THINKING_SLIDER } from '../../common/SettingSearch';
import { PageShell } from '../../common/PageShell';

// 板块头：只给标题，不写副标题（SectionHeader 的 subtitle 空串时整行不渲染）
const SECTION_DISPLAY: string = '显示';
const SECTION_RENDER: string = '渲染';
const SECTION_CODE: string = '代码';

@Component
export struct PrefReplyDisplayPage {
  // 默认展开思考（@StorageLink 即写即持久化；持久注册在 EntryAbility，先于本页任何实例）
  @StorageLink(PREF_THINK_EXPAND_KEY) thinkExpand: boolean = false;
  // 流式输出自动跟随：true = AI 输出时列表自动滚底 / false = 停在当前位置（需重新开启才恢复）；
  // ChatFollowController.maybeFollow 现读——即时生效，无广播需求
  @StorageLink(PREF_STREAM_FOLLOW_KEY) streamFollow: boolean = true;
  // 会话加载动画：true = 进入会话历史加载期间消息区显示淡蒙层与动画（默认）/ false = 纯背景；
  // 消费方 = ChatPageContent 加载分支订阅——切换后下次进入会话生效
  @StorageLink(PREF_CHAT_LOADING_OVERLAY_KEY) chatLoadingOverlay: boolean = true;
  // HTML 预览运行脚本：true = 受限预览可执行输入 HTML 的脚本（无桥、无网络、无文件权限）/
  // false = 剥脚本（缺省，安全优先）；消费方 = MarkdownPreviewCover.aboutToAppear 点开时读取
  //——预览是点开才建的新实例，天然即时
  @StorageLink(PREF_PREVIEW_JS_KEY) previewJs: boolean = false;
  // 长代码块自动收起：true = 生成结束的长代码块（超行数阈值）收起为前若干行 + 底部展开条 /
  // false = 保持展开（缺省）；消费方 = MarkdownScrollableBlock 终态评估处现读——已终态块评估
  // 一次不再重评
  @StorageLink(PREF_CODE_AUTO_COLLAPSE_KEY) codeAutoCollapse: boolean = false;
  // 代码块行号：true = Markdown 代码块、HTML <pre> 与工具卡 diff 块逐行显示行号（默认）/
  // false = 不显示；消费方 = MarkdownCodeText / MarkdownHtmlBlockView / ChatToolDiffBlock
  // 渲染期现读——已挂载块不即时增删行号
  @StorageLink(PREF_CODE_LINE_NUMBERS_KEY) codeLineNumbers: boolean = true;
  // 长消息进页收起：true = 进会话时把超阈值的超长消息（助手与用户同判）收起为一行提示
  //（缺省，进页快）/ false = 进页全部展开；已挂载消息不即时换形态
  @StorageLink(PREF_LONG_MSG_COLLAPSE_KEY) longMsgCollapse: boolean = true;
  // 显示助手消息气泡：true = 助手回复带气泡底色、圆角与内距（默认 = 开关引入前形态）/
  // false = 三者撤除、正文贴行沿（过程段与工具卡不跟、用户泡不跟）；消费方 = ChatPageContent
  // 进页读一次后下发 ChatMessageItem
  @StorageLink(PREF_ASSISTANT_BUBBLE_KEY) assistantBubble: boolean = true;
  // 思考档位滑轨（★ 2026-11-25 思考档位滑轨笔）：true = 标题栏「思考」热区点开滑轨面板
  //（默认）/ false = 旧菜单；消费方 = ChatTitleBarOverlay @StorageProp @Watch 订阅——拨动即
  // 生效，不用重进会话（与多数渲染开关「重进生效」不同，故单列）
  @StorageLink(PREF_THINKING_SLIDER_KEY) thinkingSlider: boolean = true;
  // 消息内 HTML 直接渲染：true = 消息中的 htmlBlock 走白名单结构投影 + 原生组件渲染（默认）/
  // false = 一律按源码文本显示；消费方 = MarkdownScrollableBlock 内容分支现读
  @StorageLink(PREF_HTML_BLOCK_RENDER_KEY) htmlBlockRender: boolean = true;
  // SVG 预览开关已退役（功能恒开，读值封装 isSvgPreviewEnabled 恒 true），勿回加
  // 顶部/底部留白（vp，导航壳下发；顶部 = 首卡落在标题栏渐变模糊蒙层下方——列表卡片法则）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;

  // 显示板块组卡（六行；行副标题 = 动词开头一句简介）。方法名沿用拆组前旧名，现只承载本板块。
  // ★ 同色笔：显示卡全紫 / 渲染卡全橙 / 代码卡全蓝
  private replyGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.lightbulb'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_THINK_EXPAND,
        secondary: '自动展开新思考块',
        toggleValue: (): boolean => this.thinkExpand,
        onToggle: (isOn: boolean): void => {
          this.thinkExpand = isOn;
        }
      },
      {
        icon: $r('sys.symbol.arrow_down_circle'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_STREAM_FOLLOW,
        secondary: '输出时自动滚到底部',
        toggleValue: (): boolean => this.streamFollow,
        onToggle: (isOn: boolean): void => {
          this.streamFollow = isOn;
        }
      },
      {
        icon: $r('sys.symbol.hourglass'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_CHAT_LOADING_OVERLAY,
        secondary: '进入会话时消息区显示加载动画',
        toggleValue: (): boolean => this.chatLoadingOverlay,
        onToggle: (isOn: boolean): void => {
          this.chatLoadingOverlay = isOn;
        }
      },
      {
        icon: $r('sys.symbol.message'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_LONG_MSG_COLLAPSE,
        secondary: '进入会话时收起超长消息',
        toggleValue: (): boolean => this.longMsgCollapse,
        onToggle: (isOn: boolean): void => {
          this.longMsgCollapse = isOn;
        }
      },
      {
        icon: $r('sys.symbol.message'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_ASSISTANT_BUBBLE,
        secondary: '关闭后回复贴边排列',
        toggleValue: (): boolean => this.assistantBubble,
        onToggle: (isOn: boolean): void => {
          this.assistantBubble = isOn;
        }
      },
      {
        icon: $r('sys.symbol.slider_horizontal_2_1'),
        iconBg: SETTING_ICON_PURPLE,
        label: SETTING_TITLE_THINKING_SLIDER,
        secondary: '滑轨选档，关闭改用菜单',
        toggleValue: (): boolean => this.thinkingSlider,
        onToggle: (isOn: boolean): void => {
          this.thinkingSlider = isOn;
        }
      }
    ];
  }

  // 显示板块重建键（键含本组开关值：任一开关变动即键变 → 组卡重建 → Toggle 拉新值——坑57）
  private replyGroupKey(): string {
    return [String(this.thinkExpand), String(this.streamFollow), String(this.chatLoadingOverlay),
      String(this.longMsgCollapse), String(this.assistantBubble),
      String(this.thinkingSlider)].join('|');
  }

  // 渲染板块组卡（消息内 HTML 直接渲染 / HTML 预览运行脚本；行序按渲染链路由浅入
  // 深，危险的脚本执行置末）。★ 方法名避开 ArkUI 内置属性 renderGroup（同名编译错 10505001）
  private renderItems(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.website'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_HTML_BLOCK_RENDER,
        secondary: '直接渲染消息里的 HTML 块',
        toggleValue: (): boolean => this.htmlBlockRender,
        onToggle: (isOn: boolean): void => {
          this.htmlBlockRender = isOn;
        }
      },
      {
        icon: $r('sys.symbol.code_slash'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_PREVIEW_JS,
        secondary: '运行预览中的 HTML 脚本',
        toggleValue: (): boolean => this.previewJs,
        onToggle: (isOn: boolean): void => {
          this.previewJs = isOn;
        }
      }
    ];
  }

  // 渲染板块重建键（键含本组开关值，坑57）
  private renderItemsKey(): string {
    return [String(this.htmlBlockRender), String(this.previewJs)].join('|');
  }

  // ── 代码板块组卡（代码块行号 / 长代码块自动收起）──
  private codeGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.list_number'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_CODE_LINE_NUMBERS,
        secondary: '在代码块中显示行号',
        toggleValue: (): boolean => this.codeLineNumbers,
        onToggle: (isOn: boolean): void => {
          this.codeLineNumbers = isOn;
        }
      },
      {
        icon: $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
        iconBg: SETTING_ICON_BLUE,
        label: SETTING_TITLE_CODE_AUTO_COLLAPSE,
        secondary: '生成结束的长代码块自动收起',
        toggleValue: (): boolean => this.codeAutoCollapse,
        onToggle: (isOn: boolean): void => {
          this.codeAutoCollapse = isOn;
        }
      }
    ];
  }

  // 代码板块重建键（键含本组开关值，坑57）
  private codeGroupKey(): string {
    return [String(this.codeLineNumbers), String(this.codeAutoCollapse)].join('|');
  }

  build() {
    // 页面骨架统一由 PageShell 提供；标题 = 行名常量（与一级页入口行共用单一来源）
    PageShell({
      title: SETTING_TITLE_PREF_REPLY_DISPLAY,
      content: () => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: SECTION_GAP }) {
        // ── 板块1 显示 ──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_DISPLAY })
          // 开关组卡（恒单例纪元键 ForEach：键变重建刷开关，见 replyGroupKey 注释）
          ForEach([this.replyGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.replyGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
        }
        .width('100%')
        // ── 板块2 渲染（HTML / 预览脚本）──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_RENDER })
          // 开关组卡（恒单例纪元键 ForEach：键变重建刷开关，见 renderItemsKey 注释）
          ForEach([this.renderItemsKey()], (_key: string) => {
            GroupSettingCard({ items: this.renderItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
        }
        .width('100%')
        // ── 板块3 代码（行号 / 自动收起）──
        Column({ space: SECTION_HEADER_GAP }) {
          SectionHeader({ title: SECTION_CODE })
          // 开关组卡（恒单例纪元键 ForEach：键变重建刷开关，见 codeGroupKey 注释）
          ForEach([this.codeGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.codeGroup(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
        }
        .width('100%')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }
}
