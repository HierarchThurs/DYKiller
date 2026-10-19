#ifndef DKShareImagePlate_h
#define DKShareImagePlate_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 从预乘 RGBA 图片中移除与外缘连通的中性底板，保留独立的图标前景。
bool DKShareRemoveImagePlate(uint8_t *pixels, size_t width, size_t height, size_t stride);

#ifdef __cplusplus
}
#endif
#endif
