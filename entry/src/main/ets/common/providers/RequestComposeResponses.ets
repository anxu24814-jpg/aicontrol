// OpenAI Responses 协议请求体组装域（DS 全家桶二期 S3 自 RequestCompose 域级最小拆分迁出）。
// 一句话职责 =「请求历史 + 采样 + 工具声明 → /responses 请求体 JSON」——纯函数面；CC /
// Anthropic / Gemini 三段留在 RequestCompose 一行未动。
// · 拆出理由（宪法 1200 硬线）：S3 加官方联网裸 tools 项、safety_check / title 与整 output
//   回传后该件剔头超线；按域级最小拆分把整个 Responses 段外迁。
// · 依赖方向：本件 → RequestCompose（共用叶子 parseToolSchema / isRemoteFilePart /
//   hasReasoningInHistory 等，单向无环）。断言直跑副本把本件剥 import 后拼接到
//   RequestCompose.ts 尾部（同文件内共享叶子；无重名导出）。
import { AiToolDef, SamplingParams } from './AiTypes';
import {
  ComposeChatMessage, ComposeImagePart, hasReasoningInHistory, isEmptyAssistantTurn,
  isRemoteFilePart, parseToolSchema, REASONING_REPLAY_PLACEHOLDER
} from './RequestCompose';

// OpenAI Responses API 请求体：/v1/responses（stream=true）——官方 input 兼容
// [{role,content}] 形态（system 不进 input——instructions 是顶层指导位，多条 \n\n 连接，
// 无 system 省略字段）；★ 显式 store: false——官方默认 store:true（服务端存储上下文），
// 项目「本地管理上下文」原则显式关闭（隐私红线）。键序照 Anthropic 先例：尾部键
interface OpenAiResponsesRequest {
  model: string;
  input: ResponsesMessageItem[];
  instructions?: string;
  stream: boolean;
  store: boolean;
  tools?: ResponsesToolItem[]; // 工具声明（官方扁平形态 name/parameters 直挂）
  reasoning?: OpenAiResponsesReasoning;
  // encrypted reasoning 保真开关：true = 请求带 include:['reasoning.encrypted_content']
  // ——官方 stateless 工具轮要求；仅 OpenAI 官方端点开（AiTypes.isOfficialOpenAiBaseUrl
  // 判定，第三方网关不支持此 include）
  include?: string[];
  temperature?: number; // 采样覆盖（官方 Responses 无 penalties 字段——不发）
  top_p?: number;
  max_output_tokens?: number; // >0 才发送；0 = 不限制 = 不发字段
  // DS 官方扩展（二期 #4 / #6）：title 会话标题 / safety_check 内容安全（缺省不带 =
  // 请求体逐字节不变）
  title?: Record<string, Object>;
  safety_check?: Record<string, Object>;
}

// 工具声明项（官方 Responses tools 扁平形态——与 chat 的嵌套 function 不同）。三可选 =
// 官方服务端工具裸项（{type:'deepseek_web_search'} 只有 type，无 name/description/parameters）
interface ResponsesToolItem {
  type: string;
  name?: string;
  description?: string;
  parameters?: Object;
}

// 思考档位载体（Responses 接口 reasoning 对象形态——与 chat 的顶层 reasoning_effort 不同）
interface OpenAiResponsesReasoning { effort: string }

// Responses 多模态 content part：input_image 的 image_url 为**直串 data URI**（与 chat 的
// 嵌套 {url} 形态不同——官方两接口各自形态，勿互抄）。reasoning item 的明文内容块复用本
// 形态（type='reasoning_text' + text，不另开同构接口以免结构化类型禁令触雷）；input_file
// 两字段（file_data data URI / filename）供 function_call_output.output 数组承载文件附件
//（官方三型 input_text | input_image | input_file）
interface ResponsesContentPart {
  type: string;
  text?: string;
  image_url?: string;
  file_data?: string;
  filename?: string;
}

interface ResponsesMessageItem {
  role?: string;
  content?: string | ResponsesContentPart[];
  // 工具调用 item：官方 input 数组混合形态——function_call（assistant 轮）/
  // function_call_output（工具结果），两者皆无 role（type 自别）
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  // ★ output 类型放宽 string | 内容项数组（官方规格）——工具结果附件启用数组形态；
  // 无附件路径恒 string 逐字节零回归（数组 stringify 形态虽合法但只降级为纯文本，本端不产）
  output?: string | ResponsesContentPart[];
  // reasoning item：stateless 工具轮回传保真——id + encrypted_content 原样（官方「must
  // retain reasoning items」；裸 reasoning 文本不合法）
  id?: string;
  encrypted_content?: string;
}

