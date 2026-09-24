// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// assert-security-store.mjs — 凭据与安全域断言（2026-09-12 夜间接力笔 1 新建；任务书
// 任务书-夜间接力笔1-凭据与存储域补钉-20260911，已随交付归卷 docs/归档/任务书-归档-04）。
// 职责一行 = 守四件零覆盖安全/存储源文件的形态不变量：凭据明文只进 Asset、跨卸载持久
//（IS_PERSISTENT）、Asset↔DB 行写序成对、生物门禁官方契约。
//
// 域内容 = 69 组 48 钉，四段：A 凭据（KeyStore.ets，14）/ B 池（ProviderKeyDb.ets，14）/
// C 余额（ProviderBalanceDb.ets，8）/ D 门禁（BiometricGate.ets，12）。全部源码形态钉
//（无直跑段）；★ 钉与全部 17 发注入反验记录 = docs/自检报告/自检报告-凭据与存储域补钉-20260911.md。
// 来由 = 上游全面自检 §3-A 盲区图（205 文件中 111 个零断言提及，本四件在其列）+ 其 I3 注入
// 实证（删 savePoolKey 的 IS_PERSISTENT 整道门禁零红）——后人勿以「源码形态钉冗余」为由删钉。
//
// 运行：node scripts/assert-security-store.mjs（可单独跑；delivery-gate SUB_CHECKS 第十三件，
// 总数基线随本件 +48）。与既有件零重叠：四文件在既有 12 件断言脚本中零提及（2026-09-12 grep 实证）。
// 判据纪律（坑34/38/47 家族）：①一切判据跑剥注释源——先 CRLF 归一，再逐行先剥 \r 再剥 //
//（CRLF 下 $ 不跨 \r，剥序颠倒行注释剥不掉）；②切段 = 签名行起至首个独占行 } 止（禁窗口
// 正则，坑37）；③不绑行号，定位一律用符号名 / 常量名 / 字面量。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { check, report } from './assert-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

// 剥行注释（§2.2 逐字剥法：先剥 \r 再剥 //——四个目标文件无 /* */ 块注释、无字符串内 //，
// 已实测，见报告「剥注释自测」节）
const codeOnly = (t) => t.split('\n')
  .map((l) => l.replace(/\r$/, '').replace(/\/\/.*$/, '')).join('\n');
const rd = (rel) => codeOnly(readFileSync(
  path.join(here, '..', '..', 'entry', 'src', 'main', 'ets', rel), 'utf-8'));

// 切段：自函数签名行起，到首个独占行 } 止（四件源文件函数体内部无列 0 的 }，边界已实测）
const seg = (src, fnName) => {
  const m = new RegExp('^(export )?(async )?function ' + fnName + '\\(', 'm').exec(src);
  if (!m) {
    return '';
  }
  const end = src.indexOf('\n}', m.index);
  return end < 0 ? '' : src.slice(m.index, end);
};
// 顶层块（enum / interface）切片，终止符同 seg
const block = (src, declMarker) => {
  const start = src.indexOf(declMarker);
  if (start < 0) {
    return '';
  }
  const end = src.indexOf('\n}', start);
  return end < 0 ? '' : src.slice(start, end);
};

