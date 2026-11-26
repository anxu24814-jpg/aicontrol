// 模型上下文窗口卡（照 ModelCapsCard 域级拆分先例——本域自持卡壳与交互，状态归属 ModelEditPage）。
// 形态：标题行（「上下文窗口」+ 右上 ⓘ，k/m 简写说明收进气泡）→ 说明小字 → 值行（点击弹数字输入，支持 k
//   与 m 简写）→ 四枚快捷档 chips → 参考值行（勾 +「参考值 N」，无参考值灰字「暂无参考值」，右端「重置为默认」）。
// 契约：@Link value（用户覆盖值，0 = 未配置）+ @Link baseline（内置参考值，0 = 暂无）+ onCommit 回调上行真值。
// ★ 本卡不直写 value——改动经 onCommit 回父侧赋值、再经 @Link 回流（ModelCapsCard「@Link 只读 + 回调上行」
// 范式）；本卡挂 PageShell.content 内，**禁 @Prop 下发热点**（坑16 家族：两值均为异步回填，@Prop 会首帧冻结）。
// ★ 参考值不是「官方基准」：内置表两级取值——一级 = 已联网核实厂商官方文档，二级 = models.dev 第三方快照
//（一级核不到才用，表内标 [md]，出处见 ModelRegistry DEFS 行注释）；核不到显示「暂无参考值」，UI 文案禁用「官方」。
// ★ 窗口值无消费面（不接历史裁剪/用量占比/请求组装/费用估计），本卡只做配置与展示。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MAX_CONTEXT_INPUT, formatContextTokens, parseContextTokenInput } from '../../common/TokenEstimate';
import {
  CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor, selectChipBg,
  selectChipBorderColor, selectChipTextColor, CARD_RADIUS
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';
import { InputDialog } from '../chat/InputDialog';

// 快捷档一枚（标签 + 值；显式接口承载——ArkTS 禁无显式接口的对象字面量挂数组，坑59①）
export interface ContextQuickPick {
  label: string;
  value: number;
}

// 四枚快捷档（照参考图 256K / 500K / 1024K / 1M；值 = 标签 × 1024，与「k = 1024」口径同源）。
// ★ 1024K 与 1M 同值（1048576）为参考图原样保留——命中时两枚同时高亮，不特判不算错
export const CONTEXT_QUICK_PICKS: ContextQuickPick[] = [
  { label: '256K', value: 262144 },
  { label: '500K', value: 512000 },
  { label: '1024K', value: 1048576 },
  { label: '1M', value: 1048576 }
];

@Component
export struct ModelContextCard {
  // 用户覆盖值（0 = 未配置 = 跟随参考值；非 0 = 覆盖）。★ 本卡只读——写入一律经 onCommit
  @Link value: number;
  // 内置参考值（0 = 暂无参考值；由父侧 lookupContextBaseline 按模型名派生，不落库）
  @Link baseline: number;
  // 值变更上行（快捷档点击 / 输入确认 / 重置为默认三路同走本回调）
  onCommit: (v: number) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 输入弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private editCtrl: CustomDialogController | null = null;

  // 值行点击 → 官方数字型输入弹窗（number 参只控键盘；范围与格式校验在本卡 applyInput）
  private openEdit(): void {
    this.editCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '上下文窗口',
        initialText: this.value > 0 ? String(this.value) : '',
        placeholder: '例如 128k 或 1048576',
        confirmLabel: '确认',
        number: true,
        // allowEmpty = true：空串交本卡解析分支统一提示（带 k 与 m 的说明），不走弹窗的通用「内容不能为空」
        allowEmpty: true,
        onConfirm: (text: string): void => {
          this.applyInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.editCtrl.open();
  }

  // 输入落值（-1 = 非法或越界 → toast 不留值，P0-1 不静默）
  private applyInput(text: string): void {
    const parsed: number = parseContextTokenInput(text);
    if (parsed < 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 0 到 ' + MAX_CONTEXT_INPUT + ' 之间的 Token 数，支持 k 与 m 简写'
      });
      return;
    }
    this.onCommit(parsed);
  }

  build() {
    Column({ space: 10 }) {
      // 标题行（照能力卡标题档）+ 右上 ⓘ（k/m 简写说明收进气泡，卡面不再占一行）
      Row() {
        Text('上下文窗口')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({ text: '支持 k 与 m 简写，k 等于 1024，m 等于 1024 的平方' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 说明小字（置值行上方——宪法「功能设置卡布局次序」条：先说明后操作）
      Text('单次请求最多能容纳的 Token 数')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 值行：整行可点弹输入（左 = 当前值 / 右 = 单位）
      Row() {
        Text(this.value > 0 ? formatContextTokens(this.value) : '未配置')
          .fontSize(16)
          .fontColor(this.value > 0 ? cardTitleColor() : cardDescColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('Tokens')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(10)
      .backgroundColor(badgeBg(this.appColorMode))
      .onClick((): void => {
        this.openEdit();
      })
      // 快捷档 chips（紧贴值行下方；形态照能力卡：13fp / 圆角 14 / 未选淡蓝底蓝字、选中实底蓝白字）
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CONTEXT_QUICK_PICKS, (pick: ContextQuickPick) => {
          Text(pick.label)
            .fontSize(13)
            .fontColor(selectChipTextColor(this.value === pick.value, this.appColorMode))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(selectChipBg(this.value === pick.value, this.appColorMode))
            .border({ width: 1, color: selectChipBorderColor(this.value === pick.value) })
            .margin({ right: 8, bottom: 8 })
            .onClick((): void => {
              this.onCommit(pick.value);
            })
        }, (pick: ContextQuickPick): string => pick.label)
      }
      .width('100%')
      // 参考值行：命中 = 勾 + 「参考值 N」；未命中 = 灰字「暂无参考值」；右端恒在「重置为默认」。★ 勾色用官方
      // 强调色（系统色表无绿色资源，id_defined.json 全量核查无 green/success 族），自绘绿须像素实测——待决明看图后改色
      Row() {
        if (this.baseline > 0) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(16)
            .fontColor([$r('sys.color.ohos_id_color_emphasize')])
          Text('参考值 ' + formatContextTokens(this.baseline))
            .fontSize(13)
            .fontColor(cardDescColor())
            .margin({ left: 4 })
        } else {
          Text('暂无参考值')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        Blank()
        // 「重置为默认」= 纯 Text（照能力卡「重置」键形制：无胶囊遮罩、行高与标题一致）
        Text('重置为默认')
          .fontSize(13)
          .fontColor($r('sys.color.font_emphasize'))
          .onClick((): void => {
            this.onCommit(0);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
