// Python 自装包域（2026-11-15 闲 4 门 5 笔，母方案 = docs/方案-鸿蒙内置Python运行环境
// -20261106.md §2.2 第 4/5 条 + §6 门 5）：冻结白名单 9 件纯 wheel 的下载、校验、解包、
// 登记与清理状态机。消费面 = PyRuntimePage 卡三（用户手动安装/清除/重建）。
// · 路线裁定（门 5 设计）：**开发期离线冻结**（版本 + sha256 + URL + 依赖闭包全在本文件
//   常量表）——运行期不做 PyPI 元数据查询、不做包名模糊解析，只碰 files.pythonhosted.org
//   一个域名下载固定 URL。依赖闭包的解析与 marker 求值在开发期人工完成（PyPI JSON API
//   实查），运行期只做机械校验 + 名单复核，供应链面收敛到最小（方案 §3.1「固定受信官方
//   PyPI 索引，记录版本与哈希」的落地形态；镜像后置）。
// · 闸序（方案 §2.2 第 4 条「标签过滤只是第一道闸」）：①冻结表本身只收 py3-none-any
//   wheel（开发期钉）②下载后 sha256 强校验（引导脚本 hashlib 侧算，ArkTS 零哈希依赖）
//   ③归档条目黑名单（.so/.pyd/.dll/.node/.a/.o/.exe/.bin 与 .so.数字 变体 + 路径穿越）
//   ④解包后读 METADATA 的 Requires-Dist 复核——非 extra 行的依赖名（PEP 503 规范化）必须
//   落在「预置 28 包 ∪ 白名单 9 件」内，出现未知名即拒装（防二进制经依赖绕入）。
// · 网络红线（照 TextImageFetch 先例）：走应用域直连族 http.createHttp()，不 import
//   ToolHttp / HttpFlow / EndpointPolicy 任何一件——HTTP 工具域白名单是「模型发起请求」
//   的护栏，本功能是用户在管理页的显式安装动作；安装器不查用户域名清单（该清单只作用
//   exec_code 的 JS 脚本联网，方案 §2.4 权限口径），固定域名硬编码单源。
// · 执行面：校验/解包引导脚本走 execPySession 专用命名空间 '__py_installer__'（不以
//   会话 id 形态出现，不与真实会话冲突；LRU 32 上限内单键常驻）。引导脚本 stdout 以
//   __PYINST__ 前缀打 JSON 回传；脚本内 open 落入审计钩 write 记录 = 天然留痕（忽略即可）。
//   超时 30s/件（最大件 6.6MB 解包毫秒级，充裕）；不进 PyScheduler lane——native gExecMutex
//   自带串行，lane 的排队/满拒语义是用户会话执行面的，与安装器无关。
// · 清理状态机（方案 §2.4 行为矩阵「清除自装包或重建运行区」）：先置进程内
//   pyCleanedFlag（此后 exec_python 预检与安装入口一律拒绝并提示重启）→ cancelPyRun()
//   尽力中断在跑执行 → 删目录。不承诺原地恢复——解释器不 Py_FinalizeEx（PyEngine 头注释
//   红线），清包/重建后必须重启应用，重启后 flag 自然复位、ensurePyRuntime 幂等重落位。
//   在跑 exec 与删目录的竞态：本轮已加载模块仍在内存不受影响，未加载 import 会失败报
//   PythonError（不崩进程），确认弹窗文案已提示。
// · 账本（installed.json）：存 homeDir/py-site/ 内——与自装包同生命周期，清包删目录即
//   清账，不进数据库不进备份（方案 §2.6：不接 Web 信封与应用管理工具面）。
// · P0-1：下载字节数与冻结 size 比对 + sha256 双校验；installed.json 全量重写（TRUNC），
//   半写入损坏按空表读（清理动作兜底重置），不静默造数。
import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ensurePyRuntime, initPyRuntime, execPySession, cancelPyRun,
  pyRuntimeHomePath, removeTreeAsync, PY_PRESET_PACKAGES } from './PyRuntime';
