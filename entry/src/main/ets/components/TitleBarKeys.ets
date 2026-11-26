// 标题栏自绘键原子件（「形制第三处出现」时抽取，兑现 TabMoreMenu.ets 头注释「第三处再抽」
// 约定）：单圆键 + 双热区胶囊两件，几何常量与双态口径全项目一份，新增标题栏自绘键一律
// 消费本件，勿再各自复制（抽取前的三处内联键件与几何常量俱已删除并改消费本件，迁移时
// 已同步改写 sse-assert ㊲/㊹ 两组断言）。
// ★ 现役消费方十二处（全仓扫描对账口径，「抽取时那三处」是历史值不是现值；2235 侧栏页
//   增为第 12 处，2237 起该处消费四键件）：
//   ChatTitleBarOverlay〔⋯更多〕（聊天页标题栏覆盖层——2026-11-15 两态笔由〔＋|⋯〕改单圆键，
//   ＋收入更多菜单）/ TabMoreMenu.ChatTabTitleBar〔⋯更多〕
//   **单圆键**（对话页签——搜索与加号均收入 ⋯ 菜单，中央另挂分段胶囊〔消费 SegmentBar，
//   不涉本件〕）/ MemoryTitleMenu.MemoryTitleBarKeys〔＋|⋯〕（记忆页）/ SkillTitleMenu.
//   SkillTitleBarKeys〔＋|⋯〕（技能库页，「导入技能」挪进「更多」菜单与「多选」并列）/
//   KnowledgeLibraryPage.TitleBarContent〔＋|⋯〕**双热区胶囊**（知识库库页——新建为左热区 onNewBook，
//   ⋯ 恒最右弹单项「导入知识库」菜单，域件 KnowledgeTitleMenu；沿革 = 2026-11-18 曾短暂改单圆键
//   「更多」再同日恢复双键胶囊）/
//   KnowledgeBookPage.TitleBarContent 的〔＋〕**单圆键**（知识库条目清单页——单动作页用
//   单键而非双热区胶囊，胶囊多出的右热区没有动作 = 死控件）/ ProviderTitleMenu.
//   ProviderTitleBarKeys〔＋|⋯〕（服务商管理页，新建自「更多」菜单移出成左热区）/
//   TabMoreMenu.AssistantTitleBarKeys〔＋|⋯〕（助手页签——与 ChatTabTitleBar 同处一级页
//   标题栏、两页签互斥出键，共用同一隐形锚点）/ PromptTitleMenu.PromptTitleBarKeys〔＋|⋯〕
//   （提示词库页，原官方菜单数组两键改合并胶囊，「多选」换位不换链收入「更多」菜单）/
//   MountManagePage.TitleBarAddKey〔＋〕（文件夹挂载管理页，单动作页用单键）/
//   SettingsPageHost〔magnifyingglass〕（设置二级页 Host，2026-11-16 双形态笔——常显
//   搜索键重映射，单动作页用单键）/ DrawerSidePanel〔搜索|多选|设置|返回〕**四热区紧凑胶囊**
//   （侧栏会话二级页头部，2026-11-18 决明拍板「顶部三键改三键胶囊」+ 同日二级页化笔立三键，
//   ★ 2237 官方返回键隐藏后加最右返回热区成四键〔close_sidebar 朝左〕，走本件紧凑档几何非
//   40 标准档，见 TITLE_CAPSULE_COMPACT_* 注释）/ WorkspaceTitleMenu.WorkspaceTitleBarKeys
//   〔新建文件夹|⋯更多〕**双热区胶囊**（文件工作区管理页——2026-11-18 原官方菜单数组单「更多」键
//   退役，新建文件夹自菜单首项移出成左热区、⋯ 恒最右）。三热区件 TitleBarTripleCapsule 仍在本文件
//   保留（四键件同族单源，防将来单动作消费方复用；2237 起侧栏页改消费四键件）。
//   本清单与全仓使用点自动对账（feature-domain 60 组扫描钉）——新增消费方漏改这里即红。
// · 几何（vp）——四轮真机收敛值，单点微调须同步 ㊲/㊹/59/60 断言：
//   键高 40 = 官方标题栏键高（与返回键齐平）；图标 24 = 官方图标尺寸（API 参考
//   《HdsNavigation》IconStyleMode 表 NORMAL）；圆键 40×40 = 官方菜单数组单键尺寸；
//   胶囊热区 46×40、胶囊宽 92 = 2×46（两热区等分、无键间距）、圆角 = 半高 20（半圆端头）；
//   键间距 8 = 官方菜单数组间距；右缘距屏边 16 = 官方标题栏 end padding。
//   46 是长度微调位：下限 = 官方最小点击热区 40（不缩热区换长度），上限受屏宽预算约束。
//   ★ 原「会话页左组隐私态推导 W ≤ 95.5vp」随 2026-09-26 隐私会话全链退役作废；聊天页
//   2026-11-15 改单圆键后胶囊态中央区宽度走 Theme.TITLE_CENTER_ZONE_*（39% / 130~170），
//   有标题态走避让全宽 + 对称内收 64（同日截断修复笔，见 ChatTitleBarOverlay
//   TITLE_TEXT_ZONE_INSET）。
// · 双态（档位 = resolveEffectiveLevel(immersiveLevel)，与标题栏同排官方键同口径，本件内
//   解析、调用方只传档位值；分项已退役——档位恒跟随总档）：
//   · 材质档（level ≥ 0）= 壳体走官方 THIN 材质（interactive = 按压形变/触点光效，标题栏
//     是材质生效区），热区透明底 + 关原生按压（坑58：材质生效时开原生按压会叠色）——按压
//     反馈由壳体材质在触点处响应（官方分段胶囊同机制：材质容器 + 子项命中）。
//   · 「无」档（level < 0）= 壳体无材质无底色，改由各热区垫官方纯色底
//     （comp_background_tertiary）——胶囊左热区圆左半、右热区圆右半拼出整胶囊；**禁壳体与
//     热区同时垫同色**（该语义色带透明度，双层叠色会现出内圈色块，规范《行内按钮与光感》
//     §4）；此档保留原生按压，按压只暗当前热区那一半。
// · 本件只画键、不管容器：覆盖层根 Row（全宽全高 + justifyContent End + padding right
//   TITLE_BAR_EDGE_INSET）与 keepStackTitle（覆盖层默认置空主标题）由调用方负责。
// ★ 覆盖层死规矩（坑30，真机启动闪退实锤）：经官方 stackBuilder 消费的 UI 必须是组件，且由
//   **组件内 @Builder** 挂载——全局 @Builder 被官方 titleBar napi 直接调用时无视图上下文，
//   编译产物取 this 为 undefined → 启动即崩。
import { uiMaterial } from '@kit.ArkUI';
import { resolveEffectiveLevel, resolvedUiMaterial } from '../common/ImmersiveLevel';

