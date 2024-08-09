type
  DepKind* = enum
    fmUnknown = ""
    fmGitRepo = "git"
    fmHgRepo = "hg"
    fmLocalFile = "local"
  
  Dep* = tuple
    name: string
    url: string
    kind: DepKind
    sha: string
    parent: string

  NumericVersion* = distinct seq[int]

  VersionType* = enum
    vNumeric
    vSHA
    vAnyVersion
    vRange
  Version* = object
    case kind*: VersionType
    of vNumeric:
      nver*: NumericVersion
    of vSHA:
      sha*: string
    of vAnyVersion:
      discard
    of vRange:
      vrange*: string
  
  VersionSpec* = distinct string

  DepAndVersion* = tuple
    dep: Dep
    version: Version

  ReqDesc* = distinct string
  ReqNimbleDesc* = distinct string

  RawReq* = tuple
    name: string
    label: string
    parent: string
    version: string

  ParsedNimbleReq* = object
    case isUrl*: bool
    of true:
      url*: string
    of false:
      name*: string
    version*: string

  ReqSource* = tuple
    url: string
    kind: DepKind

  Req* = tuple
    pkgname: string
    parent: string
    src: ReqSource
    version: Version
  
  PinnedReq* = tuple
    pkgname: string
    parent: string
    src: ReqSource
    sha: string
  
  InstalledPackage* = tuple
    name: string
    version: string
    sha: string
