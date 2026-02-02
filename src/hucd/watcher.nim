## Transcript file watching and incremental processing

import std/[os, json, times, tables, strutils]
import ../shared/types

proc processTranscript*(transcriptPath: string, entry: var TranscriptEntry) =
  ## Process a transcript file, updating entry with token/message counts
  ## Supports incremental reading from offset

  if not fileExists(transcriptPath):
    return

  let f = open(transcriptPath, fmRead)
  defer: f.close()

  let currentSize = f.getFileSize()

  # If file was truncated, reset state
  if currentSize < entry.size:
    log(DEBUG, "File truncated, resetting: " & transcriptPath)
    entry.offset = 0
    entry.tokensAfterSummary = 0
    entry.messagesAfterSummary = 0
    entry.lastCacheReadTokens = 0
    entry.incompleteLineBuffer = ""

  # Seek to offset for incremental read
  if entry.offset > 0 and entry.offset < currentSize:
    f.setFilePos(entry.offset)

  # Read new content
  let newContent = f.readAll()

  # Prepend incomplete line from previous read
  let fullContent = entry.incompleteLineBuffer & newContent
  entry.incompleteLineBuffer = ""

  var lines = fullContent.splitLines()

  # If content doesn't end with newline, last line is incomplete
  if fullContent.len > 0 and not fullContent.endsWith("\n") and lines.len > 0:
    entry.incompleteLineBuffer = lines[^1]
    lines = lines[0..^2]

  for line in lines:
    if line.len == 0:
      continue

    try:
      let jsonEntry = parseJson(line)
      let entryType = jsonEntry.getOrDefault("type").getStr("")

      if entryType == "summary":
        # Reset counters on compaction
        entry.tokensAfterSummary = 0
        entry.messagesAfterSummary = 0
        continue

      if entryType in ["user", "assistant"]:
        entry.messagesAfterSummary += 1

      if jsonEntry.hasKey("message"):
        let message = jsonEntry["message"]
        if not message.isNil and message.kind == JObject and message.hasKey("usage"):
          let usage = message["usage"]
          if not usage.isNil and usage.kind == JObject:
            var totalTokens = 0
            totalTokens += usage.getOrDefault("output_tokens").getInt(0)
            totalTokens += usage.getOrDefault("input_tokens").getInt(0)

            entry.tokensAfterSummary = totalTokens  # Replaces, not accumulates (per design)
            entry.lastCacheReadTokens = usage.getOrDefault("cache_read_input_tokens").getInt(0)

    except JsonParsingError:
      # Invalid JSON line - skip (could be mid-write)
      continue
    except:
      continue

  entry.offset = currentSize
  entry.size = currentSize
  entry.mtime = getFileInfo(transcriptPath).lastWriteTime
  entry.lastChecked = now().utc()

proc scanTranscripts*(projectsDir: string, cache: var TranscriptCache) =
  ## Scan all projects for transcript files and update cache
  ## Two-phase scan:
  ## 1. Walk directories to find new files (skip cold directories)
  ## 2. Check all cached transcripts for file size changes (catches modifications)

  if not dirExists(projectsDir):
    log(DEBUG, "Projects directory not found: " & projectsDir)
    return

  let now = getTime()
  let thirtyDaysAgo = now - initDuration(days = 30)
  var scannedDirs = 0
  var skippedDirs = 0
  var updatedFiles = 0

  # Phase 1: Walk directories to discover new files
  for projectKind, projectPath in walkDir(projectsDir):
    if projectKind != pcDir:
      continue

    try:
      let dirMtime = getFileInfo(projectPath).lastWriteTime

      # Skip directories not modified in 30+ days (cold storage optimization)
      if dirMtime < thirtyDaysAgo:
        skippedDirs += 1
        continue

      # Always walk directories to find new files (removed broken dir mtime optimization)
      scannedDirs += 1

      for transcriptPath in walkFiles(projectPath / "*.jsonl"):
        if not cache.transcripts.hasKey(transcriptPath):
          # New file - full process
          try:
            var entry = TranscriptEntry()
            processTranscript(transcriptPath, entry)
            cache.transcripts[transcriptPath] = entry
            updatedFiles += 1
          except OSError as e:
            if e.errorCode != 2:  # Ignore ENOENT
              log(WARN, "Error reading new file " & transcriptPath & ": " & e.msg)
          except Exception as e:
            log(WARN, "Error processing new file " & transcriptPath & ": " & e.msg)

    except:
      continue

  # Phase 2: Check all cached transcripts for modifications (by file size)
  # This catches file content changes that don't affect directory mtime
  var toDelete: seq[string] = @[]

  for transcriptPath, entry in cache.transcripts.mpairs:
    # Only check transcripts under this projectsDir
    if not transcriptPath.startsWith(projectsDir):
      continue

    try:
      let info = getFileInfo(transcriptPath)
      let currentSize = info.size

      # File grew - process new content incrementally
      if currentSize > entry.size:
        processTranscript(transcriptPath, entry)
        updatedFiles += 1

    except OSError as e:
      if e.errorCode == 2:  # ENOENT - file deleted
        toDelete.add(transcriptPath)
      # Ignore other errors (file might be temporarily locked)
    except:
      discard

  # Clean up deleted files
  for path in toDelete:
    cache.transcripts.del(path)

  if skippedDirs > 0 or updatedFiles > 0:
    log(DEBUG, "Scanned " & $scannedDirs & " dirs, skipped " & $skippedDirs & " cold, updated " & $updatedFiles & " files")
