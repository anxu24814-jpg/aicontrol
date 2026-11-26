// 技能库管理页（设置页行卡 push 无参，唯一入口；自包 PageShell 壳）：
// · 技能清单：行 = 名称 + 触发描述副标题（★ 自定义图标已退役 2026-11-02——旧行首图标位撤除，
//   skills.icon 列墓碑化见 SkillDb 头注释）；点行卡进编辑页；行卡右侧四点键 → 官方菜单
//  （★ 拍板：「编辑 / 删除」两项退役——编辑 = 行卡点击、删除 = 行左滑确认链，菜单只余两导出）。
// · 两导出（自编辑页操作卡移入）：**入口变、底层链不变**——单文件 exportSkillMd、整包
//   exportSkillPack，回报都在分享面板选「另存为文件」。导出对象 = 库里已保存的行，无需「先落库
//   再打包」；行菜单锚点见 SkillRowMenu。
// · 标题栏两键：「＋新建」+「⋯更多」（导入技能收入菜单，与「多选」并列——导入**换位不换链**；
//   菜单域件 = SkillTitleMenu.ets，覆盖层只占标题栏右侧，主标题经 keepStackTitle 保留）。
// · 多选批量删除：入口 = 「更多」菜单「多选」项，形态照 PromptLibraryPage；★ 内置行
//  （source='builtin'）**不参与多选**：不渲染勾选圈、点行无动作、「全选」跳过——全选判据与
//   动作都吃**可选可见集**（visibleSkills 剔除内置）。
// · 删除确认：ConfirmDialog（成员位——坑7），文案含「已启用的助手将同步移除该技能」（删技能
//   联动清各助手 skills 列，后果必须事先可见）。
// · 刷新链：@StorageProp(SKILL_LIST_TICK_KEY) @Watch → reload（写点 = SkillDb 增删改收口；
//   本页在栈中不显示时也收 tick，pop 回来即新列表）。
// · ★ 内置行：名称行尾带「内置」标（实底胶囊 StatusBadge）；四点菜单隐藏「删除」项（DB
//  deleteSkill 首行守卫兜底）。可看可启用可导出、随备份走，仅禁删禁改。
// · 库满拦截：「＋新建」push 前查 countSkills，达上限 toast（SkillDb 侧 throw 是第二道兜底——
//  「UI 就近提示 + 域层硬约束」分工，非漂移面）。
// · ★ 菜单宿主 init 恒传**空行对象**（emptySkill，禁 null 断言）：ComponentContent 创建时即
//   固化 UI 树，builder 构建期读 params.item——null 断言首建即抛 TypeError（进页闪退，真机
//   实锤，勿改回）。
// · 长列表 = List + Repeat.virtualScroll（行渲染拆同文件 @ComponentV2 渲染件，规范 §4.6）；
//   键只写 id（整体替换后同 id 新对象靠 item 比对刷新）；让位 = offset 轨；0 行由壳侧 Scroll 兜底。
// · 搜索：常显搜索框，命中 = **名称 + 触发描述 + 正文**（口径与纯函数在 common/LibrarySearch）；
//   数据源 = 可见集 visibleSkills；0 行两态分派单源 emptyHintText。
// · 搜索框承载：框上移**标题栏下方带**（SearchTopBand.ets，REGULAR 恒光感；让位算式
//   searchBandContentTop 单源该件），框吸顶不随内容滚，无自锁面。
import { CARD_RADIUS } from '../../common/Theme';
import { UIUtils } from '@kit.ArkUI';
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
  SKILL_FULL_TIP, SKILL_LIST_TICK_KEY, SkillFileRow, SkillRow
} from '../../common/store/SkillDb';
import { composeBatchImportPreview, composeImportPreview, SkillBatchPreviewItem,
  SkillImportPreviewInput, SKILL_FILE_MAX_COUNT,
  skillFileExt, SKILL_TOTAL_MAX } from '../../common/SkillText';
import { exportSkillMd, exportSkillPack, pickedFileName, readSkillMdFile, readSkillPack,
  SkillPackFilePayload, SkillPackPayload, SkillPackReadResult } from '../../common/SkillPack';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
