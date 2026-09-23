// 「开源项目鸣谢」二级页（2026-09-02 新增；「关于」页卡片进入——决明需求「关于页
// AI 辅助开发声明下加新卡，开源项目鸣谢，点击进二级页」）。版式随 AiAssistPage 定稿：
// 说明段（卡外） + 分组块（**分组标题在卡外左上** + 一张大卡，条目两行式 = 项目名 +
// 一句话说明，条间官方 Divider）。
// ★ 名单数据 = 下方 OPEN_SOURCE_GROUPS 常量——后续增删项目只动该常量。
// 条目说明只记「项目名 + 协议 + 一句话说明」，不写实现细节（保持轻量可维护）。
// ★ 2026-09-24 补「第三方商标」组（开源准备笔 2）：三张服务商 logo（DeepSeek / 月之暗面 /
// 智谱）随包分发但此前无声明——与仓库根 LICENSE-THIRD-PARTY.md「第三方商标」节同源；
// 组级说明走下方 OpenSourceGroup.note 字段（不新增卡片、不动页面标题）。
// ★ 2026-09-23 补第 9 条：PaddleOCR（PP-OCRv6 三模型与识别字典随包于 rawfile/ocr）——
// 内置识别引擎 2026-09-16 落地时漏登；模型权重 Apache-2.0 已逐仓核实（方案档实查记录）。
// ★ 2026-09-07 补全并简化：名单扩至 8 条（新增 formula_hybrid 与 rawfile/document-parser
// 文档解析四库），分组合一（原「参考与移植」/「第三方组件」→「开源项目」），条目一律
// 「协议 · 一句话用途」；许可文本随包 NOTICE.md + LICENSE-*.txt、项目根
// LICENSE-THIRD-PARTY.md 全文收录。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor
} from '../common/Theme';
import { SETTING_TITLE_OPEN_SOURCE } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';

// 鸣谢条目（项目名主行 + 一句话说明副行）
interface OpenSourceItem {
  // 项目名（含来源标注，如 GitHub 仓库 / ohpm 包名）
  name: string;
  // 一句话说明（协议 + 用途；纯展示）
  desc: string;
}

// 鸣谢分组（卡外左上标题 + 卡片条目清单）
interface OpenSourceGroup {
  title: string;
  // 组级说明（空串 = 不渲染；位置在组标题与卡片之间——先说明后清单）
  note: string;
  items: OpenSourceItem[];
}

const OPEN_SOURCE_GROUPS: OpenSourceGroup[] = [
  {
    title: '开源项目',
    note: '',
    items: [
      {
        name: 'Cube Chat（chatcube）',
        desc: 'MIT · GitHub LongLiveY96/chatcube，流式引擎与渲染组件参考'
      },
      {
        name: '@lidary/markdown',
        desc: 'MIT · 消息 Markdown 渲染'
      },
      {
        name: '@cangjie-tpc/markdown_hybrid',
        desc: 'Apache-2.0 · 增量 Markdown 渲染'
      },
      {
        name: '@cangjie-tpc/formula_hybrid',
        desc: 'MIT · LaTeX 公式渲染'
      },
      {
        name: 'SheetJS（xlsx）',
        desc: 'Apache-2.0 · Excel 文档解析'
      },
      {
        name: 'PDF.js',
        desc: 'Apache-2.0 · PDF 文档解析'
      },
      {
        name: 'Mammoth.js',
        desc: 'BSD-2-Clause · Word 文档解析'
      },
      {
        name: 'JSZip',
        desc: 'MIT · ZIP 压缩包解析'
      },
      {
        name: 'PaddleOCR（PP-OCRv6）',
        desc: 'Apache-2.0 · 内置识别的模型与字典'
      }
    ]
  },
  {
    title: '第三方商标',
    note: '下列标识为第三方商标，本应用与权利人不存在关联，亦未获其赞助或认可。标识仅用于识别对应的服务，相关商标归各自权利人所有。',
    items: [
      {
        name: 'DeepSeek',
        desc: '服务商卡片头像'
      },
      {
        name: '月之暗面 Kimi',
        desc: '服务商卡片头像'
      },
      {
        name: '智谱 Z.ai',
        desc: '服务商卡片头像'
      }
    ]
  }
];

@Component
export struct OpenSourcePage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（状态最小化）
  topPad: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新配色；卡片背景/分割线用）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 分组大卡（自制分组卡：AiAssistPage 先例——cardBg 圆角 16，无轮廓线；条目两行式
  //（名称 15sp 主色 + 说明 13sp 次要色），条间官方 Divider（左右各缩进 16vp，左沿对齐文字）
  @Builder
  GroupCard(group: OpenSourceGroup) {
    Column() {
      ForEach(group.items, (item: OpenSourceItem) => {
        Column({ space: 4 }) {
          Text(item.name)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
          Text(item.desc)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        Divider()
          .color(cardBorderColor(this.appColorMode))
          // 分割线不延伸至卡片两端：左右各缩进 16vp（同 AiAssistPage）
          .padding({ left: 16, right: 16 })
      }, (item: OpenSourceItem) => item.name)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 组间距 = 卡片块自身 margin（分组块属大区块非卡片间距，组间距 16vp 不进 CARD_SPACING）
    .margin({ bottom: 16 })
  }

  // 分组（卡外左上标题 + 卡片；标题宽度 CARD_PANEL_WIDTH 使左沿与卡片左沿对齐——同
  // AiAssistPage PermissionPage 先例；标题与卡片间距 8vp）
  @Builder
  GroupBlock(group: OpenSourceGroup) {
    Text(group.title)
      .width(CARD_PANEL_WIDTH)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .margin({ bottom: 8 })
    // 组级说明（有才渲染；与卡片左沿对齐，同说明段宽度口径）
    if (group.note !== '') {
      Text(group.note)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(20)
        .width(CARD_PANEL_WIDTH)
        .margin({ bottom: 8 })
    }
    this.GroupCard(group)
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——同 AboutPage 坑）
    Column() {
      Scroll() {
        Column() {
          // 鸣谢说明段（通用措辞；宽度 CARD_PANEL_WIDTH 左对齐——与卡片左沿对齐）
          Text('本应用在开发过程中参考了以下开源项目，并使用了其中部分组件与实现思路，在此致以谢意。')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .lineHeight(21)
            .width(CARD_PANEL_WIDTH)
            .margin({ bottom: 16 })

          ForEach(OPEN_SOURCE_GROUPS, (group: OpenSourceGroup) => {
            this.GroupBlock(group)
          }, (group: OpenSourceGroup) => group.title)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（规范同 AboutPage：首元素静止时完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——同 AboutPage）
      .align(Alignment.TopStart)
      // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）
    PageShell({
      title: SETTING_TITLE_OPEN_SOURCE,
      content: () => {
        this.Content()
      }
    })
  }
}
