// 助手 MCP 服务器开关三级页：编辑页组卡「MCP」行 push，param = 助手 id。
// ★ 前身 = 工具调用页末位「MCP 服务器绑定卡」（决明「mcp 移出工具调用」拍板整体迁出成页，
// 原卡随迁退役）——行数据与开关链自 AssistantToolsPage 原样搬迁：行 = 服务器名 + 状态短语
// + 行尾 Toggle，Toggle 为唯一控制面（坑5/坑16 家族口径，行点击空转）；开关即时落库
// assistants.mcpServers 列（序列化单源 serializeEnabledMcpServerIds），失败回滚显示态 +
// toast 不静默，纪元拨回让 Toggle 回到旧值。
// 绑定语义：勾选服务器 ∩ 服务器 enabled → 对话声明其工具（collectTools 追加段消费；停用
// 服务器勾选保留，恢复启用即生效——副行状态短语如实显示「已停用」）。
// ★ 本页只管「这名助手用哪些」（助手页只配置口径，同 HTTP 凭据 / 脚本联网域名行）：服务器
// 的添加/编辑/删除/启停唯一入口 = 设置 → 工具调用 → MCP 管理页，本页零服务器写点；行状态
// 短语的工具件数经 registeredMcpEntriesFor 同步读（与对话声明面同一取值口，停用/未同步即已
// 注销恒 0 件，如实显示）。
// 空态：无服务器整卡不出（原绑定卡同口径），出页顶说明 + 一行引导；引导与说明合并进
// InfoCard，不再保留原卡外说明文字。
// 刷新链：无保存动作 → onBackPressed pop({saved:true})（坑17「无保存动作的完成返回」姿势）
// 刷编辑页组卡「MCP」行摘要；开关落库失败 toast，显示态回滚由纪元拨回自转。
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_MCP_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, SECTION_GAP, cardDescColor } from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { queryAssistant, updateAssistantMcpServers } from '../../common/store/AssistantDb';
import { queryMcpServers } from '../../common/store/ChatDb';
import { McpServerRow } from '../../common/store/McpDb';
import { parseEnabledMcpServerIds, serializeEnabledMcpServerIds } from '../../common/McpText';
// 绑定卡状态短语带注册面工具件数——与对话声明面（collectTools 追加段）同一取值口，同步读零 IO
import { registeredMcpEntriesFor } from '../../common/providers/McpTools';