// ═══ 69 组：凭据与安全域（夜间接力笔 1；上游全面自检 §3-A 盲区图的凭据侧收口）═══
{
  const ks = rd('common/store/KeyStore.ets');
  const pdb = rd('common/store/ProviderKeyDb.ets');
  const bal = rd('common/store/ProviderBalanceDb.ets');
  const bio = rd('common/BiometricGate.ets');
  // module.json5 只读活行判据（两枚权限钉）：CRLF 归一但不剥注释——「被注释掉即红」靠
  // 行首锚点识别，剥注释会毁掉这个判据
  const mj5 = readFileSync(path.join(here, '..', '..', 'entry', 'src', 'main', 'module.json5'), 'utf-8')
    .replace(/\r\n/g, '\n');
  const livePerm = (perm) =>
    new RegExp('^[ \\t]*"name": "' + perm + '"[ \\t]*$', 'm').test(mj5);

  // ── A 凭据（KeyStore.ets，14 钉）──
  const aSave = seg(ks, 'savePoolKey');
  const aDav = seg(ks, 'saveDavPassword');
  const aSe = seg(ks, 'saveSearchEngineKey');
  const aPersist = (s) => {
    const iP = s.indexOf('asset.Tag.IS_PERSISTENT, true)');
    const iAdd = s.indexOf('await asset.add(attrs);');
    return iP >= 0 && iAdd >= 0 && iP < iAdd;
  };
  // ★ 反验 I1：删 savePoolKey 的 IS_PERSISTENT 行 → 恰本钉唯一红（上游 I3 注入实证的
  // 门禁盲区在此收口——「卸载后密钥丢失」事故加固点）
  check('69 凭据-savePoolKey 带 IS_PERSISTENT true ★', aPersist(aSave), true);
  check('69 凭据-saveDavPassword 带 IS_PERSISTENT true', aPersist(aDav), true);
  check('69 凭据-saveSearchEngineKey 带 IS_PERSISTENT true', aPersist(aSe), true);
  const aDelAdd = (s) => {
    const iR = s.indexOf('await remove');
    const iAdd = s.indexOf('await asset.add(attrs);');
    return iR >= 0 && iAdd >= 0 && iR < iAdd;
  };
  // 反验 I2：任一处 remove 行挪到 add 之后 → 本钉红
  check('69 凭据-三处 save 均先删后加', [aDelAdd(aSave), aDelAdd(aDav), aDelAdd(aSe)],
    [true, true, true]);
  // 反验 I3：改 'aic.p.' 字面量 → 本钉红
  check('69 凭据-别名三前缀常量逐字',
    [ks.includes("const PROVIDER_KEY_PREFIX: string = 'aic.p.';"),
      ks.includes("const DAV_PASSWORD_ALIAS: string = 'aic.dav.password';"),
      ks.includes("const SEARCH_ENGINE_KEY_PREFIX: string = 'aic.se.';")],
    [true, true, true]);
  const poolAlias = "PROVIDER_KEY_PREFIX + providerId + '/' + keyId";
  // 反验 I4：任一处漏 '/' → 本钉红（别名错位 = 存取错条目）
  check('69 凭据-池条目别名拼法三处一致',
    [seg(ks, 'savePoolKey').includes(poolAlias), seg(ks, 'loadPoolKey').includes(poolAlias),
      seg(ks, 'removePoolKey').includes(poolAlias)],
    [true, true, true]);
  const aRm = seg(ks, 'removeByAlias');
  check('69 凭据-removeByAlias 双分支（不存在静默 + 其余上抛）',
    [aRm.includes("if (!(typeof biz.code === 'number' && biz.code === ERR_ASSET_NOT_FOUND))"),
      aRm.includes("throw new Error('密钥资产删除失败：code '")],
    [true, true]);
  const aQry = seg(ks, 'querySecret');
  check('69 凭据-querySecret 不存在返回空串非抛错',
    [aQry.includes('biz.code === ERR_ASSET_NOT_FOUND'),
      aQry.indexOf("return '';") >= 0 &&
        aQry.indexOf("return '';") < aQry.indexOf("throw new Error('密钥资产读取失败："),
      aQry.includes("throw new Error('密钥资产读取失败：")],
    [true, true, true]);
  // 反验 I5：注入 hilog 打 apiKey → 恰本钉红（凭证层现役零日志，剥注释后判）
  check('69 凭据-明文零入日志（剥注释源负向钉）', ks.includes('hilog'), false);
  check('69 凭据-编解码走 util utf-8',
    [ks.includes("util.TextEncoder.create('utf-8')"), ks.includes("util.TextDecoder.create('utf-8')")],
    [true, true]);
  // 反验 I6：注释掉该权限行 → 本钉红（活行判据——被注释仍含同款文本，故锚定行首；
  // module.json5 交付态零改动，注入属 §4 反验授权面、改后逐字节还原）
  check('69 凭据-持久化权限已在 module.json5 声明（活行判据）',
    livePerm('ohos.permission.STORE_PERSISTENT_DATA'), true);
  check('69 凭据-遗留连接别名常量逐字',
    ks.includes("const ALIAS_TEXT: string = 'aicontrol.conn';"), true);
  const aConn = seg(ks, 'loadConnection');
  check('69 凭据-遗留连接三字段读取与残缺返回 null',
    [aConn.includes('asset.Tag.SECRET'), aConn.includes('asset.Tag.DATA_LABEL_NORMAL_1'),
      aConn.includes('asset.Tag.DATA_LABEL_NORMAL_2'),
      /if \(secret === undefined \|\| baseUrl === undefined \|\| model === undefined\) \{\s*return null;/
        .test(aConn)],
    [true, true, true, true]);
  const aRmKeys = seg(ks, 'removePoolKeys');
  check('69 凭据-removePoolKeys 逐条循环删',
    [aRmKeys.includes('for (const keyId of keyIds)'),
      aRmKeys.includes('await removePoolKey(providerId, keyId)')],
    [true, true]);

  // ── B 池（ProviderKeyDb.ets，14 钉）──
  const bIns = seg(pdb, 'insertProviderKey');
  const bImp = seg(pdb, 'importPoolKeyRow');
  const bSeed = seg(pdb, 'seedPoolKey');
  const bQry = seg(pdb, 'queryProviderKeys');
  const bMig = seg(pdb, 'migrateProviderKeyPools');
  const bOrder = (s) => {
    const iS = s.indexOf('await savePoolKey(');
    const iI = s.indexOf("sharedRdbStore().insert('provider_keys'");
    return iS >= 0 && iI >= 0 && iS < iI;
  };
  // ★ 反验 I7：seedPoolKey 内 savePoolKey 与 insert 调序 → 恰本钉红
  //（反序会留「行在明文无」假条目——头注释写序承诺的机器化）
  check('69 池-写序成对三处（Asset 先于 DB 行）★',
    [bOrder(bIns), bOrder(bImp), bOrder(bSeed)], [true, true, true]);
  const bRoll = (s) => {
    const iC = s.indexOf('} catch (e) {');
    return iC >= 0 && s.slice(iC).includes('removePoolKey(') && s.slice(iC).includes('throw');
  };
  // 反验 I8：删 seedPoolKey 的 catch 内回滚行 → 恰本钉红
  //（importPoolKeyRow 的 if (hasSecret) 包裹被 includes 容许——缺明文档无资产可回滚）
  check('69 池-行插失败回滚资产三处', [bRoll(bIns), bRoll(bImp), bRoll(bSeed)],
    [true, true, true]);
  const bDel = seg(pdb, 'deleteProviderKey');
  check('69 池-删序（Asset 先于行）',
    bDel.indexOf('removePoolKey(') >= 0 &&
      bDel.indexOf('removePoolKey(') < bDel.indexOf('.delete(predicates)'), true);
  const bRen = seg(pdb, 'renameProviderKey');
  // 反验 I9：删 0 行守卫 → 恰本钉红（行已删的「已重命名」假成功拦截）
  check('69 池-renameProviderKey 0 行 throw（防假成功）',
    [bRen.includes('affected === 0'), bRen.includes("throw new Error('密钥不存在或已删除')")],
    [true, true]);
  const bMax = seg(pdb, 'maxLabelNumber');
  check('69 池-label 自动取号守卫',
    [bMax.includes("startsWith('Key ')"), bMax.includes('!Number.isNaN(n)'), bMax.includes('n > max')],
    [true, true, true]);
  const bRot = seg(pdb, 'nextRotationStart');
  check('69 池-轮询指针语义（内存态不持久化）',
    [bRot.includes('enabledCount <= 0'), bRot.includes('return 0;'),
      bRot.includes('ptr % enabledCount'), bRot.includes('rotationPointers'),
      bRot.includes('sharedRdbStore'), pdb.includes('preferences')],
    [true, true, true, true, false, false]);
  check('69 池-查重守卫（读明文比对 + trim + 缺明文跳过）',
    [bIns.includes('plaintext.trim()'), bIns.includes('existing === target'),
      bIns.includes("existing !== '' &&")],
    [true, true, true]);
  // 反验：迁移段判据随 I8 同源（seedPoolKey 调序不影响本钉）；不阻断 = 段内零 throw
  const iSeedCall = bMig.indexOf('if (await seedPoolKey(id, legacy))');
  check('69 池-池迁移幂等与不阻断',
    [iSeedCall >= 0, bMig.indexOf('await removeProviderKey(id);') > iSeedCall,
      (bMig.match(/hilog\.error\(/g) || []).length >= 2, bMig.includes('throw')],
    [true, true, true, false]);
  // 反验 I10：删 queryProviderKeys 的 finally 块 → 恰本钉红
  check('69 池-ResultSet 与 close 成对',
    [bQry.includes('finally'), bQry.includes('result.close()'),
      bMig.includes('querySql'), bMig.includes('result.close()')],
    [true, true, true, true]);
  // 反验 I11：注入 hilog 打 plaintext → 恰本钉红（现役三处实参打 id / e.message，
  // 判据按 hilog 实参文本判、不按「有没有 hilog」）
  const bLogArgs = [...pdb.matchAll(/hilog\.\w+\(([\s\S]*?)\)\s*;/g)].map((m) => m[1]).join('\n');
  check('69 池-明文零入日志（hilog 实参抽验）',
    [(pdb.match(/hilog\./g) || []).length >= 2, bLogArgs.includes('plaintext'),
      bLogArgs.includes('apiKey'), bLogArgs.includes('secret')],
    [true, false, false, false]);
  check('69 池-表名与六列逐字',
    [pdb.includes("RdbPredicates('provider_keys')"),
      pdb.includes("['id', 'providerId', 'label', 'enabled', 'sortOrder', 'createdAt']"),
      pdb.includes("insert('provider_keys'")],
    [true, true, true]);
  check('69 池-importPoolKeyRow 的 null 语义',
    [bImp.includes("plaintext !== null && plaintext !== ''"),
      /if \(hasSecret\) \{\s*await savePoolKey\(/.test(bImp)],
    [true, true]);
  const bQei = seg(pdb, 'queryEnabledKeyIds');
  const bFep = seg(pdb, 'firstEnabledPoolKey');
  check('69 池-两查语义',
    [bQei.includes('row.enabled'), bFep.includes('keyIds.length === 0'),
      bFep.includes("return ''")],
    [true, true, true]);
  const bTog = seg(pdb, 'setProviderKeyEnabled');
  check('69 池-启停写 1/0 三态', bTog.includes('enabled ? 1 : 0'), true);

  // ── C 余额（ProviderBalanceDb.ets，8 钉）──
  const cUpd = seg(bal, 'updateBalanceConfig');
  const cSave = seg(bal, 'saveBalanceText');
  const cQry = seg(bal, 'queryBalanceState');
  // ★ 反验 I12：往配置 bucket 加 balance_last_text → 恰本钉唯一红
  //（查询文本与配置分通道——查询不改配置的拍板口径）
  check('69 余额-updateBalanceConfig 不写 last_text ★',
    [!cUpd.includes('balance_last_text'), cUpd.includes("'balance_enabled'"),
      cUpd.includes("'balance_base_url'"), cUpd.includes("'balance_path'"),
      cUpd.includes("'balance_result_path'"), cUpd.includes("'balance_currency'"),
      cUpd.includes("'balance_currency_path'"), cUpd.includes("'balance_key'"),
      cUpd.includes("'balance_headers'")],
    [true, true, true, true, true, true, true, true, true]);
  const cBucket = cSave.slice(cSave.indexOf('const bucket'), cSave.indexOf('};') + 2);
  // ★ 反验 I13：往文本 bucket 加第二列 → 恰本钉红（恰一项 = 分通道语义）
  check('69 余额-saveBalanceText 只写 last_text ★',
    [cBucket.includes("'balance_last_text': text"),
      (cBucket.match(/balance_/g) || []).length === 1],
    [true, true]);
  check('69 余额-queryBalanceState 行不存在 throw',
    cQry.includes("throw new Error('服务商不存在或已删除')"), true);
  // 判据以代码为准：读取面 = 八配置列（headers 在其内）+ balance_last_text 共九列
  //（源头注释列数口径差已于 2026-09-12 注释修正笔对齐——ProviderBalanceDb :1 九列、
  // :5 配置八列、ChatDbMigrate v3 行去「配置」误标；读列被改坏即本钉红）
  const cCols = cQry.slice(cQry.indexOf('const columns'), cQry.indexOf('];') + 2);
  check('69 余额-读九列齐',
    [cCols.includes("'balance_enabled'"), cCols.includes("'balance_base_url'"),
      cCols.includes("'balance_path'"), cCols.includes("'balance_result_path'"),
      cCols.includes("'balance_currency'"), cCols.includes("'balance_currency_path'"),
      cCols.includes("'balance_key'"), cCols.includes("'balance_last_text'"),
      cCols.includes("'balance_headers'"), (cCols.match(/balance_/g) || []).length === 9],
    [true, true, true, true, true, true, true, true, true, true]);
  check('69 余额-ResultSet finally close',
    [cQry.includes('finally'), cQry.includes('result.close()')], [true, true]);
  check('69 余额-零日志（剥注释源负向钉）', bal.includes('hilog'), false);
  const cCfg = block(bal, 'export interface BalanceConfig');
  const cState = block(bal, 'export interface BalanceState');
  check('69 余额-两接口字段齐',
    [['enabled', 'baseUrl', 'path', 'resultPath', 'currency', 'currencyPath', 'key', 'headers']
      .every((f) => new RegExp('^\\s*' + f + ': ', 'm').test(cCfg)),
      cState.includes('extends BalanceConfig'), cState.includes('lastText: string;')],
    [true, true, true]);
  check('69 余额-两写点同走 providers 行定位',
    [cUpd.includes("RdbPredicates('providers')"), cUpd.includes(".equalTo('id', providerId)"),
      cSave.includes("RdbPredicates('providers')"), cSave.includes(".equalTo('id', providerId)")],
    [true, true, true, true]);

  // ── D 门禁（BiometricGate.ets，12 钉）──
  const dGate = seg(bio, 'biometricGate');
  const dMsg = seg(bio, 'gateOutcomeMessage');
  // ★ 反验 I14：删 challenge 末两字节 → 恰本钉唯一红（真机 401 加固点，删了即退回事故形态）
  const dChal = /new Uint8Array\(\[([\s\S]*?)\]\)/.exec(dGate);
  const dChalN = dChal
    ? dChal[1].split(',').map((x) => x.trim()).filter((x) => x.length > 0).length
    : 0;
  check('69 门禁-challenge 恒 16 字节非空 ★', dChalN, 16);
  // ★ 反验 I15：authType 加第二类型 → 恰本钉红（恒单类型——09-05 决明拍板，无类型回退；
  // 头注释提及处已被剥注释剔除，计数恰 1 = 坑38 双向陷阱的正向侧自证）
  check('69 门禁-恒单类型且全文件恰一处发起 ★',
    [(bio.match(/getUserAuthInstance\(/g) || []).length, dGate.includes('authType: [preferred]')],
    [1, true]);
  // 反验 I16：删终态处 off → 恰本钉红（计数降为 1）
  check('69 门禁-on/off 成对',
    [(bio.match(/instance\.off\('result', callback\);/g) || []).length >= 2,
      (bio.match(/instance\.on\('result', callback\);/g) || []).length === 1],
    [true, true]);
  check('69 门禁-恒 resolve 零 reject（剥注释源负向钉）', bio.includes('reject'), false);
  check('69 门禁-ATL2 降 ATL1 预检保留',
    [dGate.includes('AuthTrustLevel.ATL2'),
      dGate.includes('probeLevel = userAuth.AuthTrustLevel.ATL1;')],
    [true, true]);
  check('69 门禁-权限 201 → PERMISSION_DENIED 四路',
    (bio.match(/PERMISSION_DENIED/g) || []).length >= 4, true);
  // ★ 反验 I17：两 if 调序 → 恰本钉红（权限缺失被误报「设备不支持」的判序防线）
  const dIPerm = dGate.indexOf('if (probe.permissionDenied)');
  const dIOk = dGate.indexOf('if (!probe.ok)');
  check('69 门禁-预检判序（权限缺失短路先于不支持）★',
    dIPerm >= 0 && dIOk >= 0 && dIPerm < dIOk, true);
  check('69 门禁-五态文案齐（取消返空串）',
    [dMsg.includes('case BiometricGateOutcome.CANCELED:'), dMsg.includes("return '';"),
      dMsg.includes('请先在系统设置中录入人脸或指纹'),
      dMsg.includes('当前设备不支持人脸或指纹识别'),
      dMsg.includes('生物识别权限未生效，请重新构建安装应用后重试'),
      dMsg.includes("return '认证失败，code '")],
    [true, true, true, true, true, true]);
  const dEnum = block(bio, 'export enum BiometricGateOutcome');
  check('69 门禁-七态枚举齐',
    ['PASSED', 'CANCELED', 'FAILED', 'NOT_ENROLLED', 'NOT_SUPPORTED', 'ERROR', 'PERMISSION_DENIED']
      .every((m) => new RegExp('^\\s*' + m + '[,\\s]', 'm').test(dEnum)), true);
  check('69 门禁-权限已在 module.json5 声明（读侧活行）',
    livePerm('ohos.permission.ACCESS_BIOMETRIC'), true);
  check('69 门禁-每次调用新建实例（官方一次性契约）',
    [/^let instance/m.test(bio), /^const instance/m.test(bio),
      dGate.includes('let instance: userAuth.UserAuthInstance;')],
    [false, false, true]);
  check('69 门禁-预检只探选定类型',
    [(bio.match(/probeType\(preferred/g) || []).length,
      (bio.match(/probeType\(/g) || []).length],
    [2, 3]);
}

report();
