import { useEffect, useRef } from "react";
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
  return new THREE.BoxGeometry(1, 1, 1);
}

export default function SceneViewer({ sceneIr, resetToken, onSelect }: Props) {
  const hostRef = useRef<HTMLDivElement>(null);
  const resetRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    resetRef.current?.();
  }, [resetToken]);

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !sceneIr) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#b9d7df");
    scene.fog = new THREE.Fog("#b9d7df", 180, 520);
    const camera = new THREE.PerspectiveCamera(sceneIr.camera.fov, 1, 0.1, 1_000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
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
    sun.position.set(70, 105, 50);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2_048, 2_048);
    sun.shadow.camera.left = -110;
    sun.shadow.camera.right = 110;
    sun.shadow.camera.top = 110;
    sun.shadow.camera.bottom = -110;
    scene.add(sun);

    const sceneGroup = new THREE.Group();
    sceneGroup.name = sceneIr.name;
    scene.add(sceneGroup);
    const selectables: THREE.Mesh[] = [];
    for (const part of sceneIr.parts) {
      const material = new THREE.MeshStandardMaterial({
        color: new THREE.Color(part.color),
        transparent: part.transparency > 0,
        opacity: 1 - part.transparency,
        roughness: part.material === "water" || part.material === "glass" ? 0.22 : 0.82,
        metalness: part.material === "metal" ? 0.55 : 0.02,
        side: THREE.DoubleSide,
        depthWrite: part.transparency < 0.5,
      });
      const mesh = new THREE.Mesh(geometryFor(part), material);
      mesh.name = part.id;
      mesh.userData.sourceId = part.source_id;
      mesh.position.fromArray(part.position);
      mesh.scale.fromArray(part.size);
      mesh.rotation.set(
        THREE.MathUtils.degToRad(part.rotation[0]),
        THREE.MathUtils.degToRad(part.rotation[1]),
        THREE.MathUtils.degToRad(part.rotation[2]),
        "YXZ",
      );
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
      onSelect(hit ? String(hit.object.userData.sourceId) : null);
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
    <div className="viewer" ref={hostRef} aria-label="Интерактивное 3D-превью">
      {!sceneIr && <div className="viewer-empty"><span className="viewer-orbit">◎</span><strong>Пространство появится здесь</strong><p>Загрузите фотографию — основные формы, пути и высоты превратятся в редактируемую сцену.</p></div>}
    </div>
  );
}
