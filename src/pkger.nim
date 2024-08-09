import std/logging
import std/strformat
import std/strutils
import std/tables

import argparse

import ./objs; export objs
import ./context; export context
import ./deps
import ./nimblefiles
import ./packages; export packages

#---------------------------------------------------------
# 
#---------------------------------------------------------
const START_SENTINEL = "### PKGER START - DO NOT EDIT BELOW #########"
const END_SENTINEL =   "### PKGER END - DO NOT EDIT ABOVE ###########"

proc setNimCfgDirs(ctx: PkgerContext, dirs: seq[string]) =
  ## Set a nim.cfg file's paths to the given set
  let existing = try:
      readFile(ctx.rootDir/"nim.cfg")
    except:
      ""
  var body: seq[string]
  # body.add("--noNimblePath")
  for dir in dirs:
    body.add("--path:\"" & dir & "\"")
  
  var state = "init"
  var lines: seq[string]
  for line in existing.splitLines():
    case state
    of "init":
      lines.add(line)
      if line == START_SENTINEL:
        lines.add(body)
        state = "inside"
    of "inside":
      if line == END_SENTINEL:
        lines.add(line)
        state = "after"
    of "after":
      lines.add(line)
    else:
      raise ValueError.newException("Invalid state: " & state)
    
  if state == "init":
    lines.add(START_SENTINEL)
    lines.add(body)
    lines.add(END_SENTINEL)
    lines.add("")
  writeFile(ctx.rootDir/"nim.cfg", lines.join("\n"))

proc refreshNimCfg*(ctx: PkgerContext) =
  let pinned = ctx.getPinnedReqs()
  var nimPaths: seq[string]
  for pin in pinned:
    let srcPath = ctx.ondiskPath(pin.toReq())
    nimPaths.add(getNimPathsFromProject(srcPath).mapIt(relativePath(srcPath/it, ctx.rootDir)))
  ctx.setNimCfgDirs(nimPaths)

proc use(ctx: PkgerContext, req: Req, parent = ""): seq[PinnedReq] =
  let pinned = ctx.ensurePresent(req)
  result.add(pinned)
  # if recursive:
  #   let subparent = pinned.pkgname
  #   let path = ctx.ondiskPath(pinned.toReq())
  #   for nreq in listNimbleRequires(path):
  #     let childreq = ctx.toReq(nreq.ReqNimbleDesc, subparent)
  #     if childreq.pkgname in encountered:
  #       continue
  #     encountered.add(childreq.pkgname)
  #     result.add(ctx.use(childreq, recursive = true))
  if parent == "":
    ctx.add(result)
    ctx.refreshNimCfg()

proc use(ctx: PkgerContext, pkg: ReqDesc, parent = ""): seq[PinnedReq] =
  let req = ctx.toReq(pkg, parent = parent)
  ctx.use(req)

proc cmd_fetch(ctx: PkgerContext) =
  ## Fetch all the source packages that are missing
  let pinned = ctx.getPinnedReqs()
  var newpinned: seq[PinnedReq]
  for pin in pinned:
    newpinned.add(ctx.ensurePresent(pin.toReq()))
  ctx.setPinnedReqs(newpinned)

proc cmd_listdeps(dir_or_nimblefile: string) =
  for req in listNimbleRequires(dir_or_nimblefile):
    echo $req

proc cmd_status(ctx: PkgerContext) =
  ## Print out a human readable status of dependencies
  let installed = ctx.installedPackages()
  var installedMap = newTable[string, InstalledPackage](installed.len)
  for pkg in installed:
    installedMap[pkg.name] = pkg
  
  let allreqs = sorted(ctx.allReqs())
  var used: seq[string]
  var fulfilled: seq[string]
  var missing: seq[string]
  for req in allreqs:
    var parts: seq[string]
    parts.add req.label
    if req.parent != "":
      parts.add "(" & req.parent & ")"
    let ver = $req.version
    if ver != "":
      parts.add ver
    if installedMap.hasKey(req.name):
      used.add(req.name)
      let inst = installedMap[req.name]
      parts = concat(@["[x]"], parts, @["(" & inst.nice & ")"])
      fulfilled.add(parts.join(" "))
    else:
      parts = concat(@["[ ]"], parts)
      missing.add(parts.join(" "))
  for x in fulfilled:
    echo x
  for x in missing:
    echo x
  
  for inst in installed:
    if inst.name notin used:
      echo &"[x] {inst.name} ({inst.version} {inst.sha})"

#---------------------------------------------------------
# plumbing
#---------------------------------------------------------
proc cmd_updatepackagelist(ctx: PkgerContext) =
  info &"updating package list for {ctx.rootDir}"
  updatePackagesDir(ctx)

#---------------------------------------------------------
# porcelain
#---------------------------------------------------------
proc cmd_init(dirname: string) =
  info &"initializing pkger in {dirname}"
  if fileExists(dirname/"pkger.json"):
    warn &"pkger already initialized"
    return
  writeFile("pkger.json", "{}")

  let pkgerdir = dirname/"pkger"
  createDir pkgerdir
  writeFile(pkgerdir/".gitignore", """
lazy
_cache
_packages
""")

  cmd_updatepackagelist(pkgerContext())

var p = newParser:
  # option("-d", "--depsdir", default=some("pkger"), help="Directory where pkger will keep deps")
  command("init"):
    run:
      cmd_init(getCurrentDir())
  command("status"):
    run:
      cmd_status(pkgerContext())
  command("use"):
    help("Add a package to this project.")
    flag("--no-deps", help="If provided, don't also add the packages deps")
    arg("package", help="package, package@version, package@sha, ./localpath, https://github.com/path/to/repo@sha, etc...")
    run:
      discard use(pkgerContext(), opts.package.ReqDesc)
  command("fetch"):
    help("Fetch all the external packages that are missing")
    run:
      cmd_fetch(pkgerContext())
  command("listdeps"):
    arg("path", help="Path to .nimble file or containing dir")
    run:
      cmd_listdeps(opts.path)
  command("low"):
    command("updatepackagelist"):
      run:
        var ctx = pkgerContext()
        cmd_updatepackagelist(ctx)

proc cli*(args: seq[string]) =
  try:
    p.run(args)
  except UsageError as e:
    stderr.writeLine getCurrentExceptionMsg()
    raise

when isMainModule:
  addHandler(newConsoleLogger())
  cli(commandLineParams())
