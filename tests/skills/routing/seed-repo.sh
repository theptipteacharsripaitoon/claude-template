#!/usr/bin/env bash
# Seeds a disposable, domain-representative repo for one routing case so the
# live evaluation prompts land in a project that actually looks like the
# domain (an empty template routes differently from a real repo — measured
# confound in the v2 cycle).
# Usage: seed-repo.sh <case-id> <target-dir> [template-root]
set -euo pipefail

CASE="${1:?usage: seed-repo.sh <case-id> <target-dir> [template-root]}"
DIR="${2:?usage: seed-repo.sh <case-id> <target-dir> [template-root]}"
TPL="${3:-$(cd "$(dirname "$0")/../../.." && pwd)}"

mkdir -p "$DIR"
cp "$TPL/CLAUDE.md" "$DIR/"
cp -r "$TPL/.claude" "$DIR/"
[[ -f "$TPL/.gitignore" ]] && cp "$TPL/.gitignore" "$DIR/"
[[ -f "$TPL/.gitattributes" ]] && cp "$TPL/.gitattributes" "$DIR/"
# When the template root is a primary checkout it may carry worktrees/logs;
# a seeded repo must not.
rm -rf "$DIR/.claude/worktrees" "$DIR/.claude/logs"

cd "$DIR"

py_dag() { # minimal but realistic Airflow DAG
  cat > "$1" <<'EOF'
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator


def load_orders(ds, **_):
    print(f"loading orders for {ds}")


with DAG(
    dag_id="orders_daily",
    start_date=datetime(2026, 1, 1),
    schedule="0 2 * * *",
    catchup=False,
    default_args={"retries": 0, "retry_delay": timedelta(minutes=5)},
) as dag:
    PythonOperator(task_id="load_orders", python_callable=load_orders)
EOF
}

tsql_proc() { # T-SQL stored procedure with a transaction
  cat > "$1" <<'EOF'
CREATE OR ALTER PROCEDURE dbo.usp_update_inventory
    @BatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE TOP (@BatchSize) inv
    SET inv.qty_on_hand = s.qty
    FROM dbo.Inventory inv
    JOIN dbo.Staging_Inventory s ON s.sku = inv.sku;
    COMMIT;
END
EOF
}

case "$CASE" in
  layout-root-mess)
    printf 'print("main")\n' > main.py
    printf 'print("v2")\n' > "main (copy).py"
    printf 'select 1;\n' > adhoc_query.sql
    printf 'notes\n' > notes.txt
    printf 'a,b\n1,2\n' > export_final_v3.csv
    printf '#!/usr/bin/env bash\necho run\n' > run_stuff.sh
    ;;
  layout-python-importable)
    printf 'def helper():\n    return 1\n' > helpers.py
    printf 'from helpers import helper\n\nprint(helper())\n' > mymod.py
    printf 'import mymod\n' > run_all.py
    ;;
  layout-dags-by-team)
    mkdir -p dags
    py_dag dags/orders_daily.py
    py_dag dags/finance_recon.py
    py_dag dags/marketing_sync.py
    ;;
  layout-sql-proc-file)
    mkdir -p sql
    tsql_proc sql/usp_load_orders.sql
    tsql_proc usp_misplaced_proc.sql
    ;;
  layout-frontend-components)
    mkdir -p src/components
    printf 'export const Button = () => <button/>;\n' > src/components/Button.jsx
    printf 'export const card = () => <div/>;\n' > src/components/card.jsx
    printf 'export const NavBar = () => <nav/>;\n' > src/components/NavBar.jsx
    printf '{"name":"app","version":"1.0.0"}\n' > package.json
    ;;
  review-dag-deploy|dag-add-retry)
    mkdir -p dags
    py_dag dags/orders_daily.py
    ;;
  review-proc-deadlock)
    mkdir -p sql
    tsql_proc sql/usp_update_inventory.sql
    ;;
  review-etl-counts)
    mkdir -p dags sql
    py_dag dags/load_orders.py
    printf 'MERGE dbo.Orders AS t USING staging.Orders AS s ON t.id = s.id\nWHEN NOT MATCHED THEN INSERT (id, qty) VALUES (s.id, s.qty);\n' > sql/merge_orders.sql
    ;;
  review-dtsx-thai)
    mkdir -p packages
    cat > packages/LoadCustomers.dtsx <<'EOF'
