import std/os
import std/strutils

type
  NimbleFileData* = object
    name*: string
    requires*: seq[string]
    srcDir*: string
    version*: string

proc findNimbleFiles*(root: string): seq[string] =
  if fileExists(root) and root.endsWith(".nimble"):
    return @[root]
  for nimblefile in walkFiles(root/"*.nimble"):
    result.add(nimblefile)

proc parseRequiresLine*(x: string): seq[string] =
  var state = "init"
  var buf = ""
  for c in x:
    case state
    of "init":
      if c == '"':
        state = "inside"
    of "inside":
      if c == '"':
        result.add(buf)
        buf.setLen(0)
        state = "init"
      else:
        buf.add(c)
    else:
      discard

proc parseNimbleFile*(path: string): NimbleFileData =
  ## Read a .nimble file and do a best effort attempt at parsing it
  ## Anyone who wants to improve this is welcome to
  result.name = path.splitFile()[1]
  for line in readFile(path).splitLines():
    let sline = line.strip()
    let components = sline.splitWhitespace()
    if components.len == 0:
      continue
    case components[0].toLower()
    of "version:":
      result.version = components[1].split('"')[1]
    of "version":
      result.version = components[2].split('"')[1]
    of "srcdir:":
      result.srcDir = components[1].split('"')[1]
    of "srcdir":
      result.srcDir = components[2].split('"')[1]
    of "requires:", "requires":
      result.requires.add sline.parseRequiresLine()
    else:
      discard

proc getProjectNameFromNimble*(path: string): string =
  for nimblefile in path.findNimbleFiles():
    let data = parseNimbleFile(nimblefile)
    if data.name != "":
      return data.name

proc getVersionFromNimble*(path: string): string =
  for nimblefile in path.findNimbleFiles():
    let data = parseNimbleFile(nimblefile)
    if data.version != "":
      return data.version

proc listNimbleRequires*(dirname: string): seq[string] =
  ## Parse the nimble file in a dir and return the Reqs required by that file
  for nimblefile in findNimbleFiles(dirname):
    let data = parseNimbleFile(nimblefile)
    result.add(data.requires)

proc splitNimbleNameAndVersion*(x: string): tuple[name: string, version: string] =
  var name = ""
  var version = ""
  var inname = true
  for c in x:
    if inname:
      if c in {'a'..'z','A'..'Z','0'..'9','_'}:
        name.add(c)
      else:
        inname = false
        version.add(c)
    else:
      version.add(c)
  return (name.strip(), version.strip())