// ── 几何常量（消费方渲染与断言同源；vp）──
export const TITLE_KEY_HEIGHT: number = 40;
export const TITLE_KEY_ICON_SIZE: number = 24;
export const TITLE_BAR_EDGE_INSET: number = 16;
export const TITLE_KEY_GAP: number = 8;
export const TITLE_ROUND_KEY_SIZE: number = 40;
export const TITLE_CAPSULE_ZONE_W: number = 46;
export const TITLE_CAPSULE_WIDTH: number = TITLE_CAPSULE_ZONE_W * 2;
export const TITLE_CAPSULE_RADIUS: number = TITLE_KEY_HEIGHT / 2;

// ── 紧凑档几何（★ 侧栏会话二级页头部专属，2026-11-18 决明拍板「比正常胶囊略缩但仍协调」：
// 成因 = 助手名截断预算——侧栏面板时代面板宽 85% 屏（306/272vp），40 标准档三键胶囊 138 会把
// 助手名压到 88/54vp（窄屏四字名都放不下）；36/36/20 档胶囊宽 108（2237 微调笔：热区 40→36、
// 总宽 120→108，缩 10%——三键图标中心距 = 热区宽，缩热区即缩图标间距，决明「三键间距略缩」）
// 比原三枚 36 散键（128 含间距）还窄 20，名字区反增 32vp。高 36 = 侧栏既有键高档（2227 统一笔）
// 零新档，缩后热区宽 36 = 高 36 方整同档；图标 20 仍官方可读尺寸。注意热区宽 36 < 官方 40 下限，
// 属侧栏紧凑档专属让步（高 36 已先例差 4），不扩散到 40 标准档。
// **双档隔离**：正式标题栏键一律 40 标准档（与官方返回键齐平），本档只在侧栏页头部语境消费，
// 禁互抄——两族常量并立即为防混用信号，跨档复用须先拍板）──
export const TITLE_CAPSULE_COMPACT_HEIGHT: number = 36;
export const TITLE_CAPSULE_COMPACT_ZONE_W: number = 36;
export const TITLE_CAPSULE_COMPACT_ICON: number = 20;
export const TITLE_CAPSULE_COMPACT_WIDTH: number = TITLE_CAPSULE_COMPACT_ZONE_W * 3;
export const TITLE_CAPSULE_COMPACT_RADIUS: number = TITLE_CAPSULE_COMPACT_HEIGHT / 2;
// 紧凑档单圆键边长（36）：与紧凑胶囊同高（三键胶囊 108×36 同排等高）；圆键取边长成圆，
// 图标同档 20（TITLE_CAPSULE_COMPACT_ICON）。2026-11-18 侧栏会话二级页分段行首个消费方
export const TITLE_ROUND_KEY_COMPACT_SIZE: number = TITLE_CAPSULE_COMPACT_HEIGHT;