import { applyDefaultUserAgent, applyEffectiveProxy } from '../providers/RequestIdentity';
import { REQ_LOG_SOURCE_PY_INSTALL, reqLogBegin, reqLogEnd } from '../ReqLog';

// ── 冻结白名单（2026-11-15 PyPI JSON API 实查冻结；闭包核查：非 extra 依赖全部落在
// 预置 28 包 ∪ 本表内。变更 = 换版本或增删件，须同步 license 表与 LICENSE-THIRD-PARTY.md
// 自装包段 + 重跑 assert-app-domain 对应组）──
export interface PyUserPackage {
  // PyPI 规范发行名（下载与登记用名，如 python-docx）
  name: string;
  // 冻结版本
  version: string;
  // py3-none-any wheel 的 sha256（下载后强校验）
  sha256: string;
  // wheel 体积（字节）——下载结果体积分界（P0-1 第二道）
  sizeBytes: number;
  // files.pythonhosted.org 固定 URL（全冻结，运行期不拼路径）
  url: string;
  // 本表内的依赖件名（仅未预置的；预置依赖如 lxml/Pillow 不列）
  deps: string[];
  // 许可标识（许可档登记用）
  license: string;
}

export const PY_USER_PACKAGES: PyUserPackage[] = [
  { name: 'python-docx', version: '1.2.0',
    sha256: '3fd478f3250fbbbfd3b94fe1e985955737c145627498896a8a6bf81f4baf66c7',
    sizeBytes: 252987,
    url: 'https://files.pythonhosted.org/packages/d0/00/1e03a4989fa5795da308cd774f05b704ace555a70f9bf9d3be057b680bcf/python_docx-1.2.0-py3-none-any.whl',
    deps: [], license: 'MIT' },
  { name: 'python-pptx', version: '1.0.2',
    sha256: '160838e0b8565a8b1f67947675886e9fea18aa5e795db7ae531606d68e785cba',
    sizeBytes: 472788,
    url: 'https://files.pythonhosted.org/packages/d9/4f/00be2196329ebbff56ce564aa94efb0fbc828d00de250b1980de1a34ab49/python_pptx-1.0.2-py3-none-any.whl',
    deps: ['xlsxwriter'], license: 'MIT' },
  { name: 'pypdf', version: '7.1.0',
    sha256: '47cca6b24bdcf4c4d65b5f7b8b972535c61710a061261e737688777cfd9a7bfb',
    sizeBytes: 418698,
    url: 'https://files.pythonhosted.org/packages/ed/4c/d19f91b743c8579b67e3d8b001e095745dec5bb13a9b4b9eadc235a85d9e/pypdf-7.1.0-py3-none-any.whl',
    deps: [], license: 'BSD-3-Clause' },
  { name: 'pdfplumber', version: '0.11.10',
    sha256: '7741ea81bf165b474b153e6789d10d18e06b6ddcf3ec84289c3ef2fed6802580',
    sizeBytes: 60047,
    url: 'https://files.pythonhosted.org/packages/a2/9a/07d658e1e7fad860f1c541ab941348125dbdab773be3a0afaf32361866c7/pdfplumber-0.11.10-py3-none-any.whl',
    deps: ['pdfminer.six'], license: 'MIT' },
  { name: 'beautifulsoup4', version: '4.15.0',
    sha256: 'd6f88de62e1d4e38ecb1077eb9724cd0eff29d2a08ca16a401e9b9e93f117cf9',
    sizeBytes: 109924,
    url: 'https://files.pythonhosted.org/packages/88/c6/92fcd42f1ba33e1184263f25bfabf3d27c383410470f169e4b8163bf9c17/beautifulsoup4-4.15.0-py3-none-any.whl',
    deps: ['soupsieve'], license: 'MIT' },
  { name: 'soupsieve', version: '4.1.1',
    sha256: '8ff3422dab0b720fb667ee79864d80531a0e57994a13eb701697719ffcb751f6',
    sizeBytes: 55089,
    url: 'https://files.pythonhosted.org/packages/cd/65/7fae69a095696195334a934eab23aeb12e2715e6c3f08025d2f91942750e/soupsieve-4.1.1-py3-none-any.whl',
    deps: [], license: 'MIT' },
  { name: 'xlsxwriter', version: '3.3.1',
    sha256: '8e2c89e59d733fe59e112317218c64fbbc276d90a8c144ebd6f7fa15e7ab184a',
    sizeBytes: 180583,
    url: 'https://files.pythonhosted.org/packages/88/eb/1e6af9959a567901a7e7c7cef2e75883e487df223ed67f9a8977ff863bd8/xlsxwriter-3.3.1-py3-none-any.whl',
    deps: [], license: 'BSD-2-Clause' },
  { name: 'pdfminer.six', version: '20260107',
    sha256: '366585ba97e80dffa8f00cebe303d2f381884d8637af4ce422f1df3ef38111a9',
    sizeBytes: 6592252,
    url: 'https://files.pythonhosted.org/packages/20/8b/28c4eaec9d6b036a52cb44720408f26b1a143ca9bce76cc19e8f5de00ab4/pdfminer_six-20260107-py3-none-any.whl',
    deps: ['charset-normalizer'], license: 'MIT' },
  { name: 'charset-normalizer', version: '3.5.2',
    sha256: 'b6b751274acb69d77b3323d6b7dbaa3c7fdfc1eb829b7eb61d262f32e1af9685',
    sizeBytes: 68872,
    url: 'https://files.pythonhosted.org/packages/fc/ad/d07d7862a62ffa6d79d68074d14823243dd235a77c45262acbf6adeb28bf/charset_normalizer-3.5.2-py3-none-any.whl',
    deps: [], license: 'MIT' }
];

