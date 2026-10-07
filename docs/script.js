const config = {
  anims: {
    live: {
      interval: 1000,
      getProgress: (now) => {
        const t = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
        return t / 86400;
      },
    },
    cycle: {
      interval: 50,
      getProgress: (now) => {
        const t = now.getSeconds() * 1000 + now.getMilliseconds();
        return t / 60000;
      },
    },
  },
  states: [
    { at: 0, name: "night", colours: {
      sky1: "#060a1a", sky2: "#141d3a", sun: "#e8e6df",
      l10: "#232c47", l9: "#202842", l8: "#1d243c", l7: "#1a2036",
      l6: "#171c30", l5: "#14182a", l4: "#111524", l3: "#0e111e",
      l2: "#0b0e18", l1: "#080a12",
      starsOpacity: "1" } },
    { at: 6, name: "sunrise", colours: {
      sky1: "#6b6fae", sky2: "#ffb997", sun: "#fff3d6",
      l10: "#8a7fa8", l9: "#7d739c", l8: "#706790", l7: "#635b84",
      l6: "#564f78", l5: "#49436c", l4: "#3c3760", l3: "#2f2b54",
      l2: "#221f48", l1: "#15133c",
      starsOpacity: "0.2" } },
    { at: 12, name: "day", colours: {
      sky1: "#3a8fd9", sky2: "#bfe3ff", sun: "#ffdf5e",
      l10: "#b9cbdd", l9: "#a9bccd", l8: "#99adbd", l7: "#899ead",
      l6: "#798f9d", l5: "#69808d", l4: "#59717d", l3: "#49626d",
      l2: "#39535d", l1: "#29444d",
      starsOpacity: "0" } },
    { at: 18, name: "sunset", colours: {
      sky1: "#2b2d5c", sky2: "#ff6b35", sun: "#ff9a3c",
      l10: "#7a4a5a", l9: "#6d4252", l8: "#603a4a", l7: "#533242",
      l6: "#462a3a", l5: "#392232", l4: "#2c1a2a", l3: "#1f1222",
      l2: "#150c1a", l1: "#0d0712",
      starsOpacity: "0.3" } },
  ],
};

const root = document.documentElement;
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
let animMode = localStorage.getItem("skyline-theme") || "live";
if (!["live", "cycle", "sunrise", "day", "sunset", "night"].includes(animMode)) animMode = "live";

config.states.push({ ...config.states[0], name: "end", at: 24 });

let animation;
let layerEls = [];
const parallaxDepths = [
  ["layer11", 0.9],
  ["layer10", 0.8], ["layer10-lights", 0.8],
  ["layer9", 0.7], ["layer9-lights", 0.7],
  ["layer8", 0.6], ["layer8-lights", 0.6],
  ["layer7", 0.5], ["layer7-lights", 0.5],
  ["layer6", 0.4], ["layer6-lights", 0.4],
  ["layer5", 0.3], ["layer5-lights", 0.3],
  ["layer4", 0.2], ["layer4-lights", 0.2],
  ["layer3", 0.15], ["layer3-lights", 0.15],
  ["layer2", 0.08], ["layer2-lights", 0.08],
  ["layer1", 0], ["layer1-lights", 0],
];
let scrollPos = 0;

// Window lights: white by day, warm yellow at night. No fading — each
// window flips at its own random time inside the sunset/sunrise windows.
const LIGHTS_ON = "#ffd166";
const LIGHTS_OFF = "#ffffff";
const SUNSET_START = 17, SUNSET_END = 19;
const SUNRISE_START = 5, SUNRISE_END = 8;
let lightEls = [];

function hexToRgb(hex) {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : null;
}

function lerp(start, end, t) {
  return (1 - t) * start + t * end;
}

function applyColour(key, value) {
  if (key === "starsOpacity") root.style.setProperty("--stars-opacity", value);
  else root.style.setProperty("--" + key, value);
}

function getProgress() {
  return config.anims[animMode].getProgress(new Date());
}

function updateAnim() {
  const progress = getProgress() * 24;
  const nextIndex = config.states.findIndex((f) => f.at !== 0 && progress < f.at);
  const lastState = config.states[nextIndex - 1];
  const nextState = config.states[nextIndex];
  const t = (progress - lastState.at) / (nextState.at - lastState.at);

  for (const key of Object.keys(lastState.colours)) {
    if (key === "lights" || key === "lightsOpacity") continue;
    if (key === "starsOpacity") {
      applyColour(key, String(lerp(parseFloat(lastState.colours[key]), parseFloat(nextState.colours[key]), t).toFixed(3)));
      continue;
    }
    const a = hexToRgb(lastState.colours[key]);
    const b = hexToRgb(nextState.colours[key]);
    const rgb = [0, 1, 2].map((i) => Math.round(lerp(a[i], b[i], t)));
    applyColour(key, `rgb(${rgb.join(",")})`);
  }
  placeOrbs(progress);
  updateLights(progress);
}

