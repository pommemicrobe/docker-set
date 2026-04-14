#!/bin/sh
# Next.js installer — runs inside the site container
# Env: SITE_NAME, SITE_URL (provided by framework.sh)
set -eu

cd /app

npx --yes create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias '@/*' --use-npm

# Create PM2 ecosystem file
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'nextjs',
    script: 'npm',
    args: 'start',
    cwd: '/app',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF

npm run build || echo "Build failed — rebuild after customizing: npm run build"

echo ""
echo "Next steps:"
echo "  1. Customize your app in src/"
echo "  2. Rebuild: docker exec -it $SITE_NAME npm run build"
echo "  3. Visit: https://$SITE_URL"
