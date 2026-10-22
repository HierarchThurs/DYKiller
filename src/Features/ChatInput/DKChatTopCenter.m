//
//  DKChatTopCenter.m
//  DYKiller
//

#import "DKChatTopCenter.h"

const CGFloat kDKChatTopAvatarSide = 52.0;

static const CGFloat kDKChatTopCenterGap = 8.0;       // 胶囊之间、胶囊与屏幕边
static const CGFloat kDKChatTopAvatarLift = 2.0;
static const CGFloat kDKChatTopCapsuleOverlap = 2.0;
static const CGFloat kDKChatTopLineSpacing = 2.0;
static const CGFloat kDKChatTopCenterPadding = 12.0;  // 名称胶囊左右留白
static const CGFloat kDKChatTopSidePadding = 8.0;     // 两侧胶囊左右留白
static const CGFloat kDKChatTopSideInset = 2.0;       // 两侧胶囊内容的最小上下留白
static const CGFloat kDKChatTopCardRadius = 18.0;     // 多行名称胶囊的圆角
static const CGFloat kDKChatTopMinimumScale = 0.1;

static BOOL DKChatTopPieceExists(const DKChatTopPiece *piece) {
    return piece->size.width > 0.0 && piece->size.height > 0.0;
}

// 一侧的胶囊：各项上下排列、水平居中；内容放不下时整体等比缩小，否则保持原尺寸。
static CGRect DKChatTopSideCapsule(DKChatTopPiece *pieces[], NSUInteger count, CGRect row,
                                   CGFloat minX, CGFloat maxX, BOOL alignRight) {
    if (!count) return CGRectNull;
    CGFloat width = 0.0, height = (count - 1) * kDKChatTopLineSpacing;
    for (NSUInteger i = 0; i < count; i++) {
        width = MAX(width, pieces[i]->size.width);
        height += pieces[i]->size.height;
    }
    CGFloat room = MAX(0.0, maxX - minX);
    CGFloat scale = MIN((room - kDKChatTopSidePadding * 2.0) / width,
                        (CGRectGetHeight(row) - kDKChatTopSideInset * 2.0) / height);
    scale = MAX(kDKChatTopMinimumScale, MIN(1.0, scale));
    CGFloat capsuleWidth = MIN(room, width * scale + kDKChatTopSidePadding * 2.0);
    CGRect capsule = CGRectMake(alignRight ? maxX - capsuleWidth : minX, CGRectGetMinY(row),
                                capsuleWidth, CGRectGetHeight(row));
    CGFloat y = CGRectGetMidY(row) - height * scale * 0.5;
    for (NSUInteger i = 0; i < count; i++) {
        pieces[i]->scale = scale;
        pieces[i]->center = CGPointMake(CGRectGetMidX(capsule), y + pieces[i]->size.height * scale * 0.5);
        y += (pieces[i]->size.height + kDKChatTopLineSpacing) * scale;
    }
    return capsule;
}

DKChatTopCenterFrames DKChatTopCenterFramesMake(DKChatTopCenterSpec spec) {
    DKChatTopCenterFrames frames = {0};
    frames.streak = spec.streak;
    frames.online = spec.online;
    CGRect row = spec.row;
    CGFloat side = spec.avatarSide;
    CGFloat avatarY = side > CGRectGetHeight(row) ? CGRectGetMinY(row) - kDKChatTopAvatarLift
                                                  : CGRectGetMidY(row) - side * 0.5;
    frames.avatar = CGRectMake(CGRectGetMidX(row) - side * 0.5, avatarY, side, side);

    DKChatTopPiece *pieces[] = { &frames.streak, &frames.online };
    DKChatTopPiece *center[2], *left[2], *right[2];
    NSUInteger centerCount = 0, leftCount = 0, rightCount = 0;
    for (NSUInteger i = 0; i < 2; i++) {
        DKChatTopPiece *piece = pieces[i];
        piece->scale = 1.0;
        piece->center = CGPointZero;
        if (!DKChatTopPieceExists(piece)) continue;
        if (piece->place == DKChatTopPlaceLeft) left[leftCount++] = piece;
        else if (piece->place == DKChatTopPlaceRight) right[rightCount++] = piece;
        else center[centerCount++] = piece;
    }

    // 名称胶囊：名称一行在上，居中项依次在下。
    CGFloat padding = centerCount ? 6.0 : 4.5;
    CGFloat height = spec.name.height + padding * 2.0;
    CGFloat width = spec.name.width;
    for (NSUInteger i = 0; i < centerCount; i++) {
        height += center[i]->size.height + kDKChatTopLineSpacing;
        width = MAX(width, center[i]->size.width);
    }
    width = MIN(width + kDKChatTopCenterPadding * 2.0, CGRectGetWidth(row) - kDKChatTopCenterGap * 2.0);
    frames.capsule = CGRectMake(CGRectGetMidX(row) - width * 0.5, CGRectGetMaxY(frames.avatar) - kDKChatTopCapsuleOverlap,
                                width, height);
    frames.capsuleRadius = centerCount ? MIN(kDKChatTopCardRadius, height * 0.5) : height * 0.5;
    CGFloat y = CGRectGetMinY(frames.capsule) + padding;
    frames.nameCenter = CGPointMake(CGRectGetMidX(frames.capsule), y + spec.name.height * 0.5);
    y += spec.name.height + kDKChatTopLineSpacing;
    for (NSUInteger i = 0; i < centerCount; i++) {
        center[i]->center = CGPointMake(CGRectGetMidX(frames.capsule), y + center[i]->size.height * 0.5);
        y += center[i]->size.height + kDKChatTopLineSpacing;
    }

    frames.left = DKChatTopSideCapsule(left, leftCount, row, spec.leftEdge,
                                       CGRectGetMinX(frames.avatar) - kDKChatTopCenterGap, NO);
    frames.right = DKChatTopSideCapsule(right, rightCount, row,
                                        CGRectGetMaxX(frames.avatar) + kDKChatTopCenterGap, spec.rightEdge, YES);
    return frames;
}
