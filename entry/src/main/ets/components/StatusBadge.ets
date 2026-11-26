// 全站状态词徽标（视觉规范落码：实底蓝白 → 淡底深字）：职责一句话 =
// 「强调态短词徽标的形制单源」——圆角矩形 + 四档色（强调 / 弱化 / 成功 / 危险），色值单源 =
// Theme 的 statusBadgeBg/statusBadgeFg（六色身份板之外的独立档，禁在消费侧写 hex）。
// 判据唯一来源 = docs/规范-视觉色板与徽标.md §2/§8。
// · 为何改淡底（推翻同日早些时候的「实底统一」笔）：实底蓝白一屏出现 5 颗时整列抢注意力，
//   且技能库「内置」、知识库「深度注入」这类信息标签用实底观感像按钮。淡底深字后凭形状
//   （圆角矩形）与位置区分语义，不靠色强撑层级。
// · ★ 表单重构 UI 提案 B2 拍板「徽标只扩充淡绿淡红」：四档到此为止，**琥珀警示
//   档明确不开**；两新档禁挪作身份色 / 入口图标 / 按钮底。首批消费 = 服务商头卡余额徽章
//   （成功）与密钥池「明文缺失」标注（危险）。
// · 消费面（改形制改本件一处全站跟随）：会话列表「草稿」/ 助手页与移动面板「当前」/ 抓取方式
//   面板「当前」尾标 / 技能库「内置」/ 知识库「助手写入」「深度注入」/ 模型选择分节头「使用中」/
//   模板选择面板尾标。
// · 为何独立成件（反碎片下限②登记）：消费面跨 chat / settings / assistants 三域，落任一域件
//   都会造成跨域反向依赖；Theme.ets 是常量与取色函数单源、不装组件，InfoCard 等共享件均
//   一件一文件同款先例。
// · 刷新责任在调用方（头注释契约）：入参为普通成员，父状态变化不自动刷新本件——调用方让
//   本件随行键重建 / 页面重建取新值（坑16 家族）；V2 组件内同样可用（官方《状态管理V1和V2
//   混用指导》：V2 父组件内可用 V1 子组件，普通变量传递无限制）。
// · 徽标非按钮非选项 chip，不受「行内操作按钮官方形制」条约束；四档由 tone 承载。
// ★ 提浓笔（决明「徽标不够醒目，且和图标色类似」）：**只改四档色值，形制零改**——
//   浅色档底加深（1.23 → 1.36 / 弱化 1.29）、深色档底提亮（1.20 → 1.32），字色同幅压深；
//   色值单源仍是 Theme.statusBadge*，本件不写 hex。为何改、为何不再往上推、为何气泡与淡彩
//   按钮不跟，判据全在 Theme.statusBadgeBg 头注释与规范 §2/§10，看形制不必读那里。
// ★ 表单重构 UI 提案 B3「状态点徽标」落地（dot 变体，规范条文 = 《视觉色板与徽标》
//   §2 状态点徽标段）：徽标前置一颗 6vp 实心圆点，**点色恒等于本档字色**（不得单独取色，否则
//   又拐回「新增第七色」）；高度 22vp。★ 反馈二笔：**胶囊形与 2vp 卡底色白圈一并
//   退役**——全部徽标统一圆角矩形（圆角 6）。★ 2026-10-30 决明拍板「徽标取消彩色描边」：
//   反馈二笔引入的 1vp 本档字色 35% 细边（Theme.statusBadgeBorder）随本笔退役，色源函数
//   同删；徽标回归纯淡底色块，淡染卡上的边界感靠淡底自身，不再有描边。**只配成功 / 危险两档**——读
//   「运行中 / 已连接 / 已失效」这类**持续态**；强调与弱化不配点（「草稿」「当前」加点会读成
//   「正在跑」，「已保存」是一次性结果，加点会误导成还在进行）。传 dot 而 tone 非 2/3 时按
//   无点渲染（防御：不让「加点」这件事蔓延到全档）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { statusBadgeBg, statusBadgeFg } from '../common/Theme';

