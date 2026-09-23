// 联网搜索设置二级页·引擎列表（2026-09-10 多引擎一期；同日决明指令 UI 重构对齐服务商
// 管理页——ProviderPage 同构）：总开关卡（恒首项，两分段都显示）+ 分段胶囊悬浮吸顶
//（已启用/已停用，SegmentBar 日志页/服务商管理成熟实现同款）+ 引擎卡×4（名称 + 徽章行
//〔当前使用/免配置·需 API Key/已·未配置密钥〕+ 行尾启用开关），点卡片 push 引擎配置
// 三级页（SearchEngineDetailPage）。
// 语义（2026-09-10 决明拍板解耦，废除「选中未启用引擎顺手启用」旧补丁）：开关 = 是否
// 参与（含作为回退候选——付费引擎的费用闸）；「设为当前」只在详情页操作。当前引擎被停用
// 或未配置密钥时，对话自动改用已启用引擎中第一个配置完整的，都没有时回 Bing 免密钥兜底
//（resolveEngineId 链不变）。
// 刷新链与服务商管理的差别：偏好四键走 AppStorage（@StorageLink 双向），列表/详情两页
// 订阅同键即时互刷，无 DB 自拉 → 无需 cardEpoch/onPop 重拉链；卡片仍走状态入键的
// ForEach 重建（坑16/坑57 家族——普通成员入参子组件不随父重渲，键含状态变即整卡重建）。
// 明文红线：API Key 明文只在详情页输入，保存即清空、界面只显示已·未配置徽标；明文不进
// 日志/toast。文案守「面向用户文案写作规约」。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_SPACING, CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, LIST_CARD_TITLE_FONTSIZE, badgeBg,
  cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { PREF_SEARCH_ENABLED_ENGINES_KEY, PREF_SEARCH_ENGINE_CFG_KEY,
  PREF_SEARCH_ENGINE_KEY, PREF_SEARCH_SERVICE_ENABLED_KEY } from '../../common/AppPreferences';
import { SETTING_TITLE_SEARCH_ENGINE, SETTING_TITLE_SEARCH_SERVICE } from '../../common/SettingSearch';
import { EngineCfgEntry, SEARCH_ENGINES, SearchEngineDescriptor,
  parseEngineCfg } from '../../common/search/SearchEngineRegistry';
import { ROUTE_SEARCH_ENGINE_PAGE, ROUTE_SEARCH_ENGINE_DETAIL_PAGE } from '../../common/RouteNames';

