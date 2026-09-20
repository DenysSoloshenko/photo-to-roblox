import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Trans, useTranslation } from "react-i18next";
import { analyzePhoto, compileScene, downloadReadyRoblox, fetchJson, getSession, listNotifications, loginAccount, logoutAccount, registerAccount, requestPasswordReset, resetPassword, startOAuth } from "./api";
import type { QualityMode } from "./api";
import i18n from "./i18n";
import { AdminQueue, CreateOrderPage, OrdersPage } from "./OrderWorkflow";
import CaseStudyPage from "./CaseStudyPage";
import SceneViewer from "./ScenePreview";
import type { AccountUser, Metrics, OAuthProviderStatus, RobloxFile, SceneIR, SceneResponse } from "./types";

type Status = "idle" | "analyzing" | "building" | "ready";
type Language = "en" | "fr";

function formatTime(value: number | undefined, language: Language) {
  if (value == null) return "—";
  const locale = language === "fr" ? "fr-FR" : "en-US";
  return value >= 1_000
    ? `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value / 1_000)} s`
    : `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value)} ms`;
}

function formatCost(value: number | null | undefined, language: Language) {
  if (value == null) return "—";
  return new Intl.NumberFormat(language === "fr" ? "fr-FR" : "en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 4,
    maximumFractionDigits: 4,
  }).format(value);
}

function errorText(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback;
}

type PortalView = "create" | "orders" | "admin" | "lab" | "case";

