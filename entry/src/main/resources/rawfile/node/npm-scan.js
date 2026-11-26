// npm 装后扫描与回滚（2026-11-24 鸿蒙 Node 运行时门 3 U3 S1 拆分笔，任务书-鸿蒙Node运行时门3
// U3-binrunner-20261124 §5 S1）：从 npm-worker.js 原样迁出的纯 JS 边界守卫域——node_modules
// 树遍历、装前快照、增量二进制与 .wasm 检出、整根与逐文件回滚、全树清扫、无 spec 幂等重装、
// 命中后的统一处置（回滚 → 修复 → 复扫）。方法体原样搬迁，零逻辑改写。
// · 分层（模块环零，坑50）：本件是 npm 安装域最下层，只被 npm-install-core.js 引，不 require
//   上层件；无 spec 幂等重装要用的「install 参数钉死集 + 日志捕获」单源在 npm-install-core，
//   由其在载入尾经 setNpmPrimitives 注入——本件不抄第二份参数表，也不在顶层读上层绑定。
// · 回滚范围（Y0 修正）：**只消除本次 install 引入的变化**——before 快照里完全不存在的包根
//   整根删；既有包根内只逐路径删本次新增的条目（新增文件与新增子目录都算增量——walk 会把
//   目录也记进条目集，对目录必须整删而非 unlink，否则 EISDIR 会造出假失败），绝不整根 rm
//   （旧实现把「既有包根内出现新增文件」的根也收进回滚集，升级既有包命中二进制时会把既有包
//   连根删掉，而 package.json 恢复成仍依赖它 → 盘上/清单矛盾）。既有包根被改动过时，按恢复
//   后的两清单跑一次无 spec 的幂等重装（同一套钉死参数）把包恢复到安装前版本；随后复扫，
//   仍命中或删除/修复失败一律进回执（violations ≤10 条 + cleanupNote），禁静默。rolledBack =
//   回滚完全成功且复扫无残留。
// · 纯 JS 策略：任何黑名单扩展名文件都不合法（.node/.so/.dll/.pyd/.dylib/.a/.o/.exe，含
//   .so.数字变体），故全树清扫直接删；.wasm 不拒装、回执另附 jitless 提示。
// · 符号链接一律不下降（防逃逸与循环；目录判定同时看 isDirectory 与 isSymbolicLink）。
// · bin 台账（门 3 U3 S3）：装后扫各包 package.json 的 `bin` 字段合并写 prefix 根
//   bin-ledger.json（原子写、装前不清账、同名后装覆盖、成功 install 才写）——见文件尾同名节。
// · 本件被 npm-worker.js 间接 require（设备侧 HOME 内相对解析）；非 worker 环境零副作用
//   （只导出纯函数，不启动监听、不写文件）。
'use strict';

const fs = require('node:fs');
const path = require('node:path');

// 回执里问题项清单的条数上限（命中文件 / 未处理项共用）
const VIOLATION_REPORT_MAX = 10;
// 二进制扩展黑名单（对齐 Python 自装包先例，变更记录 2180 节）；.so.数字变体单独匹配
const BINARY_EXT_RE = /\.(node|so|dll|pyd|dylib|a|o|exe)$/i;
const BINARY_SO_VERSIONED_RE = /\.so(\.\d+)+$/i;
const WASM_EXT_RE = /\.wasm$/i;

// npm 执行面（参数钉死集 + 日志捕获；单源在 npm-install-core，本件是下层不反向 require）
let npmPrimitives = null;

function setNpmPrimitives(primitives) {
  npmPrimitives = primitives;
}

// 小工具（本件是最下层，公共小件落这里，上层直接引）
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

// ── 装后扫描与回滚（纯 JS 边界；符号链接不下降——防逃逸与循环）──

function walkNodeModules(prefix, collector) {
  const root = path.join(prefix, 'node_modules');
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop();
    let names = [];
    try {
      names = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      continue; // node_modules 尚不存在 = 空集
    }
    for (const entry of names) {
      const abs = path.join(dir, entry.name);
      collector.add(path.relative(root, abs));
      if (entry.isDirectory() && !entry.isSymbolicLink()) {
        stack.push(abs);
      }
    }
  }
}

function readTextIfExists(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    return null;
  }
}

