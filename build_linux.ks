#!/usr/bin/env kr
import "scripts/tooling.k"

just run {
    if sh("uname -s") != "Linux" || sh("uname -m") != "x86_64" {
        print("Build Brain Linux on an x86_64 Linux host.")
        exit(1)
    }
    let root = repoRoot()
    let krypton = env("KRYPTON_ROOT")
    if krypton == "" { print("Set KRYPTON_ROOT to the Linux Krypton installation.")  exit(1) }
    let frontend = krypton + "/compiler/linux_x86/kcc-x64"
    let backend = krypton + "/compiler/linux_x86/elf_host"
    let stage = sh("mktemp -d /tmp/brain-linux-build.XXXXXX")
    if stage == "" { exit(1) }
    checked("mkdir -p " + quoteArg(stage + "/brain-linux"))
    checked("env KRYPTON_ROOT=" + quoteArg(krypton) + " " + quoteArg(frontend) + " --ir " + quoteArg(root + "/brain-linux.ks") + " > " + quoteArg(stage + "/brain.ir"))
    checked(quoteArg(backend) + " " + quoteArg(stage + "/brain.ir") + " " + quoteArg(stage + "/brain-linux/brain"))
    checked("chmod +x " + quoteArg(stage + "/brain-linux/brain"))
    checked("cp " + quoteArg(root + "/LICENSE") + " " + quoteArg(stage + "/brain-linux/LICENSE"))
    checked("cp " + quoteArg(root + "/codebrain.png") + " " + quoteArg(stage + "/brain-linux/brain.png"))
    checked("cp " + quoteArg(root + "/packaging/brain-linux.desktop") + " " + quoteArg(stage + "/brain-linux/brain.desktop"))
    checked("mkdir -p " + quoteArg(root + "/dist"))
    checked("tar -czf " + quoteArg(stage + "/brain-linux-x86_64.tar.gz") + " -C " + quoteArg(stage) + " brain-linux")
    checked("cp " + quoteArg(stage + "/brain-linux-x86_64.tar.gz") + " " + quoteArg(root + "/dist/brain-linux-x86_64.tar.gz"))
    checked("mkdir -p " + quoteArg(root + "/dist/brain-linux"))
    checked("cp -R " + quoteArg(stage + "/brain-linux/.") + " " + quoteArg(root + "/dist/brain-linux"))
    checked("rm -rf " + quoteArg(stage))
    print("Built dist/brain-linux/brain and dist/brain-linux-x86_64.tar.gz")
}
