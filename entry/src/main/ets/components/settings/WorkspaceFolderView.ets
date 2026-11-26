// 工作区文件夹段列表渲染件（自 WorkspaceManagePage 域级最小拆分；拆分轴照 WorkspaceSessionView /
// WorkspaceListRows 先例）：职责 = 文件夹段列表渲染——条目/空态/拖拽双分支/失败与加载两态，纯渲染 +
// 事件上抛。本段是文件夹视图的页级列表骨架（三态守卫 + 多选/拖拽结构分支 + 行键生成器注入位），挂页面
// 状态 @Link 七件，并入 WorkspaceListRows 或 WorkspaceSessionView 都会撑开其依赖面与职责。
// · 依赖方向单向（主件引本件、本件不引主件——坑50 口径）；本件零文件 IO、零 ChatDb/WorkspaceDb 直调、
//   零弹窗零导航（动作全经回调上抛主件执行）。
// · 入参契约（壳侧 hot 值禁 @Prop——规范 §5-3 星标条，坑16 家族）：entries / selectMode / selectedKeys /
//   dragEnabled / currentDir / loadFailed / loaded 七件 @Link；source 普通成员（LazyForEach 自订阅数据源
//   通知，不经组件参数观察）；contentTop 函数槽（壳侧算式现读注入，非值快照——多选态两行带收起的让位
//   判据在算式内）；entryKey 行键生成器函数槽（键含模式位/勾选位，壳侧多选态变化 → source.refresh() 重派
//   onDataReloaded → LazyForEach 按键重算复用/新建）；bottomPad @Prop（首帧快照型常量）；动作回调十件。
// · 拖拽红线（真机二轮修复语义，勿回填属性摘除形态）：dragEnabled 驱动结构分支（双 LazyForEach 条件挂
//   onMove——排序切换即生效）；onMove 全件唯一挂载点透传壳侧 applyDragMoveHandler 产物，落定/拒绝路与
//   第二道守卫仍在壳侧收口。
// · 页级三态守卫内部分派（失败卡 / 加载提示 / 文件夹段列表）——判据与原页面 Content 三分支逐态等价；
//   本件仅在「文件夹段或页级两态」时被主件实例化（会话/临时段不挂本件）。
import { CARD_SPACING, cardDescColor, CARD_RADIUS } from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { WorkspaceListEntry, WorkspaceRowsSource, WorkspaceFolderRowCard,
  WorkspaceFileRowCard, WorkspaceEmptyHint, WorkspaceFailCard } from './WorkspaceListRows';

// 多选态列表尾让位（vp，ChatSessionRows.MULTISELECT_BAR_CLEARANCE 同值 56——该常量彼件私有未导出，
// 本件本地同值，禁跨件 import 私有常量）
const MULTISELECT_BAR_CLEARANCE: number = 56;

