// 服务商详情 · 配置页签 Key 池卡（2026-08-30 多 Key 池新增；行形态域拆 ProviderKeyRowItem.ets）：
// 条目行 = label（新建自动「Key N」，可重命名）+ 掩码 + 行内「更多」键（测试连接/重命名/
// 删除）+ 启停 Toggle；「添加 Key」弹 InputDialog（密码型）。
// ★ 保存语义（2026-08-31 领导拍板「配置改后必须点右上角勾才保存」）：**启停 = 草稿态**——
// 乐观更新 + 上行宿主 ProviderToggleDraft（引用经 ConfigPanel 透传），保存链尾统一落库，
// 不点勾退出 = 草稿随页面丢弃；reload 从草稿引用回灌防弹回。**重命名/删除/添加/重填/测试
// = 资源动作即时生效**——重命名经「更多」菜单 InputDialog（对话历史同款成熟 UI），
// renameProviderKey 单列 UPDATE 覆盖（每 key 恒一名称无堆积，Asset 零触碰），领导明示
// 「命名不用点保存也记住」，与启停草稿态两语义并存。明文只进 Asset（安全红线）。
// ★ 轮询口径（2026-08-31）：发送时**按卡片顺序**轮询（sortOrder 升序 = 卡片排列序 =
// 取钥序三者一致）；401/403/429 自动切换下一支。
// ★ 取钥方式（2026-09-17 新增）：卡内分段胶囊二选一——「轮询」= 上述按序轮换（默认），
// 「随机」= 每次发送随机挑起始支；两者失败切换阶梯相同（起始支之后的环绕序），只影响
// 起始位（DB v32 providers.key_pick_mode → 发送链 nextPickStart）。改选 = 草稿态，
// 详情页标题栏「保存」落库；副行说明随模式切换（keyPickDescText）。
// ★ 明文缺失态（2026-08-31）：reload 顺带检测 plain === ''（掩码面零扩大）→「明文缺失」胶囊 + 重填键；发送兜底零改动。
// ★ 弹窗机制（坑7）：CustomDialogController 须组件成员位构造（惰性重建先例 ProviderPage）。
// ★ 连接测试（2026-08-31）：卡头 wifi 键测全池 / 单支菜单测本支——探针/聚合在
// KeyConnectTester（fetchModelIds 三协议只读零消耗，用当前表单 baseUrl/protocol）。
// ★ 能力三项测试（2026-09-21 笔）：单支行菜单「测试连接」改开**能力面板**（ConnectTestSheet
// 半模态，挂本面板根——三项真请求：非流式 / 流式 / 工具调用，逐项归态 + 模型回复原文）；
// 卡头 wifi 键仍走上面的全池批测 toast（零 token、零改动）。面板打开即自动开跑（入口菜单项
// 就叫「测试连接」，点进来意图已明确）；键条「测试」= 重跑。本面板只管「显示态 + 门闩 +
// 纪元守卫」，前置检查与三探针编排全在 KeyConnectTester.runConnectTests。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import { SegmentBar } from '../SegmentBar';
import { loadPoolKey, savePoolKey } from '../../common/store/KeyStore';
import {
  deleteProviderKey, insertProviderKey, ProviderKeyRow, queryProviderKeys, renameProviderKey
} from '../../common/store/ProviderKeyDb';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, overlayMaterial } from '../../common/ImmersiveLevel';
import { PROBE_IDLE, PROBE_RUNNING } from '../../common/providers/ConnectTestJudge';
import { KeyDisplayRow, maskKey, ProviderKeyRowItem } from './ProviderKeyRowItem';
import {
  ConnectTestRow, connectTestRows, KeyTestResult, mergeConnectTestRow, runConnectTests,
  summarizeTestResults, testKeyConnection, testPoolKeys
} from './KeyConnectTester';
import { ConnectTestSheet } from './ConnectTestSheet';
import { sheetPanelOptions, SheetDetents } from '../chat/KimiSheetCommon';

// 打点 TAG（「密钥池有时不显示」定位桩：运行日志页按 TAG 过滤判定「显示 vs 存储」两分支）
const DOMAIN: number = 0xD5A6;
const TAG: string = 'ProviderKeysPanel';

