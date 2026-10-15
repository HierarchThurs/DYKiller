// 从抖音模型抽取 DKMediaSelect 的输入字典。只读 KVC，取不到的字段视为缺失。
#ifndef DKMediaResolver_h
#define DKMediaResolver_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

id DKMediaValue(id object, NSString *key);
NSDictionary *DKResolveAweme(id aweme);
NSDictionary *DKResolveComment(id comment);
// 表情地址组：支持 AWEIMStickerModel / AWEIMEmoticonModel / AWEIMGiphyMessage / AWEIMSimilarEmojiDisplayModel。
NSArray<NSArray *> *DKResolveStickerURLGroups(id model);

#ifdef __cplusplus
}
#endif

#endif
