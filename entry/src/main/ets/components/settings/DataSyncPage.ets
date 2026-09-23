// 「数据与同步」二级页（2026-09-03 Cube 吸收第三批③；自包 PageShell 壳——
// SystemPromptPage 同款）：四卡/三卡——
// · 导出备份：9 表全行 + 偏好分域 zip（ExportImport.exportAllData）→ 系统文档保存面板
//   （picker.save）用户选位置落盘。卡内「包含密钥」开关（2026-09-10 方案-偏好与密钥接入
//   备份 §4.6）驱动两档产物：关闭 = 包内零明文；开启 = 另产口令加密的 secrets.enc
//   （Key 池 + 引擎密钥 + 余额密钥与请求头），口令入口 = 官方 InputDialog 密码型；
// · 从备份恢复：先弹冲突策略两键框（跳过合并 / 覆盖恢复，B2）→ 文档选择器选 zip →
//   沙箱中转 → importFromZip（manifest 闸门 + id 冲突两态策略 + 偏好回写 + 密钥档解密
//   回填）→ 摘要呈报 + 会话列表刷新广播；包内带 secrets.enc 时先要口令（取消 = 零副作用）；
// · WebDAV 同步：连接配置（Preferences 自持持久化——独立偏好文件，不动 persistProp
//   注册链；密码例外走 Asset——KeyStore aic.dav.password 单例条目，2026-09-03 观察⑪
//   销项）+ 测试连接 / 上传备份（导出→PUT 当日日期档，上传前显式确认是否含密钥）/
//   恢复到本机（恢复链取最近一份→导入）。远端滚动备份语义 = aicontrol_backup_YYYYMMDD.zip
//   日期档，保留最近 5 个上传日、上传后自动清更老候选（WebDavApi 头注释）。
// ★ 含密钥开关只有一个、本机导出与 WebDAV 上传共用（决明 2026-09-10 拍板）：两条路径是
// 同一份产物，两个开关会制造「本地带密钥、云上没带」的分叉（方案 §4.6）；WebDAV 侧的
// 差异化处置 = 上传前显式确认，不加第二开关。
// 行内操作键光感四件套（ImmersiveLevel 胶囊按钮簇——宪法「行内操作按钮官方形制」）：
// 主操作 primary=true 官方强调蓝，次操作 primary=false 官方灰。
// 隐私边界（2026-09-10 更新）：不含密钥档 = 包内零明文（providers 的三个明文敏感列由
// 导出侧置空）；含密钥档 = 明文只进加密件（加密实现单一来源 = ProviderShare，本页不做
// 第二套加密）；WebDAV 密码恒不进包（通道凭据自指死锁）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { PageShell } from '../../common/PageShell';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor,
  cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { cleanupExportDir, exportAllData, ExportSummary, importFromZip,
  ImportStrategy, ImportSummary } from '../../common/store/ExportImport';
import { loadDavPassword, removeDavPassword, saveDavPassword } from '../../common/store/KeyStore';
import { downloadLatestBackup, pruneOldBackups, probe, uploadBackup,
  WebDavConfig } from '../../common/WebDavApi';
import { copyFileExact } from '../../common/ImageEditUtil';
import { SESSION_LIST_RELOAD_KEY } from '../chat/ChatSessionList';
import { InputDialog } from '../chat/InputDialog';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';

// WebDAV 偏好文件与键（页面自持——不动 EntryAbility persistProp 注册链）。2026-09-03
// 密码迁 Asset（KeyStore 三导出，观察⑪销项）：preferences 只存地址/账号/目录三非敏感
// 字段；KEY_PASSWORD 为遗留键仅迁移读 + 删。密码明文不进任何日志/导出（红线沿用）。
const DAV_PREFS_FILE: string = 'webdav_config';
const KEY_BASE_URL: string = 'baseUrl';
const KEY_USERNAME: string = 'username';
const KEY_PASSWORD: string = 'password'; // 遗留键：迁移读 + 删，不再写入
const KEY_DIR_NAME: string = 'dirName';
const KEY_LAST_REMOTE_NAME: string = 'lastRemoteName'; // 恢复链①环——本机最近一次成功上传的远端档名
const DEFAULT_DIR_NAME: string = 'aicontrol';

