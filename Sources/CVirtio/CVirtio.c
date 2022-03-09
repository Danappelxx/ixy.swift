#include "CVirtio.h"
#ifdef __APPLE__
	static inline void mfence() {
		// noop
	}
#else
	#include <immintrin.h>
	static inline void mfence() {
		return _mm_mfence();
	}
#endif
