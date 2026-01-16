## Daemon-specific logging utilities
##
## Re-exports shared logging from types and provides convenience procs
## for daemon-specific logging needs.

import std/[times]
import ../shared/types

# Re-export shared logging
export types.LogLevel, types.debugMode, types.log

proc formatLogMessage*(level: LogLevel, msg: string): string =
  ## Format a log message with timestamp and level
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let levelStr = case level
    of DEBUG: "DEBUG"
    of INFO: "INFO"
    of WARN: "WARN"
    of ERROR: "ERROR"
  result = "[" & timestamp & "] [" & levelStr & "] " & msg

proc logDebug*(msg: string) =
  ## Log a debug message (only if debugMode is true)
  log(DEBUG, msg)

proc logInfo*(msg: string) =
  ## Log an info message
  log(INFO, msg)

proc logWarn*(msg: string) =
  ## Log a warning message
  log(WARN, msg)

proc logError*(msg: string) =
  ## Log an error message
  log(ERROR, msg)
