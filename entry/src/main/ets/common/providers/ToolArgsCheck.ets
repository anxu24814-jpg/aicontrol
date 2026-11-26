// 执行前统一参数校验（任务书 = docs/任务书-工具易用性P0P2P3施工-20261024.md §2）。
// 职责缝一句话：模型回参对注册表 schema 的执行前四项校验，纯函数、恒不抛。
// 为何不并入 ToolRuntime = ToolRuntime 有 6 个 import 非零 import 叶子，并入即失断言复制
// 直跑能力（坑50 判据下零 import 叶子结构上不可能入环，环扫描器自动收录零新边）；本件
// 一旦引入任何 import 即破坏直跑前提（照 ToolLimits / SkillText 零 import 叶子先例）。
// ── 契约（其余 JSON Schema 关键字一律忽略）──
// · 四项检查：①顶层对象（args 必须是 JSON 对象）②required 缺失（一次列全）③类型不匹配
//   （仅查 properties 已声明属性；integer 视同 number 不查整性——克制）④enum 越界（enum
//   非数组形态忽略该关键字）。
// · ★ 宽容度原则（修复笔 D3/D4）：校验器宽容度必须 ≥ 执行器宽容度——校验器更严 = 把
//   执行器本可执行的调用变成错参（P0 误拦面）；反之只是放行给执行器语义层兜底。落地两条：
//   enum 字符串档 trim + 小写归一后比较（对齐 http_request.method 的 toUpperCase /
//   chart_display.style 的 toLowerCase 等执行器归一习惯，中文值 trim 不受小写影响；非
//   string 值仍严格 ===）；number/integer 档接受纯数字 string（执行器 argsMountId 等明确
//   parseInt 数字串；判据 = 正则整串数字形态，防 "12abc"/"1e3"/"0x10" 混过）。
// · fail-closed 但校验器自身故障放行：函数体自包 try，任何内部异常（含 JSON.parse 抛错）返
//   null = 不拦，交执行器既有错误链兜底（照 ConfirmPrompt.preflight「恒不抛」契约先例，
//   ToolContracts.ets 注释）——校验器自损宁可放行，不误拦合法调用。
// · schema 侧防御：parse 失败 / 非对象 / 无 properties → 返 null 放行（MCP 兜底 schema
//   {"type":"object","properties":{}} 天然恒过，安全方向）。
// · ★ type 容错规则：type 字段非 string/number/integer/boolean/array/object 六类单值字符串
//   ——含数组形态（如 ["string","null"]，JSON Schema 标准 union 写法、MCP 第三方 server
//   OpenAPI 风格 schema 常见）、野值（"null"/"any"/方言值）、非字符串——即跳过该项的类型
//   检查（fail-open，与 enum 非数组忽略同向；防 MCP 真实 schema 误拒合法调用）。properties
//   成员本身非对象：跳过该属性。未声明属性一律不查（不拒多余键——scrape_web 收误传 query
//   当 url 的别名防御继续生效）。
// · ★ kill-switch（功能保险类，同族先例 = ToolLimits.TOOL_DEFS_BUDGET_ENABLED 族）：校验器
//   bug 误拦时改本常量为 false 重新构建出包即净直通。
// · 文案契约（模型面教学文案，中文，与既有 error 回执族同语；四要素 = 字段名 + 期望 + 收到
//   值开头片段 + 重试指引）：值片段压缩空白后取开头 80 字符（与 toolArgsParseErrorText 同
//   口径，ToolContracts.ets——零 import 纪律下同值私判内联 + 注释指源）；enum 值集超 12 个
//   只列前 12 + 总数说明。
export const TOOL_ARGS_CHECK_ENABLED: boolean = true;

// 值片段开头上限：与 ToolContracts.toolArgsParseErrorText 同值同式（零 import 纪律禁引彼件，
// 同值关系由 assert-tool-domain 419 组直跑钉行为面覆盖）
const ARGS_CHECK_SNIPPET_MAX: number = 80;
// enum 值集列举上限：超 12 个值只列前 12 +「等 N 个值」——值集教学文案克制长度
const ENUM_LIST_MAX: number = 12;

