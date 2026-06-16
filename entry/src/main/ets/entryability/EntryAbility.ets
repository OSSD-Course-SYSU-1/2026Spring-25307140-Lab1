/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'ENTRY';

// 接续数据 Key 常量，用于 AppStorage 和 wantParam 的键名
const CONTINUE_KEY_CHOOSE_NUMBER = 'continueChooseNumber';
const CONTINUE_KEY_CURRENT_TIME = 'continueCurrentTime';
const CONTINUE_KEY_PLAY_STATE = 'continuePlayState';
const CONTINUE_KEY_CHOOSE_SPEED = 'continueChooseSpeed';
const CONTINUE_KEY_IS_FULL_SCREEN = 'continueIsFullScreen';
const CONTINUE_KEY_IS_CONTINUATION = 'isContinuation';

export default class EntryAbility extends UIAbility {
  storage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    } catch (error) {
      hilog.error(0x0000, TAG, `onCreate catch error, code: ${error.code}, message: ${error.message}`);
      return;
    }

    // 接续冷启动时恢复数据
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.restoreContinueData(want);
      // 保证迁移后可回迁
      this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, (result) => {
        hilog.info(DOMAIN, TAG, `setMissionContinueState ACTIVE: ${JSON.stringify(result)}`);
      });
      // 触发页面恢复，系统自动恢复页面栈
      this.context.restoreWindowStage(this.storage);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });

    try {
      windowStage.on('windowStageEvent', (data)=>{
        if (data === window.WindowStageEventType.RESUMED) {
          this.context.eventHub.emit('onForeground');
        } else if (data === window.WindowStageEventType.PAUSED) {
          this.context.eventHub.emit('onBackground');
        } else {
          hilog.info(DOMAIN, TAG, 'The window stage is not paused or resume');
        }
      })
    } catch (error) {
      hilog.error(0x0000, TAG, `windowStageEvent catch error, code: ${error.code}, message: ${error.message}`);
      return;
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  /**
   * 跨端迁移保存数据：源端设备触发，将播放状态保存到 wantParam
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onContinue');
    // 从 AppStorage 读取页面保存的播放状态
    const chooseNumber = AppStorage.get<number>(CONTINUE_KEY_CHOOSE_NUMBER);
    const currentTime = AppStorage.get<number>(CONTINUE_KEY_CURRENT_TIME);
    const playState = AppStorage.get<number>(CONTINUE_KEY_PLAY_STATE);
    const chooseSpeed = AppStorage.get<number>(CONTINUE_KEY_CHOOSE_SPEED);
    const isFullScreen = AppStorage.get<boolean>(CONTINUE_KEY_IS_FULL_SCREEN);

    if (chooseNumber !== undefined) {
      wantParam[CONTINUE_KEY_CHOOSE_NUMBER] = chooseNumber;
    }
    if (currentTime !== undefined) {
      wantParam[CONTINUE_KEY_CURRENT_TIME] = currentTime;
    }
    if (playState !== undefined) {
      wantParam[CONTINUE_KEY_PLAY_STATE] = playState;
    }
    if (chooseSpeed !== undefined) {
      wantParam[CONTINUE_KEY_CHOOSE_SPEED] = chooseSpeed;
    }
    if (isFullScreen !== undefined) {
      wantParam[CONTINUE_KEY_IS_FULL_SCREEN] = isFullScreen;
    }

    hilog.info(DOMAIN, TAG, `onContinue data: videoIndex=${chooseNumber}, time=${currentTime},` +
      ` state=${playState}, speed=${chooseSpeed}, fullScreen=${isFullScreen}`);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 热启动时接收接续数据
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.restoreContinueData(want);
      this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, (result) => {
        hilog.info(DOMAIN, TAG, `setMissionContinueState ACTIVE: ${JSON.stringify(result)}`);
      });
      this.context.restoreWindowStage(this.storage);
    }
  }

  /**
   * 迁移恢复时调用（替代 onWindowStageCreate）
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageRestore');
    // 迁移场景下加载主页面
    windowStage.loadContent('pages/Index', this.storage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content on restore.');
    });
  }

  /**
   * 从 want.parameters 恢复接续数据到 AppStorage
   */
  private restoreContinueData(want: Want): void {
    if (!want.parameters) {
      return;
    }
    AppStorage.setOrCreate(CONTINUE_KEY_IS_CONTINUATION, true);

    const chooseNumber = want.parameters[CONTINUE_KEY_CHOOSE_NUMBER];
    if (chooseNumber !== undefined) {
      AppStorage.setOrCreate(CONTINUE_KEY_CHOOSE_NUMBER, chooseNumber as number);
    }
    const currentTime = want.parameters[CONTINUE_KEY_CURRENT_TIME];
    if (currentTime !== undefined) {
      AppStorage.setOrCreate(CONTINUE_KEY_CURRENT_TIME, currentTime as number);
    }
    const playState = want.parameters[CONTINUE_KEY_PLAY_STATE];
    if (playState !== undefined) {
      AppStorage.setOrCreate(CONTINUE_KEY_PLAY_STATE, playState as number);
    }
    const chooseSpeed = want.parameters[CONTINUE_KEY_CHOOSE_SPEED];
    if (chooseSpeed !== undefined) {
      AppStorage.setOrCreate(CONTINUE_KEY_CHOOSE_SPEED, chooseSpeed as number);
    }
    const isFullScreen = want.parameters[CONTINUE_KEY_IS_FULL_SCREEN];
    if (isFullScreen !== undefined) {
      AppStorage.setOrCreate(CONTINUE_KEY_IS_FULL_SCREEN, isFullScreen as boolean);
    }
    hilog.info(DOMAIN, TAG, `restoreContinueData: videoIndex=${chooseNumber}, time=${currentTime},` +
      ` state=${playState}, speed=${chooseSpeed}`);
  }
}