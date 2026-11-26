// 注入 section 数据化域：system 注入链从「六个函数按调用序拼接、顺序靠注释互证」改为
//「section 数组 + 排序函数 + 落地函数」——顺序成为可断言的数据，不再依赖人的记忆。
// ★ 零 import 叶子（断言复制直跑面；消息类型自持同构声明——RequestInject.InjectChatMessage
//   为其私有接口不可 export 先例）。ArkTS 禁结构化类型——调用方（ChatRoundAssembly）持
//   AiChatMessage[] 直传，字段同名同型互认。
// ★ 等价红线（验收形态）：改造前后 composeSendMessages 三消费者（主链 ChatRoundAssembly /
//   深度组 / 旁路 ProactiveGen）产出的四协议请求体逐字节相同——sse-assert golden 组同脚本
//   内「老链三 append 薄转出 vs 新链 assembleSystemMessages」并行互比（老链代码仍在仓 =
//   保真参照），含「无提示词 + 知识块独占 system」分支。

// 注入段视图（「本次请求构成」显示面快照）：chars = 段字符数、tokens = 段估算（estimator
// 注入——TokenEstimate 单源，禁第二套估算实现）；beginRound 定格一次、轮内不变
//（「面板与实发一致」纪律：面板读的就是这一份，禁第二条计算链）
export interface InjectSectionView {
  key: string;
  label: string;
  cacheHint: string;
  chars: number;
  tokens: number;
}

// 视图构造（纯函数）：sections → 显示快照；ChatRoundAssembly 在 beginRound 处调用
//（发送组装定格点）
export function sectionViewsOf(sections: InjectSection[],
  estimator: (text: string) => number): InjectSectionView[] {
  const views: InjectSectionView[] = [];
  for (const s of sections) {
    views.push({ key: s.key, label: s.label, cacheHint: s.cacheHint,
      chars: s.content.length, tokens: estimator(s.content) });
  }
  return views;
}

// 消息（与 AiTypes.AiChatMessage **字段集完全同构**的自持声明——零 import 纪律下不可引
// AiTypes；字段集须逐字段镜像，多一字段少一字段都会触发 arkts-no-structural-typing
// 〔ChatRoundAssembly 的 AiChatMessage[] 直传即被此禁令实锤过〕；子结构同构声明同款）。
// 本域只读写 role/content 与 systemTailChars/volatileTime 两内存标记，其余字段全量
// 随行带防丢（appendSystemBlock 重建族同口径）
export interface SectionMsg {
  role: string;
  content: string;
  images?: SectionImgPart[];
  reasoning?: string;
  toolCalls?: SectionToolCall[];
  toolCallId?: string;
  toolName?: string;
  reasoningItems?: SectionReasoningItem[];
  volatileTime?: boolean;
  systemTailChars?: number;
  createdAt?: number;
}

// 图片部件（与 AiTypes.AiImagePart 同构；零 import 自持）
export interface SectionImgPart { mimeType: string; data: string }

// 工具调用载荷（与 RequestCompose.AiToolCall 同构；零 import 自持——本域只判在场不消费）
export interface SectionToolCall { id: string; name: string; argsJson: string }

// reasoning 输出项（与 AiTypes.AiReasoningItem 同构；零 import 自持）
export interface SectionReasoningItem { id: string; encryptedContent: string }

// 注入段（一段 = 一类 system 块材料；target='meta_user' 通道本期留空占位——本仓无该消费
// 面，字段先占不消费，照总案「不顺手把 meta_user 做起来」拍板）
export interface InjectSection {
  key: string;                      // 'prompt' | 'skills' | 'memory' | 'knowledge'
  label: string;                    // 面板显示名（P3-b 构成卡消费）
  target: string;                   // 'system' | 'meta_user'
  cacheHint: string;                // 'stable'（低频变）| 'dynamic'（逐轮变）
  content: string;
  volatileTime?: boolean;           // prompt 段专属：内容含已替换的时间变量（缓存降级信号）
}

