import std/os

template TODO*(x: string) =
  when defined(release):
    {.fatal: x .}
  else:
    echo "TODO: " & x

type
  PkgerContext* = object
    rootDir*: string
    workDir*: string

proc pkgerContext*(workDir: string): PkgerContext =
  ## Given a working directory path,
  ## return the context for that path
  var p = workDir
  while not fileExists(p/"pkger.json"):
    if p == p.parentDir():
      raise ValueError.newException("Not in a pkger directory")
    p = p.parentDir()
  return PkgerContext(
    rootDir: p.absolutePath(),
    workDir: workDir.absolutePath(),
  )

proc pkgerContext*(): PkgerContext =
  ## Return the context for the current directory
  pkgerContext(getCurrentDir())

proc depsDir*(ctx: PkgerContext): string =
  ctx.rootDir / "pkger"
