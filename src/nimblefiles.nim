import std/os
import std/strutils

type
  NimbleFileData* = object
    name*: string
    requires*: seq[string]
    srcDir*: string
    version*: string

proc findNimbleFiles*(root: string): seq[string] =
  for nimblefile in walkFiles(root/"*.nimble"):
    result.add(nimblefile)

proc parseNimbleFile*(path: string): NimbleFileData =
  ## Read a .nimble file and do a best effort attempt at parsing it
  ## Anyone who wants to improve this is welcome to
  result.name = path.splitFile()[1]
  for line in readFile(path).splitLines():
    let sline = line.strip()
    let components = sline.splitWhitespace()
    if components.len == 0:
      continue
    case components[0]
    of "version":
      result.version = components[2].split('"')[1]
    of "srcDir":
      result.srcDir = components[2].split('"')[1]
    else:
      discard

proc getProjectNameFromNimble*(path: string): string =
  for nimblefile in path.findNimbleFiles():
    let data = parseNimbleFile(nimblefile)
    if data.name != "":
      return data.name