// install 前快照：node_modules 条目集 + 两清单原文（回滚的恢复目标）
function snapshotInstallState(prefix) {
  const entries = new Set();
  walkNodeModules(prefix, entries);
  return {
    entries: entries,
    packageJson: readTextIfExists(path.join(prefix, 'package.json')),
    lockfile: readTextIfExists(path.join(prefix, 'package-lock.json'))
  };
}

function isBinaryFileName(name) {
  return BINARY_EXT_RE.test(name) || BINARY_SO_VERSIONED_RE.test(name);
}

// 增量条目所属包根（相对 node_modules 根的第一级；@scope 占一级）：'@scope/pkg/x.js'
// → '@scope/pkg'，'evil/sub/w.wasm' → 'evil'
function packageRootOf(rel) {
  const segments = rel.split(/[\\/]+/);
  if (segments.length > 1 && segments[0].startsWith('@')) {
    return path.join(segments[0], segments[1]);
  }
  return segments[0];
}

// 装后安全检查：新增文件里找二进制黑名单与 .wasm；同时区分「新增包根」与「既有包根内增量」。
// 回滚集口径（Y0）：addedRoots 只收 before 快照里完全不存在的包根（可整根删）；既有包根内出现
// 的新文件只进 addedFiles（逐文件删，整根删会毁掉既有包），所属根进 touchedRoots（触发修复重装）。
function checkInstallSafety(prefix, before) {
  const after = new Set();
  walkNodeModules(prefix, after);
  const violations = [];
  const wasmFiles = [];
  const addedRoots = new Set();
  const touchedRoots = new Set();
  const addedFiles = [];
  for (const rel of after) {
    if (before.entries.has(rel)) {
      continue;
    }
    const base = path.basename(rel);
    if (isBinaryFileName(base)) {
      violations.push(rel);
    }
    if (WASM_EXT_RE.test(base)) {
      wasmFiles.push(rel);
    }
    const root = packageRootOf(rel);
    if (before.entries.has(root)) {
      addedFiles.push(rel);
      touchedRoots.add(root);
    } else {
      addedRoots.add(root);
    }
  }
  return {
    violations: violations,
    wasmFiles: wasmFiles,
    addedRoots: Array.from(addedRoots),
    addedFiles: addedFiles,
    touchedRoots: Array.from(touchedRoots)
  };
}

// 全树二进制收集（只读；相对 node_modules 根的路径）。纯 JS 策略下任何黑名单扩展名文件都
// 不合法，所以全树（不只增量）就是清扫与复扫的口径
function collectBinaryFiles(prefix) {
  const root = path.join(prefix, 'node_modules');
  const hits = [];
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop();
    let names = [];
    try {
      names = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      continue; // node_modules 尚不存在 = 空集
    }
    for (const entry of names) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory() && !entry.isSymbolicLink()) {
        stack.push(abs);
        continue;
      }
      if (isBinaryFileName(entry.name)) {
        hits.push(path.relative(root, abs));
      }
    }
  }
  return hits;
}

// 全树二进制清扫（逐文件删；返回清除项与失败项——失败如实带回，禁静默）
function sweepBinaryFiles(prefix) {
  const nodeModulesDir = path.join(prefix, 'node_modules');
  const removed = [];
  const failed = [];
  for (const rel of collectBinaryFiles(prefix)) {
    try {
      fs.unlinkSync(path.join(nodeModulesDir, rel));
      removed.push(rel);
    } catch (e) {
      failed.push(rel);
    }
  }
  return { removed: removed, failed: failed };
}

function restoreTextFile(file, beforeText) {
  if (beforeText === null) {
    try {
      fs.unlinkSync(file);
    } catch (e) {
      // 不存在 = 目标态
    }
    return;
  }
  fs.writeFileSync(file, beforeText);
}

