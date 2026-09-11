import { useCallback, useEffect, useMemo, useState } from "react";
import { Trans, useTranslation } from "react-i18next";
import { analyzePhoto, compileScene, createManualOrder, downloadReadyRoblox, getSession, listAdminOrders, listNotifications, listOrders, loginAccount, logoutAccount, registerAccount, requestPurchase, startOAuth, updateAdminOrder } from "./api";
import type { QualityMode } from "./api";
import i18n from "./i18n";
import SceneViewer from "./SceneViewer";
import type { AccountUser, ManualOrder, Metrics, OAuthProviderStatus, OrderStatus, RobloxFile, SceneIR, SceneResponse } from "./types";

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

type PortalView = "create" | "orders" | "admin" | "lab";

export default function App() {
  const { t } = useTranslation();
  const [view, setView] = useState<PortalView>(() => new URLSearchParams(window.location.search).has("order") ? "orders" : "create");
  const [user, setUser] = useState<AccountUser | null>(null);
  const [csrfToken, setCsrfToken] = useState("");
  const [oauthProviders, setOauthProviders] = useState<OAuthProviderStatus[]>([]);
  const [authOpen, setAuthOpen] = useState(false);
  const [sessionLoading, setSessionLoading] = useState(true);
  const [unreadCount, setUnreadCount] = useState(0);
  const activeLanguage: Language = i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en";

  const refreshSession = useCallback(async () => {
    try {
      const session = await getSession();
      setUser(session.user);
      setCsrfToken(session.csrf_token);
      setOauthProviders(session.oauth_providers);
    } finally {
      setSessionLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshSession();
    const params = new URLSearchParams(window.location.search);
    if (params.has("oauth") || params.has("oauth_error")) window.history.replaceState({}, "", window.location.pathname);
  }, [refreshSession]);

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
    await logoutAccount(csrfToken);
    await refreshSession();
    setView("create");
  };

  if (view === "lab") return <GeneratorLab onExit={() => setView("create")} />;

  return (
    <div className="portal-shell">
      <header className="topbar portal-topbar">
        <button type="button" className="brand brand-button" onClick={() => setView("create")} aria-label={t("brand.aria")}>
          <span className="brand-mark">S</span>
          <span><strong>SceneFoundry</strong><small>{t("brand.tagline")}</small></span>
        </button>
        <nav className="portal-nav" aria-label={t("portal.navLabel")}>
          <button className={view === "create" ? "active" : ""} onClick={() => setView("create")}>{t("portal.create")}</button>
          {user && <button className={view === "orders" ? "active" : ""} onClick={() => setView("orders")}>{t("portal.orders")}</button>}
          {user?.admin && <button className={view === "admin" ? "active" : ""} onClick={() => setView("admin")}>{t("portal.queue")}</button>}
          <button onClick={() => setView("lab")}>{t("portal.lab")}</button>
        </nav>
        <div className="topbar-actions">
          <nav className="language-switcher" aria-label={t("language.label")}>
            <button type="button" className={activeLanguage === "en" ? "active" : ""} onClick={() => changeLanguage("en")}>EN</button>
            <button type="button" className={activeLanguage === "fr" ? "active" : ""} onClick={() => changeLanguage("fr")}>FR</button>
          </nav>
          {user && <button className="notification-bell" onClick={() => setView("orders")} aria-label={t("portal.notifications")}>♢{unreadCount > 0 && <span>{unreadCount}</span>}</button>}
          {!sessionLoading && (user ? (
            <div className="account-menu"><span>{user.display_name}</span><button onClick={logOut}>{t("auth.logout")}</button></div>
          ) : <button className="header-signin" onClick={() => setAuthOpen(true)}>{t("auth.signUp")}</button>)}
        </div>
      </header>

      {view === "create" && <CreateOrderPage user={user} csrfToken={csrfToken} onAuth={() => setAuthOpen(true)} onCreated={() => setView("orders")} />}
      {view === "orders" && user && <OrdersPage csrfToken={csrfToken} />}
      {view === "admin" && user?.admin && <AdminQueue csrfToken={csrfToken} />}

      {authOpen && <AuthDialog csrfToken={csrfToken} providers={oauthProviders} onClose={() => setAuthOpen(false)} onAuthenticated={(response) => {
        setUser(response.user);
        setCsrfToken(response.csrf_token);
        setAuthOpen(false);
      }} />}
    </div>
  );
}

