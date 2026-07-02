import os
# <<<<<<< feature/frontend-fix
import urllib.parse  # 1. Add this import
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# Load .env
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")

# 2. Encode the password so special characters like '@' don't break the URL
safe_password = urllib.parse.quote_plus(DB_PASS) if DB_PASS else ""

# 3. Use the safe_password in the URL
DATABASE_URL = f"postgresql://{DB_USER}:{safe_password}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

=======
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# Get database settings from docker-compose environment variables
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "transactai")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")

# Build the connection string
DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Create engine
# >>>>>>> main
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True
)

# <<<<<<< feature/frontend-fix
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()

=======
# Session factory
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

# Base class for models
Base = declarative_base()

# Dependency for FastAPI routes
# >>>>>>> main
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
# <<<<<<< feature/frontend-fix
        db.close()
=======
        db.close()
# >>>>>>> main
