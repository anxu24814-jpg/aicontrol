// 设置读工具域：本域只承载一件 get_app_preference——应用偏好设置状态只读查询（原「写」半
// set_app_preference 已随控制台合并笔退役，决明拍板「去掉更改设置功能，保留读取能力」；
// 白名单九项 = 读件的范围与档位反查单源，沿革见变更记录）。defaultEnabled=false，普通
// 助手工具页「应用管理」卡开关。
// ★ 工具面冻结（2026-11-01 决明拍板）：白名单九项为封存基准，以后新增功能默认不接入
// 工具面，确需接入或解冻 = 停工报决明（宪法「应用管理工具面冻结」条）。
// 边界：执行器契约 ToolExecutor 在叶子模块 ToolContracts.ets——本文件模块作用域要读
// ProactiveConfig 与 MemoryGen 的常量，再引聚合根 ToolTypes 即成环、踩未初始化绑定（启动
// 闪退坑）。
import { ToolExecutor } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { PREF_AUTO_RETRY_KEY, PREF_BG_REPLY_NOTIFY_KEY } from '../AppPreferences';
import { MEMORY_AUTO_KEY, MEMORY_ENABLED_KEY, MEMORY_READ_MODE_DEFAULT, MEMORY_READ_MODE_INJECT,
  MEMORY_READ_MODE_KEY, MEMORY_READ_MODE_TOOL } from '../MemoryGen';
import { PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY,
  PROACTIVE_DAILY_LIMIT_OPTIONS, PROACTIVE_ENABLED_KEY, PROACTIVE_INTERVAL_DEFAULT,
  PROACTIVE_INTERVAL_HOURS_KEY, PROACTIVE_INTERVAL_OPTIONS, PROACTIVE_QUIET_MAX_DEFAULT,
  PROACTIVE_QUIET_MAX_KEY, PROACTIVE_QUIET_MAX_OPTIONS } from '../ProactiveConfig';
import { SETTING_TITLE_AUTO_RETRY, SETTING_TITLE_BG_REPLY_NOTIFY, SETTING_TITLE_MEMORY_AUTO,
  SETTING_TITLE_MEMORY_ENABLED, SETTING_TITLE_MEMORY_READ_MODE,
  SETTING_TITLE_PROACTIVE_DAILY_LIMIT, SETTING_TITLE_PROACTIVE_ENABLED,
  SETTING_TITLE_PROACTIVE_INTERVAL, SETTING_TITLE_PROACTIVE_QUIET_MAX } from '../SettingSearch';
// ── 查询白名单（CherryStudio apply_setting 同构；写件退役后本表 = 读件的范围单源 +
//   档位反查底料）──

// 白名单条目：中文显示名（= 界面真实标题，SETTING_TITLE_* 单源引用）↔ AppStorage 持久键常量
// （import 自各偏好域，禁裸字符串）+ kind（'toggle' 开关型 / 'level' 档位型）+ 缺省值
//（defaultLevel 与 EntryAbility persistProp 注册逐键一致——断言脚本对表）+ level 刻度名表
//（下标 = 档号，toggle 型空数组；defaultLevel 为两型统一形状、toggle 不消费）
// ★ 两型字段分载（2026-11-01 剃刀笔收紧）：defaultValue 仅 toggle 型携带（读缺省回退），
// level 型不消费不带；toggle 取值语义 valueNames 随十二项剃除退役（九项皆通用开关措辞，
// 机制从 git 历史可恢复）
export interface SetPrefWhitelistEntry {
  setting: string;
  key: string;
  kind: string;
  defaultValue?: boolean;
  defaultLevel: number;
  levels: string[];
  // 档位值映射两字段（可选；kind 仍只有 toggle / level 两型）：
  // · levelValues：档位名 → **数字落库值**（主动消息三档位键落库小时/条数/分钟**值**而非档号，
  //   读侧反查须按落库类型取值——见 resolveLevelName 三态注释）；
  // · choiceValues：档位名 → **字符串落库值**（记忆读取方式落库 'inject' / 'tool'）。
  // 两字段与 levels 等长（断言钉长度相等）；同一 entry 二者至多一者在场。
  levelValues?: number[];
  choiceValues?: string[];
}

