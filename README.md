# Opti-Inference Pipeline

Production-grade GPU AI inference on AWS EKS using Spot Instances, KEDA, FastAPI, Terraform, and GitHub Actions.

---

## Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │                  AWS Cloud                   │
                        │                                              │
  Client ──HTTPS──▶  ALB  ──▶  EKS Cluster (inference namespace)      │
                        │         │                                    │
                        │    ┌────▼──────────────────────┐            │
                        │    │  FastAPI Pod (GPU Node)    │            │
                        │    │  distilbert sentiment      │            │
                        │    │  CUDA 12.1 / g4dn.xlarge  │            │
                        │    └────────────────────────────┘            │
                        │              ▲  scale                        │
                        │    ┌─────────┴──────────┐                   │
                        │    │   KEDA ScaledObject │                   │
                        │    │   SQS Trigger       │                   │
                        │    └─────────┬──────────┘                   │
                        │              │ watches                       │
                        │    ┌─────────▼──────────┐                   │
  Client ──/enqueue──▶  │    │   SQS Queue         │                   │
                        │    └────────────────────┘                   │
                        │                                              │
                        │  ECR ◀── GitHub Actions CI/CD               │
                        │  CloudWatch Container Insights               │
                        └─────────────────────────────────────────────┘
```

---

## Why Spot GPUs Save Money

`g4dn.xlarge` On-Demand costs ~$0.526/hr. The same instance as a Spot costs ~$0.16/hr — a **70% reduction**.
Combined with KEDA's scale-to-zero, you pay nothing when the queue is empty. For bursty AI workloads this can
reduce GPU compute costs by **80–90%** compared to always-on On-Demand nodes.

---

## Why KEDA Beats CPU Autoscaling for AI

| | HPA (CPU) | KEDA (SQS) |
|---|---|---|
| Trigger | CPU % | Queue depth |
| Scale-to-zero | ❌ | ✅ |
| Reacts to backlog | ❌ | ✅ |
| GPU inference fit | Poor | Excellent |
| Cold-start aware | ❌ | ✅ (cooldown) |

GPU inference is I/O and memory bound, not CPU bound. A pod can be at 5% CPU while processing 100% of its
GPU capacity. KEDA scales on what actually matters: how many jobs are waiting.

---

## Repository Structure

```
opti-inference-pipeline/
├── terraform/
│   ├── main.tf               # Root module — providers, Helm releases
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/              # VPC, subnets, IGW, NAT
│       ├── eks/              # EKS cluster + GPU Spot node group + OIDC
│       ├── iam/              # Node role, KEDA role, LBC role, SQS queue
│       └── ecr/              # ECR repository + lifecycle policy
├── app/
│   ├── main.py               # FastAPI app — /health, /predict, /enqueue
│   └── requirements.txt
├── docker/
│   └── Dockerfile            # CUDA 12.1 base, model pre-baked at build time
├── k8s/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml   # IRSA annotations for KEDA + inference pods
│   ├── deployment.yaml       # GPU limits, nodeSelector, tolerations
│   ├── service.yaml
│   ├── ingress.yaml          # AWS ALB
│   ├── scaledobject.yaml     # KEDA SQS trigger, minReplicas=0
│   └── cloudwatch.yaml       # Container Insights DaemonSet
├── helm/
│   └── opti-inference/       # Helm chart wrapping all k8s manifests
├── .github/workflows/
│   └── deploy.yml            # Build → Push ECR → Helm upgrade → Smoke test
└── README.md
```

---

## Prerequisites

- AWS CLI v2, configured with admin credentials
- Terraform >= 1.5
- kubectl, helm v3
- Docker (with BuildKit)
- An S3 bucket for Terraform state: `opti-inference-tfstate`

---

## Deploy Step-by-Step

### 1. Provision Infrastructure

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Note the outputs:
```bash
terraform output cluster_name     # opti-inference
terraform output ecr_url          # <account>.dkr.ecr.us-east-1.amazonaws.com/opti-inference
terraform output sqs_queue_url    # https://sqs.us-east-1.amazonaws.com/<account>/opti-inference-inference-queue
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --name opti-inference --region us-east-1
```

### 3. Apply Base Manifests

```bash
kubectl apply -f k8s/namespace.yaml

export KEDA_ROLE_ARN=$(terraform -chdir=terraform output -raw keda_role_arn)
envsubst < k8s/serviceaccount.yaml | kubectl apply -f -

kubectl apply -f k8s/cloudwatch.yaml
```

### 4. Build & Push Docker Image (manual first run)

```bash
ECR_URL=$(terraform -chdir=terraform output -raw ecr_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

docker build -f docker/Dockerfile -t $ECR_URL:latest .
docker push $ECR_URL:latest
```

### 5. Deploy via Helm

```bash
SQS_URL=$(terraform -chdir=terraform output -raw sqs_queue_url)

helm upgrade --install opti-inference ./helm/opti-inference \
  --namespace inference \
  --create-namespace \
  --set image.repository=$ECR_URL \
  --set image.tag=latest \
  --set keda.sqsQueueUrl=$SQS_URL \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$KEDA_ROLE_ARN"
```

### 6. Set GitHub Secrets

In your repo → Settings → Secrets, add:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | CI IAM user key |
| `AWS_SECRET_ACCESS_KEY` | CI IAM user secret |
| `KEDA_ROLE_ARN` | From `terraform output keda_role_arn` |
| `SQS_QUEUE_URL` | From `terraform output sqs_queue_url` |

Push to `main` — CI/CD takes over from here.

---

## Test Locally (CPU mode)

```bash
cd app
pip install -r requirements.txt
uvicorn main:app --reload
```

```bash
# Health check
curl http://localhost:8000/health

# Inference
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "This product is absolutely fantastic!"}'
```

Expected response:
```json
{"label": "POSITIVE", "score": 0.9998, "gpu_used": false}
```

---

## Trigger Autoscaling

```bash
SQS_URL=$(terraform -chdir=terraform output -raw sqs_queue_url)

# Send 20 messages to trigger scale-up (threshold: 5 msgs/pod → 4 pods)
for i in $(seq 1 20); do
  aws sqs send-message --queue-url $SQS_URL --message-body "Review $i: Great product!"
done

# Watch KEDA scale pods
kubectl get pods -n inference -w
```

---

## Observability

- **CloudWatch Container Insights**: navigate to CloudWatch → Container Insights → EKS cluster
- **Inference latency**: logged per request; ship to CloudWatch Logs via Fluent Bit
- **KEDA metrics**: `kubectl get scaledobject -n inference`
- **GPU utilization**: `kubectl exec -it <pod> -n inference -- nvidia-smi`

---

## Business Value

| Metric | Traditional | Opti-Inference |
|---|---|---|
| GPU cost (idle) | Full On-Demand | $0 (scale-to-zero) |
| GPU cost (active) | ~$0.53/hr/node | ~$0.16/hr/node (Spot) |
| Scaling trigger | CPU (wrong metric) | Queue depth (right metric) |
| Deployment | Manual | Fully automated CI/CD |
| Infra provisioning | Manual | Terraform IaC |

For a platform running 8 hours/day of bursty inference, this architecture typically delivers **75–85% cost
reduction** versus always-on On-Demand GPU nodes, while maintaining production reliability through Spot
interruption handling and KEDA's intelligent scaling.
