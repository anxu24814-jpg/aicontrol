// Python 运行验证页（2026-11-06 鸿蒙Python运行时门1笔，任务书 U4-4）：门 1 临时验证面——
// 初始化内嵌解释器 + 固定诊断脚本回显，验证通过前不接任何正式功能链（工具调用、设置搜索
// 注册表都不进——门 4/5 的事）。入口 = 构建 PY_PROBE_ENABLED 开关门控（默认 false 零渲染，
// 照 BrowseWeb.BROWSE_DEBUG 族先例；翻 true 时工具调用页列表尾出临时入口）。
// 自包 PageShell 壳；无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
// 版本串原文照显（Py_GetVersion 返回值含括号与编译器串——技术内容，不受文案规约约束）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../common/PageShell';
import { codeFontFamilyNow } from '../common/ChatFont';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../common/ImmersiveLevel';
import { cancelPyRun, ensurePyRuntime, execPyCode, initPyRuntime,
  PY_PROBE_SCRIPT, PY_PROBE_SCRIPT_LONG, PY_PROBE_SCRIPT_PDF, PY_PROBE_SCRIPT_RUST,
  PY_PROBE_TITLE } from '../common/pyexec/PyRuntime';

// 诊断脚本执行超时上限（60s——stdlib zip 直读首跑含解冻路径，余量按 2 倍常规耗时设）
const PY_PROBE_TIMEOUT_MS: number = 60000;
// 长时脚本超时上限（8s < 脚本总时长约 10s——放任到点验 TimeoutError；中途点取消验 Canceled）
const PY_PROBE_LONG_TIMEOUT_MS: number = 8000;
// 输出区高度上限（固定数值——宪法「渲染克制」条：宽高不需自适应时明确指定）
const PY_PROBE_OUTPUT_HEIGHT: number = 320;

@Component
export struct PyRuntimeProbePage {
  // 页面存活守卫（1712 纪律，照 AssistantMcpPage 先例）：置位后迟到异步回调不写状态、
  // 不碰 UI；promise 本身照常 resolve 不吞，仅放弃 UI 写与提示
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 初始化状态行（版本串与耗时回显；失败时为中文错误句）
  @State initStatusText: string = '未初始化';
  // 诊断运行状态行
  @State runStatusText: string = '未运行';
  // 输出区文本（stdout 与 stderr 拼合回显，等宽字）
  @State outputText: string = '';
  // 在跑标志（初始化与运行期间禁重复触发键）
  @State initBusy: boolean = false;
  @State runBusy: boolean = false;
  // 自定义脚本草稿（默认给设置变量示例——验证重启内存态的两步法见卡内说明小字）
  @State customScript: string = 'x = 41\nprint(\'set x to\', x + 1)';

