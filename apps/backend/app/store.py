"""Postgres access for the items table."""

import os

import psycopg

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL CHECK (char_length(name) <= 200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


def _required(name):
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"missing {name}")
    return value


class Store:
    def __init__(self, host, port, user, password, dbname):
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.dbname = dbname

    @classmethod
    def from_env(cls):
        return cls(
            host=_required("POSTGRES_HOST"),
            port=int(os.environ.get("POSTGRES_PORT", "5432")),
            user=_required("POSTGRES_USER"),
            password=_required("POSTGRES_PASSWORD"),
            dbname=_required("POSTGRES_DB"),
        )

    def connect(self):
        return psycopg.connect(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            dbname=self.dbname,
            connect_timeout=5,
        )

    def migrate(self):
        with self.connect() as conn:
            conn.execute(SCHEMA)
            conn.commit()

    def insert(self, name):
        with self.connect() as conn:
            row = conn.execute(
                "INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at",
                (name,),
            ).fetchone()
            conn.commit()
        return _row(row)

    def list(self):
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT id, name, created_at FROM items ORDER BY id"
            ).fetchall()
        return [_row(row) for row in rows]

    def ping(self):
        with self.connect() as conn:
            found = conn.execute("SELECT to_regclass('public.items')").fetchone()
        if not found or found[0] is None:
            raise RuntimeError("items table is missing")


def _row(row):
    created = row[2]
    if hasattr(created, "isoformat"):
        created = created.isoformat()
    return {"id": row[0], "name": row[1], "created_at": created}
