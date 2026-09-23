// 「背景」面板（「外观显示」页内嵌，2026-08-20 由独立二级页 ChangeBgPage 迁入）：
// 三个卡片——①选择图片：拉起系统图片选择器（photoAccessHelper.PhotoViewPicker，系统级
// 选择器、无需权限）→ 拷贝到应用沙箱（picker 返回的媒体库 URI 是临时授权、应用重启后失效，
// 必须拷到沙箱持久化）→ **push 图片编辑二级页**（编辑对象 = 新选图；2026-08-22 流程合并：
// 抛弃「直接选图即生效」——保存成功才由调整页写入 AppStorage['pageBg']，PageBackground
// 统一背景组件响应式刷新，连接页/我的页/二级页底层背景自动全部跟随）；②编辑图片：对
// **当前背景图**做比例裁剪 + 模糊/遮罩调整（push ImageEditPage 二级页，两阶段编辑流程，
// 恢复上次保存的模糊/遮罩参数；未设置过背景时拦截）；③恢复默认：清空 pageBg 回官方灰底。
// 两入口差异见 pickImage()/editImage() 注释（编辑对象来源经 EditImageParam 传参）。
import { BusinessError } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import { bgFileNameFromUri, bgTripleNames, cleanBgFiles, copyFileExact, EDIT_BLUR_PCT_KEY, EDIT_CROP_STATE_KEY, EDIT_MASK_PCT_KEY, newBgFileName } from '../common/ImageEditUtil';
import { PREF_BG_SESSION_ONLY_KEY } from '../common/AppPreferences';
import {
  SETTING_TITLE_BG_SESSION_ONLY,
  SETTING_TITLE_EDIT_IMAGE,
  SETTING_TITLE_PICK_IMAGE,
  SETTING_TITLE_RESTORE_DEFAULT
} from '../common/SettingSearch';
import { ROUTE_IMAGE_EDIT_PAGE } from '../common/RouteNames';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../common/Theme';
import { EditImageParam } from './ImageEditPage';

