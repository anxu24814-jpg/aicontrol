// 助手头像编码单源：助手头像的编码解析、输入校验与沙箱文件命名/清理——无 UI、无 DB。
// · 编码形态（assistants.avatar 列原串，本件 = 解析/序列化唯一落点）：
//   '' = 默认「首字圆底」；'text:<内容>' = 文字/表情（≤2 码点）；
//   'image:<uri>' = 图片——本地 file:// URI 与网络 http(s):// 地址同一 kind（本地图与
//   网络图在存储层不分开，取型 RikkaHub Avatar 三态收敛为两 kind）。本域只存取原串，
//   脏值兜底视同默认不崩。
// · 三消费面共用（编辑页编排 / 存储层删助手级联 / 共享渲染件 AssistantCardParts）——
//   禁在别处出现第二份 text:/image: 字面量解析或 assistant_avatar_ 文件名拼接
//  （断言钉守：assert-store-consistency 编码单源组）。
// · 文件生命周期三处清理（内存与资源防线——缺一处即无界增长）：
//   ①换图成功后删旧本地文件（编辑页编排，旧值写库前现查非缓存）
//   ②恢复默认删本地文件（编辑页编排）
//   ③删助手级联删文件（AssistantDb.deleteAssistantCascade，commit 后 best-effort）
//   + 临时文件落盘前扫删（cleanAvatarTempFiles，选图链入口）。
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// kind 白名单（单源）与长度上限（2 = 码点数不是码元——代理对防护，SkillText.safeCutIndex
// 同族教训；512 = 链接长度上限，不开口子）
export const AVATAR_KIND_TEXT: string = 'text';
export const AVATAR_KIND_IMAGE: string = 'image';
export const AVATAR_TEXT_MAX: number = 2;
export const AVATAR_URL_MAX: number = 512;

// 沙箱命名前缀（扫删靠前缀，单源）：正式头像 assistant_avatar_<assistantId>_<ts>.jpg，
// 临时中转 assistant_avatar_tmp_<ts>.jpg（选图链拷贝中转，压缩落盘成功后即删）
export const AVATAR_FILE_PREFIX: string = 'assistant_avatar_';
export const AVATAR_TMP_PREFIX: string = 'assistant_avatar_tmp_';

// 解析：取第一个 ':' 之前为 kind——kind 不在白名单或值空 = 返回 ''（视同默认，脏值兜底
// 不崩）；无 ':' 同 ''。只认两 kind，新增 kind 须先改白名单
export function avatarKind(spec: string): string {
  const at: number = spec.indexOf(':');
  if (at <= 0) {
    return '';
  }
  const kind: string = spec.substring(0, at);
  if (spec.substring(at + 1) === '') {
    return '';
  }
  return kind === AVATAR_KIND_TEXT || kind === AVATAR_KIND_IMAGE ? kind : '';
}

// 解析：第一个 ':' 之后的全串（只切第一段——'image:https://…' 的 URL 本体含 ':' 不受
// 影响）；无 ':' 返回 ''
export function avatarValue(spec: string): string {
  const at: number = spec.indexOf(':');
  return at >= 0 ? spec.substring(at + 1) : '';
}

// 序列化（调用方保证已校验——isValidAvatarText / isValidAvatarUrl 先行）
export function textAvatar(text: string): string {
  return AVATAR_KIND_TEXT + ':' + text;
}

export function imageAvatar(uri: string): string {
  return AVATAR_KIND_IMAGE + ':' + uri;
}

// 换行与控制字符判据（C0 全区 + DEL + Unicode 行/段分隔符——trim 与码点数之外的第三道门）
function isControlLike(code: number): boolean {
  return code < 0x20 || code === 0x7f || code === 0x2028 || code === 0x2029;
}

// 文字/表情校验：去首尾空白后码点数 1~AVATAR_TEXT_MAX 且不含换行/控制字符。
// ★ Array.from 按码点切（emoji 等增补平面字符 = 1 码点 2 码元）——禁用 length 判字符数
export function isValidAvatarText(text: string): boolean {
  const chars: string[] = Array.from(text.trim());
  if (chars.length < 1 || chars.length > AVATAR_TEXT_MAX) {
    return false;
  }
  for (const ch of chars) {
    if (isControlLike(ch.codePointAt(0) ?? 0)) {
      return false;
    }
  }
  return true;
}

