# Builds of Retro Desktop: memory goes back to the system (-d:useMalloc), and
# a retroui checkout beside this one is used when there is one (RETROUI_SRC
# names another).
switch("define", "useMalloc")
let kit = getEnv("RETROUI_SRC", thisDir() & "/../retro/src")
if dirExists(kit): switch("path", kit)
# Android before 9 (Termux's API 24) has no posix_spawn: programs are
# started with fork and exec
when defined(android): switch("define", "useFork")
