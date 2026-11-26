// HTTP 请求模板域：列表页（HttpTemplatePage）+ 编辑页（HttpTemplateEditPage）同一文件。
// · 列表页：入口 = 设置页「请求模板」卡（push 无参）；行卡点行进编辑；删除唯一走行左滑确认链；
//   刷新 = pushPathByName 第三参 onPop 回调（坑17：编辑页保存 pop({ saved: true }) 才触发）。
// · 编辑页：param = 'new' | 模板 id；保存 = 校验 → 落库 → syncTemplateTools → toast →
//   pop({ saved: true })；「保存」键在标题栏（官方数组 menuHds）。
//   导入两路 = cURL 粘贴解析 + OpenAPI 摘要拉取（弹窗填 URL → GET JSON → 点草稿行预填表单）。
// ★ 同名撞车 = 保存时就地拒绝（httpTemplateNameTaken 排除自身）；模板参数不含明文凭据
//（headers 值用 {{凭据名称}} 引用，真值永不入库——凭据库同款红线）。
// 卡壳四件套 = CARD_PANEL_WIDTH / padding(16) / cardBg / 圆角 CARD_RADIUS（宿主无左右 16vp padding）。
// 行键纪律详见各处键注释：行键 = uid（防旧组件复用），参数行键另含 position/required，
// 文本字段不入键防丢焦点；chips 点选走 replaceParamRow 整行替换。卡内操作键 = 全宽主/淡彩次级键形制。
import { http } from '@kit.NetworkKit';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import {
 CARD_PANEL_WIDTH, SEGMENT_BAR_HEIGHT, cardBg, cardBorderColor, cardDescColor,
  cardTitleColor, badgeBg, selectChipBg, selectChipBorderColor, selectChipTextColor, CARD_RADIUS
} from '../../common/Theme';
import { HeaderPair } from '../../common/providers/AiTypes';
import { KeyValueWell } from '../KeyValueWell';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBgTinted, fallbackButtonFontTinted,
  fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InfoCard } from '../InfoCard';
import { InputDialog } from '../chat/InputDialog';
import { SETTING_TITLE_HTTP_TEMPLATES } from '../../common/SettingSearch';
import { ROUTE_HTTP_TEMPLATE_EDIT_PAGE } from '../../common/RouteNames';
import { countHttpTemplates, deleteHttpTemplate, httpTemplateNameTaken,
  insertHttpTemplate, HTTP_TEMPLATES_MAX, HTTP_TEMPLATE_NAME_MAX_CHARS,
  HTTP_TEMPLATE_PARAMS_MAX, queryHttpTemplateById, queryHttpTemplates,
  updateHttpTemplate, HttpTemplateInput, HttpTemplateRow } from '../../common/store/HttpTemplateDb';
import { TemplateHeader, TemplateParam } from '../../common/providers/HttpTemplate';
import { applyEffectiveProxy } from '../../common/providers/RequestIdentity';
import { SegmentBar } from '../SegmentBar';
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { parseCurlCommand, parseOpenApiSummary, placeholderNames, syncTemplateTools,
  templateInputFromOpenApi, validateTemplateInput, CurlDraft, OpenApiDraft,
  OpenApiOperation } from '../../common/providers/HttpTemplate';

// 表单行 uid 计数器（模块级自增，ForEach 键用；运行时标识不落库，各构造点一律走本函数）
let rowUidSeq: number = 0;

function allocRowUid(): number {
  rowUidSeq++;
  return rowUidSeq;
}

// 编辑页表单参数行（@State 数组元素；manual = 手工添加的查询参数，非占位自动发现）
interface ParamEditRow {
  name: string;
  position: string;
  desc: string;
  required: boolean;
  manual: boolean;
  uid: number;
}

// 方法五档（HEAD/OPTIONS 属低频调试位，用 http_request 原生工具；白名单单源在 ToolHttp）
const TEMPLATE_METHODS: string[] = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

// 参数位置 chips（显示文案与存储值同序双数组，选中态按存储值比对）
const TEMPLATE_POSITION_LABELS: string[] = ['路径', '查询', '正文', '请求头'];
const TEMPLATE_POSITION_VALUES: string[] = ['path', 'query', 'body', 'header'];

