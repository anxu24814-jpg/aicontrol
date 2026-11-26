// MCP 服务器编辑页（McpPage 行卡与「添加服务器」键的 push 落点）：新建/编辑双态表单 + 保存后
// 自动测连。形制 = push 页非半模态（免半模态关闭链四件复杂度）。
// · param：getParamByName 取末条；serverId '' = 新建空表单，非空 = 编辑该行（行不在 → toast + pop）。
// · 表单六卡：
//   1) 名称地址卡：名称实时校验 ^[A-Za-z0-9]+$ + 查重排除自身（异步，McpDb 增改闸兜底）；
//      地址 https?:// 保存闸。说明小字在输入框上方（宪法「功能设置卡布局次序」），错误提示在
//      下方。★ 启用开关卡已退役（决明拍板）：启停改 McpPage 行卡 Toggle；新建恒启用。
//   2) 认证卡：四档宫格（选项非按钮；chip 蓝配色，2026-11-11 决明拍板与协议版本 chip 同族）；
//      后三档保存时由 buildAuthHeaderGroup 单点组装为请求头组
//      （底层链路零分叉），故请求头卡只在自定义档显示。切档 = 整组重写，有存量头组时 toast 提示。
//   3) 协议版本卡：对话模型卡形态（卡头 + 单行值，点值行弹选 5 档）——2026-11-11 决明拍板；
//      强制档只升级 initialize 广告值与 MCP-Protocol-Version 头（只认新形态报文的服务器仍
//      连不上，说明收卡头 ⓘ）。
//   4) 请求头卡（仅自定义档）：行组 ≤ MCP_HEADERS_MAX（达限 toast + 保存链兜底）、值可显隐、
//      逐行删除 TEXTUAL trash 图标键（无底 + font_secondary，禁垫四件套）、添加键
//      fallbackButton* 四件套 primary=true。名称为空的行保存时丢弃。
//   5) 工具缓存卡（编辑态）：逐行 Toggle（即时落库 + 注册面同步）+ 最近同步时间 + lastError
//      全文红字。行键含 enabled（坑44/80 家族——漏则开关翻转界面不动）。
//   6) 连接测试卡：按当前表单态直跑握手 + tools/list；不落库、不动 lastError/lastSyncAt；
//      测试会话前后清（未保存配置不得留在会话缓存）。
// · ★ 明文红线（Asset 分流）：头值明文仅本页内存（value 字段 + bearer/apiKey 输入 + oldValues/
//   storedValue 普通成员——读回不上屏不落日志，保存链组装即写 Asset），保存成功即清引用；编辑
//   态值框空起手不回填原明文。标记三态（非明文）：Asset 值在 = 「已保存」/ 元数据 hasValue 但
//   Asset 空 = 「值缺失，请填入新值」/ 从未设置 = 「未设置」。Asset 读失败时保存链与测试键拦截
//  （P0-1，不静默清空密钥）。
// · 保存链（顺序即拦截序）：名称格式 → 查重 → URL → 头值读取完成闸 → 协议版本 → 头组 ≤5 →
//   ChatDb.addMcpServer / editMcpServer 委托单点（「先 Asset 后 DB」写序在委托层）→
//   clearMcpSession → 自动测连（syncMcpServer = 握手 + tools/list；成功 = 新缓存按名合并旧开关
//   + lastSyncAt + 清错，失败 = 缓存不动只回写 lastError 摘要，不阻断保存）→ syncMcpTools 注册面
//   同步 → toast「已保存」/「已保存。同步失败：…」→ pop({ saved: true })（坑17：result 须 Object）
//   → 管理页 onPop 重拉。新建行 id 由委托层铸造、按名查回。tools/list 结果入缓存前经 $ref 内联
//   展开，再按名合并旧开关（expand → merge → serialize）。
// · ★ 返回链：onBackPressed 拦截后 pop 带 result（坑17）；保存在途时拦住提示，等写落定再返回
//  （防父页重拉抢在写提交前读到旧行）。
// · 删除与启停均迁至 McpPage 行卡；本页不再带删除键与启用开关卡。
// · departed 守卫（全站纪律）：置位后不写状态、不碰 UI、不 pop；写库等数据层意图照常完成。
// · 行键：头行 = 行 uid（组件侧 Map 懒分配，防删中间行后余行复用串值）；工具行 = 工具名 + enabled。
// · 卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS（规范 §4.3）。toast 全
//   UIContext 形态。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { FunctionalCardHeader, SettingMenuRow } from './FunctionalSettingRows';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBgTinted, fallbackButtonFontTinted,
  fallbackButtonMaterialTinted, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { HeaderPair } from '../../common/providers/AiTypes';
