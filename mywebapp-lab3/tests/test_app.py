from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app import main


class FakeCursor:
    def __init__(self):
        self.last_query = ""

    def execute(self, query, params=None):
        self.last_query = query

    def fetchone(self):
        if "SELECT 1" in self.last_query:
            return (1,)

        if "WHERE id" in self.last_query:
            return {
                "id": 1,
                "name": "Keyboard",
                "quantity": 3,
                "created_at": datetime(2024, 1, 1, tzinfo=timezone.utc),
            }

        if "RETURNING id" in self.last_query:
            return {
                "id": 2,
                "name": "Mouse",
                "quantity": 5,
                "created_at": datetime(2024, 1, 2, tzinfo=timezone.utc),
            }

        return None

    def fetchall(self):
        return [
            {"id": 1, "name": "Keyboard"},
            {"id": 2, "name": "Mouse"},
        ]

    def close(self):
        pass


class FakeConnection:
    def cursor(self, cursor_factory=None):
        return FakeCursor()

    def commit(self):
        pass

    def close(self):
        pass


@pytest.fixture(autouse=True)
def fake_database(monkeypatch):
    monkeypatch.setattr(main, "get_connection", lambda: FakeConnection())


@pytest.fixture
def client():
    return TestClient(main.app)


def test_root_returns_html(client):
    response = client.get("/", headers={"accept": "text/html"})

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Simple Inventory" in response.text


def test_root_rejects_unsupported_accept_header(client):
    response = client.get("/", headers={"accept": "application/xml"})

    assert response.status_code == 406


def test_health_alive(client):
    response = client.get("/health/alive")

    assert response.status_code == 200
    assert response.text == "OK"


def test_health_ready(client):
    response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.text == "OK"


def test_get_items_json(client):
    response = client.get("/items", headers={"accept": "application/json"})

    assert response.status_code == 200
    assert response.json() == [
        {"id": 1, "name": "Keyboard"},
        {"id": 2, "name": "Mouse"},
    ]


def test_get_items_html_escapes_item_names(client):
    response = client.get("/items", headers={"accept": "text/html"})

    assert response.status_code == 200
    assert "Inventory Items" in response.text
    assert "Keyboard" in response.text


def test_create_item_json(client):
    response = client.post(
        "/items",
        headers={"accept": "application/json"},
        json={"name": "Mouse", "quantity": 5},
    )

    assert response.status_code == 201
    assert response.json()["id"] == 2
    assert response.json()["name"] == "Mouse"
    assert response.json()["quantity"] == 5


def test_get_item_json(client):
    response = client.get("/items/1", headers={"accept": "application/json"})

    assert response.status_code == 200
    assert response.json()["id"] == 1
    assert response.json()["name"] == "Keyboard"
    assert response.json()["quantity"] == 3


def test_unsupported_accept_for_items(client):
    response = client.get("/items", headers={"accept": "application/xml"})

    assert response.status_code == 406