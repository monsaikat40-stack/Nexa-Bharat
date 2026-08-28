/**
 * NEXA BHARAT - Node.js Express Backend & REST API Engine
 */

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

const DATA_DIR = path.join(__dirname, 'data');
const LEADS_FILE = path.join(DATA_DIR, 'leads.json');
const PROJECTS_FILE = path.join(DATA_DIR, 'projects.json');

// Ensure data folder and files exist
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(LEADS_FILE)) fs.writeFileSync(LEADS_FILE, '[]', 'utf8');
if (!fs.existsSync(PROJECTS_FILE)) fs.writeFileSync(PROJECTS_FILE, '[]', 'utf8');

// Helper Functions
const getLeads = () => {
  try {
    const raw = fs.readFileSync(LEADS_FILE, 'utf8');
    return JSON.parse(raw || '[]');
  } catch (err) {
    return [];
  }
};

const saveLeads = (data) => {
  fs.writeFileSync(LEADS_FILE, JSON.stringify(data, null, 2), 'utf8');
};

const getProjects = () => {
  try {
    const raw = fs.readFileSync(PROJECTS_FILE, 'utf8');
    return JSON.parse(raw || '[]');
  } catch (err) {
    return [];
  }
};

// Middlewares
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname)));

// ==========================================
// REST API ROUTES
// ==========================================

// 1. POST /api/consultations -> Create Lead
app.post('/api/consultations', (req, res) => {
  const { name, phone, email, service, location, area, budget, timeline, message } = req.body;

  if (!name || !phone) {
    return res.status(400).json({ success: false, error: 'Name and Phone number are required.' });
  }

  const leads = getLeads();
  const newLead = {
    id: `NB-${new Date().getFullYear()}-${Math.floor(1000 + Math.random() * 9000)}`,
    name,
    phone,
    email: email || '',
    service: service || 'General Construction',
    location: location || 'NCR',
    area: area || 'N/A',
    budget: budget || 'Standard',
    timeline: timeline || 'Flexible',
    message: message || '',
    status: 'NEW',
    notes: 'Inquiry received via website form.',
    createdAt: new Date().toISOString()
  };

  leads.unshift(newLead);
  saveLeads(leads);

  res.status(201).json({
    success: true,
    message: 'Consultation request received successfully.',
    leadId: newLead.id,
    data: newLead
  });
});

// 2. GET /api/consultations -> List Leads (with Search & Status filter)
app.get('/api/consultations', (req, res) => {
  let leads = getLeads();
  const { status, search } = req.query;

  if (status && status !== 'ALL') {
    leads = leads.filter(l => l.status === status);
  }

  if (search) {
    const q = search.toLowerCase();
    leads = leads.filter(l => 
      (l.name && l.name.toLowerCase().includes(q)) ||
      (l.phone && l.phone.toLowerCase().includes(q)) ||
      (l.email && l.email.toLowerCase().includes(q)) ||
      (l.location && l.location.toLowerCase().includes(q))
    );
  }

  res.json({ success: true, count: leads.length, data: leads });
});

// 3. PATCH /api/consultations -> Update Lead Status / Notes
app.patch('/api/consultations', (req, res) => {
  const { id, status, notes } = req.body;
  const leads = getLeads();
  const index = leads.findIndex(l => l.id === id);

  if (index === -1) {
    return res.status(404).json({ success: false, error: 'Lead not found.' });
  }

  if (status) leads[index].status = status;
  if (notes !== undefined) leads[index].notes = notes;

  saveLeads(leads);
  res.json({ success: true, message: 'Lead updated successfully.', data: leads[index] });
});

// 4. DELETE /api/consultations -> Delete Lead
app.delete('/api/consultations', (req, res) => {
  const { id } = req.query;
  let leads = getLeads();
  leads = leads.filter(l => l.id !== id);
  saveLeads(leads);
  res.json({ success: true, message: 'Lead deleted successfully.' });
});

// 5. GET /api/consultations/export -> Export CSV
app.get('/api/consultations/export', (req, res) => {
  const leads = getLeads();
  let csv = 'Lead ID,Name,Phone,Email,Service,Location,Area,Budget,Timeline,Status,Created At,Notes\r\n';

  leads.forEach(l => {
    const cleanName = (l.name || '').replace(/"/g, '""');
    const cleanNotes = (l.notes || '').replace(/"/g, '""');
    csv += `"${l.id}","${cleanName}","${l.phone}","${l.email}","${l.service}","${l.location}","${l.area}","${l.budget}","${l.timeline}","${l.status}","${l.createdAt}","${cleanNotes}"\r\n`;
  });

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename=nexa_bharat_leads.csv');
  res.send(csv);
});

// 6. GET /api/stats -> KPI Summary
app.get('/api/stats', (req, res) => {
  const leads = getLeads();
  const totalLeads = leads.length;
  const newLeads = leads.filter(l => l.status === 'NEW').length;
  const siteVisits = leads.filter(l => l.status === 'SITE_VISIT_SCHEDULED').length;
  const proposalsSent = leads.filter(l => l.status === 'PROPOSAL_SENT').length;
  const wonProjects = leads.filter(l => l.status === 'WON').length;

  res.json({
    success: true,
    data: {
      totalLeads,
      newLeads,
      siteVisitsScheduled: siteVisits,
      proposalsSent,
      wonProjects,
      estimatedPipeline: '₹14.85 Cr',
      conversionRate: totalLeads > 0 ? ((wonProjects / totalLeads) * 100).toFixed(1) : 0
    }
  });
});

// 7. POST /api/estimate -> Dynamic Cost Calculation
app.post('/api/estimate', (req, res) => {
  const { type = 'construction', area = 1200, tier = 'premium' } = req.body;

  const rateMap = {
    'construction': { standard: { min: 1650, max: 1850 }, premium: { min: 2100, max: 2500 }, luxury: { min: 2900, max: 3600 } },
    'interiors':    { standard: { min: 1200, max: 1500 }, premium: { min: 1800, max: 2400 }, luxury: { min: 2800, max: 4000 } },
    'renovation':   { standard: { min: 900,  max: 1250 }, premium: { min: 1400, max: 1900 }, luxury: { min: 2200, max: 3100 } },
    'modular-kitchen': { standard: { min: 1300, max: 1700 }, premium: { min: 2000, max: 2800 }, luxury: { min: 3200, max: 4800 } }
  };

  const rates = rateMap[type]?.[tier] || rateMap['construction']['premium'];
  const minTotal = rates.min * area;
  const maxTotal = rates.max * area;
  const avgTotal = (minTotal + maxTotal) / 2;

  res.json({
    success: true,
    type,
    area,
    tier,
    rateRange: `₹${rates.min} - ₹${rates.max} / sq.ft.`,
    minEstimate: minTotal,
    maxEstimate: maxTotal,
    breakdown: {
      civilMaterials: Math.round(avgTotal * 0.45),
      laborAndMEP: Math.round(avgTotal * 0.25),
      joineryAndFinishes: Math.round(avgTotal * 0.20),
      supervisionTaxes: Math.round(avgTotal * 0.10)
    }
  });
});

// 8. GET /api/projects -> Projects CMS
app.get('/api/projects', (req, res) => {
  const projects = getProjects();
  res.json({ success: true, count: projects.length, data: projects });
});

// Start Server
app.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`  NEXA BHARAT Express Server running on port ${PORT}`);
  console.log(`  Website:   http://localhost:${PORT}/index.html`);
  console.log(`  Admin CRM: http://localhost:${PORT}/admin.html`);
  console.log(`=======================================================`);
});
