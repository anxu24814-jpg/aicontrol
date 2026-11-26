// HTTP 请求设置二级页（设置页「工具调用」页跳转行落点）：承载 http_request 工具专属设置。
// 卡序 = 请求超时上限 → 同域请求间隔 → 域名准入（白名单）→ HTTP 凭据入口卡 → 请求模板入口卡。
// 「出站记录」卡已全退役（入口与「请求日志」重复零可见差异；HTTP 工具审计
// 改由请求日志页「只看 HTTP 请求」筛选档承接，本页不承载审计入口）。
// ★ 2026-11-09 三档归一笔记：「HTTP 写操作确认」卡整卡退役——写请求的确认策略并入会话
//   权限模式三档（设置页「新会话默认权限」卡 + 聊天页输入栏第三键），本页不再有分域档。
// ★ 2026-11-11 决明拍板：「域名确认档」整卡退役——按域名的确认例外（恒问 / 恒不问）与
//   会话三档同属「问不问」一根轴，留着即第二根轴；写确认此后只由会话权限模式决定。
//   域名准入白名单保留（能力边界，与确认策略不同维度，三档管不到）。存量例外条目升级后
//   不再读取（help 与发版说明写明：恒问条目失效 = 标准档下恢复按档判断，恒不问条目失效 =
//   写请求重新按档询问）。
// 自包 PageShell 壳，无标题栏菜单键；写即持久化（@StorageLink 一写即落盘、无保存动作 → 返回
// 无参 pop 不挂 onPop〔坑17 口径〕，照 ToolsSettingsPage / NetworkSettingsPage）。
// 形制照规范-列表卡片与组卡 §1.1「选择/内容卡」（控件非行形态不进组卡）；卡壳四件套 =
// CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS（宿主无左右 16vp padding，卡体恒挂卡宽
// 基准，勿写 width('100%')）；说明小字在操作行上方（宪法「功能设置卡布局次序」条）；两写键方
// 互正契约照 NetworkSettingsPage 读超时卡（用户点分段写键 / 第二写键方在途补正下标）。
// ★ 超时/间隔两卡各持一套「键 + 下标 + 双向 @Watch」而不抽共享卡片 @Builder：参数与
//   语义不同，且「值参 @Builder 承载热点」正是坑16 家族禁用形态（规范-数据存储获取刷新方案 §2
//   黑名单）。
// ★ 域名准入卡：列表数据 = @StorageLink 直连 JSON 键（写侧 AppPreferences 落
//   AppStorage）。条目清单必须**自该 @StorageLink 变量**经 parse 派生（读状态变量 = 建立渲染
//   依赖，增删条目当场重渲）——原直读 AppStorage 的写法不产生依赖，症状「操作成功但界面
//   不动、退出重进才对」（刷新规范 §3「重读数据 ≠ 界面已刷新」同族）。
// 每行 = 内嵌灰底卡（badgeBg + 圆角 12 + padding 12，行间自然分隔）：首行域名 + 行内图标删除键
//（TEXTUAL 无底）；添加键 = 卡内全宽主操作键，点击开单输入弹窗填域名。
// ★ 准入卡可收起（决明「可以展开收起的卡」）：标题行行尾折叠箭头 + 整行可点切换 + animateTo
//   300ms 条件渲染式折叠（形制照价格卡 ModelPriceCard，官方 FAQ faqs-arkui-769）；说明小字恒
//   显示，收起态 = 标题 + 说明两行短卡；清单数据在 AppStorage，展开重建即回填——零数据链改动；
//   收放态持持久键（键注释见 AppPreferencesHttp.ets）。
// ★ 标题行不带按压蒙层（形态 = 裸 Row + .onClick，无 Button 包壳）——折叠行热区只在标题
//   行，整行按压蒙层与「整卡可点」观感不对位。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, badgeBg, cardBg, cardDescColor, cardTitleColor,
  CARD_RADIUS
} from '../../common/Theme';
import { clampHttpHostIntervalMs, clampHttpTimeoutCeilingMs,
  HTTP_HOST_INTERVAL_MS, HTTP_HOST_INTERVAL_MS_DEFAULT,
  HTTP_TIMEOUT_CEILING_MS, HTTP_TIMEOUT_CEILING_MS_DEFAULT,
  PREF_HTTP_HOST_INTERVAL_MS_KEY,
  PREF_HTTP_TIMEOUT_CEILING_MS_KEY } from '../../common/AppPreferences';