// 值开头片段：压缩空白（连续空白折为一空格）后取开头 N 字符，超限缀省略号
function clipHeadSnippet(text: string): string {
  const compact: string = text.replace(/\s+/g, ' ').trim();
  return compact.length > ARGS_CHECK_SNIPPET_MAX ?
    compact.substring(0, ARGS_CHECK_SNIPPET_MAX) + '…' : compact;
}

// 值显示形态：string 原样（文案里不带引号好读），其余 JSON 序列化（number/boolean/null/对象）
function valueShown(value: Object | null): string {
  if (typeof value === 'string') {
    return value;
  }
  return JSON.stringify(value);
}

// args 值的 JSON 形态名（六词 + null）：null 须显式前置（typeof null === 'object' 是 JS
// 历史包袱，JSON 语义里 null 不属于 object）
function argValueTypeOf(value: Object | null): string {
  if (value === null) {
    return 'null';
  }
  if (typeof value === 'string') {
    return 'string';
  }
  if (typeof value === 'number') {
    return 'number';
  }
  if (typeof value === 'boolean') {
    return 'boolean';
  }
  if (Array.isArray(value)) {
    return 'array';
  }
  return 'object';
}

// enum 值匹配（修复笔 D3）：string 档 trim + 小写归一后比较（与执行器归一习惯对齐，中文值
// trim 不受小写影响），校验器宽容度不得低于执行器；非 string 值（number/boolean/null）无
// 归一语义，保持严格 ===。
function enumValueMatches(allowed: Object | null, value: Object): boolean {
  if (typeof allowed === 'string' && typeof value === 'string') {
    return allowed.trim().toLowerCase() === value.trim().toLowerCase();
  }
  return allowed === value;
}

// 纯数字串（修复笔 D4）：number/integer 档宽容——执行器明确宽容数字串（ToolMount.
// argsMountId「模型偶发传数字串也收」走 parseInt），校验器不得比执行器更严。正则整串数字
// 形态（可选负号 + 可选小数），不用 Number() 单判——后者额外接受 "1e3"/"0x10"/" 12" 等
// 执行器 parseInt 语义外的形态。
function isNumericString(text: string): boolean {
  return /^-?\d+(\.\d+)?$/.test(text.trim());
}

// enum 值集列举文案：全列（≤ 上限）或前上限个 + 总数括注（值集来自 schema，见参数说明即
// 模型侧的 parameters description）
function enumListText(values: Object[]): string {
  const shown: string[] = [];
  const limit: number = Math.min(values.length, ENUM_LIST_MAX);
  for (let i = 0; i < limit; i++) {
    shown.push(valueShown(values[i]));
  }
  return values.length > ENUM_LIST_MAX ?
    shown.join('、') + '（等 ' + values.length + ' 个值，见参数说明）' : shown.join('、');
}

