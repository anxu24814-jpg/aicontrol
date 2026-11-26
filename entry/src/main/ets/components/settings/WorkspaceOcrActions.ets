// 管理页识别文字行态与动作编排域（自 WorkspaceManagePage 域级最小拆分迁出，拆分轴 = 识别文字
// 域）：行三态派生（stateOf）+ 批量态位刷新（refreshOcrStates）+ 行菜单动作（onOcrAction =
// 查看 / 识别双路）+ 识别完成收尾（刷新 + 前台自动进查看页）+ 落定监听与引擎释放生命周期挂钩。
// · 本件零 UI：toast / 导航（进识别文字页）/ 重派生 / 行集读取 / 存活位全部经宿主接口注入
//  （分层红线照 WorkspaceOcrFlow——编排域禁 import UI 组件层）。
// · 文件夹段与会话段同构共用（2026-10-31 会话段补口）：会话视图经页面透传 stateOf / onOcr
//  消费同链，派生与动作语义两段恒一致；完成后自动进查看页两段同享。
// · 前台判据 = 入队时刻栈深：完成时栈深不变 = 仍在本页（自动进页）；期间压栈过他页 = 已离开，
//  静默落库。
import { isWorkspaceOcrCandidate, isWorkspaceOcrRunning, setWorkspaceOcrSettleListener,
  startWorkspaceOcr } from '../../common/WorkspaceOcrFlow';
import { ocrEnabled, ocrRelease } from '../../common/OcrEngine';
import { isWorkspaceDirRow, WorkspaceFileRow } from '../../common/WorkspaceUtil';
import { queryWorkspaceOcrHasText } from '../../common/store/ChatDb';
import { WorkspaceListEntry } from './WorkspaceListRows';

// 宿主回调面（页面实现）：UI 通道与存活位——本件经此触达页面，不反向 import 页面。
// ★ 箭头函数属性形制（工程惯例照 WorkspaceOcrHooks；方法简写接口不能被对象字面量实现）
export interface WorkspaceOcrActionsHost {
  // 页面存活守卫（置位后丢弃迟到刷新与导航）
  departed: () => boolean;
  // 组件在场位（识别完成收尾判据）
  pageMounted: () => boolean;
  // 全表行集（刷新扫描与显示名反查）
  rows: () => WorkspaceFileRow[];
  showToast: (message: string) => void;
  // 行态位重派生（管理页 = deriveEntries + 会话段广播键；两段同刷防标签停旧值）
  redraw: () => void;
  // 导航栈深（前台判据）
  stackSize: () => number;
  // 进识别文字页（查看路与完成自动进共用单点；返回刷新链在页面实现内挂）
  pushOcrPage: (fileId: string, name: string) => void;
}

export class WorkspaceOcrActions {
  // 有识别文本的行 id 集（两态轻量位——批量查回填，全文不进投影；非响应式 + 显式重派生）
  private ocrTextIds: Set<string> = new Set<string>();
  private host: WorkspaceOcrActionsHost;

  constructor(host: WorkspaceOcrActionsHost) {
    this.host = host;
  }

  // 生命周期挂钩：落定监听挂（他处发起任务的落定也刷新行态位——onComplete 归发起方，此处
  // 补刷标签）；调用方须已置 pageMounted
  attach(): void {
    setWorkspaceOcrSettleListener((_fileId: string): void => {
      if (this.host.pageMounted()) {
        this.refreshOcrStates();
      }
    });
  }

  // 成对释放：摘落定监听 + 引擎页级释放（页级成对释放与 ChatPage 同款；排队列尾不打
  // in-flight 识别）
  detach(): void {
    setWorkspaceOcrSettleListener(null);
    ocrRelease();
  }

  // 行三态派生单源：'running' 识别中 / 'has' 有识别文本 → 查看识别文字 / 'none' 无 → 识别文字；
  // undefined = 本行不出「识别文字」菜单项（非识别对象〔image / pdf〕或总开关关）。识别中位
  // 现查注册表（进程内单源）
  stateOf(row: WorkspaceFileRow): string | undefined {
    if (!isWorkspaceOcrCandidate(row) || !ocrEnabled()) {
      return undefined;
    }
    return isWorkspaceOcrRunning(row.id) ? 'running' :
      (this.ocrTextIds.has(row.id) ? 'has' : 'none');
  }

  // 态位刷新：批量查「有无识别文本」（全文不进投影）；回填后显式重派生；查询失败按「无文本」
  // 呈现，不阻断列表
  refreshOcrStates(): void {
    const rows: WorkspaceFileRow[] = this.host.rows();
    const ids: string[] = [];
    for (const row of rows) {
      if (!isWorkspaceDirRow(row) && isWorkspaceOcrCandidate(row) &&
        ids.indexOf(row.id) < 0) {
        ids.push(row.id);
      }
    }
    if (ids.length === 0) {
      this.ocrTextIds = new Set<string>();
      return;
    }
    queryWorkspaceOcrHasText(ids)
      .then((hits: string[]): void => {
        if (this.host.departed()) {
          return; // 迟到回写守卫（1712 纪律）：页亡不重派生不碰 UI
        }
        const hitSet: Set<string> = new Set<string>();
        for (const id of hits) {
          hitSet.add(id);
        }
        this.ocrTextIds = hitSet;
        this.host.redraw();
      })
      .catch((): void => {
        this.ocrTextIds = new Set<string>();
      });
  }

  // 行菜单动作三路：'has' = 查看直接进识别文字页（★ 修复——原实现无此路恒走重识别，
  // 「查看识别文字」名不副实）；'none' = 入编排件换「识别中」标签；running / 总开关关守卫
  // 无效（重入防线第二道）。菜单文案与派生同源 stateOf——标签与点击分支恒一致
  onOcrAction(entry: WorkspaceListEntry): void {
    const row: WorkspaceFileRow | null = entry.row;
    if (row === null) {
      return;
    }
    if (isWorkspaceOcrRunning(row.id)) {
      return; // 识别中点击无效（不重入）
    }
    if (!ocrEnabled()) {
      return; // 总开关关 = 入口不可用（标签派生已滤，防线）
    }
    if (entry.ocrState === 'has') {
      this.host.pushOcrPage(row.id, row.name);
      return;
    }
    // 前台判据 = 入队时刻栈深：完成时栈深不变 = 仍在本页（自动进页）；期间压栈过他页 = 已
    // 离开，静默落库
    const startDepth: number = this.host.stackSize();
    startWorkspaceOcr(row, {
      notify: (msg: string): void => {
        this.host.showToast(msg);
      },
      onComplete: (fileId: string, saved: boolean): void => {
        this.onOcrTaskComplete(fileId, saved, startDepth);
      }
    });
    // 注册表已置位——同拍重派生换「识别中」标签（键含 ocrState，键变即重建）
    this.host.redraw();
  }

  // 识别完成收尾：页亡 = 全静默；页在 = 刷新行态位（两路都刷，防标签停在旧值）；成功且仍在
  // 本页 = 自动进识别文字页
  private onOcrTaskComplete(fileId: string, saved: boolean, startDepth: number): void {
    if (!this.host.pageMounted()) {
      return;
    }
    this.refreshOcrStates();
    if (!saved || this.host.stackSize() !== startDepth) {
      return;
    }
    this.host.pushOcrPage(fileId, this.rowNameOf(fileId));
  }

  // 按 id 找显示名（自动进页标题用；'' = 行缺失，页面内再兜底）
  private rowNameOf(fileId: string): string {
    for (const row of this.host.rows()) {
      if (row.id === fileId) {
        return row.name;
      }
    }
    return '';
  }
}
