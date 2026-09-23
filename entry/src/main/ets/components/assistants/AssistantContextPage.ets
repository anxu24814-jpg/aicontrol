// 助手上下文与输出三级页（2026-09-01 高级设定，领导指令照参考图复刻）：编辑页「高级
// 设定」二级页「上下文与输出」行卡 push 进入，param = 助手 id。
// · 页面形态：PageShell 自包壳 + 灰底直放说明行「控制发送历史范围和单次回复长度」+
//   两张滑块卡——上下文消息数（0~100 step 1，0 = 不限制）/ 最大输出长度（0~131072
//   step 1024，0 = 不限制）。卡形制见 SliderValueCard（2026-09-09 迁出共用——上下文两卡
//   与工具轮上限卡三处同构；卡内 = 标题行〔标题 + 右侧蓝值 + square_and_pencil 编辑键弹
//   数字输入〕+ 官方 InSet 滑块 + 底部 12fp 灰说明）。
// · 发送语义（官方 API 文档查证 2026-09-01，细则见 RequestCompose/RequestInject 头注释）：
//   上下文消息数 = 应用层截取（发送序列保尾部 N 条含本条 user，注入前截——身份注入
//   永不丢，clipHistoryTail）；最大输出长度四协议方言落点 = openai chat max_tokens /
//   responses max_output_tokens / gemini maxOutputTokens / anthropic max_tokens
//   （未配置 8192 现状、显式 0 兜底 131072〔128K，说明文案照图〕、正数用值）。
// · 手动输入范围：2026-09-02 领导拍板对齐 CubeAgent 数值——上下文 0~1024 整数 / 输出
//   0~393216 整数（滑块与手动输入同上限，超出由服务商 400 自答走既有回显）。
// · 保存模式：无保存键——onBackPressed 统一落库（值对比 initial 判无改动 → 无参 pop；
//   有改动落库失败 toast 留页）→ pop({saved:true}) 刷二级页摘要。★ 保存恒写
//   contextCount/maxOutput 两键（0 也写——「进过上下文页保存」后 anthropic 的 0 走
//   131072 兜底而非 8192 现状；采样四键原样保留不经本页改动）。
// · ★ 2026-09-02 领导真机反馈修复（坑16 家族归正）：滑块卡 @Prop value/普通成员
//   valueText 居 PageShell.content（@BuilderParam）内不随父 @State 更新——拖动只动
//   滑杆内部态、右侧文案冻结，编辑弹窗改值滑块也不同步，观感「拖动条不生效只能靠
//   编辑键」。value 改 @Link 订阅式双向（onChange 直写回父 @State；编辑弹窗改 @State
//   同步进滑块进度），蓝值文案改 format 纯函数入参（读 @Link value 随刷）。采样页
//   SamplingToggleCard 同构同病同轮归正。2026-09-09 卡体迁 SliderValueCard 共用（@Link
//   契约随迁原样保留，本页零行为变化）。
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_CONTEXT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardDescColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import {
  AssistantAdvancedParams, parseAssistantAdvancedParams, serializeAssistantAdvancedParams
} from '../../common/providers/AiTypes';
import { queryAssistant, updateAssistantAdvancedParams } from '../../common/store/AssistantDb';
import { InputDialog } from '../chat/InputDialog';
import { SliderValueCard } from '../SliderValueCard';

// 滑块域常量（2026-09-02 领导拍板对齐 CubeAgent 数值：上下文消息数上限 1024 条 / 最大
// 输出长度上限 393216 tokens = 384K——两者均为滑块与手动输入共用上限；0 = 不限制语义
// 不变。手动输入上限随滑块同值——超出模型真实上限的值由服务商 400 自答，不再放宽）
const CONTEXT_SLIDER_MAX: number = 1024;
const OUTPUT_SLIDER_MAX: number = 393216;
const OUTPUT_SLIDER_STEP: number = 1024;
const CONTEXT_INPUT_MAX: number = 1024;
const OUTPUT_INPUT_MAX: number = 393216;

// 输出长度值文案（整 K 缩写：1024→1K / 65536→64K / 131072→128K；非整 K 原数字）。
// export 供二级页摘要复用（同域单一定义——P2-4 勿复制）
export function formatTokenText(v: number): string {
  if (v >= 1024 && v % 1024 === 0) {
    return (v / 1024) + 'K';
  }
  return String(v);
}

// 滑块卡（页内组件——两卡同构提取）：2026-09-09 迁出为共用 SliderValueCard（工具轮上限
// 卡第三处消费；@Link/format 契约与坑16 修复随迁原样，本页零行为变化）

