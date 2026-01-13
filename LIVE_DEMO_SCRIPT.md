# Semantic Layer v5.1 - Live Demo Script
## 6 Demo Scenarios with Sample Data & Expected Results

**Total Duration:** 20 minutes
**Prerequisites:** Demo API running on http://localhost:8000

---

## Setup Before Demo

### Start the Demo Server

```cmd
cd C:\Projects\semantic-layer-demo
python demo_api.py
```

Or with Docker:
```cmd
docker-compose -f docker-compose.demo.yml up -d
```

### Verify Server is Running

```cmd
curl http://localhost:8000/health
```

**Expected Response:**
```json
{
  "status": "healthy",
  "version": "5.1.0-demo",
  "mode": "DEMO",
  "timestamp": "2026-01-09T10:00:00.000000"
}
```

### Open These URLs in Browser Tabs

1. **Swagger UI:** http://localhost:8000/docs
2. **Demo App:** http://localhost:3000 (if React UI is running)

---

## Demo 1: Natural Language Query (3 minutes)

### Talking Points
> "Let's see how a business user can ask questions in plain English and get instant answers. No SQL knowledge required."

### Step 1: Show the Query Interface

Open Swagger UI → POST `/api/v5/query/nl`

### Step 2: Execute Query

**Input:**
```json
{
  "question": "What's our churn rate by segment?"
}
```

**Click "Execute"**

### Expected Response:

```json
{
  "query": "What's our churn rate by segment?",
  "generated_sql": "SELECT \n    c.segment,\n    COUNT(CASE WHEN s.status = 'Churned' THEN 1 END) as churned_customers,\n    COUNT(*) as total_customers,\n    ROUND(COUNT(CASE WHEN s.status = 'Churned' THEN 1 END) * 100.0 / COUNT(*), 2) as churn_rate\nFROM PROD_EDW.GOLD.DIM_CUSTOMERS c\nJOIN PROD_EDW.GOLD.FACT_SUBSCRIPTIONS s ON c.customer_id = s.customer_id\nWHERE s.start_date >= DATEADD(quarter, -1, CURRENT_DATE())\nGROUP BY c.segment\nORDER BY churn_rate DESC",
  "execution_time_ms": 847,
  "rows_returned": 3,
  "data": [
    {"segment": "Consumer", "churned_customers": 4521, "total_customers": 52847, "churn_rate": 8.55},
    {"segment": "SMB", "churned_customers": 892, "total_customers": 18392, "churn_rate": 4.85},
    {"segment": "Enterprise", "churned_customers": 23, "total_customers": 1247, "churn_rate": 1.84}
  ],
  "confidence": 0.94,
  "entities_used": ["Customer", "Subscription"],
  "metrics_used": ["churn_rate"],
  "pipeline": {
    "steps": [
      {"step": "PARSE", "duration_ms": 45, "status": "complete", "details": "Extracted entities and intent"},
      {"step": "GRAPHRAG", "duration_ms": 120, "status": "complete", "details": "Retrieved context for 2 entities"},
      {"step": "BUILD_SQL", "duration_ms": 85, "status": "complete", "details": "Generated optimized Snowflake SQL"},
      {"step": "SECURITY", "duration_ms": 15, "status": "complete", "details": "Applied RLS and column masking"},
      {"step": "EXECUTE", "duration_ms": 847, "status": "complete", "details": "Returned 3 rows"}
    ],
    "total_time_ms": 1112
  }
}
```

### Key Points to Highlight

1. **"Notice the 5-step pipeline"** - Parse, GraphRAG, Build SQL, Security, Execute
2. **"The AI understood 'churn rate' and 'segment'"** - Mapped to our defined metric
3. **"Generated SQL is optimized for Snowflake"** - Uses our actual table names
4. **"Confidence score is 94%"** - AI is confident in the interpretation
5. **"Under 2 seconds total"** - From question to answer

### Follow-up Query (Optional)

**Input:**
```json
{
  "question": "What was revenue by segment last quarter?"
}
```

---

## Demo 2: Knowledge Graph Navigation (3 minutes)

### Talking Points
> "The Knowledge Graph understands how our data connects. Let's explore the Customer entity and see its relationships."

### Step 1: Show All Entities

**GET** `/api/v5/graph/entities`

**Expected Response:**
```json
{
  "entities": ["Customer", "Order", "Product", "Subscription"],
  "count": 4,
  "details": {
    "Customer": {"description": "Master customer dimension...", "row_count": 2847392},
    "Order": {"description": "Transactional fact table...", "row_count": 48392847},
    "Product": {"description": "Product catalog...", "row_count": 12847},
    "Subscription": {"description": "Customer subscription records...", "row_count": 892384}
  }
}
```

### Step 2: Explore Customer Entity

**GET** `/api/v5/graph/explore/Customer`

