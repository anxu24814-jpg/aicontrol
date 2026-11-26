// HTTP 凭据编辑页：管理页「添加凭据」/ 行菜单「编辑」/ 值缺失行「编辑」三入口 push，
// param = HttpCredEditParam{owner, credId}（credId '' = 新建）。名称 + 值 + 用途说明三字段
// 一处填——新建态值必填；编辑态值空起手，留空 = 保持原值（Asset 零触碰，纯元数据改）。
// 用途说明可选、上限 30 字，随 env_list 回执给助手看。形制照 PriceTemplateEditPage（标题栏
// 「保存」键官方 HDS 数组 + pop 带 result 触发管理页 onPop 重拉〔坑17〕；标题恒「编辑凭据」）。
// ★ 删除不进本页（决明拍板：保留行菜单）。
// ★ 明文红线（KeyStore 头注释同源）：值输入 @State 仅本页内存、保存即清，零日志零 toast
// 回显；编辑态不回填原明文（空起手——回显即驻留，违明文最小过手纪律）。
// ★ 改名语义（HttpCredentials 头注释同源）：名称可改（纯元数据覆盖写零 Asset 触碰）；编辑
// 态查重排除自身（credNameTakenExcept），值缓存失效在 editCredential 收口（名称是值缓存键）。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, CARD_SPACING, cardBg, cardDescColor,
  cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { BadgeTone, StatusBadge } from '../StatusBadge';
import { ReadonlyField } from '../ReadonlyField';
import { InfoCard } from '../InfoCard';
import { ROUTE_HTTP_CREDENTIAL_EDIT_PAGE } from '../../common/RouteNames';
import { getHttpCredentialsCfgJson } from '../../common/AppPreferencesHttp';
import { addCredential, credDescValid, credNameTaken, credNameTakenExcept, credNameValid,
  editCredential, HTTP_CRED_DESC_MAX_CHARS, HTTP_CRED_NAME_MAX_CHARS,
  HTTP_CRED_VALUE_MAX_CHARS, HttpCredCfg, HttpCredEntry, parseHttpCredCfg } from '../../common/providers/HttpCredentials';
import { loadHttpCredential } from '../../common/store/KeyStore';
import { nextMessageId } from '../../common/store/ChatDb';

export interface HttpCredEditParam {
  owner: string;
  credId: string;
}

