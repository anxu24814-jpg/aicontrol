// 服务商编辑页标题栏「保存」菜单工厂（checkmark 符号两项目内真机验证过）。
// 仅 HDS 数组单形态——回退 menus 数组版 providerSaveMenuNav 已随 HDS 唯一路径化整笔退役
//（2026-10-31 撤除 PageShell menuNav 传参时全仓零消费，按退役令删除不保留）。
// ModelEditPage 存在同构函数，其下次实质改动时收敛至此（技术债登记变更记录）。
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';

export function providerSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}
