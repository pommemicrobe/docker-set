#!/bin/sh
# Gin installer — runs inside the site container (Go runtime)
# Env: SITE_NAME, SITE_URL, APP_DIR (provided by framework.sh)
set -eu

cd "$APP_DIR"

# Initialize Go module
go mod init "$SITE_NAME"

# Install Gin
go get github.com/gin-gonic/gin@latest

# Entry point with a health endpoint (matches the Dockerfile healthcheck)
cat > main.go <<'GOEOF'
package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "Hello from Gin"})
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.Run(":8080")
}
GOEOF

# .gitignore
cat > .gitignore <<'EOF'
/tmp
*.exe
*.test
*.out
.env
.DS_Store
EOF

# Tidy dependencies
go mod tidy

echo ""
echo "Next steps:"
echo "  1. Customize your API in main.go"
echo "  2. Check status: docker ps | grep $SITE_NAME"
echo "  3. Visit: https://$SITE_URL"