// prompt 段产出判据的材料形态（与 PromptInjectConfig 同构最小面——role/content/
// volatileTime；depth/position 等字段与本域无关）
export interface SectionPromptLike {
  role: string;
  content: string;
  volatileTime?: boolean;
}

// 四段产出材料（prompt 为 null = 无提示词配置；historyHasSystem = 历史已含 system 条
// 〔逐条遍历语义，照 composeSendMessages 的 system 查重——任一位置有即真，异常序列防御〕）
export interface InjectSectionsContext {
  prompt: SectionPromptLike | null;
  historyHasSystem: boolean;
  skills: string;
  memory: string;
  knowledge: string;
}

// system 位提示词是否走 section 通道（分流判据单源——ChatRoundAssembly 编排与
// composeInjectSections 共用，禁两处各写一份）：role=system + content 非空 + 历史无
// system（已含 = composeSendMessages 丢弃语义的复刻——异常路径不重复注入）。user/
// assistant 位提示词不走 section（消息级注入，照旧 composeSendMessages 老路）。
export function promptAsSection(prompt: SectionPromptLike | null,
  historyHasSystem: boolean): boolean {
  return prompt !== null && prompt.role === 'system' && prompt.content !== '' &&
    !historyHasSystem;
}

// 历史是否已含 system 条（逐条遍历——composeSendMessages system 查重同语义；与
// assembleSystemMessages 只看 history[0] 的合并判定是两个判据，勿合并）
export function historyHasSystemMsg(history: SectionMsg[]): boolean {
  for (const m of history) {
    if (m.role === 'system') {
      return true;
    }
  }
  return false;
}

// 四段产出（content '' 段不产——与 append 系「空块原样返回」负向钉同口径；prompt 段产出
// 判据见 promptAsSection，其余三段只看空串）
export function composeInjectSections(ctx: InjectSectionsContext): InjectSection[] {
  const sections: InjectSection[] = [];
  if (promptAsSection(ctx.prompt, ctx.historyHasSystem)) {
    const p: SectionPromptLike = ctx.prompt as SectionPromptLike;
    const promptSection: InjectSection = { key: 'prompt', label: '提示词',
      target: 'system', cacheHint: 'stable', content: p.content,
      volatileTime: p.volatileTime === true ? true : undefined };
    sections.push(promptSection);
  }
  if (ctx.skills !== '') {
    sections.push({ key: 'skills', label: '技能清单', target: 'system',
      cacheHint: 'stable', content: ctx.skills });
  }
  if (ctx.memory !== '') {
    sections.push({ key: 'memory', label: '记忆', target: 'system',
      cacheHint: 'stable', content: ctx.memory });
  }
  if (ctx.knowledge !== '') {
    sections.push({ key: 'knowledge', label: '知识命中', target: 'system',
      cacheHint: 'dynamic', content: ctx.knowledge });
  }
  return sortInjectSections(sections);
}

// 四路排序（拍板序：system-stable → system-dynamic → meta_user-stable → meta_user-dynamic；
// 同级保产出序——分桶拼接即稳定，不经比较排序）。当前消费面下恒等价于老链合并序
// prompt → skills → memory → knowledge。
export function sortInjectSections(sections: InjectSection[]): InjectSection[] {
  const sysStable: InjectSection[] = [];
  const sysDynamic: InjectSection[] = [];
  const metaStable: InjectSection[] = [];
  const metaDynamic: InjectSection[] = [];
  for (const s of sections) {
    if (s.target !== 'system') {
      if (s.cacheHint === 'dynamic') {
        metaDynamic.push(s);
      } else {
        metaStable.push(s);
      }
    } else if (s.cacheHint === 'dynamic') {
      sysDynamic.push(s);
    } else {
      sysStable.push(s);
    }
  }
  return sysStable.concat(sysDynamic).concat(metaStable).concat(metaDynamic);
}