@Component
export struct WorkspaceFolderView {
  // 当前层扁平项（文件夹行在前文件行在后；@Link 整表新数组下传，空态判据与图片滑切 scope 同源）
  @Link entries: WorkspaceListEntry[];
  // 多选两态（壳侧 @State @Watch 收敛键驱动刷新；本件消费 = 行卡三成员 + 尾部让位 + 键生成器）
  @Link selectMode: boolean;
  @Link selectedKeys: string[];
  // 拖拽可用态（结构分支驱动位——本件 = 双 LazyForEach 条件挂分支的判据，语义见主件 dragEnabled 注释）
  @Link dragEnabled: boolean;
  // 当前位置（'' = 根；空态双分支文案判据）
  @Link currentDir: string;
  // 页级两态（三态守卫内部分派判据——壳侧 load 成功/失败两写点）
  @Link loadFailed: boolean;
  @Link loaded: boolean;
  // 列表数据源（壳侧单写口维护；★ 普通成员——LazyForEach 自订阅数据源通知，不经组件参数观察）
  source: WorkspaceRowsSource = new WorkspaceRowsSource();
  // 内容区顶留白算式（壳侧 contentTop() 现读注入——函数槽随每次重渲现读，非值快照）
  contentTop: () => number = (): number => 0;
  // 底部让位（导航壳下发）
  @Prop bottomPad: number = 0;
  // 行键生成器（壳侧 multiselectEntryKey 注入——常态 = 基础键，多选态并入模式位与勾选位；
  // 键覆盖该行全部可变展示成分，坑44 纪律）
  entryKey: (entry: WorkspaceListEntry) => string = (entry: WorkspaceListEntry): string => {
    return entry.key;
  };
  // 动作回调（壳侧统一执行；条目回调入参 = 行条目，勾选适配 entry→key 归壳侧绑定）
  onOpen: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onToggle: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onRename: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onMove: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onDelete: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onPreview: (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]) => void =
    (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void => {
    };
  onShare: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onOcr: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // 失败卡重试（页级 load 重入）
  onRetry: () => void = (): void => {
  };
  // 拖拽落定（壳侧 applyDragMoveHandler 产物——onMove 唯一挂载点透传）
  onRowDragMove: (from: number, to: number) => void = (from: number, to: number): void => {
  };

  build() {
    // 页级三态守卫（失败卡 / 加载提示 / 列表——与原页面 Content 三分支逐态等价）
    if (this.loadFailed) {
      this.FailState()
    } else if (!this.loaded) {
      this.LoadingState()
    } else {
      this.FolderList()
    }
  }

  @Builder
  FolderList() {
    List({ space: CARD_SPACING }) {
      // 说明小字（首项；先说明后操作次序在此静态项内体现）：原「当前位置」卡已随面包屑笔退役（路径归
      // 页顶面包屑、上一级 = 点父段），上传键挪入标题栏「更多」菜单，本行仍是对上传落点与用途的唯一屏上
      // 说明；统计行已随「数据总览」笔退役；裸文本改 InfoCard 单源件
      ListItem() {
        InfoCard({ text: '上传的文件保存在当前文件夹，不会自动发给助手。', fullWidth: true })
      }
      .padding({ bottom: 8 })

      // 文件夹段条目（挂官方原位拖拽）。真机二轮修复：拖拽挂/摘必须改结构分支——原「onMove 传
      // undefined 摘除」不随页内重渲生效（LazyForEach.onMove 属性不随局部重渲 patch），改两套
      // LazyForEach 条件挂 + dragEnabled 驱动节点级重建；行渲染抽 FolderEntry（两分支唯一共用体，
      // 除 onMove 一行外逐字相同，改动须同步）。条目层挂与卡同值圆角 CARD_RADIUS（拖拽预览背板按
      // 条目轮廓画，矩形则浮起后四角露直角蒙层）；条目宽 = 容器水平 padding 16 + 卡体 width('100%')
      //（规范 §4.8 形态①，卡侧零改动）
      if (this.dragEnabled) {
        LazyForEach(this.source, (item: WorkspaceListEntry): void => {
          this.FolderEntry(item);
        }, (item: WorkspaceListEntry): string => this.entryKey(item))
          // 官方拖拽排序（长按条目即拖；上报值 = 数据源下标，只透传壳侧 applyDragMoveHandler 产物，
          // 不做换算——落定与拒绝路全在壳侧收口）
          .onMove(this.onRowDragMove)
      } else {
        LazyForEach(this.source, (item: WorkspaceListEntry): void => {
          this.FolderEntry(item);
        }, (item: WorkspaceListEntry): string => this.entryKey(item))
      }

      // 空态：根目录 = 原空态文案；子目录 = 空文件夹态 + 指引
      if (this.entries.length === 0) {
        ListItem() {
          if (this.currentDir === '') {
            WorkspaceEmptyHint({
              main: '工作区还没有文件',
              sub: '助手在对话里保存的文件、你在这里上传的文件都会显示在这里'
            })
          } else {
            WorkspaceEmptyHint({
              main: '这个文件夹里还没有文件',
              sub: '你可以上传文件到这里，也可以新建子文件夹。'
            })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    // 空白区滑动修复（决明报障「文件夹段不满一屏时滑空白屏幕不动」）：layoutWeight(1) 是拆分迁址前的
    // 写法——迁入本件后父容器 = 自定义组件隐式包裹节点，layoutWeight 仅 Row/Column/Flex 布局生效
    //（官方 FAQ faqs-arkui-1545）⇒ List 按内容自适应，卡外空白区不在视口内、手势落空。改 height('100%')
    // 铺满组件节点（组件节点由壳侧 usage 位 layoutWeight(1) 撑满）
    .height('100%')
    // 左右 16 = 卡收窄（水平 padding 保留；卡体 width('100%')——宿主有 padding 正当）
    .padding({ left: 16, right: 16 })
    // 拖拽卡四件套①：容器有水平 padding ⇒ 必挂 clip(false)——水平 padding 即视口缩进，不关则长按
    // 浮起放大的卡被视口边界削成直角（规范 §4.8 第 1 条）
    .clip(false)
    // 顶/底留白走官方 offset（坑9 防线：容器 padding = 视口缩进会裁掉内容，勿回迁）
    .contentStartOffset(Math.max(this.contentTop(), 0))
    // 多选态尾部追加批量条让位（批量条悬浮贴底，不加让位则末卡被遮）
    .contentEndOffset(this.bottomPad + 16 + (this.selectMode ? MULTISELECT_BAR_CLEARANCE : 0))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  // 文件夹视图行条目（FolderList 双拖拽分支共用体，除 onMove 一行外逐字相同；entryKey 由壳生成，勾选位/
  // 模式位变化即重建本行）。多选笔：行卡加传多选三成员（勾选圈/点卡切换），不传 = 普通态
  @Builder
  FolderEntry(item: WorkspaceListEntry) {
    ListItem() {
      if (item.kind === 'folder') {
        WorkspaceFolderRowCard({
          entry: item,
          selectMode: this.selectMode,
          selected: this.selectedKeys.indexOf(item.key) >= 0,
          onOpen: this.onOpen,
          onToggle: this.onToggle,
          onRename: this.onRename,
          onMove: this.onMove,
          onDelete: this.onDelete
        })
      } else {
        WorkspaceFileRowCard({
          entry: item,
          showDir: false,
          suppressPressEffect: true,
          selectMode: this.selectMode,
          selected: this.selectedKeys.indexOf(item.key) >= 0,
          onPreview: (entry: WorkspaceListEntry): void => {
            this.onPreview(entry, this.entries);
          },
          onToggle: this.onToggle,
          onShare: this.onShare,
          onOcr: this.onOcr,
          onRename: this.onRename,
          onMove: this.onMove,
          onDelete: this.onDelete
        })
      }
    }
    .borderRadius(CARD_RADIUS)
  }

  // 页级失败态（三态守卫之一；让位与列表一致走 offset 轨）
  @Builder
  FailState() {
    List({ space: CARD_SPACING }) {
      ListItem() {
        WorkspaceFailCard({
          onRetry: (): void => {
            this.onRetry();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    // 空白区滑动修复同 FolderList（layoutWeight 迁址后不生效）
    .height('100%')
    .padding({ left: 16, right: 16 })
    .contentStartOffset(Math.max(this.contentTop(), 0))
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  // 页级加载态（「没读完」不显示成空态）
  @Builder
  LoadingState() {
    List({ space: CARD_SPACING }) {
      ListItem() {
        Text('正在读取工作区…')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      }
    }
    .width('100%')
    // 空白区滑动修复同 FolderList（layoutWeight 迁址后不生效）
    .height('100%')
    .padding({ left: 16, right: 16 })
    .contentStartOffset(Math.max(this.contentTop(), 0))
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }
}
