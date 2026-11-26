// 识别文字页：工作区图片 / PDF 预识别文本的查看与校对——管理页文件行菜单「识别文字 /
// 查看识别文字」或识别完成自动进入。param = WorkspaceOcrPageParam{fileId, name}
//（getParamByName 取末条，声明单源在本件）。内容 = 元信息卡（引擎 / 识别时间 / 已校对；
// stale 加过期提示行 +「重新识别」主键）+ 全高 TextArea 编辑形态；aboutToAppear 现读行 +
// 六列记录 + 文件 stat 指纹派生状态（fresh / stale / none + 校对位）。
// · 保存链：无保存键、onBackPressed 统一落库（值对比 initial，无改动不写库；有改动
//   saveWorkspaceOcrEdit 只写文本与校对时刻、不动指纹列；超 MAX_EXTRACTED_CHARS 拒存留页——
//   校对路是 ocrText 唯一无界写口，上限与识别路抽取闸同源）。本页 pop 恒带 result
//   { ocrChanged: true }（无改动也带）——坑17：识别完成自动进页后无编辑返回，管理页仍要刷新。
// · 重新识别：已校对（ocrEditedAt > 0）先 ConfirmDialog 防毁校对；识别链复用 WorkspaceOcrFlow
//  （注册表守重入），成功页内刷新（基线随新文本重置），失败 toast 留原文。
// · 退出语义：任务与页面解耦——识别中可返回，任务照常落库；aboutToDisappear 调 ocrRelease
//   成对释放（与 ChatPage / 管理页各自页级成对，不打 in-flight 识别）。
import { fileIo as fs } from '@kit.CoreFileKit';
import { MAX_EXTRACTED_CHARS } from '../../common/DocumentParse';
import { PageShell } from '../../common/PageShell';
import { ROUTE_WORKSPACE_OCR_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { formatWorkspaceTime } from '../../common/WorkspaceUtil';
import { workspaceFilesDir } from '../../common/store/WorkspaceDb';
import { WorkspaceOcrRecord, WorkspaceOcrState, ocrStateOf } from '../../common/store/WorkspaceDbOcr';
import { queryWorkspaceOcr, queryWorkspaceRowById, saveWorkspaceOcrEdit } from '../../common/store/ChatDb';
import { ocrEnabled, ocrRelease } from '../../common/OcrEngine';
import { isWorkspaceOcrRunning, startWorkspaceOcr } from '../../common/WorkspaceOcrFlow';
import { WorkspaceFileRow } from '../../common/WorkspaceUtil';
import { ConfirmDialog } from '../chat/ConfirmDialog';

export interface WorkspaceOcrPageParam {
  fileId: string;
  name: string; // 标题用显示名（'' = 页内兜底「识别文字」）
}

@Component
export struct WorkspaceOcrPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 定位与行载荷（构造后不变，坑30；row 由 aboutToAppear 按 id 现读——重识别需派生绝对路径）
  private fileId: string = '';
  private row: WorkspaceFileRow | null = null;
  private absPath: string = '';
  @State private loaded: boolean = false;
  @State private text: string = '';
  @State private ocrState: WorkspaceOcrState = 'none';
  @State private edited: boolean = false;
  @State private engineLabel: string = '';
  @State private ocrAt: number = 0;
  // 重识别进行中（注册表现查冗余位——meta 卡「识别中…」状态行要随之显隐，故必须响应式）
  @State private recognizing: boolean = false;
  // 保存基线（返回链值对比用；重识别成功刷新后随新文本重置）
  private initialText: string = '';
  @StorageProp('appColorMode') appColorMode: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 重新识别确认（覆盖已校对内容时弹；构造在组件成员位——坑7）
  private reconfirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '重新识别',
      message: '将重新识别此文件的文字，当前校对内容会被覆盖。',
      confirmLabel: '重新识别',
      onConfirm: (): void => {
        this.doReRecognize();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_WORKSPACE_OCR_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last === null) {
      this.toast('缺少文件参数');
      this.pathStack.pop();
      return;
    }
    const param = last as WorkspaceOcrPageParam;
    this.fileId = param.fileId;
    queryWorkspaceRowById(this.fileId)
      .then((row: WorkspaceFileRow | null): void => {
        if (this.departed) {
          return; // 页面已亡不再 toast/pop（否则会多退一层）
        }
        if (row === null) {
          this.toast('文件已不在本机');
          this.pathStack.pop();
          return;
        }
        this.row = row;
        const filesDir: string = workspaceFilesDir();
        this.absPath = filesDir === '' ? '' : filesDir + '/' + row.localPath;
        this.reload();
      })
      .catch((_e: Object): void => {
        this.toast('文件读取失败，请重试');
      });
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 与引擎建立成对释放（排队列尾、不打 in-flight 识别）
    ocrRelease();
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 记录与状态现读（首载与重识别完成共用单一路径）：六列记录 + 单文件一次 statSync 指纹
  // 比对——state / 校对位 / 引擎 / 时刻四值派生，文本与基线同点赋值
  private reload(): void {
    queryWorkspaceOcr(this.fileId)
      .then((record: WorkspaceOcrRecord | null): void => {
        if (this.departed) {
          return;
        }
        let curMtime: number = 0;
        let curSize: number = 0;
        if (this.absPath !== '') {
          try {
            const st: fs.Stat = fs.statSync(this.absPath);
            curMtime = st.mtime * 1000;
            curSize = st.size;
          } catch (e) {
            // 文件缺失 = 指纹必不命中，state 落 stale（文本仍可看可校对）
          }
        }
        const state: WorkspaceOcrState = ocrStateOf(record, curMtime, curSize);
        this.ocrState = state;
        this.edited = record !== null && record.ocrEditedAt > 0;
        this.engineLabel = record !== null ? this.engineDisplayName(record.ocrEngine) : '';
        this.ocrAt = record !== null ? record.ocrAt : 0;
        const nextText: string = record !== null ? record.ocrText : '';
        this.text = nextText;
        this.initialText = nextText;
        this.loaded = true;
      })
      .catch((_e: Object): void => {
        this.toast('识别文字读取失败，请重试');
      });
  }

  // 引擎显示名（三引擎内置名 + 文档解析引擎名原样——workspaceDocMetaLine 同口径）
  private engineDisplayName(engine: string): string {
    if (engine === 'system') {
      return '系统识别';
    }
    if (engine === 'builtin') {
      return '内置识别';
    }
    if (engine === 'model') {
      return '视觉模型';
    }
    return engine;
  }

  private metaLine(): string {
    const parts: string[] = [];
    if (this.engineLabel !== '') {
      parts.push('识别引擎 ' + this.engineLabel);
    }
    if (this.ocrAt > 0) {
      parts.push(formatWorkspaceTime(this.ocrAt));
    }
    if (this.edited) {
      parts.push('已校对');
    }
    return parts.join(' · ');
  }

  // 重新识别入口（stale 与常态共用）
  private onReRecognize(): void {
    if (this.row === null) {
      return;
    }
    if (!ocrEnabled()) {
      this.toast('文字识别功能未开启，可在 设置 → 功能模型 中开启');
      return;
    }
    if (this.recognizing || isWorkspaceOcrRunning(this.fileId)) {
      return; // 识别中不重入（注册表单源 + 页面位双守卫）
    }
    if (this.edited) {
      this.reconfirmCtrl.open();
      return;
    }
    this.doReRecognize();
  }

  private doReRecognize(): void {
    const row: WorkspaceFileRow | null = this.row;
    if (row === null) {
      return;
    }
    this.recognizing = true;
    startWorkspaceOcr(row, {
      notify: (msg: string): void => {
        this.toast(msg);
      },
      onComplete: (_fileId: string, _saved: boolean): void => {
        this.recognizing = false;
        // 成败都刷新：成功换新文本（基线随新文本重置），失败留原文本（toast 已由流程给出）
        this.reload();
      }
    });
  }

  // 返回统一落库（值对比 initial 判改动；恒带 result 的分歧点见文件头）
  private onBack(): boolean {
    if (this.text === this.initialText) {
      // 无改动不写库；恒带 result（坑17——管理页 onPop 刷新菜单标签态）
      this.pathStack.pop({ ocrChanged: true });
      return true;
    }
    // 校对路长度闸：识别路文本有 MAX_EXTRACTED_CHARS 抽取上限，校对路是 ocrText 唯一无界写口
    //——超限拒存留页，不静默截断（截断会无声毁用户校对内容）
    if (this.text.length > MAX_EXTRACTED_CHARS) {
      this.toast('识别文字超过 12 万字符上限，请删减后再保存');
      return true;
    }
    saveWorkspaceOcrEdit(this.fileId, this.text)
      .then((): void => {
        if (this.departed) {
          return; // 写库照常，页面已亡不再 pop（否则会多退一层）
        }
        this.pathStack.pop({ ocrChanged: true });
      })
      .catch((_e: Object): void => {
        this.toast('保存失败，请重试');
      });
    return true; // 拦截返回——落库结果回调内再 pop（失败留页）
  }

  build() {
    PageShell({
      title: this.row !== null && this.row.name !== '' ? this.row.name : '识别文字',
      onBackPressed: (): boolean => {
        return this.onBack();
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  @Builder
  Content() {
    Column({ space: 12 }) {
      if (this.loaded) {
        this.MetaCard()
        TextArea({ placeholder: '暂无识别文字', text: this.text })
          .width('100%')
          .layoutWeight(1)
          // 识别中禁编辑：识别完成 reload 以落库文本覆盖 this.text——不闭闸则窗口内手改内容
          // 被静默冲掉（扫描件识别分钟级，窗口真实存在）
          .enabled(!this.recognizing)
          .onChange((value: string): void => {
            this.text = value;
          })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: Math.max(this.topPad, 0) + 12,
      bottom: this.bottomPad + 16
    })
  }

  // 元信息卡：meta 行 + 识别中状态行 + stale 过期提示行 +「重新识别」键（stale 时主键突出）
  @Builder
  MetaCard() {
    Column({ space: 8 }) {
      if (this.metaLine() !== '') {
        Text(this.metaLine())
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      if (this.recognizing) {
        Text('识别中，完成后自动刷新…')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      if (this.ocrState === 'stale') {
        Text('文件已更新，此文字已过期')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
      }
      Button('重新识别')
        .fontSize(14)
        .fontColor(fallbackButtonFont(this.contentFallback, this.ocrState === 'stale'))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel,
          this.ocrState === 'stale'))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel,
          this.ocrState === 'stale'))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.onReRecognize();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
