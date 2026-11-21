from fastapi import FastAPI

from app.api.v1.choir import router as choir_router

app = FastAPI(title="Coral IA", version="0.1.0")
app.include_router(choir_router, prefix="/api/v1", tags=["coral"])


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
