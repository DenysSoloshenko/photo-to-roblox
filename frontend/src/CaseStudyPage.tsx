import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import SceneViewer from "./ScenePreview";
import type { SceneIR } from "./types";
import "./case-study.css";

const ROOT = "/cases/springer-park";
const copy = {
  en: {
    eyebrow: "Field notes / Case 01", title: "A neighbourhood, rebuilt as a world.",
    intro: "An open-data study of Springer Park, Burnaby. Streets, building footprints and paths become an editable Roblox environment—with a human in the loop.",
    badge: "Open-data demonstration", preview: "Explore the 3D study", reset: "Reset view", loading: "Loading the neighbourhood…", failed: "The preview could not load. You can still view the images or download the study.", retry: "Try again",
    download: "Download the .rbxlx study", count: "editable parts", buildings: "building footprints", area: "metre study area", overview: "Overview", plan: "Source plan", street: "Closer look",
    rendered: "Three.js rendering of the exported geometry. Not a Roblox Studio screenshot.",
    pipeline: "From geography to geometry", steps: [
      ["01", "Start with usable sources", "OpenStreetMap vector features establish roads, paths and footprints. No Google imagery, tiles or customer photos are included."],
      ["02", "Build an interpretation", "A deterministic offline builder adds original, procedural facades and planting. Heights and details remain approximations—not a surveyed digital twin."],
      ["03", "Inspect, then export", "The browser and Roblox export share the same geometry. Check the composition here, then open the editable .rbxlx in Roblox Studio."],
    ],
    truth: "What this case proves—and what it does not", works: "A repeatable vector-to-geometry workflow, a browser preview and an editable Roblox file.", limits: "This is an operator-built demonstration, not a completed customer order or live photo-to-AI result. Roblox Studio Play, mobile performance and full walkability still need testing.",
    rights: "Source and licence", rightsBody: "Map data © OpenStreetMap contributors, available under ODbL 1.0. Download the source and derived geometry below. Facades and planting are procedural; imagery from the earlier Google-based research prototype is not published here.",
    source: "Source data", derived: "Derived geometry", license: "Licence & methods", watch: "A 60-second project walkthrough", videoCaption: "Actual interface captures and rendered case views. Captions describe the current beta, including its remaining release checks.",
    next: "Have a place in mind?", nextBody: "The current beta accepts 1–3 photos you own or may use. A neighbourhood-scale build needs a separate scope review; this case is not a promise of a whole district for $19.", cta: "See the photo-order workflow",
  },
  fr: {
    eyebrow: "Carnet de terrain / Cas 01", title: "Un quartier devient un monde.",
    intro: "Une étude de Springer Park, à Burnaby, fondée sur des données ouvertes. Rues, bâtiments et chemins deviennent un environnement Roblox modifiable, avec intervention humaine.",
    badge: "Démonstration avec données ouvertes", preview: "Explorer l’étude en 3D", reset: "Réinitialiser la vue", loading: "Chargement du quartier…", failed: "L’aperçu n’a pas pu être chargé. Les images et le fichier restent disponibles.", retry: "Réessayer",
    download: "Télécharger l’étude .rbxlx", count: "pièces modifiables", buildings: "emprises de bâtiments", area: "mètres de zone étudiée", overview: "Vue d’ensemble", plan: "Plan source", street: "Vue rapprochée",
    rendered: "Rendu Three.js de la géométrie exportée. Ce n’est pas une capture de Roblox Studio.",
    pipeline: "De la géographie à la géométrie", steps: [
      ["01", "Choisir des sources utilisables", "Les données vectorielles OpenStreetMap définissent rues, chemins et bâtiments. Aucune image Google ni photo client n’est incluse."],
      ["02", "Construire une interprétation", "Un générateur hors ligne déterministe ajoute des façades et de la végétation procédurales. Hauteurs et détails restent approximatifs."],
      ["03", "Inspecter puis exporter", "L’aperçu et l’export Roblox partagent la même géométrie. Vérifiez la composition, puis ouvrez le fichier .rbxlx dans Roblox Studio."],
    ],
    truth: "Ce que ce cas démontre—et ses limites", works: "Un processus reproductible, des données vectorielles à la géométrie, avec aperçu et fichier Roblox modifiable.", limits: "Démonstration réalisée par un opérateur, et non commande client ou résultat IA en direct. Le mode Play, les performances mobiles et les déplacements restent à tester dans Roblox Studio.",
    rights: "Sources et licence", rightsBody: "Données cartographiques © contributeurs OpenStreetMap, sous ODbL 1.0. Sources et géométrie dérivée sont téléchargeables ci-dessous. Façades et végétation sont procédurales ; les images de l’ancien prototype Google ne sont pas publiées ici.",
    source: "Données sources", derived: "Géométrie dérivée", license: "Licence et méthode", watch: "Le projet en 60 secondes", videoCaption: "Captures réelles de l’interface et rendus du cas. Les légendes décrivent la bêta et les contrôles restant avant le lancement.",
    next: "Un lieu en tête ?", nextBody: "La bêta accepte 1 à 3 photos dont vous détenez les droits. Un quartier entier exige une étude de périmètre distincte ; ce cas ne promet pas un quartier complet pour 19 $.", cta: "Voir le parcours de commande photo",
  },
};

