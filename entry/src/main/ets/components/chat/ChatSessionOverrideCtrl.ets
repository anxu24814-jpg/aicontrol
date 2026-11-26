// 会话级覆盖域（2026-10-06 域级最小拆分自 ChatPage——宪法 1200 硬线：拆分时该页剔头 1282 行
// 越线，本笔对它有实质改动〔同日两刀第二刀〕，按「改动所属域先拆」取边界最清晰的一域外迁；
// 三个方法连同前置注释整段原样搬迁，语义零变化）。域定义一句话：**会话级覆盖「三值一对象」
// 的读写与联网镜像回流**——只换本次改的那一值（另两值原样保留）；有行会话 DB 覆盖列为真源
//（UPDATE 后以 DB 重读收口），无行会话（新建未发送）只存内存、首发随建行写入。
// · 搬迁面（方法体自 ChatPage 原样搬迁，语义零变化）：刷新链 refreshWebSearchFlag（写联网两键
//   镜像 CHAT_WEBSEARCH_ALLOWED_KEY / CHAT_WEBSEARCH_ON_KEY + AI 配置域归属键
//   CHAT_AI_ADMIN_OWNER_KEY；含 2026-10-05 自检轮 D1 的 departed 迟到写丢弃语义——该标记随域
//   迁入本件）+ 联网选择 pickWebSearch + 会话内选模型 pickModel。
// · 为何不能并入既有同域件（反碎片下限①②申报）：ChatCompressCtrl / ChatSheetCtrl 分属压缩链
//   与面板开关域，与本域无关；页面同域内无既有件可并入（覆盖三值只此一处读写）。形态沿用
//   同工程 ChatHostDelegates / ChatStreamFlowCtrl 的申报口径：本件是**实质编排非转接壳**——
//   落库与内存双写、镜像两键判定、迟到写丢弃全在本件体内，宿主只留九件依赖注入（页面态与
//   控制器能力闭包集，照 ChatSheetCtrl / ChatCompressCtrl 的 refs 形制）。
// · 真源与注入点：内存覆盖真源仍在页面（组件成员 memoryOverride，本件经 readOverride /
//   writeOverride 闭包读写——组件态与逻辑分离，照 AttachmentPickCtrl.getAttachments 同款）；
//   两消费方注入改指本件 = ChatSendRefs.sessionOverride（首发随建行写入）与
//   ChatPageLoadRefs.memoryOverride（DB 无行时兜底），同走 currentOverride 读单点。
// · 拆分沿革：2026-09-10 会话级覆盖层笔立语义（三值一对象 / 有行 DB 为真源 / 无行内存 + 首发
//   随建行写入）；2026-09-19 联网开关迁标题栏「更多」菜单（页面壳落 onPickWebSearch 形态不变，
//   本件只换落点）；2026-10-05 控制台门笔把会话归属控制台键并入本刷新链、同日自检轮 D1 加
//   departed 迟到写守卫；2026-10-06 本笔记整域外迁（本件成立，页面留真源 + 调用点接线）。
// · 依赖方向（零环红线，坑50）：本件禁 import ChatPage（宿主经构造实参注入）；ChatDb 三条读写
//   口与 AppStorage 三键常量就近 import 本件（原 ChatPage 消费面随迁）。

import { ConversationOverride, queryConversationOverride, updateConversationModelOverride,
  updateConversationWebSearchOverride } from '../../common/store/ChatDb';
import { PREF_DS_OFFICIAL_WEB_KEY, PREF_SEARCH_ENGINE_KEY } from '../../common/AppPreferences';
// DS 官方档分流（★ S1，修订版任务书 S1④）：哨兵 id 只在回调链流转、禁落持久层
import { DS_OFFICIAL_WEB_ID } from '../../common/providers/DsServerTools';
import { CHAT_AI_ADMIN_OWNER_KEY, CHAT_WEBSEARCH_ALLOWED_KEY,
  CHAT_WEBSEARCH_ON_KEY } from './ChatParamChipBar';

