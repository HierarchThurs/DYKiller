// 公共更新链只在最外层提交颜色，避免子类调用 super 时重复分配随机方案。
// 功能关闭且条目 / Label 上没有本功能状态时，全部直接走原生。
#import "DKDanmakuColor.h"

%hook AWEDanmakuItemCommonView
- (void)updateWithDescriptor:(id)descriptor {
    if (!DKDanmakuViewEngaged(self)) { %orig; return; }
    DKDanmakuBeginEntry(self, descriptor);
    @try { %orig; } @finally { DKDanmakuEndUpdate(self); }
}
- (void)updateDanmaKuUnitView {
    if (!DKDanmakuViewEngaged(self)) { %orig; return; }
    DKDanmakuBeginUpdate(self, NO);
    @try { %orig; } @finally { DKDanmakuEndUpdate(self); }
}
- (void)prepareForReuse {
    if (DKDanmakuViewEngaged(self)) DKDanmakuResetView(self);
    %orig;
}
- (void)didMoveToWindow {
    %orig;
    if (DKDanmakuViewEngaged(self)) DKDanmakuTrackView(self);
}
%end

%hook AWEDanmakuItemAuthorView
- (void)updateWithDescriptor:(id)descriptor {
    if (!DKDanmakuViewEngaged(self)) { %orig; return; }
    DKDanmakuBeginEntry(self, descriptor);
    @try { %orig; } @finally { DKDanmakuEndUpdate(self); }
}
%end

%hook AWEDanmakuItemActivityView
- (void)updateWithDescriptor:(id)descriptor {
    if (!DKDanmakuViewEngaged(self)) { %orig; return; }
    DKDanmakuBeginEntry(self, descriptor);
    @try { %orig; } @finally { DKDanmakuEndUpdate(self); }
}
%end

%hook AWEDanmakuItemAdView
- (void)updateWithDescriptor:(id)descriptor {
    if (!DKDanmakuViewEngaged(self)) { %orig; return; }
    DKDanmakuBeginEntry(self, descriptor);
    @try { %orig; } @finally { DKDanmakuEndUpdate(self); }
}
%end

%hook AWEDanmakuDiggNumView
- (void)updateDiggImageAndDiggLabel {
    AWEDanmakuItemCommonView *owner = DKDanmakuDiggOwner(self);
    if (!owner || !DKDanmakuViewEngaged(owner)) { %orig; return; }
    DKDanmakuBeginUpdate(owner, NO);
    @try { %orig; } @finally { DKDanmakuEndUpdate(owner); }
}
- (void)configDanmakuDiggImageWithModel:(id)model {
    AWEDanmakuItemCommonView *owner = DKDanmakuDiggOwner(self);
    if (!owner || !DKDanmakuViewEngaged(owner)) { %orig; return; }
    DKDanmakuBeginUpdate(owner, NO);
    @try { %orig; } @finally { DKDanmakuEndUpdate(owner); }
}
- (void)updateLayOutIfNeed {
    AWEDanmakuItemCommonView *owner = DKDanmakuDiggOwner(self);
    if (!owner || !DKDanmakuViewEngaged(owner)) { %orig; return; }
    DKDanmakuBeginUpdate(owner, NO);
    @try { %orig; } @finally { DKDanmakuEndUpdate(owner); }
}
- (void)layoutSubviews {
    %orig;
    AWEDanmakuItemCommonView *owner = DKDanmakuDiggOwner(self);
    if (owner && DKDanmakuViewEngaged(owner)) DKDanmakuLayoutDigg(self);
}
%end

%hook AWEDanmakuContentLabel
- (void)setTextColor:(UIColor *)color {
    if (!DKDanmakuLabelEngaged(self) || DKDanmakuOwnWrite(self)) { %orig; return; }
    DKDanmakuNativeWriteBegin(self);
    @try { %orig; } @finally { DKDanmakuNativeWriteFinished(self); }
}
- (void)setAttributedText:(NSAttributedString *)text {
    if (!DKDanmakuLabelEngaged(self) || DKDanmakuOwnWrite(self)) { %orig; return; }
    DKDanmakuNativeWriteBegin(self);
    @try { %orig; } @finally { DKDanmakuNativeWriteFinished(self); }
}
- (void)setText:(NSString *)text {
    if (!DKDanmakuLabelEngaged(self) || DKDanmakuOwnWrite(self)) { %orig; return; }
    DKDanmakuNativeWriteBegin(self);
    @try { %orig; } @finally { DKDanmakuNativeWriteFinished(self); }
}
- (void)setStrokeWidth:(double)width {
    if (!DKDanmakuLabelEngaged(self) || DKDanmakuOwnWrite(self)) { %orig; return; }
    DKDanmakuNativeWriteBegin(self);
    @try { %orig; } @finally { DKDanmakuNativeWriteFinished(self); }
}
- (void)setStrokeColor:(UIColor *)color {
    if (!DKDanmakuLabelEngaged(self) || DKDanmakuOwnWrite(self)) { %orig; return; }
    DKDanmakuNativeWriteBegin(self);
    @try { %orig; } @finally { DKDanmakuNativeWriteFinished(self); }
}
- (void)drawTextInRect:(CGRect)rect {
    if (!DKDanmakuLabelEngaged(self)) { %orig; return; }
    DKDanmakuBeginDraw(self);
    @try { %orig; } @finally { DKDanmakuEndDraw(self); }
}
%end
