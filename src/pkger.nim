{.experimental: "codeReordering".}

import std/deques
import std/json
import std/logging
import std/options
import std/os
import std/osproc
import std/sequtils
import std/sha1
import std/streams
import std/strformat
import std/strutils
import std/tables
import std/tempfiles
import std/typetraits
import std/uri

import argparse

import ./commandline
import ./nimblefiles

type
  PackageKind* = enum
    fmUnknown = ""
    fmGitRepo = "git"
    fmHgRepo = "hg"
    fmLocalFile = "local"
  
  Dep* = tuple
    name: string
    url: string
    kind: PackageKind
    sha: string
    parent: string
  
  Requirement* = tuple
    sourceFile: string ## The .nimble/pkger.json file this requirement comes from
    sourcePkg: string ## The package that is requiring this
    reqstring: string ## The full string requirement

  # NumericVersion* = distinct seq[int]

  # VersionType* = enum
  #   vNumeric
  #   vSHA
  #   vAnyVersion
  #   vRange
  # Version* = object
  #   case kind*: VersionType
  #   of vNumeric:
  #     nver*: NumericVersion
  #   of vSHA:
  #     sha*: string
  #   of vAnyVersion:
  #     discard
  #   of vRange:
  #     vrange*: string
  
  # VersionSpec* = distinct string

  # DepAndVersion* = tuple
  #   dep: Dep
  #   version: Version

  # ReqDesc* = distinct string
  # ReqNimbleDesc* = distinct string

  # RawReq* = tuple
  #   name: string
  #   label: string
  #   parent: string
  #   version: string

  # ParsedNimbleReq* = object
  #   case isUrl*: bool
  #   of true:
  #     url*: string
  #   of false:
  #     name*: string
  #   version*: string

  # ReqSource* = tuple
  #   url: string
  #   kind: PackageKind

  # Req* = tuple
  #   pkgname: string
  #   parent: string
  #   src: ReqSource
  #   version: Version
  
  # PinnedReq* = tuple
  #   pkgname: string
  #   parent: string
  #   src: ReqSource
  #   sha: string
  
  # InstalledPackage* = tuple
  #   name: string
  #   version: string
  #   sha: string

  # ContextualPinnedReq* = tuple
  #   ctx: PkgerContext
  #   pinned: PinnedReq

  PkgerContext* = object
    rootDir*: string
    workDir*: string
    depsDir*: string

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


#-----------------------------------------------------------------
# Package registry
#-----------------------------------------------------------------
const PACKAGES_REPO_URL = when defined(testmode):
    currentSourcePath().parentDir()/"../tests/data/packagesrepo"
  else:
    "https://github.com/nim-lang/packages"

proc packages_repo_dir*(ctx: PkgerContext): string =
  getConfigDir() / "nimpkger" / "packages"

proc cache_dir*(ctx: PkgerContext): string =
  getConfigDir() / "nimpkger" / "_cache"

proc updatePackagesRepo(ctx: PkgerContext) =
  ## Download the latest packages.json repo
  let packages_dir = ctx.packages_repo_dir()
  if not packages_dir.dirExists:
    # initial clone
    runsh(@["git", "clone", PACKAGES_REPO_URL, packages_dir])
  else:
    # update existing clone?
    runsh(@["git", "fetch", "origin"], workingDir = packages_dir)
    runsh(@["git", "reset", "--hard", "FETCH_HEAD"], workingDir = packages_dir)

# proc lookupPackageFromRegistry*(ctx: PkgerContext, name: string): Option[ReqSource] =
#   ## Get package info for a particular package
#   let packages_json = ctx.packages_repo_dir()/"packages.json"
#   if not packages_json.fileExists():
#     ctx.updatePackagesRepo()
#   if not packages_json.fileExists():
#     raise ValueError.newException("Failed to get packages repo")
#   let data = block:
#     let fs  = newFileStream(packages_json, fmRead)
#     if fs == nil:
#       raise ValueError.newException("Failed to read " & packages_json & " while looking up name: " & name)
#     parseJson(fs)
#   for item in data:
#     let thisname = item{"name"}.getStr()
#     if thisname == name:
#       let meth = item{"method"}.getStr()
#       let depkind = case meth
#         of "git": fmGitRepo
#         of "hg": fmHgRepo
#         else: fmUnknown
#       return some((
#         url: item{"url"}.getStr(),
#         kind: depkind,
#       ))

