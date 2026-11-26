// 提示词槽规格表（自 FunctionalModelPage.ets 域级最小拆分——原表逐字搬迁、未改一处判据）。职责：槽 kind →
// 定制键 / 内置模板 / 必留占位符 / 面板标题 / 输入框占位 / 生效模板现读——宿主功能模型页八槽（标题生成 /
// 记忆提取 / 记忆导入 / 记忆优化 / 文字识别 / 推荐问题 / 上下文压缩 / 命令审批）的编辑面板播种
//（openPromptSlot）、保存校验与恢复默认（savePrompt / restorePrompt）、**关闭前脏态判据**都取本表。
// 为什么不并入 PromptTemplateDb.ets：那件是 **DB 域**（用户自存模板资产 CRUD 与上限），本件是
// **纯规格表**（AppStorage 现读、零 DB 依赖、断言脚本可剥读）；并入会让 DB 件反向依赖 UI 槽语义。
// ★ 新增提示词槽必须同笔改三处（原铁律随表部分外移，另两处在 FunctionalModelPage 头注释）：
//   ①本表加分支（漏 = 未知 sheetKind 静默落默认标题槽，编辑保存会**写到标题提示词键上**，最隐蔽）；
//   ②宿主 sheetKind 值域注释；③宿主 isPromptSheet() 加 `||` 项（漏 = 面板不渲染，点键没反应）。
//   三处任一漏改都能编译通过。
// ★ required（单占位符串）已扩为 **requiredList（多占位符数组）**：审批槽五占位符全拦（缺任一 = 模型盲判，
//   安全弱化；拍板记录见 ApprovalGate 头注释）；七个旧槽以单元素数组保持行为等价（OCR 槽 requiredList: []）。
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
import { APPROVAL_PROMPT_KEY, APPROVAL_PROMPT_REQUIRED, APPROVAL_PROMPT_TEMPLATE,
  approvalLevelPromptText,
  resolveApprovalPromptTemplate } from '../../common/providers/ApprovalGate';
import { CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE } from '../../common/providers/ToolContracts';

// 提示词槽规格（保存校验 / 恢复默认回显 / 面板标题 / 输入框占位 / 缺占位符文案五处按槽取，
// 禁各处再写一遍三目链（P2-4））
export interface PromptSlot {
  key: string; // 定制键（'' = 未定制 = 生效 builtin）
  builtin: string; // 内置默认模板（「恢复默认」回显）
  requiredList: string[]; // 必须保留的占位符（缺任一 = 保存拦截）；[] = 本槽无占位符不校验（识别提示词）
  missingTip: string; // 单占位符槽的缺占位符拦截文案；多占位符槽由保存侧动态列出缺项，不用本字段
  sheetTitle: string; // 编辑面板标题
  boxPlaceholder: string; // 输入框占位文案
  // 面板说明小字（'' = 不渲染；占位符的运行时展开在组装时发生，面板只见占位符本体，此字段把
  // 展开文本亮给用户）
  hint: string;
}

