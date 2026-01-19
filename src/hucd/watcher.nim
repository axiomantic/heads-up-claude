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
  ## Optimized: skip directories that haven't been modified recently

  if not dirExists(projectsDir):
    log(DEBUG, "Projects directory not found: " & projectsDir)
    return

  let now = getTime()
  let thirtyDaysAgo = now - initDuration(days = 30)
  var scannedDirs = 0
  var skippedDirs = 0

  for projectKind, projectPath in walkDir(projectsDir):
    if projectKind != pcDir:
      continue

    # Optimization: skip project directories not modified in 30+ days
    # This avoids walking thousands of old session files
    try:
      let dirMtime = getFileInfo(projectPath).lastWriteTime
      if dirMtime < thirtyDaysAgo:
        skippedDirs += 1
        continue
    except:
      continue

    scannedDirs += 1

    for transcriptPath in walkFiles(projectPath / "*.jsonl"):
      try:
        let currentMtime = getFileInfo(transcriptPath).lastWriteTime

        # Check if we have cached state
        if cache.transcripts.hasKey(transcriptPath):
          var entry = cache.transcripts[transcriptPath]

          # Skip if mtime unchanged
          if entry.mtime == currentMtime:
            entry.lastChecked = now().utc()
            cache.transcripts[transcriptPath] = entry
            continue

          # Process incrementally
          processTranscript(transcriptPath, entry)
          cache.transcripts[transcriptPath] = entry
        else:
          # New file - full process
          var entry = TranscriptEntry()
          processTranscript(transcriptPath, entry)
          cache.transcripts[transcriptPath] = entry

      except OSError as e:
        if e.errorCode == 2:  # ENOENT - file deleted
          cache.transcripts.del(transcriptPath)
        else:
          log(WARN, "Error reading " & transcriptPath & ": " & e.msg)
      except Exception as e:
        log(WARN, "Error processing " & transcriptPath & ": " & e.msg)

  if skippedDirs > 0:
    log(DEBUG, "Scanned " & $scannedDirs & " dirs, skipped " & $skippedDirs & " inactive (30+ days)")