proc updatePackagesDir*(ctx: PkgerContext) =
  ## Download the latest packages.json data
  updatePackagesRepo(ctx)

proc packageDownloadDir*(ctx: PkgerContext): string =
  ctx.depsDir/"lazy"

# proc nameFromURL*(ctx: PkgerContext, url: string): string =
#   let pinned = ctx.getRecursivePinnedReqs()
#   for (octx, req) in pinned:
#     if req.src.url == url:
#       return req.pkgname
  
#   let data = block:
#     let fname = ctx.packages_repo_dir()/"packages.json"
#     if not fname.fileExists():
#       ctx.updatePackagesRepo()
#     let fs = newFileStream(fname, fmRead)
#     if fs == nil:
#       raise ValueError.newException("Failed to read " & fname & " while looking up url: " & url)
#     parseJson(fs)
#   for item in data:
#     let thisurl = item{"url"}.getStr()
#     if thisurl == url:
#       return item{"name"}.getStr()

#-----------------------------------------------------------------
# Git stuff
#-----------------------------------------------------------------
proc urlToDirname*(url: string): string =
  let parsed = parseUri(url)
  if parsed.path != "":
    result = parsed.path.split("/")[^1]
  else:
    result = parsed.hostname
  result &= "-" & $secureHash(url)

proc gitGetSHA*(repodir: string, commitish: string): Option[string] =
  try:
    let (outp, rc) = execCmdEx("git rev-parse " & quoteShell(commitish),
      options = {poUsePath},
      workingDir = repodir)
    if rc == 0:
      return some(outp.strip())
  except:
    discard

proc gitThingExists*(repodir: string, commitish: string): bool =
  ## Return true if the commitish exists
  gitGetSHA(repodir, commitish).isSome()

proc gitSearchForCommitish*(repodir: string, version: string): string =
  if repodir.gitThingExists(version):
    return version
  if version.startsWith("v"):
    let unv = version.strip(chars={'v'}, leading = true, trailing = false)
    if repodir.gitThingExists(unv):
      return unv
  if repodir.gitThingExists("origin/" & version):
    return "origin/" & version

proc cacheGitRepo*(ctx: PkgerContext, url: string, resetToVersion = ""): string =
  ## Clone a git repo if it doesn't exist and return the path to the repo on disk
  let cachedir = ctx.cache_dir()
  createDir(cachedir)
  let repodir = cachedir/urlToDirname(url)
  result = repodir
  if dirExists(repodir):
    if resetToVersion != "":
      try:
        runsh(@["git", "fetch", "origin"], workingDir = repodir)  
      except:
        logging.error &"Error running `git fetch origin` in {repodir}"
        raise
  else:
    try:
      runsh(@["git", "clone", "--recurse-submodules", url, repodir])
    except:
      logging.error &"Error running `git clone` for url={url} to dir={repodir}"
      raise
  if resetToVersion != "":
    var version = repodir.gitSearchForCommitish(resetToVersion)
    runsh(@["git", "reset", "--recurse-submodules", "--hard", version], workingDir = repodir)

proc readGitSha*(repodir: string): string =
  runshout(@["git", "rev-parse", "HEAD"], workingDir = repodir, silent = true).strip()

proc placeGitRepo*(ctx: PkgerContext, url: string, dstdir: string, resetToVersion = "") =
  ## Ensure that a git repo exists at dstdir, using the available cached git repo if present
  if dirExists(dstdir):
    if resetToVersion != "":
      let sha = try:
          readGitSha(dstdir)
        except: ""
      if sha == resetToVersion:
        return
    else:
      return
  let srcdir = ctx.cacheGitRepo(url, resetToVersion)
  info "cp -R " & srcdir.niceDir & " " & dstdir.niceDir
  copyDirWithPermissions(srcdir, dstdir)

