// 技能库管理页（2026-09-13 技能层笔 1 新建，方案-技能层-20260913 §2.5；设置页行卡 push +
// 助手技能页「管理技能库」入口 push——自包 PageShell 壳，照 PromptLibraryPage 清单形制）：
// · 技能清单：行 = 图标 + 名称 + 触发描述副标题；点行卡进技能编辑页；行卡右侧四点键 →
//   官方菜单（编辑 / 导出 SKILL.md / 导出技能包 / 删除）；
// · 两导出（2026-09-13 入口调整笔自技能编辑页操作卡移入）：**入口变、底层链不变**——单文件
//   走 SkillPack.exportSkillMd、整包走 exportSkillPack，回报都在分享面板选「另存为文件」。
//   导出对象 = 库里已保存的行（菜单挂在已存在的行上），故没有编辑页那份「表单现值 vs 库里值」
//   的分岔，也无需「先落库再打包」；行菜单锚点见 SkillRowMenu。
// · 标题栏两键：「＋新建」+「导入技能」（笔 2 加——导入的入口在家 = 库页，技能编辑页只
//   负责单件编辑与附件维护）。**不做多选批量删除**——技能库上限 50 件且删除要连带清各助手启用
//   列，批量无收益而误删代价高；PromptLibraryPage 的多选是为提示词库的批量清理场景设的；
//   ★ 2026-09-14 格式兼容笔：入口由「导入技能包」改「导入技能」= **单入口双格式**——同一键
//   按扩展名分派，zip 走技能包链、.md 走单文件链（不再新增第三键：标题栏双键是既有形制，
//   为两格式各加一键的收益不抵挤压成本）；
//   ★ 2026-09-15 两键合并为双热区胶囊（决明「技能库右上角也合并」，同记忆页/消息页方案）：
//   HDS 路径改官方标题栏自定义区覆盖层（stackBuilder）= 共用件 components/TitleBarKeys.ets
//   的 TitleBarActionCapsule〔＋|导入〕——官方菜单数组每项只渲染独立圆钮、画不出合并形态；
//   覆盖层只占标题栏右侧，主标题「技能库」经 PageShell.keepStackTitle 保留；回退路径仍是
//   官方两键数组。键位与动作一字未改（＋ 在左、导入在右），skillLibMenuHds 随本笔整支删除。
// · 删除确认：ConfirmDialog（成员位——坑7），文案含「已启用的助手将同步移除该技能」
//   （删技能会联动清各助手 skills 列，这条后果必须让用户事先看见）；
// · 刷新链：@StorageProp(SKILL_LIST_TICK_KEY) @Watch → reload（SKILL_LIST_TICK_KEY 写点 =
//   SkillDb 增删改函数收口，编辑页保存/库页删除都经它；MemoryPage 同款姿势——本页在栈中
//   不显示时也能收到 tick，pop 回来即是新列表）；
// · ★ 2026-09-13 会话中创建技能笔：内置行（source='builtin'，seed 元技能「创建技能」）——
//   名称行尾带「内置」小字标（13fp 官方强调色，助手卡「当前」标同形制）；四点菜单隐藏
//   「删除」项（SkillRowMenu 判 source；DB deleteSkill 首行守卫兜底）。内置行可看可启用
//   可导出、随备份走，仅禁删禁改；
// · 库满拦截：本页「＋新建」键 push 前查 countSkills，达上限 toast（SkillDb 侧还有第二道
//   throw 兜底——两处判定不是漂移面而是「UI 就近提示 + 域层硬约束」的分工）。
// · ★ 菜单宿主 init 恒传**空行对象**（emptySkill，禁 null 断言）：ComponentContent 创建时
//   即固化 UI 树，SkillRowMenuBuilder 构建期要读 params.item.source——null 断言会在首建即
//   读 null 属性抛 TypeError（进页闪退，2026-09-13 真机实锤，勿改回）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { PageShell } from '../../common/PageShell';
import { ROUTE_SKILL_EDIT_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_SKILL_LIBRARY } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import {
  countSkills, deleteSkill, insertSkill, insertSkillFile, querySkillFiles, querySkills,
  skillIconOr, SKILL_FULL_TIP, SKILL_LIST_TICK_KEY, SkillFileRow, SkillRow
} from '../../common/store/SkillDb';
import { composeBatchImportPreview, composeImportPreview, SkillBatchPreviewItem,
  SkillImportPreviewInput, SKILL_FILE_MAX_COUNT,
  SKILL_ICON_DEFAULT, skillFileExt, SKILL_TOTAL_MAX } from '../../common/SkillText';
