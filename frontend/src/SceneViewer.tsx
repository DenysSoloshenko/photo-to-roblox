import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type { SceneIR, ScenePart } from "./types";

interface Props {
  sceneIr: SceneIR | null;
  resetToken: number;
  onSelect: (sourceId: string | null) => void;
}

function geometryFor(part: ScenePart): THREE.BufferGeometry {
  if (part.shape === "ball") return new THREE.SphereGeometry(0.5, 16, 12);
  if (part.shape === "cylinder") return new THREE.CylinderGeometry(0.5, 0.5, 1, 14);
  if (part.shape === "wedge") {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute([
      -0.5,-0.5,-0.5, 0.5,-0.5,-0.5, 0.5,-0.5,0.5, -0.5,-0.5,0.5,
      -0.5,0.5,0.5, 0.5,0.5,0.5,
    ], 3));
    geometry.setIndex([
      0,2,1, 0,3,2,
      3,5,2, 3,4,5,
      0,4,3, 0,1,4,
      1,5,4, 1,2,5,
    ]);
    geometry.computeVertexNormals();
    return geometry;
  }
  return new THREE.BoxGeometry(1, 1, 1);
}

export default function SceneViewer({ sceneIr, resetToken, onSelect }: Props) {
  const { t } = useTranslation();
  const hostRef = useRef<HTMLDivElement>(null);
  const resetRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    resetRef.current?.();
  }, [resetToken]);

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !sceneIr) return;

    const extent = Math.max(sceneIr.bounds.width, sceneIr.bounds.depth, 110);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#b9d7df");
    scene.fog = new THREE.Fog("#b9d7df", Math.max(180, extent * 1.8), Math.max(520, extent * 4));
    const camera = new THREE.PerspectiveCamera(sceneIr.camera.fov, 1, 0.1, Math.max(1_000, extent * 8));
    const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: import.meta.env.DEV });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.07;
    controls.maxPolarAngle = Math.PI * 0.49;
    const resetCamera = () => {
      camera.position.fromArray(sceneIr.camera.position);
      controls.target.fromArray(sceneIr.camera.target);
      camera.fov = sceneIr.camera.fov;
      camera.updateProjectionMatrix();
      controls.update();
    };
    resetRef.current = resetCamera;
    resetCamera();

    scene.add(new THREE.HemisphereLight("#e9f8ff", "#58604b", 1.55));
    const sun = new THREE.DirectionalLight("#fff1d4", 2.1);
    sun.position.set(extent * .65, extent, extent * .45);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2_048, 2_048);
    sun.shadow.bias = -0.0002;
    sun.shadow.normalBias = Math.max(0.03, extent / 1400);
    sun.shadow.camera.left = -extent;
    sun.shadow.camera.right = extent;
    sun.shadow.camera.top = extent;
    sun.shadow.camera.bottom = -extent;
    sun.shadow.camera.far = extent * 4;
    scene.add(sun);

    const sceneGroup = new THREE.Group();
    sceneGroup.name = sceneIr.name;
    scene.add(sceneGroup);
    const selectables: THREE.InstancedMesh[] = [];
    const buckets = new Map<string, ScenePart[]>();
    for (const part of sceneIr.parts) {
      if (part.transparency >= .99) continue;
      const key = JSON.stringify([part.shape, part.material, part.color, part.transparency, part.cast_shadow]);
      const bucket = buckets.get(key) || [];
      bucket.push(part);
      buckets.set(key, bucket);
    }
    const transform = new THREE.Object3D();
    for (const rows of buckets.values()) {
      const part = rows[0];
      const material = new THREE.MeshStandardMaterial({
        color: new THREE.Color(part.color),
        transparent: part.transparency > 0,
        opacity: 1 - part.transparency,
        roughness: part.material === "water" || part.material === "glass" ? 0.22 : 0.82,
        metalness: part.material === "metal" ? 0.55 : 0.02,
        side: THREE.DoubleSide,
        depthWrite: part.transparency < 0.5,
      });
      const mesh = new THREE.InstancedMesh(geometryFor(part), material, rows.length);
      mesh.userData.sourceIds = rows.map(row => row.source_id);
      rows.forEach((row, index) => {
        transform.position.fromArray(row.position);
        transform.scale.fromArray(row.size);
        transform.rotation.set(THREE.MathUtils.degToRad(row.rotation[0]), THREE.MathUtils.degToRad(row.rotation[1]), THREE.MathUtils.degToRad(row.rotation[2]), "YXZ");
        transform.updateMatrix();
        mesh.setMatrixAt(index, transform.matrix);
      });
      mesh.instanceMatrix.needsUpdate = true;
      mesh.computeBoundingSphere();
      mesh.castShadow = part.cast_shadow && part.transparency < 0.9;
      mesh.receiveShadow = true;
      mesh.visible = part.transparency < 0.99;
      sceneGroup.add(mesh);
      if (mesh.visible) selectables.push(mesh);
    }

    const grid = new THREE.GridHelper(Math.max(sceneIr.bounds.width, sceneIr.bounds.depth), 20, "#81948c", "#a5b6af");
    grid.position.y = 0.025;
    (grid.material as THREE.Material).opacity = 0.18;
    (grid.material as THREE.Material).transparent = true;
    scene.add(grid);

    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    const handlePointer = (event: PointerEvent) => {
      const bounds = renderer.domElement.getBoundingClientRect();
      pointer.x = ((event.clientX - bounds.left) / bounds.width) * 2 - 1;
      pointer.y = -((event.clientY - bounds.top) / bounds.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObjects(selectables, false)[0];
      onSelect(hit && hit.instanceId !== undefined ? String(hit.object.userData.sourceIds[hit.instanceId]) : null);
    };
    renderer.domElement.addEventListener("pointerdown", handlePointer);

    const resize = () => {
      const { clientWidth, clientHeight } = host;
      renderer.setSize(clientWidth, clientHeight, false);
      camera.aspect = clientWidth / Math.max(clientHeight, 1);
      camera.updateProjectionMatrix();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(host);
    resize();
    // Local authoring aid only; omitted from production builds.
    const captureButton = import.meta.env.DEV ? document.createElement("button") : null;
    if (captureButton) {
      captureButton.textContent = "Save preview PNG";
      captureButton.style.cssText = "position:absolute;right:12px;top:12px;z-index:2;padding:8px 12px;border-radius:8px;border:1px solid #abc;background:#fff;cursor:pointer";
      captureButton.onclick = () => {
        renderer.render(scene, camera);
        const link = document.createElement("a");
        link.download = "scenefoundry-preview.png";
        link.href = renderer.domElement.toDataURL("image/png");
        link.click();
      };
      host.appendChild(captureButton);
    }
    renderer.setAnimationLoop(() => {
      controls.update();
      renderer.render(scene, camera);
    });

    return () => {
      resetRef.current = null;
      observer.disconnect();
      renderer.setAnimationLoop(null);
      renderer.domElement.removeEventListener("pointerdown", handlePointer);
      controls.dispose();
      grid.geometry.dispose();
      (grid.material as THREE.Material).dispose();
      captureButton?.remove();
      scene.traverse((object) => {
        if (object instanceof THREE.Mesh) {
          object.geometry.dispose();
          const materials = Array.isArray(object.material) ? object.material : [object.material];
          materials.forEach((material) => material.dispose());
        }
      });
      renderer.dispose();
      host.removeChild(renderer.domElement);
    };
  }, [sceneIr, onSelect]);

  return (
    <div className="viewer" ref={hostRef} aria-label={t("viewer.aria")}>
      {!sceneIr && <div className="viewer-empty"><span className="viewer-orbit">◎</span><strong>{t("viewer.emptyTitle")}</strong><p>{t("viewer.emptyBody")}</p></div>}
    </div>
  );
}
