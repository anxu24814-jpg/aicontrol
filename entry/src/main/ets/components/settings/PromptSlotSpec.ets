// 提示词槽规格表（2026-09-23 半模态关闭确认笔自 FunctionalModelPage.ets 拆出——该页 1180 行
// 临 1200 硬线，而本次改动所属域恰是「提示词槽规格与生效值」：原表 + 新增的生效值现读函数
// 一并落在本件；拆法 = 域级最小拆分，原表逐字搬迁、未改一处判据）。
// 职责一句话：槽 kind → 定制键 / 内置模板 / 必留占位符 / 面板标题 / 输入框占位 / 生效模板现读
// ——宿主功能模型页七槽（标题生成 / 记忆提取 / 记忆导入 / 记忆优化 / 文字识别 / 推荐问题 /
// 上下文压缩）的编辑面板播种（openPromptSlot）、保存校验与恢复默认（savePrompt /
// restorePrompt）、以及**关闭前脏态判据**（requestClosePrompt）都取本表。
// 为什么不并入既有同域件（反碎片下限第②问）：候选 `common/store/PromptTemplateDb.ets` 是
// **DB 域**（用户自存模板资产的 CRUD 与上限），本件是**纯规格表**（各功能槽的键与内置模板，
// AppStorage 现读、零 DB 依赖、断言脚本可剥读），两者调用面与失效面不同；并入会让 DB 件
// 反向依赖 UI 槽语义。
// ★ 新增一个提示词槽必须同笔改三处（原铁律随表部分外移，另两处在 FunctionalModelPage 头注释
//   的「三处联动铁律」条目下）：①本表加分支（漏 = 未知 sheetKind 静默落默认标题槽，编辑保存
//   会**写到标题提示词键上**，最隐蔽的改错键）；②宿主 sheetKind 值域注释；③宿主
//   isPromptSheet() 加 `||` 项（漏 = 面板不渲染，点键没反应）。三处任一漏改都能编译通过。
import { TITLE_PROMPT_CONTENT, TITLE_PROMPT_KEY, TITLE_PROMPT_TEMPLATE,
  resolveTitlePromptTemplate } from '../../common/TitleGen';
import { MEMORY_PROMPT_CONTENT, MEMORY_PROMPT_KEY, MEMORY_PROMPT_TEMPLATE,
  resolveMemoryPromptTemplate } from '../../common/MemoryGen';
import { MEMORY_OPT_PROMPT_KEY, MEMORY_OPT_PROMPT_MEMORIES, MEMORY_OPT_PROMPT_TEMPLATE,
  resolveMemoryOptPromptTemplate } from '../../common/MemoryOpt';
import { MEMORY_IMPORT_PROMPT_CONTENT, MEMORY_IMPORT_PROMPT_KEY,
  MEMORY_IMPORT_PROMPT_TEMPLATE, resolveMemoryImportPromptTemplate } from '../../common/MemoryImport';
import { OCR_PROMPT_KEY, OCR_PROMPT_TEMPLATE,
  resolveOcrPromptTemplate } from '../../common/providers/OcrVisionApi';
import { SUGGEST_PROMPT_CONTENT, SUGGEST_PROMPT_KEY, SUGGEST_PROMPT_TEMPLATE,
  resolveSuggestPromptTemplate } from '../../common/SuggestGen';
import { COMPRESS_PROMPT_CONVERSATION, COMPRESS_PROMPT_CONTENT, COMPRESS_PROMPT_KEY,
  resolveCompressPromptTemplate } from '../../common/CompressGen';

// 提示词槽规格（★ 2026-09-11 记忆优化提示词开放后由两分支升为规格表）：保存校验 / 恢复默认
// 回显 / 面板标题 / 输入框占位 / 缺占位符文案五处按槽取，禁各处再写一遍三目链（P2-4）
export interface PromptSlot {
  key: string; // 定制键（'' = 未定制 = 生效 builtin）
  builtin: string; // 内置默认模板（「恢复默认」回显）
  required: string; // 必须保留的占位符（缺 = 保存拦截）；'' = 本槽无占位符不校验（识别提示词）
  missingTip: string; // 缺占位符的拦截文案（required 为空时不使用）
  sheetTitle: string; // 编辑面板标题
  boxPlaceholder: string; // 输入框占位文案
}