// 标题栏保存键官方 HDS 数组（PriceTemplateEditPage 同款形制）
function credSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct HttpCredentialEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 归属命名空间 + 编辑对象 id（'' = 新建）
  private owner: string = '';
  private credId: string = '';
  @State private name: string = '';
  // 明文输入（保存成功即清——明文纪律；编辑态恒空起手不回填原值）
  @State private value: string = '';
  @State private desc: string = '';
  // 编辑态值缺失（loadHttpCredential 判空——驱动卡头徽标；新建态恒 false）
  @State private missing: boolean = false;
  @State private saving: boolean = false;

  aboutToAppear(): void {
    // param 解析（owner 缺失 = 异常栈——入口唯一且必传）
    const params: Array<HttpCredEditParam> =
      this.pathStack.getParamByName(ROUTE_HTTP_CREDENTIAL_EDIT_PAGE) as Array<HttpCredEditParam>;
    const param: HttpCredEditParam | undefined =
      params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param.owner === '') {
      this.getUIContext().getPromptAction().showToast({ message: '参数缺失' });
      this.pathStack.pop();
      return;
    }
    this.owner = param.owner;
    this.credId = param.credId;
    if (param.credId === '') {
      return; // 新建：空表单
    }
    // 编辑态回填：元数据同步读偏好；值不回填（明文最小过手），缺失态异步判定
    const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
    const entries: HttpCredEntry[] = cfg.get(this.owner) ?? [];
    const entry: HttpCredEntry | undefined =
      entries.find((e: HttpCredEntry): boolean => e.id === this.credId);
    if (entry === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '凭据不存在或已删除' });
      this.pathStack.pop();
      return;
    }
    this.name = entry.name;
    this.desc = entry.desc;
    loadHttpCredential(this.owner, this.credId)
      .then((value: string): void => {
        if (this.departed) {
          return;
        }
        this.missing = value === '';
      })
      .catch((_e: Object): void => {
        if (this.departed) {
          return;
        }
        this.missing = true;
      });
  }

  // 值输入占位（新建必填 / 编辑留空保持）——缺失状态由卡头徽标 + 只读井承载，不靠占位文案
  //（占位会随输入被冲掉）
  private valuePlaceholder(): string {
    return this.credId === '' ? '密钥或令牌的值' : '留空保持原值';
  }

  // 保存（顺序即拦截序）：名称 → 查重（新建/编辑分路，编辑排除自身）→ 用途说明 → 新建值
  // 必填 → 落库（add/edit 统一收口缓存失效）→ pop 带 result（坑17）
  private save(): void {
    if (this.saving) {
      return;
    }
    const name: string = this.name.trim();
    if (name === '' || !credNameValid(name)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '名称不能为空，也不能包含花括号' });
      return;
    }
    const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
    if (this.credId === '') {
      if (credNameTaken(cfg, this.owner, name)) {
        this.getUIContext().getPromptAction()
          .showToast({ message: '这个名称已经存在。请换一个' });
        return;
      }
    } else if (credNameTakenExcept(cfg, this.owner, name, this.credId)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '这个名称已经存在。请换一个' });
      return;
    }
    const desc: string = this.desc.trim();
    if (!credDescValid(desc)) {
      this.getUIContext().getPromptAction()
        .showToast({ message: '用途说明最多 ' + HTTP_CRED_DESC_MAX_CHARS + ' 字' });
      return;
    }
    const value: string = this.value.trim();
    if (this.credId === '' && value === '') {
      this.getUIContext().getPromptAction().showToast({ message: '值不能为空' });
      return;
    }
    this.saving = true;
    const write: Promise<void> = this.credId === '' ?
      addCredential(this.owner, nextMessageId('cred'), name, desc, value) :
      editCredential(this.owner, this.credId, name, desc, value);
    write
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.value = ''; // 明文即弃（组件态零驻留）
        this.getUIContext().getPromptAction().showToast({ message: '已保存「' + name + '」' });
        this.pathStack.pop({ saved: true });
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

  // 字段标签（13fp 次要字色，贴在自己的框上方）
  @Builder
  FieldLabel(text: string, topGap: number) {
    Text(text)
      .fontSize(13)
      .fontColor(cardDescColor())
      .width('100%')
      .margin({ top: topGap })
  }

  // 引用写法：名称实时派生；空名给一句占位，不显示裸花括号
  private refName(): string {
    const trimmed: string = this.name.trim();
    return trimmed === '' ? '填写名称后显示引用写法' : '{{' + trimmed + '}}';
  }

  // 只读井已上收公共件 components/ReadonlyField.ets（形制与判据见该件头注释与规范 §4.17）

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 凭据卡（名称 / 值 / 用途说明三字段收成一张）──
        // ★ 卡头右上状态徽标：用 if/else 两个实例而非传变量——StatusBadge 入参是普通成员
        //（刷新责任在调用方），分支切换即重建实例才能拿到新档位（坑16 家族）
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('凭据')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
            if (this.credId !== '') {
              if (this.missing) {
                StatusBadge({ text: '值缺失', tone: BadgeTone.DANGER })
              } else {
                StatusBadge({ text: '已保存', tone: BadgeTone.SUCCESS })
              }
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          this.FieldLabel('名称', 0)
          TextInput({ placeholder: '例如 weather_key', text: this.name })
            .width('100%')
            .maxLength(HTTP_CRED_NAME_MAX_CHARS)
            .onChange((value: string): void => {
              this.name = value;
            })
          Text('名称在同一范围内唯一，助手在请求里用它引用。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          this.FieldLabel('值', 10)
          if (this.credId !== '') {
            ReadonlyField({ label: '当前值',
              value: this.missing ? '缺失，请填入新值' : '已加密保存，不回显', warn: this.missing })
          }
          TextInput({ placeholder: this.valuePlaceholder(), text: $$this.value })
            .type(InputType.Password)
            .showPasswordIcon(true)
            .width('100%')
            .maxLength(HTTP_CRED_VALUE_MAX_CHARS)
          Text(this.credId === '' ? '保存后即可在请求里引用。' : '留空则保持原值，填了就覆盖。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
          this.FieldLabel('用途说明', 10)
          TextInput({ placeholder: '例如 调用天气服务的密钥', text: this.desc })
            .width('100%')
            .maxLength(HTTP_CRED_DESC_MAX_CHARS)
            .onChange((value: string): void => {
              this.desc = value;
            })
          Text('给助手看的备注，可不填。助手查询凭据时会一并看到。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)

        // ── 安全说明（独立成条；走 InfoCard 单源件——条状提示件已拍板否决，同屏两种提示
        // 观感是规范红线）──
        InfoCard({ text: '值加密保存在本机，不会出现在聊天和日志里。' })

        // ── 引用方式卡：只读展示变量名，随名称输入实时变化；不参与保存、不接收点击 ──
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('引用方式')
              .fontSize(CARD_SECTION_TITLE_FONTSIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            StatusBadge({ text: '只读', tone: BadgeTone.WEAK })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          ReadonlyField({ icon: $r('sys.symbol.key'), value: this.refName() })
          Text('在请求模板或助手的 HTTP 工具里用这个名字引用。值不会写进模板。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
        .padding(16)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: '编辑凭据',
      menuHds: credSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content()
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