#-----------------------------------------------------------------
# Parsing and serializing
#-----------------------------------------------------------------
# proc parseNumericVersion*(x: string): NumericVersion =
#   x.split(".").mapIt(parseInt(it)).NumericVersion

# proc `$`*(x: NumericVersion): string =
#   toSeq(x.distinctBase.mapIt($it)).join(".")

# proc `$`*(x: Version): string =
#   case x.kind
#   of vSHA:
#     x.sha
#   of vAnyVersion:
#     ""
#   of vNumeric:
#     $x.nver
#   of vRange:
#     x.vrange

# proc nice*(x: InstalledPackage): string =
#   result = x.name
#   if x.version != "":
#     result &= " " & x.version
#   if x.sha != "":
#     result &= " " & x.sha

# proc parseVersion*(x: string): Version =
#   ## Parse a string description of a version
#   if x == "":
#     return Version(kind: vAnyVersion)
#   else:
#     try:
#       return Version(kind: vNumeric, nver: parseNumericVersion(x))
#     except:
#       return Version(kind: vSHA, sha: x)

# proc parse*(x: ReqNimbleDesc): ParsedNimbleReq =
#   let d = x.string.strip()
#   if ":" in d:
#     # url
#     let parts = d.split(seps={'#','@'}, 1)
#     let url = parts[0]
#     let version = if parts.len > 1:
#         parts[1]
#       else:
#         ""
#     return ParsedNimbleReq(
#       isUrl: true,
#       url: url,
#       version: version,
#     )
#   else:
#     let (name, version) = d.splitNimbleNameAndVersion()
#     return ParsedNimbleReq(
#       isUrl: false,
#       name: name,
#       version: version,
#     )

# proc pin*(req: Req, sha: string): PinnedReq =
#   (
#     pkgname: req.pkgname,
#     parent: req.parent,
#     src: req.src,
#     sha: sha,
#   )

# proc toReq*(pinned: PinnedReq): Req =
#   (
#     pkgname: pinned.pkgname,
#     parent: pinned.parent,
#     src: pinned.src,
#     version: Version(kind: vSHA, sha: pinned.sha),
#   )

# proc toReq*(ctx: PkgerContext, reqdesc: ReqDesc, parent: string): Req =
#   ## Parse a string requirement description into a Requirement
#   ## `parent` should be "" if this requirement is a base requirement
#   ## otherwise it should be the name of the pkg requiring this
#   let desc = reqdesc.string
#   let parts = desc.split("@", 1)
#   let name_or_url = parts[0]
#   let version = parseVersion(if parts.len > 1: parts[1] else: "")
#   if dirExists(name_or_url):
#     # localpath
#     let nimbleName = getProjectNameFromNimble(name_or_url)
#     let pkgname = if nimbleName != "": nimbleName else: name_or_url.splitFile.name
#     return (
#       pkgname: pkgname,
#       parent: parent,
#       src: (
#         url: relativePath(name_or_url, ctx.rootDir),
#         kind: fmLocalFile,
#       ),
#       version: version
#     )
  
#   # Check package registry
#   let o = ctx.lookupPackageFromRegistry(name_or_url)
#   if o.isSome:
#     let pkgsrc = o.get()
#     return (
#       pkgname: name_or_url,
#       parent: parent,
#       src: pkgsrc,
#       version: version,
#     )
  
#   # Try git
#   let isGit = block:
#     let parsed = parseUri(name_or_url)
#     if "git" in parsed.hostname or name_or_url.endsWith(".git"):
#       true
#     else:
#       try:
#         discard execProcess("git", args = @["ls-remote", "--tags", name_or_url],
#           options={poUsePath})
#         true
#       except:
#         false
#   if isGit:
#     let git_repo_path = ctx.cacheGitRepo(name_or_url)
#     let pkgname = getProjectNameFromNimble(git_repo_path)
#     return (
#       pkgname: pkgname,
#       parent: parent,
#       src: (
#         url: name_or_url,
#         kind: fmGitRepo,
#       ),
#       version: version
#     )
 