// 槽规格解析（sheetKind → 规格；'prompt' = 标题卡，未知值同落标题槽——宿主 SheetHost 分支已
// 保证只有七种提示词 kind 会走到这里。★ 2026-09-17 识别提示词槽（'ocrPrompt'）加入：无占位符
// ——识别链的图片以附件部件随请求发送，不是文本插值，保存不做占位符校验；键与内置模板
// 单源 OcrVisionApi 域，本件零复写）
export function resolvePromptSlot(sheetKind: string): PromptSlot {
  if (sheetKind === 'ocrPrompt') {
    return {
      key: OCR_PROMPT_KEY, builtin: OCR_PROMPT_TEMPLATE,
      required: '',
      missingTip: '',
      sheetTitle: '文字识别提示词', boxPlaceholder: '输入文字识别提示词'
    };
  }
  if (sheetKind === 'suggestPrompt') {
    return {
      key: SUGGEST_PROMPT_KEY, builtin: SUGGEST_PROMPT_TEMPLATE,
      required: SUGGEST_PROMPT_CONTENT,
      missingTip: '提示词须包含 ' + SUGGEST_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
      sheetTitle: '推荐问题提示词', boxPlaceholder: '输入推荐问题提示词'
    };
  }
  if (sheetKind === 'memoryPrompt') {
    return {
      key: MEMORY_PROMPT_KEY, builtin: MEMORY_PROMPT_TEMPLATE,
      required: MEMORY_PROMPT_CONTENT,
      missingTip: '提示词须包含 ' + MEMORY_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
      sheetTitle: '记忆提取提示词', boxPlaceholder: '输入记忆提取提示词'
    };
  }
  if (sheetKind === 'memoryOptPrompt') {
    return {
      key: MEMORY_OPT_PROMPT_KEY, builtin: MEMORY_OPT_PROMPT_TEMPLATE,
      required: MEMORY_OPT_PROMPT_MEMORIES,
      missingTip: '提示词须包含 ' + MEMORY_OPT_PROMPT_MEMORIES + ' 占位符，用于插入记忆条目清单',
      sheetTitle: '记忆优化提示词', boxPlaceholder: '输入记忆优化提示词'
    };
  }
  // ★ 2026-09-22 记忆导入笔第六槽：导入整理用独立提示词（输入域 = 外部平台文本，与本库会话
  // 记录不同，不能共用提取槽模板）；键与内置模板单源 MemoryImport 域，本件零复写。
  // 占位符 {content} 必留（插的是待整理文本）；{maxItems} 缺 = 用户显式去掉条数约束
  if (sheetKind === 'memoryImportPrompt') {
    return {
      key: MEMORY_IMPORT_PROMPT_KEY, builtin: MEMORY_IMPORT_PROMPT_TEMPLATE,
      required: MEMORY_IMPORT_PROMPT_CONTENT,
      missingTip: '提示词须包含 ' + MEMORY_IMPORT_PROMPT_CONTENT + ' 占位符，用于插入待整理的文本',
      sheetTitle: '记忆导入提示词', boxPlaceholder: '输入记忆导入提示词'
    };
  }
  // ★ 2026-09-23 上下文压缩笔第七槽：压缩交接摘要生成提示词（输入域 = 会话转写文本）；
  // 键与内置模板单源 CompressGen 域，本件零复写。占位符 {conversation} 必留（插的是待压缩
  // 对话记录）；{supplement} 缺 = 用户显式去掉补充要求插槽，生成侧当空处理
  if (sheetKind === 'compressPrompt') {
    return {
      key: COMPRESS_PROMPT_KEY, builtin: COMPRESS_PROMPT_CONTENT,
      required: COMPRESS_PROMPT_CONVERSATION,
      missingTip: '提示词须包含 ' + COMPRESS_PROMPT_CONVERSATION + ' 占位符，用于插入待压缩的对话记录',
      sheetTitle: '上下文压缩提示词', boxPlaceholder: '输入上下文压缩提示词'
    };
  }
  return {
    key: TITLE_PROMPT_KEY, builtin: TITLE_PROMPT_TEMPLATE,
    required: TITLE_PROMPT_CONTENT,
    missingTip: '提示词须包含 ' + TITLE_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
    sheetTitle: '标题生成提示词', boxPlaceholder: '输入标题生成提示词'
  };
}

// 槽 → 生效模板现读（七槽单源，2026-09-23 关闭确认笔新增）：各槽落各自域件的现读纯函数
//（定制键非空取定制、'' 回内置——与生成链实际读到的模板同源）。两处消费：①编辑面板打开时
// 播种输入框（openPromptSlot）；②关闭前脏态判据（requestClosePrompt 的比对右侧）。
// ★ 必须是**现读**、不得改成打开时快照：面板内「恢复默认」会即时清定制键并把内置模板回显到
// 输入框，此刻内容与生效值相等、不该弹确认；快照比对会把这种情形误报成「有未保存改动」
export function effectivePromptOf(sheetKind: string): string {
  if (sheetKind === 'memoryPrompt') {
    return resolveMemoryPromptTemplate();
  }
  if (sheetKind === 'memoryImportPrompt') {
    return resolveMemoryImportPromptTemplate();
  }
  if (sheetKind === 'memoryOptPrompt') {
    return resolveMemoryOptPromptTemplate();
  }
  if (sheetKind === 'ocrPrompt') {
    return resolveOcrPromptTemplate();
  }
  if (sheetKind === 'suggestPrompt') {
    return resolveSuggestPromptTemplate();
  }
  if (sheetKind === 'compressPrompt') {
    return resolveCompressPromptTemplate();
  }
  return resolveTitlePromptTemplate();
}
