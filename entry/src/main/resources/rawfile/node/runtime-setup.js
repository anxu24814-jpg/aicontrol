// 运行区准备件（2026-11-23 鸿蒙 Node 运行时门 2，任务书-鸿蒙Node运行时门2-20261123
// §3.1「运行区与单飞准备」/§3.5「npm 文件集落位判据」）：bootstrap 的准备态（prepare）在此定型。
// · 本件职责（S2 起）：①placement-spec 读入与四件字节落位自检；②npm-fileset.tar.gz 的
//   最小 tar 解析与解包（临时子目录 → 逐件 sha256 全验 → rename 就位 → 写 .ready）；
//   ③二次准备快路径（命中 .ready 只校验版本串、三个关键件与 npm/package.json 版本，不全扫
//   1926 件）；④当前版本就绪后的旧版本目录清扫。
// · 解析安全（§3.5 判据 5）：magic 同时接受老 GNU `ustar  \0`（冻结包 2384 头全是此格式）与
//   POSIX `ustar\0`；只按 typeflag 判定（只许 0 文件 / 5 目录），拒绝 L/K/x/g/S（长名/PAX/
//   符号链接头）与 1/2（hardlink/symlink）；拒绝绝对路径、反斜杠、`.`/`..` 段、重复路径与
//   越界 size；prefix 区非零按 prefix/name 拼接后过同一套路径闸。任一负例都抛含条目序号的
//   可读错误，禁静默错位。
// · 状态契约：prepare = 'running'（解包中）| 'ready'（.ready 已在场且校验过）| 'failed'
//   （+prepareError）。.ready 内容 = `<runtimeVersion>:<tar sha256>`，只有全验通过才写；
//   解包在临时子目录 `<HOME>/.npm-unpack-<pid>-<rand>/` 完成，失败清临时目录且不写 .ready。
//   准备失败后本进程不可重试（node::Start 单次），下次冷启清暂存后重试——调用方只报告。
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');

// 宿主 NodeRuntime.ets 写入的落位说明文件（HOME 下一级；通道、版本与四件尺寸的唯一注入面）
const SPEC_NAME = 'placement-spec.json';
// 就绪标记（内容 = 版本串:tar sha256；临时文件 + rename 原子写）
const READY_NAME = '.ready';
const READY_TMP_SUFFIX = '.tmp';
// 解包临时子目录前缀（冷启清暂存；就绪前残留一律按半成品清）
const UNPACK_TMP_PREFIX = '.npm-unpack-';
// npm 文件集件名与顶层目录（冻结 tar 顶层只有 npm/）
const TAR_FILE_NAME = 'npm-fileset.tar.gz';
const NPM_DIR_NAME = 'npm';
// npm 版本期望（§3.5 判据 3；读 npm/package.json 比对，不执行 npm CLI）
const NPM_VERSION = '11.19.1';
// 关键件（§3.5 判据 3/6；快路径只验这四项 + 版本，不全扫 1926 件）
const NPM_KEY_FILES = ['npm/package.json', 'npm/bin/npm-cli.js', 'npm/lib/cli.js'];
const NPM_KEY_DIRS = ['npm/node_modules'];
// §3.5 判据 4 的两条绝对路径读数（禁包名 specifier）
const NPM_CLI_REL = 'npm/bin/npm-cli.js';
const NPM_TAR_PKG_REL = 'npm/node_modules/tar/package.json';
// 旧版本目录判据（只匹配 node-X.Y.Z-gN；node-data 等门 1 遗留不匹配，禁误删）
const VERSION_DIR_PATTERN = /^node-\d+\.\d+\.\d+-g\d+$/;
const RUNTIME_VERSION_PATTERN = /^\d+\.\d+\.\d+-g\d+$/;
// tar 块尺寸与解包让出事件循环的粒度（1926 件解包期间 status 仍可应答，§3.1）
const TAR_BLOCK = 512;
const YIELD_EVERY_ENTRIES = 64;
// 文件权限恢复口径（只按可执行位归两档，§3.5 判据 6）
const MODE_FILE_DEFAULT = 0o644;
const MODE_FILE_EXEC = 0o755;
const MODE_DIR_DEFAULT = 0o755;

// ── 小工具 ──

function errorText(e) {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    return String(e);
  } catch (err) {
    return 'unknown-error';
  }
}

