# Terraform Project Reference Guide

## Purpose

This README is a quick-reference guide for developers working on this
Terraform project. It explains the project layout, module design,
outputs, environment configuration, and common AWS networking patterns
discussed during development.

------------------------------------------------------------------------

# Project Structure

``` text
terraform/
│
├── backend.tf
├── providers.tf
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
│
├── environments/
│   ├── dev/
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── terraform.tfvars
│   └── prod/
│       └── terraform.tfvars
│
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ec2/
    ├── alb/
    └── rds/
```

------------------------------------------------------------------------

# Root Files

## versions.tf

Locks Terraform and provider versions.

``` hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

Responsibilities: - Terraform version - Provider version locking -
Dependency compatibility

------------------------------------------------------------------------

## providers.tf

Configures AWS provider.

``` hcl
provider "aws" {
  region = var.aws_region
}
```

Responsibilities: - Authentication - Region selection - Provider
configuration

------------------------------------------------------------------------

## backend.tf

Configures remote Terraform state.

Example:

``` hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```

Responsibilities: - Shared state - State locking - Version history -
Team collaboration

------------------------------------------------------------------------

## variables.tf

Declares input variables.

``` hcl
variable "vpc_cidr" {
  type = string
}

variable "aws_region" {
  type = string
}
```

Contains declarations only.

Values come from:

-   terraform.tfvars
-   -var
-   -var-file
-   environment variables

------------------------------------------------------------------------

## main.tf

Root orchestration layer.

Creates no business logic itself.

Instead it wires reusable modules together.

Example:

``` hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr = var.vpc_cidr
}

module "alb" {
  source = "./modules/alb"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
}

module "ec2" {
  source = "./modules/ec2"

  subnet_id = module.vpc.public_subnets[0]
}
```

------------------------------------------------------------------------

## outputs.tf

Exports useful values.

Example:

``` hcl
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns" {
  value = module.alb.alb_dns
}
```

Outputs are consumed by:

-   Humans
-   Other Terraform configurations
-   CI/CD
-   Automation

------------------------------------------------------------------------

# Environments

Each environment contains only values.

Example:

``` text
environments/
    dev/
        terraform.tfvars

    staging/
        terraform.tfvars

    prod/
        terraform.tfvars
```

Example:

``` hcl
aws_region    = "us-east-1"
vpc_cidr      = "10.0.0.0/16"
instance_type = "t3.micro"
```

Deploy using

``` bash
terraform apply \
-var-file=environments/dev/terraform.tfvars
```

The infrastructure code never changes between environments.

Only variable values do.

------------------------------------------------------------------------

# Modules

Each folder under modules represents one reusable infrastructure
component.

Example:

``` text
modules/

    vpc/

        main.tf
        variables.tf
        outputs.tf
```

Each module behaves like a miniature Terraform project.

------------------------------------------------------------------------

## Module Structure

### main.tf

Creates resources.

Example:

``` hcl
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
}
```

------------------------------------------------------------------------

### variables.tf

Declares module inputs.

``` hcl
variable "vpc_cidr" {
  type = string
}
```

Think of these as function parameters.

------------------------------------------------------------------------

### outputs.tf

Exports values for other modules.

``` hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}
```

Outputs define the public interface of a module.

------------------------------------------------------------------------

# Module Communication

Modules never reference each other directly.

Correct flow:

``` text
VPC Module
     │
 outputs
     │
Root Module
     │
 inputs
     │
EC2 / ALB / RDS Module
```

Example:

``` hcl
module "ec2" {
  source = "./modules/ec2"

