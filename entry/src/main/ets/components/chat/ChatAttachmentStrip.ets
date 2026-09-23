// 聊天输入框内附件条（2026-08-24 四十六改新增，决明需求「附件放输入框内、类参考图效果」）：
// 原「胶囊外附件 chip 行」（ChatInputBar AttachmentRow，三十一改初版）重做为参考图形态——
// · 图片 = 真缩略图方块（PixelMap 内存小图，KimiAttachmentCtrl 上传后解码自沙箱副本、
//   随即删除——「手机端不驻留本体」存储决策不变，仅多一张内存小图）；解码失败降级图标卡。
//   四十七改：缩略图改从模块级仓库 AttachmentThumbStore 按 fileId 直取——@Prop 深拷贝
//   会破坏 PixelMap（真机空白实锤），PixelMap 不走组件参数（详见仓库头注释）。
// · 文件 = 图标卡（类型图标 + 文件名 + 「EXT, 16.39 KB」副行，参考图样式）。★ 2026-09-17
//   全面自检第4轮笔2：原「视频」图标支随附件类型收窄成死支——入列白名单（classifyByName
//   全集 image/text/doc，AttachmentPickCtrl 不产生 kind='video'）后该判据不可达，已退役
//   （断言 67 组负向钉全仓守）。
// · 删除 = 右上角深色 x 徽标（向上骑跨卡片顶边，参考图同款）。四十七改：徽标水平方向
//   收回卡片内（原向右半探出 9vp——横滑至最右时与胶囊右上圆角裁剪区相碰/视觉重叠，
//   决明真机反馈；现只向上探出，由条顶部留白承接，任何滚动位置都不碰胶囊边缘）。
//   ★ 2026-09-09 决明真机「删除按钮错位、锚点不在附件右上角而是略左偏」：收回过度——
//   热区（26）比可视圆（18）宽出的半差使圆右缘内缩 4vp，现右移该半差、右缘与卡片右缘
//   齐平（仍不探出卡片，四十七改结论不破）。
// 横滑：官方 Scroll 横向 + BarState.Off（隐藏滚动条）——数量超宽不换行（主流聊天 App 形态，
// 决明需求「附件过多横滑切换」）；Scroll 通用 align 默认 Center，须显式 Start 左对齐
//（2026-08-20 列表卡片规范同款踩坑）。
// 高度：本组件不设高度——内容自适应（输入框整体高度自适应由外层胶囊 Column 承担，
// 决明需求「输入框高度自适应」）。
// 材质红线：附件项只用语义色填充（comp_background_tertiary 卡底），不设材质/边框/阴影——
// 胶囊外层已有 systemMaterial，「同一子树最外层只设一次材质」（沉浸光感性能十诫，
// 见 docs/沉浸光感适配规范.md）；深色/浅色由官方语义色自动适配。
import { image } from '@kit.ImageKit';
import { PendingAttachment } from '../../common/providers/AiTypes';
import { extLabel, formatFileSize, ATTACH_SHARED_ID_KEY, sharedGeomId,
  ATTACH_PREVIEW_ANIM } from '../../common/AttachmentUtil';
import { getThumb } from './AttachmentThumbStore';

// 几何常量（参考图（1080 宽屏 ≈ 360vp）换算取整；调样式只改这里）
const ITEM_SIZE: number = 64; // 附件项高 = 图片缩略图边长 = 文件卡高
const ITEM_RADIUS: number = 12; // 附件项圆角
const ITEM_SPACE: number = 12; // 附件项间距
const CARD_ICON_SIZE: number = 30; // 文件卡类型图标
const CARD_TEXT_MAX_WIDTH: number = 112; // 文件卡文字列最大宽（文件名超出省略号；
// 四十七改自 132 调短——决明反馈文件名显示过长，截断限制收紧）
const BADGE_VISUAL: number = 18; // 删除徽标可视圆径
const BADGE_HIT: number = 26; // 删除徽标热区边长（透明底扩触——18 可视圆太小不够点）
const STRIP_HPAD: number = 12; // 附件条左右留白
const STRIP_TOP: number = 12; // 附件条顶部留白（≥ 徽标上探出 9，防探出部分被胶囊裁剪）
const STRIP_BOTTOM: number = 4; // 附件条底部留白（输入行 TextArea 上 padding 补足与文字的间距）

