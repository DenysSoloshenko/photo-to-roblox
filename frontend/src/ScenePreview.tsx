import { lazy, Suspense } from "react";
import type { ComponentProps } from "react";
import { useTranslation } from "react-i18next";

const SceneViewer = lazy(() => import("./SceneViewer"));

export default function ScenePreview(props: ComponentProps<typeof SceneViewer>) {
  const { t } = useTranslation();
  return <Suspense fallback={<p role="status">{t("orders.loading")}</p>}><SceneViewer {...props} /></Suspense>;
}