// DS Responses 轮回传取数（二期 S3）：列载荷 = {"protocol":"responses","items":[…]}——本函数
// 只认协议标签（旧行无 protocol 键 = CC 形态，回 null 走既有 message 组装）。返回 items 原样
// 数组 = 官方「把上一轮整个 output item 原样放回 input」的唯一取数口；坏串/非数组回 null。
// 导出供 ChatMessageCompose 回放合成复用（显示层按同一份 items 合成步骤行与来源）
export function responsesEchoItemsOf(serverToolsJson: string | undefined): Object[] | null {
  if (serverToolsJson === undefined || serverToolsJson === '') {
    return null;
  }
  let root: Record<string, Object>;
  try {
    root = JSON.parse(serverToolsJson) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  if (root === null || typeof root !== 'object' || root['protocol'] !== 'responses') {
    return null;
  }
  const items: Object | undefined = root['items'];
  if (items === undefined || items === null || !Array.isArray(items)) {
    return null;
  }
  return items as Object[];
}

export function composeOpenAiResponsesBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', sampling: SamplingParams | null = null,
  tools: AiToolDef[] = [], reasoningInclude: boolean = false,
  dsTitle: boolean = false, dsSafety: boolean = false): string {
  // system 提取（走 instructions，不进 input 数组）；user/assistant 原样；assistant 工具
  // 调用轮 = message item（文本非空才带）+ function_call item 族；role='tool' =
  // function_call_output item（官方要求全部 function_call 先于其 output）。
  // ★ reasoning item 回传：stateless 工具轮要求 function_call 前有其配对 reasoning item
  //（缺失 400 实锤；第三方端点同要求，载体为明文）——回放序 = reasoning item 先于
  // message/function_call（服务端校验该序），载体二选一与占位规则见下方分支注释
  const input: ResponsesMessageItem[] = [];
  const systemParts: string[] = [];
  const sessionThinking: boolean = hasReasoningInHistory(messages); // 思考会话判据（见函数注释）
  // 服务端工具回传闸（自检轮修，与 CC 侧 roundHasServerDefs 对称）：本轮声明含 serverType
  // 项才回传历史 output items。web_search_call 是 output-only 类型——连接换到别的 Responses
  // 端点后继续塞进 input 会被拒（该会话此后每轮 400）；与 CC 侧「非官方档轮省略该字段」
  // 同一语义、同一判据来源
  const roundHasServerDefs: boolean = tools.some((t: AiToolDef): boolean =>
    t.serverType !== undefined && t.serverType !== '');
  for (const m of messages) {
    // DS Responses 轮回传（二期 S3）：该轮存了官方 output items（protocol 标签 responses）→
    // 整个 output 原样放回 input（官方多轮形态），不再走本方言的 message/function_call 组装。
    // 浏览器上下文（含 signature）的续接全靠这份原样回传
    if (m.role === 'assistant' && roundHasServerDefs) {
      const echo: Object[] | null = responsesEchoItemsOf(m.serverToolCallsJson);
      if (echo !== null) {
        for (const item of echo) {
          input.push(item as ResponsesMessageItem);
        }
        continue;
      }
    }
    // 空 assistant item 跳过（§4.5 修）：本方言不消费 server_tools，空 content item 上游
    // 可能 400（input 以 assistant item 结尾还会撞 Responses 的续写硬限）
    if (isEmptyAssistantTurn(m)) {
      continue;
    }
    if (m.role === 'system') {
      systemParts.push(m.content);
      continue;
    }
    if (m.role === 'tool') {
      // ★ 工具结果附件——有图/PDF 时 output 内容项数组化（官方规格 output = string |
      // (input_text|input_image|input_file)[]；无附件路径恒 string 逐字节零回归）。
      // input_file.file_data 带 data URI 前缀；image 走 input_image 直串 data URI
      if (m.images !== undefined && m.images.length > 0) {
        const outParts: ResponsesContentPart[] = [{ type: 'input_text', text: m.content }];
        for (const img of m.images) {
          if (img.mimeType === 'application/pdf') {
            outParts.push({ type: 'input_file', filename: 'document.pdf',
              file_data: 'data:application/pdf;base64,' + img.data });
          } else {
            outParts.push({ type: 'input_image',
              image_url: 'data:' + img.mimeType + ';base64,' + img.data });
          }
        }
        input.push({ type: 'function_call_output', call_id: m.toolCallId ?? '', output: outParts });
        continue;
      }
      input.push({ type: 'function_call_output', call_id: m.toolCallId ?? '', output: m.content });
      continue;
    }
    if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // reasoning item 回放（★ 序红线 = 先于 message item 与 function_call item——官方
      // 输入序即输出序，服务端实测校验该序，反序同样 400）：
      // ① 捕获到官方保真项（id+encrypted_content，仅 OpenAI 官方端点有）→ 原样回传；
      // ② 未捕获但会话在思考模式 → 明文 reasoning item（第三方端点输入规格 = content 为
      //    reasoning_text 块列表）；思考文本空 = 补占位（载体缺席即被拒）
      if (m.reasoningItems !== undefined && m.reasoningItems.length > 0) {
        for (const ri of m.reasoningItems) {
          input.push({ type: 'reasoning', id: ri.id, encrypted_content: ri.encryptedContent });
        }
      } else if (sessionThinking) {
        const reasoningText: string = m.reasoning !== undefined && m.reasoning !== '' ?
          m.reasoning : REASONING_REPLAY_PLACEHOLDER;
        input.push({ type: 'reasoning',
          content: [{ type: 'reasoning_text', text: reasoningText }] });
      }
      if (m.content !== '') {
        input.push({ role: 'assistant', content: m.content });
      }
      for (const tc of m.toolCalls) {
        input.push({ type: 'function_call', call_id: tc.id, name: tc.name, arguments: tc.argsJson });
      }
      continue;
    }
    if (m.images !== undefined && m.images.length > 0) {
      // 带图：content = [input_image 块..., input_text 块（非空才带）]。★ DS 服务端解析件
      // 防御性跳过（isRemoteFilePart——file_id 引用件非本方言消费形态）；全部被跳过时回落
      // 纯文本形态，空 content 数组不上送
      const visibleImages: ComposeImagePart[] = m.images.filter(
        (img: ComposeImagePart): boolean => !isRemoteFilePart(img));
      if (visibleImages.length > 0) {
        const parts: ResponsesContentPart[] = [];
        for (const img of visibleImages) {
          parts.push({ type: 'input_image', image_url: 'data:' + img.mimeType + ';base64,' + img.data });
        }
        if (m.content !== '') { parts.push({ type: 'input_text', text: m.content }); }
        input.push({ role: m.role, content: parts });
      } else {
        input.push({ role: m.role, content: m.content });
      }
    } else {
      input.push({ role: m.role, content: m.content });
    }
  }
  const req: OpenAiResponsesRequest = {
    model: model,
    input: input,
    stream: true,
    store: false
  };
  // 工具声明：官方扁平 tools 数组；schema 坏串工具跳过
  if (tools.length > 0) {
    const apiTools: ResponsesToolItem[] = [];
    for (const t of tools) {
      // 官方服务端工具裸项（二期 S3）：serverType 非空 → {type} 单键项（无 function 包裹）。
      // 与客户端 function 工具是否互斥官方无明文——按可共存声明，400 冲突时由流域
      // ChatKeyRoundCtrl.retryWithoutClientTools 剔除客户端工具重发一次（任务书 §1-7）
      if (t.serverType !== undefined && t.serverType !== '') {
        apiTools.push({ type: t.serverType });
        continue;
      }
      const schema: Object | null = parseToolSchema(t.parametersJson);
      if (schema === null) {
        continue;
      }
      apiTools.push({ type: 'function', name: t.name, description: t.description,
        parameters: schema });
    }
    if (apiTools.length > 0) {
      req.tools = apiTools;
      // encrypted reasoning 请求开关：官方 stateless 工具轮回传保真的前置——无 include 则
      // 流中 reasoning item 不带 encrypted_content，回传链无从谈起；与工具声明同门
      //（无工具 = 无工具轮 = 无回传面，不发）
      if (reasoningInclude) {
        req.include = ['reasoning.encrypted_content'];
      }
    }
  }
  if (systemParts.length > 0) {
    req.instructions = systemParts.join('\n\n');
  }
  if (thinking !== '') {
    req.reasoning = { effort: thinking };
  }
  // 采样覆盖（官方 Responses 接口无 penalties 字段不发；maxOutput 0 = 不限制不发字段）
  if (sampling !== null) {
    if (sampling.temperature !== undefined) {
      req.temperature = sampling.temperature;
    }
    if (sampling.topP !== undefined) {
      req.top_p = sampling.topP;
    }
    if (sampling.maxOutput !== undefined && sampling.maxOutput > 0) {
      req.max_output_tokens = sampling.maxOutput;
    }
  }
  // DS 官方扩展字段（二期 #4 标题 / #6 安全）：两布尔缺省 false ⇒ 请求体逐字节不变
  if (dsTitle) {
    req.title = { 'enabled': true };
  }
  if (dsSafety) {
    req.safety_check = { 'level': 'high' };
  }
  return JSON.stringify(req);
}

