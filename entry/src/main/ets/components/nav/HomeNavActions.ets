// 导航动作域（自 HomeNavigation 拆出）：设置域二级页 push 编排 + 设置页签搜索菜单构造
//（HDS 单形态；回退 Navigation.menus 版已随 2026-10-31 HDS 兜底撤除整笔退役）。依赖组件状态的
// 对话/助手页签动作（新建会话/多选菜单/＋新建）留在 HomeNavigation。push 方法总口径：均无参 push
//（无保存动作页返回不挂 onPop，坑17 口径单源见 PageMapBuilder 文件头），各方法注释只记目标页身份
// 与差异行为。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import {
  ROUTE_COST_STATS_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_INFO_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_PROMPT_LIBRARY_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_SEARCH_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_NETWORK_PAGE,
  ROUTE_WEB_SERVICE_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_DATA_SYNC_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_WORKSPACE_MANAGE_PAGE,
  ROUTE_MOUNT_MANAGE_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_LIBRARY_PAGE
} from '../../common/RouteNames';

export class HomeNavActions {
  private pathStack: NavPathStack = new NavPathStack();

  constructor(pathStack: NavPathStack) {
    this.pathStack = pathStack;
  }

  // 设置页「服务商管理」行卡
  pushProvider(): void {
    this.pathStack.pushPathByName(ROUTE_PROVIDER_PAGE, null);
  }

  // 设置页「更多信息」行卡
  pushInfo(): void {
    this.pathStack.pushPathByName(ROUTE_INFO_PAGE, null);
  }

  // 设置页「提示词」行卡
  pushPrompts(): void {
    this.pathStack.pushPathByName(ROUTE_PROMPT_LIBRARY_PAGE, null);
  }

  // 设置页「偏好与外观」行卡
  pushPreferences(): void {
    this.pathStack.pushPathByName(ROUTE_PREFERENCES_PAGE, null);
  }

  // 设置页「数据与同步」行卡
  pushDataSync(): void {
    this.pathStack.pushPathByName(ROUTE_DATA_SYNC_PAGE, null);
  }

  // 设置页「功能模型」行卡（选择即时写键）
  pushFunctionalModel(): void {
    this.pathStack.pushPathByName(ROUTE_FUNCTIONAL_MODEL_PAGE, null);
  }

  // 设置页「用量统计」行卡（纯展示）
  pushUsageStats(): void {
    this.pathStack.pushPathByName(ROUTE_USAGE_STATS_PAGE, null);
  }

  // 设置页「费用估计」行卡（纯展示）
  pushCostStats(): void {
    this.pathStack.pushPathByName(ROUTE_COST_STATS_PAGE, null);
  }

  // 设置页「记忆」行卡（写操作即时落库）
  pushMemory(): void {
    this.pathStack.pushPathByName(ROUTE_MEMORY_PAGE, null);
  }

  // 设置页「存储管理」行卡（清理动作无回传结果）
  pushStorage(): void {
    this.pathStack.pushPathByName(ROUTE_STORAGE_PAGE, null);
  }

  // 设置页「工具调用」行卡
  pushTools(): void {
    this.pathStack.pushPathByName(ROUTE_TOOLS_PAGE, null);
  }

  // 设置页「文件工作区」行卡（增删改即时落库）
  pushWorkspace(): void {
    this.pathStack.pushPathByName(ROUTE_WORKSPACE_MANAGE_PAGE, null);
  }

  // 设置页「文件夹挂载」行卡（授权与行读写即时落定）
  pushMount(): void {
    this.pathStack.pushPathByName(ROUTE_MOUNT_MANAGE_PAGE, null);
  }

  // 设置页「网络」行卡（UA 写即持久化）
  pushNetwork(): void {
    this.pathStack.pushPathByName(ROUTE_NETWORK_PAGE, null);
  }

  // 设置页「Web 服务」行卡（开关/端口/口令写即持久化）
  pushWebService(): void {
    this.pathStack.pushPathByName(ROUTE_WEB_SERVICE_PAGE, null);
  }

  // 设置页「主动消息」行卡（开关与间隔档即时持久化）
  pushProactive(): void {
    this.pathStack.pushPathByName(ROUTE_PROACTIVE_PAGE, null);
  }

  // 设置页「技能库」行卡（增删改即时落库并广播 SKILL_LIST_TICK_KEY）
  pushSkillLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_SKILL_LIBRARY_PAGE, null);
  }

  // 设置页「知识库」行卡（增删改即时落库并广播 KNOWLEDGE_LIST_TICK_KEY）
  pushKnowledgeLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_LIBRARY_PAGE, null);
  }

  // 设置页签标题栏搜索键：官方路由 push 搜索页
  pushSearch(): void {
    this.pathStack.pushPathByName(ROUTE_SEARCH_PAGE, null);
  }

  // 设置页签标题栏搜索键菜单（HDS 主路径，hdsTitleBarOptions 第 5 参消费；官方放大镜符号坑72 口径）
  settingsSearchMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.magnifyingglass'),
          action: (): void => {
            this.pushSearch();
          }
        }
      }]
    };
  }
}
