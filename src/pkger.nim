import argparse

var p = newParser:
  option("-d", "--depsdir", default=some("pkger"), help="Directory where pkger will keep deps")
  command("init"):
    run:
      echo $opts.parentOpts.depsdir
  command("low"):
    command("updatepackagelist"):
      run:
        echo "update package list?"

proc cli*(args: seq[string]) =
  try:
    p.run(args)
  except UsageError as e:
    stderr.writeLine getCurrentExceptionMsg()
    raise  

when isMainModule:
  cli(commandLineParams())
