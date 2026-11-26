// 挂载删除工具域（2026-10-13 浏览页删除与跳转笔拆件）：本件 = mount_delete 一件的 desc /
// schema / 确认预检 / 执行器，方法体自 ToolMount.ets 原样搬迁（该件本笔新增删除后剔头越
// 1200 硬线，按宪法「越线须先把本次改动所属功能域拆到独立文件」+ 独立工具域先拆同族先例
// 〔ToolClipboard / ToolWebSearch〕拆出）。职责缝一句话：把挂载内文件或文件夹删除到系统
// 回收站（可恢复）的 AI 工具件。
// · 共用骨架单源在 ToolMount（公共闸 mountGate / args 解析两枚 / 懒激活 / 根路径转换——
//   本域六件共用的装载与授权骨架，本件只引不复制，禁第二实现）。
// · 删除本体单源 common/MountTrash.ets（回收站调用 + 能力门 + 失败文案，与浏览页删除共用）。
// · 语义口径（设计定稿，勿改）：恒走回收站**不降级永久删除**；确认链**恒不可逆档**（删除是
//   最高破坏性动作——谨慎 / 标准档恒问、无「本会话内允许」第三键；高效档由 routeConfirmPrompt
//   统一放行，仅密码恒禁仍是地板）；TOCTOU 纪律（照 copy_in 便签先例）：预检把探测结论**恒落便签**
//   ctx.preflightMemo——条目在 = 身份串（执行器删除调用前复探比对、不一致即拒，防「用户确认后
//   被外部应用换成另一个同名内容」的误删）；条目不在 = missing 哨兵（不弹卡、执行器按哨兵拒
//   ——防同一轮并发写工具或外部应用在预检与执行窗口内创建同名条目后，本调用把它未经确认删除；
//   自检轮 2026-10-13 修：原实现 stat 失败不落便签，执行器无守卫直接走回收站调用）。残留窗口 =
//   复探到 deleteToTrash 之间的微秒级（平台无原子比对位），登记于变更记录。
import { fileIo as fs } from '@kit.CoreFileKit';
import { ToolExecutor, toolArgsParseErrorText, ConfirmPrompt,
  CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_ROUTE_HUMAN } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { queryFolderMounts } from '../store/ChatDb';
import { FolderMountRow } from '../store/MountDb';
import { MOUNT_MODE_READ_WRITE, composeMountDeleteReply, joinMountPath,
  mountModeLabel, mountRelPathNormalize, mountRelPathRejectReason } from '../MountUtil';
import { MountTrashOutcome, deleteMountEntryToTrash } from '../MountTrash';
import { MountGateOutcome, argsMountId, argsString, ensureMountActivated,
  mountGate, mountRootPathFromUri } from './ToolMount';

export const MOUNT_DELETE_DESC: string =
  '删除文件夹挂载里的文件或文件夹，删除的内容会放进系统文件管理的回收站，之后可以恢复。只对读写模式的挂载可用，只读挂载会返回错误。mountId 是挂载编号，取自 mount_list 回执里的清单。path 是要删除的内容在挂载内的相对路径，文件与文件夹都可以。每次删除前都会单独征求用户确认。删除针对的是用户授权文件夹里的原文件，请谨慎使用。';

export const MOUNT_DELETE_SCHEMA: string = '{"type":"object","properties":{' +
  '"mountId":{"type":"number","description":"挂载编号，取自 mount_list 回执里的挂载清单。必须是读写模式的挂载。"},' +
  '"path":{"type":"string","description":"要删除的文件或文件夹在挂载内的相对路径，例如 资料/笔记.md 或 资料/旧稿。"}},' +
  '"required":["mountId","path"]}';

// ── 确认预检与执行器（执行器闸序 = 公共闸 → 模式闸 → 便签复探 → 回收站删除）──

// 删除预检便签前缀（载荷 = 条目身份串；本域自定义词表，信道 = 执行上下文 preflightMemo——
// 与 copy_in 两 token 同信道不同载荷，逐调用隔离故互不干扰）
const MOUNT_DELETE_MEMO_PREFIX: string = 'entry:';

