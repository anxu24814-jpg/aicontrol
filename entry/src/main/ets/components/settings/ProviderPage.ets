// 服务商管理列表页（自包 PageShell 壳）：
// 结构 = 标题栏下分段胶囊悬浮吸顶（已启用/已停用两分段，SegmentBar；开关启停 reload 后卡片按
// enabled 归段）+ 服务商卡片 List。每卡 = 名称 + Base URL 副行 + 徽章行（OpenAI 兼容 / N 模型 /
// 已停用）+ 启用开关 + 行尾四点键菜单（编辑 / 分享 / 打开官网——仅内置家显示，判据见
// menuCallbacks）；删除统一走行左滑确认链（菜单「删除」已退役）。
// ★ 单家导出唯一入口 = exportShareConfig（ProviderShareFlow.ets）——高级页同名按钮退役后本菜单
//   项即全应用唯一单家导出入口。
// ★ 长按拖拽原位排序：本页 List 挂 .clip(false) + ForEach 挂官方 onMove——内边距与卡宽零改；
//   排序页 ProviderSortPage 已退役（其转向理由 = 坑10 浮起被列表裁切，由 clip(false) 消解）。
//   拖拽落定 = 数据源按「可见行槽位回填」重排 + 全量回写 sortOrder（落库序是全局序，列表按分段
//   过滤显示——语义见 applyDragMove）。卡上不留拖拽手柄。
// 列表顶/底留白全量走官方 contentStartOffset/contentEndOffset（坑9；起始偏移 = 分段胶囊悬浮位
// 下方）——卡片上滚依次穿过胶囊背板与标题栏蒙层两道光感。
// 入口结构：设置页「服务商管理」行卡 push 本页；标题栏（ProviderTitleMenu 域件）= 右上角
// 合并胶囊〔＋新建服务商 | ⋯更多〕（新建 = push 详情页新建态〔恒传空串，坑12〕/ 更多 = 弹菜单 =
// 分享配置〔exportShareAll〕/ 导入配置〔importShareConfig〕/ 价格模板——「刷新」项已撤，与进页/
// 返回重拉及写动作自刷重复）。点卡片 push 编辑态；删除 =
// ConfirmDialog（官方实底）→ deleteProvider 事务级联 + Asset key 清理 + 当前选择失效（解析侧兜底）。
// 刷新通道：★ 坑17·onPop（子页 pop 必带 result）为保存路径可靠原语；★ onShown 兜底并存（坑25
// 「每次页面显示触发含 pop 返回」）——编辑页自动查余额只写库不 pop result，裸返回的余额联动归
// 本通道；reload 防重入门见 reloading 注释。
// ★ 裁剪口径（对照参考图）：余额徽章不做；顶部聊天键不做（聊天即主页签，语义重复）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { whenReady } from '../../common/store/ChatDb';
import { SETTING_TITLE_PROVIDER } from '../../common/SettingSearch';
import {
  deleteProvider, ProviderRow,
  queryProviders, saveProviderOrder, setProviderEnabled
} from '../../common/store/ProviderDb';
import { removePoolKeys } from '../../common/store/KeyStore';
import { queryProviderKeys, ProviderKeyRow } from '../../common/store/ProviderKeyDb';
import { ENDPOINT_CHAT, PROTOCOL_OPENAI } from '../../common/providers/AiTypes';
import { providerOfficialSite } from '../../common/providers/ProviderCatalog';
import { launchExternalLink } from '../../common/ExternalLink';
import { KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import {
  CARD_SPACING, SEGMENT_BAR_HEIGHT, TITLE_BAR_MASK_EXTRA_HEIGHT,
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, badgeBg, cardBg, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { PageTopSegmentBand } from '../SegmentBar';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import {
  PROVIDER_CARD_MENU_ID_PREFIX, ProviderCardMenuCallbacks, ProviderCardMenuHost
} from './ProviderCardMenu';
import { exportShareAll, exportShareConfig, importShareConfig } from './ProviderShareFlow';

import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { ProviderCardItem } from './ProviderCardItem';
import {
  PROVIDER_TITLE_MENU_ANCHOR_ID, ProviderTitleBarKeys, ProviderTitleMenuCallbacks,
  ProviderTitleMenuHost
} from './ProviderTitleMenu';
import { ROUTE_PRICE_TEMPLATE_PROVIDERS_PAGE, ROUTE_PROVIDER_DETAIL_PAGE } from '../../common/RouteNames';

@Component
export struct ProviderPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行（数据层意图照常完成）
  private departed: boolean = false;
  // 顶部留白（vp，PageMapBuilder 注入——首卡落标题栏蒙层下方）
  @Prop topPad: number = 0;
  // 底部留白（vp = 避让区高，PageMapBuilder 注入——列表尾卡不压手势条）
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感总档（标题栏自绘键与菜单宿主共用——覆盖层组件不在 PageShell 参数链上）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 分段选中（0 已启用 / 1 已停用；SegmentBar @Link 双向）
  @State private segIndex: number = 0;

  // 标题栏下方带承载：胶囊经官方 bottomBuilder 承载，内容区件在 API 26 不出材质，
  // 迁入标题栏生效区即恢复光感。几何全在 PageTopSegmentBand（带顶 = 标题栏下沿不是 topPad）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.segItems,
      selectedIndex: $segIndex
    })
  }

  private segItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '已启用' },
    { text: '已停用' }
  ]);
  @State private rows: ProviderRow[] = [];
  @State private hintText: string = '';
  // 卡片重建纪元（坑16：reload 成功自增 → ForEach 键含纪元 → 整卡重建 → 卡内 aboutToAppear 自拉重跑）
  @State private cardEpoch: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 口令弹窗控制器（分享导出「包含密钥」档用）。★ askPassphrase 样板全仓两处（本页 / DataSyncPage）
  // ——共享化须把控制器构造移出组件方法，落坑7 家族，已登记技术债务清单
  private passCtrl: CustomDialogController | null = null;

  // 口令输入弹窗（resolve 文本 / 取消 resolve null——Promise 恒 settle）。★ 两个取消口都要接：
  // onCancel = 弹窗内「取消」键（程序化 close，不触发控制器级 cancel——只接 cancel 时此键让 Promise
  // 永挂、busy 卡死置灰）；cancel = 返回键/点遮罩/Esc。少接一个就有一种姿势锁死按钮
  private askPassphrase(title: string, placeholder: string): Promise<string | null> {
    return new Promise<string | null>((resolve: (value: string | null) => void) => {
      this.passCtrl = new CustomDialogController({
        systemMaterial: overlayMaterial(),
        builder: InputDialog({
          title: title,
          initialText: '',
          placeholder: placeholder,
          confirmLabel: '确认',
          password: true,
          onConfirm: (text: string): void => {
            resolve(text);
          },
          onCancel: (): void => {
            resolve(null);
          }
        }),
        autoCancel: true,
        cancel: (): void => {
          resolve(null);
        },
        alignment: DialogAlignment.Center
      });
      this.passCtrl.open();
    });
  }
  // 卡片菜单节点宿主（init/open/dispose 成对，见 ProviderCardMenu.ets）
  private cardMenu: ProviderCardMenuHost = new ProviderCardMenuHost();
  // 标题栏更多菜单节点宿主（init/open/dispose 成对，见 ProviderTitleMenu.ets）
  private titleMenu: ProviderTitleMenuHost = new ProviderTitleMenuHost();
  private pendingDelete: ProviderRow | null = null;
  // 行左滑删除互斥组（RowSwipeDelete 单源下发；reload / 拖拽落定 / 滚动开始三路收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  // reload 防重入门：保存返回时 onPop 与 onShown 双通道各触发一次 reload → queryProviders 双拉
  // + cardEpoch 双自增。进行中直接 return 只消重复执行，不破「onPop 可靠原语 + onShown 兜底」
  // 双链并存结构；whenReady 恒不 reject、query 两支均复位，flag 无悬挂路径
  private reloading: boolean = false;

  aboutToAppear(): void {
    this.reload();
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyRow()));
    this.titleMenu.init(this.getUIContext(), this.titleCallbacks());
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.cardMenu.dispose();
    this.titleMenu.dispose();
  }

  private emptyRow(): ProviderRow {
    return { id: '', name: '', baseUrl: '', enabled: true, sortOrder: 0, createdAt: 0,
      balanceEnabled: false, balanceLastText: '', protocol: PROTOCOL_OPENAI, headers: '',
      endpoint: ENDPOINT_CHAT, promptCacheEnabled: false, promptCacheTtl: '5m', bodyOverrides: '',
      keyPickMode: KEY_PICK_ROTATE, builtin: false };
  }

  private reload(): void {
    // 防重入门：进行中直接 return（双通道并存下的重复执行只跑一次）
    if (this.reloading) {
      return;
    }
    this.reloading = true;
    // DB 就绪守卫：DB 未就绪直查抛「数据库未就绪」且提示钉死；先等 whenReady 再拉，init 失败
    // 提示重启（缓存 false 无重试）
    whenReady().then((ok: boolean): void => {
      if (this.departed) {
        this.reloading = false;
        return;
      }
      if (!ok) {
        this.reloading = false;
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      queryProviders()
        .then((rows: ProviderRow[]): void => {
          this.reloading = false;
          if (this.departed) {
            return;
          }
          this.rows = rows; // 一次性赋值（状态修改合并为一次刷新）
          this.hintText = '';
          // 列表整组重拉即收口行左滑展开态（RowSwipeDelete 键含纪元整卡重建，双保险）
          this.swipeGroup.collapse();
          // 坑16：纪元自增进 ForEach 键 → 全卡重建 → 卡内自拉重跑（计数/余额随库刷新）
          this.cardEpoch += 1;
        })
        .catch((e: Object): void => {
          this.reloading = false;
          if (this.departed) {
            return;
          }
          this.hintText = '服务商列表读取失败：' + (e as Error).message;
        });
    });
  }

  // 菜单回调组装（init/open 两处共用；显式接口构造——坑72：union 上下文禁匿名对象字面量）
  private menuCallbacks(row: ProviderRow): ProviderCardMenuCallbacks {
    const callbacks: ProviderCardMenuCallbacks = {
      item: row,
      // 「打开官网」准入（只适用内置服务商）：builtin 与官网表域名**双条件**——内置行的 Base URL
      // 可在详情页改写，改成中转站后域名不再代表这家，映射落空即空串 = 菜单整项不渲染（fail-safe）
      siteUrl: row.builtin ? providerOfficialSite(row.baseUrl) : '',
      onEdit: (item: ProviderRow): void => {
        this.openDetail(item.id);
      },
      onShare: (item: ProviderRow): void => {
        this.shareProvider(item);
      },
      onOpenSite: (item: ProviderRow): void => {
        this.openOfficialSite(item);
      }
    };
    return callbacks;
  }

  // 分享：单家导出唯一实现 = exportShareConfig（对话框三选 → 缺失确认 → 口令 → 加密/序列化 →
  // 沙箱文件 → 系统分享面板）；失败/取消均函数内部兜底（P0-1）
  private shareProvider(item: ProviderRow): void {
    if (item.id === '') {
      return;
    }
    exportShareConfig(this.getUIContext(), item.id,
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder));
  }

  // 打开官网：内置家跳各家开放平台控制台。准入已在 menuCallbacks 裁定——本方法只做「查表 →
  // 取宿主上下文 → 交统一外链出口」；★ 用户主动点击场景失败给中文提示不静默（隐私政策页同口径）；
  // 地址查空直接返回（防御：正常不达）
  private openOfficialSite(item: ProviderRow): void {
    const siteUrl: string = providerOfficialSite(item.baseUrl);
    if (siteUrl === '') {
      return;
    }
    try {
      // 宿主上下文走 UIContext 形态（禁全局 getContext）
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, siteUrl, (): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '无法打开官网，请稍后重试' });
      });
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '无法打开官网，请稍后重试' });
    }
  }

  private openCardMenu(row: ProviderRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row),
      AppStorage.get<number>(IMMERSIVE_LEVEL_KEY) ?? 0);
  }

  // 开关落库 + 本地行同步（失败回滚态提示——重拉恢复真值，P0-1 不静默）。★ 停用即解绑：停用会
  // 解除引用它的模型选择（助手绑定 / 会话覆盖 / 功能模型 8 槽），有解除时给回执（用户得知道那些
  // 槽位为什么变成「未选择」）
  private toggleProvider(row: ProviderRow, isOn: boolean): void {
    setProviderEnabled(row.id, isOn)
      .then((cleared: number): void => {
        if (!this.departed && cleared > 0) {
          this.getUIContext().getPromptAction().showToast({
            message: '已停用，引用它的模型选择已解除'
          });
        }
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '操作失败：' + (e as Error).message });
        this.reload();
      });
  }

  // 删除确认（官方实底弹窗，三处删除同款材质）
  private openDeleteConfirm(row: ProviderRow): void {
    this.pendingDelete = row;
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除服务商',
        message: '将删除「' + row.name + '」及其模型配置与 API 密钥，不可恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deletePending();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 删除执行：查池条目 id → 库内事务级联（服务商行 + 模型行 + key 池行）→ Asset 池条目成对清理
  //（数据层照常完成，判守只在 UI 动作前）→ 当前选择失效 → 重拉 + toast
  private async deletePending(): Promise<void> {
    const row: ProviderRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    try {
      // 池条目 id 先于删行查得（Asset 无前缀查询能力，按名逐条删——成对释放红线）
      const keyRows = await queryProviderKeys(row.id);
      const keyIds: string[] = keyRows.map((key: ProviderKeyRow): string => key.id);
      await deleteProvider(row.id);
      await removePoolKeys(row.id, keyIds);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除「' + row.name + '」' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 标题栏 ＋ 键：新建服务商 = push 详情页新建态。★ 恒传空串，勿传 null——坑12 真机实锤（null
  // 被详情页读作编辑 id →「新建秒退」+ 不存在 toast；参数契约 string）
  private openAdd(): void {
    this.openDetail('');
  }

  // 详情页跳转（卡片点击 = 编辑态携 id；＋ 键新建 = 新建态空串）。★ 勿回传 null：参数契约 =
  // string，null 曾被误读为编辑 id 致「新建秒退」（坑12）。
  // ★ onPop 返回即 reload（纪元自增 → 整卡重建重拉），官方回调链不经过 @BuilderParam content
  // 传播；★ onShown 兜底并存（裸返回无 result 的重拉归 onShown），本回调保留为保存路径可靠原语
  private openDetail(providerId: string): void {
    this.pathStack.pushPathByName(ROUTE_PROVIDER_DETAIL_PAGE, providerId, (): void => {
      this.reload();
    });
  }

  // 价格模板管理入口：push 无参——选择页自拉服务商全集（含停用与内置），点行再携 providerId 进
  // 原模板列表页；本页无联动数据，返回无参 pop 不挂 onPop（坑17 口径）
  private openPriceTemplates(): void {
    this.pathStack.pushPathByName(ROUTE_PRICE_TEMPLATE_PROVIDERS_PAGE, null);
  }

  // 标题栏「更多」菜单回调（分享配置 / 批量导入 / 价格模板三项；「新建」由覆盖层 ＋ 键直连
  // openAdd；「排序」随排序页退役改原位拖拽；「刷新」已撤，见文件头；坑72：禁匿名对象字面量）
  private titleCallbacks(): ProviderTitleMenuCallbacks {
    const callbacks: ProviderTitleMenuCallbacks = {
      onShareAll: (): void => {
        this.shareAllProviders();
      },
      onImportAll: (): void => {
        this.importProviders();
      },
      onPriceTemplates: (): void => {
        this.openPriceTemplates();
      }
    };
    return callbacks;
  }

  // 批量分享：打包全部已启用服务商——编排 = exportShareAll（与单家 exportShareConfig 同一对话框
  // 三选语义；口令弹窗回调就地注入本页 askPassphrase）
  private shareAllProviders(): void {
    exportShareAll(this.getUIContext(),
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder));
  }

  // 批量导入：选文件 → 解析 → 预览分服务商 → 逐家新增；onDone = 列表 reload（导入的副本即刻上屏）
  private importProviders(): void {
    importShareConfig(this.getUIContext(),
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder),
      (): void => {
        this.reload();
      });
  }

  // 标题栏覆盖层（右上角合并胶囊〔＋新建服务商 | ⋯更多〕）——组件内 @Builder 挂载是
  // 硬约束（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图上下文，启动即闪退）；
  // 键件与几何在 ProviderTitleMenu.ets，本页只注入三参
  @Builder
  TitleBarKeys() {
    ProviderTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onAdd: (): void => {
        this.openAdd();
      },
      onMore: (): void => {
        this.openTitleMenu();
      }
    })
  }

  // 标题栏更多菜单弹出（胶囊右热区 action；锚点右缘与 ⋯ 键右缘同值 16，故「更多」必须是胶囊
  // 右热区末键）
  private openTitleMenu(): void {
    this.titleMenu.open(this.getUIContext(), this.titleCallbacks(), this.immersiveLevel);
  }

  // 分段可见性判据（单源：visibleRows 过滤与拖拽槽位回填共用——两处分家会让「拖拽落定后的
  // 显示序」与「可见行集合」失步）
  private inCurrentSegment(row: ProviderRow): boolean {
    return this.segIndex === 0 ? row.enabled : !row.enabled;
  }

  // 当前分段可见行（0 已启用 / 1 已停用）：开关启停 reload 后行按 enabled 归段——卡片从当前分段
  // 消失、另一分段可见；分段切换 = 状态过滤即时生效；详情页改动 pop 回来 = onPop 自动 reload 归段
  private visibleRows(): ProviderRow[] {
    return this.rows.filter((row: ProviderRow): boolean => this.inCurrentSegment(row));
  }

  // 原位拖拽落定：onMove 上报的 from/to 是**可见行数组**（当前分段过滤后）的下标，而落库序
  // sortOrder 是**全量全局序**——直接对 this.rows 做 splice 会落错位置。语义 = 可见行在自己占的
  // 槽位内换位：全量序中属于当前分段的位置按新可见序逐个回填，另一分段的行相对位置一动不动
  //（例：[A启 B停 C启] 在已启用段把 C 拖到 A 前 → [C启 B停 A启]）。回写 = saveProviderOrder 全量 ids
  private applyDragMove(from: number, to: number): void {
    const visible: ProviderRow[] = this.visibleRows();
    if (from === to || from < 0 || to < 0 || from >= visible.length || to >= visible.length) {
      return;
    }
    const nextVisible: ProviderRow[] = visible.slice();
    const moved: ProviderRow = nextVisible.splice(from, 1)[0];
    nextVisible.splice(to, 0, moved);
    let cursor: number = 0;
    const nextAll: ProviderRow[] = this.rows.slice();
    for (let i = 0; i < nextAll.length; i++) {
      if (this.inCurrentSegment(nextAll[i])) {
        nextAll[i] = nextVisible[cursor];
        cursor++;
      }
    }
    this.rows = nextAll;
    // 拖拽落定行序重排，展开行随重排移动观感错乱——一并收口
    this.swipeGroup.collapse();
    saveProviderOrder(nextAll.map((row: ProviderRow): string => row.id))
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 列表内容起始偏移（分段胶囊悬浮位下方——胶囊顶 = topPad − 蒙层渐隐边缘 8 + 胶囊高 40 + 28）
  private listStartOffset(): number {
    return Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28;
  }

  // 左滑删除入口（RowSwipeDelete 单源）：按 id 查行走既有确认链；菜单「删除」退役后本入口为唯一删除路径
  private askDeleteById(id: string): void {
    const row: ProviderRow | undefined =
      this.rows.find((item: ProviderRow): boolean => item.id === id);
    if (row !== undefined) {
      this.openDeleteConfirm(row);
    }
  }

  @Builder
  ProviderCard(row: ProviderRow) {
    ProviderCardItem({
      row: row,
      // modelCount/balance 派生展示由卡内自拉——本装配不传派生值；刷新 = onPop/onShown → reload
      // → 纪元键整卡重建
      menuAnchorId: PROVIDER_CARD_MENU_ID_PREFIX + row.id,
      onOpen: (tapped: ProviderRow): void => {
        this.openDetail(tapped.id);
      },
      onToggle: (toggled: ProviderRow, isOn: boolean): void => {
        this.toggleProvider(toggled, isOn);
      },
      onMenu: (menuRow: ProviderRow): void => {
        this.openCardMenu(menuRow);
      }
    })
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。外层 Stack 两层：
  // 标题栏更多菜单隐形锚点（几何 = 日志页「按钮下沿」公式，坑11；★ MORE_MENU_ANCHOR_RIGHT(16)
  // 与 TITLE_BAR_EDGE_INSET(16) 恒同值——单边改动即菜单横偏）+ 滚动层
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Row() {
        Blank()
        Column()
          .width(1)
          .height(1)
          .id(PROVIDER_TITLE_MENU_ANCHOR_ID)
      }
      .width('100%')
      .padding({ right: MORE_MENU_ANCHOR_RIGHT })
      .margin({ top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0) })
      List({ space: CARD_SPACING }) {
        ForEach(this.visibleRows(), (row: ProviderRow) => {
          // ★ 条目层同挂 borderRadius(16)——**拖拽快照的矩形底靠它消**（真机实拍：长按后卡片圆角
          // 处露出一圈极淡的直角蒙层；删了即复发）。条目宽 = 卡宽，两处圆角同值即逐边重合
          ListItem() {
            // 行左滑删除层：卡满行宽（List padding 左右 16 收窄）→ cardInset 0；内置行不可删
            //（数据层硬拦截——无删除能力即不挂左滑）；展开态不进键
            RowSwipeDelete({
              rowId: row.id,
              swipeEnabled: !row.builtin,
              group: this.swipeGroup,
              cardInset: 0,
              content: (): void => {
                this.ProviderCard(row)
              },
              onSwipeDelete: (rowId: string): void => {
                this.askDeleteById(rowId);
              }
            })
          }
          .borderRadius(CARD_RADIUS)
          // 坑16：键含 cardEpoch——reload 成功纪元自增 → 整卡重建 → 卡内自拉重跑；行身份仍 =
          // row.id（纪元全局同变不影响 diff）
        }, (row: ProviderRow): string => row.id + '|' + this.cardEpoch)
          // ★ 原位拖拽排序：官方 onMove（仅适用于 List）；离手上报 from/to = 可见行下标 →
          // applyDragMove 槽位回填 + 落库。拖拽期间禁改数据源（官方红线：离手前改会让落位动画
          // 错乱）——本回调只在离手后跑
          .onMove((from: number, to: number): void => {
            this.applyDragMove(from, to);
          })

        if (this.rows.length === 0 && this.hintText === '') {
          ListItem() {
            Column({ space: 8 }) {
              Text('暂无服务商')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('点右上角加号键新建，或在详情页保存后回到此页')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            .padding(24)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)
          }
        }
        if (this.rows.length > 0 && this.visibleRows().length === 0 && this.hintText === '') {
          ListItem() {
            Text(this.segIndex === 0 ? '暂无已启用的服务商' : '暂无已停用的服务商')
              .fontSize(13)
              .fontColor(cardDescColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding(24)
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(CARD_RADIUS)
          }
        }
        if (this.hintText !== '') {
          ListItem() {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('100%')
          }
        }
      }
      .width('100%')
      .height('100%')
      // ★ 顶/底留白走官方 offset（属滚动内容，卡片可滑入胶囊背板与标题栏蒙层背后 = 双道光感；
      // List padding 顶/底 = 视口缩进会裁掉内容 = 坑9 根因勿回迁）
      .contentStartOffset(this.listStartOffset())
      .contentEndOffset(this.bottomPad + 16)
      // 左右 16 = 卡片水平居中收窄；顶/底禁用 padding（见上）
      .padding({ left: 16, right: 16 })
      // ★ 关裁剪（核心一行）：List 的水平 padding = 视口缩进，长按拖拽浮起的卡片会被这圈边界削成
      // 直边（坑10 根因），官方对 onMove 的预览无旋钮（dragPreview 只对 onDragStart 生效）——解法
      // 只在几何：关掉列表自身裁剪。代价面 = 内容与回弹也会越出列表边界（上缘出屏、下缘落避让区、
      // 左右为屏缘）。
      // ★ 勿回删本行：删掉即复发坑10
      .clip(false)
      // 短内容也上下可拖（alwaysEnabled，会话列表同款）+ 滚动条常关
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      // 滚动开始即收口行左滑展开态（会话列表/五库同口径）
      .onScrollStart((): void => {
        this.swipeGroup.collapse();
      })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_PROVIDER,
      // 标题栏两键：〔＋新建服务商〕= push 详情页新建态 /〔⋯更多〕= 弹菜单（分享配置 / 导入配置 /
      // 价格模板）。标题栏 = 覆盖层合并胶囊（键件 = ProviderTitleBarKeys，menuHds 传 null，
      // keepStackTitle = true 保主标题）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarKeys();
      },
      keepStackTitle: true,
      // 标题栏下方带承载（分段胶囊经官方 bottomBuilder 承载）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      // onShown 兜底重拉：每次页面显示含 pop 返回即重拉（坑25「onShown 是可靠姿势」；与 onPop
      // 两链并存 + reload 防重入门——保存返回双通道只执行一次，见 reloading 注释）。编辑页自动
      // 查余额只写库不 pop result，裸返回的余额数字联动归本通道
      onShown: (): void => {
        this.reload();
      },
      content: (): void => {
        this.Content()
      }
    })
  }
}
