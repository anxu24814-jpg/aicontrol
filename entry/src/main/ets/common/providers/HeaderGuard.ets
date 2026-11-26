// 凭据类请求头判据与增量合并纯函数（2026-10-04 AI 配置服务商笔，任务书
// -AI配置服务商与安全输入-20261004 §3.5）：AI 配置工具 set_headers / manage_balance 的
// 头操作共用的两枚判定——凭据类头名黑名单（命中即整调用拒，引导用户手动填）+ 增量 merge
// （保留未提及行 / 同名覆盖 / 按名删）。
// ★ 零 import 叶子件（ConnectTestJudge 先例）：断言脚本把本文件复制为 .ts 直跑同一实现，
// 引一次外部绑定就把可直跑根基带走；域件消费本件 = 单向无环。
// ★ 词表取**严**侧（任务书拍板）：'key' 子串会误拒 X-Keywords 类头——误拒代价 = 用户到
// 详情页手动添加，可接受；漏放代价 = 凭据被 AI 写进配置，不可接受。误拒兜底句在 desc 与
// 各回执（「请让用户在服务商详情页手动添加」）。
const CREDENTIAL_HEADER_MARKERS: string[] = [
  'authorization', 'token', 'cookie', 'secret', 'credential', 'key'
];

// 头名是否属凭据类（黑名单子串匹配：小写化后 includes 任一标记词即命中；trim 后判、空名
// 恒不命中——空行由 serializeHeaderPairs 在入库侧丢弃，不进本判据）
export function isCredentialHeaderName(name: string): boolean {
  const lower: string = name.trim().toLowerCase();
  if (lower === '') {
    return false;
  }
  for (const marker of CREDENTIAL_HEADER_MARKERS) {
    if (lower.includes(marker)) {
      return true;
    }
  }
  return false;
}

// 头键值对（结构与 AiTypes.HeaderPair 同形——本件零 import 故自带一份；两侧字段名恒 k/v，
// 消费方逐字段映射，禁结构合并）
export interface HeaderKV {
  k: string;
  v: string;
}

// 增量合并（不就地改——返回新数组）：保留未提及的原有行；add 同名（大小写不敏感）覆盖该行
// 值、异名追加到尾；removeKeys 按名（大小写不敏感）删。同名判定取**首个**同名行（serialize
// 侧本就丢重名，防御脏数据形态）
export function mergeHeaderPairs(existing: HeaderKV[], add: HeaderKV[],
  removeKeys: string[]): HeaderKV[] {
  const removed: string[] = removeKeys.map((key: string): string => key.trim().toLowerCase())
    .filter((key: string): boolean => key !== '');
  const kept: HeaderKV[] = existing.filter((pair: HeaderKV): boolean =>
    !removed.includes(pair.k.trim().toLowerCase()));
  for (const pair of add) {
    const name: string = pair.k.trim();
    if (name === '') {
      continue; // 空名行丢弃（serializeHeaderPairs 同口径）
    }
    const lower: string = name.toLowerCase();
    const hit: number = kept.findIndex((row: HeaderKV): boolean =>
      row.k.trim().toLowerCase() === lower);
    if (hit >= 0) {
      kept[hit] = { k: kept[hit].k, v: pair.v };
    } else {
      kept.push({ k: name, v: pair.v });
    }
  }
  return kept;
}
