import { useCallback, useEffect, useMemo, useState } from "react";
import { analyzePhoto, ApiError, compileScene, downloadRoblox } from "./api";
import SceneViewer from "./SceneViewer";
import type { Metrics, SceneIR, SceneResponse } from "./types";

type Status = "idle" | "analyzing" | "building" | "downloading" | "ready";

function formatTime(value?: number) {
  if (value == null) return "—";
  return value >= 1_000 ? `${(value / 1_000).toFixed(1)} s` : `${value.toFixed(0)} ms`;
}

function formatCost(value?: number | null) {
  return value == null ? "—" : `$${value.toFixed(4)}`;
}

function errorText(error: unknown) {
  if (error instanceof ApiError && error.payload.errors?.length) {
    return error.payload.errors.map((item) => `${item.path}${item.id ? ` (${item.id})` : ""}: ${item.message}`).join("\n");
  }
  return error instanceof Error ? error.message : "Неизвестная ошибка";
}

export default function App() {
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
    if (!photo) return setError("Сначала выберите фотографию.");
    setStatus("analyzing");
    setError(null);
    try {
      receiveScene(await analyzePhoto(photo, hint));
    } catch (reason) {
      setError(errorText(reason));
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
      setError(errorText(reason));
      setStatus("ready");
    }
  };

  const download = async () => {
    setStatus("downloading");
    setError(null);
    try {
      await downloadRoblox(JSON.parse(editor) as Record<string, unknown>);
    } catch (reason) {
      setError(errorText(reason));
    } finally {
      setStatus("ready");
    }
  };

  const loadDevelopmentScene = async () => {
    setStatus("building");
    setError(null);
    try {
      const response = await fetch("/api/v1/scenes/examples/park");
      if (!response.ok) throw new Error("Development example is unavailable");
      receiveScene((await response.json()) as SceneResponse);
    } catch (reason) {
      setError(errorText(reason));
      setStatus("idle");
    }
  };

  const onSelect = useCallback((sourceId: string | null) => setSelectedId(sourceId), []);
  const busy = status === "analyzing" || status === "building" || status === "downloading";
  const selectedParts = useMemo(() => sceneIr?.parts.filter((part) => part.source_id === selectedId).length || 0, [sceneIr, selectedId]);

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="SceneFoundry"><span className="brand-mark">S</span><span><strong>SceneFoundry</strong><small>photo → Roblox</small></span></a>
        <div className={`api-badge ${visionStatus?.configured ? "online" : "offline"}`}><span /> {visionStatus?.configured ? `${visionStatus.model} подключён` : "Vision API не настроен"}</div>
      </header>

      <main className="workspace">
        <aside className="panel upload-panel">
          <div className="eyebrow">01 · Вход</div>
          <h1>Соберите мир из фотографии</h1>
          <p className="lede">Один кадр превращается в компактную сцену, которую можно поправить до экспорта.</p>
          <label className={`dropzone ${photoUrl ? "has-photo" : ""}`}>
            {photoUrl ? <img src={photoUrl} alt="Выбранная локация" /> : <span className="drop-icon">↥</span>}
            <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePhoto(event.target.files?.[0] || null)} />
            <span className="drop-copy"><strong>{photo ? photo.name : "Выберите фото локации"}</strong><small>JPEG, PNG или WebP · до 10 MB</small></span>
          </label>
          <label className="field-label" htmlFor="hint">Что важно сохранить? <span>необязательно</span></label>
          <textarea id="hint" value={hint} onChange={(event) => setHint(event.target.value)} placeholder="Например: оставить дорожку широкой и сохранить старую яблоню слева" rows={4} />
          <button className="primary-button" onClick={analyze} disabled={!photo || busy || !visionStatus?.configured}>
            {status === "analyzing" ? <><span className="spinner" /> Анализирую пространство…</> : "Создать редактируемую сцену"}
          </button>
          {!visionStatus?.configured && <p className="setup-note">Добавьте <code>OPENAI_API_KEY</code> в окружение Rails. Тестовый пример ниже не имитирует распознавание и доступен только в development.</p>}
          {import.meta.env.DEV && <button className="text-button" onClick={loadDevelopmentScene} disabled={busy}>Открыть development-пример</button>}
          {error && <pre className="error-box" role="alert">{error}</pre>}
        </aside>

        <section className="stage">
          <div className="stage-toolbar">
            <div><span className="eyebrow">02 · SceneIR</span><strong>{sceneIr?.name || "Будущая сцена"}</strong></div>
            <div className="toolbar-actions">
              {selectedId && <span className="selection-chip">{selectedId} · {selectedParts} деталей</span>}
              <button onClick={() => setResetToken((value) => value + 1)} disabled={!sceneIr}>Сбросить камеру</button>
            </div>
          </div>
          <SceneViewer sceneIr={sceneIr} resetToken={resetToken} onSelect={onSelect} />
          <div className="viewer-help">Тяните для вращения · колесо для масштаба · клик по объекту показывает semantic ID</div>
          <div className="metrics-row">
            <Metric label="Vision" value={formatTime(metrics.vision_ms)} />
            <Metric label="Сборка" value={formatTime(metrics.compile_ms)} />
            <Metric label="Детали" value={sceneIr ? String(sceneIr.stats.part_count) : "—"} />
            <Metric label="API" value={formatCost(metrics.api_cost_usd)} accent />
          </div>
        </section>

        <aside className="panel editor-panel">
          <div className="editor-heading"><div><span className="eyebrow">03 · SceneSpec</span><h2>Редактор композиции</h2></div><span className="schema-pill">v1.0</span></div>
          <p>JSON создан vision-моделью. Измените координаты или параметры и пересоберите сцену.</p>
          <textarea className="json-editor" aria-label="SceneSpec JSON" spellCheck={false} value={editor} onChange={(event) => setEditor(event.target.value)} placeholder="После анализа здесь появится SceneSpec JSON" />
          <div className="editor-actions">
            <button className="secondary-button" onClick={rebuild} disabled={!editor || busy}>{status === "building" ? "Собираю…" : "Пересобрать"}</button>
            <button className="download-button" onClick={download} disabled={!editor || busy}>{status === "downloading" ? "Экспорт…" : "Скачать .rbxlx"}</button>
          </div>
          <div className="export-note"><span>✓</span><p><strong>Одна геометрия</strong><br />Превью и Roblox-файл строятся из одного SceneIR.</p></div>
        </aside>
      </main>
    </div>
  );
}

function Metric({ label, value, accent = false }: { label: string; value: string; accent?: boolean }) {
  return <div className={`metric ${accent ? "accent" : ""}`}><span>{label}</span><strong>{value}</strong></div>;
}
