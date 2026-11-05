<script lang="ts">
	import { onMount } from 'svelte';
	import * as THREE from 'three';
	import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

	let { matte, wheelColour }: { matte: boolean; wheelColour: string } = $props();
	let canvas = $state<HTMLCanvasElement>();
	let paused = $state(false);
	let unavailable = $state(false);
	let angle = 0.48;

	onMount(() => {
		const surface = canvas;
		if (!surface) return;

		let renderer: THREE.WebGLRenderer;
		try {
			renderer = new THREE.WebGLRenderer({ canvas: surface, antialias: true, alpha: true });
		} catch {
			unavailable = true;
			return;
		}

		const scene = new THREE.Scene();
		const studio = new RoomEnvironment();
		const reflections = new THREE.PMREMGenerator(renderer);
		const environment = reflections.fromScene(studio, 0.04);
		scene.environment = environment.texture;
		scene.environmentIntensity = 0.72;
		studio.dispose();
		reflections.dispose();
		renderer.toneMapping = THREE.ACESFilmicToneMapping;
		const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 30);
		camera.position.set(0, 2.35, 6.6);
		camera.lookAt(0, 1.13, 0);
		const bike = new THREE.Group();
		scene.add(bike, new THREE.HemisphereLight(0xe1ebff, 0x78646a, 2.3));

		const key = new THREE.DirectionalLight(0xffffff, 3);
		key.position.set(2, 5, 4);
		const rimLight = new THREE.DirectionalLight(0xff6678, 2);
		rimLight.position.set(-3, 2, -4);
		scene.add(key, rimLight);

		const paint = new THREE.MeshPhysicalMaterial({ color: 0x20232a, roughness: 0.24, clearcoat: 1 });
		const trim = new THREE.MeshStandardMaterial({ color: 0x17191e, roughness: 0.82 });
		const tire = new THREE.MeshStandardMaterial({ color: 0x111216, roughness: 0.94 });
		const metal = new THREE.MeshStandardMaterial({ color: 0x777c87, roughness: 0.32 });
		const wheels = new THREE.MeshStandardMaterial({ roughness: 0.33 });
		const glass = new THREE.MeshPhysicalMaterial({ color: 0x516174, roughness: 0.2, transparent: true, opacity: 0.72 });
		const headlamp = new THREE.MeshBasicMaterial({ color: 0xddeaff });
		const taillamp = new THREE.MeshBasicMaterial({ color: 0xff3348 });
		const gold = new THREE.MeshStandardMaterial({ color: 0xaa752a, metalness: 0.68, roughness: 0.34 });

		// Cross sections vary in height and width to form the tapered, sculpted bodywork.
		function shell(sections: [number, number, number, number, number][], material: THREE.Material) {
			const contour = [[-1, 0.16], [-0.82, 0], [0.82, 0], [1, 0.16], [0.94, 0.71], [0.66, 0.96], [0, 1], [-0.66, 0.96], [-0.94, 0.71]];
			const vertices: number[] = [];
			const indices: number[] = [];
			const ring = contour.length;
			for (const [x, low, high, width, crown] of sections) {
				for (const [z, y] of contour) vertices.push(x - crown * y, low + (high - low) * y, z * width);
			}
			for (let i = 0; i < sections.length - 1; i++) {
				for (let j = 0; j < ring; j++) {
					const a = i * ring + j;
					const b = i * ring + (j + 1) % ring;
					indices.push(a, a + ring, b, b, a + ring, b + ring);
				}
			}
			const end = (sections.length - 1) * ring;
			for (let j = 1; j < ring - 1; j++) indices.push(0, j, j + 1, end, end + j + 1, end + j);
			const geometry = new THREE.BufferGeometry();
			geometry.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
			geometry.setIndex(indices);
			geometry.computeVertexNormals();
			bike.add(new THREE.Mesh(geometry, material));
		}

		function panel(points: [number, number][], width: number, material: THREE.Material, bevel = 0.045, offset = 0) {
			const shape = new THREE.Shape();
			points.forEach(([x, y], index) => index ? shape.lineTo(x, y) : shape.moveTo(x, y));
			shape.closePath();
			const geometry = new THREE.ExtrudeGeometry(shape, {
				depth: width, bevelEnabled: true, bevelSize: bevel, bevelThickness: bevel, bevelSegments: 2
			});
			geometry.translate(0, 0, offset - width / 2);
			bike.add(new THREE.Mesh(geometry, material));
		}

		function tube(from: THREE.Vector3, to: THREE.Vector3, radius: number, material: THREE.Material) {
			const axis = to.clone().sub(from);
			const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, axis.length(), 12), material);
			mesh.position.copy(from).addScaledVector(axis, 0.5);
			mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), axis.normalize());
			bike.add(mesh);
		}

		for (const x of [-1.12, 1.12]) {
			const wheel = new THREE.Group();
			wheel.position.set(x, 0.43, 0);
			bike.add(wheel);
			wheel.add(new THREE.Mesh(new THREE.TorusGeometry(0.345, 0.084, 16, 48), tire));
			for (const z of [-0.075, 0.075]) {
				const lip = new THREE.Mesh(new THREE.TorusGeometry(0.272, 0.035, 12, 40), wheels);
				lip.position.z = z;
				wheel.add(lip);
			}
			for (let spoke = 0; spoke < 8; spoke++) {
				const pivot = new THREE.Group();
				pivot.rotation.z = spoke * Math.PI / 4;
				const bar = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.034, 0.1), wheels);
				bar.position.x = 0.15;
				pivot.add(bar);
				wheel.add(pivot);
			}
			const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.083, 0.083, 0.23, 20), metal);
			hub.rotation.x = Math.PI / 2;
			wheel.add(hub);
			const brake = new THREE.Mesh(new THREE.RingGeometry(0.14, 0.217, 48), metal);
			brake.position.z = 0.124;
			wheel.add(brake);
			const tread = new THREE.InstancedMesh(new THREE.BoxGeometry(0.034, 0.021, 0.071), trim, 48);
			const block = new THREE.Object3D();
			for (let i = 0; i < tread.count; i++) {
				const theta = i * Math.PI * 2 / tread.count;
				block.position.set(0.418 * Math.cos(theta), 0.418 * Math.sin(theta), i % 2 ? 0.033 : -0.033);
				block.rotation.set(0, i % 2 ? 0.28 : -0.28, theta + Math.PI / 2);
				block.updateMatrix();
				tread.setMatrixAt(i, block.matrix);
			}
			wheel.add(tread);
		}

		shell([[-1.47, 1.02, 1.16, 0.13, 0], [-1.2, 0.83, 1.22, 0.25, 0], [-0.74, 0.66, 1.19, 0.31, 0], [-0.2, 0.52, 0.99, 0.31, 0], [0.48, 0.48, 0.82, 0.29, 0], [0.78, 0.56, 0.89, 0.17, 0]], paint);
		shell([[-1.41, 1.15, 1.22, 0.14, 0], [-1.24, 1.17, 1.31, 0.24, 0], [-0.83, 1.16, 1.32, 0.27, 0], [-0.63, 1.12, 1.27, 0.25, 0], [-0.51, 1.06, 1.16, 0.28, 0], [-0.14, 0.99, 1.09, 0.27, 0], [0.02, 0.99, 1.04, 0.18, 0]], trim);
		shell([[0.34, 0.67, 1.17, 0.19, 0], [0.58, 0.61, 1.55, 0.3, 0.1], [0.88, 0.75, 1.63, 0.34, 0.12], [1.13, 1.04, 1.53, 0.28, 0.1], [1.35, 1.15, 1.37, 0.13, 0.04]], paint);
		shell([[0.96, 1.44, 1.98, 0.16, 0.38], [1.02, 1.45, 2.01, 0.17, 0.38], [1.045, 1.47, 1.98, 0.13, 0.38]], glass);
		panel([[0.78, 0.83], [0.99, 0.94], [1.27, 0.92], [1.48, 0.76], [1.22, 0.82]], 0.22, paint, 0.025);
		for (const side of [-1, 1]) {
			panel([[0.81, 1.28], [1.26, 1.31], [1.28, 1.21], [1.06, 1.14], [0.91, 1.18]], 0.06, trim, 0.018, side * 0.264);
			panel([[0.88, 1.25], [1.24, 1.285], [1.235, 1.25], [1.02, 1.21]], 0.018, headlamp, 0.008, side * 0.3);
			panel([[-0.87, 0.76], [-0.56, 0.79], [-0.25, 0.66], [0.44, 0.68], [0.63, 0.77], [0.61, 0.63], [0.38, 0.57], [-0.45, 0.59]], 0.07, trim, 0.026, side * 0.29);
			panel([[-1.22, 1.115], [-0.87, 1.115], [-0.53, 1.015], [-0.86, 1.06]], 0.018, metal, 0.008, side * 0.259);
			panel([[-1.32, 1.04], [-1.13, 1.08], [-1.16, 1.01], [-1.32, 0.99]], 0.025, taillamp, 0.008, side * 0.228);
			tube(new THREE.Vector3(1.12, 0.43, side * 0.15), new THREE.Vector3(0.76, 1.36, side * 0.15), 0.037, metal);
			tube(new THREE.Vector3(-1.08, 0.46, side * 0.19), new THREE.Vector3(-0.81, 1.04, side * 0.19), 0.049, metal);
			tube(new THREE.Vector3(0.62, 1.54, 0), new THREE.Vector3(0.42, 1.64, side * 0.37), 0.028, trim);
			tube(new THREE.Vector3(0.48, 1.63, side * 0.25), new THREE.Vector3(0.37, 1.92, side * 0.47), 0.014, metal);
			panel([[0.26, 1.89], [0.27, 1.99], [0.45, 2.03], [0.53, 1.94], [0.45, 1.87]], 0.075, trim, 0.025, side * 0.47);
			tube(new THREE.Vector3(-1.09, 0.78, side * 0.24), new THREE.Vector3(-0.98, 1.02, side * 0.24), 0.037, gold);
		}
		tube(new THREE.Vector3(-1.34, 0.61, 0.25), new THREE.Vector3(-0.46, 0.52, 0.25), 0.074, trim);

		const observer = new ResizeObserver(() => {
			const { clientWidth, clientHeight } = surface;
			if (!clientWidth || !clientHeight) return;
			renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
			renderer.setSize(clientWidth, clientHeight, false);
			camera.aspect = clientWidth / clientHeight;
			camera.position.z = Math.max(5.85, 7 / camera.aspect);
			camera.lookAt(0, 1.05, 0);
			camera.updateProjectionMatrix();
		});
		observer.observe(surface);

		paused = matchMedia('(prefers-reduced-motion: reduce)').matches;
		let previous = 0;
		renderer.setAnimationLoop((time) => {
			if (!paused && previous) angle += Math.min(time - previous, 50) * 0.00055;
			previous = time;
			bike.rotation.y = angle;
			paint.roughness = matte ? 0.87 : 0.22;
			paint.clearcoat = matte ? 0.01 : 1;
			wheels.color.set(wheelColour);
			renderer.render(scene, camera);
		});

		return () => {
			observer.disconnect();
			renderer.setAnimationLoop(null);
			bike.traverse((object) => {
				if (object instanceof THREE.Mesh) object.geometry.dispose();
			});
			for (const material of [paint, trim, tire, metal, wheels, glass, headlamp, taillamp, gold]) material.dispose();
			environment.dispose();
			renderer.dispose();
		};
	});
</script>

<div class="stage">
	{#if unavailable}
		<p class="muted">3D preview is unavailable on this device. See the shop photos below.</p>
	{:else}
		<button type="button" class="viewer" aria-label={paused ? 'Resume bike rotation' : 'Pause bike rotation'} onclick={() => (paused = !paused)}>
			<canvas bind:this={canvas} aria-hidden="true"></canvas>
			<span class="playback">{paused ? 'Resume rotation' : 'Pause rotation'}</span>
		</button>
	{/if}
</div>

<style>
	.stage {
		overflow: hidden;
		border: 1px solid var(--line);
		border-radius: 8px;
		background: radial-gradient(ellipse at 50% 65%, #393b46, #17191f 62%, #101115);
	}

	.stage p { padding: 24px; }

	.viewer {
		position: relative;
		display: block;
		width: 100%;
		padding: 0;
		border: 0;
		background: none;
		color: var(--text);
		cursor: pointer;
	}

	canvas {
		display: block;
		width: 100%;
		height: clamp(245px, 45vw, 420px);
	}

	.playback {
		position: absolute;
		right: 12px;
		bottom: 12px;
		padding: 6px 10px;
		border-radius: 4px;
		background: var(--bg);
		font-size: 0.85rem;
	}
</style>
