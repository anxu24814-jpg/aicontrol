// 服务商余额域存储层（2026-08-30 详情页改版新建）：providers 表 balance_* 九列的读写。
// 自 ProviderDb.ets 域级拆出（宪法 400 行红线——ProviderDb 322 行 + 余额读写函数必超线；
// 余额是独立功能域，表结构/迁移在 ChatDbMigrate.ets（DB 单一初始化源），本文件复用
// sharedRdbStore 同一 DB 句柄，红线同源：ResultSet 用完 close / 行级查询天然有界）。
// 语义：配置八列由详情页标题栏「保存」键统一落库（updateBalanceConfig）；查询结果文本
// balance_last_text 由「查询」键成功后单独落库（saveBalanceText）——重启保留上次值
//（任务书拍板：查询仅手动触发，不轮询）。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from './ChatDb';

// 余额查询配置（balance_* 配置列的域视图；key 为空 = 查询时回退聊天密钥，
// baseUrl 为空 = 回退服务 baseUrl；headers = 余额查询自定义头 JSON 串（serializeHeaderPairs
// 范式，空 k/v 行丢弃、空数组 = ''），查询时逐条追加且允许覆盖默认认证头——BalanceApi）
export interface BalanceConfig {
  enabled: boolean;
  baseUrl: string;
  path: string;
  resultPath: string;
  currency: string;
  currencyPath: string;
  key: string;
  headers: string;
}

// 余额态（配置 + 上次查询文本——详情页顶部卡徽章消费「启用且查得时显示」）
export interface BalanceState extends BalanceConfig {
  lastText: string;
}

// 读余额态（详情页编辑态回填 / 顶部卡徽章）；行不存在抛错（调用方 toast 呈现）
export async function queryBalanceState(providerId: string): Promise<BalanceState> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', providerId);
  const columns: string[] = ['balance_enabled', 'balance_base_url', 'balance_path',
    'balance_result_path', 'balance_currency', 'balance_currency_path', 'balance_key',
    'balance_last_text', 'balance_headers'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      const state: BalanceState = {
        enabled: result.getLong(result.getColumnIndex('balance_enabled')) === 1,
        baseUrl: result.getString(result.getColumnIndex('balance_base_url')),
        path: result.getString(result.getColumnIndex('balance_path')),
        resultPath: result.getString(result.getColumnIndex('balance_result_path')),
        currency: result.getString(result.getColumnIndex('balance_currency')),
        currencyPath: result.getString(result.getColumnIndex('balance_currency_path')),
        key: result.getString(result.getColumnIndex('balance_key')),
        lastText: result.getString(result.getColumnIndex('balance_last_text')),
        headers: result.getString(result.getColumnIndex('balance_headers'))
      };
      return state;
    }
    throw new Error('服务商不存在或已删除');
  } finally {
    result.close();
  }
}

// 写余额配置（详情页「保存」键；配置列整体回写，不动 last_text）
export async function updateBalanceConfig(providerId: string, cfg: BalanceConfig): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'balance_enabled': cfg.enabled ? 1 : 0,
    'balance_base_url': cfg.baseUrl,
    'balance_path': cfg.path,
    'balance_result_path': cfg.resultPath,
    'balance_currency': cfg.currency,
    'balance_currency_path': cfg.currencyPath,
    'balance_key': cfg.key,
    'balance_headers': cfg.headers
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', providerId);
  await sharedRdbStore().update(bucket, predicates);
}

// 查询成功后写余额文本（顶部卡徽章刷新 + 重启保留；与配置落库分通道——查询不改配置）
export async function saveBalanceText(providerId: string, text: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'balance_last_text': text };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', providerId);
  await sharedRdbStore().update(bucket, predicates);
}
