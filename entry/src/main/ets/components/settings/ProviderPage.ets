// 服务商管理列表页（2026-08-30 反馈轮 2 起自包 PageShell 壳——★ 坑16·2026-08-30 刷新
// 链定稿：刷新 = reload（菜单「刷新」键 / 详情页·排序页 onPop / 开关启停 / 删除回调）
// 成功自增 cardEpoch → ForEach 键含纪元整卡重建 → 卡内自拉重跑；旧 tick 广播在 push
// 页内 @StorageProp @Watch 实测不触发已删、徽章 @Builder 值参快照已改 ForEach 重建；图片参考
// 形态对齐）：标题栏下分段胶囊悬浮吸顶（2026-08-30 反馈轮 9 领导指令——已启用/已停用
// 两分段，日志页成熟实现同款 SegmentBar；开关启停 reload 后卡片按 enabled 归段）+
// 服务商卡片 List（官方 List({space})
// 设置列表卡片口径）—— 每卡 = 名称 + Base URL 副行 + 徽章行（OpenAI 兼容 /
// N 模型 / 已停用）+ 启用开关 + 四点菜单键（编辑/分享/删除——2026-09-03 加「分享」，
// 单家导出唯一入口 = 编排 exportShareConfig，ProviderShareFlow.ets；2026-09-20 高级页
// 同名导出按钮随卡退役后本项即全应用唯一单家导出入口）。★ 长按拖拽已移除
//（2026-08-30 反馈轮 6，领导方案——坑10 浮起被列表内容区裁切且 dragPreview 无效，排序
// 独立成页：标题栏更多菜单「排序」push ProviderSortPage 长按排序；卡上拖拽手柄随之
// 移除防误导）。列表顶/底留白全量
// 走官方 contentStartOffset/contentEndOffset（反馈轮 3 接入光感、轮 4 摘双轨全量化，坑9，
// 真机确认；轮 9 起始偏移 = 分段胶囊悬浮位下方）——卡片上滚依次穿过胶囊背板与标题栏
// 蒙层两道光感。
// 入口结构（入口放服务商管理卡片——领导指令）：设置页「服务商管理」行卡 push 本页；
// 本页标题栏（ProviderTitleMenu 域件）——★ 2026-09-22 决明「标题栏更多菜单，新建键移出与
// 更多形成双键胶囊，参考消息页实现，功能不变」：HDS 路径右上角 = 合并胶囊〔＋新建服务商 |
// ⋯更多〕（新建 = push 详情页新建态〔恒传空串，坑12〕/ 更多 = 弹菜单四项 = 刷新〔手动重拉〕/
// 分享配置〔批量打包已启用服务商 exportShareAll〕/ 导入配置〔importShareConfig，预览分服务商〕/
// 排序〔push 排序页〕）；回退路径 = 官方菜单数组两键同序；点卡片 push 编辑态；删除 =
// ConfirmDialog（官方实底，与删除会话/删除模型同款）→ deleteProvider 事务级联 + Asset key
// 清理 + 当前选择失效（解析侧另有兜底）。
// 刷新通道（2026-08-30 收敛前为 onShown + 广播双保险——多轮不可靠后领导拍板去自动链，
// 改手动刷新键；历史见变更记录当日节）。★ 坑17·2026-08-30 全链统一：自动刷新恢复 =
// onPop（子页 pop 必带 result——保存/删除 pop({ saved/deleted: true })、排序页
// onBackPressed 拦截 → pop({ saved: true })；onPop 触发条件官方 d.ts 实锤，见
// PromptEditPage 注释）。
// ★ 裁剪口径（对照参考图）：余额徽章不做（领导明确）；顶部聊天键不做（aicontrol 聊天即
// 主页签，语义重复）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { whenReady } from '../../common/store/ChatDb';
import { SETTING_TITLE_PROVIDER } from '../../common/SettingSearch';
import {
  deleteProvider, ProviderRow,
  queryProviders, setProviderEnabled
} from '../../common/store/ProviderDb';
import { removePoolKeys } from '../../common/store/KeyStore';
import { queryProviderKeys, ProviderKeyRow } from '../../common/store/ProviderKeyDb';
import { ENDPOINT_CHAT, PROTOCOL_OPENAI } from '../../common/providers/AiTypes';
import { KEY_PICK_ROTATE } from '../../common/store/ProviderKeyDb';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import {
  CARD_SPACING, CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, TITLE_BAR_MASK_EXTRA_HEIGHT,
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, badgeBg, cardBg, cardDescColor,
  cardTitleColor
} from '../../common/Theme';
import { SegmentBar } from '../SegmentBar';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import {
  PROVIDER_CARD_MENU_ID_PREFIX, ProviderCardMenuCallbacks, ProviderCardMenuHost
} from './ProviderCardMenu';
import { exportShareAll, exportShareConfig, importShareConfig } from './ProviderShareFlow';

