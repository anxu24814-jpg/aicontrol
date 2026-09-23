// 设置读写工具域（2026-09-08 自 ToolTypes.ets 域级最小拆分外迁——债务条登记的候选缝之
// 一，域 332 行整体迁出后 ToolTypes 回落软引导区）。
// 两个内置工具（均 defaultEnabled=false + console-exclusive，仅控制台助手可用；注册与
// 工具名常量归口 ToolTypes.ets，本文件只承载实现）：
// · set_app_preference（2026-09-05 控制台助手第二笔）：按用户明确指令直改应用偏好设置
//   （白名单二十二键：十七开关 + 五档位；方案 A 直改 + 回执）；desc/schema 自白名单
//   动态生成零双源。★ 规模释义修正（2026-09-10 本笔）：本条原写「十五键：十二开关」是
//   2026-09-09 智感握姿功能整体移除前的旧数（a83ad7a 删条目未跟改注释，同轮 ToolTypes
//   头注释同误）——移除后实为十四键（十一开关 + 三档位），本次扩面三开关后为十七键；
//   ★ 2026-09-12 分项退役：原「悬浮底栏」「其他控件」两档位键出表（两处档位恒跟随沉浸
//   光感总档，见 ImmersiveLevel.ets 头注释），回落十五键。
//   ★ 2026-09-13 工具补齐三件扩面：主动消息四键（总开关 + 三档位）+ 记忆读取方式
//   （十五 → 二十键：十五开关 + 五档位）——三档位键落库的是**值**（小时/条数/分钟，
//   不是档号），读取方式落库字符串，故本笔引入 levelValues / choiceValues 两可选映射字段
//   （见 SetPrefWhitelistEntry 注释；kind 仍只有 toggle / level 两型，模型面契约零变化）。
//   ★ 2026-09-19 会话图标显示键并入（二十 → 二十一键：十六开关 + 五档位，纯 toggle 零新
//   机制，见 set-pref-tool-check.mjs 头注释同笔记录）——本条为现状数，2026-09-20 D6-2 核正；
//   ★ 2026-09-22 聊天自动重试键并入（二十一 → 二十二键：十七开关 + 五档位，纯 toggle 零新机制）
// · get_app_preference（2026-09-06 设置读工具）：应用偏好设置状态只读查询（读写分离两
//   工具——调研档 docs/调研-设置状态读取工具-20260906.md；决明拍板只对控制台助手开放
//   且可关闭）。
// 边界：执行器契约 ToolExecutor 在叶子模块 ToolContracts.ets（2026-09-13 闪退修复笔外迁——
// 本文件模块作用域要读 ProactiveGen/MemoryGen 的常量，再引聚合根 ToolTypes 即成环、踩未
// 初始化绑定）；AppStorage 直写即持久化（各键
// persistProp 均已在 EntryAbility 注册——禁重复 persistProp 禁新广播键，坑16/17）。
import { ToolExecutor } from './ToolContracts';
import { PREF_AUTO_RETRY_KEY, PREF_BIOMETRIC_FACE_KEY, PREF_BG_SESSION_ONLY_KEY,
  PREF_KEYBOARD_SEND_KEY, PREF_KEEP_SCREEN_ON_KEY, PREF_LAUNCH_NEW_CHAT_KEY,
  PREF_SEARCH_SERVICE_ENABLED_KEY, PREF_SESSION_ICON_KEY, PREF_SESSION_TIME_KEY,
  PREF_STREAM_ENGINE_KEY, PREF_STREAM_FOLLOW_KEY, PREF_TAB_SWITCH_ANIM_KEY,
  PREF_THINK_EXPAND_KEY } from '../AppPreferences';
import { MEMORY_AUTO_KEY, MEMORY_ENABLED_KEY, MEMORY_READ_MODE_DEFAULT, MEMORY_READ_MODE_INJECT,
  MEMORY_READ_MODE_KEY, MEMORY_READ_MODE_TOOL } from '../MemoryGen';