<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts" DTS:ExecutableType="Microsoft.Package">
  <DTS:Property DTS:Name="PackageFormatVersion">8</DTS:Property>
  <DTS:ObjectName>LoadCustomers</DTS:ObjectName>
  <DTS:Executables>
    <DTS:Executable DTS:ExecutableType="Microsoft.Pipeline">
      <components>
        <component name="Derived Column" componentClassID="Microsoft.DerivedColumn"/>
      </components>
    </DTS:Executable>
  </DTS:Executables>
</DTS:Executable>
EOF
    ;;
  review-api-breaking)
    mkdir -p api routes
    cat > api/openapi.yaml <<'EOF'
openapi: 3.0.3
info: {title: users-api, version: 1.4.0}
paths:
  /users/{id}:
    get:
      responses:
        "200":
          content:
            application/json:
              schema:
                type: object
                properties:
                  id: {type: integer}
                  email: {type: string}
EOF
    printf 'from fastapi import APIRouter\n\nrouter = APIRouter()\n\n\n@router.get("/users/{user_id}")\ndef get_user(user_id: int) -> dict:\n    return {"id": user_id, "email": "x@example.com"}\n' > routes/users.py
    ;;
  review-gha-change)
    mkdir -p .github/workflows
    cat > .github/workflows/deploy.yml <<'EOF'
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh
EOF
    ;;
  move-utils-file)
    mkdir -p helpers
    printf 'def util():\n    return 1\n' > utils.py
    printf 'from utils import util\n' > app.py
    ;;
  cleanup-branch-sequence|cleanup-repo-recall)
    mkdir -p src build dist
    printf 'print("app")\n' > src/app.py
    printf 'artifact\n' > build/out.bin
    printf 'artifact\n' > dist/bundle.js
    printf 'old scratch\n' > untitled1.py
    ;;
  untrack-node-modules)
    mkdir -p node_modules/leftpad src
    printf 'module.exports = (s) => s;\n' > node_modules/leftpad/index.js
    printf 'console.log("app");\n' > src/index.js
    printf '{"name":"app","version":"1.0.0"}\n' > package.json
    # deliberately drop the template .gitignore so node_modules is trackable,
    # matching the real-world mistake the prompt is about
    rm -f .gitignore
    ;;
  secret-scan-repo)
    mkdir -p src
    printf 'import os\n\nDB_URL = os.environ["DATABASE_URL"]\n' > src/config.py
    printf 'print("app")\n' > src/main.py
    ;;
  login-session-cookies)
    mkdir -p templates
    printf 'from flask import Flask, request, session\n\napp = Flask(__name__)\n\n\n@app.route("/login", methods=["POST"])\ndef login():\n    session["user"] = request.form["email"]\n    return "ok"\n' > app.py
    printf '<form method="post"><input name="email"/><input name="pw" type="password"/></form>\n' > templates/login.html
    ;;
  pg-query-performance)
    mkdir -p queries
    cat > queries/slow_search.sql <<'EOF'
-- PostgreSQL
SELECT u.id, u.email, p.payload->>'city' AS city
FROM users u
JOIN profiles p ON p.user_id = u.id
WHERE u.email ILIKE '%@example.com'
ORDER BY u.created_at DESC
LIMIT 50;
EOF
    ;;
  dag-create-orders)
    mkdir -p dags include
    printf '# shared SQL lives here\n' > include/README.md
    ;;
  # ---- v7 full-coverage seeds. One repo shape serves each domain cluster so
  # 25 new cases cost 6 shapes, and prompts land in a repo that looks real.
  cov-api-design|cov-config-management|cov-dependency-review|cov-documentation|\
  cov-fastapi-review|cov-python-performance|cov-python-refactor|cov-python-review|\
  cov-testing|cov-verification|cov-observability|amb-slow-endpoint|amb-cleanup-tests|amb-env-secret|amb-document-api)
    mkdir -p app tests_app
    cat > pyproject.toml <<'EOF'
[project]
name = "orders-service"
version = "0.3.0"
requires-python = ">=3.11"
dependencies = ["fastapi==0.115.0", "uvicorn==0.30.0", "pydantic==2.8.0", "requests==2.32.0"]
EOF
    cat > app/main.py <<'EOF'
from fastapi import Depends, FastAPI

from .parsing import parse_order_line
from .settings import get_settings

