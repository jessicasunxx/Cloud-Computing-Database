#!/bin/bash

# MySQL Setup Script for User Service
# This script sets up MySQL database completely under your control
# Run this script on your VM to set up MySQL from scratch
# Usage: sudo ./setup-mysql.sh

set -e

echo "=========================================="
echo "MySQL Database Complete Setup Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root (needed for MySQL installation)
if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}This script requires root privileges to install MySQL${NC}"
   echo "Please run with: sudo ./setup-mysql.sh"
   exit 1
fi

echo -e "${YELLOW}Step 1: Updating system packages...${NC}"
apt-get update

echo -e "${YELLOW}Step 2: Installing MySQL Server...${NC}"
apt-get install -y mysql-server

echo -e "${YELLOW}Step 3: Starting MySQL service...${NC}"
systemctl enable mysql
systemctl start mysql

# Wait for MySQL to be ready
sleep 3

echo -e "${YELLOW}Step 4: Checking MySQL status...${NC}"
if systemctl is-active --quiet mysql; then
    echo -e "${GREEN}✅ MySQL service is running${NC}"
else
    echo -e "${RED}❌ MySQL service failed to start${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 5: Setting MySQL root password...${NC}"
echo "Please enter MySQL root password (will be used for configuration):"
read -s MYSQL_ROOT_PASSWORD
echo ""

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "${YELLOW}⚠️  No password set, will use empty password${NC}"
    MYSQL_CMD="mysql -u root"
else
    echo -e "${YELLOW}Setting root password...${NC}"
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
    echo -e "${GREEN}✅ Root password set successfully${NC}"
fi

echo ""
echo -e "${YELLOW}Step 6: Running security configuration (optional but recommended)...${NC}"
echo "Do you want to run mysql_secure_installation? (y/n)"
read -r RUN_SECURE
if [ "$RUN_SECURE" = "y" ] || [ "$RUN_SECURE" = "Y" ]; then
    mysql_secure_installation
fi

echo ""
echo -e "${YELLOW}Step 7: Creating database and tables...${NC}"

# Find schema.sql file relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../database/schema.sql"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "${RED}❌ Schema file not found: $SCHEMA_FILE${NC}"
    echo "Please ensure database/schema.sql file exists"
    exit 1
fi

echo "Using schema file: $SCHEMA_FILE"
$MYSQL_CMD < "$SCHEMA_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Database and tables created successfully!${NC}"
else
    echo -e "${RED}❌ Database creation failed${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 8: Loading sample data (optional)...${NC}"
SAMPLE_DATA_FILE="${SCRIPT_DIR}/../database/sample_data.sql"
if [ -f "$SAMPLE_DATA_FILE" ]; then
    echo "Do you want to load sample data? (y/n)"
    read -r LOAD_SAMPLE
    if [ "$LOAD_SAMPLE" = "y" ] || [ "$LOAD_SAMPLE" = "Y" ]; then
        $MYSQL_CMD pawpal_db < "$SAMPLE_DATA_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Sample data loaded successfully!${NC}"
        else
            echo -e "${YELLOW}⚠️  Sample data loading failed (may already exist)${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Sample data file not found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 9: Verifying database...${NC}"
$MYSQL_CMD pawpal_db -e "SHOW TABLES;" 2>&1
USER_COUNT=$($MYSQL_CMD pawpal_db -e "SELECT COUNT(*) as count FROM users;" 2>&1 | tail -1)
DOG_COUNT=$($MYSQL_CMD pawpal_db -e "SELECT COUNT(*) as count FROM dogs;" 2>&1 | tail -1)

echo ""
echo -e "${GREEN}✅ Database verification complete${NC}"
echo "  - Users table records: $USER_COUNT"
echo "  - Dogs table records: $DOG_COUNT"

echo ""
echo -e "${YELLOW}Step 10: Generating .env configuration...${NC}"
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "${SCRIPT_DIR}/config/database.env.example" ]; then
        cp "${SCRIPT_DIR}/config/database.env.example" "$ENV_FILE"
    else
        cat > "$ENV_FILE" <<EOF
NODE_ENV=production
PORT=3001
DB_HOST=localhost
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=${MYSQL_ROOT_PASSWORD}
DB_NAME=pawpal_db
DB_POOL_MAX=10
ALLOWED_ORIGINS=http://localhost:3000
SKIP_DB=false
EOF
    fi
    echo -e "${GREEN}✅ .env file created${NC}"
    
    # Update password in .env if it was set
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_ROOT_PASSWORD}/" "$ENV_FILE"
        echo -e "${GREEN}✅ Database password written to .env file${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  .env file already exists, please manually update DB_PASSWORD${NC}"
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo "Suggested DB_PASSWORD value: $MYSQL_ROOT_PASSWORD"
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ MySQL database setup complete!${NC}"
echo "=========================================="
echo ""
echo "Database Information:"
echo "  - Database name: pawpal_db"
echo "  - Username: root"
echo "  - Password: ${MYSQL_ROOT_PASSWORD:-（not set）}"
echo "  - Host: localhost"
echo "  - Port: 3306"
echo ""
echo "Next steps:"
echo "1. Check .env file configuration is correct"
echo "2. Start User Service: cd user-service && npm start"
echo "3. Test connection: curl http://localhost:3001/health"
echo ""