  // 初始化：stdlib 落位（幂等）→ native init（幂等）→ 状态行回显版本串与耗时
  private doInit(): void {
    if (this.initBusy) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.initStatusText = '初始化失败，应用上下文不可用';
      return;
    }
    this.initBusy = true;
    this.initStatusText = '初始化中';
    ensurePyRuntime(ctx).then((homeDir: string): Promise<void> => {
      if (this.departed) {
        return Promise.resolve();
      }
      return initPyRuntime(homeDir).then((outcome): void => {
        if (this.departed) {
          return;
        }
        if (outcome.ok) {
          this.initStatusText = outcome.version + '，耗时 ' + outcome.elapsedMs + ' ms';
        } else {
          this.initStatusText = '初始化失败，' + outcome.error;
        }
      });
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.initStatusText = '初始化失败，' + e.message;
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.initBusy = false;
    });
  }

  // 运行脚本（参数化：诊断 = 秒完成固定脚本；长脚本 ≈10s 循环验取消与超时两项）
  // → stdout/stderr 拼合回显（两键共用 runBusy 互斥——Python 全局串行，后发排队而非并发）
  private doRun(script: string, timeoutMs: number): void {
    if (this.runBusy) {
      return;
    }
    this.runBusy = true;
    this.runStatusText = '运行中';
    this.outputText = '';
    execPyCode(script, timeoutMs).then((outcome): void => {
      if (this.departed) {
        return;
      }
      this.runStatusText = (outcome.ok ? '完成' : '失败') + '，耗时 ' + outcome.elapsedMs + ' ms' +
        (outcome.error !== '' ? '，' + outcome.error : '');
      const parts: string[] = [];
      if (outcome.stdout !== '') {
        parts.push(outcome.stdout);
      }
      if (outcome.stderr !== '') {
        parts.push(outcome.stderr);
      }
      this.outputText = parts.join('\n');
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.runStatusText = '失败，' + e.message;
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.runBusy = false;
    });
  }

  private doCancel(): void {
    cancelPyRun();
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 初始化卡——说明小字在操作行上方（宪法「功能设置卡布局次序」条）
        Column({ space: 10 }) {
          Text('初始化')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('首次使用会把内置标准库释放到应用私有目录，已在场则直接复用。重复点击无副作用。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Text(this.initStatusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .fontFamily(codeFontFamilyNow())
            .width('100%')
          Button('初始化')
            .fontSize(15)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.initBusy)
            .onClick((): void => {
              this.doInit();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 诊断卡——双键行 + 输出区
        Column({ space: 10 }) {
          Text('运行诊断')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('固定脚本依次验证解释器版本、平台、数学计算、zlib 压缩与 JSON 编解码。跑长脚本约十秒，中途点取消验证协作式中断，放任到八秒上限验证超时。取消为协作式，脚本停在原生调用中时不能立即生效。本页为门 1 验证用临时面。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Text(this.runStatusText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Row({ space: 12 }) {
            Button('运行诊断')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.runBusy)
              .onClick((): void => {
                this.doRun(PY_PROBE_SCRIPT, PY_PROBE_TIMEOUT_MS);
              })
            Button('跑长脚本')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.runBusy)
              .onClick((): void => {
                this.doRun(PY_PROBE_SCRIPT_LONG, PY_PROBE_LONG_TIMEOUT_MS);
              })
            Button('取消')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .onClick((): void => {
                this.doCancel();
              })
          }
          .width('100%')
          // 输出区（可滚动等宽字回显——滚动容器显式 .scrollBar(BarState.Off) 宪法条款）
          Scroll() {
            Column() {
              Text(this.outputText === '' ? '暂无输出' : this.outputText)
                .fontSize(12)
                .fontFamily(codeFontFamilyNow())
                .fontColor(cardDescColor())
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height(PY_PROBE_OUTPUT_HEIGHT)
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollBar(BarState.Off)
          .padding(8)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 门 3 验证卡（2132 补——两段判据固定成键，免手输抄错；输出走同一输出区回显）
        Column({ space: 10 }) {
          Text('门 3 验证')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('两段固定判据。Rust 三件期望输出 rust-trio OK 2026.9.1 2.50.4 50.0.2。pypdfium2 期望输出 pdfium OK pages 1。失败时看输出区末行的错误类型。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Row({ space: 12 }) {
            Button('验 Rust 三件')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.runBusy)
              .onClick((): void => {
                this.doRun(PY_PROBE_SCRIPT_RUST, PY_PROBE_TIMEOUT_MS);
              })
            Button('验 pypdfium2')
              .fontSize(15)
              .fontColor(fallbackButtonFont(this.contentFallback, false))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .layoutWeight(1)
              .enabled(!this.runBusy)
              .onClick((): void => {
                this.doRun(PY_PROBE_SCRIPT_PDF, PY_PROBE_TIMEOUT_MS);
              })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 自定义脚本卡——第 7 项重启内存态的触发面：两步法 = 先跑设置变量的脚本，杀掉
        // 应用重进后再跑读取同名变量的脚本，报 NameError 即符合预期（内存变量不跨重启）
        Column({ space: 10 }) {
          Text('自定义脚本')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('验证重启后的内存态。先跑设置变量的脚本，杀掉应用重进后把脚本改成读取同名变量再跑，报 NameError 即符合预期，变量不跨重启保留。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          TextArea({ text: this.customScript, placeholder: '例如 x = 41 加一行 print' })
            .fontSize(13)
            .fontFamily(codeFontFamilyNow())
            .fontColor(cardTitleColor())
            .height(120)
            .width('100%')
            .enabled(!this.runBusy)
            .onChange((v: string): void => {
              this.customScript = v;
            })
          Button('跑自定义')
            .fontSize(15)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.runBusy && this.customScript.trim() !== '')
            .onClick((): void => {
              this.doRun(this.customScript, PY_PROBE_TIMEOUT_MS);
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
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

  build() {
    PageShell({
      title: PY_PROBE_TITLE,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
