// 服务商配置迁移编排域（2026-09-02 建档；2026-09-20 决明指令「迁移卡退役、只留菜单」——
// 原 ProviderSharePanel 的「配置迁移」卡自高级页签整件退役〔与卡片菜单「分享」重复〕，
// 组件结构同笔删除，本件只留三条编排函数）。
// · 入口面（退役后唯一入口，全在服务商管理页）：卡片菜单「分享」= 单家导出
//  （exportShareConfig）；标题栏更多菜单「分享配置」= 批量导出（exportShareAll）、
//  「导入配置」= 批量导入（importShareConfig）。三条链路与全部文案逐字未动，本笔只减入口。
// · 单家导出（2026-09-03 改版）：导出键弹官方对话框三选（取消/不含密钥/包含密钥）后走
//   对应链路；「含密钥」强制口令加密（裸明文 Key 落盘形态不存在）；「不含密钥」档会同时
//   省略 Key 池/余额 Key/自定义请求头。导入恒为**新增**服务商（可重复导入）。
// · 批量版（2026-09-07）：导出 = 打包全部已启用服务商（v2 批量容器，口令一次加密整个包）；
//   导入 = 统一 parseShareFile（v1/v2 双版）→ 预览对话框分服务商逐列（名称 · 模型数 ·
//   密钥数）→ 逐家 applyShare（失败自动回滚）→ 结果对话框分服务商呈报成功/失败 →
//   onDone 回调（列表页 = reload）。单家与批量导出共用一个对话框三选语义，防漂移。
// · 导出链 = LogPage 日志导出同款官方姿势：沙箱暂存（ProviderShare.writeShareFile，
//   唯一名 + 清历史）→ systemShare 官方分享面板（自带「另存为文件」系统能力）；JSON
//   文件 UTD 用 PLAIN_TEXT（本地 uniformTypeDescriptor.d.ts 无 JSON 枚举，纯文本超集
//   兼容，LogPage 先例同款）。
// · 导入链 = AttachmentPickCtrl 同款 DocumentViewPicker（免权限）→ 文本读取 → 解析
//  （加密文件经口令弹窗，GCM 认证失败 = 口令错/文件损坏）→ 落库编排（三层 id 重新
//   生成 = 新增语义）→ 结果回执（对话框豁免档 = 单键告知/两键确认，见任务书 §3.5）。
// · 序列化/加密/落库全在 common/store/ProviderShare.ets（安全设计与文件格式见其头注释）。
// · askPassphrase 经回调注入（口令弹窗 = InputDialog password 型；CustomDialogController
//   须组件成员位构造 = 坑7）：调用方各自持控制器，本件不持 UI——uiContext 只作弹窗/写
//   文件/分享面板的上下文来源。
import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import {
  applyShare, buildSharePayload, parseShareFile, readShareFileText, serializeEncryptedShare,
  serializeEncryptedShares, serializeShare, serializeShares, ShareKeyRow, ShareProvider,
  writeShareFile
} from '../../common/store/ProviderShare';
import { ProviderRow, queryProviders } from '../../common/store/ProviderDb';
import { overlayMaterial } from '../../common/ImmersiveLevel';

