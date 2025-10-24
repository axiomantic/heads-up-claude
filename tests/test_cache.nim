import unittest
import std/[times, tables, json, options]
import std/os except getCacheDir
import ../src/types
import ../src/cache

suite "Cache Module":
  setup:
    let testCacheDir = getTempDir() / "heads-up-claude-test-cache"
    if dirExists(testCacheDir):
      removeDir(testCacheDir)

  teardown:
    let testCacheDir = getTempDir() / "heads-up-claude-test-cache"
    if dirExists(testCacheDir):
      removeDir(testCacheDir)

  test "getCacheDir creates directory if it doesn't exist":
    let originalHome = getEnv("HOME")
    let testHome = getTempDir() / "test-home"
    putEnv("HOME", testHome)

    let cacheDir = getCacheDir()
    check dirExists(cacheDir)
    check cacheDir == testHome / ".cache" / "heads-up-claude"

    putEnv("HOME", originalHome)
    if dirExists(testHome):
      removeDir(testHome)

  test "getCacheKey generates consistent keys":
    let filePath = "/test/file.jsonl"
    let modTime = fromUnix(1234567890)

    let key1 = getCacheKey(filePath, modTime)
    let key2 = getCacheKey(filePath, modTime)

    check key1 == key2
    check key1.len > 0

  test "getCacheKey generates different keys for different files":
    let modTime = fromUnix(1234567890)

    let key1 = getCacheKey("/test/file1.jsonl", modTime)
    let key2 = getCacheKey("/test/file2.jsonl", modTime)

    check key1 != key2

  test "loadCache returns empty table when cache doesn't exist":
    let originalHome = getEnv("HOME")
    let testHome = getTempDir() / "test-home-nocache"
    putEnv("HOME", testHome)

    let cache = loadCache()
    check cache.len == 0

    putEnv("HOME", originalHome)
    if dirExists(testHome):
      removeDir(testHome)

  test "saveCache and loadCache round-trip":
    let originalHome = getEnv("HOME")
    let testHome = getTempDir() / "test-home-roundtrip"
    putEnv("HOME", testHome)

    var cache = initTable[string, FileCache]()

    var fc = FileCache()
    fc.modTime = fromUnix(1234567890)
    fc.contextTokens = 1000
    fc.cacheReadTokens = 500
    fc.apiTokens = 1500
    fc.messageCount = 10
    fc.firstTimestamp = some(parse("2025-01-01T00:00:00.000Z", "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))
    fc.lastTimestamp = some(parse("2025-01-01T01:00:00.000Z", "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))

    cache["test-key"] = fc

    saveCache(cache)

    let loadedCache = loadCache()
    check loadedCache.len == 1
    check loadedCache.hasKey("test-key")

    let loaded = loadedCache["test-key"]
    check loaded.contextTokens == 1000
    check loaded.cacheReadTokens == 500
    check loaded.apiTokens == 1500
    check loaded.messageCount == 10
    check loaded.firstTimestamp.isSome
    check loaded.lastTimestamp.isSome

    putEnv("HOME", originalHome)
    if dirExists(testHome):
      removeDir(testHome)