@Component
export struct BackgroundPanel {
  // 沉浸光感整体档位（2026-08-20 弹窗/按钮/标题栏三键合并；驱动提示
  // Toast 材质，迁自 ChangeBgPage）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换时自动刷新卡片配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 路由栈（AppearancePage 透传 PageMap 入参）：「选择图片/编辑图片」卡片 push 编辑二级页
  pathStack: NavPathStack = new NavPathStack();
  // 当前背景图 URI（空 = 未设置背景；编辑入口需有图才可进入）
  @StorageProp('pageBg') pageBg: string = '';
  // 背景仅用于会话页开关（2026-09-05 新增开关卡）：true = 自定义背景只在会话页显示，
  // 其余页面用默认底色；false = 全应用生效（默认）。消费方 = PageBackground 组合判定，
  // 切换经 AppStorage 全局即刷，本组件无需额外广播
  @StorageLink(PREF_BG_SESSION_ONLY_KEY) bgSessionOnly: boolean = false;
  // 官方 HDS 列表项卡片可用性（2026-08-22 检查补：本面板原无 syscap 自检——2026-08-21
  // 列表卡片规范「优先官方 HdsListItemCard，无 Full 回退自制」；与 MainMenu/InfoPage 同源）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // toast 统一入口（2026-08-22 检查提取，P2-4：4 处重复样板）：材质随沉浸光感总档
  // （基准 THICK = 官方默认档）
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 背景面板卡片（2026-08-22 检查对齐列表卡片规范）：HDS 分支**不传 cardBackgroundColor**
  // （官方默认深浅自动反色，同 MainMenu/InfoPage 定稿——原自定义 cardBg 已删）；
  // 无 Full 回退自制无描边白底卡片（同 MainMenu 回退样式）；onClick 参数按值传递
  // （@Builder 规则——回调引用创建后不变，安全）
  @Builder
  CardItem(title: string, desc: string, action: () => void) {
    if (this.hdsListCardAvailable) {
      if (desc === '') {
        HdsListItemCard({
          textItem: { primaryText: { text: title } },
          cardBorderRadius: 16,
          onClick: action
        })
        .width(CARD_PANEL_WIDTH)
      } else {
        HdsListItemCard({
          textItem: { primaryText: { text: title }, secondaryText: { text: desc } },
          cardBorderRadius: 16,
          onClick: action
        })
        .width(CARD_PANEL_WIDTH)
      }
    } else {
      Button() {
        Row() {
          Column({ space: 4 }) {
            Text(title)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            if (desc !== '') {
              Text(desc)
                .fontSize(13)
                .fontColor($r('sys.color.font_tertiary'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([cardDescColor()])
        }
        .width('100%')
        .padding(16)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .onClick(action)
    }
  }

  // 编辑图片（当前背景）：push 编辑二级页，编辑对象 = 当前背景图（编辑页解码时经
  // resolveEditDecodePath 优先取干净底图——重新编辑基于干净底图，模糊/遮罩可逆；调整页
  // 恢复上次保存的模糊/遮罩参数）。未设置过背景时拦截提示
  private editImage(): void {
    if (this.pageBg.length === 0) {
      this.toast('请先选择图片');
      return;
    }
    // 2026-08-22 起编辑对象经 push 参数传入（srcUri = 当前背景 URI；不再传 null 由
    // 编辑页自行读 pageBg——两入口统一走参数，编辑页零感知来源差异）
    this.pathStack.pushPathByName(ROUTE_IMAGE_EDIT_PAGE, { srcUri: this.pageBg } as EditImageParam);
  }

  // 选择图片：官方图片选择器 → 拷贝到应用沙箱 → **push 编辑二级页**（编辑对象 = 新选图，
  // 保存成功才生效；2026-08-22 流程合并，原「copy 后 set pageBg + toast 已更换」链路删除）。
  // 全链路见文件头注释；转场 = NavPathStack 官方系统级（编辑页右侧滑入，与「编辑图片」
  // 入口同一转场机制——系统选图器在 select resolve 时已收场，立即 push 即播，无人为等待）
  private async pickImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return; // 用户取消选择，不提示
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        throw new Error('host context unavailable');
      }
      // ★ 临时文件防堆积（2026-08-22 流程合并配套）：先清上一轮「选图 → 编辑页取消/返回」
      // 残留的未引用临时文件（保留当前背景三名：显示图 + 干净底图 + 可编辑原图，bgTripleNames
      // 公共推导；未设背景时空名单 = 只清残留）。任意时刻未引用残留 ≤ 1 个，沙箱有界。
      // 清理放本处而非编辑页 aboutToDisappear：调整页保存在途链有 decodeScaled(srcDecodePath)
      // 重解码分支，编辑页销毁时删文件会与在途读取竞态；本回调执行时编辑页早已销毁、
      // 无并发任务（P1-2 轻量：随用户手势执行）
      cleanBgFiles(context.filesDir, bgTripleNames(bgFileNameFromUri(this.pageBg)));
      // 唯一名方案（2026-08-21 修复坑34）：每次换图生成新文件名 + 清旧文件——
      // 固定文件名覆盖时 pageBg 的 file:// URI 每次相同，@StorageProp 相同字符串不触发
      // 刷新（已挂载页面不更新，重建页面/重启才正常，真机复现）；唯一名保证 URI 必然变化
      const destPath: string = context.filesDir + '/' + newBgFileName();
      // 拷贝用官方 fd 级姿势（华为官方博客《从相册选取图片保存进应用沙箱》标准流程）：
      // openSync 打开媒体 URI 拿 fd → copyFileSync(fd, fd)。不能用 fs.copy/copyFile 直接传
      // URI 字符串——其对媒体库 URI（file://media/...）解析不可靠，真机报「路径或文件不存在」
      // （2026-08-20 决明实测所有图片均失败后按官方姿势修复）；公共函数 copyFileExact
      copyFileExact(result.photoUris[0], destPath);
      // 校验拷贝结果 + 转 file:// URI：Image 组件加载沙箱文件的标准 URI 形式。
      // 2026-08-20 排查「toast 成功但背景未变」：此前直接存纯路径（/data/storage/...），
      // Image 静默加载失败、页面露出兜底纯色，看起来像没生效；改 file:// URI 后按官方姿势
      const stat: fs.Stat = fs.statSync(destPath);
      const destUri: string = fileUri.getUriFromPath(destPath);
      console.info('image pick copied, size=' + stat.size + ', uri=' + destUri);
      // ★ 流程合并（2026-08-22）：不再 set pageBg / toast「背景已更换」/ 清编辑参数记忆——
      // push 编辑页，保存成功才由调整页写 pageBg 生效；参数记忆清零也移到调整页按编辑源
      // 判定（选图 srcUri≠pageBg 才清零——选图后未走到调整页就取消时旧背景参数不丢，
      // 见 ImageAdjustPage.aboutToAppear 注释）；编辑页/调整页转场、渐变模糊标题栏、
      // 沉浸光感全部沿用现有 PageShell 官方示例，本入口零新增 UI 机制
      this.pathStack.pushPathByName(ROUTE_IMAGE_EDIT_PAGE, { srcUri: destUri } as EditImageParam);
    } catch (err) {
      // toast 带错误码（BusinessError.code），失败时可据此快速定位环节
      const code: number | undefined = (err as BusinessError).code;
      console.error('image pick failed: ' + JSON.stringify(err));
      this.toast('图片处理失败' + (code !== undefined ? ' (' + code + ')' : ''));
    }
  }

  // 恢复默认：清空 pageBg（PersistentStorage 同步持久化）+ 清空背景文件
  // （扫删全部 page_background_*，2026-08-21 唯一名方案配套：文件不再被同名覆盖，
  // 不清会残留孤儿——「恢复默认→再换图」循环每轮 +1，违反数据有界防线；
  // 删除失败仅日志，pageBg 已清空显示官方灰底不受影响，下次换图扫删自愈）+
  // 清零编辑参数记忆三键（2026-08-21 决明反馈：恢复默认后参数残留——参数跟随当前背景图，
  // 无背景即从 0 开始；2026-08-22 补缩放状态键——本处为唯一显式清零点，
  // 选图/编辑当前背景的「新图从 0」已改为读侧判定，不写 AppStorage）
  private restoreDefault(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context !== undefined) {
      cleanBgFiles(context.filesDir, []);
    }
    AppStorage.setOrCreate<string>('pageBg', '');
    AppStorage.setOrCreate<number>(EDIT_BLUR_PCT_KEY, 0);
    AppStorage.setOrCreate<number>(EDIT_MASK_PCT_KEY, 0);
    AppStorage.setOrCreate<number[]>(EDIT_CROP_STATE_KEY, [0, 0, 0]);
    this.toast('已恢复默认背景');
  }

  // 背景仅用于会话页开关卡（2026-09-05 决明指令「恢复默认卡上新增一卡」）：行卡 = 标题 +
  // 说明 + 右侧官方开关（AppearancePage.FallbackSwitchCard 先例——自绘卡 cardBg +
  // borderRadius 16 + CARD_PANEL_WIDTH + 官方 Toggle；开关行非单条目导航卡，不走
  // HdsListItemCard 形态）。@StorageLink 写入即持久化（persistProp 已注册）
  @Builder
  SessionOnlySwitchCard() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(SETTING_TITLE_BG_SESSION_ONLY)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Text('开启后自定义背景只在会话页显示，其他页面用默认底色。关闭后恢复全应用生效')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.bgSessionOnly })
        .onChange((isOn: boolean): void => {
          this.bgSessionOnly = isOn;
        })
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .width(CARD_PANEL_WIDTH)
  }

  build() {
    // 卡片列表布局（2026-08-20 定稿规则，见 AGENTS.md「列表卡片规范」）：从上往下依次排列、
    // 卡片间距统一 CARD_SPACING = 10vp、宽度统一 CARD_PANEL_WIDTH 居中（2026-08-20 定稿：
    // 与光感面板/分段胶囊对齐，见 common/Theme.ets）——外层（AppearancePage
    // 内容区 Column）负责顶对齐与整体留白
    Column({ space: CARD_SPACING }) {
      this.CardItem(SETTING_TITLE_PICK_IMAGE, '选图后进入编辑页调整', () => {
        this.pickImage();
      })
      this.CardItem(SETTING_TITLE_EDIT_IMAGE, '调整当前背景：比例裁剪、模糊与遮罩', () => {
        this.editImage();
      })
      // 开关卡放「恢复默认」上方（2026-09-05 决明指令「恢复默认卡上新增一卡」）
      this.SessionOnlySwitchCard()
      this.CardItem(SETTING_TITLE_RESTORE_DEFAULT, '', () => {
        this.restoreDefault();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
