/**
 * 消息字体注册与加载（平台依赖面）：@kit.ArkGraphics2D 的 FontCollection 全局实例 +
 * loadFontSyncWithCheck（官方推荐同步注册接口；API 23+ 带明确错误码 25900001~25900008 与
 * 401，注册名以「别名, 回退族」链喂 fontFamily）。
 * 与 ChatFont.ets 的职责缝：纯解析与值域在 ChatFont.ets（零 import 叶子件，断言直跑），
 * 本件只管「怎么把字体装进系统」+ 库文件存在性校验（fs 依赖面），两者均属消息字体域。
 * 注册时机四处：①启动——EntryAbility loadContent 回调（字体键 persistProp 与 v1 迁移之后、
 * PREF_LOADED_KEY 置 1 之前——此刻页面组件尚未实例化，消息页首帧渲染即有正确字体）；
 * ②设置面切换/导入——先注册成功再写偏好键（注册失败不落选择，页面明确报错）；③字体页
 * 进页——注册全部选项字体（未选中档的行标题也要以对应字体渲染「自证」——重启不回退默认
 * 字体）；④不做卸载——unloadFontSync 会使在用排版对象渲染异常（官方警示），会话内注册过
 * 的字体保留到进程结束，删除字体文件也不回收已载入字体；常驻面收窄靠懒注册——启动只注册
 * 选中档，字体页打开后全部选项常驻到进程结束（行标题自证的必需代价；别名幂等表防重复
 * 加载），导入校验时注册的字体同样常驻（校验必需，不可免）。
 * ★ 应用级字体下发：「字体仅用于会话页」开关关闭（全局态）时把正文档主族名写入
 * ApplicationContext.setFont 应用级槽位（官方 API 12+，单族名；显式 fontFamily 优先于
 * 槽位——会话页显式链不受影响）。下发时机官方约束 = 窗口已创建且 loadContent 完成之后
 * ——启动链在 loadContent 回调内、设置面运行时切换页面已加载，均满足。
 */

import { common } from '@kit.AbilityKit';
import { text } from '@kit.ArkGraphics2D';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FontLibEntry, FontRegisterRequest, FONT_BODY_DEFAULT, FONT_BODY_FANGSONG,
  FONT_BODY_SERIF, FONT_CODE_DEFAULT, FONT_CODE_JETBRAINS,
  PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY, PREF_FONT_LIB_KEY, bodyFontPrimaryFamilyNow,
  bodyRegisterRequestNow, builtinFontRequest, codeRegisterRequestNow, customAliasForId,
  customIdOf, entryById, fileNameOf, fontLibNow, fontSessionOnlyNow, parseFontLib,
  resolveBodyFontId, resolveCodeFontId, serializeFontLib } from './ChatFont';

const DOMAIN = 0x0000;
const TAG = 'ChatFontLoader';

// 已注册别名（进程内幂等表）：同名重复注册官方行为是静默失败，先查表短路；别名唯一性由
// 构造保证（内置固定名 + 自定义按文件名时间戳派生）
const registeredAliases: Set<string> = new Set<string>();

// 错误码 → 用户文案（官方 loadFontSyncWithCheck 抛错码全表；文案遵「面向用户文案写作规约」）
function fontErrorText(code: number): string {
  if (code === 25900001 || code === 401) {
    return '字体文件参数无效';
  }
  if (code === 25900002) {
    return '字体文件不存在';
  }
  if (code === 25900007) {
    return '字体文件是空文件';
  }
  if (code === 25900008) {
    return '字体文件已损坏，或格式不支持';
  }
  if (code >= 25900003 && code <= 25900006) {
    return '字体文件读取失败';
  }
  return '字体注册失败。错误码 ' + code.toString();
}

// 注册单个别名（幂等；'' = 成功，非空 = 错误文案）
function registerFontAlias(alias: string, source: string, rawfile: boolean): string {
  if (alias === '' || source === '') {
    return '字体文件无效';
  }
  if (registeredAliases.has(alias)) {
    return '';
  }
  try {
    const target: string | Resource = rawfile ? $rawfile(source) : 'file://' + source;
    text.FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, target);
    registeredAliases.add(alias);
    hilog.info(DOMAIN, TAG, '字体注册成功 alias=%{public}s', alias);
    return '';
  } catch (error) {
    const failure = error as BusinessError;
    hilog.error(DOMAIN, TAG, '字体注册失败 alias=%{public}s code=%{public}d msg=%{public}s',
      alias, failure.code, failure.message);
    return fontErrorText(failure.code);
  }
}