// ═══ 单家导出编排（服务商卡片菜单「分享」项唯一实现）═══
// 口令弹窗 = CustomDialog（组件依赖），经 askPassphrase 回调注入；uiContext 供弹窗/
// 写文件/分享面板取上下文。失败统一 toast（P0-1 不静默）；用户取消路径恒 return 静默（正常取消）。
export async function exportShareConfig(uiContext: UIContext, providerId: string,
  askPassphrase: (title: string, placeholder: string) => Promise<string | null>): Promise<void> {
  if (providerId === '') {
    uiContext.getPromptAction().showToast({ message: '请先保存服务商后再导出' });
    return;
  }
  try {
    // 是否包含密钥（官方对话框；API 26 三键竖排——2026-09-03 决明真机实锤，首版误把
    // 「取消」放首位致其在最上，调按钮序即得「取消最下」；曾绕道 showActionMenu 同日
    // 回退：对话框形态带 message 栏位说明更完整）
    // 确认弹窗统一豁免：三键选择语义（包含密钥/不含密钥/取消），见任务书 §3.5
    const choice = await uiContext.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '导出配置',
      message: '包含密钥：文件带上 API Key，经口令加密，自备份推荐。分享给他人等于共享你的额度，仅限可信对象。\n不含密钥：对方导入后自行填写 Key。',
      buttons: [
        { text: '包含密钥', color: $r('sys.color.font_primary') },
        { text: '不含密钥', color: $r('sys.color.font_primary') },
        { text: '取消', color: $r('sys.color.font_secondary') }
      ]
    });
    if (choice.index === 2 || choice.index < 0) {
      return; // 取消键（-1 = 关闭防御）
    }
    const includeSecrets: boolean = choice.index === 0;
    const payload: ShareProvider = await buildSharePayload(providerId, includeSecrets);
    let json: string;
    if (includeSecrets) {
      // 缺失 Key 显式确认（2026-09-03 自检，Asset 丢失事故教训）：「明文缺失」支导出为
      // 空、不造假象——但静默导出会让用户误以为备份全量，导出前弹官方对话框确认
      const missing: number = payload.keys.filter((k: ShareKeyRow): boolean =>
        k.secret === null || k.secret === '').length;
      if (missing > 0) {
        // 确认弹窗统一豁免：两键确认但模块级函数宿主（CustomDialogController 须组件成员位——坑 7），见任务书 §3.5
        const confirm = await uiContext.getPromptAction().showDialog({
          systemMaterial: overlayMaterial(),
          title: '备份不完整',
          message: missing + ' 支 Key 的明文已缺失，可能因之前签名变更丢失，不会进入备份文件。继续导出？',
          buttons: [
            { text: '取消导出', color: $r('sys.color.font_secondary') },
            { text: '继续导出', color: $r('sys.color.font_primary') }
          ]
        });
        if (confirm.index !== 1) {
          return;
        }
      }
      const pass: string | null =
        await askPassphrase('设置备份口令', '口令加密文件内容，导入时需输入（丢失无法恢复）');
      if (pass === null) {
        return; // 用户取消
      }
      json = await serializeEncryptedShare(payload, pass);
    } else {
      json = serializeShare(payload);
    }
    const ctx: common.Context = uiContext.getHostContext() as common.Context;
    const path: string = writeShareFile(ctx, json, payload.name);
    const fileName: string = path.substring(path.lastIndexOf('/') + 1);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      uri: fileUri.getUriFromPath(path),
      title: fileName,
      label: 'FILE'
    };
    const controller: systemShare.ShareController =
      new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(uiContext.getHostContext() as common.UIAbilityContext, {});
  } catch (e) {
    uiContext.getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
  }
}

// ═══ 批量导出编排（服务商管理页标题栏菜单「分享配置」）═══
// 与 exportShareConfig 同构（防漂移同源：对话框三选 → 缺失确认 → 一次性口令 → 批量
// 序列化 → 沙箱暂存 → 系统分享面板），范围 = 全部已启用服务商。差异：v2 批量容器
// serializeShares/serializeEncryptedShares（ProviderShare.ets，多包一）、文件名
// 「服务商配置」、口令仅一次（整个包同一口令）。无启用服务商 = toast 返回（P0-1 不
// 静默）；用户取消路径恒 return 静默（正常取消）。
export async function exportShareAll(uiContext: UIContext,
  askPassphrase: (title: string, placeholder: string) => Promise<string | null>): Promise<void> {
  try {
    const all: ProviderRow[] = await queryProviders();
    const enabled: ProviderRow[] = all.filter((row: ProviderRow): boolean => row.enabled);
    if (enabled.length === 0) {
      uiContext.getPromptAction().showToast({ message: '没有已启用的服务商' });
      return;
    }
    // 名称摘录（≤5 家全列，更多省略「等 N 家」——对话框 message 防超长）
    const names: string[] = enabled.map((row: ProviderRow): string => row.name);
    const nameList: string = names.slice(0, 5).join('、') +
      (names.length > 5 ? ' 等 ' + names.length + ' 家' : '');
    // 确认弹窗统一豁免：三键选择语义（分享范围三选），见任务书 §3.5
    const choice = await uiContext.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '分享服务商配置',
      message: '将打包 ' + enabled.length + ' 家已启用的服务商：' + nameList +
        '。\n包含密钥：文件带上 API Key，经口令加密，分享给他人等于共享你的额度，仅限可信对象。\n不含密钥：对方导入后自行填写 Key。',
      buttons: [
        { text: '包含密钥', color: $r('sys.color.font_primary') },
        { text: '不含密钥', color: $r('sys.color.font_primary') },
        { text: '取消', color: $r('sys.color.font_secondary') }
      ]
    });
    if (choice.index === 2 || choice.index < 0) {
      return; // 取消键（-1 = 关闭防御）
    }
    const includeSecrets: boolean = choice.index === 0;
    const payloads: ShareProvider[] = [];
    let missing: number = 0;
    for (const row of enabled) {
      const payload: ShareProvider = await buildSharePayload(row.id, includeSecrets);
      if (includeSecrets) {
        missing += payload.keys.filter((k: ShareKeyRow): boolean =>
          k.secret === null || k.secret === '').length;
      }
      payloads.push(payload);
    }
    if (includeSecrets && missing > 0) {
      // 确认弹窗统一豁免：两键确认但模块级函数宿主（坑 7），见任务书 §3.5
      const confirm = await uiContext.getPromptAction().showDialog({
        systemMaterial: overlayMaterial(),
        title: '备份不完整',
        message: missing + ' 支 Key 的明文已缺失，可能因之前签名变更丢失，不会进入备份文件。继续导出？',
        buttons: [
          { text: '取消导出', color: $r('sys.color.font_secondary') },
          { text: '继续导出', color: $r('sys.color.font_primary') }
        ]
      });
      if (confirm.index !== 1) {
        return;
      }
    }
    let json: string;
    if (includeSecrets) {
      const pass: string | null =
        await askPassphrase('设置备份口令', '口令加密文件内容，导入时需输入（丢失无法恢复）');
      if (pass === null) {
        return; // 用户取消
      }
      json = await serializeEncryptedShares(payloads, pass);
    } else {
      json = serializeShares(payloads);
    }
    const ctx: common.Context = uiContext.getHostContext() as common.Context;
    const path: string = writeShareFile(ctx, json, '服务商配置');
    const fileName: string = path.substring(path.lastIndexOf('/') + 1);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      uri: fileUri.getUriFromPath(path),
      title: fileName,
      label: 'FILE'
    };
    const controller: systemShare.ShareController =
      new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(uiContext.getHostContext() as common.UIAbilityContext, {});
  } catch (e) {
    uiContext.getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
  }
}

