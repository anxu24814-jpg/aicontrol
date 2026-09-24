// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// 断言脚本共享帮助模块（2026-09-11 拆域笔立；宪法「单文件规模上限 · 脚本例外与拆分触发线」
// 条：sse-assert 剔头越 6000 行即按域切 assert-<域>.mjs + 共享帮助模块）。职责 = 断言
// 计数与打印（check / checkContract）+ 收尾汇总（report）+ 区域取段（segOf）；域脚本 =
// sse-assert.mjs（通用域）与 assert-<域>.mjs 各域件。
// ★ 写钉前先过宪法「断言资产守则」条（2026-09-22 第 2 批退役审计立）：落笔前两问——**合法改动
//   会让它红吗？缺陷会让它不红吗？**任一答「会」即不写或改判；禁写三类零判别力形态 = 值抄本 /
//   对开放式集合断言「恰 N 处」的计数快照 / 源码文案抄本；新增钉 ≤8 枚/笔（超须写理由，门禁
//   PIN_BUDGET 侧会提醒）。
// · 本模块无状态外泄：三栏计数私有，域脚本只能经 check / checkContract 累加、经 report 出总结。
// · 两级记账（2026-09-24 记账户笔）：check = 形态钉（源码形状判据），checkContract = 契约钉
//   （复制产品源直跑同一实现的行为判据）。两者判据同形、打印逐字一致；**过**分记两栏，**败**
//   统一进 failed（两栏之和），故「契约过 + 形态过 = 总过」恒成立、退出码看两栏合计。未迁移的
//   钉一律走 check，默认归形态栏。
// · 汇总行「结果：N 过 / M 败（契约 X / 形态 Y）」是 delivery-gate「断言总数」的解析锚（judge
//   取末次匹配）——**前缀「结果：N 过 / M 败」勿改**，前缀一改门禁计数即归零；括号段可追加
//   （该正则无尾锚）。X + Y = N（两栏之和）。
// · 判据正则**按锚点检索**、勿按行号读——它是 delivery-gate 的 judge() 内唯一一处
//   `out.matchAll(/结果：` 行（2026-09-24 时在 `delivery-gate.mjs:757`；该文件头注释一经增删，
//   行号即漂移而引用不会报错）。
// · 失败明细走 stderr（与 PASS 分流），门禁合并两流后按 FAIL 前缀抽取红灯原因行。
let passed = 0;
let failed = 0;          // 两栏之和：check 与 checkContract 各记一处，退出码与汇总行同取此值
let contractPassed = 0;  // 契约栏「过」；形态栏 = passed - contractPassed

// 两级记账单点：check 与 checkContract 共用本函数，只有级别标记不同——判据与打印格式全等。
function record(name, actual, expected, isContract) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    passed++;
    if (isContract) {
      contractPassed++;
    }
    console.log('PASS ' + name);
  } else {
    failed++;  // 两栏同入：契约钉的败也进 failed，退出码判定不会漏判
    console.error('FAIL ' + name);
    console.error('  期望: ' + JSON.stringify(expected));
    console.error('  实际: ' + JSON.stringify(actual));
  }
}

export function check(name, actual, expected) {
  record(name, actual, expected, false);
}

// 契约钉：与 check 同形同义（判据 = JSON.stringify 两端全等，打印逐字照旧），只多记一个级别
// 标记——**过**累计进「契约」栏（形态栏 = 总过 − 契约过），**败**与形态钉同走 failed（两栏
// 之和），故任一栏有败都反映到退出码。迁移只换函数名、不动参数，故族笔迁移前后 PASS 名全集
// 逐字不变（等价证明口径见宪法「脚本例外与拆分触发线」条）。
export function checkContract(name, actual, expected) {
  record(name, actual, expected, true);
}

export function report() {
  console.log('———');
  console.log('结果：' + passed + ' 过 / ' + failed + ' 败'
    + '（契约 ' + contractPassed + ' / 形态 ' + (passed - contractPassed) + '）');
  // process.exitCode 而非 process.exit()——Windows node v24 下 process.exit() 触发 libuv
  // 崩溃退出码恒 127（2026-08-30 实测连跑 5 次均 127，输出行可靠但退出码不可靠；任务书拍板④）
  process.exitCode = failed === 0 ? 0 : 1;  // failed 已是两栏之和，契约栏的败不会漏判
}

// 区域取段（2026-09-13 判据族松散面收口，N11 笔）：起止双锚都命中才给段，任一失效返回空串。
// 与「尾部切片」（src.slice(src.indexOf(锚))）的区别 = 上界有第二锚，判据分得清「段内」与
// 「段后别处」；★ 空串是**响亮失败**——正向判据挂 includes 必红，不让尾锚被改名/删注释时
// 静默退化成「锚点之后全算」的宽松区（判据族同坑49：宽容度 = 判别力，上界越宽越难分辨）。
// ★ 负向判据（期望 false）用空段会静默变绿，段非空须另挂形态钉（先例 assert-app-domain
// 「形态-锚点命中段非空」）。
export function segOf(src, startAnchor, endAnchor) {
  const i = src.indexOf(startAnchor);
  if (i < 0) {
    return '';
  }
  const j = src.indexOf(endAnchor, i + startAnchor.length);
  return j > i ? src.slice(i, j) : '';
}