// 自装包目录名（homeDir 下一级；PYTHONPATH 第五层——PyEngine.cpp init 拼接，纯 py 层
// 末位、libDir 之前，优先级最低不遮蔽预置包；init 时目录可不存在，装包后 import 即见
//——前提是安装器收尾 importlib.invalidate_caches：CPython 对不存在目录缓存 None finder
// 且不自愈，先 import 失败过的进程不清缓存不认新装包）
export const PY_USER_SITE_DIR_NAME = 'py-site';
// 安装账本文件名（py-site 内——清包删目录即清账）
const PY_USER_INSTALLED_FILE = 'installed.json';
// 下载中转目录名（py-site 内，点前缀不进 import 语义）
const PY_STAGING_DIR_NAME = '.staging';
// 下载域名钉（冻结表 URL 全部以此为前缀；运行期唯一网络面）
const PY_INSTALL_HOST = 'https://files.pythonhosted.org/';
// 单件下载体积上限（冻结表最大件 6.6MB，64MB 兜底防异常响应）
const PY_INSTALL_MAX_BYTES = 64 * 1024 * 1024;
// 下载超时（连接 20s / 读取 90s——国内直连 PyPI 官方源慢是常态，读取给宽）
const PY_INSTALL_CONNECT_MS = 20000;
const PY_INSTALL_READ_MS = 90000;
// 引导脚本超时（校验 + 解包单件；毫秒级工作，30s 兜底）
const PY_INSTALL_SCRIPT_MS = 30000;
// 安装器专用命名空间 key（不以会话 id 形态出现；与用户会话命名空间分家）
const PY_INSTALLER_SESSION = '__py_installer__';
// 引导脚本回传标记（stdout 前缀——从捕获输出中定位 JSON 段）
const PY_INST_MARK = '__PYINST__';
// 预置包规范名集合（依赖复核判据用；从 PY_PRESET_PACKAGES「名 版本」串拆名规范化）
const PY_PRESET_NORMAL_NAMES: Set<string> = new Set<string>(
  PY_PRESET_PACKAGES.map((item: string): string => normalizePep503(item.split(' ')[0])));

// PEP 503 规范名（小写 + [-_.] 归一为 -；typing_extensions / typing-extensions 同归一）
function normalizePep503(name: string): string {
  return name.trim().toLowerCase().replace(/[-_.]+/g, '-');
}

// 已装条目（installed.json 内形态）
export interface PyUserInstalledEntry {
  name: string;
  version: string;
  sha256: string;
  installedAt: number;
}