function isZeroBlock(block) {
  for (let i = 0; i < block.length; i++) {
    if (block[i] !== 0) {
      return false;
    }
  }
  return true;
}

// 字段读取：到首个 NUL 为止（tar 头字段以 NUL 补齐；整字段无 NUL 时取满长度）
function readField(buffer, offset, length) {
  const slice = buffer.subarray(offset, offset + length);
  const nul = slice.indexOf(0);
  const body = nul >= 0 ? slice.subarray(0, nul) : slice;
  return body.toString('utf8');
}

// 八进制字段：空白/NUL 容忍；非八进制字符一律判损坏（禁静默当 0）
function parseOctalField(header, offset, length, label, entryNo) {
  const raw = header.subarray(offset, offset + length).toString('latin1').replace(/[\0 ]+$/g, '');
  if (raw === '') {
    return 0;
  }
  if (!/^[0-7]+$/.test(raw)) {
    throw entryError(entryNo, label + ' 不是合法八进制');
  }
  const value = parseInt(raw, 8);
  if (!Number.isFinite(value) || value < 0 || value > Number.MAX_SAFE_INTEGER) {
    throw entryError(entryNo, label + ' 超出可解析范围');
  }
  return value;
}

function entryError(entryNo, detail) {
  return new Error('tar 第 ' + entryNo + ' 条目解析失败，' + detail);
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function yieldToLoop() {
  return new Promise((resolve) => {
    setImmediate(resolve);
  });
}

function unlinkQuiet(target) {
  try {
    fs.unlinkSync(target);
  } catch (e) {
    // ENOENT = 目标态；其他错误交给上层（清理失败不该掩盖主错误）
  }
}

// 递归删树（容错：不存在 = 目标态；失败不抛，交由上层如实报告）
function removeTreeQuiet(target) {
  if (!target) {
    return;
  }
  try {
    fs.rmSync(target, { recursive: true, force: true, maxRetries: 2 });
  } catch (e) {
    // 清理失败：保持现场，上层错误信息里能看见残留
  }
}

// ── placement-spec 读入与落位自检 ──

// 读落位说明（缺失/结构不符抛错——调用方转 failed + prepareError，不静默）
function readPlacementSpec(homeDir) {
  const raw = fs.readFileSync(path.join(homeDir, SPEC_NAME), 'utf8');
  const spec = JSON.parse(raw);
  if (spec === null || typeof spec !== 'object' || !Array.isArray(spec.files)) {
    throw new Error('placement-spec 结构不符');
  }
  return spec;
}

// 字节落位自检：逐件在场 + 尺寸与 spec 声明一致（尺寸单源 = 宿主常量，Node 侧不自持期望值）
// 返回 {ok, error}；错误串含哪一件、哪个环节先失败（stat 缺失 vs 尺寸不符）
function checkPlacement(homeDir, spec) {
  for (let i = 0; i < spec.files.length; i++) {
    const item = spec.files[i];
    const target = path.join(homeDir, item.name);
    let stat;
    try {
      stat = fs.statSync(target);
    } catch (e) {
      return { ok: false, error: '落位件缺失 ' + item.name + '（' + (e.code || 'stat 失败') + '）' };
    }
    if (stat.size !== item.bytes) {
      return {
        ok: false,
        error: '落位件尺寸不符 ' + item.name + '，实际 ' + stat.size + ' B，期望 ' + item.bytes + ' B'
      };
    }
  }
  return { ok: true, error: '' };
}

// 准备所需的扩展字段（runtimeVersion / npmEntries / tar 期望 sha256）
function validateSpecForPrepare(spec) {
  if (typeof spec.runtimeVersion !== 'string' || !RUNTIME_VERSION_PATTERN.test(spec.runtimeVersion)) {
    return { ok: false, error: 'placement-spec 缺少合法 runtimeVersion' };
  }
  const counts = spec.npmEntries;
  if (counts === null || typeof counts !== 'object'
    || !Number.isInteger(counts.files) || counts.files < 0
    || !Number.isInteger(counts.dirs) || counts.dirs < 0) {
    return { ok: false, error: 'placement-spec 缺少 npmEntries 条目计数' };
  }
  const tarItem = spec.files.find((item) => item.name === TAR_FILE_NAME);
  if (tarItem === undefined || typeof tarItem.sha256 !== 'string'
    || !/^[0-9a-f]{64}$/.test(tarItem.sha256)) {
    return { ok: false, error: 'placement-spec 缺少 ' + TAR_FILE_NAME + ' 期望 sha256' };
  }
  return { ok: true, error: '', tarSha256: tarItem.sha256 };
}

// ── tar 解析（最小实现；安全判据见文件头注释）──

// 路径闸：name 与 prefix/name 拼接结果都走这一套（禁绝对路径 / .. / 空段 / 反斜杠）
function assertEntryPath(relPath, entryNo, typeFlag) {
  if (relPath === '') {
    throw entryError(entryNo, '路径为空');
  }
  if (relPath.charAt(0) === '/') {
    throw entryError(entryNo, '路径为绝对路径 ' + relPath);
  }
  if (/^[A-Za-z]:/.test(relPath)) {
    throw entryError(entryNo, '路径带盘符前缀 ' + relPath);
  }
  if (relPath.indexOf('\\') >= 0) {
    throw entryError(entryNo, '路径含反斜杠 ' + relPath);
  }
  if (relPath.indexOf('\0') >= 0) {
    throw entryError(entryNo, '路径含 NUL 字符');
  }
  let body = relPath;
  if (typeFlag === '5') {
    if (body.endsWith('/')) {
      body = body.slice(0, -1);
    }
  } else if (body.endsWith('/')) {
    throw entryError(entryNo, '文件条目路径以斜杠结尾 ' + relPath);
  }
  if (body === '') {
    throw entryError(entryNo, '路径为空');
  }
  const segments = body.split('/');
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    if (segment === '') {
      throw entryError(entryNo, '路径含空段（连续斜杠）' + relPath);
    }
    if (segment === '.' || segment === '..') {
      throw entryError(entryNo, '路径段为 ' + segment + ' ' + relPath);
    }
    if (segment.length > 255) {
      throw entryError(entryNo, '路径段过长 ' + relPath);
    }
  }
  return body;
}

