// DS 历史导出包解析域（DS 全家桶接入批 S5②）。一句话职责 =「把 DeepSeek 官方导出的
// deepseek_data zip 解析成本应用可导入的会话清单」——解压读取面 + 纯映射面两段，落库面在
// DsHistoryImportApply（本件不碰库）。
// · 格式单源 = demo 本地参考源码 chat-demo/src/services/chat/history/ 的 README.md +
//   format.ts + schema.ts（MIT 项目——**只引格式不引实现**，本项目自研 ArkTS，禁复制其代码）。
//   归档结构四类条目 = manifest.json（首个条目，export_format_version 必须 = 3）/
//   chat_session_index.json（会话索引）/ chat_sessions/{session_id}.json（会话全量消息树）/
//   chat_sessions/{session_id}_files/{file_id}_{file_name}（图片原件）。压缩目录可能平铺也可能
//   带一层导出目录名（zlib 条目形态未文档化，照 ExportImportApply.locateDecompressRoot 两形态
//   兼容）。时间 = UTC RFC 3339 Z 结尾可选小数秒。
// · 白名单读取纪律（代决 7 / S5 指令）：**只按四类路径模式读取**，模式外文件忽略不炸——
//   zlib.decompressFile 是整包解压无选择性，白名单约束的是「读什么」而非「解什么」；
//   dsZipPathAllowed 同时充当 export_path 配对的安全闸（拒 ../ 绝对路径 反斜杠穿越）。
// · 体积闸（代决 7）：zip 解包累计 512MB、单 JSON 20MB，超限中文报错拒收（判据 = 纯函数
//   dsZipTotalSizeVerdict / dsJsonSizeVerdict，IO 面负责先 stat 后读）。★ 2026-11-14 自检
//   报告 §4.4 修：解压**前**先扫中央目录声明总字节（dsZipCentralDirTotal / 预扫壳），超限
//   在落盘前拒收；预扫不可解析（ZIP64/坏包）退回「解压后 dsWalkTotalBytes 闸」兜底。
// · 导入映射口径（二期 S1 真保真；决明 2026-11-14 拍板）：
//   **全树导入**——所有消息节点（含各版本分支）都读，不再只导 current_message_id 父链；
//   分支表按「每个非选中子节点 → 其选中链最深后代」＋「当前停留点本身」产出，落库后直接走
//   现有行内版本步进器（零新显示组件）。
//   联网过程片段保真——TOOL_SEARCH / TOOL_OPEN / TOOL_FIND / READ_LINK / TOOL_IMAGE_SEARCH
//   映射为 CC 形态 server_tool_calls 串（写已有 messages.server_tools 列），回放经既有
//   dsServerCallJsonsOf / 来源卡 / 步骤行三纯函数渲染；`signature` **不读不存**（方案档
//   §4.1：展示零贡献、只决定导入的历史能否被官方端点继续引用网页）。
//   TIP / CONTENT_RISK / PARTIAL_FILE_READ 仍不收（无对应展示，只计数）。
//   TEMPLATE_RESPONSE 按状态映射导入（模板文案 = 该消息可见正文，错误族 status='error' 其余
//   'done'）；THINK→reasoning；正文保真；零可展示内容的节点**保留**（空正文，否则分支父链断裂）。
//   单会话节点数上限 3000（代决）：超限整会话拒绝导入并呈报，不截断（截断产半残消息树）。
// · 防御口径：父链断裂（父 id 不在树内 / 环）截断该线并计数呈报，不炸整包；坏消息行跳过计数；
//   会话容器字段不合法整会话跳过计数；缺失图片跳过计数；索引列出而无文件的会话计数——全部
//   **聚合呈报面**（DsParseReport），单点坏不升级成整包失败。
// · 临时目录成对释放（宪法内存防线）：解压目录任何退出路径都清——解析函数内部失败路径自清，
//   成功路径把 rootDir 交还调用方、由调用方 finally 调 dsReleaseParsedZip 释放（两消费方 =
//   预览与落库 apply，各自 owns try/finally）。
// · 本件 = 解压读取 IO 壳；路径/体积/版本三闸与全部纯映射面（片段白名单、全树建树、分支头、
//   状态映射、节点上限）已按宪法 1200 硬线拆到 DsHistoryParse（S1 真保真后本件剔头超线，
//   域级最小拆分；IO 逻辑一行未动）。纯函数剥 import 可直跑（assert-ds-integration 己组）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cleanupDir } from '../store/ExportImport';
// 纯映射面（拆分件）：类型与解析入口由本件 IO 壳消费；三闸常量/判据仍在下方本件内
import { DsParseCounters, DsParseReport, DsParsedSession, DsParsedZip, DS_JSON_MAX_BYTES,
  DS_ZIP_MAX_TOTAL_BYTES, dsJsonSizeVerdict, dsManifestVerdict, dsParseSessionText,
  dsZipCentralDirTotal, dsZipPathAllowed, dsZipTotalSizeVerdict } from './DsHistoryParse';
