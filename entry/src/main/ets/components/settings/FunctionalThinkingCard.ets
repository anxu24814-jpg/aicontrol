// 功能思考档位卡：卡头 = 标题 + ⓘ；单行「思考档位 + 当前档」，说明并入 ⓘ 与行副标题。
// 八条功能模型小任务链共用的全局档位（'' = 默认不干预 / off / low / high / max），聊天对话不受
// 影响；菜单恒五档全集，归一侧在 TitleApi.resolveFunctionalThinking。
// 档位菜单 = 行内原生 bindMenu（行件 = FunctionalSettingRows.SettingThinkingRow）——原状态驱动
// bindMenu 在外部点击/系统返回收起后残留显隐状态，报障后改原生，重复点按恒可再开。
// 自持有读取：档位持久键 @StorageProp 订阅即刷——本卡落键、备份导入等外部写点全部即时反映，
// 父侧零镜像零回调。
import { SETTING_TITLE_FUNCTIONAL_THINKING } from '../../common/SettingSearch';
import { FUNCTIONAL_THINKING_KEY } from '../../common/store/ProviderDb';
import { THINKING_OPTIONS } from '../../common/providers/AiTypes';
import { FunctionalCardHeader, SettingThinkingRow } from './FunctionalSettingRows';

@Component
export struct FunctionalThinkingCard {
  // 全局档持久键（'' = 默认不干预）+ @State 镜像（@Watch 回灌——备份导入等第二写键方在途时
  // 菜单与显示行随键同步）
  @StorageProp(FUNCTIONAL_THINKING_KEY) @Watch('syncTier') thinkingStored: string = '';
  @State private thinkingTier: string = '';

  aboutToAppear(): void {
    this.syncTier();
  }

  // 持久键 → 镜像回灌（aboutToAppear 播种 + @Watch 外部写点跟随）
  private syncTier(): void {
    this.thinkingTier = this.thinkingStored;
  }

  // 档位落键（菜单 onPick）：先刷行值再写持久键——菜单收起前勾选即时回显；同值不回写防递归
  private pickTier(tier: string): void {
    this.thinkingTier = tier;
    if (tier !== this.thinkingStored) {
      AppStorage.setOrCreate<string>(FUNCTIONAL_THINKING_KEY, tier);
    }
  }

  build() {
    Column({ space: 12 }) {
      FunctionalCardHeader({
        title: SETTING_TITLE_FUNCTIONAL_THINKING,
        hint: '对标题、记忆、压缩、审批等后台功能任务生效，聊天对话不受影响。档位按每个功能任务自己配置的模型生效，模型不支持思考字段时该任务自动回到默认。关闭仅在模型支持关闭思考时生效，其余模型不改行为。开启思考会增加功能任务的等待时间与用量消耗'
      })
      // 档位行：左主副标题 + 右当前档，整行点按弹官方菜单（显隐无状态，形制与 SettingValueRow 同规格）
      SettingThinkingRow({
        label: '思考档位',
        subtitle: '仅对后台任务生效',
        value: $thinkingTier,
        options: THINKING_OPTIONS,
        offOk: true,
        dividerTop: false,
        onPick: (option: string): void => {
          this.pickTier(option);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
