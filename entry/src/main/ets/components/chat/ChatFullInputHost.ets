// 全屏输入半模态宿主域（自 ChatPage 域级拆出，onSend/onClose 编排体方法体原样搬迁）：全屏
// 输入面板（KimiFullInputSheet）的**装配与面板发送/关闭编排**——busy 守卫与投递收口（发送
// 入口改判落点在本件 onSend，届时直接改此处，ChatPage 零增行）。
// · 反碎片下限②申报（为何不能并入既有件）：KimiFullInputSheet 是被装配的面板本体（本件
//   装配它——并入即宿主与被宿主倒置）；ChatSheetCtrl 是九形态共享的开启写序与手势关闭路由
//   域，并入 = 单形态专属编排污染共享域；ChatPageContent 是内容区，域不合。
// · 四通道留页面（init/draft/cmd/live）：draft/cmd 是页面级命令通道（lifecycle 分享回写 /
//   branchCtrl 编辑分流 / visionConfirm 还草稿 / ChatInputBar @Watch 五域消费）；init/live
//   被 ChatSheetCtrl 开关路由读写（openInput 播种、手势关闭确认现读）——本件经值参与上行
//   回调对接，不持镜像（单一真相在页面 @State）；状态写回（fullInputLive 置空 / 草稿回写）
//   经 onDelivered/onPanelClose 两枚宿主回接闭包落页面（refs 闭包形制，照 ChatSheetCtrl）。
import { KimiFullInputSheet } from './KimiFullInputSheet';

@Component
export struct ChatFullInputHost {
  // 打开时胶囊输入框文本快照（值参自页面 fullInputInit——面板每次打开重建实例，创建后不变）
  initial: string = '';
  // 胶囊已选附件数（发送可用判定的附件侧输入——面板内无附件条，见 KimiFullInputSheet 头注释）
  attachCount: number = 0;
  // 底部系统导航条高（透传面板底部留白兜底——模型面板 bottomInset 先例）
  bottomInset: number = 0;
  // 实时草稿上行（父持 live——关闭即回写胶囊；任何关闭路径不丢未发送编辑）
  onDraftChange: (text: string) => void = (_text: string): void => {
  };
  // 长文本粘贴/上屏转附件上行（判定与收口判据单源在 AttachmentPickCtrl，本件零逻辑桥接）
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false); // 缺省与 KimiFullInputSheet 同款：退化为不转附件原文留框（P0-1 禁静默失败）
    };
  // 投递能力（= 页面 sendWithAttachments；true = 已投递或已进入确认流程，false = 守卫拦下）
  deliver: (text: string) => boolean = (_text: string): boolean => false;
  // 投递成功收尾（页面：清胶囊草稿命令 + 清 fullInputLive + 关面板——状态真相在页面故上行）
  onDelivered: () => void = (): void => {
  };
  // 保存/xmark 关闭（页面：live 回写胶囊 + 关面板——live 真相在页面故上行）
  onPanelClose: () => void = (): void => {
  };

  build() {
    KimiFullInputSheet({
      initial: this.initial,
      attachCount: this.attachCount,
      bottomInset: this.bottomInset,
      onDraftChange: (text: string): void => {
        this.onDraftChange(text);
      },
      // 长文本粘贴转附件（面板侧）：判定与收口判据与胶囊同源（单源在 AttachmentPickCtrl），
      // 本件只桥接上行——catch 兜底 = addPastedText 契约「永不 reject」万一破了也让收口跑到
      onPasteLongText: (text: string, settle: (converted: boolean) => void): void => {
        this.onPasteLongText(text, settle);
      },
      onSend: (text: string): void => {
        // 面板发送 = 面板文本 + 胶囊当前已选附件；发送后胶囊经命令清空。
        // ★ 发送入口改判（排队插队）：原 busy 前置守卫（自检 P1「静默吞掉」防线）随「运行中
        // 不插话」红线被排队功能取代整段退役——busy 时交 send() 守卫自动入队并返回 true
        //（入队也算投递，面板按已投递收尾）；带附件 busy 由入口层拒绝入队 + toast 并返回
        // false，此时面板与文本原样（既有收尾契约不变）。
        // 清草稿与关面板按返回值收尾——未投递（解析阻断 / 无服务商等守卫拦下）时面板与
        // 文本原样留着（面板文本是面板自身 @State，不关就不丢）
        if (!this.deliver(text)) {
          return;
        }
        this.onDelivered();
      },
      onClose: (): void => {
        // 「保存」/xmark：关闭即回写胶囊（live 实时上行，未发送编辑不丢）——回写与
        // 关面板在页面（live 真相在页面 @State）
        this.onPanelClose();
      }
    })
  }
}
