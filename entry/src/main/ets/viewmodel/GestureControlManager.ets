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
import { audio } from '@kit.AudioKit';

const DOMAIN = 0xFF00;
const TAG = 'GestureControlManager';

/**
 * 手势类型枚举
 */
export enum GestureType {
  NONE = 'none',
  BRIGHTNESS = 'brightness',
  VOLUME = 'volume'
}

/**
 * 手势控制回调接口
 */
export interface GestureControlCallback {
  onBrightnessChange?(value: number): void;
  onVolumeChange?(value: number): void;
  onGestureStart?(type: GestureType): void;
  onGestureEnd?(): void;
}

/**
 * 手势控制回调实现类
 */
export class GestureControlCallbackImpl implements GestureControlCallback {
  private brightnessChangeCallback?: (value: number) => void;
  private volumeChangeCallback?: (value: number) => void;
  private gestureStartCallback?: (type: GestureType) => void;
  private gestureEndCallback?: () => void;
  
  constructor(
    brightnessChange?: (value: number) => void,
    volumeChange?: (value: number) => void,
    gestureStart?: (type: GestureType) => void,
    gestureEnd?: () => void
  ) {
    this.brightnessChangeCallback = brightnessChange;
    this.volumeChangeCallback = volumeChange;
    this.gestureStartCallback = gestureStart;
    this.gestureEndCallback = gestureEnd;
  }
  
  onBrightnessChange(value: number): void {
    if (this.brightnessChangeCallback) {
      this.brightnessChangeCallback(value);
    }
  }
  
  onVolumeChange(value: number): void {
    if (this.volumeChangeCallback) {
      this.volumeChangeCallback(value);
    }
  }
  
  onGestureStart(type: GestureType): void {
    if (this.gestureStartCallback) {
      this.gestureStartCallback(type);
    }
  }
  
  onGestureEnd(): void {
    if (this.gestureEndCallback) {
      this.gestureEndCallback();
    }
  }
}

/**
 * 手势控制管理器
 * 负责处理横屏时的亮度和音量手势调节
 */
export class GestureControlManager {
  private static instance: GestureControlManager;
  private context: Context | undefined = undefined;
  private callback: GestureControlCallback | undefined = undefined;
  
  // 当前亮度值 (0.0 - 1.0)
  private currentBrightness: number = 0.5;
  // 当前音量值 (0.0 - 1.0)
  private currentVolume: number = 0.5;
  
  // 手势状态
  private gestureType: GestureType = GestureType.NONE;
  private startY: number = 0;
  private isGestureActive: boolean = false;
  
  // 音量管理器
  private audioVolumeManager: audio.AudioVolumeManager | null = null;
  private volumeMin: number = 0;
  private volumeMax: number = 15;
  
  // 手势灵敏度系数
  private readonly SENSITIVITY: number = 0.002;
  // 最小滑动距离阈值
  private readonly MIN_SWIPE_DISTANCE: number = 10;
  
  static getInstance(): GestureControlManager {
    if (!GestureControlManager.instance) {
      GestureControlManager.instance = new GestureControlManager();
    }
    return GestureControlManager.instance;
  }
  
  /**
   * 初始化手势控制管理器
   */
  async initialize(context: Context, callback: GestureControlCallback): Promise<void> {
    this.context = context;
    this.callback = callback;
    
    try {
      // 初始化音量管理器
      const audioManager = audio.getAudioManager();
      this.audioVolumeManager = audioManager.getVolumeManager();
      
      // 获取音量范围
      this.volumeMin = this.audioVolumeManager.getMinVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.volumeMax = this.audioVolumeManager.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      
      // 获取当前音量
      const currentVol = this.audioVolumeManager.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.currentVolume = currentVol / this.volumeMax;
      
      // 监听系统音量变化
      const volumeCallback = (volumeEvent: audio.VolumeEvent) => {
        // 只处理媒体音量类型的变化
        if (volumeEvent.volumeType === audio.AudioVolumeType.MEDIA) {
          this.currentVolume = volumeEvent.volume / this.volumeMax;
          if (this.callback?.onVolumeChange) {
            this.callback.onVolumeChange(this.currentVolume);
          }
        }
      };
      this.audioVolumeManager.on('volumeChange', volumeCallback);
      
      // 获取当前亮度
      await this.initBrightness();
      
      hilog.info(DOMAIN, TAG, `GestureControlManager initialized. Brightness: ${this.currentBrightness}, Volume: ${this.currentVolume}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to initialize: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 初始化亮度
   */
  private async initBrightness(): Promise<void> {
    if (!this.context) {
      return;
    }
    
    try {
      const topWindow = await window.getLastWindow(this.context);
      const properties = topWindow.getWindowProperties();
      this.currentBrightness = properties.brightness;
      
      // 如果亮度为-1（跟随系统），设置为默认值0.5
      if (this.currentBrightness < 0) {
        this.currentBrightness = 0.5;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get brightness: ${JSON.stringify(error)}`);
      this.currentBrightness = 0.5;
    }
  }
  
