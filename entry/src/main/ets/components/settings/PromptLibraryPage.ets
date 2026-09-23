// 提示词库管理页（2026-08-30 提示词注入新建；设置页行卡「会话提示词」push——照 ProviderPage
// 自包 PageShell 壳先例）：
// · 模板清单（2026-08-31 起库页 = 用户模板——系统提示词 2026-08-31 独立化：不再置顶显示，
//   queryTemplates 过滤 isGlobal=0；系统提示词由独立页 SystemPromptPage 管理——设置页
//   「系统提示词」行卡进入）；
// · 标题栏双键（2026-08-31 领导指令：更多弹窗菜单拆分，高频直达——照 ChatPage 标题栏
//   ChatTitleMenu 同构姿势：HDS/回退双形态菜单数组；【＋新建提示词】在左、【⋯多选】在最右
//   （顺序 = 数组成员序，与 ChatPage 双键同构——若真机轴向相反仅反转数组一行）；
//   多选 = 进入批量删除模式（批量条/删除编排同会话列表先例）；
// · 行卡右侧四点键（dot_grid_2x2）→ 官方菜单：编辑 / 删除（2026-08-30 领导指令「提示词
//   卡右侧放更多，点击弹菜单」——照 ProviderCardItem 四点键姿势，弃 bindMenu 长按
//   （转场后菜单残留，真机截图实锤））；行卡本体点击仍进编辑（冗余入口无害）；
//   ★ 2026-09-06 多选态圈选框移右缘（决明指令「类似对话历史多选」——SessionCardItem
//   同款形制：内容区 layoutWeight(1) + Checkbox 与四点键互斥同位）；
// · 删除确认：ConfirmDialog（成员位——坑7）固定文案（builder 参数创建时固定，动态模板名
//   不入——信息不损失：删除后果提示足够）；
// · 菜单基建（PromptRowMenuHost + 锚点常量）在 PromptTemplateMenu.ets
//   （官方 openMenu + AppMenuHost——两菜单节点 init 一次、dispose 成对）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_PROMPT_EDIT_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_PROMPT } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  deleteTemplate, PromptTemplateRow, queryTemplates
} from '../../common/store/PromptTemplateDb';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { SessionMultiselectBar } from '../chat/SessionMultiselectBar';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import {
  PROMPT_ROW_MENU_ID_PREFIX, PromptRowMenuCallbacks, PromptRowMenuHost
} from './PromptTemplateMenu';
import { ConfigurationConstant } from '@kit.AbilityKit';