// 注册内置字体档（正文 serif/fangsong、代码 jetbrains；其余档无需注册直接回 ''）
export function registerBuiltinFont(id: string): string {
  const request: FontRegisterRequest | null = builtinFontRequest(id);
  if (request === null) {
    return '';
  }
  return registerFontAlias(request.alias, request.source, request.rawfile);
}

// 注册自定义字体文件（导入校验消费；别名从文件名主干派生，跨重启稳定）
export function registerCustomFontPath(path: string): string {
  const alias: string = customAliasForId(fileNameOf(path));
  return registerFontAlias(alias, path, false);
}

// 沙箱文件存在性（库校验用；取不到回 false——缺失即剔除）
function fileExists(path: string): boolean {
  if (path === '') {
    return false;
  }
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

// 字体库文件校验：剔除文件已不在的项（换机恢复 / 外部清理后列表不留死项——选中值随之经
// resolve 回落默认档）；返回清理后的库 JSON
function cleanFontLib(): string {
  const libJson: string = fontLibNow();
  const entries: FontLibEntry[] = parseFontLib(libJson);
  const alive: FontLibEntry[] = [];
  let removed: number = 0;
  for (const entry of entries) {
    if (fileExists(entry.path)) {
      alive.push(entry);
    } else {
      removed++;
    }
  }
  if (removed === 0) {
    return libJson;
  }
  const next: string = serializeFontLib(alive);
  AppStorage.setOrCreate<string>(PREF_FONT_LIB_KEY, next);
  hilog.warn(DOMAIN, TAG, '字体库清理缺失项 %{public}d 个', removed);
  return next;
}

// 启动注册（EntryAbility loadContent 回调消费）：①库校验清死项 ②选中键归一（脏值/指向
// 已删字体 → 复位默认档，设置面与实际渲染保持一致）③只注册当前选中档；选中档不可用
//（文件缺失/损坏）时复位为默认档，失败详情 hilog 留痕
export function ensureSelectedFontsRegistered(): void {
  const libJson: string = cleanFontLib();
  // 选中键归一
  const rawBody: string = AppStorage.get<string>(PREF_FONT_BODY_KEY) ?? '';
  const bodyValue: string = resolveBodyFontId(rawBody, libJson);
  if (bodyValue !== rawBody) {
    AppStorage.setOrCreate<string>(PREF_FONT_BODY_KEY, bodyValue);
  }
  const rawCode: string = AppStorage.get<string>(PREF_FONT_CODE_KEY) ?? '';
  const codeValue: string = resolveCodeFontId(rawCode, libJson);
  if (codeValue !== rawCode) {
    AppStorage.setOrCreate<string>(PREF_FONT_CODE_KEY, codeValue);
  }
  // 按需注册（只注册选中档）
  const bodyRequest: FontRegisterRequest | null = bodyRegisterRequestNow();
  if (bodyRequest !== null) {
    const bodyError: string = registerFontAlias(bodyRequest.alias, bodyRequest.source, bodyRequest.rawfile);
    if (bodyError !== '') {
      hilog.warn(DOMAIN, TAG, '正文字体选中档不可用，复位默认：%{public}s', bodyError);
      AppStorage.setOrCreate<string>(PREF_FONT_BODY_KEY, FONT_BODY_DEFAULT);
    }
  }
  const codeRequest: FontRegisterRequest | null = codeRegisterRequestNow();
  if (codeRequest !== null) {
    const codeError: string = registerFontAlias(codeRequest.alias, codeRequest.source, codeRequest.rawfile);
    if (codeError !== '') {
      hilog.warn(DOMAIN, TAG, '代码字体选中档不可用，复位默认：%{public}s', codeError);
      AppStorage.setOrCreate<string>(PREF_FONT_CODE_KEY, FONT_CODE_DEFAULT);
    }
  }
}

// 字体页进页消费：注册全部选项字体（内置三档：衬线/仿宋/JetBrains Mono + 库内全部自定义）
//——注册后选择组卡的行标题才能以对应字体渲染「自证」；未选中档也须注册，否则重启后行
// 标题回退默认字体、点选后才恢复。registeredAliases 幂等：同进程重复进页零重复加载；
// 失败只 hilog 不阻断页面（该行回退默认字体，真正点选时 prepareFontSelection 再明确报错）
export function ensureAllFontOptionsRegistered(): void {
  const builtinIds: string[] = [FONT_BODY_SERIF, FONT_BODY_FANGSONG, FONT_CODE_JETBRAINS];
  for (const id of builtinIds) {
    const failure: string = registerBuiltinFont(id);
    if (failure !== '') {
      hilog.warn(DOMAIN, TAG, '选项字体注册失败 id=%{public}s：%{public}s', id, failure);
    }
  }
  for (const entry of parseFontLib(fontLibNow())) {
    const failure: string = registerCustomFontPath(entry.path);
    if (failure !== '') {
      hilog.warn(DOMAIN, TAG, '选项字体注册失败 id=%{public}s：%{public}s', entry.id, failure);
    }
  }
}

// 设置面选行前就绪性检查（自定义档 = 注册库内该文件；内置档 = 注册内置；默认/等宽档恒
// 就绪）。返回 '' = 可写键，非空 = 错误文案（页面不落选择并提示）。正文与代码共用本函数
//——值域已自足（'custom:<id>' 与内置值不重叠），无需分域
export function prepareFontSelection(value: string, libJson: string): string {
  const id: string = customIdOf(value);
  if (id !== '') {
    const entry: FontLibEntry | null = entryById(parseFontLib(libJson), id);
    if (entry === null) {
      return '字体已不可用，请重新导入';
    }
    return registerCustomFontPath(entry.path);
  }
  return registerBuiltinFont(value);
}

// ── 应用级字体下发 ──
// 全局态把正文档主族名写入 ApplicationContext.setFont 应用级槽位。失败返回错误文案
//（调用面 toast 或按需忽略——启动链忽略返回值只留痕），开关值照常落盘、下次启动按落盘
// 态重发；已挂载文本是否即时刷新官方未明示（真机验证项，见 BLOCKED 清单）。context 传
// null = 宿主上下文不可达（P0-1 禁静默：hilog 留痕 + 错误文案返回，不假装成功）

// 全局态下发正文档主族名（启动全局态 / 设置面切正文档 / 开关切到全局 三处消费）
export function applyAppFontGlobal(context: common.Context | null): string {
  if (context === null) {
    hilog.error(DOMAIN, TAG, '应用级字体下发失败：宿主上下文不可达');
    return '无法获取应用上下文，字体范围暂未生效';
  }
  const family: string = bodyFontPrimaryFamilyNow();
  try {
    context.getApplicationContext().setFont(family);
    hilog.info(DOMAIN, TAG, '应用级字体下发 family=%{public}s', family);
    return '';
  } catch (error) {
    const failure = error as BusinessError;
    hilog.error(DOMAIN, TAG, '应用级字体下发失败 family=%{public}s code=%{public}d msg=%{public}s',
      family, failure.code, failure.message);
    return '应用字体设置失败。错误码 ' + failure.code.toString();
  }
}

// 恢复系统默认（开关切回仅会话页消费；setFont('null') 官方恢复语义——字面量 'null'）
export function resetAppFont(context: common.Context | null): string {
  if (context === null) {
    hilog.error(DOMAIN, TAG, '应用级字体恢复失败：宿主上下文不可达');
    return '无法获取应用上下文，字体范围暂未生效';
  }
  try {
    context.getApplicationContext().setFont('null');
    hilog.info(DOMAIN, TAG, '应用级字体已恢复系统默认');
    return '';
  } catch (error) {
    const failure = error as BusinessError;
    hilog.error(DOMAIN, TAG, '应用级字体恢复失败 code=%{public}d msg=%{public}s',
      failure.code, failure.message);
    return '应用字体设置失败。错误码 ' + failure.code.toString();
  }
}

// 启动链入口（loadContent 回调内、ensureSelectedFontsRegistered 之后）：仅会话页态
//（默认）零动作——应用级槽位保持系统默认；全局态下发。此刻组件未实例化，全局首帧即
// 正确字体，无「已挂载残留旧字形」面
export function applyAppFontOnLaunch(context: common.Context | null): void {
  if (!fontSessionOnlyNow()) {
    applyAppFontGlobal(context);
  }
}
