// 服务商详情 · 模型页签面板：工具卡（获取模型 = GET {baseUrl}/models 拉清单进半模态勾选同步〔清单 =
// API 实际结果、初始勾选 = 库已有、右上勾保存 = 勾选入库/取消移除、API 外手动行零触碰，域件
// ModelFetchSheet〕/ 添加 = 手动新建进编辑模型页 / 搜索 = modelId 子串过滤）+ 模型清单（对话/向量两组，
// 一卡一模型：modelId + 能力标签徽章 + 行尾启停 Toggle；★ 决明指令改形——四点菜单退役，编辑改点卡片直进
// 编辑页、删除唯一走行左滑确认链、Toggle 只管启停）。卡片只显示 modelId，不兜底自定义名（model.name 的
// UI 消费仅剩 ModelPickerSheet 与 ModelEditPage 表单）。
// ★ 获取半模态关闭语义：勾选态有未保存改动时，三路关闭（xmark / 下拉·侧滑·三键 back / 点蒙层）都先弹
//「放弃这次勾选？」，未通过则面板保持打开；判据 = 脏态镜像 fetchDirty，收口 = requestCloseFetch（单源）。
// 停用语义：停用模型不进聊天模型选择面板、不参与当前连接解析（解析侧兜底首个启用模型）；本页签全量展示。
// ★ 保存语义（决明拍板「所有配置改后必须点右上角勾才能保存」）：启停（单行 Toggle 与「更多」批量）=
// 草稿态——乐观更新本地清单 + 上行宿主 ProviderToggleDraft 记草稿，详情页「保存」链尾统一落库，直接退出
// = 草稿随页面丢弃；面板重建（页签切换/纪元键）reload 时从草稿回灌。获取同步/添加/删除 = 即时落库。
// 刷新通道：编辑模型页 pop 后经 AppStorage 一次性计数器广播重拉（坑3 口径）；新建服务商 providerId 为空
// → 整面板换提示卡。获取模型用父页当前表单值（Base URL/密钥改后免保存即可试拉）。模型卡组件已域拆
// ModelCardItem.ets。
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
import {
 CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor,
  menuDividerColor, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted, fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, resolvedUiMaterial, overlayMaterial } from '../../common/ImmersiveLevel';
