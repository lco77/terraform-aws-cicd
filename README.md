# AWS CI/CD pipeline generator for Terraform based IaC

## Description
This repo is used to create CI/CD pipelines suitable for Terraform managed IaC.

Pre-requisites:
- S3 bucket to store Terraform state files
- S3 bucket to store CICD artifacts
- DynamoDB table to store Terraform locks

Each pipeline is made of individual components such as:
- Roles
- Policies
- Cloudwatch rules
- CodeCommit repo
- CodeBuild environment
- CodePipeline pipeline
- etc...


The CI/CD workflow includes the following stages:
- Source (from the app CodeCommit repository)
- Plan (To perform Terraform Plan operation)
- Approval (Manual approval of Terraform plan)
- Apply (Terraform apply and actual build)


## Usage
To deploy a new CI/CD infrastructure:
- open cloudshell

- install Terraform
```
export TF_VERSION=1.5.7
wget -q https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
unzip terraform_${TF_VERSION}_linux_amd64.zip
```

- clone repo
```
git clone repo_url
cd repo_folder
```

- create a new sub-directory <pipeline_name> for your new config 
```
mkdir subdir
cd subdir
```

- create backend.cfg in the subdirectory
```
bucket         = "s3-bucket-name" --> your S3 bucket name for terraform states
key            = "s3-bucket-key/pipeline-name.json" --> Change this value to match var.app_name_prefix below 
region         = "eu-west-1"
encrypt        = true
kms_key_id     = "..." --> your KMS key id
dynamodb_table = "..." --> your DynamoDB table name for terraform locks
```

- create terraform.tfvars in the subdirectory
```
app_name_prefix            = "example" --> change this
app_repo_production_branch = "main"
aws_region                 = "eu-west-1"
cicd_repository_name       = "example"
terraform_version          = "1.5.7"
cicd_key_arn               = "..." --> your KMS key id
cicd_bucket_name           = "..." --> your S3 bucket name for CICD artifacts
```

- deploy resources
```
../terraform init -backend-config="example/backend.cfg"
../terraform plan -var-file="example/terraform.tfvars" -out="example/plan.out"
../terraform apply "example/plan.out"
```

- Manually create buildspec.yml in the new repo to initialize the main branch

- Start coding!

- On a later stage, you can also apply changes to all pipelines in POWERSHELL as follows:
```
$dir = "example","..."
foreach ($d in $dir){
    terraform init -backend-config="$d/backend.cfg" -reconfigure; terraform plan -var-file="$d/terraform.tfvars" -out="$d/plan.out"; terraform apply "$d/plan.out"
}
```