const TEMPLATE_HEADERS_MAX: number = 5;

// 导入卡折叠动画时长（与全站折叠同族 300ms + EaseInOut，UIContext 形态）
const FOLD_ANIM_MS: number = 300;

// ═══ 列表页 ═══
@Component
export struct HttpTemplatePage {
  // 页面存活守卫：置位后迟到异步回调不写状态不碰 UI 不上行，写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 光感档 + 内容区回退能力位（fallbackButton* 四件套消费；订阅式即刷，坑16 正解）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @State private rows: HttpTemplateRow[] = [];
  // 删除确认（惰性构造——坑7 形态豁免：open 前才 new，PriceTemplateEditPage 同款）
  private confirmCtrl: CustomDialogController | null = null;
  private pendingDeleteId: number = -1;
  private pendingDeleteName: string = '';
  // 行左滑删除互斥组（reload / 滚动开始两路收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();

  aboutToAppear(): void {
    this.reload();
    // 注册表同步兜底（启动链已同步；接旁路改动窗口，幂等零开销）
    syncTemplateTools();
  }

  private reload(): void {
    queryHttpTemplates().then((rows: HttpTemplateRow[]): void => {
      if (this.departed) {
        return;
      }
      this.rows = rows;
      // 整组重拉即收口左滑展开态（删行后原行销毁，双保险）
      this.swipeGroup.collapse();
    }).catch((_e: Object): void => {
      // 库读失败保旧态（下次进出页重拉）
    });
  }