**Expected Response:**
```json
{
  "entity": "Customer",
  "details": {
    "name": "Customer",
    "description": "Master customer dimension containing all customer attributes...",
    "physical_table": "PROD_EDW.GOLD.DIM_CUSTOMERS",
    "row_count": 2847392,
    "columns": [
      {"name": "customer_id", "type": "VARCHAR", "is_pk": true},
      {"name": "customer_name", "type": "VARCHAR", "pii": true},
      {"name": "email", "type": "VARCHAR", "pii": true, "mask": "partial"},
      {"name": "segment", "type": "VARCHAR"},
      {"name": "region", "type": "VARCHAR"}
    ]
  },
  "connections": [
    {"entity": "Order", "relationship": "PLACES", "direction": "outgoing", "cardinality": "1:N"},
    {"entity": "Subscription", "relationship": "HAS", "direction": "outgoing", "cardinality": "1:N"},
    {"entity": "Support_Ticket", "relationship": "SUBMITS", "direction": "outgoing", "cardinality": "1:N"}
  ],
  "connection_count": 3
}
```

### Step 3: Find Join Path

**GET** `/api/v5/graph/path?from_entity=Customer&to_entity=Product`

**Expected Response:**
```json
{
  "from": "Customer",
  "to": "Product",
  "paths_found": 1,
  "paths": [
    {
      "path": ["Customer", "Order", "Product"],
      "joins": ["customer_id = customer_id", "product_id = product_id"],
      "relationships": ["PLACES", "CONTAINS"]
    }
  ],
  "recommended_path": {
    "path": ["Customer", "Order", "Product"],
    "joins": ["customer_id = customer_id", "product_id = product_id"]
  }
}
```

### Key Points to Highlight

1. **"We have 4 main entities with 48+ million orders"**
2. **"Customer connects to Order, Subscription, and Support"**
3. **"The system automatically discovers join paths"**
4. **"This is what GraphRAG uses to understand context"**

---

## Demo 3: DDL Impact Analysis (4 minutes)

### Talking Points
> "This is the feature that prevents 3am incidents. Let's simulate a risky schema change and see what it would affect."

### Step 1: Show Available Sample DDLs

**GET** `/api/v5/ddl/samples`

**Expected Response:**
```json
{
  "samples": [
    {
      "name": "High Risk - Rename Primary Key",
      "ddl": "ALTER TABLE PROD_EDW.GOLD.DIM_CUSTOMERS RENAME COLUMN customer_id TO cust_id",
      "expected_risk": 78,
      "description": "Renaming a primary key affects all downstream joins"
    },
    {
      "name": "Low Risk - Add Column",
      "ddl": "ALTER TABLE PROD_EDW.GOLD.DIM_PRODUCTS ADD COLUMN supplier_id VARCHAR(50)",
      "expected_risk": 12,
      "description": "Adding a new column has minimal downstream impact"
    }
  ]
}
```

### Step 2: Analyze HIGH RISK Change

**POST** `/api/v5/ddl/analyze-impact`

**Input:**
```json
{
  "ddl_statement": "ALTER TABLE PROD_EDW.GOLD.DIM_CUSTOMERS RENAME COLUMN customer_id TO cust_id"
}
```

**Expected Response:**
```json
{
  "analysis_id": "impact_20260109_001",
  "risk_score": 78,
  "risk_level": "HIGH",
  "change_type": "COLUMN_RENAME",
  "affected_table": "PROD_EDW.GOLD.DIM_CUSTOMERS",
  "column_affected": "customer_id",
  "downstream_impact": {
    "tables": [
      {"name": "FACT_ORDERS", "join_affected": true, "risk": "HIGH"},
      {"name": "FACT_SUBSCRIPTIONS", "join_affected": true, "risk": "HIGH"}
    ],
    "dashboards": [
      {"name": "Executive KPI Dashboard", "owner": "Finance", "risk": "CRITICAL"},
      {"name": "Customer Analytics Dashboard", "owner": "Customer Success", "risk": "HIGH"}
    ],
    "reports": [
      {"name": "Monthly Board Deck", "schedule": "Monthly", "risk": "CRITICAL"}
    ],
    "data_products": [
      {"name": "Customer 360 API", "consumers": 12, "risk": "CRITICAL"}
    ]
  },
  "affected_counts": {
    "tables": 3,
    "views": 3,
    "dashboards": 4,
    "reports": 2,
    "data_products": 1,
    "total_consumers": 15
  },
  "approval_required": "EXECUTIVE",
  "recommended_actions": [
    "Schedule change during maintenance window",
    "Notify all dashboard owners 48 hours in advance",
    "Update all downstream views before column rename"
  ],
  "estimated_effort": "4-6 hours with team coordination"
}
```

### Step 3: Analyze LOW RISK Change