import { PROACTIVE_DAILY_LIMIT_DEFAULT, PROACTIVE_DAILY_LIMIT_KEY,
  PROACTIVE_DAILY_LIMIT_OPTIONS, PROACTIVE_ENABLED_KEY, PROACTIVE_INTERVAL_DEFAULT,
  PROACTIVE_INTERVAL_HOURS_KEY, PROACTIVE_INTERVAL_OPTIONS, PROACTIVE_QUIET_MAX_DEFAULT,
  PROACTIVE_QUIET_MAX_KEY, PROACTIVE_QUIET_MAX_OPTIONS } from '../ProactiveGen';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY,
  IMMERSIVE_LEVEL_SHORT_NAMES } from '../ImmersiveLevel';
import { SETTING_TITLE_AUTO_RETRY, SETTING_TITLE_BIOMETRIC_FACE, SETTING_TITLE_BG_SESSION_ONLY, SETTING_TITLE_CONTENT_FALLBACK,
  SETTING_TITLE_IMMERSIVE_LEVEL, SETTING_TITLE_KEYBOARD_SEND,
  SETTING_TITLE_KEEP_SCREEN_ON, SETTING_TITLE_LAUNCH_ENTRY, SETTING_TITLE_MEMORY_AUTO,
  SETTING_TITLE_MEMORY_ENABLED, SETTING_TITLE_MEMORY_READ_MODE,
  SETTING_TITLE_PROACTIVE_DAILY_LIMIT, SETTING_TITLE_PROACTIVE_ENABLED,
  SETTING_TITLE_PROACTIVE_INTERVAL, SETTING_TITLE_PROACTIVE_QUIET_MAX,
  SETTING_TITLE_SEARCH_SERVICE,
  SETTING_TITLE_SESSION_ICON,
  SETTING_TITLE_SESSION_TIME,
  SETTING_TITLE_STREAM_ENGINE, SETTING_TITLE_STREAM_FOLLOW, SETTING_TITLE_TAB_SWITCH_ANIM,
  SETTING_TITLE_THINK_EXPAND } from '../SettingSearch';
// ── 设置写工具（2026-09-05 控制台助手第二笔；CherryStudio apply_setting 白名单注册表
//   同构——不在表内的 setting 一律硬拒绝且错误文案回显允许清单，加新键须显式改代码，
//   防提示注入翻转危险设置）──

// 白名单条目：中文显示名（= 界面真实标题，SETTING_TITLE_* 单源引用——模型从用户原话
// 直接取词零映射歧义）↔ AppStorage 持久键常量（import 自 AppPreferences/ImmersiveLevel，
// 禁裸字符串）+ kind（'toggle' 开关型传布尔 value / 'level' 档位型传刻度名 level——
// 2026-09-06 扩面引入两型，光感档位为数字档位键）+ 缺省值（defaultValue/defaultLevel 与
// EntryAbility persistProp 注册逐键一致——断言脚本对表）+ level 刻度名表（下标 = 档号，
// 引 ImmersiveLevel 刻度常量展开零复制，toggle 型空数组）+ 生效时机一句话（回执 hint 底料
// ——★各键消费方形态不一，现读型/订阅型混合，逐键对照 AppPreferences/ImmersiveLevel 注释
// 写就，禁一律写「即时生效」）+ valueNames（可选，toggle 取值含义——见接口注释；2026-09-06
// 生物识别卡改分段选择语义后引入）
export interface SetPrefWhitelistEntry {
  setting: string;
  key: string;
  kind: string;
  defaultValue: boolean;
  defaultLevel: number;
  levels: string[];
  hint: string;
  // toggle 型取值含义（可选——2026-09-06 生物识别卡改分段选择后引入）：[true 名, false 名]，
  // 有值时 desc 逐键附取值、缺 value 错误文案与成功回执 valueName 按名转述（UI 已是选择
  // 语义，「开启/关闭」措辞错位）；未写字段 = 通用开关措辞
  valueNames?: string[];
  // ★ 2026-09-13 档位值映射两字段（可选；kind 仍只有 toggle / level 两型——模型面契约零变化，
  // 模型依旧传刻度名）：
  // · levelValues：档位名 → **数字落库值**（在场时写 levelValues[档号]，缺省写档号本身——
  //   沉浸光感即无映射型）。主动消息三档位键落库小时/条数/分钟**值**而非档号，故须映射；
  // · choiceValues：档位名 → **字符串落库值**（记忆读取方式落库 'inject' / 'tool'）。
  // 两字段与 levels 等长（断言钉长度相等）；同一 entry 二者至多一者在场；均缺省 = 档号直落。
  levelValues?: number[];
  choiceValues?: string[];
}

