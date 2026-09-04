#include "RingAtomics.h"

#include <stdatomic.h>

uint64_t revox_ring_load_cursor(const void *pointer) {
    return atomic_load_explicit((const _Atomic uint64_t *)pointer, memory_order_acquire);
}

void revox_ring_store_cursor(void *pointer, uint64_t value) {
    atomic_store_explicit((_Atomic uint64_t *)pointer, value, memory_order_release);
}
