# Semantic Layer v5.1 Deployment Guide
## Windows + Azure AD SSO + Single Database

---

## Prerequisites

### 1. Python 3.11+
```powershell
# Check Python version
python --version

# If not installed, download from https://www.python.org/downloads/
# OR use winget:
winget install Python.Python.3.11
```

### 2. Git (optional, for version control)
```powershell
winget install Git.Git
```

### 3. Visual Studio Code (recommended)
```powershell
winget install Microsoft.VisualStudioCode
```

---

## Step 1: Set Up Project Directory

```powershell
# Create project directory
mkdir C:\Projects\semantic-layer
cd C:\Projects\semantic-layer

# Create virtual environment
python -m venv venv

# Activate virtual environment
.\venv\Scripts\Activate.ps1

# If you get execution policy error, run:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Step 2: Install Dependencies

```powershell
# Upgrade pip
python -m pip install --upgrade pip

# Install core dependencies
pip install fastapi uvicorn[standard] pydantic python-dotenv pyyaml

# Install Snowflake connector with SSO support
pip install "snowflake-connector-python[secure-local-storage]"

# Install additional dependencies
pip install httpx aiofiles python-multipart

# Optional: for Redis caching
pip install redis

# Optional: for dbt integration
pip install dbt-snowflake
```

### Create requirements.txt
```powershell
pip freeze > requirements.txt
```

---

## Step 3: Copy Application Files

Copy the semantic layer files from the zip to your project:

```
C:\Projects\semantic-layer\
├── app\
│   ├── __init__.py
│   ├── main_v5.py
│   ├── snowflake_connection.py      # NEW: Azure AD connection
│   ├── config.py                     # NEW: Configuration loader
│   ├── compliance\
│   ├── contracts\
│   ├── costs\
│   ├── dbt\
│   ├── gateway\
│   ├── governance\
│   ├── products\
│   ├── quality\
│   ├── search\
│   ├── security\
│   └── workflows\
├── config.yaml                       # Your configuration
├── config.template.yaml              # Template (don't edit)
├── requirements.txt
├── .env                              # Environment variables (optional)
└── README.md
```

---

## Step 4: Configure Your Connection

### Option A: Using config.yaml (Recommended)

1. Copy the template:
```powershell
copy config.template.yaml config.yaml
```

2. Edit `config.yaml` with your values:
```yaml
snowflake:
  # Your Snowflake account - find this in Snowflake URL
  # If your URL is: https://xy12345.east-us-2.azure.snowflakecomputing.com
  # Then account is: xy12345.east-us-2.azure
  account: "xy12345.east-us-2.azure"
  
  # Your Azure AD email
  user: "abhi.basu@yourcompany.com"
  
  # The role you want to use (must be granted to you)
  role: "DATA_ENGINEER_ROLE"
  
  # Your warehouse
  warehouse: "ANALYTICS_WH"
  
  # The single database to focus on
  database: "PROD_EDW"
  
  # Default schema
  schema: "ANALYTICS"
  
  # Keep this as externalbrowser for Azure AD SSO
  authenticator: "externalbrowser"
```

### Option B: Using Environment Variables

Create a `.env` file:
```env
SNOWFLAKE_ACCOUNT=xy12345.east-us-2.azure
SNOWFLAKE_USER=abhi.basu@yourcompany.com
SNOWFLAKE_ROLE=DATA_ENGINEER_ROLE
SNOWFLAKE_WAREHOUSE=ANALYTICS_WH
SNOWFLAKE_DATABASE=PROD_EDW
SNOWFLAKE_SCHEMA=ANALYTICS
SNOWFLAKE_AUTHENTICATOR=externalbrowser
```

---

## Step 5: Test Snowflake Connection

### Quick Test Script
Create `test_connection.py`:
```python
"""Test Snowflake connection with Azure AD SSO"""
from app.snowflake_connection import SnowflakeConfig, SnowflakeConnectionManager

# Update these values for your environment
config = SnowflakeConfig(
    account="xy12345.east-us-2.azure",      # Your account
    user="abhi.basu@yourcompany.com",        # Your email
    role="DATA_ENGINEER_ROLE",               # Your role
    warehouse="ANALYTICS_WH",                # Your warehouse
    database="PROD_EDW"                      # Your database
)

print("Testing Snowflake connection...")
print("A browser window will open for Azure AD authentication.\n")

manager = SnowflakeConnectionManager(config)
result = manager.test_connection()

if result["status"] == "connected":
    print("✅ SUCCESS! Connected to Snowflake\n")
    for key, value in result["details"].items():
        print(f"  {key}: {value}")
else:
    print(f"❌ FAILED: {result['error']}")
