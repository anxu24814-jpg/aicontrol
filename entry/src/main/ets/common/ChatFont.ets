/**
 * 消息字体域单源：偏好键 + 值域 + 字体库解析/序列化 + 纯解析（家族串推导 / 选项行构造 /
 * 别名派生 / v1 迁移）+ AppStorage 现读封装。
 * 零 import 叶子件（照 AppPreferences / ScriptLimits 范式）——node 侧断言 copyFileSync 直跑
 * 纯函数；字体注册的平台依赖面在同域 ChatFontLoader.ets（职责缝 = 本件「说什么字体」/
 * loader「怎么把字体装进系统」）。
 * 消费方：ChatFontSection（字体段读写 + 导入/删除流）、ChatFontLoader（启动/切换按需注册 +
 * 应用级 setFont 下发）、消息域 V1 宿主（@StorageProp 自订阅后经 @Param 下发 V2 叶件）——
 * 家族串一律经本件纯函数推导，禁在消费方拼串；思考段标题、工具卡、代码块标题、推荐语也
 * 消费正文档（逐件显式下发）。字体范围开关 PREF_FONT_SESSION_ONLY_KEY 细则见该键注释。
 * 数据模型：prefFontBody = 'default|serif|fangsong|monospace|custom:<id>'；prefFontCode =
 * 'default|jetbrains|custom:<id>'；prefFontLib = JSON 数组串 [{"id","name","path"}]（id =
 * 沙箱文件名，唯一且跨重启稳定；name 重名或撞内置档行标签时由 uniqueLibName 加序号）——
 * 正文与代码两域共享一库，导入一次两边列表都可选；删除在字体段管理卡（先复位选中再删文件）。
 * 家族串用「别名, 回退族」逗号链（官方 fontFamily 多字体回退语义）——注册未完成或文件缺失
 * 时逐级回落；「等宽」正文档与代码默认走系统通用族名 'monospace'（官方无文档承诺，真机
 * 探针项——不生效则回落默认字体）。
 * 迁移（v1 遗留）：旧四键（Body/Code × Path/Name）由 EntryAbility 启动链一次性并入本库
 *（migrateLegacyFontSelectionNow，幂等）——旧四键为过渡只读键，下版本删除。
 */

// ── 偏好键（正文 / 代码选择 + 共享字体库）──
// 注册位置 = EntryAbility loadContent 回调 persistProp 区（坑17 口径，全部既有键之后、
// PREF_LOADED_KEY 置 1 之前）；消费方一律引用本文件常量，禁裸字符串。
export const PREF_FONT_BODY_KEY: string = 'prefFontBody';
export const PREF_FONT_CODE_KEY: string = 'prefFontCode';
export const PREF_FONT_LIB_KEY: string = 'prefFontLib';

// ── 字体范围开关 ──
// true（默认）= 字体只在会话页生效（显式链形态，零回归）；false = 正文档经
// ApplicationContext.setFont 下发应用级槽位（官方 API 12+，单族名——缺字回退由系统兜底；
// 显式 fontFamily 优先于应用级槽位，会话页显式链不受影响），应用内未显式指定的文字（设置页、
// 会话列表、助手头像、会话徽章等）跟随正文选择。代码字体不在开关范围（setFont 单槽位被正文
// 档占用），恒只在会话页生效。消费方 = ChatFontLoader.applyAppFontOnLaunch（启动下发）+
// ChatFontSection（开关读写 + 切档/删除复位全局态重发）。注册位置同上（字体三键之后、
// PREF_LOADED 置 1 之前）；随偏好备份走（BACKUP_PREF_KEYS 通用偏好段）
export const PREF_FONT_SESSION_ONLY_KEY: string = 'prefFontSessionOnly';

// v1 退役四键（迁移过渡期只读：迁移函数读值并入字体库后清空；下版本删除 persistProp 与常量）
export const PREF_FONT_BODY_PATH_KEY: string = 'prefFontBodyPath';
export const PREF_FONT_BODY_NAME_KEY: string = 'prefFontBodyName';
export const PREF_FONT_CODE_PATH_KEY: string = 'prefFontCodePath';
export const PREF_FONT_CODE_NAME_KEY: string = 'prefFontCodeName';