// 头解析：magic 双格式、校验和、typeflag 白名单、prefix 拼接（POSIX 与老 GNU 同口径，
// 冻结包 prefix 区全零——非零即按 prefix 处理并过同一路径闸）
function parseTarHeader(header, entryNo) {
  const magic = header.subarray(257, 265).toString('latin1');
  if (magic !== 'ustar\u0000' + '00' && magic !== 'ustar  \u0000') {
    throw entryError(entryNo, '头 magic 不受支持（' + JSON.stringify(magic) + '）');
  }
  // 校验和（无符号口径，冻结包 2384 头全过；不一致 = 错位或损坏，禁继续）
  const stored = parseOctalField(header, 148, 8, '校验和', entryNo);
  let computed = 0;
  for (let i = 0; i < TAR_BLOCK; i++) {
    computed += (i >= 148 && i < 156) ? 0x20 : header[i];
  }
  if (computed !== stored) {
    throw entryError(entryNo, '头校验和不符（实际 ' + computed + '，声明 ' + stored + '）');
  }
  const name = readField(header, 0, 100);
  if (name === '') {
    throw entryError(entryNo, '文件名字段为空');
  }
  const mode = parseOctalField(header, 100, 8, 'mode', entryNo);
  const size = parseOctalField(header, 124, 12, 'size', entryNo);
  const typeFlag = String.fromCharCode(header[156]);
  if (typeFlag === '1' || typeFlag === '2') {
    throw entryError(entryNo, '拒绝 hardlink/symlink 头（typeflag ' + typeFlag + '）' + name);
  }
  if (typeFlag === 'L' || typeFlag === 'K') {
    throw entryError(entryNo, '拒绝 GNU 长名头（typeflag ' + typeFlag + '）' + name);
  }
  if (typeFlag === 'x' || typeFlag === 'g') {
    throw entryError(entryNo, '拒绝 PAX 扩展头（typeflag ' + typeFlag + '）' + name);
  }
  if (typeFlag === 'S') {
    throw entryError(entryNo, '拒绝 sparse 头（typeflag S）' + name);
  }
  if (typeFlag !== '0' && typeFlag !== '5') {
    throw entryError(entryNo, 'typeflag 不在白名单（' + JSON.stringify(typeFlag) + '）' + name);
  }
  if (typeFlag === '5' && size !== 0) {
    throw entryError(entryNo, '目录条目 size 非零 ' + name);
  }
  if ((mode & 0o7777) !== mode) {
    throw entryError(entryNo, 'mode 越界 ' + name);
  }
  let relPath = name;
  const prefixRaw = header.subarray(345, 500);
  if (!isZeroBlock(prefixRaw)) {
    const prefix = readField(header, 345, 155);
    if (prefix === '') {
      throw entryError(entryNo, 'prefix 区非零但不可解析 ' + name);
    }
    relPath = prefix + '/' + name;
  }
  const safePath = assertEntryPath(relPath, entryNo, typeFlag);
  return {
    path: safePath,
    mode: mode & 0o7777,
    size: size,
    type: typeFlag === '5' ? 'dir' : 'file'
  };
}

