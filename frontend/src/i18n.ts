import i18n from "i18next";
import { initReactI18next } from "react-i18next";

const LANGUAGE_STORAGE_KEY = "scenefoundry-language";

function initialLanguage(): "en" | "fr" {
  try {
    return window.localStorage.getItem(LANGUAGE_STORAGE_KEY) === "fr" ? "fr" : "en";
  } catch {
    return "en";
  }
}

const resources = {
  en: {
    translation: {
      language: {
        label: "Language",
        english: "English",
        french: "French",
      },
      brand: {
        aria: "SceneFoundry home",
        tagline: "photo → Roblox",
      },
      api: {
        connected: "{{model}} connected",
        refinement: "2-pass",
        notConfigured: "Vision API not configured",
      },
      upload: {
        step: "01 · Input",
        title: "Build a world from a photograph",
        lede: "One image becomes a compact scene you can refine before export.",
        selectedAlt: "Selected location",
        choose: "Choose a location photo",
        formats: "JPEG, PNG, or WebP · up to 10 MB",
        hintLabel: "What should be preserved?",
        optional: "optional",
        hintPlaceholder: "For example: keep the path wide and preserve the old apple tree on the left",
        analyzing: "Analyzing the location…",
        create: "Create editable scene",
        setupNote: "Add <code>OPENAI_API_KEY</code> to the Rails environment. The example below is a development fixture and is never presented as vision output.",
        developmentExample: "Open development example",
      },
      stage: {
        step: "02 · SceneIR",
        futureScene: "Your scene will appear here",
        selectedParts_one: "{{count}} part",
        selectedParts_other: "{{count}} parts",
        resetCamera: "Reset camera",
        help: "Drag to orbit · scroll to zoom · click an object to reveal its semantic ID",
      },
      metrics: {
        vision: "Vision",
        build: "Build",
        parts: "Parts",
        api: "API",
      },
      editor: {
        step: "03 · SceneSpec",
        title: "Composition editor",
        description: "Vision creates the JSON. Edit coordinates or parameters, then rebuild the scene.",
        placeholder: "SceneSpec JSON will appear here after analysis",
        building: "Building…",
        rebuild: "Rebuild",
        exporting: "Exporting…",
        download: "Download .rbxlx",
      },
      export: {
        title: "One geometry source",
        body: "The preview and Roblox file are built from the same SceneIR.",
      },
      viewer: {
        aria: "Interactive 3D preview",
        emptyTitle: "Your world will appear here",
        emptyBody: "Upload a photograph to turn its main forms, paths, and elevations into an editable scene.",
      },
      errors: {
        unknown: "Unknown error",
        choosePhoto: "Choose a photograph first.",
        developmentUnavailable: "The development example is unavailable.",
      },
    },
  },
  fr: {
    translation: {
      language: {
        label: "Langue",
        english: "Anglais",
        french: "Français",
      },
      brand: {
        aria: "Accueil de SceneFoundry",
        tagline: "photo → Roblox",
      },
      api: {
        connected: "{{model}} connecté",
        refinement: "2 passages",
        notConfigured: "API Vision non configurée",
      },
      upload: {
        step: "01 · Entrée",
        title: "Créez un monde à partir d’une photographie",
        lede: "Une image devient une scène compacte que vous pouvez affiner avant l’exportation.",
        selectedAlt: "Lieu sélectionné",
        choose: "Choisir une photo du lieu",
        formats: "JPEG, PNG ou WebP · jusqu’à 10 Mo",
        hintLabel: "Que faut-il préserver ?",
        optional: "facultatif",
        hintPlaceholder: "Par exemple : garder le chemin large et préserver le vieux pommier à gauche",
        analyzing: "Analyse du lieu…",
        create: "Créer une scène modifiable",
        setupNote: "Ajoutez <code>OPENAI_API_KEY</code> à l’environnement Rails. L’exemple ci-dessous est un jeu de données de développement et n’est jamais présenté comme un résultat de l’analyse visuelle.",
        developmentExample: "Ouvrir l’exemple de développement",
      },
      stage: {
        step: "02 · SceneIR",
        futureScene: "Votre scène apparaîtra ici",
        selectedParts_one: "{{count}} élément",
        selectedParts_other: "{{count}} éléments",
        resetCamera: "Réinitialiser la caméra",
        help: "Faites glisser pour pivoter · faites défiler pour zoomer · cliquez sur un objet pour afficher son identifiant sémantique",
      },
      metrics: {
        vision: "Vision",
        build: "Construction",
        parts: "Éléments",
        api: "API",
      },
      editor: {
        step: "03 · SceneSpec",
        title: "Éditeur de composition",
        description: "Vision crée le JSON. Modifiez les coordonnées ou les paramètres, puis reconstruisez la scène.",
        placeholder: "Le JSON SceneSpec apparaîtra ici après l’analyse",
        building: "Construction…",
        rebuild: "Reconstruire",
        exporting: "Exportation…",
        download: "Télécharger le .rbxlx",
      },
      export: {
        title: "Une seule source géométrique",
        body: "L’aperçu et le fichier Roblox sont construits à partir du même SceneIR.",
      },
      viewer: {
        aria: "Aperçu 3D interactif",
        emptyTitle: "Votre monde apparaîtra ici",
        emptyBody: "Importez une photographie pour transformer ses formes, chemins et dénivelés principaux en scène modifiable.",
      },
      errors: {
        unknown: "Erreur inconnue",
        choosePhoto: "Choisissez d’abord une photographie.",
        developmentUnavailable: "L’exemple de développement est indisponible.",
      },
    },
  },
} as const;

void i18n.use(initReactI18next).init({
  resources,
  lng: initialLanguage(),
  fallbackLng: "en",
  supportedLngs: ["en", "fr"],
  interpolation: { escapeValue: false },
  react: { useSuspense: false },
  initAsync: false,
});

i18n.on("languageChanged", (language) => {
  const normalized = language.startsWith("fr") ? "fr" : "en";
  document.documentElement.lang = normalized;
  try {
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, normalized);
  } catch {
    // Language persistence is optional; the active session remains translated.
  }
});

document.documentElement.lang = i18n.resolvedLanguage?.startsWith("fr") ? "fr" : "en";

export default i18n;
