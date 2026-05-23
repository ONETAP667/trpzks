from fastapi import FastAPI, HTTPException, Response, Request
from pydantic import BaseModel
import psycopg2
from psycopg2.extras import RealDictCursor
import yaml
import os
import html

CONFIG_PATH = "/etc/mywebapp/config.yaml"

app = FastAPI(title="Simple Inventory")


class ItemCreate(BaseModel):
    name: str
    quantity: int


def load_config():
    if not os.path.exists(CONFIG_PATH):
        raise RuntimeError(f"Config file not found: {CONFIG_PATH}")

    with open(CONFIG_PATH, "r") as f:
        config = yaml.safe_load(f)

    if not config or "database" not in config:
        raise RuntimeError("Missing 'database' section in config")

    required = ["dbname", "user", "password", "host", "port"]
    for key in required:
        if key not in config["database"]:
            raise RuntimeError(f"Missing database config field: {key}")

    return config


def get_db_config():
    return load_config()["database"]


def get_connection():
    return psycopg2.connect(**get_db_config())


def wants_html(request: Request) -> bool:
    accept = request.headers.get("accept", "")
    return "text/html" in accept


def wants_json(request: Request) -> bool:
    accept = request.headers.get("accept", "")
    return "application/json" in accept or "*/*" in accept or accept == ""


def unsupported_accept():
    raise HTTPException(
        status_code=406,
        detail="Supported Accept headers: text/html, application/json",
    )


@app.get("/")
def root(request: Request):
    accept = request.headers.get("accept", "")

    if "text/html" not in accept and "*/*" not in accept and accept != "":
        raise HTTPException(status_code=406, detail="Root endpoint supports only text/html")

    html_content = """
    <!doctype html>
    <html>
    <head>
        <title>Simple Inventory</title>
    </head>
    <body>
        <h1>Simple Inventory</h1>
        <h2>Business endpoints</h2>
        <table border="1">
            <tr>
                <th>Method</th>
                <th>Endpoint</th>
                <th>Description</th>
            </tr>
            <tr>
                <td>GET</td>
                <td>/items</td>
                <td>List all inventory items</td>
            </tr>
            <tr>
                <td>POST</td>
                <td>/items</td>
                <td>Create new inventory item</td>
            </tr>
            <tr>
                <td>GET</td>
                <td>/items/&lt;id&gt;</td>
                <td>Show inventory item details</td>
            </tr>
        </table>
    </body>
    </html>
    """

    return Response(content=html_content, media_type="text/html")


@app.get("/health/alive")
def health_alive():
    return Response(content="OK", media_type="text/plain", status_code=200)


@app.get("/health/ready")
def health_ready():
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()
        cur.close()
        conn.close()

        return Response(content="OK", media_type="text/plain", status_code=200)

    except Exception as e:
        return Response(
            content=f"Service is not ready: {str(e)}",
            media_type="text/plain",
            status_code=500,
        )


@app.get("/items")
def get_items(request: Request):
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute("SELECT id, name FROM items ORDER BY id;")
    items = cur.fetchall()

    cur.close()
    conn.close()

    if wants_html(request):
        rows = ""

        for item in items:
            rows += f"""
            <tr>
                <td>{item["id"]}</td>
                <td>{html.escape(item["name"])}</td>
            </tr>
            """

        html_content = f"""
        <!doctype html>
        <html>
        <head>
            <title>Inventory Items</title>
        </head>
        <body>
            <h1>Inventory Items</h1>
            <table border="1">
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                </tr>
                {rows}
            </table>
        </body>
        </html>
        """

        return Response(content=html_content, media_type="text/html")

    if wants_json(request):
        return items

    unsupported_accept()


@app.post("/items", status_code=201)
def create_item(item: ItemCreate, request: Request):
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute(
        """
        INSERT INTO items (name, quantity)
        VALUES (%s, %s)
        RETURNING id, name, quantity, created_at;
        """,
        (item.name, item.quantity),
    )

    new_item = cur.fetchone()
    conn.commit()

    cur.close()
    conn.close()

    if wants_html(request):
        html_content = f"""
        <!doctype html>
        <html>
        <head>
            <title>Created Item</title>
        </head>
        <body>
            <h1>Created Item</h1>
            <table border="1">
                <tr><th>ID</th><td>{new_item["id"]}</td></tr>
                <tr><th>Name</th><td>{html.escape(new_item["name"])}</td></tr>
                <tr><th>Quantity</th><td>{new_item["quantity"]}</td></tr>
                <tr><th>Created At</th><td>{new_item["created_at"]}</td></tr>
            </table>
        </body>
        </html>
        """

        return Response(content=html_content, media_type="text/html", status_code=201)

    if wants_json(request):
        return new_item

    unsupported_accept()


@app.get("/items/{item_id}")
def get_item(item_id: int, request: Request):
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute(
        """
        SELECT id, name, quantity, created_at
        FROM items
        WHERE id = %s;
        """,
        (item_id,),
    )

    item = cur.fetchone()

    cur.close()
    conn.close()

    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")

    if wants_html(request):
        html_content = f"""
        <!doctype html>
        <html>
        <head>
            <title>Inventory Item</title>
        </head>
        <body>
            <h1>Inventory Item</h1>
            <table border="1">
                <tr><th>ID</th><td>{item["id"]}</td></tr>
                <tr><th>Name</th><td>{html.escape(item["name"])}</td></tr>
                <tr><th>Quantity</th><td>{item["quantity"]}</td></tr>
                <tr><th>Created At</th><td>{item["created_at"]}</td></tr>
            </table>
        </body>
        </html>
        """

        return Response(content=html_content, media_type="text/html")

    if wants_json(request):
        return item

    unsupported_accept()