#   raise ValueError.newException("Mercurial not yet supported")

# proc toReq*(ctx: PkgerContext, reqdesc: ReqNimbleDesc, parent: string): Req =
#   let parsed = reqdesc.parse()
#   case parsed.isUrl
#   of true:
#     var desc = parsed.url
#     if parsed.version != "":
#       desc &= "@" & parsed.version
#     return ctx.toReq(desc.ReqDesc, parent)
#   of false:
#     # not a URL
#     var req = ctx.toReq(parsed.name.ReqDesc, parent)
#     if parsed.version != "":
#       req.version = Version(kind: vRange, vrange: parsed.version)
#     return req
    

# proc ondiskPath*(ctx: PkgerContext, req: Req): string =
#   ## Return the path to where the source code is/should be
#   case req.src.kind
#   of fmUnknown:
#     raise ValueError.newException("Can't choose path for unknown dep type: " & $req)
#   of fmLocalFile:
#     return ctx.rootDir/req.src.url
#   of fmGitRepo, fmHgRepo:
#     return ctx.depsDir/"lazy"/req.pkgname 


# proc ensurePresent*(ctx: PkgerContext, req: Req): PinnedReq =
#   ## Put source code for a single package in place
#   case req.src.kind
#   of fmUnknown:
#     raise ValueError.newException("Can't fetch: " & $req)
#   of fmLocalFile:
#     if not dirExists(req.src.url):
#       raise ValueError.newException("Local package missing: " & $req)
#     return req.pin("")
#   of fmGitRepo:
#     let path = ctx.ondiskPath(req)
#     var resetToVersion = case req.version.kind
#       of vNumeric:
#         "v" & $req.version.nver
#       of vSHA:
#         req.version.sha
#       of vAnyVersion:
#         ""
#       of vRange:
#         ""
#     ctx.placeGitRepo(req.src.url, path, resetToVersion)
#     return req.pin(readGitSha(path))
#   of fmHgRepo:
#     raise ValueError.newException("Mercurial not yet supported")

# proc placePackage*(ctx: PkgerContext, package_desc: string, dstdir: string): Dep =
#   ## Install a package@version in dstdir/{package}
#   let o = ctx.locatePackage(package_desc)
#   if o.isNone:
#     raise ValueError.newException("package not found: " & package_desc)
#   let vdep = o.get()
#   ctx.fetch(vdep.dep, some(vdep.version))

# proc getNimPathsFromProject*(dirname: string): seq[string] =
#   ## Return what should be set as --path:X to add the given package
#   ## to the path.
#   for nimblefile in findNimbleFiles(dirname):
#     let data = parseNimbleFile(nimblefile)
#     result.add(data.srcDir)

# proc installedPackages*(ctx: PkgerContext): seq[InstalledPackage] =
#   for pin in ctx.getImmediatePinnedReqs():
#     let path = ctx.ondiskPath(pin.toReq())
#     if not dirExists(path):
#       continue
#     let version = try:
#         getVersionFromNimble(path)
#       except:
#         ""
#     result.add((
#       name: pin.pkgname,
#       version: version,
#       sha: pin.sha,
#     ))

# proc allReqs*(ctx: PkgerContext): seq[RawReq] =
#   ## List all known requirements (without fetching anything) for this project
#   var packagesToProcess = @[(ctx, ctx.rootDir, "")]
#   for (octx, pin) in ctx.getRecursivePinnedReqs():
#     let path = octx.ondiskPath(pin.toReq())
#     if dirExists(path):
#       packagesToProcess.add((octx, path, pin.pkgname))
#   while packagesToProcess.len > 0:
#     let (octx, path, proj_name) = packagesToProcess.pop()
#     # Add pinned reqs if this is a pkger project
#     block:
#       var subctx: PkgerContext
#       let isPkgerProject = try:
#         subctx = pkgerContext(path)
#         subctx.rootDir == path
#       except ValueError:
#         false
#       if isPkgerProject:
#         for pin in subctx.getImmediatePinnedReqs():
#           let label = case pin.src.kind
#             of fmLocalFile: pin.src.url
#             of fmGitRepo, fmHgRepo: pin.pkgname
#             else: pin.pkgname
#           result.add((
#             name: pin.pkgname,
#             label: label,
#             parent: proj_name,
#             version: pin.sha,
#           ))
#     # Add nimble requires
#     for reqdesc in listNimbleRequires(path):
#       let ndesc = ReqNimbleDesc(reqdesc).parse()
#       if ndesc.isUrl:
#         result.add((
#           name: octx.nameFromURL(ndesc.url),
#           label: ndesc.url,
#           parent: proj_name,
#           version: ndesc.version,
#         ))
#       else:
#         if ndesc.name == "nim":
#           continue
#         result.add((
#           name: ndesc.name,
#           label: ndesc.name,
#           parent: proj_name,
#           version: ndesc.version,
#         ))
    
