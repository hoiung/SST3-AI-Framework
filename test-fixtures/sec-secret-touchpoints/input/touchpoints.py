"""Synthetic env-var + credential touchpoints."""
import os
from dotenv import load_dotenv


def env_reads():
    api_key = os.environ["API_KEY"]
    db_url = os.environ.get("DATABASE_URL")
    region = os.getenv("AWS_REGION")
    # Fail-Fast violation form (2-arg getenv) — the #1470 defect class.
    cache_host = os.getenv("REDIS_HOST", "localhost")
    # Same defect class via the other idiomatic spelling. ast-grep treats
    # os.environ.get($KEY) and os.environ.get($KEY, $DEF) as disjoint, so this
    # line is invisible unless the 2-arg environ.get pattern is wired too.
    cache_port = os.environ.get("REDIS_PORT", "6379")
    return api_key, db_url, region, cache_host, cache_port


def init_dotenv():
    load_dotenv()


# Synthetic password literal (safe — fixture-only sentinel)
PASSWORD_LITERAL = 'password = "fixture-fake-not-real"'

# Synthetic AWS-key (test pattern starting with AKIA prefix per regex)
AWS_KEY_FAKE = "AKIAFIXTUREFAKEABC12"
