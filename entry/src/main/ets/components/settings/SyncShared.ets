// 「数据与同步」两卡共用件（自 DataSyncPage 域级最小拆分：summaryLine / backupDateLabel / cleanupExport /
// askImportStrategy / SyncField 五件原样迁入，方法体逐字等价）——DataSyncPage 与 S3SyncCard 双消费，禁第三套
// 复制拼装（assert-feature-domain 54 组关系钉守消费面）。不并入 DataSyncPage：共享件留页面文件会造
// S3SyncCard → DataSyncPage 双向 import 环。
// 弹窗两件（口令输入 / 上传确认）刻意不迁：CustomDialogController 须组件成员位构造（坑7），迁出即破——两卡
// 各自自含同款实现（54 契约钉全仓扫描兜底 onCancel 接线）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cardDescColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { cleanupExportDir, ExportSummary, ImportStrategy, ImportSummary } from '../../common/store/ExportImport';

// 表单输入行（label + 输入框；password 型走 TextInput.type）。★ 独立子组件 + @Link 订阅式双向（父侧 $字段
// 传参直挂 @State，回填随刷）——原 @Builder 按值传参属坑16/75 家族（异步回填后输入框仍显示空，观感 = 已存
// 配置丢失）；与 ProviderConfigPanel 契约一致。labelWidth 可调（S3 密钥两行标签较长，默认 56 不动存量四行）
@Component
export struct SyncField {
  @Link value: string;
  label: string = '';
  placeholder: string = '';
  isPassword: boolean = false;
  labelWidth: number = 56;

  build() {
    Row({ space: 10 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(this.labelWidth)
      TextInput({ text: this.value, placeholder: this.placeholder })
        .fontSize(14)
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .layoutWeight(1)
        .onChange((text: string): void => {
          this.value = text;
        })
    }
    .width('100%')
  }
}

// 导出/导入摘要行（呈报口径：表 × 行数收敛为一句）。损坏分域如实呈报：文件在但解析失败此前静默跳过、摘要只打
// 非零表，用户会误当「备份里本来就没有」；行级失败（单行转换异常 / 不可导入行 / 写入被拒）也如实报条数，覆盖
// 恢复场景才看得到「有数据其实没进来」。两入口共用本拼装
export function summaryLine(summary: ExportSummary | ImportSummary, exported: boolean): string {
  const counts: Record<string, number> = exported ?
    (summary as ExportSummary).counts : (summary as ImportSummary).imported;
  const parts: string[] = [];
  const pairs: string[][] = [['conversations', '会话'], ['messages', '消息'],
    ['providers', '服务商'], ['assistants', '助手'], ['prompt_templates', '提示词']];
  for (const pair of pairs) {
    const n: number = counts[pair[0]] ?? 0;
    if (n > 0) {
      parts.push(`${pair[1]} ${n}`);
    }
  }
  if (!exported) {
    for (const t of (summary as ImportSummary).parseFailed ?? []) {
      const hit: string[][] = pairs.filter((p: string[]): boolean => p[0] === t);
      parts.push(`${hit.length > 0 ? hit[0][1] : t}表损坏未导入`);
    }
    const rowFailed: number = (summary as ImportSummary).totalRowFailures;
    if (rowFailed > 0) {
      parts.push(`部分数据未导入 ${rowFailed} 条`);
    }
  }
  return parts.join('、');
}

// 远端档名 → 档期标签：反解 8 位日期显示为 YYYY-MM-DD；非日期档名（如旧版固定名）原样显示
export function backupDateLabel(remoteName: string): string {
  const m: RegExpMatchArray | null = remoteName.match(/(\d{4})(\d{2})(\d{2})/);
  if (m === null) {
    return remoteName;
  }
  return `${m[1]}-${m[2]}-${m[3]}`;
}

// 导出临时产物清删（zip + 解包目录——数据有界；文件名反解 stamp）
export function cleanupExport(ctx: common.UIAbilityContext, fileName: string): void {
  const stamp: string = fileName.replace('aicontrol_backup_', '').replace('.zip', '');
  try {
    fs.unlinkSync(ctx.cacheDir + '/aicontrol_backup_' + stamp + '.zip');
  } catch (e) {
    // 已不存在 = 目标状态
  }
  cleanupExportDir(ctx, stamp);
}

// 导入冲突策略弹窗（官方对话框两键，UIContext 形态）。返回 null = 用户取消（点空白/返回键），取消 = 静默放弃零导入
export async function askImportStrategy(ui: UIContext): Promise<ImportStrategy | null> {
  // 确认弹窗统一豁免：选择语义非纯确认（跳过/覆盖 + 取消）
  const choice = await ui.getPromptAction().showDialog({
    systemMaterial: overlayMaterial(),
    title: '选择导入方式',
    message: '跳过已存在则保留本机记录，只导入备份中的新记录。覆盖已存在则用备份中的记录替换本机同 id 记录，用于恢复误改的数据。覆盖还会用备份里的偏好设置覆盖本机设置，跳过则本机设置保持不变。用较旧的备份覆盖时，备份中没有的设置项会恢复为默认值。',
    buttons: [
      { text: '跳过已存在', color: $r('sys.color.font_secondary') },
      { text: '覆盖已存在', color: $r('sys.color.font_primary') }
    ]
  });
  if (choice.index === 0) {
    return 'skip';
  }
  if (choice.index === 1) {
    return 'overwrite';
  }
  return null;
}
