// 确认卡等待载荷的跨进程编解码（2026-11-08 两千一百二十八笔新增）。
// 职责一句话：把「这行工具调用正等用户确认」的卡面状态（说明串 / 档位 / 明细 / 目标域 /
// 审批闸说明）编进等待行的工具结果位，并在回放时原样解出——确认卡重进后可继续作答。
// · 为什么塞 result 而不加列/加键：落库序列化白名单恒五键（toolCallId / name / argsJson /
//   result / isError，serializeToolRecord 是「base64 不落库」的唯一闸），加键或加列都会破
//   白名单契约与零迁移口径。等待行的 result 本就恒空（等待中无结果），借它承载暂停态载荷
//   不动任何既有键义；结算时 record.result 被真实结果覆盖，载荷自然消失。
// · 识别判据必须强：只有带 pending_confirm 对象且 text 非空的 JSON 才算等待载荷——工具
//   真实结果里不可能出现该键（模型产出的业务 JSON 也不会），误判面为零。
// · 为什么新开本件：写侧（ChatToolRoundCtrl）与读侧（ChatMessageProjection）分属两域，
//   放任一侧都会让另一侧反向依赖；纯函数叶件是零环红线（坑50）下的唯一单源位置。
import { CONFIRM_LEVEL_WRITE } from '../../common/providers/ToolContracts';

// 等待载荷键（落库 JSON 顶层键名；解析与构造同源）
export const CONFIRM_WAIT_KEY: string = 'pending_confirm';

// 卡面暂停态（与 ChatMessage.toolConfirm* 运行时字段一一对应；aiNote 空 = 未配审批模型）
export interface ConfirmWaitState {
  text: string;
  level: string;
  detail: string;
  domain: string;
  aiNote: string;
}

// 落库信封（外层显式接口——ArkTS 禁无类型对象字面量，arkts-no-untyped-obj-literals）
interface ConfirmWaitEnvelope {
  pending_confirm: ConfirmWaitState;
}

// 编码：等待行 result 位的载荷串（text 为空 = 无卡面主因句，不编码——回空串让调用方走
// 普通工具卡路径，不伪造等待态）
export function buildConfirmWaitPayload(state: ConfirmWaitState): string {
  if (state.text === '') {
    return '';
  }
  const envelope: ConfirmWaitEnvelope = {
    pending_confirm: {
      text: state.text,
      level: state.level,
      detail: state.detail,
      domain: state.domain,
      aiNote: state.aiNote
    }
  };
  return JSON.stringify(envelope);
}

// 解码（回放侧）：合法 JSON + pending_confirm 对象 + text 非空才成立；坏形/缺键一律回
// null（fail-safe：调用方按普通工具结果处理，不炸历史重建）
export function parseConfirmWaitPayload(result: string): ConfirmWaitState | null {
  if (result === '' || result.indexOf(CONFIRM_WAIT_KEY) < 0) {
    return null; // 先做子串快筛：绝大多数结果不含该键，免一次 JSON.parse
  }
  let parsed: object;
  try {
    parsed = JSON.parse(result) as object;
  } catch (e) {
    return null;
  }
  if (parsed === null || Array.isArray(parsed)) {
    return null;
  }
  const rec = parsed as Record<string, Object>;
  const raw: Object | undefined = rec[CONFIRM_WAIT_KEY];
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return null;
  }
  const body = raw as Record<string, Object>;
  const text: Object | undefined = body['text'];
  if (typeof text !== 'string' || text === '') {
    return null;
  }
  const level: Object | undefined = body['level'];
  const detail: Object | undefined = body['detail'];
  const domain: Object | undefined = body['domain'];
  const aiNote: Object | undefined = body['aiNote'];
  return {
    text: text as string,
    level: typeof level === 'string' ? level as string : CONFIRM_LEVEL_WRITE,
    detail: typeof detail === 'string' ? detail as string : '',
    domain: typeof domain === 'string' ? domain as string : '',
    aiNote: typeof aiNote === 'string' ? aiNote as string : ''
  };
}
