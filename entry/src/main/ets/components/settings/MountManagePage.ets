// 「文件夹挂载」管理页（独立整页——与工作区管理页是平行的两个文件域，四重互斥）：给 AI 授权
// 本机文件夹（FOLDER 选择器 → persistPermission 持久化 → 每进程按需 activate），管理清单：
// 添加 / 改名 / 切换模式（只读↔读写）/ 重新授权 / 移除。系统侧授权动作全在本页（fileShare 四
// 接口），本地行读写经 ChatDb 委托（两套真相的边界）。★「允许 AI 使用」per-挂载开关已整面拆除
//（决明拍板：想断访问直接移除挂载；访问门收敛为助手工具页组卡开关单层）。
//
// 三件套：本件 = 页面外壳（@State / 生命周期 / 授权编排 / 列表与卡渲染 / 添加半模态宿主——面板
// 内联 @Builder，表单与页态双向绑定，免 @Prop 回填）；common/MountUtil.ets = 纯函数（模式位映射 /
// 名称路径派生 / 状态与失败文案）；common/store/MountDb.ets = folder_mounts 行读写（含上限与
// 查重闸），页面经 ChatDb 委托消费。
//
// 授权链路（官方《授权持久化》）：
// 添加 = 双 canIUse 能力门 → FOLDER 选择器（用户亲手选目录 = 唯一授权动作）→ 半模态填名称与
//   模式 → **同会话 persistPermission**（只能对临时授权持久化，故必须一气呵成）→ 落本地行 →
//   丢弃临时条目；落行失败走「先查后撤」孤儿补偿（见 compensateOrphanGrant）。
// 切换模式 = 重拉选择器 → **先 persist 新位** → 丢弃临时条目 → **再撤旧位**（不能凭旧持久权改
//   模式）。★ 次序不可反（真机实锤；双证 = 官方「取消持久化授权后需重新获取临时权限」+ 系统
//   源码 RemoveNormalPolicy 按（tokenid, 路径）整条删）：先撤后持久会删掉刚建的临时授权，
//   persist 报 PolicyErrorCode 1，挂载转「需重新授权」的授权真空。
// 重新授权 = 同次序，**同路径不撤旧位**（撤 = 连本次新授权一起删），异路径才清理旧记录（尽力）。
// 丢弃临时条目（deactivate）= persist 后内核仍留选择器条目（内核 set 为 OR，后续激活只增不减）
//   ——只读挂载会残留系统级写位；不动持久记录（与 revoke 的区别），失败只留痕。
// 失效检测 = 进页 checkPersistentPermission（API 17 起免权限、免 activate——工具执行时懒激活）。
// 移除 = revokePermission（尽力，双模式位全清）+ 删本地行，**不动原文件**（系统位未授 DELETE/
//   RENAME，想动也动不了——双保险）。
//
// ★ 卡面现状（2026-11-16 决明参照服务商编辑页模型卡重绘）：①页首 InfoCard 蓝卡（MOUNT_INFO_TEXT
//   静态双权限口径，不随清单变动，页尾同义说明行已退役）；②区头「我的挂载 · N」；③卡面迁
//   MountManageCard.ets——名称 + 模式徽章 + 路径，下排三键「打开 / 移除 / 更多」；卡内只读/读写
//   分段胶囊与卡头铅笔改名键退役，模式切换与重命名收进卡「更多」菜单（域件 MountCardMenu，菜单
//   宿主在本页、锚点挂卡内「更多」键）；④切换模式回调改 Promise<void>（无胶囊可复位；取消/失败
//   由页面 toast 与 reload 如实呈报原模式）。添加入口唯一 = 标题栏右上角「＋」单圆键。
//
// ★ 添加半模态（规范-半模态 §1/§7）：挂页面根（判据三条全过）+ 关闭链四件（$$ 双向 / onWillDismiss
// 放行 / 关闭恒不复位内容形态）+ 关闭-再开五件式。零暂存站点：关闭 = 放弃本次添加（未落任何库
// 数据，临时授权随进程退出自清，无需确认）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileShare, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import {
  addFolderMount,
  isReady,
  queryFolderMounts,
  removeFolderMount,
  renameFolderMount,
  updateFolderMountGrant
} from '../../common/store/ChatDb';
import { FolderMountRow } from '../../common/store/MountDb';
import {
  MOUNT_MAX_COUNT,
  MOUNT_MODE_READ_ONLY,
  MOUNT_MODE_READ_WRITE,
  MOUNT_NAME_MAX_CHARS,
  MountBrowseParam,
  mountCardKey,
  mountModeLabel,
  mountModeMask,
  mountNameFromUri,
  mountNameRejectReason,
  mountOtherMode,
  mountPolicyErrorText,
  mountWarningLine
} from '../../common/MountUtil';
import {
  CONTENT_FALLBACK_KEY,
  IMMERSIVE_LEVEL_KEY,
  fallbackButtonBg,
  fallbackButtonFont,
  fallbackButtonMaterial,
  fallbackButtonStateEffect,
  overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor,
  selectChipBg, selectChipBorderColor, selectChipTextColor, CARD_RADIUS
} from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { MountCardView, MountManageCard } from './MountManageCard';
import {
  MOUNT_CARD_MENU_ID_PREFIX,
  MountCardMenuCallbacks,
  MountCardMenuHost
} from './MountCardMenu';
import { SETTING_TITLE_MOUNT } from '../../common/SettingSearch';
import { ROUTE_MOUNT_BROWSE_PAGE } from '../../common/RouteNames';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import { sheetPanelOptions, sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { TITLE_BAR_EDGE_INSET, TitleBarRoundKey } from '../TitleBarKeys';

const DOMAIN: number = 0xD5B0;
const TAG: string = 'MountManagePage';

// 页首 info 卡静态文案（不随权限状态变动；面向用户文案规约：句号分句、无冒号分号括号连环）
const MOUNT_INFO_TEXT: string = 'AI 读取的是文件夹里的原文件，不会复制一份。只读挂载仅可查看和读取。' +
  '读写挂载还可修改和删除，删除前会先征求同意，内容进系统回收站。移除挂载不影响文件夹里的文件。';

// 回退路径键数组（mountAddMenuNav）已随 HDS 唯一路径化退役；添加入口 = 标题栏覆盖层单键。

// 卡视图载荷迁 MountManageCard.ets（卡面渲染与下排三键归该件）

// 卡菜单占位载荷（宿主 init 首建用——弹出前必 rebuild，菜单内容与动作按点击当刻卡数据生成）
const EMPTY_CARD: MountCardView = {
  id: 0,
  name: '',
  dirUri: '',
  mode: MOUNT_MODE_READ_ONLY,
  warningText: '',
  needReauth: false
};

@Component
export struct MountManagePage {
  // 页面存活守卫：置位后迟到异步回调不写状态不碰 UI 不上行，写库照常完成
  private departed: boolean = false;
  // 顶部/底部留白（vp，PageMap 传入；HDS 路径内容区延伸到标题栏背后）
  topPad: number = 0;
  bottomPad: number = 0;
  // 路由栈（正常态卡内「打开」键进浏览页三级页 push）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 内容区回退开关（行内文字键四件套驱动）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 双系统能力门——手机 FOLDER 链路是 API 26 前沿新开面：FolderSelection 管选择器目录模式、
  // FolderAuthorization 管 fileShare 持久授权；任一不过整链路不可用，卡区降级为说明 + 附件指引
  private folderSelectionCapable: boolean =
    canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
  private folderAuthCapable: boolean =
    canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  private capable: boolean = this.folderSelectionCapable && this.folderAuthCapable;
  // 挂载清单视图（进页 load 现读 + 校验后整组重赋）
  @State private cards: MountCardView[] = [];
  // 首载完成标记（false = 未加载，避免空态闪显）
  @State private loaded: boolean = false;
  // 进页装载闸（防重入）
  private loading: boolean = false;
  // 选目录在途闸（添加 / 切换模式 / 重新授权三路共用）
  private picking: boolean = false;
  // 落库在途闸（添加确认 / 移除两路）
  private addingMount: boolean = false;
  private removing: boolean = false;
  // ── 添加半模态（可见性 + 内容载荷）──
  // 可见性挂 @Watch = 关闭-再开兜底网（机制总表 = assert-ui-shape 329 组）
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  // 离场动效在途位（requestCloseAdd 置位 / onSheetGone 清位）与开意图位
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 待添加载荷（选择器已返回、尚未 persist 的临时授权；关闭面板 = 放弃本次添加——载荷不即清
  //〔关闭动画期内容树恒在，规范 §1 关闭恒不复位〕，下次添加路径必然整组重写）
  @State private pendingUri: string = '';
  @State private pendingName: string = '';
  @State private pendingMode: number = MOUNT_MODE_READ_ONLY;
  // 半模态滚动感知（bindToScrollable 绑定）
  private sheetScroller: Scroller = new Scroller();
  // 卡「更多」菜单宿主（AppMenuHost 薄壳——节点 init/dispose 成对，域件见 MountCardMenu）
  private cardMenuHost: MountCardMenuHost = new MountCardMenuHost();
  // 改名弹窗与移除确认弹窗（组件成员位构造——坑7；动态文案经 open* 方法重建）
  private inputCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '',
      placeholder: '',
      confirmLabel: '保存',
      onConfirm: (text: string): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '',
      message: '',
      confirmLabel: '',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  // 进页装载（授权态现读校验）
  aboutToAppear(): void {
    // 卡菜单节点首建（getUIContext 需组件就绪故不在构造期）；初参为占位卡，弹出前必 rebuild 实参
    this.cardMenuHost.init(this.getUIContext(), this.cardMenuCallbacks(EMPTY_CARD));
    this.load();
  }

  // ── 装载与授权校验 ──
  // 进页：读清单 → 逐行 checkPersistentPermission → 失效警示 + 校验时点回写；校验失败/异常按
  // 「需重新授权」呈报（P0-1 不静默），单行回写失败不阻断整页
  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      if (!isReady()) {
        this.showToast('数据库尚未就绪，请稍后再试');
        return;
      }
      const rows: FolderMountRow[] = await queryFolderMounts();
      const views: MountCardView[] = [];
      for (const row of rows) {
        // 能力门不过的设备不校验（必失败，会把「设备不支持」误呈成「授权失效」）
        const granted: boolean = this.capable ? await this.checkGrant(row.dirUri, row.mode) : false;
        const now: number = Date.now();
        try {
          await updateFolderMountGrant(row.id, row.mode, row.dirUri, now,
            granted ? '' : '授权已失效');
        } catch (e) {
          hilog.error(DOMAIN, TAG, '挂载校验时点回写失败：%{public}s', (e as Error).message);
        }
        views.push({
          id: row.id,
          name: row.name,
          dirUri: row.dirUri,
          mode: row.mode,
          warningText: mountWarningLine(granted),
          needReauth: !granted
        });
      }
      if (this.departed) {
        return;
      }
      this.cards = views;
      this.loaded = true;
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '挂载清单装载失败：%{public}s', (e as Error).message);
      this.showToast('加载挂载列表失败，请重试');
    } finally {
      this.loading = false;
    }
  }

  // 授权存活探测（免权限版，API 17 起；异常按未授权呈报并留痕——探测失败不给假绿）
  private async checkGrant(uri: string, mode: number): Promise<boolean> {
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: mountModeMask(mode) };
      const result: boolean[] = await fileShare.checkPersistentPermission([policy]);
      return result.length > 0 && result[0];
    } catch (e) {
      hilog.error(DOMAIN, TAG, '持久授权探测异常：%{public}s', (e as Error).message);
      return false;
    }
  }

  // 持久化授权（添加 / 切换模式 / 重新授权三路共用；失败抛原始错误由调用方映射文案）
  private async persistGrant(uri: string, mode: number): Promise<void> {
    const policy: fileShare.PolicyInfo = { uri: uri, operationMode: mountModeMask(mode) };
    await fileShare.persistPermission([policy]);
  }

  // 撤销持久授权（切换模式 / 移除两路共用；尽力而为，失败留痕不静默——行侧动作不阻断）
  private async revokeGrantQuiet(uri: string, mode: number): Promise<void> {
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: mountModeMask(mode) };
      await fileShare.revokePermission([policy]);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '撤销持久授权未成功（放行行侧动作）：%{public}s',
        (e as Error).message);
    }
  }

  // 丢弃选择器留下的临时授权条目（deactivate——只删本次进程内可用性，不碰持久记录，与 revoke
  // 的区别见文件头）。尽力而为：失败只留痕，内核位停留宽位不影响功能
  private async deactivateGrantQuiet(uri: string, mode: number): Promise<void> {
    try {
      const policy: fileShare.PolicyInfo = { uri: uri, operationMode: mountModeMask(mode) };
      await fileShare.deactivatePermission([policy]);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '丢弃临时授权条目未成功（内核位维持旧宽位，不影响持久授权）：%{public}s',
        (e as Error).message);
    }
  }

  // 失败文案统一映射（code 13900001 + 逐 URI PolicyErrorCode 如实透传；库侧中文错原样出）
  private failureText(e: Object): string {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      e as BusinessError<Array<fileShare.PolicyErrorResult>>;
    const policyCode: number = this.firstPolicyCode(e);
    if (policyCode > 0) {
      // 逐 URI 原始原因留痕（system message 是现场诊断唯一原始线索，toast 只给友好文案）
      hilog.error(DOMAIN, TAG, '持久授权失败：code=%{public}d policyCode=%{public}d message=%{public}s',
        err.code, policyCode, this.firstPolicyMessage(e));
      return mountPolicyErrorText(err.code, policyCode);
    }
    if (typeof err.code === 'number' && err.code !== 0) {
      return '挂载操作失败（code ' + err.code + '）';
    }
    const message: string = (e as Error).message;
    return message !== '' ? message : '挂载操作失败，请重试';
  }

  private firstPolicyCode(e: Object): number {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      e as BusinessError<Array<fileShare.PolicyErrorResult>>;
    if (err.code === 13900001 && err.data !== undefined && err.data.length > 0) {
      return err.data[0].code;
    }
    return 0;
  }

  private firstPolicyMessage(e: Object): string {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      e as BusinessError<Array<fileShare.PolicyErrorResult>>;
    if (err.code === 13900001 && err.data !== undefined && err.data.length > 0) {
      return err.data[0].message;
    }
    return '';
  }

  // ── 添加流程（添加键 → 能力门 → 选择器 → 半模态 → persist → 落行）──
  private async onAddTap(): Promise<void> {
    if (!this.capable) {
      this.showToast('当前设备不支持选择文件夹，可以让助手在文件工作区里处理文件');
      return;
    }
    if (this.cards.length >= MOUNT_MAX_COUNT) {
      this.showToast('最多支持 ' + MOUNT_MAX_COUNT + ' 个挂载，先移除一个再添加');
      return;
    }
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const uri: string = await this.pickFolderUri();
      if (this.departed) {
        return;
      }
      if (uri === '') {
        return; // 用户取消，静默
      }
      for (const card of this.cards) {
        if (card.dirUri === uri) {
          this.showToast('这个文件夹已经挂载过了');
          return;
        }
      }
      // 载荷备好即开面板（persist 在确认时执行——必须与本次选择同会话完成，官方明示）
      this.pendingUri = uri;
      this.pendingName = mountNameFromUri(uri, '已选文件夹');
      this.pendingMode = MOUNT_MODE_READ_ONLY;
      this.openSheet();
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '打开文件夹选择器失败：%{public}s', (e as Error).message);
      this.showToast('打开文件夹选择失败，请重试');
    } finally {
      this.picking = false;
    }
  }

  // 拉系统 FOLDER 选择器（三路共用；返回 '' = 用户取消）
  private async pickFolderUri(): Promise<string> {
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      throw new Error('无法获取应用上下文');
    }
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    // maxSelectNumber = 1：只取 uris[0]（单目录）。FOLDER 模式下多选由 allowsMulFolderSelection
    // 管辖，本值同时满足全仓「每构造点显式设 maxSelectNumber」防线（assert-app-domain 89 组）
    options.maxSelectNumber = 1;
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
    const uris: string[] = await docPicker.select(options);
    return uris.length > 0 ? uris[0] : '';
  }

  // 面板确认添加：persist → 落行 → 程序化关面板 → 刷新。两段分离：persist 段失败 = 无新授权
  // 可撤、面板保持打开；落行段失败 = 系统侧授权成孤儿，走「先查后撤」补偿后再报错
  private async confirmAdd(): Promise<void> {
    if (this.addingMount) {
      return;
    }
    const uri: string = this.pendingUri;
    if (uri === '') {
      return;
    }
    const name: string = this.pendingName.trim();
    // 模式与名称在入口一次快照：persist 的 await 窗口内面板未关、chips 仍可点，直读 pendingMode
    // 会让「系统授权位 = 点确认时的值 / 落行 mode = await 后的新值」分叉
    const mode: number = this.pendingMode;
    const reject: string = mountNameRejectReason(name);
    if (reject !== '') {
      this.showToast(reject);
      return;
    }
    this.addingMount = true;
    try {
      await this.persistGrant(uri, mode);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      // persist 段失败：面板保持打开（可改名重试或关闭放弃）；本次无新授权可撤，不走补偿
      this.addingMount = false;
      hilog.error(DOMAIN, TAG, '添加挂载授权失败：%{public}s', (e as Error).message);
      this.showToast(this.failureText(e));
      return;
    }
    try {
      await addFolderMount(name, uri, mode);
      // 落行成功 → 丢弃选择器临时条目（失败路径不调它——补偿段 revoke 已连条目一并删）；
      // 丢弃属数据层清理照常完成——departed 判守只放在 UI 动作之前
      await this.deactivateGrantQuiet(uri, mode);
      if (this.departed) {
        return;
      }
      this.requestCloseAdd(); // 程序化关闭（落库成功、无暂存损失——规范 §1 负面清单）
      this.showToast('已添加挂载');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      // 落行段失败：系统侧本次授权已成孤儿——先查后撤补偿（见下），再如实报错
      hilog.error(DOMAIN, TAG, '添加挂载入库失败：%{public}s', (e as Error).message);
      await this.compensateOrphanGrant(uri, mode);
      if (this.departed) {
        return;
      }
      this.showToast(this.failureText(e));
    } finally {
      this.addingMount = false;
    }
  }

  // 孤儿授权补偿（先查后撤）：查无同 dirUri 行才撤回本次授权（有 = 并发竞态被承接，撤则反伤；
  // 对账失败也不撤）。补偿自带 try：任何异常只留痕，不得顶替原始失败 toast
  private async compensateOrphanGrant(uri: string, mode: number): Promise<void> {
    try {
      const rows: FolderMountRow[] = await queryFolderMounts();
      for (const row of rows) {
        if (row.dirUri === uri) {
          return;
        }
      }
      await this.revokeGrantQuiet(uri, mode);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '孤儿授权补偿未完成（残留维持已评估接受口径）：%{public}s',
        (e as Error).message);
    }
  }

  // ── 卡操作：进浏览页 / 更多菜单（重命名 + 模式切换）/ 重新授权 / 移除 ──
  // 打开键回调（正常态进浏览页；失效态不跳页只给 toast 指引——进页必落失效卡）。★ 卡体
  // 空白热区已拆除，本方法唯一入口 = 卡内「打开」键；其余卡内件各自持 onClick
  private onCardTap(card: MountCardView): void {
    if (card.needReauth) {
      this.showToast('该挂载需重新授权后才能浏览');
      return;
    }
    const param: MountBrowseParam = { mountId: card.id };
    this.pathStack.pushPathByName(ROUTE_MOUNT_BROWSE_PAGE, param);
  }

  // 卡内「更多」键上行：菜单内容与动作按点击当刻卡数据现建（模式 / 失效态不吃首帧快照）
  private onCardMore(card: MountCardView): void {
    this.cardMenuHost.open(this.getUIContext(), this.cardMenuCallbacks(card), this.immersiveLevel);
  }

  // 菜单回调装配（init 占位与 open 实参同一装配口——锚点 id 在卡件按键拼接前缀 + 卡 id）
  private cardMenuCallbacks(card: MountCardView): MountCardMenuCallbacks {
    return {
      id: card.id,
      mode: card.mode,
      needReauth: card.needReauth,
      onRename: (): void => {
        this.openRenameDialog(card);
      },
      onSwitchMode: (): void => {
        this.onSwitchMode(card);
      }
    };
  }

  private openRenameDialog(card: MountCardView): void {
    this.inputCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名挂载',
        initialText: card.name,
        confirmLabel: '保存',
        maxLength: MOUNT_NAME_MAX_CHARS,
        onConfirm: (text: string): void => {
          this.doRename(card, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.inputCtrl.open();
  }

  private async doRename(card: MountCardView, rawName: string): Promise<void> {
    const name: string = rawName.trim();
    const reject: string = mountNameRejectReason(name);
    if (reject !== '') {
      this.showToast(reject);
      return;
    }
    try {
      await renameFolderMount(card.id, name);
      if (this.departed) {
        return;
      }
      this.patchCard(card.id, name);
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '挂载改名失败：%{public}s', (e as Error).message);
      this.showToast(this.failureText(e));
    }
  }

  // 切换模式（只读 ↔ 读写）：系统约束变更持久化模式必须重拉选择器拿新临时授权再 persist，故必然
  // 再选一次文件夹。★ 无返回值——分段胶囊退役后卡面无「待复位」状态，取消 / 选错目录 / 失败一律
  // 由 toast 如实报，并 reload 把界面拉回库内真实模式。
  // ★ 次序纪律（真机实锤）：**persist 新位在前、revoke 旧位在后**——反序会把选择器刚建的临时
  // 授权连根删掉，persist 报 PolicyErrorCode 1 并把挂载打成授权真空（详见文件头）；revoke 失败
  // 只留痕（新位可用性不受影响）
  private async onSwitchMode(card: MountCardView): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      this.showToast('系统要求切换访问模式时重新选择这个文件夹');
      const uri: string = await this.pickFolderUri();
      if (this.departed) {
        return;
      }
      if (uri === '') {
        return;
      }
      if (uri !== card.dirUri) {
        this.showToast('请选择原来的文件夹「' + card.name + '」');
        return;
      }
      const nextMode: number = mountOtherMode(card.mode);
      await this.persistGrant(uri, nextMode); // ① 先落新模式位（此刻临时授权最新鲜）
      await this.deactivateGrantQuiet(uri, nextMode); // ② 丢弃临时条目（内核位交下次按行模式激活）
      await this.revokeGrantQuiet(uri, card.mode); // ③ 再撤旧模式位（尽力）
      await updateFolderMountGrant(card.id, nextMode, uri, Date.now(), '');
      if (this.departed) {
        return;
      }
      this.showToast('已切换为' + mountModeLabel(nextMode));
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      // persist 段失败 = 旧授权原样未动（本次未撤任何位），重载如实呈报原模式
      hilog.error(DOMAIN, TAG, '切换挂载模式失败：%{public}s', (e as Error).message);
      this.showToast(this.failureText(e));
      this.load();
    } finally {
      this.picking = false;
    }
  }

  // 重新授权（失效态操作行键；接受新 URI 并回写 dirUri，查重排除本行）。★ 次序同 onSwitchMode，
  // 且**同路径不撤旧位**（撤会连本次新授权一起删）；异路径才清理旧记录（尽力，旧记录本已失效）
  private async onReauth(card: MountCardView): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const uri: string = await this.pickFolderUri();
      if (this.departed) {
        return;
      }
      if (uri === '') {
        return;
      }
      for (const other of this.cards) {
        if (other.id !== card.id && other.dirUri === uri) {
          this.showToast('这个文件夹已经挂载过了');
          return;
        }
      }
      await this.persistGrant(uri, card.mode); // ① 先落授权（同路径同模式在系统侧幂等）
      await this.deactivateGrantQuiet(uri, card.mode); // ② 丢弃临时条目（内核位交下次按行模式激活）
      if (uri !== card.dirUri) {
        await this.revokeGrantQuiet(card.dirUri, card.mode); // ③ 旧路径失效残留清理（尽力）
      }
      await updateFolderMountGrant(card.id, card.mode, uri, Date.now(), '');
      if (this.departed) {
        return;
      }
      this.showToast('已重新授权');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '重新授权失败：%{public}s', (e as Error).message);
      this.showToast(this.failureText(e));
      this.load();
    } finally {
      this.picking = false;
    }
  }

  private openRemoveConfirm(card: MountCardView): void {
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '移除挂载',
        message: '将移除「' + card.name + '」。AI 将无法再访问这个文件夹，文件夹里的文件不会被删除。',
        confirmLabel: '移除',
        onConfirm: (): void => {
          this.doRemove(card);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private async doRemove(card: MountCardView): Promise<void> {
    if (this.removing) {
      return;
    }
    this.removing = true;
    try {
      // 双模式位全清：历史失败路径可能遗留另一模式位记录（系统按（tokenid, 路径, 模式）逐条存）——
      // 只撤行模式位会残留可访问授权；撤授权与删行为数据层（成对释放）照常完成
      await this.revokeGrantQuiet(card.dirUri, card.mode);
      await this.revokeGrantQuiet(card.dirUri, mountOtherMode(card.mode));
      await removeFolderMount(card.id);
      if (this.departed) {
        return;
      }
      this.showToast('已移除挂载');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '移除挂载失败：%{public}s', (e as Error).message);
      this.showToast('移除失败，请重试');
    } finally {
      this.removing = false;
    }
  }

  // 就地替换一行（改名用——@State 数组整组重赋驱动 ForEach 键变重建；未变字段传当前值）
  private patchCard(id: number, name: string): void {
    const next: MountCardView[] = [];
    for (const card of this.cards) {
      if (card.id === id) {
        next.push({ id: card.id, name: name, dirUri: card.dirUri, mode: card.mode,
          warningText: card.warningText, needReauth: card.needReauth });
      } else {
        next.push(card);
      }
    }
    this.cards = next;
  }

  // ── 添加半模态：关闭-再开五件式（全文件唯一写可见性 true 处 = applyOpen，329 组守）──
  private openSheet(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 离场动效在途：只记开意图（onSheetGone 正路 / onSheetVisibleChanged 兜底补开）
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.sheetShow = true;
  }

  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（标题栏 xmark 经 onClose、手势/蒙层经 onWillDismiss 两路同调）：先清开意图 →
  // 置在途位 → 再写可见性，序不可倒置
  private requestCloseAdd(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 添加确认键（本面板唯一收口动作 = 主操作键形制：primary 强调蓝 + 恒白字，四件套双态）。
  // ★ 键宽恒挂 CARD_PANEL_WIDTH（决明报障「添加键宽度不对」——自然宽度居中读作小胶囊键）
  @Builder
  AddConfirmButton(label: string, enabled: boolean, action: () => void) {
    Button(label)
      .width(CARD_PANEL_WIDTH)
      .fontColor(fallbackButtonFont(this.contentFallback, true))
      .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .enabled(enabled)
      .onClick((): void => {
        action();
      })
  }

  // 模式选项 chip（选项非按钮——纯 Text + 自绘圆角底；选中实底强调蓝 + 白字）
  @Builder
  ModeChip(label: string, mode: number) {
    Text(label)
      .fontSize(14)
      .fontColor(selectChipTextColor(this.pendingMode === mode, this.appColorMode))
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(selectChipBg(this.pendingMode === mode, this.appColorMode))
      .border({ width: 1, color: selectChipBorderColor(this.pendingMode === mode) })
      .onClick((): void => {
        this.pendingMode = mode;
      })
  }

  // 页首 info 蓝卡（形制单源 InfoCard.ets；正文 = MOUNT_INFO_TEXT 静态双权限口径）
  @Builder
  InfoCardSlot() {
    InfoCard({ text: MOUNT_INFO_TEXT })
  }

  // 区头行（标题 + 数量；首载完成前不显示 0 防空态闪显；添加入口唯一 = 标题栏「＋」）
  @Builder
  ListHeader() {
    Text(this.loaded ? '我的挂载 · ' + this.cards.length : '我的挂载')
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardTitleColor())
      .width(CARD_PANEL_WIDTH)
  }

  // 单个挂载卡（卡面整体迁 MountManageCard.ets；本页只下发数据与动作回调）

  // 空态（居中引导；添加入口唯一收标题栏「＋」，文案指路不挂键）
  @Builder
  EmptyState() {
    Column({ space: 12 }) {
      Text('还没有挂载。点右上角的「＋」选择一个文件夹，授权给 AI 后助手就能读取和编辑里面的文件。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .textAlign(TextAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding({ top: 32, bottom: 32 })
    .alignItems(HorizontalAlign.Center)
  }

  // 设备不支持降级卡（双 canIUse 门不过——说明 + 附件指引）
  @Builder
  UnsupportedCard() {
    Column({ space: 8 }) {
      Text('当前设备不支持文件夹挂载')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
      Text('可以先把文件用对话附件发给助手，让助手保存到文件工作区里处理。')
        .fontSize(13)
        .fontColor(cardDescColor())
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        this.InfoCardSlot()
        this.ListHeader()
        if (!this.capable) {
          this.UnsupportedCard()
        } else if (this.loaded && this.cards.length === 0) {
          this.EmptyState()
        } else if (this.cards.length > 0) {
          // 行键 = mountCardKey 五成分（id / 名 / URI / 模式 / 警示文案；needReauth 由警示文案派生）
          ForEach(this.cards, (card: MountCardView): void => {
            MountManageCard({
              card: card,
              menuAnchorId: MOUNT_CARD_MENU_ID_PREFIX + card.id,
              onOpen: (): void => {
                this.onCardTap(card);
              },
              onReauth: (): void => {
                this.onReauth(card);
              },
              onSwitchMode: (): void => {
                this.onSwitchMode(card);
              },
              onRemove: (): void => {
                this.openRemoveConfirm(card);
              },
              onMore: (): void => {
                this.onCardMore(card);
              }
            })
          }, (card: MountCardView): string => mountCardKey(card.id, card.name, card.dirUri,
            card.mode, card.warningText))
          if (this.cards.length >= MOUNT_MAX_COUNT) {
            Text('已达挂载数量上限，移除一个后可再添加')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
              .textAlign(TextAlign.Start)
          }
        }
        // 首载瞬间（!loaded 且零卡）不渲染中间区——块表读取毫秒级，空态闪显反而更差
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    // 滚动内容穿透标题栏背后被渐变模糊采样（PageShell 蒙层需有内容可透）
    .clip(false)
  }

  // 添加半模态内容（名称 + 模式 + 说明小字在操作键上方〔宪法「功能设置卡布局次序」〕+ 确认键；
  // 表单以 $$ 直绑页态 pendingName / pendingMode，免 @Prop 回填时序问题）
  @Builder
  AddSheet() {
    HdsNavigation() {
      Scroll(this.sheetScroller) {
        Column({ space: CARD_SPACING }) {
          // 名称卡
          Column({ space: 8 }) {
            Text('挂载名称')
              .fontSize(14)
              .fontColor(cardTitleColor())
            TextInput({ text: $$this.pendingName, placeholder: '例如 资料' })
              .fontSize(15)
              .maxLength(MOUNT_NAME_MAX_CHARS)
              .width('100%')
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          // 模式卡（options chips）
          Column({ space: 10 }) {
            Text('访问模式')
              .fontSize(14)
              .fontColor(cardTitleColor())
            Row({ space: 8 }) {
              this.ModeChip('只读', MOUNT_MODE_READ_ONLY)
              this.ModeChip('读写', MOUNT_MODE_READ_WRITE)
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          // 说明小字（操作键行上方——宪法「功能设置卡布局次序」）
          Text('只读时 AI 只能查看与读取文件。读写时还能新建、修改与删除文件，改动前都会先' +
            '征求你的同意。删除的内容会放进系统文件管理的回收站。无论哪种模式，AI 都无法' +
            '移动文件。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .textAlign(TextAlign.Start)

          // 确认键（主操作键形制 + 满宽，与上方两张表单卡同宽，见 AddConfirmButton 注释）
          this.AddConfirmButton('添加', !this.addingMount, (): void => {
            this.confirmAdd();
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('添加挂载', '', (): void => {
      this.requestCloseAdd();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.sheetScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  // 标题栏右上角「＋」单圆键（添加入口唯一）。形制 = TitleBarRoundKey 共用件（几何单源，禁手搓）；
  // 经 titleBarStack 覆盖层承载（keepStackTitle 保主标题）
  @Builder
  TitleBarAddKey() {
    Row() {
      TitleBarRoundKey({
        icon: $r('sys.symbol.plus'),
        label: '添加挂载',
        immersiveLevel: this.immersiveLevel,
        onTap: (): void => {
          this.onAddTap();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    // 页面骨架由 PageShell 提供；bindSheet 挂页面根（规范-半模态 §1 挂点判据三条全过）
    PageShell({
      title: SETTING_TITLE_MOUNT,
      titleBarStack: (): void => {
        this.TitleBarAddKey();
      },
      keepStackTitle: true,
      content: () => {
        this.Content()
      }
    })
      .bindSheet($$this.sheetShow, this.AddSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseAdd();
        },
        undefined, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.cardMenuHost.dispose(); // 与 init 成对（ComponentContent 不 dispose 泄漏——SDK d.ts NOTE）
  }
}