function CreateOrderPage({ user, csrfToken, onAuth, onCreated }: { user: AccountUser | null; csrfToken: string; onAuth: () => void; onCreated: () => void }) {
  const { t } = useTranslation();
  const [photos, setPhotos] = useState<File[]>([]);
  const [title, setTitle] = useState("");
  const [sceneType, setSceneType] = useState("other");
  const [style, setStyle] = useState("roblox_stylized");
  const [mustPreserve, setMustPreserve] = useState("");
  const [instructions, setInstructions] = useState("");
  const [rights, setRights] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!user) return onAuth();
    setBusy(true);
    setError(null);
    try {
      const form = new FormData();
      photos.forEach((photo) => form.append("source_photos[]", photo));
      form.append("title", title);
      form.append("scene_type", sceneType);
      form.append("style", style);
      form.append("must_preserve", mustPreserve);
      form.append("instructions", instructions);
      form.append("rights_confirmed", String(rights));
      await createManualOrder(csrfToken, form);
      onCreated();
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="portal-main">
      <section className="hero-card">
        <div>
          <span className="eyebrow">{t("manual.eyebrow")}</span>
          <h1>{t("manual.title")}</h1>
          <p>{t("manual.lede")}</p>
          <div className="promise-grid">
            <div><strong>{t("manual.free")}</strong><span>{t("manual.freeBody")}</span></div>
            <div><strong>{t("manual.hours")}</strong><span>{t("manual.hoursBody")}</span></div>
            <div><strong>$19</strong><span>{t("manual.priceBody")}</span></div>
          </div>
        </div>
        <div className="hero-art" aria-hidden="true"><span>photo</span><b>→</b><span>world</span></div>
      </section>

      <section className="order-layout">
        <form className="order-form surface" onSubmit={submit}>
          <div className="section-heading"><span>01</span><div><h2>{t("manual.uploadTitle")}</h2><p>{t("manual.uploadBody")}</p></div></div>
          <label className="multi-dropzone">
            <input type="file" multiple accept="image/jpeg,image/png,image/webp" onChange={(event) => setPhotos(Array.from(event.target.files || []).slice(0, 3))} />
            <span className="drop-icon">↥</span><strong>{photos.length ? t("manual.filesSelected", { count: photos.length }) : t("manual.choosePhotos")}</strong><small>{t("manual.formats")}</small>
          </label>
          {photos.length > 0 && <div className="file-chips">{photos.map((photo) => <span key={`${photo.name}-${photo.size}`}>{photo.name}</span>)}</div>}

          <div className="section-heading"><span>02</span><div><h2>{t("manual.briefTitle")}</h2><p>{t("manual.briefBody")}</p></div></div>
          <label className="form-field"><span>{t("manual.projectName")}</span><input required maxLength={120} value={title} onChange={(event) => setTitle(event.target.value)} placeholder={t("manual.projectPlaceholder")} /></label>
          <div className="field-row">
            <label className="form-field"><span>{t("manual.sceneType")}</span><select value={sceneType} onChange={(event) => setSceneType(event.target.value)}><option value="home">{t("manual.types.home")}</option><option value="garden">{t("manual.types.garden")}</option><option value="park">{t("manual.types.park")}</option><option value="landscape">{t("manual.types.landscape")}</option><option value="venue">{t("manual.types.venue")}</option><option value="other">{t("manual.types.other")}</option></select></label>
            <label className="form-field"><span>{t("manual.style")}</span><select value={style} onChange={(event) => setStyle(event.target.value)}><option value="roblox_stylized">{t("manual.styles.roblox")}</option><option value="faithful">{t("manual.styles.faithful")}</option><option value="low_poly">{t("manual.styles.lowPoly")}</option><option value="colorful">{t("manual.styles.colorful")}</option></select></label>
          </div>
          <label className="form-field"><span>{t("manual.preserve")}</span><textarea rows={3} maxLength={2000} value={mustPreserve} onChange={(event) => setMustPreserve(event.target.value)} placeholder={t("manual.preservePlaceholder")} /></label>
          <label className="form-field"><span>{t("manual.notes")}</span><textarea rows={3} maxLength={2000} value={instructions} onChange={(event) => setInstructions(event.target.value)} placeholder={t("manual.notesPlaceholder")} /></label>
          <label className="consent-row"><input type="checkbox" checked={rights} onChange={(event) => setRights(event.target.checked)} /><span>{t("manual.rights")}</span></label>
          {error && <pre className="error-box" role="alert">{error}</pre>}
          <button className="primary-button order-submit" disabled={busy || photos.length === 0 || !title || !rights}>{busy ? t("manual.sending") : user ? t("manual.request") : t("manual.signUpRequest")}</button>
          <p className="no-card">{t("manual.noCard")}</p>
        </form>

        <aside className="process-card surface">
          <span className="eyebrow">{t("manual.process")}</span>
          <ol><li><b>1</b><div><strong>{t("manual.processUpload")}</strong><span>{t("manual.processUploadBody")}</span></div></li><li><b>2</b><div><strong>{t("manual.processBuild")}</strong><span>{t("manual.processBuildBody")}</span></div></li><li><b>3</b><div><strong>{t("manual.processPreview")}</strong><span>{t("manual.processPreviewBody")}</span></div></li><li><b>4</b><div><strong>{t("manual.processUnlock")}</strong><span>{t("manual.processUnlockBody")}</span></div></li></ol>
          <div className="beta-note">{t("manual.betaNote")}</div>
        </aside>
      </section>
    </main>
  );
}