```

### Run the test:
```powershell
python test_connection.py
```

**Expected behavior:**
1. A browser window opens
2. You log in with your Azure AD credentials
3. You may see MFA prompt
4. Browser shows "Authentication successful"
5. Terminal shows connection details

---

## Step 6: Find Your Snowflake Account Details

### How to find your account identifier:

1. **From Snowflake URL:**
   - Go to Snowflake
   - Look at the URL: `https://xy12345.east-us-2.azure.snowflakecomputing.com`
   - Your account is: `xy12345.east-us-2.azure`

2. **From Snowflake UI:**
   - Click your user icon (bottom left)
   - Click "Account"
   - Copy the "Account Identifier"

### How to find available roles:
```sql
-- Run this in Snowflake
SHOW GRANTS TO USER "your.email@company.com";
```

### How to see your current role:
```sql
SELECT CURRENT_ROLE();
```

### List databases you can access:
```sql
SHOW DATABASES;
```

---

## Step 7: Start the Semantic Layer

### Development Mode (with auto-reload):
```powershell
cd C:\Projects\semantic-layer
.\venv\Scripts\Activate.ps1
uvicorn app.main_v5:app --reload --host 0.0.0.0 --port 8000
```

### Production Mode:
```powershell
uvicorn app.main_v5:app --host 0.0.0.0 --port 8000 --workers 4
```

### Access the API:
- **Swagger UI:** http://localhost:8000/docs
- **ReDoc:** http://localhost:8000/redoc
- **Health Check:** http://localhost:8000/health

---

## Step 8: Verify Deployment

### Check capabilities:
```powershell
curl http://localhost:8000/api/v5/capabilities
```

### Test DDL governance:
```powershell
# Trigger a metadata crawl
curl -X POST http://localhost:8000/api/v5/ddl/crawl

# Check crawl status
curl http://localhost:8000/api/v5/ddl/crawl/status

# List schemas
curl http://localhost:8000/api/v5/ddl/schemas
```

---

## Troubleshooting

### Error: "externalbrowser authentication is not supported"
```powershell
# Reinstall with SSO support
pip uninstall snowflake-connector-python
pip install "snowflake-connector-python[secure-local-storage]"
```

### Error: "Failed to connect to account"
- Verify your account identifier format
- Check if you're on VPN (some orgs require it)
- Try the connection in Snowflake CLI first:
  ```powershell
  snowsql -a xy12345.east-us-2.azure -u your.email@company.com --authenticator externalbrowser
  ```

### Error: "Role does not exist or not authorized"
- Ask your Snowflake admin to grant the role to your user:
  ```sql
  GRANT ROLE DATA_ENGINEER_ROLE TO USER "your.email@company.com";
  ```

### Browser doesn't open for authentication
- Make sure you're running in a terminal with GUI access
- Check if default browser is set in Windows settings
- Try setting browser explicitly:
  ```python
  import webbrowser
  webbrowser.register('chrome', None, webbrowser.BackgroundBrowser("C://Program Files//Google//Chrome//Application//chrome.exe"))
  ```

### Token expired / Session timeout
- The connector caches tokens automatically
- For long-running servers, implement token refresh:
  ```python
  # Tokens are automatically refreshed, but if issues persist:
  manager.disconnect()
  manager.connect()  # Will use cached token or prompt for new auth
  ```

---

## Create Windows Service (Optional)

For production deployment, run as a Windows service:

### Using NSSM (Non-Sucking Service Manager):
```powershell
# Download NSSM
winget install nssm

# Install service
nssm install SemanticLayer "C:\Projects\semantic-layer\venv\Scripts\python.exe"
nssm set SemanticLayer AppParameters "-m uvicorn app.main_v5:app --host 0.0.0.0 --port 8000"
nssm set SemanticLayer AppDirectory "C:\Projects\semantic-layer"
nssm set SemanticLayer DisplayName "Semantic Layer v5.1"

# Start service
nssm start SemanticLayer
```

---

## Quick Reference: Key Commands

```powershell
# Activate environment
.\venv\Scripts\Activate.ps1

# Start server (development)
uvicorn app.main_v5:app --reload --port 8000

# Start server (production)
uvicorn app.main_v5:app --host 0.0.0.0 --port 8000 --workers 4

# Test connection
python test_connection.py

# Check API health
curl http://localhost:8000/health

# View API docs
start http://localhost:8000/docs
```

---

## Next Steps

1. **Configure schemas to crawl** in `config.yaml`
2. **Run initial metadata crawl** via API
3. **Set up security policies** (RLS, masking)
4. **Create data contracts** for critical tables
5. **Connect EDW-Nexus** to the API

---

## Support

- **Slack:** #semantic-layer-support
- **Documentation:** [Confluence link]
- **Issues:** [GitHub/Jira link]
