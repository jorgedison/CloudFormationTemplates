# AWS CloudFormation Templates

Repositorio de ejemplos CloudFormation organizados por dominio de AWS. Plantillas pequeñas, legibles y reutilizables para aprender y arrancar pruebas de infraestructura.

## Estructura

```text
templates/
  compute/
    ec2/
  database/
    dynamodb/
  monitoring/
    cloudwatch/
  networking/
    vpc/
  serverless/
    lambda-api/
  storage/
    s3/
scripts/
  validate.sh
```

## Catalogo

| Categoria | Plantilla | Proposito |
| --- | --- | --- |
| Networking | `templates/networking/vpc/basic-vpc.yml` | VPC con dos subnets publicas, Internet Gateway, rutas y Flow Logs opcionales. |
| Compute | `templates/compute/ec2/ec2-ssm-managed.yml` | EC2 administrable por SSM, sin SSH abierto. Tags de ambiente. |
| Compute | `templates/compute/ec2/ec2-ssh-restricted.yml` | EC2 con SSH restringido por CIDR y KeyPair opcional. Tags de ambiente. |
| Compute | `templates/compute/ec2/01-ec2-instance.yml` | Ejemplo basico de EC2. |
| Compute | `templates/compute/ec2/02-ec2-elastic-ip.yml` | EC2 con Elastic IP. |
| Compute | `templates/compute/ec2/03-ec2-mappings.yml` | EC2 usando mappings por ambiente. |
| Compute | `templates/compute/ec2/04-ec2-parameters.yml` | EC2 con parametros y SSH restringido. |
| Compute | `templates/compute/ec2/05-ec2-elastic-ip-security-group.yml` | EC2 con Elastic IP y Security Group. |
| Compute | `templates/compute/ec2/06-ec2-user-data-web.yml` | EC2 con Apache via UserData y señalizacion cfn-signal. |
| Storage | `templates/storage/s3/private-bucket.yml` | Bucket S3 privado con cifrado, versionado, bloqueo publico y lifecycle de versiones. |
| Database | `templates/database/dynamodb/on-demand-table.yml` | Tabla DynamoDB on-demand con PITR, cifrado y sort key opcional. |
| Serverless | `templates/serverless/lambda-api/lambda-http-api.yml` | Lambda Python con API Gateway HTTP API, X-Ray, CORS, throttling y DLQ opcional. |
| Monitoring | `templates/monitoring/cloudwatch/billing-alarm.yml` | Alarma de billing con notificacion SNS y periodo configurable. |

## Despliegue

### 1. Crear una VPC de laboratorio

```bash
aws cloudformation deploy \
  --stack-name lab-vpc \
  --template-file templates/networking/vpc/basic-vpc.yml \
  --capabilities CAPABILITY_IAM
```

Obtienes los IDs con:

```bash
aws cloudformation describe-stacks \
  --stack-name lab-vpc \
  --query 'Stacks[0].Outputs'
```

> **Nota:** `EnableFlowLogs=true` por defecto. Requiere `CAPABILITY_IAM` por el rol de Flow Logs.
> Para desactivarlos: `--parameter-overrides EnableFlowLogs=false`

### 2. Crear una EC2 administrable por SSM

```bash
aws cloudformation deploy \
  --stack-name lab-ec2-ssm \
  --template-file templates/compute/ec2/ec2-ssm-managed.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    VpcId=vpc-xxxxxxxx \
    SubnetId=subnet-xxxxxxxx \
    EnvironmentName=dev
```

La subnet necesita salida a internet o VPC endpoints para SSM, SSM Messages y EC2 Messages.

### 3. Crear un bucket S3 privado

```bash
aws cloudformation deploy \
  --stack-name lab-s3-private \
  --template-file templates/storage/s3/private-bucket.yml \
  --parameter-overrides EnvironmentName=dev
```

Las versiones antiguas expiran tras 90 dias por defecto (configurable con `NoncurrentVersionRetentionDays`).

### 4. Crear una tabla DynamoDB

```bash
# Con sort key (defecto)
aws cloudformation deploy \
  --stack-name lab-dynamodb \
  --template-file templates/database/dynamodb/on-demand-table.yml \
  --parameter-overrides EnvironmentName=dev

# Solo partition key
aws cloudformation deploy \
  --stack-name lab-dynamodb-pk \
  --template-file templates/database/dynamodb/on-demand-table.yml \
  --parameter-overrides EnableSortKey=false EnvironmentName=dev
```

### 5. Crear una API serverless

```bash
aws cloudformation deploy \
  --stack-name lab-lambda-api \
  --template-file templates/serverless/lambda-api/lambda-http-api.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides EnvironmentName=dev
```

La DLQ SQS se crea por defecto (`EnableDlq=true`). Solo captura fallos de invocaciones asincronas.

### 6. Crear una alarma de billing

Las metricas de billing se publican en `us-east-1` y requieren tener habilitadas las alertas de facturacion en la cuenta.

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name lab-billing-alarm \
  --template-file templates/monitoring/cloudwatch/billing-alarm.yml \
  --parameter-overrides \
    AlarmEmail=tu-correo@example.com \
    MonthlyThresholdUsd=10 \
    AlarmPeriodSeconds=21600
```

Despues del despliegue debes confirmar la suscripcion SNS desde el correo recibido.

## Referencias cross-stack

Todos los templates exportan sus outputs principales con el patron `${AWS::StackName}-<Recurso>`.
Ejemplo para usar el VPC ID en otro stack:

```yaml
VpcId: !ImportValue 'lab-vpc-VpcId'
SubnetId: !ImportValue 'lab-vpc-PublicSubnetOneId'
```

## Validacion

Ejecuta:

```bash
./scripts/validate.sh
```

El script valida las plantillas con PyYAML y, si estan instalados, ejecuta `cfn-lint` y `yamllint`.

Herramientas recomendadas:

```bash
pip install cfn-lint yamllint
```

La configuracion de `cfn-lint` esta en `.cfnlintrc` (regiones, checks habilitados).

## Criterios de diseño

- Plantillas pequeñas y enfocadas en un solo recurso o patron.
- Parametros para valores de cuenta, VPC, subnet, ambiente y nombres opcionales.
- Sin AMIs hardcodeadas en EC2; se usa Parameter Store.
- Sin SSH abierto a internet por defecto.
- Recursos con cifrado o configuraciones seguras cuando aplica.
- `DeletionPolicy: Retain` en recursos con datos persistentes (S3 y DynamoDB).
- `Export` en todos los Outputs para referencias cross-stack con `!ImportValue`.
- Tags `Name`, `Environment` y `ManagedBy` en recursos principales.
- `CreationPolicy` + `cfn-signal` en instancias con UserData complejo.
- Flow Logs habilitados por defecto en VPC para auditoria de trafico.
- Lifecycle rules en S3 para limpiar versiones antiguas automaticamente.
- Sort key opcional en DynamoDB para soportar tablas de solo partition key.
- DLQ SQS opcional en Lambda para capturar fallos de invocaciones asincronas.
