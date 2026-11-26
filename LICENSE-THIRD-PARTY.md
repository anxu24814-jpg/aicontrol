# 第三方许可声明

本文件收录本应用所使用第三方开源组件的完整许可证文本，与「关于 → 开源项目鸣谢」页条目对应。
rawfile 文档解析组件（SheetJS / PDF.js / Mammoth.js / JSZip）的许可文本已随包分发于
`entry/src/main/resources/rawfile/document-parser/NOTICE.md` 与 `LICENSE-*.txt`，此处不重复。
rawfile 内置识别资产（PaddleOCR PP-OCRv6 三模型与识别字典）的许可文本已随包分发于
`entry/src/main/resources/rawfile/ocr/NOTICE.md` 与 `LICENSE-Apache-2.0.txt`，此处不重复。
Node 运行环境（Node.js / npm 文件集及其依赖包）的许可声明与逐包清单已随包分发于
`entry/src/main/resources/rawfile/node/NOTICE.md` 与 `LICENSE-Node.js.txt`，此处只留组件清单节。

## Mermaid 11.16.0 — MIT 与捆绑依赖许可

固定原始发行包：https://registry.npmjs.org/mermaid/-/mermaid-11.16.0.tgz 。
原样随包 `entry/src/main/resources/rawfile/markdown-preview/mermaid.min.js`，SHA256
`74d7c46dabca328c2294733910a8aa1ed0c37451776e8d5295da38a2b758fb9b`。
不取自 AGPL 应用包装，不修改或裁掉 bundle 中的版权与捆绑许可尾注。

Mermaid MIT 全文、DOMPurify 3.4.0（采用 Apache-2.0 选项）、js-yaml 4.1.1、
lodash/Underscore、cytoscape 及声明依赖树的许可全文随包收录于
`entry/src/main/resources/rawfile/markdown-preview/NOTICE.txt`。该合集是许可告知的保守超集，
不宣称其列出的所有包都进入固定 bundle；未将 npm 依赖树作为应用依赖或打包资源。
独立可信 `mermaid.html` 是本项目的受限调用与输出校验壳，不是上游或竞品代码。

## Cube Chat（chatcube）— MIT License

来源：https://github.com/LongLiveY96/chatcube

MIT License

Copyright (c) 2026 longlivey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## @cangjie-tpc/formula_hybrid — MIT License（MicroTeX）与 Apache License 2.0（MathJax-mhchem）

来源：https://gitcode.com/Cangjie-TPC/formula-ffi
上游组件：https://github.com/NanoMichael/MicroTeX / https://github.com/mhchem/MathJax-mhchem

MIT License

Copyright (c) 2020 Nano Michael

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "{}"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright {yyyy} {name of copyright owner}

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

## PaddleOCR（PP-OCRv6）— Apache License 2.0

来源：https://github.com/PaddlePaddle/PaddleOCR

模型仓：https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx
        https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx
        https://huggingface.co/PaddlePaddle/PP-LCNet_x0_25_textline_ori_onnx

本应用内置识别引擎随包分发上述三模型（经 converter_lite 离线转换为 MindSpore Lite 的 `.ms`）
与识别字典 `ppocr/utils/dict/ppocrv6_tiny_dict.txt`（6,904 行）。

许可口径：PaddleOCR 本体与模型权重均 Apache-2.0（各模型仓 license front-matter 已逐仓核实）。

许可全文与随包署名见 `entry/src/main/resources/rawfile/ocr/LICENSE-Apache-2.0.txt`
与同目录 `NOTICE.md`。

## 第三方商标 — 非许可条目

以下随包资源是第三方商标。本应用只在用户配置的服务地址指向该家官方域名时，用其识别对应的服务，
不构成本项目对相关商标的任何权利主张，也不表示与权利人之间存在关联、赞助或认可关系。

| 资源 | 权利人 | 用途 |
| --- | --- | --- |
| `entry/src/main/resources/base/media/deepseek_logo.png` | DeepSeek | 服务商卡片头像 |
| `entry/src/main/resources/base/media/kimi_logo.svg`（另有 `dark/media/` 反白版） | 月之暗面 Kimi | 服务商卡片头像 |
| `entry/src/main/resources/base/media/zai_logo.svg`（另有 `dark/media/` 反白版） | 智谱 Z.ai | 服务商卡片头像 |

本项目自身的开源许可证（Apache License 2.0）不授予任何商标使用权。权利人若认为上述用法不妥，
联系开发者后将移除对应资源。

消费点：`entry/src/main/ets/common/providers/ProviderCatalog.ets` 的 `providerAvatarAsset`，
展示于 `entry/src/main/ets/components/settings/ProviderHeadCard.ets`。

## Unicode Character Database 16.0.0 — Unicode License v3

来源：https://www.unicode.org/Public/16.0.0/ucd/CaseFolding.txt

