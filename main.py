"""
NEXA BHARAT - Python FastAPI Backend & REST API Server
"""

import json
import os
import random
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

app = FastAPI(title="NEXA BHARAT API", version="1.0.0")

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
LEADS_FILE = os.path.join(DATA_DIR, "leads.json")
PROJECTS_FILE = os.path.join(DATA_DIR, "projects.json")

os.makedirs(DATA_DIR, exist_ok=True)
if not os.path.exists(LEADS_FILE):
    with open(LEADS_FILE, "w", encoding="utf-8") as f:
        json.dump([], f)
if not os.path.exists(PROJECTS_FILE):
    with open(PROJECTS_FILE, "w", encoding="utf-8") as f:
        json.dump([], f)


def read_leads():
    try:
        with open(LEADS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def write_leads(data):
    with open(LEADS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def read_projects():
    try:
        with open(PROJECTS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


# Data Models
class ConsultationCreate(BaseModel):
    name: str
    phone: str
    email: Optional[str] = ""
    service: Optional[str] = "General Construction"
    location: Optional[str] = "NCR"
    area: Optional[str] = "N/A"
    budget: Optional[str] = "Standard"
    timeline: Optional[str] = "Flexible"
    message: Optional[str] = ""


class ConsultationUpdate(BaseModel):
    id: str
    status: Optional[str] = None
    notes: Optional[str] = None


class EstimateRequest(BaseModel):
    type: Optional[str] = "construction"
    area: Optional[int] = 1200
    tier: Optional[str] = "premium"


# 1. POST /api/consultations
@app.post("/api/consultations", status_code=201)
def create_consultation(payload: ConsultationCreate):
    leads = read_leads()
    new_id = f"NB-{datetime.utcnow().year}-{random.randint(1000, 9999)}"
    now_iso = datetime.utcnow().isoformat() + "Z"

    new_lead = {
        "id": new_id,
        "name": payload.name,
        "phone": payload.phone,
        "email": payload.email,
        "service": payload.service,
        "location": payload.location,
        "area": payload.area,
        "budget": payload.budget,
        "timeline": payload.timeline,
        "message": payload.message,
        "status": "NEW",
        "notes": "Inquiry received via website form.",
        "createdAt": now_iso,
    }

    leads.insert(0, new_lead)
    write_leads(leads)

    return {
        "success": True,
        "message": "Consultation request received successfully.",
        "leadId": new_id,
        "data": new_lead,
    }


# 2. GET /api/consultations
@app.get("/api/consultations")
def list_consultations(
    status: Optional[str] = Query(None), search: Optional[str] = Query(None)
):
    leads = read_leads()

    if status and status != "ALL":
        leads = [l for l in leads if l.get("status") == status]

    if search:
        q = search.lower()
        leads = [
            l
            for l in leads
            if (
                q in l.get("name", "").lower()
                or q in l.get("phone", "").lower()
                or q in l.get("email", "").lower()
                or q in l.get("location", "").lower()
            )
        ]

    return {"success": True, "count": len(leads), "data": leads}


# 3. PATCH /api/consultations
@app.patch("/api/consultations")
def update_consultation(payload: ConsultationUpdate):
    leads = read_leads()
    for lead in leads:
        if lead.get("id") == payload.id:
            if payload.status:
                lead["status"] = payload.status
            if payload.notes is not None:
                lead["notes"] = payload.notes
            write_leads(leads)
            return {
                "success": True,
                "message": "Lead updated successfully.",
                "data": lead,
            }

    raise HTTPException(status_code=404, detail="Lead not found")


# 4. DELETE /api/consultations
@app.delete("/api/consultations")
def delete_consultation(id: str = Query(...)):
    leads = read_leads()
    leads = [l for l in leads if l.get("id") != id]
    write_leads(leads)
    return {"success": True, "message": "Lead deleted successfully."}


# 5. GET /api/consultations/export (CSV)
@app.get("/api/consultations/export")
def export_csv():
    leads = read_leads()
    csv_lines = [
        "Lead ID,Name,Phone,Email,Service,Location,Area,Budget,Timeline,Status,Created At,Notes"
    ]

    for l in leads:
        name = l.get("name", "").replace('"', '""')
        notes = l.get("notes", "").replace('"', '""')
        csv_lines.append(
            f'"{l.get("id")}","{name}","{l.get("phone")}","{l.get("email")}","{l.get("service")}","{l.get("location")}","{l.get("area")}","{l.get("budget")}","{l.get("timeline")}","{l.get("status")}","{l.get("createdAt")}","{notes}"'
        )

    csv_content = "\r\n".join(csv_lines)
    return Response(
        content=csv_content,
        media_type="text/csv",
        headers={
            "Content-Disposition": "attachment; filename=nexa_bharat_leads.csv"
        },
    )


# 6. GET /api/stats
@app.get("/api/stats")
def get_stats():
    leads = read_leads()
    total = len(leads)
    new_count = len([l for l in leads if l.get("status") == "NEW"])
    site_visits = len(
        [l for l in leads if l.get("status") == "SITE_VISIT_SCHEDULED"]
    )
    proposals = len([l for l in leads if l.get("status") == "PROPOSAL_SENT"])
    won = len([l for l in leads if l.get("status") == "WON"])

    return {
        "success": True,
        "data": {
            "totalLeads": total,
            "newLeads": new_count,
            "siteVisitsScheduled": site_visits,
            "proposalsSent": proposals,
            "wonProjects": won,
            "estimatedPipeline": "₹14.85 Cr",
            "conversionRate": round((won / total) * 100, 1) if total > 0 else 0,
        },
    }


# 7. POST /api/estimate
@app.post("/api/estimate")
def calculate_estimate(payload: EstimateRequest):
    rate_map = {
        "construction": {
            "standard": {"min": 1650, "max": 1850},
            "premium": {"min": 2100, "max": 2500},
            "luxury": {"min": 2900, "max": 3600},
        },
        "interiors": {
            "standard": {"min": 1200, "max": 1500},
            "premium": {"min": 1800, "max": 2400},
            "luxury": {"min": 2800, "max": 4000},
        },
        "renovation": {
            "standard": {"min": 900, "max": 1250},
            "premium": {"min": 1400, "max": 1900},
            "luxury": {"min": 2200, "max": 3100},
        },
        "modular-kitchen": {
            "standard": {"min": 1300, "max": 1700},
            "premium": {"min": 2000, "max": 2800},
            "luxury": {"min": 3200, "max": 4800},
        },
    }

    rates = rate_map.get(payload.type, rate_map["construction"]).get(
        payload.tier, {"min": 2100, "max": 2500}
    )
    min_tot = rates["min"] * payload.area
    max_tot = rates["max"] * payload.area
    avg_tot = (min_tot + max_tot) / 2

    return {
        "success": True,
        "type": payload.type,
        "area": payload.area,
        "tier": payload.tier,
        "rateRange": f"₹{rates['min']} - ₹{rates['max']} / sq.ft.",
        "minEstimate": min_tot,
        "maxEstimate": max_tot,
        "breakdown": {
            "civilMaterials": round(avg_tot * 0.45),
            "laborAndMEP": round(avg_tot * 0.25),
            "joineryAndFinishes": round(avg_tot * 0.20),
            "supervisionTaxes": round(avg_tot * 0.10),
        },
    }


# 8. GET /api/projects
@app.get("/api/projects")
def list_projects():
    projects = read_projects()
    return {"success": True, "count": len(projects), "data": projects}


# Serve Static files from current directory
app.mount("/", StaticFiles(directory=os.path.dirname(__file__), html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
