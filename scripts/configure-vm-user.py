#!/usr/bin/env python3
"""Configure the VM login locally without printing its password or hash."""
import getpass
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
target = root / "disk_config" / "vm.local.toml"
if not sys.stdin.isatty():
    sys.exit("Execute este comando em um terminal interativo do Ubuntu.")
if target.exists():
    sys.exit("vm.local.toml já existe. Preserve-o e revise a configuração localmente.")
password = getpass.getpass("Senha local do usuário enthroned na VM: ")
if not password:
    sys.exit("A senha não pode ficar vazia.")
if password != getpass.getpass("Repita a senha: "):
    sys.exit("As senhas não coincidem. Nenhum arquivo foi criado.")
result = subprocess.run(
    ["openssl", "passwd", "-6", "-stdin"], input=password + "\n",
    text=True, capture_output=True, check=False,
)
if result.returncode or not result.stdout.startswith("$6$"):
    sys.exit("Não foi possível gerar o hash local. Nenhum arquivo foi criado.")
template = (root / "disk_config" / "vm.example.toml").read_text(encoding="utf-8")
assert template.count("REPLACE_WITH_LOCAL_HASH") == 1
content = template.replace("REPLACE_WITH_LOCAL_HASH", result.stdout.strip())
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    stream.write(content)
print("Login da VM configurado localmente. Senha e hash não foram exibidos.")
