import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  acceptAdminOrder,
  approveAdminOrder,
  authorizeOrderPayment,
  cancelOrder,
  createManualOrder,
  declineAdminOrder,
  listAdminOrders,
  listOrders,
  updateAdminOrder,
} from "./api";
import SceneViewer from "./SceneViewer";
import type { AccountUser, GenerationMetrics, ManualOrder, OrderStatus } from "./types";

type Confirmation = {
  title: string;
  body: string;
  confirmLabel: string;
  tone?: "primary" | "danger";
  onConfirm: () => Promise<void>;
};

type OrderAction = "authorize" | "cancel" | null;
type OperatorAction = "accept" | "decline" | "approve";

const ORDER_PROGRESS: Record<OrderStatus, number> = {
  payment_pending: 8,
  submitted: 22,
  accepted: 38,
  building: 62,
  reviewing: 82,
  preview_ready: 94,
  ready: 100,
  delivered: 100,
  declined: 100,
  cancelled: 100,
  failed: 100,
};

function errorText(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback;
}

function formatDate(value: string | null, locale: string) {
  return value ? new Date(value).toLocaleString(locale) : "—";
}

function formatMoney(cents: number, currency: string, locale: string) {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currency.toUpperCase(),
    maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(cents / 100);
}

function firstMetric(metrics: GenerationMetrics | null, keys: string[]) {
  for (const key of keys) {
    const value = metrics?.[key];
    if (typeof value === "number" || typeof value === "string") return value;
  }
  return null;
}