// 清理待重启旗（进程内单例；清包/重建置位，重启自然复位——不落盘：重启本身就是用户可见
// 的「重新启用」动作，持久化只会造出「重启后仍锁死」的第二真相）
let pyCleanedFlag: boolean = false;

export function pyCleanedNeedsRestart(): boolean {
  return pyCleanedFlag;
}

// 建目录（EEXIST 容错——照 PyRuntime.ets 同款）
function mkdirTolerant(path: string): void {
  try {
    fs.mkdirSync(path, true);
  } catch (e) {
    const err = e as BusinessErrorLike;
    if (err.code !== 13900015) {
      throw e as Error;
    }
  }
}

interface BusinessErrorLike {
  code: number;
  message: string;
}

// 整件字节落盘（照 PyRuntime.ets 同款先例）
function writeAllBytes(path: string, bytes: Uint8Array): void {
  const file: fs.File = fs.openSync(path,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength });
  } finally {
    fs.closeSync(file);
  }
}

// 小 JSON 文本落盘（TRUNC 全量重写）
function writeAllText(path: string, text: string): void {
  writeAllBytes(path, util.TextEncoder.create('utf-8').encodeInto(text));
}

// 自装包目录绝对路径（空串 = 上下文未注入，调用方如实处理）
export function pyUserSitePath(): string {
  const home: string = pyRuntimeHomePath();
  return home === '' ? '' : home + '/' + PY_USER_SITE_DIR_NAME;
}

