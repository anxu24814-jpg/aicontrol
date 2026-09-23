# Built-in OCR third-party notices

This directory contains the models and dictionary used only by the built-in on-device OCR
engine (MindSpore Lite inference provided by the system; the engine runs fully offline).

- `det.ms`, `rec.ms`, `cls.ms`: PaddleOCR PP-OCRv6 text detection / text recognition and
  PP-LCNet textline orientation classification models, converted offline to MindSpore Lite
  `.ms` format with `converter_lite`.
  Upstream project: https://github.com/PaddlePaddle/PaddleOCR
  Model repos: https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx,
  https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx,
  https://huggingface.co/PaddlePaddle/PP-LCNet_x0_25_textline_ori_onnx
  License: Apache-2.0.
- `rec_dict.txt`: recognition character dictionary (`ppocr/utils/dict/ppocrv6_tiny_dict.txt`).
  Upstream project: https://github.com/PaddlePaddle/PaddleOCR. License: Apache-2.0.

Full license text is provided in `LICENSE-Apache-2.0.txt` in this directory. The in-app
acknowledgements page lists this component (Settings -> More -> About -> Open source
acknowledgements). Keep this file updated when replacing any bundled OCR asset.
