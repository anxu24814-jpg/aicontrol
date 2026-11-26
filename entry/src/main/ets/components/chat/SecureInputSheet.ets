// 安全输入面板：密钥明文的**带外输入面**，两态——
// · 直写态（中转键 PROVIDER_SECURE_INPUT_TARGET_KEY 有目标）：AI 配置工具建好「待填目标」
//   后，保存即 savePoolKey 直存 Asset 目标条目（目标卡防钓鱼核对）。
// · 暂存态（无目标——常驻入口主路径）：保存写会话暂存单槽（KeyStore.setPendingKey，内存
//   态不触 Asset），配出由 AI 工具 assign_key 转运；**永不进对话文本与模型上下文**（面板
//   内容零进请求链；只进槽与 Asset）。
// 链路：直写写点 = ToolProviderAdmin 的 create / add_key；读点 = ChatInputBar（chip 恒显，
// 入口不依赖目标存在）+ 本面板（目标显示）；直写清点 = 保存成功 / assign_key 转运后置 ''；
// 暂存清点 = assign_key 成功 / 显示条 × 键 / 离开会话页（ChatInputBar aboutToDisappear）。
// 中转键内存键不 persistProp——重启即清；暂存槽同内存态，寿命 = 会话页（决明拍板「未配置
// 不保存，跟未发送附件一样」）。
// ★ 明文纪律：输入值零日志零回显（保存后清组件态）；错误文案不带明文；本文件不 import
//   任何请求组装件。保存守卫对齐 UI 重填链（ProviderKeysPanel.confirmRefill：trim 非空 +
//   savePoolKey 覆盖写 + 成败 toast；差异仅「成功后清中转键 + 关面板」）。
// 壳 = 规范-半模态全套：HdsNavigation MODAL + sheetTitleBarOptions（标题栏不出保存键——
// 保存动作在内容区自成）+ Scroll clip(false) + 缺省档位（内容少用低档）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { PROVIDER_SECURE_INPUT_TARGET_KEY, ProviderRow, queryProviders } from '../../common/store/ProviderDb';
import { ProviderKeyRow, queryProviderKeys } from '../../common/store/ProviderKeyDb';
import { savePoolKey, setPendingKey } from '../../common/store/KeyStore';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';

// 待填目标判定（纯函数——断言直跑）：JSON 解析成功且 providerId 非空才算有目标；空串 /
// 坏 JSON / 缺字段一律 false（不抛错）。chip 显隐的唯一判据（任务书 §4.2）
export function secureTargetHasGoal(raw: string): boolean {
  if (raw === '') {
    return false;
  }
  try {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const providerId: Object | undefined = parsed['providerId'];
    return typeof providerId === 'string' && providerId !== '';
  } catch (e) {
    return false;
  }
}

@Component
export struct SecureInputSheet {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图
  // 照常完成
  private departed: boolean = false;
  // 半模态标题栏材质随沉浸光感总档 + 内容区回退双态（保存键四件套）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 关闭上行（标题栏 xmark 与保存成功 / 目标失效共用——宿主 ChatInputBar 置 sheetShow=false）
  onClose: () => void = () => {
  };
  // 目标显示（aboutToAppear 解析中转键 + 查库定名；域外不改）
  @State private providerName: string = '';
  @State private baseUrl: string = '';
  @State private keyLabel: string = '';
  // 双态：false = 直写态（有中转键目标，保存落 Asset 目标条目）；true = 暂存态（无目标，
  // 保存写会话暂存单槽）。loadTarget 同步段定初值，查库失效降级置位
  @State private stashMode: boolean = false;
  // 明文输入（密码型；保存成功即清——明文纪律：值零日志零回显，只在 savePoolKey 参数位）
  @State private secret: string = '';
  @State private saving: boolean = false;
  private providerId: string = '';
  private keyId: string = '';

  aboutToAppear(): void {
    this.loadTarget();
  }

  // 目标解析：hasGoal 假（空串/坏 JSON/缺字段）= 暂存态静默——常驻入口主路径无目标可言，
  // 不报错不关面板；hasGoal 真但查库未命中（目标已删）或读库异常 = toast 一次降级暂存态
  //（P0-1 不静默，同时不挡用户暂存自己的密钥）
  private loadTarget(): void {
    const raw: string = AppStorage.get<string>(PROVIDER_SECURE_INPUT_TARGET_KEY) ?? '';
    if (!secureTargetHasGoal(raw)) {
      this.stashMode = true;
      return;
    }
    let providerId: string = '';
    let keyId: string = '';
    try {
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const rawP: Object | undefined = parsed['providerId'];
      const rawK: Object | undefined = parsed['keyId'];
      if (typeof rawP === 'string') {
        providerId = rawP;
      }
      if (typeof rawK === 'string') {
        keyId = rawK;
      }
    } catch (e) {
      this.stashMode = true; // 防御不可达（hasGoal 已核过解析）——降级不抛错
      return;
    }
    queryProviders()
      .then(async (rows: ProviderRow[]): Promise<void> => {
        if (this.departed) {
          return;
        }
        const provider: ProviderRow | undefined =
          rows.find((row: ProviderRow): boolean => row.id === providerId);
        if (provider === undefined) {
          this.degradeStash();
          return;
        }
        const keys: ProviderKeyRow[] = await queryProviderKeys(providerId);
        if (this.departed) {
          return;
        }
        const key: ProviderKeyRow | undefined =
          keys.find((row: ProviderKeyRow): boolean => row.id === keyId);
        if (key === undefined) {
          this.degradeStash();
          return;
        }
        this.providerId = providerId;
        this.keyId = keyId;
        this.providerName = provider.name;
        this.baseUrl = provider.baseUrl; // 域名可见——防钓鱼核对面（任务书 §4.3 目标卡）
        this.keyLabel = key.label;
      })
      .catch((): void => {
        this.degradeStash();
      });
  }