// 已装清单（读 installed.json；无文件/损坏 = 空表如实返回——半写入账本按空读，清理动作
// 兜底重置；不静默修补）
export function pyUserInstalledList(): PyUserInstalledEntry[] {
  const site: string = pyUserSitePath();
  if (site === '') {
    return [];
  }
  try {
    const raw: string = fs.readTextSync(site + '/' + PY_USER_INSTALLED_FILE);
    const parsed: object = JSON.parse(raw) as object;
    const holder = parsed as Record<string, object>;
    if ((holder['v'] as Object as number) !== 1) {
      return []; // 台账形态不符（未来升版/异构写入）——按空表读，防旧读侧误读新结构丢账
    }
    const rows = holder['packages'] as object[];
    if (!Array.isArray(rows)) {
      return [];
    }
    const out: PyUserInstalledEntry[] = [];
    for (const row of rows) {
      const r = row as Record<string, Object>;
      const name: string = (r['name'] ?? '') as string;
      const version: string = (r['version'] ?? '') as string;
      const sha256: string = (r['sha256'] ?? '') as string;
      const installedAt: number = (r['installedAt'] ?? 0) as number;
      if (name !== '' && version !== '') {
        out.push({ name, version, sha256, installedAt });
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

// 单件是否已装（按冻结名精确比对；不含版本——冻结表升版时旧版件会被判已装而跳过重装，
// 升版笔须先「清除自装包」再装，或同笔扩此判定比版本）
export function isPyUserPackageInstalled(name: string): boolean {
  return pyUserInstalledList().some((entry: PyUserInstalledEntry): boolean => entry.name === name);
}

// 追加登记（读-改-写全量重写；调方保证在安装成功点）
function appendInstalledRecord(entry: PyUserInstalledEntry): void {
  const site: string = pyUserSitePath();
  if (site === '') {
    throw new Error('应用上下文未注入，无法登记自装包');
  }
  const rows: PyUserInstalledEntry[] = pyUserInstalledList().filter(
    (row: PyUserInstalledEntry): boolean => row.name !== entry.name);
  rows.push(entry);
  const payload: PyInstalledFilePayload = { v: 1, packages: rows };
  writeAllText(site + '/' + PY_USER_INSTALLED_FILE, JSON.stringify(payload));
}

// installed.json 文件形态（appendInstalledRecord 写出与 pyUserInstalledList 读回的契约）
interface PyInstalledFilePayload {
  v: number;
  packages: PyUserInstalledEntry[];
}

// ── 引导脚本（校验 + 解包 + 元数据回传；跑在 '__py_installer__' 命名空间）──
// 头行 _PYINST_RAW 由 runInstallScript 拼接（JSON 双重 stringify 字面量），本常量自带
// import/def 序言的完整可编译段——参数只含路径/sha256/包名，无用户输入注入面。失败全收
// 敛为 {ok:false,error,tops} 一形：解包后任一失败也带回已落盘 top-level 名供调用方回滚
//（r["tops"] 在 extractall 前先记 + 函数体 try 兜底；模块级 try 是 def 段自身炸的终防线），
// ArkTS 侧统一转中文。
const PY_INST_SCRIPT_BODY = [
  'import hashlib, json, os, sys, zipfile',
  'def _pyinst_main():',
  '    a = json.loads(_PYINST_RAW)',
  '    whl = a["whl"]',
  '    want = a["sha256"]',
  '    dest = a["dest"]',
  '    r = {"ok": False, "name": a.get("name", ""), "tops": [], "requires": []}',
  '    try:',
  '        h = hashlib.sha256()',
  '        with open(whl, "rb") as f:',
  '            while True:',
  '                b = f.read(1048576)',
  '                if not b:',
  '                    break',
  '                h.update(b)',
  '        got = h.hexdigest()',
  '        if got != want:',
  '            r["error"] = "sha256 mismatch got=" + got',
  '            return r',
  '        with zipfile.ZipFile(whl) as zf:',
  '            names = zf.namelist()',
  '            tops = []',
  '            for n in names:',
  '                parts = n.split("/")',
  '                if n.startswith("/") or ".." in parts or (len(parts) == 1 and parts[0] != ""):',
  '                    r["error"] = "unsafe entry " + n',
  '                    return r',
  '                t = parts[0]',
  '                if t and t not in tops:',
  '                    tops.append(t)',
  '                low = n.lower()',
  '                if low.endswith((".so", ".pyd", ".dll", ".dylib", ".node", ".a", ".o", ".exe", ".bin")) or ".so." in low:',
  '                    r["error"] = "binary entry " + n',
  '                    return r',
  '            os.makedirs(dest, exist_ok=True)',
  '            r["tops"] = tops',
  '            zf.extractall(dest)',
  '        di = None',
  '        for t in tops:',
  '            if t.endswith(".dist-info"):',
  '                di = t',
  '                break',
  '        if di is None:',
  '            r["error"] = "dist-info missing"',
  '            return r',
  '        req = []',
  '        mp = os.path.join(dest, di, "METADATA")',
  '        if os.path.exists(mp):',
  '            with open(mp, "r", encoding="utf-8", errors="replace") as f:',
  '                for line in f:',
  '                    s = line.rstrip("\\r\\n")',
  '                    if s.startswith("Requires-Dist:"):',
  '                        req.append(s[len("Requires-Dist:"):].strip())',
  '                    elif req and s and not s.startswith(" ") and not s.startswith("\\t"):',
  '                        break',
  '        r["ok"] = True',
  '        r["requires"] = req',
  '        return r',
  '    except BaseException as e:',
  '        r["error"] = repr(e)',
  '        return r',
  'try:',
  '    _out = _pyinst_main()',
  'except BaseException as e:',
  '    _out = {"ok": False, "error": repr(e)}',
  'sys.stdout.write("' + PY_INST_MARK + '" + json.dumps(_out, ensure_ascii=False))'
].join('\n');

// 引导脚本结果（stdout JSON 段解析）
interface PyInstScriptResult {
  ok: boolean;
  name: string;
  tops: string[];
  requires: string[];
  error: string;
}

// 引导脚本入参（JSON 字面量注入 _PYINST_RAW 的契约形态）
interface PyInstScriptArgs {
  whl: string;
  sha256: string;
  dest: string;
  name: string;
}

// 跑引导脚本（单件校验 + 解包；失败以 ok:false 结果返回不抛——脚本任一失败形态都尽力
// 带回已落盘 tops 供调用方回滚，中文包装在调用方统一做）
async function runInstallScript(whlPath: string, sha256: string, destDir: string,
  pkgName: string): Promise<PyInstScriptResult> {
  const args: PyInstScriptArgs = { whl: whlPath, sha256: sha256, dest: destDir, name: pkgName };
  const script: string = '_PYINST_RAW = ' + JSON.stringify(JSON.stringify(args))
    + '\n' + PY_INST_SCRIPT_BODY;
  const outcome = await execPySession(script, PY_INSTALL_SCRIPT_MS, PY_INSTALLER_SESSION, '');
  const markAt: number = outcome.stdout.indexOf(PY_INST_MARK);
  if (markAt < 0) {
    return { ok: false, name: pkgName, tops: [], requires: [],
      error: '安装脚本未回传结果' + (outcome.stderr !== '' ? '：' + outcome.stderr.slice(0, 300) : '') };
  }
  try {
    const obj: object = JSON.parse(outcome.stdout.substring(markAt + PY_INST_MARK.length)) as object;
    const r = obj as Record<string, Object>;
    return {
      ok: (r['ok'] ?? false) as boolean,
      name: (r['name'] ?? '') as string,
      tops: (r['tops'] ?? []) as Object as string[],
      requires: (r['requires'] ?? []) as Object as string[],
      error: (r['error'] ?? '') as string
    };
  } catch (e) {
    return { ok: false, name: pkgName, tops: [], requires: [], error: '安装脚本回传无法解析' };
  }
}

// 依赖复核（闸④）：解包回传的 Requires-Dist 原文行逐条判名——含 extra 的行整行跳过
// （可选依赖不进安装闭包），其余行取 PEP 508 名段规范化后必须 ∈ 预置名 ∪ 白名单名；
// 未知名 = 白名单外依赖，拒装（调用方负责删解包产物）
function verifyRequires(parsed: PyInstScriptResult): void {
  const whiteNames: Set<string> = new Set<string>(
    PY_USER_PACKAGES.map((pkg: PyUserPackage): string => normalizePep503(pkg.name)));
  for (const raw of parsed.requires) {
    const semiAt: number = raw.indexOf(';');
    const namePart: string = (semiAt >= 0 ? raw.substring(0, semiAt) : raw).trim();
    const markerPart: string = semiAt >= 0 ? raw.substring(semiAt + 1) : '';
    if (markerPart.includes('extra')) {
      continue; // extra 行 = 可选特性依赖，不属安装闭包
    }
    // PEP 508 名段 = 首个版本/括号/分号符前段
    const cut: number = namePart.search(/[\[><=!~;(]/);
    const depName: string = normalizePep503(cut >= 0 ? namePart.substring(0, cut) : namePart);
    if (depName === '') {
      continue;
    }
    if (!PY_PRESET_NORMAL_NAMES.has(depName) && !whiteNames.has(depName)) {
      throw new Error('包 ' + parsed.name + ' 的依赖 ' + depName
        + ' 不在预置包与自装白名单内，已拒绝安装');
    }
  }
}

// 解包回滚（删引导脚本回传的 top-level 目录；单件失败时调用，best-effort）
async function rollbackTops(siteDir: string, tops: string[]): Promise<void> {
  for (const top of tops) {
    await removeTreeAsync(siteDir + '/' + top);
  }
}

// 删单文件（best-effort 容错——staging 中转件清理；失败残留由「清除自装包」兜底）
function unlinkQuiet(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (e) {
    // 容错：中转件残留无害，清理动作兜底
  }
}

// ── 下载（照 TextImageFetch 形制；失败 throw 中文）──
async function downloadWheel(url: string, destPath: string, expectBytes: number): Promise<void> {
  if (!url.startsWith(PY_INSTALL_HOST)) {
    throw new Error('下载地址不属于官方 PyPI 文件域，已拒绝');
  }
  const request: http.HttpRequest = http.createHttp();
  const header: Record<string, string> = {};
  applyDefaultUserAgent(header);
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: header,
    usingCache: false,
    expectDataType: http.HttpDataType.ARRAY_BUFFER,
    maxLimit: PY_INSTALL_MAX_BYTES,
    connectTimeout: PY_INSTALL_CONNECT_MS,
    readTimeout: PY_INSTALL_READ_MS
  };
  applyEffectiveProxy(options);
  const startedAt: number = Date.now();
  const logId: string = reqLogBegin({
    source: REQ_LOG_SOURCE_PY_INSTALL, model: '', method: 'GET', url: url, headers: header,
    body: ''
  });
  let logEnded: boolean = false; // 单次性哨兵：已记终态的错误只 rethrow，防二次 reqLogEnd 覆写码
  try {
    const resp: http.HttpResponse = await request.request(url, options);
    if (resp.responseCode < 200 || resp.responseCode > 299 ||
      !(resp.result instanceof ArrayBuffer)) {
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, 'wheel 下载未返回文件数据', '');
      logEnded = true;
      throw new Error('下载失败（HTTP ' + resp.responseCode + '）');
    }
    const bytes: Uint8Array = new Uint8Array(resp.result);
    if (bytes.byteLength !== expectBytes) {
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
        'wheel 体积与冻结值不符（' + bytes.byteLength + '/' + expectBytes + ' B）', '');
      logEnded = true;
      throw new Error('下载体积与预期不符（' + bytes.byteLength + '/' + expectBytes + ' B）');
    }
    writeAllBytes(destPath, bytes);
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', '');
    logEnded = true;
  } catch (e) {
    if (logEnded) {
      throw e as Error; // 已记终态的中文下载错误（体积/HTTP），勿二次包装
    }
    reqLogEnd(logId, -1, Date.now() - startedAt, 'wheel 下载失败：' + (e as Error).message, '');
    throw new Error('下载失败：' + (e as Error).message);
  } finally {
    request.destroy();
  }
}

// 安装计划闭包（目标件 + 递归依赖，剔除已装；返回保持依赖先序）
function buildInstallPlan(target: string): PyUserPackage[] {
  const byName: Map<string, PyUserPackage> = new Map<string, PyUserPackage>();
  for (const pkg of PY_USER_PACKAGES) {
    byName.set(pkg.name, pkg);
  }
  const plan: PyUserPackage[] = [];
  const visiting: Set<string> = new Set<string>(); // 进行中栈（环检测）——冻结表当前为树形，改表引入循环依赖时此处红而非栈溢出
  const visit = (name: string): void => {
    const pkg: PyUserPackage | undefined = byName.get(name);
    if (pkg === undefined) {
      throw new Error('包 ' + name + ' 不在自装白名单内');
    }
    if (plan.some((item: PyUserPackage): boolean => item.name === name)) {
      return;
    }
    if (visiting.has(name)) {
      throw new Error('白名单依赖出现循环（' + name + '），禁止安装');
    }
    visiting.add(name);
    for (const dep of pkg.deps) {
      visit(dep);
    }
    visiting.delete(name);
    if (!isPyUserPackageInstalled(name)) {
      plan.push(pkg);
    }
  };
  visit(target);
  return plan;
}

// 安装台账进程级防重入（页面级 installBusy 不随安装 Promise 存活——安装中退出重进页
// 不可再触发第二条并发链；同名 wheel 冻结字节相同，双链本可幂等覆盖，此旗防进度互覆与重复下载）
let pyInstalling: boolean = false;

// 装包后失效解释器路径缓存：CPython 对不存在目录的 finder 缓存为 None 且不自愈——用户
// 先 import 失败再装包的场景，不清缓存则同进程 import 仍失败到重启；path_importer_cache
// 是解释器级，安装会话跑一次即全局生效。best-effort：失败降级回「重启后恢复」形态
async function invalidatePyImporterCaches(): Promise<void> {
  try {
    await execPySession('import importlib\nimportlib.invalidate_caches()',
      PY_INSTALL_SCRIPT_MS, PY_INSTALLER_SESSION, '');
  } catch (e) {
    // 容错：安装器会话不可用等极端态——最坏回到 None 缓存形态（重启后恢复），不阻断回报
  }
}

// 安装主入口（管理页卡三消费；onNote = 进度文本回调，UI 层做 departed 守卫；任一件失败
// 即停——已成功件保留登记（部分成功如实可见），失败件回滚解包产物；循环逐件复查清理旗，
// 清包/重建与安装并发交错时立即中止）
export async function installPyUserPackage(targetName: string,
  onNote: (text: string) => void): Promise<void> {
  if (pyCleanedFlag) {
    throw new Error('Python 运行环境已清理，请重启应用后再安装自装包');
  }
  if (pyInstalling) {
    throw new Error('已有安装任务进行中，请稍候。');
  }
  const ctxHome: string = pyRuntimeHomePath();
  if (ctxHome === '') {
    throw new Error('应用上下文未注入，无法安装自装包');
  }
  pyInstalling = true;
  try {
    const plan: PyUserPackage[] = buildInstallPlan(targetName);
    if (plan.length === 0) {
      onNote('已是最新安装状态');
      return;
    }
    onNote('准备 Python 运行环境');
    const homeDir: string = await ensurePyRuntime();
    const initOutcome = await initPyRuntime(homeDir);
    if (!initOutcome.ok) {
      throw new Error('Python 初始化失败：' + initOutcome.error);
    }
    const siteDir: string = homeDir + '/' + PY_USER_SITE_DIR_NAME;
    const stagingDir: string = siteDir + '/' + PY_STAGING_DIR_NAME;
    mkdirTolerant(siteDir);
    mkdirTolerant(stagingDir);
    let done: number = 0;
    try {
      for (const pkg of plan) {
        if (pyCleanedFlag) {
          throw new Error('Python 运行环境已清理，安装中止');
        }
        done += 1;
        const fileName: string = pkg.url.substring(pkg.url.lastIndexOf('/') + 1);
        const whlPath: string = stagingDir + '/' + fileName;
        onNote('下载 ' + pkg.name + ' ' + pkg.version + '（' + done + '/' + plan.length + '）');
        await downloadWheel(pkg.url, whlPath, pkg.sizeBytes);
        onNote('安装 ' + pkg.name + '（' + done + '/' + plan.length + '）');
        let parsed: PyInstScriptResult | undefined = undefined;
        try {
          parsed = await runInstallScript(whlPath, pkg.sha256, siteDir, pkg.name);
          if (!parsed.ok) {
            throw new Error('包完整性校验未通过（' + pkg.name + '）：' + parsed.error);
          }
          verifyRequires(parsed);
          try {
            appendInstalledRecord({
              name: pkg.name, version: pkg.version, sha256: pkg.sha256, installedAt: Date.now()
            });
          } catch (e) {
            throw new Error('安装台账写入失败（' + pkg.name + '）：' + (e as Error).message);
          }
        } catch (e) {
          // 失败件回滚：脚本任一失败形态都带回已落盘 tops（sha256/黑名单失败时为空——解包
          // 未发生）；台账写失败同样回滚。回滚自身失败不掩盖原始错误（残留由「清除自装包」兜底）
          await rollbackTops(siteDir, parsed !== undefined ? parsed.tops : [])
            .catch((): void => {});
          unlinkQuiet(whlPath);
          throw e as Error;
        }
        unlinkQuiet(whlPath); // 校验解包通过即弃中转件（best-effort，残留由清除动作兜底）
      }
    } finally {
      await invalidatePyImporterCaches(); // 部分成功件也要能被同进程 import 到
    }
    onNote('安装完成（共 ' + plan.length + ' 件）');
  } finally {
    pyInstalling = false;
  }
}

// 清除自装包（方案 §2.4 行为矩阵：置旗 → 尽力中断在跑执行 → 删 py-site 整目录〔账本
// 随目录走〕；此后 exec_python 与安装入口一律拒到重启）
export async function clearPyUserPackages(): Promise<void> {
  pyCleanedFlag = true; // 先置旗——后续 exec 与安装立即被拒
  cancelPyRun();
  const site: string = pyUserSitePath();
  if (site !== '') {
    await removeTreeAsync(site);
  }
}

// 重建运行区（删 homeDir 整目录；重启后 ensurePyRuntime 按 .ready 缺失幂等重落位——
// rawfile 三件内置零网络）
export async function rebuildPyRuntime(): Promise<void> {
  pyCleanedFlag = true;
  cancelPyRun();
  const home: string = pyRuntimeHomePath();
  if (home !== '') {
    await removeTreeAsync(home);
  }
}
