#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mapfile -d '' templates < <(find templates -type f -name '*.yml' -print0 | sort -z)

if ((${#templates[@]} == 0)); then
  echo "No se encontraron plantillas .yml"
  exit 0
fi

python3 - <<'PY'
import pathlib
import sys

try:
    import yaml
except ModuleNotFoundError:
    print("WARN: PyYAML no esta instalado; se omite la carga YAML local.")
    raise SystemExit(0)


class CfnLoader(yaml.SafeLoader):
    pass


def unknown_tag(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return {suffix: loader.construct_scalar(node)}
    if isinstance(node, yaml.SequenceNode):
        return {suffix: loader.construct_sequence(node)}
    if isinstance(node, yaml.MappingNode):
        return {suffix: loader.construct_mapping(node)}
    return None


CfnLoader.add_multi_constructor("!", unknown_tag)

failed = False
for path in sorted(pathlib.Path("templates").rglob("*.yml")):
    try:
        data = yaml.load(path.read_text(), Loader=CfnLoader)
        if not isinstance(data, dict):
            raise ValueError("el documento no contiene un objeto YAML de nivel superior")
        if "Resources" not in data:
            raise ValueError("falta la seccion Resources")
        print(f"YAML OK: {path}")
    except Exception as exc:
        failed = True
        print(f"YAML ERROR: {path}: {exc}", file=sys.stderr)

if failed:
    raise SystemExit(1)
PY

if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint "${templates[@]}"
else
  echo "WARN: cfn-lint no esta instalado; se omite validacion CloudFormation."
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint "${templates[@]}" README.md
else
  echo "WARN: yamllint no esta instalado; se omite validacion de estilo YAML."
fi
