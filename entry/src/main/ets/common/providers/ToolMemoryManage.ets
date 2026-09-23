// 记忆管理工具域（2026-09-13 任务书-记忆管理工具-20260913，第 15 件内置工具 manage_memory
// 的执行器与中转）：助手经自然语言管理长期记忆库（★ 2026-09-21 剥离笔起**非独占**——自
// CONSOLE_EXCLUSIVE_TOOLS 移出，普通助手经助手工具页「记忆」卡开关可开；作用域见下方条）
// ——list 完整查看条数/内容/顺序，
// create/update/delete 三写（含 delete，拍板 1：记忆删除无「N 会话引用」级联链，UI 记忆页
// 有完整管理兜底——突破 manage_prompts 无 delete 先例）。
// · 校验/定位/回执纯逻辑全在 MemoryText（零 import 直跑域，断言脚本复制直跑，search_memory
//   纯函数同款待遇）；本文件只做 IO 编排：queryMemories → 定位 → 写原语 → 广播 → 回执。
// · 定位 = 记忆原文精确匹配（拍板 2：0 命中回名单 / ≥2 命中拒歧义）——list 回执里的原文
//   即 update/delete 的定位键，连续操作不漂移。
// · create 落库形态与 UI 手动新增同形（MemoryEditPage）：source='manual'、assistantId=''、
//   conversationId=''（拍板 5——工具是用户意志的代理，语义归人工渠道，UI 副行「手动添加」
//   文案与既有断言零改动）；sortOrder 由 insertMemory 取 max+1 落卡底 = 注入序末尾，与 UI
//   新增行为一致。
// · 库满拒绝单源复用 MemoryGen 的 MEMORY_FULL_TIP（记忆页「＋」新建键上限拦截同句——同一
//   状况同一说法）。MEMORY_FULL_TIP import 自 MemoryGen：MemoryGen 现引叶子 ToolContracts
//   （2026-09-13 闪退修复笔外迁接口，原 ToolTypes↔域 反向环全数斩断——环内模块作用域读写对方
//   绑定会踩未初始化绑定，真机启动闪退实锤），故此处只余「常量读」，恒就绪。
// · 三写点后均 broadcastMemoryList（MemoryPage 前台列表即时刷新，自动链写点同款）。
// · 恒 resolve 不 reject（外拆域件先例）：全部错误态走纯文本回执（非法参数 / 定位失败 /
//   库满 / update 行已被删的 affected-0 防御）；原语抛错已捕获转文本，兜底由
//   executeToolCall 包装 error JSON 不炸轮次。
// · 管理面独立（拍板 4）：记忆总开关关 / 读取方式 = 按需读取 / 助手 memoryInject 关均不
//   影响本件——与 UI「停用后仍可查看、编辑和删除」同口径；search_memory 的四闸与隐私过滤
//   均不挂本件（ChatSendCtrl 声明收集处零特判，普通件经 defsFor 自动声明）。
// · 作用域（v35，2026-09-20 助手级记忆）：执行者的记忆库经 MEMORY_EXEC_ASSISTANT_KEY 中转
//   （键非空 = 执行者助手自己的库 / 空 = 全局库——与 search_memory 同判据同键）；list/
//   create/update/delete 全程锁定同一库，原文定位只在本库集合内命中 = 跨库操作天然隔离
//   （隔离靠定位集锁本库，非前缀判据——两库行 id 前缀 'asmem-'/'mem-' 是 nextMessageId
//   连字符形态，仅供人读）；上限口径两库一致（MEMORY_MAX_TOTAL
//   库级独立计数）。
import { ToolExecutor } from './ToolContracts';
import { ManageMemoryValidation, MemoryLocateOutcome, MemoryManageItem,
  MEMORY_CONTENT_MAX, MEMORY_MANAGE_LIST_DEFAULT_COUNT, MEMORY_MANAGE_LIST_MAX_COUNT,
  locateMemoryByContent, validateManageMemoryArgs, composeMemoryManageList,
  composeMemoryManageNoHit, composeMemoryManageMultiHit, composeMemoryManageCreateReply,
  composeMemoryManageUpdateReply, composeMemoryManageDeleteReply } from '../MemoryText';
