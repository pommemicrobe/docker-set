package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const maxBodyBytes = 1 << 20 // 1 MB request body cap

// syncExecTimeout bounds the synchronous docker/script execs (site list, logs)
// so a hung CLI cannot pin a request goroutine. Async jobs use their own
// (shutdown-scoped) context and are unaffected.
const syncExecTimeout = 30 * time.Second

// siteNameRe mirrors the validation in lib/common.sh closely enough to
// reject anything unsafe before a name reaches the filesystem or an argv.
var siteNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

const maxSiteNameLen = 64

// siteURLRe matches lib/common.sh validate_url; it also guarantees the
// positional url argument can never be mistaken for a script flag.
var siteURLRe = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]+)?$`)

type server struct {
	cfg    *config
	jobs   *jobManager
	logger *slog.Logger
}

func newServer(cfg *config, jobs *jobManager, logger *slog.Logger) *server {
	return &server{cfg: cfg, jobs: jobs, logger: logger}
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	// Admin SPA: unauthenticated (the assets are not secret) and registered
	// before the API routes. The exact-match "/" and the /static/ subtree do
	// not overlap /health, /api/* or /hooks/*, which stay as-is below.
	mux.HandleFunc("GET /{$}", s.handleIndex)
	mux.HandleFunc("GET /static/{path...}", s.handleStaticAsset)
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.Handle("GET /api/meta", s.requireBearer(s.handleMeta))
	mux.Handle("GET /api/sites", s.requireBearer(s.handleListSites))
	mux.Handle("POST /api/sites", s.requireBearer(s.handleCreateSite))
	mux.Handle("POST /api/sites/{name}/deploy", s.requireBearer(s.handleDeploySite))
	mux.Handle("GET /api/sites/{name}/logs", s.requireBearer(s.handleSiteLogs))
	mux.Handle("GET /api/jobs", s.requireBearer(s.handleListJobs))
	mux.Handle("GET /api/jobs/{id}", s.requireBearer(s.handleGetJob))
	mux.HandleFunc("POST /hooks/github/{site}", s.handleGitHubWebhook)
	return s.withRequestLog(mux)
}

// withRequestLog caps request bodies and logs every request. Only method,
// path, status and duration are logged: never headers, bodies or query values.
func (s *server) withRequestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.logger.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"ms", time.Since(start).Milliseconds())
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (sr *statusRecorder) WriteHeader(code int) {
	sr.status = code
	sr.ResponseWriter.WriteHeader(code)
}

// =============================================================================
// HEALTH
// =============================================================================

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// =============================================================================
// SITES
// =============================================================================

func (s *server) handleListSites(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), syncExecTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", "scripts/site-list.sh", "--json")
	cmd.Dir = s.cfg.dir
	cmd.Stdin = nil
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	// On failure the stderr is logged server-side only; the client gets a
	// generic 502 so script internals never leak over the wire.
	if err := cmd.Run(); err != nil {
		s.logger.Error("site-list.sh failed", "error", err, "stderr", stderr.String())
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "failed to list sites"})
		return
	}

	out := bytes.TrimSpace(stdout.Bytes())
	if !json.Valid(out) {
		// Defensive: strip any non-JSON noise around the array before relaying
		out = extractJSONArray(out)
		if !json.Valid(out) {
			s.logger.Error("site-list.sh returned invalid JSON", "stderr", stderr.String())
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "failed to list sites"})
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(out)
}

// extractJSONArray returns the slice between the first '[' and the last ']'.
func extractJSONArray(b []byte) []byte {
	start := bytes.IndexByte(b, '[')
	end := bytes.LastIndexByte(b, ']')
	if start == -1 || end <= start {
		return nil
	}
	return b[start : end+1]
}

type createSiteRequest struct {
	Name            string `json:"name"`
	URL             string `json:"url"`
	Template        string `json:"template"`
	Mode            string `json:"mode"`
	FromGit         string `json:"from_git"`
	Branch          string `json:"branch"`
	WithDB          bool   `json:"with_db"`
	NoSSL           bool   `json:"no_ssl"`
	NoStart         *bool  `json:"no_start"` // default true: creation is fast, an explicit deploy starts the site
	CPU             string `json:"cpu"`
	Memory          string `json:"memory"`
	Aliases         string `json:"aliases"`
	RedirectAliases bool   `json:"redirect_aliases"`
	Framework       string `json:"framework"`
}

func (s *server) handleCreateSite(w http.ResponseWriter, r *http.Request) {
	var req createSiteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body: " + err.Error()})
		return
	}

	if !validSiteName(req.Name) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid site name (lowercase letters, digits, hyphens; max 64)"})
		return
	}
	if !siteURLRe.MatchString(req.URL) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid url (expected domain.com, sub.domain.com or localhost:3000)"})
		return
	}
	templates, err := s.listTemplates()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "cannot list templates: " + err.Error()})
		return
	}
	if !slices.Contains(templates, req.Template) {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error":     "unknown template",
			"templates": templates,
		})
		return
	}
	if req.Mode != "" && req.Mode != "dev" && req.Mode != "prod" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid mode (dev or prod)"})
		return
	}
	if req.Framework != "" {
		frameworks, err := s.listFrameworks()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "cannot list frameworks: " + err.Error()})
			return
		}
		if !slices.Contains(frameworks, req.Framework) {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"error":      "unknown framework",
				"frameworks": frameworks,
			})
			return
		}
	}
	if req.Branch != "" && !validBranch(req.Branch) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": `invalid branch (allowed: letters, digits, . _ / -; no leading dash, no "..")`})
		return
	}
	if req.FromGit != "" && !validGitURL(req.FromGit) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid from_git (expected https://, git:// or ssh:// URL, or user@host:path)"})
		return
	}
	if req.Aliases != "" && !validAliases(req.Aliases) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid aliases (comma-separated hostnames; no leading dash)"})
		return
	}

	argv := []string{"bash", "scripts/site-create.sh", req.Name, req.URL, req.Template}
	if req.Mode != "" {
		argv = append(argv, "--mode", req.Mode)
	}
	if req.FromGit != "" {
		argv = append(argv, "--from-git", req.FromGit)
	}
	if req.Branch != "" {
		argv = append(argv, "--branch", req.Branch)
	}
	if req.WithDB {
		argv = append(argv, "--with-db")
	}
	if req.NoSSL {
		argv = append(argv, "--no-ssl")
	}
	if req.CPU != "" {
		argv = append(argv, "--cpu", req.CPU)
	}
	if req.Memory != "" {
		argv = append(argv, "--memory", req.Memory)
	}
	if req.Aliases != "" {
		argv = append(argv, "--aliases", req.Aliases)
	}
	if req.RedirectAliases {
		argv = append(argv, "--redirect-aliases")
	}
	if req.Framework != "" {
		argv = append(argv, "--framework", req.Framework)
	}
	if req.NoStart == nil || *req.NoStart {
		argv = append(argv, "--no-start")
	}

	s.enqueueJob(w, "create", req.Name, argv)
}

// listTemplates returns the template directories (everything under
// templates/ except the shared dockerfiles directory).
func (s *server) listTemplates() ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(s.cfg.dir, "templates"))
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.IsDir() && e.Name() != "dockerfiles" {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

// listFrameworks returns the framework directories under frameworks/ (mirrors
// the script's own -d "$FRAMEWORKS_DIR/$name" check); non-directory entries
// such as .gitkeep are skipped.
func (s *server) listFrameworks() ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(s.cfg.dir, "frameworks"))
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

type deployRequest struct {
	NoCache bool `json:"no_cache"`
}

func (s *server) handleDeploySite(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if !validSiteName(name) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid site name"})
		return
	}
	if !s.siteDirExists(name) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "unknown site"})
		return
	}

	var req deployRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body: " + err.Error()})
		return
	}

	argv := []string{"bash", "scripts/site-deploy.sh", name}
	if req.NoCache {
		argv = append(argv, "--no-cache")
	}

	s.enqueueJob(w, "deploy", name, argv)
}

func (s *server) handleSiteLogs(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if !validSiteName(name) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid site name"})
		return
	}
	if !s.siteDirExists(name) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "unknown site"})
		return
	}

	tail := 100
	if v := r.URL.Query().Get("tail"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 5000 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tail must be an integer between 1 and 5000"})
			return
		}
		tail = n
	}

	ctx, cancel := context.WithTimeout(r.Context(), syncExecTimeout)
	defer cancel()
	// The container carries the site name (container_name: ${SITE_NAME})
	cmd := exec.CommandContext(ctx, "docker", "logs", "--tail", strconv.Itoa(tail), name)
	cmd.Dir = s.cfg.dir
	cmd.Stdin = nil
	out, err := cmd.CombinedOutput()

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
	}
	w.Write(out)
}

// =============================================================================
// JOBS
// =============================================================================

// enqueueJob starts a job and writes the 202/409/429 response.
func (s *server) enqueueJob(w http.ResponseWriter, kind, site string, argv []string) {
	id, existing, err := s.jobs.enqueue(kind, site, argv)
	if errors.Is(err, errQueueFull) {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": "job queue is full, retry later",
		})
		return
	}
	if existing != "" {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error":  "a job is already queued or running for this site",
			"job_id": existing,
		})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"job_id": id})
}

func (s *server) handleListJobs(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.jobs.list())
}

func (s *server) handleGetJob(w http.ResponseWriter, r *http.Request) {
	view, ok := s.jobs.get(r.PathValue("id"))
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}
	writeJSON(w, http.StatusOK, view)
}

// =============================================================================
// GITHUB WEBHOOK
// =============================================================================

type pushPayload struct {
	Ref        string `json:"ref"`
	Repository struct {
		DefaultBranch string `json:"default_branch"`
	} `json:"repository"`
}

func (s *server) handleGitHubWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cannot read body"})
		return
	}

	// Signature first: nothing (including site existence) is disclosed to
	// callers that do not hold the webhook secret.
	if !verifyGitHubSignature(s.cfg.webhookSecret, body, r.Header.Get("X-Hub-Signature-256")) {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid signature"})
		return
	}

	site := r.PathValue("site")
	if !validSiteName(site) || !s.siteDirExists(site) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "unknown site"})
		return
	}

	switch event := r.Header.Get("X-GitHub-Event"); event {
	case "ping":
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	case "push":
	default:
		w.WriteHeader(http.StatusNoContent)
		return
	}

	var payload pushPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON payload"})
		return
	}

	// Deploy only pushes to the tracked branch: the manifest source_branch
	// when set, otherwise the repository default branch from the payload.
	pushed, isBranch := strings.CutPrefix(payload.Ref, "refs/heads/")
	target := s.manifestSourceBranch(site)
	if target == "" {
		target = payload.Repository.DefaultBranch
	}
	if !isBranch || target == "" || pushed != target {
		writeJSON(w, http.StatusOK, map[string]string{"skipped": "branch"})
		return
	}

	s.enqueueJob(w, "webhook-deploy", site, []string{"bash", "scripts/site-deploy.sh", site})
}

// manifestSourceBranch reads the source_branch scalar from the site manifest
// (sites/<site>/site.yaml); empty when absent.
func (s *server) manifestSourceBranch(site string) string {
	f, err := os.Open(filepath.Join(s.cfg.dir, "sites", site, "site.yaml"))
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if v, ok := strings.CutPrefix(sc.Text(), "source_branch:"); ok {
			return strings.Trim(strings.TrimSpace(v), `"`)
		}
	}
	return ""
}

