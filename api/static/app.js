// docker-set control plane - admin SPA.
// Vanilla ES; no framework, no external requests. The API token lives in
// sessionStorage (this tab only) and is attached as a bearer to every /api/*
// call. A 401 anywhere clears it and returns to the connect gate.
"use strict";

(function () {
  const TOKEN_KEY = "docker-set-api-token";
  const SITES_INTERVAL = 5000;
  const JOB_INTERVAL = 1500;

  const $ = (id) => document.getElementById(id);

  // ---- Elements ----
  const tokenForm = $("token-form");
  const tokenInput = $("token-input");
  const connectBtn = $("connect-btn");
  const disconnectBtn = $("disconnect-btn");
  const connStatus = $("conn-status");
  const gate = $("gate");
  const gateError = $("gate-error");
  const dashboard = $("dashboard");

  const sitesBody = $("sites-body");
  const sitesMeta = $("sites-meta");
  const sitesError = $("sites-error");
  const sitesRefresh = $("sites-refresh");

  const createForm = $("create-form");
  const createError = $("create-error");
  const createSubmit = $("create-submit");
  const templateSel = $("c-template");
  const modeSel = $("c-mode");

  const jobState = $("job-state");
  const jobSummary = $("job-summary");
  const jobOutput = $("job-output");

  const logsModal = $("logs-modal");
  const logsTitle = $("logs-title");
  const logsTail = $("logs-tail");
  const logsRefresh = $("logs-refresh");
  const logsOutput = $("logs-output");

  // ---- State ----
  let sitesTimer = null;
  let jobTimer = null;
  let logsSite = null;

  // ---- Token helpers ----
  const getToken = () => sessionStorage.getItem(TOKEN_KEY) || "";
  const setToken = (t) => sessionStorage.setItem(TOKEN_KEY, t);
  const clearToken = () => sessionStorage.removeItem(TOKEN_KEY);

  // Thrown when a request comes back 401: the caller stops, the gate is shown.
  class AuthError extends Error {}

  // api wraps fetch: attaches the bearer, and on 401 clears the token and
  // drops back to the connect gate. Returns the raw Response otherwise.
  async function api(path, opts = {}) {
    const headers = Object.assign({}, opts.headers, {
      Authorization: "Bearer " + getToken(),
    });
    const res = await fetch(path, Object.assign({}, opts, { headers }));
    if (res.status === 401) {
      handleUnauthorized();
      throw new AuthError("unauthorized");
    }
    return res;
  }

  // Reads {"error": "..."} from a JSON body, falling back to a status line.
  async function errorMessage(res) {
    try {
      const data = await res.json();
      if (data && data.error) return data.error;
    } catch (_) {
      /* not JSON */
    }
    return "request failed (HTTP " + res.status + ")";
  }

  function showError(node, msg) {
    node.textContent = msg;
    node.hidden = false;
  }
  function hideError(node) {
    node.hidden = true;
    node.textContent = "";
  }

  // ---- Connection lifecycle ----
  function handleUnauthorized() {
    clearToken();
    stopSitesPolling();
    stopJobPolling();
    showGate("Token rejected (401). Please reconnect with a valid API token.");
  }

  function showGate(message) {
    dashboard.hidden = true;
    gate.hidden = false;
    disconnectBtn.hidden = true;
    connectBtn.hidden = false;
    tokenInput.hidden = false;
    tokenInput.value = "";
    connStatus.textContent = "Disconnected";
    connStatus.className = "pill pill-off";
    if (message) showError(gateError, message);
    else hideError(gateError);
    tokenInput.focus();
  }

  function showDashboard() {
    hideError(gateError);
    gate.hidden = true;
    dashboard.hidden = false;
    connectBtn.hidden = true;
    tokenInput.hidden = true;
    disconnectBtn.hidden = false;
    connStatus.textContent = "Connected";
    connStatus.className = "pill pill-on";
  }

  async function connect(token) {
    setToken(token);
    connStatus.textContent = "Connecting…";
    connStatus.className = "pill pill-off";
    try {
      // /api/meta doubles as the token check and the form data source.
      const res = await api("/api/meta");
      if (!res.ok) {
        clearToken();
        showGate(await errorMessage(res));
        return;
      }
      const meta = await res.json();
      populateMeta(meta);
      showDashboard();
      startSitesPolling();
    } catch (err) {
      if (err instanceof AuthError) return; // gate already shown
      clearToken();
      showGate("Could not reach the API: " + err.message);
    }
  }

  function disconnect() {
    clearToken();
    stopSitesPolling();
    stopJobPolling();
    showGate("");
  }

  // ---- Meta / create form ----
  function populateMeta(meta) {
    const templates = (meta.templates || []).slice().sort();
    templateSel.replaceChildren();
    for (const t of templates) {
      const o = document.createElement("option");
      o.value = t;
      o.textContent = t;
      templateSel.appendChild(o);
    }
    const modes = meta.modes && meta.modes.length ? meta.modes : ["dev", "prod"];
    modeSel.replaceChildren();
    for (const m of modes) {
      const o = document.createElement("option");
      o.value = m;
      o.textContent = m;
      modeSel.appendChild(o);
    }
  }

  // ---- Sites table ----
  function startSitesPolling() {
    refreshSites();
    stopSitesPolling();
    sitesTimer = setInterval(() => {
      // Pause background refreshes while the logs modal is open.
      if (!logsModal.open) refreshSites();
    }, SITES_INTERVAL);
  }
  function stopSitesPolling() {
    if (sitesTimer) clearInterval(sitesTimer);
    sitesTimer = null;
  }

  async function refreshSites() {
    try {
      const res = await api("/api/sites");
      if (!res.ok) {
        showError(sitesError, await errorMessage(res));
        return;
      }
      hideError(sitesError);
      const sites = await res.json();
      renderSites(Array.isArray(sites) ? sites : []);
    } catch (err) {
      if (err instanceof AuthError) return;
      showError(sitesError, "Could not load sites: " + err.message);
    }
  }

  function renderSites(sites) {
    sitesMeta.textContent = sites.length + (sites.length === 1 ? " site" : " sites");
    sitesBody.replaceChildren();

    if (sites.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 6;
      td.className = "muted center";
      td.textContent = "No sites yet. Create one to get started.";
      tr.appendChild(td);
      sitesBody.appendChild(tr);
      return;
    }

    for (const site of sites) {
      const tr = document.createElement("tr");
      tr.appendChild(cell(site.name || "-"));
      tr.appendChild(cell(site.url || "-", "mono"));
      tr.appendChild(cell(site.template || "-"));
      tr.appendChild(cell(site.mode || "-"));
      tr.appendChild(statusCell(site.status));

      const actions = document.createElement("td");
      actions.className = "col-actions";
      const wrap = document.createElement("div");
      wrap.className = "row-actions";
      wrap.appendChild(actionButton("Deploy", () => deploySite(site.name)));
      wrap.appendChild(actionButton("Logs", () => openLogs(site.name)));
      actions.appendChild(wrap);
      tr.appendChild(actions);

      sitesBody.appendChild(tr);
    }
  }

  function cell(text, cls) {
    const td = document.createElement("td");
    if (cls) td.className = cls;
    td.textContent = text;
    return td;
  }

  function statusCell(status) {
    const td = document.createElement("td");
    const span = document.createElement("span");
    span.className = "status";
    const dot = document.createElement("span");
    const known = status === "running" || status === "exited" || status === "stopped";
    dot.className = "dot dot-" + (known ? status : "stopped");
    const label = document.createElement("span");
    label.textContent = status || "unknown";
    span.appendChild(dot);
    span.appendChild(label);
    td.appendChild(span);
    return td;
  }

  function actionButton(label, onClick) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "ghost small";
    b.textContent = label;
    b.addEventListener("click", onClick);
    return b;
  }

  // ---- Deploy ----
  async function deploySite(name) {
    try {
      const res = await api("/api/sites/" + encodeURIComponent(name) + "/deploy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
      if (res.status === 202) {
        const { job_id } = await res.json();
        watchJob(job_id, "Deploy " + name);
        return;
      }
      if (res.status === 409) {
        setJobNotice("A deploy is already in progress for " + name + ".", "pill-running");
        return;
      }
      if (res.status === 429) {
        setJobNotice("The job queue is full. Retry in a moment.", "pill-failed");
        return;
      }
      setJobNotice(await errorMessage(res), "pill-failed");
    } catch (err) {
      if (err instanceof AuthError) return;
      setJobNotice("Deploy failed: " + err.message, "pill-failed");
    }
  }

  // ---- Create ----
  async function submitCreate(event) {
    event.preventDefault();
    hideError(createError);

    const payload = {
      name: $("c-name").value.trim(),
      url: $("c-url").value.trim(),
      template: templateSel.value,
      mode: modeSel.value,
      from_git: $("c-git").value.trim(),
      branch: $("c-branch").value.trim(),
      with_db: $("c-withdb").checked,
      no_ssl: $("c-nossl").checked,
    };
    // Drop empty optionals so the server applies its own defaults.
    if (!payload.from_git) delete payload.from_git;
    if (!payload.branch) delete payload.branch;

    createSubmit.disabled = true;
    try {
      const res = await api("/api/sites", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (res.status === 202) {
        const { job_id } = await res.json();
        watchJob(job_id, "Create " + payload.name);
        createForm.reset();
        return;
      }
      if (res.status === 429) {
        showError(createError, "The job queue is full. Retry in a moment.");
        return;
      }
      showError(createError, await errorMessage(res));
    } catch (err) {
      if (err instanceof AuthError) return;
      showError(createError, "Create failed: " + err.message);
    } finally {
      createSubmit.disabled = false;
    }
  }

  // ---- Job watcher ----
  function setJobState(state) {
    jobState.textContent = state;
    const cls = { running: "pill-running", success: "pill-success", failed: "pill-failed" };
    jobState.className = "pill " + (cls[state] || "pill-idle");
  }

  function setJobNotice(message, pillClass) {
    stopJobPolling();
    jobSummary.textContent = message;
    jobState.textContent = pillClass === "pill-failed" ? "error" : "info";
    jobState.className = "pill " + (pillClass || "pill-idle");
    jobOutput.textContent = "";
  }

  function stopJobPolling() {
    if (jobTimer) clearTimeout(jobTimer);
    jobTimer = null;
  }

  function watchJob(jobId, title) {
    stopJobPolling();
    jobSummary.textContent = title + " — job " + jobId;
    setJobState("running");
    jobOutput.textContent = "";

    const poll = async () => {
      try {
        const res = await api("/api/jobs/" + encodeURIComponent(jobId));
        if (!res.ok) {
          setJobNotice(await errorMessage(res), "pill-failed");
          return;
        }
        const job = await res.json();
        jobOutput.textContent = job.output || "";
        jobOutput.scrollTop = jobOutput.scrollHeight;

        if (job.state === "success" || job.state === "failed") {
          setJobState(job.state);
          const suffix = job.state === "failed" && typeof job.exit_code === "number"
            ? " (exit " + job.exit_code + ")" : "";
          jobSummary.textContent = title + " — " + job.state + suffix;
          refreshSites();
          return;
        }
        setJobState(job.state === "queued" ? "running" : job.state);
        jobTimer = setTimeout(poll, JOB_INTERVAL);
      } catch (err) {
        if (err instanceof AuthError) return;
        setJobNotice("Lost track of the job: " + err.message, "pill-failed");
      }
    };
    poll();
  }

  // ---- Logs modal ----
  async function openLogs(name) {
    logsSite = name;
    logsTitle.textContent = "Logs — " + name;
    logsOutput.textContent = "Loading…";
    if (!logsModal.open) logsModal.showModal();
    await loadLogs();
  }

  async function loadLogs() {
    if (!logsSite) return;
    const tail = encodeURIComponent(logsTail.value || "200");
    try {
      const res = await api(
        "/api/sites/" + encodeURIComponent(logsSite) + "/logs?tail=" + tail
      );
      const text = await res.text();
      logsOutput.textContent = res.ok
        ? (text || "(no output)")
        : (text || "Could not load logs (HTTP " + res.status + ")");
      logsOutput.scrollTop = logsOutput.scrollHeight;
    } catch (err) {
      if (err instanceof AuthError) return;
      logsOutput.textContent = "Could not load logs: " + err.message;
    }
  }

  // ---- Wiring ----
  tokenForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const token = tokenInput.value.trim();
    if (token.length < 32) {
      showError(gateError, "The API token looks too short (min 32 characters).");
      return;
    }
    connect(token);
  });
  disconnectBtn.addEventListener("click", disconnect);
  sitesRefresh.addEventListener("click", refreshSites);
  createForm.addEventListener("submit", submitCreate);
  logsRefresh.addEventListener("click", loadLogs);
  logsTail.addEventListener("change", loadLogs);
  logsModal.addEventListener("close", () => {
    logsSite = null;
  });

  // ---- Boot ----
  if (getToken()) {
    connect(getToken());
  } else {
    showGate("");
  }
})();
