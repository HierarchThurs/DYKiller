#import "DKColorHex.h"

static NSString *DKColorHexCanonical(id raw, BOOL keepAlpha) {
    if (![raw isKindOfClass:NSString.class]) return nil;
    NSString *hex = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 3 && hex.length != 6 && hex.length != 8) return nil;
    for (NSUInteger index = 0; index < hex.length; index++) {
        unichar c = [hex characterAtIndex:index];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return nil;
    }
    if (hex.length == 3) {
        NSMutableString *expanded = [NSMutableString stringWithCapacity:6];
        for (NSUInteger index = 0; index < 3; index++) {
            [expanded appendFormat:@"%C%C", [hex characterAtIndex:index], [hex characterAtIndex:index]];
        }
        hex = expanded;
    }
    if (keepAlpha) {
        if (hex.length == 6) hex = [@"FF" stringByAppendingString:hex];
        return [@"#" stringByAppendingString:hex.uppercaseString];
    }
    if (hex.length == 8) hex = [hex substringFromIndex:2];
    return [@"#" stringByAppendingString:hex.uppercaseString];
}

NSString *DKColorHexNormalize(id raw) {
    return DKColorHexCanonical(raw, NO);
}

NSString *DKColorHexNormalizeAlpha(id raw) {
    return DKColorHexCanonical(raw, YES);
}

static NSString *DKColorHexScheme(id raw, BOOL gradient, BOOL keepAlpha, NSString **reason) {
    NSString *failure = nil;
    if (![raw isKindOfClass:NSString.class]) failure = @"类型不符";
    else if ([raw rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) failure = @"包含换行或控制字符";
    if (failure) { if (reason) *reason = failure; return nil; }
    NSArray *parts = [raw componentsSeparatedByString:@","];
    if (gradient ? (parts.count < 2 || parts.count > 8) : parts.count != 1) {
        if (reason) *reason = gradient ? @"渐变需包含 2–8 个颜色" : @"固定颜色只能包含一个颜色";
        return nil;
    }
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        NSString *hex = DKColorHexCanonical(part, keepAlpha);
        if (!hex) { if (reason) *reason = @"请输入 3、6 或 8 位十六进制颜色"; return nil; }
        [colors addObject:hex];
    }
    return [colors componentsJoinedByString:@","];
}

NSString *DKColorHexNormalizeSchemeAlpha(id raw, BOOL gradient, NSString **reason) {
    return DKColorHexScheme(raw, gradient, YES, reason);
}

NSString *DKColorHexNormalizeScheme(id raw, BOOL gradient, NSString **reason) {
    return DKColorHexScheme(raw, gradient, NO, reason);
}
