// 服务商详情 · 模型页签面板（2026-08-30 服务商管理域新建；同日详情页改版清单区重写）：
// 工具卡（获取模型 = GET {baseUrl}/models 拉清单弹 **半模态勾选同步**〔2026-08-31 领导
// 指令，不再直接入库——清单 = API 实际结果、初始勾选 = 库已有、右上勾保存 = 勾选入库/
// 取消移除、API 外手动行零触碰；域件 ModelFetchSheet.ets〕/
// 添加 = 手动新建进编辑模型页 / 搜索框 = modelId 子串过滤）+ 模型清单（对话/向量两分组，
// 一卡一模型：modelId 主文本 + 能力标签徽章 + 右侧启停 Toggle + 四点菜单键；★ 2026-09-17
// 交互改形（决明指令）——卡片点击进编辑退役，编辑与删除都收进四点键菜单〔ModelCardMenu
// 域件〕，Toggle 只管启停自消费点击——ProviderCardItem 同款先例）。★名称显示链收敛（详情页
// 改版拍板）：卡片只显示 modelId，不再兜底自定义名（model.name 的 UI 消费仅剩
// ModelPickerSheet 与 ModelEditPage 表单）。
// ★ 获取半模态的关闭语义（2026-09-23 半模态关闭确认笔）：勾选态有未保存改动时，关闭三路
//（标题栏 xmark / 下拉·侧滑·三键 back / 点蒙层）都先弹「放弃这次勾选？」，未通过则面板保持
// 打开；无改动直接关。判据 = 面板上行的脏态镜像 fetchDirty，收口 = requestCloseFetch（单源）。
// 停用语义：停用模型不进聊天模型选择面板、不参与当前连接解析（解析侧兜底首个启用
// 模型接替）；本页签全量展示（含停用行）。
// ★ 保存语义（2026-08-31 领导拍板「所有配置改后必须点右上角勾才能被保存」）：启停
//（单行 Toggle 与「更多」批量）= 草稿态——乐观更新本地清单 + 上行宿主 ProviderToggleDraft
// 记草稿（引用宿主直发本面板），详情页「保存」链尾统一落库，直接退出 = 草稿随页面丢弃
// 不保存；面板重建（页签切换/纪元键）reload 时从草稿引用回灌。获取同步/添加/删除 = 资源
// 动作即时落库。模型卡组件已域拆 ModelCardItem.ets（同日，原样搬迁）。
// 刷新通道：编辑模型页 pop 后经 AppStorage 一次性计数器广播重拉（会话列表同款姿势，
// 坑3 口径——Tab/页面栈层级无关）；新建服务商未保存时 providerId 为空 → 整面板换提示卡
//（模型属已保存服务商的资源）。获取模型用父页当前表单值（Base URL/密钥改后免保存即可
// 试拉——拉回的模型行仍落在该服务商名下，保存动作只管基础字段）。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fetchModelIds } from '../../common/providers/ModelListApi';
import { firstEnabledPoolKey } from '../../common/store/ProviderKeyDb';
import {
  deleteModel, ModelRow, queryModels
} from '../../common/store/ProviderDb';
import { CHECK_MODEL_USAGE_FAIL_TEXT, checkModelUsage, ModelUsageInfo,
  usageWarningText } from '../../common/store/ModelUsageCheck';
import { PROVIDER_EDIT_ID_KEY } from './ProviderKeysPanel';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor,
  menuDividerColor } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, resolvedUiMaterial, overlayMaterial } from '../../common/ImmersiveLevel';