// 卡片说明文案（导出范围与密钥边界——用户须知）
const EXPORT_NOTE: string = '包含全部会话、消息、服务商配置、模型、助手、提示词、记忆与偏好设置。不含密钥时文件内没有 API Key，恢复后需要重新填写。';
const RESTORE_NOTE: string = '导入时可选跳过已存在或覆盖已存在。跳过保留本机记录只新增，覆盖用备份内容恢复误改数据。覆盖会一并覆盖偏好设置，跳过则本机设置保持不变。用较旧的备份覆盖时，备份中没有的设置项会恢复为默认值。';

@Component
export struct DataSyncPage {
  // 顶部/底部留白（vp，PageMapBuilder 注入）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 深浅色（回退卡底）+ 光感档位（按钮簇）
  @StorageProp('appColorMode') appColorMode: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本组件按钮官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // WebDAV 表单（@State 驱动输入框；加载自 preferences）
  @State private davUrl: string = '';
  @State private davUser: string = '';
  @State private davPass: string = '';
  @State private davDir: string = DEFAULT_DIR_NAME;
  @State private davStatus: string = ''; // 同步动作状态行（'' = 无）
  @State private busy: boolean = false; // 动作互斥（导出/导入/同步三链共用）
  // 上传确认弹窗控制器（★ 组件成员位——坑7：CustomDialogController 须组件成员构造，
  // askUploadConfirm 内运行时重建 + open）
  private confirmCtrl: CustomDialogController | null = null;
  // 含密钥开关（2026-09-10 方案 §4.6）：一个开关两条路径共用（本机导出 + WebDAV 上传），
  // 默认关 = 包内零明文（最保守档）；开启后导出/上传前收一次口令
  @State private includeSecrets: boolean = false;
  // 口令弹窗控制器（每次弹出重新构造——坑7：CustomDialogController 须组件成员位构造）
  private passCtrl: CustomDialogController | null = null;

