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
import { BusinessError } from '@kit.BasicServicesKit';
import { getShowTime } from '../common/TimeUtils';
import { PlayerState } from '../model/PlayerStateModel';
import { CommonConstants as Const } from '../common/CommonConstants';
import player from 'libplayer.so';

const DOMAIN = 0x0000;
const TAG = 'INDEX';
const FULL_SIZE = '100%';
const NORMAL_SIZE = '100%';
const WIDTH_SIZE = '100%';

/**
 * The thread function for querying the current rendering time.
 */
@Concurrent
function periodicFunc(): void {
  try {
    let currentTime = player.getRenderTime();
    taskpool.Task.sendData(currentTime);
  } catch (error) {
    hilog.error(0x0000, 'periodicFunc', `sendData catch error, code: ${error.code}, message: ${error.message}`);
  }
}

@Component
export struct VideoPlayView {
  @State chooseNumber: number = -1;
  @State chooseSpeed: number = Const.VIDEO_DEFAULT_SPEED;
  @State isUse: boolean = false;
  @State isSpeedListVisible: boolean = false;
  @State isSwitchEnable: boolean = true;
  @State currentTime: number = 0;
  @State durationTime: number = 0;
  @State speedText: string | Resource = $r('app.string.Default_speed_text');
  // [Start isFullScreen]
  // the horizontal full-screen playback state flag.
  @Watch('fullScreenSet') @State isFullScreen: boolean = false;
  // [End isFullScreen]
  @StorageLink('playState') playState: PlayerState = PlayerState.IDLE;
  @Link videoSources: resourceManager.RawFileDescriptor[];
  private taskArray: Array<taskpool.Task> = [];
  private isSeek: boolean = false;