import { ModelCardItem } from './ModelCardItem';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { FetchSheetRow, ModelFetchSheet } from './ModelFetchSheet';
import { confirmSheetClose, sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

// 面板刷新自持：aboutToAppear 挂载拉取 + 面板内获取/删除自动 reload + 坑16 父页 modelsEpoch 纪元键整
// 面板重建；启停不触发 reload（草稿纯内存，库只在保存链 flush 时写）。原 MODEL_LIST_RELOAD_KEY 广播键已删。

// 打点 TAG（运行日志页按 TAG 过滤）
const DOMAIN: number = 0xD5A5;
const TAG: string = 'ProviderModelsPanel';

@Component
export struct ProviderModelsPanel {
  // 页面存活守卫（销毁守卫治理）：置位后迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  // 所属服务商 id（'' = 新建未保存）；@StorageProp 订阅而非 @Prop——SDK 26 传参链不随父状态更新
  //（面板早于回填创建即冻结，见 ProviderKeysPanel PROVIDER_EDIT_ID_KEY 注释）
  @StorageProp(PROVIDER_EDIT_ID_KEY) @Watch('onPidChanged') providerId: string = '';
  // 获取模型用的当前表单值（Base URL 与协议）；key 取池首个启用（单 Key 字段已退役）
  @Prop baseUrl: string = '';
  @Prop protocol: string = '';
  // 编辑模型页入口（父页 push；null = 新建）
  onOpenModel: (row: ModelRow | null) => void = () => {
  };
  // 获取/删除成功上行（坑16：父页自增 headEpoch → 顶卡计数徽章键变重建；@Builder 值参快照不自刷）
  onModelsChanged: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 启停草稿链（宿主 ProviderDetailPage 直发）：modelDraftRef = 草稿 Map 引用（实例恒定，reload 回灌读）；
  // onToggleDraft = 乐观上行回调（宿主记草稿，保存链尾统一落库）
  modelDraftRef: Map<string, boolean> = new Map();
  onToggleDraft: (rowId: string, on: boolean) => void = () => {
  };
  // 行左滑删除互斥组（详情页下发——与 Key 池面板共用一个实例）
  group: SwipeGroup = new SwipeGroup();
  // 数据自持 @State（aboutToAppear 拉取，不依赖父状态传播）
  @State private models: ModelRow[] = [];
  @State private keyword: string = '';
  @State private fetching: boolean = false;
  // 获取半模态：sheetRows = 探针结果行；sheetEpoch 纪元键重建 Sheet 播种勾选态；sheetShow = bindSheet 显隐
  @State private sheetRows: FetchSheetRow[] = [];
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  @State private sheetEpoch: number = 0;
  // 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）：离场动效在途期再点「获取模型」，可见性 true 会被吞或被收尾回写压回——在途期只记开意图，动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 获取半模态脏态镜像（经 onDirtyChange 上行）：勾选态与库态不一致 = 有未保存勾选，关闭请求据此决定；普通成员不驱动 UI，无需 @State
  private fetchDirty: boolean = false;
  @State private hintText: string = '';
  // 删除确认弹窗控制器（坑7：须组件成员位构造，普通类成员 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 沉浸光感档位（工具卡按钮与「更多」bindMenu 材质随档）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = 官方实底（内容区材质不生效）；false = 原材质光感；订阅式切换即刷
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  // 删除（左滑入口）：先做使用检测（功能模型槽/助手绑定/会话覆盖）→ 拼提示句 → 确认弹窗；
  // 检测失败降级成「未能检测」句（P0-1 不静默；删除照常可走）
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

  // 确认弹窗（官方实底）；使用情况句为空不拼。★ 删除目标随弹窗载荷走（闭包捕获 row，不经成员中转）：
  // 检测异步，目标存成员位会被交错的两条删除流程覆盖，用户对着 A 的弹窗删掉 B（P-19 同族）
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

  // 删除执行（row = 弹窗载荷原样下传）：库内事务级联（模型行 + 助手绑定 + 会话覆盖，见 deleteModel）
  // → 清单重拉 + 顶卡纪元上行；失败 toast 可重试（P0-1）
  private async deletePending(row: ModelRow): Promise<void> {
    try {
      await deleteModel(row.id);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除模型' });
      this.reload();
      this.onModelsChanged();
    } catch (e) {
      if (this.departed) {
        return;
      }
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
        if (this.departed) {
          return;
        }
        // 草稿回灌：重建后从宿主草稿引用恢复未保存启停态——保存前所见恒为「库态+草稿」，不弹回
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
        // 清单整组重拉即收口行左滑展开态（删行后原行销毁，双保险）
        this.group.collapse();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = '模型清单读取失败：' + (e as Error).message;
      });
  }

  // 模型启停（草稿态）：乐观更新本地清单（整组替换，ForEach 键含 enabled → 键变重建卡）+ 上行宿主记草稿；「保存」统一落库，直接退出 = 草稿丢弃；无失败路径
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

  // 批量启停（草稿态，「更多」菜单）：作用域 = 本服务商全部模型行——全行乐观更新 + 逐行上行宿主草稿；toast 注明「保存后生效」（P0-1）
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

  // 「更多」菜单（全部开启/全部关闭；固定两项无需 ForEach；分割线官方 EMBEDDED_IN_MENU，ChatTitleMenu 同款）
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

  // 关键词过滤（modelId 子串、大小写不敏感；空词 = 全量；name 不参与——显示链已收敛）
  private filtered(kind: string): ModelRow[] {
    const key: string = this.keyword.trim().toLowerCase();
    return this.models.filter((row: ModelRow): boolean => row.kind === kind &&
      (key === '' || row.modelId.toLowerCase().includes(key)));
  }

  // 获取模型（半模态勾选同步，不直接入库）：表单守卫 → 池首启用 key → 按协议拉清单 → 构造半模态行
  //（modelId + 库行 rowId/inDb）→ 纪元键重建 Sheet 播种勾选态并打开；失败 hintText，保存勾在 Sheet 内
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
        if (this.departed) {
          return;
        }
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
        this.requestOpen();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = (e as Error).message;
      })
      .finally((): void => {
        if (this.departed) {
          return;
        }
        this.fetching = false;
      });
  }

  // 半模态保存完成上行：收起面板 + 面板重拉（键变重建清单）+ 顶卡纪元（坑16）
  private onSheetSaved(): void {
    this.applySheetClose();
    this.reload();
    this.onModelsChanged();
  }

  // 关闭-再开协调（机制见字段注释）
  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.sheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性兜底（@Watch）：框架 $$ 收尾回写压回 false 时按开意图补开；用户关闭必经 applySheetClose，不会误触
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 半模态关闭请求（两路单源：标题栏 xmark 与 bindSheet onWillDismiss〔下拉/侧滑返回/三键 back/ESC/
  // 点蒙层〕）：无未保存勾选直接关，有则先确认，未通过 / 弹窗异常一律不放行 = 面板保持打开（确认弹窗
  // 形制单源 = KimiSheetCommon.confirmSheetClose）。★「保存勾」是并列的程序化关闭路径（onSheetSaved），
  // 不经确认——已表达保存意图且落库后无改动可丢。★ 手势路带 action 进来：确认通过后 action.dismiss()
  // 放行；xmark 自绘键路 action 缺省——直写可见性状态位（$$ 双向）；确认未过时不调 dismiss()、不置 false
  private requestCloseFetch(action?: DismissSheetAction): void {
    if (!this.fetchDirty) {
      this.applySheetClose(action);
      return;
    }
    confirmSheetClose(this.getUIContext(), {
      title: '放弃这次勾选？',
      message: '放弃后不会保存任何勾选变化，模型列表保持原样',
      cancelLabel: '继续勾选',
      confirmLabel: '放弃'
    }).then((approved: boolean): void => {
      if (approved) {
        this.applySheetClose(action);
      }
    });
  }

  // 关闭放行单源：手势路（action 在场）走官方 dismiss()；自绘键 / 程序化路（action 缺省）直写可见性。
  // ★ 放行 = 关闭单入口——先清开意图 + 置离场动效在途位，再写可见性（关闭-再开协调，见字段注释）
  private applySheetClose(action?: DismissSheetAction): void {
    if (action !== undefined) {
      action.dismiss();
    }
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
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
          // 行左滑删除层：模型卡 CARD_PANEL_WIDTH 居中 → cardInset 16；删除走 askDeleteById 确认链
          //（四点菜单退役后唯一删除路径）；展开态不进键
          RowSwipeDelete({
            rowId: row.id,
            group: this.group,
            content: (): void => {
              this.ModelRow(row)
            },
            onSwipeDelete: (rowId: string): void => {
              this.askDeleteById(rowId);
            }
          })
          // 键含 modelId/enabled/caps/capsUserModified（行身份仍是 id）：ForEach 同键不重建子项，改名、
          // 启停回滚与能力编辑（含派生⇄固化标志翻转）须经键变化触发卡重建，UI 才与库同步——modelId 漏出
          // 键 = 改名保存返回后主文本冻结旧名（坑44/80 家族）
        }, (row: ModelRow): string =>
          row.id + '|' + row.modelId + '|' + row.enabled + '|' + row.caps + '|' + row.capsUserModified)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  // 模型行卡（RowSwipeDelete content 位）
  @Builder
  ModelRow(row: ModelRow) {
    ModelCardItem({
      row: row,
      onToggle: (toggled: ModelRow, isOn: boolean): void => {
        this.toggleModel(toggled, isOn);
      },
      onOpen: (opened: ModelRow): void => {
        this.onOpenModel(opened);
      }
    })
  }

  // 左滑删除入口：按 id 查行走 openDeleteConfirm 既有确认链（四点菜单退役后唯一删除路径）
  private askDeleteById(id: string): void {
    const row: ModelRow | undefined =
      this.models.find((item: ModelRow): boolean => item.id === id);
    if (row !== undefined) {
      this.openDeleteConfirm(row);
    }
  }

  // 获取半模态内容（坑39：@Builder 位）。★ 内容常驻 builder、不随 sheetShow 条件卸载（bug 实锤：条件卸载
  // 会在关闭时把内容连标题抽走 → 空白面板残留且手势关闭的 onWillDismiss 不再触发 = 关不掉）；实例生命
  // 周期 = 纪元键（sheetEpoch++ 重建播种勾选态），显隐只由 bindSheet 首参驱动
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
    // 面板本体 = 纯 Column（滚动由详情页滚动层统一承载——避免双滚动容器嵌套）
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
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        } else {
          // 工具卡：搜索 / 添加 / 获取（搜索框在上、功能键行在下；次钮「添加」左、「获取模型」主操作
          // 右，更多键最右）
          Column({ space: 10 }) {
            TextInput({ placeholder: '搜索模型，按 modelId', text: this.keyword })
              .onChange((value: string): void => {
                this.keyword = value;
              })
              .width('100%')
            Row({ space: 8 }) {
              Button('添加')
                .fontColor(fallbackButtonFontTinted(this.contentFallback))
                .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
                .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
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
              // 更多键（圆底样式照标题栏更多按钮；内容区双态——光感态原材质、实底态 fallbackButton*，
              // 默认实底）；直挂 Row 不占伸缩槽——添加/获取 layoutWeight 等分剩余宽度，两处 space 8
              // 严格相等，添加左端、更多右端分别贴齐搜索框两端；菜单材质 REGULAR 随沉浸光感总档；仅
              // 清单非空显示（无目标批量无意义）
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
                  // ★ 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
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
          .borderRadius(CARD_RADIUS)

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
      // 获取半模态（坑64：声明式 bindSheet 挂面板根——BalancePanel 同款；detents = [MEDIUM, LARGE]）。
      // 手势与系统返回同调 requestCloseFetch（与 xmark 同源）；可见性 $$ 双向 + 手势路 action 条件放行。
      // ★ 本面板**整面板保留官方回弹**（第三参 true）——含脏态确认（下拉被拦 → 取消须靠预回弹把面板送回
      // 原位；空注册有「半挂」风险，KimiSheetCommon 第三参注释）——全仓唯一不推广直落的整挂载点；第四参
      // onDisappear 补开（关闭-再开协调，见字段注释）
      .bindSheet($$this.sheetShow, this.FetchSheetBuilder(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          this.requestCloseFetch(action);
        }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, true,
        (): void => {
          this.onSheetGone();
        }))
  }
}