// 回滚（Y0 修正版）：只消除本次 install 引入的变化——新增包根整根删、既有包根内逐文件删新增
// 项、两清单恢复 install 前快照。返回失败项（删除 / 恢复抛错一律如实带回，禁静默）
function applyRollback(prefix, before, safety) {
  const nodeModulesDir = path.join(prefix, 'node_modules');
  const failures = [];
  for (const relRoot of safety.addedRoots) {
    try {
      fs.rmSync(path.join(nodeModulesDir, relRoot), { recursive: true, force: true });
    } catch (e) {
      failures.push(relRoot + ' 没删掉');
    }
  }
  for (const rel of safety.addedFiles) {
    // 逐路径整删：既有包根内的增量既可能是文件、也可能是新增子目录（walk 连目录一起记账）。
    // 对目录用 unlinkSync 必抛 EISDIR → 被记成「没删掉」，rolledBack 误判 false、回执文案
    // 也跟着说谎；rmSync 递归 + force 对文件与目录同一写法，子项已被父目录带走时按 ENOENT 无视
    try {
      fs.rmSync(path.join(nodeModulesDir, rel), { recursive: true, force: true });
    } catch (e) {
      failures.push(rel + ' 没删掉');
    }
  }
  const manifests = [
    { file: path.join(prefix, 'package.json'), text: before.packageJson },
    { file: path.join(prefix, 'package-lock.json'), text: before.lockfile }
  ];
  for (const manifest of manifests) {
    try {
      restoreTextFile(manifest.file, manifest.text);
    } catch (e) {
      failures.push(path.basename(manifest.file) + ' 没恢复');
    }
  }
  return failures;
}

// 无 spec 幂等重装（回滚修复步）：按盘上（= 恢复后的）两清单把 node_modules 拉回安装前版本。
// 与正常轮同一套钉死参数（buildInstallArgv 单一来源，经 setNpmPrimitives 注入），只少了 specs 项
async function reinstallFromManifests(prefix, cacheDir, npmLibPath) {
  if (npmPrimitives === null) {
    return { ok: false, error: 'npm 参数面未注入，无法修复重装' };
  }
  const capture = npmPrimitives.createCapture();
  const savedArgv = process.argv.slice();
  try {
    const Npm = require(String(npmLibPath));
    process.argv = [process.execPath, 'npm'];
    const argv = npmPrimitives.buildArgv([], { prefix: prefix, cacheDir: cacheDir });
    const npm = new Npm({ stdout: capture.stdoutStream, stderr: capture.stderrStream, argv: argv });
    const loaded = await npm.load();
    if (loaded === null || typeof loaded !== 'object' || loaded.exec !== true
      || typeof loaded.command !== 'string' || loaded.command === '') {
      return { ok: false, error: 'npm load 未解析出可执行命令' };
    }
    await npm.exec(loaded.command, loaded.args);
    return { ok: true, error: '' };
  } catch (e) {
    return { ok: false, error: errorText(e) };
  } finally {
    process.argv = savedArgv;
  }
}

// 命中二进制后的统一处置（成功路与 npm 失败路共用）：回滚 → 幂等重装修复 → 复扫。
// 返回 rolledBack（全部成功且复扫无残留）/ failures（≤10，回执 violations 用）
async function rollbackAfterViolation(prefix, cacheDir, before, safety, npmLibPath) {
  const failures = applyRollback(prefix, before, safety);
  if (before.packageJson !== null) {
    const repaired = await reinstallFromManifests(prefix, cacheDir, npmLibPath);
    if (!repaired.ok) {
      failures.push('修复重装没成功，' + repaired.error);
    }
  }
  const remaining = collectBinaryFiles(prefix);
  if (remaining.length > 0) {
    const swept = sweepBinaryFiles(prefix);
    for (const rel of remaining) {
      if (swept.removed.indexOf(rel) < 0) {
        failures.push(rel + ' 复扫后仍在');
      }
    }
  }
  return {
    rolledBack: failures.length === 0,
    failures: failures.slice(0, VIOLATION_REPORT_MAX)
  };
}

// ── bin 台账（门 3 U3 S3，任务书 §5 S3）──
// 每次 install 成功后扫 node_modules 各包 package.json 的 `bin` 字段，合并进 prefix 根的
// bin-ledger.json（原子写：临时件 + rename）。台账不进 node_modules——回滚整根删包不会误删它；
// 装前不清账（既有包可能仍可用），已消失包的条目由读取侧（bin-runner）按入口存在性过滤。
// 条目 = { name, package, version, entry(相对 node_modules), cjs, replaced }；同名归属规则见
// pickBinCandidate（跨次安装 = 后装者胜；同批多个候选按扫描序，本就没有「后装」可言）
const BIN_LEDGER_FILE = 'bin-ledger.json';
const BIN_LEDGER_VERSION = 1;
// 单包 bin 条目上限（异常 manifest 不得撑爆台账；正常 CLI 包最多几条）
const BIN_PER_PACKAGE_MAX = 32;