function AuthDialog({ csrfToken, providers, onClose, onAuthenticated }: { csrfToken: string; providers: OAuthProviderStatus[]; onClose: () => void; onAuthenticated: (response: { user: AccountUser; csrf_token: string }) => void }) {
  const { t } = useTranslation();
  const [mode, setMode] = useState<"login" | "register">("register");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault(); setBusy(true); setError(null);
    try {
      const response = mode === "register" ? await registerAccount(csrfToken, { displayName, email, password }) : await loginAccount(csrfToken, email, password);
      onAuthenticated(response);
    } catch (reason) { setError(errorText(reason, t("errors.unknown"))); } finally { setBusy(false); }
  };

  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="auth-dialog" role="dialog" aria-modal="true" aria-labelledby="auth-title"><button className="modal-close" onClick={onClose} aria-label={t("auth.close")}>×</button><span className="eyebrow">SceneFoundry account</span><h2 id="auth-title">{mode === "register" ? t("auth.createTitle") : t("auth.loginTitle")}</h2><p>{t("auth.accountBody")}</p>
    <div className="social-grid">{providers.map((provider) => {
      const label = provider.name[0].toUpperCase() + provider.name.slice(1);
      return <button type="button" key={provider.name} disabled={!provider.configured} onClick={() => void startOAuth(csrfToken, provider.name)}><span>{t("auth.continueWith", { provider: label })}</span>{!provider.configured && <small>{t("auth.oauthSetupRequired")}</small>}</button>;
    })}</div>
    <div className="or-line"><span>{t("auth.or")}</span></div>
    <form onSubmit={submit}>{mode === "register" && <label className="form-field"><span>{t("auth.name")}</span><input required value={displayName} onChange={(event) => setDisplayName(event.target.value)} /></label>}<label className="form-field"><span>{t("auth.email")}</span><input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></label><label className="form-field"><span>{t("auth.password")}</span><input type="password" minLength={10} required value={password} onChange={(event) => setPassword(event.target.value)} /><small>{t("auth.passwordHint")}</small></label>{error && <pre className="error-box">{error}</pre>}<button className="primary-button" disabled={busy}>{busy ? t("auth.working") : mode === "register" ? t("auth.create") : t("auth.signIn")}</button></form>
    <p className="auth-switch">{mode === "register" ? t("auth.haveAccount") : t("auth.newAccount")} <button onClick={() => { setMode(mode === "register" ? "login" : "register"); setError(null); }}>{mode === "register" ? t("auth.signIn") : t("auth.create")}</button></p><small className="terms-copy">{t("auth.terms")}</small>
  </section></div>;
}

