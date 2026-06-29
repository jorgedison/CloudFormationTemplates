# AWS CloudFormation Templates

Repositorio de ejemplos CloudFormation organizados por dominio de AWS. La idea ya no es mostrar solo EC2, sino tener plantillas pequenas, legibles y reutilizables para aprender y arrancar pruebas de infraestructura.

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
| Networking | `templates/networking/vpc/basic-vpc.yml` | VPC con dos subnets publicas, Internet Gateway y rutas. |
| Compute | `templates/compute/ec2/ec2-ssm-managed.yml` | EC2 administrable por SSM, sin SSH abierto. |
| Compute | `templates/compute/ec2/ec2-ssh-restricted.yml` | EC2 con SSH restringido por CIDR. |
| Compute | `templates/compute/ec2/01-ec2-instance.yml` | Ejemplo basico de EC2. |
| Compute | `templates/compute/ec2/02-ec2-elastic-ip.yml` | EC2 con Elastic IP. |
| Compute | `templates/compute/ec2/03-ec2-mappings.yml` | EC2 usando mappings por ambiente. |
| Compute | `templates/compute/ec2/04-ec2-parameters.yml` | EC2 con parametros y SSH restringido. |
| Compute | `templates/compute/ec2/05-ec2-elastic-ip-security-group.yml` | EC2 con Elastic IP y Security Group. |
| Compute | `templates/compute/ec2/06-ec2-user-data-web.yml` | EC2 con Apache instalado via UserData. |
| Storage | `templates/storage/s3/private-bucket.yml` | Bucket S3 privado con cifrado, versionado y bloqueo publico. |
| Database | `templates/database/dynamodb/on-demand-table.yml` | Tabla DynamoDB on-demand con PITR y cifrado. |
| Serverless | `templates/serverless/lambda-api/lambda-http-api.yml` | Lambda Python expuesta con API Gateway HTTP API. |
| Monitoring | `templates/monitoring/cloudwatch/billing-alarm.yml` | Alarma de billing con notificacion por SNS. |

## Despliegue

### 1. Crear una VPC de laboratorio

```bash
aws cloudformation deploy \
  --stack-name lab-vpc \
  --template-file templates/networking/vpc/basic-vpc.yml
```

Obtienes los IDs con:

```bash
aws cloudformation describe-stacks \
  --stack-name lab-vpc \
  --query 'Stacks[0].Outputs'
```

### 2. Crear una EC2 administrable por SSM

```bash
aws cloudformation deploy \
  --stack-name lab-ec2-ssm \
  --template-file templates/compute/ec2/ec2-ssm-managed.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    VpcId=vpc-xxxxxxxx \
    SubnetId=subnet-xxxxxxxx
```

La subnet necesita salida a internet o VPC endpoints para SSM, SSM Messages y EC2 Messages.

### 3. Crear un bucket S3 privado

```bash
aws cloudformation deploy \
  --stack-name lab-s3-private \
  --template-file templates/storage/s3/private-bucket.yml
```

### 4. Crear una tabla DynamoDB

```bash
aws cloudformation deploy \
  --stack-name lab-dynamodb \
  --template-file templates/database/dynamodb/on-demand-table.yml
```

### 5. Crear una API serverless

```bash
aws cloudformation deploy \
  --stack-name lab-lambda-api \
  --template-file templates/serverless/lambda-api/lambda-http-api.yml \
  --capabilities CAPABILITY_IAM
```

### 6. Crear una alarma de billing

Las metricas de billing se publican en `us-east-1` y requieren tener habilitadas las alertas de facturacion en la cuenta.

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name lab-billing-alarm \
  --template-file templates/monitoring/cloudwatch/billing-alarm.yml \
  --parameter-overrides AlarmEmail=tu-correo@example.com MonthlyThresholdUsd=10
```

Despues del despliegue debes confirmar la suscripcion SNS desde el correo recibido.

## Validacion

Ejecuta:

```bash
./scripts/validate.sh
```

El script carga todas las plantillas `templates/**/*.yml` con PyYAML y, si estan instalados, tambien ejecuta `cfn-lint` y `yamllint`.

Herramientas recomendadas:

```bash
pip install cfn-lint yamllint
```

## Criterios usados

- Plantillas pequenas y enfocadas.
- Parametros para valores de cuenta, VPC, subnet y nombres opcionales.
- Sin AMIs hardcodeadas en EC2; se usa Parameter Store.
- Sin SSH abierto a internet por defecto.
- Recursos con cifrado o configuraciones seguras cuando aplica.
- `DeletionPolicy: Retain` en recursos con datos persistentes como S3 y DynamoDB.