// ── 主函数：四项校验，全过返 null（不拦），任一不过返字段级中文文案 ──
// 挂接点 = ToolRuntime.executeToolCall 函数体内、executor.execute 之前（挂函数内 = 主链
// 与重发链两调用文件全覆盖）
export function toolArgsCheckErrorText(schemaJson: string, argsJson: string): string | null {
  if (!TOOL_ARGS_CHECK_ENABLED) {
    return null;
  }
  try {
    const schemaTop: Object | null = JSON.parse(schemaJson) as Object | null;
    if (schemaTop === null || typeof schemaTop !== 'object' || Array.isArray(schemaTop)) {
      return null; // schema 非对象 = 防御放行
    }
    const schema: Record<string, Object> = schemaTop as Record<string, Object>;
    const propsRaw: Object | undefined = schema['properties'];
    if (propsRaw === undefined || propsRaw === null ||
      typeof propsRaw !== 'object' || Array.isArray(propsRaw)) {
      return null; // 无 properties / properties 非对象 = 防御放行（MCP 兜底 schema 恒过）
    }
    const props: Record<string, Object> = propsRaw as Record<string, Object>;
    const argsTop: Object | null = JSON.parse(argsJson) as Object | null;
    // ① 顶层对象（数组/字符串/数字/布尔/null 拒——args 串本身非法 JSON 时走下方 catch 返
    // null 放行，交执行器既有参数解析回执兜底）
    if (argsTop === null || typeof argsTop !== 'object' || Array.isArray(argsTop)) {
      return '工具参数必须是 JSON 对象，收到内容开头：' + clipHeadSnippet(argsJson) +
        '。请按工具参数说明重试。';
    }
    const args: Record<string, Object> = argsTop as Record<string, Object>;
    // ② required 缺失：逐项查在场，缺失项一次列全（减少模型自纠往返轮次）；required 非数组
    // 忽略（容错），成员非字符串跳过（fail-open）
    const requiredRaw: Object | undefined = schema['required'];
    if (Array.isArray(requiredRaw)) {
      const missing: string[] = [];
      for (const nameItem of requiredRaw as Object[]) {
        if (typeof nameItem === 'string' && args[nameItem] === undefined) {
          missing.push(nameItem);
        }
      }
      if (missing.length > 0) {
        return '缺少必填参数：' + missing.join('、') + '。请补上后重试。';
      }
    }
    // ③④ 逐属性：类型检查 + enum 越界（一个属性内先类型后 enum；按 schema 声明序首个命中即返）
    for (const key of Object.keys(props)) {
      const value: Object | undefined = args[key];
      if (value === undefined) {
        continue; // 不在场的声明属性不查（缺省与否由 required 管，可选属性可缺）
      }
      const specRaw: Object | undefined = props[key];
      if (specRaw === undefined || specRaw === null ||
        typeof specRaw !== 'object' || Array.isArray(specRaw)) {
        continue; // properties 成员非对象 = 跳过该属性（fail-open 显式规则）
      }
      const spec: Record<string, Object> = specRaw as Record<string, Object>;
      // ③ 类型不匹配：type 容错规则见文件头；integer 视同 number（不查整性——克制，传
      // 1.5 也过由执行器语义层兜）
      const typeRaw: Object | undefined = spec['type'];
      if (typeof typeRaw === 'string') {
        const declared: string = typeRaw;
        if (declared === 'string' || declared === 'number' || declared === 'integer' ||
          declared === 'boolean' || declared === 'array' || declared === 'object') {
          const actual: string = argValueTypeOf(value);
          let typeOk: boolean = declared === 'integer' ? actual === 'number' : actual === declared;
          // number/integer 档宽容纯数字 string（校验器宽容度不得低于执行器）；其余类型保持严格
          if (!typeOk && typeof value === 'string' &&
            (declared === 'number' || declared === 'integer')) {
            typeOk = isNumericString(value);
          }
          if (!typeOk) {
            return '参数 ' + key + ' 的类型应为 ' + declared + '，收到 ' + actual +
              '（值开头：' + clipHeadSnippet(valueShown(value)) + '）。请修正后重试。';
          }
        }
      }
      // ④ enum 越界：enum 为数组且成员全为原始值（string/number/boolean/null）时才检查——
      // 成员含对象/数组（脏 schema）时引用比较永 miss 必误拒，整体忽略该关键字（fail-open）
      const enumRaw: Object | undefined = spec['enum'];
      if (Array.isArray(enumRaw)) {
        const enumValues: Object[] = enumRaw as Object[];
        let hasNonPrimitive: boolean = false;
        for (const allowed of enumValues) {
          if (allowed !== null && typeof allowed === 'object') {
            hasNonPrimitive = true;
            break;
          }
        }
        if (!hasNonPrimitive) {
          let hit: boolean = false;
          for (const allowed of enumValues) {
            if (enumValueMatches(allowed, value)) {
              hit = true;
              break;
            }
          }
          if (!hit) {
            return '参数 ' + key + ' 的取值必须是 ' + enumListText(enumValues) +
              ' 之一，收到值开头：' + clipHeadSnippet(valueShown(value)) + '。请从这些值里选。';
          }
        }
      }
    }
    return null; // 四项全过 = 不拦
  } catch (e) {
    return null; // 自损放行：任何内部异常不拦，交执行器既有错误链兜底
  }
}
