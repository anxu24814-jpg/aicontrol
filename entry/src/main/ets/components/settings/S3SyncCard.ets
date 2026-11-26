// S3 对象存储同步卡（DataSyncPage 第三段「S3 同步」，WebDAV 卡同构镜像；独立文件原因 = 宪法「新增功能域
// 一律先拆」）。传输面 = common/S3Api.ets（SigV4 手写签名零 SDK）；配置 = s3_config 独立偏好文件（地址/桶名/
// 区域/AccessKeyId/目录/路径风格六项非敏感字段，不动 EntryAbility persistProp 注册链——webdav_config 同口径）
// + SecretAccessKey 走 Asset（KeyStore aic.s3.secret，明文不进偏好/日志/备份——凭据登记块 #7）。
// ★ 含密钥开关经 @Link 挂页面单例（拍板「一个开关所有路径共用」——本卡不自建，assert-feature-domain 54 组
//「一处 @State + 一处 Toggle」钉守住单例面）。两弹窗自含复刻 DataSyncPage 同款（坑7：须组件成员位构造，
// 不可抽共享；兜底 onCancel 接线）。底部三键 = 上传备份（次）/ 恢复到本机（主）/ 测试（次）——决明拍板同 WebDAV。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial, tierButtonBg, tierButtonFont, tierButtonMaterial } from '../../common/ImmersiveLevel';
import { exportAllData, ExportSummary, ImportStrategy,
  ImportSummary } from '../../common/store/ExportImport';
import { importFromZip } from '../../common/store/ExportImportApply';
import { loadS3Secret, removeS3Secret, saveS3Secret } from '../../common/store/KeyStore';
import { downloadLatestBackup, endpointFormatError, pruneOldBackups, probe, S3Config,
  uploadBackup } from '../../common/S3Api';
import { askImportStrategy, backupDateLabel, cleanupExport, summaryLine,
  SyncField } from './SyncShared';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { notifyBgChanged } from '../../common/BgRefreshBus';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import { InputDialog } from '../chat/InputDialog';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';

// S3 偏好文件与键（页面自持独立文件——同 webdav_config：不进备份两表，其中无敏感值〔Secret 在 Asset〕）
const S3_PREFS_FILE: string = 's3_config';
const KEY_ENDPOINT: string = 'endpoint';
const KEY_BUCKET: string = 'bucket';
const KEY_REGION: string = 'region';
const KEY_ACCESS_KEY: string = 'accessKeyId';
const KEY_PREFIX: string = 'prefix';
const KEY_PATH_STYLE: string = 'pathStyle';
const KEY_LAST_REMOTE_NAME: string = 'lastRemoteName'; // 恢复候选置顶——本机最近一次成功上传的远端键名
const DEFAULT_REGION: string = 'auto';
const DEFAULT_PREFIX: string = 'aicontrol';

