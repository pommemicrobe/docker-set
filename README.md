# 📦 Installation

## 🧭 Traefik

The **Traefik** container acts as a reverse proxy and handles the routing for the different sites in the project.

1. Start by going to traefik repository

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
./add-site.sh my-site
```

This will:

* Copy the contents of `templates/site-template` to `sites/my-site`.
* Replace any `{{SITE_NAME}}` placeholder inside files (if used).
* Launch the container for the new site.

---

### 🛑 `delete-site.sh`

Stops and removes a site and its associated container.

**Usage:**

```bash
./delete-site.sh my-site
```

This will:

* Stop the Docker container for the site.
* Remove its folder from the `sites/` directory.

---

# 🧩 Templates

*To be completed — Provide configuration templates or example project setups.*