function placeOrbs(hour) {
  const sun = document.getElementById("sun");
  const moon = document.getElementById("moon");
  if (!sun || !moon) return;
  const dayT = (hour - 6) / 12;
  const nightT = hour < 6 ? (hour + 24 - 18) / 12 : (hour - 18) / 12;
  if (dayT >= 0 && dayT <= 1) {
    sun.style.display = "";
    moon.style.display = "none";
    root.style.setProperty("--sun-h", (-Math.cos(dayT * Math.PI)).toFixed(3));
    root.style.setProperty("--sun-v", Math.sin(dayT * Math.PI).toFixed(3));
  } else {
    sun.style.display = "none";
    moon.style.display = "";
    root.style.setProperty("--sun-h", (-Math.cos(nightT * Math.PI)).toFixed(3));
    root.style.setProperty("--sun-v", (Math.sin(nightT * Math.PI) * 0.6).toFixed(3));
  }
}

function updateLights(hour) {
  for (const l of lightEls) {
    let on;
    if (hour >= SUNSET_END || hour < SUNRISE_START) on = true;
    else if (hour >= SUNRISE_END && hour < SUNSET_START) on = false;
    else if (hour >= SUNSET_START) on = hour >= l.sunsetAt;
    else on = hour < l.sunriseAt;
    if (on !== l.on) {
      l.on = on;
      l.el.classList.toggle("on", on);
    }
  }
}

function startAnim() {
  updateAnim();
  animation = setInterval(updateAnim, config.anims[animMode].interval);
}

function endAnim() {
  clearInterval(animation);
}

function applyStatic(name) {
  const state = config.states.find((s) => s.name === name);
  if (!state) return;
  for (const [key, val] of Object.entries(state.colours)) {
    if (key === "lights" || key === "lightsOpacity") continue;
    if (key === "starsOpacity") applyColour(key, val);
    else applyColour(key, `rgb(${hexToRgb(val).join(",")})`);
  }
  const rep = { sunrise: 6.75, day: 12, sunset: 18, night: 0 }[name] ?? 12;
  placeOrbs(rep);
  updateLights(rep);
}

function setTheme(slug) {
  endAnim();
  document.querySelectorAll("[data-theme]").forEach((b) => {
    const on = b.dataset.theme === slug;
    if (on) { b.setAttribute("data-active", ""); b.setAttribute("aria-pressed", "true"); }
    else { b.removeAttribute("data-active"); b.setAttribute("aria-pressed", "false"); }
  });
  localStorage.setItem("skyline-theme", slug);
  if (slug === "live" || slug === "cycle") {
    animMode = slug;
    startAnim();
  } else {
    applyStatic(slug);
  }
}

function setupSvg() {
  const svg = document.querySelector("#svgHost svg");
  if (!svg) return;
  layerEls = parallaxDepths
    .map(([id, scroll]) => {
      const el = svg.querySelector(`#${CSS.escape(id)}`);
      if (!el) return null;
      const m = /translate\(\s*([^,)\s]+)[,\s]+([^)\s]+)\s*\)/.exec(el.getAttribute("transform") || "");
      return { el, scroll, bx: m ? parseFloat(m[1]) : 0, by: m ? parseFloat(m[2]) : 0 };
    })
    .filter(Boolean);
  root.style.setProperty("--lights-on", LIGHTS_ON);
  root.style.setProperty("--lights-off", LIGHTS_OFF);
  lightEls = [...svg.querySelectorAll('g[id$="-lights"] :is(rect, circle, path, polygon, ellipse)')]
    .map((el) => ({
      el,
      sunsetAt: SUNSET_START + Math.random() * (SUNSET_END - SUNSET_START),
      sunriseAt: SUNRISE_START + Math.random() * (SUNRISE_END - SUNRISE_START),
      on: null,
    }));
}

function makeStars() {
  const box = document.getElementById("stars");
  if (!box) return;
  for (let i = 0; i < 90; i++) {
    const s = document.createElement("i");
    s.style.left = `${Math.random() * 100}%`;
    s.style.top = `${Math.random() * 70}%`;
    s.style.opacity = `${0.3 + Math.random() * 0.7}`;
    const sz = Math.random() < 0.15 ? 3 : 2;
    s.style.width = `${sz}px`;
    s.style.height = `${sz}px`;
    box.appendChild(s);
  }
}

function parallaxTick() {
  const y = window.scrollY || 0;
  if (y !== scrollPos) {
    scrollPos = y;
    root.style.setProperty("--scrollPos", `${y}px`);
  }
  if (!reduceMotion) {
    for (const { el, scroll, bx, by } of layerEls) {
      el.style.transform = `translate(${bx.toFixed(1)}px, ${(by + scrollPos * scroll * 0.4).toFixed(1)}px)`;
    }
  }
  requestAnimationFrame(parallaxTick);
}

document.querySelectorAll("[data-theme]").forEach((btn) => {
  btn.addEventListener("click", () => setTheme(btn.dataset.theme));
});

makeStars();
requestAnimationFrame(parallaxTick);
fetch("assets/skyline.svg")
  .then((res) => {
    if (!res.ok) throw new Error(`skyline.svg: ${res.status}`);
    return res.text();
  })
  .then((text) => {
    const host = document.getElementById("svgHost");
    host.innerHTML = text.replace(/<\?xml[^?]*\?>\s*/, "");
    const svg = host.querySelector("svg");
    if (!svg) throw new Error("skyline.svg: no <svg> found");
    svg.setAttribute("preserveAspectRatio", "xMidYMax slice");
    svg.setAttribute("aria-hidden", "true");
    svg.removeAttribute("width");
    svg.removeAttribute("height");
    setupSvg();
    setTheme(animMode);
  })
  .catch((err) => {
    console.error("Failed to load skyline.svg", err);
    setTheme(animMode);
  });