**Input:**
```json
{
  "ddl_statement": "ALTER TABLE PROD_EDW.GOLD.DIM_PRODUCTS ADD COLUMN supplier_id VARCHAR(50)"
}
```

**Expected Response:**
```json
{
  "risk_score": 12,
  "risk_level": "LOW",
  "affected_counts": {
    "tables": 0,
    "dashboards": 0,
    "total_consumers": 0
  },
  "approval_required": "AUTO_APPROVE",
  "estimated_effort": "< 30 minutes"
}
```

### Key Points to Highlight

1. **"Risk score 78 - this is a HIGH risk change"**
2. **"Look at what would break: 4 dashboards, 2 reports, 1 API"**
3. **"Executive KPI Dashboard marked CRITICAL"**
4. **"System recommends executive approval"**
5. **"Compare to adding a column - risk score 12, auto-approved"**

---

## Demo 4: Security - RLS & Column Masking (3 minutes)

### Talking Points
> "Now let's see security in action. Same query, different users, different results."

### Step 1: Show Available Users

**GET** `/api/v5/security/users`

**Expected Response:**
```json
{
  "users": {
    "sales_rep_west": {
      "display_name": "Sarah Jones",
      "role": "SALES_REP",
      "region": "West",
      "rls_filter": "region = 'West'",
      "masked_columns": ["email", "phone", "ssn", "salary"]
    },
    "vp_sales": {
      "display_name": "Jennifer Martinez",
      "role": "VP_SALES",
      "region": "ALL",
      "rls_filter": null,
      "masked_columns": ["ssn"]
    }
  }
}
```

### Step 2: Query as Sales Rep (West Region)

**POST** `/api/v5/security/demo-query`

**Input:**
```json
{
  "user_type": "sales_rep_west"
}
```

**Expected Response:**
```json
{
  "user": {
    "display_name": "Sarah Jones",
    "role": "SALES_REP",
    "region": "West"
  },
  "applied_rls": "region = 'West'",
  "masked_columns": ["email", "phone", "ssn", "salary"],
  "row_count_before_rls": 5,
  "row_count_after_rls": 2,
  "data": [
    {"customer_id": "C001", "name": "Acme Corp", "email": "jo***@acme.com", "phone": "***-***-4567", "region": "West", "revenue": 125000},
    {"customer_id": "C002", "name": "TechStart Inc", "email": "ja***@techstart.com", "phone": "***-***-5678", "region": "West", "revenue": 89000}
  ]
}
```

### Step 3: Query as VP Sales (All Regions)

**Input:**
```json
{
  "user_type": "vp_sales"
}
```

**Expected Response:**
```json
{
  "user": {
    "display_name": "Jennifer Martinez",
    "role": "VP_SALES",
    "region": "ALL"
  },
  "applied_rls": null,
  "masked_columns": ["ssn"],
  "row_count_before_rls": 5,
  "row_count_after_rls": 5,
  "data": [
    {"customer_id": "C001", "name": "Acme Corp", "email": "john@acme.com", "phone": "555-123-4567", "region": "West", "revenue": 125000},
    {"customer_id": "C002", "name": "TechStart Inc", "email": "jane@techstart.com", "phone": "555-234-5678", "region": "West", "revenue": 89000},
    {"customer_id": "C003", "name": "Global Systems", "email": "bob@global.com", "phone": "555-345-6789", "region": "East", "revenue": 234000}
  ]
}
```

### Step 4: Side-by-Side Comparison

**GET** `/api/v5/security/compare`

Shows all three users querying the same data with different results.

### Key Points to Highlight

1. **"Sarah (Sales Rep) sees only 2 rows - West region"**
2. **"Jennifer (VP) sees all 5 rows - no region filter"**
3. **"Notice Sarah's email shows jo*** - it's masked"**
4. **"Jennifer sees full email john@acme.com"**
5. **"Same query, different results based on WHO is asking"**

---

## Demo 5: Data Lineage (3 minutes)

### Talking Points
> "Where does this number come from? Let's trace the Revenue metric from source to dashboard."

### Step 1: Get Lineage for Total Revenue

**GET** `/api/v5/lineage/metrics/total_revenue`