function OrdersPage({ csrfToken }: { csrfToken: string }) {
  const { t } = useTranslation();
  const [orders, setOrders] = useState<ManualOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => { try { setOrders((await listOrders()).orders); } catch (reason) { setError(errorText(reason, t("errors.unknown"))); } finally { setLoading(false); } }, [t]);
  useEffect(() => { void load(); }, [load]);
  const purchase = async (order: ManualOrder) => { try { const response = await requestPurchase(csrfToken, order.public_id); setOrders((all) => all.map((item) => item.public_id === order.public_id ? response.order : item)); if (response.checkout_url) window.location.assign(response.checkout_url); } catch (reason) { setError(errorText(reason, t("errors.unknown"))); } };
  return <main className="portal-main narrow"><div className="page-heading"><div><span className="eyebrow">{t("orders.eyebrow")}</span><h1>{t("orders.title")}</h1><p>{t("orders.lede")}</p></div></div>{error && <pre className="error-box">{error}</pre>}{loading ? <p>{t("orders.loading")}</p> : orders.length === 0 ? <div className="empty-orders surface"><h2>{t("orders.empty")}</h2><p>{t("orders.emptyBody")}</p></div> : <div className="order-list">{orders.map((order) => <OrderCard key={order.public_id} order={order} onPurchase={() => void purchase(order)} />)}</div>}</main>;
}

function OrderCard({ order, onPurchase }: { order: ManualOrder; onPurchase: () => void }) {
  const { t, i18n: i18next } = useTranslation();
  const [previewOpen, setPreviewOpen] = useState(false);
  const locale = i18next.language.startsWith("fr") ? "fr-FR" : "en-US";
  const status = t(`orders.status.${order.status}`);
  const hasPreview = Boolean(order.preview_scene_ir || order.preview_url);
  return <><article className="customer-order surface"><div className="order-preview">{order.preview_url ? <img src={order.preview_url} alt={t("orders.previewAlt", { title: order.title })} /> : order.preview_scene_ir ? <div><span>◎</span><strong>{t("orders.interactiveReady")}</strong></div> : <div><span>◌</span><strong>{t("orders.previewPending")}</strong></div>}</div><div className="order-content"><div className="order-title-row"><div><span className={`status-pill status-${order.status}`}>{status}</span><h2>{order.title}</h2></div><strong className="order-price">${(order.price_cents / 100).toFixed(0)}</strong></div><dl><div><dt>{t("orders.submitted")}</dt><dd>{new Date(order.submitted_at).toLocaleString(locale)}</dd></div><div><dt>{t("orders.due")}</dt><dd>{new Date(order.delivery_due_at).toLocaleString(locale)}</dd></div><div><dt>{t("orders.payment")}</dt><dd>{t(`orders.paymentStatus.${order.payment_status}`)}</dd></div></dl>{hasPreview && <div className="order-actions">{order.preview_scene_ir ? <button className="secondary-link" onClick={() => setPreviewOpen(true)}>{t("orders.explorePreview")}</button> : order.preview_url && <a className="secondary-link" href={order.preview_url} target="_blank" rel="noreferrer">{t("orders.openPreview")}</a>}{order.result_url ? <a className="unlock-button" href={order.result_url}>{t("orders.download")}</a> : order.status === "preview_ready" && <button className="unlock-button" onClick={onPurchase}>{t("orders.unlock", { price: `$${(order.price_cents / 100).toFixed(0)}` })}</button>}</div>}<small className="order-id">{order.public_id}</small></div></article>{previewOpen && order.preview_scene_ir && <OrderPreviewModal order={order} onClose={() => setPreviewOpen(false)} />}</>;
}

