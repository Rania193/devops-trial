# Candidate Instructions — DevOps Trial 

⏱ **Time Limit**  
You have 2 hours to complete this trial.  
Focus on delivering working infrastructure rather than perfect code.

🎯 **Objective**  
Deploy a provided FastAPI application to AWS ECS (Fargate) using:
- Docker
- Terraform (Infrastructure as Code)
- GitHub Actions (CI/CD)
- AWS Services (ECR, ECS, ALB, Auto Scaling, CloudWatch)
- Security best practices

🛠 **What You're Given**  
A GitHub repository (or compressed file) with:
- FastAPI app (`/app`)
- Dockerfile
- Terraform template (`/infra`) — you must complete missing resources (ECS Task Definition, Service, ALB, Auto Scaling, etc.)
- GitHub Actions pipeline template (`.github/workflows/ci-cd.yml`) — you must complete missing steps
- IAM policy (shows the AWS permissions available to you) (`policies/devops-trial-iam.json`)
- Temporary AWS credentials with limited permissions (will be provided at the time of the trial)

⚠️ **Important — Resource Naming Convention**  
Your IAM permissions are restricted to project resources.  
All AWS resources **MUST** start with prefix: `devops-trial-`

Examples:
- ECR repo → `devops-trial-fastapi-app`
- ECS cluster → `devops-trial-cluster`
- Task definition family → `devops-trial-task`
- CloudWatch logs → `/ecs/devops-trial-app`

**If you do not follow this naming convention, Terraform will fail with AccessDenied errors.**

📌 **Your Tasks**

### **Core (must complete)**

#### **1. Dockerization**
- Build the FastAPI app into a Docker image.
- Push the image to Amazon ECR (`devops-trial-*`).

#### **2. Infrastructure (Terraform)**
Complete the Terraform template in `/infra` to provision:
- ECS cluster & service (Fargate)
- ECS Task Definition
- Security Group (HTTP only)
- Application Load Balancer (ALB)
- Outputs should include the ALB DNS name.

#### **3. CI/CD (GitHub Actions)**
Update the pipeline in `.github/workflows/ci-cd.yml` so that:
- On push to main, it builds & pushes the Docker image.
- Terraform runs and deploys the app.

### **Bonus (if time permits)**

#### **Monitoring & Scaling**
- Add ECS Auto Scaling policy (scale on CPU > 70%).
- Enable CloudWatch logs for ECS tasks.
- Create a CloudWatch alarm for high CPU usage.

✅ **Success Criteria**
- The app is accessible at the ALB DNS name.
- The `/health` endpoint returns `{ "status": "ok" }`.
- Terraform code is clean and idempotent.
- CI/CD pipeline automates build & deploy.
- Security group allows only HTTP (port 80) inbound.
- Logs appear in CloudWatch (bonus).

🔒 **Rules**
- Only resources prefixed with `devops-trial-` are allowed.
- Do not exceed your AWS permissions (they are intentionally scoped).
- Submit by:
  - Pushing to the provided GitHub repo, or
  - Sending back a ZIP of your solution.

💡 **Tips**
- Start with Docker + ECR, then move to ECS.
- Test incrementally (don't wait until the end to deploy).
- If you get stuck, document your approach in the README.
- Use `infra/terraform.tfvars.example` as a template for your variables.


```