// 包目录枚举（含嵌套 node_modules；@scope 下钻一层；符号链接不下降——与二进制扫描同口径）
function collectPackageDirs(nodeModulesDir) {
  const out = [];
  const stack = [{ abs: nodeModulesDir, rel: '' }];
  while (stack.length > 0) {
    const current = stack.pop();
    let names = [];
    try {
      names = fs.readdirSync(current.abs, { withFileTypes: true });
    } catch (e) {
      continue; // 目录不存在 = 空集
    }
    for (const entry of names) {
      if (!entry.isDirectory() || entry.isSymbolicLink()) {
        continue;
      }
      const abs = path.join(current.abs, entry.name);
      const rel = current.rel === '' ? entry.name : current.rel + '/' + entry.name;
      if (entry.name.startsWith('@')) {
        // scope 目录本身不是包，只再下钻一层
        let scopedNames = [];
        try {
          scopedNames = fs.readdirSync(abs, { withFileTypes: true });
        } catch (e) {
          continue;
        }
        for (const child of scopedNames) {
          if (!child.isDirectory() || child.isSymbolicLink()) {
            continue;
          }
          const childAbs = path.join(abs, child.name);
          const childRel = rel + '/' + child.name;
          out.push({ abs: childAbs, rel: childRel });
          stack.push({ abs: path.join(childAbs, 'node_modules'), rel: childRel + '/node_modules' });
        }
        continue;
      }
      out.push({ abs: abs, rel: rel });
      stack.push({ abs: path.join(abs, 'node_modules'), rel: rel + '/node_modules' });
    }
  }
  return out;
}

// package.json 读取（坏 JSON / 缺件回 null——不得让一个坏包毁掉整张台账）
function readPackageMeta(packageDir) {
  const text = readTextIfExists(path.join(packageDir, 'package.json'));
  if (text === null) {
    return null;
  }
  try {
    const meta = JSON.parse(text);
    return meta !== null && typeof meta === 'object' ? meta : null;
  } catch (e) {
    return null;
  }
}

// 包名 → 命令名（npm 口径：单字符串 bin 用包名，@scope/pkg 去 scope）
function commandNameOf(packageName) {
  if (packageName.startsWith('@')) {
    const slash = packageName.indexOf('/');
    return slash >= 0 ? packageName.slice(slash + 1) : packageName;
  }
  return packageName;
}

// bin 字段两形态（字符串 / 对象）→ [{ name, target }]（target 相对包目录）
function binTargetsOf(meta) {
  const out = [];
  const bin = meta.bin;
  if (typeof bin === 'string' && bin !== '') {
    const commandName = typeof meta.name === 'string' ? commandNameOf(meta.name) : '';
    if (commandName !== '') {
      out.push({ name: commandName, target: bin });
    }
  } else if (bin !== null && typeof bin === 'object') {
    for (const key of Object.keys(bin)) {
      if (key !== '' && typeof bin[key] === 'string' && bin[key] !== '') {
        out.push({ name: key, target: bin[key] });
      }
    }
  }
  return out.slice(0, BIN_PER_PACKAGE_MAX);
}

// 入口路径归一（去掉 ./ 前缀与反斜杠；越出包目录的条目直接丢——台账只记包内入口）
function normalizeBinTarget(target) {
  const normalized = String(target).replace(/\\/g, '/').replace(/^\.\//, '');
  if (normalized === '' || normalized.startsWith('/') || /^[a-zA-Z]:/.test(normalized)) {
    return '';
  }
  const segments = normalized.split('/');
  for (const segment of segments) {
    if (segment === '..') {
      return '';
    }
  }
  return normalized;
}

// 全树 bin 扫（返回 name → 候选条目数组；同名多包并存时谁胜由 mergeBinLedger 判——单包内
// 同名条目按 bin 字段最后一次出现，manifest 自身不该有两份）。键来自包 manifest（外部输入），
// 字典用无原型对象：constructor / toString / __proto__ 这类命令名不得读成继承成员（坑98）
function buildBinLedger(prefix) {
  const bins = Object.create(null);
  const packages = collectPackageDirs(path.join(prefix, 'node_modules'));
  for (const pkg of packages) {
    const meta = readPackageMeta(pkg.abs);
    if (meta === null) {
      continue;
    }
    const targets = binTargetsOf(meta);
    for (const item of targets) {
      const relative = normalizeBinTarget(item.target);
      if (relative === '') {
        continue;
      }
      const entry = {
        name: item.name,
        package: typeof meta.name === 'string' && meta.name !== '' ? meta.name : pkg.rel,
        version: typeof meta.version === 'string' ? meta.version : '',
        entry: pkg.rel + '/' + relative,
        // CJS 判据（任务书 §5 S3）：.cjs 恒 CJS（扩展名优先于包 type，2026-11-24 补正——
        // type:module 包内 .cjs 入口曾被误判）；其余非 .mjs 且包 type !== 'module'
        cjs: /\.cjs$/i.test(relative) || (!/\.mjs$/i.test(relative) && meta.type !== 'module')
      };
      if (bins[item.name] === undefined) {
        bins[item.name] = [];
      }
      bins[item.name].push(entry);
    }
  }
  return bins;
}

function readBinLedger(prefix) {
  const text = readTextIfExists(path.join(prefix, BIN_LEDGER_FILE));
  if (text === null) {
    return null;
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed === null || typeof parsed !== 'object' || parsed.bins === null
      || typeof parsed.bins !== 'object') {
      return null;
    }
    return parsed;
  } catch (e) {
    return null;
  }
}

