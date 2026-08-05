package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"os/exec"
	"regexp"
	"sync"
	"time"
)

const (
	jobOutputLimit = 64 * 1024 // ring buffer: last 64 KB of script output
	jobListLimit   = 100       // GET /api/jobs returns the most recent 100
	jobRetention   = 200       // finished jobs kept in memory beyond the list
)

type jobState string

const (
	jobQueued  jobState = "queued"
	jobRunning jobState = "running"
	jobSuccess jobState = "success"
	jobFailed  jobState = "failed"
)

// job fields are guarded by the manager mutex; output has its own lock
// because the running command writes to it concurrently with readers.
type job struct {
	id       string
	kind     string
	site     string
	argv     []string
	display  []string // argv with credentials redacted, safe to expose/log
	state    jobState
	created  time.Time
	started  time.Time
	finished time.Time
	exitCode int
	errMsg   string
	output   *ringBuffer
}

// jobView is the JSON shape served by /api/jobs.
type jobView struct {
	ID         string     `json:"id"`
	Kind       string     `json:"kind"`
	Site       string     `json:"site"`
	Command    []string   `json:"command"`
	State      string     `json:"state"`
	CreatedAt  time.Time  `json:"created_at"`
	StartedAt  *time.Time `json:"started_at,omitempty"`
	FinishedAt *time.Time `json:"finished_at,omitempty"`
	ExitCode   *int       `json:"exit_code,omitempty"`
	Error      string     `json:"error,omitempty"`
	Output     string     `json:"output,omitempty"`
}

// errQueueFull is returned by enqueue when queued+running jobs reach the cap;
// handlers translate it into a 429 response.
var errQueueFull = errors.New("job queue is full")

type jobManager struct {
	mu        sync.Mutex
	jobs      map[string]*job
	order     []string          // job ids, oldest first
	active    map[string]string // site -> queued/running job id (per-site exclusion)
	sem       chan struct{}     // global MAX_CONCURRENT_DEPLOYS semaphore
	maxQueued int               // MAX_QUEUED_JOBS: cap on queued+running jobs
	ctx       context.Context   // cancelled on shutdown: kills in-flight scripts
	dir       string            // cwd for every script (DOCKER_SET_DIR)
	logger    *slog.Logger
}

func newJobManager(ctx context.Context, dir string, maxConcurrent, maxQueued int, logger *slog.Logger) *jobManager {
	return &jobManager{
		jobs:      make(map[string]*job),
		active:    make(map[string]string),
		sem:       make(chan struct{}, maxConcurrent),
		maxQueued: maxQueued,
		ctx:       ctx,
		dir:       dir,
		logger:    logger,
	}
}

// enqueue registers a job for a site and starts it in the background.
// When the site already has a queued or running job, no job is created and
// the existing job id is returned instead (the caller answers 409). When the
// number of queued+running jobs has reached the cap, errQueueFull is returned
// (the caller answers 429). Per-site exclusion takes precedence over the cap.
func (m *jobManager) enqueue(kind, site string, argv []string) (id, existing string, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if cur, ok := m.active[site]; ok {
		return "", cur, nil
	}
	// active holds exactly the queued+running jobs (one per site), so its
	// length is the current queue depth.
	if m.maxQueued > 0 && len(m.active) >= m.maxQueued {
		return "", "", errQueueFull
	}

	id = newJobID()
	j := &job{
		id:      id,
		kind:    kind,
		site:    site,
		argv:    argv,
		display: redactArgv(argv),
		state:   jobQueued,
		created: time.Now().UTC(),
		output:  &ringBuffer{max: jobOutputLimit},
	}
	m.jobs[id] = j
	m.order = append(m.order, id)
	m.active[site] = id
	m.pruneLocked()

	m.logger.Info("job queued", "job_id", id, "kind", kind, "site", site, "command", j.display)
	go m.run(j)
	return id, "", nil
}

func (m *jobManager) run(j *job) {
	select {
	case m.sem <- struct{}{}:
	case <-m.ctx.Done():
		m.finish(j, -1, "server shut down before the job started")
		return
	}
	defer func() { <-m.sem }()

	m.mu.Lock()
	j.state = jobRunning
	j.started = time.Now().UTC()
	m.mu.Unlock()
	m.logger.Info("job running", "job_id", j.id, "kind", j.kind, "site", j.site)

	cmd := exec.CommandContext(m.ctx, j.argv[0], j.argv[1:]...)
	cmd.Dir = m.dir
	cmd.Stdin = nil // /dev/null: scripts must fail rather than block on a prompt
	cmd.Stdout = j.output
	cmd.Stderr = j.output

	err := cmd.Run()
	code, msg := 0, ""
	if err != nil {
		code = -1
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			code = exitErr.ExitCode()
		}
		msg = err.Error()
	}
	m.finish(j, code, msg)
}

