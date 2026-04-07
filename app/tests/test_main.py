import pytest
import os
import sys
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch

# Set env before importing app
os.environ["SKIP_MODEL_LOAD"] = "true"
os.environ["SQS_QUEUE_URL"] = "http://mock-sqs"
os.environ["AWS_ACCESS_KEY_ID"] = "test"
os.environ["AWS_SECRET_ACCESS_KEY"] = "test"
os.environ["AWS_REGION"] = "us-east-1"

# Mock boto3 before it's used in main
mock_boto3 = MagicMock()
sys.modules["boto3"] = mock_boto3

from main import app

client = TestClient(app)

def test_health():
    with client:
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "gpu" in data

def test_predict_sentiment():
    with client:
        payload = {
            "text": "I love this product!",
            "client_id": "test-client",
            "workflow": "sentiment"
        }
        response = client.post("/predict", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["client_id"] == "test-client"
        assert "result" in data
        assert "request_id" in data

def test_pii_scrubbing():
    with client:
        payload = {
            "text": "My email is test@example.com and phone is 555-123-4567",
            "client_id": "test-client",
            "workflow": "sentiment"
        }
        from main import ComplianceManager
        scrubbed = ComplianceManager.scrub(payload["text"])
        assert "[EMAIL_MASKED]" in scrubbed
        assert "[PHONE_MASKED]" in scrubbed

def test_metrics_endpoint():
    with client:
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "http_requests_total" in response.text

def test_enqueue():
    # Since we mocked boto3 at the module level, we need to access the mock through main
    import main
    with client:
        payload = {
            "text": "Queue this message",
            "client_id": "test-client",
            "workflow": "sentiment"
        }
        response = client.post("/enqueue", json=payload)
        assert response.status_code == 200
        assert response.json()["queued"] is True
        main.sqs.send_message.assert_called()
