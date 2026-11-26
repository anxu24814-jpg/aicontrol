// 「数据与同步」二级页（自包 PageShell）。页顶分段胶囊三段：「本机备份」= 备份内容卡 + 导出卡 +
// 从备份恢复卡，「WebDAV 同步」= WebDAV 卡，「S3 同步」= S3SyncCard（独立文件，宪法「新增功能域
// 一律先拆」）。承载照先例 = PageShell.titleBarBottom 下方带（恒光感）；切段只换段内卡、
// 页级状态不重置。
// · 导出备份：9 表全行 + 偏好分域 zip（ExportImport.exportAllData）→ 系统文档保存面板
//   （picker.save）用户选位置落盘。「包含密钥」开关驱动两档产物：关闭 = 包内零明文；开启 = 另产
//   口令加密 secrets.enc（Key 池 + 引擎密钥 + 余额密钥与请求头），口令入口 = InputDialog 密码型。
// · 从备份恢复：先弹冲突策略两键框（跳过合并 / 覆盖恢复）→ 选 zip → 沙箱中转 → importFromZip
//   （manifest 闸门 + id 冲突两态策略 + 偏好回写 + 密钥档解密回填）→ 摘要呈报 + 会话列表刷新
//   广播；包内带 secrets.enc 时先要口令（取消 = 零副作用）。
// · WebDAV 同步：连接配置走 Preferences 自持（独立偏好文件，不动 persistProp 注册链），密码例外
//   走 Asset（KeyStore 单例条目）+ 测试连接 / 上传备份 / 恢复到本机。远端 = 日期档
//   aicontrol_backup_YYYYMMDD.zip，保留最近 5 个上传日、上传后自动清更老候选（WebDavApi 头注释）。
// · S3 同步：S3 兼容对象存储同语义镜像——配置/动作链在 S3SyncCard 自含，传输面 common/S3Api；
//   SecretAccessKey 走 Asset，含密钥开关经 @Link 挂页面单例。
// ★ 两云卡共用件（summaryLine / backupDateLabel / cleanupExport / askImportStrategy / SyncField）
//   迁 SyncShared.ets 单源——本页只消费，禁第三套复制拼装。
// ★ 含密钥开关只有一个、本机导出与 WebDAV / S3 上传共用（决明拍板）：三条路径是同一份产物，
//   多开关会造「本地带密钥、云上没带」的分叉；云通道差异化处置 = 上传前显式确认，不加第二开关。
// 行内操作键光感四件套：主操作 primary=true 官方强调蓝，次操作 primary=false 官方灰。
// 隐私边界：不含密钥档 = 包内零明文（providers 三个明文敏感列由导出侧置空）；含密钥档 = 明文只进
// 加密件（加密实现单一来源 = ProviderShare，本页不做第二套）；WebDAV 密码恒不进包。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { PageShell } from '../../common/PageShell';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { PageTopSegmentBand } from '../SegmentBar';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial, tierButtonBg, tierButtonFont, tierButtonMaterial } from '../../common/ImmersiveLevel';
import { exportAllData, ExportSummary, ImportStrategy,
  ImportSummary } from '../../common/store/ExportImport';
import { ROUTE_DS_HISTORY_IMPORT_PAGE } from '../../common/RouteNames';
// 导入链外迁 ExportImportApply（函数名不变）
import { importFromZip } from '../../common/store/ExportImportApply';
import { askImportStrategy, backupDateLabel, cleanupExport, summaryLine,
  SyncField } from './SyncShared';
import { S3SyncCard } from './S3SyncCard';
import { loadDavPassword, removeDavPassword, saveDavPassword } from '../../common/store/KeyStore';
import { downloadLatestBackup, pruneOldBackups, probe, recordRemoteBackup, uploadBackup,
  WebDavConfig } from '../../common/WebDavApi';
import { copyFileExact } from '../../common/ImageEditUtil';
import { notifyBgChanged } from '../../common/BgRefreshBus';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import { InputDialog } from '../chat/InputDialog';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';