用于自研 Markdown 引用标签默认大小写折叠，C/F映射经机械转换为
`entry/src/main/ets/common/markdown/MarkdownCaseFold.ets`，非外部运行库。
应用内「关于 → 开源项目鸣谢 → Unicode 标准数据」离线显示以下许可全文。
阶段3调试包已接入自研助手正文，正式包仍保留旧库。原始数据指纹见源码头。

UNICODE LICENSE V3

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
authorization of the copyright holder.

## Python 运行时（CPython 3.13.18 与预置包）— 组件许可清单

应用内嵌 CPython 3.13.18 运行时（`libpython3.13.so` + 标准库 `python313.zip`），随包分发
28 个 PyPI 预置包与交叉编译原生依赖。包名、版本与许可的冻结单源 =
`scripts/python-runtime/manifest.json`（PyPI JSON API 实查，2026-11-06），本节许可名逐字
照该单源；各许可全文可在 SPDX 许可库（https://spdx.org/licenses/ ）或对应上游仓库的
LICENSE 文件查阅。

### CPython 与交叉编译原生依赖

原生依赖经 `scripts/python-runtime/factory/build-native-deps.sh` 等工厂脚本交叉编译到
OHOS aarch64 后随应用 lib 目录分发；版本与许可以脚本内冻结版本变量与通行许可为准。

| 组件 | 版本 | 许可 | 上游 |
| --- | --- | --- | --- |
| CPython | 3.13.18 | Python-2.0.1（PSF License） | https://www.python.org/ |
| zlib | 1.3.1 | Zlib | https://github.com/madler/zlib |
| OpenSSL | 3.5.4 | Apache-2.0 与 OpenSSL License 双许可 | https://www.openssl.org/ |
| libffi | 3.4.6 | MIT | https://github.com/libffi/libffi |
| freetype | 2.13.3 | FTL（FreeType License）与 GPL-2.0 双许可 | https://freetype.org/ |
| libpng | 1.6.44 | libpng License（PNG Reference Library v2） | http://www.libpng.org/pub/png/libpng.html |
| libjpeg-turbo | 3.0.4 | IJG、zlib 与 BSD-3-Clause 三许可 | https://github.com/libjpeg-turbo/libjpeg-turbo |
| libxml2 | 2.13.5 | MIT | https://gitlab.gnome.org/GNOME/libxml2 |
| libxslt | 1.1.42 | MIT | https://gitlab.gnome.org/GNOME/libxslt |
| OpenBLAS | 0.3.28 | BSD-3-Clause | https://github.com/OpenMathLib/OpenBLAS |
| qhull | 8.0.2 | Qhull License（BSD 风格） | http://www.qhull.org/ |
| PDFium | 以构建脚本探针为准（兜底分支 chromium/8138） | BSD-3-Clause | https://pdfium.googlesource.com/pdfium/ |

依赖库构建参数取自 zhubowen-bot/Guncat-Work-for-hmos（Apache-2.0，
https://github.com/zhubowen-bot/Guncat-Work-for-hmos ），在此署名。PDFium 自编
`libpdfium.so` 随 pypdfium2 包树分发。构建期工具链（setuptools、meson-python、pybind11、
maturin、cppy、setuptools_scm 等）仅参与构建，不随应用包分发。

### 预置 PyPI 包（28 项，manifest 冻结顺序）