// 宿主回接接口（页面态与控制器能力闭包集——箭头闭包持页面 this 延迟求值，照 ChatSheetCtrl /
// ChatCompressCtrl 的 refs 形制）：内存覆盖真源在页面，落库/镜像/呈报能力由页面转发
export interface ChatSessionOverrideHost {
  conversationId: () => string;
  // 无行会话内存覆盖真源读 / 写（页面组件成员；本件不持值，只经闭包读改写）
  readOverride: () => ConversationOverride | null;
  writeOverride: (ov: ConversationOverride | null) => void;
  // 提示词态解析链（镜像两键的取值闸）与会话归属能力两读（转发发送域解析缓存）
  loadPromptState: (cid: string) => Promise<void>;
  aiAdminToolsEnabled: () => boolean;
  webSearchAllowed: () => boolean;
  // 选模型后重解析连接（有行：取 DB 值；无行：走内存值）与面板关闭
  reloadConn: () => void;
  closeSheet: () => void;
  // 失败呈报（P0-1 不静默）
  toast: (message: string) => void;
}

export class ChatSessionOverrideCtrl {
  private host: ChatSessionOverrideHost;
  // 页面存活标记（2026-10-05 自检轮 D1 修复自 ChatPage 随域迁入；命名与 ChatInputBar.departed
  // 同款）：置位后 refreshWebSearchFlag 的迟到异步链不再写广播键——旧实例销毁后其链完成回调
  // 若照写，会把旧会话归属结果盖到新会话键上（跨实例污染；与坑15「出页清空滞后」同族「迟到
  // 写覆盖新真相」，规范正解 = 进入先覆写 + 迟到写丢弃）。新实例天然 false，无需复位
  private departed: boolean = false;

  constructor(host: ChatSessionOverrideHost) {
    this.host = host;
  }

  // 无行会话内存覆盖读（两注入源单点：ChatSendRefs.sessionOverride 首发随建行写入 +
  // ChatPageLoadRefs.memoryOverride 的 DB 无行兜底——同读页面真源，语义见接口注释）
  currentOverride(): ConversationOverride | null {
    return this.host.readOverride();
  }

  // 页面销毁标记置位（页面 aboutToDisappear 调用；此后迟到链一律不写广播键）
  markDeparted(): void {
    this.departed = true;
  }

  // 联网开关镜像刷新（2026-09-03 领导指令；★ 2026-09-10 会话级覆盖层笔第二阶段定稿；
  // ★ 2026-09-16 会话级技能启用笔曾扩为两族键同链，「单条消息指定技能」笔随覆盖退役回
  // 单族——函数名不动，改名撞 4 处既有断言钉锚〔assert-feature-domain 51/53 组〕）：
  // 联网两键——闸键 CHAT_WEBSEARCH_ALLOWED_KEY = 助手启用清单是否含 search_web（能力
  // 上限，chip 据此判可点/置灰）；值键 CHAT_WEBSEARCH_ON_KEY = 生效值 = 上限 **且** 本会话
  // 未关（webSearchOverride !== '0'）。
  // 调用四时点不变（打开会话 / 面板换助手 / 页面重新显示〔onShown〕/ 写覆盖后回灌），
  // load 异步，完成时机只有本链知道——load 返回 Promise。
  // ★ 2026-10-25 控制台合并笔：本链承载 AI 配置域归属键（CHAT_AI_ADMIN_OWNER_KEY——
  // 安全输入 chip 与暂存条显隐，ChatInputBar 自订阅；原控制台归属键同位改名改判据）——
  // 入口先归 false、load 链尾落真值，凡 load 重跑处键必重写（语义见键注释）。
  // 覆盖读法同 reloadConn：行在 = DB 为准，无行（新建未发送/隐私会话）= 页面内存覆盖。
  // ★ 失败口径：覆盖读失败或 load 失败 → **不写键**（镜像保持上一次解析结果）——与既有
  // 「读失败不静默翻转为默认」同一姿势，勿改成「catch 里写回默认值」（那会把一次读失败
  // 放大成"联网被关"的可见错误行为）
  refreshWebSearchFlag(): void {
    const cid: string = this.host.conversationId();
    // AI 配置域归属键先归 false（与联网两键同链写）：进页/换会话瞬间清掉上一会话残留
    // ——防「启用域会话 → 未启用会话」切换的旧值真显示窗口（未启用会话里 chip 闪现 =
    // 能力谎言，宁可在启用会话里 chip 晚一拍出现）；真值在下方 load 链尾落，失败路保持
    // false（fail-closed 隐藏是安全向——与联网键「失败不写」口径有意不同）
    AppStorage.setOrCreate<boolean>(CHAT_AI_ADMIN_OWNER_KEY, false);
    queryConversationOverride(cid)
      .then((row: ConversationOverride | null): Promise<void> => {
        const ov: ConversationOverride | null = row !== null ? row : this.host.readOverride();
        const sessionOff: boolean = ov !== null && ov.webSearchOverride === '0';
        return this.host.loadPromptState(cid).then((): void => {
          if (this.departed) {
            // 2026-10-05 自检轮 D1 修复：实例销毁后不写广播键——旧实例的迟到链（页面已
            // pop/替换）会把旧会话归属结果盖到新会话键上（普通会话 chip 误显示 = 能力
            // 谎言；与坑15 同族「迟到写覆盖新真相」，此处丢弃迟到写）
            return;
          }
          AppStorage.setOrCreate<boolean>(CHAT_AI_ADMIN_OWNER_KEY,
            this.host.aiAdminToolsEnabled());
          const allowed: boolean = this.host.webSearchAllowed();
          AppStorage.setOrCreate<boolean>(CHAT_WEBSEARCH_ALLOWED_KEY, allowed);
          AppStorage.setOrCreate<boolean>(CHAT_WEBSEARCH_ON_KEY, allowed && !sessionOff);
        });
      })
      .catch((): void => {
        // 覆盖读失败 / 提示词态 load 失败：两键保持上一次解析结果（见上条口径注释）
      });
  }

