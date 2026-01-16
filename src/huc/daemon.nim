## Daemon management utilities for statusline

import std/[os, osproc, strutils, options]

proc getPlatform*(): string =
  ## Get current platform
  when defined(macosx):
    return "darwin"
  elif defined(linux):
    return "linux"
  else:
    return "unknown"

proc getDaemonPid*(): Option[int] =
  ## Get PID of running daemon, if any
  let platform = getPlatform()

  case platform
  of "darwin":
    # Check launchd
    let (output, exitCode) = execCmdEx("launchctl list | grep -w com.headsup.claude")
    if exitCode == 0:
      let parts = output.strip().split()
      if parts.len >= 1 and parts[0] != "-":
        try:
          return some(parseInt(parts[0]))
        except:
          discard
  of "linux":
    # Check systemd
    let (output, exitCode) = execCmdEx("systemctl --user show hucd --property=MainPID --value")
    if exitCode == 0:
      try:
        let pid = parseInt(output.strip())
        if pid > 0:
          return some(pid)
      except:
        discard
  else:
    discard

  # Fallback: check for process
  let (output, exitCode) = execCmdEx("pgrep -f hucd")
  if exitCode == 0:
    try:
      return some(parseInt(output.strip().splitLines()[0]))
    except:
      discard

  return none(int)

proc isDaemonRunning*(): bool =
  ## Check if daemon is running
  getDaemonPid().isSome

proc restartDaemon*(): bool =
  ## Restart the daemon using platform service manager
  let platform = getPlatform()

  case platform
  of "darwin":
    let plist = getHomeDir() / "Library/LaunchAgents/com.headsup.claude.plist"
    if fileExists(plist):
      discard execCmd("launchctl unload " & quoteShell(plist))
      return execCmd("launchctl load " & quoteShell(plist)) == 0
  of "linux":
    return execCmd("systemctl --user restart hucd") == 0
  else:
    discard

  # Fallback: kill and restart manually
  discard execCmd("pkill -f hucd")
  let hucdPath = getHomeDir() / ".local/bin/hucd"
  if fileExists(hucdPath):
    discard execCmd("nohup " & quoteShell(hucdPath) & " >/dev/null 2>&1 &")
    return true

  return false

proc getDaemonLogs*(lines: int = 50): string =
  ## Get recent daemon logs
  let logPath = getHomeDir() / ".local/share/hucd/stderr.log"
  if fileExists(logPath):
    let (output, exitCode) = execCmdEx("tail -n " & $lines & " " & quoteShell(logPath))
    if exitCode == 0:
      return output
  return "(no logs found)"

proc getDaemonStatus*(): string =
  ## Get daemon status summary
  result = "Daemon Status:\n"

  let pid = getDaemonPid()
  if pid.isSome:
    result.add("  Status: Running (PID " & $pid.get() & ")\n")
  else:
    result.add("  Status: Not running\n")

  let platform = getPlatform()
  result.add("  Platform: " & platform & "\n")

  case platform
  of "darwin":
    let plist = getHomeDir() / "Library/LaunchAgents/com.headsup.claude.plist"
    result.add("  Service: " & (if fileExists(plist): "Installed" else: "Not installed") & "\n")
  of "linux":
    let service = getHomeDir() / ".config/systemd/user/hucd.service"
    result.add("  Service: " & (if fileExists(service): "Installed" else: "Not installed") & "\n")
  else:
    result.add("  Service: N/A\n")