  // 目标失效降级（不关面板——常驻入口下用户点开面板多半是要存密钥，目标失效不该挡路）
  private degradeStash(): void {
    this.getUIContext().getPromptAction()
      .showToast({ message: '待填目标已失效，已切换为暂存' });
    this.stashMode = true;
  }

  // 保存（双态）：trim 非空守卫 → 分态落点。暂存态 = setPendingKey 覆盖写会话单槽（内存
  // 态不触 Asset——配出由 assign_key 转运）；直写态 = savePoolKey 覆盖写（UI 重填链同款）。
  // 成功双态同收尾：清明文 + toast + 关面板；失败 toast 留面板（P0-1 不静默）
  private save(): void {
    const value: string = this.secret.trim();
    if (value === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先输入密钥' });
      return;
    }
    if (this.saving) {
      return;
    }
    if (this.stashMode) {
      this.saving = true;
      setPendingKey(value);
      this.secret = ''; // 明文即弃（组件态零驻留——明文已入会话单槽）
      this.saving = false;
      this.getUIContext().getPromptAction()
        .showToast({ message: '已暂存，可在对话里让我配置到服务商' });
      this.onClose();
      return;
    }
    if (this.providerId === '') {
      return;
    }
    this.saving = true;
    savePoolKey(this.providerId, this.keyId, value)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.secret = ''; // 明文即弃（组件态零驻留）
        AppStorage.setOrCreate(PROVIDER_SECURE_INPUT_TARGET_KEY, '');
        this.getUIContext().getPromptAction()
          .showToast({ message: '已保存到「' + this.providerName + '」' });
        this.onClose();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction()
          .showToast({ message: '保存失败：' + (e as Error).message });
      })
      .finally((): void => {
        if (this.departed) {
          return;
        }
        this.saving = false;
      });
  }

  build() {
    HdsNavigation() {
      // 渐变模糊前提：滚动容器 clip(false)（规范 §1）；内容少不滚，clip 仍按规范挂
      Scroll() {
        // 内容三段 = 先说明后操作（宪法「功能设置卡布局次序」精神）：
        // ① 说明行（分态：直写 = 本机存储承诺；暂存 = 会话寿命语义）→ ② 目标卡（直写态防钓鱼
        // 核对 / 暂存态去向说明卡）→ ③ 密码输入 + 保存键（文案分态）
        Column({ space: 12 }) {
          Text(this.stashMode ?
            '密钥只暂存在本机本会话，不会发送给模型。配置到服务商后清出，离开会话未配置则丢弃。' :
            '此内容仅保存在本机，不会发送给模型。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
          if (this.stashMode) {
            // 暂存态去向说明卡：无写入目标可核对，卡体只讲「暂存之后怎么配」——形制照目标卡
            //（防钓鱼卡同族视觉节奏），零敏感信息
            Column({ space: 8 }) {
              Text('暂存新密钥')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.key'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.font_secondary')])
                Text('保存后可在对话里告诉我配到哪个服务商。')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .borderRadius(CARD_RADIUS)
            .backgroundColor(cardBg(this.appColorMode))
          } else {
          // 目标卡：服务商名 + Base URL 全文（域名可见 = 用户肉眼核对防钓鱼）+ 目标条目名
          Column({ space: 8 }) {
            Text(this.providerName)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.baseUrl)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.key'))
                .fontSize(14)
                .fontColor([$r('sys.color.font_secondary')])
              Text('填入条目「' + this.keyLabel + '」')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .borderRadius(CARD_RADIUS)
          .backgroundColor(cardBg(this.appColorMode))
          }
          // 密码输入 + 保存（一张卡内自成——保存动作在内容区，标题栏不出保存键）
          Column({ space: 12 }) {
            TextInput({ placeholder: '粘贴或输入密钥', text: $$this.secret })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .fontSize(15)
              .width('100%')
              .onChange((value: string): void => {
                this.secret = value;
              })
            // 「保存」= 主操作键官方形制（comp_background_emphasize 强调蓝 + font_on_primary
            // 恒白 + 原生按压——SystemPromptPage 底部保存键同款四件套）；文案分态 = 直写
            // 「保存」/ 暂存「暂存」
            Button(this.stashMode ? '暂存' : '保存')
              .width('100%')
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .enabled(!this.saving)
              .onClick((): void => {
                this.save();
              })
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .borderRadius(CARD_RADIUS)
          .backgroundColor(cardBg(this.appColorMode))
        }
        .width('100%')
        .padding({ top: 4, bottom: 32 })
        .alignItems(HorizontalAlign.Center)
      }
      .clip(false)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar(sheetTitleBarOptions('安全输入', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