// ── 选择值域（正文四内置档 + 代码两内置档 + 'custom:<id>' 自定义档）──
export const FONT_BODY_DEFAULT: string = 'default';
export const FONT_BODY_SERIF: string = 'serif';
export const FONT_BODY_FANGSONG: string = 'fangsong';
export const FONT_BODY_MONO: string = 'monospace';
export const FONT_CODE_DEFAULT: string = 'default';
export const FONT_CODE_JETBRAINS: string = 'jetbrains';
// 自定义档值前缀（v1 裸 'custom' 值由迁移转换；现行值域不含裸值）
export const FONT_CUSTOM_PREFIX: string = 'custom:';
// v1 裸自定义值字面量（仅迁移识别消费）
export const FONT_LEGACY_CUSTOM: string = 'custom';

// ── 系统族名（默认字体 = 官方 'HarmonyOS Sans'；等宽 = 通用族名）──
export const FONT_FAMILY_SYSTEM: string = 'HarmonyOS Sans';
export const FONT_FAMILY_MONO: string = 'monospace';

// ── 内置字体注册别名与 rawfile 路径（单源；别名唯一是官方硬约束——重名再注册会静默失败）──
// 三款 OFL 1.1 字体原样内嵌分发（未修改 + 随附许可文本，OFL 允许闭源 App 内嵌）：
// 衬线 = Noto Serif SC、仿宋 = 朱雀仿宋、等宽 = JetBrains Mono
export const FONT_ALIAS_SERIF: string = 'AiControlNotoSerifSC';
export const FONT_ALIAS_FANGSONG: string = 'AiControlZhuqueFangsong';
export const FONT_ALIAS_JETBRAINS: string = 'AiControlJetBrainsMono';
export const FONT_RAWFILE_SERIF: string = 'fonts/NotoSerifSC-Regular.otf';
export const FONT_RAWFILE_FANGSONG: string = 'fonts/ZhuqueFangsong-Regular.ttf';
export const FONT_RAWFILE_JETBRAINS: string = 'fonts/JetBrainsMono-Regular.ttf';

// ── 自定义字体：沙箱目录（filesDir 下）、落盘文件名前缀与注册别名前缀 ──
// 落盘文件名 = 前缀 + 毫秒时间戳（chatfont_<ts>.ttf|otf|ttc），库项 id 即文件名（唯一且跨
// 重启稳定）；别名从 id 文件名主干派生
export const FONT_CUSTOM_DIR: string = 'fonts';
export const FONT_CUSTOM_FILE_PREFIX: string = 'chatfont_';
export const FONT_CUSTOM_ALIAS_PREFIX: string = 'acfont_';
// 字体库上限（无界增长防线：导入接口按库长收口，超出提示先删）
export const FONT_LIB_MAX: number = 20;

// ── 字体库项（共享库基本单元；JSON 单键持久化）──
export interface FontLibEntry {
  id: string;   // 沙箱文件名（chatfont_<ts>.<ext>）
  name: string; // 显示名（源文件名去扩展；重名时由 uniqueLibName 加序号）
  path: string; // 沙箱绝对路径
}

// ── 字体选项行（选择组卡行数据单源；行序 = 内置档 + 库序）──
export interface FontOptionRow {
  id: string;    // 行值（直接写 prefFontBody / prefFontCode）
  label: string; // 行标题
}

