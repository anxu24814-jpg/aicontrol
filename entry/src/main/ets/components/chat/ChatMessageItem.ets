// 聊天气泡渲染（2026-08-29 任务书 M1 自 dshinhm 同名文件随迁改造——原 401 行贴 400
// 红线，本次为「只删不加」式精简，宪法例外条款）：剥离 KimiMediaApi 依赖与附件媒体
// 渲染（aboutToAppear 进入即下载 / mediaStripIds / MediaThumb 缩略图 / 点击预览上行
// ——附件整体后置 M4），其余分支原样保留。
// 按 ChatMessage.kind 分发五种形态——user 右侧气泡 / assistant 左侧卡片色气泡 /
// thinking 思考折叠块 / tool 工具调用卡（★ 2026-09-20 审批卡视觉迁移笔 A：工具卡域级拆分，
// 卡面本体迁 ChatToolCard.ets，本文件 tool 分支只余一行实例化）/ notice 居中提示条。
// user/assistant 两分支 = @lidary/markdown 的 Markdown 组件 + 流式公式守卫（ChatLatexGuard）；
// 气泡行边距（常量 BUBBLE_PAD_*——dshinhm 二三三改真机定稿值随迁）：用户侧镜像（右近 4 /
// 左远 20）；★ 2026-09-16 决明「助手的右边距缩短与左边距统一」后助手侧三件（消息泡 /
// 思考块 / 工具卡）两侧同取近侧 4/4，用户泡宽度上限另收 78%（BUBBLE_USER_MAX_WIDTH，
// 2026-09-16 立 60% → 2026-09-18 增宽 30%，挂点由 constraintSize 改外层定宽壳）。
// ★ 2026-09-01 反碎片并回：ChatThinkingBlock.ets（思考折叠块，本文件单消费方、同域
// 「消息气泡分支渲染」）并入——原拆分动因 = 本文件当年 390 行逼近 400 旧红线，宪法修订
//（600 软引导 / 1000 硬线 + 反碎片下限）后按「并入既有同域文件优先」复归。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Markdown } from '@lidary/markdown';
import { BUBBLE_RADIUS, cardBg, cardBorderColor, cardDescColor, cardTitleColor, ATTACH_BUBBLE_GAP,
  CARD_SPACING, BUBBLE_PAD_FAR, BUBBLE_PAD_NEAR, BUBBLE_USER_MAX_WIDTH } from '../../common/Theme';
import { hideAttachAnnotate } from '../../common/AttachmentUtil';
import { getThinkExpandDefault, isCubeEngineEnabled } from '../../common/AppPreferences';
import { tokenShort } from '../../common/TokenEstimate';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { guardStreamingLatex, guardStreamingLatexLive } from './ChatLatexGuard';
import { AttachmentBubble } from './AttachmentBubble';
import { ChatMessage } from './ChatMessageCompose';
import { ChatToolCard } from './ChatToolCard';
import { ChatSuggestBar } from './ChatSuggestBar';
import { MESSAGE_MENU_ANCHOR_PREFIX } from './ChatMoreMenu';
import { CubeMarkdownView } from './cube/CubeMarkdownView';

// 库内层 List 与消息流 List 的嵌套滚动策略（README 先例组合：下滚父优先、回滚自身优先）。
// 坑72：nestedScroll 参数类型是 union（NestedScrollOptions | undefined），union 上下文禁
// 对象字面量——先落精确类型常量再传入。
const MD_NESTED_SCROLL: NestedScrollOptions = {
  scrollForward: NestedScrollMode.PARENT_FIRST,
  scrollBackward: NestedScrollMode.SELF_FIRST
};

// 思考半泡内「思考区 ↔ 正文区」分割线的上方留白（vp，观感参数可单点调）
const THINK_DIVIDER_GAP: number = 8;

// 气泡行内边距（dshinhm 二三三改定稿值；★ 2026-09-15 预览笔上收 Theme.ets——附件独立
// 气泡（AttachmentBubble）与消息泡两件同源消费，本文件改 import。★ 常量**值**已随
// 2026-09-16 气泡横向几何笔按角色分叉——现行口径见 Theme.ets 常量注释与本文件三处落点）
// 用户气泡蓝：自定义色板资源 chat_bubble_user（base/dark 限定词随迁——浅色 #A9C7FA /
// 深色 #3A5A94，dshinhm 真机定稿值）
@Component
export struct ChatMessageItem {
  // @ObjectLink 对象级观察：流式增量由页面侧原地改 ChatMessage 字段（键恒定不重建列表项），
  // @Observed set 触发本组件刷新
  @ObjectLink msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ask_user 答案上行（ChatPage 构造处注入 → ChatToolCard → ChatAskUserCard；默认空实现防漏接）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {};
  // browse_act 高危确认上行（2026-09-18 P2·B 单元；ChatPage 构造处注入 →
  // ChatSendCtrl.resolveBrowseConfirm → ToolRuntime.resolveBrowseConfirm；同 onAskSubmit 契约）
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  // ── 消息气泡底栏（2026-09-14 任务书；回调一律上行——照 onAskSubmit 契约，本组件零业务）──
  // 重试键点击上行（msgId；ChatPage 委托 ChatSendCtrl.retryLast 就地替换重答——多版本保留）
  onRetryMsg: (msgId: string) => void = () => {
  };
  // 版本切换键点击上行（2026-09-20 消息重新生成·多版本；msgId + 目标版下标——本组件按
  // variantActive ±1 算好目标传入，ChatPage 校验越界与落库换版；照 onRetryMsg 同契约）
  onVariantSwitch: (msgId: string, target: number) => void = () => {
  };
  // 「更多」键点击上行（msgId；ChatPage 经 ChatMessageMenuHost 按锚点弹出消息菜单）
  onMoreMenu: (msgId: string) => void = () => {
  };
  // 长按气泡上行（msgId；ChatPageContent 根 Stack 宿主开「消息全文」半模态面板——
  // ★ 2026-09-18 消息复制优化笔：复制入口自底栏复制键迁长按面板，原键与渲染器逐段
  // 长按复制一并退役〔面板内跨段落自由选择——逐段渲染组件的选择困局根治处〕）
  onCopyText: (msgId: string) => void = () => {
  };
  // 附件泡点击派发上行（2026-09-15 预览第三轮；msgId + briefId → ChatPageContent 分派：
  // 图片/文本进应用内查看器、文档走系统预览——与 onAskSubmit 同契约，本组件零业务）
  onPreviewAttach: (msgId: string, briefId: string) => void = (msgId: string,
    briefId: string): void => {
  };
  // 隐私会话（构造注入后不变——isPrivate 页级恒定，坑30 口径，普通成员即够无坑16 风险）：
  // true = 底栏整栏不显示（任务书 §2.1-④ 零留痕口径——剪贴板与菜单入口同属留痕面）
  privateSession: boolean = false;
  // 推荐问题 chip 点击上行（2026-09-19 推荐问题功能；text → ChatPageContent 复用 onSend
  // 直接发送——决策 2，不填充输入框；上行链 ChatSuggestBar → 本组件 → ChatPageContent，
  // 照 onRetryMsg 同契约，本组件零业务）
  onSuggestSend: (text: string) => void = () => {
  };
  // 摘要提示行整行点击上行（2026-09-23 上下文压缩；kind='summary' 专用——打开「上下文用量」
  // 面板看摘要详情与删除键；照 onRetryMsg 同契约，本组件零业务，ChatPage 构造处注入）
  onOpenUsage: () => void = () => {
  };
  // 用量键气泡开关（bindPopup 受控 show，照 InfoHintButton 复位语义）
  @State private usagePopupShow: boolean = false;

