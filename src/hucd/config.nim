## Daemon configuration loading and hot-reload watching

import std/[os, json, times]
import ../shared/types

type
  ConfigWatchState* = object
    configPath*: string
    lastMtime*: Time
    initialized*: bool

proc loadConfig*(path: string): DaemonConfig =
  ## Load daemon config from JSON file, returning defaults if missing
  result = defaultDaemonConfig()

  # Set default config dir if none specified
  if result.configDirs.len == 0:
    result.configDirs = @[getHomeDir() / ".claude"]

  if not fileExists(path):
    log(INFO, "Config file not found, using defaults: " & path)
    return

  try:
    let j = parseFile(path)
    result = parseDaemonConfig(j)

    # Ensure at least one config dir
    if result.configDirs.len == 0:
      result.configDirs = @[getHomeDir() / ".claude"]

    log(INFO, "Loaded config from " & path)
  except Exception as e:
    log(ERROR, "Failed to parse config: " & e.msg)
    # Keep defaults on parse error

proc initConfigWatch*(state: var ConfigWatchState) =
  ## Initialize config watch state with current mtime
  if fileExists(state.configPath):
    state.lastMtime = getFileInfo(state.configPath).lastWriteTime
  state.initialized = true

proc configFileChanged*(state: var ConfigWatchState): bool =
  ## Check if config file has changed since last check
  ## Returns true only once per change (updates internal state)
  if not state.initialized:
    initConfigWatch(state)
    return false

  if not fileExists(state.configPath):
    return false

  try:
    let currentMtime = getFileInfo(state.configPath).lastWriteTime
    if currentMtime != state.lastMtime:
      state.lastMtime = currentMtime
      return true
    return false
  except:
    return false
