#ifndef REVOX_RING_ATOMICS_H
#define REVOX_RING_ATOMICS_H

#include <stdint.h>

/// Acquire load of the 8-byte-aligned 64-bit ring cursor at `pointer` (design spec §5.9 ordering rules).
uint64_t revox_ring_load_cursor(const void *pointer);

/// Release store of `value` into the 8-byte-aligned 64-bit ring cursor at `pointer`.
void revox_ring_store_cursor(void *pointer, uint64_t value);

#endif
