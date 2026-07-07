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
    print("WARN: PyYAML no esta instalado; se omite la carga YAML local y los checks de politica.")
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


def is_truthy(value):
    return value is True or str(value).lower() == "true"


def has_encrypted_root_volume(block_device_mappings):
    if not isinstance(block_device_mappings, list):
        return False
    for mapping in block_device_mappings:
        if not isinstance(mapping, dict):
            continue
        ebs = mapping.get("Ebs")
        if isinstance(ebs, dict) and is_truthy(ebs.get("Encrypted")) and ebs.get("VolumeType") == "gp3":
            return True
    return False


def iter_ingress_rules(value):
    if isinstance(value, list):
        for item in value:
            yield from iter_ingress_rules(item)
    elif isinstance(value, dict):
        if "CidrIp" in value or "CidrIpv6" in value:
            yield value
        for child in value.values():
            yield from iter_ingress_rules(child)


def includes_port(rule, port):
    try:
        from_port = int(rule.get("FromPort", port))
        to_port = int(rule.get("ToPort", port))
    except (TypeError, ValueError):
        return False
    return from_port <= port <= to_port


def validate_policy(path, data):
    errors = []
    resources = data.get("Resources", {})
    for logical_id, resource in resources.items():
        if not isinstance(resource, dict):
            continue

        resource_type = resource.get("Type")
        props = resource.get("Properties") or {}
        label = f"{path}:{logical_id}"

        if resource_type == "AWS::EC2::Instance":
            metadata_options = props.get("MetadataOptions") or {}
            if metadata_options.get("HttpTokens") != "required":
                errors.append(f"{label}: EC2 debe requerir IMDSv2 con MetadataOptions.HttpTokens=required")
            if not has_encrypted_root_volume(props.get("BlockDeviceMappings")):
                errors.append(f"{label}: EC2 debe declarar volumen raiz gp3 cifrado")

        if resource_type == "AWS::EC2::SecurityGroup":
            for rule in iter_ingress_rules(props.get("SecurityGroupIngress")):
                if rule.get("CidrIp") == "0.0.0.0/0" and includes_port(rule, 22):
                    errors.append(f"{label}: no se permite SSH abierto a 0.0.0.0/0")

        if resource_type == "AWS::Logs::LogGroup" and "RetentionInDays" not in props:
            errors.append(f"{label}: LogGroup debe definir RetentionInDays")

        if resource_type == "AWS::S3::Bucket":
            public_block = props.get("PublicAccessBlockConfiguration") or {}
            required_blocks = ["BlockPublicAcls", "BlockPublicPolicy", "IgnorePublicAcls", "RestrictPublicBuckets"]
            if "BucketEncryption" not in props:
                errors.append(f"{label}: S3 debe habilitar BucketEncryption")
            if not all(is_truthy(public_block.get(key)) for key in required_blocks):
                errors.append(f"{label}: S3 debe bloquear acceso publico en las cuatro opciones")
            if resource.get("DeletionPolicy") != "Retain" or resource.get("UpdateReplacePolicy") != "Retain":
                errors.append(f"{label}: S3 debe usar DeletionPolicy y UpdateReplacePolicy Retain")

        if resource_type == "AWS::DynamoDB::Table":
            pitr = props.get("PointInTimeRecoverySpecification") or {}
            sse = props.get("SSESpecification") or {}
            if not is_truthy(pitr.get("PointInTimeRecoveryEnabled")):
                errors.append(f"{label}: DynamoDB debe habilitar PointInTimeRecovery")
            if not is_truthy(sse.get("SSEEnabled")):
                errors.append(f"{label}: DynamoDB debe habilitar SSE")
            if resource.get("DeletionPolicy") != "Retain" or resource.get("UpdateReplacePolicy") != "Retain":
                errors.append(f"{label}: DynamoDB debe usar DeletionPolicy y UpdateReplacePolicy Retain")

        if resource_type == "AWS::SQS::Queue":
            if not is_truthy(props.get("SqsManagedSseEnabled")) and "KmsMasterKeyId" not in props:
                errors.append(f"{label}: SQS debe tener cifrado administrado o KMS")

        if resource_type == "AWS::SNS::Topic" and "KmsMasterKeyId" not in props:
            errors.append(f"{label}: SNS Topic debe declarar KmsMasterKeyId")

    return errors


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

        policy_errors = validate_policy(path, data)
        if policy_errors:
            failed = True
            for error in policy_errors:
                print(f"POLICY ERROR: {error}", file=sys.stderr)
        else:
            print(f"POLICY OK: {path}")
    except Exception as exc:
        failed = True
        print(f"YAML ERROR: {path}: {exc}", file=sys.stderr)

if failed:
    raise SystemExit(1)
PY

if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint "${templates[@]}" --format parseable
else
  echo "WARN: cfn-lint no esta instalado; se omite validacion CloudFormation."
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint -c .yamllint "${templates[@]}" .github/workflows/validate.yml .yamllint
else
  echo "WARN: yamllint no esta instalado; se omite validacion de estilo YAML."
fi
