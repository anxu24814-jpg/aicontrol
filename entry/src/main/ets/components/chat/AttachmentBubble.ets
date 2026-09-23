// 附件独立气泡（2026-09-15 预览第三轮新建域件，任务书-附件气泡与预览 §2.5；拍板 7 =
// 决明「把各类附件独立气泡，放消息气泡前」）：该消息的全部附件集中在一枚独立气泡里，
// 排在消息气泡之前（列表时序上方）——两泡同侧（user 右对齐）同底色同圆角、小间距相连，
// 读作「一组附件 + 一句话」。宿主 = ChatMessageItem user 分支外包裹 Column（先附件泡后
// 消息泡，同一 ListItem 内竖排——拆成独立消息行即破坏回放装配归属与会话语义，红线）。
// 为何不能并入 ChatMessageItem（反碎片下限②书面理由）：①ChatMessageItem 现逾 700 行，
// 并入本件（≈170 行）将越 800 软引导线且使其承担第二职责（附件泡渲染与点击派发）；
// ②既有 AttachmentStrip（输入栏）数据契约是「待发附件 + 删除徽标 + 横滑」，与「历史简报
// + 点击预览 + 竖排换行」不同型，硬合会把两套语义与两套几何挤进一个组件；③本件可被
// 后置的「附件管理列表」笔直接复用（书 §5）。
// 取源红线（官方 FAQ faqs-arkui-154 实锤）：Image 组件不能直接传入应用沙箱路径——必经
// fileUri.getUriFromPath 转沙箱 URI；恒挂 sourceSize 让解码下沉到目标尺寸（官方下采样
// 姿势，禁原图整幅入内存）；不生成磁盘缩略图（零新增文件产物）。解码失败降级：该件改走
// 文件行形态（同输入栏「解码失败降级图标卡」先例）。
// 大小/扩展名段与输入栏附件条同口径 = AttachmentUtil.formatFileSize/extLabel 单源（本笔
// 自 ChatAttachmentStrip 上收，断言钉同源，禁第二实现）。
// ★ 2026-09-15 预览升级笔：图片缩略图挂共享元素转场 out 侧（geometryTransition + follow
// 官方模态组合示例口径）——id 判据三处同源 sharedGeomId（广播键，AttachmentUtil 注释），
// 只有「我的 id === 当前共享 id」的一枚绑定，其余空串（官方「清除绑定」语义）；transition
// 仅共享激活期挂 OPACITY 动画（常挂会让 LazyForEach 滚动重建的缩略图逐个淡入），时长曲线
// 与查看器开关动画同值（ATTACH_PREVIEW_ANIM 单源）。
import { fileUri } from '@kit.CoreFileKit';
import { AttachmentBrief, extLabel, formatFileSize, ATTACH_SHARED_ID_KEY, sharedGeomId,
  ATTACH_PREVIEW_ANIM } from '../../common/AttachmentUtil';
import { BUBBLE_PAD_FAR, BUBBLE_PAD_NEAR, BUBBLE_RADIUS } from '../../common/Theme';
import { ChatMessage } from './ChatMessageCompose';

// 几何常量（观感参数集中在常量区，调观感只改这里）
const THUMB_SIZE: number = 64; // 图片缩略图边长（书 §2.5「64vp 起步」）与文件行高
const THUMB_RADIUS: number = 12; // 缩略图圆角
const AREA_GAP: number = 8; // 图片间距 / 图片行距 / 文件行距（统一 8）
const IMG_PER_ROW: number = 3; // 图片区每行上限（书 §2.5；360vp 屏自然换行可容 4 个，
// 每行 3 个是结构上限不是宽度巧合——平板宽屏下不靠 wrap 猜，分组显式定形）
const FILE_TEXT_MAX_WIDTH: number = 180; // 文件行文字列最大宽（超长文件名单行省略）
const FILE_ICON_SIZE: number = 26; // 文件行类型图标

@Component
export struct AttachmentBubble {
  // 消息对象（@ObjectLink——回放链装配 attachBriefs 是「重建后异步赋值」，普通成员 prop
  // 只在构造期同步一次会把首帧空态冻结（坑16 同族）；对象级观察使赋值即驱动本组件刷新）
  @ObjectLink msg: ChatMessage;
  // 点击派发上行（msgId + briefId；照 onAskSubmit 契约，本组件零业务——分派实现在
  // ChatPageContent，图片/文本进查看器、文档走系统预览）
  onPreviewAttach: (msgId: string, briefId: string) => void = (msgId: string,
    briefId: string): void => {
  };
  // 解码失败件集合（id 集；Image.onError 回填新实例赋值触发重渲染——该件退出图片区改走
  // 文件行形态，图片区与文件区都由它重算）
  @State private failedIds: Set<string> = new Set<string>();
  // 共享元素广播键订阅（三处判据同源 sharedGeomId——本件 / 输入栏条 / 查看器图片页）
  @StorageProp(ATTACH_SHARED_ID_KEY) sharedId: string = '';

