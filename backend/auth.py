"""
One-time Telegram authentication.
Run this ONCE in a terminal to create the session file.
After that, main.py will start without asking for credentials.

Usage:
    cd ~/Desktop/exetrack/backend
    .venv/bin/python3 auth.py
"""
import asyncio
from telethon import TelegramClient
from config import TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_SESSION


async def main():
    client = TelegramClient(TELEGRAM_SESSION, TELEGRAM_API_ID, TELEGRAM_API_HASH)
    await client.start()
    me = await client.get_me()
    print(f"\n✅ Authenticated as: {me.first_name} @{me.username}")
    print("Session saved. You can now run main.py headlessly.\n")
    await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
