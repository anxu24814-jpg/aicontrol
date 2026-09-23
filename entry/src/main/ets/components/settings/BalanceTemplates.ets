// 余额查询模板清单（2026-08-31 多预设化单源，原单 DeepSeek 常量 BALANCE_DEEPSEEK_TEMPLATE
// 退役）：消费方 = BalanceTemplateCard 套用卡（2026-09-11 方案 v3 起挂 BalanceConfigPage
// 二级页）；历史「新建态预填恒取首项 DeepSeek」口径已随余额配置迁页删除（新建态无余额
// 入口，页内载入自行回填库态）。
// ★ 端点查证出处（2026-08-31 联网，官方文档/官方端点多源实锤）：
// ① DeepSeek：GET https://api.deepseek.com/user/balance → balance_infos[0].total_balance
//   （官方既有实装，2026-08-30 详情页改版时查证）
// ② Kimi/月之暗面：GET https://api.moonshot.cn/v1/users/me/balance → data.available_balance
//   （官方文档 platform.kimi.com/docs/api/balance；可用余额 = 现金 + 代金券，单位 CNY）
// ③ 硅基流动：GET https://api.siliconflow.cn/v1/user/info → data.totalBalance（充值+赠送
//   总额，CNY；端点与字段经官方 API 多源工具实锤）
// ★ 未收录：GLM/智谱（无官方公开余额 API——社区抓包接口随时可变，宁缺毋滥）、OpenRouter
// （credits 端点需 Management Key，普通聊天 Key 查 401）。
// headers = 模板预置请求头（现三家官方端点均无需特殊头，恒空——字段留给中转站类预设）。
import { HeaderPair } from '../../common/providers/AiTypes';

export interface BalanceTemplate {
  name: string;
  baseUrl: string;
  path: string;
  resultPath: string;
  currency: string;
  currencyPath: string;
  headers: HeaderPair[];
}

export const BALANCE_TEMPLATES: BalanceTemplate[] = [
  {
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    path: '/user/balance',
    resultPath: 'balance_infos[0].total_balance',
    currency: 'CNY',
    currencyPath: 'balance_infos[0].currency',
    headers: []
  },
  {
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn',
    path: '/v1/users/me/balance',
    resultPath: 'data.available_balance',
    currency: 'CNY',
    currencyPath: '',
    headers: []
  },
  {
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn',
    path: '/v1/user/info',
    resultPath: 'data.totalBalance',
    currency: 'CNY',
    currencyPath: '',
    headers: []
  }
];
