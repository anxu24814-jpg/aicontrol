// MCP 服务器管理页：设置 → 工具调用页「MCP」入口的落点页——服务器清单的添加/编辑/删除、
// 测连与工具同步。构成 = 说明卡 + 空态卡 + 行卡列表（「添加服务器」新建键在右上角标题栏）。
// · 行卡 = Button Normal 包壳（原生按压蒙层，HttpTemplatePage 同形）+ 内容列 + 尾部启用
//   Toggle + 四点菜单键；卡体点击进编辑页。开关即停即用（落库 setMcpServerEnabled →
//   syncMcpTools 注册面同步 → reload；失败 toast + reload 回真值）；删除 = 行左滑 →
//   ConfirmDialog → removeMcpServer 级联（清 Asset 头值组 + 剔助手引用同事务）→
//   clearMcpSession + syncMcpTools 注销 → toast + reload。
// · 菜单（McpCardMenu.ets，ProviderCardMenu 同模式）：AppMenuHost 薄壳 init/open/dispose
//   成对 + 锚点 = 四点键逐卡拼前缀；当前仅「同步」一项（编辑 = 卡片点击，删除 = 左滑）。
//   同步在途时四点键位换 LoadingProgress（ConnectTestSheet 状态区同款）。
// · 状态两值派生（无状态机）：enabled + lastSyncAt/lastError → 已停用 / 失败（2026-11-09
//   反馈笔：警示图标独占失败提示，状态短语留空，红字改固定短句「同步失败，点开查看原因」——
//   原一行省略把完整 message 截成半句；全文仍落库并在编辑页可见）/ 可用 / 未同步；
//   瞬态同步中 = syncingIds（该行换 LoadingProgress）。
// · 同步三合一：McpClient.syncMcpServer 一次握手 + tools/list → 缓存回写（成功 = 新缓存 +
//   lastSyncAt + 清错；失败 = 缓存不动只回写 lastError 摘要，不含请求头值——密钥红线）→
//   reload；两路均跑 syncMcpTools 注册面同步。工具 schema 入缓存前经 expandMcpToolSchemas
//   内联 $ref（Gemini 口不吃悬空 $ref）。
// · 读取与刷新：卡片自持有 @State + aboutToAppear 自拉；编辑页返回经 pushPathByName 第三参
//   onPop 重拉；departed 守卫兜迟到回调（不写状态不碰 UI，写库意图照常完成）。
// · ForEach 键 = 行身份 + 全部可变展示成分（id/name/enabled/host/工具数/lastError/
//   lastSyncAt——坑44/80 家族）；同步中 loading 态不进键（@State syncingIds 响应式驱动）。
// · 卡壳 = CARD_PANEL_WIDTH / cardBg / CARD_RADIUS（宿主 Column 无左右 padding，卡体恒挂卡宽
//   基准——规范-列表卡片与组卡 §4.3）；「添加服务器」= 右上角标题栏官方单图标菜单键
//  （menuHds，照 HttpCredentialsPage「添加凭据」键形制），新建达上限 toast 拦截
//  （MCP_SERVERS_MAX=8）。
// · 无保存动作 → 返回无参 pop 不挂 onPop（坑17）；自包 PageShell，标题栏右上角挂添加键。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { SETTING_TITLE_MCP } from '../../common/SettingSearch';
import { ROUTE_MCP_SERVER_EDIT_PAGE } from '../../common/RouteNames';
import {
  queryMcpServers, removeMcpServer, setMcpServerEnabled, setMcpServerTools
} from '../../common/store/ChatDb';
import { McpServerRow } from '../../common/store/McpDb';
import { MCP_SERVERS_MAX, expandMcpToolSchemas, mergeMcpToolEnablement,
  parseMcpToolCache, serializeMcpToolCache } from '../../common/McpText';
import {
  McpServerEndpoint, McpSyncOutcome, clearMcpSession, syncMcpServer
} from '../../common/providers/McpClient';
import { syncMcpTools } from '../../common/providers/McpTools';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InfoCard } from '../InfoCard';
import { McpCardMenuCallbacks, McpCardMenuHost, MCP_CARD_MENU_ID_PREFIX } from './McpCardMenu';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { McpEditParam } from './McpServerEditPage';