function formatDuration(value: string | number | null, locale: string) {
  if (value == null) return "—";
  const milliseconds = Number(value);
  if (!Number.isFinite(milliseconds)) return String(value);
  if (milliseconds < 1_000) return `${Math.round(milliseconds)} ms`;
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(milliseconds / 1_000)} s`;
}

function formatApiCost(value: string | number | null, locale: string) {
  if (value == null) return "—";
  const amount = Number(value);
  if (!Number.isFinite(amount)) return String(value);
  return new Intl.NumberFormat(locale, { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(amount);
}

export function CreateOrderPage({ user, csrfToken, onAuth, onCreated }: { user: AccountUser | null; csrfToken: string; onAuth: () => void; onCreated: () => void }) {
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
            <div><strong>{t("manual.hold")}</strong><span>{t("manual.holdBody")}</span></div>
            <div><strong>{t("manual.hours")}</strong><span>{t("manual.hoursBody")}</span></div>
            <div><strong>{t("manual.review")}</strong><span>{t("manual.reviewBody")}</span></div>
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
          <div className="hold-disclosure" role="note"><strong>{t("manual.holdDisclosureTitle")}</strong><p>{t("manual.holdDisclosureBody")}</p></div>
          {error && <pre className="error-box" role="alert">{error}</pre>}
          <button className="primary-button order-submit" disabled={busy || photos.length === 0 || !title || !rights}>{busy ? t("manual.sending") : user ? t("manual.request") : t("manual.signInRequest")}</button>
          <p className="no-card">{t("manual.nextStep")}</p>
        </form>

        <aside className="process-card surface">
          <span className="eyebrow">{t("manual.process")}</span>
          <ol><li><b>1</b><div><strong>{t("manual.processUpload")}</strong><span>{t("manual.processUploadBody")}</span></div></li><li><b>2</b><div><strong>{t("manual.processAuthorize")}</strong><span>{t("manual.processAuthorizeBody")}</span></div></li><li><b>3</b><div><strong>{t("manual.processBuild")}</strong><span>{t("manual.processBuildBody")}</span></div></li><li><b>4</b><div><strong>{t("manual.processDeliver")}</strong><span>{t("manual.processDeliverBody")}</span></div></li></ol>
          <div className="beta-note">{t("manual.betaNote")}</div>
        </aside>
      </section>
    </main>
  );
}

export function OrdersPage({ csrfToken }: { csrfToken: string }) {
  const { t } = useTranslation();
  const [orders, setOrders] = useState<ManualOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<{ id: string; action: OrderAction } | null>(null);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);

  const load = useCallback(async () => {
    try {
      setOrders((await listOrders()).orders);
      setError(null);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    void load();
    const interval = window.setInterval(() => void load(), 20_000);
    return () => window.clearInterval(interval);
  }, [load]);

  const authorize = async (order: ManualOrder) => {
    setBusy({ id: order.public_id, action: "authorize" });
    setError(null);
    try {
      const response = await authorizeOrderPayment(csrfToken, order.public_id);
      setOrders((all) => all.map((item) => item.public_id === order.public_id ? response.order : item));
      if (!response.checkout_url) throw new Error(t("orders.checkoutUnavailable"));
      window.location.assign(response.checkout_url);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
      setBusy(null);
    }
  };

  const requestCancel = (order: ManualOrder) => setConfirmation({
    title: t("orders.cancelConfirmTitle"),
    body: t("orders.cancelConfirmBody"),
    confirmLabel: t("orders.cancelConfirmAction"),
    tone: "danger",
    onConfirm: async () => {
      setBusy({ id: order.public_id, action: "cancel" });
      setError(null);
      try {
        const response = await cancelOrder(csrfToken, order.public_id);
        setOrders((all) => all.map((item) => item.public_id === order.public_id ? response.order : item));
      } catch (reason) {
        setError(errorText(reason, t("errors.unknown")));
      } finally {
        setBusy(null);
      }
    },
  });

  return <main className="portal-main narrow"><div className="page-heading"><div><span className="eyebrow">{t("orders.eyebrow")}</span><h1>{t("orders.title")}</h1><p>{t("orders.lede")}</p></div><button className="secondary-link" onClick={() => void load()} disabled={loading}>{t("orders.refresh")}</button></div><div className="hold-banner" role="note"><strong>{t("orders.holdTitle")}</strong><p>{t("orders.holdBody")}</p></div>{error && <pre className="error-box" role="alert">{error}</pre>}{loading ? <p>{t("orders.loading")}</p> : orders.length === 0 ? <div className="empty-orders surface"><h2>{t("orders.empty")}</h2><p>{t("orders.emptyBody")}</p></div> : <div className="order-list">{orders.map((order) => <OrderCard key={order.public_id} order={order} busyAction={busy?.id === order.public_id ? busy.action : null} onAuthorize={() => void authorize(order)} onCancel={() => requestCancel(order)} />)}</div>}{confirmation && <ConfirmationDialog confirmation={confirmation} onClose={() => setConfirmation(null)} />}</main>;
}

function OrderCard({ order, busyAction, onAuthorize, onCancel }: { order: ManualOrder; busyAction: OrderAction; onAuthorize: () => void; onCancel: () => void }) {
  const { t, i18n } = useTranslation();
  const [previewOpen, setPreviewOpen] = useState(false);
  const locale = i18n.language.startsWith("fr") ? "fr-FR" : "en-US";
  const price = formatMoney(order.price_cents, order.currency, locale);
  const hasPreview = Boolean(order.preview_scene_ir || order.preview_url);
  const progress = ORDER_PROGRESS[order.status];

  return <><article className="customer-order surface"><div className="order-preview">{order.preview_url ? <img src={order.preview_url} alt={t("orders.previewAlt", { title: order.title })} /> : order.preview_scene_ir ? <div><span>◎</span><strong>{t("orders.interactiveReady")}</strong></div> : <div><span>◌</span><strong>{t(`orders.progress.${order.status}`)}</strong></div>}</div><div className="order-content"><div className="order-title-row"><div><span className={`status-pill status-${order.status}`}>{t(`orders.status.${order.status}`)}</span><h2>{order.title}</h2></div><strong className="order-price">{price}</strong></div><OrderProgress order={order} progress={progress} /><dl><div><dt>{t("orders.submitted")}</dt><dd>{formatDate(order.submitted_at, locale)}</dd></div><div><dt>{t("orders.due")}</dt><dd>{formatDate(order.delivery_due_at, locale)}</dd></div><div><dt>{t("orders.payment")}</dt><dd>{t(`orders.paymentStatus.${order.payment_status}`)}</dd></div>{order.authorization_expires_at && <div><dt>{t("orders.holdExpiry")}</dt><dd>{formatDate(order.authorization_expires_at, locale)}</dd></div>}</dl><div className="payment-explainer"><strong>{t(`orders.paymentMessage.${order.payment_status}.title`)}</strong><span>{t(`orders.paymentMessage.${order.payment_status}.body`)}</span></div><div className="order-actions">{order.can_authorize && <button className="unlock-button" onClick={onAuthorize} disabled={busyAction !== null}>{busyAction === "authorize" ? t("orders.authorizing") : t("orders.authorize", { price })}</button>}{order.can_cancel && <button className="secondary-link danger-link" onClick={onCancel} disabled={busyAction !== null}>{busyAction === "cancel" ? t("orders.cancelling") : t("orders.cancel")}</button>}{hasPreview && (order.preview_scene_ir ? <button className="secondary-link" onClick={() => setPreviewOpen(true)}>{t("orders.explorePreview")}</button> : order.preview_url && <a className="secondary-link" href={order.preview_url} target="_blank" rel="noreferrer">{t("orders.openPreview")}</a>)}{order.can_download && order.result_url && <a className="unlock-button" href={order.result_url}>{t("orders.download")}</a>}</div>{!order.can_cancel && ["paid", "capture_pending"].includes(order.payment_status) && <p className="action-note">{t("orders.cancelUnavailable")}</p>}<small className="order-id">{order.public_id}</small></div></article>{previewOpen && order.preview_scene_ir && <OrderPreviewModal order={order} onClose={() => setPreviewOpen(false)} />}</>;
}

function OrderProgress({ order, progress }: { order: ManualOrder; progress: number }) {
  const { t } = useTranslation();
  const terminal = ["declined", "cancelled", "failed"].includes(order.status);
  return <div className={`order-progress ${terminal ? "terminal" : ""}`}><div><strong>{t(`orders.progress.${order.status}`)}</strong><span>{terminal ? t("orders.progressClosed") : `${progress}%`}</span></div><div className="progress-track" role="progressbar" aria-label={t("orders.progressLabel")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={progress}><span style={{ width: `${progress}%` }} /></div></div>;
}

function OrderPreviewModal({ order, onClose }: { order: ManualOrder; onClose: () => void }) {
  const { t } = useTranslation();
  const [resetToken, setResetToken] = useState(0);
  const ignoreSelection = useCallback(() => undefined, []);
  return <div className="modal-backdrop preview-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="map-preview-dialog" role="dialog" aria-modal="true" aria-label={t("orders.explorePreview")}><header><div><span className="eyebrow">{t("orders.interactivePreview")}</span><h2>{order.title}</h2></div><div><button className="secondary-link" onClick={() => setResetToken((value) => value + 1)}>{t("orders.resetCamera")}</button><button className="modal-close" onClick={onClose} aria-label={t("auth.close")}>×</button></div></header><div className="customer-scene-viewer"><SceneViewer sceneIr={order.preview_scene_ir} resetToken={resetToken} onSelect={ignoreSelection} /></div><footer><p>{t("orders.previewOnly")}</p>{order.can_download && order.result_url ? <a className="unlock-button" href={order.result_url}>{t("orders.download")}</a> : <button className="secondary-link" onClick={onClose}>{t("orders.closePreview")}</button>}</footer></section></div>;
}

export function AdminQueue({ csrfToken }: { csrfToken: string }) {
  const { t } = useTranslation();
  const [orders, setOrders] = useState<ManualOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    try {
      setOrders((await listAdminOrders()).orders);
      setError(null);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setLoading(false);
    }
  }, [t]);
  useEffect(() => {
    void load();
    const interval = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(interval);
  }, [load]);
  return <main className="portal-main admin-main"><div className="page-heading"><div><span className="eyebrow">{t("admin.eyebrow")}</span><h1>{t("admin.title")}</h1><p>{t("admin.lede")}</p></div><button className="secondary-link" onClick={() => void load()}>{t("admin.refresh")}</button></div><section className="email-template-strip surface"><div><span className="eyebrow">{t("admin.emailTemplates")}</span><strong>{t("admin.emailTemplatesBody")}</strong></div><nav aria-label={t("admin.emailTemplates")}><a href="/api/v1/admin/email_previews/password_reset" target="_blank" rel="noreferrer">{t("admin.passwordResetEmail")}</a><a href="/api/v1/admin/email_previews/preview_ready" target="_blank" rel="noreferrer">{t("admin.previewReadyEmail")}</a><a href="/api/v1/admin/email_previews/map_ready" target="_blank" rel="noreferrer">{t("admin.mapReadyEmail")}</a></nav></section>{error && <pre className="error-box" role="alert">{error}</pre>}{loading ? <p>{t("admin.loading")}</p> : orders.length === 0 ? <div className="empty-orders surface"><h2>{t("admin.empty")}</h2></div> : <div className="admin-list">{orders.map((order) => <AdminOrderCard key={order.public_id} order={order} csrfToken={csrfToken} onSaved={load} />)}</div>}</main>;
}

function AdminOrderCard({ order, csrfToken, onSaved }: { order: ManualOrder; csrfToken: string; onSaved: () => Promise<void> }) {
  const { t, i18n } = useTranslation();
  const locale = i18n.language.startsWith("fr") ? "fr-FR" : "en-US";
  const [preview, setPreview] = useState<File | null>(null);
  const [result, setResult] = useState<File | null>(null);
  const [notes, setNotes] = useState(order.admin_notes || "");
  const [busy, setBusy] = useState<OperatorAction | "save" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const [resetToken, setResetToken] = useState(0);
  const ignoreSelection = useCallback(() => undefined, []);
  const metrics = order.generation_metrics || null;
  const generationTime = firstMetric(metrics, ["total_ms", "elapsed_ms", "latency_ms", "vision_ms"]);
  const apiCost = firstMetric(metrics, ["api_cost_usd", "cost_usd", "draft_api_cost_usd"]);
  const model = firstMetric(metrics, ["vision_model", "model", "provider"]);

  useEffect(() => setNotes(order.admin_notes || ""), [order.admin_notes]);

  const save = async () => {
    setBusy("save");
    setError(null);
    try {
      const form = new FormData();
      form.append("admin_notes", notes);
      if (preview) form.append("preview_image", preview);
      if (result) form.append("result_file", result);
      await updateAdminOrder(csrfToken, order.public_id, form);
      setPreview(null);
      setResult(null);
      await onSaved();
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setBusy(null);
    }
  };

  const performAction = async (action: OperatorAction) => {
    setBusy(action);
    setError(null);
    try {
      if (action === "accept") await acceptAdminOrder(csrfToken, order.public_id);
      if (action === "decline") await declineAdminOrder(csrfToken, order.public_id);
      if (action === "approve") await approveAdminOrder(csrfToken, order.public_id);
      await onSaved();
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setBusy(null);
    }
  };

  const confirmAction = (action: OperatorAction) => {
    setConfirmation({
      title: t(`admin.confirm.${action}.title`),
      body: t(`admin.confirm.${action}.body`),
      confirmLabel: t(`admin.actions.${action}`),
      tone: action === "decline" ? "danger" : "primary",
      onConfirm: () => performAction(action),
    });
  };

  const progress = ORDER_PROGRESS[order.status];
  return <article className="admin-order surface"><div className="admin-order-heading"><div><span className={`status-pill status-${order.status}`}>{t(`orders.status.${order.status}`)}</span><h2>{order.title}</h2><p>{order.user?.display_name} · {order.user?.email}</p></div><div className="admin-heading-meta"><strong>{formatMoney(order.price_cents, order.currency, locale)}</strong><span>{t("admin.due")}: {formatDate(order.delivery_due_at, locale)}</span></div></div><OrderProgress order={order} progress={progress} /><div className="source-links">{order.source_photos.map((photo, index) => <a key={photo.id || photo.filename} href={photo.download_url}>{t("admin.source", { number: index + 1 })}: {photo.filename}</a>)}</div><section className="admin-status-grid" aria-label={t("admin.operationalStatus")}><div><span>{t("admin.status")}</span><strong>{t(`orders.status.${order.status}`)}</strong></div><div><span>{t("admin.payment")}</span><strong>{t(`orders.paymentStatus.${order.payment_status}`)}</strong></div><div><span>{t("admin.attempts")}</span><strong>{order.generation_attempts || 0}</strong></div><div><span>{t("admin.generationWindow")}</span><strong>{formatDuration(generationTime, locale)}</strong></div><div><span>{t("admin.apiCost")}</span><strong>{formatApiCost(apiCost, locale)}</strong></div><div><span>{t("admin.model")}</span><strong>{model || "—"}</strong></div></section>{order.generation_started_at && <p className="generation-timing">{t("admin.started")}: {formatDate(order.generation_started_at, locale)} · {t("admin.finished")}: {formatDate(order.generation_finished_at, locale)}</p>}{order.payment_error && <div className="generation-error" role="alert"><strong>{t("admin.paymentError")}</strong><pre>{order.payment_error}</pre></div>}{order.generation_error && <div className="generation-error" role="alert"><strong>{t("admin.generationError")}</strong><pre>{order.generation_error}</pre></div>}{order.preview_scene_ir && <section className="admin-preview"><header><div><span className="eyebrow">{t("admin.interactivePreview")}</span><strong>{t("admin.qaBeforeRelease")}</strong></div><button className="secondary-link" onClick={() => setResetToken((value) => value + 1)}>{t("orders.resetCamera")}</button></header><div><SceneViewer sceneIr={order.preview_scene_ir} resetToken={resetToken} onSelect={ignoreSelection} /></div></section>}<div className="admin-upload-grid"><label className="form-field"><span>{t("admin.preview")}</span><input key={`preview-${order.public_id}-${order.preview_url || "none"}`} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setPreview(event.target.files?.[0] || null)} /><small>{order.preview_url ? t("admin.replacementRetained") : t("admin.optionalPreview")}</small></label><label className="form-field"><span>{t("admin.result")}</span><input key={`result-${order.public_id}-${order.can_download}`} type="file" accept=".rbxlx,application/xml,text/xml" onChange={(event) => setResult(event.target.files?.[0] || null)} /><small>{order.result_url || order.preview_scene_ir ? t("admin.replacementRetained") : t("admin.resultRequired")}</small></label></div><label className="form-field"><span>{t("admin.notes")}</span><textarea rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} /></label>{error && <pre className="error-box" role="alert">{error}</pre>}<div className="admin-save-row"><small>{order.public_id}</small><button className="secondary-link" onClick={() => void save()} disabled={busy !== null}>{busy === "save" ? t("admin.saving") : t("admin.save")}</button></div><div className="operator-actions" aria-label={t("admin.operatorActions")}><button className="operator-button accept" onClick={() => confirmAction("accept")} disabled={busy !== null || !order.can_accept} title={!order.can_accept ? t("admin.guards.accept") : undefined}>{busy === "accept" ? t("admin.working") : t("admin.actions.accept")}</button><button className="operator-button decline" onClick={() => confirmAction("decline")} disabled={busy !== null || !order.can_decline} title={!order.can_decline ? t("admin.guards.decline") : undefined}>{busy === "decline" ? t("admin.working") : t("admin.actions.decline")}</button><button className="operator-button approve" onClick={() => confirmAction("approve")} disabled={busy !== null || !order.can_approve} title={!order.can_approve ? t("admin.guards.approve") : undefined}>{busy === "approve" ? t("admin.working") : t("admin.actions.approve")}</button></div><ul className="guard-list"><li className={order.can_accept ? "available" : ""}>{t("admin.guards.accept")}</li><li className={order.can_decline ? "available" : ""}>{t("admin.guards.decline")}</li><li className={order.can_approve ? "available" : ""}>{t("admin.guards.approve")}</li></ul>{confirmation && <ConfirmationDialog confirmation={confirmation} onClose={() => setConfirmation(null)} />}</article>;
}

function ConfirmationDialog({ confirmation, onClose }: { confirmation: Confirmation; onClose: () => void }) {
  const { t } = useTranslation();
  const [working, setWorking] = useState(false);
  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === "Escape" && !working) onClose(); };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose, working]);
  const confirm = async () => {
    setWorking(true);
    try {
      await confirmation.onConfirm();
      onClose();
    } finally {
      setWorking(false);
    }
  };
  return <div className="modal-backdrop confirmation-backdrop" role="presentation"><section className="confirmation-dialog" role="alertdialog" aria-modal="true" aria-labelledby="confirmation-title" aria-describedby="confirmation-body"><span className="eyebrow">{t("confirm.eyebrow")}</span><h2 id="confirmation-title">{confirmation.title}</h2><p id="confirmation-body">{confirmation.body}</p><div><button className="secondary-link" onClick={onClose} disabled={working}>{t("confirm.back")}</button><button autoFocus className={`operator-button ${confirmation.tone === "danger" ? "decline" : "accept"}`} onClick={() => void confirm()} disabled={working}>{working ? t("confirm.working") : confirmation.confirmLabel}</button></div></section></div>;
}
