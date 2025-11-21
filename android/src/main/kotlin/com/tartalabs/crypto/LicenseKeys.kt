/*
 * Copyright (c) 2025.
 * David Chiu
 * Created:  "2025"
 */

package com.tartalabs.crypto

data class LicenseKeys(
    val userCode: String,         // e.g., "myapp.lic.userCode.v1"
    val shard: String,            // e.g., "myapp.lic.shard.v1"
    val deviceWrappedCek: String, // e.g., "myapp.lic.cek.devwrap.v1"  (IV||ct+tag)
    val deviceSeed: String        // e.g., "myapp.device.seed.v1"
)
