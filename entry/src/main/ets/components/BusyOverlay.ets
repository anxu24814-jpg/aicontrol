// 手动长任务进行中遮罩：应用级浮层挂 pages/Index.ets 根
// Stack 顶层（ProactiveBanner 同位——覆盖含二级页与官方标题栏在内的全部页面），全屏半透明
// 遮罩 + 居中小方卡（LoadingProgress 转圈 + 说明行），卡形制照会话页「会话设置」半模态
//（★ 2026-10-30 自「附件与提示词」更名）
// 三格方卡（ChatPromptSheet.AttachGridRow：圆角 20 / cardBg 底 / 图标位 + 14fp 文字 / 间距 8）。
// · 遮罩命中 = HitTestMode.BLOCK_HIERARCHY（@since 20，API 26 基线可用）——自身与子节点响应
//   触摸测试、阻止所有兄弟与低优先级父节点参与（官方《触摸测试控制》；Stack 重叠场景上层
//   命中即不再测下层，本项目首个 BLOCK_HIERARCHY 用例，首验项在 BLOCKED 真机清单）。系统
//   返回手势不被遮罩消费——由宿主页 PageShell.onBackPressed 拦截后走 confirmLeaveBusyPage
//   弹确认（窗口层弹窗浮于遮罩之上可正常操作）。
// · ★ 只盖「手动触发的执行段」：计数键写点 = 五页（数据同步 / 记忆库管理 / 记忆导入 / 快速
//   清理）各长任务链的执行段起止（bump 发令牌、finally release 归还，起止成对）——交互段
//   （口令 / 策略 / 确认弹窗与系统文件选择器）不写键 = 弹窗与选择器可正常操作；后台自动链
//   （退出会话自动沉淀等）不写键 = 不遮屏（用户没发起的动作突然盖屏是灾难，
//   MEMORY_SINKING_KEY 仍由域件维护供状态行文案，两键互不相干）。
// · 「离开」语义：任务继续在后台完成（落库类不受影响），仅撤遮罩、完成提示可能不显——
//   dismissBusyOverlay 清空在途令牌（此后各任务收尾静默），令牌制保证先任务收尾不会吞掉
//   后起任务的遮罩（★ 计数 ±1 版的实锤缺陷〔自检轮 F2〕：dismiss 置 0 后先任务收尾 -1
//   会把后任务份额一并扣掉，遮罩早退 = 返回拦截空窗）。
// · 离开确认正文按链声明（bump 第三参 leaveNote）：'' = 通用「后台继续」句；导入整理与
//   优化计划两链离开即放弃结果，声明「放弃」句——与帮助中心同批口径对齐（自检轮 F1：
//   通用句在这两链上误导，弹窗与帮助曾自相矛盾）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { overlayMaterial } from '../common/ImmersiveLevel';
import { cardBg, cardTitleColor, SHEET_MASK_COLOR } from '../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';

// 进行中计数（AppStorage 键，进程内态不持久化）：> 0 = 遮罩显示。写点见头注释。
export const BUSY_OVERLAY_COUNT_KEY: string = 'busyOverlayCount';
// 遮罩说明文案（bump 时随写；多任务并存以最后写入为准——离开后先任务未完又起新任务是
// 可达交错，令牌制保证文案与遮罩归属最新任务）
export const BUSY_OVERLAY_TEXT_KEY: string = 'busyOverlayText';
// 离开确认正文（bump 时随写，按链声明离开语义）：'' = 通用句；声明了 = 用该句
export const BUSY_OVERLAY_NOTE_KEY: string = 'busyOverlayNote';
// 通用离开正文（无链级声明时的缺省句——任务继续后台完成，完成后不再提示）
const BUSY_LEAVE_DEFAULT: string = '现在离开，任务会继续在后台执行，完成后不再显示提示。';

// 在途令牌（模块内单源）：bump 发号、release 销号、dismiss 清空，计数 = 在途集大小。
// ★ 不用共享计数 ±1（自检轮 F2）：±1 无归属，dismiss 置 0 后先任务收尾会把后任务份额
// 一并扣掉；令牌谁起谁收，dismiss 撤「当前遮罩」不欠账。
let busyTokenSeq: number = 0;
const activeBusyTokens: Set<number> = new Set<number>();