// 标题栏右上角「添加服务器」键（官方标题栏菜单数组单键——单动作页用图标键，照
// HttpCredentialsPage「添加凭据」键形制；action = openEditPage('')，上限拦截在跳板内）
function mcpAddMenuHds(onAdd: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.plus'),
        action: onAdd
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct McpPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private rows: McpServerRow[] = [];
  // 同步在途行 id 集（方案 §2.3 瞬态「同步中」；数组整组替换驱动渲染——坑80 家族口径）
  @State private syncingIds: string[] = [];
  // 卡片菜单节点宿主（单项「同步」——init/open/dispose 成对，见 McpCardMenu.ets）
  private cardMenu: McpCardMenuHost = new McpCardMenuHost();
  // 删除确认弹窗控制器（★ 组件成员位按需构造——坑7；message 依赖当前名称故不预建）
  private confirmCtrl: CustomDialogController | null = null;
  private pendingDelete: McpServerRow | null = null;
  // 行左滑删除互斥组（RowSwipeDelete 单源下发；reload / 滚动开始两路收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();

  aboutToAppear(): void {
    this.reload();
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyRow()));
  }

  // 卡片菜单空行占位（init 首建参数——菜单弹出前恒经 openCardMenu 按真行重建，本值不上屏）
  private emptyRow(): McpServerRow {
    return { id: '', name: '', url: '', enabled: true, headersJson: '[]', toolsJson: '[]',
      lastSyncAt: 0, lastError: '', createdAt: 0, authKind: 'custom', protocolVersion: '' };
  }

  // 菜单回调组装（init/open 两处共用；显式接口构造——坑72：union 上下文禁匿名对象字面量）
  private menuCallbacks(row: McpServerRow): McpCardMenuCallbacks {
    const callbacks: McpCardMenuCallbacks = {
      item: row,
      onSync: (item: McpServerRow): void => {
        this.refreshRow(item);
      }
    };
    return callbacks;
  }

  // 弹出卡片菜单（锚点 = 本卡四点键；AppStorage.get 直读档位——ProviderPage 同口径）
  private openCardMenu(row: McpServerRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row),
      AppStorage.get<number>(IMMERSIVE_LEVEL_KEY) ?? 0);
  }

  // ── 卡上启停：即时落库 + 注册面同步（停用即注销、启用按缓存恢复）；失败 toast + reload 回真值 ──
  private toggleRow(row: McpServerRow, isOn: boolean): void {
    setMcpServerEnabled(row.id, isOn)
      .then((): Promise<void> => {
        return syncMcpTools();
      })
      .then((): void => {
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction()
          .showToast({ message: '操作失败：' + (e as Error).message });
        this.reload();
      });
  }

  // ── 删除级联（原编辑页五步整段迁来；②③收口在 removeMcpServer 委托单点）──
  private openDeleteConfirm(row: McpServerRow): void {
    if (row.id === '') {
      return;
    }
    this.pendingDelete = row;
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除服务器',
        message: '将删除服务器「' + row.name + '」。绑定它的助手将不再使用它的工具。',
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

  private async deletePending(): Promise<void> {
    const row: McpServerRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    try {
      await removeMcpServer(row.id);
      // ④内存会话成对清（Map 死条目防无界）；注册面同步注销（下轮对话零声明）
      clearMcpSession(row.id);
      await syncMcpTools();
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction()
        .showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  private reload(): void {
    queryMcpServers().then((rows: McpServerRow[]): void => {
      if (this.departed) {
        return;
      }
      this.rows = rows;
      // 清单整组重拉即收口行左滑展开态（删行后原行销毁，双保险）
      this.swipeGroup.collapse();
    }).catch((_e: Object): void => {
      // 库读失败保旧态（下一次进出页重拉；小表低频页，不打断——HttpTemplatePage 同款）
    });
  }

  // URL → host 副行显示段（HttpTemplatePage.hostOf 同款截取）
  private hostOf(url: string): string {
    const m: RegExpMatchArray | null = url.match(/^https?:\/\/([^/?#]+)/);
    return m !== null ? m[1] : url;
  }

  private toolCountOf(row: McpServerRow): number {
    return parseMcpToolCache(row.toolsJson).length;
  }

  // ── 状态两值派生（方案 §2.3 纯函数族：enabled 叠加位 ∩ 未同步/可用/失败三值）──
  private statusIconOf(row: McpServerRow): Resource {
    if (!row.enabled) {
      return $r('sys.symbol.pause_circle');
    }
    if (row.lastError !== '') {
      return $r('sys.symbol.exclamationmark_circle');
    }
    return row.lastSyncAt > 0 ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.clock');
  }

  private statusTextOf(row: McpServerRow): string {
    if (!row.enabled) {
      return '已停用';
    }
    if (row.lastError !== '') {
      // 失败态留空：前导 exclamationmark_circle 警示图标已是唯一失败提示，不再叠
      // 一行「失败」（2026-11-09 反馈笔）；空串由卡内条件渲染吃掉
      return '';
    }
    return row.lastSyncAt > 0 ? '可用' : '未同步';
  }

  // 状态短语色：失败态已无短语，本函数只服务图标（警示色，ConnectTestSheet 同口径
  // 「零新色」）；其余走卡内次要色。失败提示行恒警示红（停用叠加时失败事实仍在）
  private statusColorOf(row: McpServerRow): Resource {
    if (row.lastError !== '') {
      return $r('sys.color.ohos_id_color_warning');
    }
    return cardDescColor();
  }

  // 服务器行卡（RowSwipeDelete content 位，形制不变；卡 padding 4 + 壳 padding 12）
  @Builder
  McpRow(row: McpServerRow) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph(this.statusIconOf(row))
            .fontSize(16)
            .fontColor([this.statusColorOf(row)])
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(row.name)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              // 失败态 statusTextOf 回空串 = 不渲染短语（警示图标已足够，去重复字样）
              if (this.statusTextOf(row) !== '') {
                Text(this.statusTextOf(row))
                  .fontSize(12)
                  .fontColor(this.statusColorOf(row))
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            Text(this.toolCountOf(row) > 0 ?
              this.hostOf(row.url) + ' · ' + this.toolCountOf(row) + ' 件工具' :
              this.hostOf(row.url))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (row.lastError !== '') {
              // 固定短句（2026-11-09）：原单行省略会把完整 error.message 截成读不通的半句；
              // 失败态由前导警示图标承担，原因全文仍落库并在编辑页可见，卡内只留行动指引
              Text('同步失败，点开查看原因')
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_warning'))
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 启用开关（停用 = 对话不再使用它的工具，即时落库可逆，不弹确认）
          Toggle({ type: ToggleType.Switch, isOn: row.enabled })
            .onChange((isOn: boolean): void => {
              this.toggleRow(row, isOn);
            })
          // 四点菜单键（TEXTUAL 图标键，挂菜单锚点 id）；同步在途换 LoadingProgress；
          // 嵌套子件点击不冒泡，整卡点击进编辑页不受扰
          if (this.syncingIds.includes(row.id)) {
            LoadingProgress()
              .width(16)
              .height(16)
          } else {
            Button() {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .id(MCP_CARD_MENU_ID_PREFIX + row.id)
            .onClick((): void => {
              this.openCardMenu(row);
            })
          }
        }
        .width('100%')
        .padding(12)
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openEditPage(row.id);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 左滑删除入口（按 id 查行走既有确认链；菜单「删除」退役后为唯一删除路径）
  private askDeleteById(id: string): void {
    const row: McpServerRow | undefined =
      this.rows.find((item: McpServerRow): boolean => item.id === id);
    if (row !== undefined) {
      this.openDeleteConfirm(row);
    }
  }

  // ── 同步三合一（头注释口径；在途防重入 + departed 守卫 + 失败 toast 不静默）──
  private async refreshRow(row: McpServerRow): Promise<void> {
    if (this.syncingIds.includes(row.id)) {
      return;
    }
    this.syncingIds = this.syncingIds.concat([row.id]);
    try {
      const outcome: McpSyncOutcome = await syncMcpServer({
        serverId: row.id, url: row.url, headersJson: row.headersJson,
        protocolVersion: row.protocolVersion
      } as McpServerEndpoint);
      // 成功：新清单先展开 $ref，再按名合并旧缓存里的逐工具开关（用户关掉的刷新后保持
      // 关闭；新工具默认开、消失工具淘汰）+ lastSyncAt + 清 lastError
      await setMcpServerTools(row.id,
        serializeMcpToolCache(mergeMcpToolEnablement(parseMcpToolCache(row.toolsJson),
          expandMcpToolSchemas(outcome.tools))), Date.now(), '');
      await syncMcpTools();
      if (this.departed) {
        return;
      }
      this.reload();
    } catch (e) {
      // 失败：缓存与 lastSyncAt 不动只回写 lastError 全文（行卡只显固定短句，全文在编辑页
      // 与 toast 可见；摘要只含错误 message，不含请求头值——密钥红线）
      const brief: string = (e as Error).message;
      try {
        await setMcpServerTools(row.id, row.toolsJson, row.lastSyncAt, brief);
      } catch (e2) {
      }
      // 失败路同样同步注册面（缓存未变 = 幂等；若已被旁路停用，此处顺带收敛注销）
      await syncMcpTools();
      if (this.departed) {
        return;
      }
      this.reload();
      this.getUIContext().getPromptAction().showToast({
        message: brief !== '' ? brief : '同步失败，请重试'
      });
    } finally {
      if (!this.departed) {
        this.syncingIds = this.syncingIds.filter((id: string): boolean => id !== row.id);
      }
    }
  }

  // ── 编辑页跳板（行卡点击与「添加服务器」键两路同形；serverId '' = 新建）──
  private openEditPage(serverId: string): void {
    if (serverId === '' && this.rows.length >= MCP_SERVERS_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '最多支持 ' + MCP_SERVERS_MAX + ' 台 MCP 服务器，先删除一台再添加'
      });
      return;
    }
    this.pathStack.pushPathByName(ROUTE_MCP_SERVER_EDIT_PAGE,
      { serverId: serverId } as McpEditParam, (): void => {
        this.reload();
      });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明卡 = InfoCard 单源件（title + text 两排，先说明后操作）
        InfoCard({
          title: SETTING_TITLE_MCP,
          text: '添加 MCP 服务器后，在助手的工具调用页勾选，助手就能使用它提供的工具。'
        })
        if (this.rows.length === 0) {
          Column({ space: 2 }) {
            Text('还没有 MCP 服务器。')
              .fontSize(14)
              .fontColor(cardDescColor())
            Text('点右上角加号键添加第一台。添加后在这里同步它提供的工具。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .width(CARD_PANEL_WIDTH)
        }
        ForEach(this.rows, (row: McpServerRow) => {
          // 行左滑删除层：删除走 askDeleteById 确认链（菜单「删除」退役后唯一路径）；
          // 展开态不进键
          RowSwipeDelete({
            rowId: row.id,
            group: this.swipeGroup,
            content: (): void => {
              this.McpRow(row)
            },
            onSwipeDelete: (rowId: string): void => {
              this.askDeleteById(rowId);
            }
          })
        }, (row: McpServerRow): string =>
          // 键 = 行身份 + 全部可变展示成分（name/enabled/host/工具数/lastError/lastSyncAt
          // 均驱动行内显示；裸 id 键 = 复用旧卡静默冻结，坑44/80 家族）。同步中 loading
          // 态刻意不入键（@State syncingIds 响应式驱动；入键会在同步起止时无谓重建整行）
          row.id + '|' + row.name + '|' + (row.enabled ? '1' : '0') + '|' + this.hostOf(row.url) +
          '|' + this.toolCountOf(row) + '|' + row.lastError + '|' + row.lastSyncAt)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 滚动开始即收口行左滑展开态（会话列表/五库同口径）
    .onScrollStart((): void => {
      this.swipeGroup.collapse();
    })
  }

  build() {
    PageShell({
      title: SETTING_TITLE_MCP,
      // 右上角「添加服务器」新建键（官方单图标菜单键；新建上限拦截在 openEditPage 跳板内）
      menuHds: mcpAddMenuHds((): void => {
        this.openEditPage('');
      }),
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.cardMenu.dispose();
  }
}
