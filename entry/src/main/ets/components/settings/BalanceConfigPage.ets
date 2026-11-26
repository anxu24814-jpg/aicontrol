// 余额查询配置页（服务商详情页「余额查询」入口卡 push 进来）。
// · 壳 = PageShell + 右上「保存」键（ProviderSaveMenu 工厂；ModelEditPage 同构件重复
//   属技术债，未收敛）。内容 = 启用开关 + BalanceField 六字段 + 请求头卡 + 余额模板卡 + 说明行。
// · 落库 = 页内自保存（「配置改后必须显式保存」原则）：updateBalanceConfig 成功 toast +
//   pop({saved:true})（坑17 带 result 才触发入口页 onPop）。
// · ★ 加载完成闸 loaded：updateBalanceConfig 恒写八列不判空，未加载完成（含失败）时表单是
//   空初值，保存会清空用户全量余额配置（含 balance_key）——保存键即时可用而加载异步，必须有闸。
// · 查询不在本页：查询链在入口卡宿主页 ProviderDetailPage.queryBalance，先保存后查询，
//   未保存的编辑态不参与查询。
// · 滚动骨架用 Scroll+Column 不用 List：坑9——List 顶/底留白走视口缩进，内容滚不进标题栏
//   蒙层（光感落空），且 ListItem 子项不居中 CARD_PANEL_WIDTH 卡。Scroll 无按序号定位，
//   键盘避让交系统。
// · 载入：aboutToAppear 取 BalanceConfigParam{providerId}（坑59 ① 字面量挂接口），
//   queryBalanceState 回填，失败 toast 不静默。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_BALANCE_CONFIG_PAGE } from '../../common/RouteNames';
import { HeaderPair, parseHeaderPairs, serializeHeaderPairs } from '../../common/providers/AiTypes';
import {
  BalanceConfig, BalanceState, queryBalanceState, updateBalanceConfig
} from '../../common/store/ProviderBalanceDb';
import {
  CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, cardBg, cardBorderColor,
  cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { BalanceHeadersCard } from './BalanceHeadersCard';
import { BalanceTemplateCard } from './BalanceTemplateCard';
import { providerSaveMenuHds } from './ProviderSaveMenu';
import { InfoCard } from '../InfoCard';

// push 参数（入口卡仅编辑态，providerId 必填、页内恒非空）
export interface BalanceConfigParam {
  providerId: string;
}

// 输入项标签 + 输入框两段式（密码框走系统密码键盘，maxLength 长度有界）
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
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
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
  // ★ 加载完成闸：未加载完成（含失败）时表单是空初值，保存会恒写八列清空用户配置（含
  // balance_key）。失败不提供页内重试——退出重进页面重试，避免把加载失败静默降级成覆盖写
  private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // param 解析（providerId 缺失 = 异常栈——入口唯一且必传）
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

  // 编辑态加载：余额态回填（开关/六字段/请求头）；失败 toast 不静默
  private loadState(): void {
    queryBalanceState(this.providerId)
      .then((st: BalanceState): void => {
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '余额配置读取失败：' + (e as Error).message });
      });
  }

  // 余额配置落库值（trim 组配置，headers 序列化时丢弃空 k/v 行）
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

  // 保存：先过加载完成闸（见 loaded 注释）→ 落库 → toast + pop({saved:true})（坑17）；
  // 失败 toast 留页可重试（表单值不动，幂等重写最终一致）
  private save(): void {
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast(
        { message: '余额配置尚未加载完成，请稍后重试' });
      return;
    }
    updateBalanceConfig(this.providerId, this.balanceCfg())
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '保存失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    // 滚动骨架 = Scroll + Column（坑9：List 顶/底留白走视口缩进，内容滚不进标题栏蒙层，
    // 且 ListItem 子项不居中卡 → 内容左偏）。留白改内容内 padding = 随滚动滚走
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 账户卡（开关为整卡总闸 + 六字段同卡）──
        // ★ 本页保持中性卡：淡染落在服务商详情页的余额查询入口卡（ProviderDetailPage.
        //   BalanceEntryCard）——配置页要的是「改成什么样」，不抢读者对数值的注意
        // 卡序照提案帧：开关 → 地址 → 路径 → 取值，币种与币种路径并排
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('账户余额')
                .fontSize(CARD_SECTION_TITLE_FONTSIZE)
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
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 卡内分割线：开关（整卡总闸）与六个查询字段分开
          Divider()
            .strokeWidth(0.5)
            .color(cardBorderColor(this.appColorMode))
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
          // 币种与币种路径并排（均为「兜底取值」，成对读，省一行高）
          Row({ space: 8 }) {
            Column() {
              BalanceField({
                label: '币种（路径未取到时兜底）',
                placeholder: 'CNY',
                maxLength: 20,
                text: $balCurrency
              })
            }
            .layoutWeight(1)
            Column() {
              BalanceField({
                label: '币种 JSON 路径（可选）',
                placeholder: 'balance_infos[0].currency',
                text: $balCurrencyPath
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
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
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 余额请求头卡（键值井第二次消费，见 BalanceHeadersCard 头注释）──
        Column({ space: 12 }) {
          BalanceHeadersCard({ pairs: $balHeaderPairs })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 套用余额模板卡（可选加速器，放最后——先填字段的人不必先跳过一张卡）──
        BalanceTemplateCard({
          balBaseUrl: $balBaseUrl,
          balPath: $balPath,
          balResultPath: $balResultPath,
          balCurrency: $balCurrency,
          balCurrencyPath: $balCurrencyPath,
          headerPairs: $balHeaderPairs
        })

        // 说明行：交代配置落库位置与查询入口（先说明后操作；InfoCard 单源件）
        InfoCard({ text: '配置保存在本页右上角。保存后返回卡片，点「余额查询」拉取余额。' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 顶/底留白 = 内容内 padding（随滚动滚走——坑9：不走容器 padding 缩进视口）
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
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
