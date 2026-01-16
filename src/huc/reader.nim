## Status file reading for statusline

import std/[os, json, times, options]
import ../shared/types

const
  STALENESS_THRESHOLD_MINUTES* = 10

proc readStatus*(path: string): Option[Status] =
  ## Read and parse status.json
  if not fileExists(path):
    return none(Status)

  try:
    let j = parseFile(path)
    return some(parseStatus(j))
  except:
    return none(Status)

proc getStatusAge*(status: Status): Duration =
  ## Get age of status since updatedAt
  now().utc() - status.updatedAt

proc isStatusStale*(status: Status): bool =
  ## Check if status is older than threshold
  getStatusAge(status).inMinutes >= STALENESS_THRESHOLD_MINUTES

proc isApiStale*(status: Status): bool =
  ## Check if API data is stale
  if not status.api.configured:
    return false
  if status.api.fetchedAt.isNone:
    return true
  let apiAge = now().utc() - status.api.fetchedAt.get()
  return apiAge.inMinutes >= STALENESS_THRESHOLD_MINUTES