  // 图片区行分组（每行最多 IMG_PER_ROW 个；解码失败件不进图片区——降级进文件区）
  private imageRows(): AttachmentBrief[][] {
    const rows: AttachmentBrief[][] = [];
    let current: AttachmentBrief[] = [];
    for (const brief of this.msg.attachBriefs ?? []) {
      if (brief.kind === 'image' && !this.failedIds.has(brief.id)) {
        current.push(brief);
        if (current.length >= IMG_PER_ROW) {
          rows.push(current);
          current = [];
        }
      }
    }
    if (current.length > 0) {
      rows.push(current);
    }
    return rows;
  }

  // 文件区清单（文本/文档件 + 解码失败降级的图片件——图片件图标用 picture 区分）
  private fileBriefs(): AttachmentBrief[] {
    const files: AttachmentBrief[] = [];
    for (const brief of this.msg.attachBriefs ?? []) {
      if (brief.kind !== 'image' || this.failedIds.has(brief.id)) {
        files.push(brief);
      }
    }
    return files;
  }

  // 解码失败登记（新实例赋值驱动重渲染——@State 集合整体替换，勿原地 add）
  private markDecodeFailed(id: string): void {
    if (this.failedIds.has(id)) {
      return;
    }
    const next: Set<string> = new Set<string>(this.failedIds);
    next.add(id);
    this.failedIds = next;
  }

  build() {
    // 行级形态与消息泡同款：右对齐（Blank 前缀）+ 左 BUBBLE_PAD_FAR / 右 BUBBLE_PAD_NEAR。
    // ★ 宽度上限与消息泡**不同**（2026-09-16 起）：消息泡收 60%（BUBBLE_USER_MAX_WIDTH），
    // 本泡恒 100%——图片区每行 3 个是结构上限（3×64 + 2×8 + 内距 24 = 232vp），跟收会挤掉
    // 第三个缩略图；两泡同为右对齐、左缘不齐属正常（各自随内容收缩）
    Row() {
      Blank()
      // 泡体：同底色同圆角（chat_bubble_user / 16）、内距 12、宽度上限 100%；泡内不叠第二
      // 层卡底（图片裸缩略图 / 文件裸行直接排在同底色上——「泡中卡」双层底观感差，书 §6-10；
      // 对比太弱一行即改回卡底）
      Column({ space: AREA_GAP }) {
        // ── 图片区：圆角缩略图方块，每行最多 3 个、超行换行（不横滑——独立气泡有整宽
        //    可用；横滑是输入栏的克制形态）──
        ForEach(this.imageRows(), (row: AttachmentBrief[]) => {
          Row({ space: AREA_GAP }) {
            ForEach(row, (brief: AttachmentBrief) => {
              Image(fileUri.getUriFromPath(brief.absPath))
                .width(THUMB_SIZE)
                .height(THUMB_SIZE)
                .borderRadius(THUMB_RADIUS)
                .clip(true)
                .objectFit(ImageFit.Cover)
                .sourceSize({ width: THUMB_SIZE, height: THUMB_SIZE })
                // 共享元素 out 侧（官方口径：列表侧带 follow: true；id 单源判据 sharedGeomId）
                .geometryTransition(sharedGeomId(brief.id, this.sharedId), { follow: true })
                // 离场防析构（官方约束）——仅共享激活期挂，惰性期 IDENTITY 不动 LazyForEach 行为
                .transition(this.sharedId === brief.id ?
                  TransitionEffect.OPACITY.animation({ duration: ATTACH_PREVIEW_ANIM,
                    curve: Curve.Friction }) :
                  TransitionEffect.IDENTITY)
                .onClick((): void => {
                  this.onPreviewAttach(this.msg.id, brief.id);
                })
                .onError((): void => {
                  this.markDecodeFailed(brief.id);
                })
            }, (brief: AttachmentBrief) => brief.id)
          }
        }, (row: AttachmentBrief[]) => row.map((b: AttachmentBrief): string => b.id).join('|'))
        // ── 文件区：每件一行（图标 + 文件名单行省略 + 副行「EXT, 大小」）──
        ForEach(this.fileBriefs(), (brief: AttachmentBrief) => {
          Row({ space: 8 }) {
            SymbolGlyph(brief.kind === 'image' ? $r('sys.symbol.picture') :
              $r('sys.symbol.doc_text'))
              .fontSize(FILE_ICON_SIZE)
              .fontColor([$r('sys.color.icon_secondary')])
            Column({ space: 2 }) {
              Text(brief.name)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(extLabel(brief.name) + ', ' + formatFileSize(brief.size))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .constraintSize({ maxWidth: FILE_TEXT_MAX_WIDTH })
          }
          .height(THUMB_SIZE)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.onPreviewAttach(this.msg.id, brief.id);
          })
        }, (brief: AttachmentBrief) => brief.id)
      }
      .padding(12)
      .backgroundColor($r('app.color.chat_bubble_user'))
      // 圆角与消息泡同源（Theme BUBBLE_RADIUS——同屏相邻同底色的两泡须同步演化；
      // 原字面量 16 于 2026-09-17 自检轮并入单源，值不变）
      .borderRadius(BUBBLE_RADIUS)
      .constraintSize({ maxWidth: '100%' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: BUBBLE_PAD_FAR, right: BUBBLE_PAD_NEAR })
    .justifyContent(FlexAlign.End)
  }
}
