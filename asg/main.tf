data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  subnet_prefix = join(".",[split(".", var.vpc_cidr)[0],split(".", var.vpc_cidr)[1]])
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name = var.vpc_name
  cidr = var.vpc_cidr
  azs             = data.aws_availability_zones.available.zone_ids
  private_subnets = ["${local.subnet_prefix}.0.0/24", "${local.subnet_prefix}.1.0/24"]
  public_subnets  = ["${local.subnet_prefix}.3.0/24", "${local.subnet_prefix}.4.0/24"]
  enable_dns_hostnames = true
  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "aws_kms_key" "ecs" {
  description             = var.cluster_name
  deletion_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = var.cluster_name
}

resource "aws_ecs_cluster" "ecs" {
  name = var.cluster_name

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.ecs.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs.name
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/ecs/php"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "task" {
  family = "php"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn = aws_iam_role.ecs_tasks_execution_role.arn
  container_definitions = jsonencode([
    {
      name      = "php"
      image     = "registry.k8s.io/hpa-example"
      essential = true
      portMappings = [
        {
          containerPort = 80
          appProtocol = "http"
        }
      ]
    logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "X86_64"
  }

}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "aws_security_group" "scaling" {
  name        = "Scaling"
  description = "Allow Scaling inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_scaling"
  }
}

resource "aws_security_group" "task_scaling" {
  name        = "task_scaling"
  description = "Allow task_scaling inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups = [aws_security_group.scaling.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_scaling"
  }
}

resource "aws_lb" "scaling" {
  name               = "scaling"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.scaling.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "scaling" {
  name        = "scaling"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.scaling.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.scaling.arn
  }
}


data "aws_iam_policy_document" "ecs_tasks_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_tasks_execution_role" {
  name               = "scaling"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_tasks_execution_role.json}"
}

resource "aws_iam_role_policy_attachment" "ecs_tasks_execution_role" {
  role       = aws_iam_role.ecs_tasks_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "php" {
  name            = "php"
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1
  launch_type = "FARGATE"

    network_configuration {
        subnets = module.vpc.private_subnets
        security_groups = [aws_security_group.task_scaling.id]
        assign_public_ip = false
    }

  load_balancer {
    target_group_arn = aws_lb_target_group.scaling.arn
    container_name   = "php"
    container_port   = 80
  }

}

module "ecs-service-autoscaling" {
  source           = "cn-terraform/ecs-service-autoscaling/aws"
  ecs_cluster_name = aws_ecs_cluster.ecs.name
  ecs_service_name = aws_ecs_service.php.name
  name_prefix      = aws_ecs_service.php.name
}




