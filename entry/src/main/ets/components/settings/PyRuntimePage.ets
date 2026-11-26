// Python 运行环境管理页（2026-11-14 闲3门4批，母方案 = docs/方案-鸿蒙内置Python运行环境
// -20261106.md §2.6）：正式设置页——解释器状态回显 +「检查环境」键（首用落位 + 初始化，
// 均幂等，再点无副作用）+ 28 个预置包只读清单 + 卡三自装包管理。入口 = 工具调用页首组卡
//「Python 运行环境」行（push 无参，路由 ROUTE_PY_RUNTIME_PAGE）。
// 形制照同目录 CodeWorkbenchPages.ets 的 CodeWorkbenchPage（自包 PageShell 壳 + 卡壳四件套
// CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS）。★ 首卡「运行环境」2026-11-16 改固定
// 深色渐变（K3 第三处决明点名消费，形制 = NetworkSettingsPage 当前出口卡；「检查环境」键由全宽
// fallbackButton 收编为卡内文字动作行，状态句拆为「运行态 + 占用字节 + 失败摘要」三字段）——
// 卡二/卡三仍走四件套，卡三危险两键仍 fallbackButton 双态四件套。departed 守卫照
// pages/PyRuntimeProbePage.ets 先例（上下文显式取 getHostContext，与探针页同源同值）。
// 卡三「自装包」= 2026-11-15 闲4门5笔落地（门4笔原本不做）：白名单 9 件安装清单 / 清除
// 自装包 / 运行区重建，域逻辑单源 common/pyexec/PyPackages.ets（冻结表与安装状态机全在
// 该文件，本页只做用户面编排）。危险动作确认弹窗 = UIContext promptAction.showDialog
//（坑64 禁 showAlertDialog 槽内形态；ChatMoreMenu / ProviderDetailPage 同形制先例）。
// 无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
// 版本串原文照显（Py_GetVersion 返回值含括号与编译器串——技术内容，不受文案规约约束）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { codeFontFamilyNow } from '../../common/ChatFont';
import { cardBorderColor, CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor,
  CARD_RADIUS, HERO_CARD_ACTION_HEIGHT, HERO_CARD_BADGE_BG, HERO_CARD_BADGE_TEXT,
  HERO_CARD_COPY_MIN_HEIGHT, HERO_CARD_DANGER, HERO_CARD_DIVIDER, HERO_CARD_LABEL,
  HERO_CARD_SUCCESS, HERO_CARD_TEXT, HERO_CARD_TEXT_DIM, heroCardColors,
  heroCardMidColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { SETTING_TITLE_PY_RUNTIME } from '../../common/SettingSearch';
import { ensurePyRuntime, initPyRuntime, PY_PRESET_PACKAGES,
  pyRuntimePlaced, pyRuntimeUsageBytesAsync } from '../../common/pyexec/PyRuntime';
import { PY_USER_PACKAGES, PyUserInstalledEntry, PyUserPackage,
  clearPyUserPackages, installPyUserPackage, pyCleanedNeedsRestart,
  pyUserInstalledList, rebuildPyRuntime } from '../../common/pyexec/PyPackages';

// 运行区占用数值（MB 一位小数——首卡主视觉大数字只吃数值，「MB」单位由卡内固定文案承担；
// 不走 formatWorkspaceSize，那件是断言直跑的零 import 叶子且为两位小数混合档）
function formatPyMbValue(bytes: number): string {
  return (bytes / (1024 * 1024)).toFixed(1);
}

@Component
export struct PyRuntimePage {
  // 页面存活守卫（1712 纪律，照 PyRuntimeProbePage 先例）：置位后迟到异步回调不写状态、
  // 不碰 UI；promise 本身照常 resolve 不吞，仅放弃 UI 写
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 运行态（首卡徽标文案；四值 = 未落位 / 已就绪 / 检查中 / 检查失败）。2026-11-16 首卡渐变
  // 笔：原 statusText 是「态 + 占用」拼接句，主视觉要单独吃数值，故拆成三字段（态 / 占用 /
  // 失败摘要），禁再拼回一句
  @State runtimeState: string = '未落位';
  // 运行区占用字节（-1 = 未统计或统计失败；主视觉大数字单源，禁解析格式化字符串）
  @State usageBytes: number = -1;
  // 检查失败摘要（仅「检查失败」态有值，落主视觉文字态；「检查失败」四字由徽标承担，不重复）
  @State failNote: string = '';
  // 解释器版本串（Py_GetVersion 原文长串；仅「检查环境」成功后回显，等宽字）
  @State versionText: string = '';
  // 在跑标志（落位 + 初始化期间禁重复触发键——ensurePyRuntime 自带单飞，此处只管 UI 互斥）
  @State checkBusy: boolean = false;
  // 占用统计在跑（异步面——状态行旁显示小转圈，统计完回填占用读数；2026-11-14 起）
  @State usageBusy: boolean = false;
  // 占用统计世代号（2170 自检轮修）：检查流开始时自增作废在途统计，仅最新世代可回填
  // 状态行——防「检查失败」句被进页时发起的旧统计迟到覆盖成「已就绪」
  private usageEpoch: number = 0;
  // 预置包清单（PY_PRESET_PACKAGES 展示镜像，只读不写——静态数据不吃状态装饰）
  private presetPackages: string[] = PY_PRESET_PACKAGES;
  // ── 卡三「自装包」状态（2026-11-15 闲4门5笔）──
  // 白名单 9 件展示镜像（PY_USER_PACKAGES 只读静态——不吃状态装饰，同 presetPackages 口径）
  private userPackages: PyUserPackage[] = PY_USER_PACKAGES;
  // 已装名集合（进页现读一次 installed.json；安装成功后重读刷新——行键含已装态驱动刷新）
  @State installedNames: string[] = [];
  // 安装/清除/重建同族互斥（期间全部安装键与危险两键禁用；onNote 进度文本仅 busy 时随状态行显示）
  @State installBusy: boolean = false;
  // 安装进度文本（域件 onNote 回填，departed 守卫后写入）
  @State installNote: string = '';
  // 清理待重启态（进页读 pyCleanedNeedsRestart 进程旗 + 本页清除/重建完成后置位；置位后
  // 安装键与危险两键全禁，卡顶说明追加重启提示句）
  @State needsRestart: boolean = false;

  aboutToAppear(): void {
    // 进页现读落位态填状态行（纯读不抛；此时不主动触发落位——首用落位交给用户点键）。
    // 占用读数刻意不在此同步算——数千文件递归 stat 曾阻塞转场帧（2026-11-14 决明实测
    // 进页卡顿根因），改先显就绪、进页后异步统计回填（refreshUsage）
    if (pyRuntimePlaced()) {
      this.runtimeState = '已就绪';
      this.refreshUsage();
    } else {
      this.runtimeState = '未落位';
    }
    // 卡三进页现读已装清单与清理旗（installed.json 是微型 JSON 同步读——与 pyRuntimePlaced
    // 同级轻量盘读；运行区未落位时 pyUserInstalledList 返回空表如实显示零已装）
    this.refreshInstalled();
    this.needsRestart = pyCleanedNeedsRestart();
  }

  // 占用统计（异步面，fire-and-forget）：busy 置位 → 异步求和 → 回填字节数（-1 或异常 =
  // 占用未知，如实展示不静默造数）。消费方 = aboutToAppear 与 doCheck 成功分支两处
  private refreshUsage(): void {
    this.usageBusy = true;
    const epoch: number = ++this.usageEpoch;
    pyRuntimeUsageBytesAsync().then((bytes: number): void => {
      if (this.departed || epoch !== this.usageEpoch) {
        return;
      }
      this.usageBytes = bytes >= 0 ? bytes : -1;
      this.runtimeState = '已就绪';
    }).catch((e: Error): void => {
      if (this.departed || epoch !== this.usageEpoch) {
        return;
      }
      this.usageBytes = -1;
      this.runtimeState = '已就绪';
    }).finally((): void => {
      if (this.departed || epoch !== this.usageEpoch) {
        return;
      }
      this.usageBusy = false;
    });
  }

  // 检查环境：首用落位（幂等）→ native init（幂等）→ 状态行回显就绪 + 版本串，占用经
  // refreshUsage 异步回填；失败给中文句不静默。与卡三安装族的并发由域件侧兜底
  //（ensurePyRuntime 单飞 + installPyUserPackage 进程级 pyInstalling 旗），本页不互斥。
  // needsRestart 态拒查——重建后检查键会触发 homeDir 重落位，绕过「重启后恢复」设计
  private doCheck(): void {
    if (this.checkBusy || this.needsRestart) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.runtimeState = '检查失败';
      this.failNote = '应用上下文不可用';
      return;
    }
    this.checkBusy = true;
    this.usageEpoch += 1; // 检查流接管状态行——进页发起的在途占用统计一律作废（成功分支经 refreshUsage 重发新世代）
    this.runtimeState = '检查中';
    this.failNote = '';
    ensurePyRuntime(ctx).then((homeDir: string): Promise<void> => {
      if (this.departed) {
        return Promise.resolve();
      }
      return initPyRuntime(homeDir).then((outcome): void => {
        if (this.departed) {
          return;
        }
        if (outcome.ok) {
          this.runtimeState = '已就绪';
          this.versionText = outcome.version;
          this.refreshUsage();
        } else {
          this.runtimeState = '检查失败';
          this.failNote = outcome.error;
          this.usageBusy = false; // 进页统计已被作废而检查失败不重发 refreshUsage——显式收标志，防常驻
        }
      });
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.runtimeState = '检查失败';
      this.failNote = e.message;
      this.usageBusy = false; // 同上：catch 路径也不重发占用统计
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.checkBusy = false;
    });
  }

  // ── 卡三动作区（2026-11-15 闲4门5笔；域逻辑单源 PyPackages.ets，本页只做编排）──

  // 已装名集合重读（进页 / 安装成功 / 清除完成后调用；整体换引用触发 @State 刷新）
  private refreshInstalled(): void {
    this.installedNames = pyUserInstalledList().map((entry: PyUserInstalledEntry): string => entry.name);
  }

  private isInstalled(name: string): boolean {
    return this.installedNames.indexOf(name) >= 0;
  }

  // 安装单件（域件内部按冻结依赖闭包多件连装，依赖先序）：进度经 onNote 回填状态行；
  // 成功重读已装清单 + 刷新占用；失败 toast 域件抛出的中文 Error
  private doInstall(pkgName: string): void {
    if (this.installBusy || this.needsRestart) {
      return;
    }
    this.installBusy = true;
    this.installNote = '正在准备安装';
    installPyUserPackage(pkgName, (note: string): void => {
      if (!this.departed) {
        this.installNote = note;
      }
    }).then((): void => {
      if (this.departed) {
        return;
      }
      this.refreshInstalled();
      this.refreshUsage();
    }).catch((e: Error): void => {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: e.message });
    }).finally((): void => {
      if (this.departed) {
        return;
      }
      this.installBusy = false;
      this.installNote = '';
    });
  }

  // 危险动作确认（UIContext promptAction.showDialog 形态——坑64 禁 showAlertDialog 槽内
  // 形态，ChatMoreMenu / ProviderDetailPage 同形制先例）。返回是否点了确认键；弹窗异常 =
  // 显式 toast 不静默吞（宁可不执行，照 ProviderDetailPage 口径）
  private async confirmDanger(title: string, message: string, confirmLabel: string): Promise<boolean> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: title,
        message: message,
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: confirmLabel, color: $r('sys.color.font_primary') }
        ]
      });
      return choice.index === 1;
    } catch (e) {
      if (!this.departed) {
        this.getUIContext().getPromptAction().showToast({ message: '确认框未弹出，请重试' });
      }
      return false;
    }
  }

  // 清除/重建共通骨架：确认 → 置 busy → 调域件 → 成功置 needsRestart 锁页 + 重读已装
  // 清单（账本随目录删除，清单全回未装态）→ 失败 toast → busy 复位；departed 后一律不写状态
  private async runDangerAction(title: string, message: string, confirmLabel: string,
    action: () => Promise<void>, busyNote: string): Promise<void> {
    if (this.installBusy || this.needsRestart) {
      return;
    }
    const confirmed: boolean = await this.confirmDanger(title, message, confirmLabel);
    if (!confirmed || this.departed) {
      return;
    }
    this.installBusy = true;
    this.installNote = busyNote;
    try {
      await action();
      if (this.departed) {
        return;
      }
      this.needsRestart = true;
      this.refreshInstalled();
    } catch (e) {
      if (!this.departed) {
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      }
    } finally {
      if (!this.departed) {
        this.installBusy = false;
        this.installNote = '';
      }
    }
  }

  private doClear(): void {
    this.runDangerAction('清除自装包',
      '将删除全部自装包与安装记录。Python 会话中的变量将失效。完成后需重启应用再使用 Python。',
      '清除', (): Promise<void> => clearPyUserPackages(), '正在清除自装包');
  }

  private doRebuild(): void {
    this.runDangerAction('重建运行区',
      '将删除整个 Python 运行区并删除自装包，重启应用后自动重新释放内置运行环境。Python 会话中的变量将失效。',
      '重建', (): Promise<void> => rebuildPyRuntime(), '正在重建运行区');
  }

  // ── 首卡展示派生（2026-11-16 首卡渐变笔；全为纯读函数，不持状态）──

  // 首卡深浅档（渐变三停/中停色单源 = Theme.heroCardColors / heroCardMidColor）
  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  // 徽标点色：已就绪浅绿 / 检查失败浅红 / 未落位与检查中灰白（与网络出口卡、Web 状态卡同口径）
  private stateDotColor(): string {
    if (this.runtimeState === '已就绪') {
      return HERO_CARD_SUCCESS;
    }
    return this.runtimeState === '检查失败' ? HERO_CARD_DANGER : HERO_CARD_TEXT_DIM;
  }

  // 主视觉文字态（与大数字同槽；不重复徽标已说的四字，失败态改给摘要）
  private visualLabel(): string {
    if (this.checkBusy) {
      return '正在检查环境';
    }
    if (this.runtimeState === '检查失败') {
      return this.failNote !== '' ? this.failNote : '检查未通过';
    }
    if (this.usageBusy && this.usageBytes < 0) {
      return '正在统计占用';
    }
    if (this.runtimeState === '已就绪') {
      return '占用未知';
    }
    return '环境未释放';
  }

  // 文字态色：失败浅红，其余白（与网络卡文字态同口径）
  private visualLabelColor(): string {
    return this.runtimeState === '检查失败' ? HERO_CARD_DANGER : HERO_CARD_TEXT;
  }

  // 主视觉数值串（只在 usageBytes >= 0 时消费；单位「MB」由卡内固定文案承担）
  private usageValueText(): string {
    return formatPyMbValue(this.usageBytes);
  }

  // 口径行是否回显版本串（版本串分支在卡内，须保留等宽字体）。检查失败态一律走 captionHint
  // 的重试句——versionText 只在 init 成功时写入、失败分支不清，若只判非空，一次成功之后的任何
  // 失败都会把旧版本号顶在「检查失败」徽标下、且「可再次检查重试」永不出现（与主视觉 usageBytes
  // 同判：旧读数不许顶格）
  private showVersionCaption(): boolean {
    return this.versionText !== '' && this.runtimeState !== '检查失败';
  }

  // 口径行说明句（只在 showVersionCaption 为假时消费）。
  // 失败态改指路重试——此时主视觉已给错误摘要，同一句话再说「首次检查会释放…」没有信息量
  private captionHint(): string {
    if (this.runtimeState === '检查失败') {
      return '可再次检查重试';
    }
    return '首次检查会释放内置标准库与预置包，重复检查无副作用';
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 首卡「运行环境」（2026-11-16 首卡渐变笔；形制 = NetworkSettingsPage 当前出口卡：
        // 标签 + 状态徽标 → 主视觉 → 口径行 → 细线 → 文字动作行）。固定深色渐变，K3 第三处
        // 点名消费；深浅两档取 Theme.heroCardColors / heroCardMidColor 单源，不随卡底透明度档
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('运行环境')
              .fontSize(13)
              .fontColor(HERO_CARD_LABEL)
            Blank()
            // 状态徽标：22vp 半透明圆角矩形 + 6vp 点（与网络出口卡、Web 状态卡同形）；点色兼作
            // 状态——已就绪浅绿，检查失败浅红，未落位与检查中灰白
            Row({ space: 5 }) {
              Column()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.stateDotColor())
              Text(this.runtimeState)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(HERO_CARD_BADGE_TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(22)
            .padding({ left: 8, right: 8 })
            .borderRadius(6)
            .backgroundColor(HERO_CARD_BADGE_BG)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 主视觉：已就绪且有占用读数 = 大数字 + 单位；其余态（未落位/检查中/检查失败/占用
          // 未知）= 文字态包同高块并底对齐（块高恒定，四态切换卡高不跳——照网络卡延迟块口径）。
          // 数值分支必须并认「已就绪」：检查失败时 usageBytes 可能留着上次旧值，单看 >= 0 会把
          // 旧读数顶在「检查失败」徽标下面
          if (this.usageBytes >= 0 && this.runtimeState === '已就绪' && !this.checkBusy) {
            Row({ space: 5 }) {
              Text(this.usageValueText())
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(HERO_CARD_TEXT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('MB')
                .fontSize(13)
                .fontColor(HERO_CARD_TEXT_DIM)
                .margin({ bottom: 5 })
            }
            .width('100%')
            .constraintSize({ minHeight: HERO_CARD_COPY_MIN_HEIGHT })
            .alignItems(VerticalAlign.Bottom)
          } else {
            Row() {
              Text(this.visualLabel())
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.visualLabelColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .constraintSize({ minHeight: HERO_CARD_COPY_MIN_HEIGHT })
            .alignItems(VerticalAlign.Bottom)
          }
          // 口径行：检查成功后回显版本串原文（等宽；技术内容不受文案规约约束）；未检查过或
          // 检查失败讲首检与重试——说明在动作行上方（宪法「功能设置卡布局次序」条）
          Column() {
            if (this.showVersionCaption()) {
              Text(this.versionText)
                .fontSize(12)
                .fontFamily(codeFontFamilyNow())
                .fontColor(HERO_CARD_TEXT_DIM)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            } else {
              Text(this.captionHint())
                .fontSize(13)
                .fontColor(HERO_CARD_TEXT_DIM)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Divider()
            .strokeWidth(0.5)
            .color(HERO_CARD_DIVIDER)
            .margin({ top: 4 })
          // 卡内检查键（原全宽 fallbackButton 收编入卡；深卡无实底键——图标 + 文字，busy 与
          // 待重启态降不透明度；守卫在 doCheck 内，与网络卡「测试连接」同形）
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(16)
              .fontColor([HERO_CARD_TEXT])
            Text(this.checkBusy ? '检查中' : '检查环境')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(HERO_CARD_TEXT)
          }
          .width('100%')
          .height(HERO_CARD_ACTION_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .opacity(this.checkBusy || this.needsRestart ? 0.6 : 1)
          .onClick((): void => {
            this.doCheck();
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(heroCardMidColor(this.isDarkMode()))
        .linearGradient({
          angle: 135,
          colors: heroCardColors(this.isDarkMode())
        })
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
        // 卡二「预置包」——28 项只读清单，短列表 Column 全量渲染（无滚动容器，无滚动条面）
        Column({ space: 10 }) {
          Text('预置包')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('应用内置的预置包随运行环境一并就位，无需联网下载。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Column({ space: 8 }) {
            ForEach(this.presetPackages, (pkg: string) => {
              Text(pkg)
                .fontSize(13)
                .fontColor(cardTitleColor())
                .width('100%')
            }, (pkg: string) => pkg)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 卡三「自装包」——白名单 9 件手动安装 / 清除 / 重建（2026-11-15 闲4门5笔；域逻辑
        // 单源 PyPackages.ets。清单行 2026-11-15 决明笔改规范组卡行形——组卡行规格见下方
        // 清单行注释；卡头/进度行/危险两键原位不动，危险区确认弹窗与 needsRestart 锁页
        // 见 doClear/doRebuild 注释）
        Column({ space: 10 }) {
          Text('自装包')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('自装包从 Python 官方仓库下载安装，仅限白名单内的纯 Python 包。安装需要联网。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          // 清理待重启提示（追加在说明小字位；置位后全部操作键禁用，见各行 enabled）
          if (this.needsRestart) {
            Text('运行环境已清理，重启应用后恢复使用。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          // 9 件清单行（2026-11-15 决明「规范组卡 + 裸文字安装键」笔重排）：组卡行规格 =
          // 左列包名 16fp Medium（过长自适应缩小：minFontSize/maxFontSize + maxLines(1)
          // 官方单行自适应档——超宽先缩字号、缩到下限才截断；自适应生效时 fontSize 不生效
          // 故不设）+ 版本副行 14fp 次要灰，行高固定 64（组卡两行档）；右侧 = 已装文字 /
          // 裸文字「安装」键。行内可变成分 = 已装态 + 禁用态（busy/needsRestart 键位透明度）
          // ——键全四项覆盖（列表键纪律：透明度不进键即冻结首帧）
          Column({ space: 0 }) {
            ForEach(this.userPackages, (pkg: PyUserPackage, idx: number) => {
              if (idx > 0) {
                Divider()
                  .strokeWidth(0.5)
                  .color(cardBorderColor(this.appColorMode))
                  .width('100%')
              }
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(pkg.name)
                    .maxLines(1)
                    .minFontSize(12)
                    .maxFontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(cardTitleColor())
                    .width('100%')
                  Text(pkg.version)
                    .fontSize(14)
                    .fontColor(cardDescColor())
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (this.isInstalled(pkg.name)) {
                  Text('已装')
                    .fontSize(14)
                    .fontColor(cardDescColor())
                    .flexShrink(0)
                } else {
                  // 裸文字键（决明「安装改裸文字键并缩小字号」）：套用模板先例形制——纯
                  // Text 13fp 强调蓝 + onClick，无 Button 壳无四件套；Text 不吃官方自动压暗，
                  // 禁用态显式 opacity(0.4)（行内按钮规范轻动作档禁用形制）
                  Text('安装')
                    .fontSize(13)
                    .fontColor($r('sys.color.font_emphasize'))
                    .flexShrink(0)
                    .enabled(!this.installBusy && !this.needsRestart)
                    .opacity(this.installBusy || this.needsRestart ? 0.4 : 1)
                    .onClick((): void => {
                      this.doInstall(pkg.name);
                    })
                }
              }
              .width('100%')
              .height(64)
              .alignItems(VerticalAlign.Center)
            }, (pkg: PyUserPackage): string => pkg.name + ':' +
              (this.isInstalled(pkg.name) ? '1' : '0') + ':' +
              (this.installBusy ? '1' : '0') + ':' + (this.needsRestart ? '1' : '0'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          // 安装/清除/重建进度行（onNote 回填；仅 busy 时出现——小转圈照卡一 usageBusy 形制）
          if (this.installBusy) {
            Row({ space: 6 }) {
              Text(this.installNote)
                .fontSize(13)
                .fontColor(cardDescColor())
                .layoutWeight(1)
              LoadingProgress()
                .width(14)
                .height(14)
                .color(cardDescColor())
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          // 分隔后危险区两键（fallbackButton 四件套同「检查环境」键形制）
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
            .width('100%')
          Button('清除自装包')
            .fontSize(15)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.installBusy && !this.needsRestart)
            .onClick((): void => {
              this.doClear();
            })
          Button('重建运行区')
            .fontSize(15)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.installBusy && !this.needsRestart)
            .onClick((): void => {
              this.doRebuild();
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
      title: SETTING_TITLE_PY_RUNTIME,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
