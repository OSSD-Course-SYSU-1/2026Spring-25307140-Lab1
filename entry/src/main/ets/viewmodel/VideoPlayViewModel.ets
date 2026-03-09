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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { taskpool } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { PlayerState } from '../model/PlayerStateModel';
import { CommonConstants as Const } from '../common/CommonConstants';
import player, { getRenderTime } from 'libplayer.so';

const DOMAIN = 0x0000;
const TAG = 'VideoPlayViewModel';

@Concurrent
function periodicFunc(): void {
  try {
    let currentTime = getRenderTime();
    taskpool.Task.sendData(currentTime);
  } catch (error) {
    hilog.error(0x0000, 'periodicFunc', `sendData catch error, code: ${error.code}, message: ${error.message}`);
  }
}

@Observed
export class VideoPlayViewModel {
  @Track chooseNumber: number = -1;
  @Track chooseSpeed: number = Const.VIDEO_DEFAULT_SPEED;
  @Track isUse: boolean = false;
  @Track isSpeedListVisible: boolean = false;
  @Track isSwitchEnable: boolean = true;
  @Track currentTime: number = 0;
  @Track durationTime: number = 0;
  @Track speedText: string | Resource = $r('app.string.Default_speed_text');
  @Track isSeek: boolean = false;
  @Track playState: PlayerState = PlayerState.IDLE;

  public videoSources: resourceManager.RawFileDescriptor[] = [];
  private taskArray: Array<taskpool.Task> = [];
  private hostContext: Context | undefined = undefined;

  setUIContext(uiContext: UIContext): void {
    this.hostContext = uiContext.getHostContext();
  }

  async initialize(): Promise<void> {
    try {
      await this.setWindowProperties();
      this.registerEventListeners();
      this.startPeriodicTask();
    } catch (error) {
      hilog.error(DOMAIN, TAG, `initialize catch error, code: ${error.code}, message: ${error.message}`);
    }
  }

  async setWindowProperties(): Promise<void> {
    if (!this.hostContext) {
      return;
    }
    
    try {
      const topWindow = await window.getLastWindow(this.hostContext);
      
      await topWindow.setWindowSystemBarProperties({
        statusBarContentColor: '#FFFFFF'
      });
      
      await topWindow.setWindowKeepScreenOn(true);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set window properties. Cause: ${error.code}, message: ${error.message}`);
    }
  }

  registerEventListeners(): void {
    if (!this.hostContext) {
      return;
    }
    
    this.hostContext.eventHub.on('onBackground', this.onBackground);
    this.hostContext.eventHub.on('onForeground', this.onForeground);
  }

  unregisterEventListeners(): void {
    if (!this.hostContext) {
      return;
    }
    
    this.hostContext.eventHub.off('onBackground');
    this.hostContext.eventHub.off('onForeground');
  }

  startPeriodicTask(): void {
    this.taskArray.length = 0;
    this.taskArray.push(new taskpool.Task(periodicFunc));
    this.taskArray[0].onReceiveData((value: number) => {
      if (!this.isSeek) {
        this.currentTime = value / Const.TIME_RATIO;
      }
    });
    try {
      taskpool.executePeriodically(Const.TIME_INTERVAL, this.taskArray[0], taskpool.Priority.HIGH);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `executePeriodically failed: ${error.code}, message: ${error.message}`);
    }
  }

  stopPeriodicTask(): void {
    if (this.taskArray.length > 0) {
      try {
        taskpool.cancel(this.taskArray[0]);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `cancel failed: ${error.code}, message: ${error.message}`);
      }
    }
  }

  onBackground(): void {
    player.pause();
  }

  onForeground(): void {
    if (AppStorage.get<PlayerState>('playState') === PlayerState.PLAYING) {
      player.resume();
    }
  }

  togglePlayPause(playState: PlayerState): PlayerState {
    if (playState === PlayerState.PLAYING) {
      player.pause();
      return PlayerState.PAUSE;
    } else if (playState === PlayerState.PAUSE) {
      player.resume();
      return PlayerState.PLAYING;
    }
    return playState;
  }

  onSliderChange(value: number, mode: SliderChangeMode): void {
    this.currentTime = value;
    
    if (this.durationTime > 0) {
      if (mode === SliderChangeMode.Begin) {
        this.isSeek = true;
      }
      
      if (mode === SliderChangeMode.End) {
        this.performSeek(value);
      }
    }
  }

  async performSeek(value: number): Promise<void> {
    try {
      await player.seekVideo(value);
      setTimeout(() => {
        this.isSeek = false;
      }, Const.RELOAD_TIME);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Seek failed: ${error.code}, message: ${error.message}`);
    }
  }

  toggleSpeedList(): void {
    this.isSpeedListVisible = true;
  }

  hideSpeedList(): void {
    if (this.isSpeedListVisible) {
      this.isSpeedListVisible = false;
    }
  }

  onSpeedSelected(speed: number, index: number): void {
    if (this.chooseSpeed !== speed) {
      this.chooseSpeed = speed;
      player.setSpeed(this.chooseSpeed);
      this.speedText = Const.VIDEO_SPEED_TEXT_ARR[index];
      this.isSpeedListVisible = false;
    }
  }

  async onVideoSelected(index: number, rawDes: resourceManager.RawFileDescriptor): Promise<PlayerState | null> {
    if (this.chooseNumber === index) {
      return null;
    }
    
    this.isSwitchEnable = false;
    this.durationTime = 0;
    this.chooseNumber = index;
    this.isUse = false;

    if (!rawDes) {
      hilog.error(DOMAIN, TAG, 'player inputFile is null');
      this.isSwitchEnable = true;
      return null;
    }
    
    try {
      const data = await player.switchVideo(rawDes.fd, rawDes.offset, rawDes.length);
      
      if (data.code === 0) {
        player.play();
        this.durationTime = data.durationTime / Const.TIME_RATIO;
        this.isUse = true;
        this.isSwitchEnable = true;
        return PlayerState.PLAYING;
      } else {
        hilog.error(DOMAIN, TAG, 'player init failed, err code is ' + data.code);
      }
      
      this.isSwitchEnable = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Switch video failed: ${error.code}, message: ${error.message}`);
      this.isSwitchEnable = true;
    }
    
    return null;
  }

  cleanup(): void {
    try {
      this.stopPeriodicTask();
      this.unregisterEventListeners();
    } catch (error) {
      hilog.error(0x0000, TAG, `cleanup catch error, code: ${error.code}, message: ${error.message}`);
    }
  }
}