import { exportSkillMd, exportSkillPack, pickedFileName, readSkillMdFile, readSkillPack,
  SkillPackFilePayload, SkillPackPayload, SkillPackReadResult } from '../../common/SkillPack';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { SKILL_ROW_MENU_ID_PREFIX, SkillRowMenuCallbacks, SkillRowMenuHost } from './SkillRowMenu';
import { skillIconResource } from './SkillIcons';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 标题栏两键（★ 2026-09-15 合并胶囊笔：HDS 路径 = 官方标题栏自定义区覆盖层里的一枚双热区
// 胶囊〔＋新建 | 导入〕，官方菜单数组本页传 null；回退路径无 stackBuilder 机制，仍是官方
// 两键数组——数组成员序 = 显示序 =【＋新建】在左、【导入】在右）。键位与动作一字未改
// （笔 2 加导入：方案 §3.3 导入的入口在家 = 库页，技能编辑页只负责单件编辑/导出；2026-09-14
// 格式兼容笔起该键收 zip 与 .md 两种文件，文案随之改「导入技能」）
function skillLibMenuNav(onNew: () => void, onImport: () => void): NavigationMenuItem[] {
  return [{
    value: '新建技能',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNew
  } as NavigationMenuItem, {
    value: '导入技能',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
    action: onImport
  } as NavigationMenuItem];
}