// 文件副行扩展名段与大小段：2026-09-15 预览笔上收 AttachmentUtil（extLabel /
// formatFileSize 单源——附件气泡与输入栏附件条两消费方同口径，断言钉同源；本文件原
// 本地实现已删）。docStateLabel（解析态段）仍留本文件——输入栏独有语义。

// 文档附件副行解析态段（2026-09-03 第三批②）：覆盖大小段——解析中/失败/过大是用户当下
// 最关心的信息；done 与未开始的 idle 仍显示大小（解析完成无需打扰）。
// ★ 2026-09-15 附件 PDF 页渲染一期新增页图档（档序 = 现有三档之后、回落大小段之前）：
// 扫描件 PDF 已转页图，用户看到的「这条附件发了什么」由大小改为页数口径；页数超上限
// （RENDER_MAX_PAGES）时补「共 N 页」——N = 全量页数，M = 实发页图数
function docStateLabel(att: PendingAttachment): string {
  if (att.parseState === 'parsing') {
    return '解析中…';
  }
  if (att.parseState === 'failed') {
    return '解析失败';
  }
  if (att.parseState === 'toolarge') {
    return '过大不支持';
  }
  const sentPages: number = att.pageImages !== undefined ? att.pageImages.length : 0;
  if (att.parseState === 'done' && sentPages > 0) {
    const totalPages: number = att.pageCount ?? sentPages;
    return totalPages > sentPages ?
      '已转 ' + sentPages + ' 页图，共 ' + totalPages + ' 页' :
      '已转 ' + sentPages + ' 页图';
  }
  return extLabel(att.name) + ', ' + formatFileSize(att.size);
}

@Component
export struct AttachmentStrip {
  // 待发附件（父组件 @State 持有；数组赋值触发 @Prop 刷新——发送成功/删除后父组件重新赋值）
  @Prop attachments: PendingAttachment[] = [];
  // 删除（index 上行父组件从列表移除——本地状态独占，无网络副作用）
  onRemove: (index: number) => void = () => {
  };
  // 点开预览（2026-09-15 预览第三轮，拍板 4：fileId 上行 → ChatInputBar 透传 →
  // ChatPageContent 分派——图片/文本进查看器、文档走系统预览；解析中/失败/过大的文档
  // 同样可预览——预览只看文件与解析无关）
  onPreview: (fileId: string) => void = () => {
  };
  // 共享元素广播键订阅（2026-09-15 预览升级笔；三处判据同源 sharedGeomId——本件 /
  // 消息气泡缩略图 / 查看器图片页）
  @StorageProp(ATTACH_SHARED_ID_KEY) sharedId: string = '';