@Component
export struct SearchEnginePage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（引擎卡 push 引擎配置三级页）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 偏好四键（EntryAbility persistProp 注册先于本页实例化，注册默认 = ALL_SEARCH_ENGINE_IDS
  // 全开；@StorageLink 双向——详情页改动经 AppStorage 即时回流本页，无需 onPop 重拉）。
  // 本处默认值仅键缺失时生效，取 ['bing_local'] = 降级到免 key 引擎可用，与域内 fallback
  // 链（resolveEngineId 兜 bing_local）同向
  @StorageLink(PREF_SEARCH_SERVICE_ENABLED_KEY) searchEnabled: boolean = true;
  @StorageLink(PREF_SEARCH_ENGINE_KEY) currentEngine: string = 'bing_local';
  @StorageLink(PREF_SEARCH_ENABLED_ENGINES_KEY) enabledEngines: string[] = ['bing_local'];
  @StorageLink(PREF_SEARCH_ENGINE_CFG_KEY) cfgJson: string = '';
  // 分段选中（0 已启用 / 1 已停用——服务商管理同款）
  @State private segIndex: number = 0;
  private segItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '已启用' },
    { text: '已停用' }
  ]);

  private isEnabled(engineId: string): boolean {
    return this.enabledEngines.includes(engineId);
  }

  private hasKeyMarked(engineId: string): boolean {
    const entry: EngineCfgEntry | undefined = parseEngineCfg(this.cfgJson).get(engineId);
    return entry !== undefined && entry.hasKey;
  }

  // 当前分段可见引擎（0 已启用 / 1 已停用）——enabledEngines 为 @StorageLink 响应式，
  // 开关启停后卡片按状态归段即时生效（服务商管理 reload 归段同观感）
  private visibleEngines(): SearchEngineDescriptor[] {
    return SEARCH_ENGINES.filter((engine: SearchEngineDescriptor): boolean =>
      this.segIndex === 0 ? this.isEnabled(engine.id) : !this.isEnabled(engine.id));
  }

  // 启用开关（父页唯一写入口；替换整数组保证 @StorageLink 响应）
  private toggleEngine(engineId: string, isOn: boolean): void {
    if (isOn) {
      if (!this.isEnabled(engineId)) {
        this.enabledEngines = this.enabledEngines.concat([engineId]);
      }
    } else {
      this.enabledEngines = this.enabledEngines.filter((id: string): boolean => id !== engineId);
    }
  }

  // 详情页跳转（param = 引擎 id；★ 勿传 null——param 契约 = string，坑12 同款）。
  // 不挂 onPop：偏好走 AppStorage 响应式，本页 @StorageLink 订阅自动刷新（文件头注释）
  private openDetail(engineId: string): void {
    this.pathStack.pushPathByName(ROUTE_SEARCH_ENGINE_DETAIL_PAGE, engineId);
  }

  // 列表内容起始偏移（分段胶囊悬浮位下方——ProviderPage 同款公式）
  private listStartOffset(): number {
    return Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28;
  }

  // 卡片重建键（启用态/当前引擎/密钥态任一变 → 整卡重建——坑16/坑57 家族）
  private cardKey(engine: SearchEngineDescriptor): string {
    return [engine.id, String(this.isEnabled(engine.id)),
      String(engine.id === this.currentEngine), String(this.hasKeyMarked(engine.id))].join('|');
  }

  // 总开关卡（恒首项，不随分段过滤——特性级闸门与服务商管理无对应物，ProviderConfigPanel
  // 启用卡自绘形态同款：标题 15 + 说明 12 + 行尾 Toggle；@StorageLink 直读直写响应式）。
  // ★ 2026-09-10 联网开关归位笔：卡内补一行归属说明——把「是否联网由助手决定、对话页
  // 输入框上方可随时开关」写在落点上（此前这句话只存在于 chip 被拒时的那条 toast 里；
  // 说明小字随操作控件同列，遵守「功能设置卡布局次序」条）。★ 同日会话级覆盖层笔第二阶段：
  // 句尾改口径——对话页那个开关已改为**只调整当前会话**（不再改助手配置），原文案会误导
  // 用户以为它是助手级快捷位。★ 2026-09-10 控制台助手设置读写扩面：卡标题原字面量「总开关」
  // 改引 SETTING_TITLE_SEARCH_SERVICE（全称「联网搜索总开关」——理由见该常量注释）。
  // ★ 2026-09-19 联网开关迁标题栏「更多」菜单后说明句去位置词（守 HelpContent 头注释
  // 「界面耦合红线」口径——文案钉归属语义不钉键位置）：「对话页输入框上方的开关」改
  // 「会话内的联网开关」
  @Builder
  MasterCard() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(SETTING_TITLE_SEARCH_SERVICE)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Text('关闭后对话不再联网搜索')
          .fontSize(13)
          .fontColor(cardDescColor())
        Text('这里配置引擎与密钥。是否联网由助手决定，会话内的联网开关只调整当前会话')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.searchEnabled })
        .onChange((isOn: boolean): void => {
          this.searchEnabled = isOn;
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。Stack 顶层
  // 对齐两层：内容滚动层（List）+ 分段胶囊悬浮层（后声明在上）——ProviderPage 同构，
  // 无标题栏菜单（引擎为固定四家，无新建/排序/导入需求）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      List({ space: CARD_SPACING }) {
        ListItem() {
          this.MasterCard()
        }
        ForEach(this.visibleEngines(), (engine: SearchEngineDescriptor) => {
          ListItem() {
            SearchEngineCardItem({
              engineId: engine.id,
              label: engine.label,
              requiresApiKey: engine.requiresApiKey,
              engineEnabled: this.isEnabled(engine.id),
              isCurrent: engine.id === this.currentEngine,
              hasKey: this.hasKeyMarked(engine.id),
              onOpen: (engineId: string): void => {
                this.openDetail(engineId);
              },
              onToggle: (engineId: string, isOn: boolean): void => {
                this.toggleEngine(engineId, isOn);
              }
            })
          }
          // 键含状态（启用/当前/密钥）——状态变整卡重建，徽章与开关不定格首帧
        }, (engine: SearchEngineDescriptor): string => this.cardKey(engine))

        // 分段空态（四引擎固定存在，空态只可能是「全部在另一段」）
        if (this.visibleEngines().length === 0) {
          ListItem() {
            Text(this.segIndex === 0 ? '暂无已启用的搜索引擎' : '暂无已停用的搜索引擎')
              .fontSize(13)
              .fontColor(cardDescColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding(24)
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(16)
          }
        }
      }
      .width('100%')
      .height('100%')
      // 顶/底留白走官方 contentStartOffset/contentEndOffset（坑9——List padding 顶/底会
      // 裁内容；起始偏移 = 分段胶囊悬浮位下方，卡片上滚从胶囊背板穿过模糊透出）
      .contentStartOffset(this.listStartOffset())
      .contentEndOffset(this.bottomPad + 16)
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)

      // 分段胶囊悬浮固定层（Stack 顶层后声明在上；位置 = 标题栏下沿 + 蒙层渐隐边缘 8）
      Column() {
        SegmentBar({
          items: this.segItems,
          selectedIndex: $segIndex
        })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: Math.max(this.topPad - 8, 0) })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_SEARCH_ENGINE,
      content: (): void => {
        this.Content()
      }
    })
  }
}

