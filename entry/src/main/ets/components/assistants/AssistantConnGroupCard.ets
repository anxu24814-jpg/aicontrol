// 助手编辑页「连接组卡」域件（原「HTTP 与脚本联网」组卡〔AssistantHttpGroupCard〕扩展：
// 决明「mcp 移出工具调用，mcp 和脚本联网组成组卡」拍笔——MCP 行并入成三行卡并随迁更名）。
// 一句话职责 = 三个入口行的摘要与跳转（MCP 服务器开关页 / 凭据管理页 / 本助手域名管理页）
// + 返回重拉。
// ★ 为何独立成件（反碎片下限①「职责缝」+ ②「并入既有同域文件优先于新开」）：三行同属
//   「按助手配置的连接与凭据」域（MCP 服务器勾选 / HTTP 凭据 / 写请求授权域名），一份摘要
//   状态 + 一条重拉链即可，拆开反而各自持状态；宿主编辑页行数紧张，本域整块外置。非「纯
//   转接壳」——摘要计算与偏好/库读取本体在本件。
// 摘要口径：MCP = 本助手勾选服务器台数（'已启用 N 台服务器'/'未启用'，读 assistants
// .mcpServers 列，解析单源 McpText.parseEnabledMcpServerIds——禁复用 tools 解析，四列语义
// 各异是既定口径；服务器全局停用不影响台数口径，逐台状态在开关页内如实显示）；HTTP 凭据 =
// 本助手凭据条数（'N 条凭据'/'未配置'）；脚本联网域名 = 本助手清单计数（'N 个域名'/'未配
// 置'，不含全局段——全局授权不专属本助手）。空态与失败态同显示「未配置」（配置面读不到偏
// 好 = 无可引用凭据，管理页内重存即自愈）。
// ★ 助手页只读口径（决明指令）：凭据与域名两入口进的都是**只读清单**——push 参数携
// readOnly = true，管理页不渲染添加入口 / 行菜单 / 删除键（新增、编辑、删除统一在
// 设置 → 工具调用 → HTTP 请求（凭据）/ 脚本工作台（脚本联网域名））；MCP 行进的开关页只管
// 「这名助手用哪些」，服务器本身的增删改唯一入口 = 设置 → 工具调用 → MCP 管理页。与助手
// 记忆页、技能页一致：助手页只配置「这名助手用哪些」，库本身的增删改只留在设置页。
// ★ 组卡刷新责任在调用方（GroupSettingCard 头注释）：items 是普通成员入参，本件以
// ForEach([groupKey()]) 单例纪元键承载——任一摘要变动即键变 → 组卡整体重建拉新值。
import { CodeHttpHostManageParam, getCodeHttpHostsJson, getHttpCredentialsCfgJson, parseCodeHttpHosts }
  from '../../common/AppPreferencesHttp';
import { HttpCredCfg, HttpCredManageParam, parseHttpCredCfg } from '../../common/providers/HttpCredentials';
import {
  ROUTE_ASSISTANT_MCP_PAGE, ROUTE_CODE_HTTP_HOST_MANAGE_PAGE, ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE
} from '../../common/RouteNames';
import { parseEnabledMcpServerIds } from '../../common/McpText';
import { queryAssistant } from '../../common/store/AssistantDb';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE } from '../GroupSettingCard';

@Component
export struct AssistantConnGroupCard {
  // 归属助手 id（宿主编辑页的 rowId）
  assistantId: string = '';
  // 宿主共享 NavPathStack（push 管理页 param = 本助手 id）
  pathStack: NavPathStack = new NavPathStack();
  @State private credSummary: string = '未配置';
  @State private hostSummary: string = '未配置';
  // MCP 行摘要（assistants.mcpServers 勾选台数；异步库读回填，初值待 aboutToAppear）
  @State private mcpSummary: string = '未启用';
  // 页面存活守卫：置位后迟到异步回调不写状态（1712 纪律——queryAssistant 回调写 @State）
  private departed: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 摘要重算（凭据与域名 = 同步读偏好元数据，异常按未配置——配置面回默认可自愈；MCP =
  // 异步读库，失败静默保持旧值，重进自拉）
  private refresh(): void {
    try {
      const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
      const creds: number = (cfg.get(this.assistantId) ?? []).length;
      this.credSummary = creds > 0 ? creds + ' 条凭据' : '未配置';
    } catch (e) {
      this.credSummary = '未配置';
    }
    try {
      const hosts: number = parseCodeHttpHosts(getCodeHttpHostsJson(), this.assistantId).length;
      this.hostSummary = hosts > 0 ? hosts + ' 个域名' : '未配置';
    } catch (e) {
      this.hostSummary = '未配置';
    }
    queryAssistant(this.assistantId)
      .then((row): void => {
        if (this.departed || row === null) {
          return;
        }
        const bound: number = parseEnabledMcpServerIds(row.mcpServers).length;
        this.mcpSummary = bound > 0 ? '已启用 ' + bound + ' 台服务器' : '未启用';
      })
      .catch((_e: Object): void => {
        // 保旧值不静默改写（库读失败属环境态，重进编辑页自拉；toast 留给开关页内的写链）
      });
  }

  // 组卡重建键（恒单例纪元键——键含三行摘要，任一变动即重建拉新值；§4.1 刷新责任）
  private groupKey(): string {
    return this.credSummary + '|' + this.hostSummary + '|' + this.mcpSummary;
  }

  // 行数据（三入口行：图标 + 标题 + 摘要 + 右箭头）。跳转行默认带箭头（§3.2——曾按旧令
  // 全撤后经决明反馈恢复，勿再撤）；三行统一蓝（卡内主色并列取首行）；push 参数对象形态携
  // readOnly = true（MCP 行 param = 助手 id，开关页内落库面）
  private groupItems(): GroupEntryItem[] {
    const credParam: HttpCredManageParam = { owner: this.assistantId, readOnly: true };
    const hostParam: CodeHttpHostManageParam = { owner: this.assistantId, readOnly: true };
    const rows: GroupEntryItem[] = [
      {
        // MCP：externaldrive = 设置侧「MCP」行同源图标（已核验在册名，坑72）
        icon: $r('sys.symbol.externaldrive'),
        iconBg: SETTING_ICON_BLUE,
        label: 'MCP',
        secondary: this.mcpSummary,
        chevron: true,
        onClick: (): void => {
          // onPop：返回重拉三行摘要——只读态摘要不受管理动作影响，重拉幂等无害
          this.pathStack.pushPathByName(ROUTE_ASSISTANT_MCP_PAGE, this.assistantId,
            (): void => {
              this.refresh();
            });
        }
      },
      {
        icon: $r('sys.symbol.lock_shield'),
        iconBg: SETTING_ICON_BLUE,
        label: 'HTTP 凭据',
        secondary: this.credSummary,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE, credParam,
            (): void => {
              this.refresh();
            });
        }
      },
      {
        icon: $r('sys.symbol.code'),
        iconBg: SETTING_ICON_BLUE,
        label: '脚本联网域名',
        secondary: this.hostSummary,
        chevron: true,
        onClick: (): void => {
          this.pathStack.pushPathByName(ROUTE_CODE_HTTP_HOST_MANAGE_PAGE, hostParam,
            (): void => {
              this.refresh();
            });
        }
      }
    ];
    return rows;
  }

  build() {
    Column() {
      ForEach([this.groupKey()], (_key: string) => {
        GroupSettingCard({ items: this.groupItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
      }, (key: string): string => key)
    }
    .width('100%')
  }
}
