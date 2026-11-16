// biome-ignore-all lint/correctness/useQwikValidLexicalScope: This standalone DOM script does not use Qwik serialization.
const demo = document.querySelector("video.app-shot");
const motionPreference = matchMedia("(prefers-reduced-motion: reduce)");

if (demo) {
  const respectMotionPreference = () => {
    if (motionPreference.matches) demo.pause();
    else
      demo.play().catch(() => {
        // Keep the poster visible when the browser blocks automatic playback.
      });
  };
  motionPreference.addEventListener("change", respectMotionPreference);
  respectMotionPreference();
}

fetch("https://api.github.com/repos/alielsokary/CaskHub")
  .then((response) =>
    response.ok ? response.json() : Promise.reject(response.status),
  )
  .then(({ stargazers_count: count }) => {
    if (!Number.isFinite(count)) return;
    document.getElementById("gh-stars").textContent =
      `${new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(count).toLowerCase()}+`;
    document
      .getElementById("gh-star")
      .setAttribute(
        "aria-label",
        `CaskHub on GitHub, ${count.toLocaleString("en")} stars`,
      );
  })
  .catch(() => {
    // Keep the static star count when GitHub is unavailable or rate-limits us.
  });

document.querySelectorAll(".video-poster").forEach((poster) => {
  poster.addEventListener("click", (event) => {
    event.preventDefault();
    const frame = document.createElement("iframe");
    frame.src = `https://www.youtube-nocookie.com/embed/${poster.dataset.videoId}?autoplay=1&rel=0`;
    frame.title = poster.dataset.videoTitle;
    frame.allow = "autoplay; encrypted-media; picture-in-picture; fullscreen";
    frame.allowFullscreen = true;
    frame.referrerPolicy = "strict-origin-when-cross-origin";
    poster.replaceWith(frame);
    frame.focus();
  });
});

