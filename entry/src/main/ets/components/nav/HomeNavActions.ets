// 导航动作域（2026-09-01 自 HomeNavigation.ets 域级拆出——三页签（助手页签）接入后该
// 文件必超 400 红线；域边界 = 设置域六个二级页 push 编排 + 设置页签搜索菜单构造〔HDS/
// 回退双形态〕，方法体原样搬迁行为不变）。对话页签动作（新建会话/多选菜单）与助手页签
// 动作（＋新建）依赖组件状态/菜单域件，留在 HomeNavigation。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  ROUTE_APPEARANCE_PAGE,
  ROUTE_COST_STATS_PAGE,
  ROUTE_FUNCTIONAL_MODEL_PAGE,
  ROUTE_INFO_PAGE,
  ROUTE_MEMORY_PAGE,
  ROUTE_PREFERENCES_PAGE,
  ROUTE_PROMPT_LIBRARY_PAGE,
  ROUTE_PROVIDER_PAGE,
  ROUTE_SEARCH_ENGINE_PAGE,
  ROUTE_SEARCH_PAGE,
  ROUTE_TOOLS_PAGE,
  ROUTE_PROACTIVE_PAGE,
  ROUTE_DATA_SYNC_PAGE,
  ROUTE_SYSTEM_PROMPT_PAGE,
  ROUTE_STORAGE_PAGE,
  ROUTE_USAGE_STATS_PAGE,
  ROUTE_SKILL_LIBRARY_PAGE,
  ROUTE_KNOWLEDGE_LIBRARY_PAGE
} from '../../common/RouteNames';

export class HomeNavActions {
  private pathStack: NavPathStack = new NavPathStack();

  constructor(pathStack: NavPathStack) {
    this.pathStack = pathStack;
  }

  // 设置页「服务商管理」行卡：官方路由 push 二级页
  pushProvider(): void {
    this.pathStack.pushPathByName(ROUTE_PROVIDER_PAGE, null);
  }

  // 设置页「外观显示」行卡：官方路由 push 二级页（M2c 反馈轮 1 领导另批补卡）
  pushAppearance(): void {
    this.pathStack.pushPathByName(ROUTE_APPEARANCE_PAGE, null);
  }

  // 设置页「更多信息」行卡：官方路由 push 二级页（M2c 反馈轮 1 同类缺口一并补齐）
  pushInfo(): void {
    this.pathStack.pushPathByName(ROUTE_INFO_PAGE, null);
  }

  // 设置页「提示词」行卡：官方路由 push 管理页（2026-08-30 提示词注入）
  pushPrompts(): void {
    this.pathStack.pushPathByName(ROUTE_PROMPT_LIBRARY_PAGE, null);
  }

  // 设置页「系统提示词」行卡：push 独立页（2026-08-31 起——不再经编辑页全局分支；
  // 无参，页面自读 queryGlobalTemplate 回填）
  pushSystemPrompt(): void {
    this.pathStack.pushPathByName(ROUTE_SYSTEM_PROMPT_PAGE, null);
  }

  // 设置页「偏好设置」行卡：官方路由 push 二级页（2026-09-01 偏好设置页；无参——
  // 开关即时生效无保存键，返回不挂 onPop）
  pushPreferences(): void {
    this.pathStack.pushPathByName(ROUTE_PREFERENCES_PAGE, null);
  }

  // 设置页「数据与同步」行卡：push 二级页（2026-09-03 第三批③；无参）
  pushDataSync(): void {
    this.pathStack.pushPathByName(ROUTE_DATA_SYNC_PAGE, null);
  }

  // 设置页「功能模型」行卡：push 二级页（2026-09-05 功能模型页；无参——选择即时写键
  // 无保存动作，返回不挂 onPop）
  pushFunctionalModel(): void {
    this.pathStack.pushPathByName(ROUTE_FUNCTIONAL_MODEL_PAGE, null);
  }

  // 设置页「用量统计」行卡：push 二级页（2026-09-06 token 用量统计；无参——纯列表展示
  // 无保存动作，返回不挂 onPop）
  pushUsageStats(): void {
    this.pathStack.pushPathByName(ROUTE_USAGE_STATS_PAGE, null);
  }

  // 设置页「费用估计」行卡：push 二级页（2026-09-10 费用估计；无参——纯展示无保存动作，
  // 返回不挂 onPop）
  pushCostStats(): void {
    this.pathStack.pushPathByName(ROUTE_COST_STATS_PAGE, null);
  }

  // 设置页「记忆」行卡：push 二级页（2026-09-08 记忆域；无参——写操作即时落库无保存
  // 动作，返回不挂 onPop）
  pushMemory(): void {
    this.pathStack.pushPathByName(ROUTE_MEMORY_PAGE, null);
  }

  // 设置页「存储管理」行卡：push 二级页（2026-09-09 附件落盘第二轮；无参——清理动作不产
  // 生需回传的保存结果，返回不挂 onPop）
  pushStorage(): void {
    this.pathStack.pushPathByName(ROUTE_STORAGE_PAGE, null);
  }

  // 设置页「联网搜索」行卡：push 二级页（2026-09-10 多引擎一期；无参——开关与密钥配置
  // 即时持久化无保存动作，返回不挂 onPop）
  pushSearchEngine(): void {
    this.pathStack.pushPathByName(ROUTE_SEARCH_ENGINE_PAGE, null);
  }

  // 设置页「工具调用」行卡：push 二级页（2026-09-10 决明指令，先空占位——无编辑无保存
  // 动作，返回不挂 onPop）
  pushTools(): void {
    this.pathStack.pushPathByName(ROUTE_TOOLS_PAGE, null);
  }

  // 设置页「主动消息」行卡：push 二级页（2026-09-12 主动消息第一笔「触发链底层」；
  // 无参——开关与间隔档即时持久化无保存动作，返回不挂 onPop）
  pushProactive(): void {
    this.pathStack.pushPathByName(ROUTE_PROACTIVE_PAGE, null);
  }

  // 设置页「技能库」行卡：push 二级页（2026-09-13 技能层笔 1；无参——库页增删改即时落库
  // 并广播 SKILL_LIST_TICK_KEY，返回不挂 onPop）
  pushSkillLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_SKILL_LIBRARY_PAGE, null);
  }

  // 设置页「知识库」行卡：push 二级页（2026-09-21 世界书知识库首版；无参——库页增删改即时
  // 落库并广播 KNOWLEDGE_LIST_TICK_KEY，返回不挂 onPop）
  pushKnowledgeLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_LIBRARY_PAGE, null);
  }

  // 设置页签标题栏搜索键：官方路由 push 搜索页（dshinhm「我的」页同位——标题栏右上角）
  pushSearch(): void {
    this.pathStack.pushPathByName(ROUTE_SEARCH_PAGE, null);
  }

  // 设置页签标题栏搜索键菜单（HDS 主路径，hdsTitleBarOptions 第 5 参消费；dshinhm
  // searchMenuHds 同款构造——官方放大镜符号 resources.txt 实锤，坑72 口径）
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

  // 回退路径搜索菜单（无 HDS：Navigation.menus 姿势，dshinhm buildFallbackMenus 同款）
  settingsSearchMenuFallback(): NavigationMenuItem[] {
    return [{
      value: '搜索',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')),
      action: (): void => {
        this.pushSearch();
      }
    } as NavigationMenuItem];
  }
}
