// AI 生成内容标识域（2026-09-10 立，合规上架笔）——《人工智能生成合成内容标识办法》
// 要求：交互场景界面呈现、以及复制/导出带走的 AI 生成合成内容都须带显式标识；素材侧
// 《应用资质审核要求》「深度合成或生成式人工智能服务」行要「应用内已添加内容显式标识
// 截图」或《标识说明函》，两处凭据都引用本域文字。
// 消费点三处同源（改文案只改本文件）：
//   1. 界面提示行 = components/chat/ChatInputBar（输入胶囊下方常驻小字）；
//   2. 复制带标识 = components/chat/cube/CubeMarkdownView（文本/代码复制回调）；
//   3. 导出随包说明 = common/store/ExportImport（备份 zip 根部说明文件）。
// 为何独立成文件：三个消费点分属 UI 与存储两域，无同域既有文件可并入，本域职责一句话
// 可述（AI 标识文案与拼接）——符合「反碎片下限」对拆分职责缝的要求。

// 显式标识文字（三处消费同源；改此处即三处同步）
export const AI_CONTENT_LABEL: string = '内容由 AI 生成，仅供参考';

// 复制/导出场景拼接：原文末尾另起一段附标识；空文本原样返回（不造孤立标识行）
export function withAiContentLabel(text: string): string {
  if (text.length === 0) {
    return text;
  }
  return `${text}\n\n${AI_CONTENT_LABEL}`;
}

// 备份包内说明文件名（ASCII 名——跨平台解压不乱码；内容中文）
export const AI_NOTICE_FILE_NAME: string = 'AI-GENERATED-CONTENT-NOTICE.txt';

// 备份包说明正文（导出 zip 根部随包携带 = 「导出内容含显式标识」的随包凭据；导入侧按
// 已知表名读 JSON，本文件不参与恢复，纯标识用途）
export function aiNoticeFileText(): string {
  return 'AI 控制台数据备份\n\n'
    + '本备份中的助手回复为人工智能生成合成内容。\n'
    + AI_CONTENT_LABEL + '\n';
}
