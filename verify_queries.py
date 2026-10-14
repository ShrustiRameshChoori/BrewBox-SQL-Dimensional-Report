"""
verify_queries.py - runs the BrewBox project in an in-memory SQLite database so you can
sanity-check results WITHOUT installing MySQL. (MySQL is the real target; SQLite has no
ROLLUP/GROUPING, so that report is emulated with UNION ALL - same numbers.)
Usage:  python verify_queries.py
"""
import re, sqlite3

def read(f): return open(f, encoding="utf-8").read()

def to_sqlite(sql):
    sql = re.sub(r"DROP DATABASE.*?;|CREATE DATABASE.*?;|USE \w+;", "", sql)
    return sql

def show(cur, title, sql, params=()):
    print("\n" + "=" * 8, title, "=" * 8)
    cur.execute(sql, params)
    cols = [c[0] for c in cur.description]
    rows = cur.fetchall()
    print(" | ".join(cols))
    for r in rows:
        print(" | ".join("" if v is None else str(v) for v in r))
    return rows

con = sqlite3.connect(":memory:")
con.executescript(to_sqlite(read("schema.sql")))
con.executescript(to_sqlite(read("data.sql")))
cur = con.cursor()

# pull individual SELECTs from reports.sql (skip MySQL-only parts)
rep = to_sqlite(read("reports.sql"))
rep = rep.split("-- REPORT 4")[0]            # reports 1-3 are portable
stmts = [s.strip() for s in rep.split(";") if s.strip() and "SELECT" in s.upper() or "CREATE VIEW" in s.upper()]
n = 0
for s in [x.strip() for x in rep.split(";")]:
    s = re.sub(r"(?m)^\s*--.*$", "", s).strip()
    if not s: continue
    if s.upper().startswith(("DROP VIEW", "CREATE VIEW")):
        cur.execute(s); continue
    n += 1
    show(cur, f"query {n}", s)

show(cur, "ROLLUP (emulated)", """
SELECT region, category, units_sold, revenue FROM (
  SELECT s.region AS region, p.category AS category, SUM(f.quantity) units_sold, SUM(f.total_amount) revenue, 0 g1, 0 g2
  FROM fact_sales f JOIN dim_store s ON f.store_key=s.store_key JOIN dim_product p ON f.product_key=p.product_key
  GROUP BY s.region, p.category
  UNION ALL
  SELECT s.region, '-- Region Subtotal --', SUM(f.quantity), SUM(f.total_amount), 0, 1
  FROM fact_sales f JOIN dim_store s ON f.store_key=s.store_key GROUP BY s.region
  UNION ALL
  SELECT '** GRAND TOTAL **', '', SUM(quantity), SUM(total_amount), 1, 1 FROM fact_sales
) ORDER BY g1, region, g2, category""")

print("\n" + "=" * 8, "EXPLAIN QUERY PLAN (SQLite) before/after index", "=" * 8)
q = "SELECT * FROM fact_sales WHERE order_id = 'ORD-1050'"
print("BEFORE:", cur.execute("EXPLAIN QUERY PLAN " + q).fetchall())
cur.execute("CREATE INDEX idx_fact_order ON fact_sales(order_id)")
print("AFTER :", cur.execute("EXPLAIN QUERY PLAN " + q).fetchall())

# integrity checks
bad = cur.execute("SELECT COUNT(*) FROM fact_sales WHERE ROUND(quantity*unit_price-discount_amount,2) <> total_amount").fetchone()[0]
print("\nIntegrity: rows where total <> qty*price-discount ->", bad)
