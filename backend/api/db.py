import os
import urllib.parse
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# Load .env (only applies locally — Render injects env vars directly)
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

# Strip null characters and whitespace defensively
def _clean(value, default=""):
    if value is None:
        return default
    return value.strip().replace('\x00', '').replace('\r', '')

DB_HOST = _clean(os.getenv("DB_HOST"))
DB_PORT = _clean(os.getenv("DB_PORT"), "6543")
DB_NAME = _clean(os.getenv("DB_NAME"), "postgres")
DB_USER = _clean(os.getenv("DB_USER"))
DB_PASS = _clean(os.getenv("DB_PASS"))

# Debug — shows in Render deploy logs so you can confirm values
print(f"[DB] HOST={repr(DB_HOST)} PORT={repr(DB_PORT)} NAME={repr(DB_NAME)} USER={repr(DB_USER)}")

if not DB_HOST or not DB_USER:
    raise RuntimeError(
        f"Missing required DB env vars. HOST={repr(DB_HOST)} USER={repr(DB_USER)}"
    )

# URL-encode the password so special characters like '@' don't break the URL
safe_password = urllib.parse.quote_plus(DB_PASS) if DB_PASS else ""

# Build connection string
DATABASE_URL = f"postgresql://{DB_USER}:{safe_password}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

print(f"[DB] Connecting to {DB_HOST}:{DB_PORT}/{DB_NAME}")

# Create engine
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    connect_args={"connect_timeout": 10},
)

# Session factory
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

# Base class for models
Base = declarative_base()

# Dependency for FastAPI routes
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()