export default function CaseStudyPage() {
  const { i18n } = useTranslation();
  const c = copy[i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en"];
  const [mode, setMode] = useState<"overview" | "plan" | "street">("overview");
  const [interactive, setInteractive] = useState(false);
  const [scene, setScene] = useState<SceneIR | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [reset, setReset] = useState(0);
  const ignoreSelect = useCallback(() => undefined, []);
  const displayedScene = useMemo<SceneIR | null>(() => !scene ? null : ({ ...scene, camera: mode === "plan" ? { position: [0, 1500, .01], target: [0, 0, 0], fov: 48 } : mode === "street" ? { position: [120, 320, 590], target: [0, 20, -70], fov: 48 } : scene.camera }), [scene, mode]);
  useEffect(() => {
    if (!interactive || scene) return;
    const controller = new AbortController();
    setFailed(false);
    fetch(`${ROOT}/scene.json`, { signal: controller.signal })
      .then(response => { if (!response.ok) throw Error("Case unavailable"); return response.json(); })
      .then((value: SceneIR) => { if (!controller.signal.aborted) setScene(value); })
      .catch(() => { if (!controller.signal.aborted) setFailed(true); });
    return () => controller.abort();
  }, [interactive, scene, attempt]);

  return <main className="portal-main case-page">
    <header className="case-heading"><span className="eyebrow">{c.eyebrow}</span><span className="case-badge">{c.badge}</span><h1>{c.title}</h1><p>{c.intro}</p></header>
    <section className="case-stage" aria-label={c.preview}>
      {interactive ? <div className="case-live">{displayedScene ? <SceneViewer sceneIr={displayedScene} resetToken={reset} onSelect={ignoreSelect} /> : <div className="case-loading" role="status">{failed ? <><p>{c.failed}</p><button onClick={() => setAttempt(v => v + 1)}>{c.retry}</button></> : c.loading}</div>}</div> : <img className={`case-render case-render-${mode}`} src={`${ROOT}/${mode === "plan" ? "plan.svg" : `${mode}.png`}`} alt={`${c[mode]} — Springer Park open-data study`} width="1600" height="1000" />}
      <div className="case-stage-controls"><div role="group" aria-label="View">{(["overview", "plan", "street"] as const).map(view => <button key={view} aria-pressed={mode === view} onClick={() => setMode(view)}>{c[view]}</button>)}</div><button className="case-explore" onClick={() => interactive ? setReset(v => v + 1) : setInteractive(true)}>{interactive ? c.reset : c.preview} ↗</button></div>
    </section>
    <p className="case-caption">{c.rendered} <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">© OpenStreetMap contributors · ODbL</a></p>
    <div className="case-metrics"><div><strong>5,682</strong><span>{c.count}</span></div><div><strong>20</strong><span>{c.buildings}</span></div><div><strong>440 × 290</strong><span>{c.area}</span></div><a className="primary-button" href={`${ROOT}/Springer_Park_Open_Data.rbxlx`} download>{c.download} ↓</a></div>
    <section className="case-process"><span className="eyebrow">{c.pipeline}</span><div>{c.steps.map(([number,title,body]) => <article key={number}><span>{number}</span><h2>{title}</h2><p>{body}</p></article>)}</div></section>
    <section className="case-video surface"><div><span className="eyebrow">SceneFoundry / Beta</span><h2>{c.watch}</h2><p>{c.videoCaption}</p></div><video controls playsInline preload="none" poster={`${ROOT}/overview.png`} aria-label={c.watch}><source src={`${ROOT}/SceneFoundry_Case_Walkthrough.mp4`} type="video/mp4" /><track kind="captions" src={`${ROOT}/walkthrough.en.vtt`} srcLang="en" label="English" /></video></section>
    <div className="case-notes"><section><h2>{c.truth}</h2><p>{c.works}</p><p>{c.limits}</p></section><section><h2>{c.rights}</h2><p>{c.rightsBody}</p><div className="case-links"><a href={`${ROOT}/source.json`} download>{c.source} ↗</a><a href={`${ROOT}/scene.json`} download>{c.derived} ↗</a><a href={`${ROOT}/LICENSE.md`}>{c.license} ↗</a></div></section></div>
    <section className="case-next"><div><h2>{c.next}</h2><p>{c.nextBody}</p></div><a href="/" className="primary-button">{c.cta} →</a></section>
  </main>;
}
