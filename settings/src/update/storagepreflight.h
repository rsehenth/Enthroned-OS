/*
 * Enthroned Settings - storage preflight decision (Lote 9.2, H4-001).
 * Pure decision over measured QStorageInfo facts, kept out of the engine so
 * the compiled smoke test can exercise valid, ready, unavailable and
 * insufficient volumes without touching a real filesystem. QStorageInfo has
 * no exists(): validity is isValid()/isReady() and an undeterminable size
 * (bytesAvailable() < 0) is an explicit unreadable outcome, never a pass.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QtGlobal>

namespace Enthroned {

enum class StoragePreflight {
    Ok,           // volume measured and above the minimum free space
    Insufficient, // volume measured and below the minimum free space
    Unreadable    // volume absent, not ready, or size could not be determined
};

inline StoragePreflight storagePreflightCheck(bool isValid, bool isReady,
                                              qint64 bytesAvailable, qint64 minBytes)
{
    if (!isValid || !isReady || bytesAvailable < 0) {
        return StoragePreflight::Unreadable;
    }
    return bytesAvailable < minBytes ? StoragePreflight::Insufficient
                                     : StoragePreflight::Ok;
}

} // namespace Enthroned
