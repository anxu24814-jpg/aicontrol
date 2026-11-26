// 会话权限模式单一状态源（2026-11-09 决明拍板「真完全权限 + 输入栏工具行第三键」笔立；
// 同日按决明「退出重进选择消失，修」改按会话换档，再按「重启后也记得，每会话绑定」改持久化；
// 2026-11-09 三档归一笔记决明拍板：档名收敛为谨慎 / 标准 / 高效，高效开放到设置页默认档，
// 原三域审批卡（网页高危 / HTTP 写 / 数据管理）整批退役——权限只由本三档一根旋钮控制）。
// 职责一句话：会话级确认策略的三档值、当前会话覆盖值的读写与换会话换档、按会话持久表的
// 读写、档名与档位映射、旧三域档的一次性折算迁移。
// · 三档语义：谨慎 = 每次确认（直落人工卡，不过审批模型）；标准 = 先问审批模型（缺省档，
//   放行即执行、拒绝与拿不准落人工卡）；高效 = 一律执行，删除等不可逆操作也不弹卡。
//   ★ 高效档的地板只剩两条且都不是「审批」：密码框输入恒禁（红线 9，预检早退）、系统权限
//   弹窗（平台面）。域名准入白名单在高效档下同样不设限（决明 2026-11-09 拍板：
//   「完全权限时不设限」）——该卡只在谨慎 / 标准档下生效。★ 2026-11-11 域名确认档整档
//   退役（按域名的确认例外与会话三档同轴），写确认自此只由本三档裁决。
// · 作用域：应用默认档落盘、随备份走，三档全开放（原「完全权限只能在会话内切」已撤）；
//   会话内第三键菜单同样三档，会话档按会话绑定并跨重启保留。
//   ★ 会话档按会话绑定并跨重启保留（2026-11-09 决明拍板）：JSON 表「会话 id → 档」落
//   persistProp（`prefChatPermissionModes`），刻意不进备份表（键是本机会话 id，换机无意义；
//   高效档跨设备静默复现等于替新设备放宽确认策略）。判据 = enterConversation 进页写定
//   当前会话 id，只有 id 变化才按表回填——同一会话页重建（退出重进 / 从二级页回栈）与
//   杀进程重启都保留；切到没切过档的会话 = 空串 = 走默认档，互不继承。
//   表条目上限 200（最久未写的先出）；会话删除不主动清（陈旧 id 不会复用，靠上限兜底）。
// · 未显式切档 = 空串：正常路径由启动迁移（migrateLegacyApproveModes）一次性写定默认档，
//   此后不再出现空串；空串只剩两条来路——备份导入后的当次运行窗口、旧版本回退。此时
//   确认链按旧三域档逐域裁决（只读兜底，旧键已无任何设置页写点）。
// ★ 为何不能并入既有同域件（反碎片下限①②申报）：AppPreferences 是持久键章程件（零 import
//   叶子），会话表的解析/上限/回填是行为逻辑，并入会让一件同时承担两种职责；
//   ChatSessionOverrideCtrl 是 DB 覆盖编排（三值一对象、随会话行落库），其真源是 DB 且异步，
//   确认链是同步读——并进去会把同步判据拖成异步；ChatPromptState 是请求侧提示词态。
//   三者职责缝清晰，故新开本叶子。
// ★ 依赖方向（坑50）：本件单向 import AppPreferences（键常量与档位常量单一来源，后者零
//   import 叶子契约不破）；AppPreferences 不反向引本件，无环。ConfirmRouting 本已引
//   AppPreferences，再引本件不新增环面。AppStorage 是全局能力，不产生模块依赖。
import { APPROVE_MODE_ASK, APPROVE_MODE_AUTO, APPROVE_MODE_MODEL,
  browseApproveMode, CHAT_PERMISSION_MODE_CONV_KEY, CHAT_PERMISSION_MODE_KEY,
  dataApproveMode, defaultPermissionMode, httpApproveMode,
  PREF_CHAT_PERMISSION_MODES_KEY, PREF_DEFAULT_PERMISSION_MODE_KEY } from '../AppPreferences';

