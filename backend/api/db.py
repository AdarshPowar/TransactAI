import os
import urllib.parse
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

print("=== STARTING X-RAY DEBUG ===", flush=True)

raw_user = os.getenv("DB_USER")
raw_pass = os.getenv("DB_PASS")
raw_host = os.getenv("DB_HOST")
raw_port = os.getenv("DB_PORT")
raw_name = os.getenv("DB_NAME")

print(f"DB_USER: {repr(raw_user)}", flush=True)
print(f"DB_PASS: {repr(raw_pass)}", flush=True)
print(f"DB_HOST: {repr(raw_host)}", flush=True)
print(f"DB_PORT: {repr(raw_port)}", flush=True)
print(f"DB_NAME: {repr(raw_name)}", flush=True)

print("=== END X-RAY DEBUG ===", flush=True)
sys.stdout.flush()
# --- END OF DEBUG CODE ---

# Load .env
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "6543")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")

# URL-encode the password so special characters like '@' don't break the URL
safe_password = urllib.parse.quote_plus(DB_PASS) if DB_PASS else ""

# Build connection string
DATABASE_URL = f"postgresql://{DB_USER}:{safe_password}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Create engine
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True
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