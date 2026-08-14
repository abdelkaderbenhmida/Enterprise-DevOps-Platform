import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Must be set before importing main: it now fails fast when secrets are unset.
os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_PASSWORD", "test-db-password")
os.environ.setdefault("DATABASE_HOST", "localhost")

import main


def test_app_metadata():
    assert main.app.title == "Task Manager API"
    assert main.app.version == "1.0.0"


def test_task_model_has_owner():
    columns = main.Task.__table__.columns
    assert "user_id" in columns
    assert columns["user_id"].nullable is False


def test_fail_fast_when_secrets_missing():
    import subprocess
    import sys

    env = os.environ.copy()
    env.pop("SECRET_KEY", None)
    env.pop("DATABASE_PASSWORD", None)
    backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    result = subprocess.run(
        [sys.executable, "-c", "import main"],
        cwd=backend_dir,
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "SECRET_KEY" in result.stderr or "DATABASE_PASSWORD" in result.stderr


def test_cors_no_wildcard_with_credentials():
    cors = [m for m in main.app.user_middleware if m.cls.__name__ == "CORSMiddleware"]
    assert cors, "CORSMiddleware not registered"
    kwargs = cors[0].kwargs
    assert kwargs.get("allow_credentials") is False
