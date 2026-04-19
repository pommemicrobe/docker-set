# Next.js Framework

Next.js is installed via the official `create-next-app` using Docker. No local Node.js installation required.

## Installation

```bash
./scripts/site-create.sh my-nextjs my-nextjs.com nodejs-traefik --framework nextjs
```

This will:
1. Create the site from nodejs-traefik template
2. Run `npx create-next-app` via Docker
3. Configure PM2 for production mode
4. Build the application

## Post-installation

1. **Customize your app** in `sites/<name>/app/src/`
2. **Rebuild after changes**: `docker exec -it <name> npm run build`
3. **Visit your site**

## Configuration

The installation creates a Next.js app with:

| Feature | Value |
|---------|-------|
| TypeScript | Enabled |
| Tailwind CSS | Enabled |
| ESLint | Enabled |
| App Router | Enabled |
| src/ directory | Enabled |
| Import alias | `@/*` |

## Directory Structure

```
sites/<name>/app/
├── src/
│   └── app/           # App Router pages
│       ├── layout.tsx
│       ├── page.tsx
│       └── globals.css
├── public/            # Static assets
├── ecosystem.config.js # PM2 configuration
├── next.config.ts
├── package.json
├── tailwind.config.ts
└── tsconfig.json
```

## Development Mode

To run in development mode with hot reload:

```bash
# Option 1: Temporary dev server
docker exec -it <name> npm run dev

# Option 2: Update PM2 config
# Edit ecosystem.config.js and change args from 'start' to 'dev'
# Then restart: docker exec -it <name> pm2 restart all
```

## Production Builds

After making changes, rebuild the application:

```bash
docker exec -it <name> npm run build
docker exec -it <name> pm2 restart all
```

## Environment Variables

The Node.js template forwards these from the site's `.env` to the container:

| Variable | Source | Default |
|----------|--------|---------|
| `NODE_ENV` | site `.env` | `production` |
| `DB_HOST` | site `.env` | `mysql` |
| `DB_DATABASE` | site `.env` (auto-filled with `--with-db`) | (empty) |
| `DB_USERNAME` | site `.env` | (empty) |
| `DB_PASSWORD` | site `.env` | (empty) |

Access them in code via `process.env.DB_HOST` etc. Add custom variables in
`ecosystem.config.js`:

```javascript
// ecosystem.config.js
env: {
  NODE_ENV: 'production',
  PORT: 3000,
  // Custom variables here
}
```

## Files

- `install.sh` - Installation script (uses Docker Node.js image)
- `README.md` - This documentation
