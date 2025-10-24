import std/[json, os, times, tables, md5, options]
import types

proc getCacheDir*(): string =
  let home = getEnv("HOME")
  result = home / ".cache" / "heads-up-claude"
  if not dirExists(result):
    createDir(result)

proc getCacheKey*(filePath: string, modTime: Time): string =
  result = getMD5(filePath & $modTime.toUnix())

proc loadCache*(): Table[string, FileCache] =
  result = initTable[string, FileCache]()
  let cacheFile = getCacheDir() / "file-cache.json"
  if not fileExists(cacheFile):
    return

  try:
    let cacheData = parseJson(readFile(cacheFile))
    for key, val in cacheData.pairs:
      var cache = FileCache()
      cache.modTime = fromUnix(val["modTime"].getInt())
      cache.contextTokens = val.getOrDefault("contextTokens").getInt()
      cache.cacheReadTokens = val.getOrDefault("cacheReadTokens").getInt()
      cache.apiTokens = val.getOrDefault("apiTokens").getInt()
      cache.messageCount = val.getOrDefault("messageCount").getInt()
      if val.hasKey("firstTimestamp") and val["firstTimestamp"].kind != JNull:
        let ts = val["firstTimestamp"].getStr()
        cache.firstTimestamp = some(parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))
      else:
        cache.firstTimestamp = none(DateTime)
      if val.hasKey("lastTimestamp") and val["lastTimestamp"].kind != JNull:
        let ts = val["lastTimestamp"].getStr()
        cache.lastTimestamp = some(parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))
      else:
        cache.lastTimestamp = none(DateTime)
      result[key] = cache
  except:
    discard

proc saveCache*(cache: Table[string, FileCache]) =
  let cacheFile = getCacheDir() / "file-cache.json"
  var cacheData = newJObject()

  for key, val in cache.pairs:
    var entry = newJObject()
    entry["modTime"] = newJInt(val.modTime.toUnix())
    entry["contextTokens"] = newJInt(val.contextTokens)
    entry["cacheReadTokens"] = newJInt(val.cacheReadTokens)
    entry["apiTokens"] = newJInt(val.apiTokens)
    entry["messageCount"] = newJInt(val.messageCount)
    if val.firstTimestamp.isSome:
      entry["firstTimestamp"] = newJString(format(val.firstTimestamp.get(), "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"))
    else:
      entry["firstTimestamp"] = newJNull()
    if val.lastTimestamp.isSome:
      entry["lastTimestamp"] = newJString(format(val.lastTimestamp.get(), "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"))
    else:
      entry["lastTimestamp"] = newJNull()
    cacheData[key] = entry

  try:
    writeFile(cacheFile, $cacheData)
  except:
    discard
