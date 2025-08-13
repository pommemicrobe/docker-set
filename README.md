# 📦 Installation

## Network

1. Start by creating `web` network:

   ```bash
   sudo docker network create web
   ```

## 🧭 Traefik

The **Traefik** container acts as a reverse proxy and handles the routing for the different sites in the project.

1. Start by going to traefik repository:

   ```bash
   cd traefik
   ```

2. Create the `acme.json` file from `acme.json.dist` and set the correct permissions:

   ```bash
   cp acme.json.dist acme.json
   chmod 600 acme.json
   ```

3. Create the `traefik.yaml` file from the template:

   ```bash
   cp traefik.yaml.dist traefik.yaml
   ```

4. Open `traefik.yaml` and **replace the email** with your own to enable SSL certificate generation.

5. Start the Traefik container:

   ```bash
   sudo docker compose up -d
   ```

---

## 🗄️ MySQL

The **MySQL** container is used to manage the shared database for all sites in the project.

> 💡 For better security, it is recommended to create a separate user for each project, with access restricted to a specific database.

1. Navigate to the MySQL folder:

   ```bash
   cd mysql
   ```

2. Create the `.env` file from the example:

   ```bash
   cp .env.dist .env
   ```

3. Edit the `.env` file and fill in your custom values.

4. Start the MySQL container:

   ```bash
   sudo docker compose up -d
   ```

---

# ⚙️ Scripts

This project includes two utility scripts to manage site containers based on predefined templates.

### ▶️ `add-site.sh`

Creates a new site from a predefined template and starts its container.

**Usage:**

```bash
./scripts/add-site.sh my-site my-site.com php-standalone
```

This will:

* Create `my-site`in `sites/my-site`
* Launch the container for the new site.

---

### 🛑 `delete-site.sh`

Stops and removes a site and its associated container.

**Usage:**

```bash
./scripts/delete-site.sh my-site
```

This will:

* Stop the Docker container for the site.
* Remove its folder from the `sites/` directory.

---

### 📦 `add-framework.sh`

Installs a framework or CMS into an existing site's app directory.

**Usage:**

```bash
./scripts/add-framework.sh my-site laravel
```

This will:

* Copy the framework files from `template-frameworks/laravel/` to `sites/my-site/app/`
* Replace placeholder variables (`SITE_NAME`, `SITE_URL`) in framework files
* Display installation instructions and next steps

**Available frameworks:**

```bash
./scripts/add-framework.sh
```

Shows available frameworks and existing sites.

---

# 🧩 Templates

This project provides ready-to-use templates for different technology stacks. Each template comes in two variants:

## 📋 Available Templates

### 🐘 PHP Templates
- **`php-standalone`** - Basic PHP container with direct port exposure (80, 443)
- **`php-traefik`** - PHP container with Traefik integration for SSL and domain routing

### 🟢 NodeJS Templates  
- **`nodejs-standalone`** - NodeJS container with direct port exposure (3000)
- **`nodejs-traefik`** - NodeJS container with Traefik integration for SSL and domain routing

## 🚀 Template Features

### PHP Templates
- **FrankenPHP** base image for modern PHP applications
- **Extensions**: PDO MySQL, GD, Intl, Zip, OPcache, MySQLi
- **Tools**: Composer, Node.js, npm
- Perfect for **WordPress**, **Laravel**, and custom PHP projects

### NodeJS Templates
- **Node.js 22 LTS** for stability and performance
- **PM2** for automatic process restart and monitoring
- **Watch mode** for development (auto-restart on file changes)
- Perfect for **NextJS**, **AdonisJS**, **Express**, and other NodeJS frameworks

## 📖 Usage Examples

```bash
# Create a WordPress site with SSL
./scripts/add-site.sh my-wordpress my-wordpress.local php-traefik

# Create a NextJS project with SSL  
./scripts/add-site.sh my-nextjs my-nextjs.local nodejs-traefik

# Create a development PHP site (direct access)
./scripts/add-site.sh my-php-dev my-php-dev.local php-standalone

# Create a development NodeJS site (direct access)
./scripts/add-site.sh my-node-dev my-node-dev.local nodejs-standalone
```

## 🔧 Template Structure

Each template includes:
- **`Dockerfile`** - Container configuration
- **`compose.yaml`** - Docker Compose setup with environment variables
- **`.env.dist`** - Environment template
- **`app/`** - Directory for your application code

## 📝 Development Workflow

### Method 1: Manual Setup
1. **Create site**: Use `add-site.sh` with desired template
2. **Add code**: Place your application in `sites/<site-name>/app/`
3. **Configure**: Edit `.env` file if needed

### Method 2: Framework Installation
1. **Create site**: Use `add-site.sh` with desired template  
2. **Install framework**: Use `add-framework.sh` to install a pre-configured framework
3. **Configure**: Edit framework-specific settings if needed

**Access your sites:**
- Traefik templates: `https://your-domain.local`
- Standalone templates: `http://localhost:3000` (NodeJS) or `http://localhost:80` (PHP)

## 🚀 Framework Templates

Framework templates provide ready-to-use configurations for popular frameworks and CMS:

- **Laravel**: Complete Laravel setup with optimized configuration
- **WordPress**: Pre-configured WordPress installation 
- **NextJS**: NextJS project template with best practices
- **AdonisJS**: AdonisJS framework setup

**Create frameworks:** Add new frameworks in `template-frameworks/` directory with placeholder variables for customization.
