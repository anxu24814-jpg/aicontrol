// 工具产出附件挂载缝与预算域（自 ChatSendCtrl 域级拆出）：执行器交付的工具产出附件（图片/
// 文档原件）落到本轮请求历史的承载位，并承担单发送预算计数（能力判据分派与工具结果位挂载
// 见 collectToolImage / toolResultMedia；collectImage / collectPageImage 自 ChatSendCtrl
// 原样随迁）。
// · 为何不并入既有同域件（反碎片下限②申报）：挂载缝两类消费方跨域——执行上下文构造
//   （ChatSendCtrl.buildExecutionContext）与工具轮（ChatToolRoundCtrl），并入任一侧都跨域；
//   本件是实质逻辑件非转接壳。
// · 依赖方向（零环红线，坑50）：本件禁 import ChatSendCtrl / ChatToolRoundCtrl——宿主态
//   （Key 池历史 / 连接）一律经 ToolMediaRefs 箭头闭包延迟求值到达（构造期各域件晚于彼此
//   创建也不悬空，调用时刻恒已就位）。

import { AiChatMessage, AiConnection, AiImagePart } from '../../common/providers/AiTypes';
import { TOOL_IMAGE_ATTACH_MAX } from '../../common/providers/ToolLimits';
// 协议×模型能力判据单源（零 import 叶子）
import { resolveToolMediaSupport } from '../../common/providers/ToolMediaSupport';

// 挂载缝宿主读数集（照 RoundAssemblyRefs 形制：箭头闭包持宿主延迟求值，调用时刻恒取当时值）
export interface ToolMediaRefs {
  // 本轮请求历史活引用（宿主 keyRound.currentHistory()——push 即生效）
  roundHistory: () => AiChatMessage[];
  // 当前连接（宿主 refs.conn()——工具结果位判据逐请求现读，连接切换即时生效）
  conn: () => AiConnection | null;
  // 本调用附件登记（宿主 toolRound.attachCallMedia——按 callId 记到本调用的
  // ToolEventRecord.mediaParts；未命中条目不在场回 false）
  attachCallMedia: (callId: string, mimeType: string, data: string) => boolean;
}

export class ChatToolMediaCtrl {
  private refs: ToolMediaRefs;
  // 本发送内执行器已挂载的工具图张数（上限 TOOL_IMAGE_ATTACH_MAX 单发送有界，防模型连环
  // 读图 token 失控；清零点 = resetForRound，由宿主 buildExecutionContext 调用。附件图不
  // 计数——附件是用户显式行为，本计数只挡模型自主读图）
  private toolImageAttached: number = 0;

  constructor(refs: ToolMediaRefs) {
    this.refs = refs;
  }

  // 轮首计数清零（计数器与上下文构造同拍归零，单发送有界语义由该点保证）
  resetForRound(): void {
    this.toolImageAttached = 0;
  }

  // 工具图挂载：图挂进本轮请求历史最后一条 user 消息的 images（回溯找 user 恒命中本轮
  // userReq；无 user 消息场景〔重发链等〕回 false 由执行器中文回执）。上限计数只挡执行器路。
  // ★ 本挂载位只承载 image/*——compose 层 user images 通道四方言全按图片直发，非图片
  // mime（application/pdf）塞入即服务端拒收整请求 400，由本方法拒 false 后执行器顺序落回
  // 解析路（与 BLOCKED 真机清单「读 PDF 回落解析文本」登记预期一致）。能力协议的 PDF 交付
  // 走 collectToolImage 工具结果位，不经本方法
  collectImage(mimeType: string, data: string): boolean {
    if (this.toolImageAttached >= TOOL_IMAGE_ATTACH_MAX) {
      return false;
    }
    if (!mimeType.startsWith('image/')) {
      return false;
    }
    const history: AiChatMessage[] = this.refs.roundHistory();
    for (let i = history.length - 1; i >= 0; i--) {
      if (history[i].role === 'user') {
        // 局部引用收窄（ArkTS 严格空检查——索引访问的字段窄化不保持，直写 history[i]
        // .images.push 会报 possibly undefined）
        const userMsg: AiChatMessage = history[i];
        if (userMsg.images === undefined) {
          userMsg.images = [];
        }
        const part: AiImagePart = { mimeType: mimeType, data: data };
        userMsg.images.push(part);
        this.toolImageAttached++;
        return true;
      }
    }
    return false;
  }

  // 扫描件 PDF 页图挂载缝：与 collectImage 同挂载逻辑但**不计数**——页图预算 = 单册
  // ≤ RENDER_MAX_PAGES 30 页（上限计数只挡执行器散图路）
  collectPageImage(mimeType: string, data: string): boolean {
    const history: AiChatMessage[] = this.refs.roundHistory();
    for (let i = history.length - 1; i >= 0; i--) {
      if (history[i].role === 'user') {
        const userMsg: AiChatMessage = history[i];
        if (userMsg.images === undefined) {
          userMsg.images = [];
        }
        const part: AiImagePart = { mimeType: mimeType, data: data };
        userMsg.images.push(part);
        return true;
      }
    }
    return false;
  }

  // ── 工具结果附件缝 ──

  // 本调用附件挂载（执行器经派生上下文的 collectImage 到达；ChatToolRoundHost.
  // collectToolImage 的实现体）三段：①预算闸（单发送 ≤ TOOL_IMAGE_ATTACH_MAX，图片与 PDF
  // 共用同一预算）→ ②恒记本调用 record（attachCallMedia——卡面与请求组装的共同来源，
  // **两条落点路都记**＝卡面渲染不随协议退化的关键）→ ③能力协议走工具结果位（回传链 push
  // 时带图）；非能力协议回落 user 消息位（collectImage 自带预算闸与自增；非图片 mime 被拒
  // 后执行器顺序落回解析路）。任一环节失败回 false（执行器据此中文回执）
  collectToolImage(callId: string, mimeType: string, data: string): boolean {
    if (this.toolImageAttached >= TOOL_IMAGE_ATTACH_MAX) {
      return false;
    }
    if (!this.refs.attachCallMedia(callId, mimeType, data)) {
      return false;
    }
    if (this.toolResultMedia()) {
      this.toolImageAttached++;
      return true;
    }
    return this.collectImage(mimeType, data);
  }

  // 本连接的工具结果附件位判据（resolveToolMediaSupport 单源消费——本域禁写第二份协议
  // 判断，防双源漂移）：null 连接 → false；逐请求现读（结果 push 带图与否与挂载分流共此一源）
  toolResultMedia(): boolean {
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null) {
      return false;
    }
    return resolveToolMediaSupport(conn.protocol, conn.endpoint, conn.model,
      conn.baseUrl).image;
  }
}