import { broadcastAssistantMemoryList, broadcastMemoryList, countAssistantMemories,
  countMemories, deleteAssistantMemory, deleteMemory, insertAssistantMemory, insertMemory,
  MemoryRow, MEMORY_MAX_TOTAL, queryAssistantMemories, queryMemories,
  updateAssistantMemoryContent, updateMemoryContent } from '../store/MemoryDb';
import { MEMORY_EXEC_ASSISTANT_KEY, MEMORY_FULL_TIP } from '../MemoryGen';

// 工具名常量 TOOL_MANAGE_MEMORY 归口 ToolTypes.ets（与注册/反向拦截/seed 同源引用，本域
// 不重复定义防漂移）。

// schema：上限值随常量单源动态拼（照 buildManagePromptsDesc 先例——改常量 schema 自随）
export const MANAGE_MEMORY_SCHEMA: string =
  '{"type":"object","properties":{"action":{"type":"string",' +
  '"enum":["list","create","update","delete"],' +
  '"description":"list=查看全部记忆（按注入顺序编号），create=新增一条，update=修改一条，delete=删除一条"},' +
  '"content":{"type":"string","description":"create=新记忆全文（' + MEMORY_CONTENT_MAX +
  ' 字内）；update/delete=目标记忆的原文，必须逐字引用 list 返回的内容"},' +
  '"new_content":{"type":"string","description":"update 专用，修改后的记忆全文（' +
  MEMORY_CONTENT_MAX + ' 字内）"},' +
  '"offset":{"type":"integer","description":"list 专用，从第几条开始（默认 1）"},' +
  '"limit":{"type":"integer","description":"list 专用，本页条数（默认 ' +
  MEMORY_MANAGE_LIST_DEFAULT_COUNT + '，最大 ' + MEMORY_MANAGE_LIST_MAX_COUNT + '）"}},' +
  '"required":["action"]}';

// desc：说明四 action 与原文定位规则、库上限（常量单源——RikkaHub #1356 教训：不嵌任何
// 随时间变化的值，常量上限无碍提示缓存）、「执行后向用户复述」的行为要求（与控制台提示词
// 的写操作策略句同向）；★ v35 补作用域语义一句（能力单源在 desc，随请求下发模型每请求可见）；
// ★ 2026-09-21 剥离笔补末句 = 与知识库的双向划界（决策 10）——只点**域名**不点工具名
//（inject 模式或助手未启用知识库时该工具可能未声明，点名会诱导模型调用未声明工具白耗一轮）
export function buildManageMemoryDesc(): string {
  return '管理用户的长期记忆库。记忆范围 = 当前助手的记忆作用域（助手记忆时操作该助手的' +
    '记忆库，全局记忆时操作全局记忆库）。action 取 list 按注入顺序查看全部记忆（分页，每页默认 ' +
    MEMORY_MANAGE_LIST_DEFAULT_COUNT + ' 条），create 新增一条，update 与 delete 按原文定位后' +
    '修改或删除一条。update 与 delete 的 content 必须逐字引用 list 返回的某条记忆原文，' +
    '改删前先 list 查看原文。库上限 ' + MEMORY_MAX_TOTAL + ' 条，单条上限 ' + MEMORY_CONTENT_MAX +
    ' 字。仅在用户明确要求时调用，执行后向用户复述改了什么。' +
    '与用户无关的领域知识属于知识库，不在记忆库范围，整理那类内容请用知识库那一族。';
}

// MemoryRow → 定位/回执最小形态（零 import 域不引 DB 类型——适配在此单点）
function toManageItems(rows: MemoryRow[]): MemoryManageItem[] {
  const items: MemoryManageItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, content: row.content });
  }
  return items;
}