// ★ 白名单改为**惰性构建**（2026-09-13 真机启动闪退修复笔）：原为模块级常量，条目里要读
// ProactiveGen / MemoryGen 的档位域数组与常量（levelValues、defaultLevel 的 indexOf 计算）——
// 而模块求值期这两模块可能尚在求值中（ToolTypes 聚合根 → 本文件 → … → 回指聚合根的环），
// 读到的是未初始化绑定（undefined），随后 .map() 即 TypeError = 启动 JsError 闪退。
// 改成首次调用时构建并缓存：调用点全在运行时（desc/schema 注册、读写执行器），彼时全图模块
// 求值已完成、值必就绪；且与源数组逐元素同源（断言 MAP_PAIRS 对表照旧，禁字面量双源）。
let whitelistCache: SetPrefWhitelistEntry[] | null = null;

// 白名单（恰二十二项：十七开关 + 五档位；顺序 = 开关在前档位在后——UI desc 允许清单同序）
export function setPrefWhitelist(): SetPrefWhitelistEntry[] {
  if (whitelistCache !== null) {
    return whitelistCache;
  }
  whitelistCache = [
  { setting: SETTING_TITLE_THINK_EXPAND, key: PREF_THINK_EXPAND_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '只影响之后新显示的思考内容，已显示的不变' },
  { setting: SETTING_TITLE_STREAM_ENGINE, key: PREF_STREAM_ENGINE_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '下一条消息发送时生效' },
  { setting: SETTING_TITLE_STREAM_FOLLOW, key: PREF_STREAM_FOLLOW_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '下一次输出时生效' },
  { setting: SETTING_TITLE_KEYBOARD_SEND, key: PREF_KEYBOARD_SEND_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '即时生效，输入框回车键形态随即切换' },
  { setting: SETTING_TITLE_KEEP_SCREEN_ON, key: PREF_KEEP_SCREEN_ON_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '下次进入会话页时生效' },
  { setting: SETTING_TITLE_SESSION_TIME, key: PREF_SESSION_TIME_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，会话列表卡片随即刷新' },
  { setting: SETTING_TITLE_SESSION_ICON, key: PREF_SESSION_ICON_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，会话列表卡片随即刷新' },
  // 2026-09-22 聊天自动重试笔（二十一 → 二十二键：十七开关 + 五档位，纯 toggle 零新机制）
  // ——hint 写「下一条消息发送时生效」而非即时生效：开关值在轮首现读一次、轮内锁定
  //（域件口径，防生成中途切换产生不确定行为）
  { setting: SETTING_TITLE_AUTO_RETRY, key: PREF_AUTO_RETRY_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '下一条消息发送时生效，正在生成的回复不受影响' },
  { setting: SETTING_TITLE_BIOMETRIC_FACE, key: PREF_BIOMETRIC_FACE_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    valueNames: ['人脸识别', '指纹识别'],
    hint: '下次加密会话认证时生效' },
  { setting: SETTING_TITLE_BG_SESSION_ONLY, key: PREF_BG_SESSION_ONLY_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '即时生效，页面背景随即按新范围显示' },
  { setting: SETTING_TITLE_CONTENT_FALLBACK, key: CONTENT_FALLBACK_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，界面按钮样式随即切换' },
  { setting: SETTING_TITLE_TAB_SWITCH_ANIM, key: PREF_TAB_SWITCH_ANIM_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，页签切换随即按开关状态播放或跳过动画' },
  { setting: SETTING_TITLE_LAUNCH_ENTRY, key: PREF_LAUNCH_NEW_CHAT_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    valueNames: ['新对话', '会话列表'],
    hint: '下次启动应用时生效' },
  // ── 2026-09-10 扩面：记忆域与联网搜索域三个总开关（决明「先做小的」——零新机制纯 toggle；
  //   排在档位项之前保持「开关在前档位在后」的既有分组；hint 逐键照各键真实消费点写，禁
  //   一律「即时生效」：记忆两键消费方 = MemoryGen 守卫（发送注入/退出沉淀现读）+ MemoryPage
  //   @StorageLink；联网总开关消费方 = ChatSendCtrl 发送前声明过滤 + ChipBar @StorageProp
  //   置灰 + dispatchSearch 执行兜底）──
  { setting: SETTING_TITLE_MEMORY_ENABLED, key: MEMORY_ENABLED_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，关闭后发送不再注入记忆，自动整理与手动整理同时停用' },
  { setting: SETTING_TITLE_MEMORY_AUTO, key: MEMORY_AUTO_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '下次退出会话时生效' },
  { setting: SETTING_TITLE_SEARCH_SERVICE, key: PREF_SEARCH_SERVICE_ENABLED_KEY, kind: 'toggle',
    defaultValue: true, defaultLevel: 0, levels: [],
    hint: '即时生效，关闭后不再联网，对话页的联网开关与助手的读取网页工具随即置灰' },
  // ── 2026-09-13 工具补齐三件扩面：主动消息四键 + 记忆读取方式（十五 → 二十键；toggles 在前
  //   档位在后的既有分组序保持）。★ 主动消息三档位键落库的是**值**（小时 / 条数 / 分钟——
  //   ProactiveGen.resolveXxx 按档位域数组白名单兜底），不是档号，故引 levelValues 映射；
  //   刻度名 = 值 + 单位（数字单源自 ProactiveGen 档位域数组，禁字面量双源）；默认档 =
  //   档位域数组里默认值的下标（indexOf 计算——档位域数组调整时自动跟随）。读取方式落库
  //   字符串（MemoryGen.MEMORY_READ_MODE_INJECT/TOOL），引 choiceValues 映射 ──
  { setting: SETTING_TITLE_PROACTIVE_ENABLED, key: PROACTIVE_ENABLED_KEY, kind: 'toggle',
    defaultValue: false, defaultLevel: 0, levels: [],
    hint: '即时生效，关闭后不再主动发消息' },
  { setting: SETTING_TITLE_PROACTIVE_INTERVAL, key: PROACTIVE_INTERVAL_HOURS_KEY, kind: 'level',
    defaultValue: false,
    defaultLevel: PROACTIVE_INTERVAL_OPTIONS.indexOf(PROACTIVE_INTERVAL_DEFAULT),
    levels: PROACTIVE_INTERVAL_OPTIONS.map((hours: number): string => hours + ' 小时'),
    levelValues: PROACTIVE_INTERVAL_OPTIONS,
    hint: '下次排程时生效' },
  { setting: SETTING_TITLE_PROACTIVE_DAILY_LIMIT, key: PROACTIVE_DAILY_LIMIT_KEY, kind: 'level',
    defaultValue: false,
    defaultLevel: PROACTIVE_DAILY_LIMIT_OPTIONS.indexOf(PROACTIVE_DAILY_LIMIT_DEFAULT),
    levels: PROACTIVE_DAILY_LIMIT_OPTIONS.map((count: number): string => count + ' 条'),
    levelValues: PROACTIVE_DAILY_LIMIT_OPTIONS,
    hint: '即时生效，按本地自然日计数' },
  { setting: SETTING_TITLE_PROACTIVE_QUIET_MAX, key: PROACTIVE_QUIET_MAX_KEY, kind: 'level',
    defaultValue: false,
    defaultLevel: PROACTIVE_QUIET_MAX_OPTIONS.indexOf(PROACTIVE_QUIET_MAX_DEFAULT),
    levels: PROACTIVE_QUIET_MAX_OPTIONS.map((minutes: number): string => minutes + ' 分钟'),
    levelValues: PROACTIVE_QUIET_MAX_OPTIONS,
    hint: '下次回前台时生效' },
  { setting: SETTING_TITLE_MEMORY_READ_MODE, key: MEMORY_READ_MODE_KEY, kind: 'level',
    defaultValue: false,
    // 默认档 = 数组首项（自动注入）——首项即 MemoryGen.MEMORY_READ_MODE_DEFAULT，顺序契约
    // 同 MemoryPage 分段卡（下标 0 = 自动注入 / 1 = 按需读取）
    defaultLevel: [MEMORY_READ_MODE_INJECT, MEMORY_READ_MODE_TOOL].indexOf(MEMORY_READ_MODE_DEFAULT),
    levels: ['自动注入', '按需读取'],
    choiceValues: [MEMORY_READ_MODE_INJECT, MEMORY_READ_MODE_TOOL],
    hint: '即时生效，切到按需后发送不再注入记忆，需要模型支持工具调用' },
  { setting: SETTING_TITLE_IMMERSIVE_LEVEL, key: IMMERSIVE_LEVEL_KEY, kind: 'level',
    defaultValue: false, defaultLevel: 0, levels: IMMERSIVE_LEVEL_SHORT_NAMES.slice(),
    hint: '即时生效，全应用材质光感随即切换' }
  ];
  return whitelistCache;
}

// 参数校验结果（纯函数可断言）：ok = true 时其余字段有效；false 时 error 为回显允许清单
// 的中文文案（模型可感知自纠）。level 型：level = 刻度名在 levels 表中的下标（档号）、
// levelName = 原刻度名；toggle 型 level 恒 -1、levelName 恒 ''。★ 2026-09-13 起同步带出
// levelValues / choiceValues 两映射字段（白名单条目原样带出，未写字段 = 空数组）——写执行器
// 据此换算落库值、读侧据此反查刻度名
export interface SetPrefValidation {
  ok: boolean;
  setting: string;
  key: string;
  kind: string;
  defaultValue: boolean;
  defaultLevel: number;
  levels: string[];
  hint: string;
  // 白名单条目 valueNames 带出（toggle 取值语义；未写字段 = 空数组）——回执 valueName 底料
  valueNames: string[];
  levelValues: number[];
  choiceValues: string[];
  value: boolean;
  level: number;
  levelName: string;
  error: string;
}

function rejectSetPref(error: string): SetPrefValidation {
  return { ok: false, setting: '', key: '', kind: '', defaultValue: false, defaultLevel: 0,
    levels: [], hint: '', valueNames: [], levelValues: [], choiceValues: [], value: false,
    level: -1, levelName: '', error: error };
}

// 参数校验纯函数（searchHelpTopics 同款自包含姿势——断言脚本剥 TS 求值直跑）：坏 JSON /
// 缺参 / 白名单外 / 类型错全拒；kind 分支——toggle 型必须传布尔 value（传 level 拒，防
// 模型两参混传）；level 型必须传该键刻度表内的 level 刻度名（传 value 拒；档名不在表内
// 拒且回显合法档名）。白名单外文案回显允许清单（Cherry 教训——防注入翻转，同时供模型换
// 正确设置名重试）
export function validateSetPrefArgs(argsJson: string): SetPrefValidation {
  let setting: string = '';
  let hasValue: boolean = false; // value 键在场（不论类型）
  let valueIsBool: boolean = false; // 在场且为布尔
  let value: boolean = false;
  let hasLevel: boolean = false; // level 键在场（不论类型）
  let levelName: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawSetting: Object | undefined = parsed['setting'];
    const rawValue: Object | undefined = parsed['value'];
    const rawLevel: Object | undefined = parsed['level'];
    if (typeof rawSetting === 'string') {
      setting = rawSetting.trim();
    }
    if (rawValue !== undefined) {
      hasValue = true;
      if (typeof rawValue === 'boolean') {
        valueIsBool = true;
        value = rawValue;
      }
    }
    if (rawLevel !== undefined) {
      hasLevel = true;
      if (typeof rawLevel === 'string') {
        levelName = rawLevel.trim();
      }
    }
  } catch (e) {
    return rejectSetPref('参数解析失败，开关项需要 setting 与 value，档位项需要 setting 与 level');
  }
  if (setting === '') {
    return rejectSetPref('缺少 setting 参数，值为要修改的设置项名称');
  }
  for (const entry of setPrefWhitelist()) {
    if (entry.setting !== setting) {
      continue;
    }
    if (entry.kind === 'level') {
      if (!hasLevel) {
        return rejectSetPref('档位项「' + setting + '」需要 level 参数，取值：' +
          entry.levels.join('、'));
      }
      if (hasValue) {
        return rejectSetPref('档位项「' + setting + '」用 level 传刻度名，不用 value 布尔');
      }
      const idx: number = entry.levels.indexOf(levelName);
      if (idx < 0) {
        return rejectSetPref('「' + setting + '」的档位必须是：' + entry.levels.join('、'));
      }
      return { ok: true, setting: entry.setting, key: entry.key, kind: entry.kind,
        defaultValue: entry.defaultValue, defaultLevel: entry.defaultLevel,
        levels: entry.levels, hint: entry.hint, valueNames: [],
        levelValues: entry.levelValues !== undefined ? entry.levelValues : [],
        choiceValues: entry.choiceValues !== undefined ? entry.choiceValues : [],
        value: false, level: idx, levelName: levelName, error: '' };
    }
    // toggle 型
    if (!hasValue) {
      // 取值含义文案（valueNames 有值 = 选择语义条目——生物识别卡改分段后「开启/关闭」错位）
      const names: string = entry.valueNames !== undefined && entry.valueNames.length === 2
        ? '传 true 选' + entry.valueNames[0] + '，false 选' + entry.valueNames[1]
        : '传 true 开启或 false 关闭';
      return rejectSetPref('开关项「' + setting + '」需要 value 参数，' + names);
    }
    if (!valueIsBool) {
      return rejectSetPref('value 参数必须是 true 或 false');
    }
    if (hasLevel) {
      return rejectSetPref('开关项「' + setting + '」用 value 传布尔，不用 level 档位');
    }
    return { ok: true, setting: entry.setting, key: entry.key, kind: entry.kind,
      defaultValue: entry.defaultValue, defaultLevel: entry.defaultLevel,
      levels: entry.levels, hint: entry.hint,
      valueNames: entry.valueNames !== undefined ? entry.valueNames : [],
      levelValues: [], choiceValues: [],
      value: value, level: -1, levelName: '', error: '' };
  }
  const names: string = setPrefWhitelist()
    .map((e: SetPrefWhitelistEntry): string => e.setting).join('、');
  return rejectSetPref('不支持的设置项：' + setting + '。可修改的设置：' + names);
}

// 参数 schema（setting 枚举自白名单生成——双源防护：schema 层与执行层同源，白名单外传值
// 在模型侧即被约束；执行层 validateSetPrefArgs 二次校验双闸——业界共识模型可能幻觉传值）。
// level 枚举 = 两刻度表并集（JSON Schema 无法按 setting 值条件约束——逐键合法档名由 desc
// 与执行层校验兜底，schema 层并集已滤掉明显的幻觉词）
export function buildSetPrefSchema(): string {
  const names: string = setPrefWhitelist()
    .map((e: SetPrefWhitelistEntry): string => '"' + e.setting + '"').join(',');
  const allLevels: string[] = [];
  for (const entry of setPrefWhitelist()) {
    for (const lv of entry.levels) {
      if (!allLevels.includes(lv)) {
        allLevels.push(lv);
      }
    }
  }
  const levelEnum: string = allLevels
    .map((lv: string): string => '"' + lv + '"').join(',');
  return '{"type":"object","properties":{"setting":{"type":"string","description":"要修改的' +
    '设置项，必须从枚举中选取","enum":[' + names + ']},"value":{"type":"boolean",' +
    '"description":"开关项的目标状态，true 开启 false 关闭。仅开关项传此参数"},' +
    '"level":{"type":"string","description":"档位项的目标档位刻度名。仅档位项传此参数"' +
    ',"enum":[' + levelEnum + ']}},"required":["setting"]}';
}

// 工具 desc 动态拼接（Cherry hint 同款——白名单清单挂进 desc，模型从 desc 即知全部可写项
// 与语义约束，无需另查；加键 desc 自动跟随零双源）。开关项与档位项分组列出，档位项附合法
// 刻度名（schema 枚举是并集，逐键取值域在此给全）
export function buildSetPrefDesc(): string {
  const toggles: string[] = [];
  const levels: string[] = [];
  for (const entry of setPrefWhitelist()) {
    if (entry.kind === 'level') {
      levels.push(entry.setting + '（' + entry.levels.join('/') + '）');
    } else if (entry.valueNames !== undefined && entry.valueNames.length === 2) {
      // 选择语义条目（UI 为分段点选非开关）——desc 逐键附取值含义，防模型按「开启/关闭」
      // 理解与转述
      toggles.push(entry.setting + '（true=' + entry.valueNames[0] + '/false=' +
        entry.valueNames[1] + '）');
    } else {
      toggles.push(entry.setting);
    }
  }
  return '修改本应用的偏好设置。开关项传 value，true 开启 false 关闭：' + toggles.join('、') +
    '。档位项传 level 刻度名：' + levels.join('、') +
    '。仅在用户明确要求修改某项设置时调用，不要猜测或主动建议修改。' +
    '一次只改用户点名的设置项。';
}

// 设置修改执行器（方案 A 直改 + 回执）：白名单校验（纯函数）→ 写前读旧值 → AppStorage.set
// 直写即持久化（各键 persistProp 均已在 EntryAbility 注册——禁重复 persistProp 禁新广播键，
// 坑16/17；UI 刷新交各键既有消费链）→ 回执 {ok, setting, oldValue, newValue, hint}（level
// 型附 levelName 刻度名）供模型如实转述改了什么与何时生效；写入失败不静默（set 返 false
// 理论不可达——persistProp 保证键在场，防御兜底）。
// ★ 2026-09-13 档位值映射：level 型落库值三态——choiceValues 在场写字符串（记忆读取方式）、
// levelValues 在场写数字落库值（主动消息三档位）、均不在场写档号（沉浸光感现状）。回执
// oldValue / newValue 一律为**落库值**，levelName 为刻度名；旧值缺省回退按映射折算（读侧
// 的类型泛型必须与落库类型一致——写字符串却按 get<number> 读会把旧值读成缺省）
export class SetAppPreferenceExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: SetPrefValidation = validateSetPrefArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    if (v.kind === 'level') {
      if (v.choiceValues.length > 0) {
        const fallbackText: string = v.choiceValues[v.defaultLevel];
        const oldText: string = AppStorage.get<string>(v.key) ?? fallbackText;
        const newText: string = v.choiceValues[v.level];
        const writtenText: boolean = AppStorage.set<string>(v.key, newText);
        if (!writtenText) {
          return Promise.resolve(JSON.stringify({ error: '设置写入失败，设置未变更' }));
        }
        return Promise.resolve(JSON.stringify({ ok: true, setting: v.setting,
          oldValue: oldText, newValue: newText, levelName: v.levelName, hint: v.hint }));
      }
      const mapped: boolean = v.levelValues.length > 0;
      const oldLevel: number = AppStorage.get<number>(v.key) ??
        (mapped ? v.levelValues[v.defaultLevel] : v.defaultLevel);
      const newLevel: number = mapped ? v.levelValues[v.level] : v.level;
      const written: boolean = AppStorage.set<number>(v.key, newLevel);
      if (!written) {
        return Promise.resolve(JSON.stringify({ error: '设置写入失败，设置未变更' }));
      }
      return Promise.resolve(JSON.stringify({ ok: true, setting: v.setting,
        oldValue: oldLevel, newValue: newLevel, levelName: v.levelName, hint: v.hint }));
    }
    const oldValue: boolean = AppStorage.get<boolean>(v.key) ?? v.defaultValue;
    const written: boolean = AppStorage.set<boolean>(v.key, v.value);
    if (!written) {
      return Promise.resolve(JSON.stringify({ error: '设置写入失败，设置未变更' }));
    }
    // 回执附 valueName（valueNames 有值 = 选择语义条目——模型如实转述「已改为人脸识别」
    // 而非「已开启」；无 = 空串，模型按通用开关措辞转述）
    const valueName: string = v.valueNames.length === 2
      ? (v.value ? v.valueNames[0] : v.valueNames[1]) : '';
    return Promise.resolve(JSON.stringify({ ok: true, setting: v.setting,
      oldValue: oldValue, newValue: v.value, valueName: valueName, hint: v.hint }));
  }
}

// ── 设置查询执行器（2026-09-06 设置读工具；与写工具同一 setPrefWhitelist() 单源）──

// 查询结果条目（kind 两型字段选择性在场：toggle 型 value 必在，valueNames 条目另附
// valueName；level 型仅 levelName——JSON.stringify 丢弃 undefined 键，载荷零冗余字段）
interface GetPrefItem {
  setting: string;
  kind: string;
  value?: boolean;
  valueName?: string;
  levelName?: string;
}

// 查询工具顶层载荷
interface GetPrefPayload {
  settings: GetPrefItem[];
}

// 查询工具 desc（白名单清单不进 desc——全量返回值自解释，模型调用后即得全部项名与当前
// 值，desc 拼清单徒增每请求 token；desc 只立调用纪律：状态类问题先查实不猜测，范围口径
// 与写工具一致由尾句点明）
export function buildGetPrefDesc(): string {
  return '查询本应用偏好设置与光感档位的当前状态，返回全部可查询设置项的实时值，开关项含' +
    '当前布尔值，选择项含当前所选名称，档位项含当前刻度名。用户询问某项设置是否开启、当前' +
    '选的是什么、光感在哪一档时调用；回答设置状态前先调用本工具查实，不要凭记忆或猜测回答。' +
    '查询范围与修改应用设置工具一致。';
}

// 档位名反查（读侧单源；导出便于断言直跑）：落库值 → 刻度名。三态——命中映射回刻度名；
// 未命中（脏值 / 版本回滚遗留值）回 String(落库值)；键未配置回缺省档刻度名。★ 类型泛型必须
// 与落库类型一致（2026-09-13 自检轮实查的真缺陷面）：choiceValues 型落库是字符串
//（记忆读取方式），levelValues 型落库是数字（主动消息三档位），无映射型落库是档号（光感）——
// 一律按 get<number> 读会把 'tool' 读成缺省（静默错值），故按在场类型分支取值
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
// 面）；值缺省回退与 persistProp 注册值一致（?? defaultValue/defaultLevel——正常路径注册
// 先于任何读取，回退仅防御）；level 型反查走 resolveLevelName 单源（三型映射分支）。
// 全量约 1KB 远低于 clipToolResult 截断线；无参工具 schema 空 object（GetTimeInfoExecutor 同款）
export class GetAppPreferenceExecutor implements ToolExecutor {
  execute(_argsJson: string): Promise<string> {
    const items: GetPrefItem[] = [];
    for (const entry of setPrefWhitelist()) {
      if (entry.kind === 'level') {
        const lvItem: GetPrefItem = { setting: entry.setting, kind: entry.kind,
          levelName: resolveLevelName(entry) };
        items.push(lvItem);
        continue;
      }
      const value: boolean = AppStorage.get<boolean>(entry.key) ?? entry.defaultValue;
      const item: GetPrefItem = { setting: entry.setting, kind: entry.kind, value: value };
      if (entry.valueNames !== undefined && entry.valueNames.length === 2) {
        item.valueName = value ? entry.valueNames[0] : entry.valueNames[1];
      }
      items.push(item);
    }
    const payload: GetPrefPayload = { settings: items };
    return Promise.resolve(JSON.stringify(payload));
  }
}
