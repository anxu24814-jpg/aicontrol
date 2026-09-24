// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// assert-price-template.mjs — 价格模板域断言（2026-09-11 拆域笔自 sse-assert.mjs 整块迁出；
// 宪法「脚本例外与拆分触发线」条：主脚本剔头越 6000 行即拆域，拆法 = 按域切 assert-<域>.mjs
// + 共享帮助模块 assert-lib.mjs，门禁逐件登记并以「断言总数 = 各件求和」+「搬迁前后 PASS 名
// 全集逐字比对」为行为等价证明）。
//
// 域内容 = 63 组 27 钉：A 迁移三处同步（DB v28）/ B 删服务商级联事务内 / C 数据层形态（0 行
// throw + 常量判限）/ D 宿主接线（★套用通道「先写载荷后自增纪元」两行序——同值不触发 @Watch
// 的静默失败家族）/ E 形制与复用 / E2 卡宽（条卡与编辑模型页卡体链零 '100%' 扫描——判据同
// sse-assert ㊿ 组 H 段）/ F priceSummary 摘要纯函数（CostStatsCalc 复制直跑）/ G 路由与上限
// 三层防线 / H 既有回归。源码抽取 + 直跑混合。
//
// 运行：node scripts/assert-price-template.mjs（可单独跑；delivery-gate 已登记为子检查之一）。
// 本域触及的文件与主脚本零重叠，值改动此域源文件时本脚本单独跑即够，跨域改动仍跑全门禁。
import { copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { check, report, segOf } from './assert-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const tmpDir = path.join(here, '.tmp');
mkdirSync(tmpDir, { recursive: true });
// 57 组配套：费用估计计算层 2026-09-10（CostStatsCalc 零 import——复制直跑，同
// SseParser/MemoryText 范式；价格解析/序列化/谷时判定/折算/聚合/格式化）
const costCalcSrc = path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', 'common', 'store', 'CostStatsCalc.ets');
copyFileSync(costCalcSrc, path.join(tmpDir, 'CostStatsCalc.ts'));
// ★ 拆域补齐（2026-09-11）：本域 F 段除组内单独 import 的 priceSummary 外，还复用了原
// sse-assert 文件级 import 的 parse/serializePriceConfig——那条隐式依赖在整块搬迁后即
// ReferenceError（等价性证明抓出的第一处），此处按本域实需显式收窄到两项。
const { parsePriceConfig, serializePriceConfig } = await import('./.tmp/CostStatsCalc.ts');

// ═══ 63 组：价格模板（服务商级模板库 + 条卡套用/存模板两链 + 复用价格卡）═══
// 2026-09-11 价格模板执行笔（任务书-价格模板-20260911 §4 断言清单全量，25 钉）：A 迁移三处
// 同步 / B 级联事务内 / C 数据层形态（0 行 throw + 常量判限）/ D 宿主接线（★套用通道
// 「先写载荷后自增纪元」两行序——同值不触发 @Watch 的静默失败家族是本笔最易做错处）/
// E 形制与复用（「选择模板」键 + 半模态行卡——2026-09-11 方案 v3 三处模板统一半模态
//   改写，原 chips 选项胶囊钉位移〔E 段首两钉，位移非删除〕+ 存为模板键四件套 +
//   编辑页复用价格卡不自绘表单）/
// F 摘要纯函数（CostStatsCalc 复制直跑，57 组同源模块缓存 import）/ G 路由与上限三层
// 防线 / H 既有回归（价格卡既有链零改动 + 计算层六导出逐字在位）。源码抽取 + 直跑混合。
{
  const { readFileSync: rfs63 } = await import('node:fs');
  const rd63 = (rel) => rfs63(path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', rel),
    'utf-8').replace(/\r\n/g, '\n');
  const mig63 = rd63('common/store/ChatDbMigrate.ets');
  const pdb63 = rd63('common/store/ProviderDb.ets');
  const ptdb63 = rd63('common/store/PriceTemplateDb.ets');
  const bar63 = rd63('components/settings/PriceTemplateBarCard.ets');
  const mep63 = rd63('components/settings/ModelEditPage.ets');
  const mpc63 = rd63('components/settings/ModelPriceCard.ets');
  const ptp63 = rd63('components/settings/PriceTemplatePage.ets');
  const ptep63 = rd63('components/settings/PriceTemplateEditPage.ets');
  const rn63 = rd63('common/RouteNames.ets');
  const pmb63 = rd63('components/nav/PageMapBuilder.ets');

  // ── A 迁移三处同步（升版铁律）──
  const schema63 = rd63('common/store/ChatDbSchema.ets'); // 2026-09-23 压缩笔：建表常量外迁，文本判据随迁读新件
  const priceSql63 = (/const SQL_CREATE_PRICE_TEMPLATES[\s\S]*?';/.exec(schema63) || [''])[0];
  check('63 迁移-建表 SQL 五列齐（id PK/providerId/name/priceConfig/createdAt）',
    [priceSql63.includes('id TEXT PRIMARY KEY'), priceSql63.includes('providerId TEXT NOT NULL'),
      priceSql63.includes('name TEXT NOT NULL'), priceSql63.includes('priceConfig'),
      priceSql63.includes('createdAt INTEGER NOT NULL')],
    [true, true, true, true, true]);
  const ensure63 = (/export async function ensureSchema[\s\S]*?\n}/.exec(mig63) || [''])[0];
  check('63 迁移-ensureSchema 建表调用在位', ensure63.includes(
    'await db.executeSql(SQL_CREATE_PRICE_TEMPLATES);'), true);
  // ★ 2026-09-22 版本号族关系化笔：本组原「63 迁移-DB_VERSION = 40」值抄本钉**整条退役**
  //（升版必红、判别力为零——合法升版与真失步同红）。版本号一致性自本笔起由
  // assert-store-consistency 143 组「版本-」三钉按关系形态守（常量 vs 两处头标记 vs 末级写），
  // 升版只需改产品源三处，断言零改动。
  const migFn63 = (/export async function migrateSchema[\s\S]*$/.exec(mig63) || [''])[0];
  const br63 = (/if \(db\.version === 27\) \{[\s\S]*?\n  \}/.exec(migFn63) || [''])[0];
  check('63 迁移-v27 逐级分支（CREATE + 只写 28，禁一步写 DB_VERSION）',
    [br63.includes('SQL_CREATE_PRICE_TEMPLATES'), br63.includes('db.version = 28;'),
      !br63.includes('db.version = DB_VERSION')],
    [true, true, true]);

  // ── B 级联（事务内）──
  const delFn63 = (/export async function deleteProvider[\s\S]*?\n}/.exec(pdb63) || [''])[0];
  check('63 级联-deleteProvider 内 price_templates 的 delete（条件 providerId）',
    [delFn63.includes("RdbPredicates('price_templates')"),
      delFn63.includes(".equalTo('providerId', id)")], [true, true]);
  const txBegin63 = delFn63.indexOf('db.beginTransaction()');
  const txCommit63 = delFn63.indexOf('db.commit()');
  const tplDelIdx63 = delFn63.indexOf('await db.delete(templatePredicates)');
  check('63 级联-该 delete 位于 beginTransaction 与 commit 之间（防脱离事务）',
    txBegin63 >= 0 && tplDelIdx63 > txBegin63 && txCommit63 > tplDelIdx63, true);
  // ★ 2026-09-11 自检轮补钉（回归手段）：commit **之后**的会话覆盖级联清必须自吞异常——
  // 抛错会落进外层 catch 对已提交事务 rollBack，并把整笔报成「删除失败」（实况行已删），
  // 连带调用方的 Asset 池清理与列表刷新被跳过（留跨卸载保留的孤儿密钥明文）。
  // 判据跑剥注释源（本段新增的说明注释里含 try/catch/rollBack 字样，不剥会喂绿裸判——坑38）
  const codeOnly63 = (t) => t.split('\n')
    .map((l) => l.replace(/\r$/, '').replace(/\/\/.*$/, '')).join('\n');
  // ★ 2026-09-13 N11 判据族收口：区域上界原为**函数尾**——区域内 `} catch (e) {` 有 2 处
  //（内层自吞 catch + 外层兜底 catch），内层 catch 被换成 `} finally {` 之类时仍能取到外层的
  // 而绿。改收在**外层 catch 之前**（尾锚两空格缩进；内层是四空格，不误命中），区域 = 级联清段
  const afterCommit63 = segOf(codeOnly63(delFn63), 'db.commit()', '\n  } catch (e) {');
  const clearIdx63 = afterCommit63.indexOf('clearConversationModelOverride');
  check('63 级联-commit 后的会话覆盖级联清被内层 try/catch 包裹（抛错不得触发外层 rollBack）',
    [afterCommit63.includes('try {'),
      clearIdx63 > afterCommit63.indexOf('try {'),
      afterCommit63.indexOf('} catch (e) {') > clearIdx63], [true, true, true]);

  // ── C 数据层形态 ──
  check('63 数据层-四函数齐（queryByProvider/insert/update/delete）',
    [/export async function queryTemplatesByProvider/.test(ptdb63),
      /export async function insertTemplate/.test(ptdb63),
      /export async function updateTemplate/.test(ptdb63),
      /export async function deleteTemplate/.test(ptdb63)],
    [true, true, true, true]);
  const updFn63 = (/export async function updateTemplate[\s\S]*?\n}/.exec(ptdb63) || [''])[0];
  check('63 数据层-updateTemplate 0 行 throw（防假成功）',
    /affected === 0[\s\S]*?throw new Error/.test(updFn63), true);
  const insFn63 = (/export async function insertTemplate[\s\S]*?\n}/.exec(ptdb63) || [''])[0];
  check('63 数据层-上限判限引用常量非字面量（判限处不含裸 20/50）',
    [/existing\.length >= PRICE_TEMPLATE_MAX/.test(insFn63),
      !/>= 20\b/.test(insFn63), !/maxLength = 50|length > 50/.test(ptdb63)],
    [true, true, true]);
  check('63 数据层-insert/update 两写点均含 priceConfig 列',
    [insFn63.includes("'priceConfig'"), updFn63.includes("'priceConfig'")], [true, true]);

  // ── D 宿主接线（套用通道两行序 = 本笔最易做错处）──
  check('63 接线-套用通道 applyJson/applyTick 两 @Link 成对（两宿主 $ 绑定 + 卡 @Link + 无 @Prop 回退）',
    [mep63.includes('applyJson: $priceApplyJson,'), mep63.includes('applyTick: $priceApplyTick,'),
      ptep63.includes('applyJson: $applyJson,'), ptep63.includes('applyTick: $applyTick,'),
      /^\s*@Link applyJson: string;$/m.test(mpc63),
      /^\s*@Link @Watch\('onApplyTick'\) applyTick: number;$/m.test(mpc63),
      /^\s*@Prop\b.*(applyJson|applyTick)/m.test(mpc63)],
    [true, true, true, true, true, true, false]);
  const applyFn63 = (/private applyPriceTemplate[\s\S]*?\n  \}/.exec(mep63) || [''])[0];
  const idxJson63 = applyFn63.indexOf('this.priceApplyJson = priceConfig;');
  const idxTick63 = applyFn63.indexOf('this.priceApplyTick += 1;');
  check('63 接线-先写载荷后自增纪元（两行序，调换即同值不触发静默失败）',
    idxJson63 >= 0 && idxTick63 >= 0 && idxJson63 < idxTick63, true);
  const saveTpl63 = (/private onSaveAsTemplate[\s\S]*?\n  \}/.exec(mep63) || [''])[0];
  check('63 接线-存为模板守卫（json 非空 + complete，hint 优先直显）',
    [saveTpl63.includes("this.priceDraft.json === ''"),
      saveTpl63.includes('!this.priceDraft.complete'),
      saveTpl63.includes('this.priceDraft.hint')], [true, true, true]);
  check('63 接线-模板重拉调用点 ≥2（挂载 + 存模板后）',
    (mep63.match(/this\.reloadPriceTemplates\(\);/g) || []).length >= 2, true);

  // ── E 形制与复用 ──
  // ★ 2026-09-11 三处模板统一半模态（方案 v3 S3）改写：原「63 形制-chips = Text + badgeBg +
  // 无 stateEffect」一钉随条卡 chips 退役**位移**为下两钉（位移非删除——chips 形态判据由
  // 「卡内零横向 Scroll + 选择模板键四件套 + 半模态三要素」覆盖；badgeBg 灰底判据随形态
  // 退役不再适用）；「存为模板」键钉与复用钉不动。
  check('63 形制-「选择模板」键 = 内容区双态四件套 + 空态置灰（原 chips 钉位移①）',
    [bar63.includes("Button('选择模板')"),
      (/Button\('选择模板'\)[\s\S]*?\.enabled\(this\.templates\.length > 0\)/.exec(bar63) ||
        [''])[0].includes('fallbackButtonFont(')],
    [true, true]);
  check('63 形制-卡内零横向 Scroll + 半模态三要素（bindSheet + sheetPanelOptions + MEDIUM；原 chips 钉位移②）',
    [!bar63.includes('ScrollDirection.Horizontal'), bar63.includes('.bindSheet('),
      bar63.includes('sheetPanelOptions('), bar63.includes('SheetSize.MEDIUM')],
    [true, true, true, true]);
  const saveBtn63 = (/Button\('存为模板'\)[\s\S]*?\.onClick/.exec(bar63) || [''])[0];
  check('63 形制-「存为模板」键走内容区双态四件套 + 到上限置灰',
    [saveBtn63.includes('fallbackButtonFont('), saveBtn63.includes('fallbackButtonBg('),
      saveBtn63.includes('fallbackButtonMaterial('), saveBtn63.includes('fallbackButtonStateEffect('),
      saveBtn63.includes('.enabled(this.templates.length < PRICE_TEMPLATE_MAX)')],
    [true, true, true, true, true]);
  check('63 复用-模板编辑页挂 ModelPriceCard 不自绘价格表单 + priceJson @Link 链（页 @State + $ 绑定）',
    [ptep63.includes('ModelPriceCard({'), !ptep63.includes('PriceField'),
      !/@State private (inputText|cachedText|outputText)/.test(ptep63),
      !ptep63.includes('vInputText'),
      /@State private priceJson: string = '';/.test(ptep63),
      ptep63.includes('priceJson: $priceJson,')],
    [true, true, true, true, true, true]);

  // ── E2 卡宽（2026-09-11 决明「模型能力页（添加模型）价格模版卡怎么又是全宽？对齐规范」）──
  // 判据与 ㊿ 组 H 段同源：以 `.backgroundColor(cardBg(` 为卡锚，沿属性链向上取链顶
  // `.width(...)`，遇非 `.` 行即停；写 '100%' = 全宽缺陷（卡体撑满屏宽、比基准左右各宽 16vp）。
  // 本页列容器只带顶/底 padding（用属性链向上遇非 `.` 行即停——防把容器 padding 误算进卡链），
  // 左右收窄责任在卡体 → 编辑模型页三卡与条卡一致写 CARD_PANEL_WIDTH。
  // ★ 只认字面量 '100%'：`calc(100% - 32vp)` 类相对宽（卡宽基准本体 / 会话气泡
  //   `calc(100% - Xvp)`）是正当写法，判据含 '100%' 会把它们误判成缺陷（09-10 扫描同坑）。
  const fullWidthCards63 = (src) => {
    const ls = src.split('\n');
    let n = 0;
    for (let i = 0; i < ls.length; i++) {
      if (!/\.backgroundColor\(cardBg\(/.test(ls[i])) continue;
      let j = i;
      let w = '';
      while (j >= 0 && /^\s*\./.test(ls[j])) {
        if (/^\.width\(/.test(ls[j].trim())) w = ls[j].trim();
        j--;
      }
      if (w.includes("'100%'")) n++;
    }
    return n;
  };
  check('63 卡宽-编辑模型页与条卡零全宽卡（卡体链一律 CARD_PANEL_WIDTH）',
    [fullWidthCards63(mep63), fullWidthCards63(bar63)], [0, 0]);
  check('63 卡宽-条卡卡体挂 CARD_PANEL_WIDTH 且 Theme 导入同名常量（防回写 100%）',
    [bar63.includes('.width(CARD_PANEL_WIDTH)'),
      bar63.includes('CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor')
    ], [true, true]);

  // ── F 摘要纯函数（CostStatsCalc 复制直跑，57 组同源模块缓存 import）──
  const { priceSummary } = await import('./.tmp/CostStatsCalc.ts');
  check('63 摘要-未配置三态（空串/坏 JSON/主价缺）',
    [priceSummary(''), priceSummary('not-json'), priceSummary('{"input":2}')],
    ['未配置', '未配置', '未配置']);
  check('63 摘要-主价+缓存挂键+谷时三段（cachedInput 缺省不出现「缓存」）',
    [priceSummary(serializePriceConfig({ input: 2, output: 8 })),
      priceSummary(serializePriceConfig({ input: 2, cachedInput: 0.5, output: 8 })),
      priceSummary(serializePriceConfig({ input: 2, cachedInput: 0.5, output: 8,
        valley: { input: 1, output: 4, segments: [{ start: '00:30', end: '08:30' }] } }))],
    ['输入 2 · 输出 8', '输入 2 · 输出 8 · 缓存 0.5', '输入 2 · 输出 8 · 缓存 0.5 · 含谷时价']);
  const rtJson63 = serializePriceConfig({ input: 2, cachedInput: 0.5, output: 8,
    valley: { input: 1, output: 4, segments: [{ start: '00:30', end: '08:30', days: [1, 2] }] } });
  const rtJson63b = serializePriceConfig(parsePriceConfig(rtJson63));
  check('63 摘要-round-trip 稳定（serialize→parse→serialize 同串后摘要同串）',
    rtJson63 === rtJson63b && priceSummary(rtJson63) === priceSummary(rtJson63b), true);

  // ── G 路由与上限 ──
  check('63 路由-两 ROUTE_* 常量 + PageMapBuilder 两分支',
    [rn63.includes("ROUTE_PRICE_TEMPLATE_PAGE: string = 'priceTemplatePage'"),
      rn63.includes("ROUTE_PRICE_TEMPLATE_EDIT_PAGE: string = 'priceTemplateEditPage'"),
      pmb63.includes('name === ROUTE_PRICE_TEMPLATE_PAGE'),
      pmb63.includes('name === ROUTE_PRICE_TEMPLATE_EDIT_PAGE')],
    [true, true, true, true]);
  const ss63 = rd63('common/SettingSearch.ets');
  check('63 路由-不进设置搜索注册表（防误登记，四级页非设置项）',
    ss63.includes('PRICE_TEMPLATE'), false);
  check('63 上限-三处引用同一常量 + insertTemplate 超限 throw 兜底在位',
    [bar63.includes('this.templates.length < PRICE_TEMPLATE_MAX'),
      ptp63.includes('this.templates.length >= PRICE_TEMPLATE_MAX'),
      /existing\.length >= PRICE_TEMPLATE_MAX[\s\S]*?throw new Error/.test(insFn63)],
    [true, true, true]);

  // ── H 既有回归（任务书红线：价格卡只许加通道，其余零改动）──
  check('63 回归-价格卡既有链零改动（priceJson @Link @Watch / 段键三成分 / cloneSeg 自增 rev）',
    [/@Link @Watch\('onJsonChange'\) priceJson: string;/.test(mpc63),
      /'vs' \+ seg\.segId \+ '-' \+ seg\.rev[\s\S]{0,30}'-' \+ index/.test(mpc63),
      /rev: this\.nextSegRev,/.test(mpc63), /this\.nextSegRev\+\+;/.test(mpc63)],
    [true, true, true, true]);
  const cost63 = rd63('common/store/CostStatsCalc.ets');
  check('63 回归-计算层既有六导出与 VALLEY_SEGMENT_MAX 逐字在位',
    [/export function parsePriceConfig\(json: string\): ModelPriceConfig \| null \{/.test(cost63),
      /export function serializePriceConfig\(cfg: ModelPriceConfig\): string \{/.test(cost63),
      /export function inValleyTime\(/.test(cost63),
      /export function inAnyValleySegment\(/.test(cost63),
      /export function costOfEvent\(/.test(cost63),
      /export function aggregateCosts\(/.test(cost63),
      /export const VALLEY_SEGMENT_MAX: number = 6;/.test(cost63)],
    [true, true, true, true, true, true, true]);

  // ── I 谷时「添加时段」键蓝底（2026-09-11 决明「添加时段键改蓝底」；判据剔注释 + 键块切法
  // 同 assert-ui-shape 67 组——从唯一 Button 标签起到紧随 .width('100%') 止，块内数
  // `, true))` = 3 且 `, false))` = 0，不用窗口正则）──
  const mpcCode63 = mpc63.split('\n').map((l) => l.split('//')[0]).join('\n');
  const segKey63 = (() => {
    const start = mpcCode63.indexOf("Button('添加时段')");
    if (start < 0) {
      return '';
    }
    const end = mpcCode63.indexOf(".width('100%')", start);
    return end < start ? '' : mpcCode63.slice(start, end);
  })();
  check('63 谷时-「添加时段」键 primary=true（三参全真 + 零 false；上限置灰另钉在位）',
    [segKey63.split(', true))').length - 1, segKey63.split(', false))').length - 1,
      /Button\('添加时段'\)[\s\S]*?\.enabled\(this\.valleySegs\.length < VALLEY_SEGMENT_MAX\)/
        .test(mpcCode63)],
    [3, 0, true]);
}

report();
