// 服务端工具步骤域（DS 全家桶二期 S3，自 ChatStreamFlowCtrl 域级最小拆分）。
// 一句话职责 =「服务端工具流事件 → serverstep 合成行 + 落列快照」：CC 的 call_started/done
// 建行与更新、末帧合体串、Responses 的 item 原样累积与整 output 快照，全在本域。
// · 拆出理由（宪法 1200 硬线）：S3 加 Responses 三态事件与 itemJson 后 ChatStreamFlowCtrl
//   剔头越 1250；按域级最小拆分把「服务端工具步骤」整域外迁，正文/思考/揭示/收尾一行未动。
// · 数据有界：stepRows/callJsons 按步序键（一轮工具步数上界），Responses rawItems 按
//   output_index 覆盖；全部随轮清点（reset 与 assistantFull 同生命周期）。
// · 显示面单源：行名/态提取在 DsServerTools（零依赖判据件），本域只做编排与写数据源。
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { nextMessageId } from '../../common/store/ChatDb';
import { SseServerToolEvent } from '../../common/providers/SseParser';
import { serverCallKeyOf, serverStepNameOf, serverStepStateOf } from '../../common/providers/DsServerTools';
import { ChatResponsesFlowCtrl } from './ChatResponsesFlowCtrl';

export class ChatServerStepCtrl {
  // 步序键（步序#调用键）→ serverstep 合成行 id；同键复用行（started 建、completed 原位更新）
  private stepRows: Map<string, string> = new Map();
  // 步序键 → callJson（末帧未达时组装部分结构的料——屏显与库一致）
  private stepCallJsons: Map<string, string> = new Map();
  private callsJson: string = '';
  private annotationsJson: string = '';
  private toolsFull: string = '';
  private autoSeq: number = 0;
  private responses: ChatResponsesFlowCtrl = new ChatResponsesFlowCtrl();

  // 轮首/轮末清点（与正文累积串同拍）
  reset(): void {
    this.stepRows.clear();
    this.stepCallJsons.clear();
    this.callsJson = '';
    this.annotationsJson = '';
    this.toolsFull = '';
    this.autoSeq = 0;
    this.responses.reset();
  }

  // 列载荷快照（settlement 与 finishStream 共用单一组装点，禁第二份）：Responses = 官方
  // items 信封；CC = 末帧合体串优先，末帧未达则按已见 call 组装**步**形态部分结构
  snapshot(isResponses: boolean): string {
    if (isResponses) {
      return this.responses.snapshotOf();
    }
    if (this.toolsFull !== '') {
      return this.toolsFull;
    }
    if (this.stepCallJsons.size === 0) {
      return '';
    }
    const steps: string[] = [];
    let stepIndex: number = 0;
    for (const callJson of this.stepCallJsons.values()) {
      steps.push('{"index":' + stepIndex.toString() + ',"calls":[' + callJson + ']}');
      stepIndex++;
    }
    return '{"server_tool_calls":[' + steps.join(',') + ']}';
  }

  // 流事件路由：call_started/call_completed → 建行/原位更新（行键 = 步序 + 步内调用键）
  noteEvent(ev: SseServerToolEvent, liveAssistantId: string, dataSource: ChatDataSource): void {
    if (ev.callJson === undefined || ev.callJson === '') {
      return;
    }
    const stepKey: string = ev.step !== undefined ? String(ev.step) :
      'auto-' + this.autoSeq++;
    const callKey: string = serverCallKeyOf(ev.callJson);
    const rowKey: string = stepKey + '#' +
      (callKey !== '' ? callKey : 'auto-' + this.autoSeq++);
    const existingId: string = this.stepRows.get(rowKey) ?? '';
    if (existingId === '') {
      // call_started：合成 serverstep 行（生成中态）；首见即 completed（started 帧缺 call
      // 被丢的防御形态）直接落终态，不留永转圈行
      const initialState: string = ev.type === 'call_completed' ?
        serverStepStateOf(ev.callJson) : 'running';
      const row: ChatMessage = newChatMessage(nextMessageId('serverstep'), 'serverstep', '',
        serverStepNameOf(ev.callJson), initialState);
      row.toolOutputJson = ev.callJson;
      dataSource.bindDisplayMember(row, liveAssistantId);
      const ownerMsg: ChatMessage | null = dataSource.findMessage(liveAssistantId);
      if (ownerMsg !== null) {
        if (ownerMsg.createdAt !== undefined) {
          row.createdAt = ownerMsg.createdAt;
        }
        if (ownerMsg.modelLabel !== undefined) {
          row.modelLabel = ownerMsg.modelLabel;
        }
      }
      dataSource.insertBefore(liveAssistantId, row);
      this.stepRows.set(rowKey, row.id);
    } else if (ev.type === 'call_completed') {
      // call_completed：原位更新（行对象 @Observed，赋值即驱动该行重渲染——不整表重投影）
      // ★ 自检轮修：只有 completed 才改态与内容——Responses 的 searching / in_progress 帧
      // 也走 call_started，首版无条件覆盖把已在场行提前翻 done，且把带 action 的合成串
      // 换成三态降级串（查询词在展开区消失，直到 done 才恢复）
      const row: ChatMessage | null = dataSource.findMessage(existingId);
      if (row !== null) {
        row.toolState = serverStepStateOf(ev.callJson);
        row.toolOutputJson = ev.callJson;
      }
    }
    // 步内调用串：首见即记（部分结构兜底要它），completed 覆盖为终态；started 不覆盖已记内容
    //（同 call 的 searching 帧只是状态推进，不该抹掉 added 帧带来的 action）
    if (!this.stepCallJsons.has(rowKey) || ev.type === 'call_completed') {
      this.stepCallJsons.set(rowKey, ev.callJson);
    }
    // Responses：官方 item 原样串按 output_index 覆盖（done 盖 added；无 step 用自增键）
    if (ev.itemJson !== undefined && ev.itemJson !== '') {
      this.responses.noteItem(ev.step, ev.itemJson);
    }
  }

  // 末帧路由：server_tool_calls / annotations 原样串入并组装合体串（禁 parse 重排）
  noteTail(callsJson: string | undefined, annotationsJson: string | undefined): void {
    if (callsJson !== undefined) {
      this.callsJson = callsJson;
    }
    if (annotationsJson !== undefined) {
      this.annotationsJson = annotationsJson;
    }
    if (this.callsJson !== '' || this.annotationsJson !== '') {
      let full: string = '{"server_tool_calls":' +
        (this.callsJson !== '' ? this.callsJson : '[]');
      if (this.annotationsJson !== '') {
        full += ',"annotations":' + this.annotationsJson;
      }
      this.toolsFull = full + '}';
    }
  }

  // Responses 终止快照（整轮 output 原样串；后到覆盖）
  noteResponsesOutput(json: string): void {
    this.responses.noteOutput(json);
  }
}
