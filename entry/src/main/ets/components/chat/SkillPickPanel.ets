// 「附件与提示词」半模态 · 技能选择面板域件（★ 2026-10-13 状态面板笔新建——原「指定技能页」
// AssistantSkillPage hostKind='designate'（对话页「技能」卡 push 整页）退役，改本面板第四子态；
// 决明拍板：形制参考提示词注入面板〔PromptPickPanel〕——每卡右侧官方开关、同时只能开一个）。
// 与 PromptPickPanel 的一处**刻意差异**：互斥取**自动切换**而非「拒绝 + 弹回」——开第二个技能
// 直接切换（零 toast 零拒绝；提示词注入面板同日同口径改判，见 PromptPickPanel 注释），故本件
// 无开关纪元字段（指定值纯内存、零落库零失败路径，键含选中态即可驱动重建）。
// 语义：单条消息指定技能——全库可选（有意差异：含助手未启用的技能，竞品 Open WebUI /
// LibreChat 只列已启用，见调研档 §三）；只用于下一条消息、发完自动取消、不落库；点当前行
// 开关（关）= 取消指定（上行两空）。控制台助手整卡入口在宿主咽喉点拦截（openSkillPage
// toast 拒绝），链路侧另有 ChatPromptState.skillBlocked 硬封锁（多层守卫，见方案 §2.8 #4）。
// 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）；选中上行
// onPicked(skillId, skillName)——宿主回主面板 + onSkillDesignated 通知页面写两 @State。
// ★ 滚动骨架 = Scroll + Column（★ 勿改回 List，2026-10-30 决明真机报障后统一——与
// 2026-10-25 模板半模态 TemplatePickSheet 同病同修）：List 对滚出视口的行做布局级虚拟化，
// clip(false) 只管绘制裁剪、管不住行回收，行卡滑到视口上缘即整张消失；Scroll 不回收子项，
// 配 clip(false) 行卡才滑进标题栏渐变模糊区渐隐 = 记忆页选会话（ConvPickerSheet）同款形态。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { querySkills, SkillRow } from '../../common/store/SkillDb';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';

@Component
export struct SkillPickPanel {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 已指定的技能 id（进入面板播种开关初始态；'' = 未指定）
  @Prop currentId: string = '';
  // 面板底部留白（尾部安全区让位行高）
  @Prop bottomPadInset: number = 0;
  // 选中上行（宿主更新「技能」卡状态 + onSkillDesignated + 回主面板）
  onPicked: (skillId: string, skillName: string) => void = () => {
  };
  // 滚动控制器（宿主 sheet 壳 bindToScrollable 绑标题栏渐变模糊——传引用共用同一实例）
  scroller: Scroller = new Scroller();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private skills: SkillRow[] = [];
  // 技能清单读取失败提示（PromptPickPanel 同款形制——失败呈报原因，禁静默空列表 P0-1）
  @State private hintText: string = '';
  @State private pickCurrentId: string = '';

  aboutToAppear(): void {
    this.pickCurrentId = this.currentId;
    // 归零防御（面板重进复用宿主同一 scroller 实例；未绑定时静默无效，与原行为同构——
    // scrollToIndex 是 List/Grid/WaterFlow 专属，Scroll 骨架改 scrollTo）
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.reload();
  }

  private reload(): void {
    querySkills()
      .then((rows: SkillRow[]): void => {
        if (this.departed) {
          return;
        }
        this.skills = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.skills = [];
        // 失败呈报（PromptPickPanel 同款）：置 hintText 上列表失败行，不静默装「无技能」
        this.hintText = '技能列表读取失败：' + (e as Error).message;
      });
  }

  private nameOf(skillId: string): string {
    for (const row of this.skills) {
      if (row.id === skillId) {
        return row.name;
      }
    }
    return '';
  }

  // 指定落点（纯内存态——无落库无失败路径；上行后宿主回主面板）
  private pick(skillId: string): void {
    this.pickCurrentId = skillId;
    this.onPicked(skillId, skillId === '' ? '' : this.nameOf(skillId));
  }

  // 开关切换（互斥 = 自动切换：开第二个直接切换，不拒绝不弹回；关当前 = 取消指定）：
  // 开关是本面板唯一控制面，行点击不切换（PromptPickPanel 同款交互语言）
  private onSwitch(skillId: string, toOn: boolean): void {
    if (toOn) {
      this.pick(skillId);
      return;
    }
    if (this.pickCurrentId === skillId) {
      this.pick('');
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: CARD_SPACING }) {
        // 页顶说明句（原指定技能页句逐字保留——生效范围与时机两判据；13fp 次要色无卡底）
        Text('选中的技能只用于下一条消息，发完自动取消。助手页的技能设置不受影响。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)

        // 技能行（右侧官方开关；ForEach 键含选中态——选中变即键变重建，开关回落正确行）。
        // ★ 行首图标位随自定义图标功能退役（2026-11-02）
        ForEach(this.skills, (row: SkillRow) => {
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text(row.name)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                // 名行单行收敛（同族行卡同款，防长名撑高行卡致面板高矮不一）
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.description !== '' ? row.description : '未填写触发描述')
                .fontSize(13)
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pickCurrentId === row.id })
              .onChange((on: boolean): void => {
                this.onSwitch(row.id, on);
              })
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
        }, (row: SkillRow): string => row.id + (this.pickCurrentId === row.id ? '|on' : ''))

        // 空态行（原指定技能页句逐字保留——技能库为空给引导语；空组卡无意义不出）
        if (this.skills.length === 0 && this.hintText === '') {
          Text('技能库还没有技能。可在 设置 → 技能库 新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        }
        // 失败行（hintText 非空才挂——PromptPickPanel 空态/失败行同款位次）
        if (this.hintText !== '') {
          Text(this.hintText)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width(CARD_PANEL_WIDTH)
            .padding(16)
        }
        // 尾部透明占位（底部安全区让位——Blank 在 ListItem 下编译 10905201，用 Row）
        Row()
          .width('100%')
          .height(this.bottomPadInset)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      // 容器零左右边距，卡宽 CARD_PANEL_WIDTH 自理（规范-半模态 §3，ConvPickerSheet 同形；
      // 原 List padding left/right 16 + 卡 100% 的等价搬迁——几何零位移）；顶 20 = 首卡与
      // 标题栏蒙层留白（原 List padding top 同值）
      .padding({ top: 20 })
    }
    .width('100%')
    .height('100%')
    // 顶对齐（Scroll 默认 Center，内容不满屏时会垂直居中——ConvPickerSheet 同款显式）
    .align(Alignment.Top)
    // ★ 动态模糊生效前提（沉淀「列表类」节）：滚动内容穿透标题栏背后（clip(false) 缺省
    // 裁剪 = 模糊无内容可透——PromptPickPanel 同款）
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
