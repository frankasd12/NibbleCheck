# api/main.py
import os
import re
from typing import List, Dict, Any

from fastapi import FastAPI, HTTPException, Query, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import psycopg
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/dogfood",
)
SIMILARITY_FLOOR = float(os.getenv("SIMILARITY_FLOOR", "0.30"))  # tune 0.25–0.35
STATUS_WEIGHT = {"UNSAFE": 3, "CAUTION": 2, "SAFE": 1}  # worst-case wins

app = FastAPI(title="NibbleCheck API", version="0.2.0")

# CORS for dev; tighten for prod
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ALLOW_ORIGINS", "*").split(","),  # e.g. http://localhost:5173
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def db():
    """Get a psycopg3 connection with autocommit and set pg_trgm similarity limit if present."""
    conn = psycopg.connect(DATABASE_URL, autocommit=True)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT set_limit(%s);", (SIMILARITY_FLOOR,))
    except Exception:
        # pg_trgm may not be installed yet (e.g., early CI) — OK for /health etc.
        pass
    return conn


@app.get("/health")
def health():
    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/search")
def search(q: str = Query(..., min_length=1), limit: int = Query(10, ge=1, le=50)):
    sql = """
      SELECT food_id, canonical_name, group_name, default_status, matched, matched_from, score
      FROM search_foods_enriched(%s, %s);
    """
    with db() as conn, conn.cursor() as cur:
        cur.execute(sql, (q, limit))
        rows = cur.fetchall()

    results = [
        {
            "food_id": r[0],
            "canonical_name": r[1],
            "group_name": r[2],
            "default_status": r[3],
            "matched": r[4],
            "matched_from": r[5],
            "score": float(r[6]),
        }
        for r in rows
        if float(r[6]) >= SIMILARITY_FLOOR
    ]
    return {"query": q, "count": len(results), "results": results}


@app.get("/foods/{food_id}")
def food_detail(food_id: int):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, canonical_name, group_name, default_status, notes, sources
            FROM foods WHERE id=%s;
            """,
            (food_id,),
        )
        food = cur.fetchone()
        if not food:
            raise HTTPException(status_code=404, detail="Food not found")

        cur.execute(
            "SELECT name FROM synonyms WHERE food_id=%s ORDER BY name;",
            (food_id,),
        )
        synonyms = [r[0] for r in cur.fetchall()]

        cur.execute("SELECT * FROM rules WHERE food_id=%s ORDER BY id;", (food_id,))
        colnames = [desc.name for desc in cur.description]
        rules = [dict(zip(colnames, row)) for row in cur.fetchall()]

    return {
        "id": food[0],
        "canonical_name": food[1],
        "group_name": food[2],
        "default_status": food[3],
        "notes": food[4],
        "sources": food[5],
        "synonyms": synonyms,
        "rules": rules,
    }


# ---- Helpers ---------------------------------------------------------------

def _pick_overall_status(items: List[Dict[str, Any]]) -> str:
    if not items:
        return "SAFE"
    w = max(STATUS_WEIGHT.get(i["status"], 1) for i in items)
    for k, v in STATUS_WEIGHT.items():
        if v == w:
            return k
    return "SAFE"


_TOKEN_SPLIT_RE = re.compile(r"[,\;/\(\)\[\]\{\}\u2022•]")


def _tokenize_ingredients(s: str) -> List[str]:
    s = s.lower()
    s = _TOKEN_SPLIT_RE.sub(",", s)
    parts = [p.strip() for p in s.split(",")]
    parts = [p for p in parts if 2 <= len(p) <= 64]
    # trim leading/trailing numbers/% (very light normalization)
    parts = [re.sub(r"^\d+%?\s*|\s*\d+%?$", "", p).strip() for p in parts]
    # drop empties and dupes
    seen, out = set(), []
    for p in parts:
        if p and p not in seen:
            out.append(p)
            seen.add(p)
    return out


# ---- Endpoints: CV / OCR + Text -------------------------------------------

@app.post("/classify/resolve")
async def classify_resolve(file: UploadFile = File(...)):
    """
    Multipart upload endpoint.
    Send a field named 'file' with the image (JPEG/PNG).
    """
    try:
        content = await file.read()
        print(f"Received file: {file.filename} ({len(content)} bytes)")
        # TODO: run detector → map labels → DB → rules
        return {"status": "success", "filename": file.filename, "bytes": len(content)}
    except Exception as e:
        print(f"Error processing image: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/ingredients/resolve")
def ingredients_resolve(payload: Dict[str, Any]):
    """
    JSON body: { "ingredients_text": "wheat flour, raisins, cinnamon, sugar" }
    """
    text = str(payload.get("ingredients_text", "")).strip()
    if not text:
        raise HTTPException(status_code=400, detail="ingredients_text is required")

    tokens = _tokenize_ingredients(text)
    hits: List[Dict[str, Any]] = []

    with db() as conn, conn.cursor() as cur:
        for t in tokens:
            cur.execute(
                """
                SELECT food_id, canonical_name, default_status, matched_from, score
                FROM search_foods_enriched(%s, %s);
                """,
                (t, 5),
            )
            rows = [
                {
                    "token": t,
                    "food_id": r[0],
                    "name": r[1],
                    "status": r[2],
                    "matched_from": r[3],
                    "db_score": float(r[4]),
                }
                for r in cur.fetchall()
                if float(r[4]) >= SIMILARITY_FLOOR
            ]
            if rows:
                # rank by worst-case status first, then by score
                best = sorted(
                    rows,
                    key=lambda x: (
                        STATUS_WEIGHT.get(x["status"], 1),
                        x["db_score"],
                    ),
                    reverse=True,
                )[0]
                hits.append(best)

    return {"hits": hits, "overall_status": _pick_overall_status(hits)}