  // 底栏显隐总判据（任务书 §2.1-④）：助手消息且非流式中；隐私会话整栏不显示。
  // streaming 挂在 @Observed 字段上，流式收口（finishStream / settleRoundAssistant）
  // 置假即刷新出栏；回放历史行两字段 undefined 同判「已结束」
  private barVisible(): boolean {
    return this.msg.kind === 'assistant' && this.msg.streaming !== true && !this.privateSession;
  }

  // 推荐问题 chips 显隐总判据（2026-09-19 推荐问题功能，任务书 §5.1「全与才显示」）：
  // 末条助手消息（tail）且非流式中（streaming）且建议非空且非隐私会话。
  // ★ 「非 busy」由 tail + streaming 联合承载，不透传页级 busy（状态最小化 + 免 @Prop
  // 级联）：新轮发送 push 首条消息即清全部 tail（ChatDataSource.push），流式占位自身
  // streaming=true——busy 窗口内本判据恒 false，两道保险的第一道即结构保证
  private suggestVisible(): boolean {
    return this.msg.tail === true && this.msg.streaming !== true && !this.privateSession &&
      (this.msg.suggestions ?? []).length > 0;
  }

  // 用户消息显示正文（2026-09-15 预览第三轮，拍板 5「显示层隐去」）：有附件简报且尾部标注
  // 逐字吻合 → 剥掉标注段（附件泡已呈现名单，不再重复）；无简报（导入恢复/老数据）→
  // 原样显示标注作回退。**只改显示层**——复制键与协议文本仍用库内全文（msg.text）
  private displayBodyText(): string {
    const briefs = this.msg.attachBriefs;
    if (briefs === undefined || briefs.length === 0) {
      return this.msg.text;
    }
    const names: string[] = briefs.map((b): string => b.name);
    return hideAttachAnnotate(this.msg.text, names);
  }

  // ── 用量键气泡数据（2026-09-14 消息底栏：原气泡外 meta 文字行整体退役，文案迁入气泡；
  // ★ 2026-09-15 决明改版〔照其供图形态〕：竖排行 —— 标题行「Token 用量」+ 分割线 +
  // 标签左·数值右六行，缓存由括号内缀改独立行、速度殿后。计算口径沿用 2026-09-06 拍板
  // ——输入 = 当轮请求计费输入〔prompt 含全部历史上下文，连续对话中后轮大于前轮是正常计费
  // 口径〕；输出 = 本条回复自身 token；总计 = 输入 + 输出〔= 协议 total 原值〕；缓存 = 输入
  // 里的命中部分〔真子集，故列在输入之后，总计不重复计它〕；token 数 ≥1000 缩 k 一位小数
  //〔tokenShort 单点〕；tok/s = 输出 token ÷ 纯流式秒〔口径③〕；用时 <60s 一位小数否则
  // 整数秒。术语与设置页「用量统计」同名同义（任务书 §2.7：输入/输出；速度与用时是统计页
  // 没有的维度，措辞写全不裸缩写）。★ 2026-09-23 首字耗时笔：七行（原六行 + 「首字耗时」），
  // 末三行按发生序排 = 首字耗时 → 用时 → 生成速度；首字行 >0 才挂（老账本行/无产出轮无），
  // 常开测量不随请求日志开关——两枚指标的分野见 ChatUsageRoundCtrl 域头注释 ──
  private usagePromptCount(): number {
    const total: number = this.msg.usageTokens ?? 0;
    const completion: number = this.msg.usageCompletionTokens ?? 0;
    // 输入 = 整轮总量 − 输出；负值防御归零（仅防脏数据）
    return total - completion > 0 ? total - completion : 0;
  }

  // 用时数值串（标签在行首，本函数只出数值与单位）
  private usageDurationValue(): string {
    const seconds: number = (this.msg.usageDurationMs ?? 0) / 1000;
    return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
  }

  // 生成速度数值串（tok/s；单位跟数字不裸缩写——任务书 §2.7-1）
  private usageSpeedValue(): string {
    const completion: number = this.msg.usageCompletionTokens ?? 0;
    const durationMs: number = this.msg.usageDurationMs ?? 0;
    return Math.round(completion / (durationMs / 1000)) + ' tok/s';
  }

  // 首字耗时数值串（2026-09-23 首字耗时笔）：口径 = 本轮首个正文或思考增量到达的墙钟耗时
  //（跨流取首个非 0；常开测量、不随请求日志开关——与请求日志那枚「首字节」是两个指标，
  // 详见 ChatUsageRoundCtrl）。分档与「用时」同规则（<60 秒一位小数，否则整数秒）
  private usageFirstTokenValue(): string {
    const seconds: number = (this.msg.usageFirstTokenMs ?? 0) / 1000;
    return seconds < 60 ? (Math.round(seconds * 10) / 10) + 's' : Math.round(seconds) + 's';
  }

  // token 数缩略（≥1000 缩 k 一位小数；各数值行共用）——2026-09-17 提取共用至
  // common/TokenEstimate.tokenShort（上下文面板同口径），本组件改引单源

  // 长按守卫（★ 2026-09-18 复制入口迁移笔；★ 同日流式闸笔）：隐私会话不弹（零留痕口径
  // 照底栏整栏不显示——复制面板同属留痕面）；流式生成中不弹（决明拍板「只在停止状态可
  // 长按复制」——生成中快照是半截文本，复制即误导；判据同底栏 barVisible 单消息级：
  // finishStream / settleRoundAssistant 收口置假后即可复制，手动停止轮同享；user 行该
  // 字段恒 undefined 不受影响）；空文本无可复制。守卫内收（手势两泡恒挂、不满足静默不弹）
  // 而非手势条件分支——ArkUI 通用属性链上做条件手势反而多写组件分支
  private requestCopySheet(): void {
    if (this.privateSession || this.msg.streaming === true || this.msg.text === '') {
      return;
    }
    this.onCopyText(this.msg.id);
  }

