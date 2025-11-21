package com.tartalabs.crypto


interface SecretStore {
    fun put(key: String, value: ByteArray)
    fun get(key: String): ByteArray?
    fun remove(key: String)
}