const carousel = document.querySelector(".quote-carousel");
if (carousel) {
  const viewport = carousel.querySelector(".quote-viewport");
  const track = carousel.querySelector(".quote-track");
  const slides = [...track.children];
  const controls = carousel.querySelector(".carousel-controls");
  const dots = slides.map((_, index) => {
    const dot = document.createElement("button");
    dot.type = "button";
    dot.setAttribute("aria-label", `Show quote ${index + 1} of ${slides.length}`);
    dot.addEventListener("click", () => step(index - current));
    carousel.querySelector(".carousel-dots").append(dot);
    return dot;
  });
  let current = 0;
  let timer;
  let engaged = false;

  const offsetOf = (index) => slides[0].offsetLeft - slides.at(index).offsetLeft;
  const show = (index) => {
    current = (index + slides.length) % slides.length;
    track.style.transform = `translateX(${offsetOf(current)}px)`;
    slides.forEach((slide, i) => {
      slide.classList.toggle("is-active", i === current);
      slide.toggleAttribute("inert", i !== current);
    });
    dots.forEach((dot, i) =>
      dot.setAttribute("aria-current", String(i === current)),
    );
  };
  const schedule = () => {
    clearInterval(timer);
    if (!engaged && !motionPreference.matches && !document.hidden)
      timer = setInterval(() => show(current + 1), 4000);
  };
  const step = (delta) => {
    show(current + delta);
    schedule();
  };

  slides.forEach((slide, index) => {
    slide.setAttribute("aria-label", `${index + 1} of ${slides.length}`);
  });
  controls.querySelectorAll("[data-step]").forEach((button) => {
    button.addEventListener("click", () => step(Number(button.dataset.step)));
  });

  // Drag follows the pointer, then settles on the nearest neighbour.
  let drag = null;
  let swiped = false;
  viewport.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    drag = { x: event.clientX, moved: false };
    swiped = false;
  });
  viewport.addEventListener("pointermove", (event) => {
    if (!drag) return;
    const distance = event.clientX - drag.x;
    if (!drag.moved) {
      if (Math.abs(distance) < 6) return;
      drag.moved = true;
      viewport.setPointerCapture(event.pointerId);
      viewport.classList.add("is-dragging");
    }
    track.style.transform = `translateX(${offsetOf(current) + distance}px)`;
  });
  const endDrag = (event) => {
    if (!drag) return;
    const distance = event.clientX - drag.x;
    const moved = drag.moved;
    drag = null;
    viewport.classList.remove("is-dragging");
    if (!moved) return;
    swiped = true;
    if (Math.abs(distance) > 60) step(distance < 0 ? 1 : -1);
    else show(current);
  };
  viewport.addEventListener("pointerup", endDrag);
  viewport.addEventListener("pointercancel", endDrag);
  viewport.addEventListener("dragstart", (event) => event.preventDefault());

  // Trackpad and Magic Mouse swipes arrive as wheel events followed by momentum.
  // One step per gesture; a reversal or a fresh burst during momentum starts a new one.
  let gestureX = 0;
  let gestureY = 0;
  let lockedDirection = 0;
  let lastMagnitude = 0;
  let wheelQuiet;
  const resetGesture = () => {
    gestureX = 0;
    gestureY = 0;
    lockedDirection = 0;
    lastMagnitude = 0;
  };
  viewport.addEventListener(
    "wheel",
    (event) => {
      const { deltaX, deltaY } = event;
      if (Math.abs(deltaX) > Math.abs(deltaY)) event.preventDefault();
      clearTimeout(wheelQuiet);
      wheelQuiet = setTimeout(resetGesture, 150);
      const magnitude = Math.abs(deltaX);
      if (lockedDirection) {
        const reversed = Math.sign(deltaX) === -lockedDirection && magnitude > 2;
        const renewed =
          Math.sign(deltaX) === lockedDirection &&
          magnitude > 8 &&
          magnitude > lastMagnitude * 2;
        lastMagnitude = magnitude;
        if (!reversed && !renewed) return;
        resetGesture();
      }
      lastMagnitude = magnitude;
      gestureX += deltaX;
      gestureY += deltaY;
      if (Math.abs(gestureX) > 30 && Math.abs(gestureX) > Math.abs(gestureY)) {
        lockedDirection = Math.sign(gestureX);
        step(lockedDirection);
      }
    },
    { passive: false },
  );
  // Faded neighbours are inert, so their clicks land on the viewport.
  viewport.addEventListener("click", (event) => {
    if (swiped) return;
    const { left, right } = slides.at(current).getBoundingClientRect();
    if (event.clientX < left) step(-1);
    else if (event.clientX > right) step(1);
  });

  const engage = (value) => () => {
    engaged = value;
    schedule();
  };
  carousel.addEventListener("pointerenter", engage(true));
  carousel.addEventListener("pointerleave", engage(false));
  carousel.addEventListener("focusin", engage(true));
  carousel.addEventListener("focusout", (event) => {
    if (!carousel.contains(event.relatedTarget)) engage(false)();
  });
  document.addEventListener("visibilitychange", schedule);
  motionPreference.addEventListener("change", schedule);
  addEventListener("resize", () => show(current));

  controls.hidden = false;
  carousel.classList.add("is-ready");
  track.style.transition = "none";
  const start = slides.findIndex((slide) => slide.hasAttribute("data-start"));
  show(start === -1 ? Math.floor(slides.length / 2) : start);
  track.getBoundingClientRect();
  track.style.transition = "";
  schedule();
}

const themeToggle = document.querySelector(".theme-toggle");
const applyTheme = (theme) => {
  document.documentElement.dataset.theme = theme;
  themeToggle.setAttribute(
    "aria-label",
    `Switch to ${theme === "dark" ? "light" : "dark"} theme`,
  );
  // Show the app screenshots in the same appearance as the page.
  document.querySelector(`.segmented button[data-mode="${theme}"]`)?.click();
};
themeToggle.addEventListener("click", () => {
  const theme =
    document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  try {
    localStorage.setItem("theme", theme);
  } catch {
    // Private browsing can block storage; the toggle still works for this visit.
  }
  applyTheme(theme);
});