// ── 字体库解析 / 序列化（纯函数，断言直跑）──
// 脏值容错（非数组 / 字段缺失 / 坏 JSON 一律回空表——照 AppPreferences 坏 JSON 口径）
export function parseFontLib(json: string): FontLibEntry[] {
  const list: FontLibEntry[] = [];
  if (json === '') {
    return list;
  }
  try {
    const raw: Object = JSON.parse(json) as Object;
    if (!Array.isArray(raw)) {
      return list;
    }
    for (const item of raw as Object[]) {
      const entry: FontLibEntry = item as FontLibEntry;
      if (typeof entry.id === 'string' && typeof entry.name === 'string' &&
        typeof entry.path === 'string' && entry.id !== '' && entry.path !== '') {
        list.push({ id: entry.id, name: entry.name, path: entry.path });
      }
    }
  } catch (error) {
    return list;
  }
  return list;
}

export function serializeFontLib(entries: FontLibEntry[]): string {
  return JSON.stringify(entries);
}

export function entryById(entries: FontLibEntry[], id: string): FontLibEntry | null {
  for (const entry of entries) {
    if (entry.id === id) {
      return entry;
    }
  }
  return null;
}

// 导入入库显示名：同库重名自动加序号（'名 2' / '名 3'…）；★ 内置档行标签视同重名一并避让
//（两域并集）——选择组卡行是 ForEach（键 = label），显示名撞内置标签会让两行同键：官方口径
//「重复键值框架可能无法正常工作，只创建首件」→ 自定义行静默不显示、无法点选
export function uniqueLibName(base: string, entries: FontLibEntry[]): string {
  const safe: string = base !== '' ? base : '自定义字体';
  let candidate: string = safe;
  let n: number = 2;
  while (isLibNameTaken(entries, candidate)) {
    candidate = safe + ' ' + n.toString();
    n++;
  }
  return candidate;
}

function isLibNameTaken(entries: FontLibEntry[], name: string): boolean {
  if (BUILTIN_LABELS.indexOf(name) >= 0) {
    return true;
  }
  for (const entry of entries) {
    if (entry.name === name) {
      return true;
    }
  }
  return false;
}

// ── 路径 / 文件名工具（纯函数）──
export function fileNameOf(path: string): string {
  if (path === '') {
    return '';
  }
  const slash: number = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return slash >= 0 ? path.substring(slash + 1) : path;
}

