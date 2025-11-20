import std/os
import std/json

import ./objs

template TODO*(x: string) =
  when defined(release):
    {.fatal: x .}
  else:
    echo "TODO: " & x

proc pkgerContext*(workDir: string): PkgerContext =
  ## Given a working directory path,
  ## return the context for that path
  var p = workDir
  while not fileExists(p/"pkger.json"):
    if p == p.parentDir():
      raise ValueError.newException("Not in a pkger directory")
    p = p.parentDir()
  let config = readFile(p/"pkger.json").parseJson()
  let depsDir = p / config{"dir"}.getStr()
  return PkgerContext(
    rootDir: p.absolutePath(),
    workDir: workDir.absolutePath(),
    depsDir: depsDir.absolutePath(),
  )

proc pkgerContext*(): PkgerContext =
  ## Return the context for the current directory
  pkgerContext(getCurrentDir())