// 库页搜索过滤纯函数（零 import 叶子件；命中字段 = 名称 + 触发描述 + 正文，空词 = 全显）
import { filterSkillsByKeyword } from '../../common/LibrarySearch';
// 标题栏下方带搜索框承载件 + 内容顶让位算式
import { SearchTopBand, searchBandContentTop } from '../SearchTopBand';
import { SKILL_ROW_MENU_ID_PREFIX, SkillRowMenuCallbacks, SkillRowMenuHost } from './SkillRowMenu';
// 全站状态词徽标形制单源（「内置」标 = 实底胶囊）
import { StatusBadge } from '../StatusBadge';
// 多选批量条（共用件，图标三键形态）
import {
  isAllSelectedIn, nextSelectAllIds, SessionMultiselectActionBar
} from '../chat/SessionMultiselectBar';
// 行级左滑删除横滑层（键位 / SwipeGroup 互斥口径见该件头注释）
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
// 标题栏键与「更多」菜单域（导入键收入菜单 + 新增「多选」）
import {
  SkillMoreMenuAnchor, SkillTitleBarKeys, SkillTitleMenuCallbacks, SkillTitleMenuHost
} from './SkillTitleMenu';

@Component
export struct SkillLibraryPage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 全量技能（搜索过滤与库满判定的基；上限 50 件有界）
  @State private skills: SkillRow[] = [];
  // 搜索词与过滤后的可见行（列表数据源）；空词 = 全显
  @State private keyword: string = '';
  @State private visibleSkills: SkillRow[] = [];
  @State private deleteTarget: SkillRow | null = null;
  // 多选模式与选中集（选中 id 集合 @State 观察代理数组入 napi 坑6：批量删除传库前逐元素拷贝）
  @State private multiSelect: boolean = false;
  @State private selectedIds: string[] = [];
  // 行左滑互斥组（容器单源——可见集重算 / 进多选 / 渲染件滚动开始均经组收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  // 列表刷新广播（递增 tick；@Watch 对同值不触发）
  @StorageProp(SKILL_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 菜单材质档位（@StorageProp 自订阅——AppMenuHost 弹出时解析；PromptLibraryPage 同款）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 菜单节点宿主（官方 openMenu：init 一次 / 弹出前重建 / dispose 成对——见域件注释）
  private rowMenu: SkillRowMenuHost = new SkillRowMenuHost();
  // 标题栏「更多」菜单节点宿主（机制同 rowMenu；内容与锚点在 SkillTitleMenu.ets）
  private titleMenu: SkillTitleMenuHost = new SkillTitleMenuHost();
  // 待导入载荷（审阅弹窗期间持有；导入或取消后清空——弹窗是异步确认，载荷必须跨帧存活）
  private pendingImport: SkillPackReadResult | null = null;
  // 导入审阅弹窗控制器（★ 按需构造赋成员位——坑7 姿态；message 依载荷动态拼，不能预建）
  private importCtrl: CustomDialogController | null = null;
  // 删除确认弹窗（坑7：必须成员位构造——普通类 open() 静默无效，真机实锤）
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
    this.titleMenu.init(this.getUIContext(), this.titleMenuCallbacks());
    this.reload();
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.rowMenu.dispose();
    this.titleMenu.dispose();
  }

  private onListTick(): void {
    this.reload();
  }

  // 新建：达上限即就地拦截（P0-1 明确提示；不 push 空编辑页让用户白填）；多选态新建让位
  //（push 返回后残留会与批量删除交错）
  private onNewSkill(): void {
    if (this.multiSelect) {
      return;
    }
    countSkills()
      .then((count: number): void => {
        if (this.departed) {
          return;
        }
        if (count >= SKILL_TOTAL_MAX) {
          this.getUIContext().getPromptAction().showToast({ message: SKILL_FULL_TIP });
          return;
        }
        this.editSkill('');
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '技能库读取失败：' + (e as Error).message });
      });
  }

  // 空行对象（init 建菜单节点的占位载荷——**禁传 null 断言**：ComponentContent 创建时即固化
  // UI 树，传 null 首建即抛 TypeError = 进页闪退，真机实锤；菜单收窄后 builder 不再读 source，
  // 但硬化形态保留——打开菜单前 rebuild 会换真实行）
  private emptySkill(): SkillRow {
    return { id: '', name: '', description: '', content: '', source: '',
      createdAt: 0, updatedAt: 0, sortOrder: 0 };
  }

  private rowCallbacks(row: SkillRow): SkillRowMenuCallbacks {
    return {
      item: row,
      onExportMd: (item: SkillRow): void => {
        this.exportRowMd(item);
      },
      onExportPack: (item: SkillRow): void => {
        this.exportRowPack(item);
      }
    };
  }

  private reload(): void {
    querySkills()
      .then((rows: SkillRow[]): void => {
        if (this.departed) {
          return;
        }
        this.skills = rows;
        // 搜索态下增删改后仍在同一过滤视图里（关键词不因重拉被清空——记忆库页同款口径）
        this.applyFilter(rows);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '技能读取失败：' + (e as Error).message });
      });
  }

  // 可见行重算（纯内存过滤，不查库；空词 = 全显）。两个重算点：reload 成功与搜索框 onChange
  private applyFilter(rows: SkillRow[]): void {
    // 可见集重算 → 收起左滑展开行
    this.swipeGroup.collapse();
    this.visibleSkills = filterSkillsByKeyword(rows, this.keyword);
  }

  // 内容顶留白：让出标题栏下方带内框位（算式单源 = searchBandContentTop，本页只分派）。
  // ★ 多选态带收起 → 归 topPad
  private contentTopPad(): number {
    return !this.multiSelect
      ? searchBandContentTop(this.topPad, 28) : this.topPad;
  }

  // 0 行态提示文案（两态不可混，分派单源）：库空 = 新建引导；搜索无命中 = 单句不带引导
  private emptyHintText(): string {
    if (this.skills.length === 0) {
      return '暂无技能。点右上角的「＋」新建，再到助手编辑页的技能分区里启用。';
    }
    return '没有匹配的技能。';
  }

  // 进编辑页（空参 = 新建；本页不进多选态，无新建语义冲突的守卫需求）
  private editSkill(skillId: string): void {
    this.pathStack.pushPathByName(ROUTE_SKILL_EDIT_PAGE, skillId);
  }

  // 导出 SKILL.md：底层链 = serializeSkillMd → 沙箱暂存 → 官方分享面板（自带「另存为文件」）。
  // 取库里已保存的行；失败 toast 不静默（P0-1）
  private async exportRowMd(row: SkillRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const path: string = exportSkillMd(ctx, row);
      await this.shareFile(path, ctx);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 导出技能包：连同附件打成 zip → 分享。菜单挂在已落库的行上，导出内容本就是库里值，无需
  // 「先落库再打包」
  private async exportRowPack(row: SkillRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const files: SkillFileRow[] = await querySkillFiles(row.id);
      if (this.departed) {
        return;
      }
      const path: string = await exportSkillPack(ctx, row, files);
      if (this.departed) {
        return;
      }
      await this.shareFile(path, ctx);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 分享面板（两导出共用；utd 与 label 照既有链的 FILE 形态）
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

  // 导入技能（单入口双格式）：库满先拦 → 选择器取 zip 或 .md → 解析（各带容错三态）→ 重名拒
  // → **原文审阅弹窗**（正文是指令注入面，必须用户过目）→ 落库 + 附件逐个入库（单件失败不炸
  // 整批，计数呈报）。任何一步失败都 toast 中文原因，不静默（P0-1）
  private async importPack(): Promise<void> {
    try {
      const count: number = await countSkills();
      if (this.departed) {
        return;
      }
      if (count >= SKILL_TOTAL_MAX) {
        this.getUIContext().getPromptAction().showToast({ message: SKILL_FULL_TIP });
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '技能库读取失败：' + (e as Error).message });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 导入 = 单件动作（只取 uris[0]）：不设 maxSelectNumber 时系统面板默认多选，多选件除首个
      // 外静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      // 后缀过滤（元素内 '|' 左描述右后缀，数组总长 ≤ 100 字符）。★「该参数仅部分设备能力
      // 可用」——**不得当唯一防线**，硬闸是下方按扩展名分派 + 不支持格式的兜底提示
      selectOpts.fileSuffixFilters = ['技能文件|.zip,.md'];
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (this.departed) {
        return;
      }
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const read: SkillPackReadResult | null = await this.readPickedEntry(ctx, uris[0]);
      if (this.departed) {
        return;
      }
      if (read === null) {
        return; // 扩展名不在支持面（readPickedEntry 已给中文提示）
      }
      if (!read.ok) {
        this.getUIContext().getPromptAction().showToast({ message: read.error });
        return;
      }
      // 单件形态（技能包恒一件 / 单文件）走原链：重名即拒整批
      if (read.payloads.length === 1 && read.skipped.length === 0) {
        const payload: SkillPackPayload = read.payloads[0];
        // 重名拒（不做自动改名——两个「长得像但名字不同」的技能比当场拒绝更难排查）
        const existing: SkillRow[] = await querySkills();
        if (this.departed) {
          return;
        }
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
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 多件链：逐件过重名与库容，导不了的并入跳过清单如实呈报（「能导的先导、导不了的逐条说清」；
  // 单件时逐件等同整批）。全部不可导入 = toast 首条原因；库容不足 = 说清要腾多少位（不做
  // 「先塞满再丢尾」——静默丢件是红线）
  private async importMulti(read: SkillPackReadResult): Promise<void> {
    try {
      const existing: SkillRow[] = await querySkills();
      if (this.departed) {
        return;
      }
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
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 按扩展名分派（skillFileExt 小写归一）：.md → readSkillMdFile（无附件，自家导出可导回）；
  // .zip / '' → readSkillPack（'' = URI 取不到名的极端形态）；其余 → 兜底提示后返回 null
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

  // 审阅确认（ConfirmDialog 成员位弹窗；message 载名称/触发描述/正文摘录/附件清单/跳过项；
  // 确认键 NORMAL）。取消键清载荷（遮罩关闭路径无回调，仍由下次导入覆盖，单份载荷有界）
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

  // 预览文案：组装逻辑在纯函数层 composeImportPreview（★ 弹窗 message 是无上限 Text，长名
  // 附件会顶出屏——纯函数做分段截断 + 条数封顶，安全提示句恒在末尾）。单件走原函数；多件（或
  // 带跳过项）走 composeBatchImportPreview——只列件名与附件数，附件级警告加技能名前缀后并进
  // 跳过清单（逐件展开正文会顶爆上界；完整正文在导入后的编辑页可看）
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

  // 落库（技能行 + 附件逐件）：`i < SKILL_FILE_MAX_COUNT` 是页面侧第二道界（读取侧已封顶）；
  // 单件写入失败计失败数，不炸整批。多件**串行**落库（并发建行会让库容判定与写入之间出现时间
  // 窗；上限 50 且本地 DB，串行代价可忽略），逐件走 importOne，末尾汇总一次
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
      content: payload.content })
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

  // 行卡四点键菜单（只余两导出——编辑 = 行卡点击、删除 = 行左滑）
  private openRowMenu(row: SkillRow): void {
    if (this.multiSelect) {
      return; // 多选态四点键失效（切换语义并入行点击；渲染侧多选态也不出该键）
    }
    this.rowMenu.open(this.getUIContext(), this.rowCallbacks(row), this.immersiveLevel);
  }

  // ── 标题栏「更多」菜单（导入技能 + 多选两项）──
  private titleMenuCallbacks(): SkillTitleMenuCallbacks {
    return {
      onImport: (): void => {
        this.importPack();
      },
      onMultiselect: (): void => {
        this.onMultiSelect();
      }
    };
  }

  // 弹出「更多」菜单（定位 = 隐形锚点 SkillMoreMenuAnchor，几何见 SkillTitleMenu.ets）。
  // ★ 多选态让位：原键位一律让位、动作集中在批量条——一处守卫闭全菜单
  private openMoreMenu(): void {
    if (this.multiSelect) {
      return;
    }
    this.titleMenu.open(this.getUIContext(), this.titleMenuCallbacks(), this.immersiveLevel);
  }

  // ── 多选（菜单「多选」项 → 批量删除模式）──
  // 进入多选：幂等 + 进入即清空已选（清空只留批量条「全不选」一处，防两入口）
  private onMultiSelect(): void {
    if (this.multiSelect) {
      return;
    }
    this.swipeGroup.collapse();
    this.multiSelect = true;
    this.selectedIds = [];
  }

  private exitMultiSelect(): void {
    this.multiSelect = false;
    this.selectedIds = [];
  }

  // 可选行 id 集（全选判据与动作的共同输入——**可见集**单源，勿在别处重造）。★ 内置行恒定
  // 剔除：内置技能禁删（行卡菜单不出「删除」、deleteSkill 首行守卫兜底），全选跳过它们，批量
  // 删除也就撞不到库层守卫（决明拍板「不参与多选」）。过滤态只吃可见行（吃全量会选屏外行）
  private selectableSkillIds(): string[] {
    const ids: string[] = [];
    for (const row of this.visibleSkills) {
      if (row.source !== 'builtin') {
        ids.push(row.id);
      }
    }
    return ids;
  }

  // 全选/全不选（批量条左端键）；判据纯函数在 SessionMultiselectBar（共用单源）
  private toggleSelectAll(): void {
    this.selectedIds = nextSelectAllIds(this.selectableSkillIds(), this.selectedIds);
  }

  // 勾选切换（渲染件上行行 id——与点卡通勾选同一逻辑）
  private toggleSelectId(id: string): void {
    const idx: number = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      this.selectedIds = this.selectedIds.filter((item: string): boolean => item !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  private confirmDelete(row: SkillRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  // 左滑删除入口（行 id → 行对象后走既有确认链；行已在重拉中消失 = 静默不弹；内置行渲染侧
  // 不挂左滑，不会到这里）
  private confirmDeleteById(id: string): void {
    const row: SkillRow | undefined =
      this.skills.find((r: SkillRow): boolean => r.id === id);
    if (row !== undefined) {
      this.confirmDelete(row);
    }
  }

  // 批量删除确认（批量条主操作）；文案与单删同一句（通用后果提示，不写动态件数）；空选由本
  // 守卫拦住（不加禁用态）
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.confirmCtrl.open();
  }

  private doDelete(): void {
    if (this.multiSelect) {
      this.doDeleteSelected();
      return;
    }
    const target: SkillRow | null = this.deleteTarget;
    if (target === null) {
      return;
    }
    this.deleteTarget = null;
    // 删行 + 联动清各助手 skills 列 + 广播（都在 deleteSkill 一个事务里；本页不重复广播）
    deleteSkill(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 批量删除（逐件调既有单件原语——不新增库层批量原语，级联与广播单一来源仍只有 deleteSkill
  // 一处，两处实现 = 两处漂移面；上限 50 有界，逐件本地事务代价可接受）。全成才报成功件数，
  // 任一失败如实说「部分删除失败」；完成/失败都退出多选。★ 计数变量名取 settled（不用那个
  // 三字母短名）——assert-skill-domain「导入落库无死计数」负向钉在**全文件**扫该短名，撞名即假红
  private doDeleteSelected(): void {
    const ids: string[] = [];
    for (const id of this.selectedIds) {
      ids.push(id);
    }
    let settled: number = 0;
    let failed: boolean = false;
    for (const id of ids) {
      deleteSkill(id)
        .then((): void => {
          settled++;
          if (settled === ids.length) {
            this.reportDeleteSelected(ids.length, failed);
          }
        })
        .catch((): void => {
          failed = true;
          settled++;
          if (settled === ids.length) {
            this.reportDeleteSelected(ids.length, failed);
          }
        });
    }
  }

  // 批量删除结果（单点呈报——成功报件数，失败如实说部分失败不逐件列名；先 toast 再退多选与重拉）
  private reportDeleteSelected(total: number, failed: boolean): void {
    if (failed) {
      this.getUIContext().getPromptAction().showToast({ message: '部分技能删除失败，请重试' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + total + ' 件技能' });
    }
    this.exitMultiSelect();
    this.reload();
  }

  // 标题栏覆盖层（右上角合并胶囊〔＋新建 | ⋯更多〕）——组件内 @Builder 挂载是硬约束
  //（坑30：全局 @Builder 被 titleBar napi 调用时无视图上下文，启动即闪退）；胶囊与两动作注入
  // 在域件 SkillTitleMenu.ets（SkillTitleBarKeys），本页只传两动作
  @Builder
  TitleBarContent() {
    SkillTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onAdd: (): void => {
        this.onNewSkill();
      },
      onMore: (): void => {
        this.openMoreMenu();
      }
    })
  }

  // 标题栏下方带搜索框：SearchTopBand 恒 REGULAR 光感，几何与命中透传见该件
  @Builder
  SearchBand() {
    SearchTopBand({
      keyword: $keyword,
      placeholder: '搜索名称、描述或正文',
      onInput: (value: string): void => {
        this.keyword = value;
        this.applyFilter(this.skills);
      }
    })
  }

  // 内容区（Stack 同层三件 = 「更多」菜单隐形锚点 + 内容层 + 多选批量条，顶部对齐）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 目标；几何 = 「按钮下沿」公式，见域件；
      // HitTest.None 不拦滚动与触摸）
      SkillMoreMenuAnchor({ topPad: this.topPad })
      if (this.visibleSkills.length === 0) {
        // 0 行分支（壳侧 Scroll 兜底——Repeat 无行可挂；提示行 13fp cardDescColor +
        // CARD_PANEL_WIDTH 无卡底）。
        Scroll() {
          Column({ space: 10 }) {
            // 空态两态不可混，分派单源 = emptyHintText（库空原文 / 搜索无命中单句）
            Text(this.emptyHintText())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ top: this.contentTopPad(), bottom: this.bottomPad + 16 })
        }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      } else {
        SkillLibRows({
          // 数据源 = 过滤后的可见集
          skills: UIUtils.enableV2Compatibility(this.visibleSkills),
          // 多选态与选中集（标量 @Param + 桥接数组下行，Checkbox 纯视觉框架件随 @Param 刷新）
          multiSelect: this.multiSelect,
          selectedIds: UIUtils.enableV2Compatibility(this.selectedIds),
          appColorMode: this.appColorMode,
          // 左滑互斥组
          group: this.swipeGroup,
          // 顶留白：让出带内框位（contentTopPad）
          topPad: this.contentTopPad(),
          bottomPad: this.bottomPad,
          onOpen: (row: SkillRow): void => {
            this.editSkill(row.id);
          },
          onToggle: (id: string): void => {
            this.toggleSelectId(id);
          },
          onMenu: (row: SkillRow): void => {
            this.openRowMenu(row);
          },
          // 左滑删除（删除键与长距直达同链，弹既有确认框；删除唯一走本链）
          onSwipeDelete: (id: string): void => {
            this.confirmDeleteById(id);
          }
        })
          .width('100%')
          .height('100%')
      }

      // 多选批量条（图标三键 ActionBar，计数在确认弹窗；barBottom = bottomPad + 16）。
      // ★ 全选吃**可选可见集**（selectableSkillIds——不选屏外行，内置行恒定剔除）
      if (this.multiSelect) {
        SessionMultiselectActionBar({
          allSelected: isAllSelectedIn(this.selectableSkillIds(), this.selectedIds),
          barBottom: this.bottomPad + 16,
          onCancel: (): void => {
            this.exitMultiSelect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          },
          onToggleAll: (): void => {
            this.toggleSelectAll();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      // 主标题：多选态 = 「已选 N 项」随勾选实时刷（@Prop 传导）；常态 = 搜索注册表标题常量
      title: this.multiSelect ? '已选 ' + this.selectedIds.length + ' 项' : SETTING_TITLE_SKILL_LIBRARY,
      // 标题栏两键 = 覆盖层合并胶囊〔＋新建 | ⋯更多〕（menuHds 传 null，keepStackTitle 保主标题）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      // 标题栏下方带搜索框。
      // ★ 多选态带收起（隐藏开关经 @Prop 进壳早期返回——titleBarBottom 普通成员不能动态置空，
      // 见 PageShell 同名参注释）；内容让位 = contentTopPad
      titleBarBottom: (): void => {
        this.SearchBand();
      },
      titleBarBottomHidden: this.multiSelect,
      content: (): void => {
        this.Content();
      }
    })
  }
}

// ═══ 技能清单渲染域（同文件同域——壳引渲染件单向）═══
// 机制 = List + Repeat.virtualScroll（V2）：数据源壳侧构造处桥接；键只写技能 id（整体替换后
// 同 id 新对象靠 item 比对刷新——坑16 键载荷机制等价接替，禁键载荷回潮）；数据源 = 壳侧
// 过滤后的可见集，本件不知有「过滤」（纯渲染）；让位 = offset 轨；0 行由壳侧分支渲染。
// 行卡事件上行壳侧执行。
// ★ 多选态标量 @Param + 选中集桥接数组下行（勾选圈纯视觉框架件随 @Param 刷新）；内置行
// 多选态不出勾选圈且点行无动作（可选集剔除在壳侧，本件只按 source 判渲染）。
// ★ 行卡包 RowSwipeDelete；**内置行不挂左滑**（enabled 传 false——判据 = 是否提供删除能力：
// 内置行禁删，DB 守卫兜底）；多选态 swipeEnabled 翻 false；展开态不进键；滚动开始经组收起。
// ★ 四点键只余两导出（编辑 = 点卡、删除 = 行左滑）；点卡语义不变（常态进编辑 / 多选态切勾选）
@ComponentV2
struct SkillLibRows {
  // 技能清单（壳侧桥接传入——Repeat 懒加载要求数据源具 V2 观察能力；搜索态下 = 可见集）
  @Param skills: SkillRow[] = [];
  // 多选模式（勾选圈/四点键互斥——标量 @Param 下行）
  @Param multiSelect: boolean = false;
  // 选中集（桥接数组——Checkbox select 逐行比对刷新）
  @Param selectedIds: string[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 左滑互斥组（壳侧单源）
  @Param group: SwipeGroup = new SwipeGroup();
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 事件三枚（透传壳侧回调；★ 读当前 ri.item，禁构造期快照）
  @Event onOpen: (row: SkillRow) => void = () => {
  };
  @Event onToggle: (id: string) => void = () => {
  };
  @Event onMenu: (row: SkillRow) => void = () => {
  };
  // 左滑删除（删除键与长距直达共用——壳侧走既有确认链）
  @Event onSwipeDelete: (id: string) => void = () => {
  };

  // 行卡（多选态 = 勾选圈贴右缘 + 行点击切换；普通态 = 点击进编辑 + 右侧四点键；显示与锚点读
  // 当前 ri.item）。★ 内置行不参与多选——
  // 多选态不渲染勾选圈、点行无动作（禁删的同口径延伸）
  @Builder
  SkillCard(ri: RepeatItem<SkillRow>) {
    // ★ 蒙层边距统一口径：卡底 Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 回添，
    // 几何零位移
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(ri.item.name !== '' ? ri.item.name : '未命名技能')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                // 名称单行收敛（不收敛时行卡随名称长短高矮不一）
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 内置行「内置」标（实底胶囊 StatusBadge）：回标题右侧原位（2026-11-01 决明两轮
              // 拍板定案——首移行尾「贴最右、更多键左边」真机否决「不跟更多并排」，左右布局
              // 恢复原状；行内 VerticalAlign.Center 徽标高 ≈ 标题行高，与标题同一条线）
              if (ri.item.source === 'builtin') {
                StatusBadge({ text: '内置' })
              }
            }
            .alignItems(VerticalAlign.Center)
            Text(ri.item.description !== '' ? ri.item.description : '未填写触发描述，模型较难自动命中')
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.multiSelect) {
            // 勾选圈贴右缘（官方 Checkbox 纯视觉指示器——坑5：hitTestBehavior(None) 穿透 +
            // 卡片 onClick 单一通路）；内置行不出勾选圈（壳侧可选集剔除，两处判据同源）
            if (ri.item.source !== 'builtin') {
              Checkbox()
                .select(this.selectedIds.indexOf(ri.item.id) >= 0)
                .hitTestBehavior(HitTestMode.None)
            }
          } else {
            // 四点键（普通态：两导出项）
            Button() {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .id(SKILL_ROW_MENU_ID_PREFIX + ri.item.id)
            .onClick((): void => {
              this.onMenu(ri.item);
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      .onClick((): void => {
        if (this.multiSelect) {
          if (ri.item.source !== 'builtin') {
            this.onToggle(ri.item.id);
          }
          return;
        }
        this.onOpen(ri.item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: 10 }) {
      Repeat<SkillRow>(this.skills)
        .each((ri: RepeatItem<SkillRow>) => {
          ListItem() {
            // 保真层 Column 居中（ListItem 子项不水平居中致窄卡整列左偏，实锤）
            Column({ space: 10 }) {
              // 行卡包横滑层：**内置行 enabled 传 false**（与「不出删除项 / 不参与多选」同口径）；
              // 多选态整层退化
              RowSwipeDelete({
                rowId: ri.item.id,
                swipeEnabled: !this.multiSelect && ri.item.source !== 'builtin',
                group: this.group,
                content: (): void => {
                  this.SkillCard(ri)
                },
                onSwipeDelete: (id: string): void => {
                  this.onSwipeDelete(id);
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 技能 id（身份唯一；改名/改描述靠整体替换后 item 比对刷新，禁键载荷回潮）
        .key((row: SkillRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 5 为屏内缓冲（轻行卡；按页设值非全局口径）
    .cachedCount(5)
    // 竖滚开始收起左滑展开行（互斥经 SwipeGroup 单源）
    .onScrollStart((): void => {
      this.group.collapse();
    })
  }
}