// 徽标几何（规范 §2：圆角矩形 6 / 带点总高 22 / 圆点 6 / 点与字间距 5；无描边）。
// border 计入布局空间（内容区 = 尺寸 − padding − border），退役 1vp 细边时 padding 各补 1
//（5/5/1/1 + 框 → 6/6/2/2；8/8 + 框 → 9/9），外轮廓与行高零漂移。
const DOT_SIZE: number = 6;
const DOT_GAP: number = 5;
const BADGE_RADIUS: number = 6;
const DOT_BADGE_HEIGHT: number = 22;

// 四档语义（与 Theme.statusBadge* 的 tone 参数同值）
export enum BadgeTone {
  // 强调：草稿 / 当前 / 内置 / 使用中 / 助手写入 / 深度注入 / 计数
  EMPHASIS = 0,
  // 弱化：已停用 / 未配置 / 历史态 / 协议名
  WEAK = 1,
  // 成功：已保存 / 已连接 / 余额查得
  SUCCESS = 2,
  // 危险：密钥失效 / 明文缺失（不做「警示琥珀」档——见头注释）
  DANGER = 3
}

@Component
export struct StatusBadge {
  // 徽标文案（短状态词；普通成员——刷新责任在调用方，见头注释）
  text: string = '';
  // 色档（默认强调；弱化态传 BadgeTone.WEAK）
  tone: number = BadgeTone.EMPHASIS;
  // 状态点变体（B3）：true = 徽标前置圆点（只在 SUCCESS / DANGER 生效，见头注释）
  dot: boolean = false;
  // 系统颜色模式（两档色各自双态，见 Theme.statusBadge*）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 可选字体族（2026-11-04 字体补接笔）：默认空串 = 不设 fontFamily，全站既有 26 处调用零变化；
  // 会话页消息域消费方（文件改动卡与其详情面板）传正文字体族串，随字体设置即时重绘。
  // ★ 只能双分支写（非空才调用）：fontFamily 签名不收 undefined；也禁「非空 ? 族名 : 系统族名」
  // 三元回退——显式系统族名会钉死应用级槽位（同 assert-chat-font I5 负判据的事故形态）。
  @Prop fontFamily: string = '';

  // 点变体是否成立（tone 只认成功 / 危险两档）
  private dotted(): boolean {
    return this.dot && (this.tone === BadgeTone.SUCCESS || this.tone === BadgeTone.DANGER);
  }

  build() {
    if (this.dotted()) {
      Row({ space: DOT_GAP }) {
        // 点 = 同档字色（禁单独取色）
        Column()
          .width(DOT_SIZE)
          .height(DOT_SIZE)
          .borderRadius(DOT_SIZE / 2)
          .backgroundColor(statusBadgeFg(this.tone, this.appColorMode))
        if (this.fontFamily !== '') {
          Text(this.text)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(statusBadgeFg(this.tone, this.appColorMode))
            .fontFamily(this.fontFamily)
        } else {
          Text(this.text)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(statusBadgeFg(this.tone, this.appColorMode))
        }
      }
      .height(DOT_BADGE_HEIGHT)
      .padding({ left: 9, right: 9 })
      .borderRadius(BADGE_RADIUS)
      .backgroundColor(statusBadgeBg(this.tone, this.appColorMode))
      .alignItems(VerticalAlign.Center)
    } else {
      if (this.fontFamily !== '') {
        Text(this.text)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(statusBadgeFg(this.tone, this.appColorMode))
          .backgroundColor(statusBadgeBg(this.tone, this.appColorMode))
          .borderRadius(BADGE_RADIUS)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .fontFamily(this.fontFamily)
      } else {
        Text(this.text)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(statusBadgeFg(this.tone, this.appColorMode))
          .backgroundColor(statusBadgeBg(this.tone, this.appColorMode))
          .borderRadius(BADGE_RADIUS)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
    }
  }
}