// 条目清单（golden 生成与全量比对共用；只解析、不落盘）
function listTarEntries(tarBuffer) {
  const tar = tarBuffer;
  const entries = [];
  let offset = 0;
  let sawEnd = false;
  while (offset + TAR_BLOCK <= tar.length) {
    const header = tar.subarray(offset, offset + TAR_BLOCK);
    if (isZeroBlock(header)) {
      if (!isZeroBlock(tar.subarray(offset))) {
        throw entryError(entries.length + 1, '归档结束零块后仍有非零数据');
      }
      sawEnd = true;
      break;
    }
    const entryNo = entries.length + 1;
    const meta = parseTarHeader(header, entryNo);
    const dataStart = offset + TAR_BLOCK;
    if (meta.size > tar.length - dataStart) {
      throw entryError(entryNo, '条目 size 越界（' + meta.size + ' B）' + meta.path);
    }
    const data = tar.subarray(dataStart, dataStart + meta.size);
    entries.push({
      path: meta.path,
      type: meta.type,
      mode: meta.mode,
      size: meta.size,
      sha256: meta.type === 'file' ? sha256(data) : ''
    });
    offset = dataStart + Math.ceil(meta.size / TAR_BLOCK) * TAR_BLOCK;
  }
  if (!sawEnd) {
    throw new Error('tar 缺少归档结束零块（可能被截断）');
  }
  return entries;
}

// ── 解包（临时目录内逐件写 + 读回 sha256 全验）──

function modeForEntry(meta) {
  if (meta.type === 'dir') {
    return MODE_DIR_DEFAULT;
  }
  return (meta.mode & 0o111) !== 0 ? MODE_FILE_EXEC : MODE_FILE_DEFAULT;
}

function applyMode(absPath, mode) {
  try {
    fs.chmodSync(absPath, mode);
  } catch (e) {
    // Windows 无 POSIX 位（本机只验不抛错）；真机失败由调用方统计（不算解包失败但如实报）
    if (process.platform !== 'win32') {
      throw e;
    }
  }
}