import { ModelCardItem } from './ModelCardItem';
import { MODEL_CARD_MENU_ID_PREFIX, ModelCardMenuCallbacks, ModelCardMenuHost } from './ModelCardMenu';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { FetchSheetRow, ModelFetchSheet } from './ModelFetchSheet';
import { confirmSheetClose, sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

// （2026-08-30 刷新链路收敛：原 MODEL_LIST_RELOAD_KEY AppStorage 广播键已删——面板刷新
// 自持：挂载/切页签重建 aboutToAppear + 面板内启停/获取自动 reload + 坑16 父页
// modelsEpoch 纪元键整面板重建。2026-08-31：启停不再触发 reload——草稿态纯内存乐观
// 更新，库只在保存链 flush 时写）
// （2026-08-31：模型卡组件域拆 ModelCardItem.ets——统一保存语义改动腾行数红线，原样搬迁）

// 打点 TAG（模型使用检测失败留痕——运行日志页按 TAG 过滤）
const DOMAIN: number = 0xD5A5;
const TAG: string = 'ProviderModelsPanel';

@Component
export struct ProviderModelsPanel {
  // 所属服务商 id（'' = 新建未保存——整面板换提示卡；★ @StorageProp 订阅——@Prop 传参链
  // SDK 26 不随父状态更新（面板创建早于回填即冻结——「重进后不显示」同族根因，见
  // ProviderKeysPanel PROVIDER_EDIT_ID_KEY 注释），改订阅式自感知详情页写键）
  @StorageProp(PROVIDER_EDIT_ID_KEY) @Watch('onPidChanged') providerId: string = '';
  // 获取模型用的当前表单值（父页 @State 同步；@Prop 随父渲染更新）：Base URL 与协议——
  // key 不再走表单（单 Key 字段退役），取池首个启用（2026-08-30 多 Key 池）
  @Prop baseUrl: string = '';
  @Prop protocol: string = '';
  // 编辑模型页入口（父页执行 push；参数 = 目标行，null = 新建）
  onOpenModel: (row: ModelRow | null) => void = () => {
  };
  // 获取模型成功上行（坑16·2026-08-30 复活：父页自增 headEpoch → 顶卡计数徽章键变
  // 重建重拉——卡内 @Builder 值参快照不自刷；组件方法回调不经 content 传播链）
  onModelsChanged: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 启停草稿链（2026-08-31 统一保存语义，宿主 ProviderDetailPage 直发本面板）：
  // modelDraftRef = ProviderToggleDraft model Map 引用（实例恒定，reload 回灌读）；
  // onToggleDraft = 乐观上行回调（宿主记草稿，保存链尾统一落库）
  modelDraftRef: Map<string, boolean> = new Map();
  onToggleDraft: (rowId: string, on: boolean) => void = () => {
  };
  // （2026-08-30 自持有重构：modelTick 外部驱动已删——面板数据自持 @State 自刷
  //（挂载/切页签重建 aboutToAppear + 面板内启停/获取自动 reload），不依赖父状态传播）
  @State private models: ModelRow[] = [];
  @State private keyword: string = '';
  @State private fetching: boolean = false;
  // 获取半模态（2026-08-31）：rows = 探针结果行（sheetEpoch 纪元键重建 Sheet 播种勾选
  // 态）；sheetShow 显隐（bindSheet 宿主；关闭 = 勾选态随实例销毁丢弃，无堆积）
  @State private sheetRows: FetchSheetRow[] = [];
  @State private sheetShow: boolean = false;
  @State private sheetEpoch: number = 0;
  // 获取半模态脏态镜像（★ 2026-09-23 关闭确认笔；面板经 onDirtyChange 同步上行）：勾选态与
  // 库态不一致 = 有未保存勾选，关闭请求据此决定「先确认 / 直接关」。普通成员——只参与判断，
  // 不驱动 UI，无需 @State
  private fetchDirty: boolean = false;
  @State private hintText: string = '';
  // 模型卡菜单节点宿主（init/open/dispose 成对，见 ModelCardMenu.ets）
  private cardMenu: ModelCardMenuHost = new ModelCardMenuHost();
  // 删除确认弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 沉浸光感档位（「更多」菜单材质随档——ChatParamChipBar 菜单同款；
  // 行内 TEXTUAL 图标键无材质，光感承载 = 菜单材质，键本体调参点见按钮行注释）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    this.reload();
    // 菜单节点首建（getUIContext 需组件就绪故不挂构造期；菜单空行载体仅供初次 init，
    // 每次弹出前 rebuild 换真行——ProviderPage 同款）
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyRow()));
  }

  aboutToDisappear(): void {
    // 成对释放（ComponentContent 不 dispose 泄漏——AppMenuHost 头注释）
    this.cardMenu.dispose();
  }

  // 菜单初始载体（空行：仅满足 init 一次性建节点的类型需求，弹出前必被 rebuild 换掉）
  private emptyRow(): ModelRow {
    return {
      id: '', providerId: '', modelId: '', name: '', kind: 'chat', caps: '', createdAt: 0,
      enabled: true, capsUserModified: false, favorite: false, priceConfig: '',
      contextWindow: 0
    };
  }

  // 菜单回调载体（每次弹出前重建，携带当前行）
  private menuCallbacks(row: ModelRow): ModelCardMenuCallbacks {
    return {
      item: row,
      onEdit: (target: ModelRow): void => {
        this.onOpenModel(target);
      },
      onDelete: (target: ModelRow): void => {
        this.openDeleteConfirm(target);
      }
    };
  }

  private openCardMenu(row: ModelRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row), this.immersiveLevel);
  }

  // 删除（菜单项）：先做使用检测（功能模型槽 / 助手绑定 / 会话覆盖）→ 拼提示句 → 确认
  // 弹窗。检测失败 = 降级成「未能检测」句（P0-1 不静默；删除照常可走，检测只是提示面）
  private openDeleteConfirm(row: ModelRow): void {
    checkModelUsage(row.providerId, row.modelId)
      .then((info: ModelUsageInfo): void => {
        this.showDeleteDialog(row, usageWarningText(info));
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, '模型使用检测失败（删除照常，提示降级）：%{public}s',
          (e as Error).message);
        this.showDeleteDialog(row, CHECK_MODEL_USAGE_FAIL_TEXT);
      });
  }

  // 确认弹窗（官方实底，与删除会话/删除服务商同款材质）；使用情况句为空 = 无引用，不拼。
  // ★ 删除目标随弹窗载荷走（闭包捕获 row，不经成员中转）：检测是异步的，弹窗开启时刻与
  // 用户点「删除」时刻相隔若干 await——目标若存成员位，两条删除流程交错时后写覆盖前写，
  // 用户会对着 A 的弹窗删掉 B（P-19 同族口径：值在消息边界取，随即随载荷下传）
  private showDeleteDialog(row: ModelRow, usageText: string): void {
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除模型',
        message: '将删除模型「' + row.modelId + '」，不可恢复。' + usageText,
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deletePending(row);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 删除执行（row = 弹窗载荷原样下传，见 showDeleteDialog）：库内事务级联（模型行 + 助手
  // 绑定 + 会话覆盖，见 deleteModel）→ 清单重拉 + 顶卡纪元上行（计数徽章整卡重建）；
  // 失败 toast 可重试（P0-1）
  private async deletePending(row: ModelRow): Promise<void> {
    try {
      await deleteModel(row.id);
      this.getUIContext().getPromptAction().showToast({ message: '已删除模型' });
      this.reload();
      this.onModelsChanged();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 编辑对象回填（AppStorage 写值触发——自感知重拉，见键常量注释）
  onPidChanged(): void {
    this.reload();
  }

  private reload(): void {
    if (this.providerId === '') {
      return;
    }
    queryModels(this.providerId, '')
      .then((rows: ModelRow[]): void => {
        // 草稿回灌（2026-08-31 统一保存语义）：面板随页签切换/纪元键销毁重建，重建后从
        // 宿主草稿引用恢复未保存启停态——「库态+草稿」始终等于用户所见（保存前不弹回）
        const draft: Map<string, boolean> = this.modelDraftRef;
        this.models = rows.map((row: ModelRow): ModelRow => {
          const drafted: boolean | undefined = draft.get(row.id);
          if (drafted === undefined) {
            return row;
          }
          const next: ModelRow = {
            id: row.id, providerId: row.providerId, modelId: row.modelId, name: row.name,
            kind: row.kind, caps: row.caps, createdAt: row.createdAt, enabled: drafted,
            capsUserModified: row.capsUserModified, favorite: row.favorite,
            priceConfig: row.priceConfig, contextWindow: row.contextWindow
          };
          return next;
        });
        this.hintText = '';
      })
      .catch((e: Object): void => {
        this.hintText = '模型清单读取失败：' + (e as Error).message;
      });
  }

  // 模型启停（2026-08-31 统一保存语义改草稿态）：乐观更新本地清单（数组整组替换，ForEach
  // 键含 enabled → 键变重建卡，Toggle 与数据态一致）+ 上行宿主记草稿——点详情页标题栏
  // 「保存」统一落库，直接退出 = 草稿随页面丢弃不保存；纯内存操作无失败路径（原即时落库
  // 的失败 toast+回滚链随之删除）
  private toggleModel(row: ModelRow, isOn: boolean): void {
    this.models = this.models.map((item: ModelRow): ModelRow => {
      if (item.id !== row.id) {
        return item;
      }
      const next: ModelRow = {
        id: item.id, providerId: item.providerId, modelId: item.modelId, name: item.name,
        kind: item.kind, caps: item.caps, createdAt: item.createdAt, enabled: isOn,
        capsUserModified: item.capsUserModified, favorite: item.favorite,
        priceConfig: item.priceConfig, contextWindow: item.contextWindow
      };
      return next;
    });
    this.onToggleDraft(row.id, isOn);
  }

  // 批量启停（2026-08-31 统一保存语义改草稿态，「更多」菜单）：作用域 = 本服务商已添加
  // 模型全行（表内行）——全行乐观更新 + 逐行上行宿主草稿，点「保存」统一落库；toast 注明
  // 「保存后生效」（不即时生效须让用户可见，P0-1）；纯内存无失败路径
  private batchEnabled(on: boolean): void {
    if (this.providerId === '') {
      return;
    }
    const ids: string[] = this.models.map((row: ModelRow): string => row.id);
    this.models = this.models.map((row: ModelRow): ModelRow => {
      if (row.enabled === on) {
        return row;
      }
      const next: ModelRow = {
        id: row.id, providerId: row.providerId, modelId: row.modelId, name: row.name,
        kind: row.kind, caps: row.caps, createdAt: row.createdAt, enabled: on,
        capsUserModified: row.capsUserModified, favorite: row.favorite,
        priceConfig: row.priceConfig, contextWindow: row.contextWindow
      };
      return next;
    });
    for (const id of ids) {
      this.onToggleDraft(id, on);
    }
    this.getUIContext().getPromptAction().showToast({
      message: (on ? '已全部开启 ' : '已全部关闭 ') + ids.length + ' 个模型（保存后生效）'
    });
  }

  // 「更多」菜单（全部开启/全部关闭；Menu 内固定两项——无需 ForEach；分割线官方
  // EMBEDDED_IN_MENU 深浅分治，ChatTitleMenu 同款）
  @Builder
  BatchMenu() {
    Menu() {
      MenuItem({ content: '全部开启' })
        .onClick(() => {
          this.batchEnabled(true);
        })
      MenuItem({ content: '全部关闭' })
        .onClick(() => {
          this.batchEnabled(false);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 关键词过滤（modelId 子串、大小写不敏感；空关键词 = 全量。★仅匹配 modelId——名称
  // 显示链已收敛，name 不再参与过滤）
  private filtered(kind: string): ModelRow[] {
    const key: string = this.keyword.trim().toLowerCase();
    return this.models.filter((row: ModelRow): boolean => row.kind === kind &&
      (key === '' || row.modelId.toLowerCase().includes(key)));
  }

  // 获取模型（2026-08-31 改半模态勾选同步——不再直接入库）：表单守卫 → 池首启用 key →
  // 按协议拉清单 → 构造半模态行（modelId + 库行 rowId/inDb 映射）→ 纪元键重建 Sheet 播种
  // 勾选态并打开；失败 hintText（同步落库在 Sheet 保存勾，onSaved 上行回面板）
  private fetchModels(): void {
    if (this.fetching || this.providerId === '') {
      return;
    }
    if (this.baseUrl.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先在「配置」页签填写 Base URL' });
      return;
    }
    this.fetching = true;
    this.hintText = '';
    firstEnabledPoolKey(this.providerId)
      .then((key: string): Promise<string[]> => {
        if (key === '') {
          throw new Error('请先在「配置」页签的密钥池添加 API Key');
        }
        return fetchModelIds(this.baseUrl.trim(), key, this.protocol);
      })
      .then((ids: string[]): void => {
        if (ids.length === 0) {
          this.getUIContext().getPromptAction().showToast({ message: '服务商未返回模型' });
          return;
        }
        const rowByModelId: Map<string, ModelRow> = new Map();
        for (const row of this.models) {
          rowByModelId.set(row.modelId, row);
        }
        // 清单去重（insertModel 查重责任在调用方——同 id 重复行会双插堆积）
        const seen: Set<string> = new Set();
        this.sheetRows = [];
        for (const id of ids) {
          if (seen.has(id)) {
            continue;
          }
          seen.add(id);
          const hit: ModelRow | undefined = rowByModelId.get(id);
          this.sheetRows.push({
            modelId: id, rowId: hit !== undefined ? hit.id : '', inDb: hit !== undefined
          });
        }
        this.sheetEpoch += 1;
        this.sheetShow = true;
      })
      .catch((e: Object): void => {
        this.hintText = (e as Error).message;
      })
      .finally((): void => {
        this.fetching = false;
      });
  }

  // 半模态保存完成上行：收起面板 + 面板重拉（键变重建清单）+ 顶卡纪元（坑16）
  private onSheetSaved(): void {
    this.sheetShow = false;
    this.reload();
    this.onModelsChanged();
  }

  // 半模态关闭请求（★ 2026-09-23 关闭确认笔——两路单源：标题栏 xmark 的 onDismiss 与 bindSheet
  // onWillDismiss〔下拉 / 侧滑返回 / 三键 back / ESC / 点蒙层〕都调本方法）：无未保存勾选直接关；
  // 有则先确认，未通过 / 弹窗异常一律不置 sheetShow = 面板保持打开（确认弹窗形制单源 =
  // KimiSheetCommon.confirmSheetClose）。★ 「保存勾」是与本方法并列的**程序化关闭**路径
  //（onSheetSaved），不经确认——用户已表达保存意图，且落库后无改动可丢
  private requestCloseFetch(): void {
    if (!this.fetchDirty) {
      this.sheetShow = false;
      return;
    }
    confirmSheetClose(this.getUIContext(), {
      title: '放弃这次勾选？',
      message: '放弃后不会保存任何勾选变化，模型列表保持原样',
      cancelLabel: '继续勾选',
      confirmLabel: '放弃'
    }).then((approved: boolean): void => {
      if (approved) {
        this.sheetShow = false;
      }
    });
  }

  // 分组区（对话/向量；空组整区不渲染）：组标题 + 一卡一模型
  @Builder
  GroupSection(title: string, kind: string) {
    if (this.filtered(kind).length > 0) {
      Column({ space: 10 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width(CARD_PANEL_WIDTH)
        ForEach(this.filtered(kind), (row: ModelRow) => {
          ModelCardItem({
            row: row,
            menuAnchorId: MODEL_CARD_MENU_ID_PREFIX + row.id,
            onToggle: (toggled: ModelRow, isOn: boolean): void => {
              this.toggleModel(toggled, isOn);
            },
            onMenu: (menuRow: ModelRow): void => {
              this.openCardMenu(menuRow);
            }
          })
          // 键含 enabled/caps/capsUserModified：ForEach 同键不重建子项（官方键值 diff 规则），
          // 启停回滚与能力编辑（含派生⇄固化标志翻转——全不勾保存后徽章消失）须经键变化
          // 触发卡重建，UI 才与库同步（modelId 行身份不可变）
        }, (row: ModelRow): string => row.id + '|' + row.enabled + '|' + row.caps + '|' + row.capsUserModified)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  // 获取半模态内容（坑39：@Builder 位）。★ 内容常驻 builder、不随 sheetShow 条件卸载
  //（bug 实锤：条件卸载会在任何关闭动作时把内容连标题一起抽走 → 空白面板残留且手势
  // 关闭的 onWillDismiss 赋值无变化不再触发收起 = 关不掉须重启）；实例生命周期 = 纪元键
  //（sheetEpoch++ 重建播种勾选态），显隐只由 bindSheet 首参驱动
  @Builder
  FetchSheetBuilder() {
    ForEach([this.sheetEpoch], (epoch: number) => {
      ModelFetchSheet({
        rows: this.sheetRows,
        onSaved: (): void => {
          this.onSheetSaved();
        },
        onDirtyChange: (dirty: boolean): void => {
          this.fetchDirty = dirty;
        },
        onDismiss: (): void => {
          this.requestCloseFetch();
        }
      })
    }, (epoch: number): string => 'fetchSheet|' + epoch)
  }

  build() {
    // 面板本体 = 纯 Column（2026-08-30 反馈轮 2：滚动由详情页滚动层统一承载——原自带
    // Scroll 属双滚动容器嵌套，且配置面板无滚动承载导致「配置页无法滚」同根）
    Column({ space: 10 }) {
        if (this.providerId === '') {
          // 新建未保存：模型是已保存服务商的资源（providerId 是行身份），先保存再管理
          Column({ space: 8 }) {
            Text('保存服务商后即可管理模型')
              .fontSize(16)
              .fontColor(cardTitleColor())
            Text('点击右上角「保存」完成创建，再回到此页签获取或添加模型')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width(CARD_PANEL_WIDTH)
          .padding(24)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        } else {
          // ── 工具卡：搜索 / 添加 / 获取（2026-08-30 领导指令「获取/添加按钮与搜索框
          // 换位」：搜索框在上、功能键行在下；2026-09-02 决明「换序」：次钮「添加」左、
          // 主操作「获取模型」（蓝底）右，更多键最右）──
          Column({ space: 10 }) {
            TextInput({ placeholder: '搜索模型，按 modelId', text: this.keyword })
              .onChange((value: string): void => {
                this.keyword = value;
              })
              .width('100%')
            Row({ space: 8 }) {
              Button('添加')
                .fontColor(fallbackButtonFont(this.contentFallback, false))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .onClick((): void => {
                  this.onOpenModel(null);
                })
              Button(this.fetching ? '获取中…' : '获取模型')
                .fontColor(fallbackButtonFont(this.contentFallback, true))
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .layoutWeight(1)
                .enabled(!this.fetching)
                .onClick((): void => {
                  this.fetchModels();
                })
              // 更多键（2026-08-31 圆底样式——照标题栏更多按钮（圆底灰钮 + 中心图标，
              // 与前两钮同底同按压光感）；★内容区双态（2026-09-03）：光感态 = 原材质
              //（resolvedButton*）；实底态 = fallbackButton* 官方实底（contentFallback 默认 true）；
              // 直挂 Row 不占伸缩槽——添加/获取 layoutWeight
              // 等分剩余宽度（较旧三槽等分各增宽约 30vp），两处 space 8 间距严格相等，
              // 添加左端与搜索框左端、更多右端与搜索框右端贴齐（Row 两端 = 搜索框
              // width 100% 两端；2026-09-02 换序后「添加/获取」对调，贴齐语义不变）；
              // 菜单 = 全部开启/全部关闭，bindMenu 材质 REGULAR 随沉浸光感总档；仅模型
              // 清单非空显示——无目标批量无意义）
              if (this.models.length > 0) {
                Button() {
                  SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                    .fontSize(18)
                    .fontColor([fallbackButtonFont(this.contentFallback, false)])
                }
                .type(ButtonType.Circle)
                .width(40)
                .height(40)
                .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
                .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
                .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
                .bindMenu(this.BatchMenu, {
                  placement: Placement.BottomRight,
                  // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
                  systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                    this.immersiveLevel, true)
                })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)

          if (this.hintText !== '') {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width(CARD_PANEL_WIDTH)
          }
          if (this.models.length === 0) {
            Text('暂无模型。点「获取模型」从服务商拉取，或「添加」手动登记')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }

          // ── 模型清单（对话/向量分组；搜索态两组同过滤）──
          this.GroupSection('对话模型', 'chat')
          this.GroupSection('向量模型', 'embedding')
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 获取半模态（坑64：声明式 bindSheet 挂面板根——BalancePanel 同款；detents 选择器
      // 类 [MEDIUM, LARGE]；onWillDismiss 手势关闭动画前置回写——KimiSheetCommon 定稿。
      // ★ 2026-09-23 关闭确认笔：手势与系统返回同调 requestCloseFetch（与标题栏 xmark 同源
      // ——两路都进确认）；确认未过时不置 sheetShow，面板保持打开）
      .bindSheet(this.sheetShow, this.FetchSheetBuilder(), sheetPanelOptions((): void => {
        this.requestCloseFetch();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }
}