| # | 包 | 版本 | 许可 | 上游 |
| --- | --- | --- | --- | --- |
| 1 | pip | 26.3 | MIT | https://pip.pypa.io/ |
| 2 | setuptools | 84.2.1 | MIT | https://github.com/pypa/setuptools |
| 3 | wheel | 0.48.0 | MIT | https://github.com/pypa/wheel |
| 4 | flit-core | 4.2.0 | BSD-3-Clause | https://github.com/pypa/flit |
| 5 | packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | https://github.com/pypa/packaging |
| 6 | pyparsing | 3.3.3 | MIT | https://github.com/pyparsing/pyparsing |
| 7 | six | 1.17.0 | MIT | https://github.com/benjaminp/six |
| 8 | et-xmlfile | 2.0.0 | MIT | https://foss.heptapod.net/openpyxl/et_xmlfile |
| 9 | openpyxl | 3.1.5 | MIT | https://foss.heptapod.net/openpyxl/openpyxl |
| 10 | python-dateutil | 4.0.0 | BSD-3-Clause | https://github.com/dateutil/dateutil |
| 11 | typing-extensions | 4.16.0 | PSF-2.0 | https://github.com/python/typing_extensions |
| 12 | tzdata | 2026.6 | Apache-2.0 | https://github.com/python/tzdata |
| 13 | fonttools | 4.68.0 | MIT | https://github.com/fonttools/fonttools |
| 14 | cycler | 0.12.1 | BSD | https://github.com/matplotlib/cycler |
| 15 | pycparser | 3.12 | BSD-3-Clause | https://github.com/eliben/pycparser |
| 16 | cffi | 2.1.1 | MIT-0 | https://github.com/python-cffi/cffi |
| 17 | contourpy | 1.4.0 | BSD-3-Clause | https://github.com/contourpy/contourpy |
| 18 | kiwisolver | 1.5.1 | BSD | https://github.com/nucleic/kiwisolver |
| 19 | lxml | 6.1.3 | BSD-3-Clause | https://lxml.de/ |
| 20 | matplotlib | 3.11.2 | PSF（matplotlib 协议） | https://matplotlib.org/ |
| 21 | numpy | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | https://numpy.org/ |
| 22 | pandas | 3.1.1 | BSD-3-Clause | https://pandas.pydata.org/ |
| 23 | pillow | 13.0.0 | MIT-CMU | https://python-pillow.org/ |
| 24 | regex | 2026.9.29 | Apache-2.0 AND CNRI-Python | https://github.com/mrabarnett/mrab-regex |
| 25 | cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | https://github.com/pyca/cryptography |
| 26 | pydantic-core | 2.50.4 | MIT | https://github.com/pydantic/pydantic-core |
| 27 | rpds-py | 2026.9.1 | MIT | https://github.com/crate-py/rpds |
| 28 | pypdfium2 | 5.14.0 | BSD-3-Clause, Apache-2.0 | https://github.com/pypdfium2/pypdfium2 |

### Rust 组件说明

cryptography、pydantic-core、rpds-py 三件经 maturin 交叉编译为 CPython 扩展，静态链接
Rust 标准库；Rust 工具链与标准库按 Apache-2.0 / MIT 双许可分发
（https://www.rust-lang.org/ ）。三件本体已列于上表，此处只补 Rust 标准库的许可归属。

### 自装包白名单（运行期按需安装，冻结版本）

除随包分发的预置包外，应用还支持在 Python 运行环境管理页从 PyPI 官方仓库
（files.pythonhosted.org）按需安装白名单内的纯 Python wheel 包，含二进制成分的包一律
拒绝安装。下列包名、版本与 sha256 在应用内冻结，单源 =
`entry/src/main/ets/common/pyexec/PyPackages.ets`，本节许可名逐字照该单源。

| 包 | 版本 | 许可 | 说明 |
| --- | --- | --- | --- |
| python-docx | 1.2.0 | MIT | Word 文档读写 |
| python-pptx | 1.0.2 | MIT | PPT 文档生成 |
| pypdf | 7.1.0 | BSD-3-Clause | PDF 读取处理 |
| pdfplumber | 0.11.10 | MIT | PDF 文本与表格提取 |
| beautifulsoup4 | 4.15.0 | MIT | HTML 解析 |
| soupsieve | 4.1.1 | MIT | beautifulsoup4 依赖 |
| xlsxwriter | 3.3.1 | BSD-2-Clause | Excel 文档生成 |
| pdfminer.six | 20260107 | MIT | PDF 文本挖掘 |
| charset-normalizer | 3.5.2 | MIT | 字符编码检测 |

## Node 运行时（Node.js 24.22.3 与 npm 文件集）— 组件许可清单

应用内嵌 Node.js 24.22.3 运行时（`libnode.so`，由 `scripts/node-runtime/factory/` 工厂交叉编译，
对上游源码树的补丁清单见 `scripts/node-runtime/manifest.json` 的 `patches` 节），并随包分发
npm 11.19.1 文件集及其依赖包。包名、版本与许可的冻结单源 = `scripts/node-runtime/manifest.json`
与 `scripts/node-runtime/evidence/license-manifest.json`（工厂构建期逐包扫描），本节许可名逐字
照该单源。

| 组件 | 版本 | 许可 | 说明 |
| --- | --- | --- | --- |
| Node.js | 24.22.3 | MIT | 内嵌运行环境本体（`libnode.so`） |
| npm | 11.19.1 | Artistic-2.0 | 随包的包管理文件集 |

Node.js 本体的 MIT 许可全文、npm 许可全文的落点，以及 npm 文件集内全部包的逐包许可清单，随包
收录于 `entry/src/main/resources/rawfile/node/NOTICE.md`，由 `scripts/node-runtime/gen-license-notice.mjs`
自上述单源清单生成。`libnode.so` 内编入的 Node.js 上游外部维护库（V8、zlib、c-ares、llhttp、ada 等）
各自的许可声明全文，随包收录于同目录 `LICENSE-Node.js.txt`（Node.js v24.22.3 源码树根 `LICENSE`
文件原件）。两份文件在此不重复抄录。

运行期经助手从 npm 官方源安装的包（纯 JS、精确版本）不随应用包分发，其许可以各包自带的 `LICENSE`
文件为准。
