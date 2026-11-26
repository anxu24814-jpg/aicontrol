// Responses 协议流式载荷累积域（DS 全家桶二期 S3，自 ChatStreamFlowCtrl 域级最小拆分）.
// 一句话职责 =「把 Responses 流的官方 output item 原样攒成可落库的信封，并记住终止事件的
// 完整 output 快照」。宿主（ChatStreamFlowCtrl）只留两处薄调用（增量记录 / 快照取值）。
// · 拆出理由（宪法 1200 硬线）：S3 新增 web_search_call 三态、itemJson 落库与整 output
//   回传后，ChatStreamFlowCtrl 剔头越 1250；按域级最小拆分把 Responses 专属累积态外迁，
//   CC/Anthropic/Gemini 路径一行未动。
// · 数据有界：rawItems 按 output_index 覆盖（同 key 后到覆盖先到），index 数量 = 本轮工具
//   步数（单轮有界）；outputJson 单值后到覆盖。
// · 列载荷形态（代决 #17 同列标签）：{"protocol":"responses","items":[…]}——读侧按 protocol
//   分派；无终止快照时用流内逐 item 兜底（中止/失败轮的屏显与库一致）。
export class ChatResponsesFlowCtrl {
  // output_index → 官方 item 原样串（added 建、done 覆盖）
  private rawItems: Map<number, string> = new Map<number, string>();
  // 终止事件（completed/incomplete）携带的完整 output 数组原样串（'' = 未收到）
  private outputJson: string = '';
  // 无 step 的 item 自增键游标（防覆盖别人的槽位）
  private seq: number = 0;

  // 轮首/轮末清点（与 assistantFull 同生命周期）
  reset(): void {
    this.rawItems.clear();
    this.outputJson = '';
    this.seq = 0;
  }

  // 终止事件快照记录（后到覆盖——理论上单发）
  noteOutput(json: string): void {
    if (json !== '') {
      this.outputJson = json;
    }
  }

  // 流内 item 记录（step 缺省用自增键；返回新的自增游标，宿主无需自持）
  noteItem(step: number | undefined, itemJson: string): void {
    if (itemJson === '') {
      return;
    }
    if (step !== undefined) {
      this.rawItems.set(step, itemJson);
      return;
    }
    this.rawItems.set(this.seq, itemJson);
    this.seq = this.seq + 1;
  }

  // 快照组装：完整 output 优先（官方整轮形态，回传保真的唯一来源）；否则按 index 升序
  // 拼流内 item；两者皆无回 ''
  snapshotOf(): string {
    if (this.outputJson !== '') {
      return '{"protocol":"responses","items":' + this.outputJson + '}';
    }
    if (this.rawItems.size === 0) {
      return '';
    }
    const keys: number[] = [];
    this.rawItems.forEach((_json: string, idx: number): void => {
      keys.push(idx);
    });
    keys.sort((a: number, b: number): number => a - b);
    const items: string[] = [];
    for (const k of keys) {
      const json: string = this.rawItems.get(k) ?? '';
      if (json !== '') {
        items.push(json);
      }
    }
    if (items.length === 0) {
      return '';
    }
    return '{"protocol":"responses","items":[' + items.join(',') + ']}';
  }
}
