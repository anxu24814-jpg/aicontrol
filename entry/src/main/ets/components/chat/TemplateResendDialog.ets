// 模板重发参数编辑对话框：参数字段随模板参数清单动态生成（零挂载风险）；形制照 InputDialog；
// 调用方动态构造（坑7 组件成员位约束，每次打开重建）。纯展示——params / initial 入、values
// 回调出，模板现查与执行编排全在 ChatPageContent / ChatToolResendCtrl。参数上限 6
// （HTTP_TEMPLATE_PARAMS_MAX），内容区滚动有界、对话框高度封顶防溢出屏。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { TemplateParam, positionLabel } from '../../common/providers/HttpTemplate';
import { cardDescColor, cardTitleColor } from '../../common/Theme';

// 参数行标签说明与输入框的间距（观感参数，与 InputDialog 输入框 margin top 16 同族）
const PARAM_ROW_GAP: number = 12;
// 内容区最大高度（vp——6 参数极限形态防对话框溢出屏，约 3.5 行参数可见、区内滚动）
const DIALOG_MAX_HEIGHT_VP: number = 420;

@CustomDialog
export struct TemplateResendDialog {
  // 官方 @CustomDialog 约定字段（关闭弹窗用；由外层 builder 注入，编译器此处免初始化）
  controller: CustomDialogController;
  title: string = '';
  // 模板显示名（副行说明）
  templateName: string = '';
  // 参数清单（现查模板行 parseTemplateParams 产物；构造时一次性传入）
  params: TemplateParam[] = [];
  // 预填值（卡上原 argsJson 解析——parseResendPrefill 产物；缺参给空串）
  initial: Record<string, string> = {};
  // 确认回调（values = 参数名 → 输入值；可省参数空串合法——「按空处理」语义由组装函数承接）
  onConfirm: (values: Record<string, string>) => void = (_values: Record<string, string>): void => {
  };
  // 各参数输入值（@State 数组；元素替换被观察——onChange 回写即刷新，键 = 参数名恒定）
  @State texts: string[] = [];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    const seed: string[] = [];
    for (const p of this.params) {
      const v: string | undefined = this.initial[p.name];
      seed.push(typeof v === 'string' ? v : '');
    }
    this.texts = seed;
  }

  // 确认键：必填参数空 = toast 点名保留弹窗可重输（P0-1 不静默）；就绪 = close + 回调
  // （组装与执行的报错面在执行链，弹窗只挡「必填缺失」这一本地可判形态）
  private confirm(): void {
    for (let i = 0; i < this.params.length; i++) {
      if (this.params[i].required && (this.texts[i] ?? '').trim() === '') {
        this.getUIContext().getPromptAction().showToast(
          { message: '请填写参数 ' + this.params[i].name });
        return;
      }
    }
    const values: Record<string, string> = {};
    for (let i = 0; i < this.params.length; i++) {
      values[this.params[i].name] = this.texts[i] ?? '';
    }
    this.controller.close();
    this.onConfirm(values);
  }

  // 参数行（位置中文名单源 positionLabel——与模型面 schema description 同一映射，禁第二份）
  @Builder
  ParamRow(param: TemplateParam, index: number) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(param.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (param.required) {
          Text('必填')
            .fontSize(11)
            .fontColor(cardDescColor())
        }
      }
      .width('100%')
      Text(positionLabel(param.position) + (param.desc !== '' ? '，' + param.desc : ''))
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      TextInput({ text: this.texts[index] ?? '', placeholder: '例如填 ' + param.name + ' 的值' })
        .fontSize(15)
        .onChange((value: string): void => {
          // @State 数组元素替换（被观察——坑80 家族正道：元素整体赋值非属性原地改）
          this.texts[index] = value;
        })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        // 副行：模板显示名
        Text(this.templateName)
          .fontSize(12)
          .fontColor(cardDescColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
        // 参数区（texts 随 aboutToAppear 播种后恒对齐 params）
        Column({ space: PARAM_ROW_GAP }) {
          ForEach(this.params, (param: TemplateParam, index: number): void => {
            this.ParamRow(param, index)
          }, (param: TemplateParam): string => param.name)
        }
        .width('100%')
        .margin({ top: 14 })
        // 按钮行：官方文字按钮半宽；确认动作 = 发起执行，文案用「发送」对齐动作语义
        Row({ space: 8 }) {
          Button('取消')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .layoutWeight(1)
            .onClick((): void => {
              this.controller.close();
            })
          Button('发送')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .layoutWeight(1)
            .onClick((): void => {
              this.confirm();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 20, bottom: 12 })
    }
    .width('100%')
    .constraintSize({ maxHeight: DIALOG_MAX_HEIGHT_VP })
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
