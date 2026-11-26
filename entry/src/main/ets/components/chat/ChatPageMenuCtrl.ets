// 聊天页菜单动作域（自 ChatPage 域级拆出，方法体原样搬迁）：页面「更多」菜单回调簇（会话
// 工作区/会话统计/会话轨迹；「分支」组已随面板退役、「刷新」组已随菜单项退役整组
// 删除——动作 refreshPage 保留，唯一消费方 = 错误覆盖层「重试」；★ 2026-10-30 联网项迁出笔：
// 原联网快照三件与 refs.webSubMenu 装配段随「联网」项迁 ChatPromptSheet 联网卡整删；★
// 2026-11-11 新建去重笔：「新建会话」菜单项与对应回调字段撤除，本域 newSession 只为标题栏
// 〔＋〕键存活；★ 2026-11-15 标题栏两态笔：右上改单圆键〔⋯更多〕，新建会话回菜单首项，
// 本域 newSession 恢复为菜单动作）+ 菜单节点宿主生命周期（init/open/dispose）+ 新建会话导航。
// · 为何不并入既有件（反碎片下限②申报）：ChatMoreMenu.ets 是菜单**内容与宿主**域（全局
//   @Builder 与 AppMenuHost 子类），本件是**页面动作装配**域（持页面控制器引用与导航栈）；
//   并入会让菜单领域件反向依赖页面控制器（层级倒置）。
import { UIContext } from '@kit.ArkUI';
import { ChatMoreMenuCallbacks, ChatMoreMenuHost } from './ChatMoreMenu';
import { ChatSheetCtrl } from './ChatSheetCtrl';
import { nextMessageId } from '../../common/store/ChatDb';

// 页面动作依赖（refs 闭包延迟求值照 ChatSheetCtrl / ChatPageLoad 形制——页面控制器实例直传）
export interface ChatPageMenuRefs {
  ui: () => UIContext;
  sheet: ChatSheetCtrl;
  // 会话轨迹 push（路由常量与 param 在页面闭包——本域只报点击）
  onOpenTrace: () => void;
  // 会话工作区 push（同 onOpenTrace 形态——路由常量与 param 在页面闭包，本域只报点击）
  onOpenWorkspace: () => void;
  // ★ 2026-10-30 联网项迁出笔：原 webSearchOn（联网快照源）与 webSubMenu（二级菜单 builder
  // 载体）两字段随「联网」项迁出整删——发送链的 webSearchOn @StorageProp 在页面侧不受影响
  // 草稿保存先行：newSession 的 replacePath 路径上，新页恢复链可能先于旧页延迟销毁的
  // leave() 执行——动作点抢先保存（转发 lifecycle.saveDraftFromHost，单保存逻辑双触发，
  // 幂等）防新页恢复读到「旧页尚未保存」的旧槽值
  saveDraftNow: () => void;
  // 新建会话导航（★ 2026-11-16 首页布局双形态笔注入化）：入参 = 菜单域已生成的懒创建新
  // id——二级页形态 = replacePathByName 同路由替换（坑57 同分支复用防，原内联实现迁注入）；
  // 侧栏形态主区常驻态 = 上抛 DrawerMainArea 换 activeConvId（@Link 回 HomeNavigation，
  // 双交替重建即达，无路由动作）。
  // 注入而非内联判形态：本域不 import 形态键，页面构造时给实现（依赖方向 = 页面知道壳形态）
  newSessionNav: (newId: string) => void;
  // 设置项兜底（★ 2026-11-16 双形态真机修复笔，可选）：仅侧栏形态主区常驻态传——侧栏域
  // 故障时「更多」菜单恒可达设置页（切回底栏形态的逃生门）；二级页形态不传 = 菜单不挂该项
  onOpenSettings?: () => void;
}

export class ChatPageMenuCtrl {
  private refs: ChatPageMenuRefs;
  private host: ChatMoreMenuHost = new ChatMoreMenuHost();

  constructor(refs: ChatPageMenuRefs) {
    this.refs = refs;
  }

  // 菜单宿主首建（页面 aboutToAppear；open 前重建换真值，首建只为节点就绪）
  init(ui: UIContext): void {
    this.host.init(ui, this.build());
  }

  // 弹出「更多」官方菜单（材质 THIN 基准随沉浸光感总档，宿主内解析——THIN 为决明拍板的全菜单统一档）
  open(immersiveLevel: number): void {
    this.host.open(this.refs.ui(), this.build(), immersiveLevel);
  }

  // 节点释放（与 init 成对——ComponentContent 不释放即泄漏）
  dispose(): void {
    this.host.dispose();
  }

  // 新建会话（★ 2026-11-15 标题栏两态笔：右上改单圆键后入口回到「更多」菜单首项；★
  // 2026-11-16 首页布局双形态笔：导航动作注入化——refs.newSessionNav 承接，二级页形态
  // 行为不变〔replacePath 同路由替换，坑57 同分支复用防〕、侧栏形态上抛主区换 id）：懒创建
  // ——领导指令「空会话不进历史」本地生成会话 id 不落库，首条消息发送时 ChatDb 才建行
  //（insertMessage 内 ensureConversation），新建不发消息 = 历史无痕
  newSession(): void {
    // 草稿保存先行（refs.saveDraftNow——见接口注释的 replacePath 竞态）
    this.refs.saveDraftNow();
    this.refs.newSessionNav(nextMessageId('conv'));
  }

  // 「更多」菜单回调簇（open 每次弹出前重建节点取当前深浅色；快照纪律见文件头）
  private build(): ChatMoreMenuCallbacks {
    return {
      // ★ 2026-11-15 标题栏两态笔：右上改单圆键后新建会话回菜单首项，动作链一字未动
      onNewSession: (): void => {
        this.newSession();
      },
      // ★ 2026-10-30 联网项迁出笔：原联网快照三件与 webSubMenu 装配段随「联网」项整删
      //（迁 ChatPromptSheet 联网卡，见 ChatMoreMenu 文件头）
      // 会话统计项：点击开面板
      onOpenStats: (): void => {
        this.refs.sheet.openStats();
      },
      // 会话轨迹项：push 独立页（无数据变更 → 返回无参 pop）
      onOpenTrace: (): void => {
        this.refs.onOpenTrace();
      },
      // 会话工作区项：push 独立页（同会话轨迹回调链形态）
      onOpenWorkspace: (): void => {
        this.refs.onOpenWorkspace();
      },
      // 设置项兜底（★ 双形态真机修复笔；可选透传——refs 没给 = undefined = 菜单不挂该项）
      onOpenSettings: this.refs.onOpenSettings
      // 上下文用量菜单项已撤回（决明口径「只留输入框环形入口」）：面板入口 = 输入条圆环
      // 与摘要轻提示行；勿再往本接口加 usageEnabled/onOpenUsage
    };
  }
}
