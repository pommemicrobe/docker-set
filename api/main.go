// Command api-server is the docker-set control plane API: a thin,
// authenticated executor of the repository's management scripts.
// It never reimplements script logic and never builds shell strings;
// every action is an argv exec of a whitelisted script.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

// Tokens shorter than this are refused at startup: too short to resist
// online guessing on an exposed webhook endpoint.
const minSecretLen = 32

type config struct {
	dir           string // docker-set repository root (inside the container)
	apiToken      string
	webhookSecret string
	listenAddr    string
	maxConcurrent int
	maxQueued     int
}

func loadConfig() (*config, error) {
	cfg := &config{
		dir:           os.Getenv("DOCKER_SET_DIR"),
		apiToken:      os.Getenv("API_TOKEN"),
		webhookSecret: os.Getenv("WEBHOOK_SECRET"),
		listenAddr:    os.Getenv("LISTEN_ADDR"),
		maxConcurrent: 1,
		maxQueued:     100,
	}
	if cfg.listenAddr == "" {
		cfg.listenAddr = ":9000"
	}
	if v := os.Getenv("MAX_CONCURRENT_DEPLOYS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return nil, fmt.Errorf("MAX_CONCURRENT_DEPLOYS must be a positive integer, got %q", v)
		}
		cfg.maxConcurrent = n
	}
	if v := os.Getenv("MAX_QUEUED_JOBS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return nil, fmt.Errorf("MAX_QUEUED_JOBS must be a positive integer, got %q", v)
		}
		cfg.maxQueued = n
	}
	if cfg.dir == "" {
		return nil, errors.New("DOCKER_SET_DIR is required (absolute path to the docker-set repository)")
	}
	if info, err := os.Stat(cfg.dir); err != nil || !info.IsDir() {
		return nil, fmt.Errorf("DOCKER_SET_DIR %q is not a directory", cfg.dir)
	}
	if _, err := os.Stat(filepath.Join(cfg.dir, "scripts", "site-list.sh")); err != nil {
		return nil, fmt.Errorf("DOCKER_SET_DIR %q is not a docker-set checkout (scripts/site-list.sh missing)", cfg.dir)
	}
	if len(cfg.apiToken) < minSecretLen {
		return nil, fmt.Errorf("API_TOKEN is missing or shorter than %d characters (generate one: openssl rand -hex 32)", minSecretLen)
	}
	if len(cfg.webhookSecret) < minSecretLen {
		return nil, fmt.Errorf("WEBHOOK_SECRET is missing or shorter than %d characters (generate one: openssl rand -hex 32)", minSecretLen)
	}
	return cfg, nil
}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := loadConfig()
	if err != nil {
		logger.Error("configuration error", "error", err)
		os.Exit(1)
	}

	// Jobs run under this context: cancelling it kills in-flight scripts.
	jobCtx, cancelJobs := context.WithCancel(context.Background())
	defer cancelJobs()

	srv := newServer(cfg, newJobManager(jobCtx, cfg.dir, cfg.maxConcurrent, cfg.maxQueued, logger), logger)

	httpSrv := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           srv.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		// Bounds the synchronous endpoints (list/logs/health/jobs); deploys are
		// async (202 returned immediately) so they are unaffected.
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	errCh := make(chan error, 1)
	go func() { errCh <- httpSrv.ListenAndServe() }()
	logger.Info("listening",
		"addr", cfg.listenAddr,
		"docker_set_dir", cfg.dir,
		"max_concurrent_deploys", cfg.maxConcurrent,
		"max_queued_jobs", cfg.maxQueued)

	select {
	case err := <-errCh:
		logger.Error("server error", "error", err)
		os.Exit(1)
	case <-ctx.Done():
	}

	// Graceful HTTP shutdown; in-flight scripts are then killed (a deploy
	// interrupted here is re-runnable: the scripts are idempotent enough).
	logger.Info("shutting down (in-flight jobs will be killed)")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		logger.Warn("shutdown incomplete", "error", err)
	}
	cancelJobs()
}
