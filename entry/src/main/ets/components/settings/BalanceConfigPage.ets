// 余额查询配置页（2026-09-11 三处模板统一半模态 + 余额配置二级页化，方案 v3 四百零三~
// 五节执行）：自 ProviderBalancePanel 半模态升格为二级页——判项③拍板：余额模板原位照搬
// = 半模态套半模态（官方文档只约束 UIExtension 嵌套情形，普通嵌套未表态 → 按「文档没写
// 不赌」不采用），迁页后三处半模态均挂页面/卡片根，机制完全统一。
// · 壳 = PageShell + 标题「余额查询」+ 右上「保存」键（复用 ProviderSaveMenu 工厂双路，
//   不新开第三个同构件——ModelEditPage 同构重复件属另一笔技术债，本笔不顺手收敛）；
// · 内容 = 启用开关行 + BalanceField 六字段 +「套用余额模板」卡（BalanceTemplateCard）
//   + 余额请求头卡（BalanceHeadersCard 复用）+ 说明行；
// · 落库 = 页内自保存（判项④拍板——「配置改后必须显式保存」原则保留，保存键从服务商页
//   挪到本页）：updateBalanceConfig(providerId, cfg) 成功 toast + pop({saved:true})（坑17
//   带 result 才触发入口页 onPop）；数据层三函数零改动；★ 服务商编辑页保存链的
//   updateBalanceConfig 段已同笔删除（P0-1 双证：人工 grep + 钉 B2——恒写八列不判空，
//   残留调用会清空用户余额配置含 balance_key）；★ 另配「加载完成闸」loaded——页内保存同样
//   走恒写八列的同一函数，未加载完（含加载失败）时表单是空初值，必须有闸挡住（见 loaded 注释）；
// ★ 2026-09-11 决明真机反馈修正笔（本页三处）：
//   ① 滚动容器 List → Scroll+Column——原 List 骨架两处病：顶/底留白走 List padding =
//      视口缩进，内容永远滚不进标题栏蒙层（沉浸光感落空，坑9 同款）；ListItem 子项
//      不居中 CARD_PANEL_WIDTH 卡 → 整列内容左偏。改 Scroll+Column 后留白属内容内
//      padding（随滚动滚走 = 光感生效），Column 默认水平居中还卡正确列位——与
//      PriceTemplateEditPage / ModelEditPage 等表单页同一根骨架；
//   ② 页底「查询」主键删除——查询键移出入口卡（见下）；
//   ③ BalanceField 的 List 焦点滚动链（itemIndex + scrollToIndex）随骨架退役：Scroll 无
//      按序号定位，项目 Scroll 表单页（服务商配置面板 / 编辑模型页）均无此机制，键盘
//      避让交系统；若真机出现字段被键盘遮挡，另笔按 Scroll 定位方案补。
// · 查询：★ 2026-09-11 起不在本页（决明反馈③——「查询键应放在外面余额查询卡内，配置
//   余额与余额查询双键」）：查询链移入入口卡宿主页 ProviderDetailPage.queryBalance，
//   入参 = 本页保存落库后的配置（先保存后查询；未保存的编辑态不参与查询——卡面说明小字
//   已交代）。原「吃未保存最新值」的顾虑由「配置→保存→查询」显式两步化解；
// · 载入：aboutToAppear getParamByName 取 BalanceConfigParam{providerId}（坑59 ①
//   字面量挂接口），queryBalanceState 回填开关/六字段/请求头，失败 toast 不静默（P0-1）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_BALANCE_CONFIG_PAGE } from '../../common/RouteNames';
import { HeaderPair, parseHeaderPairs, serializeHeaderPairs } from '../../common/providers/AiTypes';
import {
  BalanceConfig, BalanceState, queryBalanceState, updateBalanceConfig
} from '../../common/store/ProviderBalanceDb';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { BalanceHeadersCard } from './BalanceHeadersCard';
import { BalanceTemplateCard } from './BalanceTemplateCard';
import { providerSaveMenuHds, providerSaveMenuNav } from './ProviderSaveMenu';

