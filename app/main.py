import os
import asyncio
import boto3
import torch
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import pipeline

# ── State ──────────────────────────────────────────────────────────────────────
state: dict = {}

@asynccontextmanager
async def lifespan(app: FastAPI):
    state["classifier"] = pipeline(
        "sentiment-analysis",
        model="distilbert-base-uncased-finetuned-sst-2-english",
        device=0 if torch.cuda.is_available() else -1,
    )
    state["gpu_available"] = torch.cuda.is_available()
    yield
    state.clear()

app = FastAPI(title="Opti-Inference", lifespan=lifespan)

SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION", "us-east-1"))

# ── Schemas ────────────────────────────────────────────────────────────────────
class PredictRequest(BaseModel):
    text: str

class PredictResponse(BaseModel):
    label: str
    score: float
    gpu_used: bool

# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    if "classifier" not in state:
        raise HTTPException(503, "Model not loaded")
    return {
        "status": "ok",
        "gpu": state["gpu_available"],
        "cuda_device": torch.cuda.get_device_name(0) if state["gpu_available"] else None,
    }

@app.post("/predict", response_model=PredictResponse)
async def predict(req: PredictRequest):
    if "classifier" not in state:
        raise HTTPException(503, "Model not loaded")
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(None, state["classifier"], req.text)
    return PredictResponse(
        label=result[0]["label"],
        score=round(result[0]["score"], 4),
        gpu_used=state["gpu_available"],
    )

@app.post("/enqueue")
async def enqueue(req: PredictRequest):
    """Push a job to SQS for async processing."""
    if not SQS_QUEUE_URL:
        raise HTTPException(500, "SQS_QUEUE_URL not configured")
    sqs.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=req.text)
    return {"queued": True}