// 三档值（用户面档名与值解耦，档名只由 permissionModeLabel 单源给出）。★ 值 'full' 是
// 持久化契约（旧档存的就是 full），改名会牵动存量会话表与备份，档名改「高效」只动 label。
export const PERMISSION_MODE_CAUTIOUS: string = 'cautious';
export const PERMISSION_MODE_STANDARD: string = 'standard';
export const PERMISSION_MODE_FULL: string = 'full';

// 按会话表条目上限（最久未写的先出；只防无界增长，正常使用远达不到）
const SESSION_MODE_MAX: number = 200;

// 四枚键常量（PREF_DEFAULT_PERMISSION_MODE_KEY 落盘随备份 / PREF_CHAT_PERMISSION_MODES_KEY
// 按会话表落盘不随备份 / CHAT_PERMISSION_MODE_KEY 当前会话档只存内存 /
// CHAT_PERMISSION_MODE_CONV_KEY 当前会话 id 只存内存）定义在 AppPreferences 主件，本件
// 单向引用——见文件头依赖方向条。

// 合法值校验（读侧与写侧共用；脏值按迁移态处理，绝不把未知串当档位用）
export function isPermissionMode(mode: string): boolean {
  return mode === PERMISSION_MODE_CAUTIOUS || mode === PERMISSION_MODE_STANDARD ||
    mode === PERMISSION_MODE_FULL;
}

// 档名显示单源（输入栏菜单、设置页默认档卡、会话状态半模态共用，禁两处各写一份）
export function permissionModeLabel(mode: string): string {
  if (mode === PERMISSION_MODE_CAUTIOUS) {
    return '谨慎';
  }
  if (mode === PERMISSION_MODE_FULL) {
    return '高效';
  }
  return '标准';
}

// 当前生效会话 id（'' = 本次运行尚未进过会话页）
function activeConversationId(): string {
  return AppStorage.get<string>(CHAT_PERMISSION_MODE_CONV_KEY) ?? '';
}

// 按会话表解析（脏串 / 数组根 / 非法值一律丢，只认三档——读取口径照旧域名档同款实现，该档
// 已于 2026-11-11 整档退役）
function parseSessionModes(json: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (json === '') {
    return out;
  }
  try {
    const raw = JSON.parse(json) as Record<string, Object>;
    if (Array.isArray(raw)) {
      return {};
    }
    for (const convId of Object.keys(raw)) {
      const value: Object = raw[convId];
      if (typeof value === 'string' && isPermissionMode(value)) {
        out[convId] = value;
      }
    }
  } catch (e) {
    return {};
  }
  return out;
}

function readSessionModes(): Record<string, string> {
  return parseSessionModes(AppStorage.get<string>(PREF_CHAT_PERMISSION_MODES_KEY) ?? '');
}

// 写表 + 上限收口（ArkTS 无 delete，剔除键 = 重建不含该键的新对象；表尾 = 最近写过）
function writeSessionModes(map: Record<string, string>): void {
  let keys: string[] = Object.keys(map);
  let latest: Record<string, string> = map;
  while (keys.length > SESSION_MODE_MAX) {
    const fresh: Record<string, string> = {};
    for (let i = 1; i < keys.length; i++) {
      fresh[keys[i]] = map[keys[i]];
    }
    latest = fresh;
    keys = Object.keys(fresh);
  }
  AppStorage.setOrCreate<string>(PREF_CHAT_PERMISSION_MODES_KEY, JSON.stringify(latest));
}

// 当前会话覆盖原值（'' = 当前会话未手动切档）
export function readSessionPermissionMode(): string {
  const raw: string = AppStorage.get<string>(CHAT_PERMISSION_MODE_KEY) ?? '';
  return isPermissionMode(raw) ? raw : '';
}

// 生效模式（'' = 迁移态，确认链按旧三域档逐域裁决）。会话覆盖优先于应用默认档。
export function effectivePermissionMode(): string {
  const session: string = readSessionPermissionMode();
  return session !== '' ? session : defaultPermissionMode();
}

