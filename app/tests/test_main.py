import pytest
import os
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch

# Set env before importing app
os.environ["SKIP_MODEL_LOAD"] = "true"
os.environ["SQS_QUEUE_URL"] = "http://mock-sqs"

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
        # We can't easily check the internal state of the model call here without more mocks,
        # but we can test the ComplianceManager directly or mock the model.
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
    with patch("main.sqs.send_message") as mock_send:
        with client:
            payload = {
                "text": "Queue this message",
                "client_id": "test-client",
                "workflow": "sentiment"
            }
            response = client.post("/enqueue", json=payload)
            assert response.status_code == 200
            assert response.json()["queued"] is True
            mock_send.assert_called_once()