  private hostOf(urlTemplate: string): string {
    const m: RegExpMatchArray | null = urlTemplate.match(/^https?:\/\/([^/?#]+)/);
    return m !== null ? m[1] : urlTemplate;
  }

  private openDeleteConfirm(id: number, name: string): void {
    this.pendingDeleteId = id;
    this.pendingDeleteName = name;
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除模板',
        message: '将删除模板「' + name + '」，助手将不再能调用它。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.removeRow();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private removeRow(): void {
    const id: number = this.pendingDeleteId;
    this.pendingDeleteId = -1;
    deleteHttpTemplate(id).then((): Promise<void> => syncTemplateTools()).then((): void => {
      if (this.departed) {
        return;
      }
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
    }).catch((_e: Object): void => {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    });
  }

  // 左滑删除入口（RowSwipeDelete onSwipeDelete 单源）：按 id 走既有确认链
  private askDeleteById(id: string): void {
    const row: HttpTemplateRow | undefined =
      this.rows.find((item: HttpTemplateRow): boolean => String(item.id) === id);
    if (row !== undefined) {
      this.openDeleteConfirm(row.id, row.name);
    }
  }

  // 模板行卡（RowSwipeDelete content 位）
  @Builder
  TemplateRow(row: HttpTemplateRow) {
    // ★ Row → Button 包壳取官方原生按压蒙层；蒙层边距 = 卡底 Column padding 4，内容 padding 12 回添
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(row.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(row.method + ' · ' + this.hostOf(row.urlTemplate))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
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
        this.pathStack.pushPathByName(ROUTE_HTTP_TEMPLATE_EDIT_PAGE, String(row.id),
          (): void => {
            this.reload();
          });
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        InfoCard({
          title: SETTING_TITLE_HTTP_TEMPLATES,
          text: '把常用接口存成模板后，助手把它当作一件带名字的工具调用，只需填参数，不用自己拼网址。写操作仍按确认档询问。'
        })
        if (this.rows.length === 0) {
          Column({ space: 2 }) {
            Text('还没有模板。')
              .fontSize(14)
              .fontColor(cardDescColor())
            Text('点下方按钮新建，或进编辑页粘贴一条 cURL 命令快速生成。')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .width(CARD_PANEL_WIDTH)
        }
        ForEach(this.rows, (row: HttpTemplateRow) => {
          // 行左滑删除层（askDeleteById 确认链）；展开态不进键
          RowSwipeDelete({
            rowId: String(row.id),
            group: this.swipeGroup,
            content: (): void => {
              this.TemplateRow(row)
            },
            onSwipeDelete: (rowId: string): void => {
              this.askDeleteById(rowId);
            }
          })
        }, (row: HttpTemplateRow): string =>
          // 键 = 行 id + 可变展示成分（name/method/urlTemplate，副行 host 由此派生）：裸 id 键在
          // reload 整组替换后键集合不变，旧行卡复用、Text 停旧内容（规范-数据存储获取刷新方案 §3 同族）
          row.id + '|' + row.name + '|' + row.method + '|' + row.urlTemplate)
        // 新建键（淡彩次级档，形制走 fallbackButton*Tinted 族）
        Button('新建模板')
          .fontColor(fallbackButtonFontTinted(this.contentFallback))
          .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
          .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .width(CARD_PANEL_WIDTH)
          .height(44)
          .onClick((): void => {
            this.openEditPage('new');
          })
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
    // 滚动开始即收口左滑展开态（会话列表/五库同口径）
    .onScrollStart((): void => {
      this.swipeGroup.collapse();
    })
  }

  private openEditPage(param: string): void {
    if (param === 'new' && this.rows.length >= HTTP_TEMPLATES_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '模板最多 ' + HTTP_TEMPLATES_MAX + ' 个，请先删除不用的模板'
      });
      return;
    }
    this.pathStack.pushPathByName(ROUTE_HTTP_TEMPLATE_EDIT_PAGE, param, (): void => {
      this.reload();
    });
  }

  build() {
    PageShell({
      title: SETTING_TITLE_HTTP_TEMPLATES,
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// ═══ 编辑页 ═══
@Component
export struct HttpTemplateEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态不碰 UI 不上行，写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 表单值（页内 @State 持有，无父页 @Link 链；BalanceConfigPage 同款）
  @State private editId: number = -1; // -1 = 新建
  @State private origName: string = ''; // 同名查重排除自身
  @State private name: string = '';
  @State private methodIdx: number = 0;
  @State private urlTemplate: string = '';
  // 请求头行组（挂 KeyValueWell，行键与增删下沉井内）
  @State private headerRows: HeaderPair[] = [];
  @State private bodyTemplate: string = '';
  @State private params: ParamEditRow[] = [];
  @State private curlText: string = '';
  // OpenAPI 拉取（卡内地址输入行已退役，地址经「拉取」弹窗回调实参下传）
  @State private apiDraft: OpenApiDraft | null = null;
  @State private fetching: boolean = false;
  // 导入卡展开态（默认收起，纯 UI 态不持久化）
  @State private importOpen: boolean = false;
  // 保存进行中闸（防重入；无渲染依赖，不入 @State）
  private saving: boolean = false;
  private methodItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: 'GET' },
    { text: 'POST' },
    { text: 'PUT' },
    { text: 'DELETE' },
    { text: 'PATCH' }
  ]);
  // 拉取接口文档弹窗（组件成员位构造——坑7 形态豁免；材质挂 overlayMaterial）
  private docCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '拉取接口文档',
      placeholder: '例如 https://api.example.com/openapi.json',
      confirmLabel: '拉取',
      onConfirm: (text: string): void => {
        this.fetchOpenApi(text);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  // cURL 粘贴弹窗（多行输入；确认即解析回填，失败 toast 由 importCurl 给）
  private curlCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '粘贴 cURL',
      placeholder: '粘贴 curl 命令',
      confirmLabel: '解析并填入',
      multiline: true,
      onConfirm: (text: string): void => {
        this.curlText = text;
        this.importCurl();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    try {
      const params: string[] =
        (this.pathStack.getParamByName(ROUTE_HTTP_TEMPLATE_EDIT_PAGE) ?? []) as string[];
      const param: string = params.length > 0 ? params[params.length - 1] : 'new';
      if (param !== 'new') {
        const id: number = parseInt(param, 10);
        // 按 id 查（slug 列在 insert 回填窗口可空，id 主键恒命中）
        if (Number.isFinite(id)) {
          queryHttpTemplateById(id).then((row: HttpTemplateRow | null): void => {
            if (row !== null) {
              this.fillFromRow(row);
            }
          }).catch((_e: Object): void => {
            // 载入失败留空表单，保存校验会拦空 URL
          });
        }
      }
    } catch (e) {
      // param 缺失按新建（入口唯一，理论不可达）
    }
  }

  private fillFromRow(row: HttpTemplateRow): void {
    this.editId = row.id;
    this.origName = row.name;
    this.name = row.name;
    const idx: number = TEMPLATE_METHODS.indexOf(row.method);
    this.methodIdx = idx >= 0 ? idx : 0;
    this.urlTemplate = row.urlTemplate;
    this.bodyTemplate = row.bodyTemplate;
    const rows: HeaderPair[] = [];
    try {
      const arr: object = JSON.parse(row.headersJson);
      if (Array.isArray(arr)) {
        for (const item of arr as object[]) {
          const rec = item as Record<string, Object>;
          const n: Object = rec['name'];
          const v: Object = rec['value'];
          if (typeof n === 'string' && typeof v === 'string') {
            rows.push({ k: n, v: v });
          }
        }
      }
    } catch (e) {
      // 脏库数据按无头处理
    }
    this.headerRows = rows;
    const ps: ParamEditRow[] = [];
    try {
      const arr: object = JSON.parse(row.paramsJson);
      if (Array.isArray(arr)) {
        for (const item of arr as object[]) {
          const rec = item as Record<string, Object>;
          const n: Object = rec['name'];
          const p: Object = rec['position'];
          if (typeof n === 'string' && typeof p === 'string') {
            const d: Object = rec['desc'];
            ps.push({
              name: n, position: p, desc: typeof d === 'string' ? d : '',
              required: rec['required'] === true, manual: p === 'query', uid: allocRowUid()
            });
          }
        }
      }
    } catch (e) {
      // 脏库数据按无参处理
    }
    this.params = ps;
  }

  // 占位自动发现（URL/头值/正文变化后调）：新占位按出处默认位置入参表，已存在的跳过
  private syncParamDiscover(): void {
    const known: string[] = this.params.map((p: ParamEditRow): string => p.name);
    const seed: ParamEditRow[] = [];
    const fromUrl: string[] = placeholderNames(this.urlTemplate);
    for (const n of fromUrl) {
      if (!known.includes(n)) {
        seed.push({ name: n, position: 'path', desc: '', required: true, manual: false,
          uid: allocRowUid() });
        known.push(n);
      }
    }
    for (const h of this.headerRows) {
            for (const n of placeholderNames(h.v)) {
        if (!known.includes(n)) {
          seed.push({ name: n, position: 'header', desc: '', required: true, manual: false,
            uid: allocRowUid() });
          known.push(n);
        }
      }
    }
    for (const n of placeholderNames(this.bodyTemplate)) {
      if (!known.includes(n)) {
        seed.push({ name: n, position: 'body', desc: '', required: true, manual: false,
          uid: allocRowUid() });
        known.push(n);
      }
    }
    if (seed.length > 0) {
      this.params = this.params.concat(seed);
    }
  }

  private headerRecord(): string {
    const arr: TemplateHeader[] = [];
    for (const h of this.headerRows) {
      if (h.k.trim() !== '') {
        const row: TemplateHeader = { name: h.k.trim(), value: h.v };
        arr.push(row);
      }
    }
    return JSON.stringify(arr);
  }

  private paramsRecord(): string {
    const arr: TemplateParam[] = [];
    for (const p of this.params) {
      if (p.name.trim() !== '') {
        const row: TemplateParam = {
          name: p.name.trim(), position: p.position, desc: p.desc, required: p.required
        };
        arr.push(row);
      }
    }
    return JSON.stringify(arr);
  }

  private methodValue(): string {
    return TEMPLATE_METHODS[this.methodIdx];
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return; // 防重入：双击保存会两次并发过查重窗、各自插入同名模板（查重无 UNIQUE 兜底）
    }
    this.saving = true;
    try {
      await this.saveInner();
    } finally {
      this.saving = false;
    }
  }

  private async saveInner(): Promise<void> {
    const method: string = this.methodValue();
    const name: string = this.name.trim();
    if ((method === 'GET' || method === 'HEAD') && this.bodyTemplate.trim() !== '') {
      this.getUIContext().getPromptAction().showToast({
        message: 'GET 与 HEAD 请求不带正文，请清空正文模板或改用 POST'
      });
      return;
    }
    if (this.bodyTemplate.trim() !== '' &&
      placeholderNames(this.bodyTemplate).length > 0 &&
      !this.params.some((p: ParamEditRow): boolean => p.position === 'body')) {
      this.getUIContext().getPromptAction().showToast({
        message: '正文里的占位还没有定义为请求体参数'
      });
      return;
    }
    const invalid: string = validateTemplateInput(name, this.urlTemplate.trim(),
      this.headerRecord(), this.bodyTemplate, this.paramsRecord(),
      HTTP_TEMPLATE_NAME_MAX_CHARS, HTTP_TEMPLATE_PARAMS_MAX);
    if (invalid !== '') {
      this.getUIContext().getPromptAction().showToast({ message: invalid });
      return;
    }
    if (name !== this.origName) {
      const taken: boolean = await httpTemplateNameTaken(name);
      if (this.departed) {
        return;
      }
      if (taken) {
        this.getUIContext().getPromptAction().showToast({
          message: '已有同名模板，请换一个名称'
        });
        return;
      }
    }
    const input: HttpTemplateInput = {
      name: name, method: method, urlTemplate: this.urlTemplate.trim(),
      headersJson: this.headerRecord(), bodyTemplate: this.bodyTemplate,
      paramsJson: this.paramsRecord()
    };
    try {
      if (this.editId >= 0) {
        await updateHttpTemplate(this.editId, input);
      } else {
        const count: number = await countHttpTemplates();
        if (this.departed) {
          return;
        }
        if (count >= HTTP_TEMPLATES_MAX) {
          this.getUIContext().getPromptAction().showToast({
            message: '模板最多 ' + HTTP_TEMPLATES_MAX + ' 个，请先删除不用的模板'
          });
          return;
        }
        await insertHttpTemplate(input);
        if (this.departed) {
          return;
        }
      }
      await syncTemplateTools();
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.pathStack.pop({ saved: true });
    } catch (e) {
      if (this.departed) {
        return;
      }
      // 库层兜底闸（HTTP_TEMPLATES_FULL）不直拼上屏——特判给中文，其余通用提示
      const msg: string = (e as Error).message;
      this.getUIContext().getPromptAction().showToast({
        message: msg === 'HTTP_TEMPLATES_FULL' ?
          '模板最多 ' + HTTP_TEMPLATES_MAX + ' 个，请先删除不用的模板' : '保存失败，请重试'
      });
    }
  }

  private importCurl(): void {
    const draft: CurlDraft | null = parseCurlCommand(this.curlText);
    if (draft === null) {
      this.getUIContext().getPromptAction().showToast({
        message: '没有解析出请求地址，请检查粘贴的命令'
      });
      return;
    }
    // 非五档方法保守落 GET 读档——落 POST 会把 HEAD 探测 / OPTIONS 协商静默改写成写方法
    const idx: number = TEMPLATE_METHODS.indexOf(draft.method);
    const methodFallback: boolean = idx < 0;
    this.methodIdx = methodFallback ? 0 : idx;
    this.urlTemplate = draft.url;
    const rows: HeaderPair[] = [];
    for (let i = 0; i < draft.headerNames.length && i < TEMPLATE_HEADERS_MAX; i++) {
      rows.push({ k: draft.headerNames[i], v: draft.headerValues[i] });
    }
    this.headerRows = rows;
    this.bodyTemplate = draft.body;
    this.syncParamDiscover();
    this.getUIContext().getPromptAction().showToast({
      message: methodFallback ?
        '方法 ' + draft.method + ' 不在支持列表，已按 GET 填入' : '已填入表单，占位参数已识别'
    });
  }

  // OpenAPI 文档拉取（用户主动操作，不走工具域闸；一建一销 + finally destroy，15 秒超时）。
  // ★ 必须注入生效代理（applyEffectiveProxy）——配了代理的用户按直连拉外网文档必败，与传输两路同口径
  private async fetchOpenApi(urlText: string): Promise<void> {
    const url: string = urlText.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.getUIContext().getPromptAction().showToast({
        message: '请填写以 http:// 或 https:// 开头的文档地址'
      });
      return;
    }
    this.fetching = true;
    const req: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000,
        usingCache: false,
        maxLimit: 2 * 1024 * 1024
      };
      applyEffectiveProxy(options);
      const resp: http.HttpResponse = await req.request(url, options);
      if (this.departed) {
        return;
      }
      const okCode: boolean = resp.responseCode >= 200 && resp.responseCode < 300;
      const bodyText: string = typeof resp.result === 'string' ? resp.result : '';
      if (!okCode) {
        this.getUIContext().getPromptAction().showToast({
          message: '文档拉取失败，对方返回状态 ' + resp.responseCode
        });
        return;
      }
      if (bodyText === '') {
        // 2xx 无响应体单独给因——与状态失败共用文案会报「返回状态 200」自相矛盾
        this.getUIContext().getPromptAction().showToast({
          message: '对方返回了空内容，请确认文档地址后重试'
        });
        return;
      }
      const draft: OpenApiDraft | null = parseOpenApiSummary(bodyText, HTTP_TEMPLATES_MAX);
      if (draft === null || draft.ops.length === 0) {
        this.getUIContext().getPromptAction().showToast({
          message: '没有解析出接口。目前只支持 JSON 格式的 OpenAPI 文档'
        });
        return;
      }
      this.apiDraft = draft;
      this.getUIContext().getPromptAction().showToast({
        message: '解析出 ' + draft.ops.length + ' 个接口，点接口行填入表单'
      });
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({
        message: '文档拉取失败，请检查地址与网络后重试'
      });
    } finally {
      try {
        req.destroy();
      } catch (e) {
      }
      this.fetching = false;
    }
  }

