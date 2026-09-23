// 记忆编辑页（2026-09-08 决明指令：取消「记忆条目」新增弹窗，添加/编辑一律进二级页——
// 形制对齐会话提示词编辑页 PromptEditPage）：内容多行 TextArea + 字数计数 + 页尾说明行
// + 标题栏「保存」键（checkmark）。标题恒「编辑记忆」（新建态不显示「添加记忆」——
// PromptEditPage「标题恒编辑提示词」同规）；板块标题黑（cardTitleColor）/说明与计数灰
// （cardDescColor）两层级同 PromptEditPage。
// · param = 对象 MemoryEditParam（2026-09-20 助手级记忆 v35——{ id, libraryId }，库判据 =
//   'global' 全局库 | 助手 id 助手库；★ 字符串形态兼容保留 = 全局库，旧调用形态零破坏）：
//   新增 insertMemory / insertAssistantMemory（source 'manual'，助手库落库带归属）、编辑
//   updateMemoryContent / updateAssistantMemoryContent（updatedAt 刷新）→ toast +
//   pop({saved:true})——坑17：pop 必带 result 才触发库管理页 onPop 重拉（无参 pop 不触发，
//   PromptEditPage 同款）；
// · 上限守卫（MEMORY_MAX_TOTAL）在库管理页「＋」新建键 push 前拦截，本页不做二次判定
//   （push 到保存之间无并发写点：自动整理由退出会话触发，编辑页停留期间不可达）；
// · 读取/保存失败一律 toast 明示，不静默（P0-1）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_MEMORY_EDIT_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardDescColor, cardTitleColor, SECTION_TITLE_FONTSIZE } from '../../common/Theme';
import { insertAssistantMemory, insertMemory, MEMORY_SCOPE_GLOBAL, MemoryRow,
  queryAssistantMemory, queryMemory, updateAssistantMemoryContent,
  updateMemoryContent } from '../../common/store/MemoryDb';
import { MEMORY_CONTENT_MAX } from '../../common/MemoryText';
// push 参数载体（interface 单源 = MemoryLibraryPage.ets——库管理页与编辑页消费同一形态）
import { MemoryEditParam } from './MemoryLibraryPage';

function memorySaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

function memorySaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}

@Component
export struct MemoryEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新增；其他 = 记忆 id）——构造后不变（坑30）
  editId: string = '';
  // 目标库（'global' = 全局库 / 助手 id = 助手库——push param 随行；保存与回填同源分派）
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  @State private content: string = '';
  // 加载完成闸（★ O-13 修复，同族四页统一）：.catch 只 toast、页面仍停在「编辑态空表单」——
  // 此时用户填写保存会走 updateMemoryContent(this.editId) 命中真实行、覆盖其内容。闸 = 未加载
  // 完成不许落库（形制与理由照 BalanceConfigPage 的 loaded 闸先例）：新建态无待读行显式置真、
  // 读成功置真、读失败保持假 ⇒ 保存链首拦一道显式提示（不弹出用户 + 封死覆盖路径）；
  // 普通成员即可（不驱动 UI）
  private loaded: boolean = false;

  aboutToAppear(): void {
    // param 解析（对象形态 { id, libraryId }；★ 字符串形态兼容 = 旧调用零破坏，落全局库；
    // null/其他 = '' + 全局库 = 新增）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (typeof last === 'string') {
      this.editId = last;
      this.libraryId = MEMORY_SCOPE_GLOBAL;
    } else if (last !== null) {
      const parsed = last as MemoryEditParam;
      this.editId = typeof parsed.id === 'string' ? parsed.id : '';
      this.libraryId = typeof parsed.libraryId === 'string' && parsed.libraryId !== '' ?
        parsed.libraryId : MEMORY_SCOPE_GLOBAL;
    }
    if (this.editId === '') {
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」）
      return;
    }
    // 编辑态回填（按库分派——判据 = 入参 libraryId〔路由参数〕，与 id 形态无关；两库行
    // id 前缀为连字符形态 'asmem-'/'mem-'，仅供人读，全仓无按前缀判库的代码）
    const read: Promise<MemoryRow | null> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      queryMemory(this.editId) : queryAssistantMemory(this.editId);
    read
      .then((row): void => {
        if (row === null) {
          // ★ 同族统一修复（2026-09-13）：查不到退栈回上页（形制照 SkillEditPage O-11
          // 修复与 ProviderDetailPage 同行守卫）——删记忆入口在库管理页，退回即见最新列表；
          // 本分支未改任何数据，库管理页 onPop 重拉是给保存链用的（无 result 不触发）
          this.getUIContext().getPromptAction().showToast({ message: '记忆不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.content = row.content;
        this.loaded = true; // 闸放行（读成功）
      })
      .catch((e: Object): void => {
        // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死空壳覆盖既有行（见成员位注释）
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  private save(): void {
    // 加载完成闸（未加载完 = 表单是空初值，落库即覆盖既有行；闸的形状与理由照 BalanceConfigPage
    // 先例；O-13 修复）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '记忆未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const content: string = this.content.trim();
    if (content === '') {
      this.getUIContext().getPromptAction().showToast({ message: '内容不能为空' });
      return;
    }
    if (this.editId === '') {
      // 新增：按库分派（助手库带归属，source 'manual' 与全局手动新增同形）
      const insert: Promise<MemoryRow> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
        insertMemory({ content: content, source: 'manual', assistantId: '', conversationId: '' }) :
        insertAssistantMemory(this.libraryId, content, 'manual', '');
      insert
        .then((_row: MemoryRow): void => {
          this.done();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    } else {
      // 编辑：按库分派（只写 content + updatedAt，sortOrder/createdAt/source 保持）
      const write: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
        updateMemoryContent(this.editId, content) :
        updateAssistantMemoryContent(this.editId, content);
      write
        .then((): void => {
          this.done();
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  // 保存成功：toast + pop 带 result（坑17——记忆页 onPop 重拉）
  private done(): void {
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    this.pathStack.pop({ saved: true });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Text('内容')
            .fontSize(SECTION_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(cardTitleColor())
            .width('100%')
          TextArea({ placeholder: '例如 用户偏好简洁的中文回答', text: this.content })
            .width('100%')
            .height(220)
            .maxLength(MEMORY_CONTENT_MAX)
            .onChange((value: string): void => {
              this.content = value;
            })
          Text(this.content.length + ' / ' + MEMORY_CONTENT_MAX)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
            .textAlign(TextAlign.End)
          Text('记忆按读取方式自动携带，或供助手检索。请勿存入口令、密钥等敏感信息。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: '编辑记忆',
      menuHds: memorySaveMenuHds((): void => {
        this.save();
      }),
      menuNav: memorySaveMenuNav((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