// 单圆键（40×40 圆形热区）：标题栏上的独立动作键（搜索 / 新建 / 添加类）
@Component
export struct TitleBarRoundKey {
  // 图标（系统符号资源 sys.symbol.*）
  icon: Resource = $r('sys.symbol.plus');
  // 无障碍文案（标题栏自绘键无可见文字，读屏与自动化按此识别）
  label: string = '';
  // 点击回调（动作由调用方定）
  onTap: () => void = (): void => {
  };
  // 光感档位（沉浸光感总档，档位在本件内解析）。
  // ★ 非豁免区消费方（全屏模态内容区等，官方生效范围之外）应恒传 -1（「无」档实底）——
  // 现暂无效例（首例 AttachmentViewer 返回键已随该页二级页化退役）；将来再现非豁免区
  // 自绘键时重启本口径
  @Prop immersiveLevel: number = 0;
  // 材质基准档（普通标题栏键缺省 THIN；侧栏 bottomBuilder 键传 REGULAR——强档 −1 后落
  // THIN，与同排分段胶囊/搜索带同厚度。THIN 基准在强档落 ULTRA_THIN，静态只剩图标无底）
  materialStyle: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THIN;
  // 紧凑档（36×36 圆键 + 20 图标，几何单源 = 同文件 TITLE_ROUND_KEY_COMPACT_SIZE /
  // TITLE_CAPSULE_COMPACT_ICON）：2026-11-18 侧栏会话二级页分段行首个消费方——与同排
  // 分段胶囊（36vp 背板）、三键紧凑胶囊等高。缺省 false = 40 标准档；双档隔离口径同
  // 胶囊族（正式标题栏键位禁传本档）
  compact: boolean = false;