@Component
export struct AssistantMcpPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id）
  private rowId: string = '';
  // 服务器库行（进页拉一次——本页生命周期内无服务器写点，MCP 管理页在设置侧；重进自拉）
  @State mcpRows: McpServerRow[] = [];
  // 绑定集（assistants.mcpServers 解析缓存——开关显示态单一真源）
  @State mcpBound: string[] = [];
  // 绑定卡纪元（坑44/80 家族）：GroupSettingCard.items 是普通成员入参，父组件重渲不更新它
  // → 行定格首帧。本纪元进卡 ForEach 键（键变重建 = 规范 §3 主通道）：库读回、开关交互
  // 都自增 → 卡整体重建 → 行内容拉新值；落库失败回滚同自增拨回
  @State mcpToggleEpoch: number = 0;

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_MCP_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.mcpBound = parseEnabledMcpServerIds(row.mcpServers);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
    // MCP 服务器清单（卡行数据；库读失败保空 = 整卡不出，重进自拉）
    queryMcpServers()
      .then((rows: McpServerRow[]): void => {
        if (this.departed) {
          return;
        }
        this.mcpRows = rows;
        this.mcpToggleEpoch += 1;
      })
      .catch((_e: Object): void => {
        // 保空态整卡不出（小表低频页，不打断——McpPage reload 同款口径）
      });
  }

  // 状态短语（McpPage.statusTextOf 同源口径的精简版 + 工具件数；失败摘要全文仍归管理页）：
  // 已停用叠加位 ∩ 同步失败 / 可用 / 未同步；「· N 件」= 该服务器当前注册面工具件数
  //（registeredMcpEntriesFor 同步读——与对话声明面同一取值口，停用/未同步即已注销恒 0 件，
  // 如实显示）。★ 「开关页显示工具数（N 件）」沿用原绑定卡现行口径（占用可见拍板项 D5）
  private mcpStatusOf(row: McpServerRow): string {
    let status: string;
    if (!row.enabled) {
      status = '已停用';
    } else if (row.lastError !== '') {
      status = '同步失败';
    } else {
      status = row.lastSyncAt > 0 ? '可用' : '未同步';
    }
    return status + ' · ' + registeredMcpEntriesFor([row.id]).length + ' 件';
  }

  // 卡行数据（开关行：服务器名 + 状态短语 + 行尾 Toggle——GroupSettingCard 开关行的 Toggle
  // 是唯一控制面，坑5/坑16 家族口径；行点击空转）
  private mcpCardItems(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const row of this.mcpRows) {
      items.push({
        label: row.name,
        secondary: this.mcpStatusOf(row),
        toggleValue: (): boolean => this.mcpBound.includes(row.id),
        onToggle: (isOn: boolean): void => {
          this.toggleMcpBound(row.id, isOn);
        }
      });
    }
    return items;
  }

  // 卡重建键（坑44/80：行内可变展示成分全覆盖——服务器名/启停/同步时间/错误摘要/工具件数
  // + 绑定开关态 + 纪元；★ **新增可变成分必须进键**，不进即静默冻结〔工具件数即占用可见笔
  // 新增后补进键的实例〕）
  private mcpCardKey(): string {
    const rowSig: string[] = this.mcpRows.map((row: McpServerRow): string =>
      row.id + '|' + row.name + '|' + (row.enabled ? '1' : '0') + '|' + row.lastSyncAt +
      '|' + row.lastError + '|' + registeredMcpEntriesFor([row.id]).length);
    return 'mcpBind|' + this.mcpToggleEpoch + '|' + this.mcpBound.join(',') + '|' + rowSig.join(';');
  }

  // 绑定开关（即时落库 assistants.mcpServers——「选择即落库」语义；失败回滚显示态 + toast
  // 不静默，纪元拨回让 Toggle 回到旧值）
  private toggleMcpBound(serverId: string, isOn: boolean): void {
    const prev: string[] = this.mcpBound;
    const next: string[] = isOn
      ? (prev.includes(serverId) ? prev : prev.concat([serverId]))
      : prev.filter((id: string): boolean => id !== serverId);
    this.mcpBound = next;
    this.mcpToggleEpoch += 1;
    updateAssistantMcpServers(this.rowId, serializeEnabledMcpServerIds(next))
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.mcpBound = prev;
        this.mcpToggleEpoch += 1;
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  @Builder
  Content() {
    Scroll() {
      // 板块间 SECTION_GAP（Theme 三档常量）
      Column({ space: SECTION_GAP }) {
        // 页顶说明（InfoCard 单源件）：开关语义 + 服务器管理入口指引一条非显然信息
        InfoCard({ text: '打开开关后，本助手即可使用该服务器的工具，改动即时生效。服务器的添加与管理在 设置 → 工具调用 页的「MCP」行。' })
        // 绑定开关卡（行源 = 服务器库 + 绑定集；无服务器整卡不出，出引导行——原绑定卡同口径）。
        // 开关行 Toggle 为唯一控制面，键含纪元 + 绑定集 + 行状态全量（见 mcpCardKey）
        if (this.mcpRows.length > 0) {
          ForEach([this.mcpCardKey()], (_key: string) => {
            GroupSettingCard({ items: this.mcpCardItems(), dividerLeft: 8 })
          }, (key: string): string => key)
        } else {
          Text('还没有 MCP 服务器，可在 设置 → 工具调用 页的「MCP」行添加。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        }
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
  }

  build() {
    PageShell({
      title: 'MCP 服务器',
      // 右上角无菜单键（纯开关列表页）
      onBackPressed: (): boolean => {
        // 开关行即时落库（本页无待保存项），完成返回带 result（坑17 姿势——编辑页组卡
        // onPop 刷「MCP」行摘要）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