// 删除预检便签「条目不在」哨兵（★ 自检轮新增）：预检探测时条目不在 = 不弹卡、写本哨兵；
// 执行器按哨兵拒（照 copy_in 先例「预检结论恒落便签，执行器按便签分臂」——原实现此路径
// 不落便签，执行器对它无守卫：同轮并发写工具或外部应用在窗口内创建同名条目即未经确认删除）
const MOUNT_DELETE_MEMO_MISSING: string = 'missing:';

// 条目身份串（mtime 取 Stat.mtime 秒值——坑32 同源口径；目录与文件同式）
function mountEntryIdentity(st: fs.Stat): string {
  return MOUNT_DELETE_MEMO_PREFIX + (st.isDirectory() ? 'd' : 'f') + '|' + st.mtime + '|' + st.size;
}

// 确认预检（删除 = 恒不可逆档；fail-closed 边界 = 条目 stat 成功之后：其后的异常返保守人工
// 卡且按不可逆档——与 copy_in 保守卡同档同因：catch 时目标状态未知，加严恰好堵住
// 「本会话内允许」漏过未知状态的面）。契约：全包 try/catch 恒不抛
export async function mountDeleteNeedsConfirm(argsJson: string,
  ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let mountId = 0;
  let path = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    mountId = argsMountId(parsed, 'mountId');
    path = argsString(parsed, 'path').trim();
  } catch (e) {
    return null; // 坏形态：执行器必有参数错误回执
  }
  if (!(mountId > 0) || path === '') {
    return null; // 执行器必拒
  }
  if (mountRelPathRejectReason(path) !== '') {
    return null; // 执行器路径闸必拒（无需弹卡问人一个必拒动作）
  }
  let entryProbed = false;
  try {
    const rows: FolderMountRow[] = await queryFolderMounts();
    let row: FolderMountRow | undefined = undefined;
    for (const candidate of rows) {
      if (candidate.id === mountId) {
        row = candidate;
        break;
      }
    }
    if (row === undefined) {
      return null; // 执行器查行闸拒
    }
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return null; // 只读挂载：执行器模式闸拒
    }
    // 条目探测前置 = 激活（与执行器同闸同缓存——未激活 stat 必失准）；激活失败 = 执行器必报
    // 授权文案，不弹卡
    try {
      await ensureMountActivated(row);
    } catch (e) {
      return null;
    }
    const relPath: string = mountRelPathNormalize(path);
    if (relPath === '') {
      return null; // 执行器必拒（根不可删）
    }
    const absPath: string = joinMountPath(mountRootPathFromUri(row.dirUri), relPath);
    let st: fs.Stat;
    try {
      st = fs.statSync(absPath);
    } catch (e) {
      // 条目探测失败（不在）——不弹卡；便签落 missing 哨兵，执行器按哨兵拒（防同一轮并发
      // 写工具或外部应用在预检与执行窗口内创建同名条目后被本调用未经确认删除；照 copy_in
      // 先例：预检结论恒落便签——条目在 = 身份串 / 不在 = 哨兵，执行器按便签分臂）
      ctx.preflightMemo = MOUNT_DELETE_MEMO_MISSING;
      return null;
    }
    entryProbed = true;
    // ★ TOCTOU 便签写点：stat 成功后写条目身份串（载荷与读点见文件头）
    ctx.preflightMemo = mountEntryIdentity(st);
    const what: string = st.isDirectory() ? '文件夹' : '文件';
    const prompt: ConfirmPrompt = {
      text: '助手要删除挂载「' + row.name + '」里的' + what + '「' + relPath +
        '」，删除后可以从系统文件管理的回收站恢复。',
      level: CONFIRM_LEVEL_IRREVERSIBLE,
      detail: '删除的对象是用户授权文件夹里的原文件 · 删除会放进系统回收站，恢复需要用户到' +
        '系统文件管理里操作'
    };
    // 恒不可逆档归一（数据管理档：不可逆档只在高效档放行，谨慎 / 标准档恒问）
    return routeConfirmPrompt(prompt, dataApproveMode());
  } catch (e) {
    if (!entryProbed) {
      // 探测前异常（清单读取 / 根路径转换等）⇒ 执行器公共闸同路径必拒，不弹卡
      return null;
    }
    // fail-closed：条目已探测后的异常 = 状态在确认链内未知 ⇒ 不可逆档保守人工卡（见函数头注）
    return {
      text: '删除前的确认检查出现异常，本次删除需要你确认。',
      level: CONFIRM_LEVEL_IRREVERSIBLE,
      route: CONFIRM_ROUTE_HUMAN
    };
  }
}

