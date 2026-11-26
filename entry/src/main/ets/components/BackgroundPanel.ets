// 「背景」面板（「背景」三级页整页承载，原为「外观显示」页内嵌段——2026-10-18 决明改版：选择/编辑两卡 → 预览框 + 并排双键）：
// 布局 = ①预览框（设备比例的手机屏缩略图，与编辑图片页裁剪框同一宽高比、高度约其一半）→
// ②「选择图片 / 编辑图片」并排双键 → ③「背景生效范围」分段行卡 → ④「恢复默认」单卡。
// 功能链路：①选择图片：拉起系统图片选择器（photoAccessHelper.PhotoViewPicker，系统级、
// 无需权限）→ 拷贝到应用沙箱（picker 返回的媒体库 URI 是临时授权、应用重启后失效，必须
// 拷到沙箱持久化）→ **push 图片编辑二级页**（编辑对象 = 新选图；流程合并：抛弃「直接选图
// 即生效」——保存成功才由调整页写入 AppStorage['pageBg']，PageBackground 响应式刷新全应用
// 背景）；②编辑图片：对**当前背景图**做比例裁剪 + 模糊/遮罩调整（push ImageEditPage，两阶段
// 编辑流程，恢复上次保存的参数；未设置过背景时拦截）；③恢复默认：清空 pageBg 回官方灰底。
// 两入口差异见 pickImage()/editImage() 注释（编辑对象来源经 EditImageParam 传参）。
// 预览图源 = BgCache 共享位图（借用不释放，零二次解码）；编辑页保存后 popToName 返回本页时
// 经页面显示纪元重读 AppStorage 同步（pageBg 的 @StorageProp 在栈下层可能冻结，见
// PageBackground 头注释 O1）。
import { BusinessError } from '@kit.BasicServicesKit';
import { SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CONTENT_FALLBACK_KEY,
  fallbackButtonBgOffCard,
  fallbackButtonFont,
  fallbackButtonMaterial,
  fallbackButtonStateEffect,
  IMMERSIVE_LEVEL_KEY,
  overlayMaterial,
  resolvedUiMaterial
} from '../common/ImmersiveLevel';
import {
  bgFileNameFromUri,
  bgTripleNames,
  cleanBgFiles,
  copyFileExact,
  newBgFileName,
  resetPageBackground,
  ScreenMetrics,
  screenMetrics
} from '../common/ImageEditUtil';
import { ensureBgPixelMap, getBgPixelMap } from '../common/BgCache';
import { notifyBgChanged, registerBgRefreshListener, unregisterBgRefreshListener }
  from '../common/BgRefreshBus';
import { BG_SHOWN_EPOCH_KEY, bumpBgShownEpoch } from '../common/PageBackground';
import { PREF_BG_SESSION_ONLY_KEY, PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT,
  CARD_ALPHA_MIN, CARD_ALPHA_MAX, CARD_ALPHA_STEP, clampCardAlphaLevel }
  from '../common/AppPreferences';
import {
  SETTING_TITLE_BG_SESSION_ONLY,
  SETTING_TITLE_EDIT_IMAGE,
  SETTING_TITLE_PICK_IMAGE,
  SETTING_TITLE_RESTORE_DEFAULT
} from '../common/SettingSearch';
import { ROUTE_IMAGE_EDIT_PAGE } from '../common/RouteNames';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardBorderColor, cardDescColor, CARD_RADIUS } from '../common/Theme';
import { SettingSegmentRowCard } from './SegmentBar';
import { SliderValueCard } from './SliderValueCard';
import { ConfirmDialog } from './chat/ConfirmDialog';
import { EditImageParam } from './ImageEditPage';