  // 删除徽标：18 可视深底圆 + 白 x（深浅色通用——叠在图片/卡片上的浮层 scrim 语义，参考图
  // 同款），外层 26 透明热区（backgroundColor(Color.Transparent) 官方扩触姿势——无背景
  // 容器空白区不响应触摸）；TopEnd 对齐 + offset((26−18)/2, -13)：垂直上移半热区 → 可视圆
  // 骑跨卡片顶边（上探出 9 = 18/2，由 STRIP_TOP 承接）；水平右移热区比可视圆宽出的半差 4 →
  // **可视圆右缘与卡片右缘齐平**（★ 2026-09-09 决明真机「锚点略左偏」——原 x=0 使右缘内缩
  // 4vp；四十七改的 offset(13, -13) 右探出版会与胶囊右上圆角裁剪区相碰，仍不取）。
  // 入参传 att 不传 index：ForEach 键稳定的项在数组变更后复用旧子组件（index 闭包陈旧，
  // 删中间项后再删会错位）——点击时按 fileId 实查当下索引（2026-09-04 解析自检笔）
  @Builder
  RemoveBadge(att: PendingAttachment) {
    Stack() {
      Stack() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(11)
          .fontColor([Color.White])
      }
      .width(BADGE_VISUAL)
      .height(BADGE_VISUAL)
      .borderRadius(BADGE_VISUAL / 2)
      .backgroundColor('#B31C1C1E')
    }
    .width(BADGE_HIT)
    .height(BADGE_HIT)
    .backgroundColor(Color.Transparent)
    .offset({ x: (BADGE_HIT - BADGE_VISUAL) / 2, y: -BADGE_HIT / 2 })
    .onClick(() => {
      const index: number =
        this.attachments.findIndex((item: PendingAttachment): boolean =>
          item.fileId === att.fileId);
      if (index >= 0) {
        this.onRemove(index);
      }
    })
  }

  // 图片附件项：真缩略图方块（Cover 裁满；thumb 从模块级仓库 AttachmentThumbStore 直取——
  // @Prop 深拷贝会破坏 PixelMap，不走组件参数）。整卡点击上行预览（删除徽标在 Stack 上层
  // 独立命中，点徽标不触发预览——两热区不串为真机验证项）。★ 2026-09-15 预览升级笔：
  // 缩略图挂共享元素 out 侧（follow: true 官方口径；id 判据三处同源 sharedGeomId），
  // transition 仅共享激活期挂（常挂会让条内缩略图随数组增删逐个淡入）
  @Builder
  ImageItem(thumb: image.PixelMap, att: PendingAttachment) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(thumb)
        .width(ITEM_SIZE)
        .height(ITEM_SIZE)
        .borderRadius(ITEM_RADIUS)
        .clip(true)
        .objectFit(ImageFit.Cover)
        .geometryTransition(sharedGeomId(att.fileId, this.sharedId), { follow: true })
        .transition(this.sharedId === att.fileId ?
          TransitionEffect.OPACITY.animation({ duration: ATTACH_PREVIEW_ANIM,
            curve: Curve.Friction }) :
          TransitionEffect.IDENTITY)
      this.RemoveBadge(att)
    }
    .onClick(() => {
      this.onPreview(att.fileId);
    })
  }

  // 文件附件项（图片解码失败也降级走这里——kind 图标区分类型）。整卡点击上行预览
  @Builder
  FileItem(att: PendingAttachment) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row({ space: 8 }) {
        SymbolGlyph(att.kind === 'image' ? $r('sys.symbol.picture') : $r('sys.symbol.doc_text'))
          .fontSize(CARD_ICON_SIZE)
          .fontColor([$r('sys.color.icon_secondary')])
        Column({ space: 2 }) {
          Text(att.name)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 副行：文档附件显示解析态（解析中/失败/过大），其余显示扩展名+大小
          Text(att.kind === 'doc' ? docStateLabel(att) :
            extLabel(att.name) + ', ' + formatFileSize(att.size))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: CARD_TEXT_MAX_WIDTH })
      }
      .height(ITEM_SIZE)
      .padding({ left: 10, right: 12 })
      .borderRadius(ITEM_RADIUS)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      this.RemoveBadge(att)
    }
    .onClick(() => {
      this.onPreview(att.fileId);
    })
  }

  build() {
    Scroll() {
      Row({ space: ITEM_SPACE }) {
        ForEach(this.attachments, (att: PendingAttachment) => {
          // 缩略图仓库直取（两次 get 廉价——Map 查找；取不到 = 解码失败/非图片 → 图标卡）
          if (att.kind === 'image' && getThumb(att.fileId) !== undefined) {
            this.ImageItem(getThumb(att.fileId) as image.PixelMap, att)
          } else {
            this.FileItem(att)
          }
          // 键须含 parseState：解析完成/失败经 patchAttachment 整数组替换上行但 fileId
          // 不变——官方 ForEach「键已存在即复用旧组件」不重跑 itemGenerator，副行
          // docStateLabel 会定格「解析中…」（2026-09-04 解析修复；5b418ff P1-1 同族）
        }, (att: PendingAttachment) => att.fileId + '|' + (att.parseState ?? ''))
      }
      .padding({ left: STRIP_HPAD, right: STRIP_HPAD, top: STRIP_TOP, bottom: STRIP_BOTTOM })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    // Scroll 通用 align 默认 Alignment.Center——内容不足一屏宽时必须显式左对齐（官方
    // ts-universal-attributes-location 核实，项目列表卡片规范同款）
    .align(Alignment.Start)
    .width('100%')
  }
}
