# Document parser third-party notices

This directory contains browser bundles used only inside the local ArkWeb document
parser sandbox.

- `xlsx.full.min.js`: SheetJS CE, detected runtime version `0.20.3`.
  Upstream project: https://github.com/SheetJS/sheetjs. License: Apache-2.0.
- `mammoth.browser.min.js`: Mammoth.js browser bundle.
  Upstream project: https://github.com/mwilliamson/mammoth.js. License: BSD-2-Clause.
- `pdf.min.js` and `pdf.worker.min.js`: Mozilla PDF.js, version `3.11.174`.
  Upstream project: https://github.com/mozilla/pdfjs-dist. License: Apache-2.0.
- `jszip.min.js`: JSZip, version `3.10.1`.
  Upstream project: https://github.com/Stuk/jszip. License: MIT or GPL-3.0.
  Bundled pako dependency is MIT licensed.

Keep this file updated when replacing any bundled parser dependency.

Full license texts are provided in the accompanying LICENSE-*.txt files.
