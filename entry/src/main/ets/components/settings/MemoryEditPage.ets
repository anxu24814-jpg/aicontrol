// 记忆编辑页（添加入口已取消弹窗，一律进本二级页；形制对齐 PromptEditPage）：多行 TextArea +
// 字数计数 + 说明行 + 标题栏「保存」键（checkmark；标题恒「编辑记忆」，新建态不显示「添加记忆」）。
// · param = MemoryEditParam { id, libraryId }（'global' 全局库 / 助手 id 助手库；字符串形态兼容 =
//   全局库）：新增走 insertMemoryGuarded / insertAssistantMemoryGuarded（source 'manual'，助手库落库
//   带归属）、编辑走 updateMemoryContent / updateAssistantMemoryContent（刷 updatedAt）→ toast +
//   pop({saved:true})——坑17：pop 必带 result 才触发库管理页 onPop 重拉，无参不触发。
// · 上限守卫两层：库管理页「＋」push 前拦截（体验层）+ Guarded 命令事务内硬闸（完整性层）——
//   停留期间工具 create 与导入链照常可写库，push 前余量到保存时可能已满，由命令内判定兜住
//   （满额/父行缺失抛错走既有 catch toast）。
// · 读取/保存失败一律 toast 明示，不静默（P0-1）。
// · 表单形态：单字段页收成一张记忆卡（卡头 标题 + 库徽标 + 字数、编辑框、字段说明、卡脚
//   来源/上次更新）；安全说明独立 InfoCard 置卡后。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_MEMORY_EDIT_PAGE } from '../../common/RouteNames';
import {
 CARD_PANEL_WIDTH, SECTION_GAP, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  CARD_NOTE_FONTSIZE, CARD_SECTION_TITLE_FONTSIZE, CARD_RADIUS
} from '../../common/Theme';
import { insertAssistantMemoryGuarded, insertMemoryGuarded, MEMORY_SCOPE_GLOBAL, MemoryRow,
  queryAssistantMemory, queryMemory, updateAssistantMemoryContent,
  updateMemoryContent } from '../../common/store/MemoryDb';
import { MEMORY_CONTENT_MAX, memorySourceLabel } from '../../common/MemoryText';
// push 参数载体（interface 单源 = MemoryLibraryPage.ets——库管理页与编辑页消费同一形态）
import { MemoryEditParam } from './MemoryLibraryPage';
import { InfoCard } from '../InfoCard';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { formatConvTime } from '../chat/SessionSearchPanels';

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

@Component
export struct MemoryEditPage {
  // 页面存活守卫（2026-10-18 销毁守卫全站治理）：置位后本组件迟到异步回调不写状态、不碰 UI、
  // 不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 卡片底色/卡脚描边取色（记忆卡与卡脚按深浅分治）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象 id（'' = 新增；其他 = 记忆 id）——构造后不变（坑30）
  editId: string = '';
  // 目标库（'global' = 全局库 / 助手 id = 助手库——push param 随行；保存与回填同源分派）
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  @State private content: string = '';
  // 卡脚用的来源与更新时间（编辑态从行回填，新建态按手动添加兜底）
  @State private updatedAt: number = 0;
  @State private source: string = 'manual';
  // 加载完成闸（同族四页统一）：.catch 只 toast、页面仍停在空表单——此时保存会走
  // updateMemoryContent(this.editId) 命中真实行、覆盖其内容。未加载完成不许落库：新建态无待读
  // 行显式置真、读成功置真、读失败保持假 ⇒ 保存链首拦一道显式提示。普通成员不驱动 UI
  private loaded: boolean = false;
  // 保存进行中闸（防重入）：写入命令事务内只有容量闸无内容查重——新建态连点保存会插入两条
  // 内容相同的记忆。save 内查闸置真、失败回调复位（成功经 done 离页组件销毁，无需复位）
  private saving: boolean = false;