  // 联网开关选择落覆盖（★ 2026-09-10 会话级覆盖层笔第二阶段定稿语义 = 决明拍板第 2 种）。
  // 写的是**本会话**：点「关闭」= 写 webSearchOverride '0'（只影响这条会话），点「开启」=
  // 清覆盖 ''（跟随助手的启用清单）。★ 上一笔「chip 写回 assistants.tools」整条撤回——
  // 助手配置不再被会话内操作改动，助手未启用联网时 chip 根本不可点（硬闸在 chip 侧）。
  // 落库分两态同 pickModel：会话已有行 = UPDATE；无行（新建未发送/隐私会话）= 只存内存，
  // 首发落行时随 insertMessage 写入。失败 toast 不静默（P0-1），随后照常重解析（有行会话
  // 以 DB 为真源、无行会话按内存值生效）
  pickWebSearch(on: boolean): void {
    const prev: ConversationOverride | null = this.host.readOverride();
    const value: string = on ? '' : '0';
    // 内存覆盖与 DB 双写同值（无行会话的内存是唯一载体，有行会话保证两条读法一致）；
    // ★ 模型两列**原样保留**——覆盖是「三值一对象」，重建时只换本次改的那一值，勿写成
    // 三值全传（那会在无行会话里顺手清掉模型覆盖）
    this.host.writeOverride({
      modelProviderId: prev !== null ? prev.modelProviderId : '',
      modelId: prev !== null ? prev.modelId : '',
      webSearchOverride: value
    } as ConversationOverride);
    updateConversationWebSearchOverride(this.host.conversationId(), value)
      .then((): void => {
        this.refreshWebSearchFlag(); // 有行：以 DB 重读收口；无行：0 行不报错，按内存值生效
      })
      .catch((e: Object): void => {
        this.host.toast('联网开关保存失败：' + (e as Error).message);
        this.refreshWebSearchFlag();
      });
  }

