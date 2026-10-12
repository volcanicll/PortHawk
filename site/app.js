// PortHawk landing page.
//
// The page is a fixed stage: scenes are stacked in one viewport and scrolling is
// intercepted to move between them, so nothing ever scrolls. A single video of
// the real app plays alongside, and each scene seeks it to the matching segment
// using the timings the app's own frame renderer emitted (assets/manifest.json).
(function () {
  "use strict";

  var REPO = "volcanicll/PortHawk";
  var FALLBACK_VERSION = "v0.1.2";
  var LATEST_DMG = "https://github.com/" + REPO + "/releases/latest/download/PortHawk-arm64.dmg";

  function el(id) { return document.getElementById(id); }
  function setText(node, text) { if (node) node.textContent = text; }

  // --- Live version binding -------------------------------------------------
  // Fetches the latest release so shipping an app version never needs a site
  // redeploy. Falls back to releases.atom, which is not rate limited.

  (function version() {
    var downloadBtn = el("download-btn");
    var installLink = el("install-link");
    var versionEl = el("release-version");
    var btnVerEl = el("download-version");
    var metaEl = el("release-meta");
    var deployedNote = el("deployed-note");

    if (downloadBtn) downloadBtn.href = LATEST_DMG;
    if (installLink) installLink.href = LATEST_DMG;
    setText(versionEl, FALLBACK_VERSION);
    setText(btnVerEl, FALLBACK_VERSION);

    function apply(v, publishedAt) {
      setText(versionEl, v);
      setText(btnVerEl, v);
      if (publishedAt && metaEl) {
        var d = new Date(publishedAt);
        var stamp = d.getFullYear() + "-" +
          String(d.getMonth() + 1).padStart(2, "0") + "-" +
          String(d.getDate()).padStart(2, "0");
        metaEl.innerHTML =
          'Latest <span class="mono">' + v + "</span> · " + stamp +
          ' · <a href="https://github.com/' + REPO + '/releases" target="_blank" rel="noopener" style="color:var(--blue)">changelog</a>' +
          " · macOS 13+ · Apple Silicon";
      }
    }

    function markLive() { setText(deployedNote, "· version tracks Releases live"); }

    fetch("https://api.github.com/repos/" + REPO + "/releases/latest")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (rel) { apply(rel.tag_name || FALLBACK_VERSION, rel.published_at); markLive(); })
      .catch(function () {
        fetch("https://github.com/" + REPO + "/releases.atom")
          .then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); })
          .then(function (xml) {
            var m = xml.match(/releases\/tag\/(v[0-9][^<"\s]*)/);
            if (m) { apply(m[1], null); markLive(); }
          })
          .catch(function () { /* keep the fallback version */ });
      });
  })();

  // --- Scene navigation -----------------------------------------------------

  var sceneEls = Array.prototype.slice.call(document.querySelectorAll(".scene"));
  var video = el("demo");
  var rail = el("rail");
  var hint = el("hint");

  // Chapter labels, in the same order as the scenes in the markup.
  var LABELS = {
    hero: "Overview",
    arrive: "Ports arrive",
    favorite: "Favorites",
    end: "End a process",
    alert: "Alerts",
    filter: "Exposure",
    detail: "Detail",
    settings: "Settings",
    install: "Install",
  };

  var current = 0;
  var scenes = sceneEls.map(function (node) { return node.getAttribute("data-scene"); });

  // Video segments per scene, filled in from the manifest once it loads. Until
  // then the hero simply loops the whole clip.
  var segments = {};
  var manifest = null;

  // How long to hold the final frame of a scene before repeating it. Without a
  // dwell the loop reads as a stutter; with one, the outcome of the action has
  // time to register. Scenes that end on a state worth studying hold longer.
  var DWELL_MS = {
    arrive: 1100,
    favorite: 1400,
    end: 1500,
    alert: 2000,
    filter: 1800,
    detail: 2400,
    settings: 1800,
  };
  var DEFAULT_DWELL_MS = 1200;

  function loadManifest() {
    return fetch("assets/manifest.json")
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (m) {
        manifest = m;
        var byName = {};
        m.scenes.forEach(function (s) { byName[s.name] = s.frame / m.fps; });
        var order = m.scenes.map(function (s) { return s.name; });
        // Each feature scene plays from its own start to the next one's, so a
        // scene shows exactly the animation that illustrates its caption.
        order.forEach(function (name, i) {
          var next = order[i + 1];
          segments[name] = {
            start: byName[name],
            end: next ? byName[next] : m.duration,
          };
        });
      })
      .catch(function () { /* hero keeps looping the whole clip */ });
  }

  var rafId = null;
  var dwellTimer = null;

  function stopSegmentWatch() {
    if (rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
    if (dwellTimer !== null) { clearTimeout(dwellTimer); dwellTimer = null; }
  }

  /// Play the segment belonging to `name`, holding its last frame and then
  /// repeating it, so a scene keeps demonstrating for as long as it is on
  /// screen. A visitor who reads slowly should not be left staring at a frozen
  /// frame — that is the whole point of showing the UI move.
  function playSegment(name) {
    stopSegmentWatch();
    if (!video || !segments[name]) return;
    var seg = segments[name];
    var dwell = DWELL_MS[name] !== undefined ? DWELL_MS[name] : DEFAULT_DWELL_MS;

    function playOnce() {
      // A tiny lead-in avoids landing exactly on the boundary frame.
      if (Math.abs(video.currentTime - seg.start) > 0.05) {
        video.currentTime = seg.start + 0.001;
      }
      video.loop = false;
      var p = video.play();
      if (p && p.catch) p.catch(function () { /* autoplay blocked */ });

      function tick() {
        // Leave a small margin so the segment's last frame is not clipped by
        // rounding at the boundary.
        if (video.currentTime >= seg.end - 0.02) {
          video.pause();
          rafId = null;
          // Hold the outcome, then go round again while this scene is current.
          dwellTimer = setTimeout(function () {
            dwellTimer = null;
            if (scenes[current] === name) playOnce();
          }, dwell);
          return;
        }
        rafId = requestAnimationFrame(tick);
      }
      rafId = requestAnimationFrame(tick);
    }

    playOnce();
  }

  /// The hero plays the whole clip on a loop as an attract mode.
  function playWholeLoop() {
    stopSegmentWatch();
    if (!video) return;
    video.loop = true;
    video.currentTime = 0;
    var p = video.play();
    if (p && p.catch) p.catch(function () { /* autoplay blocked */ });
  }

  function applyScene(index) {
    index = Math.max(0, Math.min(scenes.length - 1, index));
    var changed = index !== current;
    var goingDown = index > current;
    current = index;

    sceneEls.forEach(function (node, i) {
      node.classList.toggle("is-active", i === index);
      node.classList.toggle("is-before", i < index);
    });

    // Drives the device's counter-drift, so it lags in the direction of travel.
    var stage = el("stage");
    if (stage) stage.setAttribute("data-direction", goingDown ? "down" : "up");

    if (rail) {
      Array.prototype.forEach.call(rail.children, function (btn, i) {
        btn.classList.toggle("is-current", i === index);
        btn.setAttribute("aria-current", i === index ? "true" : "false");
      });
    }

    var name = scenes[index];
    if (name === "hero") playWholeLoop();
    else if (name === "install") { if (video) video.pause(); }
    else playSegment(name);

    if (hint) hint.classList.toggle("is-hidden", index > 0);
    if (changed && history.replaceState) {
      history.replaceState(null, "", "#" + name);
    }
  }

  function step(delta) { applyScene(current + delta); }

  // --- Build the chapter rail ----------------------------------------------

  if (rail) {
    scenes.forEach(function (name, i) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.setAttribute("aria-label", LABELS[name] || name);
      var label = document.createElement("span");
      label.className = "label";
      label.textContent = LABELS[name] || name;
      var tick = document.createElement("span");
      tick.className = "tick";
      btn.appendChild(label);
      btn.appendChild(tick);
      btn.addEventListener("click", function () { applyScene(i); });
      rail.appendChild(btn);
    });
  }

  // --- Wheel: one gesture advances one scene -------------------------------
  // Trackpads emit a long momentum tail, so the accumulated delta is gated and
  // then locked briefly; without that a single flick would skip several scenes.

  var wheelAccum = 0;
  var wheelLockedUntil = 0;
  var WHEEL_THRESHOLD = 40;
  var WHEEL_LOCK_MS = 550;

  window.addEventListener("wheel", function (e) {
    // On narrow screens the page scrolls normally instead.
    if (window.matchMedia("(max-width: 860px)").matches) return;
    e.preventDefault();
    var now = Date.now();
    if (now < wheelLockedUntil) return;
    // A mostly-horizontal gesture is not a scene change.
    if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;

    wheelAccum += e.deltaY;
    if (Math.abs(wheelAccum) < WHEEL_THRESHOLD) return;

    step(wheelAccum > 0 ? 1 : -1);
    wheelAccum = 0;
    wheelLockedUntil = now + WHEEL_LOCK_MS;
  }, { passive: false });

  // --- Keyboard ------------------------------------------------------------

  window.addEventListener("keydown", function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    switch (e.key) {
      case "ArrowDown": case "PageDown": case " ": case "Spacebar":
        e.preventDefault(); step(1); break;
      case "ArrowUp": case "PageUp":
        e.preventDefault(); step(-1); break;
      case "Home":
        e.preventDefault(); applyScene(0); break;
      case "End":
        e.preventDefault(); applyScene(scenes.length - 1); break;
      default: break;
    }
  });

  // --- Touch: vertical swipe ----------------------------------------------

  var touchStartY = null;
  window.addEventListener("touchstart", function (e) {
    touchStartY = e.touches[0].clientY;
  }, { passive: true });

  window.addEventListener("touchend", function (e) {
    if (window.matchMedia("(max-width: 860px)").matches) return;
    if (touchStartY === null) return;
    var dy = touchStartY - e.changedTouches[0].clientY;
    if (Math.abs(dy) > 50) step(dy > 0 ? 1 : -1);
    touchStartY = null;
  }, { passive: true });

  // --- Top-bar links jump to a scene --------------------------------------

  Array.prototype.forEach.call(document.querySelectorAll('.topbar nav a[href^="#"]'), function (a) {
    a.addEventListener("click", function (e) {
      var target = a.getAttribute("href").slice(1);
      var idx = scenes.indexOf(target);
      if (idx === -1 && target === "features") idx = scenes.indexOf("arrive");
      if (idx === -1) return;
      e.preventDefault();
      applyScene(idx);
    });
  });

  // --- Boot ----------------------------------------------------------------

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  loadManifest().then(function () {
    var startAt = scenes.indexOf((location.hash || "").slice(1));
    applyScene(startAt > 0 ? startAt : 0);
  });

  if (video && reduceMotion) {
    // Respect the preference: show a still frame rather than an animation.
    video.autoplay = false;
    video.addEventListener("loadeddata", function () { video.pause(); });
  }
})();