// 目标库读取（v35 分派单点：键非空 = 执行者助手库，空 = 全局库——list/update/delete 定位
// 与 search_memory 同判据）
function readTargetLibrary(targetAssistantId: string): Promise<MemoryRow[]> {
  return targetAssistantId !== '' ?
    queryAssistantMemories(targetAssistantId) : queryMemories();
}

// 目标库广播（写点收口：三写动作按库分派广播键——两库列表页各自 @Watch 重拉）
function broadcastForLibrary(targetAssistantId: string): void {
  if (targetAssistantId !== '') {
    broadcastAssistantMemoryList();
  } else {
    broadcastMemoryList();
  }
}

// 记忆管理执行器：校验 → 按 action 分路（list 只读 / create 上限守卫 + 新增 / update 与
// delete 定位三态 → 写原语 → 广播 → 回执）。导出 = ToolTypes 注册引用 + 断言脚本源码形态钉。
// ★ v35：全程锁定执行者作用域库（targetAssistantId —— execute 入口一次读取，四 action
// 同值；原文定位只在本库集合内命中 = 跨库操作天然隔离）
export class ManageMemoryExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: ManageMemoryValidation = validateManageMemoryArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(v.error);
    }
    const targetAssistantId: string = AppStorage.get<string>(MEMORY_EXEC_ASSISTANT_KEY) ?? '';
    if (v.action === 'list') {
      return readTargetLibrary(targetAssistantId).then((rows: MemoryRow[]): string =>
        composeMemoryManageList(toManageItems(rows), v.offset, v.limit));
    }
    if (v.action === 'create') {
      const countRead: Promise<number> = targetAssistantId !== '' ?
        countAssistantMemories(targetAssistantId) : countMemories();
      return countRead.then((count: number): Promise<string> => {
        if (count >= MEMORY_MAX_TOTAL) {
          return Promise.resolve(MEMORY_FULL_TIP);
        }
        const insertDone: Promise<MemoryRow> = targetAssistantId !== '' ?
          insertAssistantMemory(targetAssistantId, v.content, 'manual', '') :
          insertMemory({ content: v.content, source: 'manual', assistantId: '',
            conversationId: '' });
        return insertDone
          .then((_row: MemoryRow): string => {
            broadcastForLibrary(targetAssistantId);
            return composeMemoryManageCreateReply(v.content, count + 1);
          });
      });
    }
    // update / delete：原文精确匹配定位（三态判定在纯函数层；定位集 = 目标库）
    return readTargetLibrary(targetAssistantId).then((rows: MemoryRow[]): Promise<string> => {
      const items: MemoryManageItem[] = toManageItems(rows);
      const outcome: MemoryLocateOutcome = locateMemoryByContent(items, v.content);
      if (outcome.state === 'none') {
        return Promise.resolve(composeMemoryManageNoHit(items));
      }
      if (outcome.state === 'multi') {
        return Promise.resolve(composeMemoryManageMultiHit(outcome.hits));
      }
      if (v.action === 'update') {
        // updateMemoryContent 只写 content + updatedAt（sortOrder/createdAt/source 保持）；
        // affected 0 抛错 = 定位与落库间行被删的防御，捕获转文本回执
        const write: Promise<void> = targetAssistantId !== '' ?
          updateAssistantMemoryContent(outcome.hitId, v.newContent) :
          updateMemoryContent(outcome.hitId, v.newContent);
        return write
          .then((): string => {
            broadcastForLibrary(targetAssistantId);
            return composeMemoryManageUpdateReply(outcome.hitContent, v.newContent);
          })
          .catch((e: Object): string => '修改未生效：' + (e as Error).message);
      }
      const del: Promise<void> = targetAssistantId !== '' ?
        deleteAssistantMemory(outcome.hitId) : deleteMemory(outcome.hitId);
      return del
        .then((): string => {
          broadcastForLibrary(targetAssistantId);
          return composeMemoryManageDeleteReply(outcome.hitContent, rows.length - 1);
        })
        .catch((e: Object): string => '删除未生效：' + (e as Error).message);
    });
  }
}
