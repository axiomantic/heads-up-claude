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

proc writeTranscriptCache*(cacheDir: string, cache: TranscriptCache) =
  ## Write transcripts.json to cache directory
  let cachePath = cacheDir / "transcripts.json"
  var j = %*{
    "version": cache.version,
    "last_pruned": cache.lastPruned.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "transcripts": newJObject()
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

  atomicWriteJson(cachePath, j)
  log(DEBUG, "Wrote transcript cache to " & cachePath)