import { KeyValueWell } from '../KeyValueWell';
import { OptionTileGrid } from '../OptionTileGrid';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { ROUTE_MCP_SERVER_EDIT_PAGE } from '../../common/RouteNames';
import {
  addMcpServer, editMcpServer, loadMcpServerHeaderValues, queryMcpServers, setMcpServerTools
} from '../../common/store/ChatDb';
import { McpServerRow } from '../../common/store/McpDb';
import {
  MCP_AUTH_API_KEY, MCP_AUTH_BEARER, MCP_AUTH_CUSTOM, MCP_AUTH_NONE, MCP_HEADERS_MAX,
  McpHeaderMetaItem, McpToolCacheItem, expandMcpToolSchemas, isValidMcpServerName,
  mergeMcpToolEnablement, normalizeMcpAuthKind, parseMcpHeaderMeta, parseMcpToolCache,
  serializeMcpHeaderMeta, serializeMcpToolCache
} from '../../common/McpText';
import {
  MCP_VERSION_AUTO, MCP_VERSIONS_LEGAL, isValidMcpProtocolVersion
} from '../../common/providers/McpRpc';
import {
  McpServerEndpoint, McpSyncOutcome, clearMcpSession, syncMcpServer
} from '../../common/providers/McpClient';
import { syncMcpTools } from '../../common/providers/McpTools';
import { formatWorkspaceTime } from '../../common/WorkspaceUtil';

  // 编辑页入参（serverId '' = 新建，非空 = 编辑该服务器）
export interface McpEditParam {
  serverId: string;
}

// 认证头组（保存链与测试连接共用；metas/values 等长，与 serializeMcpHeaderMeta + headerValues
// 两参数同形）
interface McpAuthHeaderGroup {
  metas: McpHeaderMetaItem[];
  values: string[];
}

// 认证四档宫格选项（规范 §4.13「恰 4 项 → 宫格」；标签与值同序，顺序即阅读序）
const MCP_AUTH_LABELS: string[] = ['无需认证', 'Bearer Token', 'API Key', '自定义请求头'];
const MCP_AUTH_OPTIONS: string[] = [MCP_AUTH_NONE, MCP_AUTH_BEARER, MCP_AUTH_API_KEY, MCP_AUTH_CUSTOM];

  // 测试连接专用会话键（新建态无 serverId——固定桩值防命中错服务器；测试前后均清）
const MCP_TEST_SESSION_ID: string = 'mcp-connection-test';

// 协议版本选项（自动协商垫首 + 四个强制档；顺序即菜单展示序）与显示名（同序；'' 在协议域
// 是「自动协商」不是「默认」，显示名单源在本页，勿下沉到思考档位件的默认语义）
const MCP_VERSION_OPTIONS: string[] = [MCP_VERSION_AUTO].concat(MCP_VERSIONS_LEGAL);
const MCP_VERSION_LABELS: string[] = ['自动协商'].concat(MCP_VERSIONS_LEGAL);

  // 输入长度上限（输入有界红线；头名/头值与另两卡同界）
const MCP_NAME_MAX: number = 32;
const MCP_URL_MAX: number = 500;
const HEADER_KEY_MAX: number = 100;
const HEADER_VALUE_MAX: number = 500;

// 工具清单折叠动画时长（官方 FAQ faqs-arkui-769 同值 300ms + EaseInOut）
const FOLD_ANIM_MS: number = 300;

