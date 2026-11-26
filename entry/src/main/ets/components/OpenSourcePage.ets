// 「开源项目鸣谢」二级页（「关于」页卡片进入）。版式随 AiAssistPage 定稿：说明段（卡外）
// + 分组块（**分组标题在卡外左上** + 一张大卡，条目两行式 = 项目名 + 一句话说明，条间官方
// Divider）；组级说明走 OpenSourceGroup.note 字段。
// ★ 名单数据 = 下方 OPEN_SOURCE_GROUPS 常量——后续增删项目只动该常量；条目说明只记
// 「项目名 + 协议 + 一句话说明」，不写实现细节。名单与仓库根 LICENSE-THIRD-PARTY.md 同源
//（全文收录；许可文本另随包 NOTICE.md + LICENSE-*.txt，「第三方商标」节亦同源）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor, CARD_RADIUS
} from '../common/Theme';
import { SETTING_TITLE_OPEN_SOURCE } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';
import { InfoCard } from './InfoCard';

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

// 许可全文在应用内离线可读；与根LICENSE-THIRD-PARTY及标准数据源码头同文。
const UNICODE_LICENSE_V3: string = `UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.`;

const OPEN_SOURCE_GROUPS: OpenSourceGroup[] = [
  {
    title: '开源项目',
    note: '',
    items: [
      {
        name: 'Cube Chat（chatcube）',
        desc: 'MIT · GitHub LongLiveY96/chatcube，流式传输与文档解析等参考'
      },
      {
        name: '@cangjie-tpc/formula_hybrid',
        desc: 'MIT、Apache-2.0 · 独立 LaTeX 公式排版'
      },
      {
        name: 'Mermaid 11.16.0 与捆绑依赖',
        desc: 'MIT、ISC、BSD、Apache-2.0 等 · 离线图表预览，完整许可随应用分发'
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
      },
      // Node 运行环境两条（2026-11-24 鸿蒙 Node 运行时门 4）：许可声明全文与 npm 文件集逐包清单
      // 随包收录于 rawfile/node/NOTICE.md 与 LICENSE-Node.js.txt，此处只记项目名、协议与用途
      {
        name: 'Node.js 24.22.3',
        desc: 'MIT · 内嵌运行环境，许可声明全文随应用分发'
      },
      {
        name: 'npm 11.19.1 与捆绑依赖',
        desc: 'Artistic-2.0、ISC、MIT 等 · 包管理文件集，完整许可随应用分发'
      }
    ]
  },
  {
    title: '内置字体',
    note: '下列字体随应用分发，用于消息字体的可选项，许可协议均为 SIL Open Font License 1.1，可自由使用与再分发。版权归各字体作者所有，许可全文随应用提供。',
    items: [
      {
        name: 'Noto Serif SC',
        desc: 'SIL OFL 1.1 · 版权 2017-2024 Adobe · 衬线预设'
      },
      {
        name: '朱雀仿宋',
        desc: 'SIL OFL 1.1 · 版权 2023 浙江星玺科技（璇玑造字）· 仿宋预设'
      },
      {
        name: 'JetBrains Mono',
        desc: 'SIL OFL 1.1 · 版权 2020 JetBrains 项目作者 · 代码等宽预设'
      }
    ]
  },
  {
    title: 'Unicode 标准数据',
    note: 'Unicode Character Database 16.0.0，用于 Markdown 引用标签的大小写折叠。原始数据来自 unicode.org。',
    items: [{ name: 'Unicode License v3', desc: UNICODE_LICENSE_V3 }]
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

  // 分组大卡（自制分组卡，AiAssistPage 先例：cardBg 圆角无轮廓线、条目两行式、条间官方 Divider）
  @Builder
  GroupCard(group: OpenSourceGroup) {
    Column() {
      ForEach(group.items, (item: OpenSourceItem, index: number) => {
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
        // 末条后不留分割线（「条间线」语义——尾线贴卡底缘可见故收）
        if (index < group.items.length - 1) {
          Divider()
            .color(cardBorderColor(this.appColorMode))
            .padding({ left: 16, right: 16 })
        }
      }, (item: OpenSourceItem) => item.name)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 组间距 = 卡片块自身 margin（分组块属大区块非卡片间距，组间距 16vp 不进 CARD_SPACING）
    .margin({ bottom: 16 })
  }

  // 分组（卡外左上标题 + 卡片；标题宽度 CARD_PANEL_WIDTH 与卡片左沿对齐）
  @Builder
  GroupBlock(group: OpenSourceGroup) {
    Text(group.title)
      .width(CARD_PANEL_WIDTH)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .margin({ bottom: 8 })
    // 组级说明（空串不渲染；InfoCard 单源件）。★ 勿传 fullWidth：本页滚动列无水平 padding、
    // 同组卡片走 CARD_PANEL_WIDTH，fullWidth 会左右各宽出 16vp 与卡片/页首说明卡不齐
    //（缺省卡宽即对齐）
    if (group.note !== '') {
      InfoCard({ text: group.note })
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
          // 鸣谢说明段（通用措辞，InfoCard 单源件）
          InfoCard({ text: '本应用在开发过程中参考了以下开源项目，并使用了其中部分组件与实现思路，在此致以谢意。' })
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
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
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