// 同名候选择一（任务书代决表第 3 项「后装者覆盖」）：优先本次安装清单里的包（preferred，按
// 出现次序取最后一个）→ 否则保留台账里已在册的那个包（未被本次安装动过，不该凭空换）→
// 再否则取扫到第一个。这样一次全树重扫不会把同名归属随机翻面。注意 preferred 的遍历序是
// **扫描序**不是清单序：同一次安装里两个包都提供同名命令时，谁胜取决于目录遍历（本就没有
// 「后装」；跨次安装才是后装者胜，那也是该项要表达的场景）
function pickBinCandidate(list, existing, preferredSet) {
  let preferred = null;
  for (const item of list) {
    if (preferredSet.has(item.package)) {
      preferred = item;
    }
  }
  if (preferred !== null) {
    return preferred;
  }
  if (existing !== null && existing !== undefined && typeof existing === 'object') {
    for (const item of list) {
      if (item.package === existing.package) {
        return item;
      }
    }
  }
  return list[0];
}

// 合并写账（成功 install 才调）：既有条目原样保留（装前不清账），同名条目按 pickBinCandidate
// 择一；换到别的包时打 replaced 标记（运行回执据此注明一次覆盖）。preferredPackages = 本次
// 安装清单的包名（npm-worker 从 specs 剥版本号传入）
function mergeBinLedger(prefix, preferredPackages) {
  const before = readBinLedger(prefix);
  const candidates = buildBinLedger(prefix);
  // 无原型对象（同上：命令名是外部文本；Object.assign 写入 __proto__ 键时普通对象会改原型
  // 而不是建自有键）
  const merged = before !== null
    ? Object.assign(Object.create(null), before.bins) : Object.create(null);
  const preferredSet = new Set(Array.isArray(preferredPackages) ? preferredPackages : []);
  const overwritten = [];
  const names = Object.keys(candidates);
  for (const name of names) {
    const old = merged[name];
    const chosen = pickBinCandidate(candidates[name], old, preferredSet);
    if (old !== null && old !== undefined && typeof old === 'object'
      && old.package !== chosen.package) {
      overwritten.push(name);
      chosen.replaced = true;
    }
    merged[name] = chosen;
  }
  const ledger = {
    version: BIN_LEDGER_VERSION,
    updatedAt: new Date().toISOString(),
    bins: merged
  };
  const target = path.join(prefix, BIN_LEDGER_FILE);
  const temp = target + '.tmp';
  fs.writeFileSync(temp, JSON.stringify(ledger));
  fs.renameSync(temp, target);
  return { total: Object.keys(merged).length, updated: names.length, overwritten: overwritten };
}

module.exports = {
  setNpmPrimitives,
  errorText,
  readTextIfExists,
  snapshotInstallState,
  checkInstallSafety,
  applyRollback,
  rollbackAfterViolation,
  reinstallFromManifests,
  collectBinaryFiles,
  sweepBinaryFiles,
  buildBinLedger,
  readBinLedger,
  mergeBinLedger,
  BIN_LEDGER_FILE,
  // 台账结构版本导出给断言侧（与 bin-runner.LEDGER_VERSION 钉相等——两件在设备上不同目录，
  // 无法互引，只能靠断言守）
  BIN_LEDGER_VERSION,
  VIOLATION_REPORT_MAX
};