// ★ 白名单**惰性构建**（真机启动闪退修复）：条目要读 ProactiveConfig / MemoryGen 的档位
// 域数组与常量（levelValues、defaultLevel 的 indexOf 计算），而模块求值期这两模块可能尚在
// 求值中（经聚合根 ToolTypes 回指成环），读到未初始化绑定随后 .map() 即 TypeError = 启动
// JsError 闪退。改成首次调用时构建并缓存——调用点全在运行时，彼时全图求值已完成、值必
// 就绪；且与源数组逐元素同源（断言对表照旧，禁字面量双源）。
let whitelistCache: SetPrefWhitelistEntry[] | null = null;

// 白名单（恰九项：五开关 + 四档位；顺序 = 开关在前档位在后。★ 2026-11-01 剃刀笔收窄：
// 原 21 项中 12 项纯界面/输入/外观偏好剃除——查询面只留助手自身能力与行为域（记忆、
// 主动消息）+ 两条故障诊断高频项（自动重试、后台回复提醒）；被剃项功能与设置页不动，
// 只是助手不再可查。冻结基准 = 本表）
export function setPrefWhitelist(): SetPrefWhitelistEntry[] {
  if (whitelistCache !== null) {
    return whitelistCache;
  }
  whitelistCache = [
  { setting: SETTING_TITLE_BG_REPLY_NOTIFY, key: PREF_BG_REPLY_NOTIFY_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [] },
  // 开关值在轮首现读一次、轮内锁定（域件口径）
  { setting: SETTING_TITLE_AUTO_RETRY, key: PREF_AUTO_RETRY_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [] },
  // ── 记忆域两键（消费方 = MemoryGen 守卫〔发送注入/退出沉淀现读〕+ MemoryPage
  //   @StorageLink）──
  { setting: SETTING_TITLE_MEMORY_ENABLED, key: MEMORY_ENABLED_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [] },
  { setting: SETTING_TITLE_MEMORY_AUTO, key: MEMORY_AUTO_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [] },
  // ── 主动消息四键 + 记忆读取方式：三档位键落库的是**值**（小时/条数/分钟，ProactiveConfig
  //   档位域数组）非档号，故引 levelValues；刻度名数字单源自档位域数组（禁字面量双源），
  //   默认档 = 默认值下标（indexOf 计算，数组调整自动跟随）。读取方式落库字符串
  //   （MemoryGen 常量），引 choiceValues ──
  { setting: SETTING_TITLE_PROACTIVE_ENABLED, key: PROACTIVE_ENABLED_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [] },
  { setting: SETTING_TITLE_PROACTIVE_INTERVAL, key: PROACTIVE_INTERVAL_HOURS_KEY, kind: 'level',
    defaultLevel: PROACTIVE_INTERVAL_OPTIONS.indexOf(PROACTIVE_INTERVAL_DEFAULT),
    levels: PROACTIVE_INTERVAL_OPTIONS.map((hours: number): string => hours + ' 小时'),
    levelValues: PROACTIVE_INTERVAL_OPTIONS },
  { setting: SETTING_TITLE_PROACTIVE_DAILY_LIMIT, key: PROACTIVE_DAILY_LIMIT_KEY, kind: 'level',
    defaultLevel: PROACTIVE_DAILY_LIMIT_OPTIONS.indexOf(PROACTIVE_DAILY_LIMIT_DEFAULT),
    levels: PROACTIVE_DAILY_LIMIT_OPTIONS.map((count: number): string => count + ' 条'),
    levelValues: PROACTIVE_DAILY_LIMIT_OPTIONS },
  { setting: SETTING_TITLE_PROACTIVE_QUIET_MAX, key: PROACTIVE_QUIET_MAX_KEY, kind: 'level',
    defaultLevel: PROACTIVE_QUIET_MAX_OPTIONS.indexOf(PROACTIVE_QUIET_MAX_DEFAULT),
    levels: PROACTIVE_QUIET_MAX_OPTIONS.map((minutes: number): string => minutes + ' 分钟'),
    levelValues: PROACTIVE_QUIET_MAX_OPTIONS },
  { setting: SETTING_TITLE_MEMORY_READ_MODE, key: MEMORY_READ_MODE_KEY, kind: 'level',
    // 默认档 = 数组首项（自动注入）——首项即 MemoryGen.MEMORY_READ_MODE_DEFAULT，顺序契约
    // 同 MemoryPage 分段卡（下标 0 = 自动注入 / 1 = 按需读取）
    defaultLevel: [MEMORY_READ_MODE_INJECT, MEMORY_READ_MODE_TOOL].indexOf(MEMORY_READ_MODE_DEFAULT),
    levels: ['自动注入', '按需读取'],
    choiceValues: [MEMORY_READ_MODE_INJECT, MEMORY_READ_MODE_TOOL] }
  ];
  return whitelistCache;
}