// 解包本体：期望条目计数（spec.npmEntries 单源）逐类守卫，超限即停（防无界解包）；
// 分两遍——先逐件落盘，再逐件读回比对 sha256（设备侧期望 = 已过 sha 校验的 tar 条目内容，
// §3.5 判据 2）。两遍分离是实测结论：Windows 上写后立刻读同一件慢一个数量级，分开快约
// 8 倍；单遍内的顺序语义不变（全验仍在 rename 之前完成）
async function extractTarBuffer(tarBuffer, destRoot, options) {
  const opts = options || {};
  const expected = opts.expectedCounts || null;
  if (!Buffer.isBuffer(tarBuffer)) {
    throw new Error('解包输入不是 Buffer');
  }
  fs.mkdirSync(destRoot, { recursive: true });
  const rootAbs = path.resolve(destRoot);
  const seen = new Set();
  const written = [];
  let offset = 0;
  let entryCount = 0;
  let fileCount = 0;
  let dirCount = 0;
  let diskBytes = 0;
  let sawEnd = false;
  // 第一遍：解析 + 落盘（条目 sha256 记为其次遍期望值）
  while (offset + TAR_BLOCK <= tarBuffer.length) {
    const header = tarBuffer.subarray(offset, offset + TAR_BLOCK);
    if (isZeroBlock(header)) {
      if (!isZeroBlock(tarBuffer.subarray(offset))) {
        throw entryError(entryCount + 1, '归档结束零块后仍有非零数据');
      }
      sawEnd = true;
      break;
    }
    entryCount++;
    const meta = parseTarHeader(header, entryCount);
    const dataStart = offset + TAR_BLOCK;
    if (meta.size > tarBuffer.length - dataStart) {
      throw entryError(entryCount, '条目 size 越界（' + meta.size + ' B）' + meta.path);
    }
    if (seen.has(meta.path)) {
      throw entryError(entryCount, '重复路径 ' + meta.path);
    }
    seen.add(meta.path);
    if (expected !== null) {
      if (meta.type === 'file' && fileCount + 1 > expected.files) {
        throw entryError(entryCount, '文件数超出期望（' + expected.files + '）' + meta.path);
      }
      if (meta.type === 'dir' && dirCount + 1 > expected.dirs) {
        throw entryError(entryCount, '目录数超出期望（' + expected.dirs + '）' + meta.path);
      }
    }
    const absPath = path.join(rootAbs, meta.path);
    const absResolved = path.resolve(absPath);
    if (absResolved !== rootAbs && !absResolved.startsWith(rootAbs + path.sep)) {
      throw entryError(entryCount, '解包目标越出根目录 ' + meta.path);
    }
    if (meta.type === 'dir') {
      fs.mkdirSync(absResolved, { recursive: true });
      applyMode(absResolved, modeForEntry(meta));
      dirCount++;
    } else {
      fs.mkdirSync(path.dirname(absResolved), { recursive: true });
      const data = tarBuffer.subarray(dataStart, dataStart + meta.size);
      fs.writeFileSync(absResolved, data);
      applyMode(absResolved, modeForEntry(meta));
      written.push({ path: meta.path, absPath: absResolved, size: meta.size, sha256: sha256(data) });
      fileCount++;
      diskBytes += meta.size;
    }
    offset = dataStart + Math.ceil(meta.size / TAR_BLOCK) * TAR_BLOCK;
    if (entryCount % YIELD_EVERY_ENTRIES === 0) {
      await yieldToLoop();
    }
  }
  if (!sawEnd) {
    throw new Error('tar 缺少归档结束零块（可能被截断）');
  }
  // 第二遍：逐件读回全验（尺寸 + sha256；禁只验哨兵）
  for (let i = 0; i < written.length; i++) {
    const record = written[i];
    const back = fs.readFileSync(record.absPath);
    if (back.length !== record.size) {
      throw new Error('tar 第 ' + (i + 1) + ' 个文件落盘尺寸不符（' + back.length + '/'
        + record.size + ' B）' + record.path);
    }
    if (sha256(back) !== record.sha256) {
      throw new Error('tar 第 ' + (i + 1) + ' 个文件落盘 sha256 不符 ' + record.path);
    }
    if ((i + 1) % YIELD_EVERY_ENTRIES === 0) {
      await yieldToLoop();
    }
  }
  if (expected !== null) {
    if (fileCount !== expected.files || dirCount !== expected.dirs) {
      throw new Error('解包条目数不符，实际 ' + fileCount + ' 文件 / ' + dirCount
        + ' 目录，期望 ' + expected.files + ' / ' + expected.dirs);
    }
  }
  return {
    entries: entryCount,
    files: fileCount,
    dirs: dirCount,
    diskBytes: diskBytes
  };
}

// ── npm 树校验（关键件 + 版本 + Node 可读；§3.5 判据 3/4）──

// 单件探针：如实记录 exists/stat/read 哪一步先失败（§3.5 判据 4 的取证要求）
function probeFile(root, relPath) {
  const absPath = path.join(root, relPath);
  if (!fs.existsSync(absPath)) {
    return { ok: false, step: 'exists', detail: relPath + ' 不存在' };
  }
  let stat;
  try {
    stat = fs.statSync(absPath);
  } catch (e) {
    return { ok: false, step: 'stat', detail: relPath + ' stat 失败（' + errorText(e) + '）' };
  }
  if (!stat.isFile()) {
    return { ok: false, step: 'stat', detail: relPath + ' 不是普通文件' };
  }
  if (stat.size === 0) {
    return { ok: false, step: 'read', detail: relPath + ' 为空文件' };
  }
  return { ok: true, step: 'ok', detail: '', absPath: absPath };
}

function probeDir(root, relPath) {
  const absPath = path.join(root, relPath);
  if (!fs.existsSync(absPath)) {
    return { ok: false, step: 'exists', detail: relPath + ' 不存在' };
  }
  let stat;
  try {
    stat = fs.statSync(absPath);
  } catch (e) {
    return { ok: false, step: 'stat', detail: relPath + ' stat 失败（' + errorText(e) + '）' };
  }
  if (!stat.isDirectory()) {
    return { ok: false, step: 'stat', detail: relPath + ' 不是目录' };
  }
  return { ok: true, step: 'ok', detail: '', absPath: absPath };
}