app = FastAPI()


@app.get("/orders")
async def list_orders(settings=Depends(get_settings)) -> list[dict]:
    rows = []
    with open(settings.data_file, encoding="utf-8") as fh:
        for line in fh:
            rows.append(parse_order_line(line))
    return rows


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
EOF
    cat > app/parsing.py <<'EOF'
def parse_order_line(line: str) -> dict:
    sku, qty, price = line.strip().split(",")
    total = int(qty) * float(price)
    return {"sku": sku, "qty": int(qty), "total": total}


def compute_payment(subtotal: float, discount_pct: float) -> float:
    if discount_pct < 0 or discount_pct > 100:
        raise ValueError(f"bad discount: {discount_pct}")
    return round(subtotal * (1 - discount_pct / 100), 2)
EOF
    cat > app/settings.py <<'EOF'
import os


def get_settings():
    class S:
        data_file = os.environ.get("ORDERS_DATA_FILE", "orders.csv")
        db_timeout = int(os.environ.get("DB_TIMEOUT", "30"))
    return S()
EOF
    printf 'from app.parsing import compute_payment\n\n\ndef test_payment_basic():\n    assert compute_payment(100.0, 10.0) == 90.0\n' > tests_app/test_parsing.py
    ;;
  cov-docker|cov-docker-review)
    cat > Dockerfile <<'EOF'
FROM python:3.12
COPY . /app
WORKDIR /app
RUN pip install -r requirements.txt
CMD ["python", "server.py"]
EOF
    printf 'flask==3.0.0\n' > requirements.txt
    printf 'print("serving")\n' > server.py
    cat > docker-compose.yml <<'EOF'
services:
  web:
    build: .
    ports: ["8000:8000"]
EOF
    ;;
  cov-kubernetes)
    mkdir -p k8s
    cat > k8s/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
spec:
  replicas: 2
  selector:
    matchLabels: {app: orders}
  template:
    metadata:
      labels: {app: orders}
    spec:
      containers:
        - name: orders
          image: registry.local/orders:1.4.2
          ports: [{containerPort: 8000}]
EOF
    ;;
  cov-database-migrations)
    mkdir -p migrations/versions
    printf '[alembic]\nscript_location = migrations\n' > alembic.ini
    printf '"""add orders table\n\nRevision ID: a1b2c3\n"""\n\nfrom alembic import op\nimport sqlalchemy as sa\n\n\ndef upgrade():\n    op.create_table("users", sa.Column("id", sa.Integer, primary_key=True))\n\n\ndef downgrade():\n    op.drop_table("users")\n' > migrations/versions/0001_add_users.py
    ;;
  cov-design-system|cov-ui-review)
    mkdir -p src/components src/pages
    # shellcheck disable=SC2016  # ${variant} is a JSX template literal, not shell
    printf 'export const Button = ({variant="primary", children}) => <button className={`btn btn-${variant}`}>{children}</button>;\n' > src/components/Button.jsx
    printf 'export const Checkout = () => <main><h1>Checkout</h1><Button>Pay now</Button></main>;\n' > src/pages/Checkout.jsx
    printf '{"name":"web","version":"2.1.0"}\n' > package.json
    ;;
  cov-agent-design|cov-llm-evaluation|cov-prompt-engineering)
    mkdir -p prompts evals
    printf 'You are a support triage assistant. Classify each ticket as BILLING, BUG, or OTHER.\nRespond with JSON: {"category": ..., "confidence": ...}\n' > prompts/triage-system.txt
    printf '{"input": "I was charged twice", "expected": "BILLING"}\n{"input": "App crashes on login", "expected": "BUG"}\n' > evals/golden.jsonl
    ;;
  cov-release-readiness)
    printf '# Changelog\n\n## [Unreleased]\n- fix: order rounding\n\n## [1.1.0] - 2026-06-01\n- feat: orders endpoint\n' > CHANGELOG.md
    printf '__version__ = "1.1.0"\n' > version.py
    printf 'print("app")\n' > app.py
    ;;
  *)
    echo "seed-repo.sh: unknown case id '$CASE'" >&2
    exit 1
    ;;
esac

git init -q .
# Windows MAX_PATH guard: template skill paths are deep; inert elsewhere.
git config core.longpaths true
git add -A
git -c user.email=eval@template -c user.name=routing-eval commit -qm "seed: $CASE"
