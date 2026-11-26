// 工作区列表渲染域（自 WorkspaceManagePage 域级最小拆分迁出，拆分轴照 MemoryLibraryRows）：壳
//（WorkspaceManagePage / WorkspaceSessionView）= 数据装载 / 动作编排 / 弹窗 / 导航；本件 = 纯渲染 +
// 事件上抛——数据源（LazyForEach 契约）+ 扁平项类型与派生（workspaceEntryKey / workspaceEntryAddr）+
// 行卡族（位置卡 / 文件夹行 / 文件行）+ 空态与失败卡，管理页三视图共用。
// · 本件零文件 IO、零 ChatDb/WorkspaceDb 直调（IO 与库全在壳侧；负向钉守）；移动目标派生与执行全在壳侧
//（行卡只上行 onMove 意图，候选差异〔当前目录/自身/子树排除〕归 WorkspaceUtil.deriveWorkspaceMoveTargets 单源）。
// · 行卡成员一律普通成员非响应式（LazyForEach 键控重建 = 行卡唯一更新路径，创建时值恒正确）；行内键须含
// 全部可变展示成分（workspaceEntryKey）——键不全 = 改名/移动/覆盖写后卡面停在旧值（坑44 家族）。
// · 多选三成员（selectMode / selected / onToggle，全普通成员）：勾选态刷新走键驱动——壳侧键生成器把勾选位
// 并入行键 + 数据源 refresh() 重派 onDataReloaded ⇒ 被勾行键变重建、其余键不变复用。多选态行尾四点键换
// 官方勾选圈（Checkbox 纯视觉 hitTestBehavior(None)——坑5：自带点击会消费事件），点卡切换勾选、原动作让位。
// · 行卡组件命名带 Card 后缀避让 WorkspaceUtil 导出的 WorkspaceFileRow 类型（TS2440 导入名冲突）。
// · 图标符号名：folder / square_and_pencil / arrowshape_right / trash / share / ellipsis_circle /
//   square_grid_2x2 / doc_plaintext 为既有在用名；新增 pdf_doc / doc_zipper / music / video 须走坑72 两道门。
// · 菜单 = 行尾四点键 bindMenu 双参 REGULAR 材质（66b 组守）+ 组件内 @Builder（坑51 载体纪律）；「移动」
//   项点击上行 onMove（原 STACK 二级子菜单退役，目标选择归管理页半模态；候选为空时壳侧出指引 toast）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { WorkspaceFileRow, formatWorkspaceSize,
  sourceLabel, workspaceIconTierOf, workspaceParentDir } from '../../common/WorkspaceUtil';
import { cardBg, cardDescColor, cardTitleColor, menuDividerColor, CARD_RADIUS } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { formatConvTime } from '../chat/SessionSearchPanels';

// 扁平列表项（两视图共用行载荷：文件夹视图 = 文件夹行 + 文件行；会话视图组列表 = 会话行自绘、文件行复用本件）
export interface WorkspaceListEntry {
  key: string;            // 键含全部可变展示成分（workspaceEntryKey 单源派生）
  kind: string;           // 'folder' | 'file'
  row: WorkspaceFileRow | null; // 文件行载荷（folder 行为 null）
  absPath: string;        // 运行时绝对路径（filesDir + '/' + localPath；folder 行恒 ''）
  dirName: string;        // 文件夹行段名
  dirPath: string;        // 文件夹行完整 dir 路径
  fileCount: number;      // 文件夹行「N 个文件」（list 工具回执同源计数）
  // 文件夹行直接子文件夹数（deriveWorkspaceDirListing 同源——显式目录行与文件路径派生段按名去重全集；
  // undefined = 文件行/未装配，消费按 0。副标题三态判据位：fileCount>0「N 个文件」/ folderCount>0「M 个文件夹」/ 全零「空文件夹」）
  folderCount?: number;
  // 文件夹行显示名（助手文件夹 UI 显示助手名——undefined = 用 dirName 原名；定位/动作恒用 dirName 原值
  //〔库操作名 ≠ 显示名〕，反查失败不填 = 回退原名不谎报）
  displayName?: string;
  // 识别文字态位（只文件行由壳侧派生；undefined = 本行不出「识别文字」菜单项——非识别对象或总开关关）：
  // 'running' 识别中 / 'has' 有识别文本 → 「查看识别文字」/ 'none' 无 → 「识别文字」。键生成器并入本位
  //（坑44——菜单文案是行卡可变展示成分，键漏 = 识别完成后标签停在旧值）
  ocrState?: string;
}