  aboutToAppear(): void {
    try {
      let hostContext: Context | undefined = this.getUIContext().getHostContext();
      // Set the status bar color and keep the window always on.
      window.getLastWindow(hostContext).then((topWindow) => {
        topWindow.setWindowSystemBarProperties({
          statusBarContentColor: '#FFFFFF'
        }).catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG,
            `Failed to setWindowSystemBarProperties. Cause: ${error.code}, message: ${error.message}`);
        });
        topWindow.setWindowKeepScreenOn(true).catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG,
            `Failed to setWindowKeepScreenOn. Cause: ${error.code}, message: ${error.message}`);
        });
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `Failed to getLastWindow. Cause: ${error.code}, message: ${error.message}`);
      });

      // Register callbacks for monitoring the app entering the foreground and background.
      hostContext?.eventHub.on('onBackground', this.backgroundEventFunc);
      hostContext?.eventHub.on('onForeground', this.foregroundEventFunc);

      // Create a sub-thread for obtaining rendering time.
      this.taskArray.length = 0;
      this.taskArray.push(new taskpool.Task(periodicFunc));
      this.taskArray[0].onReceiveData((value: number) => {
        if (!this.isSeek) {
          this.currentTime = value / Const.TIME_RATIO;
        }
      })
      taskpool.executePeriodically(Const.TIME_INTERVAL, this.taskArray[0], taskpool.Priority.HIGH);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `aboutToAppear catch error, code: ${error.code}, message: ${error.message}`);
      return;
    }
  }

  aboutToDisappear(): void {
    try {
      // Cancel the sub-thread and event listening.
      taskpool.cancel(this.taskArray[0]);
      let hostContext: Context | undefined = this.getUIContext().getHostContext();
      hostContext?.eventHub.off('onBackground');
      hostContext?.eventHub.off('onForeground');
    } catch (error) {
      hilog.error(0x0000, TAG, `aboutToDisappear catch error, code: ${error.code}, message: ${error.message}`);
      return;
    }
  }

  backgroundEventFunc() {
    // The app stops playing when exiting to the background.
    player.pause();
  }

  foregroundEventFunc() {
    // The app resumes playing when returning to the foreground.
    if (AppStorage.get<PlayerState>('playState') === PlayerState.PLAYING) {
      player.resume();
    }
  }

  // [Start fullScreenSet]
  fullScreenSet() {
    // Window Orientation and Layout When Setting Full Screen.
    window.getLastWindow(this.getUIContext().getHostContext()).then((topWindow) => {
      topWindow.setPreferredOrientation(this.isFullScreen ?
        window.Orientation.AUTO_ROTATION_LANDSCAPE : window.Orientation.PORTRAIT).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `Failed to setPreferredOrientation. Cause: ${error.code}, message: ${error.message}`);
      });
      topWindow.setWindowLayoutFullScreen(this.isFullScreen ? true : false).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG,
          `Failed to setWindowLayoutFullScreen. Cause: ${error.code}, message: ${error.message}`);
      });
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to getLastWindow. Cause: ${error.code}, message: ${error.message}`);
    });
  }

  // [End fullScreenSet]

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // [Start XComponent]
        XComponent({
          id: 'playerXC',
          type: XComponentType.SURFACE,
          libraryname: 'player'
        })
          .width(WIDTH_SIZE)
          .height(this.isFullScreen ? NORMAL_SIZE : FULL_SIZE)
        // [End XComponent]

        Column() {
          Row() {
            Image($r('app.media.back'))
              .width('40vp')
              .height('40vp')
              .onClick(() => {
                this.isFullScreen = false;
              })

            Text($r('app.string.Video_name'))
              .fontColor(Color.White)
              .fontSize('20fp')
              .fontWeight(FontWeight.Medium)
              .margin({ left: '12vp' })
          }
          .width('100%')
          .height('24%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: '36vp' })
          .visibility(this.isFullScreen ? Visibility.Visible : Visibility.Hidden)

          Blank()
            .width('100%')
            .height('60%')

          Row() {
            Row() {
              Image(this.playState == PlayerState.PLAYING ?
                $r('app.media.ic_public_pause') : $r('app.media.ic_public_play'))
                .width('25vp')
                .height('25vp')
                .onClick(() => {
                  // Playback State Management.
                  if (this.playState === PlayerState.PLAYING) {
                    player.pause();
                    this.playState = PlayerState.PAUSE;
                  } else if (this.playState === PlayerState.PAUSE) {
                    player.resume();
                    this.playState = PlayerState.PLAYING;
                  }
                })
            }
            .width(this.isFullScreen ? '5%' : '8%')
            .height('100%')
            .justifyContent(FlexAlign.Center)

            Row() {
              Text(getShowTime(this.currentTime))
                .fontColor(Color.White)
                .fontSize('12fp')

              Slider({
                value: this.currentTime,
                min: 0,
                max: this.durationTime
              })
                .width(this.isFullScreen ? '80%' : '70%')
                .selectedColor('#F67609')
                .trackColor('#464642')
                .enabled(!this.isSeek)
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.currentTime = value;
                  if (this.durationTime > 0) {
                    if (mode === SliderChangeMode.Begin) {
                      this.isSeek = true;
                    }
                    if (mode == SliderChangeMode.End) {
                      // Perform the seek operation when the sliding ends.
                      player.seekVideo(value).then(()=>{
                        this.playState = PlayerState.PLAYING;
                        // Wait for the loading to complete before getting the time.
                        setTimeout(() => {
                          this.isSeek = false;
                        }, Const.RELOAD_TIME);
                      })
                    }
                  }
                })

              Text(getShowTime(this.durationTime))
                .fontColor(Color.White)
                .fontSize('12fp')
            }
            .width(this.isFullScreen ? '80%' : '70%')
            .height('100%')
            .justifyContent(FlexAlign.Center)

            Row() {
              Text(this.speedText)
                .fontColor(Color.White)
                .fontSize('14fp')
            }
            .width(this.isFullScreen ? '7%' : '14%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.isSpeedListVisible = true;
            })

            if (!this.isFullScreen) {
              Row() {
                Image($r('app.media.ic_public_enlarge'))
                  .width('25vp')
                  .height('25vp')
              }
              .width('8%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.isFullScreen = !this.isFullScreen;
              })
            }
          }
          .width(this.isFullScreen ? '70%' : '100%')
          .height('16%')
          .justifyContent(FlexAlign.SpaceBetween)
          .visibility(this.isSpeedListVisible ? Visibility.Hidden : Visibility.Visible)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: '16vp', right: '16vp' })
        .visibility(this.isUse ? Visibility.Visible : Visibility.Hidden)

        Row() {
          Column() {
            List({ space: 0, initialIndex: 2 }) {
              ForEach(Const.VIDEO_SPEED_ARR, (item: number, index: number) => {
                ListItem() {
                  Column() {
                    Text(Const.VIDEO_SPEED_TEXT_ARR[index])
                      .fontSize('16fp')
                      .fontColor(this.chooseSpeed === item ? '#F67609' : '#FFFFFF')
                  }
                  .width('100%')
                  .height('50vp')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .onClick(() => {
                    if (this.chooseSpeed !== item) {
                      this.chooseSpeed = item;
                      // Set the playback speed and update the UI.
                      player.setSpeed(this.chooseSpeed);
                      this.speedText = Const.VIDEO_SPEED_TEXT_ARR[index];
                      this.isSpeedListVisible = false;
                    }
                  })
                }
              }, (item: number, index: number) => {
                return 'item: ' + item.toString() + 'index: ' + index.toString();
              })
            }
            .width('100%')
            .height('100%')
            .stackFromEnd(true)
            .divider({
              strokeWidth: 0.1,
              color: '#EEEEEE',
              endMargin: 16,
              startMargin: 16
            })
          }
          .width(this.isFullScreen ? '180vp' : '120vp')
          .height('100%')
          .padding({ top: '16vp', bottom: '36vp' })
          .justifyContent(FlexAlign.End)
          .backgroundColor('#08ffffff')
          .onClick(() => {
            hilog.info(DOMAIN, TAG, 'click list');
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .visibility(this.isSpeedListVisible ? Visibility.Visible : Visibility.Hidden)
        .onClick(() => {
          if (this.isSpeedListVisible) {
            this.isSpeedListVisible = false;
          }
        })
      }
      .width('100%')
      .height(this.isFullScreen ? '100%' : '35%')

      Column() {
        Row() {
          Text($r('app.string.Video_name'))
            .fontSize('24fp')
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width('100%')
        .height('25%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: '20vp', right: '20vp' })

        Row() {
          Text($r('app.string.Episodes'))
            .fontSize('16fp')
            .fontWeight(FontWeight.Regular)
            .fontColor(Color.White)
        }
        .width('100%')
        .height('20%')
        .padding({ left: '20vp', right: '20vp' })

        Row() {
          List({ space: '16vp', initialIndex: 0 }) {
            ForEach(this.videoSources, (item: resourceManager.RawFileDescriptor, index: number) => {
              ListItem() {
                Column() {
                  Text((index + 1).toString())
                    .fontSize('20fp')
                    .fontColor(this.chooseNumber === index && this.isUse ? '#F67609' : '#FFFFFF')
                }
                .width(40)
                .height(40)
                .backgroundColor('#3B3A37')
                .borderRadius($r('sys.float.corner_radius_level5'))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderColor(this.chooseNumber === index && this.isUse ? '#F67609' : '#3B3A37')
                .borderWidth(1)
                .onClick(() => {
                  if (this.chooseNumber === index) {
                    return;
                  }
                  // Reset status.
                  this.isSwitchEnable = false;
                  this.durationTime = 0;
                  this.chooseNumber = index;
                  this.isUse = false;

                  // Read rawfile video source.
                  let rawDes = item;
                  if (!rawDes) {
                    hilog.error(DOMAIN, TAG, 'player inputFile is null');
                  }
                  // Switch video and change state after success.
                  player.switchVideo(rawDes!.fd, rawDes!.offset, rawDes!.length).then((data) => {
                    if (data.code === 0) {
                      player.play();
                      this.playState = PlayerState.PLAYING;
                      this.durationTime = data.durationTime / Const.TIME_RATIO;
                      this.isUse = true;
                    } else {
                      hilog.error(DOMAIN, TAG, 'player init failed, err code is ' + data.code);
                    }
                    this.isSwitchEnable = true;
                  })
                })
              }
            }, (item: resourceManager.RawFileDescriptor, index: number) => {
              return 'item: ' + item.toString() + 'index: ' + index.toString();
            })
          }
          .width('100%')
          .height('100%')
          .listDirection(Axis.Horizontal)
          .enabled(this.isSwitchEnable)
        }
        .width('100%')
        .height('30%')
        .padding({ left: '20vp', right: '20vp' })
      }
      .width('100%')
      .height('35%')
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [[0x1b1a1c, 0], [0x000000, 0.5]]
      })
      .visibility(this.isFullScreen ? Visibility.Hidden : Visibility.Visible)

      Blank()
        .width('100%')
        .height('55%')
        .backgroundColor(Color.Black)
        .visibility(this.isFullScreen ? Visibility.Hidden : Visibility.Visible)
    }
    .height('100%')
    .width('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}