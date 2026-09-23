// 服务商编辑页标题栏「保存」菜单工厂（2026-08-31 自 ProviderDetailPage 域拆——统一保存
// 语义改动需在宿主页加启停草稿链，原 400 行贴线，按防屎山规则拆本域腾位；checkmark 符号
// 两项目内真机验证过）。HDS 数组 / 回退 menus 数组双形态——chatTitleMenu 工厂同款姿势。
// ModelEditPage 存在同构函数，其下次实质改动时收敛至此（技术债登记变更记录）。
import { SymbolGlyphModifier } from '@kit.ArkUI';
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

export function providerSaveMenuNav(onSave: () => void): NavigationMenuItem[] {
  return [{
    value: '保存',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
    action: onSave
  } as NavigationMenuItem];
}
