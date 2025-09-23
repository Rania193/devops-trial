# DevOps Trail — FastAPI on AWS ECS

## Some changes I made: 
The original skeleton expected the pipeline to manually fetch the current ECS task definition JSON, edit the container image with jq, and call aws ecs register-task-definition & aws ecs update-service.
I replaced that approach with Terraform.  Terraform will be the single source of truth for the ECS service and task definition.
This avoids configuration drift and gives plan/apply previews. On the downside, i had to upload the terraform.tfstate to the repo, which is not a best practice for sure and is a security hazard. But in production env we would have remote state stored in S3.
## Your Tasks
1. **Dockerize & Run Locally**
   - Verify you can build and run the FastAPI app locally with Docker.
   - Endpoint `/` should return JSON.
   - Endpoint `/health` should return `{ "status": "ok" }`.

2. **Terraform Infrastructure**
   - Implement Terraform in `infra/main.tf` to deploy:
     - ECR repo
     - ECS cluster (Fargate)
     - ALB + Target Group + Listener
     - Security Groups (least privilege)
     - Task Definition + Service
     - Autoscaling policy (CPU-based)
     - CloudWatch alarm (CPU > 70%)
   - Output ALB DNS name.

3. **GitHub Actions CI/CD**
   - Complete the skeleton in `.github/workflows/ci-cd.yml`.
   - Workflow should:
     - Build & push Docker image to ECR (tagged with commit SHA).
     - Run Terraform to deploy ECS service.

4. **Verification**
   - After deployment, provide:
     - ALB DNS endpoint showing app response.
     - Screenshot or logs showing autoscaling/CloudWatch alarm.

## Notes
- Use `infra/terraform.tfvars.example` as a template.
- AWS credentials must be provided as GitHub Secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_ACCOUNT_ID`



# DevOps Trial — FastAPI on AWS ECS

This repository contains a small FastAPI app and starter infrastructure code.  
Your goal is to containerize the app and deploy it to AWS ECS (Fargate) using Terraform and GitHub Actions.  

---

## 🚀 Your Tasks

### 1. Dockerize & Run Locally
- Verify you can build and run the FastAPI app locally with Docker.  
- Endpoint `/` should return JSON.  
- Endpoint `/health` should return `{ "status": "ok" }`.  
- Push the image to **Amazon ECR**.  

---

### 2. Terraform Infrastructure

Complete the **Terraform template in `/terraform`** to provision the following:  

**Core (must complete):**
- ECS Cluster (Fargate)  
- ECS Task Definition + Service  
- Application Load Balancer (ALB) + Target Group + Listener  
- Security Group (HTTP only)  
- Output the **ALB DNS name**  

**Bonus (optional):**
- ECS Auto Scaling policy (CPU-based)  
- CloudWatch logs for ECS tasks  
- CloudWatch alarm (CPU > 70%)  

---

### 3. GitHub Actions CI/CD

Complete the **pipeline stub in `.github/workflows/ci-cd.yml`**. The workflow should:  

**Core (must complete):**
- Build & push Docker image to ECR (tagged with commit SHA).  
- Run Terraform to deploy ECS service.  

**Bonus (optional):**
- Add additional checks or notifications.  

AWS credentials will be provided via GitHub Secrets:  
- `AWS_ACCESS_KEY_ID`  
- `AWS_SECRET_ACCESS_KEY`  
- `AWS_ACCOUNT_ID`  

---

### 4. Verification

After deployment, provide:  
- The **ALB DNS endpoint** showing the app response.  
- (Bonus) Screenshot or logs showing autoscaling or CloudWatch alarm.  

---

## 📝 Notes
- Use `terraform/terraform.tfvars.example` as a template for variables.  
- The FastAPI app is already functional — focus on infrastructure & automation.  
- If you get stuck, document your approach in the README.  

---

## ✅ Success Criteria
- App accessible at the ALB DNS.  
- `/health` endpoint returns `{ "status": "ok" }`.  
- Terraform is idempotent and clean.  
- CI/CD automates build & deploy.  
- Security group allows only port 80 inbound.  
- (Bonus) Monitoring & scaling work correctly.  