  // 用量行（标签左·数值右对齐——2026-09-15 决明「同图竖向排列」；标签次要色、数值
  // 主色加粗，两处色位对位即行形态判据）。@Builder 按值传参只读展示（内容为预组合串、
  // 弹窗内容重开即重算，无刷新需求——照 ToolSummaryRow 先例）
  @Builder
  UsageRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Blank()
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
    }
    .width('100%')
  }

  // 用量键气泡内容（bindPopup builder——首层容器禁 position；内距 12，横宽 200〔初版 280
  // 照 InfoHintButton——那是长整段说明文本的几何；本气泡内容是短「标签 + 数值」行对，
  // 2026-09-15 决明「气泡横宽减少，因用量数字不长」故收窄；最宽一行「生成速度 + 9999 tok/s」
  // 约 120vp，200 宽留足余量〕。组件内直读 this.msg 规避坑57 按值传参；字段在流末收口后
  // 不变，弹出时现读即可无需订阅。
  // ★ 2026-09-15 决明改版（照其供图形态）：①标题 = 纯文字「Token 用量」（16fp Bold；
  // **气泡内不显示任何符号**，供图那枚 AI 徽标与模型名都不取——决明「不用显示图标与
  // 模型」+ 二轮明确「用量气泡不显示符号」，用量符号只落在底栏那枚用量键上）；②标题下加
  // 分割线，其身下六行竖排；③速度行殿后且恒主色无强调蓝（决明「速度不用蓝体」「我们
  // 速度放最后」）；④缓存行是比供图多的一行（决明「我们多了缓存显示」），命中 >0 才列
  //〔2026-09-10 拍板 >0 门不变，形态由括号内缀改独立行〕；⑤用时与速度同行门 = 时长
  // 在场（时长缺省的协议两行同缺）；⑥原末行口径声明退役（决明二轮「用量气泡底部提示
  // 删除」——原防「单轮数与设置页聚合数对不上」误读，随标题行语义自明而撤）──
  @Builder
  UsagePopup() {
    Column({ space: 10 }) {
      // 标题行（16fp Bold 取「板块标题规范」标准档；纯文字无符号——见上注①）
      Text('Token 用量')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .width('100%')
      // 标题与用量行的分组分割线（照工具卡分割线形制）
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
      Column({ space: 8 }) {
        this.UsageRow('输入', tokenShort(this.usagePromptCount()))
        if ((this.msg.usageCachedTokens ?? 0) > 0) {
          this.UsageRow('缓存', tokenShort(this.msg.usageCachedTokens ?? 0))
        }
        this.UsageRow('输出', tokenShort(this.msg.usageCompletionTokens ?? 0))
        this.UsageRow('总计', tokenShort(this.msg.usageTokens ?? 0))
        if ((this.msg.usageDurationMs ?? 0) > 0) {
          // 首字耗时殿于用时之前（2026-09-23 首字耗时笔）：时间三行按发生序排——首字 → 用时
          // → 生成速度。＞0 才显（升级前的老账本行与无产出轮次无此行）；口径见
          // usageFirstTokenValue 注释
          if ((this.msg.usageFirstTokenMs ?? 0) > 0) {
            this.UsageRow('首字耗时', this.usageFirstTokenValue());
          }
          this.UsageRow('用时', this.usageDurationValue());
          this.UsageRow('生成速度', this.usageSpeedValue());
        }
      }
      .width('100%')
    }
    .width(200)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }

  // 正文渲染键（2026-09-20 重试真机修复笔）：id#纪元——非前缀替换（重试清空重答 /
  // 切换版本换整段内容）时 renderEpoch 自增即键变，外层 ForEach 整组件重建 → 渲染器
  // 全量重解析（修「正文停在旧内容」：两渲染器对内容整体替换不重解析，真机实测重试与
  // 切版后正文不变、退出重进才正确——重建与退出重进同效）。流式追加（前缀单调）不动
  // 本键，打字机增量路径与 K1 零闪屏口径零影响（见 ChatMessageCompose.renderEpoch）
  private mdRenderKey(): string {
    return this.msg.id + '#' + (this.msg.renderEpoch ?? 0);
  }

  build() {
    if (this.msg.kind === 'user') {
      // 用户消息两泡竖排（★ 2026-09-15 预览笔拍板 7：附件独立气泡、置于消息气泡之前〔列表
      // 时序上方〕）：外包裹 Column 先附件泡后消息泡，间距 ATTACH_BUBBLE_GAP——两泡同属
      // 本条消息（同一 ListItem，拆独立消息行即破坏回放装配归属，红线 §3-9）
      Column({ space: ATTACH_BUBBLE_GAP }) {
        // 附件泡（有简报才挂，零占位；点击派发上行 ChatPageContent 分派预览）
        if ((this.msg.attachBriefs ?? []).length > 0) {
          AttachmentBubble({
            msg: this.msg,
            onPreviewAttach: (msgId: string, briefId: string): void => {
              this.onPreviewAttach(msgId, briefId);
            }
          })
        }
        // 消息泡：右对齐、浅蓝底（chat_bubble_user，深浅色随限定词）。★ 空文本规则（纯附件
        // 消息）：标注隐去后正文为空 → 整只不渲染（禁空气泡，只剩上方附件泡）。正文 =
        // displayBodyText()（有简报时剥标注）；公式守卫用全量版 guardStreamingLatex——
        // 显示文本随简报装配变化（回放先渲染后装配），增量版按 msg.id 存状态会吃到变短
        // 的输入，全量重扫无状态零风险。★ 宽度上限 = BUBBLE_USER_MAX_WIDTH（78%——2026-09-16
        // 决明「用户的缩短为原60%左右，右边距不变」立 60%，2026-09-18「再增宽30%左右」调
        // 78%；行内距两者皆不动，故右缘贴位与右距不变、短消息泡仍随内容收缩）。
        // ★ 2026-09-18 换行修复（决明「超长内容会顶出气泡右侧，不换行」）：宽度上限的**挂点**
        // 由气泡自身的 constraintSize 改为外层定宽壳——constraintSize 只是测量之后的尺寸
        // 钳制，泡内 Markdown 的段落仍按父行全宽排版，泡一收窄内容就顶出右缘（官方《尺寸
        // 设置》constraintSize 取值表 + FAQ faqs-arkui-95「ConstraintSize 尺寸设置不生效」
        // 同族现象）；改为外壳显式 width 后，壳宽即子组件的**测量约束**，段落按上限换行、
        // 高度自然增长，宽内容块（代码/表格自带横滚面）也收在泡内横滚
        if (this.displayBodyText() !== '') {
          Row() {
            Blank()
            // 定宽壳：只承担宽度上限，不画底不设内距（气泡形制全在下方 Markdown 上）；
            // alignItems(End) 让短泡贴壳右缘，右缘位置与收窄前一致
            Column() {
              Markdown({
                content: guardStreamingLatex(this.displayBodyText()),
                options: { darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK },
                nestedScroll: MD_NESTED_SCROLL
              })
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.chat_bubble_user'))
                .borderRadius(BUBBLE_RADIUS)
                // 长按开「消息全文」面板（2026-09-18 复制入口迁移）：用户气泡同享——
                // @lidary 渲染 Text 无 copyOption（默认 None，本地 text.d.ts 实锤），
                // 长按在气泡层空闲无争用。挂在气泡上而非定宽壳上：壳内空档不长按响应
                .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
                  this.requestCopySheet();
                }))
            }
            .width(BUBBLE_USER_MAX_WIDTH)
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding({ left: BUBBLE_PAD_FAR, right: BUBBLE_PAD_NEAR })
          .justifyContent(FlexAlign.End)
        }
      }
      .width('100%')
    } else if (this.msg.kind === 'assistant') {
      // 助手气泡：左对齐、卡片色底（深浅色自适应）。★ 2026-09-02 阶段 5 双渲染分流：
      // 实验态 = CubeMarkdownView（markdown_hybrid 增量解析——K1 闪屏根治：@lidary 全量
      // 重解析 × 打字机 30Hz 揭示每秒约 30 次全文重解析）；原生态 = @lidary 原样。开关
      // build 期现读——已上屏行不回翻（渲染器不切换），新渲染行随开关（重进会话全量生效）。
      // user 分支不换（静态短文本无闪屏，变量隔离——对照只在 assistant 渲染）。
      // ★ 2026-09-14 消息气泡底栏：底栏挂气泡体 Column 内、双渲染器之后（两引擎共享层
      // 零适配——调研档 §四·补）；原气泡外用量 meta 文字行退役（内容迁入用量键气泡）。
      // 外层 Column({space:4})：气泡本体 + 推荐问题 chips 两项（2026-09-19 推荐问题笔起
      // chips 挂卡外下方——space 4 即卡与 chips 间距；左右 padding 在本层，两者同缘对齐）
      Column({ space: 4 }) {
        Row() {
          Column({ space: 8 }) {
            // ── 自动重试状态行（2026-09-22 聊天自动重试笔）：挂气泡内、正文之上——判据 =
            // 运行时字段非空（undefined / '' = 无重试，结构零变化）；纯文本一行，数字随次数
            // 原地更新不新增行、不堆叠。样式取组卡副标题规格（14fp 小字）+ 官方次要色资源
            //（零自绘色值）；与正文同列受气泡内距约束，故与正文左对齐 ──
            if (this.msg.retryHint !== undefined && this.msg.retryHint !== '') {
              Text(this.msg.retryHint)
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
            }
            // ★ 2026-09-20 重试真机修复笔：两分支各包一层「id#纪元」键 ForEach——重试清空
            // 重答与切版换整段内容时键变即整组件重建（渲染器全量重解析），流式追加不动键
            //（修复动因与实测见 mdRenderKey 注释）
            if (isCubeEngineEnabled()) {
              ForEach([this.mdRenderKey()], (_renderKey: string): void => {
                CubeMarkdownView({
                  // 流式公式守卫：未闭合 $ 尾部转义（与 @lidary 分支同一喂入口）
                  content: guardStreamingLatexLive(this.msg),
                  darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                })
              }, (renderKey: string): string => renderKey)
            } else {
              ForEach([this.mdRenderKey()], (_renderKey: string): void => {
                Markdown({
                  // 流式公式守卫：未闭合 $ 尾部转义（同 user 分支）
                  content: guardStreamingLatexLive(this.msg),
                  options: { darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK },
                  nestedScroll: MD_NESTED_SCROLL
                })
              }, (renderKey: string): string => renderKey)
            }
            // ── 截断尾注（2026-09-23 输出上限与超时治理笔 2）：挂气泡内、正文之下——与
            // 上方 retryHint 状态行一上一下对称（状态行在正文之上、截断提示在正文之下），
            // 两者都是气泡内次要小字。判据 = 运行时字段恰 true（undefined/false = 无截断，
            // 结构零变化）；样式照 retryHint 行同款（14fp 小字 + 官方次要色资源），**只追加
            // 一行、不改写正文**（渲染刷新红线：794 节「非前缀整段替换」才须推 renderEpoch）；
            // 文案两条建议与判据同界——判据只认真截断（responses 侧收窄到 max_output_tokens，
            // 内容过滤不挂键），故「提高上限 / 降低档位」恒与真因一致 ──
            if (this.msg.truncated === true) {
              Text('输出被上限截断，可提高输出上限或降低思考档位')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
            }
            // ── 气泡内底部工具栏（2026-09-14 任务书；2026-09-15 真机反馈改右下锚定）：
            // 宽度写法仍 = 写作①（不设百分比宽度、不加 Blank，短消息气泡被撑到约底栏宽
            // 的已知面保留）；对齐 = alignSelf(ItemAlign.End) 挂气泡右缘、从右下角向左排
            // （Column 默认 alignItems Center，不显式指定时长文下底栏悬在居中位）；
            // 间距 2 → 12（真机反馈键间距太近）──
            if (this.barVisible()) {
              Row({ space: 12 }) {
                // ── 版本切换键（2026-09-20 消息重新生成·多版本）：形态 ‹ i/N ›（左箭头 +
                // 当前/总数 + 右箭头），N>1 才渲染；★ 首版仅末条（tail 判据与重试键同源——
                // 切换历史轮会改后续轮上下文，属分支范畴不做）。两端到头禁点（enabled false
                // + 降透明度——LobeChat 形；RikkaHub 的半透明仍可点不取）。箭头 = 行内图标
                // 键形制（SymbolGlyph 无底 TEXTUAL + font_secondary），数字 = 次要色小字──
                if (this.msg.tail === true && (this.msg.variantCount ?? 1) > 1) {
                  Row({ space: 2 }) {
                    Button() {
                      SymbolGlyph($r('sys.symbol.chevron_left'))
                        .fontSize(14)
                        .fontColor([$r('sys.color.font_secondary')])
                    }
                    .buttonStyle(ButtonStyleMode.TEXTUAL)
                    .enabled((this.msg.variantActive ?? 0) > 0)
                    .opacity((this.msg.variantActive ?? 0) > 0 ? 1 : 0.4)
                    .onClick((): void => {
                      this.onVariantSwitch(this.msg.id, (this.msg.variantActive ?? 0) - 1);
                    })
                    Text(((this.msg.variantActive ?? 0) + 1) + '/' + (this.msg.variantCount ?? 1))
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))
                    Button() {
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(14)
                        .fontColor([$r('sys.color.font_secondary')])
                    }
                    .buttonStyle(ButtonStyleMode.TEXTUAL)
                    .enabled((this.msg.variantActive ?? 0) < (this.msg.variantCount ?? 1) - 1)
                    .opacity((this.msg.variantActive ?? 0) < (this.msg.variantCount ?? 1) - 1 ? 1 : 0.4)
                    .onClick((): void => {
                      this.onVariantSwitch(this.msg.id, (this.msg.variantActive ?? 0) + 1);
                    })
                  }
                }
                // 用量键（拍板 6：点击弹气泡；usageTokens 在场才挂——隐私会话零落库与
                // 无用量协议天然不弹空气泡）。★ 2026-09-20 D4-4 注释核正：旧注「失败轮
                // 天然不弹」系七百八十二节之前的退役口径——中断/失败轮自该节起同落账本
                //（error 收尾同落同显），轮内已有完整收尾段时照挂值仍会弹气泡，勿据旧注
                // 把下面的挂载守卫当误改删回。★ 2026-09-15 决明改版：符号由 info_circle 改
                // sys.symbol.data_proportion——与一级页设置页「用量统计」行卡同款
                //（同源符号 = 一眼对上那张卡；键形仍是 InfoHintButton 那种 TEXTUAL 图标键，
                // 字号取底栏统一的 16fp、非该件的卡头 18fp，只是换成用量自己的符号）。
                // 气泡 builder 直读 this.msg（坑57 按值传参规避）
                if (this.msg.usageTokens !== undefined) {
                  Button() {
                    SymbolGlyph($r('sys.symbol.data_proportion'))
                      .fontSize(16)
                      .fontColor([$r('sys.color.font_secondary')])
                  }
                  .buttonStyle(ButtonStyleMode.TEXTUAL)
                  .onClick((): void => {
                    this.usagePopupShow = !this.usagePopupShow;
                  })
                  // 底栏右下锚定后用量键在屏右半区：placement 用 BottomRight（右缘对齐
                  // 向左展开，InfoHintButton 同族几何——2026-09-15 随键位右移从 BottomLeft
                  // 改锚；200 宽气泡在窄屏个别键位下仍可能横向放不下，官方 API 参考实锤
                  //「当前位置显示不下时会自动调整位置」，越界兜底由系统避让承担）
                  .bindPopup(this.usagePopupShow, {
                    builder: (): void => {
                      this.UsagePopup();
                    },
                    placement: Placement.BottomRight,
                    // 弹层族材质（2026-09-22 决明指令「气泡全 thick」；「无」档 = 材质关闭，
                    // 回落到不设 popupColor 的官方默认形态）
                    systemMaterial: overlayMaterial(),
                    onStateChange: (event: PopupStateChangeParam): void => {
                      if (!event.isVisible) {
                        this.usagePopupShow = false;
                      }
                    }
                  })
                }
                // 重试键（仅末条助手消息——历史轮重生成属分支范畴，任务书自定口径③；
                // ★ 2026-09-20 重试真链复活并升级多版本：点击上行 ChatPage → ChatSendCtrl
                // .retryLast 就地重答，旧回答保进 variants 可经切换键回看）
                if (this.msg.tail === true) {
                  Button() {
                    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                      .fontSize(16)
                      .fontColor([$r('sys.color.font_secondary')])
                  }
                  .buttonStyle(ButtonStyleMode.TEXTUAL)
                  .onClick((): void => {
                    this.onRetryMsg(this.msg.id);
                  })
                }
                // 「更多」键（锚点 = 前缀 + 消息 id，ChatPage 侧 ChatMessageMenuHost 消费）
                // ★ 2026-09-18 消息复制优化笔：复制键退役——复制入口迁气泡长按（「消息全文」
                // 面板内自由选择，跨段落可选；原键整条直复制无选择能力，与本笔要解的
                // 「逐段只能选一段」同属复制体验缺口，随入口迁移一并退役）
                Button() {
                  SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                    .fontSize(16)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .id(MESSAGE_MENU_ANCHOR_PREFIX + this.msg.id)
                .onClick((): void => {
                  this.onMoreMenu(this.msg.id);
                })
              }
              .margin({ top: 6 })
              .alignSelf(ItemAlign.End)
            }
          }
          // 气泡形制统一挂内容列（两渲染器共享：内边距/卡片底/圆角/宽度上限——原 Markdown
          // 组件形制原样上移，视觉零回归）
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(cardBg(this.appColorMode))
          // ★ 2026-09-16 思考块同泡化：上方紧贴思考半泡时（thinkAbove）上缘切直角——
          // 与思考半泡的下缘直角拼成一个气泡（角半径常量四处同源，禁单改其一）
          .borderRadius({
            topLeft: this.msg.thinkAbove === true ? 0 : BUBBLE_RADIUS,
            topRight: this.msg.thinkAbove === true ? 0 : BUBBLE_RADIUS,
            bottomLeft: BUBBLE_RADIUS,
            bottomRight: BUBBLE_RADIUS
          })
          .constraintSize({ maxWidth: '100%' })
          // 长按开「消息全文」面板（2026-09-18 复制入口迁移）：Cube 引擎侧 setIsOnCopy(false)
          // 已退役渲染器逐段长按复制（CubeMarkdownView），长按在气泡层让位本手势
          .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
            this.requestCopySheet();
          }))
          Blank()
        }
        .width('100%')
        // ── 推荐问题 chips（2026-09-19 推荐问题功能；★ 同日决明反馈笔移卡外下方）：
        // 挂外层 Column 内、气泡 Row 之后 = 气泡卡外下方（外层 space 4 给间距、左右
        // padding 与气泡同缘对齐——chips 独立于卡片底与圆角，长建议换行不再撑泡）；
        // 判据/数据链/点击上行链不变（suggestVisible + @Observed suggestions + onSuggestSend）──
        if (this.suggestVisible()) {
          ChatSuggestBar({
            suggestions: this.msg.suggestions ?? [],
            onPick: (text: string): void => {
              this.onSuggestSend(text);
            }
          })
        }
      }
      .width('100%')
      // ★ 2026-09-16 决明「助手的右边距缩短与左边距统一」：右侧由 BUBBLE_PAD_FAR(20) 改
      // BUBBLE_PAD_NEAR(4)，与左侧同值——助手气泡横向加宽、左右对称；同笔思考块与工具卡
      // 按既有「左右边距对齐助手气泡」契约随形（三件同值，勿单改其一）
      .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
    } else if (this.msg.kind === 'thinking') {
      // ★ 2026-09-16 思考块同泡化（决明「把回复的思维链也收入气泡，仍支持展开收起」）：
      // 由气泡外独立灰字块改为「助手气泡上半」——与下方正文泡同宽同底（cardBg）、上缘圆角
      // 16 / 下缘直角，靠负 margin 吃掉列表项间距 CARD_SPACING 使两半贴合；正文泡上缘由
      // msg.thinkAbove 切直角配合（见 ChatMessageCompose.thinkAbove 字段注释，写点 = 思考
      // 行三条创建链）。结构镜像助手分支（Row + Blank）——两半宽度算法完全同源，勿改单边。
      // 左右边距仍 4/4 与助手泡统一（三件同值契约）
      Row() {
        Column() {
          // 生成中标记传导（streaming 三态收口的判据源；undefined 归一为 false = 已结束）
          ChatThinkingBlock({ text: this.msg.text, streaming: this.msg.streaming === true })
          // 思考区与正文区分割线（形制照工具卡：1vp cardBorderColor；内缩由气泡内距给出，
          // 与两侧文字对齐）
          Divider()
            .strokeWidth(1)
            .color(cardBorderColor(this.appColorMode))
            .margin({ top: THINK_DIVIDER_GAP })
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius({
          topLeft: BUBBLE_RADIUS,
          topRight: BUBBLE_RADIUS,
          bottomLeft: 0,
          bottomRight: 0
        })
        .constraintSize({ maxWidth: '100%' })
        Blank()
      }
      .width('100%')
      .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
      .margin({ bottom: -CARD_SPACING })
    } else if (this.msg.kind === 'tool') {
      // 工具调用卡（★ 2026-09-20 审批卡视觉迁移笔 A：卡面本体域级拆分至 ChatToolCard.ets，
      // 本分支只余一行实例化——搬迁零行为变更；两回调透传契约同 onAskSubmit/onBrowseConfirm。
      // 拆分动因 = 本笔要给工具卡加专属头行与回执行，本文件拆分前 1192 行越 1200 硬线）
      ChatToolCard({
        msg: this.msg,
        onAskSubmit: (callId: string, answerJson: string): void => {
          this.onAskSubmit(callId, answerJson);
        },
        onBrowseConfirm: (callId: string, approved: boolean): void => {
          this.onBrowseConfirm(callId, approved);
        }
      })
    } else if (this.msg.kind === 'summary') {
      // 压缩摘要提示行（2026-09-23 上下文压缩）：一行高的**持久**轻提示——与 notice 同款
      // 居中式样，但本行**落库**（notice「不落库」的惯例不适用于本行——它标记的是会话的
      // 持久压缩状态，重进会话由回放重建）；文案固定（msg.text 存的是摘要正文，展示不用它
      // ——正文在用量面板的折叠区看）；整行可点 → 打开上下文用量面板
      Row() {
        Blank()
        Text('上下文已压缩，摘要见上下文用量')
          .fontSize(11)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
      .onClick((): void => {
        this.onOpenUsage();
      })
    } else {
      // notice：居中提示条（连接状态/错误提示等）
      Row() {
        Blank()
        Text(this.msg.text)
          .fontSize(11)
          .fontColor(this.msg.level === 'error' ? $r('sys.color.ohos_id_color_warning') : cardDescColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
    }
  }
}

// ═══ 思考过程折叠块（2026-08-27 二二九改拍板形态：「thinking 分支 Text 全量 → 默认折叠
// （标题行「思考过程·收起/展开」+ 内容截断 3 行/展开全量），@State 每消息独立；样式沿用
// 灰字体系」。2026-09-01 自 ChatThinkingBlock.ets 并回本文件；同日偏好设置起初始态改读
// 「默认展开思考」偏好键——缺省 false 收起形态不变，见 AppPreferences.ets）═══
// 交互：标题行整行可点切换折叠/展开（chevron 旋转指示 + 动作文字「展开/收起」）；每消息
// 实例独立 @State（列表项回收即弃，不跨消息串态）。
// ★ 2026-09-16 决明「显示尾部最新 + 加高度动画」（三改）：
//  ① 折叠态不再截断头部——内容区取**末尾切片**（最新一段）并底部对齐，流式期看到的始终是
//     最新思考（原实现 maxLines(3) 显示的是最早三行）；
//  ② 折叠态内容区高度恒定 = THINK_BODY_COLLAPSED_H（3 行）——切片只换文本不改高度，流式
//     增长不抖动（高度随内容跳变会整条气泡忽高忽低）；
//  ③ 展开/收起走显式数值高度 + animateTo 插值（尺寸属「可动画属性・布局属性」，官方
//     《属性动画概述》实读；自然高度不可插值，故展开目标用实测全量高度而非省略高度约束）。
//     收起动画期间仍显示全量（观感 = 内容被裁掉而非文字跳变），动画结束才切回切片。
// ★ 2026-09-16 决明「生成中折叠态显最新三行 / 结束后折叠不展示，加收拢动画」（三态收口）：
//  折叠态内容区高度按**本轮是否仍在生成**分两档——生成中 = 3 行窗口（同上②）；已结束 = 0
//  （THINK_BODY_DONE_H，内容区收拢、标题行与分割线仍留作展开入口）。判据 = 消息运行时字段
//  streaming（见 ChatMessageCompose 字段注释；写点 = 思考行懒创建置真 + finishStream /
//  settleRoundAssistant 置假；回放/翻页重建的行该字段天然 undefined ⇒ 判「已结束」）。流末
//  （streaming 真→假）走同一段 260ms 动画收拢——观感是「收拢」而非跳变。两条边界：
//  ①展开态（含偏好「默认展开思考」）不强制收起——用户明确表达过要看，收口只作用于折叠态；
//  ②已结束的块再点展开仍显全量，收起回到 0。
// ★ 2026-09-16 真机反馈修（决明「展开是分割线下移同步露出内容，收起却是思考区文字消失、全白、
//  分割线再收起，可优化吗」）：根因 = 官方《卡包展开折叠动画实现》背景知识原文「布局类改变宽高
//  的动画，**内容都是直接到终点状态**」——内容盒高度跟着视窗收窄的话，它的布局直接按终点（0）
//  算 ⇒ 收拢起手帧文字就没了、只剩空卡在收（展开看不出问题：终点是满高，故表现为「同步露出」）。
//  修 = **内容盒与视窗解耦**（新增内层内容盒）：动画起手把内容盒冻结在「起手视窗高与终点的较大
//  者」（展开 = 满高、收拢 = 起手满高/折叠窗高），animateTo 只动视窗外层高度 + 裁切 ⇒ 文字全程
//  在场、被逐帧裁掉；动画结束解冻回终值。贴边键随之明确：视窗「折叠中且仍在生成」贴下沿（预览
//  态末段留窗、收尾切切片零跳变），其余（展开态 + 已结束的收拢）贴上沿——收拢 = 展开的逐帧倒放
//  （下沿上移盖住文字），不再出现「文字先没了、空卡再收」。
// 折叠态预览行数（拍板口径 3 行；观感参数可单点调）
const THINKING_COLLAPSED_LINES: number = 3;
// 思考文字字号（fp）与行高（vp）——与下方 Text 样式声明同源；行高同时是高度换算基准
const THINK_FONT_SIZE: number = 12;
const THINK_LINE_HEIGHT: number = 18;
// 折叠态内容区高度（vp）= 恰 3 行：固定高，切片文本换多少写多少都不改高度
const THINK_BODY_COLLAPSED_H: number = THINKING_COLLAPSED_LINES * THINK_LINE_HEIGHT;
// 已结束（streaming 假）折叠态内容区高度（vp）= 0：整块收拢，只留标题行与分割线
const THINK_BODY_DONE_H: number = 0;
// 展开/收起高度动画时长（ms；与输入栏工具行展开同量级观感）
const THINK_EXPAND_ANIM_MS: number = 260;
// 单行字数估算的宽度未测得兜底（首帧前调 measure 用；偏小 = 少取历史，不裁最新）
const THINK_TAIL_FALLBACK_CHARS: number = 20;

// ── 折叠态尾部切片（纯函数，组件外顶层；2026-09-16 自检轮自 ChatThinkingBlock.tailPreview
// 提取并补行数收口——原实现是组件私有方法，断言只能盯源码形态、行为零执行面，短行密集
// 形态的缺陷正是从这条盲区逃逸；提纯后由 assert-feature-domain 109 组源内提取直跑，
// 照本仓 zoomOffsetRange / pinchOffset 先例）──
// 返回「交给 Text 从头部渲染」的那一段 = 思考全文的末尾片段，四环：
//  ① 末尾取段——字符量上界 = 折叠行数 × 单行字数估算；
//  ② 代理对保护——切点落在 UTF-16 代理对中间则前移一位（emoji 不被劈开）；
//  ③ 行首对齐——切点后半行宽内有换行则改从换行后开始，不显示半行；
//  ④ 行数收口——短行密集文本（分点草稿 / 空行分段 / 代码段）按字符量取会远超折叠行数，
//     Text 的 maxLines 只渲染前几行 ⇒ 窗口里落的反而是**旧**内容（自检轮实测：分点草稿
//     切片渲染 10 行、空行分段 5 行，末段均不可见）；故把切点沿换行边界后推，直到剩余
//     部分渲染行数 ≤ 折叠行数——末尾（最新段）始终保留在窗口内
export function thinkTailSlice(text: string, perLine: number): string {
  const limit: number = perLine * THINKING_COLLAPSED_LINES;
  if (text.length <= limit) {
    return text;
  }
  let start: number = text.length - limit;
  const code: number = text.charCodeAt(start);
  if (code >= 0xDC00 && code <= 0xDFFF) {
    start--;
  }
  const nl: number = text.indexOf('\n', start);
  if (nl >= 0 && nl < start + Math.ceil(perLine / 2)) {
    start = nl + 1;
  }
  // 收口循环有界：每轮至少前进 1 个字符，窗内换行数 ≤ 字符量上界；窗内无换行（单行长段，
  // 例如一整段无换行的长推理）= 字符量切法即正解，直接退出
  while (thinkPreviewLines(text, start, perLine) > THINKING_COLLAPSED_LINES) {
    const next: number = text.indexOf('\n', start);
    if (next < 0) {
      break;
    }
    start = next + 1;
  }
  return text.substring(start);
}

// 切片渲染行数估算（与折叠态 Text 的 maxLines 同口径）：段内按单行字数折行 + 段数；
// 空段记 1 行（空行同样占一行高，不记会低估行数）
function thinkPreviewLines(text: string, start: number, perLine: number): number {
  let lines: number = 0;
  const segs: string[] = text.substring(start).split('\n');
  for (const seg of segs) {
    lines += Math.max(1, Math.ceil(seg.length / perLine));
  }
  return lines;
}

@Component
struct ChatThinkingBlock {
  // 思考全文（kind='thinking' 的 ChatMessage.text；@Prop 构建时传导，流式增量由页面侧原地
  // 改 msg.text → 父组件重渲 → 本 @Prop 更新；沿 @Prop 契约防坑57）。@Watch = 展开态下
  // 文本增长须重算内容区高度（折叠态高度恒定，无需重算——见 onTextChange）
  @Prop @Watch('onTextChange') text: string;
  // 本轮是否仍在流式生成（父组件按 this.msg.streaming === true 传导——见 ChatMessageCompose
  // 字段注释；@Watch = 流末收拢，见 onStreamingChange）。折叠态高度两档与收起目标高度都随它判
  @Prop @Watch('onStreamingChange') streaming: boolean;
  // 初始态 = 偏好「默认展开思考」（AppPreferences persistProp 键，创建期读一次——手动
  // 切换后仍逐块独立不受影响；偏好改动对已上屏块不回翻，重进会话/新消息生效）
  @State private expanded: boolean = getThinkExpandDefault();
  // 内容区显式高度（vp）：折叠三态 = 生成中 THINK_BODY_COLLAPSED_H / 已结束 THINK_BODY_DONE_H
  // （见 collapsedH）；展开 = 全量实测高度（measureFullH）。偏好默认展开时创建期读不到宽度，
  // 停在折叠高，由首个 onAreaChange 补测（见 onBlockArea）
  @State private bodyH: number = THINK_BODY_COLLAPSED_H;
  // 内容显示全量（true）还是尾部切片（false）——收起动画期间仍为 true（见头注释③），
  // 动画结束（onFinish）才切回切片
  @State private fullBody: boolean = getThinkExpandDefault();
  // 内容盒（内层 Column）高度（vp）：稳态与视窗同高；**两向动画期冻结在起手值**（见
  // animateBody）——官方实锤「布局类宽高动画，内容直接到终点状态」，内容盒若跟着视窗收窄
  // 就会按终点高（0）重排，文字在收拢起手帧消失（真机报障形态）；冻结后内容布局与视窗解耦
  @State private contentH: number = THINK_BODY_COLLAPSED_H;
  // 内容区实测宽度（vp；onAreaChange 回写）——measureTextSize 的约束宽，也是切片字数基准；
  // 0 = 尚未测得
  private textW: number = 0;

  // 折叠态目标高度（vp）：生成中 = 3 行窗口；已结束 = 0（收拢）——首帧定档、展开/收起、
  // 流末收拢三处同源，禁各写一套（改口径只改本函数）
  private collapsedH(): number {
    return this.streaming ? THINK_BODY_COLLAPSED_H : THINK_BODY_DONE_H;
  }

  // 首帧定档：已结束的历史块直接落在收拢态——回放/翻页重建的对象 streaming 天然 undefined，
  // @Watch 不触发初值，故须在此给定（否则会停在折叠高、白显三行）；生成中的块与展开态
  // （偏好默认展开）维持原路径：前者落在折叠高，后者由首个 onAreaChange 补全量高
  aboutToAppear(): void {
    if (!this.expanded) {
      this.bodyH = this.collapsedH();
    }
    this.contentH = this.bodyH;
  }

  // 视窗贴边键（见 build 内容区注释与头注释真机反馈修）：折叠中且仍在生成 → 贴下沿（预览态
  // 末段/最新留在窗内、收尾切切片零跳变）；其余（展开态 + 已结束的收拢）→ 贴上沿，
  // 收拢即展开的逐帧倒放（视窗下沿上移盖住文字，不再「文字先没了、空卡再收」）
  private stickTop(): boolean {
    return this.expanded || !this.streaming;
  }

  // 高度动画统一入口（展开/收起/流末收拢三路共用）：
  //  ①冻结内容盒——必须在 animateTo **之外**改（闭包内改的状态会被一并插值）；冻结值取
  //    「**当前内容盒高**、起手视窗高、终点」三者较大者：展开 = 满高（终点）、收拢 = 起手
  //    满高 / 折叠窗高（即正文的完整高度）。含当前 contentH 是为**动画被打断**的时序（生成
  //    中手动收起未毕即流末收拢）：只看视窗高与终点时，后者会把冻结值拉小（满高 → 折叠窗高），
  //    内容盒一缩就重演本笔要修的症状（文字先消失）。内容布局因此全程与视窗解耦（官方机制
  //    见头注释真机反馈修）；稳态下 contentH 恒等于 bodyH，本项无行为差异；
  //  ②animateTo 内只动视窗高度（贴边键与全量/切片键由调用方在闭包外置好）；
  //  ③onFinish 解冻内容盒回终值，并把内容切回尾部切片（收起/收拢两路；展开路已为全量）
  private animateBody(target: number): void {
    this.contentH = Math.max(this.contentH, this.bodyH, target);
    this.getUIContext().animateTo({
      duration: THINK_EXPAND_ANIM_MS,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        this.contentH = target;
        if (!this.expanded) {
          this.fullBody = false;
        }
      }
    }, (): void => {
      this.bodyH = target;
    });
  }

  // 流末收拢（streaming 真→假）：折叠态用与展开收起同一段 260ms 动画收敛到折叠态目标
  //（collapsedH——此刻 streaming 已为假 ⇒ 即 THINK_BODY_DONE_H，走同一单源，勿写死常量；
  // 观感是「收拢」而非 54vp 跳变）；展开态（含偏好默认展开）零动作 = 不强制收起（见头注释边界①）
  onStreamingChange(): void {
    if (this.streaming || this.expanded) {
      return;
    }
    this.animateBody(this.collapsedH());
  }

  // 文本增量（流式）：展开态内容区高度按新长度重算；折叠态高度恒定（正文为尾部切片，
  // 每次刷新自渲染最新段），零额外成本
  onTextChange(): void {
    if (this.expanded) {
      this.bodyH = this.measureFullH();
      this.contentH = this.bodyH; // 内容盒随视窗（展开态文本增长；动画期冻结见 animateBody）
    }
  }

  // 内容区实测宽度回写（onAreaChange；宽度只随屏宽/旋转变化，0.5vp 阈值去抖防重入）
  private onBlockArea(wVp: number): void {
    if (wVp <= 0 || Math.abs(wVp - this.textW) < 0.5) {
      return;
    }
    this.textW = wVp;
    // 首帧补测：偏好「默认展开思考」时创建期无宽度，bodyH 停在折叠高 → 拿到宽度补一次；
    // 折叠态（常规）零成本
    if (this.expanded) {
      this.bodyH = this.measureFullH();
      this.contentH = this.bodyH; // 内容盒随视窗（同上）
    }
  }

  // 全量思考文本的渲染高度（vp）：getMeasureUtils().measureTextSize 与 Text 同参
  //（同字号 12fp / 同行高 18vp / 同宽约束）；返回值为 px，经 UIContext.px2vp 换算
  //（本地 d.ts 实读单位）。宽度未测得或测量异常 → 按字数估算回落（宁高勿低：
  // 高 = 底部留白，低 = 文字被裁）
  private measureFullH(): number {
    const fallback: number = Math.max(THINK_BODY_COLLAPSED_H,
      Math.ceil(this.text.length / this.charsPerLine()) * THINK_LINE_HEIGHT);
    if (this.textW <= 0) {
      return fallback;
    }
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: this.text,
        constraintWidth: this.textW,
        fontSize: THINK_FONT_SIZE,
        lineHeight: THINK_LINE_HEIGHT
      });
      const hVp: number = this.getUIContext().px2vp(size.height as number);
      return hVp > 0 ? hVp : fallback;
    } catch (e) {
      return fallback;
    }
  }

  // 单行字数估算：12fp 中文全角字宽 ≈ 字号，故字数 ≈ 宽 ÷ 字号（混排英文更窄 = 实际行数
  // 更少，方向安全）；下限 8 防极端窄宽除出荒谬值
  private charsPerLine(): number {
    if (this.textW <= 0) {
      return THINK_TAIL_FALLBACK_CHARS;
    }
    const n: number = Math.floor(this.textW / THINK_FONT_SIZE);
    return n >= 8 ? n : THINK_TAIL_FALLBACK_CHARS;
  }

  // 折叠态预览文本 = 末尾切片（多行收口后交给 Text 从头部渲染，等价于显示最新的几行）。
  // 切片本体的四环逻辑（末尾取段 / 代理对保护 / 行首对齐 / 行数收口）在文件尾顶层纯函数
  // thinkTailSlice——提纯动因与实测见其注释
  private tailPreview(): string {
    return thinkTailSlice(this.text, this.charsPerLine());
  }

  // 展开/收起（标题行整行可点）：高度以显式数值驱动并包进 animateTo（尺寸属性可动画）
  private toggleExpanded(): void {
    const next: boolean = !this.expanded;
    // 收起目标随生成态分档（生成中回 3 行窗 / 已结束回 0）——见 collapsedH
    const target: number = next ? this.measureFullH() : this.collapsedH();
    // 两个非可动画键在起手即翻转（贴边随 expanded、全量/切片随 next）——放闭包外与放闭包内
    // 同效（布尔不进插值），放外面是为让 animateBody 成为三条路的统一入口
    this.expanded = next;
    if (next) {
      this.fullBody = true;
    }
    this.animateBody(target);
  }

  build() {
    Column({ space: 4 }) {
      // 标题行（整行可点）:图标 + 「思考过程」+ 动作文字（拍板文案形态）
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(THINK_FONT_SIZE)
          .fontColor([cardDescColor()])
          .rotate({ angle: this.expanded ? 180 : 0 })
        Text('思考过程')
          .fontSize(THINK_FONT_SIZE)
          .fontColor(cardDescColor())
        Text(this.expanded ? '收起' : '展开')
          .fontSize(THINK_FONT_SIZE)
          .fontColor(cardDescColor())
      }
      .padding({ top: 2, bottom: 2 })
      .onClick((): void => {
        this.toggleExpanded();
      })
      // 内容区两级（灰字斜体沿用原 thinking 分支样式）：
      //  · 外层 = 视窗：显式高度（bodyH，动画里唯一动的东西）+ 裁切；
      //  · 内层 = 内容盒：自带高度（contentH），动画期冻结在起手值——文字因此不按视窗终点高
      //    重排（官方机制与真机报障见头注释「真机反馈修」）。
      //  视窗贴边键 stickTop：贴上沿时收拢 = 展开的逐帧倒放（下沿上移盖住文字）；贴下沿时是
      //  折叠预览态与生成中的手动收起——末段（最新）始终留在视野里，收尾切切片零跳变
      //（2026-09-16 自检轮结论在本键上延续）。已结束收拢为 0 = 整块不可见，正文仍在窗内
      //  渲染，展开动画即从这扇窗长出来。
      Column() {
        Column() {
          Text(this.fullBody ? this.text : this.tailPreview())
            .fontSize(THINK_FONT_SIZE)
            .fontColor(cardDescColor())
            .fontStyle(FontStyle.Italic)
            .lineHeight(THINK_LINE_HEIGHT)
            .width('100%')
            .maxLines(this.fullBody ? Number.MAX_SAFE_INTEGER : THINKING_COLLAPSED_LINES)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(this.contentH)
        // 内容盒内对齐：展开/动画期贴上沿；折叠预览态贴下沿（尾部切片贴着窗口下沿出现）
        .justifyContent(this.fullBody ? FlexAlign.Start : FlexAlign.End)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(this.bodyH)
      .clip(true)
      .justifyContent(this.stickTop() ? FlexAlign.Start : FlexAlign.End)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    // 宽度回写（本组件唯一 onAreaChange：只认宽度变化，高度变化零成本）
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.onBlockArea(newArea.width as number);
    })
  }
}