  private applyOpenApiOp(op: OpenApiOperation): void {
    if (this.apiDraft === null) {
      return;
    }
    const input = templateInputFromOpenApi(this.apiDraft.base, op, HTTP_TEMPLATE_NAME_MAX_CHARS);
    this.name = input.name;
    const idx: number = TEMPLATE_METHODS.indexOf(input.method);
    this.methodIdx = idx >= 0 ? idx : 0;
    this.urlTemplate = input.urlTemplate;
    this.bodyTemplate = input.bodyTemplate;
    // ★ OpenAPI 回填按 input.headersJson 重置请求头行组：不清则上一接口的请求头（可含认证头）
    // 残留并写进新模板——模板即权威预设，防不一致态
    const headerRows: HeaderPair[] = [];
    try {
      const arr: object = JSON.parse(input.headersJson);
      if (Array.isArray(arr)) {
        for (const item of arr as object[]) {
          const rec = item as Record<string, Object>;
          const n: Object = rec['name'];
          const v: Object = rec['value'];
          if (typeof n === 'string' && typeof v === 'string') {
            headerRows.push({ k: n, v: v });
          }
        }
      }
    } catch (e) {
      // 纯函数产物理论合法；防御不炸 UI
    }
    this.headerRows = headerRows;
    const ps: ParamEditRow[] = [];
    try {
      const arr: object = JSON.parse(input.paramsJson);
      if (Array.isArray(arr)) {
        for (const item of arr as object[]) {
          const rec = item as Record<string, Object>;
          const n: Object = rec['name'];
          const p: Object = rec['position'];
          if (typeof n === 'string' && typeof p === 'string') {
            const d: Object = rec['desc'];
            ps.push({
              name: n, position: p, desc: typeof d === 'string' ? d : '',
              required: rec['required'] === true, manual: p === 'query', uid: allocRowUid()
            });
          }
        }
      }
    } catch (e) {
      // 纯函数产物理论合法；防御不炸 UI
    }
    this.params = ps;
    this.getUIContext().getPromptAction().showToast({ message: '已填入表单' });
  }

