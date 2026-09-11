import { useCallback, useEffect, useMemo, useState } from "react";
import { Trans, useTranslation } from "react-i18next";
import { analyzePhoto, ApiError, compileScene, downloadRoblox } from "./api";
import i18n from "./i18n";
import SceneViewer from "./SceneViewer";
import type { Metrics, SceneIR, SceneResponse } from "./types";

type Status = "idle" | "analyzing" | "building" | "downloading" | "ready";
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
  if (error instanceof ApiError && error.payload.errors?.length) {
    return error.payload.errors.map((item) => `${item.path}${item.id ? ` (${item.id})` : ""}: ${item.message}`).join("\n");
  }
  return error instanceof Error ? error.message : fallback;
}

export default function App() {
  const { t } = useTranslation();
  const [photo, setPhoto] = useState<File | null>(null);
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [hint, setHint] = useState("");
  const [sceneIr, setSceneIr] = useState<SceneIR | null>(null);
  const [editor, setEditor] = useState("");
  const [metrics, setMetrics] = useState<Metrics>({});
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const [resetToken, setResetToken] = useState(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [visionStatus, setVisionStatus] = useState<{ configured: boolean; model: string } | null>(null);

  useEffect(() => {
    fetch("/api/v1/status")
      .then((response) => response.json())
      .then((body) => setVisionStatus({ configured: Boolean(body.vision_configured), model: String(body.vision_model) }))
      .catch(() => setVisionStatus(null));
  }, []);

  useEffect(() => () => {
    if (photoUrl) URL.revokeObjectURL(photoUrl);
  }, [photoUrl]);

  const receiveScene = (response: SceneResponse) => {
    setSceneIr(response.scene_ir);
    setEditor(JSON.stringify(response.scene_spec, null, 2));
    setMetrics(response.metrics);
    setSelectedId(null);
    setStatus("ready");
  };

  const choosePhoto = (file: File | null) => {
    setPhoto(file);
    setError(null);
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    setPhotoUrl(file ? URL.createObjectURL(file) : null);
  };

  const analyze = async () => {
    if (!photo) return setError(t("errors.choosePhoto"));
    setStatus("analyzing");
    setError(null);
    try {
      receiveScene(await analyzePhoto(photo, hint));
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
      setMetrics((current) => ({ ...current, compile_ms: response.metrics.compile_ms }));
      setStatus("ready");
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
      setStatus("ready");
    }
  };

  const download = async () => {
    setStatus("downloading");
    setError(null);
    try {
      await downloadRoblox(JSON.parse(editor) as Record<string, unknown>);
    } catch (reason) {
      setError(errorText(reason, t("errors.unknown")));
    } finally {
      setStatus("ready");
    }
  };

  const loadDevelopmentScene = async () => {
    setStatus("building");
    setError(null);
    try {
      const response = await fetch("/api/v1/scenes/examples/park");
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
  const busy = status === "analyzing" || status === "building" || status === "downloading";
  const selectedParts = useMemo(() => sceneIr?.parts.filter((part) => part.source_id === selectedId).length || 0, [sceneIr, selectedId]);
  const activeLanguage: Language = i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en";

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label={t("brand.aria")}>
          <span className="brand-mark">S</span>
          <span><strong>SceneFoundry</strong><small>{t("brand.tagline")}</small></span>
        </a>
        <div className="topbar-actions">
          <nav className="language-switcher" aria-label={t("language.label")}>
            <button type="button" className={activeLanguage === "en" ? "active" : ""} aria-pressed={activeLanguage === "en"} title={t("language.english")} onClick={() => changeLanguage("en")}>EN</button>
            <button type="button" className={activeLanguage === "fr" ? "active" : ""} aria-pressed={activeLanguage === "fr"} title={t("language.french")} onClick={() => changeLanguage("fr")}>FR</button>
          </nav>
          <div className={`api-badge ${visionStatus?.configured ? "online" : "offline"}`}>
            <span /> {visionStatus?.configured ? t("api.connected", { model: visionStatus.model }) : t("api.notConfigured")}
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
          <button className="primary-button" onClick={analyze} disabled={!photo || busy || !visionStatus?.configured}>
            {status === "analyzing" ? <><span className="spinner" /> {t("upload.analyzing")}</> : t("upload.create")}
          </button>
          {!visionStatus?.configured && <p className="setup-note"><Trans i18nKey="upload.setupNote" components={{ code: <code /> }} /></p>}
          {import.meta.env.DEV && <button className="text-button" onClick={loadDevelopmentScene} disabled={busy}>{t("upload.developmentExample")}</button>}
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
          <div className="editor-heading"><div><span className="eyebrow">{t("editor.step")}</span><h2>{t("editor.title")}</h2></div><span className="schema-pill">v1.0</span></div>
          <p>{t("editor.description")}</p>
          <textarea className="json-editor" aria-label="SceneSpec JSON" spellCheck={false} value={editor} onChange={(event) => setEditor(event.target.value)} placeholder={t("editor.placeholder")} />
          <div className="editor-actions">
            <button className="secondary-button" onClick={rebuild} disabled={!editor || busy}>{status === "building" ? t("editor.building") : t("editor.rebuild")}</button>
            <button className="download-button" onClick={download} disabled={!editor || busy}>{status === "downloading" ? t("editor.exporting") : t("editor.download")}</button>
          </div>
          <div className="export-note"><span>✓</span><p><strong>{t("export.title")}</strong><br />{t("export.body")}</p></div>
        </aside>
      </main>
    </div>
  );
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
  return <div className={`metric ${accent ? "accent" : ""}`}><span>{label}</span><strong>{value}</strong></div>;
}
