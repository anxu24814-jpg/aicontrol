// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// assert-net-parse.mjs — 网络传输与文档解析域断言（2026-09-12 夜间接力笔 4 新建；
// 任务书-夜间接力笔4-网络与文档解析加固-20260911，验收闭环后随交付归卷
// docs/归档/任务书-归档-04）。职责一行 = 守本笔两处改码的回归钉（钉随码走）+ 两域既有
// 不变量：http 请求缓存与建销成对、WebDAV 备份恢复链、隐式 WebView 解析器就绪时序。
//
// 域内容 = 72 组 35 钉，两段：A 传输（WebDavApi.ets，16）/ B 解析（DocumentParse.ets 跨
// ChatPage.ets 一行，19）。★ 钉与全部 12 发注入反验记录 =
// docs/自检报告/自检报告-网络与文档解析加固-20260911.md。
// ★ 2026-09-15 附件 PDF 页渲染一期（任务书-附件PDF页渲染与视觉门控-20260915 执行笔）B 段
// +4 钉（页渲染与解析同 promise 单元 / RENDER_MAX_PAGES 30 常量单源 / 渲染降级不抛 /
// clearPages 成对）+ 控制器调用计数钉 5 → 9（同钉改写）、空 catch 负向钉 1 → 2（新增
// clearPagesSilent 静默收口）——本件 31 → 35 钉，加本笔变更记录九百一十八节。
//
// 运行：node scripts/assert-net-parse.mjs（可单独跑；delivery-gate SUB_CHECKS 第十六件，
// 总数基线随本件 +31）。与既有件零重叠：①ChatStreamBase 等七文件的 usingCache 由既有件
// 守（assert-chat-runtime A 段等）——本件只在 A3 地板判据里读它们、不重复下钉；②ChatPage
// 只读一行（aboutToDisappear 的 docParser.cancelCurrentParse() 调用点），该页编排层不属本件
//（assert-chat-runtime 已声明编排层不属其域，本件同样不越界）；③WebDAV 页面层（DataSyncPage
// 的 lastName 持久化与恢复交互）不在本件——本件只判传输层。
// 判读对象逐钉写死（本件纪律）：A10 / A11 / B2 / B12 四枚负向钉与其余 A/B 判据一律跑剥
// 注释源（正向钉不剥 = 坑38 假绿、负向钉不剥 = 假红），四枚负向钉各打印「剥前命中 / 剥后
// 命中」实证；★ 唯一例外 = B13 的 URL 全字面量判原文——'resource://rawfile/…' 含 //，
// 剥注释判据会把字面量截断（该全字面量在头注释中不存在，无坑38 假绿面，钉注释已写明）。
// 剥序 = 先 \r 后 //（CRLF 下 $ 不跨 \r，坑47）。切段 = 显式边界（顶层函数 \n} / 类内
// 方法 \n  } / struct 行首 }——坑37 家族）；不绑行号，定位一律符号名 / 常量名 / 字面量。
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { check, report } from './assert-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = path.join(here, '..', '..', 'entry', 'src', 'main', 'ets');

// 归一化读（CRLF→LF）
const rdRaw = (rel) => readFileSync(path.join(SRC_ROOT, rel), 'utf-8').replace(/\r\n/g, '\n');
// 剥行注释源（先剥 \r 再剥 //）
const codeOnly = (t) => t.split('\n')
  .map((l) => l.replace(/\r$/, '').replace(/\/\/.*$/, '')).join('\n');
const rd = (rel) => codeOnly(rdRaw(rel));
// 顶层块切：marker 起、首个列 0 独占行 } 止（顶层函数 / class 通用——块内闭合行缩进 ≥1）
const block = (src, marker) => {
  const start = src.indexOf(marker);
  if (start < 0) {
    return '';
  }
  const end = src.indexOf('\n}', start);
  return end < 0 ? '' : src.slice(start, end);
};
const fnSeg = (src, name) => block(src, 'function ' + name);
// struct 段：export struct 起、首个行首 } 止（struct 体闭合行缩进 ≥2，列 0 } 不误配；
// 落书已实测取到整个宿主、不串出——书 §3.2.1）
const structSeg = (src, name) => block(src, 'export struct ' + name);
// 类内方法段：两空格缩进方法名起、首个 '\n  }' 止（方法体内闭包闭合缩进 ≥4，不误配）
const method = (blk, name) => {
  const m = new RegExp('^  (private |protected |public |static )*(async )?' + name + '\\(', 'm')
    .exec(blk);
  if (!m) {
    return '';
  }
  const end = blk.indexOf('\n  }', m.index);
  return end < 0 ? '' : blk.slice(m.index, end);
};
// 剥注释实证（§6-3）：剥前含 // 行数 / 剥后残留（期望 0）
const stripProbe = (raw) => {
  const before = raw.split('\n').filter((l) => l.trimStart().startsWith('//')).length;
  const after = codeOnly(raw).split('\n').filter((l) => l.trimStart().startsWith('//')).length;
  return before + ' 行 / 残留 ' + after;
};