@Component
export struct S3SyncCard {
  // 页面存活守卫（销毁守卫治理）：置位后迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  // 深浅色（回退卡底）+ 光感档位 + 内容区回退开关（DataSyncPage 同款三件）
  @StorageProp('appColorMode') appColorMode: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 含密钥开关（页面单例 @Link——本卡不自建开关）
  @Link includeSecrets: boolean;
  @State private s3Endpoint: string = '';
  @State private s3Bucket: string = '';
  @State private s3Region: string = DEFAULT_REGION;
  @State private s3Ak: string = '';
  @State private s3Sk: string = '';
  @State private s3Prefix: string = DEFAULT_PREFIX;
  @State private s3PathStyle: boolean = true;
  @State private s3Status: string = ''; // 同步动作状态行（'' = 无）
  @State private busy: boolean = false; // 动作互斥（测试/上传/恢复三链共用）
  // 上传确认弹窗控制器（坑 7：CustomDialogController 须组件成员位构造）
  private confirmCtrl: CustomDialogController | null = null;
  // 口令弹窗控制器（每次弹出重新构造——坑 7 同上）
  private passCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.loadS3Config();
  }

  // ── S3 配置（preferences 读写）──

  private async s3Store(): Promise<preferences.Preferences> {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return preferences.getPreferences(ctx, S3_PREFS_FILE);
  }

  private async loadS3Config(): Promise<void> {
    try {
      const store: preferences.Preferences = await this.s3Store();
      if (this.departed) {
        return;
      }
      this.s3Endpoint = store.getSync(KEY_ENDPOINT, '') as string;
      this.s3Bucket = store.getSync(KEY_BUCKET, '') as string;
      const region: string = store.getSync(KEY_REGION, '') as string;
      this.s3Region = region !== '' ? region : DEFAULT_REGION;
      this.s3Ak = store.getSync(KEY_ACCESS_KEY, '') as string;
      const prefix: string = store.getSync(KEY_PREFIX, '') as string;
      this.s3Prefix = prefix !== '' ? prefix : DEFAULT_PREFIX;
      this.s3PathStyle = store.getSync(KEY_PATH_STYLE, true) as boolean;
      // Secret 自 Asset 回显——异步晚到不阻塞表单，@State 就绪即渲（WebDAV 密码同款）
      this.s3Sk = await loadS3Secret();
    } catch (e) {
      // 配置读取失败 = 初次使用默认空表单（不阻断）
    }
  }

  private async saveS3Config(): Promise<void> {
    try {
      const store: preferences.Preferences = await this.s3Store();
      store.putSync(KEY_ENDPOINT, this.s3Endpoint.trim());
      store.putSync(KEY_BUCKET, this.s3Bucket.trim());
      store.putSync(KEY_REGION, this.s3Region.trim() !== '' ? this.s3Region.trim() : DEFAULT_REGION);
      store.putSync(KEY_ACCESS_KEY, this.s3Ak.trim());
      store.putSync(KEY_PREFIX, this.s3Prefix.trim() !== '' ? this.s3Prefix.trim() : DEFAULT_PREFIX);
      store.putSync(KEY_PATH_STYLE, this.s3PathStyle);
      // Secret 只进 Asset（KeyStore #7）；清空保存 = 删条目，preferences 不留空串残迹
      if (this.s3Sk !== '') {
        await saveS3Secret(this.s3Sk);
      } else {
        await removeS3Secret();
      }
      await store.flush();
    } catch (e) {
      this.toast('配置保存失败：' + (e as Error).message);
    }
  }

  private s3Config(): S3Config {
    return {
      endpoint: this.s3Endpoint.trim(),
      bucket: this.s3Bucket.trim(),
      region: this.s3Region.trim() !== '' ? this.s3Region.trim() : DEFAULT_REGION,
      accessKeyId: this.s3Ak.trim(),
      secretAccessKey: this.s3Sk,
      prefix: this.s3Prefix.trim() !== '' ? this.s3Prefix.trim() : DEFAULT_PREFIX,
      pathStyle: this.s3PathStyle
    };
  }

  private s3ConfigOk(): boolean {
    return this.s3Endpoint.trim() !== '' && this.s3Bucket.trim() !== '' &&
      this.s3Ak.trim() !== '' && this.s3Sk !== '';
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 会话列表刷新广播（坑3 计数器口径——doImport 同款，成败解耦见 DataSyncPage O2 注）
  private broadcastSessionReload(): void {
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }

  // 口令输入弹窗（resolve 文本 / 取消 resolve null——Promise 恒 settle，编排侧判空；InputDialog 密码型 + allowEmpty
  // 默认 false = 空口令被拦）。★ 两个取消口都要接——onCancel = 弹窗内「取消」键（程序化 close 不触发控制器级
  // cancel），cancel = 返回键/点遮罩/Esc——少接一个就有一种取消姿势把按钮锁死（54 契约钉 J 系兜底）
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

  // 上传确认弹窗（自绘 ConfirmDialog 两键，confirmTone NORMAL——上传非破坏动作不配红；取消/遮罩/返回键三路关闭 =
  // 零动作放弃；onWillDismiss 桥接遮罩/返回键路径，settled 单次闸防 dismiss 与回调竞态双 resolve）
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
          title: '上传到 S3',
          message: this.includeSecrets ?
            '本次备份包含密钥，已口令加密，将上传到你的对象存储。口令请自行保管，丢失后无法恢复。' :
            '本次备份不包含密钥，将上传到你的对象存储。在新设备恢复后需要重新填写密钥。',
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

  // ── 动作链 ──

  private async doS3Test(): Promise<void> {
    if (this.busy || !this.s3ConfigOk()) {
      if (!this.s3ConfigOk()) {
        this.toast('请先填写服务地址、桶名、Access Key ID 与 Secret Access Key');
      }
      return;
    }
    const endpointErr: string = endpointFormatError(this.s3Endpoint);
    if (endpointErr !== '') {
      this.toast(endpointErr);
      return;
    }
    this.busy = true;
    this.s3Status = '正在测试连接…';
    try {
      await probe(this.s3Config());
      await this.saveS3Config();
      if (this.departed) {
        return;
      }
      this.s3Status = '连接成功，配置已保存';
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.s3Status = '连接失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async doS3Upload(): Promise<void> {
    if (this.busy || !this.s3ConfigOk()) {
      if (!this.s3ConfigOk()) {
        this.toast('请先填写服务地址、桶名、Access Key ID 与 Secret Access Key');
      }
      return;
    }
    const endpointErr: string = endpointFormatError(this.s3Endpoint);
    if (endpointErr !== '') {
      this.toast(endpointErr);
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    this.s3Status = '正在打包并上传…';
    try {
      // 上传前显式确认（与 WebDAV 同口径：不加第二开关，让用户明确知道这次上传带不带密钥、传到哪；取消 = 零动作）
      const confirmed: boolean = await this.askUploadConfirm();
      if (this.departed) {
        return;
      }
      if (!confirmed) {
        this.s3Status = ''; // 用户取消（取消键/遮罩/返回键三路同语义）
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
          this.s3Status = '';
          return; // 用户取消
        }
        passphrase = pass;
      }
      // 执行段遮罩：打包→上传→登记→滚动清理全程盖浮层 + 拦返回（嵌套 try/finally 起止成对——BusyOverlay 头注释）
      const busyToken: number = bumpBusyOverlay('正在上传备份');
      try {
        const summary: ExportSummary = await exportAllData(ctx, this.includeSecrets, passphrase);
        if (this.departed) {
          return;
        }
        try {
          const remoteName: string = await uploadBackup(this.s3Config(), summary.path);
          // 记录本机最近上传键名（恢复候选置顶——传输层不读 preferences，页面层持久化）；本机记录与远端清理属
          // 数据层，照常完成——判守只放在 UI 之前
          const store: preferences.Preferences = await this.s3Store();
          store.putSync(KEY_LAST_REMOTE_NAME, remoteName);
          await store.flush();
          if (this.departed) {
            return;
          }
          const line: string = summaryLine(summary, true);
          this.s3Status = `上传完成（${line}），正在清理旧备份…`;
          await this.saveS3Config();
          // 滚动清理更老备份档（保留最近 5 份，尽力而为——内部全吞，恒正常返回）
          await pruneOldBackups(this.s3Config());
          if (this.departed) {
            return;
          }
          this.s3Status = `上传完成（${line}）`;
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
      this.s3Status = '上传失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async doS3Restore(): Promise<void> {
    if (this.busy || !this.s3ConfigOk()) {
      if (!this.s3ConfigOk()) {
        this.toast('请先填写服务地址、桶名、Access Key ID 与 Secret Access Key');
      }
      return;
    }
    const endpointErr: string = endpointFormatError(this.s3Endpoint);
    if (endpointErr !== '') {
      this.toast(endpointErr);
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    this.busy = true;
    const tempZip: string = ctx.cacheDir + '/s3_download_tmp.zip';
    try {
      // B2：下载之前先定冲突策略（避免选中策略前白下载一份大包；取消零副作用）
      const strategy: ImportStrategy | null = await askImportStrategy(this.getUIContext());
      if (this.departed) {
        return;
      }
      if (strategy === null) {
        return; // 用户取消
      }
      this.s3Status = '正在下载并恢复…';
      // 执行段遮罩：下载→导入写库全程盖浮层 + 拦返回——口令回调弹窗在窗口层浮于遮罩之上可正常操作（BusyOverlay）
      const busyToken: number = bumpBusyOverlay('正在恢复备份');
      try {
        const store: preferences.Preferences = await this.s3Store();
        if (this.departed) {
          return;
        }
        const lastName: string = store.getSync(KEY_LAST_REMOTE_NAME, '') as string;
        const remoteName: string = await downloadLatestBackup(this.s3Config(), tempZip, lastName);
        if (this.departed) {
          return;
        }
        const summary: ImportSummary = await importFromZip(ctx, tempZip, strategy,
          (): Promise<string | null> =>
            this.askPassphrase('输入文件口令', '该文件含密钥，已口令加密'));
        // 背景直达刷新：放 departed 守卫之前——notify 广播给全部注册实例、不依赖发起页存活（与 DataSyncPage 同构）
        notifyBgChanged();
        if (this.departed) {
          return;
        }
        this.broadcastSessionReload();
        // line 含行级失败分档（C1，与 DataSyncPage 两入口同口径——共用 summaryLine 单源）
        const line: string = summaryLine(summary, false);
        const secretTip: string = summary.secretFailures > 0 ?
          `，有 ${summary.secretFailures} 项密钥未写入，请到服务商管理或联网搜索页重填` : '';
        const graphTip: string = summary.graphFailedSessions > 0 ?
          `，有 ${summary.graphFailedSessions} 个会话的分支未导入，请重新导出备份后再试` : '';
        this.s3Status = `已恢复 ${backupDateLabel(remoteName)} 的备份` +
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
        this.s3Status = '';
      } else {
        // 刷新照发（与 doImport 同口径——写库后失败时列表须反映实况）
        this.broadcastSessionReload();
        this.s3Status = '恢复失败：' + msg;
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

  // 行内操作键（光感四件套 + 内容区回退双态——DataSyncPage.ActionBtn 同款封装；档位三态 = tierButton* 分发：
  // primary 主档蓝 / tinted 淡彩次级 / 默认灰次钮）。weight > 0 = Row 行内均分，0 = Column 单键占满
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

  build() {
    Column({ space: 10 }) {
      // 卡头（标题 + 说明——无测试键，测试在底部第三键）
      Text('S3 同步')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('整库备份上传到 S3 兼容存储，保留最近 5 份。内容与本机导出一致，不含价格模板，密钥开关在本机备份分段。区域不确定填 auto。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      SyncField({ label: '地址', value: $s3Endpoint, placeholder: 'https://s3.example.com',
        isPassword: false })
      SyncField({ label: '桶名', value: $s3Bucket, placeholder: '存储桶名称', isPassword: false })
      SyncField({ label: '区域', value: $s3Region, placeholder: 'auto', isPassword: false })
      SyncField({ label: 'Access Key ID', value: $s3Ak, placeholder: '访问密钥 ID',
        isPassword: false, labelWidth: 124 })
      SyncField({ label: 'Secret Access Key', value: $s3Sk, placeholder: '访问密钥 Secret',
        isPassword: true, labelWidth: 124 })
      SyncField({ label: '目录', value: $s3Prefix, placeholder: 'aicontrol', isPassword: false })
      // 路径风格开关行（说明左 + 官方 Toggle 右——ExportCard 含密钥开关行同款形制）
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('路径风格')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          Text('开启后按 地址/桶名/文件名 访问，MinIO 与 R2 保持开启。关闭后按 桶名.域名 访问。')
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.s3PathStyle })
          .onChange((isOn: boolean): void => {
            this.s3PathStyle = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 底部三键（决明拍板三键行形制；四档笔起上传备份、测试改淡彩次级档，恢复到本机保持主钮蓝）
      Row({ space: 10 }) {
        this.ActionBtn('上传备份', false, (): void => {
          this.doS3Upload();
        }, 1, true)
        this.ActionBtn('恢复到本机', true, (): void => {
          this.doS3Restore();
        }, 1)
        this.ActionBtn('测试', false, (): void => {
          this.doS3Test();
        }, 1, true)
      }
      .width('100%')
      if (this.s3Status !== '') {
        Text(this.s3Status)
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