// 标题栏保存键官方 HDS 数组
function mcpSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct McpServerEditPage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 光感档 + 内容区回退能力位（fallbackButton* 四件套消费——订阅式随档即刷；AppStorage.get
  // 现读非响应式，坑16 正解）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 编辑对象行 id（'' = 新建）
  private serverId: string = '';
  // ── 表单值（★ 启用开关已退役：新建恒启用，编辑态启停改 McpPage 行卡 Toggle）──
  @State private name: string = '';
  @State private url: string = '';
  // 认证方式四档与广告协议版本（存量行归一为 'custom' / ''）；取值域单源 = McpText.MCP_AUTH_* /
  // McpRpc.MCP_VERSIONS_LEGAL
  @State private authKind: string = MCP_AUTH_CUSTOM;
  @State private protocolVersion: string = MCP_VERSION_AUTO;
  // 认证分档输入（值仅本页内存，保存成功即清；旧值只在私有成员，不上屏不落日志——明文红线）
  @State private bearerToken: string = '';
  @State private apiKeyName: string = '';
  @State private apiKeyValue: string = '';
  private bearerStoredValue: string = '';
  @State private bearerHasStored: boolean = false;
  @State private bearerMetaHasValue: boolean = false;
  private apiKeyStoredValue: string = '';
  @State private apiKeyHasStored: boolean = false;
  @State private apiKeyMetaHasValue: boolean = false;
  // 测试连接（只读探针：不落库、不动 lastError/lastSyncAt；testing 防重入）
  @State private testing: boolean = false;
  @State private testResult: string = '';
  @State private testOk: boolean = false;
  // 请求头行组（value = 明文输入，保存成功即清）。行键/布局/删除键/添加键全下沉 KeyValueWell
  // 单源，本页只保留「值不回显」所需的平行元数据（下方三组）。
  @State private headerRows: HeaderPair[] = [];
  // 行标记三态平行数组（下标对齐 headerRows）：rowFromDb = 编辑回填行（true 才显示标记）；
  // rowHasAssetValue = Asset 值实况；rowMetaHasValue = 元数据 hasValue（备份导入后丢值的判据）
  private rowFromDb: boolean[] = [];
  @State private rowHasAssetValue: boolean[] = [];
  private rowMetaHasValue: boolean[] = [];
  // 井的行级标注入参（由 syncHeaderMarks 单点重算——三组平行数组是判据源，本组只承载文案）
  @State private rowMarks: string[] = [];
  @State private rowMarkWarn: boolean[] = [];
  // 旧值明文组（编辑态 Asset 读回，不上屏不落日志；「留空保持原值」的回填源，成功即清）
  private oldValues: string[] = [];
  // Asset 值读取完成闸（编辑态有回填头行时未完成 = 保存拦截——组重写语义下盲存会静默清空
  // 密钥，P0-1；新建态恒 true）
  private headerValuesLoaded: boolean = true;
  // 实时查重命中（名称输入异步查库回写）
  @State private nameTaken: boolean = false;
  // 保存/同步在途（防重入 + 提示行）
  @State private saving: boolean = false;
  @State private syncing: boolean = false;
  // 工具缓存卡数据（编辑态回填，只读；保存后回写走库，pop 后管理页重拉）。挂 @State：卡头徽标
  // 直接读它们，普通成员在异步回填后不触发重渲（徽标会冻在首帧）
  @State private toolsCache: McpToolCacheItem[] = [];
  @State private lastSyncAt: number = 0;
  @State private lastError: string = '';
  // 工具清单展开态（缺省收起；点标题行展开，纯 UI 态不持久化）
  @State private toolsOpen: boolean = false;

  // 行级标注重算（井 rowMark 入参单点）：判据 = 回填行 ∧ (Asset 实况, 元数据 hasValue) 三态。
  // 只在平行数组变化处调用，不在 build 里算（宪法性能红线）
  private syncHeaderMarks(): void {
    const marks: string[] = [];
    const warns: boolean[] = [];
    for (let i: number = 0; i < this.headerRows.length; i++) {
      if (!this.rowFromDb[i]) {
        marks.push('');
        warns.push(false);
        continue;
      }
      const has: boolean = i < this.rowHasAssetValue.length && this.rowHasAssetValue[i];
      const meta: boolean = i < this.rowMetaHasValue.length && this.rowMetaHasValue[i];
      marks.push(has ? '已保存' : (meta ? '值缺失，请填入新值' : '未设置'));
      warns.push(!has && meta);
    }
    this.rowMarks = marks;
    this.rowMarkWarn = warns;
  }

  // 行删除的平行数组同步（井已自行 splice headerRows，本侧只裁元数据 + 重算标注）
  private dropHeaderMeta(index: number): void {
    this.rowFromDb.splice(index, 1);
    this.rowMetaHasValue.splice(index, 1);
    this.rowHasAssetValue.splice(index, 1);
    this.oldValues.splice(index, 1);
    this.syncHeaderMarks();
  }

  // 工具清单摘要：件数 + 已关闭件数（用户进这页常是确认「我是不是把某个工具关了」）
  private toolsSummary(): string {
    if (this.toolsCache.length === 0) {
      return '';
    }
    let off: number = 0;
    for (const tool of this.toolsCache) {
      if (!tool.enabled) {
        off++;
      }
    }
    return off > 0 ? this.toolsCache.length + ' 件工具，' + off + ' 件已关闭' :
      this.toolsCache.length + ' 件工具，全部启用';
  }

  aboutToAppear(): void {
    // param 解析（入口唯一且必传）
    const params: Array<McpEditParam> =
      this.pathStack.getParamByName(ROUTE_MCP_SERVER_EDIT_PAGE) as Array<McpEditParam>;
    const param: McpEditParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.serverId = param.serverId;
    if (param.serverId === '') {
      return; // 新建：空表单（新建恒启用）
    }
    // 编辑态回填：元数据同步读库；头值不回填（明文最小过手）——只异步判定 Asset 值实况
    queryMcpServers()
      .then((rows: McpServerRow[]): void => {
        if (this.departed) {
          return;
        }
        const row: McpServerRow | undefined =
          rows.find((item: McpServerRow): boolean => item.id === param.serverId);
        if (row === undefined) {
          this.getUIContext().getPromptAction().showToast({ message: '服务器不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.url = row.url;
        // 脏值防御：未知认证档归 custom、非法版本归自动协商（绕过 UI 手改库不产生空选态）
        this.authKind = normalizeMcpAuthKind(row.authKind);
        this.protocolVersion = isValidMcpProtocolVersion(row.protocolVersion) ?
          row.protocolVersion : MCP_VERSION_AUTO;
        this.lastSyncAt = row.lastSyncAt;
        this.lastError = row.lastError;
        this.toolsCache = parseMcpToolCache(row.toolsJson);
        const metas: McpHeaderMetaItem[] = parseMcpHeaderMeta(row.headersJson);
        this.headerRows = metas.map((meta: McpHeaderMetaItem): HeaderPair =>
          ({ k: meta.name, v: '' } as HeaderPair));
        this.rowFromDb = metas.map((_meta: McpHeaderMetaItem): boolean => true);
        this.rowMetaHasValue = metas.map((meta: McpHeaderMetaItem): boolean => meta.hasValue);
        this.rowHasAssetValue = metas.map((_meta: McpHeaderMetaItem): boolean => false);
        this.syncHeaderMarks();
        this.headerValuesLoaded = metas.length === 0;
        // ★ 回填按「行身份」映射而非原始下标：Asset 读回异步，期间用户可删/加行使平行数组
        // 错位——按下标覆写会把被删行的密钥写到后一行头上。记住发起读取时的行对象序，回执按
        // indexOf 落到当前位置，已删行跳过，新增行保留空槽。
        const loadedRows: HeaderPair[] = this.headerRows.slice();
        loadMcpServerHeaderValues(row.id)
          .then((values: string[]): void => {
            if (this.departed) {
              return;
            }
            const nextOldValues: string[] = this.oldValues.slice();
            const nextHasAssetValue: boolean[] = this.rowHasAssetValue.slice();
            for (let i: number = 0; i < loadedRows.length && i < values.length; i++) {
              const currentIndex: number = this.headerRows.indexOf(loadedRows[i]);
              if (currentIndex < 0) {
                continue; // 该行在读取期间已被用户删除
              }
              nextOldValues[currentIndex] = values[i];
              nextHasAssetValue[currentIndex] = values[i] !== '';
            }
            this.oldValues = nextOldValues;
            this.rowHasAssetValue = nextHasAssetValue;
            // 标注随 Asset 实况重算（井的 rowMark 是 @Prop，整组替换即刷）
            this.syncHeaderMarks();
            // 认证分档旧值分桶：bearer = Authorization 头，apiKey = 首行名值对；值只进私有成员
            // 供「留空保持原值」，标记态走 @State（明文不上屏）
            for (let i: number = 0; i < metas.length; i++) {
              if (this.authKind === MCP_AUTH_BEARER &&
                metas[i].name.toLowerCase() === 'authorization') {
                this.bearerMetaHasValue = metas[i].hasValue;
                this.bearerStoredValue = i < values.length ? values[i] : '';
                this.bearerHasStored = this.bearerStoredValue !== '';
              }
            }
            if (this.authKind === MCP_AUTH_API_KEY && metas.length > 0) {
              this.apiKeyName = metas[0].name;
              this.apiKeyMetaHasValue = metas[0].hasValue;
              this.apiKeyStoredValue = values.length > 0 ? values[0] : '';
              this.apiKeyHasStored = this.apiKeyStoredValue !== '';
            }
            this.headerValuesLoaded = true;
          })
          .catch((_e: Object): void => {
            // 读失败保显示旧态（标记不误报缺失），完成闸不开——保存链拦截防静默清空值
            if (this.departed) {
              return;
            }
            this.headerValuesLoaded = false;
          });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction()
          .showToast({ message: '服务器读取失败：' + (e as Error).message });
      });
  }

  // ── 名称实时校验（格式同步判 + 查重异步查库排除自身；McpDb 增改闸是保存时兜底）──
  private onNameChange(value: string): void {
    this.name = value;
    this.nameTaken = false;
    const trimmed: string = value.trim();
    if (trimmed === '') {
      return;
    }
    queryMcpServers()
      .then((rows: McpServerRow[]): void => {
        if (this.departed) {
          return;
        }
        // 竞态守卫：只认最新输入发起的查重结果（快速连续输入丢弃过期回执）
        if (trimmed !== this.name.trim()) {
          return;
        }
        this.nameTaken = rows.some((row: McpServerRow): boolean =>
          row.name === trimmed && row.id !== this.serverId);
      })
      .catch((_e: Object): void => {
        // 实时查重失败 = 降级无实时提示（保存链 McpDb 增改闸单点把守，不算静默失败）
      });
  }

  private nameErrorText(): string {
    const trimmed: string = this.name.trim();
    if (trimmed !== '' && !isValidMcpServerName(trimmed)) {
      return '名称只能用字母和数字';
    }
    if (this.nameTaken) {
      return '已有名为「' + trimmed + '」的服务器';
    }
    return '';
  }

  // ── 请求头行组 ──
  // 添加行（井的 onAddRow 钩子；上限拦截 + toast 是本域规则）——追加后元数据同步补位并重算标注
  private addHeaderRow(): void {
    if (this.headerRows.length >= MCP_HEADERS_MAX) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '最多添加 ' + MCP_HEADERS_MAX + ' 组请求头' });
      return;
    }
    this.headerRows.push({ k: '', v: '' });
    this.rowFromDb.push(false);
    this.rowMetaHasValue.push(false);
    this.rowHasAssetValue.push(false);
    this.oldValues.push('');
    this.syncHeaderMarks();
  }

  // ── 认证方式：切档 = 整组重写；有存量头组时给一次性提示防误伤（宫格只发四常量）──
  private pickAuthKind(kind: string): void {
    if (this.authKind === kind) {
      return;
    }
    const replacing: boolean = this.hasExistingHeaderGroup();
    this.authKind = kind;
    if (replacing) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '切换认证方式后保存，会替换现有的请求头' });
    }
  }

  private hasExistingHeaderGroup(): boolean {
    if (this.rowFromDb.some((v: boolean): boolean => v)) {
      return true;
    }
    return this.headerRows.some((row: HeaderPair): boolean => row.k.trim() !== '');
  }

  // 值标记三态（bearer/apiKey 与自定义头组同语义，非明文）
  private authMarkOf(hasStored: boolean, metaHasValue: boolean): string {
    if (hasStored) {
      return '已保存';
    }
    if (metaHasValue) {
      return '值缺失，请填入新值';
    }
    return '未设置';
  }

  private authMarkWarnOf(hasStored: boolean, metaHasValue: boolean): boolean {
    return metaHasValue && !hasStored;
  }

  private authPlaceholderOf(hasStored: boolean, metaHasValue: boolean, example: string): string {
    if (hasStored) {
      return '留空保持原值';
    }
    if (metaHasValue) {
      return '值缺失，请填入新值';
    }
    return example;
  }

  // Bearer 头值组装：粘贴的令牌可能自带「Bearer 」前缀——剥离后统一加前缀，防双前缀；存量值
  // 路径不经过本函数。空输入由调用方先归一，本函数只处理非空令牌
  private bearerHeaderValueOf(input: string): string {
    const trimmed: string = input.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return 'Bearer ' + trimmed.substring(7).trim();
    }
    return 'Bearer ' + trimmed;
  }

  // 认证头组组装单点（保存链与测试连接共用——禁抄两份）：按 authKind 分档，none = 空组。留空
  // 语义沿 custom 档：空且旧值在 = 留空保持（storedValue 回填）、空且无旧值 = 不组装。鉴权失败
  // 由 401 错误句归因
  private buildAuthHeaderGroup(): McpAuthHeaderGroup {
    const metas: McpHeaderMetaItem[] = [];
    const values: string[] = [];
    if (this.authKind === MCP_AUTH_BEARER) {
      // trim 后空 = 留空语义（与自定义档空值同判，纯空白不造「Bearer 」空头）
      const rawToken: string = this.bearerToken.trim();
      const token: string = rawToken !== '' ? this.bearerHeaderValueOf(rawToken) :
        (this.bearerHasStored ? this.bearerStoredValue : '');
      if (token !== '') {
        metas.push({ name: 'Authorization', hasValue: true });
        values.push(token);
      }
    } else if (this.authKind === MCP_AUTH_API_KEY) {
      const headerName: string = this.apiKeyName.trim();
      if (headerName !== '') {
        const value: string = this.apiKeyValue !== '' ? this.apiKeyValue :
          (this.apiKeyHasStored ? this.apiKeyStoredValue : '');
        metas.push({ name: headerName, hasValue: value !== '' });
        values.push(value);
      }
    } else if (this.authKind === MCP_AUTH_CUSTOM) {
      for (let i: number = 0; i < this.headerRows.length; i++) {
        const row: HeaderPair = this.headerRows[i];
        const headerName: string = row.k.trim();
        if (headerName === '') {
          continue;
        }
        if (row.v !== '') {
          metas.push({ name: headerName, hasValue: true });
          values.push(row.v);
        } else if (this.rowHasAssetValue[i]) {
          metas.push({ name: headerName, hasValue: true });
          values.push(this.oldValues[i]);
        } else {
          metas.push({ name: headerName, hasValue: false });
          values.push('');
        }
      }
    }
    const group: McpAuthHeaderGroup = { metas: metas, values: values };
    return group;
  }

  // ── 逐行开关（编辑态）：即时落库 + 注册面同步；失败 toast + 回读真值（P0-1）。写链
  //    runWriteQueued 已串行——连点各写一次，最后一次落定即用户意图──
  private toggleTool(toolName: string, isOn: boolean): void {
    if (this.serverId === '') {
      return;
    }
    const next: McpToolCacheItem[] = this.toolsCache.map((item: McpToolCacheItem): McpToolCacheItem => {
      if (item.name !== toolName) {
        return item;
      }
      const replaced: McpToolCacheItem = {
        name: item.name, description: item.description, inputSchema: item.inputSchema,
        enabled: isOn
      };
      return replaced;
    });
    this.toolsCache = next;
    setMcpServerTools(this.serverId, serializeMcpToolCache(next), this.lastSyncAt, this.lastError)
      .then((): Promise<void> => {
        return syncMcpTools();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction()
          .showToast({ message: '开关保存失败：' + (e as Error).message });
        this.reloadRowState();
      });
  }

  // 回读本行库现值（开关写失败的回滚显示——UI 不留在失败态）
  private reloadRowState(): void {
    queryMcpServers()
      .then((rows: McpServerRow[]): void => {
        if (this.departed) {
          return;
        }
        const row: McpServerRow | undefined =
          rows.find((item: McpServerRow): boolean => item.id === this.serverId);
        if (row === undefined) {
          return;
        }
        this.toolsCache = parseMcpToolCache(row.toolsJson);
        this.lastSyncAt = row.lastSyncAt;
        this.lastError = row.lastError;
      })
      .catch((_e: Object): void => {
      });
  }

  // ── 测试连接（只读探针）：按当前表单态直跑握手 + tools/list；头值经 endpoint.headerValues
  //    显式传入（新输入值尚未落 Asset）。会话前后均清——未保存配置不得留在缓存──
  private async testConnection(): Promise<void> {
    if (this.testing) {
      return;
    }
    const url: string = this.url.trim();
    if (!/^https?:\/\//.test(url)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '地址需以 https:// 或 http:// 开头' });
      return;
    }
    if (!this.headerValuesLoaded && this.rowFromDb.some((v: boolean): boolean => v)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '请求头值读取失败，请重新进入本页再测试' });
      return;
    }
    if (!isValidMcpProtocolVersion(this.protocolVersion)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '协议版本不合法，请重新选择' });
      return;
    }
    const group: McpAuthHeaderGroup = this.buildAuthHeaderGroup();
    const sessionId: string = this.serverId !== '' ? this.serverId : MCP_TEST_SESSION_ID;
    this.testing = true;
    this.testResult = '';
    clearMcpSession(sessionId);
    try {
      const outcome: McpSyncOutcome = await syncMcpServer({
        serverId: sessionId, url: url, headersJson: serializeMcpHeaderMeta(group.metas),
        protocolVersion: this.protocolVersion, headerValues: group.values
      } as McpServerEndpoint);
      if (this.departed) {
        return;
      }
      this.testOk = true;
      this.testResult = '连接成功，' + outcome.tools.length + ' 件工具';
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.testOk = false;
      const brief: string = (e as Error).message;
      this.testResult = brief !== '' ? '连接失败：' + brief : '连接失败，请检查地址和认证配置';
    } finally {
      clearMcpSession(sessionId);
      if (!this.departed) {
        this.testing = false;
      }
    }
  }

  // ── 保存链（顺序即拦截序；自动测连失败不阻断保存——两路都回写缓存口后 pop）──
  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const name: string = this.name.trim();
    if (name === '' || !isValidMcpServerName(name)) {
      this.getUIContext().getPromptAction().showToast({ message: '名称只能用字母和数字' });
      return;
    }
    if (this.nameTaken) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '已有名为「' + name + '」的服务器，请换一个名称' });
      return;
    }
    const url: string = this.url.trim();
    if (!/^https?:\/\//.test(url)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '地址需以 https:// 或 http:// 开头' });
      return;
    }
    if (!this.headerValuesLoaded && this.rowFromDb.some((v: boolean): boolean => v)) {
      // 值读取未完成：组重写语义下盲存会把「留空保持」行清成空值——拦截重试（P0-1）
      this.getUIContext().getPromptAction()
        .showToast({ message: '请求头值读取失败，请重新进入本页再保存' });
      return;
    }
    if (!isValidMcpProtocolVersion(this.protocolVersion)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '协议版本不合法，请重新选择' });
      return;
    }
    // 头组组装（单点复用——与测试连接同一段 buildAuthHeaderGroup；名称为空的行丢弃）
    const group: McpAuthHeaderGroup = this.buildAuthHeaderGroup();
    const metas: McpHeaderMetaItem[] = group.metas;
    const values: string[] = group.values;
    if (metas.length > MCP_HEADERS_MAX) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '最多添加 ' + MCP_HEADERS_MAX + ' 组请求头' });
      return;
    }
    this.saving = true;
    this.syncing = true;
    try {
      let serverId: string = this.serverId;
      if (serverId === '') {
        await addMcpServer(name, url, serializeMcpHeaderMeta(metas), values, this.authKind,
          this.protocolVersion);
        // 新建行 id 由委托层铸造——按名查回（名称唯一闸保证必中；查不到抛错不静默）
        const rows: McpServerRow[] = await queryMcpServers();
        const hit: McpServerRow | undefined =
          rows.find((row: McpServerRow): boolean => row.name === name);
        if (hit === undefined) {
          throw new Error('保存后未能定位新服务器行');
        }
        serverId = hit.id;
      } else {
        await editMcpServer(serverId, name, url, serializeMcpHeaderMeta(metas), values,
          this.authKind, this.protocolVersion);
      }
      // 明文即弃（值组已写 Asset——页面引用清空）
      this.headerRows = [];
      this.oldValues = [];
      this.bearerToken = '';
      this.apiKeyValue = '';
      this.bearerStoredValue = '';
      this.apiKeyStoredValue = '';
      // 配置变更清会话缓存（下次同步重握手）
      clearMcpSession(serverId);
      // 自动测连：成功 = 新缓存 + lastSyncAt + 清错；失败 = 缓存不动只回写 lastError 摘要（保留
      // 当前缓存与同步时间，不得回退到进页旧快照；摘要不含头值——密钥红线）。新缓存先经 $ref
      // 内联展开再落库
      let syncBrief: string = '';
      try {
        const outcome: McpSyncOutcome = await syncMcpServer({
          serverId: serverId, url: url, headersJson: serializeMcpHeaderMeta(metas),
          protocolVersion: this.protocolVersion
        } as McpServerEndpoint);
        await setMcpServerTools(serverId,
          serializeMcpToolCache(mergeMcpToolEnablement(this.toolsCache,
            expandMcpToolSchemas(outcome.tools))), Date.now(), '');
      } catch (e) {
        syncBrief = (e as Error).message;
        const keepTools: string = serializeMcpToolCache(this.toolsCache);
        try {
          await setMcpServerTools(serverId, keepTools, this.lastSyncAt, syncBrief);
        } catch (e2) {
          // 摘要回写失败：管理页显示旧态，下次刷新自愈——不叠加提示
        }
      }
      // 注册面同步（新增/改名/换 URL 后声明面即刻收敛；失败路幂等无动作）
      await syncMcpTools();
      if (this.departed) {
        return; // 用户在途退出：写库与回写已照常完成，放弃已亡组件上的 UI 与 pop
      }
      this.syncing = false;
      this.getUIContext().getPromptAction().showToast({
        message: syncBrief === '' ? '已保存' : '已保存。同步失败：' + syncBrief
      });
      this.pathStack.pop({ saved: true });
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.syncing = false;
      this.getUIContext().getPromptAction()
        .showToast({ message: '保存失败：' + (e as Error).message });
    } finally {
      if (!this.departed) {
        this.saving = false;
      }
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 名称地址卡（★ 启用开关卡已退役，启停改 McpPage 行卡 Toggle）──
        Column({ space: 6 }) {
          Text('名称')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('名称只能用字母和数字，助手调用工具时会用到它。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          TextInput({ placeholder: '例如 weather', text: this.name })
            .width('100%')
            .maxLength(MCP_NAME_MAX)
            .onChange((value: string): void => {
              this.onNameChange(value);
            })
          if (this.nameErrorText() !== '') {
            Text(this.nameErrorText())
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('100%')
          }
          Text('服务器地址')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
            .margin({ top: 6 })
          Text('例如 https://example.com/mcp')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          TextInput({ placeholder: '粘贴服务器地址', text: this.url })
            .width('100%')
            .maxLength(MCP_URL_MAX)
            .onChange((value: string): void => {
              this.url = value;
            })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 认证卡（四档选择——后三档保存时归一为请求头组，底层链路零分叉）──
        Column({ space: 8 }) {
          Text('认证')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('选择服务器要求的认证方式。切换后保存会整组替换现有的请求头。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          // 认证四档 = 2×2 选项宫格（规范 §4.13「恰 4 项 → 宫格」）：选中后原地展开对应输入；
          // 宫格是选项不是按钮，选中态归 authKind 单一真值。chip 配色档 = 与协议版本 chip 同族
          // （未选淡蓝底蓝字 / 选中强调蓝实底白字 / 撤圆勾，2026-11-11 决明拍板）
          OptionTileGrid({
            labels: MCP_AUTH_LABELS,
            values: MCP_AUTH_OPTIONS,
            selectedValue: this.authKind,
            tone: 'chip',
            onPick: (value: string): void => {
              this.pickAuthKind(value);
            }
          })
          if (this.authKind === MCP_AUTH_NONE) {
            Text('不需要鉴权的服务器选这一档。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          if (this.authKind === MCP_AUTH_BEARER) {
            Text('令牌只存在本机凭据区。保存时自动组装成 Authorization 请求头。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({
              placeholder: this.authPlaceholderOf(this.bearerHasStored,
                this.bearerMetaHasValue, '例如粘贴 Bearer 令牌'),
              text: this.bearerToken
            })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .maxLength(HEADER_VALUE_MAX)
              .width('100%')
              // 与 API Key 分支输入统一 40（官方默认高），消除两档自然高度差
              .height(40)
              .onChange((value: string): void => {
                this.bearerToken = value;
              })
            if (this.bearerHasStored || this.bearerMetaHasValue) {
              Text(this.authMarkOf(this.bearerHasStored, this.bearerMetaHasValue))
                .fontSize(12)
                .fontColor(this.authMarkWarnOf(this.bearerHasStored, this.bearerMetaHasValue) ?
                  $r('sys.color.ohos_id_color_warning') : cardDescColor())
                .width('100%')
                .height(18)
            }
          }
          if (this.authKind === MCP_AUTH_API_KEY) {
            Text('保存时把这组名称和值放进请求头。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            TextInput({ placeholder: '请求头名称，例如 X-API-Key', text: this.apiKeyName })
              .maxLength(HEADER_KEY_MAX)
              .width('100%')
              .height(40)
              .onChange((value: string): void => {
                this.apiKeyName = value;
              })
            TextInput({
              placeholder: this.authPlaceholderOf(this.apiKeyHasStored,
                this.apiKeyMetaHasValue, '例如粘贴密钥'),
              text: this.apiKeyValue
            })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .maxLength(HEADER_VALUE_MAX)
              .width('100%')
              .height(40)
              .onChange((value: string): void => {
                this.apiKeyValue = value;
              })
            if (this.apiKeyHasStored || this.apiKeyMetaHasValue) {
              Text(this.authMarkOf(this.apiKeyHasStored, this.apiKeyMetaHasValue))
                .fontSize(12)
                .fontColor(this.authMarkWarnOf(this.apiKeyHasStored, this.apiKeyMetaHasValue) ?
                  $r('sys.color.ohos_id_color_warning') : cardDescColor())
                .width('100%')
                .height(18)
            }
          }
          if (this.authKind === MCP_AUTH_CUSTOM) {
            Text('在下方请求头卡里添加自备密钥。名称为空的行保存时丢弃。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 协议版本卡（对话模型卡形态：卡头 + 单行值，点值行弹选 5 档——2026-11-11 决明拍板；
        //    强制档只升级广告值，只认新报文形态的服务器仍可能连不上，边界收卡头 ⓘ）──
        Column() {
          Column({ space: 12 }) {
            FunctionalCardHeader({
              title: '协议版本',
              hint: '自动协商适合大多数服务器。强制版本只升级握手广告值，只认新版报文形态的服务器仍可能连不上。'
            })
            Column() {
              SettingMenuRow({
                // ★ 2026-11-11 自检轮：行标签原复述卡头「协议版本」（同形先例 = 默认模型卡
                // 卡头「默认模型」+ 行「模型」，行标签不复述卡头标题），改「版本」
                label: '版本',
                subtitle: '握手时广播的值',
                value: this.protocolVersion,
                options: MCP_VERSION_OPTIONS,
                optionLabels: MCP_VERSION_LABELS,
                dividerTop: false,
                onPick: (option: string): void => {
                  this.protocolVersion = option;
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 16, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 请求头卡（仅自定义档显示）──
        // 行组挂 KeyValueWell（行键纪律、键｜值布局、行尾圆删、添加键下沉井内）；本页只补值
        // 密文（valueSecret）与行级标注（rowMark 三态，判据在 syncHeaderMarks）；上限拦截走
        // onAddRow 钩子（≤5 组 + toast 是本域规则）
        if (this.authKind === MCP_AUTH_CUSTOM) {
          Column({ space: 12 }) {
            Column({ space: 2 }) {
              Text('请求头')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .width('100%')
              Text('在这里添加自备密钥的请求头。名称为空的行保存时丢弃')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            KeyValueWell({
              rows: $headerRows,
              keyPlaceholder: '名称，例如 Authorization',
              valuePlaceholder: '值，例如 Bearer abc123',
              addLabel: '＋ 添加请求头',
              keyMaxLength: HEADER_KEY_MAX,
              valueMaxLength: HEADER_VALUE_MAX,
              valueSecret: true,
              emptyHint: '暂无请求头。无需鉴权的服务器可以不填',
              rowMark: this.rowMarks,
              rowMarkWarn: this.rowMarkWarn,
              onAddRow: (): void => {
                this.addHeaderRow();
              },
              onRowRemoved: (index: number): void => {
                this.dropHeaderMeta(index);
              }
            })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        }

        // ── 工具缓存卡（编辑态：逐行开关；错误全文承接，管理页只显示摘要）──
        // 卡头徽标：已同步 / 同步失败配点，未同步属弱化档不配点；清单默认折叠成一行摘要——
        // 十几件工具平铺会把连接测试挤出视口。展开态纯 UI、不持久化。
        if (this.serverId !== '') {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('工具缓存')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .layoutWeight(1)
              if (this.lastError !== '') {
                StatusBadge({ text: '同步失败', tone: BadgeTone.DANGER, dot: true })
              } else if (this.lastSyncAt > 0) {
                StatusBadge({ text: '已同步', tone: BadgeTone.SUCCESS, dot: true })
              } else {
                StatusBadge({ text: '未同步', tone: BadgeTone.WEAK })
              }
              if (this.toolsCache.length > 0) {
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(12)
                  .fontColor([cardDescColor()])
                  .rotate({ angle: this.toolsOpen ? 180 : 0 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              if (this.toolsCache.length > 0) {
                this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
                  (): void => {
                    this.toolsOpen = !this.toolsOpen;
                  });
              }
            })
            if (this.toolsCache.length > 0) {
              Text(this.toolsSummary())
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            Text(this.lastSyncAt > 0 ? '最近同步 ' + formatWorkspaceTime(this.lastSyncAt) :
              '尚未同步。保存后自动连接并同步')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
            if (this.lastError !== '') {
              Text(this.lastError)
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_warning'))
                .width('100%')
            }
            if (this.toolsCache.length === 0 && this.lastError === '' && this.lastSyncAt > 0) {
              Text('服务器未提供工具')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            if (this.toolsCache.length > 0 && this.toolsOpen) {
              Text('关闭的工具不注入对话。刷新清单后开关保留。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
              ForEach(this.toolsCache, (tool: McpToolCacheItem) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(tool.name)
                    .fontSize(14)
                    .fontColor(cardTitleColor())
                    .width('100%')
                  if (tool.description !== '') {
                    Text(tool.description)
                      .fontSize(12)
                      .fontColor(cardDescColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                // 逐工具开关：即时落库 + 注册面同步；键含 enabled（见 ForEach 键生成器）——
                // 漏一项 = 开关翻转后界面静默冻结（坑44/80 家族，键须覆盖全部可变展示成分）
                Toggle({ type: ToggleType.Switch, isOn: tool.enabled })
                  .onChange((isOn: boolean): void => {
                    this.toggleTool(tool.name, isOn);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (tool: McpToolCacheItem): string =>
              't' + tool.name + (tool.enabled ? '1' : '0'))
            }
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        }

        // ── 连接测试卡（只读探针——按当前表单态直跑握手与 tools/list，不落库）──
        Column({ space: 8 }) {
          Text('连接测试')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
          Text('按上面填写的地址、认证和协议版本连接一次，不会保存配置。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          Button('测试连接')
            .fontColor(fallbackButtonFontTinted(this.contentFallback))
            .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
            .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.testing)
            .onClick((): void => {
              this.testConnection();
            })
          if (this.testing) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(16)
                .height(16)
              Text('正在连接服务器')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          if (this.testResult !== '') {
            Text(this.testResult)
              .fontSize(13)
              .fontColor(this.testOk ? cardDescColor() : $r('sys.color.ohos_id_color_warning'))
              .width('100%')
          }
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 同步在途提示（保存链全程显示——写库与自动测连在途）──
        if (this.syncing) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
            Text('正在连接服务器并同步工具')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width(CARD_PANEL_WIDTH)
          .alignItems(VerticalAlign.Center)
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
      title: '编辑服务器',
      // ★（坑17）：保存链带参 pop，无参 pop 时 McpPage 的 onPop 不重拉（列表冻结）。拦截返回：
      // 保存在途 → 拦住提示，等写落定再返回（防重拉抢在写提交前读到旧行）；空闲 → pop 带
      // result 触发重拉（无改动也重拉一次，小表低频页代价可忽略）
      onBackPressed: (): boolean => {
        if (this.saving) {
          this.getUIContext().getPromptAction().showToast({ message: '正在保存，请稍候' });
          return true;
        }
        this.pathStack.pop({ saved: true });
        return true;
      },
      menuHds: mcpSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