import { ProviderCardItem } from './ProviderCardItem';
import {
  PROVIDER_TITLE_MENU_ANCHOR_ID, ProviderTitleBarKeys, ProviderTitleMenuCallbacks,
  ProviderTitleMenuHost, providerMoreMenuNav
} from './ProviderTitleMenu';
import { ROUTE_PROVIDER_DETAIL_PAGE, ROUTE_PROVIDER_SORT_PAGE } from '../../common/RouteNames';

// （坑16·2026-08-30：列表广播键与行内 tick 键均已删——push 页内订阅不触发；刷新链
// 定稿见文件头注释）
@Component
export struct ProviderPage {
  // 顶部留白（vp，PageMapBuilder 注入——首卡落标题栏蒙层下方）
  @Prop topPad: number = 0;
  // 底部留白（vp = 避让区高，PageMapBuilder 注入——列表尾卡不压手势条）
  @Prop bottomPad: number = 0;
  // 官方路由栈（「+」键 push 详情页新建态 / 卡片跳转编辑态）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感总档（2026-09-22 合并胶囊笔新增）：标题栏自绘键须显式下发档位（PageShell 自订阅
  // 同名键但覆盖层组件不在其参数链上），菜单宿主弹出亦消费同一值——一处订阅两处共用
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 分段选中（0 已启用 / 1 已停用——2026-08-30 反馈轮 9 领导指令；SegmentBar @Link 双向）
  @State private segIndex: number = 0;
  // 分段选项（纯展示普通成员——SegmentBar 契约，变化场景无）
  private segItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '已启用' },
    { text: '已停用' }
  ]);
  @State private rows: ProviderRow[] = [];
  @State private hintText: string = '';
  // 卡片重建纪元（坑16·2026-08-30：reload 成功自增 → ForEach 键含纪元 → 整卡重建 →
  // 卡内 aboutToAppear 自拉重跑；替代 push 页内实测不触发的 tick 广播，与复活的
  // onPop 回 reload 组成当前唯一刷新链）
  @State private cardEpoch: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 口令弹窗控制器（分享导出「包含密钥」档用；★ askPassphrase 同款样板现两处
  //（本页 / DataSyncPage）——2026-09-20 高级页迁移卡退役后原第三处随卡删除；共享化须把
  // 控制器构造移出组件方法，落坑7 家族，暂不提取，已登记技术债务清单（偿还时机 =
  // 真机在场提取并同轮验弹窗））
  private passCtrl: CustomDialogController | null = null;

  // 口令输入弹窗（resolve 文本 / 用户取消 resolve null——Promise 恒 settle，编排侧判空）
  // ★ 两个取消口都要接（2026-09-10 报障修复）：onCancel = 弹窗内「取消」键（程序化 close，
  // 不触发控制器级 cancel——原只有 cancel 时此键让 Promise 永挂、busy 卡死置灰）；
  // cancel = 返回键/点遮罩/Esc（d.ts 原文）。少接一个就有一种取消姿势把按钮锁死。
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
  // 标题栏更多菜单节点宿主（新建/排序两项，见 ProviderTitleMenu.ets）
  private titleMenu: ProviderTitleMenuHost = new ProviderTitleMenuHost();
  // 菜单删除目标（确认弹窗回调持引用）
  private pendingDelete: ProviderRow | null = null;

  aboutToAppear(): void {
    this.reload();
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyRow()));
    this.titleMenu.init(this.getUIContext(), this.titleCallbacks());
  }

  aboutToDisappear(): void {
    this.cardMenu.dispose();
    this.titleMenu.dispose();
  }

  private emptyRow(): ProviderRow {
    return { id: '', name: '', baseUrl: '', enabled: true, sortOrder: 0, createdAt: 0,
      balanceEnabled: false, balanceLastText: '', protocol: PROTOCOL_OPENAI, headers: '',
      endpoint: ENDPOINT_CHAT, promptCacheEnabled: false, promptCacheTtl: '5m', bodyOverrides: '',
      keyPickMode: KEY_PICK_ROTATE };
  }

  private reload(): void {
    // DB 就绪守卫（2026-08-30 与 ChatSessionList 同族竞态修复）：DB 未就绪直查抛「数据库
    // 未就绪」且提示钉死；先等 whenReady 再拉，init 失败提示重启（缓存 false 无重试）
    whenReady().then((ok: boolean): void => {
      if (!ok) {
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      queryProviders()
        .then((rows: ProviderRow[]): void => {
          this.rows = rows; // 一次性赋值（状态修改合并为一次刷新）
          this.hintText = '';
          // 坑16：纪元自增进 ForEach 键 → 全卡重建 → 卡内自拉重跑（计数/余额随库刷新）
          this.cardEpoch += 1;
        })
        .catch((e: Object): void => {
          this.hintText = '服务商列表读取失败：' + (e as Error).message;
        });
    });
  }

  // 菜单回调组装（init/open 两处共用；显式接口构造——坑72：union 上下文禁匿名对象字面量）
  private menuCallbacks(row: ProviderRow): ProviderCardMenuCallbacks {
    const callbacks: ProviderCardMenuCallbacks = {
      item: row,
      onEdit: (item: ProviderRow): void => {
        this.openDetail(item.id);
      },
      onShare: (item: ProviderRow): void => {
        this.shareProvider(item);
      },
      onDelete: (item: ProviderRow): void => {
        this.openDeleteConfirm(item);
      }
    };
    return callbacks;
  }

  // 分享（2026-09-03 卡片菜单项）：单家导出唯一实现 = ProviderShareFlow.ets 导出的
  // exportShareConfig（对话框三选 → 缺失确认 → 口令 → 加密/序列化 → 沙箱文件 → 系统分享
  // 面板；2026-09-20 高级页同名按钮随迁移卡退役，本项自此为该编排全应用唯一入口）；
  // 失败/取消均函数内部兜底（P0-1）
  private shareProvider(item: ProviderRow): void {
    if (item.id === '') {
      return;
    }
    exportShareConfig(this.getUIContext(), item.id,
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder));
  }

  private openCardMenu(row: ProviderRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row),
      AppStorage.get<number>(IMMERSIVE_LEVEL_KEY) ?? 0);
  }

  // 开关落库 + 本地行同步（失败回滚态提示——重拉恢复真值，P0-1 不静默）
  private toggleProvider(row: ProviderRow, isOn: boolean): void {
    setProviderEnabled(row.id, isOn)
      .then((): void => {
        this.reload();
      })
      .catch((e: Object): void => {
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

  // 删除执行：先查池条目 id 集 → 库内事务级联（服务商行 + 模型行 + key 池行）→ Asset
  // 池条目成对清理 → 当前选择失效 → 本地重拉 + toast；任一步失败 toast 可重试（P0-1）
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
      this.getUIContext().getPromptAction().showToast({ message: '已删除「' + row.name + '」' });
      this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 标题栏 ＋ 键（2026-09-22 自「更多」菜单移出，动作一字未动）：新建服务商 = push 详情页
  // 新建态。★ 恒传空串，勿传 null——坑12 真机实锤（null 被详情页读作编辑 id →「新建秒退」
  // + 不存在 toast；参数契约 string 见下方 openDetail）
  private openAdd(): void {
    this.openDetail('');
  }

  // 详情页跳转（卡片点击 = 编辑态携 id；标题栏 ＋ 键新建 = 新建态空串）。★ 勿回传 null：
  // 参数契约 = string，null 曾被详情页误读为编辑 id 致「新建秒退」（轮 7 修复，
  // ProviderDetailPage 注释；坑12）
  // ★ 坑16·2026-08-30 onPop 复活：返回即 reload（纪元自增 → 整卡重建重拉）——此前
  //「去自动链」拍板针对的真凶是徽章 @Builder 值参快照 + tick 广播 push 页内不触发，
  // 并非 onPop 本身（hilog 取证：卡内 load 赋值成功、徽章仍冻结首帧值）；onPop 走
  // Navigation 官方回调链，不经过 @BuilderParam content 传播
  private openDetail(providerId: string): void {
    this.pathStack.pushPathByName(ROUTE_PROVIDER_DETAIL_PAGE, providerId, (): void => {
      this.reload();
    });
  }

  // 标题栏「更多」菜单回调（刷新/批量分享/批量导入/排序四项；★ 2026-09-22 起「新建服务商」
  // 不经本接口——改由覆盖层 ＋ 键直连 openAdd；坑72：显式接口构造禁匿名对象字面量）
  private titleCallbacks(): ProviderTitleMenuCallbacks {
    const callbacks: ProviderTitleMenuCallbacks = {
      // 手动刷新键（坑16·2026-08-30 复活自动链：reload 重拉行 + cardEpoch 自增进
      // ForEach 键整卡重建——卡内自拉派生数据随重建执行；旧 tick 广播在 push 页内
      // @StorageProp @Watch 实测不触发已删）
      onRefresh: (): void => {
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '已刷新' });
      },
      onShareAll: (): void => {
        this.shareAllProviders();
      },
      onImportAll: (): void => {
        this.importProviders();
      },
      onSort: (): void => {
        // 排序页 push（坑16·2026-08-30 onPop 复活：排序返回即 reload——序变与卡内
        // 派生数据一并刷新；复活理由见 openDetail 注释）
        this.pathStack.pushPathByName(ROUTE_PROVIDER_SORT_PAGE, null, (): void => {
          this.reload();
        });
      }
    };
    return callbacks;
  }

  // 批量分享（2026-09-07 标题菜单「分享配置」）：打包全部已启用服务商——编排 =
  // ProviderShareFlow.exportShareAll（与单服务商 exportShareConfig 同一对话框三选语义；
  // 口令弹窗回调就地注入，askPassphrase 为本页既有方法零重复）；失败/取消均编排内兜底
  private shareAllProviders(): void {
    exportShareAll(this.getUIContext(),
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder));
  }

  // 批量导入（2026-09-07 标题菜单「导入配置」）：选文件 → 解析 → 预览分服务商 → 逐家
  // 新增；onDone = 列表 reload（纪元自增整卡重建，与刷新键同通道——导入的副本即刻上屏）
  private importProviders(): void {
    importShareConfig(this.getUIContext(),
      (title: string, placeholder: string): Promise<string | null> =>
        this.askPassphrase(title, placeholder),
      (): void => {
        this.reload();
      });
  }

  // 标题栏覆盖层（HDS 路径：右上角合并胶囊〔＋新建服务商 | ⋯更多〕）——组件内 @Builder 挂载
  // 是硬约束（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图上下文，启动即闪退）；
  // 键件与几何在 components/settings/ProviderTitleMenu.ets，本页只注入三参（档位 + 两动作）
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

  // 标题栏更多菜单弹出（胶囊右热区 action；锚点 = Content 内隐形锚点本页唯一 id——锚点右缘
  // 与 ⋯ 键右缘同值 16，故「更多」必须是胶囊右热区/菜单数组末键）
  private openTitleMenu(): void {
    this.titleMenu.open(this.getUIContext(), this.titleCallbacks(), this.immersiveLevel);
  }

  // 当前分段可见行（0 已启用 / 1 已停用）：开关启停 reload 重拉后行按 enabled 归段——
  // 卡片从当前分段消失、另一分段可见（领导口径「卡变到对应部分」）；分段切换 = 状态过滤
  // 即时生效无需 pop 再 push；详情页开关改动后 pop 回来 = onPop 自动 reload 归段
  //（坑16·2026-08-30 复活）
  private visibleRows(): ProviderRow[] {
    return this.rows.filter((row: ProviderRow): boolean =>
      this.segIndex === 0 ? row.enabled : !row.enabled);
  }

  // 列表内容起始偏移（分段胶囊悬浮位下方——胶囊顶 = topPad − 蒙层渐隐边缘 8 + 胶囊高
  // 40 + 间距 28，LogPageContent/ProviderDetailPage 吸顶三段构成同款）
  private listStartOffset(): number {
    return Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28;
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。外层 Stack
  // 顶部对齐三层：标题栏更多菜单隐形锚点（几何 = 日志页「按钮下沿」公式，坑11；★ 右缘
  // MORE_MENU_ANCHOR_RIGHT(16) 与标题栏键右避让 TITLE_BAR_EDGE_INSET(16) 恒同值——锚点右缘
  // = ⋯ 热区右缘，两常量单边改动即菜单横偏）+ 内容
  // 滚动层（List）+ 分段胶囊悬浮层（后声明在上）
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
          // 条目层无圆角/拖拽属性（2026-08-30 反馈轮 6：拖拽移除后条目轮廓塑形与浮起
          // 背板均无消费方——圆角由卡片自身承担；历史口径见坑2/坑10）
          ListItem() {
            ProviderCardItem({
              row: row,
              // （2026-08-30 自持有重构：modelCount/balance 派生展示改卡内自拉——本装配
              // 不传派生值；刷新 = 菜单「刷新」键/子页 onPop → reload → 纪元键整卡重建）
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
          // 坑16：键含 cardEpoch——reload 成功纪元自增 → 整卡重建 → 卡内自拉重跑（替代
          // push 页内实测不触发的 tick 广播）；行身份仍 = row.id（纪元全局同变不影响 diff）
        }, (row: ProviderRow): string => row.id + '|' + this.cardEpoch)

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
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)
          }
        }
        // 分段空态：有服务商但当前分段无（全部在另一段——开关归段后可能出现）
        if (this.rows.length > 0 && this.visibleRows().length === 0 && this.hintText === '') {
          ListItem() {
            Text(this.segIndex === 0 ? '暂无已启用的服务商' : '暂无已停用的服务商')
              .fontSize(13)
              .fontColor(cardDescColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding(24)
              .backgroundColor(cardBg(this.appColorMode))
              .borderRadius(16)
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
      // ★ 顶/底留白走官方 contentStartOffset/contentEndOffset（offset 属滚动内容：卡片
      // 上滚滑入分段胶囊背板与标题栏蒙层背后被模糊透出 = 双道光感；List padding 顶/底 =
      // 视口缩进会裁掉内容 = 坑9 根因勿回迁。归零条款按显示区长度读、短内容偏移不归零
      // ——坑9 勘误 2026-08-30 真机确认；起始偏移轮 9 起 = 分段胶囊悬浮位下方
      //（listStartOffset）
      .contentStartOffset(this.listStartOffset())
      .contentEndOffset(this.bottomPad + 16)
      // 左右 16 = 卡片水平居中收窄（反馈轮 2「卡不居中」修复）；顶/底禁用 padding（见上）
      .padding({ left: 16, right: 16 })
      // 短内容也上下可拖（反馈轮 2「上下无法滚动」修复——alwaysEnabled，会话列表同款；
      // offset 轨下拖拽回弹时卡片短暂滑入蒙层、光感亦可见）+ 滚动条常关
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)

      // ── 分段胶囊悬浮固定层（Stack 顶层后声明在上；已启用/已停用——2026-08-30 反馈
      // 轮 9 领导指令，日志页/详情页成熟实现同款：官方 CapsuleSegmentButtonV2 背板沉浸
      // 材质 colorInvert，内容上滚从胶囊背后穿过模糊透出）；位置 = 标题栏下沿 + 蒙层
      // 渐隐边缘 8vp（LogPageContent 同款）──
      Column() {
        SegmentBar({
          items: this.segItems,
          selectedIndex: $segIndex
        })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: Math.max(this.topPad - 8, 0) })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_PROVIDER,
      // 标题栏两键（★ 2026-09-22 决明「新建键移出与更多形成双键胶囊，参考消息页实现」）：
      // 〔＋新建服务商〕= push 详情页新建态 /〔⋯更多〕= 弹菜单（刷新 / 分享配置 / 导入配置 /
      // 排序）。HDS 路径 = 官方标题栏自定义区覆盖层合并胶囊〔＋|⋯〕（键件 = ProviderTitleBarKeys，
      // menuHds 传 null，keepStackTitle = true 保住主标题「服务商管理」）；回退路径 =
      // 官方菜单数组两键（menuNav，形态与覆盖层不同 = 无 stackBuilder 机制所限）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarKeys();
      },
      keepStackTitle: true,
      menuNav: providerMoreMenuNav((): void => {
        this.openAdd();
      }, (): void => {
        this.openTitleMenu();
      }),
      // 坑16·2026-08-30：仍不传 onShown（页显重拉无需求——菜单键/onPop 已覆盖回链）
      content: (): void => {
        this.Content()
      }
    })
  }
}
