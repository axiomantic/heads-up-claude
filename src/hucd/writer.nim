## Atomic file writing utilities for daemon

import std/[os, json, times, tables]
import ../shared/types

proc atomicWriteJson*(path: string, data: JsonNode) =
  ## Write JSON to file atomically using tmp+rename pattern
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  try:
    writeFile(tmpPath, pretty(data))
    moveFile(tmpPath, path)
  except Exception as e:
    # Cleanup tmp file on failure
    try:
      removeFile(tmpPath)
    except:
      discard
    raise e

proc writeStatus*(cacheDir: string, status: Status) =
  ## Write status.json to cache directory
  let statusPath = cacheDir / "status.json"
  let statusJson = status.toJson()
  atomicWriteJson(statusPath, statusJson)
  log(DEBUG, "Wrote status to " & statusPath)

proc loadTranscriptCache*(cacheDir: string): TranscriptCache =
  ## Load transcripts.json from cache directory if it exists
  let cachePath = cacheDir / "transcripts.json"
  result = TranscriptCache(
    version: 1,
    lastPruned: now().utc(),
    transcripts: initTable[string, TranscriptEntry](),
    dirMtimes: initTable[string, Time]()
  )

  if not fileExists(cachePath):
    log(DEBUG, "No transcript cache found at " & cachePath)
    return

  try:
    let content = readFile(cachePath)
    let j = parseJson(content)
    if j.isNil:
      log(WARN, "Failed to parse transcript cache")
      return

    result.version = j.getOrDefault("version").getInt(1)
    let lastPrunedStr = j.getOrDefault("last_pruned").getStr("")
    if lastPrunedStr.len > 0:
      result.lastPruned = parse(lastPrunedStr, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())

    let transcripts = j.getOrDefault("transcripts")
    if transcripts.kind == JObject:
      for path, entry in transcripts:
        var te = TranscriptEntry()
        te.size = entry.getOrDefault("size").getInt(0)
        te.offset = entry.getOrDefault("offset").getInt(0)
        te.mtime = fromUnix(entry.getOrDefault("mtime").getInt(0))
        let lastCheckedStr = entry.getOrDefault("last_checked").getStr("")
        if lastCheckedStr.len > 0:
          te.lastChecked = parse(lastCheckedStr, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
        te.tokensAfterSummary = entry.getOrDefault("tokens_after_summary").getInt(0)
        te.messagesAfterSummary = entry.getOrDefault("messages_after_summary").getInt(0)
        te.lastCacheReadTokens = entry.getOrDefault("last_cache_read_tokens").getInt(0)
        te.incompleteLineBuffer = entry.getOrDefault("incomplete_line_buffer").getStr("")
        result.transcripts[path] = te

    # Load directory mtimes (may not exist in old cache files)
    if j.hasKey("dir_mtimes"):
      let dirMtimes = j["dir_mtimes"]
      if not dirMtimes.isNil and dirMtimes.kind == JObject:
        for path, mtime in dirMtimes:
          result.dirMtimes[path] = fromUnix(mtime.getInt(0))

    log(INFO, "Loaded transcript cache: " & $result.transcripts.len & " entries, " & $result.dirMtimes.len & " dirs")
  except Exception as e:
    log(WARN, "Failed to load transcript cache: " & e.msg)

proc writeTranscriptCache*(cacheDir: string, cache: TranscriptCache) =
  ## Write transcripts.json to cache directory
  let cachePath = cacheDir / "transcripts.json"
  var j = %*{
    "version": cache.version,
    "last_pruned": cache.lastPruned.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "transcripts": newJObject(),
    "dir_mtimes": newJObject()
  }

  for path, entry in cache.transcripts:
    j["transcripts"][path] = %*{
      "size": entry.size,
      "offset": entry.offset,
      "mtime": entry.mtime.toUnix(),
      "last_checked": entry.lastChecked.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "tokens_after_summary": entry.tokensAfterSummary,
      "messages_after_summary": entry.messagesAfterSummary,
      "last_cache_read_tokens": entry.lastCacheReadTokens,
      "incomplete_line_buffer": entry.incompleteLineBuffer
    }

  for path, mtime in cache.dirMtimes:
    j["dir_mtimes"][path] = %mtime.toUnix()

  atomicWriteJson(cachePath, j)
  log(DEBUG, "Wrote transcript cache to " & cachePath)
