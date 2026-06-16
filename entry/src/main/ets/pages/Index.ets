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

import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoPlayView } from '../view/VideoPlayView';
import { VideoPlayViewModel } from '../viewmodel/VideoPlayViewModel';
import { PlayerState } from '../model/PlayerStateModel';
import { CommonConstants as Const } from '../common/CommonConstants';

const VIDEO_NAMES = ['1.mp4', '2.mp4', '3.mp4'];
const TAG = 'INDEX';

// 接续数据 Key（与 EntryAbility 保持一致）
const CONTINUE_KEY_CHOOSE_NUMBER = 'continueChooseNumber';
const CONTINUE_KEY_CURRENT_TIME = 'continueCurrentTime';
const CONTINUE_KEY_PLAY_STATE = 'continuePlayState';
const CONTINUE_KEY_CHOOSE_SPEED = 'continueChooseSpeed';
const CONTINUE_KEY_IS_FULL_SCREEN = 'continueIsFullScreen';
const CONTINUE_KEY_IS_CONTINUATION = 'isContinuation';

@Entry
@Component
struct Index {
  @State videoResources : resourceManager.RawFileDescriptor[] = [];
  @State viewModel: VideoPlayViewModel = new VideoPlayViewModel();
  @State isFullScreen: boolean = false;
  private continueSyncTimerId: number = -1;

  aboutToAppear(): void {
    try {
      this.videoResources.length = 0;
      for (let i = 0; i< VIDEO_NAMES.length; i++) {
        let rawDes = this.getUIContext().getHostContext()?.resourceManager.getRawFdSync(VIDEO_NAMES[i]);
        if (rawDes) {
          this.videoResources.push(rawDes);
        }
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `aboutToAppear catch error, code: ${error.code}, message: ${error.message}`);
    }
    // 启动接续状态定时同步
    this.startContinueStateSync();
    // 检测是否为接续恢复场景
    this.checkContinueRestore();
  }

  aboutToDisappear(): void {
    this.stopContinueStateSync();
    try {
      for (let i = 0; i< VIDEO_NAMES.length; i++) {
        this.getUIContext().getHostContext()?.resourceManager.closeRawFdSync(VIDEO_NAMES[i]);
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `aboutToDisappear catch error, code: ${error.code}, message: ${error.message}`);
    }
  }

  /**
   * 定时将 ViewModel 状态同步到 AppStorage，供 onContinue 读取
   */
  private startContinueStateSync(): void {
    this.continueSyncTimerId = setInterval(() => {
      this.syncContinueState();
    }, 500); // 每500ms同步一次
  }

  private stopContinueStateSync(): void {
    if (this.continueSyncTimerId !== -1) {
      clearInterval(this.continueSyncTimerId);
      this.continueSyncTimerId = -1;
    }
  }

  /**
   * 将当前播放状态写入 AppStorage
   */
  private syncContinueState(): void {
    AppStorage.setOrCreate(CONTINUE_KEY_CHOOSE_NUMBER, this.viewModel.chooseNumber);
    AppStorage.setOrCreate(CONTINUE_KEY_CURRENT_TIME, this.viewModel.currentTime);
    AppStorage.setOrCreate(CONTINUE_KEY_PLAY_STATE, this.viewModel.playState as number);
    AppStorage.setOrCreate(CONTINUE_KEY_CHOOSE_SPEED, this.viewModel.chooseSpeed);
    AppStorage.setOrCreate(CONTINUE_KEY_IS_FULL_SCREEN, this.isFullScreen);
  }

  /**
   * 检测是否为接续恢复，若是则延迟恢复播放状态
   */
  private async checkContinueRestore(): Promise<void> {
    const isContinuation = AppStorage.get<boolean>(CONTINUE_KEY_IS_CONTINUATION);
    if (isContinuation !== true) {
      return;
    }
    // 接续恢复标记已处理，清除
    AppStorage.setOrCreate(CONTINUE_KEY_IS_CONTINUATION, false);

    const savedIndex = AppStorage.get<number>(CONTINUE_KEY_CHOOSE_NUMBER);
    if (savedIndex === undefined || savedIndex < 0) {
      return;
    }
    hilog.info(0x0000, TAG, `Restoring continue state: videoIndex=${savedIndex}`);

    // 等待 ViewModel 初始化完成后再恢复
    setTimeout(async () => {
      await this.restoreContinueState(savedIndex);
    }, 800);
  }

  /**
   * 恢复接续的播放状态：加载视频、设置进度和倍速
   */
  private async restoreContinueState(videoIndex: number): Promise<void> {
    const rawDes = this.videoResources[videoIndex];
    if (!rawDes) {
      hilog.error(0x0000, TAG, `Video resource at index ${videoIndex} not found`);
      return;
    }

    // 加载接续的视频
    const playState = await this.viewModel.onVideoSelected(videoIndex, rawDes);
    if (playState !== null) {
      this.viewModel.playState = playState;
    }

    // 恢复播放进度
    const savedTime = AppStorage.get<number>(CONTINUE_KEY_CURRENT_TIME);
    if (savedTime !== undefined && savedTime > 0) {
      this.viewModel.currentTime = savedTime;
      await this.viewModel.performSeek(savedTime);
    }

    // 恢复播放速度
    const savedSpeed = AppStorage.get<number>(CONTINUE_KEY_CHOOSE_SPEED);
    if (savedSpeed !== undefined && savedSpeed !== Const.VIDEO_DEFAULT_SPEED) {
      this.viewModel.chooseSpeed = savedSpeed;
      const speedIndex = Const.VIDEO_SPEED_ARR.indexOf(savedSpeed);
      if (speedIndex >= 0) {
        this.viewModel.speedText = Const.VIDEO_SPEED_TEXT_ARR[speedIndex];
      }
    }

    // 恢复播放状态：接续前如果在播放中，则自动播放
    const savedPlayState = AppStorage.get<number>(CONTINUE_KEY_PLAY_STATE);
    if (savedPlayState === PlayerState.PLAYING && this.viewModel.playState !== PlayerState.PLAYING) {
      this.viewModel.playState = this.viewModel.togglePlayPause(this.viewModel.playState);
    }

    // 恢复全屏状态
    const savedFullScreen = AppStorage.get<boolean>(CONTINUE_KEY_IS_FULL_SCREEN);
    if (savedFullScreen === true) {
      this.isFullScreen = true;
    }

    // 清理 AppStorage 中的接续数据
    AppStorage.setOrCreate(CONTINUE_KEY_CHOOSE_NUMBER, -1);
    hilog.info(0x0000, TAG, 'Continue state restored successfully');
  }

  onBackPress(): boolean | void {
    if (this.isFullScreen) {
      this.isFullScreen = false;
      return true;
    }
    return false;
  }

  build() {
    Column() {
      VideoPlayView({
        viewModel: this.viewModel,
        videoSources: $videoResources,
        isFullScreen: this.isFullScreen
      });
    }
    .width('100%')
    .height('100%')
  }
}