// WebDAV 偏好文件与键（页面自持，不动 persistProp 注册链）：preferences 只存地址/账号/目录；
// 密码走 Asset，KEY_PASSWORD 为遗留键仅迁移读 + 删。密码明文不进任何日志/导出（红线）
const DAV_PREFS_FILE: string = 'webdav_config';
const KEY_BASE_URL: string = 'baseUrl';
const KEY_USERNAME: string = 'username';
const KEY_PASSWORD: string = 'password'; // 遗留键：迁移读 + 删，不再写入
const KEY_DIR_NAME: string = 'dirName';
const KEY_LAST_REMOTE_NAME: string = 'lastRemoteName'; // 恢复链①环——本机最近一次成功上传的远端档名
const DEFAULT_DIR_NAME: string = 'aicontrol';

// 卡片说明文案（导出范围与密钥边界——用户须知）
const EXPORT_NOTE: string = '包含全部会话、消息、配置与偏好。不含密钥时，恢复后需重新填写 API Key。';
const RESTORE_NOTE: string = '跳过只导入本机没有的记录。覆盖会替换本机同 id 记录与偏好设置。用较旧备份覆盖时，缺失设置恢复默认。';
// 含密钥开关说明（开关管三条路径，独立成卡才不会被读成只影响本机导出）
const SCOPE_NOTE: string = '导出、WebDAV 与 S3 共用本开关。关闭后包内不含明文密钥，恢复后需重新填写。';

