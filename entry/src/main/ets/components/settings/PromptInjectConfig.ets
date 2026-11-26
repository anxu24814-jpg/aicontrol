// 提示词注入配置域件（注入身份/位置/深度配置）。三行常显形态（决明拍板）：身份 / 位置 / 深度各一行，
// 左侧 13fp 灰标签、右侧官方分段胶囊（≤3 项纯文字走分段胶囊，见《规范-列表卡片与组卡》§4.13 分工判据）；
// 原「身份」「位置」两枚弹菜单功能键已退役。
// · 三行语义（与 RequestInject.composeSendMessages 一致，字段与保存链零改）：身份 = 系统 / 用户 / AI 回复；
//   位置 = 开头（系统提示位）/ 消息前（深度位）；深度 = 消息前第 N 条用户消息之前（0 = 最近一条；AI 回复
//   身份从 1 起，0 会注入成末条，Gemini 拒 + 跨模型不一致）。
// · 联动：身份 system → 位置恒「开头」、深度不适用（显示固定说明，不给可点控件）；身份 assistant →
//   深度只 1~4，切到消息前时深度 0 自动钳位 1。
// · 取值上行两回调（父页 @State 持有，保存链落库用）；本件只读 @Link 三值、改动经回调上行，回到父侧赋值
//   再经 @Link 回流——@Watch 只负责「父侧异步回填 → 本件分段下标」同步（坑16 家族：@Prop 首帧快照会让
//   编辑既有模板时仍显示缺省 system/head/0）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { SegmentBar } from '../SegmentBar';
import {
  SEGMENT_BAR_HEIGHT, cardBorderColor, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  INJECT_DEPTH_MAX, INJECT_POSITION_DEPTH, INJECT_POSITION_HEAD,
  INJECT_ROLE_ASSISTANT, INJECT_ROLE_SYSTEM, INJECT_ROLE_USER
} from '../../common/providers/RequestInject';

// 注入配置脏值钳位（模块级，回填/保存链共用——编辑页与知识条目页两处消费；默认值 = 现状注入行为）
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

// 分段下标 ↔ 域值（顺序契约：身份 0 系统 / 1 用户 / 2 AI 回复；位置 0 开头 / 1 消息前）
const ROLE_ORDER: string[] = [INJECT_ROLE_SYSTEM, INJECT_ROLE_USER, INJECT_ROLE_ASSISTANT];
const POSITION_ORDER: string[] = [INJECT_POSITION_HEAD, INJECT_POSITION_DEPTH];

function roleIndexOf(role: string): number {
  const i: number = ROLE_ORDER.indexOf(sanitizeInjectRole(role));
  return i < 0 ? 0 : i;
}

function positionIndexOf(position: string): number {
  return sanitizeInjectPosition(position) === INJECT_POSITION_DEPTH ? 1 : 0;
}

// 深度下标：非 AI 回复身份 0~4 五档；AI 回复身份 1~4 四档（域值 1 对应下标 0）
function depthIndexOf(depth: number, assistant: boolean): number {
  const d: number = sanitizeInjectDepth(depth);
  if (assistant) {
    return (d < 1 ? 1 : d) - 1;
  }
  return d;
}