// ═══ 批量导入编排（服务商管理页标题栏菜单「导入配置」）═══
// 选文件 → 读文本 → 解析（v1/v2 双版——v1 单家老文件同样可导，加密文件弹口令）→ 预览
// 对话框分服务商逐列（名称 · 模型数 · 密钥数，量级 = 解析载荷直读，无额外查库）→ 逐家
// applyShare（失败自动回滚，半成品零留存）→ 结果对话框分服务商呈报成功/失败 → onDone。
// 导入恒新增副本（可重复导入）；解析/读取失败兜底统一 toast（'已取消导入' = 用户取消，
// 静默）；askPassphrase 回调注入（组件弹窗，纯逻辑层不持 UI——exportShareConfig 同款）。
export async function importShareConfig(uiContext: UIContext,
  askPassphrase: (title: string, placeholder: string) => Promise<string | null>,
  onDone: (importedCount: number) => void): Promise<void> {
  try {
    const ctx: common.UIAbilityContext =
      uiContext.getHostContext() as common.UIAbilityContext;
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
    // 分享配置 = 单文件导入（后续口令与确认对话框都是单载荷语义）：不设 maxSelectNumber
    // 系统面板默认多选（上限 500），多选件除首个外静默丢失（2026-09-11 自检；
    // AttachmentPickCtrl 2026-09-03 同款教训）
    const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    selectOpts.maxSelectNumber = 1;
    const uris: Array<string> = await docPicker.select(selectOpts);
    if (uris.length === 0) {
      return; // 用户取消选择
    }
    const text: string = await readShareFileText(uris[0]);
    const payloads: ShareProvider[] = await parseShareFile(text, async (): Promise<string> => {
      const pass: string | null = await askPassphrase('输入文件口令', '该文件含密钥，已口令加密');
      if (pass === null) {
        throw new Error('已取消导入');
      }
      return pass;
    });
    const lines: string[] = payloads.map((p: ShareProvider): string =>
      '· ' + p.name + '（' + p.models.length + ' 个模型，' + p.keys.length + ' 支密钥）');
    // 确认弹窗统一豁免：两键确认但模块级函数宿主（坑 7），见任务书 §3.5
    const confirm = await uiContext.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '导入服务商配置',
      message: '将导入 ' + payloads.length + ' 家服务商：\n' + lines.join('\n') +
        '\n\n导入后均为新增副本，不会覆盖现有内容。',
      buttons: [
        { text: '取消', color: $r('sys.color.font_secondary') },
        { text: '开始导入', color: $r('sys.color.font_primary') }
      ]
    });
    if (confirm.index !== 1 || confirm.index < 0) {
      return; // 取消（-1 = 关闭防御）
    }
    let okCount: number = 0;
    const failures: string[] = [];
    for (const p of payloads) {
      try {
        await applyShare(p);
        okCount += 1;
      } catch (e) {
        failures.push(p.name + '（' + (e as Error).message + '）');
      }
    }
    let resultMsg: string = '成功导入 ' + okCount + ' 家服务商。';
    if (failures.length > 0) {
      resultMsg = resultMsg + '\n失败 ' + failures.length + ' 家：\n' + failures.join('\n');
    }
    // 确认弹窗统一豁免：单键告知语义（导入完成回执），见任务书 §3.5
    await uiContext.getPromptAction().showDialog({
      systemMaterial: overlayMaterial(),
      title: '导入完成',
      message: resultMsg,
      buttons: [{ text: '知道了', color: $r('sys.color.font_primary') }]
    });
    onDone(okCount);
  } catch (e) {
    const msg: string = (e as Error).message;
    if (msg !== '已取消导入') {
      uiContext.getPromptAction().showToast({ message: '导入失败：' + msg });
    }
  }
}