# proc `%`*(x: ReqSource): JsonNode =
#   %* {
#     "url": x.url,
#     "kind": x.kind,
#   }

# proc `%`*(x: PinnedReq): JsonNode =
#   %* {
#     "pkgname": x.pkgname,
#     "parent": x.parent,
#     "src": x.src,
#     "sha": x.sha,
#   }

# proc readDepsFile(ctx: PkgerContext): JsonNode =
#   try:
#     parseJson(readFile(ctx.depsDir/"deps.json"))
#   except:
#     %* {
#       "pinned": {}
#     }

# proc writeDepsFile(ctx: PkgerContext, data: JsonNode) =
#   writeFile(ctx.depsDir/"deps.json", data.pretty())

# proc getImmediatePinnedReqs*(ctx: PkgerContext): seq[PinnedReq] =
#   let data = readDepsFile(ctx)
#   for name in data["pinned"].keys():
#     let item = data["pinned"][name]
#     let pinned = to(item, PinnedReq)
#     result.add(pinned)

# proc getRecursivePinnedReqs*(ctx: PkgerContext): seq[ContextualPinnedReq] =
#   let immediate = ctx.getImmediatePinnedReqs()
#   for pinned in immediate:
#     result.add((ctx, pinned))
#     # check this package's deps
#     let path = ctx.ondiskPath(pinned.toReq())
#     let subctx = try:
#         pkgerContext(path)
#       except ValueError:
#         continue
#     if subctx.rootDir == ctx.rootDir:
#       # went up the path to find the original
#       continue
#     result.add(subctx.getRecursivePinnedReqs())

# proc setPinnedReqs*(ctx: PkgerContext, pinned: seq[PinnedReq]) =
#   var data = readDepsFile(ctx)
#   data["pinned"] = newJObject()
#   for req in pinned:
#     data["pinned"][req.pkgname] = %req
#   ctx.writeDepsFile(data)

# proc add*(ctx: PkgerContext, req: seq[PinnedReq]) =
#   var existing = ctx.getImmediatePinnedReqs()
#   existing.add(req)
#   ctx.setPinnedReqs(existing)


#---------------------------------------------------------
# pkger.nims
#---------------------------------------------------------
# const START_SENTINEL = "### PKGER START - DO NOT EDIT BELOW #########"
# const END_SENTINEL =   "### PKGER END - DO NOT EDIT ABOVE ###########"

# proc setNimCfgDirs(ctx: PkgerContext, dirs: seq[string]) =
#   ## Set a nim.cfg file's paths to the given set
#   let existing = try:
#       readFile(ctx.rootDir/"nim.cfg")
#     except:
#       ""
#   var body: seq[string]
#   # body.add("--noNimblePath")
#   for dir in dirs:
#     body.add("--path:\"" & dir & "\"")
  
#   var state = "init"
#   var lines: seq[string]
#   for line in existing.splitLines():
#     case state
#     of "init":
#       lines.add(line)
#       if line == START_SENTINEL:
#         lines.add(body)
#         state = "inside"
#     of "inside":
#       if line == END_SENTINEL:
#         lines.add(line)
#         state = "after"
#     of "after":
#       lines.add(line)
#     else:
#       raise ValueError.newException("Invalid state: " & state)
    
