package main

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed static/*
var embeddedStatic embed.FS

// staticUI is the embedded admin SPA rooted at the static/ directory. Only
// files present in the embed are ever served: reads outside it fail closed.
var staticUI = mustSubFS(embeddedStatic, "static")

func mustSubFS(f fs.FS, dir string) fs.FS {
	sub, err := fs.Sub(f, dir)
	if err != nil {
		// The embed directive guarantees the directory exists at build time.
		panic(err)
	}
	return sub
}

// uiCSP is deliberately tight: the SPA loads no third-party code, so every
// resource is same-origin. base-uri 'none' blocks <base> hijacking; form-action
// 'self' keeps any form POST on this origin.
const uiCSP = "default-src 'self'; base-uri 'none'; form-action 'self'"

// uiContentTypes maps the extensions the SPA actually ships. Anything else
// falls back to octet-stream rather than guessing.
var uiContentTypes = map[string]string{
	".html": "text/html; charset=utf-8",
	".js":   "text/javascript; charset=utf-8",
	".css":  "text/css; charset=utf-8",
	".svg":  "image/svg+xml",
	".ico":  "image/x-icon",
	".json": "application/json",
	".map":  "application/json",
}

// handleIndex serves the SPA entry point (unauthenticated: the assets are not
// secret; the API token is entered in the page and gates every /api/* call).
func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	serveAsset(w, r, "index.html")
}

// handleStaticAsset serves an embedded asset by its path (unauthenticated).
func (s *server) handleStaticAsset(w http.ResponseWriter, r *http.Request) {
	serveAsset(w, r, r.PathValue("path"))
}

func serveAsset(w http.ResponseWriter, r *http.Request, name string) {
	// Normalise and refuse traversal before touching the FS. fs.FS already
	// rejects ".." but this fails closed regardless of the FS implementation.
	name = strings.TrimPrefix(path.Clean("/"+name), "/")
	if name == "" || name == "." || strings.Contains(name, "..") {
		http.NotFound(w, r)
		return
	}

	data, err := fs.ReadFile(staticUI, name)
	if err != nil {
		// Missing vs outside-the-embed are indistinguishable to the client.
		http.NotFound(w, r)
		return
	}

	ct := uiContentTypes[strings.ToLower(path.Ext(name))]
	if ct == "" {
		ct = "application/octet-stream"
	}
	h := w.Header()
	h.Set("Content-Type", ct)
	h.Set("Content-Security-Policy", uiCSP)
	h.Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}