  subnet_id = module.vpc.public_subnets[0]
  vpc_id    = module.vpc.vpc_id
}
```

Reference syntax:

``` hcl
module.<module_name>.<output_name>
```

Example:

``` hcl
module.vpc.vpc_id
module.vpc.public_subnets
module.vpc.private_subnets
```

------------------------------------------------------------------------

# Resource Multiplication using count

Example:

``` hcl
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id     = aws_vpc.this.id
  cidr_block = var.public_subnets[count.index]
}
```

Given

``` hcl
public_subnets = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]
```

Terraform creates

    aws_subnet.public[0]
    aws_subnet.public[1]

Iteration:

  count.index   CIDR
  ------------- -------------
  0             10.0.1.0/24
  1             10.0.2.0/24

Access:

``` hcl
aws_subnet.public[0].id
aws_subnet.public[1].id
aws_subnet.public[*].id
```

Prefer `for_each` when resources should have stable identities.

------------------------------------------------------------------------

# Route Tables

## AWS Default Route Table

Every VPC automatically receives a main route table.

Terraform can manage it using:

``` hcl
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
```

If Terraform created the VPC, importing is unnecessary because
`default_route_table_id` is already known.

------------------------------------------------------------------------

## Custom Route Tables

Example:

``` hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.public.id
}
```

One route table can be associated with multiple subnets.

Typical design:

-   Public Route Table → Public Subnets
-   Private Route Table → Private Subnets

------------------------------------------------------------------------

# NAT Gateway depends_on

Example:

``` hcl
depends_on = [
  aws_internet_gateway.example
]
```

Reason:

Terraform only infers dependencies from references.

The NAT Gateway references:

-   Elastic IP
-   Subnet

It does not reference the Internet Gateway.

AWS, however, requires the VPC to have an attached Internet Gateway
before a public NAT Gateway is successfully provisioned.

The explicit dependency prevents race conditions during creation.

------------------------------------------------------------------------

# Best Practices

-   Keep modules focused on one responsibility.
-   Never hardcode IDs between modules.
-   Expose only required outputs.
-   Use the root module as the wiring layer.
-   Store state remotely.
-   Separate environments with tfvars.
-   Prefer custom route tables over modifying the default one unless
    required.
-   Use `for_each` instead of `count` when identity stability matters.
-   Version-lock Terraform and providers.
-   Keep module interfaces small and well documented.

------------------------------------------------------------------------

# `count` vs `for_each` in Terraform

Both `count` and `for_each` allow Terraform to create multiple instances of a resource. The key difference is **how Terraform identifies and tracks those resources in its state**.

---

# `count`

`count` creates resources using a **numeric index**.

Example:

```hcl
variable "public_subnets" {
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]
}

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  cidr_block = var.public_subnets[count.index]
}
```

Terraform creates:

```text
aws_subnet.public[0] → 10.0.1.0/24
aws_subnet.public[1] → 10.0.2.0/24
aws_subnet.public[2] → 10.0.3.0/24
```

Here, the **resource identity is its index** (`0`, `1`, `2`).

---

## Problem with `count`

Suppose you insert a new subnet in the middle:

```hcl
public_subnets = [
  "10.0.1.0/24",
  "10.0.1.128/25",
  "10.0.2.0/24",
  "10.0.3.0/24"
]
```

Terraform now sees:

```text
aws_subnet.public[0] → 10.0.1.0/24
aws_subnet.public[1] → 10.0.1.128/25
aws_subnet.public[2] → 10.0.2.0/24
aws_subnet.public[3] → 10.0.3.0/24
```

Previously:

```text
aws_subnet.public[1] → 10.0.2.0/24
aws_subnet.public[2] → 10.0.3.0/24
```

Terraform interprets this as:

- Replace `aws_subnet.public[1]`
- Replace `aws_subnet.public[2]`
- Create `aws_subnet.public[3]`

Although only one subnet was added, multiple resources may be recreated because their **indexes shifted**.

---

# `for_each`

`for_each` creates resources using a **unique key** instead of an index.

Example:

```hcl
resource "aws_subnet" "public" {
  for_each = toset(var.public_subnets)

  cidr_block = each.value
}
```

Terraform creates:

```text
aws_subnet.public["10.0.1.0/24"]
aws_subnet.public["10.0.2.0/24"]
aws_subnet.public["10.0.3.0/24"]
```

The **resource identity is now the CIDR block**, not its position in the list.

---

## Adding a new subnet

After adding:

```hcl
public_subnets = [
  "10.0.1.0/24",
  "10.0.1.128/25",
  "10.0.2.0/24",
  "10.0.3.0/24"
]
```

Terraform sees:

Existing:

```text
10.0.1.0/24 ✔
10.0.2.0/24 ✔
10.0.3.0/24 ✔
```

New:

```text
10.0.1.128/25
```

Plan:

```text
Create:
aws_subnet.public["10.0.1.128/25"]
```

The existing resources are left unchanged because their identities did not change.

---

# Stable Identity

A **stable identity** means a resource keeps the same identity even if the collection's order changes.

With `count`:

```text
Identity = Position

[0]
[1]
[2]
```

With `for_each`:

```text
Identity = Key

["public-a"]
["public-b"]
["public-c"]
```

or

```text
["10.0.1.0/24"]
["10.0.2.0/24"]
["10.0.3.0/24"]
```

Reordering items does not affect resource identities.

---

# Best Practice: Use a Map

Instead of a list:

```hcl
public_subnets = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]
```

Prefer a map:

```hcl
public_subnets = {
  public-a = "10.0.1.0/24"
  public-b = "10.0.2.0/24"
}
```

Then:

```hcl
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  cidr_block = each.value

  tags = {
    Name = each.key
  }
}
```

Terraform creates:

```text
aws_subnet.public["public-a"]
aws_subnet.public["public-b"]
```

The keys (`public-a`, `public-b`) become the permanent identities of the resources.

---

# When to Use `count`

Use `count` when:

- Creating a fixed number of identical resources.
- Resource identity is based on position.
- The list is unlikely to change over time.

Examples:

- Create exactly 3 EC2 instances.
- Create 2 NAT Gateways.
- Create 4 Availability Zone resources.

Example:

```hcl
resource "aws_instance" "web" {
  count = 3

  ami           = var.ami
  instance_type = "t3.micro"
}
```

---

# When to Use `for_each`

Use `for_each` when:

- Each resource has a natural unique identifier.
- Resources may be added or removed later.
- Order should not affect existing resources.

Examples:

- Subnets
- Security Groups
- IAM Users
- Route Tables
- S3 Buckets
- DNS Records

Example:

```hcl
resource "aws_security_group" "sg" {
  for_each = var.security_groups

  name = each.key
}
```

---

# Summary

| Feature | `count` | `for_each` |
|---------|---------|------------|
| Resource identity | Numeric index (`0`, `1`, `2`) | Unique key (`public-a`, `db`, etc.) |
| Best for | Fixed number of similar resources | Resources with unique names/IDs |
| Sensitive to ordering | Yes | No |
| Reordering causes replacement | Often | No |
| Adding/removing items | Can recreate multiple resources | Only affected resource changes |
| Preferred for production | Sometimes | Usually |

---

## Rule of Thumb

- **Use `count`** for a fixed number of nearly identical resources.
- **Use `for_each`** when resources have unique names or identifiers and may change over time.

In most production Terraform code, **`for_each` is preferred** because it gives resources **stable identities**, reducing unnecessary replacements during future infrastructure changes.

------------------------------------------------------------------------

# End-to-End Flow

``` text
terraform apply
        │
        ▼
Root Module (main.tf)
        │
        ▼
Calls Modules
        │
        ▼
Modules Create AWS Resources
        │
        ▼
Module Outputs
        │
        ▼
Root Outputs
        │
        ▼
Terraform State Updated
```

This design keeps infrastructure modular, reusable, testable, and easy
to extend as additional AWS services are introduced.