import { addHttpAllowedHost,
  HTTP_ALLOWED_HOST_MAX_CHARS, HTTP_ALLOWED_HOSTS_MAX,
  httpPolicyHostInputValid, normalizeHttpPolicyHost,
  parseHttpAllowedHosts,
  PREF_HTTP_ALLOWED_HOSTS_KEY, PREF_HTTP_ALLOWLIST_CARD_COLLAPSED_KEY,
  removeHttpAllowedHost } from '../../common/AppPreferencesHttp';
import { SETTING_TITLE_HTTP_ALLOWLIST, SETTING_TITLE_HTTP_CREDENTIALS,
  SETTING_TITLE_HTTP_INTERVAL,
  SETTING_TITLE_HTTP_REQUEST, SETTING_TITLE_HTTP_TEMPLATES, SETTING_TITLE_HTTP_TIMEOUT } from '../../common/SettingSearch';
import { ROUTE_HTTP_CREDENTIALS_PAGE,
  ROUTE_HTTP_TEMPLATE_PAGE } from '../../common/RouteNames';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial } from '../../common/ImmersiveLevel';
import { InputDialog } from '../chat/InputDialog';
import { SegmentBar } from '../SegmentBar';

// 折叠动画时长（官方 FAQ faqs-arkui-769 同值 300ms + EaseInOut，与价格卡同族；本页两卡共用）
const FOLD_ANIM_MS: number = 300;

