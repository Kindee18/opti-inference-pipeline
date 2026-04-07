# Opti-Inference: Enterprise AI Automation Framework
### *Strategic Architectural Showcase for Lustrew Dynamics LLC*

---

## 🏛️ Executive Summary

This repository demonstrates a **production-grade, compliance-first AI inference pipeline** specifically architected for Lustrew Dynamics' high-stakes clients. This framework serves as a foundational infrastructure for **AEGIS ADA** (Workflow Automation) and **OptimumAI** (Advertising Intelligence), solving the "Triple Constraint" of AI: **Security**, **Scalability**, and **Infrastructure Cost**.

---

## 📐 Pipeline Architecture

```mermaid
graph TD
    User([User/Client]) -->|REST API| Gateway[FastAPI AI Gateway]
    
    subgraph "Compliance & Intelligence"
        Gateway --> PII[PII Compliance Layer]
        PII --> NLP[NLP Engines: Sentiment/Summ]
        Gateway --> Vision[Vision Engine: TensorRT Sim]
        NLP --> Metrics[Prometheus Metrics]
        Vision --> Metrics
    end
    
    subgraph "Event-Driven Scaling"
        Gateway --> SQS[AWS SQS: Metadata Pointers]
        SQS --> KEDA[KEDA Scaler]
        KEDA -->|Auto-Scale| Pods[GPU Inference Pods]
    end
    
    subgraph "Observability Layer"
        Metrics --> Dash[Prometheus/Grafana]
        Gateway --> Logs[JSON Audit Logs]
    end
```

---

## 🚀 Strategic Industry Solutions

### 1. OptimumAI: Computer Vision & Edge Intelligence
*   **Feature:** Asynchronous processing of image/video streams using **TensorRT**-optimized detection.
*   **Presigned URL Architecture:** Uses **S3 Presigned URLs** as pointers to heavy binary data, bypassing SQS payload limits.

### 2. Data Sovereignty & PII Masking (Compliance-First)
*   **Feature:** Automatic masking of Emails, Phones, SSNs, and Credit Cards *before* processing.
*   **Benefit:** Audit-ready for GDPR/HIPAA regulated sectors.

### 3. Multi-Model Orchestration & Scaling
*   **Feature:** A unified gateway serving Sentiment, Summarization, and Computer Vision.
*   **Benefit:** **KEDA** scale-to-zero logic reduces idle GPU costs by up to **90%**.

---

## 🛠️ How to Use This Project

### 1. Prerequisites
- **Python 3.10+**
- **Docker & Docker Compose**
- **AWS CLI** (or LocalStack for zero-cost testing)
- **Terraform** (for infrastructure provisioning)

### 2. Local Development & Testing
To run the project locally without incurring any AWS costs:

```bash
# Clone the repository
git clone https://github.com/Kindee18/opti-inference-pipeline.git
cd opti-inference-pipeline/app

# Install dependencies (Lightweight mode)
pip install -r requirements.txt

# Run the API locally (Mocks enabled)
export SKIP_MODEL_LOAD=true
export SQS_QUEUE_URL=http://localhost:4566
uvicorn main:app --reload
```

### 3. Running the Zero-Cost Validation Suite
The project includes a full E2E simulation using **LocalStack** and **KinD**:

```bash
# Execute the full local E2E test
chmod +x ../scripts/test_local_e2e.sh
../scripts/test_local_e2e.sh
```

### 4. Interacting with the API

**Real-time Inference (with PII Masking):**
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Contact me at test@example.com or call 555-123-4567",
    "client_id": "lustrew-saas-01",
    "workflow": "sentiment"
  }'
```

**Check Observability Metrics:**
```bash
curl http://localhost:8000/metrics
```

---

## 🏗️ Infrastructure & Deployment

### 1. Manual Infrastructure Setup
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2. CI/CD Pipeline (GitHub Actions)
The project is equipped with a **Zero-Cost CI Pipeline** that validates:
- **Python Logic:** PII scrubbing and metrics verification.
- **Infrastructure:** `terraform validate` and `helm lint`.
- **Build Integrity:** Multi-stage Docker build validation.

The pipeline automatically skips the `terraform apply` step unless `AWS_ACCESS_KEY_ID` is configured in GitHub Secrets, making it safe for open-source exploration.

---

## 🔌 API Reference & Configuration

| Variable | Description | Default |
|---|---|---|
| `PII_MASKING_ENABLED` | Toggles the data scrubbing layer | `true` |
| `SKIP_MODEL_LOAD` | Bypasses ML downloads for rapid dev | `false` |
| `MODEL_SOURCE_S3` | Pulls models from registry instead of local | `local` |

---

## 📊 Business Impact Metrics

| Feature | Impact on Lustrew Dynamics | Business Outcome |
|---|---|---|
| **Presigned S3 URLs** | Heavy Payload Handling | **High Scalability** |
| **PII Scrubbing** | PHI/PII Protection | **Compliance-Ready** |
| **Multi-Model Pool** | Shared GPU Resources | **50% Lower Overhead** |
| **KEDA Scaling** | Scale-to-Zero | **90% Cost Savings** |
