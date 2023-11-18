################## IAM POLICIES/ROLES ##################

data "aws_iam_policy" "admin_policy" {
  name = "AdministratorAccess"
}

resource "aws_iam_role" "codepipeline_role" {
  name_prefix = "role-codepipeline-${var.app_name_prefix}-"
  description = "Role for ${var.app_name_prefix} Pipeline"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name_prefix = "policy-codepipeline-${var.app_name_prefix}-"
  role        = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${var.cicd_bucket_name}",
        "arn:aws:s3:::${var.cicd_bucket_name}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect":"Allow",
      "Action": [
        "codecommit:GetBranch",
        "codecommit:GetCommit",
        "codecommit:UploadArchive",
        "codecommit:GetUploadArchiveStatus",
        "codecommit:CancelUploadArchive"
      ],
      "Resource": [
        "${aws_codecommit_repository.app_repo.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:Decrypt"
        ],
      "Resource": [
          "${var.cicd_key_arn}"
        ]
    } 
  ]
}
EOF
}

resource "aws_iam_role" "codebuild_role" {
  name_prefix = "role-codebuild-${var.app_name_prefix}-"
  description = "Role for ${var.app_name_prefix} Codebuild projects"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codebuild_admin_capabilities" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = data.aws_iam_policy.admin_policy.arn
}

resource "aws_iam_role" "cloudwatch_events_role" {
  name_prefix = "role-cw-events-${var.app_name_prefix}-"
  description = "Role for ${var.app_name_prefix} Cloudwatch Events"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch_events_policy" {
  name_prefix = "policy-cw-events-${var.app_name_prefix}-"
  role        = aws_iam_role.cloudwatch_events_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codepipeline:StartPipelineExecution"
      ],
      "Resource": [
        "${aws_codepipeline.pipeline_1.arn}"
      ]
    }
  ]
}

EOF
}

################## CLOUDWATCH ##################

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.app_name_prefix}"
  retention_in_days = 0
}

resource "aws_cloudwatch_event_rule" "app_repo_event_in_main" {
  name_prefix   = "${var.app_name_prefix}-repo-main"
  description   = "${aws_codecommit_repository.app_repo.repository_name} - Capture changes in main branch"
  is_enabled    = true
  event_pattern = <<EOF
{
  "source": [
    "aws.codecommit"
  ],
  "detail-type": [
    "CodeCommit Repository State Change"
  ],
  "resources": [
    "${aws_codecommit_repository.app_repo.arn}"
  ],
  "detail": {
    "referenceType": [
      "branch"
    ],
    "referenceName": [
      "main"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "invoke_pipeline_1" {
  target_id = "Run-${aws_codepipeline.pipeline_1.name}"
  rule      = aws_cloudwatch_event_rule.app_repo_event_in_main.name
  arn       = aws_codepipeline.pipeline_1.arn
  role_arn  = aws_iam_role.cloudwatch_events_role.arn
}

################## CODE-COMMIT ##################

resource "aws_codecommit_repository" "app_repo" {
  repository_name = "${var.app_name_prefix}"
  description     = "${var.app_name_prefix} codebase"
}

################## CODE-PIPELINE ##################

resource "aws_codepipeline" "pipeline_1" {
  name     = "${var.app_name_prefix}"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = var.cicd_bucket_name
    type     = "S3"
    # Uses S3 KMS encryption
    encryption_key {
      id   = var.cicd_key_arn
      type = "KMS"
    }

  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      namespace        = "SourceVariables"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      input_artifacts  = []
      output_artifacts = ["source-code"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.app_repo.repository_name
        BranchName           = var.app_repo_production_branch
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Plan"

    action {
      name             = "Terraform_Plan"
      namespace        = "PlanVariables"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-code"]
      output_artifacts = []
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
        EnvironmentVariables = jsonencode([
          {
            name  = "Release_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "Commit_ID"
            value = "#{SourceVariables.CommitId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_VAR_repository_name"
            value = var.app_name_prefix
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_VAR_repository_uri"
            value = "codecommit::${var.aws_region}://${var.app_name_prefix}"
            type  = "PLAINTEXT"
          },
          {
            name  = "Phase"
            value = "PLAN"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "Approval"

    action {
      name             = "Approve"
      category         = "Approval"
      owner            = "AWS"
      provider         = "Manual"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      configuration = {
        CustomData = "Approve IaC changes"
      }
    }
  }

  stage {
    name = "Apply"

    action {
      name             = "Terraform_Apply"
      namespace        = "ApplyVariables"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source-code"]
      output_artifacts = []
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
        EnvironmentVariables = jsonencode([
          {
            name  = "Release_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "Commit_ID"
            value = "#{SourceVariables.CommitId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_VAR_repository_name"
            value = var.app_name_prefix
            type  = "PLAINTEXT"
          },
          {
            name  = "TF_VAR_repository_uri"
            value = "codecommit::${var.aws_region}://${var.app_name_prefix}"
            type  = "PLAINTEXT"
          },
          {
            name  = "Phase"
            value = "APPLY"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }
}

################## CODE-BUILD ##################

resource "aws_codebuild_project" "terraform_build" {
  name          = "${var.app_name_prefix}"
  description   = "${var.app_name_prefix} Terraform Plan/Apply jobs"
  badge_enabled = false
  build_timeout = "60"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_VERSION"
      value = var.terraform_version
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  source {
    type = "CODEPIPELINE"
  }
}