@Component
export struct HttpRequestSettingsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 超时上限档位键（写即持久化；@Watch 补正分段下标——备份导入等第二写键方在途时 UI 随键同步）
  @StorageLink(PREF_HTTP_TIMEOUT_CEILING_MS_KEY) @Watch('onTimeoutKeyChanged')
  timeoutCeilingMs: number = HTTP_TIMEOUT_CEILING_MS_DEFAULT;
  @State @Watch('onTimeoutSegChanged') timeoutSeg: number = 1;
  // 同域请求间隔档位键（同款双 @Watch 互正契约。默认 1 秒 = 下表下标 2）
  @StorageLink(PREF_HTTP_HOST_INTERVAL_MS_KEY) @Watch('onIntervalKeyChanged')
  hostIntervalMs: number = HTTP_HOST_INTERVAL_MS_DEFAULT;
  @State @Watch('onIntervalSegChanged') intervalSeg: number = 2;
  // 分段选项（顺序契约：下标 0~3 与 HTTP_TIMEOUT_CEILING_MS 的 30s/1m/2m/3m 天然同序，勿乱调）
  private timeoutItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '30 秒' },
    { text: '1 分钟' },
    { text: '2 分钟' },
    { text: '3 分钟' }
  ]);
  // 分段选项（顺序契约：下标 0~3 与 HTTP_HOST_INTERVAL_MS 的 0/500/1000/2000 毫秒天然同序）
  private intervalItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '关闭' },
    { text: '0.5 秒' },
    { text: '1 秒' },
    { text: '2 秒' }
  ]);
  // 域名准入白名单：@StorageLink 直连 JSON 数组键；条目清单自本变量派生（见 allowHosts），增删即重渲
  @StorageLink(PREF_HTTP_ALLOWED_HOSTS_KEY) allowedHostsJson: string = '';
  // 准入卡收放态（缺省 false = 默认展开，存量行为零回归）。@StorageLink 双向 = 点标题行即写
  // 即落盘，重进/重启保持
  @StorageLink(PREF_HTTP_ALLOWLIST_CARD_COLLAPSED_KEY) allowCardCollapsed: boolean = false;
  // 添加域名弹窗（卡内输入行已退役，添加键 = 卡内全宽主操作键，点开单输入弹窗填域名）。★ 组件
  // 成员位构造（坑7）；内容静态 = 一次构造一劳永逸；弹层材质统一挂 overlayMaterial
  private addAllowCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '添加允许域名',
      placeholder: '例如 api.example.com',
      confirmLabel: '添加',
      onConfirm: (text: string): void => {
        this.addAllowHost(text);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  // 白名单条目清单（自 allowedHostsJson 派生——读状态变量即建立渲染依赖；原直读 AppStorage 的
  // 写法不产生依赖，症状「操作成功但界面不动、退出重进才对」〔刷新规范 §3 反面实锤同族〕。
  // 条数上限 100 有界，逐渲染解析开销可忽略）
  private allowHosts(): string[] {
    return parseHttpAllowedHosts(this.allowedHostsJson);
  }

  // 添加白名单域名（弹窗已校验非空并关闭）：输入合法性经 httpPolicyHostInputValid 单源校验；超长 = toast（存储侧
  // 与 parse / set 同口径剔除超长条目，不在此先拦会「添加成功但行不出现、零提示」）；满员 toast
  //（上限 HTTP_ALLOWED_HOSTS_MAX）；重复添加幂等
  private addAllowHost(text: string): void {
    const host: string = normalizeHttpPolicyHost(text);
    if (!httpPolicyHostInputValid(host)) {
      this.getUIContext().getPromptAction().showToast({
        message: '请填写纯域名，例如 api.example.com'
      });
      return;
    }
    if (host.length > HTTP_ALLOWED_HOST_MAX_CHARS) {
      this.getUIContext().getPromptAction().showToast({
        message: '域名过长，最多 ' + HTTP_ALLOWED_HOST_MAX_CHARS + ' 个字符'
      });
      return;
    }
    if (!addHttpAllowedHost(host)) {
      this.getUIContext().getPromptAction().showToast({
        message: '名单已满，最多 ' + HTTP_ALLOWED_HOSTS_MAX + ' 个域名'
      });
      return;
    }
  }

  aboutToAppear(): void {
    // 分段下标初始化（@StorageLink 直读盘上原始值，越界/非法经映射 helper 回退默认档；消费侧
    // 钳制兜底双保险）
    this.timeoutSeg = this.timeoutToSeg(this.timeoutCeilingMs);
    this.intervalSeg = this.intervalToSeg(this.hostIntervalMs);
  }

  // 档位 ↔ 分段下标映射（白名单与下标天然同序；越界值钳制后仍不在白名单时回退默认档——防御
  // 分支，正常不可达）
  private timeoutToSeg(value: number): number {
    const idx: number = HTTP_TIMEOUT_CEILING_MS.indexOf(clampHttpTimeoutCeilingMs(value));
    return idx >= 0 ? idx : HTTP_TIMEOUT_CEILING_MS.indexOf(HTTP_TIMEOUT_CEILING_MS_DEFAULT);
  }

  private intervalToSeg(value: number): number {
    const idx: number = HTTP_HOST_INTERVAL_MS.indexOf(clampHttpHostIntervalMs(value));
    return idx >= 0 ? idx : HTTP_HOST_INTERVAL_MS.indexOf(HTTP_HOST_INTERVAL_MS_DEFAULT);
  }

  // 用户点分段 → 写持久键（同值不回写防递归）
  private onTimeoutSegChanged(): void {
    const value: number = clampHttpTimeoutCeilingMs(HTTP_TIMEOUT_CEILING_MS[this.timeoutSeg]);
    if (value !== this.timeoutCeilingMs) {
      this.timeoutCeilingMs = value;
    }
  }

  private onIntervalSegChanged(): void {
    const value: number = clampHttpHostIntervalMs(HTTP_HOST_INTERVAL_MS[this.intervalSeg]);
    if (value !== this.hostIntervalMs) {
      this.hostIntervalMs = value;
    }
  }

  // 第二写键方（备份导入恢复）→ 补正分段下标（@StorageLink 自动响应）
  private onTimeoutKeyChanged(): void {
    const seg: number = this.timeoutToSeg(this.timeoutCeilingMs);
    if (seg !== this.timeoutSeg) {
      this.timeoutSeg = seg;
    }
  }

  private onIntervalKeyChanged(): void {
    const seg: number = this.intervalToSeg(this.hostIntervalMs);
    if (seg !== this.intervalSeg) {
      this.intervalSeg = seg;
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 请求超时上限卡：标题 → 说明小字 → 分段胶囊四档（说明在操作行上方）
        Column({ space: 10 }) {
          // 标题 + 说明小字同组成对（space 2，标题紧贴说明、再 10 进控件）
          Column({ space: 2 }) {
            Text(SETTING_TITLE_HTTP_TIMEOUT)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('助手调用接口时等待响应的最长时间，只作用于 HTTP 请求工具。模型可以按需缩短，不会超过这个上限。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.timeoutItems,
              selectedIndex: $timeoutSeg
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 同域请求间隔卡：标题 → 说明小字 → 分段四档。说明句覆盖两个机制的分工——本卡管「本机
        // 节奏」，上游限流提示驱动的熔断恒生效、不随「关闭」档失效（与帮助条目同口径）
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            Text(SETTING_TITLE_HTTP_INTERVAL)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('请求同一域名时两笔之间的最短间隔，避免连续请求给对方的服务造成压力。对方返回限流提示时，应用会自动等待更久。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          Column() {
            SegmentBar({
              items: this.intervalItems,
              selectedIndex: $intervalSeg
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 域名准入卡：白名单收紧面——留空 = 不限（现行口径），添加后只放行名单内域名（含子域）。
        // 行列表 + 添加键为本页既有形制；行为边界（重定向不受名单约束）在帮助条目写明，此处
        // 说明小字只讲控制面。标题行折叠箭头 + 整行可点、说明小字恒显示、卡体条件渲染
        Column({ space: 10 }) {
          Column({ space: 2 }) {
            // 标题行：裸 Row + .onClick（无按压蒙层）——折叠行热区只在标题行
            Row() {
              Text(SETTING_TITLE_HTTP_ALLOWLIST)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(12)
                .fontColor([cardDescColor()])
                .rotate({ angle: this.allowCardCollapsed ? 0 : 180 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
                (): void => {
                  this.allowCardCollapsed = !this.allowCardCollapsed;
                });
            })
            Text('留空时不限制助手请求的域名。添加后，助手只能请求名单内的域名及其子域名。高效档下本卡不设限。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          // 卡体（空态 + 条目行 + 添加键）：收起态整体隐藏；清单数据在 AppStorage（@StorageLink
          // allowedHostsJson 派生），展开重建即回填
          if (!this.allowCardCollapsed) {
            if (this.allowHosts().length === 0) {
              Text('名单为空，不限制域名。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            // 条目 = 内嵌灰底卡（badgeBg 底 + 圆角 12 + padding 12，行卡天然分隔）
            ForEach(this.allowHosts(), (host: string) => {
              Row({ space: 8 }) {
                Text(host)
                  .fontSize(14)
                  .fontColor(cardTitleColor())
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Button() {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(16)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  removeHttpAllowedHost(host);
                })
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(badgeBg(this.appColorMode))
              .alignItems(VerticalAlign.Center)
            }, (host: string): string => host)
            // 添加键 = 卡内全宽淡彩次级键（形态照「添加 Key / 添加请求头」）
            Button('添加域名')
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .width('100%')
              .onClick((): void => {
                this.addAllowCtrl.open();
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 「出站记录」入口卡原位于此处——已全退役（与「请求日志」重复；HTTP 请求页恒只留本工具
        // 专属设置面，审计改走请求日志页「只看 HTTP 请求」筛选档，见文件头）
        // HTTP 凭据入口卡（决明拍板双入口之一）：跳总览页（全局卡 + 每助手卡）；形制与总览页行卡
        // 同源（icon + 标题 + 副行）。卡底 Column + 四周 padding 4 = 按压蒙层距卡外圈 4vp（内容
        // padding 12 回添，几何零位移；下一卡同笔）
        Column() {
          Button() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 4 }) {
                Text(SETTING_TITLE_HTTP_CREDENTIALS)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text('给助手的接口请求存密钥，助手只引用名称')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .onClick((): void => {
            this.pathStack.pushPathByName(ROUTE_HTTP_CREDENTIALS_PAGE, null);
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
        // HTTP 请求模板入口卡：跳模板列表页；形制与凭据入口卡同源（含按压蒙层与边距统一笔）
        Column() {
          Button() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 4 }) {
                Text(SETTING_TITLE_HTTP_TEMPLATES)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text('把常用接口存成模板，助手填参数就能调用')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .onClick((): void => {
            this.pathStack.pushPathByName(ROUTE_HTTP_TEMPLATE_PAGE, null);
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
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
      title: SETTING_TITLE_HTTP_REQUEST,
      content: (): void => {
        this.Content()
      }
    })
  }
}
