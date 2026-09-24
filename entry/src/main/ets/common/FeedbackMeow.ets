// MeoW 反馈推送通道（2026-09-07 应用内反馈新增）：用户在反馈页提交的文本经第三方推送
// 服务 MeoW（api.chuckfang.com）直达开发者手机——零自有服务器方案（调研与 Cube 逆向
// 底账 = docs/调研-应用内反馈方案与Cube-Meow链路逆向-20260907.md；决明指令「先测试
// 给我推一条，成功后再进应用」，测试推送当日业务码 200 实证后接入）。
// 接口形态（MeoW 官方 api_doc + meow-push-skill 快照口径，2026-09-07 实测验证）：
// · 推荐 POST /{昵称} + JSON body { title, msg }（官方「普通消息优先采用 POST JSON」）；
// · title = 推送卡片标题，固定「AI控制台用户反馈」（2026-09-07 决明校正：用户简述的
//   问题类型不进 title——标题行拼在 msg 正文首行，见下方组装）；
// · 昵称在 URL 路径段且含中文——必须逐段 encodeURIComponent（encodeURIComponent 官方
//   全局函数，TitleApi model 名同款用法），禁整串编码；
// · ★ HTTP 状态码恒 200，成功与否看响应体业务码 status（200=成功 / 404=昵称未注册 /
//   429=超限「3 秒 1 条、分钟 15、小时 60、日 1000」/ 403=风控）；
// · 无 SDK 无鉴权，昵称即地址；推送不幂等，超时/异常不自动重试（官方 skill 明示）。
// 本层只报事实不决策（TitleApi 同款口径）：不 toast 不跳页，结果交 FeedbackPage 呈报。
// ★ 请求日志（2026-09-24 扩面笔）：本链五条返回路径（HTTP 非 200 / 响应非 JSON / 业务码非
// 200 / 成功 / 网络异常）逐条手写收尾必漏，故收敛到 settle 一处。★ 状态码口径：日志的
// status 恒记**HTTP 码**（本链成功与业务失败都是 200），业务码只进 error 文案——ReqLog 的
// 「正数 = HTTP 响应码」不变量不可破（reqLogAdvice 按 HTTP 码给建议）。代价 = 业务失败在
// 列表不标红（详情面板 error 行照实显示），与 metaso 的「HTTP 200 + 内嵌 errCode」同族，
// 已在变更记录技术债务清单登记
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from './ReqLog';

// ★ 安全红线登记（AGENTS.md「安全红线」节有指针）：MeoW 推送昵称集中本文件单点维护，
// 改名只改此一处。该值是「公开推送地址」而非密钥——专属链接本就随应用分发，任何知道
// 昵称的人都可向该昵称发消息，泄露后果 = 开发者收骚扰推送（MeoW 服务端限频兜底）。
const MEOW_FEEDBACK_NICKNAME: string = 'Pluto的AI控制台';
const MEOW_PUSH_BASE: string = 'https://api.chuckfang.com/';
// 推送标题固定——开发者侧一眼识别「这是用户反馈」（2026-09-07 决明校正：不拼用户简述，
// 标题框内容走 msg 正文首行）
const FEEDBACK_TITLE: string = 'AI控制台用户反馈';
const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

// 请求体（只声明显式接口——ArkTS 对象字面量须挂类型，坑59）
interface MeowPushBody {
  title: string;
  msg: string;
}

// MeoW 响应体（只声明消费的字段，同坑59；官方形态 {status, data, msg}）
interface MeowPushResponse {
  status?: number;
  msg?: string;
}

// 发送结果（FeedbackPage 呈报用）：ok=false 时 errorMessage 已是可直接 toast 的中文，
// 含错误码（用户读一个数字即根因——真机阻塞修复路线裁决口径）
export interface FeedbackSendResult {
  ok: boolean;
  errorMessage: string;
  status: number; // 业务码或 HTTP 码；-1 = 网络错误无状态码
}

// 发送反馈推送（非流式一次响应；TitleApi 同款骨架——request 用完即毁 + finally destroy，
// 无事件绑定）。title 恒为固定前缀；title 参数 = 反馈页标题框的用户简述（已限长 20 字，
// 此处再 trim 兜底）——非空则作为正文首行「标题：…」，空则只有正文（正文已含环境行）
export function sendFeedbackPush(content: string, title: string): Promise<FeedbackSendResult> {
  return new Promise<FeedbackSendResult>((resolve) => {
    const trimmed: string = title.trim();
    const fullMsg: string = trimmed === '' ? content : '标题：' + trimmed + '\n' + content;
    const body: MeowPushBody = { title: FEEDBACK_TITLE, msg: fullMsg };
    const bodyText: string = JSON.stringify(body);
    const url: string = MEOW_PUSH_BASE + encodeURIComponent(MEOW_FEEDBACK_NICKNAME);
    // 请求头提为局部量：请求日志要与发送侧同一份（内联字面量在 options 里取不出来，同
    // ModelListApi 注释）
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: bodyText,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      source: '用户反馈', model: '', method: 'POST', url: url, headers: header, body: bodyText
    });
    // 收尾单点（结果与日志同出）：httpCode 与 result.status 是**两个**量——本链业务码
    // （429/404/403）不是 HTTP 码，日志只认前者（见文件头状态码口径）
    const settle = (result: FeedbackSendResult, httpCode: number, respHeader: Object | null,
      tail: string): void => {
      if (respHeader !== null) {
        reqLogSetResponseHeaders(logId, respHeader);
      }
      reqLogEnd(logId, httpCode, Date.now() - startedAt,
        result.ok ? '' : result.errorMessage, tail);
      resolve(result);
    };
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        // 官方文档明示 HTTP 状态恒 200——非 200 属传输层异常，防御性报错不静默（P0-1）
        if (resp.responseCode !== 200) {
          settle({ ok: false,
            errorMessage: '发送失败(HTTP ' + resp.responseCode + ')，请稍后重试',
            status: resp.responseCode }, resp.responseCode, resp.header,
            typeof resp.result === 'string' ? resp.result : '');
          return;
        }
        const text: string = typeof resp.result === 'string' ? resp.result : '';
        let respObj: MeowPushResponse;
        try {
          respObj = JSON.parse(text) as MeowPushResponse;
        } catch (e) {
          settle({ ok: false, errorMessage: '推送服务响应异常，请稍后重试', status: 200 },
            200, resp.header, text);
          return;
        }
        if (respObj.status === 200) {
          settle({ ok: true, errorMessage: '', status: 200 }, 200, resp.header, '');
          return;
        }
        // 业务码直出（429 超限 / 404 昵称未注册 / 403 风控）——错误码给全不吞
        const biz: number = respObj.status === undefined ? -2 : respObj.status;
        const bizMsg: string = typeof respObj.msg === 'string' && respObj.msg !== '' ? '：' + respObj.msg : '';
        settle({ ok: false, errorMessage: '发送失败(code ' + biz + ')' + bizMsg, status: biz },
          200, resp.header, text);
      })
      .catch((e: Object): void => {
        const biz = e as BusinessError;
        const code: string = typeof biz.code === 'number' ? '(code ' + biz.code + ')' : '';
        settle({ ok: false, errorMessage: '网络错误' + code + '，请检查网络后重试', status: -1 },
          -1, null, '');
      })
      .finally((): void => {
        // destroy 包 try（同 ModelListApi / TitleApi / KeyConnectTester 先例）：裸 destroy 抛错
        // 会从 finally 穿出成未捕获的 promise 拒绝——本层无日志设施，故静默忽略
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}
