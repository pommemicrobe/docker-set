#!/bin/sh
# Elysia installer — runs inside the site container (Bun runtime)
# Env: SITE_NAME, SITE_URL, APP_DIR (provided by framework.sh)
set -eu

cd "$APP_DIR"

# Initialize package.json
cat > package.json <<EOF
{
  "name": "$SITE_NAME",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "bun run src/index.ts",
    "dev": "bun --hot run src/index.ts"
  },
  "dependencies": {
    "elysia": "^1.4.0"
  },
  "devDependencies": {
    "bun-types": "^1.3.0",
    "typescript": "^5.9.0"
  }
}
EOF

# TypeScript config
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "lib": ["ESNext"],
    "target": "ESNext",
    "module": "ESNext",
    "moduleDetection": "force",
    "jsx": "react-jsx",
    "allowJs": true,
    "moduleResolution": "Bundler",
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "noEmit": true,
    "strict": true,
    "skipLibCheck": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noPropertyAccessFromIndexSignature": false,
    "types": ["bun-types"]
  }
}
EOF

# Entry point with a health endpoint (matches the Dockerfile healthcheck)
mkdir -p src
cat > src/index.ts <<'EOF'
import { Elysia } from 'elysia'

const app = new Elysia()
  .get('/', () => ({ message: 'Hello from Elysia + Bun' }))
  .get('/health', () => ({ status: 'ok' }))
  .listen({ hostname: '0.0.0.0', port: 3000 })

console.log(`Elysia running at http://${app.server?.hostname}:${app.server?.port}`)
EOF

# .gitignore
cat > .gitignore <<'EOF'
node_modules
bun.lockb
bun.lock
.env
.DS_Store
EOF

# Install dependencies
bun install

echo ""
echo "Next steps:"
echo "  1. Customize your API in src/index.ts"
echo "  2. Check status: docker ps | grep $SITE_NAME"
echo "  3. Visit: https://$SITE_URL"