// section 边界字符数（Anthropic 断点切分依据——「最后一个 stable 段的边界」；分隔符 '\n\n'
// 归稳定段一侧〔append 系合并式 a + '\n\n' + b 的既有归属，改归属 = 请求体差 2 字节〕）：
// 稳定段累计总长（含段间分隔符）；0 = 无 stable 段（全 dynamic 或零段）。消费对偶 =
// composeAnthropicBody 的 lastPart.length − systemTailChars 换算（golden 互比守两侧一致）
export function stableBoundaryOf(sections: InjectSection[]): number {
  let boundary: number = 0;
  let stableCount: number = 0;
  for (const s of sections) {
    if (s.target === 'system' && s.cacheHint === 'stable') {
      boundary += s.content.length + (stableCount > 0 ? 2 : 0);
      stableCount++;
    }
  }
  return boundary;
}

// 落地（与 appendSystemBlock 族逐字等价——golden 互比守）：零段原样返回（history 引用直回
// 零拷贝）；首条 system → 合并进该条 content 尾部（段间与既有块间一律 '\n\n'，消息数不变，
// 重建对象字段族全量随行带防丢）；无 system → 首位插入独立 system 条（sections 以 '\n\n'
// 连接为一条；volatileTime 取 prompt 段标记——首插即提示词位的等价复刻）。
// ★ systemTailChars（波动尾段标记）——路径语义的复刻（golden 互比实测校正）：老链的标记
//   由「knowledge 落地那一刻 history 是否已有 system」决定——有（合并路径）→ 覆写块长；
//   由 knowledge 自己首插 → 不设。section 化后等价规则：
//   · 合并路径（history[0] 已是 system）：dynamicTail > 0 → 覆写；否则透传既有标记
//     （append 透传链等价）。
//   · 首插路径（history 无 system）：存在 stable 段（prompt/skills/memory 任一——老链由
//     它们之一首插建 system、knowledge 后并入 = 合并语义）且 dynamicTail > 0 → 覆写；
//     无 stable 段（knowledge 自己首插 = 场景「无提示词 + 知识块独占 system」）→ **恒不设**
//     （appendSystemKnowledge 首插不设标记红线——无稳定前缀可挂断点，P1-c golden 分支守此）。
export function assembleSystemMessages(history: SectionMsg[],
  sections: InjectSection[]): SectionMsg[] {
  if (sections.length === 0) {
    return history;
  }
  let joined: string = '';
  let promptVolatile: boolean | undefined = undefined;
  for (const s of sections) {
    joined = joined === '' ? s.content : joined + '\n\n' + s.content;
    if (s.key === 'prompt' && s.volatileTime === true) {
      promptVolatile = true;
    }
  }
  let dynamicTail: number = 0;
  let hasStable: boolean = false;
  for (const s of sections) {
    if (s.target !== 'system') {
      continue;
    }
    if (s.cacheHint === 'dynamic') {
      dynamicTail = s.content.length;
    } else {
      hasStable = true;
    }
  }
  if (history.length > 0 && history[0].role === 'system') {
    const merged: SectionMsg[] = [];
    merged.push({ role: 'system', content: history[0].content + '\n\n' + joined,
      images: history[0].images, reasoning: history[0].reasoning,
      toolCalls: history[0].toolCalls, reasoningItems: history[0].reasoningItems,
      volatileTime: history[0].volatileTime,
      systemTailChars: dynamicTail > 0 ? dynamicTail : history[0].systemTailChars });
    for (let i = 1; i < history.length; i++) {
      merged.push(history[i]);
    }
    return merged;
  }
  const injected: SectionMsg[] =
    [{ role: 'system', content: joined, volatileTime: promptVolatile,
      systemTailChars: hasStable && dynamicTail > 0 ? dynamicTail : undefined }];
  for (const m of history) {
    injected.push(m);
  }
  return injected;
}