#   if state == "init":
#     lines.add(START_SENTINEL)
#     lines.add(body)
#     lines.add(END_SENTINEL)
#     lines.add("")
#   writeFile(ctx.rootDir/"nim.cfg", lines.join("\n"))

# proc ensureLinuxStylePath(x: string): string =
#   when defined(windows):
#     x.replace("\\", "/")
#   else:
#     x

# proc refreshNimCfg*(ctx: PkgerContext) =
#   let pinned = ctx.getImmediatePinnedReqs()
#   var nimPaths: seq[string]
#   for pin in pinned:
#     let srcPath = ctx.ondiskPath(pin.toReq())
#     nimPaths.add(getNimPathsFromProject(srcPath).mapIt(relativePath(srcPath/it, ctx.rootDir).ensureLinuxStylePath()))
#   ctx.setNimCfgDirs(nimPaths)

#---------------------------------------------------------
# Requirement gathering
#---------------------------------------------------------
proc list_requirements_nimble_file(path: string): seq[Requirement] =
  let parsed = parseNimbleFile(path)
  for req in parsed.requires:
    result.add((
      sourceFile: path.absolutePath,
      sourcePkg: parsed.name,
      reqstring: req,
    ))

proc list_requirements_pkger_json(path: string): seq[Requirement] =
  discard

proc list_requirements(path: string): seq[Requirement] =
  ## List all the requirements defined by this directory or file
  if fileExists(path):
    if path.endsWith(".nimble"):
      return list_requirements_nimble_file(path)
    elif path.extractFilename == "pkger.json":
      return list_requirements_pkger_json(path)
    else:
      discard
  else:
    for item in walkDir(path):
      if item.kind == pcFile:
        result.add(list_requirements(item.path))

#---------------------------------------------------------
# Commands
#---------------------------------------------------------



# proc use(ctx: PkgerContext, req: Req, parent = ""): seq[PinnedReq] =
#   let pinned = ctx.ensurePresent(req)
#   result.add(pinned)
#   # if recursive:
#   #   let subparent = pinned.pkgname
#   #   let path = ctx.ondiskPath(pinned.toReq())
#   #   for nreq in listNimbleRequires(path):
#   #     let childreq = ctx.toReq(nreq.ReqNimbleDesc, subparent)
#   #     if childreq.pkgname in encountered:
#   #       continue
#   #     encountered.add(childreq.pkgname)
#   #     result.add(ctx.use(childreq, recursive = true))
#   if parent == "":
#     ctx.add(result)
#     ctx.refreshNimCfg()

# proc use(ctx: PkgerContext, pkg: ReqDesc, parent = ""): seq[PinnedReq] =
#   let req = ctx.toReq(pkg, parent = parent)
#   ctx.use(req)

# proc cmd_remove(ctx: PkgerContext, pkg: ReqDesc) =
#   let name = pkg.string
#   let pinned = ctx.getImmediatePinnedReqs()
#   var newpinned: seq[PinnedReq]
#   for pin in pinned:
#     if pin.pkgname == name:
#       continue
#     else:
#       newpinned.add(pin)
#   ctx.setPinnedReqs(newpinned)
#   ctx.refreshNimCfg()

# proc cmd_fetch(ctx: PkgerContext) =
#   ## Fetch all the source packages that are missing
#   let pinned = ctx.getRecursivePinnedReqs().sorted(proc (a,b: ContextualPinnedReq): int =
#     cmp(a.pinned.pkgname, b.pinned.pkgname)
#   )
#   var newpinned: seq[PinnedReq]
#   for (octx, pin) in pinned:
#     stdout.write(pin.pkgname & " ...")
#     let res = ctx.ensurePresent(pin.toReq())
#     if ctx == octx:
#       newpinned.add(res)
#     stdout.write(" OK\n")
#   ctx.setPinnedReqs(newpinned)
#   ctx.refreshNimCfg()

proc cmd_listreqs(dir_or_nimblefile: string) =
  for req in list_requirements(dir_or_nimblefile):
    echo &"{req.reqstring} (from {req.sourcePkg})"