  aboutToAppear(): void {
    // param 解析（对象形态 { id, libraryId }；字符串形态兼容 = 落全局库；null/其他 = '' + 全局库 = 新增）
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
    // 编辑态回填（按库分派——判据 = 入参 libraryId，与 id 形态无关；'asmem-'/'mem-' 前缀仅供人读，
    // 全仓无按前缀判库的代码）
    const read: Promise<MemoryRow | null> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      queryMemory(this.editId) : queryAssistantMemory(this.editId);
    read
      .then((row): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          // 查不到退栈回上页（同族统一形制）——删记忆入口在库管理页，退回即见最新列表；
          // 本分支未改数据，无 result 不触发 onPop 重拉
          this.getUIContext().getPromptAction().showToast({ message: '记忆不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.content = row.content;
        this.updatedAt = row.updatedAt;
        this.source = row.source;
        this.loaded = true; // 闸放行（读成功）
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 读取失败：不置闸（保持「加载未完成」）→ 保存被首拦，封死空壳覆盖既有行（见成员位注释）
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  private save(): void {
    // 加载完成闸（未加载完 = 空初值，落库即覆盖既有行；见成员位注释）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({ message: '记忆未加载完成，暂不能保存，请返回重进' });
      return;
    }
    const content: string = this.content.trim();
    if (content === '') {
      this.getUIContext().getPromptAction().showToast({ message: '内容不能为空' });
      return;
    }
    // 保存进行中闸（防重入，见成员位注释）：成功经 done 离页无需复位，失败复位允许重试
    if (this.saving) {
      return;
    }
    this.saving = true;
    if (this.editId === '') {
      // 新增：按库分派（助手库带归属，source 'manual' 与全局手动新增同形）。满额与父行校验在
      // 命令事务内判定（上限拦截原在库管理页 push 前，停留期间被并发写满的窗口由命令内硬闸
      // 兜住）；抛错走既有 catch toast，文案前缀不变
      const insert: Promise<MemoryRow> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
        insertMemoryGuarded({ content: content, source: 'manual', assistantId: '', conversationId: '' }) :
        insertAssistantMemoryGuarded(this.libraryId, content, 'manual', '');
      insert
        .then((_row: MemoryRow): void => {
          this.done();
        })
        .catch((e: Object): void => {
          if (this.departed) {
            return;
          }
          this.saving = false;
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
          if (this.departed) {
            return;
          }
          this.saving = false;
          this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
        });
    }
  }

  // 保存成功：toast + pop 带 result（坑17——记忆页 onPop 重拉）
  private done(): void {
    this.getUIContext().getPromptAction().showToast({ message: '已保存' });
    this.pathStack.pop({ saved: true });
  }

  // 卡脚文案（来源与上次更新；新建态先说清保存后记成什么）
  private footText(): string {
    if (this.editId === '') {
      return '保存后记为手动添加';
    }
    return '上次更新 ' + formatConvTime(this.updatedAt) + ' · ' + memorySourceLabel(this.source);
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: SECTION_GAP }) {
        // 记忆卡（标题 + 库徽标 + 计数、编辑器、说明、卡脚同卡；安全说明独立成 InfoCard 置卡后）
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('记忆内容')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            StatusBadge({
              text: this.libraryId === MEMORY_SCOPE_GLOBAL ? '全局记忆' : '助手记忆',
              tone: BadgeTone.WEAK
            })
            Text(this.content.length + ' / ' + MEMORY_CONTENT_MAX)
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          TextArea({ placeholder: '例如 用户偏好简洁的中文回答', text: this.content })
            .width('100%')
            .height(240)
            .maxLength(MEMORY_CONTENT_MAX)
            .onChange((value: string): void => {
              this.content = value;
            })
          Text('写清偏好或事实即可。记忆会被注入到后续对话，临时信息不要写进来。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          // 卡脚（《规范-列表卡片与组卡》§1.5）：本卡无操作按钮行，整卡结论落脚；hairline 上边线 +
          // 13fp 灰字，不放按钮/徽标
          Column() {
            Divider()
              .strokeWidth(0.5)
              .color(cardBorderColor(this.appColorMode))
            Text(this.footText())
              .fontSize(CARD_NOTE_FONTSIZE)
              .fontColor(cardDescColor())
              .width('100%')
              .maxLines(2)
              .padding({ top: 10 })
          }
          .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // info 说明卡（记忆页首元素之一定位：讲整页数据的存放与敏感信息，非字段说明故置卡后）
        InfoCard({ text: '记忆按读取方式自动携带，或供助手检索。请勿存入口令、密钥等敏感信息。' })
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
      title: '编辑记忆',
      menuHds: memorySaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