export default function App() {
  const { t } = useTranslation();
  const initialResetToken = new URLSearchParams(window.location.search).get("reset_token") || "";
  const [view, setView] = useState<PortalView>(() => new URLSearchParams(window.location.search).has("order") ? "orders" : new URLSearchParams(window.location.search).get("case") === "springer-park" ? "case" : "create");
  useEffect(() => {
    const url = new URL(window.location.href);
    if (view !== "case" && url.searchParams.has("case")) {
      url.searchParams.delete("case");
      window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
    }
  }, [view]);
  const [user, setUser] = useState<AccountUser | null>(null);
  const [csrfToken, setCsrfToken] = useState("");
  const [oauthProviders, setOauthProviders] = useState<OAuthProviderStatus[]>([]);
  const [authOpen, setAuthOpen] = useState(Boolean(initialResetToken));
  const [sessionLoading, setSessionLoading] = useState(true);
  const [sessionError, setSessionError] = useState<string | null>(null);
  const [unreadCount, setUnreadCount] = useState(0);
  const activeLanguage: Language = i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en";

  const refreshSession = useCallback(async () => {
    try {
      const session = await getSession();
      setUser(session.user);
      setCsrfToken(session.csrf_token);
      setOauthProviders(session.oauth_providers);
      setSessionError(null);
    } catch (reason) {
      setSessionError(errorText(reason, "Could not load your session."));
    } finally {
      setSessionLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshSession();
    const url = new URL(window.location.href);
    if (url.searchParams.has("oauth") || url.searchParams.has("oauth_error")) {
      url.searchParams.delete("oauth");
      url.searchParams.delete("oauth_error");
      window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
    }
  }, [refreshSession]);

  useEffect(() => {
    if (!sessionLoading && (view === "admin" || view === "lab") && !user?.admin) setView("create");
  }, [sessionLoading, user, view]);

  useEffect(() => {
    if (!user) {
      setUnreadCount(0);
      return;
    }
    void listNotifications()
      .then(({ notifications }) => setUnreadCount(notifications.filter((notification) => !notification.read).length))
      .catch(() => setUnreadCount(0));
  }, [user, view]);

  const changeLanguage = (language: Language) => void i18n.changeLanguage(language);
  const logOut = async () => {
    try {
      await logoutAccount(csrfToken);
      setUser(null);
      setCsrfToken("");
      setView("create");
      await refreshSession();
    } catch (reason) { setSessionError(errorText(reason, t("errors.unknown"))); }
  };

  const closeAuth = () => {
    setAuthOpen(false);
    const url = new URL(window.location.href);
    if (url.searchParams.has("reset_token")) {
      url.searchParams.delete("reset_token");
      window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
    }
  };

  if (view === "lab" && user?.admin) return <GeneratorLab csrfToken={csrfToken} onExit={() => setView("create")} />;

  return (
    <div className="portal-shell">
      <header className="topbar portal-topbar">
        <button type="button" className="brand brand-button" onClick={() => setView("create")} aria-label={t("brand.aria")}>
          <span className="brand-mark">S</span>
          <span><strong>SceneFoundry</strong><small>{t("brand.tagline")}</small></span>
        </button>
        <nav className="portal-nav" aria-label={t("portal.navLabel")}>
          <button className={view === "create" ? "active" : ""} onClick={() => setView("create")}>{t("portal.create")}</button>
          <a className={view === "case" ? "active" : ""} href="/?case=springer-park">{activeLanguage === "fr" ? "Étude de cas" : "Case study"}</a>
          {user && <button className={view === "orders" ? "active" : ""} onClick={() => setView("orders")}>{t("portal.orders")}</button>}
          {user?.admin && <button className={view === "admin" ? "active" : ""} onClick={() => setView("admin")}>{t("portal.queue")}</button>}
          {user?.admin && <button onClick={() => setView("lab")}>{t("portal.lab")}</button>}
        </nav>
        <div className="topbar-actions">
          <nav className="language-switcher" aria-label={t("language.label")}>
            <button type="button" className={activeLanguage === "en" ? "active" : ""} onClick={() => changeLanguage("en")}>EN</button>
            <button type="button" className={activeLanguage === "fr" ? "active" : ""} onClick={() => changeLanguage("fr")}>FR</button>
          </nav>
          {user && <button className="notification-bell" onClick={() => setView("orders")} aria-label={t("portal.notifications")}>♢{unreadCount > 0 && <span>{unreadCount}</span>}</button>}
          {!sessionLoading && (user ? (
            <div className="account-menu"><span>{user.display_name}</span><button onClick={logOut}>{t("auth.logout")}</button></div>
          ) : <button className="header-signin" onClick={() => setAuthOpen(true)}>{t("auth.signIn")}</button>)}
        </div>
      </header>

      {sessionError && <div className="error-box" role="alert">{sessionError} <button onClick={() => void refreshSession()}>{t("orders.refresh")}</button></div>}
      {view === "create" && <CreateOrderPage user={user} csrfToken={csrfToken} onAuth={() => setAuthOpen(true)} onCreated={() => setView("orders")} />}
      {view === "case" && <CaseStudyPage />}
      {view === "orders" && user && <OrdersPage key={user.id} csrfToken={csrfToken} />}
      {view === "admin" && user?.admin && <AdminQueue key={user.id} csrfToken={csrfToken} />}

      {authOpen && <AuthDialog csrfToken={csrfToken} providers={oauthProviders} resetToken={initialResetToken} onClose={closeAuth} onAuthenticated={(response) => {
        setUser(response.user);
        setCsrfToken(response.csrf_token);
        closeAuth();
      }} />}
    </div>
  );
}

type AuthMode = "login" | "register" | "forgot" | "reset";

function AuthDialog({ csrfToken, providers, resetToken, onClose, onAuthenticated }: { csrfToken: string; providers: OAuthProviderStatus[]; resetToken: string; onClose: () => void; onAuthenticated: (response: { user: AccountUser; csrf_token: string }) => void }) {
  const { t } = useTranslation();
  const [mode, setMode] = useState<AuthMode>(resetToken ? "reset" : "login");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const google = providers.find((provider) => provider.name === "google");

  const changeMode = (nextMode: AuthMode) => {
    setMode(nextMode);
    setError(null);
    setNotice(null);
    setPassword("");
    setPasswordConfirmation("");
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault(); setBusy(true); setError(null);
    try {
      if (mode === "forgot") {
        await requestPasswordReset(csrfToken, email);
        setNotice(t("auth.resetSent"));
        return;
      }
      if (mode === "reset") {
        if (password !== passwordConfirmation) throw new Error(t("auth.passwordMismatch"));
        onAuthenticated(await resetPassword(csrfToken, resetToken, password, passwordConfirmation));
        return;
      }
      const response = mode === "register"
        ? await registerAccount(csrfToken, { displayName, email, password })
        : await loginAccount(csrfToken, email, password);
      onAuthenticated(response);
    } catch (reason) { setError(errorText(reason, t("errors.unknown"))); } finally { setBusy(false); }
  };

  const beginGoogle = async () => {
    setBusy(true);
    setError(null);
    try { await startOAuth(csrfToken, "google"); }
    catch (reason) { setError(errorText(reason, t("errors.unknown"))); setBusy(false); }
  };

  const title = mode === "register" ? t("auth.createTitle") : mode === "forgot" ? t("auth.forgotTitle") : mode === "reset" ? t("auth.resetTitle") : t("auth.loginTitle");
  const body = mode === "forgot" ? t("auth.forgotBody") : mode === "reset" ? t("auth.resetBody") : t("auth.accountBody");
  const showAccountChoices = mode === "login" || mode === "register";

  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="auth-dialog" role="dialog" aria-modal="true" aria-labelledby="auth-title"><button className="modal-close" onClick={onClose} aria-label={t("auth.close")}>×</button><span className="eyebrow">SceneFoundry account</span><h2 id="auth-title">{title}</h2><p>{body}</p>
    {showAccountChoices && <><div className="social-grid"><button type="button" className="google-button" disabled={!google?.configured || busy} onClick={() => void beginGoogle()}><span className="google-label"><b>G</b>{t("auth.continueWith", { provider: "Google" })}</span>{!google?.configured && <small>{t("auth.oauthSetupRequired")}</small>}</button></div><p className="google-preferred">{t("auth.googlePreferred")}</p><div className="or-line"><span>{t("auth.or")}</span></div></>}
    <form onSubmit={submit}>
      {mode === "register" && <label className="form-field"><span>{t("auth.name")}</span><input required autoComplete="name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} /></label>}
      {mode !== "reset" && <label className="form-field"><span>{t("auth.email")}</span><input type="email" required autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} /></label>}
      {mode !== "forgot" && <label className="form-field"><span className="password-label"><span>{mode === "reset" ? t("auth.newPassword") : t("auth.password")}</span>{mode === "login" && <button type="button" onClick={() => changeMode("forgot")}>{t("auth.forgot")}</button>}</span><input type="password" minLength={10} required autoComplete={mode === "reset" ? "new-password" : mode === "login" ? "current-password" : "new-password"} value={password} onChange={(event) => setPassword(event.target.value)} /><small>{t("auth.passwordHint")}</small></label>}
      {mode === "reset" && <label className="form-field"><span>{t("auth.confirmPassword")}</span><input type="password" minLength={10} required autoComplete="new-password" value={passwordConfirmation} onChange={(event) => setPasswordConfirmation(event.target.value)} /></label>}
      {notice && <p className="success-box" role="status">{notice}</p>}
      {error && <pre className="error-box" role="alert">{error}</pre>}
      <button className="primary-button" disabled={busy || Boolean(notice)}>{busy ? t("auth.working") : mode === "register" ? t("auth.create") : mode === "forgot" ? t("auth.sendReset") : mode === "reset" ? t("auth.resetPassword") : t("auth.signIn")}</button>
    </form>
    {showAccountChoices ? <p className="auth-switch">{mode === "register" ? t("auth.haveAccount") : t("auth.newAccount")} <button type="button" onClick={() => changeMode(mode === "register" ? "login" : "register")}>{mode === "register" ? t("auth.signIn") : t("auth.create")}</button></p> : <p className="auth-switch"><button type="button" onClick={() => changeMode("login")}>{t("auth.backToSignIn")}</button></p>}
    {showAccountChoices && <small className="terms-copy">{t("auth.terms")}</small>}
  </section></div>;
}

function GeneratorLab({ csrfToken, onExit }: { csrfToken: string; onExit: () => void }) {
  const { t } = useTranslation();
  const [photo, setPhoto] = useState<File | null>(null);
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [hint, setHint] = useState("");
  const [qualityMode, setQualityMode] = useState<QualityMode>("terra");
  const [sceneIr, setSceneIr] = useState<SceneIR | null>(null);
  const [robloxFile, setRobloxFile] = useState<RobloxFile | null>(null);
  const [editor, setEditor] = useState("");
  const [metrics, setMetrics] = useState<Metrics>({});
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const [resetToken, setResetToken] = useState(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const activeRequest = useRef<AbortController | null>(null);
  useEffect(() => () => activeRequest.current?.abort(), []);
  const [visionStatus, setVisionStatus] = useState<{ configured: boolean; model: string; reasoningEffort?: string; refinementEnabled: boolean; astraEnabled: boolean; examplesEnabled: boolean } | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetchJson<{ vision_configured: boolean; vision_model: string; vision_reasoning_effort?: string; vision_refinement_enabled: boolean; astra_quality_enabled: boolean; development_examples_enabled: boolean }>("/api/v1/status", { signal: controller.signal })
      .then((body) => setVisionStatus({
        configured: Boolean(body.vision_configured),
        model: String(body.vision_model),
        reasoningEffort: body.vision_reasoning_effort ? String(body.vision_reasoning_effort) : undefined,
        refinementEnabled: Boolean(body.vision_refinement_enabled),
        astraEnabled: Boolean(body.astra_quality_enabled),
        examplesEnabled: Boolean(body.development_examples_enabled),
      }))
      .catch((reason) => { if (!controller.signal.aborted) { setVisionStatus(null); setError(errorText(reason, "Could not load AI Lab status.")); } });
    return () => controller.abort();
  }, []);

  useEffect(() => () => {
    if (photoUrl) URL.revokeObjectURL(photoUrl);
  }, [photoUrl]);

  const receiveScene = (response: SceneResponse) => {
    setSceneIr(response.scene_ir);
    setRobloxFile(response.roblox_file || null);
    setEditor(JSON.stringify(response.scene_spec, null, 2));
    setMetrics(response.metrics);
    setSelectedId(null);
    setStatus("ready");
  };

  const choosePhoto = (file: File | null) => {
    setPhoto(file);
    setRobloxFile(null);
    setError(null);
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    setPhotoUrl(file ? URL.createObjectURL(file) : null);
  };

  const runSceneRequest = async (nextStatus: Status, operation: (signal: AbortSignal) => Promise<SceneResponse>) => {
    if (activeRequest.current) return;
    const controller = new AbortController();
    activeRequest.current = controller;
    setStatus(nextStatus);
    setRobloxFile(null);
    setError(null);
    try {
      const response = await operation(controller.signal);
      if (!controller.signal.aborted) receiveScene(response);
    } catch (reason) {
      if (!controller.signal.aborted) { setError(errorText(reason, t("errors.unknown"))); setStatus("idle"); }
    } finally {
      if (activeRequest.current === controller) activeRequest.current = null;
    }
  };

  const analyze = async () => {
    if (!photo) return setError(t("errors.choosePhoto"));
    await runSceneRequest("analyzing", (signal) => analyzePhoto(photo, hint, qualityMode, csrfToken, { signal }));
  };

  const rebuild = () => runSceneRequest("building", (signal) => compileScene(JSON.parse(editor) as Record<string, unknown>, csrfToken, { signal }));

  const download = async () => {
    setError(null);
    try {
      if (!robloxFile) throw new Error(t("errors.rebuildBeforeDownload"));
      await downloadReadyRoblox(robloxFile);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    }
  };

  const loadDevelopmentScene = () => runSceneRequest("building", (signal) => fetchJson<SceneResponse>("/api/v1/scenes/examples/garden?include_map=true", { signal }));

  const changeLanguage = (language: Language) => {
    void i18n.changeLanguage(language);
  };

  const onSelect = useCallback((sourceId: string | null) => setSelectedId(sourceId), []);
  const busy = status === "analyzing" || status === "building";
  const selectedParts = useMemo(() => sceneIr?.parts.filter((part) => part.source_id === selectedId).length || 0, [sceneIr, selectedId]);
  const activeLanguage: Language = i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en";
  const activeModelLabel = qualityMode === "astra_max"
    ? `gpt-6-astra · max · ${t("api.refinement")}`
    : `${visionStatus?.model || "gpt-5.6-terra"}${visionStatus?.reasoningEffort ? ` · ${visionStatus.reasoningEffort}` : ""}${visionStatus?.refinementEnabled ? ` · ${t("api.refinement")}` : ""}`;

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label={t("brand.aria")}>
          <span className="brand-mark">S</span>
          <span><strong>SceneFoundry</strong><small>{t("brand.tagline")}</small></span>
        </a>
        <div className="topbar-actions">
          <button className="header-signin" onClick={onExit}>{t("portal.back")}</button>
          <nav className="language-switcher" aria-label={t("language.label")}>
            <button type="button" className={activeLanguage === "en" ? "active" : ""} aria-pressed={activeLanguage === "en"} title={t("language.english")} onClick={() => changeLanguage("en")}>EN</button>
            <button type="button" className={activeLanguage === "fr" ? "active" : ""} aria-pressed={activeLanguage === "fr"} title={t("language.french")} onClick={() => changeLanguage("fr")}>FR</button>
          </nav>
          <div className={`api-badge ${visionStatus?.configured ? "online" : "offline"}`}>
            <span /> {visionStatus?.configured
              ? t("api.connected", { model: activeModelLabel })
              : t("api.notConfigured")}
          </div>
        </div>
      </header>

      <main className="workspace">
        <aside className="panel upload-panel">
          <div className="eyebrow">{t("upload.step")}</div>
          <h1>{t("upload.title")}</h1>
          <p className="lede">{t("upload.lede")}</p>
          <label className={`dropzone ${photoUrl ? "has-photo" : ""}`}>
            {photoUrl ? <img src={photoUrl} alt={t("upload.selectedAlt")} /> : <span className="drop-icon">↥</span>}
            <input type="file" disabled={busy} accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePhoto(event.target.files?.[0] || null)} />
            <span className="drop-copy"><strong>{photo ? photo.name : t("upload.choose")}</strong><small>{t("upload.formats")}</small></span>
          </label>
          <label className="field-label" htmlFor="hint">{t("upload.hintLabel")} <span>{t("upload.optional")}</span></label>
          <textarea disabled={busy} id="hint" value={hint} onChange={(event) => setHint(event.target.value)} placeholder={t("upload.hintPlaceholder")} rows={4} />
          <label className="field-label quality-label" htmlFor="quality-mode">{t("quality.label")}</label>
          <select id="quality-mode" className="quality-select" value={qualityMode} onChange={(event) => setQualityMode(event.target.value as QualityMode)} disabled={busy}>
            <option value="terra">{t("quality.terraOption")}</option>
            <option value="astra_max" disabled={!visionStatus?.astraEnabled}>{t("quality.astraOption")}</option>
          </select>
          <p className={`quality-note ${qualityMode === "astra_max" ? "premium" : ""}`}>
            {qualityMode === "astra_max" ? t("quality.astraDescription") : t("quality.terraDescription")}
          </p>
          <button className="primary-button" onClick={analyze} disabled={!photo || busy || !visionStatus?.configured}>
            {status === "analyzing" ? <><span className="spinner" /> {t("upload.analyzing")}</> : t("upload.create")}
          </button>
          {!visionStatus?.configured && <p className="setup-note"><Trans i18nKey="upload.setupNote" components={{ code: <code /> }} /></p>}
          {visionStatus?.examplesEnabled && <button className="text-button" onClick={loadDevelopmentScene} disabled={busy}>{t("upload.developmentExample")}</button>}
          {error && <pre className="error-box" role="alert">{error}</pre>}
        </aside>

        <section className="stage">
          <div className="stage-toolbar">
            <div><span className="eyebrow">{t("stage.step")}</span><strong>{sceneIr?.name || t("stage.futureScene")}</strong></div>
            <div className="toolbar-actions">
              {selectedId && <span className="selection-chip">{selectedId} · {t("stage.selectedParts", { count: selectedParts })}</span>}
              <button onClick={() => setResetToken((value) => value + 1)} disabled={!sceneIr}>{t("stage.resetCamera")}</button>
            </div>
          </div>
          <SceneViewer sceneIr={sceneIr} resetToken={resetToken} onSelect={onSelect} />
          <div className="viewer-help">{t("stage.help")}</div>
          <div className="metrics-row">
            <Metric label={t("metrics.vision")} value={formatTime(metrics.vision_ms, activeLanguage)} />
            <Metric label={t("metrics.build")} value={formatTime(metrics.compile_ms, activeLanguage)} />
            <Metric label={t("metrics.parts")} value={sceneIr ? String(sceneIr.stats.part_count) : "—"} />
            <Metric label={t("metrics.api")} value={formatCost(metrics.api_cost_usd, activeLanguage)} accent />
          </div>
        </section>

        <aside className="panel editor-panel">
          <div className="editor-heading"><div><span className="eyebrow">{t("editor.step")}</span><h2>{t("editor.title")}</h2></div><span className="schema-pill">v1.1</span></div>
          <p>{t("editor.description")}</p>
          <textarea disabled={busy} className="json-editor" aria-label="SceneSpec JSON" spellCheck={false} value={editor} onChange={(event) => { setEditor(event.target.value); setRobloxFile(null); }} placeholder={t("editor.placeholder")} />
          <div className="editor-actions">
            <button className="secondary-button" onClick={rebuild} disabled={!editor || busy}>{status === "building" ? t("editor.building") : t("editor.rebuild")}</button>
            <button className="download-button" onClick={download} disabled={!robloxFile || busy}>{t("editor.download")}</button>
          </div>
          <div className={`export-note ${robloxFile ? "ready" : "stale"}`}><span>{robloxFile ? "✓" : "!"}</span><p><strong>{robloxFile ? t("export.readyTitle") : t("export.staleTitle")}</strong><br />{robloxFile ? t("export.readyBody", { size: (robloxFile.byte_size / 1_048_576).toFixed(2) }) : t("export.staleBody")}</p></div>
        </aside>
      </main>
    </div>
  );
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
  return <div className={`metric ${accent ? "accent" : ""}`}><span>{label}</span><strong>{value}</strong></div>;
}