// 显示名 = 去扩展主干（'chatfont_1.ttf' → 'chatfont_1'；无扩展原样）
export function displayNameOfFileName(fileName: string): string {
  if (fileName === '') {
    return '';
  }
  const dot: number = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

// ── 自定义值解析（纯函数）──
// 'custom:<id>' → id；非前缀 / 空 id 回空串
export function customIdOf(value: string): string {
  if (!value.startsWith(FONT_CUSTOM_PREFIX)) {
    return '';
  }
  return value.substring(FONT_CUSTOM_PREFIX.length);
}

// 值是否为「库内有效的自定义档」（前缀 + id 在库）
export function isCustomValue(value: string, libJson: string): boolean {
  const id: string = customIdOf(value);
  if (id === '') {
    return false;
  }
  return entryById(parseFontLib(libJson), id) !== null;
}

// 自定义注册别名派生（前缀 + 文件主干；空 id 回空串）
export function customAliasForId(id: string): string {
  const stem: string = displayNameOfFileName(id);
  return stem === '' ? '' : FONT_CUSTOM_ALIAS_PREFIX + stem;
}

// ── 值域归一（纯函数，断言直跑）：脏值 / 指向已删字体的自定义值一律回默认档 ──
export function resolveBodyFontId(raw: string, libJson: string): string {
  if (raw === FONT_BODY_SERIF || raw === FONT_BODY_FANGSONG || raw === FONT_BODY_MONO) {
    return raw;
  }
  return isCustomValue(raw, libJson) ? raw : FONT_BODY_DEFAULT;
}

export function resolveCodeFontId(raw: string, libJson: string): string {
  if (raw === FONT_CODE_JETBRAINS) {
    return raw;
  }
  return isCustomValue(raw, libJson) ? raw : FONT_CODE_DEFAULT;
}

// ── 家族串推导（纯函数，断言直跑）：返回直接可喂 fontFamily 的串 ──
export function bodyFontFamily(value: string, libJson: string): string {
  const resolved: string = resolveBodyFontId(value, libJson);
  if (resolved === FONT_BODY_SERIF) {
    return FONT_ALIAS_SERIF + ', ' + FONT_FAMILY_SYSTEM;
  }
  if (resolved === FONT_BODY_FANGSONG) {
    return FONT_ALIAS_FANGSONG + ', ' + FONT_FAMILY_SYSTEM;
  }
  if (resolved === FONT_BODY_MONO) {
    return FONT_FAMILY_MONO + ', ' + FONT_FAMILY_SYSTEM;
  }
  const alias: string = customAliasForId(customIdOf(resolved));
  if (alias !== '') {
    return alias + ', ' + FONT_FAMILY_SYSTEM;
  }
  return FONT_FAMILY_SYSTEM;
}

// ── setFont 主族名推导：应用级单族名槽位用——官方 setFont(font) 只吃一个族名，缺字回退由
// 系统兜底，与 fontFamily 逗号回退链是两套机制。默认 = 系统默认族名；等宽 = 通用族名
// monospace；衬线/仿宋/自定义 = 注册别名（应用级下发前 ChatFontLoader 已确保选中档注册）
export function bodyFontPrimaryFamily(value: string, libJson: string): string {
  const resolved: string = resolveBodyFontId(value, libJson);
  if (resolved === FONT_BODY_SERIF) {
    return FONT_ALIAS_SERIF;
  }
  if (resolved === FONT_BODY_FANGSONG) {
    return FONT_ALIAS_FANGSONG;
  }
  if (resolved === FONT_BODY_MONO) {
    return FONT_FAMILY_MONO;
  }
  const alias: string = customAliasForId(customIdOf(resolved));
  if (alias !== '') {
    return alias;
  }
  return FONT_FAMILY_SYSTEM;
}

export function codeFontFamily(value: string, libJson: string): string {
  const resolved: string = resolveCodeFontId(value, libJson);
  if (resolved === FONT_CODE_JETBRAINS) {
    return FONT_ALIAS_JETBRAINS + ', ' + FONT_FAMILY_MONO;
  }
  const alias: string = customAliasForId(customIdOf(resolved));
  if (alias !== '') {
    return alias + ', ' + FONT_FAMILY_MONO;
  }
  // 默认 = 逐字现状（代码链一直用通用族名 'monospace'），零回归
  return FONT_FAMILY_MONO;
}

// ── 注册需求描述（loader 消费；null = 该目标无需注册）──
export interface FontRegisterRequest {
  alias: string;
  source: string; // rawfile 相对路径（rawfile=true）或沙箱绝对路径
  rawfile: boolean;
}

// 内置档注册需求映射（纯函数）：正文 serif/fangsong、代码 jetbrains 各对应一款内置字体
export function builtinFontRequest(id: string): FontRegisterRequest | null {
  if (id === FONT_BODY_SERIF) {
    return { alias: FONT_ALIAS_SERIF, source: FONT_RAWFILE_SERIF, rawfile: true };
  }
  if (id === FONT_BODY_FANGSONG) {
    return { alias: FONT_ALIAS_FANGSONG, source: FONT_RAWFILE_FANGSONG, rawfile: true };
  }
  if (id === FONT_CODE_JETBRAINS) {
    return { alias: FONT_ALIAS_JETBRAINS, source: FONT_RAWFILE_JETBRAINS, rawfile: true };
  }
  return null;
}

// ── 选项行构造（选择组卡单源；行数随库长变——内置档 + 已导入字体）──
// 内置档行标签（两域全部；避让集单源 = 本组常量——uniqueLibName 与行构造同引，改标签只改
// 此处；两域默认档同字面 '默认'，并集去重后仍是同一避让名，无碍）
const LABEL_FONT_DEFAULT: string = '默认';
const LABEL_FONT_SERIF: string = '衬线';
const LABEL_FONT_FANGSONG: string = '仿宋';
const LABEL_FONT_MONO: string = '等宽';
const LABEL_FONT_JETBRAINS: string = 'JetBrains Mono';
const BUILTIN_LABELS: string[] = [LABEL_FONT_DEFAULT, LABEL_FONT_SERIF, LABEL_FONT_FANGSONG,
  LABEL_FONT_MONO, LABEL_FONT_JETBRAINS];

export function bodyFontRows(libJson: string): FontOptionRow[] {
  const rows: FontOptionRow[] = [
    { id: FONT_BODY_DEFAULT, label: LABEL_FONT_DEFAULT },
    { id: FONT_BODY_SERIF, label: LABEL_FONT_SERIF },
    { id: FONT_BODY_FANGSONG, label: LABEL_FONT_FANGSONG },
    { id: FONT_BODY_MONO, label: LABEL_FONT_MONO }
  ];
  appendCustomRows(rows, libJson);
  return rows;
}

export function codeFontRows(libJson: string): FontOptionRow[] {
  const rows: FontOptionRow[] = [
    { id: FONT_CODE_DEFAULT, label: LABEL_FONT_DEFAULT },
    { id: FONT_CODE_JETBRAINS, label: LABEL_FONT_JETBRAINS }
  ];
  appendCustomRows(rows, libJson);
  return rows;
}

function appendCustomRows(rows: FontOptionRow[], libJson: string): void {
  for (const entry of parseFontLib(libJson)) {
    rows.push({ id: FONT_CUSTOM_PREFIX + entry.id, label: entry.name });
  }
}

// ── v1 迁移（纯函数 + 启动封装；旧四键并入字体库、裸 'custom' 值补 id）──
export interface FontMigrationResult {
  libJson: string;
  bodyValue: string;
  codeValue: string;
}

export function migrateLegacyFontSelection(legacyBodyPath: string, legacyBodyName: string,
  bodyValue: string, legacyCodePath: string, legacyCodeName: string, codeValue: string,
  libJson: string): FontMigrationResult {
  const entries: FontLibEntry[] = parseFontLib(libJson);
  let changed: boolean = false;
  let bodyOut: string = bodyValue;
  let codeOut: string = codeValue;
  if (legacyBodyPath !== '') {
    const id: string = fileNameOf(legacyBodyPath);
    if (id !== '' && entryById(entries, id) === null) {
      // 入库名一律过 uniqueLibName（撞内置标签加序号——防选择组卡两行同键）
      entries.push({ id: id, name: uniqueLibName(legacyNameOf(legacyBodyName, id), entries),
        path: legacyBodyPath });
      changed = true;
    }
    if (bodyOut === FONT_LEGACY_CUSTOM && id !== '') {
      bodyOut = FONT_CUSTOM_PREFIX + id;
    }
  }
  if (legacyCodePath !== '') {
    const id: string = fileNameOf(legacyCodePath);
    if (id !== '' && entryById(entries, id) === null) {
      entries.push({ id: id, name: uniqueLibName(legacyNameOf(legacyCodeName, id), entries),
        path: legacyCodePath });
      changed = true;
    }
    if (codeOut === FONT_LEGACY_CUSTOM && id !== '') {
      codeOut = FONT_CUSTOM_PREFIX + id;
    }
  }
  return {
    libJson: changed ? serializeFontLib(entries) : libJson,
    bodyValue: bodyOut,
    codeValue: codeOut
  };
}

// 旧显示名（v1 存源文件名含扩展——去扩展；缺省从 id 主干兜底）
function legacyNameOf(legacyName: string, id: string): string {
  const fromKey: string = displayNameOfFileName(legacyName);
  if (fromKey !== '') {
    return fromKey;
  }
  return displayNameOfFileName(id);
}

// ── AppStorage 读值封装（非响应式现读面：loader 与迁移消费；响应式消费走 @StorageProp/@StorageLink）──
export function fontLibNow(): string {
  return AppStorage.get<string>(PREF_FONT_LIB_KEY) ?? '';
}

export function bodyFontValueNow(): string {
  return resolveBodyFontId(AppStorage.get<string>(PREF_FONT_BODY_KEY) ?? '', fontLibNow());
}

export function codeFontValueNow(): string {
  return resolveCodeFontId(AppStorage.get<string>(PREF_FONT_CODE_KEY) ?? '', fontLibNow());
}

export function bodyFontFamilyNow(): string {
  return bodyFontFamily(AppStorage.get<string>(PREF_FONT_BODY_KEY) ?? '', fontLibNow());
}

export function codeFontFamilyNow(): string {
  return codeFontFamily(AppStorage.get<string>(PREF_FONT_CODE_KEY) ?? '', fontLibNow());
}

// 范围开关现读：?? true = 键未注册时按现状（仅会话页）兜底，与 persistProp 缺省值一致
export function fontSessionOnlyNow(): boolean {
  return AppStorage.get<boolean>(PREF_FONT_SESSION_ONLY_KEY) ?? true;
}

// 当前正文选择的主族名（应用级 setFont 下发消费）
export function bodyFontPrimaryFamilyNow(): string {
  return bodyFontPrimaryFamily(AppStorage.get<string>(PREF_FONT_BODY_KEY) ?? '', fontLibNow());
}

// 当前正文 / 代码选择对应的注册需求（loader 启动注册与切换注册消费）
export function bodyRegisterRequestNow(): FontRegisterRequest | null {
  return registerRequestOfValue(bodyFontValueNow(), fontLibNow());
}

export function codeRegisterRequestNow(): FontRegisterRequest | null {
  return registerRequestOfValue(codeFontValueNow(), fontLibNow());
}

function registerRequestOfValue(value: string, libJson: string): FontRegisterRequest | null {
  const id: string = customIdOf(value);
  if (id !== '') {
    const entry: FontLibEntry | null = entryById(parseFontLib(libJson), id);
    if (entry === null) {
      return null;
    }
    return { alias: customAliasForId(id), source: entry.path, rawfile: false };
  }
  return builtinFontRequest(value);
}

// v1 迁移执行（EntryAbility 启动链消费，必须在 ensureSelectedFontsRegistered 之前）：无 v1
// 遗留（旧路径键空）即返回——天然幂等；有遗留时并入字体库、裸 'custom' 值补 id、值归一
//（不可用回落默认），最后清空旧四键防重复迁移
export function migrateLegacyFontSelectionNow(): void {
  const legacyBodyPath: string = AppStorage.get<string>(PREF_FONT_BODY_PATH_KEY) ?? '';
  const legacyCodePath: string = AppStorage.get<string>(PREF_FONT_CODE_PATH_KEY) ?? '';
  if (legacyBodyPath === '' && legacyCodePath === '') {
    return;
  }
  const result: FontMigrationResult = migrateLegacyFontSelection(legacyBodyPath,
    AppStorage.get<string>(PREF_FONT_BODY_NAME_KEY) ?? '',
    AppStorage.get<string>(PREF_FONT_BODY_KEY) ?? '', legacyCodePath,
    AppStorage.get<string>(PREF_FONT_CODE_NAME_KEY) ?? '',
    AppStorage.get<string>(PREF_FONT_CODE_KEY) ?? '', fontLibNow());
  AppStorage.setOrCreate<string>(PREF_FONT_LIB_KEY, result.libJson);
  AppStorage.setOrCreate<string>(PREF_FONT_BODY_KEY,
    resolveBodyFontId(result.bodyValue, result.libJson));
  AppStorage.setOrCreate<string>(PREF_FONT_CODE_KEY,
    resolveCodeFontId(result.codeValue, result.libJson));
  AppStorage.setOrCreate<string>(PREF_FONT_BODY_PATH_KEY, '');
  AppStorage.setOrCreate<string>(PREF_FONT_BODY_NAME_KEY, '');
  AppStorage.setOrCreate<string>(PREF_FONT_CODE_PATH_KEY, '');
  AppStorage.setOrCreate<string>(PREF_FONT_CODE_NAME_KEY, '');
}
