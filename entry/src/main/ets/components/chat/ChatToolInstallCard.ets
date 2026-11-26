// install 确认卡（2026-11-24 鸿蒙 Node 运行时门 3 U2，任务书 §3.1 / 方案档 ④⑧）：
// exec_node 的 action=install 等待态专属卡——主因句 + 逐条 name@version 安装清单 + 固定
// registry.npmjs.org 来源行 + 拒绝/允许一次双键。一句话职责 = install 逐条 name@version
// 与固定 registry 的确认卡，无第三键。
// ★ 恒无「本会话内允许」第三键（方案档 ④ 三防线第三道）：install 预检取不可逆档，
// ChatToolRoundCtrl.sessionAllowHit 对不可逆档天然不命中、grantSessionAllow 唯一写点由此
// 无入口——本卡是 grant 键在该动作上的零入口实现，禁回添第三键或 toolConfirmSessionAllow
// 写点（124 组邻域钉守）。
// ★ 形制参照 ChatBrowseConfirmCard（同域确认卡）：主因句 14fp 主色、风险块红档、双键主
// 决策行（拒绝灰底次钮 / 允许一次四件套 true 档、等宽高 40、8vp 专属例外同源）；说明性
// 小字置于键行上方（宪法「功能设置卡布局次序」）。作答回执与卡头标题仍在 ChatToolCard
// 通用链（本件只管等待态卡体）；dock 托管路径渲染 ChatBrowseConfirmCard 的 docked 档
//（不可逆档双键 + detail 折叠清单，行为面一致）。
// 组件只做展示与上行，零业务（同 ChatBrowseConfirmCard 契约）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardDescColor, cardTitleColor, badgeBg } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect }
from '../../common/ImmersiveLevel';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
from '../../common/ChatFont';
import { TOOL_EXEC_NODE } from '../../common/providers/ToolIds';
import { ChatMessage } from './ChatMessageCompose';

// ── install 卡判据（导出单源：ChatToolCard 的卡头标题分支与等待态分派共用）──
// 判据 = 工具名 exec_node + 入参 action trim 后恰为 install（read_output/exec 不命中；trim 与
// 执行侧 resolveActionValue 同规则）。模块级单键缓存：同串零重解析，串变即失效重算（宪法渲染
// 克制——build 内多次调用只解析一次）
let installCardCacheJson: string = '';
let installCardCacheValue: boolean = false;

export function isNodeInstallCard(msg: ChatMessage): boolean {
  if (msg.toolName !== TOOL_EXEC_NODE) {
    return false;
  }
  const inputJson: string = msg.toolInputJson ?? '';
  if (inputJson === installCardCacheJson) {
    return installCardCacheValue;
  }
  let value: boolean = false;
  try {
    const parsed = JSON.parse(inputJson) as Record<string, Object>;
    const raw: Object | undefined = parsed['action'];
    // 判据与执行侧 resolveActionValue 同规则（trim 后比对）：模型传 " install " 时不得落到
    // 通用确认卡，否则标题与说明都与实际动作不符
    if (typeof raw !== 'string') {
      value = false;
    } else {
      value = raw.trim() === 'install';
    }
  } catch (e) {
    value = false; // 坏 JSON 不认 install（卡面兜底句由清单解析自给）
  }
  installCardCacheJson = inputJson;
  installCardCacheValue = value;
  return value;
}

// 清单行上限（防极端长清单撑爆卡体；超出行以计数行说明——预检 spec 闸上限 20 条，本界只是
// 双保险，与预检上限同量级）
const INSTALL_CARD_MAX_LINES: number = 20;

@Component
export struct ChatToolInstallCard {
  @ObjectLink msg: ChatMessage;
  // 作答上行（ChatToolCard 透传 ChatPage → ChatSendCtrl.resolveBrowseConfirm，同确认链）
  onSubmit: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 正文字体两键 @StorageProp 自订阅 + 光感两能力位（四件套入参，同 ChatBrowseConfirmCard
  // 形制——订阅式与全仓消费点同形，零手写档位值）
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // specs 清单解析（记忆化：toolInputJson 串变才重算；坏 JSON / 缺 specs 回空数组走兜底行）
  private specsCacheJson: string = '';
  private specsCacheList: string[] = [];

  private specsList(): string[] {
    const inputJson: string = this.msg.toolInputJson ?? '';
    if (inputJson === this.specsCacheJson) {
      return this.specsCacheList;
    }
    const specs: string[] = [];
    try {
      const parsed = JSON.parse(inputJson) as Record<string, Object>;
      const raw: Object | undefined = parsed['specs'];
      if (Array.isArray(raw)) {
        const items: Object[] = raw as Object[];
        for (const item of items) {
          if (typeof item === 'string') {
            specs.push(item);
          }
        }
      }
    } catch (e) {
      // 坏 JSON = 空清单，卡面走兜底提示行
    }
    this.specsCacheJson = inputJson;
    this.specsCacheList = specs;
    return specs;
  }

  // 正文字体家族串（推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  // 风险块底色（同 ChatBrowseConfirmCard：危险红浅档 8% / 深档 14%）
  private riskFill(): string {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ?
      '#24E84026' : '#14E84026';
  }

  build() {
    Column({ space: 10 }) {
      // 主因句（预检产的说明串）
      Text(this.msg.toolConfirmText ?? '')
        .fontSize(14)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardTitleColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // 风险块（install 恒不可逆档，恒渲染——同 ChatBrowseConfirmCard 不可逆档文案与形制）
      Text('这个动作可能无法撤销，请确认后再允许。')
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor($r('app.color.dialog_confirm_red'))
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(this.riskFill())
      // 安装清单（逐条 name@version——卡面核对主体；空态兜底句，不渲染空区）
      if (this.specsList().length > 0) {
        Text('安装清单')
          .fontSize(11)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardTitleColor())
          .width('100%')
        // 键带序号：模型可能把同一个 spec 写两遍，键取 spec 原文会撞键（ArkUI 重复键行为未
        // 定义，卡面可能静默吞行）；清单纯展示、不随交互变化，序号入键零刷新代价
        ForEach(this.specsList().slice(0, INSTALL_CARD_MAX_LINES),
          (spec: string): void => {
            Text(spec)
              .fontSize(13)
              .fontFamily(this.resolveBodyFamily())
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }, (spec: string, index: number): string => index + ':' + spec)
        if (this.specsList().length > INSTALL_CARD_MAX_LINES) {
          Text('另有 ' + (this.specsList().length - INSTALL_CARD_MAX_LINES) + ' 条未显示。')
            .fontSize(12)
            .fontFamily(this.resolveBodyFamily())
            .fontColor(cardDescColor())
            .width('100%')
        }
      } else {
        Text('安装清单缺失或格式不正确，允许后也不会执行。')
          .fontSize(12)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
          .width('100%')
      }
      // 固定来源行（registry 由安装参数钉死集固定，用户与模型都不可选其他源）
      Text('来源 registry.npmjs.org')
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .width('100%')
      // 说明小字（先说明后操作——宪法布局次序）
      Text('允许一次只执行这一次。')
        .fontSize(12)
        .fontFamily(this.resolveBodyFamily())
        .fontColor(cardDescColor())
        .width('100%')
      // 双键主决策行（形制同 ChatBrowseConfirmCard：拒绝灰底次钮 / 允许一次主操作键，等宽
      // 高 40，8vp 专属例外同源；本卡无次级区）
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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 8 })
  }
}