export class MountDeleteExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return JSON.stringify({ error: '缺少挂载编号。请先调用 mount_list 查看挂载清单，' +
        '再带 mountId 与 path 重试。' });
    }
    // 闸序①公共闸
    const gate: MountGateOutcome = await mountGate(mountId, argsString(parsed, 'path'));
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场
    // 闸序②模式闸（只读挂载拒删——mount_write / mount_copy_in 同句族）
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return JSON.stringify({ error: '「' + row.name + '」是' + mountModeLabel(row.mode) +
        '挂载，不能删除。请让用户在 设置 → 文件夹挂载 中把它切换为读写模式。' });
    }
    if (gate.relPath === '') {
      return JSON.stringify({ error: '请给出要删除的文件或文件夹路径，不能删除挂载根目录。' });
    }
    const fullPath: string = joinMountPath(gate.rootPath, gate.relPath);
    // ★ 闸序③便签复探（TOCTOU 失败关闭臂——照 copy_in 先例）：预检把探测结论恒落便签，
    // 此处按便签分臂——missing 哨兵 = 预检时条目不在（未弹卡、用户零确认）⇒ 直接拒（防窗口
    // 内条目出现被未经确认删除）；身份串 = 删除调用前复探比对，不一致（或已不在）即拒并如实
    // 提示，防「确认后被外部应用换成另一个同名内容」的误删；便签 ''（唯一来源 = 预检异常走
    // 保守人工卡、获批后无便签）= 人工已确认「状态未知」⇒ 放行。各臂内零删除调用（顺序即
    // 证明）；残留窗口 = 复探到 deleteToTrash 之间的微秒级
    let isDir: boolean = false;
    if (ctx.preflightMemo === MOUNT_DELETE_MEMO_MISSING) {
      return JSON.stringify({ error: '「' + gate.relPath + '」不在挂载里。本次删除已取消，' +
        '请用 mount_list 重新确认后再试。' });
    }
    if (ctx.preflightMemo !== '') {
      let nowIdentity: string = '';
      try {
        const stNow: fs.Stat = fs.statSync(fullPath);
        nowIdentity = mountEntryIdentity(stNow);
        isDir = stNow.isDirectory();
      } catch (e) {
        return JSON.stringify({ error: '「' + gate.relPath + '」在确认之后已经不在挂载里。' +
          '本次删除已取消，请用 mount_list 重新确认后再试。' });
      }
      if (nowIdentity !== ctx.preflightMemo) {
        return JSON.stringify({ error: '「' + gate.relPath + '」在确认之后发生了变化，' +
          '可能已被其他应用改动。为避免删除未经确认的内容，本次删除已取消。请重新发起删除。' });
      }
    } else {
      // 无便签（保守人工卡获批路径）：现读类型仅供回执措辞（读失败按「文件」兜底——回执非
      // 安全面，删除结果本身由共享件如实回传）
      try {
        isDir = fs.statSync(fullPath).isDirectory();
      } catch (e) {
        isDir = false;
      }
    }
    // 闸序④删除本体（共享件——与浏览页删除同一实现；能力门 / URI 拼接 / 失败文案全在该件）
    const outcome: MountTrashOutcome = await deleteMountEntryToTrash(row.dirUri, gate.relPath);
    if (!outcome.ok) {
      return JSON.stringify({ error: outcome.errorText });
    }
    return composeMountDeleteReply(row.name, gate.relPath, isDir);
  }
}
