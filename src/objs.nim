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

  NumericVersion* = distinct seq[int]

  VersionType* = enum
    vLatest
    vNumeric
    vVCS
  Version* = object
    case kind*: VersionType
    of vNumeric:
      nver*: NumericVersion
    of vVCS:
      sha*: string  
    of vLatest:
      discard

  DepAndVersion* = tuple
    dep: Dep
    version: Version
  
