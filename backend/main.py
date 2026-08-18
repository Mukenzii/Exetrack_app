"""
ExeTrack Backend
Monitors @HUMOcardbot in Telegram and serves a simple HTTP API for the iOS app.

Run:
    python3 main.py
"""
import asyncio
import logging
from datetime import datetime

from aiohttp import web
from telethon import TelegramClient, events
from telethon.tl.types import User

from config import (
    TELEGRAM_API_ID, TELEGRAM_API_HASH,
    TELEGRAM_SESSION, MONITORED_BOTS,
)
from parser import parse_message, Transaction
from db import (
    init_db,
    save_pending_tx,
    save_device_token,
    save_merchant_category,
    mark_tx_categorized,
    get_pending_transactions,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("exetrack")


# ── Telegram handler ───────────────────────────────────────────────────────

async def on_message(event):
    sender: User = await event.get_sender()
    if not sender:
        return

    username = f"@{sender.username}" if sender.username else ""
    log.info(f"[ALL] from={username!r} bot={getattr(sender, 'bot', False)} text={event.message.message[:60]!r}")

    is_monitored = (
        username.lower() in [b.lower() for b in MONITORED_BOTS]
        or (sender.bot and any(b.lower() in username.lower() for b in ["humo", "uzcard"]))
    )
    if not is_monitored:
        return

    text = event.message.message
    log.info(f"📨 {username}: {text[:80]!r}")

    tx = parse_message(username, text)
    if not tx:
        log.info("  ↳ Not a transaction, skipping.")
        return

    log.info(f"  ↳ {tx.amount} {tx.currency} @ {tx.merchant}")
    tx_id = save_pending_tx(
        amount=tx.amount,
        merchant=tx.merchant,
        currency=tx.currency,
        tx_date=tx.date.isoformat(),
        card_last4=tx.card_last4 or "",
        raw_text=tx.raw_text,
    )
    log.info(f"  ↳ Saved as pending tx_id={tx_id}")


# ── HTTP API ───────────────────────────────────────────────────────────────

async def handle_register_device(request: web.Request) -> web.Response:
    body = await request.json()
    token = body.get("device_token")
    if not token:
        return web.json_response({"error": "missing device_token"}, status=400)
    save_device_token(token)
    log.info(f"[API] Device registered: ...{token[-8:]}")
    return web.json_response({"ok": True})


async def handle_categorize(request: web.Request) -> web.Response:
    body = await request.json()
    tx_id    = body.get("tx_id")
    merchant = body.get("merchant", "").upper()
    category = body.get("category", "")
    icon     = body.get("icon", "tag.fill")
    color    = body.get("color_hex", "#888888")
    if not (tx_id and merchant and category):
        return web.json_response({"error": "missing fields"}, status=400)
    save_merchant_category(merchant, category, icon, color)
    mark_tx_categorized(tx_id, category)
    log.info(f"[API] {merchant} → {category}")
    return web.json_response({"ok": True})


async def handle_pending_transactions(request: web.Request) -> web.Response:
    since = request.rel_url.query.get("since")
    txs = get_pending_transactions(since)
    return web.json_response({"transactions": txs, "count": len(txs)})


async def handle_health(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok", "time": datetime.now().isoformat()})


def make_app() -> web.Application:
    app = web.Application()
    app.router.add_post("/register-device",    handle_register_device)
    app.router.add_post("/categorize",          handle_categorize)
    app.router.add_get("/pending-transactions", handle_pending_transactions)
    app.router.add_get("/health",               handle_health)
    return app


# ── Entry point ────────────────────────────────────────────────────────────

async def main():
    init_db()
    log.info("✅ Database initialized")

    # HTTP server (same event loop, no threading)
    runner = web.AppRunner(make_app())
    await runner.setup()
    await web.TCPSite(runner, "0.0.0.0", 8000).start()
    log.info("✅ HTTP API started on :8000")

    # Telegram client — created inside async context for Python 3.10+ compat
    client = TelegramClient(TELEGRAM_SESSION, TELEGRAM_API_ID, TELEGRAM_API_HASH)
    client.add_event_handler(on_message, events.NewMessage)

    await client.start()
    me = await client.get_me()
    log.info(f"✅ Telegram: @{me.username} ({me.first_name})")
    log.info(f"👁  Monitoring: {', '.join(MONITORED_BOTS)}")
    log.info("⏳ Waiting for transactions...")

    await client.run_until_disconnected()


if __name__ == "__main__":
    asyncio.run(main())
