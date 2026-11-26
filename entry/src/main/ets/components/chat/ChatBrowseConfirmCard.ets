// 高危动作确认卡（形制照 ChatAskUserCard 裁剪）：工具轮预检命中高危（browse_act 词表/属性层
// 判定或 http_request 写方法）时暂停执行先问用户——点「允许一次」放行（browse_act 经注册表
// onApproved 写单次批准戳），点「拒绝」回拒绝文案让模型收尾。
// ★ 确认卡泛化：渲染不限 browse_act（ChatToolCard 判据已去工具名条件）；卡面标题与小字按
// msg.toolName 三族分支——browse_act 两句逐字不动；网络族（http_request 与模板工具 tpl_*）
// 走网络请求文案；本地数据族（数据管理 / 日程 / 工作区 / 挂载写）显示「这个操作会改动你的
// 数据」（自检轮修复：原「非 browse 一律网络句」在本地族接入后误显「发送到对方服务器」失真）。
// 中间说明串由 msg.toolConfirmText 通用承载（各工具预检产自己的说明串）。
// ★ 键区形制（2026-11-05 两千一百一十一，决明「按推荐」拍板）：动作按「主决策 / 放宽
// 范围」两层分组，不再全塌成同一层。①主决策行两档共用 = 拒绝（灰底次钮）+ 允许一次
//（主操作键，官方强调蓝 + 恒白字）；`layoutWeight(1)` 等宽 + 高 40（规范 §1 登记值），
// **8vp 小圆角为本次专属例外**（禁自绘红线登记见 docs/规范-行内按钮与光感.md §1，仅两卡
// 的实底操作键可用，禁扩散）。②非不可逆档次级区 = 本会话内允许（淡彩次级键，宽度自适应——
// 2026-11-09 三档归一笔记删「始终允许该域名」后单键不再等宽占满，避免视觉重量升格成主操作），
// 说明小字在键行上方（先说明后操作）。③取色零手写：四件套 / Tinted 三件全走 ImmersiveLevel
// 单源，字色资源随深浅分治；不可逆档只出主决策行，删除类动作永远单独问。④说明句只述本次
// 放行，范围差异交次级区说明承接。
// ★ 确认链升级：http_request 小字退役旧「不预览」表述（结构化预览落地后与现实相反）；新增
// 可展开预览块（msg.toolConfirmDetail 非空出「查看请求详情」折叠键，@State 本卡自持、作答
// 即随卡转回执态）；browse_act 分支零触碰（两句逐字不动、无预览无快捷键）。
// 渲染位 = ChatToolCard 卡体的确认卡分支（running 且 toolConfirmText 非空且未作答——见
// ChatToolCard.confirmAwaiting）；作答后卡转回执分支，说明串保留供回执行体首取用。
// 组件只做展示与上行，零业务（同 ChatAskUserCard 契约）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardDescColor, cardTitleColor, badgeBg } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  fallbackButtonBgTinted, fallbackButtonFontTinted, fallbackButtonMaterialTinted }
  from '../../common/ImmersiveLevel';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';
import { CONFIRM_LEVEL_IRREVERSIBLE } from '../../common/providers/ToolContracts';
import { TOOL_BROWSE_ACT, TOOL_HTTP_REQUEST } from '../../common/providers/ToolIds';
import { isTemplateToolName } from '../../common/providers/HttpTemplate';
import { ChatMessage } from './ChatMessageCompose';

@Component
export struct ChatBrowseConfirmCard {
  @ObjectLink msg: ChatMessage;
  // 作答上行（ChatToolCard 透传 ChatPage → ChatSendCtrl.resolveBrowseConfirm）
  onSubmit: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 正文字体两键 @StorageProp 自订阅：说明串/风险句/明细/键行按钮属消息显示面；两能力位为
  // 四件套入参（CONTENT_FALLBACK_KEY 恒 true、用户面无入口；光感总档固定强档）——订阅式与
  // 全仓消费点同形，零手写档位值
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 预览展开态（默认折叠——卡面一屏可读）
  @State detailExpanded: boolean = false;
  // 输入位托管档（2026-11-08）：docked=true 时题干进有界滚动区、键区固定不滚；上限由
  // ChatAskDock 按屏高算好后下发，本件只做 constraintSize。流内路径 docked 恒 false。
  @Prop docked: boolean = false;
  @Prop dockBodyMax: number = 200;

  // 卡面小字三族分句 = browse（网站句）/ 网络族 http_request∪模板工具（网络句，tpl_* 动态
  // 注册写入同走网络请求）/ 其余本地数据族（数据句）——原「非 browse 一律网络句」在本地族
  // 接入后失真已改判；卡头标题在 ChatToolCard.confirmTitle。★ 2111 笔：第二句主语明确成
  // 「允许一次」，不再让「只执行这一次」与同屏两个放宽范围的动作互相打架
  private confirmNote(): string {
    if (this.msg.toolName === TOOL_BROWSE_ACT) {
      return '这个操作会改动网站上的数据。允许一次只执行这一次。';
    }
    if (this.msg.toolName === TOOL_HTTP_REQUEST || isTemplateToolName(this.msg.toolName)) {
      return '这个请求会发送到对方服务器。允许一次只执行这一次。';
    }
    return '这个操作会改动你的数据。允许一次只执行这一次。';
  }