// ═══ 72 组：网络传输与文档解析（夜间接力笔 4；上游全面自检 §3-B / §3-F 收口）═══
{
  // ── A 传输（common/WebDavApi.ets，16 钉）──
  const wdRaw = rdRaw('common/WebDavApi.ets');
  const wd = codeOnly(wdRaw);
  const davReq = fnSeg(wd, 'davRequest');
  const ensureDirSeg = fnSeg(wd, 'ensureDir');
  const dlSeg = fnSeg(wd, 'downloadLatestBackup');
  const pruneSeg = fnSeg(wd, 'pruneOldBackups');
  const delSeg = fnSeg(wd, 'deleteRemoteFile');

  console.log('[剥注释实证] WebDavApi 注释行 剥前/剥后 = ' + stripProbe(wdRaw));

  // ★ 反验 I1：删 davRequest 的 usingCache: false → 恰本钉唯一红（A3 仍绿：ensureDir 那处还在）
  check('72 传输-davRequest 关响应缓存 ★', [
    davReq.includes('usingCache: false')
  ], [true]);
  // ★ 反验 I2：删 ensureDir 的 usingCache: false → 恰本钉唯一红（MKCOL 本无缓存语义，
  // 独立字面量仍按全仓惯例显式声明）
  check('72 传输-ensureDir 关响应缓存 ★', [
    ensureDirSeg.includes('usingCache: false')
  ], [true]);
  // ★ 反验 I3：两处 usingCache 全删 → A1 + A2 + 本钉三枚同源红（同源≠独立失效，报告注明）。
  // 跨文件地板：凡原文含 http.createHttp() 的文件，剥注释源必须含 usingCache——判「文件是否
  // 含 usingCache」必须在剥注释源判（头注释提及即假绿，附 B 头号坑）；遍历跳过产物目录。
  const walkEts = (dir, out) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (['.tmp', 'build', 'oh_modules', 'node_modules', '.git', '.cxx'].includes(e.name)) {
        continue;
      }
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        walkEts(p, out);
      } else if (e.name.endsWith('.ets')) {
        out.push(p);
      }
    }
    return out;
  };
  const httpFiles = [];
  const missingCache = [];
  for (const p of walkEts(SRC_ROOT, [])) {
    const raw = readFileSync(p, 'utf-8');
    if (!raw.includes('http.createHttp()')) {
      continue;
    }
    httpFiles.push(path.basename(p));
    if (!codeOnly(raw.replace(/\r\n/g, '\n')).includes('usingCache')) {
      missingCache.push(path.basename(p));
    }
  }
  console.log('[地板实证] 含 http.createHttp() 文件 ' + httpFiles.length + ' 个，缺 usingCache：'
    + (missingCache.join('、') || '无') + '（开工 8:7 → 本笔后 8:8）');
  check('72 传输-全仓 http 点缓存地板（跨文件生成式） ★', [
    httpFiles.length >= 8,
    missingCache
  ], [true, []]);
  // ★ 反验无独立发（形态钉）：createHttp 2 ↔ destroy 2，两处 destroy 都在各自 finally 内
  check('72 传输-两请求建销成对', [
    (wd.match(/http\.createHttp\(\)/g) || []).length === 2,
    (wd.match(/req\.destroy\(\)/g) || []).length === 2,
    davReq.includes('finally {') && davReq.includes('req.destroy();'),
    ensureDirSeg.includes('finally {') && ensureDirSeg.includes('req.destroy();')
  ], [true, true, true, true]);
  // ★ 反验 I4：删 candidates.push(LEGACY_BACKUP_NAME); → 恰本钉唯一红（候选序断链）
  check('72 传输-恢复链候选序 ★', (() => {
    const iL = dlSeg.indexOf("if (lastName !== '')");
    const iF = dlSeg.indexOf('for (let i = 0; i < 5; i++)');
    const iG = dlSeg.indexOf('candidates.push(LEGACY_BACKUP_NAME);');
    return [iL >= 0 && iF > iL && iG > iF];
  })(), [true]);
  check('72 传输-链内同名不重复探测', [
    dlSeg.includes('const tried: string[] = [];'),
    dlSeg.includes('tried.indexOf(name) !== -1'),
    dlSeg.includes('tried.push(name);')
  ], [true, true, true]);
  check('72 传输-全 404 统一提示',
    dlSeg.includes("throw new Error('远端还没有备份文件，请先在任意设备上传一次')"), true);
  // ★ 反验 I5：改 probe 那处 401 文案一字 → 恰本钉唯一红（计数 3→2；三处 = authError /
  // ensureDir / probe，剥注释计数）
  check('72 传输-401 文案三处同文 ★', [
    (wd.match(/账号或密码（应用密码）不正确/g) || []).length
  ], [3]);
  // ★ 反验 I12：删 pruneOldBackups 的 legacy 清理行 → 恰本钉唯一红（尽力而为恒正常返回）
  check('72 传输-清窗 6..60 逐日删 + legacy 迁移', [
    pruneSeg.includes('for (let i = 6; i <= 60; i++)'),
    pruneSeg.includes('remoteBackupName(i)'),
    pruneSeg.includes('deleteRemoteFile(cfg, LEGACY_BACKUP_NAME)'),
    !pruneSeg.includes('throw')
  ], [true, true, true, true]);
  // 负向钉（剥注释源；剥前/剥后实证——不剥注释时 catch 体内是注释行，本钉恒红）
  // ★ 2026-09-24 请求日志扩面笔**改判**（守则②b：原「全文件命中恰 1」是计数快照，合法新增
  // 即假红）：本笔在两处 finally 加 destroy 守卫（davRequest / ensureDir，同 ModelListApi /
  // TitleApi / KeyConnectTester 三先例的「二次释放异常不得外抛」形态），空 catch 1 → 3。
  // 改判为**分域计数**：总数 3 + 业务面那处（deleteRemoteFile 的全吞）恰 1 —— 原判别力保住
  //（删除链静默吞仍被逐处锁定），且第四个空 catch（须经评审的新增）即红。
  // （附 B 第三坑仍适用：禁窗口正则取 catch 块——deleteRemoteFile 的下一函数也有 try）
  const wdEmpty = (wd.match(/catch \(e\) \{\s*\}/g) || []).length;
  console.log('[剥注释实证] A10 空 catch 正则: 剥前命中 '
    + (wdRaw.match(/catch \(e\) \{\s*\}/g) || []).length + ' / 剥后命中 ' + wdEmpty
    + '（期望恰 3 = deleteRemoteFile 全吞 + 两处 destroy 守卫）');
  check('72 传输-删除全吞（负向·剥注释源）', [
    wdEmpty === 3,
    (delSeg.match(/catch \(e\) \{\s*\}/g) || []).length === 1,
    delSeg.includes('try {'),
    delSeg.includes('davRequest(')
  ], [true, true, true, true]);
  check('72 传输-凭据零入日志（负向·剥注释源）', [
    !wd.includes('hilog'),
    !wd.split('\n').some((l) => l.includes('Error(') && l.includes('cfg.password'))
  ], [true, true]);
  check('72 传输-四类错误文案分型', [
    wd.includes("super('HTTP ' + status)"),
    wd.includes('创建远端目录失败（HTTP ${resp.responseCode}）'),
    wd.includes('服务器不可达（HTTP ${status}）')
  ], [true, true, true]);
  check('72 传输-路径逐段编码', [
    fnSeg(wd, 'remoteUrl').includes("cfg.dirName.split('/').filter("),
    fnSeg(wd, 'remoteUrl').includes('encodeURIComponent(s)'),
    fnSeg(wd, 'remoteUrl').includes(".join('/')"),
    fnSeg(wd, 'trimSlash').includes("endsWith('/')")
  ], [true, true, true, true]);
  check('72 传输-GET 收字节其余收文本', [
    davReq.includes('expectDataType: method === http.RequestMethod.GET ?'),
    davReq.includes('http.HttpDataType.ARRAY_BUFFER'),
    davReq.includes('http.HttpDataType.STRING')
  ], [true, true, true]);
  check('72 传输-本地读写 fd 成对', [
    ['readLocalFile', 'writeLocalFile'].every((n) => {
      const s = fnSeg(wd, n);
      return s.includes('fs.openSync(') && s.includes('finally {')
        && s.includes('fs.closeSync(file);');
    })
  ], [true]);
  check('72 传输-命名常量逐字', [
    wd.includes('TIMEOUT_MS: number = 60000'),
    wd.includes("BACKUP_NAME_PREFIX: string = 'aicontrol_backup_'"),
    wd.includes("LEGACY_BACKUP_NAME: string = 'aicontrol_backup.zip'"),
    wd.includes('d.getFullYear()'),
    wd.includes('pad(d.getMonth() + 1)'),
    wd.includes('pad(d.getDate())')
  ], [true, true, true, true, true, true]);

  // ── B 解析（common/DocumentParse.ets 跨 ChatPage.ets 一行，15 钉）──
  const dRaw = rdRaw('common/DocumentParse.ets');
  const d = codeOnly(dRaw);
  const wdp = block(d, 'class WebDocumentParser');
  const host = structSeg(d, 'DocParserHost');
  const aboutSeg = method(structSeg(rd('components/chat/ChatPage.ets'), 'ChatPage'),
    'aboutToDisappear');

  console.log('[剥注释实证] DocumentParse 注释行 剥前/剥后 = ' + stripProbe(dRaw));

  // ★ 反验 I6：删宿主 onControllerAttached 内 docParser.markUnready(); → 恰本钉唯一红。
  // ★ 判读对象切分（防两钉同源，四百二十节 P1-1）：本钉只判方法定义与调用在位——赋值串
  // 归 B2 独占（I7 改 markUnready 体只动 B2；I6 删调用只动本钉）
  check('72 解析-就绪复位点与置位点成对 ★', [
    (d.match(/markUnready\(\): void \{/g) || []).length === 1,
    (d.match(/markReady\(\): void \{/g) || []).length === 1,
    (() => {
      const iA = host.indexOf('docParser.attachController(docParseController);');
      const iM = host.indexOf('docParser.markUnready();');
      return iA >= 0 && iM > iA;
    })(),
    host.includes('docParser.markReady();')
  ], [true, true, true, true]);
  // ★ 反验 I7：把 markUnready 体改成 this.isReady = true; → 恰本钉唯一红（false 计数 1→0）。
  // 负向钉（剥注释源）：isReady 出现 4 处但赋值只判 = true / = false 两形态（附 B 第二坑：
  // 数标识符必错）；禁第三个赋值点——第二置位点让复位失效、第二复位点让就绪闸空转
  const readyTrue = (d.match(/this\.isReady = true/g) || []).length;
  const readyFalse = (d.match(/this\.isReady = false/g) || []).length;
  console.log('[剥注释实证] B2 isReady 赋值形态: 剥前 true='
    + (dRaw.match(/this\.isReady = true/g) || []).length + '/false='
    + (dRaw.match(/this\.isReady = false/g) || []).length
    + ' / 剥后 true=' + readyTrue + '/false=' + readyFalse + '（期望各 1）');
  check('72 解析-isReady 双赋值点唯一（负向·剥注释源） ★', [
    readyTrue === 1, readyFalse === 1
  ], [true, true]);
  // ★ 反验 I8：删 cancelCurrentParse 的 !this.isReady 判 → 恰本钉唯一红。
  // runScript 调用恰 9（1 定义无 this. 前缀不计）且全部在就绪闸之后：五处上游
  // parseAttachmentNow 有 await waitUntilReady()，cancelCurrentParse 首行即 isReady 早返。
  // ★ 2026-09-15 附件 PDF 页渲染一期自 5 → 9（+4 = renderPages / getRenderState /
  // getPageImage / clearPages）——四处分别由 renderThinPdf 与 clearPagesSilent 发起，前者
  // 续在 parseAttachmentNow 链尾（同一 promise 单元，上游即 waitUntilReady 与解析完成）、
  // 后者同链 finally，故「全经就绪闸」判据不变；★ 反验：本钉计数回落 5 即红
  check('72 解析-控制器调用九处且全经就绪闸 ★', [
    (d.match(/this\.runScript\(/g) || []).length === 9,
    method(wdp, 'parseAttachmentNow').includes('await this.waitUntilReady();'),
    method(wdp, 'cancelCurrentParse')
      .includes('if (this.controller === null || !this.isReady) {')
  ], [true, true, true]);
  check('72 解析-串行队列双回调同体', [
    method(wdp, 'parseAttachment').includes('this.queueTail.then('),
    (method(wdp, 'parseAttachment')
      .match(/: Promise<DocumentParseResult> => this\.parseAttachmentNow\(att\)/g) || []).length === 2
  ], [true, true]);
  check('72 解析-就绪等待 5s 上限', [
    method(wdp, 'waitUntilReady').includes('WEB_READY_TIMEOUT_MS'),
    method(wdp, 'waitUntilReady').includes('POLL_STEP_MS'),
    method(wdp, 'waitUntilReady').includes("throw new Error('解析器未就绪')")
  ], [true, true, true]);
  check('72 解析-结果轮询 45s 上限', [
    method(wdp, 'waitForWebParseResult').includes('WEB_PARSE_TIMEOUT_MS'),
    method(wdp, 'waitForWebParseResult').includes('POLL_STEP_MS'),
    method(wdp, 'waitForWebParseResult').includes("throw new Error('解析超时')")
  ], [true, true, true]);
  check('72 解析-分型四上限与抽取上限逐字', [
    d.includes('DOCX_HARD_BYTES: number = 25 * 1024 * 1024'),
    d.includes('EXCEL_HARD_BYTES: number = 20 * 1024 * 1024'),
    d.includes('PDF_HARD_BYTES: number = 30 * 1024 * 1024'),
    d.includes('OFD_HARD_BYTES: number = 30 * 1024 * 1024'),
    d.includes('MAX_EXTRACTED_CHARS: number = 120000')
  ], [true, true, true, true, true]);
  // ★ 反验 I9：att.parseState === 'done' 改 === 'idle' → 恰本钉唯一红（done = 唯一放行态）
  check('72 解析-发送阻断三态文案 ★', [
    fnSeg(d, 'docBlockingReason').includes("att.parseState === 'done'"),
    fnSeg(d, 'docBlockingReason').includes('附件过大，暂不支持解析：'),
    fnSeg(d, 'docBlockingReason').includes('附件解析失败，请移除或更换文件后再发送：'),
    fnSeg(d, 'docBlockingReason').includes('附件仍在解析中：')
  ], [true, true, true, true]);
  check('72 解析-五扩展名白名单', [
    fnSeg(d, 'isDocCandidate').includes("att.kind !== 'doc'"),
    ['.pdf', '.docx', '.xlsx', '.xls', '.ofd']
      .every((e) => fnSeg(d, 'isDocCandidate').includes("'" + e + "'"))
  ], [true, true]);
  // ★ 反验 I11：删 .hitTestBehavior(HitTestMode.None) → 恰本钉唯一红（被点中会抢焦点）
  //（1×1 透明离屏 + 命中穿透五件齐——Cube ChatPage 形态逐项照搬）
  check('72 解析-宿主属性链五件', [
    host.includes('.width(1)'),
    host.includes('.height(1)'),
    host.includes('.opacity(0)'),
    host.includes('.position({ x: -2, y: -2 })'),
    host.includes('.hitTestBehavior(HitTestMode.None)')
  ], [true, true, true, true, true]);
  // ★ 反验 I10：parseWebResult catch 体改 throw e as Error; → 恰本钉唯一红
  //（Cube 同款容错——坏结果转 failed 态不抛）
  check('72 解析-坏结果不抛（容错）', [
    method(wdp, 'parseWebResult').includes('catch (e) {'),
    method(wdp, 'parseWebResult').includes("result.error = '解析结果无效';")
  ], [true, true]);
  // 负向钉（剥注释源）：恰两处空吞 catch——cancelCurrentParse（页面将亡无消费方）与
  // clearPagesSilent（★ 2026-09-15 页渲染一期新增：桥页清理幂等，失败由下一次 start()
  // 收口，无消费方需感知）；其余 catch 分别抛「解析脚本执行失败」/ 返回原值 / 写「解析
  // 结果无效」/ 渲染降级写 result。第三处空吞即红
  const dEmpty = (d.match(/catch \(e\) \{\s*\}/g) || []).length;
  console.log('[剥注释实证] B12 空 catch 正则: 剥前命中 '
    + (dRaw.match(/catch \(e\) \{\s*\}/g) || []).length + ' / 剥后命中 ' + dEmpty
    + '（期望恰 2 = cancelCurrentParse + clearPagesSilent）');
  check('72 解析-取消静默 + 页销毁调用点', [
    dEmpty === 2,
    aboutSeg.includes('docParser.cancelCurrentParse();')
  ], [true, true]);
  // ★ URL 全字面量判原文（含 //，剥注释判据会把字面量截断——该全字面量在头注释中不存在，
  // 无坑38 假绿面）；常量声明与双单例导出判剥注释源
  check('72 解析-桥地址与双单例导出', [
    d.includes('WEB_PARSER_URL: string ='),
    dRaw.includes("'resource://rawfile/document-parser/document-parser.html'"),
    d.includes('export const docParser: WebDocumentParser = new WebDocumentParser();'),
    d.includes('export const docParseController: webview.WebviewController = new webview.WebviewController();')
  ], [true, true, true, true]);
  check('72 解析-分块注入三调用序', [
    method(wdp, 'parseBase64').includes('BASE64_CHUNK_SIZE'),
    (() => {
      const s = method(wdp, 'parseBase64');
      const iS = s.indexOf('DocumentParserBridge.start(');
      const iA = s.indexOf('DocumentParserBridge.append(');
      const iF = s.indexOf('DocumentParserBridge.finish(');
      return iS >= 0 && iA > iS && iF > iA;
    })(),
    method(wdp, 'normalizeRunJavaScriptResult').includes('for (let i = 0; i < 2; i++)')
  ], [true, true, true]);
  check('72 解析-读副本 fd 成对', [
    fnSeg(d, 'readBase64').includes('fs.openSync('),
    fnSeg(d, 'readBase64').includes('finally {'),
    fnSeg(d, 'readBase64').includes('fs.closeSync(file);')
  ], [true, true, true]);
  // ── 2026-09-15 附件 PDF 页渲染一期（任务书-附件PDF页渲染与视觉门控-20260915）──
  // ★ 反验 J1：把 renderThinPdf 调用从 parseAttachmentNow 挪出（另起异步）→ 恰本钉唯一红。
  // 依据 = 桥页是单任务状态机（start() 重置解析态），渲染若脱出 promise 单元会与下一件
  // 附件的解析互踩——同一 promise 单元是本设计的关键不变量，不是风格偏好。
  //（2026-09-15 自检轮改判：链尾形态 `return await …`——外层 try/finally 收口桥页句柄，见 J4）
  check('72 解析-页渲染与解析同 promise 单元（链尾续做）★', [
    method(wdp, 'parseAttachmentNow').includes('return await this.renderThinPdf(att, parsed);'),
    method(wdp, 'parseAttachmentNow')
      .includes('const parsed: DocumentParseResult = await this.parseBase64(att, base64Data);')
  ], [true, true]);
  // ★ 反验 J2：RENDER_MAX_PAGES 30 → 10 → 恰本钉唯一红（常量单源；页数上限经入参传桥页）
  check('72 解析-渲染页数上限常量单源（30 页，经入参传桥页）★', [
    d.includes('export const RENDER_MAX_PAGES: number = 30;'),
    method(wdp, 'renderThinPdf').includes('renderPages(${RENDER_MAX_PAGES})')
  ], [true, true]);
  // ★ 反验 J3：渲染失败路径改抛错（删 catch 的 hilog + 返 result）→ 恰本钉唯一红
  check('72 解析-渲染降级不抛错（整批丢弃 + hilog 留痕）★', [
    method(wdp, 'renderThinPdf').includes("hilog.warn(0xD5A0, 'DocumentParse'"),
    method(wdp, 'renderThinPdf').includes('} catch (e) {'),
    method(wdp, 'pullRenderedPages').includes('return null;'),
    method(wdp, 'pullRenderedPages').includes('count !== expected')
  ], [true, true, true, true]);
  // ★ 反验 J4（2026-09-15 自检轮改判）：删 clearPagesSilent（桥页侧页图/句柄不释放）→ 本钉
  // + assert-attach-domain 99 组「释放单点收口」钉双红——同一行为的双域钉，不再是「恰本钉唯一红」。
  // 释点自检轮从渲染路径内（finally）移到 parseAttachmentNow 尾 finally：句柄建点在 parsePdf
  // 全类型（凡载入成功的 PDF 都留），释点须同样覆盖「非 thin 早退 / 解析失败 / 渲染降级 /
  // 渲染成功」全部出口，否则非 thin 的 30MB 级 PDF 句柄留存到下一件解析或离页
  check('72 解析-页图拉取后桥页清理在位（尾 finally 成对，覆盖全出口）★', [
    method(wdp, 'parseAttachmentNow').includes('} finally {'),
    method(wdp, 'parseAttachmentNow').includes('await this.clearPagesSilent();'),
    method(wdp, 'clearPagesSilent')
      .includes("await this.runScript('window.DocumentParserBridge.clearPages()');")
  ], [true, true, true]);
}
report();
