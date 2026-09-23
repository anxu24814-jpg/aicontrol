// 服务商账户余额 API（2026-08-30 详情页改版新增）：GET {余额BaseURL}{API路径} 拉账户
// 余额——恒 GET（任务书拍板：不做请求方法切换）；Authorization: Bearer {专用余额Key，
// 空 = 回退聊天密钥} + Accept 默认头；2026-08-31 起支持自定义头——query.headers 逐条
// 追加且允许覆盖默认头（同名覆盖，serializeHeaderPairs 已在入库侧丢空行）。响应 JSON
// 经点路径（如 balance_infos[0].total_balance，点分段 + [数字] 下标链）取余额文本与
// 币种——手写 ~30 行解析函数，禁第三方库（任务书红线）。
// 网络层形态照 ModelListApi.ets 先例（@kit.NetworkKit http.request 一次性响应、三错误
// 路径全中文、错误重包 Error、describeNetError 独立成份避免为一行复用引互引）；本层
// 只取数不落库（余额文本落库在 ProviderBalanceDb.saveBalanceText，调用方编排）。
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HeaderPair } from './AiTypes';

const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

// 查询入参（余额专用端点与解析路径；baseUrl 为空 = 调用方已回退服务 baseUrl 后传入；
// headers = 自定义请求头，空 k/v 行调用方已滤——此处仍防御性跳过）
export interface BalanceQuery {
  baseUrl: string;
  path: string;
  key: string;
  resultPath: string;
  currencyPath: string;
  headers: HeaderPair[];
}

// 查询结果（text = 余额文本；currency = 点路径取到的币种，未取到回 ''——配置币种兜底
// 由调用方组合）
export interface BalanceResult {
  text: string;
  currency: string;
}

// 网络层错误描述（ModelListApi 同款口径，独立成份——两文件零 import 依赖）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}

// 非 200 响应取 error.message（OpenAI 兼容方言错误体；缺失回 '' 由调用方拼提示）
function extractApiError(body: string): string {
  try {
    const parsed: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
    const err: Object | undefined = parsed['error'];
    if (err !== undefined) {
      const errMap: Record<string, Object> = err as Record<string, Object>;
      const msg: Object | undefined = errMap['message'];
      if (typeof msg === 'string' && msg !== '') {
        return msg;
      }
    }
  } catch (e) {
    // 非 JSON 错误体：原文截尾提示
  }
  return '';
}

// 点路径取值（a.b[0].c 形态：点分段对象键 + [数字] 数组下标链；值转字符串——string
// 原样、number/boolean 转字面量；路径空/中途类型不符/越界 = '' 不抛错——币种路径可选
// 语义；余额路径取空由调用方报「未取到」）
function readJsonPath(root: Record<string, Object>, path: string): string {
  if (path === '') {
    return '';
  }
  let cur: Object | undefined = root;
  const segments: string[] = path.split('.');
  for (const seg of segments) {
    if (cur === undefined || cur === null) {
      return '';
    }
    // 分段 = 键名 + 可选 [n][m]… 下标链（键可为空 = 路径以 [0] 起头）
    const bracketAt: number = seg.indexOf('[');
    const key: string = bracketAt < 0 ? seg : seg.substring(0, bracketAt);
    let indices: string = bracketAt < 0 ? '' : seg.substring(bracketAt);
    if (key !== '') {
      if (typeof cur !== 'object' || Array.isArray(cur)) {
        return '';
      }
      cur = (cur as Record<string, Object>)[key];
    }
    while (indices.startsWith('[')) {
      const close: number = indices.indexOf(']');
      if (close < 0) {
        return '';
      }
      const idx: number = Number(indices.substring(1, close));
      if (Number.isNaN(idx) || !Array.isArray(cur)) {
        return '';
      }
      cur = (cur as Object[])[idx];
      indices = indices.substring(close + 1);
    }
  }
  if (typeof cur === 'string') {
    return cur;
  }
  if (typeof cur === 'number' || typeof cur === 'boolean') {
    return String(cur);
  }
  return '';
}

// 查询账户余额：GET → 200 校验 → JSON 解析 → 点路径取值；失败 reject Error（中文提示，
// 调用方 toast 呈现，P0-1 不静默）
export function fetchBalance(query: BalanceQuery): Promise<BalanceResult> {
  return new Promise<BalanceResult>((resolve, reject) => {
    // 拼接：去尾斜杠 + 保证路径以 / 起头（模板路径已带，用户手填漏扛也能拼对）
    const base: string = query.baseUrl.trim().replace(/\/+$/, '');
    const path: string = query.path.trim().startsWith('/') ? query.path.trim() : '/' + query.path.trim();
    const url: string = base + path;
    const request: http.HttpRequest = http.createHttp();
    // 默认认证头 + 自定义头逐条覆盖（同名覆盖语义——如 new-api 系 New-Api-User 校验头）
    const header: Record<string, string> = {
      'Authorization': 'Bearer ' + query.key.trim(),
      'Accept': 'application/json'
    };
    for (const pair of query.headers) {
      if (pair.k.trim() !== '' && pair.v.trim() !== '') {
        header[pair.k.trim()] = pair.v.trim();
      }
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        if (resp.responseCode !== 200) {
          const body: string = typeof resp.result === 'string' ? resp.result : '';
          const detail: string = extractApiError(body);
          const suffix: string = detail !== '' ? '：' + detail :
            (body !== '' ? '：' + body.slice(0, 200) : '，响应无内容');
          reject(new Error('余额查询失败(HTTP ' + resp.responseCode + ')' + suffix));
          return;
        }
        const text: string = typeof resp.result === 'string' ? resp.result : '';
        try {
          const parsed: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
          const balance: string = readJsonPath(parsed, query.resultPath.trim());
          if (balance === '') {
            reject(new Error('未取到余额：检查「结果 JSON 路径」是否匹配响应结构'));
            return;
          }
          const result: BalanceResult = { text: balance, currency: readJsonPath(parsed, query.currencyPath.trim()) };
          resolve(result);
        } catch (e) {
          reject(new Error('余额查询失败：响应不是有效 JSON'));
        }
      })
      .catch((e: Object): void => {
        reject(new Error('余额查询失败：' + describeNetError(e)));
      })
      .finally((): void => {
        request.destroy();
      });
  });
}
