#include "DKShareImagePlate.h"
#include <stdlib.h>
#include <string.h>

static bool DKShareNeutralPixel(const uint8_t *p) {
    unsigned maximum = p[0], minimum = p[0];
    for (size_t c = 1; c < 3; c++) {
        if (p[c] > maximum) maximum = p[c];
        if (p[c] < minimum) minimum = p[c];
    }
    return p[3] >= 5 && (maximum - minimum) * 100 <= p[3] * 14;
}

static bool DKSharePlatePixel(const uint8_t *p, const uint8_t *plate) {
    if (p[3] < 5) return true;
    if (p[3] > plate[3] + 1) return false;
    for (size_t c = 0; c < 3; c++) {
        // 比较未预乘的颜色；允许两个色阶的解码取整差异。
        int difference = (int)p[c] * plate[3] - (int)plate[c] * p[3];
        if (abs(difference) * 255 > 2 * p[3] * plate[3]) return false;
    }
    return true;
}

bool DKShareRemoveImagePlate(uint8_t *pixels, size_t width, size_t height, size_t stride) {
    if (!pixels || !width || !height) return false;
    uint32_t candidate = 0;
    size_t votes = 0, eligible = 0, band = 0;
    size_t insetX = width / 4, insetY = height / 4;
    // 外周四分之一宽的区域用于识别底板；中心图标不参与候选投票。
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        if (x >= insetX && x < width - insetX && y >= insetY && y < height - insetY) continue;
        band++;
        uint8_t *p = pixels + y * stride + x * 4;
        if (!DKShareNeutralPixel(p)) continue;
        eligible++;
        uint32_t value;
        memcpy(&value, p, sizeof(value));
        if (!votes) candidate = value;
        if (candidate == value) votes++; else votes--;
    }
    if (!votes) return false;
    size_t matches = 0;
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        if (x >= insetX && x < width - insetX && y >= insetY && y < height - insetY) continue;
        uint32_t value;
        memcpy(&value, pixels + y * stride + x * 4, sizeof(value));
        if (value == candidate) matches++;
    }
    // 底板须在中性样本中占多数，并覆盖外周区域至少四分之一。
    if (matches * 2 <= eligible || matches * 4 < band) return false;
    uint8_t plate[4];
    memcpy(plate, &candidate, sizeof(plate));
    size_t count = width * height, head = 0, tail = 0;
    size_t *queue = malloc(count * sizeof(size_t));
    uint8_t *visited = calloc(count, 1);
    if (!queue || !visited) { free(queue); free(visited); return false; }
    // 从画布边缘向内遍历；与外缘隔开的同色细节不属于底板。
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        if (x && y && x + 1 < width && y + 1 < height) continue;
        size_t index = y * width + x;
        if (DKSharePlatePixel(pixels + y * stride + x * 4, plate)) {
            visited[index] = 1;
            queue[tail++] = index;
        }
    }
    bool removed = false;
    while (head < tail) {
        size_t index = queue[head++], x = index % width, y = index / width;
        uint8_t *p = pixels + y * stride + x * 4;
        if (p[3]) removed = true;
        memset(p, 0, 4);
        size_t neighbors[4] = { x ? index - 1 : index, x + 1 < width ? index + 1 : index,
                                y ? index - width : index, y + 1 < height ? index + width : index };
        for (size_t n = 0; n < 4; n++) {
            size_t next = neighbors[n];
            if (visited[next]) continue;
            visited[next] = 1;
            if (DKSharePlatePixel(pixels + (next / width) * stride + (next % width) * 4, plate)) queue[tail++] = next;
        }
    }
    free(queue);
    free(visited);
    return removed;
}
