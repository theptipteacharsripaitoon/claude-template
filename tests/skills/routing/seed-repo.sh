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
  cleanup-branch-sequence)
    mkdir -p src build dist
    printf 'print("app")\n' > src/app.py
    printf 'artifact\n' > build/out.bin
    printf 'artifact\n' > dist/bundle.js
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
