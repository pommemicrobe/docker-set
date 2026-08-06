package main

import "net/http"

// runtimeVersions mirrors the version constants in lib/site.sh
// (PHP_VERSIONS / NODE_VERSIONS / BUN_VERSIONS / GO_VERSIONS). It is duplicated
// here rather than parsed from the shell so /api/meta stays a pure read; keep
// the two in sync when a runtime version is added or dropped.
var runtimeVersions = map[string][]string{
	"php":    {"8.5", "8.4", "8.3", "8.2"},
	"nodejs": {"24", "22"},
	"bun":    {"1.3", "1"},
	"go":     {"1.26", "1.25"},
}

// handleMeta returns the data the create form needs, derived from the repo
// (templates/ and frameworks/) plus the static mode/runtime maps. Bearer-only.
func (s *server) handleMeta(w http.ResponseWriter, _ *http.Request) {
	templates, err := s.listTemplates()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "cannot list templates: " + err.Error()})
		return
	}
	frameworks, err := s.listFrameworks()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "cannot list frameworks: " + err.Error()})
		return
	}

	// Coerce nil slices to empty ones so the JSON is always an array.
	if templates == nil {
		templates = []string{}
	}
	if frameworks == nil {
		frameworks = []string{}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"templates":  templates,
		"frameworks": frameworks,
		"modes":      []string{"dev", "prod"},
		"runtimes":   runtimeVersions,
	})
}