  // 添加请求头（井的 onAddRow 钩子）：超限给 toast 而非隐藏按钮（让用户知道为什么加不了）
  private addHeaderRow(): void {
    if (this.headerRows.length >= TEMPLATE_HEADERS_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '最多添加 ' + TEMPLATE_HEADERS_MAX + ' 组请求头'
      });
      return;
    }
    const row: HeaderPair = { k: '', v: '' };
    this.headerRows = this.headerRows.concat([row]);
  }

  private addQueryParam(): void {
    if (this.params.length >= HTTP_TEMPLATE_PARAMS_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '参数最多 ' + HTTP_TEMPLATE_PARAMS_MAX + ' 个'
      });
      return;
    }
    const row: ParamEditRow = {
      name: '', position: 'query', desc: '', required: false, manual: true, uid: allocRowUid()
    };
    this.params = this.params.concat([row]);
  }

  // 参数行整行替换：chips 点选原地改属性不驱动渲染——@State 只观察变量重赋值与数组 API
  //〔坑80 家族〕；重赋值使 diff 触发、该行重建 chips 即刷，文本值随新对象带回不丢（键仍不含文本字段）
  private replaceParamRow(idx: number, row: ParamEditRow): void {
    this.params = this.params.map((x: ParamEditRow, i: number): ParamEditRow =>
      i === idx ? row : x);
  }

  @Builder
  FieldLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(cardDescColor())
      .width('100%')
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 基本卡 ──
        Column({ space: 10 }) {
          this.FieldLabel('模板名称')
          TextInput({ text: this.name, placeholder: '例如 查询天气' })
            .fontSize(14)
            .height(40)
            .width('100%')
            .onChange((value: string): void => {
              this.name = value;
            })
          this.FieldLabel('请求方法')
          Column() {
            SegmentBar({
              items: this.methodItems,
              selectedIndex: $methodIdx
            })
          }
          .width('100%')
          .height(SEGMENT_BAR_HEIGHT)
          this.FieldLabel('URL 模板。路径参数用大括号写占位，例如 /v1/weather/{city}')
          TextInput({ text: this.urlTemplate,
            placeholder: '例如 https://api.example.com/v1/weather/{city}' })
            .fontSize(14)
            .height(40)
            .width('100%')
            .onChange((value: string): void => {
              this.urlTemplate = value;
              this.syncParamDiscover();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // 请求头卡（行组下沉 KeyValueWell；本页只留 onRowEdited = 改值后重跑占位发现）
        Column({ space: 10 }) {
          this.FieldLabel('请求头')
          KeyValueWell({
            rows: $headerRows,
            keyPlaceholder: '名称',
            valuePlaceholder: '值。密钥写 {{凭据名}}',
            addLabel: '＋ 添加请求头',
            emptyHint: '暂无请求头。接口不需要额外头时可以不填',
            onAddRow: (): void => {
              this.addHeaderRow();
            },
            onRowEdited: (): void => {
              this.syncParamDiscover();
            }
          })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // ── 正文卡 ──
        Column({ space: 10 }) {
          this.FieldLabel('正文模板。仅 POST PUT PATCH 使用，占位写法同上')
          TextArea({ text: this.bodyTemplate, placeholder: '例如 {"city": "{city}"}' })
            .fontSize(14)
            .height(80)
            .width('100%')
            .onChange((value: string): void => {
              this.bodyTemplate = value;
              this.syncParamDiscover();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // ── 参数卡 ──
        Column({ space: 10 }) {
          this.FieldLabel('参数。URL、请求头和正文里的占位会自动出现在这里，查询参数请手工添加')
          if (this.params.length === 0) {
            Text('还没有参数。模板没有参数也能保存，助手调用时直接发送。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
          ForEach(this.params, (p: ParamEditRow, idx: number) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                TextInput({ text: p.name, placeholder: '参数名' })
                  .fontSize(14)
                  .height(36)
                  .layoutWeight(1)
                  .onChange((value: string): void => {
                    p.name = value;
                  })
                Button() {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .onClick((): void => {
                  this.params = this.params.filter((_x: ParamEditRow, i: number): boolean =>
                    i !== idx);
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              Row({ space: 6 }) {
                ForEach(TEMPLATE_POSITION_VALUES, (pos: string, pidx: number) => {
                  Text(TEMPLATE_POSITION_LABELS[pidx])
                    .fontSize(12)
                    .fontColor(selectChipTextColor(p.position === pos, this.appColorMode))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(12)
                    .backgroundColor(selectChipBg(p.position === pos, this.appColorMode))
                    .border({ width: 1, color: selectChipBorderColor(p.position === pos) })
                    .onClick((): void => {
                      // 整行替换经 replaceParamRow（原地改属性不驱动渲染）
                      this.replaceParamRow(idx, {
                        name: p.name, position: pos, desc: p.desc, required: p.required,
                        manual: p.manual, uid: p.uid
                      });
                    })
                }, (pos: string): string => pos)
                Blank()
                Text(p.required ? '必填' : '可省')
                  .fontSize(12)
                  .fontColor(selectChipTextColor(p.required, this.appColorMode))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(12)
                  .backgroundColor(selectChipBg(p.required, this.appColorMode))
                  .border({ width: 1, color: selectChipBorderColor(p.required) })
                  .onClick((): void => {
                    this.replaceParamRow(idx, {
                      name: p.name, position: p.position, desc: p.desc, required: !p.required,
                      manual: p.manual, uid: p.uid
                    });
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              TextInput({ text: p.desc, placeholder: '参数说明，例如 城市名' })
                .fontSize(13)
                .height(36)
                .width('100%')
                .onChange((value: string): void => {
                  p.desc = value;
                })
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor(badgeBg(this.appColorMode))
          }, (p: ParamEditRow): string =>
            // 键 = 行 uid（身份位：原下标键删中间行后余行复用旧组件、TextInput 停旧内容）+ position/
            // required（不入则 itemBuilder 不重执行、chips 点击无视觉反馈；入键经 replaceParamRow
            // 整行替换〔uid 继承〕后该行即重建）。文本字段 name/desc 刻意不入键——输入中重建会丢焦点
            //〔坑80 家族权衡〕
            'p' + p.uid + '-' + p.position + '-' + (p.required ? '1' : '0'))
          // 卡内全宽淡彩次级键（形制见文件头）
          Button('添加查询参数')
            .fontColor(fallbackButtonFontTinted(this.contentFallback))
            .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
            .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .width('100%')
            .onClick((): void => {
              this.addQueryParam();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
        // ── 导入卡（cURL + OpenAPI 合并一张、默认收起——常驻两张卡会把「参数」卡顶到第二屏）──
        Column({ space: 10 }) {
          Row() {
            Text('从别处导入')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([cardDescColor()])
              .rotate({ angle: this.importOpen ? 180 : 0 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
              (): void => {
                this.importOpen = !this.importOpen;
              });
          })
          Text('粘贴一条 cURL 命令，或拉取 OpenAPI 文档，方法、地址、请求头与正文会自动填进上面的表单')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          if (this.importOpen) {
            // cURL 段（粘一条命令即整组回填；卡面只留入口键，粘贴区走弹窗）
            Button('粘贴 cURL 命令')
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .width('100%')
              .onClick((): void => {
                this.curlCtrl.open();
              })
            // 段间 hairline（两段同属「从别处拿现成定义」，动作互不相干）
            Divider()
              .strokeWidth(0.5)
              .color(cardBorderColor(this.appColorMode))
            // OpenAPI 段（文档地址经弹窗回调进入拉取链，fetching 期间禁用）
            Button(this.fetching ? '拉取中' : '拉取 OpenAPI 文档')
              .fontColor(fallbackButtonFontTinted(this.contentFallback))
              .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
              .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .width('100%')
              .enabled(!this.fetching)
              .onClick((): void => {
                if (!this.fetching) {
                  this.docCtrl.open();
                }
              })
            if (this.apiDraft !== null) {
              ForEach(this.apiDraft.ops, (op: OpenApiOperation) => {
                Column({ space: 2 }) {
                  Row({ space: 8 }) {
                    Text(op.method)
                      .fontSize(12)
                      .fontColor(cardDescColor())
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(10)
                      .backgroundColor(badgeBg(this.appColorMode))
                    Text(op.path)
                      .fontSize(13)
                      .fontColor(cardTitleColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                  if (op.summary !== '') {
                    Text(op.summary)
                      .fontSize(12)
                      .fontColor(cardDescColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(10)
                .borderRadius(12)
                .backgroundColor(badgeBg(this.appColorMode))
                .onClick((): void => {
                  this.applyOpenApiOp(op);
                })
              }, (op: OpenApiOperation): string => op.method + op.path)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .width(CARD_PANEL_WIDTH)
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
      title: this.editId >= 0 ? '编辑模板' : '新建模板',
      menuHds: this.saveMenuHds(),
      content: (): void => {
        this.Content()
      }
    })
  }

  // 保存键（标题栏官方数组；「保存」类主操作键）
  private saveMenuHds(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.checkmark'),
          action: (): void => {
            this.save();
          }
        }
      }]
    } as HdsNavigationMenuContentOptions;
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
