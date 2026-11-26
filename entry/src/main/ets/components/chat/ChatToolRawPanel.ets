import { cardDescColor } from '../../common/Theme';
import { copyTextToClipboard } from '../../common/Clipboard';
import { ChatMessage } from './ChatMessageCompose';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY,
  PREF_FONT_LIB_KEY, bodyFontFamily, codeFontFamily } from '../../common/ChatFont';

interface DisplayText {
  text: string;
  mono: boolean;
}

export function isFencedCodeBlock(raw: string): boolean {
  const trimmed: string = raw.trim();
  return trimmed.length > 6 && trimmed.startsWith('```') && trimmed.endsWith('```');
}

export function formatDisplayText(raw: string): DisplayText {
  if (raw === '') {
    return { text: '', mono: false };
  }
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    if (typeof parsed === 'object' && parsed !== null) {
      return { text: JSON.stringify(parsed, null, 2), mono: true };
    }
  } catch (e) {
    // 非 JSON 原样显示，不把普通文本误判为代码。
  }
  return { text: raw, mono: isFencedCodeBlock(raw) };
}

export function selectedToolRawTab(input: string, output: string, choice: string): string {
  if (choice === 'input' && input !== '') {
    return 'input';
  }
  if (choice === 'output' && output !== '') {
    return 'output';
  }
  return output !== '' ? 'output' : (input !== '' ? 'input' : '');
}

@Component
export struct ChatToolRawPanel {
  @ObjectLink msg: ChatMessage;
  // 消息字体三键 @StorageProp 自订阅：工具调用原文属消息内容全跟随——mono 分支（JSON/代码类
  // 原文）走代码字体，非 mono 分支走正文字体
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_CODE_KEY) fontCodeValue: string = FONT_CODE_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  private formattedRaw: string = '';
  private formatted: DisplayText = { text: '', mono: false };

  // 正文/代码家族串（家族串推导单源 = ChatFont 纯函数，禁本处拼串）
  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  private resolveCodeFamily(): string {
    return codeFontFamily(this.fontCodeValue, this.fontLibJson);
  }

  private input(): string {
    return this.msg.toolInputJson || this.msg.toolInputText || '';
  }

  private output(): string {
    return this.msg.toolOutputJson || this.msg.toolDisplayText || '';
  }

  private selected(): string {
    return selectedToolRawTab(this.input(), this.output(), this.msg.toolRawTab ?? '');
  }

  private raw(): string {
    return this.selected() === 'output' ? this.output() : this.input();
  }

  private display(): DisplayText {
    const raw: string = this.raw();
    if (raw !== this.formattedRaw) {
      this.formatted = formatDisplayText(raw);
      this.formattedRaw = raw;
    }
    return this.formatted;
  }

  private copyRaw(): void {
    const raw: string = this.raw();
    if (raw === '') {
      return;
    }
    try {
      copyTextToClipboard(this.getUIContext(), raw,
        this.selected() === 'output' ? '已复制输出' : '已复制输入');
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' });
    }
  }

  @Builder
  TabChoice(label: string, value: string) {
    Button(label)
      .fontFamily(this.resolveBodyFamily())
      .buttonStyle(this.selected() === value ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL)
      .controlSize(ControlSize.SMALL)
      .accessibilitySelected(this.selected() === value)
      .onClick((): void => {
        this.msg.toolRawTab = value;
      })
  }

  build() {
    if (this.selected() !== '') {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          if (this.input() !== '') {
            this.TabChoice('输入', 'input')
          }
          if (this.output() !== '') {
            this.TabChoice('输出', 'output')
          }
          Blank()
          Button() {
            SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .controlSize(ControlSize.SMALL)
          .width(40)
          .height(40)
          .accessibilityText(this.selected() === 'output' ? '复制输出' : '复制输入')
          .onClick((): void => {
            this.copyRaw();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(this.display().text)
          .fontSize(11)
          .fontColor(cardDescColor())
          .lineHeight(16)
          .fontFamily(this.display().mono ? this.resolveCodeFamily() : this.resolveBodyFamily())
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