// 版本闸常量本件不再导出（单源在 DsHistoryParse）；为免消费方断链，此处转出同名常量
export { DS_EXPORT_FORMAT_VERSION, DS_ZIP_MAX_TOTAL_BYTES, DS_JSON_MAX_BYTES } from './DsHistoryParse';

const DOMAIN: number = 0xE17;
const TAG: string = 'DsHistoryZip';

// ── 常量（代决 7 版本闸与体积闸；格式版本单源 = demo format.ts EXPORT_FORMAT_VERSION）──

// （三闸常量单源 = DsHistoryParse：版本闸 3、解包累计 512MB、单 JSON 20MB——本件从其导入）
// 中央目录预读上限（解压前体积闸只读目录区；正常导出包目录远小于此值，超限 = 不预判，
// 交解压后闸兜底——避免为一个畸形包再读进大块内存）
const DS_ZIP_MAX_CENTRAL_BYTES: number = 8 * 1024 * 1024;

// ── IO 面（解压 / 读取 / 白名单枚举 / 图片配对）──

function dsFileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

function dsFileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (e) {
    return -1;
  }
}

// 文本读取（照 ExportImportApply.readFileText 形制：stat 定长 → openSync/readSync → utf-8 解码；
// 成对 closeSync）
function dsReadFileText(path: string): string {
  const stat: fs.Stat = fs.statSync(path);
  const ab: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const len: number = fs.readSync(file.fd, ab);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(ab).subarray(0, len));
  } finally {
    fs.closeSync(file);
  }
}

// 读文件定长区间（成对 open/close；ReadOptions.offset = 文件起点，短读即放弃——返回 null
// 由调用方走「不预判」分支，解压后体积闸照旧兜底。不重试拼接：预扫是早退优化，不值得为
// 短读引入缓冲区拷贝面）
function dsReadRangeExact(path: string, offset: number, length: number): ArrayBuffer | null {
  if (length <= 0) {
    return null;
  }
  const ab: ArrayBuffer = new ArrayBuffer(length);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const got: number = fs.readSync(file.fd, ab, { offset: offset, length: length });
    return got === length ? ab : null;
  } finally {
    fs.closeSync(file);
  }
}