// push 参数（ProviderDetailPage.BalanceEntryCard 构造；providerId 必填——入口卡仅编辑态，
// 新建态不显示故页内恒非空。★ 反馈修正笔：原 baseUrl（专用余额端点为空时的查询兜底）随
// 查询链移出本页而退役——查询兜底端点由入口卡宿主页自持，本页不再需要）
export interface BalanceConfigParam {
  providerId: string;
}

// 输入项标签 + 输入框（ProviderBalancePanel.BalanceField 原样随迁；2026-09-11 反馈修正笔
// 收窄：itemIndex / onFocusScroll 的 List 焦点滚动链随 List→Scroll+Column 退役，本件回归
// 纯「标签 + 输入框」两段式——密码框仍调系统密码键盘，maxLength 输入长度有界）
@Component
struct BalanceField {
  label: string = '';
  placeholder: string = '';
  maxLength: number = 200;
  password: boolean = false;
  @Link text: string;

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      if (this.password) {
        TextInput({ placeholder: this.placeholder, text: this.text })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .maxLength(this.maxLength)
          .width('100%')
          .onChange((value: string): void => {
            this.text = value;
          })
      } else {
        TextInput({ placeholder: this.placeholder, text: this.text })
          .maxLength(this.maxLength)
          .width('100%')
          .onChange((value: string): void => {
            this.text = value;
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct BalanceConfigPage {
  // 顶部/底部留白（vp，PageMapBuilder 注入——首卡落标题栏蒙层下方 / 避让手势条）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（pop 返回 / 保存 pop 带 result 触发入口页 onPop——坑17）
  pathStack: NavPathStack = new NavPathStack();
  // 目标服务商（push 参数；providerId 恒非空——入口卡仅编辑态）
  private providerId: string = '';
  // 表单值（页内 @State 持有——本页即落库主体，无父页 @Link 链；保存时 trim 组配置）
  @State private balanceOn: boolean = false;
  @State private balBaseUrl: string = '';
  @State private balPath: string = '';
  @State private balResultPath: string = '';
  @State private balCurrency: string = '';
  @State private balCurrencyPath: string = '';
  @State private balKey: string = '';
  @State private balHeaderPairs: HeaderPair[] = [];
  // ★ 加载完成闸（2026-09-11 大范围自检轮补）：loadState 未返回（含失败）时表单是空初值，
  // 此刻点「保存」= updateBalanceConfig 恒写八列不判空 → 用空值覆盖用户全量余额配置
  //（含 balance_key）——与本笔 P0-1 同根，只是触发面从「父页残留调用」换成「页内加载竞态」。
  // 保存键在标题栏即时可用、加载是异步的，故必须有此闸；失败时用户可退出重进页面重试加载
  //（不提供页内重试，避免把加载失败静默降级成一次覆盖写）。
  private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // param 解析（PriceTemplateEditPage 同款守卫；providerId 缺失 = 异常栈——入口唯一且
    // 必传；入口卡仅编辑态显示，页内恒非空）
    const params: Array<BalanceConfigParam> = (this.pathStack.getParamByName(
      ROUTE_BALANCE_CONFIG_PAGE) ?? []) as Array<BalanceConfigParam>;
    const param: BalanceConfigParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param.providerId === undefined || param.providerId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.providerId = param.providerId;
    this.loadState();
  }

  // 编辑态加载：余额态回填（开关/六字段/请求头）；失败 toast 不静默（P0-1）
  private loadState(): void {
    queryBalanceState(this.providerId)
      .then((st: BalanceState): void => {
        this.balanceOn = st.enabled;
        this.balBaseUrl = st.baseUrl;
        this.balPath = st.path;
        this.balResultPath = st.resultPath;
        this.balCurrency = st.currency;
        this.balCurrencyPath = st.currencyPath;
        this.balKey = st.key;
        this.balHeaderPairs = parseHeaderPairs(st.headers);
        this.loaded = true;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '余额配置读取失败：' + (e as Error).message });
      });
  }

  // 余额配置落库值（页内自保存——trim 组配置，headers 序列化空 k/v 行丢弃）
  private balanceCfg(): BalanceConfig {
    const cfg: BalanceConfig = {
      enabled: this.balanceOn,
      baseUrl: this.balBaseUrl.trim(),
      path: this.balPath.trim(),
      resultPath: this.balResultPath.trim(),
      currency: this.balCurrency.trim(),
      currencyPath: this.balCurrencyPath.trim(),
      key: this.balKey.trim(),
      headers: serializeHeaderPairs(this.balHeaderPairs)
    };
    return cfg;
  }

  // 保存（标题栏键）：先过加载完成闸（未加载 = 表单空初值，落库即清空用户配置，见 loaded
  // 注释）→ updateBalanceConfig 页内落库 → toast + pop({saved:true})（坑17——带 result 才
  // 触发入口页 onPop 自增 headEpoch 刷顶卡徽章）；失败 toast 留页可重试（表单已填值不动，
  // 幂等重写最终一致）
  private save(): void {
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast(
        { message: '余额配置尚未加载完成，请稍后重试' });
      return;
    }
    updateBalanceConfig(this.providerId, this.balanceCfg())
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast(
          { message: '保存失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    // 滚动骨架 = Scroll + Column（反馈修正笔①）：坑9——页面级 List 的顶/底留白走 List
    // padding = 视口缩进，内容永远滚不进标题栏蒙层，沉浸光感落空；另 ListItem 子项不居中
    // CARD_PANEL_WIDTH 卡 → 整列内容左偏。留白改内容内 padding = 随滚动滚走（光感生效），
    // Column 默认水平居中还卡正确列位——同 PriceTemplateEditPage / ModelEditPage 骨架
    Scroll() {
      Column({ space: 10 }) {
        // ── 账户余额开关行（启用并查询后，服务商卡片显示余额）──
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('账户余额')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('启用并查询后，服务商卡片显示余额')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.balanceOn })
            .onChange((isOn: boolean): void => {
              this.balanceOn = isOn;
            })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(VerticalAlign.Center)

        // 六字段卡（密码框第 6 位）
        Column({ space: 12 }) {
          BalanceField({
            label: '余额 Base URL（留空则用服务 Base URL）',
            placeholder: 'https://api.deepseek.com',
            maxLength: 500,
            text: $balBaseUrl
          })
          BalanceField({
            label: 'API 路径',
            placeholder: '/user/balance',
            text: $balPath
          })
          BalanceField({
            label: '结果 JSON 路径（例如 balance_infos[0].total_balance）',
            placeholder: 'balance_infos[0].total_balance',
            text: $balResultPath
          })
          BalanceField({
            label: '币种（JSON 路径未取到时兜底）',
            placeholder: 'CNY',
            maxLength: 20,
            text: $balCurrency
          })
          BalanceField({
            label: '币种 JSON 路径（可选）',
            placeholder: 'balance_infos[0].currency',
            text: $balCurrencyPath
          })
          BalanceField({
            label: '专用余额 Key（可选，留空则用密钥池首个启用）',
            placeholder: 'sk-...',
            maxLength: 500,
            password: true,
            text: $balKey
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // ── 套用余额模板卡 + 余额请求头卡（两域件复用——模板卡自带卡壳，见其头注释）──
        BalanceTemplateCard({
          balBaseUrl: $balBaseUrl,
          balPath: $balPath,
          balResultPath: $balResultPath,
          balCurrency: $balCurrency,
          balCurrencyPath: $balCurrencyPath,
          headerPairs: $balHeaderPairs
        })

        Column({ space: 12 }) {
          BalanceHeadersCard({ pairs: $balHeaderPairs })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // 说明行（先说明后操作——配置落库位置与查询入口交代；「功能设置卡布局次序」
        // 宪法条同款精神）
        Text('配置保存在本页右上角。保存后返回卡片，点「余额查询」拉取余额。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 顶/底留白 = 内容内 padding（随滚动滚走——坑9 教训：不走容器 padding 缩进视口）
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（坑18）+ 可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: '余额查询',
      menuHds: providerSaveMenuHds((): void => {
        this.save();
      }),
      menuNav: providerSaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