  /**
   * 处理触摸开始事件
   * @param x 触摸点X坐标
   * @param y 触摸点Y坐标
   * @param screenWidth 屏幕宽度
   * @param isFullScreen 是否全屏
   */
  onTouchStart(x: number, y: number, screenWidth: number, isFullScreen: boolean): void {
    if (!isFullScreen) {
      return;
    }
    
    this.startY = y;
    this.isGestureActive = true;
    
    // 判断触摸区域：左半屏调节亮度，右半屏调节音量
    if (x < screenWidth / 2) {
      this.gestureType = GestureType.BRIGHTNESS;
    } else {
      this.gestureType = GestureType.VOLUME;
    }
    
    if (this.callback?.onGestureStart) {
      this.callback.onGestureStart(this.gestureType);
    }
    
    hilog.info(DOMAIN, TAG, `Touch start at (${x}, ${y}), type: ${this.gestureType}`);
  }
  
  /**
   * 处理触摸移动事件
   * @param y 触摸点Y坐标
   */
  onTouchMove(y: number): void {
    if (!this.isGestureActive || this.gestureType === GestureType.NONE) {
      return;
    }
    
    const deltaY = y - this.startY;
    
    // 忽略太小的移动
    if (Math.abs(deltaY) < this.MIN_SWIPE_DISTANCE) {
      return;
    }
    
    // 计算变化值（向上滑动增加，向下滑动减少）
    const delta = -deltaY * this.SENSITIVITY;
    
    if (this.gestureType === GestureType.BRIGHTNESS) {
      this.adjustBrightness(delta);
    } else if (this.gestureType === GestureType.VOLUME) {
      this.adjustVolume(delta);
    }
    
    // 更新起始位置，实现连续调节
    this.startY = y;
  }
  
  /**
   * 处理触摸结束事件
   */
  onTouchEnd(): void {
    if (this.isGestureActive) {
      this.isGestureActive = false;
      this.gestureType = GestureType.NONE;
      
      if (this.callback?.onGestureEnd) {
        this.callback.onGestureEnd();
      }
      
      hilog.info(DOMAIN, TAG, 'Touch end');
    }
  }
  
  /**
   * 调节亮度
   */
  private async adjustBrightness(delta: number): Promise<void> {
    if (!this.context) {
      return;
    }
    
    try {
      // 计算新亮度值
      let newBrightness = this.currentBrightness + delta;
      newBrightness = Math.max(0.0, Math.min(1.0, newBrightness));
      
      // 设置亮度
      const topWindow = await window.getLastWindow(this.context);
      await topWindow.setWindowBrightness(newBrightness);
      
      this.currentBrightness = newBrightness;
      
      if (this.callback?.onBrightnessChange) {
        this.callback.onBrightnessChange(this.currentBrightness);
      }
      
      hilog.debug(DOMAIN, TAG, `Brightness adjusted to: ${this.currentBrightness}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to adjust brightness: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 调节音量
   */
  private adjustVolume(delta: number): void {
    if (!this.audioVolumeManager) {
      return;
    }
    
    try {
      // 计算新音量值
      let newVolume = this.currentVolume + delta;
      newVolume = Math.max(0.0, Math.min(1.0, newVolume));
      
      // 转换为系统音量等级
      const volumeLevel = Math.round(newVolume * this.volumeMax);
      
      // 使用AVVolumePanel调节系统音量
      // 注意：这里我们通过改变currentVolume来触发UI更新
      // 实际的音量调节需要通过AVVolumePanel组件
      this.currentVolume = newVolume;
      
      if (this.callback?.onVolumeChange) {
        this.callback.onVolumeChange(this.currentVolume);
      }
      
      hilog.debug(DOMAIN, TAG, `Volume adjusted to: ${this.currentVolume}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to adjust volume: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 获取当前亮度
   */
  getCurrentBrightness(): number {
    return this.currentBrightness;
  }
  
  /**
   * 获取当前音量
   */
  getCurrentVolume(): number {
    return this.currentVolume;
  }
  
  /**
   * 获取当前手势类型
   */
  getGestureType(): GestureType {
    return this.gestureType;
  }
  
  /**
   * 是否正在手势操作中
   */
  isGestureInProgress(): boolean {
    return this.isGestureActive;
  }
  
  /**
   * 清理资源
   */
  cleanup(): void {
    if (this.audioVolumeManager) {
      this.audioVolumeManager.off('volumeChange');
      this.audioVolumeManager = null;
    }
    this.context = undefined;
    this.callback = undefined;
    this.isGestureActive = false;
    this.gestureType = GestureType.NONE;
    
    hilog.info(DOMAIN, TAG, 'GestureControlManager cleaned up');
  }
}