// =============================================================================
// HELPERS
// =============================================================================

func validSiteName(name string) bool {
	return len(name) <= maxSiteNameLen && siteNameRe.MatchString(name)
}

// branchRe constrains a git branch/ref to a safe charset before it reaches an
// argv (leading dash and ".." are rejected separately below).
var branchRe = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,255}$`)

func validBranch(b string) bool {
	return branchRe.MatchString(b) && !strings.HasPrefix(b, "-") && !strings.Contains(b, "..")
}

// scpLikeRe matches scp-style git remotes (user@host:path); mirrors
// validate_git_url in scripts/site-create.sh.
var scpLikeRe = regexp.MustCompile(`^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:.+$`)

func validGitURL(u string) bool {
	if strings.HasPrefix(u, "-") { // never let a URL be read as a flag
		return false
	}
	// git:// is intentionally excluded: it is unauthenticated cleartext
	if strings.HasPrefix(u, "https://") || strings.HasPrefix(u, "ssh://") {
		return true
	}
	return scpLikeRe.MatchString(u)
}

// validAliases checks each comma-separated alias against the host regex; empty
// entries are tolerated (the script filters them) and a leading dash is barred.
func validAliases(csv string) bool {
	for _, a := range strings.Split(csv, ",") {
		a = strings.TrimSpace(a)
		if a == "" {
			continue
		}
		if strings.HasPrefix(a, "-") || !siteURLRe.MatchString(a) {
			return false
		}
	}
	return true
}

func (s *server) siteDirExists(name string) bool {
	info, err := os.Stat(filepath.Join(s.cfg.dir, "sites", name))
	return err == nil && info.IsDir()
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Warn("response encoding failed", "error", err)
	}
}
