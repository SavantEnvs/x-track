// Shared by the GPX_Parser fuzz harness and the KAT probe: in-memory feed + stubs for the LVGL
// symbols that X-Track's Stream/WString utilities reference.
#include "Utils/GPX_Parser/GPX_Parser.h"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

struct Feed {
  const uint8_t *data;
  size_t size;
  size_t pos;
};

// Stream::timedRead() polls lv_tick_get() against a millisecond timeout when the source is
// exhausted. A deterministic monotonic stub (instead of the LVGL tick) keeps that bounded.
extern "C" uint32_t lv_tick_get(void) {
  static uint32_t tick;
  return ++tick;
}

// WString's allocator hooks (LVGL's lv_mem_*) mapped onto libc so ASan sees every String buffer.
extern "C" void lv_mem_free(void *p) { free(p); }
extern "C" void *lv_mem_realloc(void *p, size_t n) { return realloc(p, n); }
extern "C" void *lv_mem_alloc(size_t n) { return malloc(n); }

static inline int feedAvailable(GPX_Parser *p) {
  Feed *f = static_cast<Feed *>(p->userData);
  return static_cast<int>(f->size - f->pos);
}

static inline int feedRead(GPX_Parser *p) {
  Feed *f = static_cast<Feed *>(p->userData);
  return f->pos < f->size ? f->data[f->pos++] : -1;
}