const copyButton = document.getElementById("copy");
let copyFeedbackTimer;
copyButton.addEventListener("click", async () => {
  const status = document.getElementById("copy-status");
  try {
    await navigator.clipboard.writeText(
      document.getElementById("brew-cmd").textContent,
    );
    clearTimeout(copyFeedbackTimer);
    copyButton.classList.add("copied");
    copyButton.setAttribute("aria-label", "Install command copied");
    status.textContent = "Install command copied.";
    copyFeedbackTimer = setTimeout(() => {
      copyButton.classList.remove("copied");
      copyButton.setAttribute("aria-label", "Copy install command");
      status.textContent = "";
    }, 1800);
  } catch {
    const range = document.createRange();
    range.selectNodeContents(document.getElementById("brew-cmd"));
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = "Select and copy the highlighted install command.";
  }
});

let screenshotMode = "dark";
const designs = new Map([
  [
    "standard",
    {
      name: "Standard",
      light: "assets/standard-light.png",
      dark: "assets/standard-dark.png",
    },
  ],
  [
    "classic",
    {
      name: "Classic",
      light: "assets/classic-light.png",
      dark: "assets/classic-dark.png",
    },
  ],
]);
const modeButtons = document.querySelectorAll("button[data-mode]");
const appearanceControl = document.querySelector(".segmented");
const screenshotGallery = document.querySelector(".themes");
let screenshotRequest = 0;
const selectModeControl = (mode) => {
  appearanceControl.dataset.mode = mode;
  modeButtons.forEach((option) => {
    option.setAttribute("aria-pressed", String(option.dataset.mode === mode));
  });
};
modeButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const mode = button.dataset.mode;
    if (mode !== "light" && mode !== "dark") return;
    const request = ++screenshotRequest;
    selectModeControl(mode);
    screenshotGallery.setAttribute("aria-busy", "true");
    const incoming = [
      ...screenshotGallery.querySelectorAll(`[data-screenshot-mode="${mode}"]`),
    ];
    try {
      // Decode both designs before the crossfade so a slow image never flashes blank.
      await Promise.all(incoming.map((screenshot) => screenshot.decode()));
    } catch {
      if (request !== screenshotRequest) return;
      selectModeControl(screenshotMode);
      screenshotGallery.setAttribute("aria-busy", "false");
      document.getElementById("appearance-status").textContent =
        "Unable to load this appearance. Please try again.";
      return;
    }
    if (request !== screenshotRequest) return;
    screenshotMode = mode;
    screenshotGallery
      .querySelectorAll("[data-screenshot-mode]")
      .forEach((screenshot) => {
        const visible = screenshot.dataset.screenshotMode === mode;
        screenshot.classList.toggle("is-visible", visible);
        screenshot.setAttribute("aria-hidden", String(!visible));
      });
    screenshotGallery.querySelectorAll("[data-design]").forEach((target) => {
      const design = designs.get(target.dataset.design);
      if (!design) return;
      target.setAttribute(
        "aria-label",
        `Enlarge ${design.name} ${mode} screenshot`,
      );
    });
    screenshotGallery.setAttribute("aria-busy", "false");
    document.getElementById("appearance-status").textContent =
      `Showing both designs in ${screenshotMode} mode.`;
  });
});

const screenshotDialog = document.getElementById("screenshot-dialog");
document.querySelectorAll("[data-design]").forEach((button) => {
  button.addEventListener("click", () => {
    const design = designs.get(button.dataset.design);
    if (!design) return;
    const screenshot = document.getElementById("expanded-screenshot");
    screenshot.src = screenshotMode === "dark" ? design.dark : design.light;
    screenshot.alt = `CaskHub ${design.name} design in ${screenshotMode} mode`;
    document.getElementById("screenshot-title").textContent =
      `CaskHub ${design.name} · ${screenshotMode === "dark" ? "Dark" : "Light"}`;
    screenshotDialog.showModal();
    document.body.style.overflow = "hidden";
  });
});
screenshotDialog
  .querySelector(".dialog-close")
  .addEventListener("click", () => screenshotDialog.close());
screenshotDialog.addEventListener("close", () => {
  document.body.style.overflow = "";
});
screenshotDialog.addEventListener("click", (event) => {
  const bounds = screenshotDialog.getBoundingClientRect();
  if (
    event.clientX < bounds.left ||
    event.clientX > bounds.right ||
    event.clientY < bounds.top ||
    event.clientY > bounds.bottom
  ) {
    screenshotDialog.close();
  }
});

applyTheme(document.documentElement.dataset.theme);
