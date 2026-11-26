// 自动重试设置三级页（偏好 → 输入与发送 →「自动重试」入口的落点页）：总开关（@StorageLink 直写
// PREF_AUTO_RETRY_KEY 旧键——与控制台助手设键路径单一真源）+ 重试参数四数字行（最大次数 / 首次等待 /
// 退避倍率 / 等待上限，编辑键弹数字输入弹窗，确认即提交、显示行回读格式化）+ 重试状态码 chips +
// 重试 / 停止关键字两词表 chips（可恢复默认）+ 页首说明（仅零产出才自动重试 + 密钥类错误优先走换钥）。
// 写即持久化（经 AppPreferencesRetry 落 JSON 键 prefAutoRetryCfg，@StorageLink 直连即重渲）；无保存动作 →
// 返回无参 pop 不挂 onPop（坑17 口径）。自包 PageShell，无标题栏菜单键。形制照 HttpRequestSettingsPage：
// 卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS；说明小字在操作区上方（宪法「功能设置
// 卡布局次序」条）；chips = 官方胶囊（Capsule + 淡蓝底 fallbackBlueBg + 原生按压，不接光感）；编辑键 = 行内
// 图标键 TEXTUAL 无底；添加 / 恢复默认 = 行内文字键四件套。
// ★ 各卡自持展开而不抽共享值参 @Builder——「值参 @Builder 承载热点」是坑16 家族禁用形态（规范 §2 黑名单）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, fallbackBlueBg, selectChipTextColor, CARD_RADIUS
} from '../../common/Theme';
import { PREF_AUTO_RETRY_KEY } from '../../common/AppPreferences';
import { AutoRetryCfg, autoRetryDefaultCfg, AUTO_RETRY_DELAY_CAP_MS_MAX, AUTO_RETRY_DELAY_CAP_MS_MIN,
  AUTO_RETRY_INITIAL_MS_MAX, AUTO_RETRY_INITIAL_MS_MIN, AUTO_RETRY_MAX_RETRIES_MAX,
  AUTO_RETRY_MAX_RETRIES_MIN, AUTO_RETRY_MULTIPLIER_MAX, AUTO_RETRY_MULTIPLIER_MIN,
  AUTO_RETRY_STATUS_MAX, AUTO_RETRY_STATUS_MIN, AUTO_RETRY_STATUS_MAX_COUNT,
  AUTO_RETRY_WORDS_MAX_COUNT, AUTO_RETRY_WORD_MAX_CHARS, parseAutoRetryCfg,
  PREF_AUTO_RETRY_CFG_KEY, setAutoRetryNumbers, setAutoRetryRetryKeywords,
  setAutoRetryStatusCodes, setAutoRetryStopKeywords } from '../../common/AppPreferencesRetry';
import { SETTING_TITLE_AUTO_RETRY } from '../../common/SettingSearch';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial } from '../../common/ImmersiveLevel';
import { InputDialog } from '../chat/InputDialog';
import { InfoHintButton } from '../InfoHintButton';
import { InfoCard } from '../InfoCard';

// 数字行与编辑弹窗的四字段判别（字面量单源——页面内三处消费：弹窗初值 / 占位提示 / 提交回写）
const NUM_FIELD_MAX: string = 'max';
const NUM_FIELD_INITIAL: string = 'initial';
const NUM_FIELD_MULTIPLIER: string = 'multiplier';
const NUM_FIELD_CAP: string = 'cap';
const ADD_KIND_STATUS: string = 'status';
const ADD_KIND_RETRY: string = 'retry';
const ADD_KIND_STOP: string = 'stop';

