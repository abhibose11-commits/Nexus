# Semantic Layer v5.1 - Deployment Guide
## Windows + Docker + Command Prompt + Azure AD SSO

---

## Prerequisites

1. **Docker Desktop** installed and running
2. **Snowflake account** with Azure AD SSO enabled
3. **Your Azure AD email** and a **granted role** in Snowflake

---

## Quick Start (5 minutes)

### Step 1: Extract Files

```cmd
cd C:\Projects
mkdir semantic-layer
cd semantic-layer
REM Extract the zip file here (right-click > Extract All)
```

### Step 2: Run Setup

```cmd
setup.bat
```

This will:
- Check if Docker is installed
- Create `.env` file from template
- Open `.env` in Notepad for you to edit

### Step 3: Edit Your Connection Details

When Notepad opens with `.env`, update these values:

```
SNOWFLAKE_ACCOUNT=xy12345.east-us-2.azure
SNOWFLAKE_USER=your.email@company.com
SNOWFLAKE_ROLE=YOUR_ROLE
SNOWFLAKE_WAREHOUSE=YOUR_WAREHOUSE
SNOWFLAKE_DATABASE=YOUR_DATABASE
```

Save and close Notepad.

### Step 4: Build and Run

```cmd
docker-compose build
docker-compose up -d
```

### Step 5: Verify

```cmd
REM Check if container is running
docker ps

REM View logs
docker-compose logs

REM Test the API
curl http://localhost:8000/health
```

Open in browser: **http://localhost:8000/docs**

---

## Detailed Command Prompt Instructions

### 1. Create Project Directory

```cmd
mkdir C:\Projects\semantic-layer
cd C:\Projects\semantic-layer
```

### 2. Extract the Zip File

Right-click the zip file and select "Extract All" to `C:\Projects\semantic-layer`

After extracting, you should have:

```
C:\Projects\semantic-layer\
    app\
    Dockerfile
    docker-compose.yml
    requirements.txt
    config.template.yaml
    .env.template
    setup.bat
    test_connection.py
```

### 3. Create Environment File

```cmd
copy .env.template .env
notepad .env
```

Update these values in `.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `SNOWFLAKE_ACCOUNT` | Your account identifier | `xy12345.east-us-2.azure` |
| `SNOWFLAKE_USER` | Your Azure AD email | `abhi.basu@company.com` |
| `SNOWFLAKE_ROLE` | Role to use | `DATA_ENGINEER_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | Warehouse name | `ANALYTICS_WH` |
| `SNOWFLAKE_DATABASE` | Database to focus on | `PROD_EDW` |

### 4. Create Config File (Optional)

```cmd
copy config.template.yaml config.yaml
notepad config.yaml
```

### 5. Create Directories

```cmd
mkdir logs
mkdir token_cache
```

### 6. Build Docker Image

```cmd
docker-compose build
```

### 7. Start the Service

```cmd
REM Start in background
docker-compose up -d

REM Or start with logs visible
docker-compose up
```

### 8. Verify Deployment

```cmd
REM Check container status
docker ps

REM Check health
curl http://localhost:8000/health

REM View API capabilities
curl http://localhost:8000/api/v5/capabilities
```

---

## Managing the Service

### View Logs

```cmd
REM Follow logs in real-time
docker-compose logs -f

REM View last 100 lines
docker-compose logs --tail=100
```

### Stop Service

```cmd
docker-compose down
```

### Restart Service

```cmd
docker-compose restart
```

### Rebuild After Code Changes

```cmd
docker-compose build --no-cache
docker-compose up -d
```

---

## Finding Your Snowflake Details

### Account Identifier

Your Snowflake URL looks like:
```
https://xy12345.east-us-2.azure.snowflakecomputing.com
```

Your account identifier is: `xy12345.east-us-2.azure`

### Finding Available Roles

Log into Snowflake and run:
```sql
SHOW GRANTS TO USER "your.email@company.com";
```

### List Databases You Can Access

```sql
SHOW DATABASES;
```

---

## API Quick Reference

| Endpoint | Description |
|----------|-------------|
| `http://localhost:8000/docs` | Swagger UI (interactive API docs) |
| `http://localhost:8000/health` | Health check |
| `http://localhost:8000/api/v5/capabilities` | List all features |

### Common API Calls

```cmd
REM Health check
curl http://localhost:8000/health

REM Get capabilities
curl http://localhost:8000/api/v5/capabilities

REM Trigger DDL crawl
curl -X POST http://localhost:8000/api/v5/ddl/crawl

REM Get crawl status
curl http://localhost:8000/api/v5/ddl/crawl/status

REM List schemas
curl http://localhost:8000/api/v5/ddl/schemas

REM Search for assets
curl "http://localhost:8000/api/v5/search?q=customer"
```

---

## Troubleshooting

### Container won't start

```cmd
REM Check Docker is running
docker --version

REM Check for errors
docker-compose logs

REM Rebuild from scratch
docker-compose down
docker-compose build --no-cache
docker-compose up
```

### Port 8000 already in use

```cmd
REM Find what's using port 8000
netstat -ano | findstr :8000

REM Kill the process (replace 12345 with actual PID)
taskkill /PID 12345 /F
```

### Reset everything

```cmd
docker-compose down
docker system prune -f
rmdir /s /q token_cache
mkdir token_cache
docker-compose build --no-cache
docker-compose up -d
```

---

## Alternative: Run Without Docker

### 1. Install Python 3.11+

Download from https://www.python.org/downloads/

### 2. Create Virtual Environment

```cmd
cd C:\Projects\semantic-layer
python -m venv venv
venv\Scripts\activate.bat
```

### 3. Install Dependencies

```cmd
pip install -r requirements.txt
```

### 4. Set Environment Variables

```cmd
set SNOWFLAKE_ACCOUNT=xy12345.east-us-2.azure
set SNOWFLAKE_USER=your.email@company.com
set SNOWFLAKE_ROLE=YOUR_ROLE
set SNOWFLAKE_WAREHOUSE=YOUR_WAREHOUSE
set SNOWFLAKE_DATABASE=YOUR_DATABASE
set SNOWFLAKE_AUTHENTICATOR=externalbrowser
```

### 5. Run the Server

```cmd
python -m uvicorn app.main_v5:app --host 0.0.0.0 --port 8000 --reload
```

---

## Command Reference

| Action | Command |
|--------|---------|
| Build image | `docker-compose build` |
| Start service | `docker-compose up -d` |
| View logs | `docker-compose logs -f` |
| Stop service | `docker-compose down` |
| Restart | `docker-compose restart` |
| Check status | `docker ps` |
| Health check | `curl http://localhost:8000/health` |
| API docs | Open `http://localhost:8000/docs` in browser |