  // 生效档位（< 0 = 「无」档 = 纯色圆底 + 保留原生按压）
  private keyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  build() {
    Button() {
      SymbolGlyph(this.icon)
        .fontSize(this.compact ? TITLE_CAPSULE_COMPACT_ICON : TITLE_KEY_ICON_SIZE)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .type(ButtonType.Normal)
    .width(this.compact ? TITLE_ROUND_KEY_COMPACT_SIZE : TITLE_ROUND_KEY_SIZE)
    .height(this.compact ? TITLE_CAPSULE_COMPACT_HEIGHT : TITLE_KEY_HEIGHT)
    .padding(0)
    .borderRadius(this.compact ? TITLE_ROUND_KEY_COMPACT_SIZE / 2 : TITLE_ROUND_KEY_SIZE / 2)
    .backgroundColor(this.keyLevel() < 0 ?
      $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .stateEffect(this.keyLevel() < 0)
    .systemMaterial(resolvedUiMaterial(this.materialStyle,
      this.immersiveLevel, true))
    .accessibilityText(this.label)
    .onClick((): void => {
      this.onTap();
    })
  }
}

// 双热区胶囊（92×40）：两个动作并排、各自可点（＋|⋯ 类），热区等分胶囊、无键间距
@Component
export struct TitleBarActionCapsule {
  // 左热区（图标 / 无障碍文案 / 点击回调）
  leftIcon: Resource = $r('sys.symbol.plus');
  leftLabel: string = '';
  onLeftTap: () => void = (): void => {
  };
  // 右热区（同上）
  rightIcon: Resource = $r('sys.symbol.dot_grid_2x2');
  rightLabel: string = '';
  onRightTap: () => void = (): void => {
  };
  // 光感档位（口径同 TitleBarRoundKey）
  @Prop immersiveLevel: number = 0;

  private keyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  build() {
    Row() {
      Button() {
        SymbolGlyph(this.leftIcon)
          .fontSize(TITLE_KEY_ICON_SIZE)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_ZONE_W)
      .height(TITLE_KEY_HEIGHT)
      .padding(0)
      .borderRadius({ topLeft: TITLE_CAPSULE_RADIUS, bottomLeft: TITLE_CAPSULE_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.leftLabel)
      .onClick((): void => {
        this.onLeftTap();
      })
      Button() {
        SymbolGlyph(this.rightIcon)
          .fontSize(TITLE_KEY_ICON_SIZE)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_ZONE_W)
      .height(TITLE_KEY_HEIGHT)
      .padding(0)
      .borderRadius({ topRight: TITLE_CAPSULE_RADIUS, bottomRight: TITLE_CAPSULE_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.rightLabel)
      .onClick((): void => {
        this.onRightTap();
      })
    }
    .width(TITLE_CAPSULE_WIDTH)
    .height(TITLE_KEY_HEIGHT)
    .borderRadius(TITLE_CAPSULE_RADIUS)
    .clip(true)
    .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN,
      this.immersiveLevel, true))
  }
}

// 三热区紧凑胶囊（108×36，紧凑档几何；2237 由 120×36 缩热区而来——缩图标间距）：三个动作并排、各自可点，首件消费方 = 侧栏面板
// 头部〔齿轮|搜索|多选〕（2026-11-18 决明拍板换位 + 三键胶囊）。与双热区胶囊的差异：
// · 几何走紧凑档（TITLE_CAPSULE_COMPACT_*，面板内嵌语境——见该常量组注释的双档隔离）；
//   左右热区半圆端头、中间热区方角，形制与双热区同宗。
// · **材质基准 = REGULAR**（双热族仍是 THIN）：本件坐在侧栏 bottomBuilder 带，与同排
//   分段胶囊（REGULAR）同厚；固定强档 −1 后落 THIN，壳体/胶囊底可见。若沿用 THIN 基准，
//   强档落 ULTRA_THIN，静态观感只剩三枚图标、无胶囊底（2235 真机反馈根因）。
// · 图标与热区色全 @Prop（双热族是静态普通成员）——多选键图标两态
//   （checkmark_circle ⇄ xmark）+ 选中态 brand 色随父 multiSelectMode 换装，普通成员
//   只在创建时初始化一次、父态变化不刷新（坑44 家族），故动态位必须 @Prop。
// · 热区色缺省 icon_primary，传 brand 即选中态强调（per-zone 色 = 决明拍板「多选蓝信号
//   不弱化」——胶囊族图标色位此前无色参，本件为首个带态消费场景而设）。
// 「无」档（level < 0）与双热族同款：壳体无材质，热区各自垫官方纯色底
// （comp_background_tertiary）+ 保留原生按压；禁壳体与热区同时垫同色（双层叠色现内圈）。
@Component
export struct TitleBarTripleCapsule {
  // 三热区图标（@Prop = 可随父态换装，如多选两态）
  @Prop leftIcon: Resource = $r('sys.symbol.plus');
  @Prop midIcon: Resource = $r('sys.symbol.magnifyingglass');
  @Prop rightIcon: Resource = $r('sys.symbol.dot_grid_2x2');
  // 三热区图标色（缺省主色；选中态传 brand）
  @Prop leftTint: ResourceColor = $r('sys.color.icon_primary');
  @Prop midTint: ResourceColor = $r('sys.color.icon_primary');
  @Prop rightTint: ResourceColor = $r('sys.color.icon_primary');
  // 无障碍文案与点击回调（不参与渲染刷新，普通成员即可——双热族同款口径）
  leftLabel: string = '';
  onLeftTap: () => void = (): void => {
  };
  midLabel: string = '';
  onMidTap: () => void = (): void => {
  };
  rightLabel: string = '';
  onRightTap: () => void = (): void => {
  };
  // 光感档位（口径同 TitleBarRoundKey）
  @Prop immersiveLevel: number = 0;

  private keyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  build() {
    Row() {
      Button() {
        SymbolGlyph(this.leftIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.leftTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .borderRadius({ topLeft: TITLE_CAPSULE_COMPACT_RADIUS,
        bottomLeft: TITLE_CAPSULE_COMPACT_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.leftLabel)
      .onClick((): void => {
        this.onLeftTap();
      })
      Button() {
        SymbolGlyph(this.midIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.midTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.midLabel)
      .onClick((): void => {
        this.onMidTap();
      })
      Button() {
        SymbolGlyph(this.rightIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.rightTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .borderRadius({ topRight: TITLE_CAPSULE_COMPACT_RADIUS,
        bottomRight: TITLE_CAPSULE_COMPACT_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.rightLabel)
      .onClick((): void => {
        this.onRightTap();
      })
    }
    .width(TITLE_CAPSULE_COMPACT_WIDTH)
    .height(TITLE_CAPSULE_COMPACT_HEIGHT)
    .borderRadius(TITLE_CAPSULE_COMPACT_RADIUS)
    .clip(true)
    .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
      this.immersiveLevel, true))
  }
}

// 四热区紧凑胶囊（144×36）：三键胶囊同档加最右返回热区（〔搜索|多选|设置|返回〕，设置键从右
// 往左第二位），首件与
// 唯一消费方 = 侧栏会话二级页（2237「侧栏页返回键移到最右侧、与三键同高组成四键胶囊」）。
// · 由来：侧栏页返回原走官方 HdsNavDestination 返回键（左端 40 圆键），2237 决明拍板隐藏官方
//   返回键（PageShell 透传 backKeyHidden → .hideBackButton(true)，官方 API 18+），把返回动作
//   自绘进标题栏覆盖层的最右热区——与三键等高等宽、同材质同档，四键一条胶囊。避让口径随之
//   变化：官方返回键不再占位，覆盖层左边让位收归 16（TITLE_BAR_EDGE_INSET），助手名区反增一
//   个返回键宽；本件只画键，返回动作由消费方回调（DrawerSidePanel.pathStack.pop 走官方返回链）。
// · 图标：最右返回热区用官方 close_sidebar（箭头朝左「收起侧栏/返回」），与首页打开键
//   open_sidebar（箭头朝右）进出语义配对——两图标均是官方系统符号，消费方传入，本件零写死。
// · 几何与双态口径照三键件同宗（紧凑档 TITLE_CAPSULE_COMPACT_*，REGULAR 基准强档落 THIN；
//   「无」档热区各垫 comp_background_tertiary + 原生按压，禁壳体与热区同垫双层叠色）；图标与
//   热区色全 @Prop（多选键两态换装同三键件坑44 家族口径）；四热区等分无键间距，宽 =
//   TITLE_CAPSULE_COMPACT_ZONE_W × 4。
@Component
export struct TitleBarQuadCapsule {
  @Prop leftIcon: Resource = $r('sys.symbol.plus');
  @Prop midIcon: Resource = $r('sys.symbol.magnifyingglass');
  @Prop rightIcon: Resource = $r('sys.symbol.dot_grid_2x2');
  @Prop backIcon: Resource = $r('sys.symbol.close_sidebar');
  @Prop leftTint: ResourceColor = $r('sys.color.icon_primary');
  @Prop midTint: ResourceColor = $r('sys.color.icon_primary');
  @Prop rightTint: ResourceColor = $r('sys.color.icon_primary');
  @Prop backTint: ResourceColor = $r('sys.color.icon_primary');
  leftLabel: string = '';
  onLeftTap: () => void = (): void => {
  };
  midLabel: string = '';
  onMidTap: () => void = (): void => {
  };
  rightLabel: string = '';
  onRightTap: () => void = (): void => {
  };
  backLabel: string = '';
  onBackTap: () => void = (): void => {
  };
  @Prop immersiveLevel: number = 0;

  private keyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  build() {
    Row() {
      Button() {
        SymbolGlyph(this.leftIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.leftTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .borderRadius({ topLeft: TITLE_CAPSULE_COMPACT_RADIUS,
        bottomLeft: TITLE_CAPSULE_COMPACT_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.leftLabel)
      .onClick((): void => {
        this.onLeftTap();
      })
      Button() {
        SymbolGlyph(this.midIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.midTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.midLabel)
      .onClick((): void => {
        this.onMidTap();
      })
      Button() {
        SymbolGlyph(this.rightIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.rightTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.rightLabel)
      .onClick((): void => {
        this.onRightTap();
      })
      Button() {
        SymbolGlyph(this.backIcon)
          .fontSize(TITLE_CAPSULE_COMPACT_ICON)
          .fontColor([this.backTint])
      }
      .type(ButtonType.Normal)
      .width(TITLE_CAPSULE_COMPACT_ZONE_W)
      .height(TITLE_CAPSULE_COMPACT_HEIGHT)
      .padding(0)
      .borderRadius({ topRight: TITLE_CAPSULE_COMPACT_RADIUS,
        bottomRight: TITLE_CAPSULE_COMPACT_RADIUS })
      .backgroundColor(this.keyLevel() < 0 ?
        $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .stateEffect(this.keyLevel() < 0)
      .accessibilityText(this.backLabel)
      .onClick((): void => {
        this.onBackTap();
      })
    }
    .width(TITLE_CAPSULE_COMPACT_ZONE_W * 4)
    .height(TITLE_CAPSULE_COMPACT_HEIGHT)
    .borderRadius(TITLE_CAPSULE_COMPACT_RADIUS)
    .clip(true)
    .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
      this.immersiveLevel, true))
  }
}