@Component
export struct BackgroundPanel {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、
  // 不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 沉浸光感整体档位（驱动提示 Toast 材质）+ 内容区回退能力位（并排双键四件套消费）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换时自动刷新卡片配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（本面板挂新滑轨卡 = 全应用唯一写点，@StorageLink 拖动直写即落盘
  //（persistProp 已注册）即广播即时层；自身卡体消费表达式引用同参，属性级刷新照常成立）
  @StorageLink(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 路由栈（PrefBackgroundPage 透传 PageMap 入参）：「选择图片/编辑图片」卡片 push 编辑二级页
  pathStack: NavPathStack = new NavPathStack();
  // 当前背景图 URI（空 = 未设置背景；编辑入口需有图才可进入）。@Watch 仅作变化信号：
  // 预览刷新一律现读 AppStorage（pop 返回时本键可能冻结，纪元兜底见下）
  @StorageProp('pageBg') @Watch('onPreviewSignal') pageBg: string = '';
  // 页面显示纪元（PageShell.onShown 自 bump）：编辑页保存后 popToName 回本页时 pageBg 的
  // @StorageProp 可能未送达（PageBackground O1 同款问题），经本键重读 AppStorage 补刷预览
  @StorageProp(BG_SHOWN_EPOCH_KEY) @Watch('onPreviewSignal') shownEpoch: number = 0;
  // ── 预览框状态 ──
  // 预览图（借用 BgCache 共享位图，不持有释放权——生命周期归缓存，同 PageBackground）
  @State previewPm: image.PixelMap | null = null;
  // 解码在途（无缓存命中时的短暂窗口：显示加载指示，避免闪成「无图」态）
  @State previewLoading: boolean = false;
  // 刷新序号：防乱序（连续换图时只采纳最新一次解码结果，先例 PageBackground.loadSeq）
  private previewSeq: number = 0;
  // 直达刷新回调：**成员初始化式箭头函数**包 refreshPreview（★ 禁 .bind(this) 直接注册
  // ——每次 bind 产生新函数身份 = 注销失位泄漏；现役同款先例 = confirmCtrl 的 onConfirm，
  // BgRefreshBus.ets 头注释）——写点直达通知一并覆盖本预览；departed 双保险
  private onBgPreviewDirectRefresh: () => void = () => {
    if (!this.departed) {
      this.refreshPreview();
    }
  };
  // 预览框尺寸（vp；aboutToAppear 按设备宽高比初始化）：宽 = 屏宽 36% 钳 [104, 144]，
  // 高 = 宽 ÷ 屏幕宽高比——与编辑图片页裁剪框同一比例，高度约其一半（「小一些」）
  private previewW: number = 120;
  private previewH: number = 260;
  // 背景生效范围：true = 自定义背景只在会话页显示；false = 全应用生效（默认）。
  // 消费方 = PageBackground 组合判定，切换经 AppStorage 全局即刷，本组件无需额外广播。
  // 分段下标与布尔键双向映射（下标 0 = 仅会话页，互设守卫同值不递归）；下标→键映射内含
  // P7 落盘 + 纪元 bump + 直达通知三副作用，见其注释
  @StorageLink(PREF_BG_SESSION_ONLY_KEY) @Watch('onBgSessionOnlyChanged') bgSessionOnly: boolean = false;
  @State @Watch('onBgSessionIndexChanged') bgSessionIndex: number = 1;
  // 分段选项（顺序契约：下标 0 = 仅会话页〔键 true〕/ 1 = 全应用〔键 false〕，勿单独乱调）
  private bgSessionItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '仅会话页' },
    { text: '全应用' }
  ]);
  // 恢复默认确认弹窗（决明拍板：动作不可逆删除自定义背景文件，确认键走 ConfirmDialog
  // 默认 DANGER 红语气）。坑7 = 必须组件成员位构造——普通类 open() 静默无效真机实锤（先例
  // ChatFontSection.confirmCtrl）；坑64 = 禁 showAlertDialog（槽内真机失效），ConfirmDialog
  // 为工程标准件。确认后编排在 restoreDefault()
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '恢复默认',
      message: '将删除自定义背景图并恢复官方灰底，卡底不透明度恢复为不透明。',
      confirmLabel: '恢复默认',
      onConfirm: (): void => {
        this.restoreDefault();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    // 预览框几何（设备比例缩略图；aspect 异常时按竖屏 0.5 兜底，P0-1 不留除零/零高）
    const m: ScreenMetrics = screenMetrics();
    const aspect: number = Number.isFinite(m.aspect) && m.aspect > 0.05 ? m.aspect : 0.5;
    this.previewW = Math.min(144, Math.max(104, m.widthVp * 0.36));
    this.previewH = this.previewW / aspect;
    this.refreshPreview();
    // 档位键归域：老备份或异常持久化值钳回合法域——赋值即经 @StorageLink 落盘
    this.cardAlphaLevel = clampCardAlphaLevel(this.cardAlphaLevel);
    // 存量键值对齐分段亮位（声明处默认值不代表键实际值——切过仅会话页的用户进页须亮对段；
    // 缺此行 = 键 true 时段亮「全应用」，且首点「仅会话页」被同值守卫吞掉不触发刷新链。
    // 其余分段行卡均有此对位〔ChatFontSection / PrefSessionReadPage /
    // PrefAppLaunchPage〕，本卡漏网系自检轮 2026-10-31 抓出补齐）
    this.bgSessionIndex = this.bgSessionOnly ? 0 : 1;
    // 直达通道注册（写点直达通知一并刷新本预览；aboutToDisappear 与 departed 置位同点注销，
    // 成对释放）
    registerBgRefreshListener(this.onBgPreviewDirectRefresh);
  }

  // 用户点分段 → 写布尔持久键（互设守卫同值不递归；下标 0 = 仅会话页 = 键 true）。
  // P7 硬化：键值无条件先落 AppStorage——@StorageLink 写入在值冻结态可能丢（分段视觉已切
  // 但盘未写，杀进程重启回旧值）；persistProp 已注册即同步落盘。切换即 bump 显示纪元：切换
  // 时刻页面已在显示态、无 onShown 事件，PageBackground 的 bgSessionOnly @Watch 送达面不可靠
  //（坑25 族）；bump 纪元键 = 用已实证可靠的刷新触发器（与 pop 返回同链）驱动全部存活实例
  // load 全键现读重判（真机症状 = 开启态换图后切全应用，背景不立即全局、重启才生效）。
  // 直达通知（主通道）：普通函数调用点名全部存活实例 load 现读重判——送达与坑16/坑25 订阅
  // 失效面正交；bump 保留为次通道
  private onBgSessionIndexChanged(): void {
    const sessionOnly: boolean = this.bgSessionIndex === 0;
    if (sessionOnly === this.bgSessionOnly) {
      return;
    }
    AppStorage.setOrCreate<boolean>(PREF_BG_SESSION_ONLY_KEY, sessionOnly);
    this.bgSessionOnly = sessionOnly;
    bumpBgShownEpoch();
    notifyBgChanged();
  }

  // 其他写键方（备份导入恢复）→ 补正分段下标
  private onBgSessionOnlyChanged(): void {
    const idx: number = this.bgSessionOnly ? 0 : 1;
    if (idx !== this.bgSessionIndex) {
      this.bgSessionIndex = idx;
    }
  }

  // 任一信号（pageBg 变化 / 页面重新显示）→ 现读 AppStorage 重刷预览
  onPreviewSignal(): void {
    this.refreshPreview();
  }

  // 预览刷新：无背景清图标态；有背景优先同步命中 BgCache（编辑页保存前已预热，零延迟），
  // 未命中异步 ensure（与 PageBackground 同一 inflight，不重复解码）。借用缓存不释放
  private refreshPreview(): void {
    const uri: string = AppStorage.get<string>('pageBg') ?? '';
    if (uri.length === 0) {
      this.previewSeq++;
      this.previewPm = null;
      this.previewLoading = false;
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      // 禁止静默失败（P0-1）：极端场景退回「无图」态但必须留日志
      hilog.error(0xD5A0, 'BackgroundPanel', 'preview load failed: host context unavailable');
      this.previewPm = null;
      this.previewLoading = false;
      return;
    }
    // 沙箱纯路径（file:// URI 剥前缀是非法相对路径，坑31；文件名拼目录，同 PageBackground）
    const path: string = context.filesDir + '/' + bgFileNameFromUri(uri);
    const hit: image.PixelMap | null = getBgPixelMap(path);
    if (hit !== null) {
      this.previewSeq++;
      this.previewPm = hit;
      this.previewLoading = false;
      return;
    }
    // 换图窗口保留旧预览（先旧后新），解码完成后按序号采纳最新一次结果
    const seq: number = ++this.previewSeq;
    this.previewLoading = true;
    ensureBgPixelMap(path).then((pm: image.PixelMap | null) => {
      if (this.departed) {
        return;
      }
      if (seq === this.previewSeq) {
        this.previewPm = pm;
        this.previewLoading = false;
      }
    });
  }

  // toast 统一入口：材质随沉浸光感总档（基准 THICK = 官方默认档）
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 背景面板卡片（2026-11-04 蒙层合规笔：整卡自绘，§4.19 范式——卡底 Column 承三件套 +
  // padding 4，内层透明 Button 蒙层，四缘各 4vp）。两种形态：有说明 = 卡高 72（4×2 + 64）、
  // 无说明 = 56（4×2 + 48）；内容内距 12 + 外层 4 = 原官方卡内距 16。onClick 按值传递
  //（@Builder 规则——回调引用创建后不变，安全）
  @Builder
  CardItem(title: string, desc: string, action: () => void) {
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 0 }) {
            Text(title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (desc !== '') {
              Text(desc)
                .fontSize(14)
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(desc === '' ? 48 : 64)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        action();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(desc === '' ? 56 : 72)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 背景预览框：有图 Cover 显示当前背景；无图时框心放应用图标，底板 app.color.bg_preview_empty
  //（随深浅）；解码在途显示加载指示。圆角同编辑页裁剪框（官方 XL 档）；clip 保证图片不越
  // 圆角；1vp 细描边——无图时底板与页面底色同色，靠描边显形
  @Builder
  PreviewBox() {
    Stack() {
      if (this.previewPm !== null) {
        Image(this.previewPm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.previewLoading) {
        // 底板随深浅（浅色浅底 / 深色深底），指示色走官方语义前景，两模式均可见
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('sys.color.font_secondary'))
      } else {
        // 无图（或解码失败兜底）：应用图标居中（预览框内 64vp / 14 圆角；会话空态已改为
        // 与启动页同物理尺寸 256px，本处受预览框比例约束保持小尺寸）
        Image($r('app.media.startIcon'))
          .width(64)
          .height(64)
          .borderRadius(14)
      }
    }
    .width(this.previewW)
    .height(this.previewH)
    .clip(true)
    .borderRadius($r('sys.float.ohos_id_corner_radius_default_xl'))
    .border({ width: 1, color: cardBorderColor(this.appColorMode) })
    .backgroundColor($r('app.color.bg_preview_empty'))
  }

  // 并排双操作键：选择图片 / 编辑图片等宽并排——行内文字键四件套；本行坐页面灰底、无卡体，
  // 次钮底取卡外面白底（fallbackButtonBgOffCard，见 ImmersiveLevel 头注释与规范 §1
  //「卡外实心件白底」条）
  @Builder
  ActionRow() {
    Row({ space: 12 }) {
      Button(SETTING_TITLE_PICK_IMAGE)
        .layoutWeight(1)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false, this.cardAlphaLevel))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.pickImage();
        })
      Button(SETTING_TITLE_EDIT_IMAGE)
        .layoutWeight(1)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false, this.cardAlphaLevel))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.editImage();
        })
    }
    .width(CARD_PANEL_WIDTH)
  }

  // 编辑图片（当前背景）：push 编辑二级页，编辑对象 = 当前背景图（编辑页解码时经
  // resolveEditDecodePath 优先取干净底图——重新编辑基于干净底图，模糊/遮罩可逆；调整页
  // 恢复上次保存的模糊/遮罩参数）。未设置过背景时拦截提示
  private editImage(): void {
    // 现读 AppStorage（不用 this.pageBg：pop 返回时 @StorageProp 可能冻结，2026-10-18）
    const currentBg: string = AppStorage.get<string>('pageBg') ?? '';
    if (currentBg.length === 0) {
      this.toast('请先选择图片');
      return;
    }
    // 编辑对象经 push 参数传入（srcUri = 当前背景 URI；两入口统一走参数，编辑页零感知来源差异）
    this.pathStack.pushPathByName(ROUTE_IMAGE_EDIT_PAGE, { srcUri: currentBg } as EditImageParam);
  }

  // 选择图片：官方图片选择器 → 拷贝到应用沙箱 → **push 编辑二级页**（编辑对象 = 新选图，
  // 保存成功才生效）；转场 = NavPathStack 官方系统级（系统选图器在 select resolve 时已收场，
  // 立即 push 即播，无人为等待）。全链路见文件头注释
  private async pickImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (this.departed) {
        return;
      }
      if (result.photoUris.length === 0) {
        return; // 用户取消选择，不提示
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        throw new Error('host context unavailable');
      }
      // ★ 临时文件防堆积：先清上一轮「选图 → 编辑页取消/返回」残留的未引用临时文件（保留
      // 当前背景三名：显示图 + 干净底图 + 可编辑原图，bgTripleNames 公共推导）。任意时刻
      // 未引用残留 ≤ 1 个，沙箱有界。清理放本处而非编辑页 aboutToDisappear：调整页保存在
      // 途链有 decodeScaled 重解码分支，编辑页销毁时删文件会与在途读取竞态；本回调执行时
      // 编辑页早已销毁、无并发任务（P1-2 轻量：随用户手势执行）。现读 AppStorage 防保留名单
      // 取到冻结旧值而误删当前背景文件
      const currentBg: string = AppStorage.get<string>('pageBg') ?? '';
      cleanBgFiles(context.filesDir, bgTripleNames(bgFileNameFromUri(currentBg)));
      // 唯一名方案（坑34）：每次换图生成新文件名 + 清旧文件——固定文件名覆盖时 pageBg 的
      // file:// URI 每次相同，@StorageProp 相同字符串不触发刷新（已挂载页面不更新，真机
      // 复现）；唯一名保证 URI 必然变化
      const destPath: string = context.filesDir + '/' + newBgFileName();
      // 拷贝用官方 fd 级姿势（华为官方博客《从相册选取图片保存进应用沙箱》标准流程）：
      // openSync 打开媒体 URI 拿 fd → copyFileSync(fd, fd)。不能用 fs.copy 直接传 URI
      // 字符串——其对媒体库 URI 解析不可靠，真机报「路径或文件不存在」（决明实测所有图片
      // 均失败后按官方姿势修复）；公共函数 copyFileExact
      copyFileExact(result.photoUris[0], destPath);
      // 校验拷贝结果 + 转 file:// URI：Image 组件加载沙箱文件的标准 URI 形式（此前直接存
      // 纯路径 Image 静默加载失败、看似「未生效」；改 file:// URI 后按官方姿势）
      const stat: fs.Stat = fs.statSync(destPath);
      const destUri: string = fileUri.getUriFromPath(destPath);
      hilog.info(0xD5A0, 'BackgroundPanel', 'image pick copied, size=%{public}d, uri=%{public}s',
        stat.size, destUri);
      // ★ 流程合并：不再 set pageBg / toast「背景已更换」——push 编辑页，保存成功才由调整页
      // 写 pageBg 生效；参数记忆清零由调整页按编辑源判定（选图 srcUri≠pageBg 才清零——
      // 选图后未走到调整页就取消时旧背景参数不丢，见 ImageAdjustPage.aboutToAppear 注释）
      this.pathStack.pushPathByName(ROUTE_IMAGE_EDIT_PAGE, { srcUri: destUri } as EditImageParam);
    } catch (err) {
      // toast 带错误码（BusinessError.code），失败时可据此快速定位环节
      const code: number | undefined = (err as BusinessError).code;
      hilog.error(0xD5A0, 'BackgroundPanel', 'image pick failed: %{public}s', JSON.stringify(err));
      this.toast('图片处理失败' + (code !== undefined ? ' (' + code + ')' : ''));
    }
  }

  // 恢复默认：清空 pageBg（同步持久化）+ 清空背景文件（扫删全部 page_background_*——唯一
  // 名方案配套：不清会残留孤儿，循环每轮 +1，违反数据有界防线；删除失败仅日志，显示不受
  // 影响，下次换图扫删自愈）+ 清零编辑参数记忆三键（参数跟随当前背景图，无背景即从 0
  // 开始；本处为唯一显式清零点）。四步整体上收 ImageEditUtil.resetPageBackground（本键与
  // 快速清理页「恢复默认背景」项共用同一函数）。
  // ★ 决明拍板：恢复默认联动卡底透明度档回 CARD_ALPHA_DEFAULT；@StorageLink 写入即落盘即
  // 广播，同值不赋值避免白刷即时面订阅。快速清理页恢复默认不联动（点名范围外）。本键经
  // confirmCtrl 确认弹窗放行后才执行
  private restoreDefault(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    resetPageBackground(context !== undefined ? context.filesDir : '');
    // 预览即时回无图态（不依赖 @StorageProp 变化信号送达）
    this.refreshPreview();
    // 透明度档回默认（不透明）：同值不赋值——避免无谓触发即时面 16 件订阅刷新
    if (this.cardAlphaLevel !== CARD_ALPHA_DEFAULT) {
      this.cardAlphaLevel = CARD_ALPHA_DEFAULT;
    }
    this.toast('已恢复默认背景与不透明度');
  }

  // 「背景生效范围」分段行卡（SettingSegmentRowCard 单源件）：左标题副标 + 右置分段胶囊，
  // 行不可点、分段为唯一控制面。写 PREF_BG_SESSION_ONLY_KEY，下标→键映射含 P7 先落盘 +
  // 纪元 bump + 直达通知三副作用（见 onBgSessionIndexChanged 注释）
  @Builder
  SessionOnlySwitchCard() {
    SettingSegmentRowCard({
      title: SETTING_TITLE_BG_SESSION_ONLY,
      subtitle: '控制自定义背景图的生效页面',
      items: this.bgSessionItems,
      selectedIndex: $bgSessionIndex
    })
  }

  // 档位名映射（中性档名，方案档 §3：值文案禁百分比——深浅两表同档不同值；表序 = L0→L4
  // 滑轨值序，越界经 clamp 归域兜底；调曲线值只改 Theme 双表、档名不动）
  private cardAlphaName(v: number): string {
    const names: string[] = ['高透', '半透', '中透', '轻透', '不透明'];
    return names[clampCardAlphaLevel(v)];
  }

  // 卡底不透明度滑轨卡：复用共享组件 SliderValueCard——离散五档无中间值可输，showEdit 传
  // false；值域四量单源引用（禁两处各写）；@StorageLink 直连 = 拖动即落盘（5 档全程最多
  // 4 次值变化），onChange clamp 由共享组件内置 min/max 收口。滑轨行 = 偏好设置页
  //「提醒间隔」行同款（左「不透明度」标签 + 右短滑轨；方向语义由说明小字承接）；说明小字
  // 经共享组件置于操作行上方（宪法布局次序）。恢复默认联动本档（见 restoreDefault 注释）
  @Builder
  CardAlphaSliderCard() {
    SliderValueCard({
      title: '卡底不透明度',
      desc: '调节应用内卡片与气泡的不透明度。最高档不透明，与应用默认效果一致。最低档保留底色，不影响文字阅读。纯色背景下透明感较弱，搭配壁纸效果更明显。',
      value: $cardAlphaLevel,
      min: CARD_ALPHA_MIN,
      max: CARD_ALPHA_MAX,
      step: CARD_ALPHA_STEP,
      format: (v: number): string => this.cardAlphaName(v),
      rowLabel: '不透明度',
      showEdit: false
    })
  }

  build() {
    // 面板布局：从上往下依次排列、间距统一 CARD_SPACING = 10vp、宽度统一 CARD_PANEL_WIDTH
    // 居中；外层（PrefBackgroundPage 内容区 Column）负责顶对齐与整体留白。★ 首两件不是卡——
    // 预览框 + 并排双键（宽度仍与卡体对齐，只是不挂卡底）
    Column({ space: CARD_SPACING }) {
      this.PreviewBox()
      this.ActionRow()
      this.SessionOnlySwitchCard()
      // 滑轨卡落位 = 开关卡与恢复默认之间（与背景观感设置相邻成组；「恢复默认」恒末位先例不变）
      this.CardAlphaSliderCard()
      this.CardItem(SETTING_TITLE_RESTORE_DEFAULT, '', () => {
        // 恢复默认先弹确认（confirmCtrl 组件成员位预建），确认后编排在 restoreDefault()
        this.confirmCtrl.open();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 直达通道注销（与 departed 置位同点，注册成对释放）
    unregisterBgRefreshListener(this.onBgPreviewDirectRefresh);
  }
}