// ── 设置查询执行器（2026-09-06 设置读工具；查询范围 = setPrefWhitelist() 单源）──

// 查询结果条目（kind 两型字段选择性在场：toggle 型 value 必在；level 型仅 levelName——
// JSON.stringify 丢弃 undefined 键，载荷零冗余字段）
interface GetPrefItem {
  setting: string;
  kind: string;
  value?: boolean;
  levelName?: string;
}

// 查询工具顶层载荷
interface GetPrefPayload {
  settings: GetPrefItem[];
}

// 查询工具 desc（白名单清单不进 desc——全量返回值自解释，拼清单徒增每请求 token；desc
// 只立调用纪律：状态类问题先查实不猜测）
export function buildGetPrefDesc(): string {
  return '查询本应用偏好设置的当前状态，返回全部可查询设置项的实时值，开关项含当前布尔值，' +
    '选择项含当前所选名称，档位项含当前刻度名。用户询问某项设置是否开启或当前选的是什么时' +
    '调用；回答设置状态前先调用本工具查实，不要凭记忆或猜测回答。';
}

// 档位名反查（读侧单源；导出便于断言直跑）：落库值 → 刻度名。三态——命中映射回刻度名；
// 未命中（脏值 / 版本回滚遗留值）回 String(落库值)；键未配置回缺省档刻度名。★ 类型泛型必须
// 与落库类型一致（真缺陷面）：choiceValues 型落库字符串（记忆读取方式）、levelValues 型落库
// 数字（主动消息三档位）、无映射型落库档号（防御分支）——一律按 get<number> 读会把 'tool'
// 读成缺省（静默错值），故按在场类型分支取值
export function resolveLevelName(entry: SetPrefWhitelistEntry): string {
  const choice: string[] = entry.choiceValues !== undefined ? entry.choiceValues : [];
  if (choice.length > 0) {
    const stored: string = AppStorage.get<string>(entry.key) ?? '';
    if (stored === '') {
      return entry.levels[entry.defaultLevel];
    }
    const hit: number = choice.indexOf(stored);
    return hit >= 0 ? entry.levels[hit] : String(stored);
  }
  const values: number[] = entry.levelValues !== undefined ? entry.levelValues : [];
  if (values.length > 0) {
    const stored: number = AppStorage.get<number>(entry.key) ?? values[entry.defaultLevel];
    const hit: number = values.indexOf(stored);
    return hit >= 0 ? entry.levels[hit] : String(stored);
  }
  const lv: number = AppStorage.get<number>(entry.key) ?? entry.defaultLevel;
  const inRange: boolean = lv >= 0 && lv < entry.levels.length;
  return inRange ? entry.levels[lv] : String(lv); // 脏档号越界回数字字面量不崩（脏数据防御）
}

// 设置查询执行器（无参全量快照）：遍历白名单现读 AppStorage（读侧零写入零副作用，无审批
// 面）；toggle 值缺省回退与 persistProp 注册值一致（?? defaultValue ?? false——回退仅防御）；
// level 型反查走 resolveLevelName 单源。全量约 0.5KB 远低于 clipToolResult 截断线；无参工具
// schema 空 object（GetTimeInfoExecutor 同款）
export class GetAppPreferenceExecutor implements ToolExecutor {
  execute(_argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const items: GetPrefItem[] = [];
    for (const entry of setPrefWhitelist()) {
      if (entry.kind === 'level') {
        const lvItem: GetPrefItem = { setting: entry.setting, kind: entry.kind,
          levelName: resolveLevelName(entry) };
        items.push(lvItem);
        continue;
      }
      const value: boolean = AppStorage.get<boolean>(entry.key) ?? entry.defaultValue ?? false;
      const item: GetPrefItem = { setting: entry.setting, kind: entry.kind, value: value };
      items.push(item);
    }
    const payload: GetPrefPayload = { settings: items };
    return Promise.resolve(JSON.stringify(payload));
  }
}