@Component
export struct AssistantContextPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id，二级页传入）
  private rowId: string = '';
  // 两值编辑态（0 = 不限制；@State 驱动卡面重建）
  @State private contextCount: number = 0;
  @State private maxOutput: number = 0;
  // 采样四键（不经本页改动，保存时原样保留）
  private keepTemperature: number | undefined = undefined;
  private keepTopP: number | undefined = undefined;
  private keepPresence: number | undefined = undefined;
  private keepFrequency: number | undefined = undefined;
  // 进页时初值（无改动判定 = 值比较；undefined 视 0——键缺失与 0 对「不限制」等价）
  private initialContextCount: number = 0;
  private initialMaxOutput: number = 0;
  // 编辑键弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private contextEditCtrl: CustomDialogController | null = null;
  private outputEditCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条，ModelSettingsPage 同款姿势）：string id
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_CONTEXT_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        const parsed: AssistantAdvancedParams | null =
          parseAssistantAdvancedParams(row.advancedParams);
        if (parsed !== null) {
          this.contextCount = parsed.contextCount ?? 0;
          this.maxOutput = parsed.maxOutput ?? 0;
          this.keepTemperature = parsed.temperature;
          this.keepTopP = parsed.topP;
          this.keepPresence = parsed.presencePenalty;
          this.keepFrequency = parsed.frequencyPenalty;
          this.initialContextCount = this.contextCount;
          this.initialMaxOutput = this.maxOutput;
        }
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 右侧蓝值文案由父组件 format 纯函数渲染（0 = 不限制语义在 format 内），本页不再
  // 持有文案方法（2026-09-02 归正时随 valueText 入参一并移除）

  // 手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（滑块联动）
  private applyContextInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() || v < 0 || v > CONTEXT_INPUT_MAX) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 0~' + CONTEXT_INPUT_MAX + ' 的整数' });
      return;
    }
    this.contextCount = v;
  }

  private applyOutputInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() || v < 0 || v > OUTPUT_INPUT_MAX) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 0~' + OUTPUT_INPUT_MAX + ' 的整数' });
      return;
    }
    this.maxOutput = v;
  }

  // 编辑键弹窗（InputDialog 数字型——2026-09-01 加 number 参；初值预填当前值）
  private openContextEdit(): void {
    this.contextEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '上下文消息数',
        initialText: String(this.contextCount),
        placeholder: '0~1024，0 为不限制',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyContextInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.contextEditCtrl.open();
  }

  private openOutputEdit(): void {
    this.outputEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '最大输出长度',
        initialText: String(this.maxOutput),
        placeholder: '0~393216 tokens，0 为不限制',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyOutputInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.outputEditCtrl.open();
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明行（灰底直放不加卡——SystemPromptPage 说明行范式）
        Text('控制发送历史范围和单次回复长度')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
        SliderValueCard({
          title: '上下文消息数', value: $contextCount,
          min: 0, max: CONTEXT_SLIDER_MAX, step: 1,
          format: (v: number): string => v === 0 ? '不限制' : v + ' 条',
          desc: '限制发送给模型的历史消息数量，0 为不限制',
          onEdit: (): void => { this.openContextEdit(); }
        })
        SliderValueCard({
          title: '最大输出长度', value: $maxOutput,
          min: 0, max: OUTPUT_SLIDER_MAX, step: OUTPUT_SLIDER_STEP,
          format: (v: number): string => v === 0 ? '无限制' : formatTokenText(v),
          desc: '0 表示不限制（由模型按自身上限输出），Claude 等强制要求该字段的服务商会兜底为 128K。开启思考档位时，输出上限会自动抬到思考所需的最小值',
          onEdit: (): void => { this.openOutputEdit(); }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: '上下文与输出',
      // 右上角无菜单键（纯参数编辑页）
      onBackPressed: (): boolean => {
        // 无改动 = 值比较（含 undefined 归 0——键缺失与 0 对「不限制」等价）→ 无参 pop
        if (this.contextCount === this.initialContextCount &&
          this.maxOutput === this.initialMaxOutput) {
          this.pathStack.pop();
          return true;
        }
        // 有改动：采样四键原样保留 + 恒写两键（0 也写——「显式不限制」语义，anthropic
        // 走 131072 兜底）
        const next: AssistantAdvancedParams = {
          temperature: this.keepTemperature,
          topP: this.keepTopP,
          presencePenalty: this.keepPresence,
          frequencyPenalty: this.keepFrequency,
          contextCount: this.contextCount,
          maxOutput: this.maxOutput
        };
        updateAssistantAdvancedParams(this.rowId, serializeAssistantAdvancedParams(next))
          .then((): void => {
            this.pathStack.pop({ saved: true });
          })
          .catch((e: Object): void => {
            this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
          });
        return true; // 拦截返回——落库结果回调内再 pop（失败留页）
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