function OrderPreviewModal({ order, onClose }: { order: ManualOrder; onClose: () => void }) {
  const { t } = useTranslation();
  const [resetToken, setResetToken] = useState(0);
  const ignoreSelection = useCallback(() => undefined, []);
  return <div className="modal-backdrop preview-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="map-preview-dialog" role="dialog" aria-modal="true" aria-label={t("orders.explorePreview")}><header><div><span className="eyebrow">{t("orders.freeInteractivePreview")}</span><h2>{order.title}</h2></div><div><button className="secondary-link" onClick={() => setResetToken((value) => value + 1)}>{t("orders.resetCamera")}</button><button className="modal-close" onClick={onClose} aria-label={t("auth.close")}>×</button></div></header><div className="customer-scene-viewer"><SceneViewer sceneIr={order.preview_scene_ir} resetToken={resetToken} onSelect={ignoreSelection} /></div><footer><p>{t("orders.previewOnly")}</p>{order.result_url ? <a className="unlock-button" href={order.result_url}>{t("orders.download")}</a> : <button className="unlock-button" onClick={() => { onClose(); }}>{t("orders.closePreview")}</button>}</footer></section></div>;
}

function AdminQueue({ csrfToken }: { csrfToken: string }) {
  const { t } = useTranslation();
  const [orders, setOrders] = useState<ManualOrder[]>([]);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => { try { setOrders((await listAdminOrders()).orders); } catch (reason) { setError(errorText(reason, t("errors.unknown"))); } }, [t]);
  useEffect(() => { void load(); }, [load]);
  return <main className="portal-main narrow"><div className="page-heading"><div><span className="eyebrow">{t("admin.eyebrow")}</span><h1>{t("admin.title")}</h1><p>{t("admin.lede")}</p></div></div>{error && <pre className="error-box">{error}</pre>}<div className="admin-list">{orders.map((order) => <AdminOrderCard key={order.public_id} order={order} csrfToken={csrfToken} onSaved={load} />)}</div></main>;
}

function AdminOrderCard({ order, csrfToken, onSaved }: { order: ManualOrder; csrfToken: string; onSaved: () => Promise<void> }) {
  const { t } = useTranslation();
  const [status, setStatus] = useState<OrderStatus>(order.status);
  const [preview, setPreview] = useState<File | null>(null);
  const [result, setResult] = useState<File | null>(null);
  const [notes, setNotes] = useState(order.admin_notes || "");
  const [busy, setBusy] = useState(false);
  const save = async () => { setBusy(true); try { const form = new FormData(); form.append("status", status); form.append("admin_notes", notes); if (preview) form.append("preview_image", preview); if (result) form.append("result_file", result); await updateAdminOrder(csrfToken, order.public_id, form); await onSaved(); } finally { setBusy(false); } };
  return <article className="admin-order surface"><div className="admin-order-heading"><div><span className={`status-pill status-${order.status}`}>{order.status}</span><h2>{order.title}</h2><p>{order.user?.display_name} · {order.user?.email}</p></div><span>{new Date(order.delivery_due_at).toLocaleString()}</span></div><div className="source-links">{order.source_photos.map((photo, index) => <a key={photo.id || photo.filename} href={photo.download_url}>{t("admin.source", { number: index + 1 })}: {photo.filename}</a>)}</div><div className="admin-grid"><label className="form-field"><span>{t("admin.status")}</span><select value={status} onChange={(event) => setStatus(event.target.value as OrderStatus)}>{["submitted", "reviewing", "building", "preview_ready", "ready", "delivered", "cancelled"].map((value) => <option key={value}>{value}</option>)}</select></label><div className="admin-payment-state"><span>{t("admin.payment")}</span><strong>{t(`orders.paymentStatus.${order.payment_status}`)}</strong><small>{t("admin.stripeManaged")}</small></div><label className="form-field"><span>{t("admin.preview")}</span><input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setPreview(event.target.files?.[0] || null)} /></label><label className="form-field"><span>{t("admin.result")}</span><input type="file" accept=".rbxlx" onChange={(event) => setResult(event.target.files?.[0] || null)} /></label></div><label className="form-field"><span>{t("admin.notes")}</span><textarea rows={2} value={notes} onChange={(event) => setNotes(event.target.value)} /></label><div className="admin-footer"><small>{order.public_id}</small><button className="primary-button" onClick={() => void save()} disabled={busy}>{busy ? t("admin.saving") : t("admin.save")}</button></div></article>;
}

