// 工具调用设置二级页：设置页工具域卡首行进入（自包 PageShell 壳，无标题栏菜单键；无编辑
// 无保存动作 → 返回无参 pop 不挂 onPop，坑17 口径）。
// 内容 = 六行跳转组卡（联网搜索 / HTTP 请求 / 脚本工作台 / Python 运行环境 / Node 运行环境 / MCP）
// +「新会话默认权限」卡 +「工具调用轮数上限」卡。
// 归属判据「只影响某工具的设置跟工具自己的页」：引擎/密钥/条数/超时只被 search_web 与
// scrape_web 消费，故归工具调用域。默认权限卡与轮数卡是全局档；轮数写即持久化、全助手一份
//（0 = 不限制，发送链按硬顶兜底）。
// ★ 2026-11-09 会话权限模式笔：原「数据管理操作确认」三档卡在此退役，原位换「新会话默认
// 权限」卡——确认策略收敛为会话级一根旋钮（聊天页输入栏第三键）。
// ★ 2026-11-09 三档归一笔记（决明拍板）：①档名收敛为谨慎 / 标准 / 高效，原「完全权限」
// 改名高效并开放到本卡（三档全可选，不再是「只能在会话内切」）；②浏览器控制页整页退役
//（该页只有「网页高危操作确认」一张卡，已并入三档统管），入口行同步撤除；③HTTP 写操作
// 确认卡同笔退役。权限此后只由本三档一根旋钮控制；旧分域档键退为墓碑，启动时一次性折算
//（见 common/chat/PermissionMode.migrateLegacyApproveModes）。
// 退役指针：脚本工作台原自绘开关卡整卡退役（总开关随助手级「脚本工作台」卡，档位段控迁
// CodeWorkbenchPage），勿回游。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';
import { SliderValueCard } from '../SliderValueCard';
import { InputDialog } from '../chat/InputDialog';
import { PREF_DEFAULT_PERMISSION_MODE_KEY, PREF_TOOL_STEP_LIMIT_KEY } from '../../common/AppPreferences';
import { PERMISSION_MODE_CAUTIOUS, PERMISSION_MODE_FULL, PERMISSION_MODE_STANDARD,
  permissionModeLabel, setDefaultPermissionMode } from '../../common/chat/PermissionMode';
import { TOOL_STEP_HARD_CAP, TOOL_STEP_LIMIT_DEFAULT, TOOL_STEP_LIMIT_MAX,
  clampToolStepLimitStored } from '../../common/providers/ToolLimits';
import { SETTING_TITLE_CODE_WORKBENCH,
  SETTING_TITLE_DEFAULT_PERMISSION_MODE, SETTING_TITLE_HTTP_REQUEST, SETTING_TITLE_MCP,
  SETTING_TITLE_NODE_RUNTIME,
  SETTING_TITLE_PY_RUNTIME,
  SETTING_TITLE_SEARCH_ENGINE,
  SETTING_TITLE_TOOL_STEP_LIMIT,
  SETTING_TITLE_TOOLS } from '../../common/SettingSearch';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard,
  SETTING_ICON_ORANGE } from '../GroupSettingCard';
import { ROUTE_CODE_WORKBENCH_PAGE,
  ROUTE_HTTP_REQUEST_PAGE, ROUTE_MCP_PAGE, ROUTE_NODE_RUNTIME_PAGE, ROUTE_NODE_RUNTIME_PROBE_PAGE,
  ROUTE_PY_RUNTIME_PAGE,
  ROUTE_PY_RUNTIME_PROBE_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE } from '../../common/RouteNames';
import { PY_PROBE_ENABLED, PY_PROBE_TITLE } from '../../common/pyexec/PyRuntime';
import { NODE_PROBE_ENABLED, NODE_PROBE_TITLE } from '../../pages/NodeRuntimeProbePage';
import { SegmentBar } from '../SegmentBar';