@Component
export struct PromptInjectConfig {
  // 当前配置（父页 @State 持有；本件只读，改动经回调上行）。@Link 非 @Prop：本件挂 PageShell.content
  //（@BuilderParam）内，@Prop 下发 = 坑16 家族首帧快照——异步回填在首帧后到达不达 UI。@Watch =
  // 父侧回填时把分段下标同步回来
  @Link @Watch('onRoleLinkChanged') role: string;
  // 命名避坑：不能叫 position——CustomComponent 基类通用属性 position() 冲突（编译 10505001 实锤）
  @Link @Watch('onPositionLinkChanged') injectPosition: string;
  @Link @Watch('onDepthLinkChanged') depth: number;
  // 深浅色（行间 hairline 取 cardBorderColor；@StorageProp 订阅，切换即刷）
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 上行回调（父页覆写 @State 三字段）
  onRoleChanged: (role: string) => void = (): void => {
  };
  onPositionChanged: (position: string, depth: number) => void = (): void => {
  };
  // 分段下标（@State + @Watch：下标被点按改动 → 上行回调；父侧三值改动 → link watch 回灌）
  @State @Watch('onRoleIndexChanged') roleIndex: number = 0;
  @State @Watch('onPositionIndexChanged') positionIndex: number = 0;
  @State @Watch('onDepthIndexChanged') depthIndex: number = 0;
  // 分段选项（普通成员：选项集在页面生命周期内不变；深度两套按身份择一）
  private roleItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '系统' },
    { text: '用户' },
    { text: 'AI 回复' }
  ]);
  private positionItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '开头' },
    { text: '消息前' }
  ]);
  private depthItemsAll: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '0' }, { text: '1' }, { text: '2' }, { text: '3' }, { text: '4' }
  ]);
  private depthItemsAssistant: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '1' }, { text: '2' }, { text: '3' }, { text: '4' }
  ]);

  private onRoleLinkChanged(): void {
    this.roleIndex = roleIndexOf(this.role);
    this.positionIndex = positionIndexOf(this.injectPosition);
    this.depthIndex = depthIndexOf(this.depth, this.role === INJECT_ROLE_ASSISTANT);
  }

  private onPositionLinkChanged(): void {
    this.positionIndex = positionIndexOf(this.injectPosition);
    this.depthIndex = depthIndexOf(this.depth, this.role === INJECT_ROLE_ASSISTANT);
  }

  private onDepthLinkChanged(): void {
    this.depthIndex = depthIndexOf(this.depth, this.role === INJECT_ROLE_ASSISTANT);
  }

  private onRoleIndexChanged(): void {
    const next: string = ROLE_ORDER[this.roleIndex] ?? INJECT_ROLE_SYSTEM;
    if (next !== this.role) {
      this.onRoleChanged(next);
    }
  }

  private onPositionIndexChanged(): void {
    const next: string = POSITION_ORDER[this.positionIndex] ?? INJECT_POSITION_HEAD;
    const d: number = next === INJECT_POSITION_HEAD ? 0 : this.depthValue();
    if (next !== this.injectPosition || d !== this.depth) {
      this.onPositionChanged(next, d);
    }
  }

  private onDepthIndexChanged(): void {
    if (this.injectPosition !== INJECT_POSITION_DEPTH) {
      return;
    }
    const d: number = this.depthValue();
    if (d !== this.depth) {
      this.onPositionChanged(INJECT_POSITION_DEPTH, d);
    }
  }

  // 下标 → 域深度（AI 回复身份从 1 起）
  private depthValue(): number {
    const base: number = this.role === INJECT_ROLE_ASSISTANT ? 1 : 0;
    const v: number = base + this.depthIndex;
    return v > INJECT_DEPTH_MAX ? INJECT_DEPTH_MAX : v;
  }

  // 联动说明（三态分支：系统固定 / 消息前可调 / 非消息前不适用）
  private hintText(): string {
    if (this.role === INJECT_ROLE_SYSTEM) {
      return '系统身份固定注入系统提示位，不调深度。';
    }
    if (this.injectPosition !== INJECT_POSITION_DEPTH) {
      return this.role === INJECT_ROLE_ASSISTANT ?
        'AI 回复身份当前从开头注入。改为消息前可按深度 1~4 注入，部分模型会按 prefill 续写。' :
        '用户身份当前从开头注入。改为消息前可紧邻目标用户消息。';
    }
    return this.role === INJECT_ROLE_ASSISTANT ?
      'AI 回复身份按深度注入，深度 1 表示最近一条用户消息之前。部分模型会按 prefill 续写。' :
      '按深度注入。深度 0 表示最近一条用户消息之前，数字越大越靠前。';
  }

  build() {
    // 三行统一 40 行高（迁就最高的分段胶囊），行间 0.5vp hairline——纯文字分支不掉行高，标签列与内容列同网格
    Column() {
      Row({ space: 10 }) {
        Text('身份')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(64)
        Column() {
          SegmentBar({ items: this.roleItems, selectedIndex: $roleIndex })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height(SEGMENT_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(0.5)
        .color(cardBorderColor(this.appColorMode))
        .margin({ top: 6, bottom: 6 })

      // 位置（系统身份固定开头，不给可点控件——避免点了不生效）
      Row({ space: 10 }) {
        Text('位置')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(64)
        if (this.role === INJECT_ROLE_SYSTEM) {
          Text('系统提示位')
            .fontSize(13)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
        } else {
          Column() {
            SegmentBar({ items: this.positionItems, selectedIndex: $positionIndex })
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height(SEGMENT_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(0.5)
        .color(cardBorderColor(this.appColorMode))
        .margin({ top: 6, bottom: 6 })

      Row({ space: 10 }) {
        Text('深度')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(64)
        if (this.role !== INJECT_ROLE_SYSTEM && this.injectPosition === INJECT_POSITION_DEPTH) {
          Column() {
            SegmentBar({
              items: this.role === INJECT_ROLE_ASSISTANT ? this.depthItemsAssistant : this.depthItemsAll,
              selectedIndex: $depthIndex
            })
          }
          .layoutWeight(1)
        } else {
          Text(this.role === INJECT_ROLE_SYSTEM ? '系统身份不调深度' : '位置为开头时不调深度')
            .fontSize(13)
            .fontColor(cardDescColor())
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height(SEGMENT_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Text(this.hintText())
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
        .margin({ top: 10 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