// 会话内切档（写点唯一 = 输入栏第三键菜单）。写即刷新所有 @StorageProp 订阅位，并把
// 「当前会话 id → 档」写进持久表（重启后按会话恢复）。
export function setSessionPermissionMode(mode: string): void {
  if (!isPermissionMode(mode)) {
    return;
  }
  AppStorage.setOrCreate<string>(CHAT_PERMISSION_MODE_KEY, mode);
  const convId: string = activeConversationId();
  if (convId === '') {
    return;
  }
  const map: Record<string, string> = readSessionModes();
  const fresh: Record<string, string> = {};
  for (const key of Object.keys(map)) {
    if (key !== convId) {
      fresh[key] = map[key];
    }
  }
  fresh[convId] = mode;
  writeSessionModes(fresh);
}

// 会话进入点（写点 = ChatPage.aboutToAppear / onShown）：只有「进的是另一个会话」才换档。
// 同一会话 id 不变（退出重进 / 从二级页回栈）→ 保留原档；换会话 / 冷启动进会话 → 按持久表
// 回填该会话记着的档（没切过 = 清回空串 = 走默认档或迁移态）。会话档因此不跨会话继承。
export function enterConversation(convId: string): void {
  if (convId === '') {
    return;
  }
  if (activeConversationId() === convId) {
    return;
  }
  AppStorage.setOrCreate<string>(CHAT_PERMISSION_MODE_CONV_KEY, convId);
  AppStorage.setOrCreate<string>(CHAT_PERMISSION_MODE_KEY, readSessionModes()[convId] ?? '');
}

// 应用默认档写点（设置页卡；三档全开放——高效档自本笔起可由用户设为默认）
export function setDefaultPermissionMode(mode: string): void {
  if (!isPermissionMode(mode)) {
    return;
  }
  AppStorage.setOrCreate<string>(PREF_DEFAULT_PERMISSION_MODE_KEY, mode);
}

// 旧三域档 → 默认档一次性折算迁移（2026-11-09 三档归一笔；写点 = EntryAbility 启动、
// persistProp 之后 PREF_LOADED 置 1 之前）。
// 只在默认档为空时执行：折算完即写定，之后永不重跑；备份导入带来空默认档时下一次启动再折算。
// 取三域最严档（ask > model > auto）——安全默认，用户可在设置页一键改宽。三域都未显式
// 设过 = 三域都走 model 推导 = 折算为标准，与升级前逐域行为等价。
export function migrateLegacyApproveModes(): void {
  if (defaultPermissionMode() !== '') {
    return;
  }
  const domains: string[] = [browseApproveMode(), httpApproveMode(), dataApproveMode()];
  let strictest: string = APPROVE_MODE_AUTO;
  for (const mode of domains) {
    if (mode === APPROVE_MODE_ASK) {
      strictest = APPROVE_MODE_ASK;
      break;
    }
    if (mode === APPROVE_MODE_MODEL) {
      strictest = APPROVE_MODE_MODEL;
    }
  }
  const mapped: string = strictest === APPROVE_MODE_ASK ? PERMISSION_MODE_CAUTIOUS :
    (strictest === APPROVE_MODE_MODEL ? PERMISSION_MODE_STANDARD : PERMISSION_MODE_FULL);
  setDefaultPermissionMode(mapped);
}

// 确认链档位归一（唯一读点 = ConfirmRouting.routeConfirmPrompt）。
// 返回 null = 高效档放行（写档与不可逆档都不再弹卡）；返回 'ask'/'model'/'auto' = 与
// AppPreferences 既有 APPROVE_MODE_* 三常量同值的旧档位；迁移态原样返回调用方传入的域档，
// 保证老用户升级零行为变化。
// ★ 形制约束：本函数是 ConfirmRouting 函数体内唯一新增自由名——断言脚本把该函数体抽成
//   .ts 直跑时，注入区补一枚同形桩 `function resolveConfirmMode(m) { return m; }` 即保持
//   迁移态语义，既有 107/129/B22 三组行为直跑钉零改判（桩与注入机制见各脚本段注释）。
export function resolveConfirmMode(domainMode: string): string | null {
  const session: string = effectivePermissionMode();
  if (session === PERMISSION_MODE_FULL) {
    return null;
  }
  if (session === PERMISSION_MODE_CAUTIOUS) {
    return APPROVE_MODE_ASK;
  }
  if (session === PERMISSION_MODE_STANDARD) {
    return APPROVE_MODE_MODEL;
  }
  return domainMode;
}