// 关键件与版本读数（快路径只做这一段；全验路径同样以它收口）
function inspectNpmTree(root) {
  for (let i = 0; i < NPM_KEY_FILES.length; i++) {
    const probe = probeFile(root, NPM_KEY_FILES[i]);
    if (!probe.ok) {
      return { ok: false, error: 'npm 关键件不可用，' + probe.step + ' 失败：' + probe.detail };
    }
  }
  for (let i = 0; i < NPM_KEY_DIRS.length; i++) {
    const probe = probeDir(root, NPM_KEY_DIRS[i]);
    if (!probe.ok) {
      return { ok: false, error: 'npm 关键目录不可用，' + probe.step + ' 失败：' + probe.detail };
    }
  }
  let pkg;
  try {
    pkg = JSON.parse(fs.readFileSync(path.join(root, 'npm/package.json'), 'utf8'));
  } catch (e) {
    return { ok: false, error: 'npm 关键件读取失败（package.json ' + errorText(e) + '）' };
  }
  if (pkg === null || typeof pkg !== 'object' || pkg.version !== NPM_VERSION) {
    return {
      ok: false,
      error: 'npm 版本不符，实际 ' + (pkg && pkg.version ? pkg.version : '未知') + '，期望 ' + NPM_VERSION
    };
  }
  // §3.5 判据 4：绝对路径读数（禁包名 specifier）；失败如实记录 resolve/require 环节
  try {
    const resolved = require.resolve(path.join(root, NPM_CLI_REL));
    if (typeof resolved !== 'string' || resolved === '') {
      return { ok: false, error: 'npm 关键件 resolve 失败：' + NPM_CLI_REL };
    }
  } catch (e) {
    return { ok: false, error: 'npm 关键件 resolve 失败（' + errorText(e) + '）' };
  }
  try {
    const tarPkgPath = path.join(root, NPM_TAR_PKG_REL);
    const tarPkg = require(tarPkgPath);
    const cacheKey = require.resolve(tarPkgPath);
    delete require.cache[cacheKey];
    if (tarPkg === null || typeof tarPkg !== 'object' || typeof tarPkg.name !== 'string') {
      return { ok: false, error: 'npm 内置包元数据异常：' + NPM_TAR_PKG_REL };
    }
  } catch (e) {
    return { ok: false, error: 'npm 内置包 require 失败（' + errorText(e) + '）' };
  }
  return { ok: true, error: '', npmVersion: pkg.version };
}

// ── .ready 与旧版本清扫 ──

function readyPath(homeDir) {
  return path.join(homeDir, READY_NAME);
}

function readReadyContent(homeDir) {
  try {
    return fs.readFileSync(readyPath(homeDir), 'utf8').trim();
  } catch (e) {
    return '';
  }
}

// 原子写 .ready（临时文件 + rename；半写不会以 .ready 名在场 = 不会假就绪）
function writeReadyAtomic(homeDir, content) {
  const tmpPath = readyPath(homeDir) + READY_TMP_SUFFIX;
  fs.writeFileSync(tmpPath, content);
  fs.renameSync(tmpPath, readyPath(homeDir));
}

// 快路径：.ready 版本串 + 关键件 + npm 版本（不全扫 1926 件，§3.1）
function checkReadyFast(homeDir, expectedReady) {
  if (readReadyContent(homeDir) !== expectedReady) {
    return { ok: false, error: '.ready 内容与期望不符' };
  }
  const inspected = inspectNpmTree(homeDir);
  if (!inspected.ok) {
    return { ok: false, error: inspected.error };
  }
  return { ok: true, error: '', npmVersion: inspected.npmVersion };
}

// 旧版本目录清扫（只匹配 node-X.Y.Z-gN 且非当前版本；node-data 等不匹配绝不误删）
function sweepOldVersions(baseDir, currentDirName) {
  const result = { removed: [], kept: [], skipped: [], failed: [] };
  if (!baseDir || !VERSION_DIR_PATTERN.test(currentDirName)) {
    return result;
  }
  let names;
  try {
    names = fs.readdirSync(baseDir);
  } catch (e) {
    return result;
  }
  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    if (!VERSION_DIR_PATTERN.test(name)) {
      continue;
    }
    if (name === currentDirName) {
      result.kept.push(name);
      continue;
    }
    const abs = path.join(baseDir, name);
    try {
      const stat = fs.lstatSync(abs);
      if (!stat.isDirectory() || stat.isSymbolicLink()) {
        result.skipped.push(name);
        continue;
      }
      fs.rmSync(abs, { recursive: true, force: true, maxRetries: 2 });
      result.removed.push(name);
    } catch (e) {
      result.failed.push({ name: name, error: errorText(e) });
    }
  }
  return result;
}