**Expected Response:**
```json
{
  "metric_name": "total_revenue",
  "lineage": {
    "upstream": [
      {"level": "Source", "name": "SAP ERP", "type": "source_system", "refresh": "Real-time CDC"},
      {"level": "Bronze", "name": "RAW.SAP_ORDERS", "type": "table", "columns": ["AUFNR", "NETWR", "WAERK", "ERDAT"]},
      {"level": "Silver", "name": "STAGING.STG_ORDERS", "type": "table", "transformations": ["Currency conversion", "Date parsing", "Null handling"]},
      {"level": "Gold", "name": "GOLD.FACT_ORDERS", "type": "table", "columns": ["order_id", "customer_id", "order_amount"]},
      {"level": "Semantic", "name": "total_revenue", "type": "metric", "expression": "SUM(CASE WHEN status != 'Cancelled' THEN order_amount END)", "certified": true}
    ],
    "downstream": [
      {"level": "Dashboard", "name": "Executive KPI Dashboard", "tool": "Tableau", "viewers": 45},
      {"level": "Dashboard", "name": "Sales Performance", "tool": "Tableau", "viewers": 128},
      {"level": "Report", "name": "Monthly Board Deck", "tool": "PowerPoint", "schedule": "Monthly"},
      {"level": "API", "name": "Revenue API", "consumers": 8, "calls_per_day": 12000}
    ]
  },
  "column_level_lineage": {
    "order_amount": {
      "source_column": "SAP_ORDERS.NETWR",
      "transformations": ["Currency conversion to USD", "Null replaced with 0", "Aggregated in metric"]
    }
  }
}
```

### Key Points to Highlight

1. **"Start at SAP ERP - that's our source of truth"**
2. **"Bronze layer: raw SAP data, column NETWR"**
3. **"Silver layer: cleaned, currency converted"**
4. **"Gold layer: production-ready FACT_ORDERS"**
5. **"Semantic layer: our certified metric definition"**
6. **"Downstream: 2 dashboards, 1 report, 1 API"**
7. **"173 viewers depend on this data!"**

---

## Demo 6: API Integration (4 minutes)

### Talking Points
> "Let's see how easy it is to integrate this into your applications."

### Step 1: Show Code Samples

**GET** `/api/v5/code-samples`

**Expected Response:**
```json
{
  "samples": {
    "python_query": "import httpx\n\nclient = httpx.Client(\n    base_url=\"http://localhost:8000\",\n    headers={\"Authorization\": \"Bearer YOUR_API_KEY\"}\n)\n\nresponse = client.post(\"/api/v5/query/nl\", json={\n    \"question\": \"What's our churn rate by segment last quarter?\"\n})\n\nresult = response.json()\nprint(f\"Generated SQL: {result['sql']}\")\nprint(f\"Data: {result['data']}\")",
    "curl_query": "curl -X POST http://localhost:8000/api/v5/query/nl \\\n  -H \"Content-Type: application/json\" \\\n  -H \"Authorization: Bearer YOUR_API_KEY\" \\\n  -d '{\"question\": \"What was revenue by region last month?\"}'"
  },
  "languages": ["python", "curl"],
  "documentation_url": "http://localhost:8000/docs"
}
```

### Step 2: Live curl Demo

```cmd
curl -X POST http://localhost:8000/api/v5/query/nl -H "Content-Type: application/json" -d "{\"question\": \"What's our churn rate by segment?\"}"
```

### Step 3: Show Swagger UI

Navigate to http://localhost:8000/docs and show:
- All available endpoints
- Request/response schemas
- Try it out functionality

### Key Points to Highlight

1. **"6 lines of Python to query your data"**
2. **"Works with any language - Python, JavaScript, curl"**
3. **"Full OpenAPI documentation at /docs"**
4. **"API keys for authentication"**
5. **"This is what you'd use in your internal tools"**

---

## Closing (1 minute)

### Summary Slide Points

1. **Natural Language Query** - Ask questions, get answers in seconds
2. **Knowledge Graph** - Understands how your data connects
3. **DDL Governance** - Prevent incidents before they happen
4. **Security** - Right data for right people, automatically
5. **Lineage** - Trace any number to its source
6. **API** - Integrate in minutes, not months

### Call to Action

> "What questions do you have? What would you like to see next?"

---

## Backup Responses (If Things Go Wrong)

### If API is Down
- Use screenshots from this document
- Show the curl commands and expected responses
- "Let me show you what you would see..."

### If Audience Asks Unexpected Questions
- "Great question! Let me show you in the API docs..."
- Navigate to Swagger UI
- Find relevant endpoint
- Show schema and try it

### Common Questions & Answers

**Q: How long does it take to set up?**
A: "Initial setup is 1-2 days. Crawling your 300+ models takes a few hours."

**Q: Does this work with our existing tools?**
A: "Yes - it's API-first. Works with Tableau, Python, any tool that can make HTTP calls."

**Q: What about performance at scale?**
A: "We use 3-layer caching. Metadata is sub-100ms. AI queries are under 5 seconds."

**Q: How accurate is the AI?**
A: "For queries matching our defined metrics, 90%+ accuracy. The Knowledge Graph provides context that generic AI doesn't have."

---

## Files to Have Ready

1. This script (printed or on second monitor)
2. Browser with Swagger UI open
3. Terminal/Command Prompt ready
4. Backup screenshots of all expected responses