// 槽规格解析（sheetKind → 规格；'prompt' = 标题卡，未知值同落标题槽——宿主 SheetHost 分支已保证只有八种提示词
// kind 会走到这里）。★ 识别提示词槽（'ocrPrompt'）无占位符——识别链的图片以附件部件随请求发送，不是文本插值，
// 保存不做占位符校验；键与内置模板单源 OcrVisionApi 域
export function resolvePromptSlot(sheetKind: string): PromptSlot {
  if (sheetKind === 'ocrPrompt') {
    return {
      key: OCR_PROMPT_KEY, builtin: OCR_PROMPT_TEMPLATE,
      requiredList: [],
      missingTip: '',
      sheetTitle: '文字识别提示词', boxPlaceholder: '输入文字识别提示词', hint: ''
    };
  }
  if (sheetKind === 'suggestPrompt') {
    return {
      key: SUGGEST_PROMPT_KEY, builtin: SUGGEST_PROMPT_TEMPLATE,
      requiredList: [SUGGEST_PROMPT_CONTENT],
      missingTip: '提示词须包含 ' + SUGGEST_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
      sheetTitle: '推荐问题提示词', boxPlaceholder: '输入推荐问题提示词', hint: ''
    };
  }
  if (sheetKind === 'memoryPrompt') {
    return {
      key: MEMORY_PROMPT_KEY, builtin: MEMORY_PROMPT_TEMPLATE,
      requiredList: [MEMORY_PROMPT_CONTENT],
      missingTip: '提示词须包含 ' + MEMORY_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
      sheetTitle: '记忆提取提示词', boxPlaceholder: '输入记忆提取提示词', hint: ''
    };
  }
  if (sheetKind === 'memoryOptPrompt') {
    return {
      key: MEMORY_OPT_PROMPT_KEY, builtin: MEMORY_OPT_PROMPT_TEMPLATE,
      requiredList: [MEMORY_OPT_PROMPT_MEMORIES],
      missingTip: '提示词须包含 ' + MEMORY_OPT_PROMPT_MEMORIES + ' 占位符，用于插入记忆条目清单',
      sheetTitle: '记忆优化提示词', boxPlaceholder: '输入记忆优化提示词', hint: ''
    };
  }
  // ★ 记忆导入槽：导入整理用独立提示词（输入域 = 外部平台文本，与本库会话记录不同，不能共用
  // 提取槽模板）；键与内置模板单源 MemoryImport 域。{content} 必留；{maxItems} 缺 = 用户显式去掉条数约束
  if (sheetKind === 'memoryImportPrompt') {
    return {
      key: MEMORY_IMPORT_PROMPT_KEY, builtin: MEMORY_IMPORT_PROMPT_TEMPLATE,
      requiredList: [MEMORY_IMPORT_PROMPT_CONTENT],
      missingTip: '提示词须包含 ' + MEMORY_IMPORT_PROMPT_CONTENT + ' 占位符，用于插入待整理的文本',
      sheetTitle: '记忆导入提示词', boxPlaceholder: '输入记忆导入提示词', hint: ''
    };
  }
  // ★ 上下文压缩槽：压缩交接摘要生成提示词（输入域 = 会话转写文本）；键与内置模板单源 CompressGen
  // 域。{conversation} 必留；{supplement} 缺 = 用户显式去掉补充要求插槽，生成侧当空处理
  if (sheetKind === 'compressPrompt') {
    return {
      key: COMPRESS_PROMPT_KEY, builtin: COMPRESS_PROMPT_CONTENT,
      requiredList: [COMPRESS_PROMPT_CONVERSATION],
      missingTip: '提示词须包含 ' + COMPRESS_PROMPT_CONVERSATION + ' 占位符，用于插入待压缩的对话记录',
      sheetTitle: '上下文压缩提示词', boxPlaceholder: '输入上下文压缩提示词', hint: ''
    };
  }
  // ★ 审批提示词槽（决明拍板开放查看/编辑/恢复默认）：键与内置模板单源 ApprovalGate 域。**五占位符
  // 全拦**（缺任一 = 该段信息不随请求给模型 = 盲判，安全弱化；缺项由保存侧动态列出）。防注入句与
  // JSON 输出格式句不设「必留句」校验（拍板接受可删——输入侧硬隔离是主防线，恢复默认键兜回）。
  // hint 说明 {level} 运行时按风险档位展开（面板只见占位符本体；展开文本经
  // approvalLevelPromptText 单源派生，禁抄本——档位规则改动自动跟随）
  if (sheetKind === 'approvalPrompt') {
    return {
      key: APPROVAL_PROMPT_KEY, builtin: APPROVAL_PROMPT_TEMPLATE,
      requiredList: APPROVAL_PROMPT_REQUIRED,
      missingTip: '',
      sheetTitle: '审批提示词', boxPlaceholder: '输入审批提示词',
      hint: '{level} 不会原样发给审批模型，运行时按风险档位展开。写操作档展开为「' +
        approvalLevelPromptText(CONFIRM_LEVEL_WRITE) + '」。不可逆档展开为「' +
        approvalLevelPromptText(CONFIRM_LEVEL_IRREVERSIBLE) + '」。展开文字由应用提供，' +
        '不受本面板编辑影响。'
    };
  }
  return {
    key: TITLE_PROMPT_KEY, builtin: TITLE_PROMPT_TEMPLATE,
    requiredList: [TITLE_PROMPT_CONTENT],
    missingTip: '提示词须包含 ' + TITLE_PROMPT_CONTENT + ' 占位符，用于插入对话内容',
    sheetTitle: '标题生成提示词', boxPlaceholder: '输入标题生成提示词', hint: ''
  };
}

// 槽 → 生效模板现读（八槽单源）：各槽落各自域件的现读纯函数（定制键非空取定制、'' 回内置——与生成链实际读到
// 的模板同源）。两处消费：①编辑面板打开时播种输入框（openPromptSlot）；②关闭前脏态判据（比对右侧）。
// ★ 必须**现读**、不得改成打开时快照：面板内「恢复默认」会即时清定制键并把内置模板回显到输入框，此刻内容与
// 生效值相等、不该弹确认；快照比对会把这种情形误报成「有未保存改动」
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
  if (sheetKind === 'approvalPrompt') {
    return resolveApprovalPromptTemplate();
  }
  return resolveTitlePromptTemplate();
}

// 提示词卡面状态广播：八张卡的提示词行值显示「默认 / 已自定义」——定制键非空即已自定义（与 effectivePromptOf
// 的 '' 回内置同判据）。保存 / 恢复默认后宿主递增本键，各卡行 @StorageProp 订阅即刷；非持久键（重启归零无影响）
export const PROMPT_STATE_EPOCH_KEY: string = 'functionalPromptStateEpoch';

export function isPromptCustomized(sheetKind: string): boolean {
  return (AppStorage.get<string>(resolvePromptSlot(sheetKind).key) ?? '') !== '';
}

export function bumpPromptStateEpoch(): void {
  AppStorage.setOrCreate<number>(PROMPT_STATE_EPOCH_KEY,
    (AppStorage.get<number>(PROMPT_STATE_EPOCH_KEY) ?? 0) + 1);
}