// 标题栏双键（2026-08-31 高频拆分——照 ChatTitleMenu 同构：数组成员序 [新建, 多选]；
// ★ 目标视觉 = 「＋左 ⋯右」（多选最右）；若真机轴向相反仅反转数组两行）；
// ★ 多选键图标 = 官方 list_checkmark（列表勾选——与旧「更多」菜单中「多选」项同符号；
//   勿用 dot_grid_2x2——那是「更多」键语义，多选键须视觉区分）
function promptMenuHds(onNew: () => void, onMulti: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.plus'),
        action: onNew
      }
    }, {
      content: {
        icon: $r('sys.symbol.list_checkmark'),
        action: onMulti
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function promptMenuNav(onNew: () => void, onMulti: () => void): NavigationMenuItem[] {
  return [{
    value: '新建提示词',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNew
  } as NavigationMenuItem, {
    value: '多选',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')),
    action: onMulti
  } as NavigationMenuItem];
}

@Component
export struct PromptLibraryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private templates: PromptTemplateRow[] = [];
  @State private deleteTarget: PromptTemplateRow | null = null;
  // 多选模式（2026-08-30 领导指令；选中 id 集合——@State 观察代理数组入 napi 坑6：
  // 批量删除传库前逐元素拷贝纯数组——deleteTemplate 无数组入参（逐个调用），天然规避）
  @State private multiSelect: boolean = false;
  @State private selectedIds: string[] = [];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 菜单材质档位（@StorageProp 自订阅——AppMenuHost 弹出时解析；SessionCardMenu 同款姿势）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 菜单节点宿主（官方 openMenu：init 一次 / 弹出前重建（基类）/ dispose 成对——见域件注释）；
  // ★ 2026-08-31 页级菜单退役（标题栏双键化），仅剩行卡四点键
  private rowMenu: PromptRowMenuHost = new PromptRowMenuHost();
  // 删除确认弹窗（坑7：必须组件成员位构造——普通类 open() 静默无效真机实锤）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除提示词',
      message: '删除后引用该模板的会话将回退助手提示词。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.rowMenu.init(this.getUIContext(), this.rowCallbacks(this.emptyRow()));
    this.reload();
  }

  aboutToDisappear(): void {
    this.rowMenu.dispose();
  }

  // 标题栏双键回调（2026-08-31 高频拆分——新建直达编辑页 / 多选进批量删除模式；
  // 与旧「更多」菜单两项功能一一对应，零语义变化）
  // ★ 2026-08-31 领导拍板「沉淀」：多选中加号不生效（对齐对话历史页 HomeNavigation
  // newConversation 同款守卫——多选中新建语义冲突：push 编辑页返回后多选态残留且与
  // 批量删除交错）
  private onNewTemplate(): void {
    if (this.multiSelect) {
      return;
    }
    this.editTemplate('');
  }

  private onMultiSelect(): void {
    this.multiSelect = true;
    this.selectedIds = [];
  }

  // 空行对象（init 建菜单节点的占位载荷——**禁传 null 断言**：ComponentContent 创建时即固化
  // UI 树（AppMenuHost 头注释），菜单 builder 若在构建期读 params.item 字段，null 会在首建即
  // 抛 TypeError = 进页闪退（2026-09-13 技能库页真机实锤的同族隐患，本页虽当前 builder 不读
  // item 也一并硬化）。形态照 ProviderPage.emptyRow / ChatSessionList.emptyItem 先例）
  private emptyRow(): PromptTemplateRow {
    return { id: '', name: '', content: '', isGlobal: false, createdAt: 0,
      injectRole: 'system', injectPosition: 'head', injectDepth: 0 };
  }

  private rowCallbacks(row: PromptTemplateRow): PromptRowMenuCallbacks {
    return {
      item: row,
      onEdit: (item: PromptTemplateRow): void => {
        this.editTemplate(item.id);
      },
      onDelete: (item: PromptTemplateRow): void => {
        this.confirmDelete(item);
      }
    };
  }

  private reload(): void {
    queryTemplates()
      .then((rows: PromptTemplateRow[]): void => {
        this.templates = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '提示词读取失败：' + (e as Error).message });
      });
  }

  private editTemplate(rowId: string): void {
    this.pathStack.pushPathByName(ROUTE_PROMPT_EDIT_PAGE, rowId, (): void => {
      this.reload();
    });
  }

  // 行卡四点键菜单（编辑 / 删除）
  private openRowMenu(row: PromptTemplateRow): void {
    if (this.multiSelect) {
      return; // 多选态四点键失效（切换语义并入行点击）
    }
    this.rowMenu.open(this.getUIContext(), this.rowCallbacks(row), this.immersiveLevel);
  }

  // 多选：行点击切换选中（勾选圈纯视觉 + 卡片 onClick 单一通路——坑5 先例）
  private toggleSelect(row: PromptTemplateRow): void {
    const idx: number = this.selectedIds.indexOf(row.id);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
      this.selectedIds = this.selectedIds.slice();
    } else {
      this.selectedIds = this.selectedIds.concat([row.id]);
    }
  }

  // 批量删除确认（多选态底部条主操作）；文案固定（通用后果提示，不用动态引用数）
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.confirmCtrl.open();
  }

  private confirmDelete(row: PromptTemplateRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  private doDelete(): void {
    if (this.multiSelect) {
      this.doDeleteSelected();
      return;
    }
    const target: PromptTemplateRow | null = this.deleteTarget;
    if (target === null) {
      return;
    }
    this.deleteTarget = null;
    this.deleteOne(target.id);
  }

  // 删除单条（引用数提示——被引用时文案「N 个会话引用，已回退助手提示词」）
  private deleteOne(id: string): void {
    deleteTemplate(id)
      .then((refCount: number): void => {
        const warned: string = refCount > 0 ? '（' + refCount + ' 个会话引用，已回退助手提示词）' : '';
        this.getUIContext().getPromptAction().showToast({ message: '已删除' + warned });
        if (this.multiSelect) {
          this.selectedIds = this.selectedIds.filter((item: string): boolean => item !== id);
        }
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 批量删除（逐个调用——引用数求和提示；完成退出多选）
  private doDeleteSelected(): void {
    const ids: string[] = [];
    for (const id of this.selectedIds) {
      ids.push(id);
    }
    let totalRefs: number = 0;
    let done: number = 0;
    let failed: boolean = false;
    for (const id of ids) {
      deleteTemplate(id)
        .then((refCount: number): void => {
          totalRefs += refCount;
          done++;
          if (done === ids.length) {
            if (failed) {
              this.getUIContext().getPromptAction().showToast({ message: '部分删除失败，请重试' });
            } else {
              const warned: string = totalRefs > 0 ? '（' + totalRefs + ' 个会话引用，已回退助手提示词）' : '';
              this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + ids.length + ' 个' + warned });
            }
            this.multiSelect = false;
            this.selectedIds = [];
            this.reload();
          }
        })
        .catch((e: Object): void => {
          failed = true;
          done++;
          if (done === ids.length) {
            this.multiSelect = false;
            this.selectedIds = [];
            this.getUIContext().getPromptAction().showToast({ message: '部分删除失败：' + (e as Error).message });
            this.reload();
          }
        });
    }
  }

  private exitMultiSelect(): void {
    this.multiSelect = false;
    this.selectedIds = [];
  }

  // 行卡（多选态 = 勾选圈贴右缘视觉 + 行点击切换——2026-09-06 决明指令「圈选框放右侧，
  // 类似对话历史多选」SessionCardItem 同款形制；普通态 = 点击进编辑 + 右侧四点键菜单）
  @Builder
  TemplateRow(row: PromptTemplateRow) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(row.name !== '' ? row.name : '无名称模板')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            // 名行单行收敛（名上限 50 字；同族行卡 MemoryRowCard/SkillCard 同款——不收敛
            // 时长名把行卡撑高、列表高矮不一）
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.content !== '' ?
            row.content.substring(0, 24) + (row.content.length > 24 ? '…' : '') : '无内容')
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.multiSelect) {
          // 勾选圈贴右缘（官方 Checkbox 纯视觉指示器——坑5：Checkbox 自带点击消费直点
          // 不联动卡片 onClick，会话列表同款修复 = select 回显 + hitTestBehavior(None)
          // 穿透 + 卡片 onClick 单一通路；与四点键互斥同位——SessionCardItem 同构）
          Checkbox()
            .select(this.selectedIds.indexOf(row.id) >= 0)
            .hitTestBehavior(HitTestMode.None)
        } else {
          // 四点键（普通态：编辑/删除菜单）：Button TEXTUAL 包裹对齐 ProviderCardItem 基准
          // 形制（2026-09-12 UI 同形异构归一笔 1——原裸 SymbolGlyph 无按压反馈、色为
          // icon_secondary；锚点 id 移 Button 层，openMenu 定位按键右缘计算不变）
          Button() {
            SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .id(PROMPT_ROW_MENU_ID_PREFIX + row.id)
          .onClick((): void => {
            this.openRowMenu(row);
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      if (this.multiSelect) {
        this.toggleSelect(row);
      } else {
        this.editTemplate(row.id);
      }
    })
  }

  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 10 }) {
          if (this.templates.length === 0) {
            // 空态行内提示行（2026-09-12 UI 同形异构归一笔 2——PriceTemplatePage 同形制：
            // 13fp cardDescColor + CARD_PANEL_WIDTH 无卡底；只加空态分支，刷新链不动）
            Text('暂无提示词。点右上角的「＋」新建，或在对话页把常用提示词保存进来。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            // ★ 2026-09-13 自检观察项 O-4 清账笔（坑16 家族，与技能库页五百一十七节同款修复）：
            // 行键原为 id 单成分——编辑页改名/改正文后返回（push 回调 reload 已重赋数组新引用），
            // id 不变 → 键不变 → ForEach 只 diff 不重建行 → 卡片停在旧名与旧正文摘录上
            //（档案成文口径：重赋数组新引用对同 key 的行无效）。行上屏的内容有哪几项，键就得
            // 含哪几项（同族先例 = 附件行键含件名、技能库行键含 id|名称|描述|图标）。此处正文
            // 取**全文**而非显示用的前 24 字切片：正文上限 2000 字，含全量只会多重建、不会漏
            // 重建，且不必为键另立一份与显示规则耦合的截断常量
            ForEach(this.templates, (row: PromptTemplateRow) => {
              this.TemplateRow(row)
            }, (row: PromptTemplateRow): string => row.id + '|' + row.name + '|' + row.content)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 多选批量条（悬浮无实底容器：取消左 / 删除右——SessionMultiselectBar 复用；
      // barBottom 避让区 + 16 同会话列表口径）
      if (this.multiSelect) {
        SessionMultiselectBar({
          barText: this.selectedIds.length > 0 ? '删除 ' + this.selectedIds.length + ' 个提示词' : '删除提示词',
          barBottom: this.bottomPad + 16,
          onCancel: (): void => {
            this.exitMultiSelect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_PROMPT,
      menuHds: promptMenuHds((): void => {
        this.onNewTemplate();
      }, (): void => {
        this.onMultiSelect();
      }),
      menuNav: promptMenuNav((): void => {
        this.onNewTemplate();
      }, (): void => {
        this.onMultiSelect();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
