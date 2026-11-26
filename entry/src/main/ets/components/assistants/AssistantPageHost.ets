// 「助手」二级页壳（2026-11-16 首页布局双形态笔，方案档 §3.8）：侧栏对话形态下侧栏底部
//「助手」入口与助手切换面板「管理助手」行的落点——内容组件 = AssistantPage 原件零改动
//（数据/编辑链/删除链全复用），本壳只补二级页形：PageShell 官方标题栏 + 标题栏覆盖层
//「＋新建助手」键（AssistantTitleBarKeys 原件复用——与页签形态右端同键同动作链：
// ASSISTANT_CREATE_CMD_KEY 指令下发 AssistantPage 弹名称对话框）。页签形态不经本壳
//（TabContent 直挂），双形态数据同源（AssistantDb），零形态分叉。
// · 壳参数契约（PageShell）：title = 页签名同款「助手」；keepStackTitle = true（覆盖层下
//   保留主标题，ChatPage 先例）；content 经组件内 @Builder 挂载（坑39：@BuilderParam
//   content 禁 lambda 直写 UI）。
import { PageShell } from '../../common/PageShell';
import { AssistantPage, ASSISTANT_CREATE_CMD_KEY } from './AssistantPage';
import { AssistantTitleBarKeys } from '../TabMoreMenu';

@Component
export struct AssistantPageHost {
  // 顶部留白（vp，PageMapBuilder 注入 = 标题栏蒙层下沿——首卡落蒙层下方，与页签形态同式）
  @Prop topPad: number = 0;
  // 底部留白（vp，PageMapBuilder 注入 = 避让区高；二级页无悬浮页签让位）
  @Prop bottomPad: number = 0;
  // 官方路由栈（助手卡编辑页 push；PageMapBuilder 注入）
  pathStack: NavPathStack = new NavPathStack();

  // 「＋新建助手」（AssistantTitleBarKeys 原件：动作 = 指令计数器下发，AssistantPage
  // @StorageProp @Watch 弹名称对话框——坑3 口径多层宿主链零透传）
  private newAssistant(): void {
    AppStorage.setOrCreate<number>(ASSISTANT_CREATE_CMD_KEY,
      (AppStorage.get<number>(ASSISTANT_CREATE_CMD_KEY) ?? 0) + 1);
  }

  // 标题栏覆盖层（坑30/51：CustomBuilder 位挂组件内 @Builder）
  @Builder
  TitleBarOverlay() {
    AssistantTitleBarKeys({
      onAdd: (): void => {
        this.newAssistant();
      }
    })
  }

  // 内容（坑39：组件内 @Builder 承载，AssistantPage 原件直挂零改动）
  @Builder
  Content() {
    AssistantPage({
      topPad: this.topPad,
      bottomPad: this.bottomPad,
      pathStack: this.pathStack
    })
  }

  build() {
    PageShell({
      title: '助手',
      titleBarStack: (): void => {
        this.TitleBarOverlay();
      },
      keepStackTitle: true,
      content: (): void => {
        this.Content();
      }
    })
  }
}