// ── 准备流程（单飞一次；状态经 snapshot 供 status 读）──

function readablePrepareError(e) {
  const detail = errorText(e);
  return detail === '' ? '准备失败（无错误详情）' : detail;
}

function snapshotOf(state) {
  return {
    prepare: state.prepare,
    prepareError: state.prepareError,
    npmVersion: state.npmVersion,
    prepareStats: state.stats
  };
}

// 准备本体：先快路径，再全量解包；任何失败 → failed + prepareError，且不留 .ready / 半成品
async function runPrepare(homeDir, spec, state) {
  const startedAt = Date.now();
  const rssBefore = process.memoryUsage().rss;
  let tarCounts = null;
  try {
    const specCheck = validateSpecForPrepare(spec);
    if (!specCheck.ok) {
      throw new Error(specCheck.error);
    }
    const expectedReady = spec.runtimeVersion + ':' + specCheck.tarSha256;
    const tarPath = path.join(homeDir, TAR_FILE_NAME);
    // 落盘 tar 的 sha256 再对账一次（ArkTS 侧已对过；此处防交付后字节被替换/截断）
    const diskTarSha = sha256(fs.readFileSync(tarPath));
    if (diskTarSha !== specCheck.tarSha256) {
      throw new Error('落盘 ' + TAR_FILE_NAME + ' sha256 不符，期望 ' + specCheck.tarSha256
        + '，实际 ' + diskTarSha);
    }
    // 冷启清暂存（快路径也清：崩溃残留在就绪后同样不留）
    removeStaleUnpackDirs(homeDir);
    // 1) 快路径：命中 .ready 只校验版本串、关键件与 npm 版本
    const fast = checkReadyFast(homeDir, expectedReady);
    if (fast.ok) {
      const rssAfterFast = process.memoryUsage().rss;
      state.npmVersion = fast.npmVersion;
      state.stats = {
        elapsedMs: Date.now() - startedAt,
        rssBeforeBytes: rssBefore,
        rssAfterBytes: rssAfterFast,
        rssDeltaBytes: rssAfterFast - rssBefore,
        diskBytes: 0,
        files: 0,
        dirs: 0,
        fastPath: true
      };
      const sweep = sweepOldVersions(path.dirname(homeDir), path.basename(homeDir));
      state.sweep = sweep;
      state.prepare = 'ready';
      return snapshotOf(state);
    }
    // 2) 全量解包：先清 .ready 与上一轮半成品（失败不会留下可被误读的就绪标记）
    unlinkQuiet(readyPath(homeDir));
    unlinkQuiet(readyPath(homeDir) + READY_TMP_SUFFIX);
    removeTreeQuiet(path.join(homeDir, NPM_DIR_NAME));
    // 3) 临时子目录解包 → 全验 → rename 就位
    const tmpDir = path.join(homeDir, UNPACK_TMP_PREFIX + process.pid + '-'
      + crypto.randomBytes(4).toString('hex'));
    let moved = false;
    try {
      const tar = zlib.gunzipSync(fs.readFileSync(tarPath));
      tarCounts = await extractTarBuffer(tar, tmpDir, { expectedCounts: spec.npmEntries });
      const tmpInspect = inspectNpmTree(tmpDir);
      if (!tmpInspect.ok) {
        throw new Error('临时目录校验失败，' + tmpInspect.error);
      }
      fs.renameSync(path.join(tmpDir, NPM_DIR_NAME), path.join(homeDir, NPM_DIR_NAME));
      moved = true;
      // 终态复核：按最终 HOME 绝对路径重跑关键件与 require.resolve/require（§3.5 判据 4）
      const finalInspect = inspectNpmTree(homeDir);
      if (!finalInspect.ok) {
        throw new Error('就位后校验失败，' + finalInspect.error);
      }
      writeReadyAtomic(homeDir, expectedReady);
      const sweep = sweepOldVersions(path.dirname(homeDir), path.basename(homeDir));
      state.npmVersion = finalInspect.npmVersion;
      state.stats = {
        elapsedMs: Date.now() - startedAt,
        rssBeforeBytes: rssBefore,
        rssAfterBytes: process.memoryUsage().rss,
        rssDeltaBytes: process.memoryUsage().rss - rssBefore,
        diskBytes: tarCounts.diskBytes,
        files: tarCounts.files,
        dirs: tarCounts.dirs,
        fastPath: false
      };
      state.sweep = sweep;
      state.prepare = 'ready';
      return snapshotOf(state);
    } catch (e) {
      if (moved) {
        removeTreeQuiet(path.join(homeDir, NPM_DIR_NAME));
      }
      throw e;
    } finally {
      removeTreeQuiet(tmpDir);
    }
  } catch (e) {
    state.prepare = 'failed';
    state.prepareError = readablePrepareError(e);
    const rssAfterFail = process.memoryUsage().rss;
    state.stats = {
      elapsedMs: Date.now() - startedAt,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfterFail,
      rssDeltaBytes: rssAfterFail - rssBefore,
      diskBytes: tarCounts !== null ? tarCounts.diskBytes : 0,
      files: tarCounts !== null ? tarCounts.files : 0,
      dirs: tarCounts !== null ? tarCounts.dirs : 0,
      fastPath: false
    };
    return snapshotOf(state);
  }
}

