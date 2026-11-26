// HTTP 凭据页域（决明拍板双入口）：两 struct 一件——总览页（HttpCredentialLibraryPage）+ 管理页
//（HttpCredentialManagePage）。
// · 总览页：入口 = HTTP 请求设置页凭据卡（push 无参）；页内 = 全局卡 + 每助手卡（发现面——零凭据
//   助手照列），点击进管理页（param = owner）。
// · 管理页：入口两处 = 助手编辑页「HTTP 凭据」卡（param 携本助手 id + readOnly，直达）+ 总览页卡；
//   形制照 ProviderKeysPanel，差异 = 无启停草稿态（全动作即时落库）、无连接测试（凭据服务面任意，
//   无固定探测端点）。
// ★ 新建/编辑/缺值补全三路统一进 HttpCredentialEditPage（「添加凭据」直接 push credId '' 新建）；
//   行卡本体点击进编辑页（readOnly 态不跳）；行菜单只余「复制」；删除唯一走左滑确认链。两处 push
//   均挂 onPop 重拉（掩码/缺失态可能变）。
// ★ 明文红线（KeyStore 头注释同源）：值只进 Asset，掩码显示（maskKey 单源自 ProviderKeyRowItem，
//   勿抄第二份）；明文不进偏好/DB/日志/toast——toast 只报名与结果。复制 = 只读动作：读明文后经
//   单源 common/Clipboard 写剪贴板即弃（值缺失行照常可点，守卫提示不静默）。
// ★ 名称校验（引用记号语法前提）：非空、不含 '{' '}'（破坏 {{名称}} 解析）、同 owner 内唯一——
//   单源 = HttpCredentials.credNameValid / credNameTaken / credNameTakenExcept。
// 卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / CARD_RADIUS（宿主无左右 16vp padding，
// 卡体恒挂卡宽基准——规范-列表卡片与组卡 §4.3）；自包 PageShell 壳；管理页对入口页仍
// pop({saved:true})〔坑17〕。
// ★ 助手页只读 + 添加键上标题栏（决明指令）：①助手编辑页入口（readOnly = true）= **纯只读清单**——
//   不渲染添加入口、行「更多」菜单，info 与空态改指路设置页（形制对齐助手记忆页）；②「添加凭据」
//   由页底通宽主操作键移入**右上角标题栏**（官方单图标键 ＋，menuHds 原样传，照
//   MemoryEditPage「保存」键形制）；只读态不挂键。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import {
 CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, badgeBg,
  menuDividerColor, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial,
  resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InfoCard } from '../InfoCard';
import { getHttpCredentialsCfgJson } from '../../common/AppPreferencesHttp';
import { deleteCredential, HTTP_CRED_MAX_PER_OWNER, HttpCredCfg,
  HttpCredEntry, HttpCredManageParam, parseHttpCredCfg } from '../../common/providers/HttpCredentials';
import { HTTP_CRED_OWNER_GLOBAL, loadHttpCredential } from '../../common/store/KeyStore';
import { copyTextToClipboard } from '../../common/Clipboard';
import { AssistantRow, queryAssistant,
  queryAssistants } from '../../common/store/AssistantDb';
import { maskKey } from './ProviderKeyRowItem';
import { SETTING_TITLE_HTTP_CREDENTIALS } from '../../common/SettingSearch';
import { ROUTE_HTTP_CREDENTIAL_EDIT_PAGE, ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE } from '../../common/RouteNames';
import { HttpCredEditParam } from './HttpCredentialEditPage';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';

// 管理页展示行（掩码预计算——明文读取算掩码后即弃，不驻留状态；missing = Asset 明文缺失）
interface CredDisplayRow {
  id: string;
  name: string;
  mask: string;
  missing: boolean;
}

// 管理页 push 参数：interface 单源 = common/providers/HttpCredentials.ets（HttpCredManageParam；
// 字符串形态兼容保留 = 旧调用可管理）

