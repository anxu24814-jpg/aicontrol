// 标题栏自绘键原子件（2026-09-11 抽取——标题栏自绘键「形制第三处出现」，兑现
// TabMoreMenu.ets 头注释「第三处再抽」的约定）：单圆键 + 双热区胶囊两件，几何常量与双态
// 口径全项目一份，新增标题栏自绘键一律消费本件，勿再各自复制。
// 形制演进与消费方（原文与真机收敛史见下表文件头注释，本件只留结论）：
//   · ChatPage 右上角〔＋|⋯〕——首处（2026-09-09 二百二十七合并胶囊 / 二百二十八长度微调 /
//     二百三十一两胶囊等长三轮收敛）；
//   · 一级页「对话」页签覆盖层〔搜索圆键 + ＋|⋯ 胶囊〕——第二处（跨页面复制，曾登记
//     「同一形制第三处再抽」）；
//   · 记忆页覆盖层〔加号圆键 + 整理|优化 胶囊〕——第三处（本件抽取的触发点）。
// ★ 2026-09-11 迁移笔：三处**已全部改消费本件**，各自的内联键件与几何常量俱已删除
//（ChatPage / TabMoreMenu 两处迁移同笔改写 sse-assert ㊲/㊹ 两组源码抽取断言并重做注入
// 验证——迁移前该两组按被迁文件的常量与 builder 正文切段）；此后新增标题栏自绘键一律
// 消费本件，勿再复制几何。
// ★ 记忆页消费方的两起一落（2026-09-15 更新）：2026-09-13 该页覆盖层整块退役（三键收进
//   「更多」菜单后合并形态不再需要，改回官方菜单数组）→ 2026-09-15 按决明「记忆页右上角
//   更多/加号合为双键，同消息页」以〔＋|⋯〕合并胶囊回归（组件件 = MemoryTitleBarKeys，
//   在 components/settings/MemoryTitleMenu.ets）。
// ★ 现役消费方七处（2026-09-22 助手页签合并胶囊笔后重数；「抽取时那三处」是历史值不是现值）：
//   ChatPage〔＋|⋯〕/ TabMoreMenu.ChatTabTitleBar（搜索圆键 + 〔＋|⋯〕）/
//   MemoryTitleMenu.MemoryTitleBarKeys〔＋|⋯〕（记忆页）/ SkillLibraryPage.TitleBarContent
//   〔＋|导入〕（技能库页）/ KnowledgeLibraryPage.TitleBarContent〔＋|导入〕（知识库库页——
//   ★ 2026-09-22 导入导出笔起两动作，自单圆键改双热区胶囊）/ KnowledgeBookPage.
//   TitleBarContent（知识库条目清单页的〔＋〕**单圆键**——TitleBarRoundKey，2026-09-21 世界书
//   知识库首版新增；单动作页用单键而非双热区胶囊，胶囊多出来的右热区没有动作 = 死控件）/
//   ProviderTitleMenu.ProviderTitleBarKeys〔＋|⋯〕（服务商管理页，2026-09-22 决明「新建键
//   移出与更多形成双键胶囊，参考消息页实现」——原「更多」菜单内的新建服务商移出成左热区，
//   同页菜单余四项）/
//   TabMoreMenu.AssistantTitleBarKeys〔＋|⋯〕（助手页签，2026-09-22 决明「助手页标题栏改为
//   ＋/更多双键胶囊，加保持原功能，点击更多弹菜单，放排序键」——原官方菜单数组单键 ＋ 退役；
//   ★ 与同件 ChatTabTitleBar 同处一级页标题栏、同栏两页签互斥出键，两枚胶囊共用同一隐形锚点）。
//   ★ 2026-09-15 版式笔二改曾加第五处 = 附件查看器顶栏返回键（恒「无」档，理由 = 全屏模态
//   内容区材质不生效）；同日二级页化笔该页顶部行整体退役（返回键归官方 HDS 标题栏），本件
//   随之退出该页——五处回四处。
//   本清单与全仓使用点自动对账（feature-domain 60 组扫描钉）——新增消费方漏改这里即红。
// · 几何（vp）——四轮真机收敛值，单点微调须同步 ㊲/㊹/59/60 断言：
//   键高 40 = 官方标题栏键高（与返回键齐平）；图标 24 = 官方图标尺寸（API 参考
//   《HdsNavigation》IconStyleMode 表 NORMAL）；圆键 40×40 = 官方菜单数组单键尺寸；
//   胶囊热区 46×40、胶囊宽 92 = 2×46（两热区等分、无键间距）、圆角 = 半高 20（半圆端头）；
//   键间距 8 = 官方菜单数组间距；右缘距屏边 16 = 官方标题栏 end padding。
//   46 是长度微调位：下限 = 官方最小点击热区 40（不缩热区换长度），上限受屏宽预算约束
//   （会话页左组隐私态推导 W ≤ 95.5vp，取 92——预算全文见 ChatPage.ets 模型胶囊注释）。
// · 双态（档位 = resolveEffectiveLevel(immersiveLevel)，与标题栏同排官方键
//   同口径，本件内解析、调用方只传档位值；2026-09-12 分项退役——原 otherLevel 入参删除，
//   档位恒跟随总档）：
//   · 材质档（level ≥ 0）= 壳体走官方 THIN 材质（interactive = 按压形变/触点光效，标题栏
//     是材质生效区），热区透明底 + 关原生按压（坑58：材质生效时开原生按压会叠色）——按压
//     反馈由壳体材质在触点处响应（官方分段胶囊同机制：材质容器 + 子项命中）。
//   · 「无」档（level < 0）= 壳体无材质无底色，改由各热区垫官方纯色底
//     （comp_background_tertiary）——胶囊左热区圆左半、右热区圆右半拼出整胶囊；**禁壳体与
//     热区同时垫同色**（该语义色带透明度，双层叠色会现出内圈色块，规范《行内按钮与光感》
//     §4）；此档保留原生按压，按压只暗当前热区那一半。
// · 本件只画键、不管容器：覆盖层根 Row（全宽全高 + justifyContent End + padding right
//   TITLE_BAR_EDGE_INSET）与 keepStackTitle（覆盖层默认置空主标题）由调用方负责。
// ★ 覆盖层死规矩（ChatTabTitleBar 头注释同源，2026-09-09 真机启动闪退实锤 = 坑30）：经官方
//   stackBuilder 消费的 UI 必须是组件，且由**组件内 @Builder** 挂载——全局 @Builder 被官方
//   titleBar napi 直接调用时无视图上下文，编译产物取 this 为 undefined → 启动即崩。
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
  // 光感档位（沉浸光感总档，档位在本件内解析；2026-09-12 分项退役前为「两源」）。
  // ★ 2026-09-15 二级页化笔：原「非豁免区消费方（全屏模态内容区等，官方生效范围之外）恒传
  // -1（「无」档实底）——首例 AttachmentViewer 返回键」随该页二级页化退役（返回键归官方
  // 标题栏），该例外**暂无效例**；将来若再现非豁免区自绘键，重启本条口径
  @Prop immersiveLevel: number = 0;

  // 生效档位（< 0 = 「无」档 = 纯色圆底 + 保留原生按压）
  private keyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  build() {
    Button() {
      SymbolGlyph(this.icon)
        .fontSize(TITLE_KEY_ICON_SIZE)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .type(ButtonType.Normal)
    .width(TITLE_ROUND_KEY_SIZE)
    .height(TITLE_KEY_HEIGHT)
    .padding(0)
    .borderRadius(TITLE_ROUND_KEY_SIZE / 2)
    .backgroundColor(this.keyLevel() < 0 ?
      $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .stateEffect(this.keyLevel() < 0)
    .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN,
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
  // 光感档位（口径同 TitleBarRoundKey；2026-09-12 分项退役前为「两源」）
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