function GeneratorLab({ onExit }: { onExit: () => void }) {
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
  const [visionStatus, setVisionStatus] = useState<{ configured: boolean; model: string; reasoningEffort?: string; refinementEnabled: boolean; astraEnabled: boolean; examplesEnabled: boolean } | null>(null);

  useEffect(() => {
    fetch("/api/v1/status")
      .then((response) => response.json())
      .then((body) => setVisionStatus({
        configured: Boolean(body.vision_configured),
        model: String(body.vision_model),
        reasoningEffort: body.vision_reasoning_effort ? String(body.vision_reasoning_effort) : undefined,
        refinementEnabled: Boolean(body.vision_refinement_enabled),
        astraEnabled: Boolean(body.astra_quality_enabled),
        examplesEnabled: Boolean(body.development_examples_enabled),
      }))
      .catch(() => setVisionStatus(null));
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

  const analyze = async () => {
    if (!photo) return setError(t("errors.choosePhoto"));
    setStatus("analyzing");
    setError(null);
    try {
      receiveScene(await analyzePhoto(photo, hint, qualityMode));
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
      setStatus("idle");
    }
  };

  const rebuild = async () => {
    setStatus("building");
    setError(null);
    try {
      const response = await compileScene(JSON.parse(editor) as Record<string, unknown>);
      setSceneIr(response.scene_ir);
      setRobloxFile(response.roblox_file || null);
      setMetrics((current) => ({ ...current, ...response.metrics }));
      setStatus("ready");
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
      setStatus("ready");
    }
  };

  const download = async () => {
    setError(null);
    try {
      if (!robloxFile) throw new Error(t("errors.rebuildBeforeDownload"));
      downloadReadyRoblox(robloxFile);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    }
  };

  const loadDevelopmentScene = async () => {
    setStatus("building");
    setError(null);
    try {
      const response = await fetch("/api/v1/scenes/examples/garden?include_map=true");
      if (!response.ok) throw new Error(t("errors.developmentUnavailable"));
      receiveScene((await response.json()) as SceneResponse);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
      setStatus("idle");
    }
  };

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
            <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePhoto(event.target.files?.[0] || null)} />
            <span className="drop-copy"><strong>{photo ? photo.name : t("upload.choose")}</strong><small>{t("upload.formats")}</small></span>
          </label>
          <label className="field-label" htmlFor="hint">{t("upload.hintLabel")} <span>{t("upload.optional")}</span></label>
          <textarea id="hint" value={hint} onChange={(event) => setHint(event.target.value)} placeholder={t("upload.hintPlaceholder")} rows={4} />
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
          <textarea className="json-editor" aria-label="SceneSpec JSON" spellCheck={false} value={editor} onChange={(event) => { setEditor(event.target.value); setRobloxFile(null); }} placeholder={t("editor.placeholder")} />
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
