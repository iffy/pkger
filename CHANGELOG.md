# v0.2.2 - 2024-11-01

- **FIX:** Add test for websock repo

# v0.2.1 - 2024-09-05

- **FIX:** Fix `init` giving warnings about already being initialized when not needed

# v0.2.0 - 2024-09-05

- **BREAKING CHANGE:** There is now a config file named pkger.json stored in each package.
- **NEW:** When initializing a project, you can specify `--dir` to set where deps go

# v0.1.2 - 2024-09-04

- **FIX:** On Windows use Linux-style paths in nim.cfg"

# v0.1.1 - 2024-08-30

- **FIX:** Packages with submodules are now supported

# v0.1.0 - 2024-08-13

- **NEW:** Remove need for `pkger.json` file in projects and instead key off of `pkger/deps.json`
- **NEW:** When fetching, only do anything if the git repo isn't already at the right commit
- **NEW:** `pkger use` works on single packages with specific versions
- **FIX:** Fix tests on Windows
- **FIX:** If the package registry isn't downloaded, download it
- **FIX:** Handle nimble files that have multiple requires per line
- **FIX:** When using a dep, you can now specify a branch other than master and it will look for `origin/BRANCHNAME`

