/* SOLAK - Real-Time 3D WebGL Hardware Engine & Spatial Parallax Sequencer */

document.addEventListener('DOMContentLoaded', () => {
  
  // 1. CURSOR GLOW FOLLOWERS SPOTLIGHT (LERP FOLLOW)
  const cursorGlow = document.getElementById('cursorGlow');
  let mouseX = window.innerWidth / 2;
  let mouseY = window.innerHeight / 2;
  let glowX = mouseX;
  let glowY = mouseY;

  window.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
  });

  // 2. VERTICAL SCROLL PROGRESS GAUGE
  const gaugeBar = document.getElementById('gaugeBar');
  const gaugeText = document.getElementById('gaugeText');

  const updateScrollGauge = (progress) => {
    const pct = Math.min(Math.max(Math.round(progress * 100), 0), 100);
    if (gaugeBar) gaugeBar.style.height = `${pct}%`;
    if (gaugeText) gaugeText.textContent = `${pct}%`;
  };

  // 3. STICKY NAVBAR SCROLL SENSING
  const navbar = document.getElementById('navbar');
  const updateNavbar = () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  };

  // =========================================================
  // 4. THREE.JS REAL-TIME 3D WEBGL HARDWARE ENGINE
  // =========================================================
  const canvas = document.getElementById('threeCanvas');
  let scene, camera, renderer;
  let hardwareGroup;
  let meshSolar, meshTp4056, meshBattery, meshRtc, meshEsp32, meshRelay;
  let componentMeshes = [];

  // Helper Material Factory (Green PCB Baseboard Traces as requested)
  const matPcbBase = new THREE.MeshStandardMaterial({ color: 0x090d16, roughness: 0.25, metalness: 0.75, transparent: false });
  const matPcbTraces = new THREE.MeshStandardMaterial({ color: 0x34d399, roughness: 0.1, metalness: 0.9, emissive: 0x059669, emissiveIntensity: 0.15 }); // GREEN PCB TRACES
  const matBrushedAluminum = new THREE.MeshStandardMaterial({ color: 0xcbd5e1, metalness: 0.95, roughness: 0.15, transparent: false });
  const matGoldPlated = new THREE.MeshStandardMaterial({ color: 0xfbbf24, metalness: 0.95, roughness: 0.1, transparent: false });
  const matBlackPlastic = new THREE.MeshStandardMaterial({ color: 0x0f172a, roughness: 0.6, metalness: 0.2, transparent: false });
  const matSolderMetal = new THREE.MeshStandardMaterial({ color: 0xe2e8f0, metalness: 0.95, roughness: 0.1, transparent: false });

  // Texture Loader for Solar Panel Wafer
  const textureLoader = (typeof THREE !== 'undefined') ? new THREE.TextureLoader() : null;

  function loadTextureMaterial(imagePath, roughness = 0.2, metalness = 0.5) {
    if (!textureLoader) return new THREE.MeshStandardMaterial({ color: 0x1e293b, roughness, metalness });
    const tex = textureLoader.load(imagePath);
    tex.wrapS = THREE.ClampToEdgeWrapping;
    tex.wrapT = THREE.ClampToEdgeWrapping;
    return new THREE.MeshStandardMaterial({
      map: tex,
      roughness: roughness,
      metalness: metalness
    });
  }

  // A. REAL 3D SOLAR PANEL
  function create3DSolarPanel() {
    const group = new THREE.Group();

    // Aluminum Outer Frame Channels
    const frameGeo = new THREE.BoxGeometry(1.85, 0.14, 0.08);
    const topBar = new THREE.Mesh(frameGeo, matBrushedAluminum); topBar.position.set(0, 0, 0.92); group.add(topBar);
    const botBar = new THREE.Mesh(frameGeo, matBrushedAluminum); botBar.position.set(0, 0, -0.92); group.add(botBar);
    const sideGeo = new THREE.BoxGeometry(0.08, 0.14, 1.85);
    const leftBar = new THREE.Mesh(sideGeo, matBrushedAluminum); leftBar.position.set(-0.92, 0, 0); group.add(leftBar);
    const rightBar = new THREE.Mesh(sideGeo, matBrushedAluminum); rightBar.position.set(0.92, 0, 0); group.add(rightBar);

    // Photo-Textured Solar Wafer Surface
    const solarMat = loadTextureMaterial('assets/tex-solar.jpg', 0.1, 0.8);
    const wafer = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 1.8), solarMat);
    wafer.rotation.x = -Math.PI / 2;
    wafer.position.y = 0.07;
    group.add(wafer);

    // Clear Glass Protective Top Plate
    const glassMat = new THREE.MeshPhysicalMaterial({ color: 0xffffff, transparent: true, opacity: 0.25, roughness: 0.0, transmission: 0.9, clearcoat: 1.0 });
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(1.82, 1.82), glassMat);
    glass.rotation.x = -Math.PI / 2;
    glass.position.y = 0.08;
    glass.userData.isGlass = true;
    group.add(glass);

    // Rear Junction Box
    const jBox = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.15, 0.35), matBlackPlastic);
    jBox.position.set(0, -0.1, 0);
    group.add(jBox);

    return group;
  }

  // B. SOLID OPAQUE 3D TP4056 CHARGER MODULE (COLOR: #0f557e)
  function create3DTP4056() {
    const group = new THREE.Group();

    // 1. Petrol Blue FR4 Circuit Board (#0f557e)
    const matPcbTp = new THREE.MeshStandardMaterial({ color: 0x0f557e, roughness: 0.25, metalness: 0.4, transparent: false, opacity: 1.0 });
    const board = new THREE.Mesh(new THREE.BoxGeometry(0.90, 0.08, 0.70), matPcbTp);
    group.add(board);

    // 2. Gold Connection Solder Pads
    const padMat = new THREE.MeshStandardMaterial({ color: 0xfbbf24, metalness: 0.95, transparent: false });
    [[-0.38, -0.28], [-0.38, 0.28], [0.38, -0.28], [0.38, 0.28], [0.38, -0.1], [0.38, 0.1]].forEach(pos => {
      const pad = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.09, 0.08), padMat);
      pad.position.set(pos[0], 0.04, pos[1]);
      group.add(pad);
    });

    // 3. Stainless Steel Micro-USB Socket & Tongue
    const usbBase = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.16, 0.32), matSolderMetal);
    usbBase.position.set(-0.32, 0.09, 0);
    group.add(usbBase);

    const usbTongue = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.04, 0.2), matBlackPlastic);
    usbTongue.position.set(-0.35, 0.09, 0);
    group.add(usbTongue);

    // 4. TP4056 SOP-8 Controller Chip & Lead Pins
    const icTp = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.08, 0.22), matBlackPlastic);
    icTp.position.set(0.02, 0.07, -0.12);
    group.add(icTp);

    for (let x = -0.08; x <= 0.08; x += 0.05) {
      const p1 = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.04, 0.06), matSolderMetal);
      p1.position.set(x + 0.02, 0.05, -0.25);
      const p2 = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.04, 0.06), matSolderMetal);
      p2.position.set(x + 0.02, 0.05, 0.01);
      group.add(p1);
      group.add(p2);
    }

    // 5. DW01 Protection IC & MOSFET
    const icDw = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.06, 0.14), matBlackPlastic);
    icDw.position.set(0.24, 0.06, -0.15);
    group.add(icDw);

    const icMos = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.06, 0.15), matBlackPlastic);
    icMos.position.set(0.24, 0.06, 0.12);
    group.add(icMos);

    // 6. Dual Red & Green Status LEDs
    const ledRed = new THREE.Mesh(new THREE.SphereGeometry(0.045, 16, 16), new THREE.MeshStandardMaterial({ color: 0xef4444, roughness: 0.1, transparent: false }));
    ledRed.position.set(-0.12, 0.08, 0.24);
    group.add(ledRed);

    const ledGreen = new THREE.Mesh(new THREE.SphereGeometry(0.045, 16, 16), new THREE.MeshStandardMaterial({ color: 0x10b981, roughness: 0.1, transparent: false }));
    ledGreen.position.set(0.02, 0.08, 0.24);
    group.add(ledGreen);

    return group;
  }

  // C. REAL 3D 18650 BATTERY (Iconic Pink Li-Ion Shrink Wrapper)
  function create3D18650Battery() {
    const group = new THREE.Group();

    // ABS Plastic Cradle
    const cradle = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.2, 0.95), matBlackPlastic);
    group.add(cradle);

    // Nickel Spring Contacts
    const spring = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.09, 0.14, 16), matBrushedAluminum);
    spring.rotation.z = Math.PI / 2;
    spring.position.set(-0.92, 0.26, 0);
    group.add(spring);

    // Iconic Pink 18650 Li-Ion Battery Shrink Wrapper (#ec4899)
    const pinkCellMat = new THREE.MeshPhysicalMaterial({
      color: 0xec4899,
      roughness: 0.15,
      metalness: 0.45,
      clearcoat: 1.0,
      clearcoatRoughness: 0.08,
      transparent: false
    });
    const cell = new THREE.Mesh(new THREE.CylinderGeometry(0.36, 0.36, 1.85, 32), pinkCellMat);
    cell.rotation.z = Math.PI / 2;
    cell.position.y = 0.26;
    group.add(cell);

    // Black Sleeve Ring Band
    const bandMat = new THREE.MeshStandardMaterial({ color: 0x020617, roughness: 0.4, transparent: false });
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.365, 0.365, 0.25, 32), bandMat);
    band.rotation.z = Math.PI / 2;
    band.position.set(0.2, 0.26, 0);
    group.add(band);

    // Positive Button Top Tip
    const tip = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.08, 16), matBrushedAluminum);
    tip.rotation.z = Math.PI / 2;
    tip.position.set(0.96, 0.26, 0);
    group.add(tip);

    return group;
  }

  // D. CLEAN 3D PROCEDURAL DS3231 RTC
  function create3DDS3231() {
    const group = new THREE.Group();

    // 1. Royal Blue FR4 PCB Board Base
    const matBluePcb = new THREE.MeshStandardMaterial({ color: 0x1d4ed8, roughness: 0.3, metalness: 0.3, transparent: false });
    const board = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.08, 0.80), matBluePcb);
    group.add(board);

    // 2. CR2032 Coin Cell Battery Holder & Coin Cell
    const socket = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.26, 0.12, 24), matBlackPlastic);
    socket.position.set(-0.1, 0.08, -0.05);
    group.add(socket);

    const coin = new THREE.Mesh(new THREE.CylinderGeometry(0.23, 0.23, 0.08, 24), matSolderMetal);
    coin.position.set(-0.1, 0.13, -0.05);
    group.add(coin);

    const clip = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.04, 0.42), matSolderMetal);
    clip.position.set(-0.1, 0.18, -0.05);
    group.add(clip);

    // 3. DS3231 SOIC-16 Controller Chip & J-Leads
    const icRtc = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.09, 0.22), matBlackPlastic);
    icRtc.position.set(0.20, 0.07, -0.15);
    group.add(icRtc);

    for (let x = -0.10; x <= 0.10; x += 0.035) {
      const l1 = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.03, 0.05), matSolderMetal);
      l1.position.set(x + 0.20, 0.04, -0.28);
      const l2 = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.03, 0.05), matSolderMetal);
      l2.position.set(x + 0.20, 0.04, -0.02);
      group.add(l1);
      group.add(l2);
    }

    // 4. 32.768kHz Crystal Oscillator Cylinder
    const crystal = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.055, 0.24, 16), matSolderMetal);
    crystal.rotation.z = Math.PI / 2;
    crystal.position.set(-0.1, 0.08, 0.26);
    group.add(crystal);

    // 5. 6 Gold I2C Header Pins
    for (let z = -0.30; z <= 0.30; z += 0.12) {
      const pin = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.22, 0.04), matGoldPlated);
      pin.position.set(-0.38, 0.04, z);
      group.add(pin);
    }

    return group;
  }

  // E. REAL 3D ESP32 MCU (Standard 1.80 x 1.25 Dev Board)
  function create3DESP32() {
    const group = new THREE.Group();

    // Photo-Textured ESP32 PCB Board
    const espMat = loadTextureMaterial('assets/tex-esp32.jpg', 0.25, 0.5);
    const board = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.08, 1.25), espMat);
    group.add(board);

    // 3D Silver Metal RF Shield (ESP-WROOM-32)
    const shield = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.16, 0.85), matBrushedAluminum);
    shield.position.set(-0.25, 0.12, 0);
    group.add(shield);

    // Dual 15-Pin Gold Header Rows
    for (let x = -0.75; x <= 0.75; x += 0.11) {
      const pinL = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.26, 0.06), matGoldPlated);
      pinL.position.set(x, 0.05, 0.54);
      const pinR = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.26, 0.06), matGoldPlated);
      pinR.position.set(x, 0.05, -0.54);
      group.add(pinL);
      group.add(pinR);
    }

    return group;
  }

  // F. HIGH-DETAIL SOLID 5V RELAY MODULE
  function create3DRelayPump() {
    const group = new THREE.Group();

    // 1. Dark FR4 PCB Baseboard
    const matRelayPcb = new THREE.MeshStandardMaterial({ color: 0x0f172a, roughness: 0.4, metalness: 0.3, transparent: false, opacity: 1.0 });
    const pcb = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.08, 0.85), matRelayPcb);
    group.add(pcb);

    // 2. Solid Opaque Songle Cyan Relay Block
    const boxMat = new THREE.MeshStandardMaterial({
      color: 0x0284c7,
      roughness: 0.15,
      metalness: 0.1,
      transparent: false,
      opacity: 1.0
    });
    const relay = new THREE.Mesh(new THREE.BoxGeometry(0.58, 0.48, 0.50), boxMat);
    relay.position.set(-0.12, 0.28, 0);
    group.add(relay);

    // Songle Top Brand Stamp Plate
    const stampMat = new THREE.MeshStandardMaterial({ color: 0xf8fafc, roughness: 0.2, transparent: false });
    const stamp = new THREE.Mesh(new THREE.PlaneGeometry(0.52, 0.44), stampMat);
    stamp.rotation.x = -Math.PI / 2;
    stamp.position.set(-0.12, 0.525, 0);
    group.add(stamp);

    // 3. Blue 3-Port Screw Terminal Block
    const termMat = new THREE.MeshStandardMaterial({ color: 0x1d4ed8, roughness: 0.3, transparent: false });
    const terminal = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.32, 0.52), termMat);
    terminal.position.set(0.28, 0.20, 0);
    group.add(terminal);

    // 3 Brass Elevator Terminal Screws
    [-0.16, 0, 0.16].forEach(z => {
      const screw = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.08, 12), matGoldPlated);
      screw.position.set(0.28, 0.37, z);
      group.add(screw);
    });

    // 4. DIP-4 EL817 Optocoupler Isolation IC
    const optoMat = new THREE.MeshStandardMaterial({ color: 0xe2e8f0, roughness: 0.4, transparent: false });
    const opto = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.08, 0.16), optoMat);
    opto.position.set(-0.30, 0.08, 0.28);
    group.add(opto);

    // 5. 1N4007 Flyback Protection Diode & Silver Stripe
    const diode = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.18, 12), matBlackPlastic);
    diode.rotation.z = Math.PI / 2;
    diode.position.set(0.06, 0.07, 0.28);
    group.add(diode);

    const stripeMat = new THREE.MeshStandardMaterial({ color: 0xe2e8f0, roughness: 0.2, transparent: false });
    const stripe = new THREE.Mesh(new THREE.CylinderGeometry(0.036, 0.036, 0.04, 12), stripeMat);
    stripe.rotation.z = Math.PI / 2;
    stripe.position.set(0.11, 0.07, 0.28);
    group.add(stripe);

    // 6. NPN Switching Transistor
    const trans = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.12, 16), matBlackPlastic);
    trans.position.set(-0.30, 0.09, -0.25);
    group.add(trans);

    // 7. Green Relay Status LED Indicator Dome
    const ledGreen = new THREE.Mesh(new THREE.SphereGeometry(0.04, 12, 12), new THREE.MeshStandardMaterial({ color: 0x10b981, roughness: 0.1, transparent: false }));
    ledGreen.position.set(-0.12, 0.08, -0.28);
    group.add(ledGreen);

    // 8. 3-Pin Input Header Row
    for (let z = -0.12; z <= 0.12; z += 0.12) {
      const pin = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.20, 0.04), matGoldPlated);
      pin.position.set(-0.40, 0.04, z);
      group.add(pin);
    }

    return group;
  }

  function initThreeJS() {
    if (!canvas || typeof THREE === 'undefined') {
      setTimeout(initThreeJS, 150);
      return;
    }

    const width = 460;
    const height = 460;

    // Scene
    scene = new THREE.Scene();

    // Camera
    camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 1000);
    camera.position.set(0, 4.8, 6.8);
    camera.lookAt(0, 0, 0);

    // Renderer with ACES Tone Mapping
    renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    if (renderer.toneMapping) {
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.25;
    }

    // Studio Lighting System
    const hemiLight = new THREE.HemisphereLight(0xffffff, 0x080c14, 2.5);
    scene.add(hemiLight);

    const sunLight = new THREE.DirectionalLight(0xffffff, 3.5);
    sunLight.position.set(5, 10, 7);
    scene.add(sunLight);

    const emeraldLight = new THREE.PointLight(0x34d399, 4.5, 20); // GREEN SPOTLIGHT FOR PCB BASEBOARD
    emeraldLight.position.set(-4, 4, -4);
    scene.add(emeraldLight);

    const amberLight = new THREE.PointLight(0xfbbf24, 4.5, 20);
    amberLight.position.set(4, 4, 4);
    scene.add(amberLight);

    // Hardware Group Container
    hardwareGroup = new THREE.Group();
    scene.add(hardwareGroup);

    // Green PCB Baseboard
    const pcbGeo = new THREE.BoxGeometry(4.4, 0.18, 4.4);
    const meshPcb = new THREE.Mesh(pcbGeo, matPcbBase);
    hardwareGroup.add(meshPcb);

    // Green Traces Wireframe
    const traceGeo = new THREE.PlaneGeometry(4.2, 4.2);
    const meshTraces = new THREE.Mesh(traceGeo, matPcbTraces);
    meshTraces.rotation.x = -Math.PI / 2;
    meshTraces.position.y = 0.1;
    hardwareGroup.add(meshTraces);

    // Instantiate 6 Proportional 3D Component Models
    meshSolar = create3DSolarPanel();
    meshSolar.position.set(-1.2, 0.25, -1.2);
    hardwareGroup.add(meshSolar);

    meshTp4056 = create3DTP4056();
    meshTp4056.position.set(1.4, 0.2, -1.4);
    hardwareGroup.add(meshTp4056);

    meshBattery = create3D18650Battery();
    meshBattery.position.set(-1.0, 0.2, 1.1);
    hardwareGroup.add(meshBattery);

    meshRtc = create3DDS3231();
    meshRtc.position.set(1.4, 0.2, -0.2);
    hardwareGroup.add(meshRtc);

    meshEsp32 = create3DESP32();
    meshEsp32.position.set(0.0, 0.25, 0.0);
    hardwareGroup.add(meshEsp32);

    meshRelay = create3DRelayPump();
    meshRelay.position.set(1.4, 0.2, 1.2);
    hardwareGroup.add(meshRelay);

    // Store array of 6 3D component meshes
    componentMeshes = [meshSolar, meshTp4056, meshBattery, meshRtc, meshEsp32, meshRelay];
  }

  initThreeJS();

  // =========================================================
  // 5. SPATIAL OPPOSITE 3D MOBILE PARALLAX SCROLL SEQUENCER
  // =========================================================
  let currentScrollY = 0;
  let targetScrollY = 0;

  // LERP Motion Variables for 3D Smartphone Device Frame
  let phoneCurrX = 0;
  let phoneTargetX = 0;
  let phoneCurrY = 0;
  let phoneTargetY = 0;
  let phoneCurrRotY = 0;
  let phoneTargetRotY = 0;
  let phoneCurrRotX = 0;
  let phoneTargetRotX = 0;
  let phoneCurrScale = 1.0;
  let phoneTargetScale = 1.0;

  const heroBg = document.getElementById('heroBg');
  const heroText = document.getElementById('heroText');
  const orb1 = document.getElementById('orb1');
  const orb2 = document.getElementById('orb2');
  const risingLogo = document.getElementById('risingLogo');
  const mechanismSection = document.getElementById('mechanism');
  const appSection = document.getElementById('app');
  const phoneDeviceFrame = document.getElementById('phoneDeviceFrame');

  // Spatial Text Cards
  const spatialCardCommand = document.getElementById('spatialCardCommand'); // Left slot card
  const spatialCardSettings = document.getElementById('spatialCardSettings'); // Left slot card
  const spatialCardEnergy = document.getElementById('spatialCardEnergy');     // Right slot card

  const cards = [
    document.getElementById('mechCard1'),
    document.getElementById('mechCard2'),
    document.getElementById('mechCard3'),
    document.getElementById('mechCard4'),
    document.getElementById('mechCard5'),
    document.getElementById('mechCard6')
  ];

  const pills = [
    document.getElementById('pill1'),
    document.getElementById('pill2'),
    document.getElementById('pill3'),
    document.getElementById('pill4'),
    document.getElementById('pill5'),
    document.getElementById('pill6')
  ];

  const renderLoop = () => {
    targetScrollY = window.scrollY;
    currentScrollY += (targetScrollY - currentScrollY) * 0.12;

    // Cursor Glow Lerp
    glowX += (mouseX - glowX) * 0.12;
    glowY += (mouseY - glowY) * 0.12;
    if (cursorGlow) {
      cursorGlow.style.transform = `translate3d(${glowX}px, ${glowY}px, 0) translate(-50%, -50%)`;
    }

    // Scroll Gauge Calculation
    const maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    const totalProgress = maxScroll > 0 ? currentScrollY / maxScroll : 0;
    updateScrollGauge(totalProgress);

    // HERO MULTI-DEPTH PARALLAX
    if (heroBg) heroBg.style.transform = `translate3d(0, ${currentScrollY * 0.22}px, 0)`;
    if (orb1) orb1.style.transform = `translate3d(0, ${currentScrollY * 0.35}px, 0)`;
    if (orb2) orb2.style.transform = `translate3d(0, ${currentScrollY * 0.15}px, 0)`;

    if (heroText && currentScrollY < 800) {
      heroText.style.transform = `translate3d(0, ${currentScrollY * 0.12}px, 0)`;
      heroText.style.opacity = Math.max(0, 1 - currentScrollY / 550).toFixed(3);
    }

    // REAL-TIME 3D THREE.JS CAMERA ORBIT & SUBTLE SPOTLIGHT LOGIC
    if (mechanismSection && hardwareGroup) {
      const rect = mechanismSection.getBoundingClientRect();
      const sectionHeight = mechanismSection.offsetHeight - window.innerHeight;
      const progress = Math.min(Math.max(-rect.top / sectionHeight, 0), 1);

      // Rotate 3D Hardware Group smoothly in 3D Space
      const targetRotY = progress * Math.PI * 2.2 + (mouseX / window.innerWidth - 0.5) * 0.75;
      const targetRotX = 0.38 + (mouseY / window.innerHeight - 0.5) * 0.45;
      hardwareGroup.rotation.y += (targetRotY - hardwareGroup.rotation.y) * 0.1;
      hardwareGroup.rotation.x += (targetRotX - hardwareGroup.rotation.x) * 0.1;

      // Calculate current active component step index (0 to 5)
      const stepIndex = Math.min(Math.floor(progress * 6), 5);

      // HIGHLIGHT ACTIVE 3D COMPONENT WITH CLEAN SUBTLE SOFT GLOW (0.10)
      componentMeshes.forEach((meshGroup, idx) => {
        if (!meshGroup) return;

        const isActive = (idx === stepIndex);

        const targetY = isActive ? 0.70 : 0.20;
        const targetScale = isActive ? 1.12 : 0.90;

        meshGroup.position.y += (targetY - meshGroup.position.y) * 0.12;
        meshGroup.scale.x += (targetScale - meshGroup.scale.x) * 0.12;
        meshGroup.scale.y += (targetScale - meshGroup.scale.y) * 0.12;
        meshGroup.scale.z += (targetScale - meshGroup.scale.z) * 0.12;

        meshGroup.traverse((child) => {
          if (child.isMesh && child.material) {
            if (isActive) {
              if (child.userData.isGlass) {
                child.material.transparent = true;
                child.material.opacity = 0.25;
              } else {
                child.material.transparent = false;
                child.material.opacity = 1.0;
              }

              if (child.material.emissive) {
                child.material.emissive.setHex(idx === 0 || idx === 1 ? 0xfbbf24 : idx === 3 || idx === 5 ? 0x22d3ee : 0x34d399);
                child.material.emissiveIntensity = 0.10;
              }
            } else {
              child.material.transparent = true;
              child.material.opacity = 0.35;
              if (child.material.emissive) {
                child.material.emissiveIntensity = 0.0;
              }
            }
          }
        });
      });

      // Update Card & Step Pill active state
      cards.forEach((card, i) => {
        if (card) {
          if (i === stepIndex) card.classList.add('active');
          else card.classList.remove('active');
        }
      });

      pills.forEach((pill, i) => {
        if (pill) {
          if (i === stepIndex) pill.classList.add('active');
          else pill.classList.remove('active');
        }
      });
    }

    // =========================================================
    // 6. SPATIAL OPPOSITE 3-SLOT 3D MOBILE SEQUENCER (350VH STICKY RUNWAY)
    // =========================================================
    if (appSection && phoneDeviceFrame) {
      const appRect = appSection.getBoundingClientRect();
      const windowH = window.innerHeight;

      // Calculate scroll progress across the 350vh sticky runway (0.0 to 1.0)
      const sectionHeight = appSection.offsetHeight - windowH;
      const progress = Math.min(Math.max(-appRect.top / sectionHeight, 0), 1);

      // PHASE 0 (0.00 – 0.18): START IN CENTER CORRIDOR (0px) WITH BLACK BOOT SCREEN + LOGO
      if (progress < 0.18) {
        phoneTargetX = 0;
        phoneTargetY = 0;
        phoneTargetRotY = 0;
        phoneTargetRotX = 0;
        phoneTargetScale = 1.05;

        // Hide all spatial cards
        showSpatialCard(null);
        switchAppScreen('boot');
      }
      
      // PHASE 1 (0.18 – 0.48): PHONE GLIDES TO RIGHT SLOT (+380px) -> TEXT CARD ON LEFT (Command Center)
      else if (progress < 0.48) {
        const p1 = (progress - 0.18) / (0.48 - 0.18); // 0 to 1
        
        phoneTargetX = p1 * 380;                              // Move Phone into Right Slot (+380px)
        phoneTargetY = Math.sin(p1 * Math.PI) * -12;
        phoneTargetRotY = p1 * -18;                           // Tilt Phone -18° Y (facing center)
        phoneTargetRotX = Math.sin(p1 * Math.PI) * 6;
        phoneTargetScale = 1.0;

        switchAppScreen('command');

        // Text Card ONLY appears on OPPOSITE side (LEFT SLOT)
        if (p1 > 0.25) {
          showSpatialCard(spatialCardCommand);
        } else {
          showSpatialCard(null);
        }
      }

      // PHASE 2 (0.48 – 0.78): PHONE SWIRLS TO LEFT SLOT (-380px) -> TEXT CARD ON RIGHT (Solar Energy)
      else if (progress < 0.78) {
        const p2 = (progress - 0.48) / (0.78 - 0.48); // 0 to 1

        phoneTargetX = 380 - (p2 * 760);                     // Move Phone from Right Slot (+380px) to Left Slot (-380px)
        phoneTargetY = Math.sin(p2 * Math.PI) * -30;
        phoneTargetRotY = -18 + (p2 * 36);                   // Tilt Phone from -18° Y to +18° Y (facing center)
        phoneTargetRotX = Math.sin(p2 * Math.PI) * 10;
        phoneTargetScale = 1.0 + Math.sin(p2 * Math.PI) * 0.06;

        switchAppScreen('energy');

        // Text Card ONLY appears on OPPOSITE side (RIGHT SLOT)
        if (p2 > 0.2 && p2 < 0.85) {
          showSpatialCard(spatialCardEnergy);
        } else {
          showSpatialCard(null);
        }
      }

      // PHASE 3 (0.78 – 1.00): PHONE GLIDES BACK TO RIGHT SLOT (+380px) -> TEXT CARD ON LEFT (Settings)
      else {
        const p3 = (progress - 0.78) / (1.00 - 0.78); // 0 to 1

        phoneTargetX = -380 + (p3 * 760);                    // Move Phone back to Right Slot (+380px)
        phoneTargetY = 0;
        phoneTargetRotY = 18 - (p3 * 36);                    // Tilt Phone back to -18° Y
        phoneTargetRotX = 0;
        phoneTargetScale = 1.0;

        switchAppScreen('settings');

        // Text Card ONLY appears on OPPOSITE side (LEFT SLOT)
        if (p3 > 0.2) {
          showSpatialCard(spatialCardSettings);
        } else {
          showSpatialCard(null);
        }
      }

      // Smooth LERP Spring Loop Execution
      phoneCurrX += (phoneTargetX - phoneCurrX) * 0.1;
      phoneCurrY += (phoneTargetY - phoneCurrY) * 0.1;
      phoneCurrRotY += (phoneTargetRotY - phoneCurrRotY) * 0.1;
      phoneCurrRotX += (phoneTargetRotX - phoneCurrRotX) * 0.1;
      phoneCurrScale += (phoneTargetScale - phoneCurrScale) * 0.1;

      // Apply 3D Transform to Smartphone Shell
      phoneDeviceFrame.style.transform = `perspective(1200px) translate3d(${phoneCurrX}px, ${phoneCurrY}px, 0) rotateX(${phoneCurrRotX}deg) rotateY(${phoneCurrRotY}deg) scale(${phoneCurrScale})`;
    }

    // Render Real-Time Three.js WebGL Scene
    if (renderer && scene && camera) {
      renderer.render(scene, camera);
    }

    // FOOTER RISING LOGO PARALLAX
    if (risingLogo) {
      const footerDistance = maxScroll - currentScrollY;
      if (footerDistance < 900) {
        const logoOffset = Math.max(0, (footerDistance / 900) * 110);
        const logoScale = 1 + (1 - logoOffset / 110) * 0.08;
        risingLogo.style.transform = `translate3d(0, ${logoOffset}px, 0) scale(${logoScale})`;
      }
    }

    updateNavbar();
    requestAnimationFrame(renderLoop);
  };

  requestAnimationFrame(renderLoop);

  // Helper function to show only ONE active text card on the OPPOSITE side of the 3D Phone
  function showSpatialCard(targetCard) {
    const allSpatialCards = [spatialCardCommand, spatialCardEnergy, spatialCardSettings];
    allSpatialCards.forEach(card => {
      if (card) {
        if (card === targetCard) card.classList.add('active');
        else card.classList.remove('active');
      }
    });
  }

  // App Screen Switcher Selectors (Boot + 3 UI screens)
  const phoneScreens = {
    boot: document.getElementById('phoneScreenBoot'),
    command: document.getElementById('phoneScreen1'),
    energy: document.getElementById('phoneScreen2'),
    settings: document.getElementById('phoneScreen3')
  };

  function switchAppScreen(screenKey) {
    Object.keys(phoneScreens).forEach(key => {
      if (phoneScreens[key]) {
        if (key === screenKey) phoneScreens[key].classList.add('active');
        else phoneScreens[key].classList.remove('active');
      }
    });
  }

  // 7. 3D CARD MAGNETIC HOVER PHYSICS
  const glassCards = document.querySelectorAll('.glass-card, .mech-card, .custom-card');
  glassCards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const cardRect = card.getBoundingClientRect();
      const cardX = e.clientX - cardRect.left;
      const cardY = e.clientY - cardRect.top;
      const centerX = cardRect.width / 2;
      const centerY = cardRect.height / 2;
      
      const rotateX = ((cardY - centerY) / centerY) * -8;
      const rotateY = ((cardX - centerX) / centerX) * 8;
      
      card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-4px)`;
    });

    card.addEventListener('mouseleave', () => {
      card.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg) translateY(0px)`;
    });
  });

  // 8. APPEARING SCROLL REVEAL OBSERVER
  const accordionItems = document.querySelectorAll('.accordion-item');
  accordionItems.forEach((item, idx) => {
    item.classList.add('reveal-slide-right');
    item.classList.add(`stagger-${(idx % 3) + 1}`);
  });

  const generalReveals = document.querySelectorAll('.hero-badge, .hero-headline, .hero-subheadline, .hero-actions, .hero-status-bar, .section-header-tag');
  generalReveals.forEach(el => el.classList.add('reveal'));

  const allReveals = document.querySelectorAll('.reveal, .reveal-zoom, .reveal-slide-left, .reveal-slide-right');

  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
      }
    });
  }, { threshold: 0.1 });

  allReveals.forEach(el => revealObserver.observe(el));

  // 9. ACCORDION EXPANSION
  const accordionHeaders = document.querySelectorAll('.accordion-header');
  accordionHeaders.forEach(header => {
    header.addEventListener('click', () => {
      const item = header.parentElement;
      const isActive = item.classList.contains('active');

      document.querySelectorAll('.accordion-item').forEach(i => i.classList.remove('active'));

      if (!isActive) item.classList.add('active');
    });
  });

});