# proc cmd_status(ctx: PkgerContext) =
#   ## Print out a human readable status of dependencies
#   let installed = ctx.installedPackages()
#   var installedMap = newTable[string, InstalledPackage](installed.len)
#   for pkg in installed:
#     installedMap[pkg.name] = pkg
  
#   let allreqs = sorted(ctx.allReqs())
#   var used: seq[string]
#   var fulfilled: seq[string]
#   var missing: seq[string]
#   for req in allreqs:
#     var parts: seq[string]
#     parts.add req.label
#     if req.parent != "":
#       parts.add "(" & req.parent & ")"
#     let ver = $req.version
#     if ver != "":
#       parts.add ver
#     if installedMap.hasKey(req.name):
#       used.add(req.name)
#       let inst = installedMap[req.name]
#       parts = concat(@["[x]"], parts, @["(" & inst.nice & ")"])
#       fulfilled.add(parts.join(" "))
#     else:
#       parts = concat(@["[ ]"], parts)
#       missing.add(parts.join(" "))
#   for x in fulfilled:
#     echo x
#   for x in missing:
#     echo x
  
#   for inst in installed:
#     if inst.name notin used:
#       echo &"[x] {inst.name} ({inst.version} {inst.sha})"

#---------------------------------------------------------
# plumbing
#---------------------------------------------------------
# proc cmd_updatepackagelist(ctx: PkgerContext) =
#   info &"updating package list for {ctx.rootDir}"
#   updatePackagesDir(ctx)

#---------------------------------------------------------
# porcelain
#---------------------------------------------------------
proc cmd_init(dirname: string, given_pkgerdir: string) =
  info &"initializing pkger in {dirname}"
  let pkgerconfig = dirname/"pkger.json"
  if fileExists(pkgerconfig):
    warn &"pkger already initialized"
    return
  
  writeFile(pkgerconfig, pretty(%* {
    "dir": given_pkgerdir,
  }) & "\n")
  let pkgerdir = dirname/given_pkgerdir
  if not fileExists(pkgerdir/"deps.json"):
    createDir pkgerdir
    writeFile(pkgerdir/"deps.json", "{}")
  if not fileExists(pkgerdir/".gitignore"):
    writeFile(pkgerdir/".gitignore", """
lazy
""")
  let ctx = pkgerContext(dirname)
  # ctx.setPinnedReqs(@[])
  # info &"created deps.json"
  # cmd_updatepackagelist(ctx)

var p = newParser:
  # option("-d", "--depsdir", default=some("pkger"), help="Directory where pkger will keep deps")
  command("init"):
    option("--dir", "-d", help="Directory to store pkger information in", default=some("pkger"))
    run:
      cmd_init(getCurrentDir(), opts.dir)
  # command("status"):
  #   run:
  #     cmd_status(pkgerContext())
  command("add"):
    help("Add a package to this project.")
    flag("--no-deps", help="If provided, don't also add the packages deps")
    arg("package", help="package, package@version, package@sha, ./localpath, https://github.com/path/to/repo@sha, etc...")
    run:
      discard
      # discard use(pkgerContext(), opts.package.ReqDesc)
  # command("fetch"):
  #   help("Fetch all the external packages that are missing")
  #   run:
  #     cmd_fetch(pkgerContext())
  command("listreqs"):
    arg("path", help="Path to .nimble file, pkger.json or containing dir", default = some("."))
    run:
      cmd_listreqs(opts.path)
  # command("remove"):
  #   help("No longer use a package in this project")
  #   arg("package", help="package name")
  #   run:
  #     cmd_remove(pkgerContext(), opts.package.ReqDesc)
  # command("low"):
  #   command("updatepackagelist"):
  #     run:
  #       var ctx = pkgerContext()
  #       cmd_updatepackagelist(ctx)
  #   command("gennimcfg"):
  #     run:
  #       refreshNimCfg(pkgerContext())

proc cli*(args: seq[string]) =
  try:
    p.run(args)
  except UsageError as e:
    stderr.writeLine getCurrentExceptionMsg()
    raise

when isMainModule:
  addHandler(newConsoleLogger())
  cli(commandLineParams())