// 编辑对象 id 广播键（2026-08-30 自持有配套：详情页 aboutToAppear 入口同步写入（编辑 =
// 参数 id / 新建 = ''）+ 新建保存成功二次写入；本面板与 ProviderModelsPanel 经 @StorageProp
// @Watch 自感知即重拉）。★ 不用 @Prop：content 通道内 @Prop 不随父更新，面板创建早于回填
// 即冻结 ''（「重进后 key 池不见」根因）。★ 出页不清空：旧页销毁滞后 pop 转场，清空与下次
// 进入写入竞态（「返回立刻重进面板冻结」根因）；本键消费方只活在本页、每次进入覆写。
export const PROVIDER_EDIT_ID_KEY: string = 'providerEditId';

@Component
export struct ProviderKeysPanel {
  // 所属服务商 id（'' = 新建未保存——整卡换提示；@StorageProp 订阅——见键常量注释）
  @StorageProp(PROVIDER_EDIT_ID_KEY) @Watch('onPidChanged') providerId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（「添加 Key」按钮材质随档——行内键光感簇数据源，
  // 见 ImmersiveLevel fallbackButton*/resolvedButton*；与 ProviderModelsPanel 同口径）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 启停草稿链（2026-08-31 统一保存语义，宿主经 ProviderConfigPanel 透传下发）：
  // draftRef = ProviderToggleDraft key Map 引用（实例恒定，reload 回灌读）；
  // onToggleDraft = 乐观上行回调（宿主记草稿，保存链尾统一落库）
  draftRef: Map<string, boolean> = new Map();
  onToggleDraft: (keyId: string, on: boolean) => void = () => {
  };
  // 连接测试用当前表单值（@Link 链直达父页——content 通道 @Prop 冻结，编辑后测须最新值）
  @Link baseUrl: string;
  @Link protocol: string;
  // 取钥方式分段下标（0 = 轮询 / 1 = 随机；@Link 链直达父页 @State——与 SegmentBar 双向绑定，
  // 落库在详情页保存链尾。★ 用 @Link 不用 @Prop：content 通道内 @Prop 不随父更新〔坑16 家族〕，
  // baseUrl/protocol 同款）
  @Link keyPickIdx: number;
  // OpenAI 接口形态（2026-09-21 能力三项测试笔新增透传：T1 自组端点与 T2/T3 流式链分发都要
  // 按 responses/chat 分流，@Link 链直达父页 @State——与 baseUrl/protocol 同款姿势）
  @Link endpoint: string;
  // 分段选项（顺序 = 下标↔模式值映射契约，勿单独乱调；标签文案与 ProviderKeyDb 值域一一对应）
  private keyPickItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '轮询' },
    { text: '随机' }
  ]);
  // 测试进行中（卡头键与单支菜单共用防重入门闩）
  @State private testing: boolean = false;
  @State private keys: KeyDisplayRow[] = [];
  @State private hintText: string = '';
  @State private working: boolean = false;
  // ── 能力三项测试面板（2026-09-21 笔）──
  // 显示态 / 副标题模型名（探针解析完成后异步回填）/ 三行结果（整组替换驱动面板重建）/
  // 重跑门闩（键「测试」连点防重入）；纪元号与被测支是普通成员——只参与比对不驱动 UI
  //（状态最小化：@State 只给会变且要刷新的变量）
  @State private sheetShow: boolean = false;
  @State private sheetModel: string = '';
  @State private sheetRows: ConnectTestRow[] = [];
  @State private sheetTesting: boolean = false;
  private sheetEpoch: number = 0;
  private sheetKeyId: string = '';
  // 添加弹窗（组件成员位构造——坑7；内容静态，一劳永逸）
  private addCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '添加 API Key',
      placeholder: 'sk-...',
      confirmLabel: '添加',
      password: true,
      onConfirm: (text: string): void => {
        this.confirmAdd(text);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  // 删除弹窗（惰性构造——消息带 label 动态拼，ProviderPage 先例）
  private delCtrl: CustomDialogController | null = null;
  private pendingDelete: KeyDisplayRow | null = null;
  // 重命名弹窗（惰性构造——坑7；InputDialog 对话历史同款：初值预填 + 同值视为取消）
  private renameCtrl: CustomDialogController | null = null;
  private pendingRename: KeyDisplayRow | null = null;
  // 重填弹窗（惰性构造同删除弹窗——标题带 label 动态拼；明文经密码型输入不脱敏日志）
  private refillCtrl: CustomDialogController | null = null;
  private pendingRefill: KeyDisplayRow | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  // 编辑对象回填（AppStorage 写值触发——自感知重拉，见键常量注释）
  onPidChanged(): void {
    this.reload();
  }

  // 取钥方式副行说明（随分段下标切；两态兜底句同文——失败切换阶梯与模式无关）
  private keyPickDescText(): string {
    const head: string = this.keyPickIdx === 1
      ? '发送时从启用的密钥中随机挑一支。'
      : '发送时按下方列表顺序轮换取钥。';
    return head + '密钥失效或限流时自动切换到下一支。明文只存系统安全存储，界面仅显示掩码。';
  }

  // 重拉：DB 行 + Asset 明文聚合赋值；done = 「刚添加」场景 toast 报实际池内数量
  private reload(done?: (count: number) => void): void {
    hilog.warn(DOMAIN, TAG, 'reload 触发 providerId=%{public}s', this.providerId);
    if (this.providerId === '') {
      return;
    }
    queryProviderKeys(this.providerId)
      .then(async (rows: ProviderKeyRow[]): Promise<KeyDisplayRow[]> => {
        const items: KeyDisplayRow[] = [];
        for (const row of rows) {
          const plain: string = await loadPoolKey(this.providerId, row.id);
          // missingPlain：Asset 空 = 明文缺失（掩码读取面顺带检测零扩大）；草稿回灌：
          // 重建后从宿主草稿恢复未保存启停态（库态+草稿 = 用户所见，保存前不弹回）
          const drafted: boolean | undefined = this.draftRef.get(row.id);
          items.push({
            id: row.id, label: row.label, mask: maskKey(plain),
            enabled: drafted !== undefined ? drafted : row.enabled,
            missingPlain: plain === ''
          });
        }
        return items;
      })
      .then((items: KeyDisplayRow[]): void => {
        this.keys = items;
        this.hintText = '';
        hilog.warn(DOMAIN, TAG, '赋值完成 keys=%{public}d', items.length);
        if (done !== undefined) {
          done(items.length);
        }
      })
      .catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'reload 失败：%{public}s', (e as Error).message);
        this.hintText = '密钥池读取失败：' + (e as Error).message;
      });
  }

  // 添加执行（InputDialog 已校验非空并关闭）：行 + Asset 成对写入 → 重拉 + toast
  private confirmAdd(text: string): void {
    if (this.working || this.providerId === '') {
      return;
    }
    this.working = true;
    insertProviderKey(this.providerId, text)
      .then((): void => {
        this.reload((count: number): void => {
          this.getUIContext().getPromptAction().showToast({ message: '已添加 API Key，池内共 ' + count + ' 支' });
        });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '添加失败：' + (e as Error).message });
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 启停（草稿态）：乐观更新（数组整组替换，ForEach 键含 enabled 重建行）+ 上行宿主记
  // 草稿——点标题栏「保存」统一落库，直接退出 = 草稿丢弃；纯内存无失败路径
  private toggleKey(row: KeyDisplayRow, isOn: boolean): void {
    this.keys = this.keys.map((item: KeyDisplayRow): KeyDisplayRow => {
      if (item.id !== row.id) {
        return item;
      }
      const next: KeyDisplayRow = {
        id: item.id, label: item.label, mask: item.mask, enabled: isOn,
        missingPlain: item.missingPlain
      };
      return next;
    });
    this.onToggleDraft(row.id, isOn);
  }

  // 重命名弹窗（惰性构造 + open）
  private openRenameDialog(row: KeyDisplayRow): void {
    this.pendingRename = row;
    this.renameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名密钥',
        initialText: row.label,
        confirmLabel: '重命名',
        onConfirm: (text: string): void => {
          this.confirmRename(row, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.renameCtrl.open();
  }

  // 重命名执行（InputDialog 已校验非空/同值跳过）：单列 UPDATE 覆盖即时落库（不经保存
  // 键）；成功 toast + reload（键含 label 重建行显示新名）；失败 toast 不静默
  private confirmRename(row: KeyDisplayRow, text: string): void {
    if (this.working || this.providerId === '') {
      return;
    }
    this.working = true;
    renameProviderKey(row.id, text)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已重命名为「' + text + '」' });
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 删除确认弹窗（惰性构造 + open）
  private openDeleteConfirm(row: KeyDisplayRow): void {
    this.pendingDelete = row;
    this.delCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除密钥',
        message: '将删除「' + row.label + '」，不可恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.deletePending();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.delCtrl.open();
  }

  private deletePending(): void {
    const row: KeyDisplayRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    deleteProviderKey(this.providerId, row.id)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除「' + row.label + '」' });
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 重填弹窗（惰性构造 + open——坑7 同删除链；密码型，空值 toast 留弹窗 = 既有校验）
  private openRefillDialog(row: KeyDisplayRow): void {
    this.pendingRefill = row;
    this.refillCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重填「' + row.label + '」',
        placeholder: 'sk-...',
        confirmLabel: '重填',
        password: true,
        onConfirm: (text: string): void => {
          this.confirmRefill(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.refillCtrl.open();
  }

  // 重填执行（InputDialog 已校验非空并关闭）：savePoolKey 覆盖写（先删后加，KeyStore 既有）
  // → 重拉 + toast「已重填」；明文不入日志/toast（安全红线）；失败 toast 不静默
  private confirmRefill(text: string): void {
    const row: KeyDisplayRow | null = this.pendingRefill;
    this.pendingRefill = null;
    if (row === null || this.working || this.providerId === '') {
      return;
    }
    this.working = true;
    savePoolKey(this.providerId, row.id, text)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已重填「' + row.label + '」' });
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '重填失败：' + (e as Error).message });
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 全池批测入口（卡头 wifi 键——单支池亦走此处，toast 直报「label：detail」；多支聚合；
  // testing 防重入；Base URL 空守卫 toast——P0-1；探针/聚合在 KeyConnectTester）。
  // ★ 2026-09-21 起**只有卡头键走本方法**：单支行菜单改走能力面板（openPanel），行为零改动
  private runTest(rows: KeyDisplayRow[]): void {
    if (rows.length === 0 || this.testing || this.providerId === '') {
      return;
    }
    if (this.baseUrl.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先填写 Base URL 再测试连接' });
      return;
    }
    this.testing = true;
    const single: boolean = rows.length === 1;
    const probe: Promise<KeyTestResult[]> = single
      ? testKeyConnection(this.providerId, rows[0], this.baseUrl.trim(), this.protocol)
        .then((r: KeyTestResult): KeyTestResult[] => [r])
      : testPoolKeys(this.providerId, rows, this.baseUrl.trim(), this.protocol);
    probe.then((results: KeyTestResult[]): void => {
      this.getUIContext().getPromptAction().showToast({
        message: single ? rows[0].label + '：' + results[0].detail : summarizeTestResults(results)
      });
    })
      .finally((): void => {
        this.testing = false;
      });
  }

  // 能力面板打开（单支行菜单入口）：记住被测支 -> 清副标题 -> 三行归「未测试」-> 显示 ->
  // 直接开跑。★ 上一轮在途不清门闩（关面板不中止进行中的请求是既定语义，见 runProbes）；
  // 重开面板 = 新一轮，旧轮结果与终态按纪元丢弃
  private openPanel(row: KeyDisplayRow): void {
    this.sheetKeyId = row.id;
    this.sheetModel = '';
    this.sheetRows = connectTestRows(PROBE_IDLE);
    this.sheetShow = true;
    this.sheetTesting = false;
    this.runProbes();
  }

  // 三探针开跑（首开与键条「测试」重跑同源）：整组重置为「测试中」即刻作废旧结果（禁新旧
  // 混显）+ 纪元自增 + 门闩防键条连点重入。**纪元守卫**：回调与终态清理都先比对打开当刻的
  // epoch，不匹配即整包丢弃——防「关闭再重开闪现上一轮结果」，也防上一轮的 finally 误清新
  // 轮门闩（关面板不中止请求是既定语义，旧轮照常自然收尾）
  private runProbes(): void {
    if (this.sheetTesting || this.providerId === '' || this.sheetKeyId === '') {
      return;
    }
    this.sheetTesting = true;
    this.sheetRows = connectTestRows(PROBE_RUNNING);
    this.sheetEpoch++;
    const epoch: number = this.sheetEpoch;
    runConnectTests(this.providerId, this.sheetKeyId, this.baseUrl.trim(), this.protocol,
      this.endpoint, (model: string): void => {
        if (epoch === this.sheetEpoch) {
          this.sheetModel = model;
        }
      }, (result: ConnectTestRow): void => {
        if (epoch === this.sheetEpoch) {
          this.sheetRows = mergeConnectTestRow(this.sheetRows, result);
        }
      })
      .finally((): void => {
        if (epoch === this.sheetEpoch) {
          this.sheetTesting = false;
        }
      });
  }

  // 能力面板内容（挂本面板根——规范-半模态 §1「非槽内最近可达根」：合法树内 / 面板不在
  // ForEach 行内故存活期不因行重建销毁 / isShow 与触发键同组件位；壳与三行在内容件）
  @Builder
  TestSheet() {
    ConnectTestSheet({
      model: $sheetModel,
      rows: $sheetRows,
      testing: $sheetTesting,
      onClose: (): void => {
        this.sheetShow = false;
      },
      onRetest: (): void => {
        this.runProbes();
      }
    })
  }

  build() {
    Column({ space: 10 }) {
      if (this.providerId === '') {
        // 新建未保存：密钥是已保存服务商的资源，先保存再管理（模型页签同款口径）
        Column({ space: 8 }) {
          Text('保存服务商后即可管理密钥')
            .fontSize(16)
            .fontColor(cardTitleColor())
          Text('点击右上角「保存」完成创建，再回到此页签添加 API Key')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width(CARD_PANEL_WIDTH)
        .padding(24)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      } else {
        Column({ space: 12 }) {
          // 标题行 + 卡头「测试连接」键（测全池；TEXTUAL 无底同四点键形态，测试中禁用）
          Row({ space: 8 }) {
            Text('API 密钥池')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            Button() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .enabled(!this.testing)
            .onClick((): void => {
              this.runTest(this.keys);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 取钥方式分段胶囊（2026-09-17：DB v32 providers.key_pick_mode 的 UI 写点；
          // 共用件 SegmentBar 零参数覆盖——全项目唯一分段封装，改前先读其头注释）。
          // 外层包 CARD 内通宽 + SEGMENT_BAR_HEIGHT（官方组件宽度 = 父容器宽、高度定值，
          // 照 FunctionalModelPage 引擎三分段同款）。草稿态：改选只动本 @Link 下标，
          // 落库在详情页标题栏「保存」链尾（与启停草稿同语义）
          Column() {
            SegmentBar({
              items: this.keyPickItems,
              selectedIndex: $keyPickIdx
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
          // 副行说明（随模式切换——轮询讲卡片顺序，随机讲随机挑支；兜底句两态共用）
          Text(this.keyPickDescText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          if (this.hintText !== '') {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('100%')
          }
          if (this.keys.length === 0) {
            Text('暂无密钥。点「添加 Key」录入第一支，获取模型与余额查询也用它')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          // 条目行（域件行 UI + 更多菜单；弹窗编排留在本面板组件成员位〔坑7〕）
          ForEach(this.keys, (row: KeyDisplayRow) => {
            ProviderKeyRowItem({
              row: row,
              onToggle: (toggled: KeyDisplayRow, isOn: boolean): void => {
                this.toggleKey(toggled, isOn);
              },
              onTest: (tested: KeyDisplayRow): void => {
                this.openPanel(tested);
              },
              onRename: (renamed: KeyDisplayRow): void => {
                this.openRenameDialog(renamed);
              },
              onDelete: (deleted: KeyDisplayRow): void => {
                this.openDeleteConfirm(deleted);
              },
              onRefill: (refilled: KeyDisplayRow): void => {
                this.openRefillDialog(refilled);
              }
            })
            // 键含 label/enabled/mask/missingPlain：任一变化 reload 后键变重建行（id 身份不变）
          }, (row: KeyDisplayRow): string => row.id + '|' + row.label + '|' + row.enabled
            + '|' + row.mask + '|' + (row.missingPlain ? 'm' : 'p'))
          // 「添加 Key」= 主操作（2026-09-02 决明要求：官方蓝底——primary=true 强调蓝 +
          // 恒白字，AdjustStageView「保存」同构；2026-09-03 内容区回退双态：光感态 = 原材质
          // （resolvedButton*），实底态 = fallbackButton* 官方实底）
          Button('添加 Key')
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .enabled(!this.working)
            .onClick((): void => {
              this.addCtrl.open();
            })
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 能力三项测试半模态（2026-09-21 笔；挂本面板根，见 TestSheet 注释）：档位 [MEDIUM,
    // LARGE] 半屏起双停靠 = 规范 §4「信息展示类」档（上下文用量 / 消息全文同口径）；
    // onWillDismiss 动画前置回写（坑73——手势关闭路径同步收口，勿用 onDisappear 迟到回调）
    .bindSheet(this.sheetShow, this.TestSheet(), sheetPanelOptions((): void => {
      this.sheetShow = false;
    }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents))
  }
}