  // 口令输入弹窗（resolve 文本 / 用户取消 resolve null——Promise 恒 settle，编排侧判空；
  // 形制与文案对齐 ProviderPage.askPassphrase 先例：InputDialog 密码型 + allowEmpty
  // 默认 false = 空口令被拦（含密钥档强制非空口令）；本型现两处〔本页 / ProviderPage〕，
  // 2026-09-20 高级页迁移卡退役后原第三处随卡删除）
  // ★ 两个取消口都要接（2026-09-10 报障修复）：onCancel = 弹窗内「取消」键（程序化 close，
  // 不触发控制器级 cancel——原只有 cancel 时此键让 Promise 永挂、busy 卡死置灰）；
  // cancel = 返回键/点遮罩/Esc（d.ts 原文）。少接一个就有一种取消姿势把按钮锁死。
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
    // 启动级残留清扫已迁 EntryAbility.onCreate（2026-09-03 自检观察⑨——本页只做表单回填）
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
      // getSync + 显式收窄（preferences.get 返回 ValueType 联合——arkts 联合收窄）
      this.davUrl = store.getSync(KEY_BASE_URL, '') as string;
      this.davUser = store.getSync(KEY_USERNAME, '') as string;
      this.davDir = store.getSync(KEY_DIR_NAME, DEFAULT_DIR_NAME) as string;
      // 密码自 Asset 回显（2026-09-03 迁 Asset）——异步晚到不阻塞表单，@State 就绪即渲
      let pass: string = await loadDavPassword();
      // 一次性存量迁移：旧版密码留在 preferences 时搬入 Asset 并删旧键。2026-09-03 立——
      // 功能未广泛装机，预计命中≈0，保险起见保留；只在「Asset 空且旧键非空」触发，重跑幂等
      const legacy: string = store.getSync(KEY_PASSWORD, '') as string;
      if (pass === '' && legacy !== '') {
        await saveDavPassword(legacy);
        store.deleteSync(KEY_PASSWORD);
        await store.flush();
        pass = legacy;
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
      // 密码只进 Asset（2026-09-03）；清空保存 = 删条目，preferences 不留空串残迹
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

  // 会话列表刷新广播（坑3 计数器口径；服务商列表页返回时经 onPop 链自刷）。
  // ★ 2026-09-10 O2 修复：与导入成败解耦——密钥档回填在 9 表与偏好全部落库之后，此前
  // 失败路径不发本广播 = 数据已进库而会话列表不刷新，须退出重进才可见（观感「真没恢复」）
  private broadcastSessionReload(): void {
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }

  // 导出摘要行（呈报口径：表 × 行数收敛为一句）
  private summaryLine(summary: ExportSummary | ImportSummary, exported: boolean): string {
    const counts: Record<string, number> = exported ?
      (summary as ExportSummary).counts : (summary as ImportSummary).imported;
    const parts: string[] = [];
    const pairs: string[][] = [['conversations', '会话'], ['messages', '消息'],
      ['providers', '服务商'], ['assistants', '助手'], ['prompt_templates', '提示词']];
    for (const pair of pairs) {
      const n: number = counts[pair[0]] ?? 0;
      if (n > 0) {
        parts.push(`${pair[1]} ${n}`);
      }
    }
    // 损坏分域如实呈报（2026-09-11 自检）：文件在但解析失败此前静默跳过、摘要只打非零表，
    // 用户会误当「备份里本来就没有」——本行同时覆盖本机导入与 WebDAV 恢复两条链
    if (!exported) {
      for (const t of (summary as ImportSummary).parseFailed ?? []) {
        const hit: string[][] = pairs.filter((p: string[]): boolean => p[0] === t);
        parts.push(`${hit.length > 0 ? hit[0][1] : t}表损坏未导入`);
      }
    }
    return parts.join('、');
  }

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
      const summary: ExportSummary = await exportAllData(ctx, this.includeSecrets, passphrase);
      // 系统文档保存面板（用户选落盘位置——免权限；DocumentViewPicker.save 官方链）
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [summary.fileName];
      const uris: Array<string> = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        this.cleanupExport(ctx, summary.fileName);
        return; // 用户取消——临时 zip 清掉即退
      }
      // ★ 2026-09-03 自检修复：uri 字符串直传 fs.copyFileSync 不可靠（copyFileExact 头注释
      // 2026-08-20 真机实锤 URI 字符串解析报「路径或文件不存在」）——统一 fd 链路
      copyFileExact(summary.path, uris[0]);
      this.cleanupExport(ctx, summary.fileName);
      const line: string = this.summaryLine(summary, true);
      const secure: string = this.includeSecrets ? '，已带上密钥并口令加密' : '';
      this.toast(`备份已保存${line !== '' ? '：' + line : ''}${secure}`);
    } catch (e) {
      this.toast('导出失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  // 导出临时产物清删（zip + 解包目录——数据有界；文件名反解 stamp）
  private cleanupExport(ctx: common.UIAbilityContext, fileName: string): void {
    const stamp: string = fileName.replace('aicontrol_backup_', '').replace('.zip', '');
    try {
      fs.unlinkSync(ctx.cacheDir + '/aicontrol_backup_' + stamp + '.zip');
    } catch (e) {
      // 已不存在 = 目标状态
    }
    cleanupExportDir(ctx, stamp);
  }

  // 导入冲突策略弹窗（B2 定案——官方对话框两键，UIContext 形态；askReturnAfterImport 同款先例）。
  // 返回 null = 用户取消（点空白/返回键），取消 = 静默放弃零导入（选择器取消同款语义）
  private async askImportStrategy(): Promise<ImportStrategy | null> {
    // 确认弹窗统一豁免：三键选择语义（跳过/覆盖 + 取消），见任务书 §3.5
    const choice = await this.getUIContext().getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '选择导入方式',
      message: '跳过已存在则保留本机记录，只导入备份中的新记录。覆盖已存在则用备份中的记录替换本机同 id 记录，用于恢复误改的数据。覆盖还会用备份里的偏好设置覆盖本机设置，跳过则本机设置保持不变。用较旧的备份覆盖时，备份中没有的设置项会恢复为默认值。',
      buttons: [
        { text: '跳过已存在', color: $r('sys.color.font_secondary') },
        { text: '覆盖已存在', color: $r('sys.color.font_primary') }
      ]
    });
    if (choice.index === 0) {
      return 'skip';
    }
    if (choice.index === 1) {
      return 'overwrite';
    }
    return null;
  }

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
      const strategy: ImportStrategy | null = await this.askImportStrategy();
      if (strategy === null) {
        return; // 用户取消
      }
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 恢复 = 单备份操作（冲突策略也只问一次）：不设 maxSelectNumber 时系统面板默认多选
      //（d.ts 上限 500，AttachmentPickCtrl 2026-09-03 实查同款），多选件除首个外静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (uris.length === 0) {
        return; // 用户取消
      }
      copyFileExact(uris[0], tempZip);
      // 密钥档口令回调（包内含 secrets.enc 时必调；取消返 null → 域内抛「已取消导入」，
      // 此时尚未写任何库 = 零副作用）
      const summary: ImportSummary = await importFromZip(ctx, tempZip, strategy,
        (): Promise<string | null> =>
          this.askPassphrase('输入文件口令', '该文件含密钥，已口令加密'));
      this.broadcastSessionReload();
      const line: string = this.summaryLine(summary, false);
      const prefInfo: string = summary.prefCount > 0 ? `，恢复设置 ${summary.prefCount} 项` : '';
      // 偏好写入走 AppStorage（@StorageProp 订阅页自动刷；用 @State 快照读的页面不刷，
      // 方案 §4.8 已知边界）——摘要文案提示重进页面
      const prefTip: string = summary.prefCount > 0 ? '。部分设置需重进页面生效' : '';
      // 密钥档分档文案（2026-09-10 O2 修复）：部分密钥未写入时如实呈报——数据与设置已
      // 恢复、仅密钥须重填，不再让用户误以为整体失败而白导一遍；页名用规范名（服务商管理 /
      // 联网搜索，与设置搜索注册表 SETTING_TITLE_* 及帮助中心措辞一致——O2 的立意就是
      // 「照提示做的下一步不能错」）
      const secretTip: string = summary.secretFailures > 0 ?
        `。有 ${summary.secretFailures} 项密钥未写入，请到服务商管理或联网搜索页重填` : '';
      this.toast(`导入完成${line !== '' ? '：' + line : ''}${prefInfo}` +
        (strategy === 'overwrite' ?
          (summary.totalOverwritten > 0 ? `（覆盖已存在 ${summary.totalOverwritten} 条）` : '') :
          (summary.totalSkipped > 0 ? `（跳过已存在 ${summary.totalSkipped} 条）` : '')) +
        prefTip + secretTip);
    } catch (e) {
      const msg: string = (e as Error).message;
      if (msg !== '已取消导入') { // 口令弹窗取消 = 零写入无需刷新（正常取消路径，静默）
        // 其余失败点在写库前后皆有可能（闸门拒绝 = 零写入；密钥回填/对账/附件作废失败 =
        // 数据已落库）——刷新照发：零写入场景多发一次无害，已写入场景漏发才误导（O2 修复）
        this.broadcastSessionReload();
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
      this.davStatus = '连接成功，配置已保存';
    } catch (e) {
      this.davStatus = '连接失败：' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  // 上传确认弹窗（★ 2026-09-12 UI 同形异构归一笔 5：原官方 showDialog 两键迁自绘
  // ConfirmDialog 两键——confirmTone NORMAL 上传非破坏动作不配红；取消/遮罩/返回键
  // 三路关闭均 = 零动作放弃。onWillDismiss 桥接遮罩/返回键路径（CustomDialogControllerOptions
  // @since 12 实存）：注册后关闭动作不自动执行须 action.dismiss() 放行，autoCancel 直关
  // 不进任何回调——缺桥接则本 Promise 在遮罩关闭时永挂；settled 单次闸防 dismiss 与
  // 回调竞态双 resolve）
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
      // 上传前显式确认（2026-09-10 方案 §4.6：WebDAV 不加第二开关，改为让用户明确知道
      // 这次上传带不带密钥、传到哪；取消 = 零动作）
      const confirmed: boolean = await this.askUploadConfirm();
      if (!confirmed) {
        this.davStatus = ''; // 用户取消（取消键/遮罩/返回键三路同语义）
        return;
      }
      let passphrase: string = '';
      if (this.includeSecrets) {
        const pass: string | null = await this.askPassphrase('设置备份口令',
          '口令加密文件内容，恢复时需输入（丢失无法恢复）');
        if (pass === null) {
          this.davStatus = '';
          return; // 用户取消
        }
        passphrase = pass;
      }
      const summary: ExportSummary = await exportAllData(ctx, this.includeSecrets, passphrase);
      try {
        const remoteName: string = await uploadBackup(this.davConfig(), summary.path);
        // 记录本机最近上传档名（恢复链①环——传输层不读 preferences，页面层持久化）
        const store: preferences.Preferences = await this.davStore();
        store.putSync(KEY_LAST_REMOTE_NAME, remoteName);
        await store.flush();
        const line: string = this.summaryLine(summary, true);
        this.davStatus = `上传完成（${line}），正在清理旧备份…`;
        await this.saveDavConfig();
        // 滚动清理更老日期档（尽力而为——内部全吞，恒正常返回）
        await pruneOldBackups(this.davConfig());
        this.davStatus = `上传完成（${line}）`;
      } finally {
        this.cleanupExport(ctx, summary.fileName);
      }
    } catch (e) {
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
      const strategy: ImportStrategy | null = await this.askImportStrategy();
      if (strategy === null) {
        return; // 用户取消
      }
      this.davStatus = '正在下载并恢复…';
      const store: preferences.Preferences = await this.davStore();
      const lastName: string = store.getSync(KEY_LAST_REMOTE_NAME, '') as string;
      const remoteName: string = await downloadLatestBackup(this.davConfig(), tempZip, lastName);
      const summary: ImportSummary = await importFromZip(ctx, tempZip, strategy,
        (): Promise<string | null> =>
          this.askPassphrase('输入文件口令', '该文件含密钥，已口令加密'));
      this.broadcastSessionReload();
      const line: string = this.summaryLine(summary, false);
      // 密钥档分档文案（O2 修复，与 doImport 同口径——部分密钥未写入时如实呈报重填入口）
      const secretTip: string = summary.secretFailures > 0 ?
        `，有 ${summary.secretFailures} 项密钥未写入，请到服务商管理或联网搜索页重填` : '';
      this.davStatus = `已恢复 ${this.backupDateLabel(remoteName)} 的备份` +
        (line !== '' ? `（${line}）` : '') +
        (summary.prefCount > 0 ? `，恢复设置 ${summary.prefCount} 项` : '') +
        (strategy === 'overwrite' && summary.totalOverwritten > 0 ?
          `，覆盖已存在 ${summary.totalOverwritten} 条` : '') + secretTip;
    } catch (e) {
      const msg: string = (e as Error).message;
      if (msg === '已取消导入') { // 口令弹窗取消 = 零写入无需刷新（状态行回静默）
        this.davStatus = '';
      } else {
        // 刷新照发（与 doImport 同口径——写库后失败时列表须反映实况，O2 修复）
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

  // 远端档名 → 档期标签：反解 8 位日期显示为 YYYY-MM-DD；非日期档名（如旧版固定名）原样显示
  private backupDateLabel(remoteName: string): string {
    const m: RegExpMatchArray | null = remoteName.match(/(\d{4})(\d{2})(\d{2})/);
    if (m === null) {
      return remoteName;
    }
    return `${m[1]}-${m[2]}-${m[3]}`;
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

  // 行内操作键（光感四件套 + 内容区回退双态——fallbackButton* 同构 + fallback 首参，见
  // CropStageView 先例；primary = 官方强调蓝主操作）。weight > 0 = Row 行内均分
  //（layoutWeight 平分——SystemPromptPage 底部双键同款；2026-09-03 真机修复：原三键
  // 各 width('100%') 排 Row = 300% 溢出，主键伸出屏右只露一点）；0 = Column 单键恒占满卡内宽
  @Builder
  ActionBtn(label: string, primary: boolean, onTap: () => void, weight: number = 0) {
    if (weight > 0) {
      Button(label)
        .layoutWeight(weight)
        .fontColor(fallbackButtonFont(this.contentFallback, primary))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, primary))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, primary))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(!this.busy)
        .onClick((): void => {
          onTap();
        })
    } else {
      Button(label)
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, primary))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, primary))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, primary))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(!this.busy)
        .onClick((): void => {
          onTap();
        })
    }
  }

  // WebDAV 输入行：独立子组件 DavField（文件尾）——@Link 双向（2026-09-03 自检 P1-2）

  build() {
    PageShell({
      title: '数据与同步',
      content: (): void => {
        this.Content();
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 导出卡（2026-09-10 方案 §4.6：卡内加一行「包含密钥」开关——一个开关两条路径
        // 共用，本机导出与 WebDAV 上传同源；行形态照 AppearancePage 光感开关卡次行先例
        // 〔说明左 + 官方 Toggle 右〕，纵向次序 = 卡说明 → 开关行 → 操作键）──
        Column({ space: 10 }) {
          this.Card('导出备份', EXPORT_NOTE)
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('包含密钥')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('开启后备份带上 API Key，文件经口令加密。本机导出与上传 WebDAV 都会带上')
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
          this.ActionBtn('导出备份到本机', true, (): void => {
            this.doExport();
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)

        // ── 恢复卡 ──
        Column({ space: 10 }) {
          this.Card('从备份恢复', RESTORE_NOTE)
          // 2026-09-03 领导指令：导入升为主操作蓝底
          this.ActionBtn('选择备份文件导入', true, (): void => {
            this.doImport();
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)

        // ── WebDAV 卡 ──
        Column({ space: 10 }) {
          // 卡头（2026-09-03 领导指令）：标题 + 说明 + 右上角测试键——wifi 图标 TEXTUAL
          // 无底，服务商 Key 池卡头同款形态；标题样式沿用 Card 件口径
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('WebDAV 同步')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .width('100%')
              Text('整库备份上传到你的 WebDAV 网盘，如坚果云。网盘保留最近 5 天的备份，每天一份，更早的自动清除。上传内容与上方导出的一致，含密钥开关同源。备份不含服务商的价格模板。导入时可选跳过或覆盖已存在记录。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .enabled(!this.busy)
            .onClick((): void => {
              this.doDavTest();
            })
          }
          .width('100%')
          DavField({ label: '地址', value: $davUrl, placeholder: 'https://dav.jianguoyun.com/dav/',
            isPassword: false })
          DavField({ label: '账号', value: $davUser, placeholder: '登录账号', isPassword: false })
          DavField({ label: '密码', value: $davPass, placeholder: '应用专用密码', isPassword: true })
          DavField({ label: '目录', value: $davDir, placeholder: 'aicontrol', isPassword: false })
          // 2026-09-03 领导指令：测试键上移卡头；上传降为次钮灰底、恢复升为主钮蓝底
          Row({ space: 10 }) {
            this.ActionBtn('上传备份', false, (): void => {
              this.doDavUpload();
            }, 1)
            this.ActionBtn('恢复到本机', true, (): void => {
              this.doDavRestore();
            }, 1)
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
        .borderRadius(16)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // ★ 2026-09-03 真机反馈修复：外层容器**不设左右边距**——卡宽 CARD_PANEL_WIDTH
      // 已含左右 16vp（Theme.ets 口径），容器再带左右 padding = 双重收窄（规范 §3 红字，
      // ProviderPage 同类坑），真机实锤卡比其余页左右各窄 16vp；Column 默认
      // alignItems=Center 自动居中，与 SystemPromptPage 同款
      .padding({
        top: this.topPad,
        bottom: this.bottomPad + 16
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}

// WebDAV 输入行组件（label + 输入框；password 型走 TextInput.type）。
// ★ 2026-09-03 自检 P1-2 修复：原 @Builder 按值传参（坑16/75 家族——loadDavConfig 异步
// 回填 @State 后输入框仍显示空，观感 = 已存配置丢失）；改独立子组件 @Link 订阅式双向
//（父侧 $davUrl 传参直挂 @State，回填随刷）——与 ProviderConfigPanel 等表单 @Link 契约一致
@Component
struct DavField {
  @Link value: string;
  label: string = '';
  placeholder: string = '';
  isPassword: boolean = false;

  build() {
    Row({ space: 10 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(56)
      TextInput({ text: this.value, placeholder: this.placeholder })
        .fontSize(14)
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .layoutWeight(1)
        .onChange((text: string): void => {
          this.value = text;
        })
    }
    .width('100%')
  }
}