// LazyForEach 数据源（照 MemoryRowsSource 契约：整表替换 + onDataReloaded；变更一律整表重拉——本域无逐项增删面；register 去重 + unregister 对称）
export class WorkspaceRowsSource implements IDataSource {
  private rows: WorkspaceListEntry[] = [];
  private listeners: DataChangeListener[] = [];

  reload(entries: WorkspaceListEntry[]): void {
    this.rows = entries;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  // 重载通知口（不动数据，只重派 onDataReloaded——MemoryRowsSource.refresh 同形）：多选态勾选/进出模式
  // 变更后由壳侧 @Watch 触发，LazyForEach 按键重算复用（勾选位由壳侧并入行键）。★ 与 reload 分工勿混：
  // reload = 数据换（唯一数据写口）；refresh = 数据不换、只重算键与重渲染——别把 refresh 当数据写口用
  refresh(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): WorkspaceListEntry {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

// 行键（坑44 两问——行卡消费的全部可变入参必须都在键里）：文件行 = 身份 id + 名 + 位置 + 大小 + 更新时间 +
// 识别文字态位（改名/移动/覆盖写三写点全落键）；文件夹行 = 完整路径 + 子文件数 + 子文件夹数 + 显示名（名称变、
// 内部增删〔文件与子文件夹两口径〕、助手名反查回填全落键——键漏显示名 = 回填后卡面定格原始段名；folderCount
// 驱动副标题三态换文案）
export function workspaceEntryKey(entry: WorkspaceListEntry): string {
  if (entry.kind === 'folder') {
    return 'd|' + entry.dirPath + '|' + entry.fileCount + '|' + (entry.folderCount ?? 0) +
      '|' + (entry.displayName ?? '');
  }
  const row: WorkspaceFileRow | null = entry.row;
  if (row === null) {
    return entry.key;
  }
  return row.id + '|' + row.name + '|' + row.dir + '|' + row.size + '|' + row.updatedAt +
    '|' + (entry.ocrState ?? '');
}

// 条目定位二元组（库操作口统一入参形态：dir = 条目所在目录、name = 条目名）
export interface WorkspaceEntryAddr {
  dir: string;
  name: string;
}

// 条目 → 定位二元组单源（宿主 doRename / openMoveSheet / moveEntryTo 三处同构算式归一——文件夹 = dirPath 的
// 父目录 + 段名，文件 = row.dir + row.name；缺行兜底空串 = 原算式语义逐字保留）
export function workspaceEntryAddr(entry: WorkspaceListEntry): WorkspaceEntryAddr {
  if (entry.kind === 'folder') {
    return { dir: workspaceParentDir(entry.dirPath), name: entry.dirName };
  }
  const row: WorkspaceFileRow | null = entry.row;
  if (row === null) {
    return { dir: '', name: '' };
  }
  return { dir: row.dir, name: row.name };
}

// 位置卡（现役消费点仅会话视图下探「当前会话」一处）：小字 label + 单行省略标题（会话标题）+ 文字键行
//（上一级 + 第二动作键）；actionLabel 空 = 第二键不渲染
@Component
export struct WorkspaceNavCard {
  label: string = '';
  title: string = '';
  upEnabled: boolean = false;
  actionLabel: string = '';
  onUp: () => void = () => {
  };
  onAction: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  build() {
    Column({ space: 8 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 8 }) {
        // 上一级（轻动作文字键：无底 TEXTUAL + font_secondary——导航类不占实底档；可用性由 upEnabled 门控）
        Button('上一级')
          .fontSize(13)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor($r('sys.color.font_secondary'))
          .enabled(this.upEnabled)
          .onClick((): void => {
            this.onUp();
          })
        if (this.actionLabel !== '') {
          Button(this.actionLabel)
            .fontSize(13)
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel,
              true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick((): void => {
              this.onAction();
            })
        }
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct WorkspaceFolderRowCard {
  entry: WorkspaceListEntry = { key: '', kind: 'folder', row: null, absPath: '',
    dirName: '', dirPath: '', fileCount: 0 };
  onOpen: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onRename: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onMove: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onDelete: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // ── 多选三成员（★ 2026-10-04 多选笔；普通成员——键控重建 = 唯一更新路径，见文件头）──
  // 多选态（true = 行尾四点键换勾选圈、点卡切换勾选；会话视图不传 = false 普通态）
  selectMode: boolean = false;
  // 本卡是否已勾选（勾选圈回显）
  selected: boolean = false;
  // 勾选切换上行（点卡触发；键以 entry.key 基础键为单值）
  onToggle: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 勾选圈（多选态；SessionCardItem.CheckKeyBuilder 同构）：官方 Checkbox + hitTestBehavior(None) 纯视觉
  // 指示器——点击穿透落到卡 onClick 单一通路（坑5）；40vp 占位 = 与四点键两态统一基准，防行宽两态微跳
  @Builder
  CheckKeyBuilder() {
    Column() {
      Checkbox()
        .select(this.selected)
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  // 行尾菜单：改名 / 移动 / 删除（移动点击上行壳侧开半模态选目标；候选为空由壳侧出指引 toast，项在场不摘除）。
  // 多选态本键不渲染（换勾选圈——菜单动作与多选互斥，会话列表同款）
  @Builder
  FolderMenu(entry: WorkspaceListEntry) {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        content: '改名' })
        .onClick((): void => {
          this.onRename(entry);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_right')),
        content: '移动' })
        .onClick((): void => {
          this.onMove(entry);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: '删除' })
        .onClick((): void => {
          this.onDelete(entry);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  // 副标题三态（单段不拼接——「0 个文件」误导空的反制）：有文件「N 个文件」；无文件有子文件夹「M 个文件夹」；
  // 全空「空文件夹」。计数变化靠键驱动（workspaceEntryKey 已并入两计数）换装本行
  private folderSubLine(): string {
    if (this.entry.fileCount > 0) {
      return this.entry.fileCount + ' 个文件';
    }
    const folderCount: number = this.entry.folderCount ?? 0;
    return folderCount > 0 ? folderCount + ' 个文件夹' : '空文件夹';
  }

  build() {
    Button() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(24)
          .fontColor([cardDescColor()])
        Column({ space: 3 }) {
          // 显示名单源 displayName（地基笔：助手文件夹显示助手名；未填 = 段名原名）
          Text(this.entry.displayName ?? this.entry.dirName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.folderSubLine())
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // C 区两态互斥（多选笔）：勾选圈 ↔ 四点键
        if (this.selectMode) {
          this.CheckKeyBuilder()
        } else {
          Button() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .bindMenu(this.FolderMenu(this.entry), {
            placement: Placement.BottomRight,
            systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
              this.immersiveLevel, true)
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(14)
    // 拖拽卡关原生按压（规范《列表卡片与组卡》§4.8 第三件——长按起手灰蒙层跟浮起的根治；本卡只服务文件夹
    // 段拖拽列表，代价 = 点卡进子目录无按压变淡；行内四点键按压反馈不受影响）
    .stateEffect(false)
    .onClick((): void => {
      // 多选态点卡 = 切换勾选（进子目录让位——切换语义并入行点击，会话列表同款）
      if (this.selectMode) {
        this.onToggle(this.entry);
        return;
      }
      this.onOpen(this.entry);
    })
  }
}

// 文件行卡（整卡可点 = 预览；行尾四点键独立热区）；副行「大小 · 时间 · 来源」，会话视图（showDir=true）非根件
// 前置所在位置（跨目录聚合必须显位置；文件夹视图位置由位置卡承载不带前缀）
@Component
export struct WorkspaceFileRowCard {
  entry: WorkspaceListEntry = { key: '', kind: 'file', row: null, absPath: '',
    dirName: '', dirPath: '', fileCount: 0 };
  showDir: boolean = false;
  // 拖拽列表成员标记：true = 本卡处于长按拖拽列表内（现仅管理页文件夹段消费）——文件行虽不落自定义序，长按
  // 同样浮起，§4.8 第三件灰蒙层跟浮起缺陷面相同，同关原生按压；false = 会话视图保留官方按压（规范「勿据此统一
  // 全仓」）。普通成员：LazyForEach 键控重建 = 唯一更新路径，构造期值恒正确
  suppressPressEffect: boolean = false;
  onPreview: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onShare: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onRename: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onMove: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onDelete: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // 识别文字动作上行（壳侧持注册表与编排，行卡只上行意图；ocrState === 'running' 时壳侧守卫点击无效〔重入防线第二道〕）
  onOcr: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // ── 多选三成员（★ 2026-10-04 多选笔；语义与 FolderRowCard 同名成员一致，见其注释）──
  selectMode: boolean = false;
  selected: boolean = false;
  onToggle: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // 勾选圈（多选态；FolderRowCard.CheckKeyBuilder 同构——两卡形制恒对齐）
  @Builder
  CheckKeyBuilder() {
    Column() {
      Checkbox()
        .select(this.selected)
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  // 行尾菜单：分享 / 识别文字〔识别对象行〕/ 改名 / 移动 / 删除；多选态本键不渲染（换勾选圈）。识别对象行
  //（image / pdf——壳侧派生 ocrState 时已判定）在分享之后出「识别文字」项，文案三态 = 识别中〔点击壳侧守卫无效〕/ 查看识别文字 / 识别文字
  @Builder
  FileMenu(entry: WorkspaceListEntry) {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')),
        content: '分享' })
        .onClick((): void => {
          this.onShare(entry);
        })
      if (entry.ocrState !== undefined) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_text')),
          content: entry.ocrState === 'running' ? '识别中' :
            (entry.ocrState === 'has' ? '查看识别文字' : '识别文字') })
          .onClick((): void => {
            this.onOcr(entry);
          })
      }
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        content: '改名' })
        .onClick((): void => {
          this.onRename(entry);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_right')),
        content: '移动' })
        .onClick((): void => {
          this.onMove(entry);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: '删除' })
        .onClick((): void => {
          this.onDelete(entry);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  build() {
    // ★ 蒙层边距统一：卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 14→10 回添，几何零位移
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph(this.iconOf())
            .fontSize(24)
            .fontColor([cardDescColor()])
          Column({ space: 3 }) {
            Text(this.nameOf())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.subLineOf())
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // C 区两态互斥（多选笔）：勾选圈 ↔ 四点键
          if (this.selectMode) {
            this.CheckKeyBuilder()
          } else {
            Button() {
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .bindMenu(this.FileMenu(this.entry), {
              placement: Placement.BottomRight,
              systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                this.immersiveLevel, true)
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      // 拖拽列表内关原生按压（suppressPressEffect——标记语义见成员注释；会话视图 false 保留官方按压）
      .stateEffect(!this.suppressPressEffect)
      .onClick((): void => {
        // 多选态点卡 = 切换勾选（预览让位——切换语义并入行点击，会话列表同款）
        if (this.selectMode) {
          this.onToggle(this.entry);
          return;
        }
        this.onPreview(this.entry);
      })
    }
    .width('100%')
    // 卡底底色随深浅色切换过渡（定位高亮淡底随 U6 定位域整支退役——两千零九十节）
    .backgroundColor(cardBg(this.appColorMode))
    .animation({ duration: 300, curve: Curve.EaseOut })
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 行首图标八档：档位判定单源 = workspaceIconTierOf（ext 专属档先行、kind 兜底）；本处只做档位→符号字面量
  // 映射（$r 须编译期字面量、禁拼接）；row 缺行兜底 doc_text 不变
  private iconOf(): Resource {
    const row: WorkspaceFileRow | null = this.entry.row;
    if (row === null) {
      return $r('sys.symbol.doc_text');
    }
    switch (workspaceIconTierOf(row.name, row.kind)) {
      case 'pdf':
        return $r('sys.symbol.pdf_doc');
      case 'sheet':
        return $r('sys.symbol.square_grid_2x2');
      case 'archive':
        return $r('sys.symbol.doc_zipper');
      case 'audio':
        return $r('sys.symbol.music');
      case 'video':
        return $r('sys.symbol.video');
      case 'image':
        return $r('sys.symbol.picture');
      case 'text':
        return $r('sys.symbol.doc_plaintext');
      default:
        return $r('sys.symbol.doc_text');
    }
  }

  private nameOf(): string {
    const row: WorkspaceFileRow | null = this.entry.row;
    return row !== null ? row.name : '';
  }

  // 副行：会话视图非根件前置所在位置（文件夹视图不带前缀——位置由位置卡承载）
  private subLineOf(): string {
    const row: WorkspaceFileRow | null = this.entry.row;
    if (row === null) {
      return '';
    }
    const dirPrefix: string = this.showDir && row.dir !== '' ? row.dir + ' · ' : '';
    return dirPrefix + formatWorkspaceSize(row.size) + ' · ' +
      formatConvTime(row.updatedAt) + ' · ' + sourceLabel(row.source);
  }
}

// 空态行内提示（两行文案参数化——根目录空态 / 子目录空态 / 会话视图空态共用形制）
@Component
export struct WorkspaceEmptyHint {
  main: string = '';
  sub: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.main)
        .fontSize(15)
        .fontColor(cardTitleColor())
      Text(this.sub)
        .fontSize(13)
        .fontColor(cardDescColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}

// 失败态卡（重试回调上抛——重试链在壳侧单一路径；P0-1 不静默不假成功）
@Component
export struct WorkspaceFailCard {
  onRetry: () => void = (): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  build() {
    Column({ space: 10 }) {
      Text('工作区列表加载失败')
        .fontSize(15)
        .fontColor(cardTitleColor())
      Button('重试')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.onRetry();
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Center)
  }
}
