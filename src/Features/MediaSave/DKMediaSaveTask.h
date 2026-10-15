// 一次保存：逐项下载、校验、转换、写入相册，结束后给出结果提示与震动反馈。同一时间只运行一个任务。
#ifndef DKMediaSaveTask_h
#define DKMediaSaveTask_h

#import "DKMediaSaveItem.h"

#ifdef __cplusplus
extern "C" {
#endif

// source 只用于诊断。可在任意线程调用，内部切到主线程开始。
void DKMediaSaveRun(NSArray<DKMediaSaveItem *> *items, NSString *source);

#ifdef __cplusplus
}
#endif

#endif
