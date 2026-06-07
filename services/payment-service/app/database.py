import sqlite3
import os

DB_PATH = os.getenv("DB_PATH", "/data/payments.db")


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_connection()
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS payments (
                id          TEXT PRIMARY KEY,
                order_ref   TEXT,
                amount      REAL NOT NULL,
                status      TEXT NOT NULL DEFAULT 'pending',
                card_last4  TEXT,
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            )
        """)
        conn.commit()
    finally:
        conn.close()