@Component
export struct AutoRetrySettingsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 总开关（承接旧布尔语义：写 PREF_AUTO_RETRY_KEY 旧键——总开关、控制台助手设键、回退通道共用一源；JSON 键只判参数不判开关）
  @StorageLink(PREF_AUTO_RETRY_KEY) autoRetry: boolean = true;
  // 参数配置 JSON 键直连（写侧经 AppPreferencesRetry 封装落键后随键重渲——条目清单经 parseAutoRetryCfg 派生即渲染依赖）
  @StorageLink(PREF_AUTO_RETRY_CFG_KEY) cfgJson: string = '';
  // 编辑弹窗控制器（坑7：须组件成员位构造，弹一次 new 一次——PrefInputSendPage 两阈值弹窗同款）
  private numberEditCtrl: CustomDialogController | null = null;
  private addCtrl: CustomDialogController | null = null;

  // 生效配置（build 内派生——读状态变量即建立渲染依赖）
  private cfg(): AutoRetryCfg {
    return parseAutoRetryCfg(this.cfgJson);
  }

  // 数字行显示格式化（提交后经解析派生回显）
  private formatCount(v: number): string {
    return v + ' 次';
  }

  private formatMs(v: number): string {
    return v + ' 毫秒';
  }

  private formatMultiplier(v: number): string {
    return '× ' + v;
  }

  // ── 数字编辑弹窗（四行各按字段构造；初值预填当前生效值，提交经域校验后整组回写）──
  private openNumberEdit(field: string): void {
    const c: AutoRetryCfg = this.cfg();
    let title: string = '';
    let initialText: string = '';
    let placeholder: string = '';
    if (field === NUM_FIELD_MAX) {
      title = '最大重试次数';
      initialText = String(c.maxRetries);
      placeholder = AUTO_RETRY_MAX_RETRIES_MIN + '~' + AUTO_RETRY_MAX_RETRIES_MAX + ' 的整数';
    } else if (field === NUM_FIELD_INITIAL) {
      title = '首次等待';
      initialText = String(c.initialDelayMs);
      placeholder = AUTO_RETRY_INITIAL_MS_MIN + '~' + AUTO_RETRY_INITIAL_MS_MAX + ' 的整数';
    } else if (field === NUM_FIELD_MULTIPLIER) {
      title = '退避倍率';
      initialText = String(c.multiplier);
      placeholder = AUTO_RETRY_MULTIPLIER_MIN + '~' + AUTO_RETRY_MULTIPLIER_MAX + ' 之间的数字';
    } else {
      title = '等待上限';
      initialText = String(c.maxDelayMs);
      placeholder = AUTO_RETRY_DELAY_CAP_MS_MIN + '~' + AUTO_RETRY_DELAY_CAP_MS_MAX + ' 的整数';
    }
    this.numberEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: title,
        initialText: initialText,
        placeholder: placeholder,
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyNumberInput(field, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.numberEditCtrl.open();
  }

  // 数字提交（整数三字段严格整数校验；倍率允许小数；合法才整组回写——未改字段传现值）
  private applyNumberInput(field: string, text: string): void {
    const c: AutoRetryCfg = this.cfg();
    if (field === NUM_FIELD_MULTIPLIER) {
      const v: number = Number(text.trim());
      if (!Number.isFinite(v) || String(v) !== text.trim() ||
        v < AUTO_RETRY_MULTIPLIER_MIN || v > AUTO_RETRY_MULTIPLIER_MAX) {
        this.toastNumberRange(field);
        return;
      }
      setAutoRetryNumbers(c.maxRetries, c.initialDelayMs, v, c.maxDelayMs);
      return;
    }
    const v: number = parseInt(text, 10);
    let rangeOk: boolean = false;
    if (field === NUM_FIELD_MAX) {
      rangeOk = v >= AUTO_RETRY_MAX_RETRIES_MIN && v <= AUTO_RETRY_MAX_RETRIES_MAX;
    } else if (field === NUM_FIELD_INITIAL) {
      rangeOk = v >= AUTO_RETRY_INITIAL_MS_MIN && v <= AUTO_RETRY_INITIAL_MS_MAX;
    } else {
      rangeOk = v >= AUTO_RETRY_DELAY_CAP_MS_MIN && v <= AUTO_RETRY_DELAY_CAP_MS_MAX;
    }
    if (!Number.isFinite(v) || String(v) !== text.trim() || !rangeOk) {
      this.toastNumberRange(field);
      return;
    }
    if (field === NUM_FIELD_MAX) {
      setAutoRetryNumbers(v, c.initialDelayMs, c.multiplier, c.maxDelayMs);
    } else if (field === NUM_FIELD_INITIAL) {
      setAutoRetryNumbers(c.maxRetries, v, c.multiplier, c.maxDelayMs);
    } else {
      setAutoRetryNumbers(c.maxRetries, c.initialDelayMs, c.multiplier, v);
    }
  }

  private toastNumberRange(field: string): void {
    let hint: string = '';
    if (field === NUM_FIELD_MAX) {
      hint = '请输入 ' + AUTO_RETRY_MAX_RETRIES_MIN + '~' + AUTO_RETRY_MAX_RETRIES_MAX + ' 的整数';
    } else if (field === NUM_FIELD_INITIAL) {
      hint = '请输入 ' + AUTO_RETRY_INITIAL_MS_MIN + '~' + AUTO_RETRY_INITIAL_MS_MAX + ' 的整数';
    } else if (field === NUM_FIELD_MULTIPLIER) {
      hint = '请输入 ' + AUTO_RETRY_MULTIPLIER_MIN + '~' + AUTO_RETRY_MULTIPLIER_MAX + ' 之间的数字';
    } else {
      hint = '请输入 ' + AUTO_RETRY_DELAY_CAP_MS_MIN + '~' + AUTO_RETRY_DELAY_CAP_MS_MAX + ' 的整数';
    }
    this.getUIContext().getPromptAction().showToast({ message: hint });
  }

  // ── 清单添加弹窗（状态码 / 重试关键字 / 停止关键字三路共用一构造）──
  private openAdd(kind: string): void {
    let title: string = '';
    let placeholder: string = '';
    if (kind === ADD_KIND_STATUS) {
      title = '添加状态码';
      placeholder = '例如 503';
    } else if (kind === ADD_KIND_RETRY) {
      title = '添加重试关键字';
      placeholder = '例如 繁忙';
    } else {
      title = '添加停止关键字';
      placeholder = '例如 欠费';
    }
    this.addCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: title,
        placeholder: placeholder,
        confirmLabel: '添加',
        number: kind === ADD_KIND_STATUS,
        onConfirm: (text: string): void => {
          this.applyAdd(kind, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.addCtrl.open();
  }

  // 清单提交（状态码验 100~599 整数去重；词验非空限长去重——同词大小写不同算重复）
  private applyAdd(kind: string, text: string): void {
    const c: AutoRetryCfg = this.cfg();
    if (kind === ADD_KIND_STATUS) {
      const v: number = parseInt(text, 10);
      if (!Number.isFinite(v) || String(v) !== text.trim() ||
        v < AUTO_RETRY_STATUS_MIN || v > AUTO_RETRY_STATUS_MAX) {
        this.getUIContext().getPromptAction().showToast({
          message: '请输入 ' + AUTO_RETRY_STATUS_MIN + '~' + AUTO_RETRY_STATUS_MAX + ' 的整数'
        });
        return;
      }
      if (c.retryStatusCodes.includes(v)) {
        this.toastAlreadyIn();
        return;
      }
      if (c.retryStatusCodes.length >= AUTO_RETRY_STATUS_MAX_COUNT) {
        this.toastListFull(AUTO_RETRY_STATUS_MAX_COUNT);
        return;
      }
      setAutoRetryStatusCodes(c.retryStatusCodes.concat([v]));
      return;
    }
    const word: string = text.trim();
    if (word === '' || word.length > AUTO_RETRY_WORD_MAX_CHARS) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 1~' + AUTO_RETRY_WORD_MAX_CHARS + ' 个字符的关键字'
      });
      return;
    }
    const lower: string = word.toLowerCase();
    const target: string[] = kind === ADD_KIND_RETRY ? c.retryKeywords : c.stopKeywords;
    const dup: boolean = target.some((w: string): boolean => w.toLowerCase() === lower);
    if (dup) {
      this.toastAlreadyIn();
      return;
    }
    if (target.length >= AUTO_RETRY_WORDS_MAX_COUNT) {
      this.toastListFull(AUTO_RETRY_WORDS_MAX_COUNT);
      return;
    }
    if (kind === ADD_KIND_RETRY) {
      setAutoRetryRetryKeywords(c.retryKeywords.concat([word]));
    } else {
      setAutoRetryStopKeywords(c.stopKeywords.concat([word]));
    }
  }

  // 删单条（点 chip 即删——chips 自带即时反馈，清单可随时再添）
  private removeStatus(code: number): void {
    const c: AutoRetryCfg = this.cfg();
    setAutoRetryStatusCodes(c.retryStatusCodes.filter((v: number): boolean => v !== code));
  }

  private removeWord(kind: string, word: string): void {
    const c: AutoRetryCfg = this.cfg();
    if (kind === ADD_KIND_RETRY) {
      setAutoRetryRetryKeywords(c.retryKeywords.filter((w: string): boolean => w !== word));
    } else {
      setAutoRetryStopKeywords(c.stopKeywords.filter((w: string): boolean => w !== word));
    }
  }

  private toastAlreadyIn(): void {
    this.getUIContext().getPromptAction().showToast({ message: '已经在列表中' });
  }

  private toastListFull(max: number): void {
    this.getUIContext().getPromptAction().showToast({ message: '列表已满，最多 ' + max + ' 条' });
  }

  build() {
    PageShell({
      title: SETTING_TITLE_AUTO_RETRY,
      content: (): void => {
        this.Content()
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 页首 info（决明「info 放首卡」：先说明后操作；InfoCard 单源件）——零行为拦截的防呆说明：密钥类错误优先走换钥，不走这里的重试
        InfoCard({ text: '自动重试只在本轮还没有显示出任何内容时进行，已经显示出内容的回复中断不自动重发。' +
          '密钥类错误优先由密钥池换钥处理，不走这里的重试。参数调整在下一条消息发送时生效。' })
        // 总开关卡（开关写旧布尔键；形制照 PrefInputSendPage 粘贴设置卡：标题行 + ⓘ → 说明小字与开关同行）
        Column({ space: 12 }) {
          Row() {
            Text(SETTING_TITLE_AUTO_RETRY)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            InfoHintButton({
              text: '覆盖网络异常、服务端临时故障，以及失败提示带有限流、繁忙、稍后再试一类临时字样的失败。' +
                '余额不足等确定性失败不会自动重发。开关与参数都在下一条消息发送时生效。'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row({ space: 12 }) {
            Text('请求失败且本轮还没有任何内容时自动重发。关闭后不自动重发，可手动点底栏的重试键。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoRetry })
              .onChange((isOn: boolean): void => {
                this.autoRetry = isOn;
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
        // 重试参数卡（四数字行；说明小字在数字行上方——宪法布局次序条）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text('重试参数')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('每次重试前的等待逐次变长。第一次按首次等待，之后乘以退避倍率，最长不超过等待上限。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Row() {
            Text('最大重试次数')
              .fontSize(13)
              .fontColor(cardDescColor())
            Blank()
            Text(this.formatCount(this.cfg().maxRetries))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openNumberEdit(NUM_FIELD_MAX);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row() {
            Text('首次等待')
              .fontSize(13)
              .fontColor(cardDescColor())
            Blank()
            Text(this.formatMs(this.cfg().initialDelayMs))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openNumberEdit(NUM_FIELD_INITIAL);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row() {
            Text('退避倍率')
              .fontSize(13)
              .fontColor(cardDescColor())
            Blank()
            Text(this.formatMultiplier(this.cfg().multiplier))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openNumberEdit(NUM_FIELD_MULTIPLIER);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row() {
            Text('等待上限')
              .fontSize(13)
              .fontColor(cardDescColor())
            Blank()
            Text(this.formatMs(this.cfg().maxDelayMs))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openNumberEdit(NUM_FIELD_CAP);
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
        // 重试状态码卡（chips = 官方胶囊 + 淡蓝底 + 原生按压，不接光感；点 chip 删除）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text('重试状态码')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('命中这些状态码的失败会自动重发。网络异常不需要状态码，始终在自动重试范围内。点状态码可删除。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          if (this.cfg().retryStatusCodes.length === 0) {
            Text('列表为空。只有网络异常会自动重试。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.cfg().retryStatusCodes, (code: number) => {
              Button(String(code))
                .type(ButtonType.Capsule)
                .fontSize(13)
                .fontColor(selectChipTextColor(false, this.appColorMode))
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor(fallbackBlueBg(this.appColorMode))
                .margin({ right: 8, bottom: 8 })
                .onClick((): void => {
                  this.removeStatus(code);
                })
            }, (code: number): string => 'status-' + code)
          }
          .width('100%')
          Button('添加状态码')
            .fontSize(15)
            .fontColor(fallbackButtonFontTinted(this.contentFallback))
            .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
            .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .onClick((): void => {
              this.openAdd(ADD_KIND_STATUS);
            })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // 重试关键字卡（chips 同上；恢复默认 = 词表回内置清单）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text('重试关键字')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('失败提示里出现这些词时自动重发，即使状态码不在上面的清单。点关键字可删除。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          if (this.cfg().retryKeywords.length === 0) {
            Text('列表为空。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.cfg().retryKeywords, (word: string) => {
              Button(word)
                .type(ButtonType.Capsule)
                .fontSize(13)
                .fontColor(selectChipTextColor(false, this.appColorMode))
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor(fallbackBlueBg(this.appColorMode))
                .margin({ right: 8, bottom: 8 })
                .onClick((): void => {
                  this.removeWord(ADD_KIND_RETRY, word);
                })
            }, (word: string): string => 'retry-' + word)
          }
          .width('100%')
          Row({ space: 12 }) {
            Button('添加重试关键字')
              .fontSize(15)
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.openAdd(ADD_KIND_RETRY);
              })
            Button('恢复默认')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                setAutoRetryRetryKeywords(autoRetryDefaultCfg().retryKeywords);
              })
          }
          .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // 停止关键字卡（同重试关键字卡形制；停止词优先于重试词判）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text('停止关键字')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('失败提示里出现这些词时不自动重发。停止关键字优先于重试关键字。点关键字可删除。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          if (this.cfg().stopKeywords.length === 0) {
            Text('列表为空。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.cfg().stopKeywords, (word: string) => {
              Button(word)
                .type(ButtonType.Capsule)
                .fontSize(13)
                .fontColor(selectChipTextColor(false, this.appColorMode))
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor(fallbackBlueBg(this.appColorMode))
                .margin({ right: 8, bottom: 8 })
                .onClick((): void => {
                  this.removeWord(ADD_KIND_STOP, word);
                })
            }, (word: string): string => 'stop-' + word)
          }
          .width('100%')
          Row({ space: 12 }) {
            Button('添加停止关键字')
              .fontSize(15)
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.openAdd(ADD_KIND_STOP);
              })
            Button('恢复默认')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                setAutoRetryStopKeywords(autoRetryDefaultCfg().stopKeywords);
              })
          }
          .width('100%')
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
  }
}