  // 预览明细串：空串 = 无预览（browse_act / 老数据），折叠键与内容都不出
  private confirmDetail(): string {
    return this.msg.toolConfirmDetail ?? '';
  }

  // 审批闸说明行：整句由闸单源给（ApprovalGate.approvalCardNote——卡面若自己拼句就得再认
  // 一遍来源、多一个状态面）；空串 = 未配置审批模型或人工确认路径 → 整行不渲染
  private confirmAiNoteText(): string {
    return this.msg.toolConfirmAiNote ?? '';
  }

  // 不可逆档判据（风险块显隐 + 次级区显隐；undefined = 写操作档兜底——老数据不因缺字段而错显红块）
  private irreversible(): boolean {
    return this.msg.toolConfirmLevel === CONFIRM_LEVEL_IRREVERSIBLE;
  }

  // 正文字体家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // 风险块底色（自绘已拍板：危险红浅档 8% / 深档 14%，与徽章实底红同源）
  private riskFill(): string {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ?
      '#24E84026' : '#14E84026';
  }

  // 题干区（Body）与键区（Keys）拆成两块 @Builder：流内路径语义逐字不变；托管路径只把
  // Body 放进有界滚动区，键区恒定固定可见。键区整块原样搬迁、零复制（同提问卡口径）。
  @Builder
  Body() {
      // 主因句（14fp 主色、最多 2 行；文本 = 预检产的说明串）
      Text(this.msg.toolConfirmText ?? '')
        .fontSize(14)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardTitleColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // 风险块（仅不可逆档——写操作档不出现）
      if (this.irreversible()) {
        Text('这个动作可能无法撤销，请确认后再允许。')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor($r('app.color.dialog_confirm_red'))
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor(this.riskFill())
      }
      // 结构化预览（仅带明细的确认出，browse_act 零变化）：折叠键 = 轻动作文字键（无底
      // TEXTUAL + font_secondary——展开折叠类轻动作不占实底档）；展开内容有界（闸在预检产
      // 串侧 ToolHttp.buildHttpConfirmPreview），限行数防极端串撑爆卡体
      if (this.confirmDetail() !== '') {
        Button(this.detailExpanded ? '收起详情' : '查看请求详情')
          .fontSize(13)
          .fontFamily(this.resolveBodyFamily())
          .padding({ left: 6, right: 6 })
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor($r('sys.color.font_secondary'))
          .onClick((): void => {
            this.detailExpanded = !this.detailExpanded;
          })
        if (this.detailExpanded) {
          Text(this.confirmDetail())
            .fontSize(12)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardDescColor())
            .maxLines(16)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(badgeBg(this.appColorMode))
        }
      }
      Text(this.confirmNote())
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .width('100%')
      // 审批闸失败短因（仅「已配置却没结论」非空——卡面须能看出审批跑过而没生效）
      if (this.confirmAiNoteText() !== '') {
        Text(this.confirmAiNoteText())
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
          .width('100%')
      }
  }

  @Builder
  Keys() {
      // 主决策行（两档共用）：拒绝 = 灰底次钮 / 允许一次 = 主操作键（primary=true 官方强调
      // 蓝 + 恒白字）。等宽 + 高 40 为规范 §1 登记值；8vp 小圆角 = 2111 专属例外，两键同形
      // 保证重心落在中线，撤掉旧 Blank 顶开造成的大空洞
      Row({ space: 12 }) {
        Button('拒绝')
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(fallbackButtonFont(this.contentFallback, false))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.onSubmit(this.msg.toolCallId ?? '', false);
          })
        Button('允许一次')
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.onSubmit(this.msg.toolCallId ?? '', true);
          })
      }
      .width('100%')
      // 次级区（仅非不可逆档）：说明小字在键行上方（先说明后操作），段间靠外层 10vp 留白
      // 分隔、不画 Divider、不套分组底板。本会话内允许 = 淡彩次级键，宽度自适应（单键不
      // 等宽占满——等宽铺满会把它推到与「允许一次」同等的视觉重量）。★ 2026-11-09 三档
      // 归一笔记：原「始终允许该域名」快捷键退役，卡片只留
      // 会话内临时放宽，权限默认面统一由三档控制（★ 2026-11-11 域名确认档整卡退役——原括号
      // 「域名档保留在设置页手工维护」已不成立，设置页无该卡，写确认只随会话三档）
      if (!this.irreversible()) {
        Column({ space: 8 }) {
          Text('放宽询问范围。本会话内允许只在本次启动内生效。')
            .fontSize(12)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardDescColor())
            .width('100%')
          Row({ space: 12 }) {
            Button('本会话内允许')
              .height(40)
              .borderRadius(8)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .onClick((): void => {
                // 意图先行：同一同步块内先写意图再上行，工具轮读到必然为真
                this.msg.toolConfirmSessionAllow = true;
                this.onSubmit(this.msg.toolCallId ?? '', true);
              })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
  }

  build() {
    Column({ space: 10 }) {
      if (this.docked) {
        Scroll() {
          Column({ space: 10 }) {
            this.Body()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .constraintSize({ maxHeight: this.dockBodyMax })
      } else {
        this.Body()
      }
      this.Keys()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 左右自持内距 16/12 已退役（独立卡时代遗留，与提问卡同笔收口）
    .padding({ top: 4, bottom: 8 })
  }
}
