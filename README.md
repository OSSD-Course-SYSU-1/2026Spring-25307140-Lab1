# 基于Surface模式进行视频播放控制

### 介绍
本实例基于AVCodec能力，实现了Surface模式下的视频播控功能。通过调用Native侧的解码器和解封装功能，完成从视频解播放、暂停、调整视频播放进度、切换视频和倍速等功能。基于本实例可以帮助开发者理解和掌握Surface模式下的视频解码能力和解码流程管理。

### 效果预览

| 应用主界面                                              |
|----------------------------------------------------|
| ![AVCodec_Index.png](screenshots/device/Index.png) |

### 使用说明

1. 进入首页后，点击下方的选集按钮进行播放，播放中点击不同的选集可切换视频播放。
2. 播放界面中，点击左侧播放和暂停按钮可控制视频播放状态。
3. 滑动进度条可调整视频播放进度。
4. 点击倍速按钮可进行视频播放速度切换。
5. 点击全屏播放按钮可进行视频横向全屏播放。

### 工程目录

```       
├──entry/src/main/cpp                 // Native层
│     ├──capbilities                  // 系统解码能力
│     │  ├──include                
│     │  │  ├──AudioDecoder.h         // 音频解码能力接口
│     │  │  ├──CodecCallback.h        // 解码回调接口
│     │  │  ├──Demuxer.h              // 解封装能力接口       
│     │  │  └──VideoDecoder.h         // 视频解码能力接口
│     │  └──src
│     │     ├──AudioDecoder.cpp       // 音频解码能力实现
│     │     ├──CodecCallback.cpp      // 解码回调实现
│     │     ├──Demuxer.cpp            // 解封装能力实现       
│     │     └──VideoDecoder.cpp       // 视频解码能力实现
│     ├──common                       // 解码公共工具
│     │  └──include      
│     │     ├──AudioSampleInfo.h      // 音频解码数据信息   
│     │     ├──MediaError.h           // 异常转态枚举
│     │     ├──MediaLog.h             // 宏定义日志
│     │     ├──SampleInfo.h           // 解码数据信息
│     │     └──VideoSampleInfo.h      // 视频解码数据信息
│     ├──player                       // 视频解码业务
│     │  ├──include
│     │  │  ├──Player.h               // 视频解码播放和控制接口       
│     │  │  └──playerNative.h         // Native交互接口          
│     │  └──src
│     │     ├──Player.cpp             // 视频解码播放和控制实现  
│     │     └──PlayerNative.cpp       // Native交互实现
│     ├──render                       // 渲染上屏
│     │  ├──include  
│     │  │  ├──XComponentManager.h    // 渲染管理接口     
│     │  │  └──XComponentRender.h     // 渲染功能接口        
│     │  └──src
│     │     ├──XComponentManager.cpp  // 渲染管理实现    
│     │     └──XComponentRender.cpp   // 渲染功能实现     
│     ├──types                      
│     │  └──libplayer
│     │     └──Index.d.ts             // 暴露给上层的接口
│     └──CMakeLists.txt               // 编译入口
└──src/main/ets                       // ArkTS层
      ├──common  
      │  ├──CommonContants.ets        // 公共常量
      │  └──TimeUtils.ets             // 时间工具能力接口    
      ├──entryability  
      │  └──EntryAbility.ets 
      ├──entrybackupability  
      │  └──EntryBackupAbility.ets  
      ├──model
      │  └──PlayerStateModel.ets      // 视频状态枚举  
      ├──pages
      │  └──index.ets                 // 主页面          
      ├──view
      │  └──VideoPlayView.ets         // 视频播放自定义组件                
      └──viewmodel                    
         └──VideoPlayViewModel.ets    // 视频播放自定义组件UI驱动   
```

### 具体实现

1. 播放功能使用AVCodec能力，通过input和output子线程送入XComponent进行渲染显示。
2. 播放和暂停功能是通过阻塞子线程实现。
3. 播放速度通过改变音频渲染速度和音画同步实现。
4. 视频资源切换功能通过对当前解码器的释放和使用新视频资源创建解码器实现。
5. 视频进度调整功能是使用解封装器切换视频轨，通过系统seek能力切换到目标进度的上一个I帧实现。

### 相关权限

- 无

### 依赖

- 不涉及

### 约束与限制

1. 本示例仅支持标准系统上运行，支持设备：直板机。
2. HarmonyOS系统：HarmonyOS 6.0.2 Release及以上。
3. DevEco Studio版本：DevEco Studio 6.0.2 Release及以上。
4. HarmonyOS SDK版本：HarmonyOS 6.0.2 Release SDK及以上。