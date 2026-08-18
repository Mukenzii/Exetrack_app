"""
Send push notifications to iOS via APNs HTTP/2 API with JWT auth.
"""
import time
import json
from typing import Optional
import httpx
import jwt as pyjwt
from config import (
    APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID,
    APNS_BUNDLE_ID, APNS_USE_SANDBOX
)

APNS_HOST = (
    "https://api.sandbox.push.apple.com"
    if APNS_USE_SANDBOX
    else "https://api.push.apple.com"
)


def _make_jwt() -> str:
    with open(APNS_KEY_PATH, "r") as f:
        private_key = f.read()
    token = pyjwt.encode(
        {"iss": APNS_TEAM_ID, "iat": int(time.time())},
        private_key,
        algorithm="ES256",
        headers={"kid": APNS_KEY_ID},
    )
    return token


def send_transaction_push(
    device_token: str,
    amount: float,
    merchant: str,
    currency: str,
    tx_id: int,
    auto_category: Optional[str] = None,
) -> bool:
    """
    Send a push notification for a new bank transaction.
    If auto_category is set → silent categorization push.
    If not → interactive push asking user to pick a category.
    """
    jwt_token = _make_jwt()
    url = f"{APNS_HOST}/3/device/{device_token}"

    if auto_category:
        # Silent background push — app auto-records the transaction
        payload = {
            "aps": {
                "content-available": 1,
            },
            "type": "auto_transaction",
            "tx_id": tx_id,
            "amount": amount,
            "merchant": merchant,
            "currency": currency,
            "category": auto_category,
        }
        apns_push_type = "background"
        apns_priority = "5"
    else:
        # Interactive push — user picks category
        amount_fmt = f"{amount:,.0f}".replace(",", " ")
        payload = {
            "aps": {
                "alert": {
                    "title": f"{amount_fmt} {currency}",
                    "body": f"{merchant} — выбери категорию",
                },
                "sound": "default",
                "badge": 1,
                "category": "TRANSACTION_CATEGORY",  # UNNotificationCategory
            },
            "type": "new_transaction",
            "tx_id": tx_id,
            "amount": amount,
            "merchant": merchant,
            "currency": currency,
        }
        apns_push_type = "alert"
        apns_priority = "10"

    headers = {
        "authorization": f"bearer {jwt_token}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": apns_push_type,
        "apns-priority": apns_priority,
    }

    try:
        with httpx.Client(http2=True) as client:
            resp = client.post(url, json=payload, headers=headers, timeout=10)
            if resp.status_code == 200:
                print(f"[APNs] ✅ Push sent to ...{device_token[-8:]}")
                return True
            else:
                print(f"[APNs] ❌ {resp.status_code}: {resp.text}")
                return False
    except Exception as e:
        print(f"[APNs] ❌ Exception: {e}")
        return False