// 标题栏「添加凭据」键（官方标题栏菜单数组单键——单动作页用图标键，照 MemoryEditPage
//「保存」；本页只读态不挂本键）
function credAddMenuHds(onAdd: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.plus'),
        action: onAdd
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

// 名称合法性单源在 HttpCredentials.credNameValid（非空、不含花括号、长度上限，UI 与断言直跑共用）

// ── 总览页（发现面：全局卡 + 每助手卡，零凭据照列）──
@Component
export struct HttpCredentialLibraryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行（数据层意图照常完成）
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private assistants: AssistantRow[] = [];
  @State private counts: string[] = []; // 与 assistants 同序的「N 条 / 未配置」副行
  @State private globalCount: number = -1; // -1 = 加载中
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    queryAssistants()
      .then((all: AssistantRow[]): void => {
        if (this.departed) {
          return;
        }
        // （原「控制台助手不列凭据卡」过滤已随控制台合并退役）
        const rows: AssistantRow[] = all;
        this.assistants = rows;
        const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
        this.globalCount = (cfg.get(HTTP_CRED_OWNER_GLOBAL) ?? []).length;
        const lines: string[] = [];
        for (const a of rows) {
          const n: number = (cfg.get(a.id) ?? []).length;
          lines.push(n > 0 ? n + ' 条凭据' : '未配置');
        }
        this.counts = lines;
      })
      .catch((_e: Object): void => {
        if (this.departed) {
          return;
        }
        this.globalCount = 0;
        this.counts = [];
      });
  }

  private openManage(owner: string): void {
    // 第三参 onPop：管理页返回重拉计数——管理动作即时落库，重拉幂等
    this.pathStack.pushPathByName(ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE, owner, (): void => {
      this.reload();
    });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明卡（InfoCard 单源件，文案原样保留；先说明后操作次序不变）
        InfoCard({
          title: SETTING_TITLE_HTTP_CREDENTIALS,
          text: '给助手的 HTTP 请求存密钥。助手只引用名称，真实值加密保存在本机，不会出现在聊天和日志里。全局凭据所有助手都能用，同名时助手自己的优先。'
        })
        // 全局卡（官方按钮 + 原生按压蒙层）。卡底 Column + 四周 padding 4 = 蒙层距卡外圈 4vp
        Column() {
          Button() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(20)
                .fontColor([cardTitleColor()])
              Column({ space: 4 }) {
                Text('全局凭据')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(cardTitleColor())
                  .width('100%')
                Text(this.globalCount > 0 ? this.globalCount + ' 条凭据' : '未配置')
                  .fontSize(13)
                  .fontColor(cardDescColor())
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(CARD_RADIUS)
          .onClick((): void => {
            this.openManage(HTTP_CRED_OWNER_GLOBAL);
          })
        }
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .padding(4)
        // 助手卡（零凭据照列——总览是发现面；形制同全局卡）
        ForEach(this.assistants, (a: AssistantRow, idx: number) => {
          Column() {
            Button() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.person_2'))
                  .fontSize(20)
                  .fontColor([cardTitleColor()])
                Column({ space: 4 }) {
                  Text(a.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(cardTitleColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(idx < this.counts.length ? this.counts[idx] : '未配置')
                    .fontSize(13)
                    .fontColor(cardDescColor())
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .alignItems(VerticalAlign.Center)
            }
            .type(ButtonType.Normal)
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(CARD_RADIUS)
            .onClick((): void => {
              this.openManage(a.id);
            })
          }
          .width(CARD_PANEL_WIDTH)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .padding(4)
        }, (a: AssistantRow) => a.id + '|' + a.name + '|' +
          (this.assistants.indexOf(a) < this.counts.length ?
            this.counts[this.assistants.indexOf(a)] : ''))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_HTTP_CREDENTIALS,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// ── 管理页（param = owner；添加与编辑统一进凭据编辑页）──
@Component
export struct HttpCredentialManagePage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行（数据层意图照常完成）
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @State private rows: CredDisplayRow[] = [];
  @State private titleText: string = SETTING_TITLE_HTTP_CREDENTIALS;
  pathStack: NavPathStack = new NavPathStack();
  // 兜底归全局（只读面最小、与助手无耦合）；aboutToAppear 取到 push 参后覆盖
  private owner: string = HTTP_CRED_OWNER_GLOBAL;
  // 只读态：true = 助手编辑页入口——无添加入口、无行菜单；aboutToAppear 同步定值，首帧即生效
  private readOnly: boolean = false;
  private working: boolean = false;
  // reload 纪元：连续动作各触发一轮，各轮 Asset 读取无序归——旧一轮晚归不得覆盖新一轮结果
  private reloadEpoch: number = 0;
  // 删除确认弹窗控制器（惰性构造——坑7：弹窗控制器须组件成员位构造）
  private delCtrl: CustomDialogController | null = null;
  private pendingDelete: CredDisplayRow | null = null;
  // 行左滑删除互斥组（reload / 滚动开始两路收口；只读态整层退化由 swipeEnabled 承担）
  private swipeGroup: SwipeGroup = new SwipeGroup();

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条）：string owner（'global' 或助手 id；取不到归全局——fail-safe
    // 到只读面最小的命名空间）/ 对象 HttpCredManageParam（owner + readOnly）
    try {
      const params: Array<Object | null> =
        (this.pathStack.getParamByName(ROUTE_HTTP_CREDENTIAL_MANAGE_PAGE) ?? []) as Array<Object | null>;
      const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
      if (typeof last === 'string') {
        this.owner = last;
      } else if (last !== null) {
        const parsed: HttpCredManageParam = last as HttpCredManageParam;
        if (typeof parsed.owner === 'string' && parsed.owner !== '') {
          this.owner = parsed.owner;
        }
        this.readOnly = parsed.readOnly === true;
      }
    } catch (e) {
    }
    this.resolveTitle();
    this.reload();
  }

  private resolveTitle(): void {
    this.titleText = this.owner === HTTP_CRED_OWNER_GLOBAL ? '全局凭据' : SETTING_TITLE_HTTP_CREDENTIALS;
    if (this.owner !== HTTP_CRED_OWNER_GLOBAL) {
      queryAssistant(this.owner)
        .then((row: AssistantRow | null): void => {
          if (this.departed) {
            return;
          }
          if (row !== null) {
            this.titleText = row.name + ' 的凭据';
          } else {
            this.titleText = '已删除助手的凭据';
          }
        })
        .catch((_e: Object): void => {
        });
    }
  }

  private reload(): void {
    const epoch: number = ++this.reloadEpoch;
    const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
    const entries: HttpCredEntry[] = cfg.get(this.owner) ?? [];
    const out: CredDisplayRow[] = [];
    let pending: number = entries.length;
    if (pending === 0) {
      this.rows = [];
      return;
    }
    for (const e of entries) {
      loadHttpCredential(this.owner, e.id)
        .then((value: string): void => {
          out.push({
            id: e.id, name: e.name,
            mask: value === '' ? '••••' : maskKey(value),
            missing: value === ''
          });
        })
        .catch((_e: Object): void => {
          out.push({ id: e.id, name: e.name, mask: '••••', missing: true });
        })
        .finally((): void => {
          if (this.departed) {
            return;
          }
          pending--;
          if (epoch !== this.reloadEpoch || pending > 0) {
            return;
          }
          // 名称序稳定（元数据行序即展示序）；非最新纪元已在上行丢弃
          this.rows = out.sort((x: CredDisplayRow, y: CredDisplayRow): number =>
            entries.findIndex((e: HttpCredEntry): boolean => e.id === x.id) -
            entries.findIndex((e: HttpCredEntry): boolean => e.id === y.id));
          this.swipeGroup.collapse();
        });
    }
  }

  // 添加入口：直接 push 编辑页空表单，名称在页内填、保存链查重。条数上限闸（50，全局与每助手各计）
  // 即唯一写入口，超限 toast 不进页
  private openAddPage(): void {
    if (this.working) {
      return;
    }
    const current: HttpCredEntry[] =
      parseHttpCredCfg(getHttpCredentialsCfgJson()).get(this.owner) ?? [];
    if (current.length >= HTTP_CRED_MAX_PER_OWNER) {
      this.getUIContext().getPromptAction().showToast({
        message: this.owner === HTTP_CRED_OWNER_GLOBAL ?
          '全局凭据最多 ' + HTTP_CRED_MAX_PER_OWNER + ' 条' :
          '每个助手最多 ' + HTTP_CRED_MAX_PER_OWNER + ' 条凭据'
      });
      return;
    }
    this.openEditPage('');
  }

  // 编辑入口（行卡点击 / 新建共用；credId '' = 新建）：编辑页保存后 pop({saved:true}) → 本页 onPop
  // 重拉 reload（掩码/缺失态可能变）
  private openEditPage(credId: string): void {
    if (this.working) {
      return;
    }
    this.pathStack.pushPathByName(ROUTE_HTTP_CREDENTIAL_EDIT_PAGE,
      { owner: this.owner, credId: credId } as HttpCredEditParam, (): void => {
        this.reload();
      });
  }

  private openDeleteConfirm(row: CredDisplayRow): void {
    this.pendingDelete = row;
    this.delCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除凭据',
        message: '将删除「' + row.name + '」，引用它的请求会失效。',
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
    const row: CredDisplayRow | null = this.pendingDelete;
    if (this.working || row === null) {
      return;
    }
    this.working = true;
    deleteCredential(this.owner, row.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除「' + row.name + '」' });
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      })
      .finally((): void => {
        this.working = false;
      });
  }

  // 复制（行「更多」菜单入口）：读明文 → copyTextToClipboard 写剪贴板 → 明文即刻丢弃。明文不进
  // 状态/日志/toast；值缺失行照常可点，守卫提示不静默
  private copyRow(row: CredDisplayRow): void {
    loadHttpCredential(this.owner, row.id)
      .then((value: string): void => {
        if (this.departed) {
          return;
        }
        if (value === '') {
          this.getUIContext().getPromptAction().showToast({ message: '值缺失，无法复制' });
          return;
        }
        copyTextToClipboard(this.getUIContext(), value, '已复制「' + row.name + '」');
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '凭据读取失败：' + (e as Error).message });
      });
  }

  @Builder
  RowMenu(row: CredDisplayRow) {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_filled_on_doc')), content: '复制' })
        .onClick((): void => {
          this.copyRow(row);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 凭据条目行：行卡本体点击进编辑页（readOnly 不跳）；四点键菜单只余「复制」（编辑 = 点卡、
  // 删除 = 左滑）；值缺失行的行内「编辑」快捷键已退役
  @Builder
  CredRow(row: CredDisplayRow) {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(row.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.missing) {
            Text('值缺失')
              .fontSize(10)
              .fontColor(cardDescColor())
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(badgeBg(this.appColorMode))
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(row.mask)
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 行「更多」菜单（只余「复制」）——只读态整段不渲染（纯展示，与助手记忆条目行同口径）
      if (!this.readOnly) {
        Button() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .bindMenu(this.RowMenu(row), {
          placement: Placement.BottomRight,
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true)
        })
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    // 行卡点击进编辑页（readOnly 不跳；四点键自吞点击不冒泡）
    .onClick((): void => {
      if (!this.readOnly) {
        this.openEditPage(row.id);
      }
    })
  }

  // 左滑删除入口（RowSwipeDelete 单源）：按 id 查行走既有确认链；菜单「删除」退役后唯一删除路径
  private askDeleteById(id: string): void {
    const row: CredDisplayRow | undefined =
      this.rows.find((item: CredDisplayRow): boolean => item.id === id);
    if (row !== undefined) {
      this.openDeleteConfirm(row);
    }
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // 说明卡（InfoCard 单源件，title 随全局/助手态分派，文案原样保留）；只读态换「这里只查看」+
        // 指路句（管理入口唯一 = 设置 → 工具调用 → HTTP 请求 → HTTP 凭据）
        InfoCard({
          title: this.readOnly ? '凭据只读' : this.owner === HTTP_CRED_OWNER_GLOBAL ?
            '全局凭据对所有助手可用' : '凭据只属于这个助手',
          text: this.readOnly ?
            '这里只查看这名助手的清单。新增、编辑与删除在设置 → 工具调用 → HTTP 请求 → HTTP 凭据。' :
            '助手在 HTTP 请求里用名称引用，值加密保存在本机，不会出现在聊天和日志里。同名时助手自己的凭据优先。'
        })
        // 条目行（行卡形制 = 白卡行 + CARD_PANEL_WIDTH，照记忆库/知识库管理页行件先例——页容器无
        // 左右 padding 时 100% 会贴屏缘，灰底是卡内行专用色不用于页级列表；空态同形给白卡指路）
        if (this.rows.length === 0) {
          Text(this.readOnly ?
            '还没有凭据。在设置 → 工具调用 → HTTP 请求 → HTTP 凭据里添加。' :
            '还没有凭据。点右上角的加号添加。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .width(CARD_PANEL_WIDTH)
        }
        ForEach(this.rows, (row: CredDisplayRow) => {
          // 行左滑删除层：行卡 CARD_PANEL_WIDTH 居中 → cardInset 16；只读态整层退化；删除走
          // askDeleteById 确认链；展开态不进键
          RowSwipeDelete({
            rowId: row.id,
            swipeEnabled: !this.readOnly,
            group: this.swipeGroup,
            content: (): void => {
              this.CredRow(row)
            },
            onSwipeDelete: (rowId: string): void => {
              this.askDeleteById(rowId);
            }
          })
        }, (row: CredDisplayRow) =>
          // 键含 name/mask/missing：改名后 reload 键变重建行——name 不进键 = 同键复用主文本冻结旧名
          //（坑44/80 家族：键覆盖行卡消费的全部可变展示字段）
          row.id + '|' + row.name + '|' + row.mask + '|' + (row.missing ? 'm' : 'v'))
        // 「添加凭据」键已移入右上角标题栏（原页底通宽主操作键退役），接线见 build 的 menuHds
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 滚动开始即收口行左滑展开态（会话列表/五库同口径）
    .onScrollStart((): void => {
      this.swipeGroup.collapse();
    })
  }

  build() {
    PageShell({
      title: this.titleText,
      // 右上角「添加凭据」键（只读态不挂键 = menuHds null）
      menuHds: this.readOnly ? null : credAddMenuHds((): void => {
        this.openAddPage();
      }),
      // 无保存动作的完成返回（坑17 标准姿势）：pop 带 result 触发入口页 onPop 重拉摘要（重拉幂等无害）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