@Component
export struct SkillLibraryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private skills: SkillRow[] = [];
  @State private deleteTarget: SkillRow | null = null;
  // 列表刷新广播（递增 tick——写点在 SkillDb 增删改收口处；@Watch 对同值不触发故用递增）
  @StorageProp(SKILL_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 菜单材质档位（@StorageProp 自订阅——AppMenuHost 弹出时解析；PromptLibraryPage 同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 菜单节点宿主（官方 openMenu：init 一次 / 弹出前重建 / dispose 成对——见域件注释）
  private rowMenu: SkillRowMenuHost = new SkillRowMenuHost();
  // 待导入载荷（审阅弹窗期间持有；导入或取消后清空——弹窗是异步确认，载荷必须跨帧存活）
  private pendingImport: SkillPackReadResult | null = null;
  // 导入审阅弹窗控制器（★ 按需构造赋成员位——坑7 姿态；message 依载荷内容动态拼，
  // 故不能预建：ProviderPage 口令弹窗同款姿势）
  private importCtrl: CustomDialogController | null = null;
  // 删除确认弹窗（坑7：必须组件成员位构造——普通类 open() 静默无效真机实锤）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除技能',
      message: '删除后无法恢复。已启用的助手将同步移除该技能。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.rowMenu.init(this.getUIContext(), this.rowCallbacks(this.emptySkill()));
    this.reload();
  }

  aboutToDisappear(): void {
    this.rowMenu.dispose();
  }

  private onListTick(): void {
    this.reload();
  }

  // 新建：达上限即就地拦截（P0-1 明确提示，不静默失败；不 push 空编辑页让用户白填一遍）
  private onNewSkill(): void {
    countSkills()
      .then((count: number): void => {
        if (count >= SKILL_TOTAL_MAX) {
          this.getUIContext().getPromptAction().showToast({ message: SKILL_FULL_TIP });
          return;
        }
        this.editSkill('');
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '技能库读取失败：' + (e as Error).message });
      });
  }

  // 空行对象（init 建菜单节点的占位载荷——**禁传 null 断言**：ComponentContent 创建时即固化
  // UI 树（AppMenuHost 头注释），SkillRowMenuBuilder 构建期要读 params.item.source（内置行
  // 隐藏删除项）；传 null 会在首建时读 null 属性抛 TypeError = 进页即闪退。2026-09-13 真机
  // 报障实锤：设置页「技能库」与助手技能页「管理技能库」两入口同因——会话中创建技能笔给
  // 菜单 builder 加了构建期 item 读取，而宿主 init 传的是 null，两头组合才暴露。形态照
  // ChatSessionList.emptyItem / ProviderPage.emptyRow 先例——打开菜单前 rebuild 会换真实行）
  private emptySkill(): SkillRow {
    return { id: '', name: '', description: '', icon: '', content: '', source: '',
      createdAt: 0, updatedAt: 0, sortOrder: 0 };
  }

  private rowCallbacks(row: SkillRow): SkillRowMenuCallbacks {
    return {
      item: row,
      onEdit: (item: SkillRow): void => {
        this.editSkill(item.id);
      },
      onExportMd: (item: SkillRow): void => {
        this.exportRowMd(item);
      },
      onExportPack: (item: SkillRow): void => {
        this.exportRowPack(item);
      },
      onDelete: (item: SkillRow): void => {
        this.confirmDelete(item);
      }
    };
  }

  private reload(): void {
    querySkills()
      .then((rows: SkillRow[]): void => {
        this.skills = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '技能读取失败：' + (e as Error).message });
      });
  }

  // 进编辑页（空参 = 新建；本页不进多选态，无新建语义冲突的守卫需求）
  private editSkill(skillId: string): void {
    this.pathStack.pushPathByName(ROUTE_SKILL_EDIT_PAGE, skillId);
  }

  // 导出 SKILL.md（入口 2026-09-13 自技能编辑页操作卡移入行卡菜单；底层链不动 =
  // serializeSkillMd → 沙箱暂存 → 官方分享面板，面板内自带「另存为文件」）。取库里已保存的
  // 行——不再有「导出取当前表单值」这层语义；失败 toast 中文原因不静默（P0-1）
  private async exportRowMd(row: SkillRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const path: string = exportSkillMd(ctx, row);
      await this.shareFile(path, ctx);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 导出技能包（同上迁入）：连同附件一起打成 zip → 分享。菜单挂在已落库的行上，导出内容本就
  // 是库里值，故不需要编辑页那份「先落库再打包」（那是为防「包里是旧正文」的静默落差）
  private async exportRowPack(row: SkillRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const files: SkillFileRow[] = await querySkillFiles(row.id);
      const path: string = await exportSkillPack(ctx, row, files);
      await this.shareFile(path, ctx);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 分享面板（两导出共用；重复两次的逻辑提子程序 P2-4——utd 与 label 照 LogPage/ProviderShare
  // 既有链的 FILE 形态）
  private async shareFile(path: string, ctx: common.Context): Promise<void> {
    const fileName: string = path.substring(path.lastIndexOf('/') + 1);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      uri: fileUri.getUriFromPath(path),
      title: fileName,
      label: 'FILE'
    };
    const controller: systemShare.ShareController =
      new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(ctx as common.UIAbilityContext, {});
  }

  // 导入技能（方案 §3.3 全链 + 2026-09-14 格式兼容笔单入口双格式）：库满先拦 → 选择器取
  // 技能包 zip 或单个 SKILL.md → 解析（各带容错三态）→ 重名拒 → **原文审阅弹窗**（技能正文
  // 是指令注入面，必须用户过目后才入库）→ 落库 + 附件逐个入库（单件失败不炸整批，计数呈报）。
  // 任何一步失败都 toast 中文原因，不静默（P0-1）
  private async importPack(): Promise<void> {
    try {
      const count: number = await countSkills();
      if (count >= SKILL_TOTAL_MAX) {
        this.getUIContext().getPromptAction().showToast({ message: SKILL_FULL_TIP });
        return;
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '技能库读取失败：' + (e as Error).message });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 导入 = 单件动作（后续只取 uris[0]）：不设 maxSelectNumber 时系统面板默认多选
      //（d.ts 上限 500），多选件除首个外静默丢失——DataSyncPage.doImport 同款守卫
      //（第 2 轮 P2-2 同族第 4 处，全面自检第 3 轮笔 2 收口）
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      // 后缀过滤（d.ts 形制：元素内 '|' 左描述右后缀、后缀可逗号分列、数组总长 ≤ 100 字符）。
      // ★ 「该参数仅部分设备能力可用」（d.ts 原文），**不得当唯一防线**——真正的硬闸是下方
      // 按扩展名分派 + 不支持格式的中文兜底提示
      selectOpts.fileSuffixFilters = ['技能文件|.zip,.md'];
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const read: SkillPackReadResult | null = await this.readPickedEntry(ctx, uris[0]);
      if (read === null) {
        return; // 扩展名不在支持面（readPickedEntry 已给中文提示）
      }
      if (!read.ok) {
        this.getUIContext().getPromptAction().showToast({ message: read.error });
        return;
      }
      // 单件形态（技能包恒一件 / 单文件）走原链逐字保留：重名即拒整批，文案不随多技能包笔改动
      if (read.payloads.length === 1 && read.skipped.length === 0) {
        const payload: SkillPackPayload = read.payloads[0];
        // 重名拒（方案 §3.3 倾向：重名拒 + 提示，不做自动改名——自动改名会让用户在库里
        // 看到两个「长得像但名字不同」的技能，比当场拒绝更难排查）
        const existing: SkillRow[] = await querySkills();
        const dup: SkillRow | undefined =
          existing.find((row: SkillRow): boolean => row.name === payload.name);
        if (dup !== undefined) {
          this.getUIContext().getPromptAction().showToast({
            message: '技能库里已有名为「' + payload.name + '」的技能，请先改名或删除后再导入'
          });
          return;
        }
        this.confirmImport(read);
        return;
      }
      await this.importMulti(read);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 多件链（2026-09-22 多技能包笔）：逐件过重名与库容，导不了的（重名 / 包内解析失败）并入
  // 跳过清单如实呈报——「能导的先导、导不了的逐条说清」，与单件链的「重名即拒整批」是件数量
  // 的自然分派（单件时逐件等同于整批）。全部不可导入 = 中止并 toast 首条原因；库容不足 =
  // 中止并说清要腾多少位（不做「先塞满再丢尾」——静默丢件是红线）
  private async importMulti(read: SkillPackReadResult): Promise<void> {
    try {
      const existing: SkillRow[] = await querySkills();
      const names: string[] = [];
      for (const row of existing) {
        names.push(row.name);
      }
      const importable: SkillPackPayload[] = [];
      const skipped: string[] = [];
      for (const item of read.skipped) {
        skipped.push(item);
      }
      for (const payload of read.payloads) {
        if (names.includes(payload.name)) {
          skipped.push('技能库里已有名为「' + payload.name + '」的技能，请先改名或删除后再导入');
        } else {
          importable.push(payload);
        }
      }
      if (importable.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: skipped[0] });
        return;
      }
      if (existing.length + importable.length > SKILL_TOTAL_MAX) {
        this.getUIContext().getPromptAction().showToast({
          message: '技能库最多 ' + SKILL_TOTAL_MAX + ' 件，已有 ' + existing.length +
            ' 件，本次要导入 ' + importable.length + ' 件。请先到技能库删掉部分技能再导入'
        });
        return;
      }
      this.confirmImport({ ok: true, payloads: importable, skipped: skipped, error: '' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 按扩展名分派（2026-09-14 格式兼容笔「单入口双格式」；skillFileExt 小写归一，见 SkillText）：
  // · .md       → 单文件链 readSkillMdFile（无附件；自家 exportSkillMd 产物由此可导回来）
  // · .zip / '' → 原技能包链 readSkillPack（'' = 极端的 URI 取不到名形态，维持既有行为不倒退）
  // · 其余      → 中文兜底提示后返回 null（调用方据此静默收尾，不再进任何解析链）
  private async readPickedEntry(ctx: common.Context,
    uri: string): Promise<SkillPackReadResult | null> {
    const ext: string = skillFileExt(pickedFileName(uri));
    if (ext === 'md') {
      return readSkillMdFile(uri);
    }
    if (ext === '' || ext === 'zip') {
      return await readSkillPack(ctx, uri);
    }
    this.getUIContext().getPromptAction().showToast({
      message: '只能导入技能包 .zip 或单个 .md 技能文件'
    });
    return null;
  }

  // 审阅确认（ConfirmDialog 成员位弹窗复用——message 载名称/触发描述/正文摘录/附件清单/
  // 跳过项，全是用户判断「要不要这个技能」所需的最小信息；确认键走常规语气 NORMAL）。
  // 取消键清载荷（2026-09-13 全面自检轮补：原「导入或取消后清空」的注释只有确认侧成立，
  // 取消/遮罩关闭都会把载荷压到下次导入才被覆盖——取消键由此处显式回收；
  // 遮罩关闭路径无回调，仍由下次导入覆盖，单份载荷有界）
  private confirmImport(read: SkillPackReadResult): void {
    this.pendingImport = read;
    this.importCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '导入技能',
        message: this.importPreviewText(read),
        confirmLabel: '导入',
        confirmTone: ConfirmDialogTone.NORMAL,
        onConfirm: (): void => {
          this.doImport();
        },
        onCancel: (): void => {
          this.pendingImport = null;
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.importCtrl.open();
  }

  // 预览文案：组装逻辑在纯函数层 composeImportPreview（★ 真机预演反推补——弹窗 message 是
  // 无上限 Text，十件长名附件能把「导入/取消」顶出屏；纯函数层做分段截断 + 条数封顶，最坏
  // 形态有结构上界，且安全提示句恒在末尾。纯函数放 SkillText 也让它可被断言实跑覆盖）
  // ★ 2026-09-22 多技能包笔：单件形态走原函数逐字不变；多件（或带跳过项）走批量预览
  // composeBatchImportPreview——只列件名与附件数，各件的附件级警告加技能名前缀后并进跳过清单
  // （多件形态下逐件展开正文会立刻顶爆上界；完整正文在导入后的技能库编辑页里逐件可看）
  private importPreviewText(read: SkillPackReadResult): string {
    if (read.payloads.length === 1 && read.skipped.length === 0) {
      const payload: SkillPackPayload = read.payloads[0];
      const names: string[] = [];
      for (const file of payload.files) {
        names.push(file.name);
      }
      const input: SkillImportPreviewInput = {
        name: payload.name,
        description: payload.description,
        content: payload.content,
        fileNames: names,
        warnings: payload.warnings
      };
      return composeImportPreview(input);
    }
    const items: SkillBatchPreviewItem[] = [];
    const skipped: string[] = [];
    for (const payload of read.payloads) {
      items.push({ name: payload.name, fileCount: payload.files.length });
      for (const warning of payload.warnings) {
        skipped.push('『' + payload.name + '』' + warning);
      }
    }
    for (const item of read.skipped) {
      skipped.push(item);
    }
    return composeBatchImportPreview({ items: items, skipped: skipped });
  }

  // 落库（技能行 + 附件逐件）：件数上限已在读取侧封顶（SkillPack 收集处，超限项进审阅警告），
  // 此处 `i < SKILL_FILE_MAX_COUNT` 是页面侧的第二道界（读取侧若放宽也越不过库约束）；
  // 单件写入失败（重名/超限）计失败数——不炸整批，导入结果一句话说清
  // ★ 2026-09-22 多技能包笔：多件时逐件**串行**落库（并发建行会让库容判定与实际写入之间出现
  // 时间窗；件数上限 50 且写入是本地 DB，串行代价可忽略），逐件走同一条 importOne，末尾汇总一次
  private doImport(): void {
    const pending: SkillPackReadResult | null = this.pendingImport;
    this.pendingImport = null;
    if (pending === null) {
      return;
    }
    this.importOne(pending, 0, 0, 0);
  }

  // 单件落库（附件并发写、失败计数；建行失败 = 该件跳过、不炸整批）→ 递归推进下一件
  private importOne(pending: SkillPackReadResult, index: number, done: number,
    fileFailed: number): void {
    if (index >= pending.payloads.length) {
      this.reportImport(pending, done, fileFailed);
      return;
    }
    const payload: SkillPackPayload = pending.payloads[index];
    insertSkill({ name: payload.name, description: payload.description,
      icon: SKILL_ICON_DEFAULT, content: payload.content })
      .then((row: SkillRow): Promise<number> => {
        const files: SkillPackFilePayload[] = payload.files;
        let failed: number = 0;
        const tasks: Promise<void>[] = [];
        for (let i: number = 0; i < files.length && i < SKILL_FILE_MAX_COUNT; i++) {
          tasks.push(insertSkillFile(row.id, files[i].name, files[i].content)
            .then((): void => {
            })
            .catch((): void => {
              failed++;
            }));
        }
        return Promise.all(tasks).then((): number => failed);
      })
      .then((failed: number): void => {
        this.importOne(pending, index + 1, done + 1, fileFailed + failed);
      })
      .catch((): void => {
        this.importOne(pending, index + 1, done, fileFailed);
      });
  }

  // 导入结果一句话（单件成功的原文案逐字不变；多件 = 已导入件数 / 未导入件数 / 附件失败数三项，
  // 顿号分句只列非零项）
  private reportImport(pending: SkillPackReadResult, done: number, fileFailed: number): void {
    const parts: string[] = [];
    if (pending.payloads.length === 1 && pending.skipped.length === 0) {
      const name: string = pending.payloads[0].name;
      parts.push(done > 0 ? '已导入「' + name + '」' : '「' + name + '」未导入');
    } else {
      const missed: number = pending.payloads.length - done + pending.skipped.length;
      if (done > 0) {
        parts.push('已导入 ' + done + ' 件技能');
      }
      if (missed > 0) {
        parts.push(missed + ' 件未导入');
      }
    }
    if (fileFailed > 0) {
      parts.push(fileFailed + ' 个附件未导入');
    }
    this.getUIContext().getPromptAction().showToast({ message: parts.join('，') });
    this.reload();
  }

  // 行卡四点键菜单（编辑 / 删除）
  private openRowMenu(row: SkillRow): void {
    this.rowMenu.open(this.getUIContext(), this.rowCallbacks(row), this.immersiveLevel);
  }

  private confirmDelete(row: SkillRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  private doDelete(): void {
    const target: SkillRow | null = this.deleteTarget;
    if (target === null) {
      return;
    }
    this.deleteTarget = null;
    // 删行 + 联动清各助手 skills 列 + 广播（三件事都在 SkillDb.deleteSkill 内一个事务里；
    // 本页不重复广播——单一写点原则）
    deleteSkill(target.id)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 行卡（点卡进编辑 + 右侧四点键菜单；图标 = 技能自带 sys.symbol 名，越界值走默认符号）
  @Builder
  SkillCard(row: SkillRow) {
    Button() {
      Row({ space: 10 }) {
        SymbolGlyph(skillIconResource(skillIconOr(row.icon)))
          .fontSize(20)
          .fontColor([cardTitleColor()])
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(row.name !== '' ? row.name : '未命名技能')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              // 名行单行收敛（名上限 64 字——不收敛时行卡随名称长短高矮不一，同族行卡
              // MemoryRowCard / TemplateRow 同款；「内置」标其后，属同行尾随标记不占截断预算）
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            // 内置行「内置」小字标（助手卡「当前」标同形制；不占 maxLines 名行的截断预算）
            if (row.source === 'builtin') {
              Text('内置')
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(row.description !== '' ? row.description : '未填写触发描述，模型较难自动命中')
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .id(SKILL_ROW_MENU_ID_PREFIX + row.id)
        .onClick((): void => {
          this.openRowMenu(row);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.editSkill(row.id);
    })
  }

  // 标题栏覆盖层（HDS 路径：右上角合并胶囊〔＋新建 | 导入〕，同消息页/记忆页方案）——
  // 组件内 @Builder 挂载是硬约束（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图
  // 上下文，启动即闪退；先例 = ChatPage.TitleBarContent / MemoryPage.TitleBarKeys）；键件与
  // 几何/光感双态走共用件 components/TitleBarKeys.ets，本页只注入两动作
  @Builder
  TitleBarContent() {
    Row() {
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建技能',
        rightIcon: $r('sys.symbol.arrow_down_to_line'),
        rightLabel: '导入技能',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onNewSkill();
        },
        onRightTap: (): void => {
          this.importPack();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    // 命中透传（二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住返回键，
    // 2026-09-11 记忆页真机实锤；一级页页签覆盖层无返回键故不设）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.skills.length === 0) {
          // 空态行内提示行（13fp cardDescColor + CARD_PANEL_WIDTH 无卡底——2026-09-12 UI
          // 同形异构归一笔统一形态，PromptLibraryPage/MemoryPage 同款）
          Text('暂无技能。点右上角的「＋」新建，再到助手编辑页的技能分区里启用。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          // ★ 2026-09-13 全面自检轮（坑16 家族）：行键原为 id 单成分——在编辑页改技能名/图标/
          // 描述后返回本页，id 不变 → 键不变 → ForEach 只 diff 不重建行 → 卡片上显示的还是旧值
          //（「重赋数组新引用对同 key 的行无效」是档案里成文的实锤口径）。按同族先例补齐：
          // 行上屏的内容有哪几项，键就得含哪几项（先例 = 附件行键含件名、MemoryRowCard 外层
          // 签名键）。删除时键消失照旧移除，无需额外处理
          ForEach(this.skills, (row: SkillRow) => {
            this.SkillCard(row)
          }, (row: SkillRow): string => row.id + '|' + row.name + '|' + row.description + '|' +
            row.icon)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: SETTING_TITLE_SKILL_LIBRARY,
      // 标题栏两键（★ 2026-09-15 合并胶囊笔）：HDS 路径 = 官方标题栏自定义区覆盖层合并胶囊
      // 〔＋新建 | 导入〕（menuHds 传 null，键件与几何走共用件 TitleBarKeys；keepStackTitle
      // = true 保住主标题「技能库」，否则覆盖层会把标题置空）；回退路径无 stackBuilder
      // 机制，仍是官方菜单数组两键（menuNav）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      menuNav: skillLibMenuNav((): void => {
        this.onNewSkill();
      }, (): void => {
        this.importPack();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
