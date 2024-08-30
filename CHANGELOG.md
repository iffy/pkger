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