// 链接校验：http:// 或 https:// 开头（大小写不敏感——'HTTP://' 是合法地址）+ 长度上限。
// 不做可达性预取（P1-2 轻量——失效由渲染兜底回首字）
export function isValidAvatarUrl(url: string): boolean {
  const trimmed: string = url.trim();
  const lower: string = trimmed.toLowerCase();
  return (lower.startsWith('http://') || lower.startsWith('https://'))
    && trimmed.length <= AVATAR_URL_MAX;
}

// 输入清洗：剔控制字符/换行（逐码点过滤）+ 去首尾空白 + 按码点截断到上限——截断永不
// 劈开代理对（Array.from 码点粒度，SkillText.safeCutIndex 同族教训）
export function sanitizeAvatarText(raw: string): string {
  const kept: string[] = [];
  for (const ch of Array.from(raw)) {
    if (!isControlLike(ch.codePointAt(0) ?? 0)) {
      kept.push(ch);
    }
  }
  return Array.from(kept.join('').trim()).slice(0, AVATAR_TEXT_MAX).join('');
}

// 正式头像文件名（唯一名——坑34：固定名会让 file:// URI 每次相同，@State 赋同值不触发
// 刷新；assistantId 含连字符与文件名合法字符集相容）
export function newAvatarFileName(assistantId: string): string {
  return AVATAR_FILE_PREFIX + assistantId + '_' + Date.now() + '.jpg';
}

// 选图中转临时文件名（压缩落盘成功后即删，进程被杀残留由 cleanAvatarTempFiles 扫删自愈）
export function newAvatarTempFileName(): string {
  return AVATAR_TMP_PREFIX + Date.now() + '.jpg';
}

// 本地图片型判定：kind = image 且值 file:// 开头（网络地址不删——URL 型头像无沙箱文件）
export function isLocalAvatarFile(spec: string): boolean {
  return avatarKind(spec) === AVATAR_KIND_IMAGE && avatarValue(spec).startsWith('file://');
}

// best-effort 删本地头像文件：非本地型 / filesDir 未就位 / 路径不在本应用沙箱内 = 静默
// 跳过（防误删——file:// 值理论上可被改写成任意路径）；文件不在 = 目标状态；删除失败
// 仅日志不抛（调用方均为收尾清理段，抛错会吞掉主流程的成功反馈）
export function deleteAvatarFile(filesDir: string, spec: string): void {
  if (!isLocalAvatarFile(spec) || filesDir === '') {
    return;
  }
  // file:///data/... 剥 scheme 得沙箱绝对路径（本应用生成的 URI 无特殊字符，无百分号
  // 编码回转面；fileUri.getUriFromPath 的逆运算，与 ImageEditUtil 前缀扫删同类的确定性变换）
  const path: string = avatarValue(spec).substring('file://'.length);
  if (path === '' || !path.startsWith(filesDir)) {
    return;
  }
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (e) {
    hilog.error(0xD5A4, 'AvatarSpec', 'delete avatar file failed: %{public}s, %{public}s',
      path, JSON.stringify(e));
  }
}

// 扫删临时中转残留（AVATAR_TMP_PREFIX*——选图取消/压缩失败/进程被杀都可能留下未引用
// 临时文件；前缀为本应用私有，无误删风险；照 ImageEditUtil.cleanBgFilesIn 姿势：
// listFileSync 前缀过滤 + 逐个 unlink，删除动作随用户手势执行一次，非轮询 P1-2）
export function cleanAvatarTempFiles(filesDir: string): void {
  if (filesDir === '') {
    return;
  }
  let names: string[] = [];
  try {
    names = fs.listFileSync(filesDir);
  } catch (e) {
    hilog.error(0xD5A4, 'AvatarSpec', 'list avatar temp files failed: %{public}s', JSON.stringify(e));
    return;
  }
  for (const name of names) {
    if (!name.startsWith(AVATAR_TMP_PREFIX)) {
      continue;
    }
    try {
      fs.unlinkSync(filesDir + '/' + name);
    } catch (e) {
      hilog.error(0xD5A4, 'AvatarSpec', 'remove avatar temp file failed: %{public}s, %{public}s',
        name, JSON.stringify(e));
    }
  }
}