// 引擎卡片段（对齐 ProviderCardItem 形态：名称 + 徽章行 + 行尾启用开关，无菜单键——
// 引擎固定四家无删除/分享）。纯展示 + 回调上行（启停/跳转编排在 SearchEnginePage）；
// 展示字段由父页 ForEach 键含状态整卡重建下发（本页偏好为 AppStorage 响应式，无需
// ProviderCardItem 的卡内自拉库链）。
@Component
struct SearchEngineCardItem {
  engineId: string = '';
  label: string = '';
  requiresApiKey: boolean = false;
  // ★ 成员名禁用 enabled——与组件通用属性方法 .enabled() 撞名 = 10505001 编译错
  //（ProviderConfigPanel.providerEnabled 同款教训，2026-09-10 再次实锤）
  engineEnabled: boolean = true;
  isCurrent: boolean = false;
  hasKey: boolean = false;
  onOpen: (engineId: string) => void = () => {
  };
  onToggle: (engineId: string, isOn: boolean) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 徽章文本清单（ForEach 数据源——坑16：@Builder 值参直调 = 按值快照，徽章行走 ForEach
  // 键变重建；顺序 = 当前使用 / 免配置·需 API Key / 已·未配置密钥）
  private badges(): string[] {
    const list: string[] = [];
    if (this.isCurrent) {
      list.push('当前使用');
    }
    list.push(this.requiresApiKey ? '需 API Key' : '免配置');
    if (this.requiresApiKey) {
      list.push(this.hasKey ? '已配置密钥' : '未配置密钥');
    }
    return list;
  }

  // 小徽章（文字胶囊——ProviderCardItem.Badge 同款）
  @Builder
  Badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(cardDescColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor(badgeBg(this.appColorMode))
  }

  build() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1——
    // ProviderCardItem 同款；行内 Toggle 子组件先命中，嵌套点击关系不变）
    Button() {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.label)
            .fontSize(LIST_CARD_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 6 }) {
            ForEach(this.badges(), (text: string) => {
              this.Badge(text)
            }, (text: string): string => text)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 启用开关（官方 Toggle 可点自切换 = 唯一控制面；停用 = 不参与对话搜索与自动回退）
        Toggle({ type: ToggleType.Switch, isOn: this.engineEnabled })
          .onChange((isOn: boolean): void => {
            this.onToggle(this.engineId, isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width('100%')
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .onClick((): void => {
      this.onOpen(this.engineId);
    })
  }
}