@Component
export struct DataSyncPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部/底部留白（vp，PageMapBuilder 注入）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 深浅色（回退卡底）+ 光感档位（按钮簇）
  @StorageProp('appColorMode') appColorMode: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = 本组件按钮官方实底（新规范下内容区材质不生效）；false = 原材质光感；
  // @StorageProp 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // WebDAV 表单（@State 驱动输入框；加载自 preferences）
  @State private davUrl: string = '';
  @State private davUser: string = '';
  @State private davPass: string = '';
  @State private davDir: string = DEFAULT_DIR_NAME;
  @State private davStatus: string = ''; // 同步动作状态行（'' = 无）
  @State private busy: boolean = false; // 动作互斥（导出/导入/同步三链共用）
  // 上传确认弹窗控制器（组件成员位——坑7；askUploadConfirm 内运行时重建 + open）
  private confirmCtrl: CustomDialogController | null = null;
  // 含密钥开关：三条路径共用，默认关 = 包内零明文（最保守档）；开启后导出/上传前收一次口令
  @State private includeSecrets: boolean = false;
  // 口令弹窗控制器（每次弹出重新构造——坑7：Controller 须成员位构造）
  private passCtrl: CustomDialogController | null = null;

  // 分段选中（0 本机备份 / 1 WebDAV 同步 / 2 S3 同步）
  @State private segIndex: number = 0;

  // 标题栏下方带承载（HDS 路径；几何与带内下移量单源 = 公共件 PageTopSegmentBand）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.segItems,
      selectedIndex: $segIndex
    })
  }
  private segItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '本机备份' },
    { text: 'WebDAV 同步' },
    { text: 'S3 同步' }
  ]);

  // 口令输入弹窗（resolve 文本 / 取消 resolve null——Promise 恒 settle；InputDialog 密码型，
  // 空口令被拦）。★ 两个取消口都要接：onCancel = 弹窗内「取消」键（不触发控制器级 cancel——
  // 原只接 cancel 时此键让 Promise 永挂、busy 卡死）；cancel = 返回键/点遮罩/Esc
  private askPassphrase(title: string, placeholder: string): Promise<string | null> {
    return new Promise<string | null>((resolve: (value: string | null) => void) => {
      this.passCtrl = new CustomDialogController({
        systemMaterial: overlayMaterial(),
        builder: InputDialog({
          title: title,
          initialText: '',
          placeholder: placeholder,
          confirmLabel: '确认',
          password: true,
          onConfirm: (text: string): void => {
            resolve(text);
          },
          onCancel: (): void => {
            resolve(null);
          }
        }),
        autoCancel: true,
        cancel: (): void => {
          resolve(null);
        },
        alignment: DialogAlignment.Center
      });
      this.passCtrl.open();
    });
  }

  aboutToAppear(): void {
    // 启动级残留清扫在 EntryAbility.onCreate——本页只做表单回填
    this.loadDavConfig();
  }

  // ── WebDAV 配置（preferences 读写）──

  private async davStore(): Promise<preferences.Preferences> {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return preferences.getPreferences(ctx, DAV_PREFS_FILE);
  }

  private async loadDavConfig(): Promise<void> {
    try {
      const store: preferences.Preferences = await this.davStore();
      if (this.departed) {
        return;
      }
      // getSync + 显式收窄（preferences.get 返回 ValueType 联合——arkts 联合收窄）
      this.davUrl = store.getSync(KEY_BASE_URL, '') as string;
      this.davUser = store.getSync(KEY_USERNAME, '') as string;
      this.davDir = store.getSync(KEY_DIR_NAME, DEFAULT_DIR_NAME) as string;
      // 密码自 Asset 回显——异步晚到不阻塞表单，@State 就绪即渲
      let pass: string = await loadDavPassword();
      // 一次性存量迁移：旧版密码留在 preferences 时搬入 Asset 并删旧键（只在「Asset 空且旧键
      // 非空」触发，重跑幂等）
      const legacy: string = store.getSync(KEY_PASSWORD, '') as string;
      if (pass === '' && legacy !== '') {
        await saveDavPassword(legacy);
        store.deleteSync(KEY_PASSWORD);
        await store.flush();
        pass = legacy;
      }
      if (this.departed) {
        return;
      }
      this.davPass = pass;
    } catch (e) {
      // 配置读取失败 = 初次使用默认空表单（不阻断）
    }
  }

  private async saveDavConfig(): Promise<void> {
    try {
      const store: preferences.Preferences = await this.davStore();
      store.putSync(KEY_BASE_URL, this.davUrl.trim());
      store.putSync(KEY_USERNAME, this.davUser.trim());
      store.putSync(KEY_DIR_NAME, this.davDir.trim() !== '' ? this.davDir.trim() : DEFAULT_DIR_NAME);
      // 密码只进 Asset；清空保存 = 删条目，preferences 不留空串残迹
      if (this.davPass !== '') {
        await saveDavPassword(this.davPass);
      } else {
        await removeDavPassword();
      }
      await store.flush();
    } catch (e) {
      this.toast('配置保存失败：' + (e as Error).message);
    }
  }

  private davConfig(): WebDavConfig {
    return {
      baseUrl: this.davUrl.trim(),
      username: this.davUser.trim(),
      password: this.davPass,
      dirName: this.davDir.trim() !== '' ? this.davDir.trim() : DEFAULT_DIR_NAME
    };
  }

  private davConfigOk(): boolean {
    return this.davUrl.trim() !== '' && this.davUser.trim() !== '' && this.davPass !== '';
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 会话列表刷新广播（坑3 计数器口径）。与导入成败解耦——密钥档回填在全部落库之后，失败路径
  // 不广播会让「数据已进库而列表不刷」
  private broadcastSessionReload(): void {
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }

  // 四件共用件已迁 SyncShared.ets 单源（S3SyncCard 同消费，禁第三套复制拼装）

  // ── 动作链 ──

  // 导出备份：collect → zip（cacheDir 临时）→ 保存面板 → 拷到用户选位 → 清临时
  private async doExport(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    try {
      // 含密钥档先收口令（用户取消 = 静默放弃，零产物；口令丢失无法恢复已在占位提示明示）
      let passphrase: string = '';
      if (this.includeSecrets) {
        const pass: string | null = await this.askPassphrase('设置备份口令',
          '口令加密文件内容，导入时需输入（丢失无法恢复）');
        if (pass === null) {
          return; // 用户取消
        }
        passphrase = pass;
      }
      // 执行段遮罩（打包期间盖应用级浮层 + 拦返回——口令弹窗 / 保存面板等交互段不盖，
      // BusyOverlay 头注释）
      const busyToken: number = bumpBusyOverlay('正在导出备份');
      const summary: ExportSummary = await exportAllData(ctx, this.includeSecrets, passphrase)
        .finally((): void => {
          releaseBusyOverlay(busyToken);
        });
      // 系统文档保存面板（用户选落盘位置——免权限；DocumentViewPicker.save 官方链）
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [summary.fileName];
      const uris: Array<string> = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        cleanupExport(ctx, summary.fileName);
        return; // 用户取消——临时 zip 清掉即退
      }
      // uri 字符串直传 fs.copyFileSync 不可靠（真机实锤「路径或文件不存在」）——统一走
      // copyFileExact 的 fd 链路
      copyFileExact(summary.path, uris[0]);
      cleanupExport(ctx, summary.fileName);
      const line: string = summaryLine(summary, true);
      const secure: string = this.includeSecrets ? '，已带上密钥并口令加密' : '';
      if (this.departed) {
        return;
      }
      this.toast(`备份已保存${line !== '' ? '：' + line : ''}${secure}`);
    } catch (e) {
      this.toast('导出失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  // 「导入 DeepSeek 对话」入口 push（三级页三态单页自含——选包/校验/应用；push 无参）
  private pushDsImport(): void {
    this.pathStack.pushPathByName(ROUTE_DS_HISTORY_IMPORT_PAGE, null);
  }

  // 冲突策略弹窗与导出临时产物清理已迁 SyncShared.ets 单源

  // 从备份恢复：选 zip → 沙箱中转 → 导入 → 刷新广播
  private async doImport(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    const tempZip: string = ctx.cacheDir + '/import_upload_tmp.zip';
    try {
      // B2：动作入口、选文件之前先定冲突策略（取消零副作用——finally 走临时文件清理与 busy 释放）
      const strategy: ImportStrategy | null = await askImportStrategy(this.getUIContext());
      if (strategy === null) {
        return; // 用户取消
      }
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 恢复 = 单备份操作（冲突策略也只问一次）：不设 maxSelectNumber 时系统面板默认多选，
      // 除首个外静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (uris.length === 0) {
        return; // 用户取消
      }
      copyFileExact(uris[0], tempZip);
      // 密钥档口令回调（包内含 secrets.enc 时必调；取消 = 域内抛「已取消导入」，尚未写库 = 零
      // 副作用）。执行段遮罩盖浮层 + 拦返回，口令弹窗在窗口层浮于遮罩之上
      const busyToken: number = bumpBusyOverlay('正在恢复备份');
      const summary: ImportSummary = await importFromZip(ctx, tempZip, strategy,
        (): Promise<string | null> =>
          this.askPassphrase('输入文件口令', '该文件含密钥，已口令加密'))
        .finally((): void => {
          releaseBusyOverlay(busyToken);
        });
      this.broadcastSessionReload();
      // 背景直达刷新：备份可含 bgSessionOnly 覆盖值（偏好回写走 AppStorage），恢复成功即点名全部
      // 存活实例重读——一级页无 onShown 自补，不通知则背景停留旧态至重启
      notifyBgChanged();
      // line 含行级失败分档（summaryLine 单源，此处不另拼）
      const line: string = summaryLine(summary, false);
      const prefInfo: string = summary.prefCount > 0 ? `，恢复设置 ${summary.prefCount} 项` : '';
      // 偏好写入走 AppStorage（@StorageProp 订阅页自动刷；用 @State 快照读的页面不刷）——摘要
      // 提示重进页面
      const prefTip: string = summary.prefCount > 0 ? '。部分设置需重进页面生效' : '';
      // 密钥档分档文案：部分密钥未写入时如实呈报——数据与设置已恢复、仅密钥须重填，不再让用户
      // 误以为整体失败；页名用规范名（与服务商管理 / 联网搜索及帮助中心措辞一致）
      const secretTip: string = summary.secretFailures > 0 ?
        `。有 ${summary.secretFailures} 项密钥未写入，请到服务商管理或联网搜索页重填` : '';
      // 图域逐会话失败如实分档：图域导入以会话为单元容错，单会话失败不炸整批——按「有几个会话
      // 的分支没进来」直说（与 parseFailed 同口径）
      const graphTip: string = summary.graphFailedSessions > 0 ?
        `。有 ${summary.graphFailedSessions} 个会话的分支未导入，请重新导出备份后再试` : '';
      if (this.departed) {
        return;
      }
      this.toast(`导入完成${line !== '' ? '：' + line : ''}${prefInfo}` +
        (strategy === 'overwrite' ?
          (summary.totalOverwritten > 0 ? `（覆盖已存在 ${summary.totalOverwritten} 条）` : '') :
          (summary.totalSkipped > 0 ? `（跳过已存在 ${summary.totalSkipped} 条）` : '')) +
        prefTip + secretTip + graphTip);
    } catch (e) {
      const msg: string = (e as Error).message;
      if (msg !== '已取消导入') { // 口令弹窗取消 = 零写入无需刷新（正常取消路径，静默）
        // 其余失败点在写库前后皆有可能——刷新照发：零写入多发一次无害，已写入漏发才误导
        this.broadcastSessionReload();
        if (this.departed) {
          return;
        }
        this.toast('恢复失败：' + msg);
      }
    } finally {
      try {
        fs.unlinkSync(tempZip);
      } catch (e) {
        // 不存在 = 目标状态
      }
      this.busy = false;
    }
  }

  private async doDavTest(): Promise<void> {
    if (this.busy || !this.davConfigOk()) {
      if (!this.davConfigOk()) {
        this.toast('请先填写服务器地址、账号与密码');
      }
      return;
    }
    this.busy = true;
    this.davStatus = '正在测试连接…';
    try {
      await probe(this.davConfig());
      await this.saveDavConfig();
      if (this.departed) {
        return;
      }
      this.davStatus = '连接成功，配置已保存';
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.davStatus = '连接失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  // 上传确认弹窗：ConfirmDialog 两键（NORMAL 不配红；取消/遮罩/返回键三路关闭均 = 零动作放弃）。
  // onWillDismiss 桥接遮罩/返回键路径（注册后须 action.dismiss() 放行；autoCancel 直关不进回调，
  // 缺桥接则 Promise 永挂）；settled 单次闸防 dismiss 与回调竞态双 resolve
  private askUploadConfirm(): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      let settled: boolean = false;
      const settle = (value: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(value);
      };
      this.confirmCtrl = new CustomDialogController({
        systemMaterial: overlayMaterial(),
        builder: ConfirmDialog({
          title: '上传到 WebDAV',
          message: this.includeSecrets ?
            '本次备份包含密钥，已口令加密，将上传到你的 WebDAV 服务器。口令请自行保管，丢失后无法恢复。' :
            '本次备份不包含密钥，将上传到你的 WebDAV 服务器。在新设备恢复后需要重新填写密钥。',
          confirmLabel: '继续上传',
          confirmTone: ConfirmDialogTone.NORMAL,
          onCancel: (): void => {
            settle(false);
          },
          onConfirm: (): void => {
            settle(true);
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          settle(false);
        }
      });
      this.confirmCtrl.open();
    });
  }

  private async doDavUpload(): Promise<void> {
    if (this.busy || !this.davConfigOk()) {
      if (!this.davConfigOk()) {
        this.toast('请先填写服务器地址、账号与密码');
      }
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    this.davStatus = '正在打包并上传…';
    try {
      // 上传前显式确认（不加第二开关，改为让用户明确知道这次带不带密钥、传到哪；取消 = 零动作）
      const confirmed: boolean = await this.askUploadConfirm();
      if (this.departed) {
        return;
      }
      if (!confirmed) {
        this.davStatus = ''; // 用户取消（取消键/遮罩/返回键三路同语义）
        return;
      }
      let passphrase: string = '';
      if (this.includeSecrets) {
        const pass: string | null = await this.askPassphrase('设置备份口令',
          '口令加密文件内容，恢复时需输入（丢失无法恢复）');
        if (this.departed) {
          return;
        }
        if (pass === null) {
          this.davStatus = '';
          return; // 用户取消
        }
        passphrase = pass;
      }
      // 执行段遮罩：打包→上传→登记→清理全程盖浮层 + 拦返回（多 await 段用嵌套 try/finally）
      const busyToken: number = bumpBusyOverlay('正在上传备份');
      try {
        const summary: ExportSummary = await exportAllData(ctx, this.includeSecrets, passphrase);
        if (this.departed) {
          return;
        }
        try {
          const remoteName: string = await uploadBackup(this.davConfig(), summary.path);
          // 记录本机最近上传档名（恢复链①环——传输层不读 preferences，页面层持久化）。数据层写
          // 照常完成，判守只放在 UI 状态与 toast 之前
          const store: preferences.Preferences = await this.davStore();
          store.putSync(KEY_LAST_REMOTE_NAME, remoteName);
          await store.flush();
          if (this.departed) {
            return;
          }
          const line: string = summaryLine(summary, true);
          this.davStatus = `上传完成（${line}），正在清理旧备份…`;
          await this.saveDavConfig();
          // 远端索引登记（恢复发现优先读 manifest；写失败只留痕不阻断；返回保护集交清理跳过）——
          // 数据层写照常完成，页面已亡也做完
          const protectedNames: string[] = await recordRemoteBackup(this.davConfig(), remoteName);
          // 滚动清理更老日期档（尽力而为——内部全吞，恒正常返回）
          await pruneOldBackups(this.davConfig(), protectedNames);
          if (this.departed) {
            return;
          }
          this.davStatus = `上传完成（${line}）`;
        } finally {
          cleanupExport(ctx, summary.fileName);
        }
      } finally {
        releaseBusyOverlay(busyToken);
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.davStatus = '上传失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async doDavRestore(): Promise<void> {
    if (this.busy || !this.davConfigOk()) {
      if (!this.davConfigOk()) {
        this.toast('请先填写服务器地址、账号与密码');
      }
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    const tempZip: string = ctx.cacheDir + '/webdav_download_tmp.zip';
    try {
      // B2：下载之前先定冲突策略（避免选中策略前白下载一份大包；取消零副作用——davStatus 保留原值）
      const strategy: ImportStrategy | null = await askImportStrategy(this.getUIContext());
      if (this.departed) {
        return;
      }
      if (strategy === null) {
        return; // 用户取消
      }
      this.davStatus = '正在下载并恢复…';
      // 执行段遮罩：下载→导入写库全程盖浮层 + 拦返回（口令弹窗在窗口层浮于遮罩之上）
      const busyToken: number = bumpBusyOverlay('正在恢复备份');
      try {
        const store: preferences.Preferences = await this.davStore();
        if (this.departed) {
          return;
        }
        const lastName: string = store.getSync(KEY_LAST_REMOTE_NAME, '') as string;
        const remoteName: string = await downloadLatestBackup(this.davConfig(), tempZip, lastName);
        if (this.departed) {
          return;
        }
        const summary: ImportSummary = await importFromZip(ctx, tempZip, strategy,
          (): Promise<string | null> =>
            this.askPassphrase('输入文件口令', '该文件含密钥，已口令加密'));
        // 背景直达刷新：放 departed 守卫之前——notify 广播给全部注册实例、不依赖发起页存活；
        // 放守卫后用户中途退出时一级页收不到通知
        notifyBgChanged();
        if (this.departed) {
          return;
        }
        this.broadcastSessionReload();
        // line 含行级失败分档（与 doImport 同口径，经 davStatus 的 line 段带出）
        const line: string = summaryLine(summary, false);
        // 密钥档分档文案（与 doImport 同口径——部分密钥未写入时如实呈报重填入口）
        const secretTip: string = summary.secretFailures > 0 ?
          `，有 ${summary.secretFailures} 项密钥未写入，请到服务商管理或联网搜索页重填` : '';
        // 图域逐会话失败如实分档（与 doImport 同口径）
        const graphTip: string = summary.graphFailedSessions > 0 ?
          `，有 ${summary.graphFailedSessions} 个会话的分支未导入，请重新导出备份后再试` : '';
        this.davStatus = `已恢复 ${backupDateLabel(remoteName)} 的备份` +
          (line !== '' ? `（${line}）` : '') +
          (summary.prefCount > 0 ? `，恢复设置 ${summary.prefCount} 项` : '') +
          (strategy === 'overwrite' && summary.totalOverwritten > 0 ?
            `，覆盖已存在 ${summary.totalOverwritten} 条` : '') + secretTip + graphTip;
      } finally {
        releaseBusyOverlay(busyToken);
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      const msg: string = (e as Error).message;
      if (msg === '已取消导入') { // 口令弹窗取消 = 零写入无需刷新（状态行回静默）
        this.davStatus = '';
      } else {
        // 刷新照发（与 doImport 同口径——写库后失败时列表须反映实况）
        this.broadcastSessionReload();
        this.davStatus = '恢复失败：' + msg;
      }
    } finally {
      try {
        fs.unlinkSync(tempZip);
      } catch (e) {
        // 不存在 = 目标状态
      }
      this.busy = false;
    }
  }

  // ── UI 件 ──

  // 卡容器（组卡规范：16 圆角 + cardBg + 16 内边距）
  @Builder
  Card(title: string, note: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardTitleColor())
      .width('100%')
    if (note !== '') {
      Text(note)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
    }
  }

  // 行内操作键（光感四件套 + 内容区回退双态；档位 = tierButton* 分发——primary 强调蓝 /
  // tinted 淡彩次级 / 默认灰）。weight > 0 = Row 行内 layoutWeight 均分；0 = 单键占满卡内宽
  //（原三键各 width('100%') 排 Row 会 300% 溢出，主键伸出屏右——真机实锤）
  @Builder
  ActionBtn(label: string, primary: boolean, onTap: () => void, weight: number = 0,
    tinted: boolean = false) {
    if (weight > 0) {
      Button(label)
        .layoutWeight(weight)
        .fontColor(tierButtonFont(this.contentFallback, primary, tinted))
        .backgroundColor(tierButtonBg(this.contentFallback, this.immersiveLevel, primary, tinted))
        .systemMaterial(tierButtonMaterial(this.contentFallback, this.immersiveLevel, primary, tinted))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(!this.busy)
        .onClick((): void => {
          onTap();
        })
    } else {
      Button(label)
        .width('100%')
        .fontColor(tierButtonFont(this.contentFallback, primary, tinted))
        .backgroundColor(tierButtonBg(this.contentFallback, this.immersiveLevel, primary, tinted))
        .systemMaterial(tierButtonMaterial(this.contentFallback, this.immersiveLevel, primary, tinted))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(!this.busy)
        .onClick((): void => {
          onTap();
        })
    }
  }

  // WebDAV 输入行：独立子组件 DavField（文件尾）——@Link 双向

  build() {
    PageShell({
      title: '数据与同步',
      // 标题栏下方带承载（HDS 路径生效；回退路径壳不消费，页面侧已二选一渲染内容区悬浮层）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      // 执行段返回拦截（BusyOverlay 单源——进行中弹确认，离开 = 撤遮罩 + 任务继续后台跑）
      onBackPressed: (): boolean => {
        return confirmLeaveBusyPage(this.getUIContext(), (): void => {
          this.pathStack.pop();
        });
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  @Builder
  Content() {
    // 内容滚动层（分段胶囊经 PageShell.titleBarBottom 下方带承载，不在本 Stack 内）
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (this.segIndex === 0) {
            this.BackupScopeCard()
            this.ExportCard()
            this.RestoreCard()
            this.DsImportCard()
          } else if (this.segIndex === 1) {
            this.WebDavCard()
          } else {
            S3SyncCard({ includeSecrets: $includeSecrets })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        // 外层容器不设左右边距——卡宽 CARD_PANEL_WIDTH 已含左右 16vp，容器再带 = 双重收窄
        //（真机实锤）；Column 默认居中。顶留白 = 胶囊位（topPad − 8）+ SEGMENT_BAR_HEIGHT + 28
        .padding({
          top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28,
          bottom: this.bottomPad + 16
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ── 备份内容卡（含密钥开关管三条路径，独立成卡才不会被读成导出卡局部选项；无操作按钮行，
  // 说明小字在开关行上方——宪法「功能设置卡布局次序」）──
  @Builder
  BackupScopeCard() {
    Column({ space: 10 }) {
      Text('备份内容')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text(SCOPE_NOTE)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('包含密钥')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          Text('开启后备份包含 API Key，文件经口令加密。')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.includeSecrets })
          .onChange((isOn: boolean): void => {
            this.includeSecrets = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // ── 导出卡（第一段「本机备份」；含密钥开关已上移到备份内容卡）──
  @Builder
  ExportCard() {
    Column({ space: 10 }) {
      this.Card('导出备份', EXPORT_NOTE)
      this.ActionBtn('导出备份到本机', true, (): void => {
        this.doExport();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // ── 恢复卡（第一段「本机备份」）──
  @Builder
  RestoreCard() {
    Column({ space: 10 }) {
      this.Card('从备份恢复', RESTORE_NOTE)
      // 导入为主操作（蓝底）
      this.ActionBtn('选择备份文件导入', true, (): void => {
        this.doImport();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // ── DeepSeek 导入卡（第一段「本机备份」尾部——DS 官方导出包解析为新会话，不覆盖本机）──
  @Builder
  DsImportCard() {
    Column({ space: 10 }) {
      this.Card('导入 DeepSeek 对话', '把 DeepSeek 官方导出的对话备份包导入本应用，会话以新会话加入会话列表，不覆盖现有会话。')
      this.ActionBtn('选择 DeepSeek 导出包', true, (): void => {
        this.pushDsImport();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // ── WebDAV 卡（第二段「WebDAV 同步」）──
  @Builder
  WebDavCard() {
    Column({ space: 10 }) {
      // 卡头 = 标题 + 说明两行制（测试键在下方三键行）
      this.Card('WebDAV 同步', '整库备份上传到你的 WebDAV 网盘，每天一份，保留最近 5 天。内容与本机导出一致，不含价格模板，密钥开关在本机备份分段。')
      SyncField({ label: '地址', value: $davUrl, placeholder: 'https://dav.jianguoyun.com/dav/',
        isPassword: false })
      SyncField({ label: '账号', value: $davUser, placeholder: '登录账号', isPassword: false })
      SyncField({ label: '密码', value: $davPass, placeholder: '应用专用密码', isPassword: true })
      SyncField({ label: '目录', value: $davDir, placeholder: 'aicontrol', isPassword: false })
      // 三键行：上传备份、测试为淡彩次级档（推进型动作），恢复到本机为主钮蓝——行为沿
      // doDavTest 原语义：成功保存配置、结果走 davStatus 状态行
      Row({ space: 10 }) {
        this.ActionBtn('上传备份', false, (): void => {
          this.doDavUpload();
        }, 1, true)
        this.ActionBtn('恢复到本机', true, (): void => {
          this.doDavRestore();
        }, 1)
        this.ActionBtn('测试', false, (): void => {
          this.doDavTest();
        }, 1, true)
      }
      .width('100%')
      if (this.davStatus !== '') {
        Text(this.davStatus)
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
