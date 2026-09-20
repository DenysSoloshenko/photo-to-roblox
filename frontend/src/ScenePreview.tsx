import { lazy, Suspense } from "react";
import type { ComponentProps } from "react";
import { useTranslation } from "react-i18next";

const SceneViewer = lazy(() => import("./SceneViewer"));

export default function ScenePreview(props: ComponentProps<typeof SceneViewer>) {
  const { i18n } = useTranslation();
  return <Suspense fallback={<p role="status">{i18n.resolvedLanguage?.startsWith("fr") ? "Chargement de l’aperçu 3D…" : "Loading the 3D preview…"}</p>}><SceneViewer {...props} /></Suspense>;
}
