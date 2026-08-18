import sqlite3
from typing import Optional
from config import DB_PATH


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_conn() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS merchant_categories (
            merchant     TEXT PRIMARY KEY,
            category     TEXT NOT NULL,
            icon         TEXT NOT NULL DEFAULT 'tag.fill',
            color_hex    TEXT NOT NULL DEFAULT '#888888',
            match_count  INTEGER DEFAULT 1,
            updated_at   TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS device_tokens (
            id           INTEGER PRIMARY KEY,
            token        TEXT UNIQUE NOT NULL,
            added_at     TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS pending_transactions (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            amount       REAL NOT NULL,
            merchant     TEXT NOT NULL,
            currency     TEXT DEFAULT 'UZS',
            tx_date      TEXT NOT NULL,
            card_last4   TEXT,
            raw_text     TEXT,
            status       TEXT DEFAULT 'pending',  -- pending / categorized / ignored
            category     TEXT,
            created_at   TEXT DEFAULT (datetime('now'))
        );
        """)


# ── merchant → category ────────────────────────────────────────────────────

def get_merchant_category(merchant: str) -> Optional[dict]:
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM merchant_categories WHERE merchant = ?",
            (merchant.upper(),)
        ).fetchone()
        return dict(row) if row else None


def save_merchant_category(merchant: str, category: str, icon: str, color_hex: str):
    with get_conn() as conn:
        conn.execute("""
        INSERT INTO merchant_categories (merchant, category, icon, color_hex, match_count)
        VALUES (?, ?, ?, ?, 1)
        ON CONFLICT(merchant) DO UPDATE SET
            category   = excluded.category,
            icon       = excluded.icon,
            color_hex  = excluded.color_hex,
            match_count = match_count + 1,
            updated_at = datetime('now')
        """, (merchant.upper(), category, icon, color_hex))


# ── device tokens ─────────────────────────────────────────────────────────

def save_device_token(token: str):
    with get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO device_tokens (token) VALUES (?)", (token,)
        )


def get_all_device_tokens() -> list[str]:
    with get_conn() as conn:
        rows = conn.execute("SELECT token FROM device_tokens").fetchall()
        return [r["token"] for r in rows]


# ── pending transactions ───────────────────────────────────────────────────

def save_pending_tx(amount: float, merchant: str, currency: str,
                    tx_date: str, card_last4: str, raw_text: str) -> int:
    with get_conn() as conn:
        cursor = conn.execute("""
        INSERT INTO pending_transactions
            (amount, merchant, currency, tx_date, card_last4, raw_text)
        VALUES (?, ?, ?, ?, ?, ?)
        """, (amount, merchant, currency, tx_date, card_last4, raw_text))
        return cursor.lastrowid


def mark_tx_categorized(tx_id: int, category: str):
    with get_conn() as conn:
        conn.execute("""
        UPDATE pending_transactions
        SET status = 'categorized', category = ?
        WHERE id = ?
        """, (category, tx_id))


def get_pending_transactions(since: str = None) -> list[dict]:
    """Return uncategorized transactions. If since is given, only newer ones."""
    with get_conn() as conn:
        if since:
            # Normalize ISO8601 (2026-07-06T09:25:10Z) → SQLite format (2026-07-06 09:25:10)
            since_normalized = since.replace("T", " ").replace("Z", "").split("+")[0]
            rows = conn.execute("""
            SELECT pt.*, mc.category as auto_category
            FROM pending_transactions pt
            LEFT JOIN merchant_categories mc ON mc.merchant = pt.merchant
            WHERE pt.status = 'pending' AND pt.created_at > ?
            ORDER BY pt.created_at ASC
            """, (since_normalized,)).fetchall()
        else:
            rows = conn.execute("""
            SELECT pt.*, mc.category as auto_category
            FROM pending_transactions pt
            LEFT JOIN merchant_categories mc ON mc.merchant = pt.merchant
            WHERE pt.status = 'pending'
            ORDER BY pt.created_at ASC
            """).fetchall()
        return [dict(r) for r in rows]