// 登记一个前台执行段（text = 遮罩文案；leaveNote = 离开确认正文，'' = 通用句），返回
// 令牌供收尾 releaseBusyOverlay——调用点必须 .finally 归还（起止成对，异常路径兜底；
// MemoryGen.bumpSinking 计数范式的令牌化改版）
export function bumpBusyOverlay(text: string, leaveNote: string = ''): number {
  busyTokenSeq = busyTokenSeq + 1;
  activeBusyTokens.add(busyTokenSeq);
  AppStorage.setOrCreate<number>(BUSY_OVERLAY_COUNT_KEY, activeBusyTokens.size);
  AppStorage.setOrCreate<string>(BUSY_OVERLAY_TEXT_KEY, text);
  AppStorage.setOrCreate<string>(BUSY_OVERLAY_NOTE_KEY, leaveNote);
  return busyTokenSeq;
}

// 归还令牌（重复归还被 Set.delete 吸收——finally 与 dismiss 竞态下幂等）
export function releaseBusyOverlay(token: number): void {
  activeBusyTokens.delete(token);
  AppStorage.setOrCreate<number>(BUSY_OVERLAY_COUNT_KEY, activeBusyTokens.size);
}

// 用户确认离开后撤遮罩（任务继续后台跑，语义见头注释）：清空全部在途令牌——离开动作
// 撤的是「当前遮罩」而非某个任务份额，此后各任务收尾静默完成
export function dismissBusyOverlay(): void {
  activeBusyTokens.clear();
  AppStorage.setOrCreate<number>(BUSY_OVERLAY_COUNT_KEY, 0);
}

// 是否有前台任务在遮罩（宿主页返回拦截判据——只拦执行段，交互段返回键由弹窗/选择器自消费）
export function busyOverlayActive(): boolean {
  return (AppStorage.get<number>(BUSY_OVERLAY_COUNT_KEY) ?? 0) > 0;
}

// 宿主页返回拦截单源（各长任务页 PageShell.onBackPressed 共用）：无前台任务 = false 官方
// 返回不变；有 = 同步返回 true 接管 + 异步弹确认，仅「离开」放行（撤遮罩 + 页面自 pop）。
// 弹窗形制与出口口径 = KimiSheetCommon.confirmSheetClose 同款（键序 [次, 主]、仅 index === 1
// 放行、蒙层关闭与异常一律留在原页——非确认出口不放行）
export function confirmLeaveBusyPage(ui: UIContext, onLeave: () => void): boolean {
  if (!busyOverlayActive()) {
    return false;
  }
  askLeaveConfirm(ui, onLeave);
  return true;
}

async function askLeaveConfirm(ui: UIContext, onLeave: () => void): Promise<void> {
  try {
    const text: string = AppStorage.get<string>(BUSY_OVERLAY_TEXT_KEY) ?? '';
    const note: string = AppStorage.get<string>(BUSY_OVERLAY_NOTE_KEY) ?? '';
    const choice = await ui.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '任务进行中',
      message: (text !== '' ? text + '尚未完成。' : '') +
        (note !== '' ? note : BUSY_LEAVE_DEFAULT),
      buttons: [
        { text: '继续等待', color: $r('sys.color.font_secondary') },
        { text: '离开', color: $r('sys.color.font_primary') }
      ]
    });
    if (choice.index === 1) {
      dismissBusyOverlay();
      onLeave();
    }
  } catch (e) {
    // 弹窗异常 = 留在原页（遮罩仍在，任务继续）——不放行返回
  }
}

@Component
export struct BusyOverlay {
  // 两键自订阅（@StorageProp——Index 挂载零参数接线，坑16 正解：订阅式即刷）
  @StorageProp(BUSY_OVERLAY_COUNT_KEY) count: number = 0;
  @StorageProp(BUSY_OVERLAY_TEXT_KEY) text: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（Index 根 Stack 常驻浮层，非瞬时即逝件；count 驱动显隐、挂载期常在）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    // 空 Stack = 无任务零尺寸零命中（ProactiveBanner 同款：不设 width/height 即内容自适应）
    Stack() {
      if (this.count > 0) {
        // 全屏遮罩层（半透明同半模态蒙层单源——能看见下层但不给点）
        Column() {
          // 小方卡（附件三格方卡形制：圆角 20 / cardBg 底 / 转圈位 + 14fp 文字 / 间距 8；
          // min 宽对齐附件卡单格观感，max 防长文案撑爆）
          Column({ space: 8 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(cardTitleColor())
            Text(this.text)
              .fontSize(14)
              .fontColor(cardTitleColor())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .constraintSize({ minWidth: 108, maxWidth: 240 })
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
          .borderRadius(20)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(SHEET_MASK_COLOR)
        .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        // 官方 TransitionEffect 渐隐渐显（禁全局 animateTo——UIContext 纪律；StoragePage
        // OPACITY 先例）
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }
    }
  }
}
