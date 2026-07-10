# DYKiller
| 测试版本 39.5.0
## 现有功能

- 聊天页视频全屏：竖屏视频画面填满整屏，HUD 保持原有层级。
- 移除聊天页视频底栏：隐藏底部快捷回复栏并禁用交互。
- 移除关注按钮：隐藏右侧头像下方的关注加号并禁用点击。
- 调试工具：通过设置开关启用全局调试入口，支持运行时信息导出。

## 项目架构


```text
DYKiller/             
├── DYKiller.plist             
├── Makefile                   
├── control                    
└── src/
    ├── Debug/                 # 调试入口、运行时信息采集与导出
    │   ├── DKDebugCapture.h
    │   ├── DKDebugCapture.m
    │   ├── DKDebugEntry.xm
    │   ├── DKDebugExport.h
    │   ├── DKDebugExport.m
    │   ├── DKDebugInspector.h
    │   └── DKDebugInspector.m
    ├── FLEX/                  # 调试导出所需的压缩与类信息辅助工具
    │   ├── DKClassDump.h
    │   ├── DKClassDump.m
    │   ├── DKZipWriter.h
    │   └── DKZipWriter.m
    ├── Features/              # 独立功能实现
    │   ├── ChatVideo/
    │   │   ├── DKChatVideoBottomBar.xm
    │   │   └── DKChatVideoFullscreen.xm
    │   └── Interaction/
    │       └── DKHideFollowButton.xm
    ├── Headers/               # 抖音私有类前向声明与必要接口声明
    │   └── DouyinHeaders.h
    ├── Settings/              # 抖音设置入口注入与功能开关注册框架
    │   ├── DKSettings.h
    │   └── DKSettingsMenu.xm
    └── Shared/                # 共享开关、版本宏与无状态工具函数
        ├── DKKeys.h
        ├── DKUtils.h
        └── DKUtils.m
```


## 致谢

### 作者

- @huami1314
- @pxx917144686
- @Wtrwx

### 项目

- [github.com/Wtrwx/DYYY](https://github.com/Wtrwx/DYYY)
- [github.com/huami1314/DYYY](https://github.com/huami1314/DYYY)
- pxx917144686 的 DYYY++ 项目
- pxx917144686 的 FLEX++ 项目

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

Copyright (c) 2026 Hierarch, huami1314, pxx917144686, Wtrwx