@Component
export struct ToolsSettingsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 三级页导航栈（PageMapBuilder 注入；跳联网搜索 / HTTP 请求 / 脚本工作台 / MCP 四个
  // 三级页）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 新会话默认权限档持久键（三档全开放；'' = 迁移态，启动迁移会一次性折算写定）。
  @StorageLink(PREF_DEFAULT_PERMISSION_MODE_KEY) @Watch('onDefaultModeChanged') defaultModePref: string = '';
  @State @Watch('onDefaultSegIndexChanged') defaultSegIndex: number = 1;
  // 工具运行参数键（@StorageLink 写即持久化——EntryAbility persistProp 区注册）：全局一份，
  // 对所有助手生效。★ 双向 @Watch——滑轨侧改 → 写键；键侧改（备份导入恢复）→ 补正滑轨值
  @StorageLink(PREF_TOOL_STEP_LIMIT_KEY) @Watch('onToolStepLimitPrefChanged') toolStepLimitPref: number =
    TOOL_STEP_LIMIT_DEFAULT;
  // 滑轨域状态（@State + $ 传 @Link——坑16 契约；@Watch 写回持久键 = 写即落盘。初值仅占位，
  // aboutToAppear 从持久键取真值并归一）
  @State @Watch('onToolStepLimitSliderChange') sliderToolStepLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  // 轮数卡编辑键弹窗控制器（CustomDialogController 须组件成员位构造——坑7 形态；弹一次
  // new 一次，无 dispose 面）
  private toolStepLimitEditCtrl: CustomDialogController | null = null;
  // 新会话默认权限三档（顺序契约：下标 0 = 谨慎 / 1 = 标准〔缺省〕/ 2 = 高效；档名只由
  // permissionModeLabel 单源给出）
  private defaultModeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: permissionModeLabel(PERMISSION_MODE_CAUTIOUS) },
    { text: permissionModeLabel(PERMISSION_MODE_STANDARD) },
    { text: permissionModeLabel(PERMISSION_MODE_FULL) }
  ]);

  // 跳转行组卡：六行行序 = 联网搜索 / HTTP 请求 / 脚本工作台 / Python 运行环境 / Node 运行环境 / MCP
  // （语义广度自上而下 = 全局引擎域 → 单工具专属配置）。方法形态照 SettingsPage.settingGroups
  // 先例——ArkTS 禁字段初始化器内匿名对象数组〔10605038〕；图标均为已核验符号（magnifyingglass
  // / link / code；MCP = externaldrive；Python = doc_plaintext），符号名以 SDK 符号表在册 +
  // 构建绿为终证（坑72）。六行 chevron 均为 true；iconBg 统一橙 = 卡内主色（与设置主页工具
  // 域卡同色）。★ Python 行曾例外用绿（2026-11-06 门 1「高风险面分族」拍板未登记规范），
  // 2026-11-14 经决明指认与组卡不统一，撤例外回归 §11.4 组卡同色。
  // ★ 2026-11-09 三档归一笔记：原第三行「浏览器控制」随整页退役（该页只剩一张审批卡，
  // 已并入「新会话默认权限」三档统管），勿回游。
  // ★ 2026-11-06 鸿蒙Python运行时门1笔：列表尾条件追加「Python 运行验证」临时行——构建期
  // 开关 PY_PROBE_ENABLED（默认 false 零渲染；真机验证轮翻 true 重构建，验证完复位）
  private toolEntryItems(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [
      {
        // 首行「联网搜索」——点入联网搜索三级页（全局引擎、密钥与联网参数都在该页）；与
        // 助手编辑页「工具调用 → 联网搜索」卡分工 = 那张管单助手是否启用，本页管全局
        icon: $r('sys.symbol.magnifyingglass'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_SEARCH_ENGINE,
        secondary: '配置全局的搜索引擎与密钥',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_SEARCH_ENGINE_PAGE, null);
        }
      },
      {
        icon: $r('sys.symbol.link'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_HTTP_REQUEST,
        // ★ 2026-11-11 自检轮：原「超时、间隔、域名档与凭据」——「域名确认档」整卡已于 2150
        // 版退役，短称仍留在行副标题里等于指引用户去找一张不存在的卡；改指实际可改的准入卡
        secondary: '超时、间隔、域名准入与凭据',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_HTTP_REQUEST_PAGE, null);
        }
      },
      {
        // 第三行「脚本工作台」——点入脚本工作台设置页（原自绘开关卡的档位段控与脚本联网域名
        // 入口落点）；图标 code 为 SDK 符号表在册名（构建绿为终证——坑72）
        icon: $r('sys.symbol.code'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_CODE_WORKBENCH,
        secondary: '运行档位与 JavaScript 联网域名',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_CODE_WORKBENCH_PAGE, null);
        }
      },
      {
        // 第四行「Python 运行环境」——点入运行环境管理页（解释器状态与预置包查看 + 首用
        // 落位）。与脚本工作台分工 = 那张管 JavaScript 脚本档位与域名，本页管内嵌 CPython
        // 运行区（助手级「Python 运行」开关卡在助手编辑页工具调用卡）。图标 doc_plaintext
        // 为本工程在用已核验名；iconBg 橙 = 组卡同色（2026-11-14 撤绿例外，见头注释）。
        // ★ 2026-11-16 决明拍板：副标题加「独立于脚本」四字——「脚本工作台」与「Python 运行
        // 环境」两行的设置项差异大（前者是权限策略，后者是运行时运维），用户易误以为是一套
        // 设置的两半；副标题直接点明各管一摊。
        icon: $r('sys.symbol.doc_plaintext'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_PY_RUNTIME,
        secondary: '解释器与包管理，独立于脚本',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PY_RUNTIME_PAGE, null);
        }
      },
      {
        // 第五行「Node 运行环境」（2026-11-24 鸿蒙 Node 运行时门 4）——点入运行环境管理页（状态与
        // 占用 + 已装包清单 + 清空 / 重建 / 重启）。与 Python 行同族同位次：两行各管一个内嵌运行时，
        // 与脚本工作台分工 = 那张管 JavaScript 脚本档位与域名（助手级「Node 运行」开关卡在助手
        // 编辑页工具调用卡）。图标沿用 code 在册符号（坑72：符号名以 SDK 符号表在册 + 构建绿为
        // 终证；与脚本工作台同图标是门 4 任务书代决，观感不可接受时只改本行）
        icon: $r('sys.symbol.code'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_NODE_RUNTIME,
        secondary: '运行时与包管理，独立于脚本',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_NODE_RUNTIME_PAGE, null);
        }
      },
      {
        // 末行「MCP」——点入 MCP 服务器管理页。图标 externaldrive 为 SDK 符号表在册名
        //（构建绿为终证——坑72）
        icon: $r('sys.symbol.externaldrive'),
        iconBg: SETTING_ICON_ORANGE,
        label: SETTING_TITLE_MCP,
        secondary: '连接 MCP 服务器扩展工具',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_MCP_PAGE, null);
        }
      }
    ];
    // 门 1 临时验证行（构建期开关门控——false 时零渲染；图标沿用 code 在册符号——坑72：
    // 符号名以 SDK 符号表在册 + 构建绿为终证，terminal 等无在册先例名勿用）
    if (PY_PROBE_ENABLED) {
      items.push({
        icon: $r('sys.symbol.code'),
        iconBg: SETTING_ICON_ORANGE,
        label: PY_PROBE_TITLE,
        secondary: '门 1 验证用临时面',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_PY_RUNTIME_PROBE_PAGE, null);
        }
      });
    }
    // Node 临时验证行（2026-11-23 鸿蒙Node运行时门1笔，同款构建期开关门控——false 时零渲染）
    if (NODE_PROBE_ENABLED) {
      items.push({
        icon: $r('sys.symbol.code'),
        iconBg: SETTING_ICON_ORANGE,
        label: NODE_PROBE_TITLE,
        secondary: '门 1 验证用临时面',
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_NODE_RUNTIME_PROBE_PAGE, null);
        }
      });
    }
    return items;
  }

  aboutToAppear(): void {
    this.defaultSegIndex = this.defaultModeToIndex(this.defaultModePref);
    // 轮数滑轨从持久键取真值并归一（脏值如 -1 / 99 / 小数不在值域 → 收口或回默认，赋值即
    // 触发 @Watch 把持久键一并归正落盘；归一同源 = 消费侧同一换算函数）
    this.sliderToolStepLimit = clampToolStepLimitStored(this.toolStepLimitPref);
  }

  // 轮数滑轨 → 持久键（写即落盘；同值不回写防递归）
  private onToolStepLimitSliderChange(): void {
    if (this.toolStepLimitPref !== this.sliderToolStepLimit) {
      this.toolStepLimitPref = this.sliderToolStepLimit;
    }
  }

  // 第二写键方（备份导入恢复）→ 补正轮数滑轨值（@StorageLink 自动响应；归一同 clamp）
  private onToolStepLimitPrefChanged(): void {
    const v: number = clampToolStepLimitStored(this.toolStepLimitPref);
    if (v !== this.sliderToolStepLimit) {
      this.sliderToolStepLimit = v;
    }
  }

  // 轮数手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（@Watch 落盘）。
  // 值域 0 = 不限制
  private applyToolStepLimitInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() || v < 0 || v > TOOL_STEP_LIMIT_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 0~' + TOOL_STEP_LIMIT_MAX + ' 的整数'
      });
      return;
    }
    this.sliderToolStepLimit = v;
  }

  // 轮数编辑键弹窗（InputDialog 数字型——初值预填当前值，成员位 Ctrl 弹一次 new 一次）
  private openToolStepLimitEdit(): void {
    this.toolStepLimitEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: SETTING_TITLE_TOOL_STEP_LIMIT,
        initialText: String(this.sliderToolStepLimit),
        placeholder: '0~' + TOOL_STEP_LIMIT_MAX + '，0 为不限制',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyToolStepLimitInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.toolStepLimitEditCtrl.open();
  }

  // 条数卡整簇已随卡迁往 SearchEnginePage（联网页），本页不再有该键的任何读写点

  // 迁移态 '' 与标准档同形（旧三域缺省都是「先问审批模型」），故未选档时下标落在 1。
  // 脏值同样当标准，写入侧由 setDefaultPermissionMode 的合法值校验兜住。
  private defaultModeToIndex(mode: string): number {
    if (mode === PERMISSION_MODE_CAUTIOUS) {
      return 0;
    }
    return mode === PERMISSION_MODE_FULL ? 2 : 1;
  }

  // 段下标注说明（跟随当前选中档变——禁把三档说明同时铺开，用户只关心自己选的那档）
  private defaultModeDesc(): string {
    if (this.defaultSegIndex === 0) {
      return '每次改动都先弹卡问你。删除等不可逆操作也一样。';
    }
    if (this.defaultSegIndex === 2) {
      return '直接执行，不再询问。删除等不可逆操作也不弹卡。域名准入不设限。密码输入始终禁止。';
    }
    return '审批模型判断普通改动，通过即执行。拒绝或拿不准才弹卡。删除等不可逆操作仍会问你。';
  }

  // 用户点分段 → 写持久键（单一写点 = PermissionMode.setDefaultPermissionMode；
  // 同值不回写防递归）
  private onDefaultSegIndexChanged(): void {
    const value: string = this.defaultSegIndex === 0 ? PERMISSION_MODE_CAUTIOUS :
      (this.defaultSegIndex === 2 ? PERMISSION_MODE_FULL : PERMISSION_MODE_STANDARD);
    if (value !== this.defaultModePref) {
      setDefaultPermissionMode(value);
    }
  }

  // 第二写键方（备份导入恢复）→ 补正分段下标
  private onDefaultModeChanged(): void {
    const idx: number = this.defaultModeToIndex(this.defaultModePref);
    if (idx !== this.defaultSegIndex) {
      this.defaultSegIndex = idx;
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 跳转行组卡（页首）：行序见 toolEntryItems 注释
        GroupSettingCard({ items: this.toolEntryItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
        // 新会话默认权限卡：说明小字跟随档位（只显示当前档那一句）且在操作行上方，写键即时
        // 持久化；三档全开放，会话内临时档由聊天页输入栏第三键负责
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(SETTING_TITLE_DEFAULT_PERMISSION_MODE)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Blank()
            InfoHintButton({
              text: '全局默认档，决定新建会话进来时的档位。聊天页输入框左侧的权限键可为当前会话单独改档，各会话分别记住自己选的档，重启应用后仍在。网页高危操作、HTTP 写操作与数据管理写操作都按这一档裁决。升级前分别设置过这三类确认档的，启动时会按最严的一档折算过来，可在本卡改选。'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text(this.defaultModeDesc())
            .fontSize(13)
            .fontColor(cardDescColor())
          Column() {
            SegmentBar({
              items: this.defaultModeItems,
              selectedIndex: $defaultSegIndex
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
        // 工具调用轮数上限卡（说明小字由共用卡内建在滑轨上方）：值域 0~32，0 = 不限制
        //（发送链换算为 256 硬顶兜底）
        SliderValueCard({
          title: SETTING_TITLE_TOOL_STEP_LIMIT, value: $sliderToolStepLimit,
          min: 0, max: TOOL_STEP_LIMIT_MAX, step: 1,
          format: (v: number): string => v === 0 ? '不限制' : v + ' 轮',
          desc: '限制一次提问中模型调用工具的最大轮数，对所有助手生效。0 为不限制，由内置 ' +
            TOOL_STEP_HARD_CAP + ' 轮硬顶兜底',
          rowLabel: '轮数',
          onEdit: (): void => {
            this.openToolStepLimitEdit();
          }
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
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_TOOLS,
      content: (): void => {
        this.Content()
      }
    })
  }
}
