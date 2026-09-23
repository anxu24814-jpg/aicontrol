// 服务商编辑页 · 启停草稿域（2026-08-31 统一保存语义新建，领导拍板「所有配置改后必须点
// 右上角勾才能被保存」）：Key 启停 / 模型启停 / 批量启停不再即时落库——面板乐观更新 UI +
// 回调上行写入本域，标题栏「保存」链尾 flush 统一落库；不点勾直接退出 = 页面销毁草稿随之
// 丢弃 = 未保存的改动自然回滚（flush 失败由保存链 catch toast + 不 pop，草稿保留可重试，
// P0-1 不静默）。
// ★ 草稿放宿主页不放面板：面板随页签切换/纪元键销毁重建，草稿在面板会丢；宿主把 Map
// 引用下发（普通成员传引用，实例恒定——flush 成功用 clear 清空复用、不换实例），面板
// reload 时读引用回灌，保证「库态 + 草稿」始终等于用户所见（切页签回来不弹回）。
// ★ 孤儿说明：key/模型的添加与删除是资源动作仍即时落库（明文只能即时进 Asset、删除有
// 确认弹窗兜底）；删除后若草稿残留对应 id，flush 对已删行 UPDATE 命中 0 行 = no-op 无
// 副作用，无需清理（P2-4）。
import { setModelEnabled } from '../../common/store/ProviderDb';
import { setProviderKeyEnabled } from '../../common/store/ProviderKeyDb';

export class ProviderToggleDraft {
  private keyDraft: Map<string, boolean> = new Map();
  private modelDraft: Map<string, boolean> = new Map();

  setKey(keyId: string, on: boolean): void {
    this.keyDraft.set(keyId, on);
  }

  setModel(rowId: string, on: boolean): void {
    this.modelDraft.set(rowId, on);
  }

  // 面板回灌引用（只读语义；实例恒定，面板可跨页签切换长期持有）
  keyState(): Map<string, boolean> {
    return this.keyDraft;
  }

  modelState(): Map<string, boolean> {
    return this.modelDraft;
  }

  // 保存链尾统一落库：全成清空草稿；任一失败 reject（保存链 catch——草稿保留可重试）
  flush(): Promise<void> {
    const jobs: Promise<void>[] = [];
    this.keyDraft.forEach((on: boolean, keyId: string): void => {
      jobs.push(setProviderKeyEnabled(keyId, on));
    });
    this.modelDraft.forEach((on: boolean, rowId: string): void => {
      jobs.push(setModelEnabled(rowId, on));
    });
    if (jobs.length === 0) {
      return Promise.resolve();
    }
    return Promise.all(jobs).then((): void => {
      this.keyDraft.clear();
      this.modelDraft.clear();
    });
  }
}
