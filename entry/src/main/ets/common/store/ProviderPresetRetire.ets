// 内置境外服务商退役执行器（合规整改①，决明「去掉所有内置境外服务商」；
// 上架台账 = docs/上架流程清单.md 同日第二条）：
// · 为什么需要本件：模板 / 预置清单删除只影响**新装**；存量设备上旧版本首启 seed 已把
//   OpenAI / Anthropic / Gemini / OpenRouter / OpenCode 五行落进 providers 表并标
//   builtin=1——数据层禁删、UI 菜单不出删除项、AI 工具也拒删，用户自己**无法移除**。
//   故启动时清一次（EntryAbility 与 seed 同批 fire-and-forget，幂等：删完后无行命中，
//   每次启动只是一次空查询）。
// · 认行判据 = builtin=1 且 baseUrl 命中 ProviderCatalog.RETIRED_OVERSEAS_ORIGINS 域名
//   （URL 是家的客观标识，用户改名不影响；用户手建的同名 / 同址行 builtin=0，不碰）。
// · 删除口径 = 与 UI 单家删除**同一条三步链**（查池条目 id 集 → deleteProvider 事务级联
//   → removePoolKeys 清 Asset 明文），不另抄实现。allowBuiltin=true 放行口之一（另有
//   ProviderBuiltinDedup 收敛执行器，白名单见 ProviderDb.deleteProvider 尾参注释）。
// · 数据说明（合规决策，变更记录一千七百一十五节）：这些出厂行上一旦被用户填过 Key /
//   建过模型，随行级联一并删除（含助手绑定复位、会话级覆盖清理、价格模板清空）；需要继续
//   使用该境外服务的用户，按自定义服务商重新添加即可（三协议与自定义地址能力未缩）。
// · 失败语义：单行失败即整体抛给调用方（hilog 留痕、下次启动重试）；Asset 明文清理顺序
//   不可换——行删后拿不到 id 集，会留下跨卸载保留的孤儿密钥明文。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isRetiredOverseasOrigin } from '../providers/ProviderCatalog';
import { deleteProvider, ProviderRow, queryProviders } from './ProviderDb';
import { ProviderKeyRow, queryProviderKeys } from './ProviderKeyDb';
import { removePoolKeys, removeProviderKey } from './KeyStore';

const DOMAIN: number = 0xD5A3;
const TAG: string = 'ProviderPresetRetire';

// 清理存量内置境外行（返回实删行数；调用点 = EntryAbility onCreate 迁移链尾）
export async function retireOverseasBuiltinProviders(): Promise<number> {
  const rows: ProviderRow[] = await queryProviders();
  let removed: number = 0;
  for (const row of rows) {
    if (!row.builtin || !isRetiredOverseasOrigin(row.baseUrl)) {
      continue;
    }
    // 池条目 id 先于删行查得（Asset 无前缀枚举，行删后拿不到 id 集——成对释放红线，
    // 与 ProviderPage.deletePending / ProviderDb.clearAllProviders 同一顺序）
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(row.id);
    const keyIds: string[] = keyRows.map((key: ProviderKeyRow): string => key.id);
    removed += await deleteProvider(row.id, true);
    await removePoolKeys(row.id, keyIds);
    // 遗留单 key（v2 形态）同删：极老库可能还没被单 key 池迁移收走，别名由 id 直推、
    // 不存在时静默通过（removeByAlias 幂等），成本一次 Asset 查询
    await removeProviderKey(row.id);
    hilog.info(DOMAIN, TAG, '已退役内置境外服务商：%{public}s（%{public}s）',
      row.name, row.baseUrl);
  }
  if (removed > 0) {
    hilog.info(DOMAIN, TAG, '内置境外服务商退役完成（%{public}d 家）', removed);
  }
  return removed;
}