  // 联网引擎选择（★ 2026-10-17 二级菜单引擎化笔）：对话页「联网」二级菜单点已启用引擎 =
  // 写全局当前引擎偏好 + 本会话联网开。全局键 AppStorage 直写（PREF_SEARCH_ENGINE_KEY，
  // persistProp 已注册——写即落盘，运行时 dispatchSearch 经 getSearchEngineId 现读；键语义
  // 见 AppPreferences 注释）；本会话联网开复用 pickWebSearch(true)（写覆盖 '' + 落库 +
  // 镜像刷新），失败呈报与重解析全在其内，本方法只多担全局键一步。全局键自带引擎侧的
  // UI 写点 = 本方法（设置页「设为当前引擎」卡与「当前使用」徽章随同笔退役）。
  // ★ DS 官方档分流（DS 全家桶接入批 S1，修订版任务书 S1④）：入参为菜单哨兵 id
  // DS_OFFICIAL_WEB_ID（只在回调链流转——禁写进任何持久层/引擎键）→ 只写官方档偏好 true
  //（全局引擎键**原样保留自带引擎值**——§4.1「改选自带回自带链，全局引擎键仍存自带引擎
  // 值」，改回自带时原选择不丢）；否则 = 自带引擎选择照旧写引擎键 + 官方档偏好 false
  //（改选自带 = 回自带链）。官方档键语义与判据单源 = DsServerTools.dsOfficialWebActive /
  // AppPreferences 注释；两支都经 pickWebSearch(true) 开本会话联网（失败呈报与镜像刷新全
  // 在其内）。
  pickWebEngine(engineId: string): void {
    if (engineId === DS_OFFICIAL_WEB_ID) {
      AppStorage.setOrCreate<boolean>(PREF_DS_OFFICIAL_WEB_KEY, true);
      this.pickWebSearch(true);
      return;
    }
    AppStorage.setOrCreate<string>(PREF_SEARCH_ENGINE_KEY, engineId);
    AppStorage.setOrCreate<boolean>(PREF_DS_OFFICIAL_WEB_KEY, false);
    this.pickWebSearch(true);
  }

  // 会话内选模型（★ 2026-09-10 会话级覆盖层笔改语义）：面板选择 = **本会话覆盖**，不是
  // 「全局当前模型」——只影响这条会话，新会话/其他会话照旧走「助手绑定 → 全局默认 →
  // 首个启用」。落库分两态：会话已有行 = 直接 UPDATE 覆盖列；**无行会话（新建未发送/
  // 隐私会话）= 只存内存**（memoryOverride，首发落行时随 insertMessage 写入——先例
  // conversations.promptId 的面板覆盖），退出即丢（决明拍板语义：空会话里改的东西不保存）。
  // 失败 toast 不静默（P0-1）；内存值不回滚——无行会话本次停留内仍生效（内存是唯一载体），
  // **有行会话则落回解析链 ②③④ 级**（行存在时 DB 为准，写失败 ⇒ 读出旧值），详见 catch 注释
  pickModel(providerId: string, modelId: string): void {
    // 内存覆盖（无行会话的唯一载体；有行会话与 DB 同值，双写保证 reloadConn 两种读法一致）；
    // ★ 联网覆盖列**原样保留**——覆盖是「三值一对象」，重建时只换本次改的模型两值，勿把
    // webSearchOverride 一并写成 ''（那会在无行会话里顺手清掉本会话的联网关闭态）
    const prev: ConversationOverride | null = this.host.readOverride();
    this.host.writeOverride({
      modelProviderId: providerId, modelId: modelId,
      webSearchOverride: prev !== null ? prev.webSearchOverride : ''
    } as ConversationOverride);
    updateConversationModelOverride(this.host.conversationId(), providerId, modelId)
      .then((): void => {
        this.host.reloadConn(); // 有行：落库后重解析取 DB 值；无行：0 行不报错，走内存值
      })
      .catch((e: Object): void => {
        this.host.toast('模型选择保存失败：' + (e as Error).message);
        // ★ 2026-09-10 会话级覆盖层笔自检更正：原注释写「本次停留内仍按内存覆盖生效」——
        // **对无行会话成立，对有行会话不成立**（reloadConn 里行存在时以 DB 为准，行写失败
        // ⇒ 读出旧值，内存覆盖不参与）。实际行为 = 落回解析链的 ②③④ 级；此处照常重解析
        // 只为把 conn 收敛到与 DB 一致（写失败不静默已由上面 toast 承担）
        this.host.reloadConn();
      });
    this.host.closeSheet();
  }

}
