import re
from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass
class Transaction:
    amount: float
    merchant: str
    currency: str
    date: datetime
    card_last4: Optional[str]
    raw_text: str


def parse_humo(text: str) -> Optional[Transaction]:
    """
    Parse @HUMOcardbot message. Real format:
        💸 Оплата
        ➖ 1.011,00 UZS
        📍 PAYME P2P H2U>TASHKE
        💳 HUMOCARD *0716
        🕓 03:04 06.07.2026
        💰 131.514,31 UZS

    Amount uses European notation: 1.011,00 → 1011.00
    ➖ = debit (expense), ➕ = credit (income, skip)
    """
    text = text.strip()

    # Only process debit transactions
    if "➖" not in text:
        return None

    # Amount: line starting with ➖
    amount_m = re.search(r"➖\s*([\d.,]+)\s*(UZS|сўм|сум|sum)", text, re.IGNORECASE)
    if not amount_m:
        return None

    amount = _parse_amount(amount_m.group(1))
    currency = "UZS"

    # Merchant: line after 📍
    merchant_m = re.search(r"📍\s*(.+)", text)
    merchant = merchant_m.group(1).strip().upper() if merchant_m else "UNKNOWN"

    # Card last4: *XXXX after HUMOCARD
    card_m = re.search(r"\*(\d{4})", text)
    card_last4 = card_m.group(1) if card_m else None

    # Date: 🕓 HH:MM DD.MM.YYYY
    date = _extract_humo_date(text)

    return Transaction(
        amount=amount,
        merchant=merchant,
        currency=currency,
        date=date,
        card_last4=card_last4,
        raw_text=text,
    )


def parse_uzcard(text: str) -> Optional[Transaction]:
    """Parse Uzcard bot — update patterns once real messages are seen."""
    text = text.strip()

    m = re.search(
        r"[Сс]умма[:\s]+([\d.,\s]+)\s*(сўм|UZS|sum|сум)",
        text, re.IGNORECASE
    )
    if not m:
        return None

    amount = _parse_amount(m.group(1))
    merchant = _extract_merchant_generic(text)
    date = _extract_date_generic(text)
    card_m = re.search(r"\*(\d{4})", text)
    card_last4 = card_m.group(1) if card_m else None

    return Transaction(
        amount=amount,
        merchant=merchant,
        currency="UZS",
        date=date,
        card_last4=card_last4,
        raw_text=text,
    )


def parse_message(sender_username: str, text: str) -> Optional[Transaction]:
    uname = sender_username.lower()
    if "humo" in uname:
        return parse_humo(text)
    if "uzcard" in uname:
        return parse_uzcard(text)
    return parse_humo(text) or parse_uzcard(text)


# ── helpers ────────────────────────────────────────────────────────────────

def _parse_amount(raw: str) -> float:
    """
    Handle European notation (1.011,00 → 1011.00)
    and plain notation (50000 or 50000.00).
    """
    raw = raw.strip()
    if "," in raw:
        # European: dot=thousands, comma=decimal
        raw = raw.replace(".", "").replace(",", ".")
    else:
        # Plain or US: remove any spaces/dots used as thousands
        raw = raw.replace(" ", "").replace(" ", "")
    return float(raw)


def _extract_humo_date(text: str) -> datetime:
    # 🕓 HH:MM DD.MM.YYYY
    m = re.search(r"🕓\s*(\d{2}):(\d{2})\s+(\d{2})\.(\d{2})\.(\d{4})", text)
    if m:
        hh, mm, dd, mo, yy = (int(x) for x in m.groups())
        try:
            return datetime(yy, mo, dd, hh, mm)
        except ValueError:
            pass
    return datetime.now()


def _extract_merchant_generic(text: str) -> str:
    patterns = [
        r"[Мм]ерчант[:\s]+([A-ZА-ЯЁa-zа-яё0-9 &'>-]+?)(?:\n|$|\.)",
        r"[Мм]агазин[:\s]+([A-ZА-ЯЁa-zа-яё0-9 &'>-]+?)(?:\n|$|\.)",
        r"[Тт]орговая точка[:\s]+([A-ZА-ЯЁa-zа-яё0-9 &'>-]+?)(?:\n|$|\.)",
    ]
    for p in patterns:
        m = re.search(p, text, re.IGNORECASE)
        if m:
            return m.group(1).strip().upper()
    return "UNKNOWN"


def _extract_date_generic(text: str) -> datetime:
    patterns = [
        (r"(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2})", "dmy_hm"),
        (r"(\d{2}):(\d{2})\s+(\d{2})\.(\d{2})\.(\d{4})",  "hm_dmy"),
    ]
    for pattern, fmt in patterns:
        m = re.search(pattern, text)
        if m:
            g = [int(x) for x in m.groups()]
            try:
                if fmt == "dmy_hm":
                    return datetime(g[2], g[1], g[0], g[3], g[4])
                else:
                    return datetime(g[4], g[3], g[2], g[0], g[1])
            except ValueError:
                pass
    return datetime.now()