func (m *jobManager) finish(j *job, code int, msg string) {
	m.mu.Lock()
	j.finished = time.Now().UTC()
	j.exitCode = code
	j.errMsg = msg
	if code == 0 {
		j.state = jobSuccess
	} else {
		j.state = jobFailed
	}
	delete(m.active, j.site)
	m.mu.Unlock()
	m.logger.Info("job finished",
		"job_id", j.id, "kind", j.kind, "site", j.site, "state", j.state, "exit_code", code)
}

// pruneLocked drops the oldest finished jobs beyond the retention cap so the
// in-memory map stays bounded. Queued/running jobs are never dropped.
func (m *jobManager) pruneLocked() {
	for len(m.order) > jobRetention {
		oldest := m.jobs[m.order[0]]
		if oldest.state != jobSuccess && oldest.state != jobFailed {
			return
		}
		delete(m.jobs, oldest.id)
		m.order = m.order[1:]
	}
}

// get returns a snapshot of one job, including its buffered output.
func (m *jobManager) get(id string) (jobView, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	j, ok := m.jobs[id]
	if !ok {
		return jobView{}, false
	}
	return m.viewLocked(j, true), true
}

// list returns the most recent jobs, newest first, without output.
func (m *jobManager) list() []jobView {
	m.mu.Lock()
	defer m.mu.Unlock()
	views := make([]jobView, 0, jobListLimit)
	for i := len(m.order) - 1; i >= 0 && len(views) < jobListLimit; i-- {
		views = append(views, m.viewLocked(m.jobs[m.order[i]], false))
	}
	return views
}

func (m *jobManager) viewLocked(j *job, withOutput bool) jobView {
	v := jobView{
		ID:        j.id,
		Kind:      j.kind,
		Site:      j.site,
		Command:   j.display,
		State:     string(j.state),
		CreatedAt: j.created,
		Error:     j.errMsg,
	}
	if !j.started.IsZero() {
		t := j.started
		v.StartedAt = &t
	}
	if !j.finished.IsZero() {
		t := j.finished
		v.FinishedAt = &t
		code := j.exitCode
		v.ExitCode = &code
	}
	if withOutput {
		v.Output = j.output.String()
	}
	return v
}

func newJobID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err) // crypto/rand failure: no safe way to continue
	}
	return hex.EncodeToString(b[:])
}

// userinfoRe matches embedded credentials in URLs (https://TOKEN@host/...),
// used by --from-git for private repositories.
var userinfoRe = regexp.MustCompile(`://[^/@\s]+@`)

// passwordLineRe masks a generated credential printed on a summary line
// ("Password: <value>" / "Mot de passe: <value>"). site-create.sh echoes the
// database password in its summary; the value is also written to the site's
// .env, so masking it in job output loses nothing.
var passwordLineRe = regexp.MustCompile(`(?i)(password|mot de passe):[ \t]*\S.*`)

// redactArgv masks credentials embedded in URL arguments so job listings and
// logs never expose deploy tokens.
func redactArgv(argv []string) []string {
	out := make([]string, len(argv))
	for i, a := range argv {
		out[i] = userinfoRe.ReplaceAllString(a, "://***@")
	}
	return out
}

// redactOutput strips credentials from captured script output. Applied at the
// single read boundary (ringBuffer.String) so it covers every script and every
// surface — the /api/jobs/{id} output field and any log line — regardless of
// what a script prints.
func redactOutput(s string) string {
	s = userinfoRe.ReplaceAllString(s, "://***@")
	s = passwordLineRe.ReplaceAllString(s, "${1}: ***")
	return s
}

// ringBuffer is an io.Writer keeping only the last max bytes written.
type ringBuffer struct {
	mu  sync.Mutex
	max int
	buf []byte
}

func (r *ringBuffer) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.buf = append(r.buf, p...)
	if over := len(r.buf) - r.max; over > 0 {
		r.buf = append([]byte(nil), r.buf[over:]...)
	}
	return len(p), nil
}

// String returns the buffered output with credentials redacted. The raw bytes
// are only ever used to feed the running command; every read goes through here.
func (r *ringBuffer) String() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return redactOutput(string(r.buf))
}