// 解压前体积预扫（§4.4 修）：读 EOCD（尾 64KB 内回扫）→ 中央目录声明的解压总字节。
// 返回 -1 = 结构不可解析 / ZIP64 / 读失败（不预判，解压后闸兜底）；≥0 = 声明总字节。
// 目的 = 恶意/异常 zip 在整包解压写满缓存盘之前被拒（decide 7 体积闸的前置同值闸）。
function dsZipDeclaredTotalBytes(zipPath: string): number {
  const size: number = dsFileSize(zipPath);
  if (size < 22) {
    return -1;
  }
  // EOCD 最小 22B + 注释最长 65535B——只可能在尾部这一窗内
  const tailLen: number = Math.min(size, 22 + 65535);
  const tail: ArrayBuffer | null = dsReadRangeExact(zipPath, size - tailLen, tailLen);
  if (tail === null) {
    return -1;
  }
  const tailView: DataView = new DataView(tail);
  let eocd: number = -1;
  for (let i = tailLen - 22; i >= 0; i--) {
    if (tailView.getUint32(i, true) === 0x06054b50) { // PK\x05\x06
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    return -1;
  }
  const entries: number = tailView.getUint16(eocd + 10, true);
  const cdSize: number = tailView.getUint32(eocd + 12, true);
  const cdOffset: number = tailView.getUint32(eocd + 16, true);
  if (entries === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
    return -1; // ZIP64：不预判
  }
  if (cdSize === 0 || cdSize > DS_ZIP_MAX_CENTRAL_BYTES || cdOffset + cdSize > size) {
    return -1;
  }
  const cd: ArrayBuffer | null = dsReadRangeExact(zipPath, cdOffset, cdSize);
  if (cd === null) {
    return -1;
  }
  return dsZipCentralDirTotal(cd, entries);
}

// 解压根定位（照 ExportImportApply.locateDecompressRoot 两形态复刻——根目录有 manifest.json
// 直用；唯一子目录下钻一层；多子目录/无 manifest = 脏包，交由调用方报错）。函数体照先例，
// 不 import 改造（该函数彼件内私有）
function locateDsDecompressRoot(dir: string): string {
  if (dsFileExists(`${dir}/manifest.json`)) {
    return dir;
  }
  try {
    const subs: string[] = [];
    for (const name of fs.listFileSync(dir)) {
      try {
        if (fs.statSync(`${dir}/${name}`).isDirectory()) {
          subs.push(name);
        }
      } catch (e) {
        // 单项 stat 失败跳过
      }
    }
    if (subs.length === 1) {
      return `${dir}/${subs[0]}`;
    }
  } catch (e) {
    // 目录不可列 = 按 dir 原样（读取处会报中文错误）
  }
  return dir;
}

// 目录累计字节（递归；单文件 stat 失败跳过——体积闸按可读部分计，读不到的文件读取处自然报错）
function dsWalkTotalBytes(dir: string): number {
  let total: number = 0;
  let names: string[] = [];
  try {
    names = fs.listFileSync(dir);
  } catch (e) {
    return 0;
  }
  for (const name of names) {
    const child: string = dir + '/' + name;
    try {
      if (fs.statSync(child).isDirectory()) {
        total += dsWalkTotalBytes(child);
      } else {
        total += Math.max(dsFileSize(child), 0);
      }
    } catch (e) {
      // 单项失败跳过
    }
  }
  return total;
}

// 图片配对（IO 面）：按 export_path 在解压根下定位原件，存在且非空 → present = true 并回填
// sourceAbs；缺失/未导出/路径不在白名单 → present = false 计 missingImages（跳过不炸）
function dsResolveSessionImages(rootDir: string, session: DsParsedSession,
  report: DsParseReport): void {
  for (const msg of session.messages) {
    for (const img of msg.images) {
      if (img.exportRel === '' || !dsZipPathAllowed(img.exportRel)) {
        report.missingImages++;
        continue;
      }
      const abs: string = rootDir + '/' + img.exportRel;
      if (!dsFileExists(abs) || dsFileSize(abs) <= 0) {
        report.missingImages++;
        continue;
      }
      img.sourceAbs = abs;
      img.present = true;
    }
  }
}

// 解析一份 DS 导出 zip（唯一 IO 入口，预览与落库 apply 共用）。流程 = 解压到 cacheDir 专用
// 目录 → 解压根定位两形态 → 体积闸（解包累计 512MB）→ manifest 版本闸（≠3 拒）→ 白名单枚举
// 会话 JSON（单文件 20MB 闸）→ 逐会话解析 → 索引对账 → 图片配对。
// · 抛错 = 中文信息（非 DS 包 / 版本不符 / 超限 / 无可导入会话），调用方 toast。
// · 目录生命周期：内部失败路径自清；成功路径把 rootDir 交还调用方，**调用方必须 finally
//   dsReleaseParsedZip**（成对释放红线——任何退出路径都清，见文件头）。
export async function dsParseArchiveZip(ctx: common.Context, zipPath: string): Promise<DsParsedZip> {
  // ★ 2026-11-14 自检报告 §4.4 修：解压**前**先读中央目录声明总字节——原实现先整包解压
  // 再判 512MB，恶意/异常 zip 可先写满缓存盘再被拒。预扫不可解析（-1）不预判，解压后
  // dsWalkTotalBytes 闸照旧（双层：声明值早退 + 实际落盘兜底）
  const declaredTotal: number = dsZipDeclaredTotalBytes(zipPath);
  const declaredVerdict: string =
    declaredTotal >= 0 ? dsZipTotalSizeVerdict(declaredTotal) : '';
  if (declaredVerdict !== '') {
    throw new Error(declaredVerdict);
  }
  const dir: string = ctx.cacheDir + '/ds_import_' + Date.now().toString();
  fs.mkdirSync(dir, true);
  try {
    try {
      await zlib.decompressFile(zipPath, dir, {});
    } catch (zipErr) {
      // zlib 原始报错是英文技术信息——包成中文拒收口径（坏 zip / 非 zip 一体呈报）
      throw new Error('选择的文件不是合法的备份包，解压失败');
    }
    const root: string = locateDsDecompressRoot(dir);
    // 体积闸①：解包累计（先于任何 JSON 读取——超限早退不白读）
    const totalVerdict: string = dsZipTotalSizeVerdict(dsWalkTotalBytes(root));
    if (totalVerdict !== '') {
      throw new Error(totalVerdict);
    }
    // manifest 版本闸（缺 manifest = 非 DS 包；同闸覆盖「白名单外路径模式为主」的陌生 zip——
    // 无 manifest 即拒，白名单外文件本就不读）
    if (!dsFileExists(`${root}/manifest.json`)) {
      throw new Error('选择的文件不是 DeepSeek 导出备份包');
    }
    const manifestText: string = dsReadFileText(`${root}/manifest.json`);
    let manifest: Object | null = null;
    try {
      manifest = JSON.parse(manifestText) as Object;
    } catch (e) {
      manifest = null;
    }
    const manifestVerdict: string = dsManifestVerdict(manifest);
    if (manifestVerdict !== '') {
      throw new Error(manifestVerdict);
    }
    // 白名单枚举会话 JSON（目录枚举为准——索引只对账不驱动；单文件先过 20MB 闸再读）
    const counters: DsParseCounters = {
      badSessions: 0, brokenChainSessions: 0, missingCurrentSessions: 0, badMessageRows: 0,
      duplicateMessageRows: 0, droppedFragments: 0, preservedToolFragments: 0,
      oversizedSessions: 0, oversizedMaxNodes: 0
    };
    const sessions: DsParsedSession[] = [];
    const sessionsDir: string = root + '/chat_sessions';
    let names: string[] = [];
    try {
      names = fs.listFileSync(sessionsDir);
    } catch (e) {
      names = []; // 无会话目录 = 空包（下方统一报「无可导入会话」）
    }
    names.sort();
    for (const name of names) {
      if (!name.endsWith('.json')) {
        continue; // *_files 图片目录与非 JSON 条目不在白名单读取面
      }
      const path: string = sessionsDir + '/' + name;
      let isFile: boolean = false;
      try {
        isFile = fs.statSync(path).isFile();
      } catch (e) {
        isFile = false;
      }
      if (!isFile || !dsZipPathAllowed('chat_sessions/' + name)) {
        continue;
      }
      const sizeVerdict: string = dsJsonSizeVerdict(dsFileSize(path));
      if (sizeVerdict !== '') {
        throw new Error(sizeVerdict);
      }
      const session: DsParsedSession | null = dsParseSessionText(dsReadFileText(path), counters);
      if (session !== null) {
        sessions.push(session);
      }
    }
    if (sessions.length === 0) {
      throw new Error('备份包中没有可导入的会话');
    }
    // 索引对账（宽容：索引缺失/损坏/字段不合法一律静默跳过——会话枚举不依赖索引）
    let missingSessionFiles: number = 0;
    const indexPath: string = root + '/chat_session_index.json';
    if (dsFileExists(indexPath) && dsJsonSizeVerdict(dsFileSize(indexPath)) === '') {
      try {
        const indexParsed: Object = JSON.parse(dsReadFileText(indexPath)) as Object;
        if (Array.isArray(indexParsed)) {
          const sessionIds: Set<string> = new Set<string>();
          for (const s of sessions) {
            sessionIds.add(s.dsId);
          }
          for (const entry of indexParsed as Object[]) {
            if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
              continue;
            }
            const idValue: Object | undefined =
              (entry as Record<string, Object>)['id'];
            if (typeof idValue === 'string' && idValue !== '' && !sessionIds.has(idValue)) {
              missingSessionFiles++;
            }
          }
        }
      } catch (e) {
        // 索引读不出 = 跳过对账（宽容）
      }
    }
    // 图片配对 + 呈报面汇总（brokenChainSessions 在解析链内已按会话累计，直接转记）
    const report: DsParseReport = {
      sessionCount: sessions.length,
      messageCount: 0,
      imageCount: 0,
      brokenChainSessions: counters.brokenChainSessions,
      missingCurrentSessions: counters.missingCurrentSessions,
      badSessions: counters.badSessions,
      badMessageRows: counters.badMessageRows,
      duplicateMessageRows: counters.duplicateMessageRows,
      droppedFragments: counters.droppedFragments,
      preservedToolFragments: counters.preservedToolFragments,
      missingImages: 0,
      missingSessionFiles: missingSessionFiles,
      oversizedSessions: counters.oversizedSessions,
      oversizedMaxNodes: counters.oversizedMaxNodes
    };
    for (const s of sessions) {
      report.messageCount += s.messages.length;
      dsResolveSessionImages(root, s, report);
      for (const msg of s.messages) {
        for (const img of msg.images) {
          if (img.present) {
            report.imageCount++;
          }
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'DS 备份解析完成：会话 %{public}d 个，消息 %{public}d 行，图片 %{public}d 张',
      report.sessionCount, report.messageCount, report.imageCount);
    return { archive: { sessions: sessions, report: report }, rootDir: root };
  } catch (e) {
    // 失败路径自清（成功路径的 rootDir 由调用方释放）
    try {
      cleanupDir(dir);
    } catch (cleanupErr) {
      // 清不掉 = 启动清扫兜底，不吞原始错误
    }
    throw e as Error;
  }
}

// 释放解析句柄（调用方 finally 调用；cleanupDir 单源 = ExportImport）。
// ★ 自检轮修：rootDir 可能是解压目录的子目录（locateDsDecompressRoot 认「仅一个子目录」形态），
// 只清 rootDir 会让外层 ds_import_<ts> 空目录每次导入残留一个；外层带本族前缀时一并清
export function dsReleaseParsedZip(parsed: DsParsedZip): void {
  try {
    cleanupDir(parsed.rootDir);
    const cut: number = parsed.rootDir.lastIndexOf('/');
    if (cut > 0) {
      const parent: string = parsed.rootDir.slice(0, cut);
      if (parent.indexOf('/ds_import_') >= 0) {
        cleanupDir(parent);
      }
    }
  } catch (e) {
    // 清不掉 = 启动清扫兜底（sweepExportTemp 已登记 ds_import_ 前缀，进程重启即清），留痕不炸
    hilog.warn(DOMAIN, TAG, 'DS 备份解压临时目录清理失败（启动清扫兜底）：%{public}s',
      (e as Error).message);
  }
}
