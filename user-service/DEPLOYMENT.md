# User Service Deployment Guide - Cloud Compute (VM)

This guide explains how to deploy the User Service on Google Cloud Compute Engine (VM).

## Prerequisites

- Google Cloud Platform account
- gcloud CLI installed and configured
- MySQL database (will be set up on the same VM, fully under your control)

## Step 1: Create VM Instance


## Step 2: SSH into VM


## Step 3: Install Dependencies on VM

```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install MySQL client (if needed)
sudo apt-get install -y default-mysql-server default-mysql-client

# Install PM2 for process management
sudo npm install -g pm2

# Install Git
sudo apt-get install -y git
```

## Step 4: Clone and Setup Application

```bash
# Create application directory
sudo mkdir -p /opt/pawpal
sudo chown $USER:$USER /opt/pawpal
cd /opt/pawpal

# Clone repository (or upload files)
git clone <your-repo-url> .
cd user-service

# Install dependencies
npm install --production
```

## Step 5: Configure Environment

```bash
# Copy environment template
cp config/database.env.example .env

# Edit environment file
nano .env
```

Set the following variables:

```env
NODE_ENV=production
PORT=3001

DB_HOST=localhost
DB_PORT=3306
DB_USERNAME=user_service
DB_PASSWORD=huakaifugui
DB_NAME=pawpal_user_db
DB_POOL_MAX=10

ALLOWED_ORIGINS=http://localhost:3000
SKIP_DB=false

```

## Step 6: Setup Database (Fully Under Your Control)

If MySQL is on the same VM, you have two options:

### Option A: Automated Setup (Recommended)

Use the automated setup script that handles everything:

```bash
cd /opt/pawpal/user-service
chmod +x setup-mysql.sh
sudo ./setup-mysql.sh
```

The script will automatically:
- Install MySQL Server
- Start and enable MySQL service
- Prompt you to set root password (you decide the password)
- Optionally run security configuration
- Create database and tables (using the provided schema.sql)
- Optionally load sample data
- Generate .env file with your password configured

**This gives you complete control over the MySQL setup while automating the process.**

### Option B: Manual Setup

If you prefer to control each step manually:

```bash
# Install MySQL Server
sudo apt-get install -y mysql-server

# Start MySQL service and enable it to start on boot
sudo systemctl enable mysql
sudo systemctl start mysql

# Verify MySQL is running
sudo systemctl status mysql

# Secure MySQL installation (optional but recommended)
sudo mysql_secure_installation
# Follow the prompts to:
# - Set root password (you decide)
# - Remove anonymous users
# - Disallow root login remotely (optional, since we're on same VM)
# - Remove test database
# - Reload privilege tables

# Create database user (if using custom user)
mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS pawpal_user_db;
CREATE USER IF NOT EXISTS 'user_service'@'localhost' IDENTIFIED BY 'huakaifugui';
GRANT ALL PRIVILEGES ON pawpal_user_db.* TO 'user_service'@'localhost';
FLUSH PRIVILEGES;
EOF

# Create database and tables (adapting schema.sql for your database name)
# Option 1: Use sed to replace database name in schema.sql
sed 's/pawpal_db/pawpal_user_db/g' ../database/schema.sql | mysql -u root -p

# Option 2: Or manually edit schema.sql to use pawpal_user_db, then:
# mysql -u root -p < ../database/schema.sql

# Load sample data (optional, update database name in sample_data.sql first)
sed 's/USE pawpal_db/USE pawpal_user_db/g' ../database/sample_data.sql | mysql -u root -p

# Verify database was created
mysql -u root -p pawpal_user_db -e "SHOW TABLES;"
mysql -u root -p pawpal_user_db -e "SELECT COUNT(*) FROM users;"
mysql -u root -p pawpal_user_db -e "SELECT COUNT(*) FROM dogs;"
```

**Important Notes:**
- You have full control over the MySQL root password
- The `schema.sql` file is provided by others, but you execute it
- All database configuration is under your control
- Update `.env` file with the password you set

If MySQL is on a separate VM, ensure:
- MySQL allows remote connections
- Firewall rules allow connection from user-service VM
- Database user has proper permissions

## Step 7: Create Systemd Service

Create service file:

```bash
sudo nano /etc/systemd/system/user-service.service
```

Add the following content:

```ini
[Unit]
Description=PawPal User Service
After=network.target mysql.service

[Service]
Type=simple
User=your-username
WorkingDirectory=/opt/pawpal/user-service
Environment=NODE_ENV=production
EnvironmentFile=/opt/pawpal/user-service/.env
ExecStart=/usr/bin/node src/app.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=user-service

[Install]
WantedBy=multi-user.target
```

Replace `your-username` with your actual username.

## Step 8: Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable user-service

# Start service
sudo systemctl start user-service

# Check status
sudo systemctl status user-service

# View logs
sudo journalctl -u user-service -f
```

## Step 9: Setup Nginx Reverse Proxy (Optional)

If you want to use port 80/443:

```bash
# Install Nginx
sudo apt-get install -y nginx

# Create Nginx configuration
sudo nano /etc/nginx/sites-available/user-service
```

Add configuration:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable and start Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/user-service /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Step 10: Verify Deployment

```bash
# Test health endpoint
curl http://localhost:3001/health

# Test from external IP
curl http://<VM_EXTERNAL_IP>:3001/health
```

## Monitoring and Maintenance

### View Logs

```bash
# Systemd logs
sudo journalctl -u user-service -f

# Application logs (if using PM2)
pm2 logs user-service
```

### Restart Service

```bash
sudo systemctl restart user-service
```

### Update Application

```bash
cd /opt/pawpal/user-service
git pull
npm install --production
sudo systemctl restart user-service
```

## Troubleshooting

### Service won't start

1. Check logs: `sudo journalctl -u user-service -n 50`
2. Verify environment variables: `sudo systemctl show user-service`
3. Test database connection manually
4. Check port availability: `sudo netstat -tulpn | grep 3001`

### Database connection issues

1. Verify MySQL is running: `sudo systemctl status mysql`
2. Test connection with your configured user:
   ```bash
   mysql -u user_service -p pawpal_user_db
   # Password: huakaifugui
   ```
3. Or test with root: `mysql -h <host> -u root -p`
4. Check firewall rules
5. Verify credentials in .env file match your configuration:
   - DB_USERNAME=user_service
   - DB_PASSWORD=huakaifugui
   - DB_NAME=pawpal_user_db

### Port already in use

```bash
# Find process using port
sudo lsof -i :3001

# Kill process if needed
sudo kill -9 <PID>
```

## Security Considerations

1. **Firewall**: Only expose necessary ports
2. **Database**: Use strong passwords, limit access
3. **Environment Variables**: Keep .env file secure (chmod 600)
4. **HTTPS**: Use SSL/TLS in production (consider Cloud Load Balancer)
5. **Updates**: Keep system and dependencies updated

## Backup

```bash
# Backup database (using your configured database name)
mysqldump -u user_service -p pawpal_user_db > backup_$(date +%Y%m%d).sql

# Or using root user
mysqldump -u root -p pawpal_user_db > backup_$(date +%Y%m%d).sql

# Backup application
tar -czf user-service-backup-$(date +%Y%m%d).tar.gz /opt/pawpal/user-service
```

