## Cache pruning for daemon

import std/[os, times, tables, algorithm]
import ../shared/types

const
  MAX_TRANSCRIPTS* = 10_000

proc pruneTranscriptCache*(cache: var TranscriptCache) =
  ## Remove entries for deleted files and enforce size limits

  var toRemove: seq[string] = @[]

  # Find entries for non-existent files
  for path, entry in cache.transcripts:
    if not fileExists(path):
      toRemove.add(path)

  # Remove deleted entries
  for path in toRemove:
    cache.transcripts.del(path)
    log(DEBUG, "Pruned deleted transcript: " & path)

  # Enforce max entries limit by removing oldest
  if cache.transcripts.len > MAX_TRANSCRIPTS:
    # Sort by lastChecked and remove oldest
    var entries: seq[(string, TranscriptEntry)] = @[]
    for path, entry in cache.transcripts:
      entries.add((path, entry))

    entries.sort(proc(a, b: (string, TranscriptEntry)): int =
      cmp(a[1].lastChecked, b[1].lastChecked)
    )

    let removeCount = cache.transcripts.len - MAX_TRANSCRIPTS
    for i in 0..<removeCount:
      cache.transcripts.del(entries[i][0])
      log(DEBUG, "Pruned oldest transcript: " & entries[i][0])

  cache.lastPruned = now().utc()
  log(INFO, "Pruned transcript cache, " & $cache.transcripts.len & " entries remaining")
