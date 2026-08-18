import os
from dotenv import load_dotenv

load_dotenv()

# Telegram API credentials
# Get from https://my.telegram.org/apps
TELEGRAM_API_ID = int(os.getenv("TELEGRAM_API_ID", "0"))
TELEGRAM_API_HASH = os.getenv("TELEGRAM_API_HASH", "")
TELEGRAM_SESSION = os.getenv("TELEGRAM_SESSION", "exetrack_session")

# Telegram bot usernames to monitor
# Add bot usernames once you know them after subscribing
MONITORED_BOTS = [
    "@HUMOcardbot",
]

# Apple Push Notifications (APNs)
# Generate .p8 key from Apple Developer portal:
# Certificates, Identifiers & Profiles → Keys → + (AuthKey)
APNS_KEY_PATH = os.getenv("APNS_KEY_PATH", "certs/AuthKey.p8")
APNS_KEY_ID = os.getenv("APNS_KEY_ID", "")        # 10-char key ID
APNS_TEAM_ID = os.getenv("APNS_TEAM_ID", "")      # 10-char team ID
APNS_BUNDLE_ID = os.getenv("APNS_BUNDLE_ID", "com.exetrack.app")
APNS_USE_SANDBOX = os.getenv("APNS_USE_SANDBOX", "true").lower() == "true"

# SQLite DB path
DB_PATH = os.getenv("DB_PATH", "exetrack.db")