// 冷启清暂存：解包临时子目录（就绪前残留一律按半成品清）
function removeStaleUnpackDirs(homeDir) {
  let names;
  try {
    names = fs.readdirSync(homeDir);
  } catch (e) {
    return;
  }
  for (let i = 0; i < names.length; i++) {
    if (names[i].startsWith(UNPACK_TMP_PREFIX)) {
      removeTreeQuiet(path.join(homeDir, names[i]));
    }
  }
}

// 准备入口（单飞：本进程只调用一次；返回 handle = 可读 snapshot + 完成 promise）
function beginPrepare(homeDir) {
  const state = {
    prepare: 'running',
    prepareError: '',
    npmVersion: '',
    stats: null,
    sweep: null
  };
  const handle = {
    spec: null,
    snapshot: () => snapshotOf(state),
    promise: null
  };
  let spec = null;
  try {
    spec = readPlacementSpec(homeDir);
  } catch (e) {
    const detail = e && e.code ? e.code : (e && e.message ? e.message : '未知错误');
    state.prepare = 'failed';
    state.prepareError = 'placement-spec 读取失败（' + detail + '）';
    state.stats = {
      elapsedMs: 0,
      rssBeforeBytes: process.memoryUsage().rss,
      rssAfterBytes: process.memoryUsage().rss,
      rssDeltaBytes: 0,
      diskBytes: 0,
      files: 0,
      dirs: 0,
      fastPath: false
    };
    handle.promise = Promise.resolve(snapshotOf(state));
    return handle;
  }
  handle.spec = spec;
  const placement = checkPlacement(homeDir, spec);
  if (!placement.ok) {
    state.prepare = 'failed';
    state.prepareError = placement.error;
    state.stats = {
      elapsedMs: 0,
      rssBeforeBytes: process.memoryUsage().rss,
      rssAfterBytes: process.memoryUsage().rss,
      rssDeltaBytes: 0,
      diskBytes: 0,
      files: 0,
      dirs: 0,
      fastPath: false
    };
    handle.promise = Promise.resolve(snapshotOf(state));
    return handle;
  }
  handle.promise = runPrepare(homeDir, spec, state).catch((e) => {
    // 兜底：runPrepare 自身已收口，这里只防未预期异常吞掉就绪态
    state.prepare = 'failed';
    state.prepareError = readablePrepareError(e);
    return snapshotOf(state);
  });
  return handle;
}

// 一次性准备（测试与诊断入口）：await 到终态快照
function prepareRuntime(homeDir) {
  return beginPrepare(homeDir).promise;
}

module.exports = {
  beginPrepare,
  prepareRuntime,
  checkPlacement,
  readPlacementSpec,
  listTarEntries,
  extractTarBuffer,
  inspectNpmTree,
  checkReadyFast,
  sweepOldVersions,
  removeStaleUnpackDirs,
  SPEC_NAME,
  READY_NAME,
  UNPACK_TMP_PREFIX,
  TAR_FILE_NAME,
  NPM_VERSION,
  NPM_KEY_FILES,
  NPM_KEY_DIRS
};
