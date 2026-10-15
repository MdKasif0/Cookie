// ==========================================================================
// Cookie — Interactive Product Showcase Logic
// Crafted with Care for macOS
// ==========================================================================

document.addEventListener("DOMContentLoaded", () => {
  // ------------------------------------------------------------------------
  // 1. Hero Cookie Interactive Click (Purr & Boop)
  // ------------------------------------------------------------------------
  const cookieActor = document.getElementById("cookieActor");
  const petToast = document.getElementById("petToast");

  const purrQuotes = [
    "purr… 🐾",
    "mew 🌿",
    "*happy blink*",
    "*gentle head bump*",
    "*tail swish*",
    "prrrrt! ✨"
  ];

  let toastTimer = null;
  let quoteIndex = 0;

  if (cookieActor && petToast) {
    cookieActor.addEventListener("click", () => {
      petToast.textContent = purrQuotes[quoteIndex % purrQuotes.length];
      quoteIndex++;

      petToast.classList.add("active");

      // Tactile spring bounce
      cookieActor.style.transform = "scale(1.06) translateY(-8px)";
      setTimeout(() => {
        cookieActor.style.transform = "";
      }, 180);

      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        petToast.classList.remove("active");
      }, 1800);
    });
  }

  // Subtle interactive glance toward cursor in hero
  const heroSection = document.getElementById("hero");
  if (heroSection && cookieActor) {
    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (!prefersReducedMotion) {
      let isHeroHovered = false;

      heroSection.addEventListener("mousemove", (e) => {
        isHeroHovered = true;
        const rect = cookieActor.getBoundingClientRect();
        const catCenterX = rect.left + rect.width / 2;
        const catCenterY = rect.top + rect.height / 2;

        const diffX = e.clientX - catCenterX;
        const diffY = e.clientY - catCenterY;

        // Very subtle glance: max 5px translation, max 2.5deg head tilt
        const maxShift = 5;
        const shiftX = Math.max(-maxShift, Math.min(maxShift, diffX * 0.012));
        const shiftY = Math.max(-maxShift, Math.min(maxShift, diffY * 0.01));
        const tiltDeg = Math.max(-2.5, Math.min(2.5, diffX * 0.006));

        cookieActor.style.transform = `translate(${shiftX}px, ${shiftY}px) rotate(${tiltDeg}deg)`;
      });

      heroSection.addEventListener("mouseleave", () => {
        if (isHeroHovered) {
          cookieActor.style.transform = "";
          isHeroHovered = false;
        }
      });
    }
  }

  // ------------------------------------------------------------------------
  // 2. Desktop Window Scene: Cookie Click Reaction
  // ------------------------------------------------------------------------
  const desktopCookie = document.getElementById("desktopCookie");
  if (desktopCookie) {
    desktopCookie.addEventListener("click", () => {
      desktopCookie.style.transform = "scale(1.15) rotate(5deg)";
      setTimeout(() => {
        desktopCookie.style.transform = "";
      }, 220);
    });
  }

  // ------------------------------------------------------------------------
  // 3. Chapter 2: "Sometimes curious." (Cursor & Touch Tracking Stage)
  // ------------------------------------------------------------------------
  const curiousStage = document.getElementById("curiousStage");
  const curiousCat = document.getElementById("curiousCat");
  const curiousPointer = document.getElementById("curiousPointer");
  const curiousCatImg = document.getElementById("curiousCatImg");
  const curiousCatWebp = document.getElementById("curiousCatWebp");

  if (curiousStage && curiousCat) {
    let isClose = false;

    const handleCuriousMove = (clientX, clientY) => {
      const rect = curiousStage.getBoundingClientRect();
      const mouseX = clientX - rect.left;
      const mouseY = clientY - rect.top;

      // Position the target indicator ring
      if (curiousPointer) {
        curiousPointer.style.left = `${mouseX}px`;
        curiousPointer.style.top = `${mouseY}px`;
      }

      // Calculate cat's center relative to stage
      const catRect = curiousCat.getBoundingClientRect();
      const catCenterX = (catRect.left + catRect.width / 2) - rect.left;
      const catCenterY = (catRect.top + catRect.height / 2) - rect.top;

      const diffX = mouseX - catCenterX;
      const diffY = mouseY - catCenterY;
      const dist = Math.hypot(diffX, diffY);

      // Clamp movement offsets
      const maxOffset = 18;
      const moveX = Math.max(-maxOffset, Math.min(maxOffset, diffX * 0.08));
      const moveY = Math.max(-maxOffset, Math.min(maxOffset, diffY * 0.06));

      // Calculate subtle head tilt angle (-12deg to 12deg)
      const angleDeg = Math.max(-12, Math.min(12, (diffX / rect.width) * 24));

      curiousCat.style.transform = `translate(${moveX}px, ${moveY}px) rotate(${angleDeg}deg)`;

      // Proximity reaction (Petting distance)
      if (dist < 80 && !isClose) {
        isClose = true;
        if (curiousCatImg) curiousCatImg.src = "assets/cookie-shy.png";
        if (curiousCatWebp) curiousCatWebp.srcset = "assets/cookie-shy.webp";
      } else if (dist >= 80 && isClose) {
        isClose = false;
        if (curiousCatImg) curiousCatImg.src = "assets/hero-cookie-open.png";
        if (curiousCatWebp) curiousCatWebp.srcset = "assets/hero-cookie-open.webp";
      }
    };

    const resetCurious = () => {
      curiousCat.style.transform = "translate(0, 0) rotate(0deg)";
      isClose = false;
      if (curiousCatImg) curiousCatImg.src = "assets/hero-cookie-open.png";
      if (curiousCatWebp) curiousCatWebp.srcset = "assets/hero-cookie-open.webp";
    };

    curiousStage.addEventListener("mousemove", (e) => {
      handleCuriousMove(e.clientX, e.clientY);
    });

    curiousStage.addEventListener("mouseleave", resetCurious);

    // Mobile touch tracking support
    curiousStage.addEventListener("touchstart", (e) => {
      if (e.touches && e.touches.length > 0) {
        handleCuriousMove(e.touches[0].clientX, e.touches[0].clientY);
      }
    }, { passive: true });

    curiousStage.addEventListener("touchmove", (e) => {
      if (e.touches && e.touches.length > 0) {
        handleCuriousMove(e.touches[0].clientX, e.touches[0].clientY);
      }
    }, { passive: true });

    curiousStage.addEventListener("touchend", resetCurious);
    curiousStage.addEventListener("touchcancel", resetCurious);
  }

  // ------------------------------------------------------------------------
  // 4. Chapter 3: "Sometimes sleepy." (Cardboard Box Peek Toggle)
  // ------------------------------------------------------------------------
  const cardboardBox = document.getElementById("cardboardBox");
  const boxTag = document.getElementById("boxTag");
  const sleepyScene = document.getElementById("sleepyScene");
  const sleepyCat = document.getElementById("sleepyCat");

  let isPeeking = false;

  const toggleBoxPeek = () => {
    isPeeking = !isPeeking;
    if (sleepyScene) {
      sleepyScene.classList.toggle("peeking", isPeeking);
    }
    if (boxTag) {
      boxTag.textContent = isPeeking ? "Peek-a-boo! 🐾" : "Click box";
    }
  };

  if (cardboardBox) {
    cardboardBox.addEventListener("click", toggleBoxPeek);
  }
  if (sleepyCat) {
    sleepyCat.addEventListener("click", toggleBoxPeek);
  }

  // ------------------------------------------------------------------------
  // 5. Chapter 4: "Pick her up. Pet her back." (Draggable Sandbox)
  // ------------------------------------------------------------------------
  const dragSandbox = document.getElementById("dragSandbox");
  const draggableCookie = document.getElementById("draggableCookie");
  const draggableCookieImg = document.getElementById("draggableCookieImg");
  const draggableCookieWebp = document.getElementById("draggableCookieWebp");

  if (dragSandbox && draggableCookie) {
    let isDragging = false;
    let startX = 0;
    let startY = 0;
    let lastX = 0;
    let lastY = 0;
    let initialLeft = 140;
    let initialTop = 120;
    let dragDistance = 0;

    draggableCookie.style.left = `${initialLeft}px`;
    draggableCookie.style.top = `${initialTop}px`;

    draggableCookie.addEventListener("pointerdown", (e) => {
      isDragging = true;
      dragDistance = 0;
      draggableCookie.setPointerCapture(e.pointerId);

      startX = e.clientX;
      startY = e.clientY;
      lastX = e.clientX;
      lastY = e.clientY;
      initialLeft = draggableCookie.offsetLeft;
      initialTop = draggableCookie.offsetTop;

      draggableCookie.classList.add("is-dragging");

      // Switch to walking/carried sprite while airborne
      if (draggableCookieImg) draggableCookieImg.src = "assets/cookie-walk.png";
      if (draggableCookieWebp) draggableCookieWebp.srcset = "assets/cookie-walk.webp";
    });

    draggableCookie.addEventListener("pointermove", (e) => {
      if (!isDragging) return;

      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      const stepX = e.clientX - lastX;
      const stepY = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      dragDistance += Math.hypot(stepX, stepY);

      const sandboxRect = dragSandbox.getBoundingClientRect();
      const cookieWidth = draggableCookie.offsetWidth;
      const cookieHeight = draggableCookie.offsetHeight;

      const minX = 12;
      const maxX = sandboxRect.width - cookieWidth - 12;
      const minY = 12;
      const maxY = sandboxRect.height - cookieHeight - 12;

      let newLeft = initialLeft + dx;
      let newTop = initialTop + dy;

      newLeft = Math.max(minX, Math.min(maxX, newLeft));
      newTop = Math.max(minY, Math.min(maxY, newTop));

      draggableCookie.style.left = `${newLeft}px`;
      draggableCookie.style.top = `${newTop}px`;
    });

    const endDrag = (e) => {
      if (!isDragging) return;
      isDragging = false;
      draggableCookie.releasePointerCapture(e.pointerId);
      draggableCookie.classList.remove("is-dragging");

      // Settle down to sitting pose
      if (draggableCookieImg) draggableCookieImg.src = "assets/cookie.png";
      if (draggableCookieWebp) draggableCookieWebp.srcset = "assets/cookie.webp";

      // If it was just a gentle click (< 10px moved), pet reaction
      if (dragDistance < 10) {
        draggableCookie.style.transform = "scale(1.12) translateY(-6px)";
        setTimeout(() => {
          draggableCookie.style.transform = "";
        }, 180);

        const sandboxToast = document.getElementById("sandboxToast");
        if (sandboxToast) {
          const sandboxPurrs = ["purr… 🐾", "mew 🌿", "*snuggle*", "*gentle stretch*"];
          sandboxToast.textContent = sandboxPurrs[Math.floor(Math.random() * sandboxPurrs.length)];
          sandboxToast.classList.add("active");
          setTimeout(() => {
            sandboxToast.classList.remove("active");
          }, 1600);
        }
      }
    };

    draggableCookie.addEventListener("pointerup", endDrag);
    draggableCookie.addEventListener("pointercancel", endDrag);
  }

  // ------------------------------------------------------------------------
  // 6. Chapter 5: Care, Play & Treats Interactive Showcase
  // ------------------------------------------------------------------------
  const treatButtons = document.querySelectorAll(".treat-button");
  const treatCatFace = document.getElementById("treatCatFace");
  const treatCatFaceWebp = document.getElementById("treatCatFaceWebp");
  const treatSpeechText = document.getElementById("treatSpeechText");

  const treatData = {
    "fish": {
      sprite: "cookie-hungry",
      text: "Cookie's ears perk up immediately! She scampers over and chomps down on the salmon fillet happily."
    },
    "tuna": {
      sprite: "cookie-hungry",
      text: "The aroma of savory tuna makes Cookie knead her paws on your desk with deep, vibrating purrs."
    },
    "cookie": {
      sprite: "cookie-hungry",
      text: "A crunchy cat biscuit! Cookie nibbles delicately, leaving tiny pretend crumbs across your window."
    },
    "catnip": {
      sprite: "cookie-dizzy",
      text: "Cookie rolls onto her back, rubbing her cheeks against the floor in pure, silly bliss."
    },
    "yarn": {
      sprite: "cookie-mischievous",
      text: "Cookie bats the warm wool yarn across your display, pouncing and tumbling with delight."
    },
    "feather": {
      sprite: "cookie-walk",
      text: "Eyes wide and dilated, Cookie wiggles her hindquarters and leaps straight up for the feather wand!"
    },
    "box": {
      sprite: "cookie-shy",
      text: "If she fits, she sits. Cookie dives head-first into the cardboard box and peeks out shyly."
    },
    "bell": {
      sprite: "cookie-cool",
      text: "Jingle jingle! Cookie gives the little brass bell an inquisitive tap with her right paw."
    }
  };

  treatButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      treatButtons.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");

      const itemKey = btn.getAttribute("data-item");
      const info = treatData[itemKey];

      if (info && treatSpeechText) {
        treatSpeechText.textContent = info.text;

        if (treatCatFace && treatCatFaceWebp) {
          treatCatFace.src = `assets/${info.sprite}.png`;
          treatCatFaceWebp.srcset = `assets/${info.sprite}.webp`;

          // Small joyful bounce animation
          treatCatFace.parentElement.style.transform = "scale(1.15)";
          setTimeout(() => {
            treatCatFace.parentElement.style.transform = "";
          }, 180);
        }
      }
    });
  });

  // ------------------------------------------------------------------------
  // 7. Dedicated "Make Cookie yours." Native Mac Customizer Window Logic
  // ------------------------------------------------------------------------
  const macSidebarItems = document.querySelectorAll(".mac-sidebar-item");
  const macPanes = document.querySelectorAll(".mac-pane");

  const previewCatActor = document.getElementById("previewCatActor");
  const previewCatImg = document.getElementById("previewCatImg");
  const previewCatWebp = document.getElementById("previewCatWebp");
  const furTintLayer = document.getElementById("furTintLayer");
  const patternOverlayLayer = document.getElementById("patternOverlayLayer");
  const previewCatName = document.getElementById("previewCatName");
  const previewCatPersonality = document.getElementById("previewCatPersonality");
  const previewCatSummary = document.getElementById("previewCatSummary");

  const furColorBtns = document.querySelectorAll("#furColorGrid .swatch-btn");
  const furColorLabel = document.getElementById("furColorLabel");
  const patternBtns = document.querySelectorAll("#patternControl .segment-btn");
  const eyeStyleBtns = document.querySelectorAll("#eyeStyleControl .segment-btn");
  const eyeColorBtns = document.querySelectorAll("#eyeColorControl .mini-pill");
  const accessoryCards = document.querySelectorAll("#accessoryCards .accessory-card");
  const personalityRows = document.querySelectorAll("#personalityList .personality-row");
  const catNameInput = document.getElementById("catNameInput");
  const nameChips = document.querySelectorAll("#nameChips .name-chip");
  const variationCards = document.querySelectorAll(".variation-card");

  // State
  let customState = {
    name: "Cookie",
    color: "warmWhite",
    pattern: "none",
    eyeStyle: "round",
    eyeColor: "charcoal",
    accessory: "classic",
    personality: "playful"
  };

  const furColorMap = {
    "warmWhite": { name: "Warm White", color: "transparent" },
    "cream": { name: "Cream", color: "rgba(247, 232, 199, 0.72)" },
    "ivory": { name: "Ivory", color: "rgba(252, 245, 227, 0.65)" },
    "softBeige": { name: "Soft Beige", color: "rgba(232, 214, 181, 0.72)" },
    "mutedSage": { name: "Muted Sage", color: "rgba(184, 196, 164, 0.68)" },
    "warmPeach": { name: "Warm Peach", color: "rgba(245, 202, 170, 0.68)" },
    "softOrange": { name: "Soft Orange", color: "rgba(239, 176, 123, 0.68)" },
    "mutedBrown": { name: "Muted Brown", color: "rgba(140, 112, 79, 0.65)" },
    "charcoal": { name: "Charcoal", color: "rgba(74, 69, 64, 0.62)" }
  };

  const personalityMap = {
    "playful": { title: "Playful", summary: "Little games and occasional bursts of mischief. Loves toys." },
    "affectionate": { title: "Affectionate", summary: "Likes being near you; follows the cursor and nearly never tires of petting." },
    "sleepy": { title: "Sleepy", summary: "Naps often beside windows, but always up for gentle company." },
    "energetic": { title: "Energetic", summary: "Always trotting off somewhere new. Quick strolling speed across monitors." },
    "curious": { title: "Curious", summary: "Watches everything, investigates moving cursors, tilts her head." },
    "grumpy": { title: "Grumpy", summary: "Judgmental, but secretly fond of you. Short fuse if over-petted." }
  };

  const updatePreview = () => {
    // 1. Sprite resolution based on accessory / eye expression
    let sprite = "cookie";
    if (customState.accessory === "glasses") {
      sprite = "cookie-cool";
    } else if (customState.accessory === "shy") {
      sprite = "cookie-shy";
    } else if (customState.accessory === "mischief") {
      sprite = "cookie-mischievous";
    } else {
      if (customState.eyeStyle === "sleepy") {
        sprite = "cookie-sleep";
      } else if (customState.eyeStyle === "sparkle") {
        sprite = "cookie-mischievous";
      } else if (customState.personality === "grumpy") {
        sprite = "cookie-angry";
      } else {
        sprite = "cookie";
      }
    }

    if (previewCatImg && previewCatWebp) {
      previewCatImg.src = `assets/${sprite}.png`;
      previewCatWebp.srcset = `assets/${sprite}.webp`;
    }

    // 2. Fur color tint
    if (furTintLayer) {
      const colorInfo = furColorMap[customState.color] || furColorMap.warmWhite;
      furTintLayer.style.backgroundColor = colorInfo.color;
    }
    if (furColorLabel) {
      furColorLabel.textContent = furColorMap[customState.color]?.name || "Warm White";
    }

    // 3. Pattern
    if (patternOverlayLayer) {
      patternOverlayLayer.className = "pattern-overlay-layer";
      if (customState.pattern !== "none") {
        patternOverlayLayer.classList.add(customState.pattern);
      }
    }

    // 4. Name and Personality
    if (previewCatName) {
      previewCatName.textContent = customState.name || "Cookie";
    }
    if (previewCatPersonality) {
      previewCatPersonality.textContent = personalityMap[customState.personality]?.title || "Playful";
    }
    if (previewCatSummary) {
      previewCatSummary.textContent = personalityMap[customState.personality]?.summary || "";
    }

    // Bounce preview cat
    if (previewCatActor) {
      previewCatActor.style.transform = "scale(1.06) translateY(-4px)";
      setTimeout(() => {
        previewCatActor.style.transform = "";
      }, 160);
    }
  };

  // Sync UI controls with customState
  const syncControls = () => {
    furColorBtns.forEach((btn) => {
      const isMatch = btn.getAttribute("data-color") === customState.color;
      btn.classList.toggle("active", isMatch);
      let check = btn.querySelector(".swatch-check");
      if (isMatch && !check) {
        check = document.createElement("span");
        check.className = "swatch-check";
        check.textContent = "✓";
        btn.appendChild(check);
      } else if (!isMatch && check) {
        check.remove();
      }
    });

    patternBtns.forEach((btn) => {
      btn.classList.toggle("active", btn.getAttribute("data-pattern") === customState.pattern);
    });

    eyeStyleBtns.forEach((btn) => {
      btn.classList.toggle("active", btn.getAttribute("data-eyestyle") === customState.eyeStyle);
    });

    eyeColorBtns.forEach((btn) => {
      btn.classList.toggle("active", btn.getAttribute("data-eyecolor") === customState.eyeColor);
    });

    accessoryCards.forEach((card) => {
      card.classList.toggle("active", card.getAttribute("data-acc") === customState.accessory);
    });

    personalityRows.forEach((row) => {
      row.classList.toggle("active", row.getAttribute("data-personality") === customState.personality);
    });

    if (catNameInput) {
      catNameInput.value = customState.name;
    }
  };

  // Sidebar Tabs
  macSidebarItems.forEach((item) => {
    item.addEventListener("click", () => {
      macSidebarItems.forEach((i) => i.classList.remove("active"));
      item.classList.add("active");

      const targetTab = item.getAttribute("data-tab");
      macPanes.forEach((pane) => {
        const isMatch = (targetTab === "appearance" && pane.id === "paneAppearance") ||
                        (targetTab === "accessories" && pane.id === "paneAccessories") ||
                        (targetTab === "personality" && pane.id === "panePersonality") ||
                        (targetTab === "name" && pane.id === "paneName");
        pane.classList.toggle("active", isMatch);
      });
    });
  });

  // Fur Color Swatches
  furColorBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      customState.color = btn.getAttribute("data-color") || "warmWhite";
      syncControls();
      updatePreview();
    });
  });

  // Patterns
  patternBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      customState.pattern = btn.getAttribute("data-pattern") || "none";
      syncControls();
      updatePreview();
    });
  });

  // Eye Style
  eyeStyleBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      customState.eyeStyle = btn.getAttribute("data-eyestyle") || "round";
      syncControls();
      updatePreview();
    });
  });

  // Eye Color
  eyeColorBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      customState.eyeColor = btn.getAttribute("data-eyecolor") || "charcoal";
      syncControls();
      updatePreview();
    });
  });

  // Accessories
  accessoryCards.forEach((card) => {
    card.addEventListener("click", () => {
      customState.accessory = card.getAttribute("data-acc") || "classic";
      syncControls();
      updatePreview();
    });
  });

  // Personality
  personalityRows.forEach((row) => {
    row.addEventListener("click", () => {
      customState.personality = row.getAttribute("data-personality") || "playful";
      syncControls();
      updatePreview();
    });
  });

  // Name Input
  if (catNameInput) {
    catNameInput.addEventListener("input", (e) => {
      const val = e.target.value.trim();
      customState.name = val.length > 0 ? val : "Cookie";
      if (previewCatName) previewCatName.textContent = customState.name;
    });
  }

  // Quick Name Chips
  nameChips.forEach((chip) => {
    chip.addEventListener("click", () => {
      const chosen = chip.textContent.trim();
      customState.name = chosen;
      syncControls();
      updatePreview();
    });
  });

  // Variations Gallery Presets
  const presets = {
    "cookie": {
      name: "Cookie",
      color: "warmWhite",
      pattern: "none",
      accessory: "classic",
      eyeStyle: "round",
      eyeColor: "charcoal",
      personality: "playful"
    },
    "mochi": {
      name: "Mochi",
      color: "charcoal",
      pattern: "tuxedo",
      accessory: "glasses",
      eyeStyle: "round",
      eyeColor: "charcoal",
      personality: "grumpy"
    },
    "chai": {
      name: "Chai",
      color: "warmPeach",
      pattern: "none",
      accessory: "shy",
      eyeStyle: "round",
      eyeColor: "warmBrown",
      personality: "affectionate"
    },
    "matcha": {
      name: "Matcha",
      color: "mutedSage",
      pattern: "tabby",
      accessory: "mischief",
      eyeStyle: "sparkle",
      eyeColor: "moss",
      personality: "curious"
    },
    "bao": {
      name: "Bao",
      color: "cream",
      pattern: "none",
      accessory: "classic",
      eyeStyle: "sleepy",
      eyeColor: "warmBrown",
      personality: "sleepy"
    }
  };

  variationCards.forEach((card) => {
    card.addEventListener("click", () => {
      variationCards.forEach((c) => c.classList.remove("active"));
      card.classList.add("active");

      const presetKey = card.getAttribute("data-preset");
      const chosen = presets[presetKey];
      if (chosen) {
        customState = { ...chosen };
        syncControls();
        updatePreview();
      }
    });
  });

  // Initial Sync
  syncControls();
  updatePreview();

  // ------------------------------------------------------------------------
  // Mobile Navigation Drawer Toggle & Accessibility Handlers
  // ------------------------------------------------------------------------
  const mobileNavToggle = document.getElementById("mobileNavToggle");
  const mobileNavMenu = document.getElementById("mobileNavMenu");

  if (mobileNavToggle && mobileNavMenu) {
    const toggleMenu = (open) => {
      const isOpen = open !== undefined ? open : !mobileNavMenu.classList.contains("active");
      mobileNavMenu.classList.toggle("active", isOpen);
      mobileNavToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
      mobileNavMenu.setAttribute("aria-hidden", isOpen ? "false" : "true");
      if (isOpen) {
        document.body.style.overflow = "hidden";
      } else {
        document.body.style.overflow = "";
      }
    };

    mobileNavToggle.addEventListener("click", () => {
      toggleMenu();
    });

    const mobileLinks = mobileNavMenu.querySelectorAll("a");
    mobileLinks.forEach((link) => {
      link.addEventListener("click", () => {
        toggleMenu(false);
      });
    });

    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && mobileNavMenu.classList.contains("active")) {
        toggleMenu(false);
        mobileNavToggle.focus();
      }
    });

    document.addEventListener("click", (e) => {
      const header = document.querySelector(".site-header");
      if (header && !header.contains(e.target) && mobileNavMenu.classList.contains("active")) {
        toggleMenu(false);
      }
    });
  }

  // ------------------------------------------------------------------------
  // Privacy Modal Sheet Handlers (Native <dialog>)
  // ------------------------------------------------------------------------
  const privacyModal = document.getElementById("privacyModal");
  const openPrivacyBtn = document.getElementById("openPrivacyBtn");
  const closePrivacyBtn = document.getElementById("closePrivacyBtn");
  const dismissPrivacyBtn = document.getElementById("dismissPrivacyBtn");

  if (privacyModal && openPrivacyBtn) {
    openPrivacyBtn.addEventListener("click", () => {
      if (typeof privacyModal.showModal === "function") {
        privacyModal.showModal();
      } else {
        privacyModal.setAttribute("open", "");
      }
    });

    const closeDialog = () => {
      if (typeof privacyModal.close === "function") {
        privacyModal.close();
      } else {
        privacyModal.removeAttribute("open");
      }
      openPrivacyBtn.focus();
    };

    if (closePrivacyBtn) closePrivacyBtn.addEventListener("click", closeDialog);
    if (dismissPrivacyBtn) dismissPrivacyBtn.addEventListener("click", closeDialog);

    // Close when clicking dialog backdrop
    privacyModal.addEventListener("click", (e) => {
      const rect = privacyModal.getBoundingClientRect();
      const isInDialog = (rect.top <= e.clientY && e.clientY <= rect.top + rect.height &&
        rect.left <= e.clientX && e.clientX <= rect.left + rect.width);
      if (!isInDialog) {
        closeDialog();
      }
    });
  }

  // ------------------------------------------------------------------------
  // Footer Back to Top Button
  // ------------------------------------------------------------------------
  const backToTopBtn = document.getElementById("backToTopBtn");
  if (backToTopBtn) {
    backToTopBtn.addEventListener("click", () => {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  // ------------------------------------------------------------------------
  // Dual-Platform Release Management (Windows & macOS)
  // ------------------------------------------------------------------------
  const heroSelectWin = document.getElementById("heroSelectWin");
  const heroSelectMac = document.getElementById("heroSelectMac");
  const downloadSelectWin = document.getElementById("downloadSelectWin");
  const downloadSelectMac = document.getElementById("downloadSelectMac");

  const downloadBtn = document.getElementById("downloadBtn");
  const heroBtnLabel = document.getElementById("heroBtnLabel");
  const heroReleaseTag = document.getElementById("heroReleaseTag");

  const downloadBadgeText = document.getElementById("downloadBadgeText");
  const downloadHeadline = document.getElementById("downloadHeadline");
  const downloadSubhead = document.getElementById("downloadSubhead");
  const downloadCardTitle = document.getElementById("downloadCardTitle");
  const downloadCardVersion = document.getElementById("downloadCardVersion");
  const downloadCardSpecs = document.getElementById("downloadCardSpecs");
  const mainDownloadBtn = document.getElementById("mainDownloadBtn");
  const mainDownloadBtnText = document.getElementById("mainDownloadBtnText");
  const downloadAltLinks = document.getElementById("downloadAltLinks");
  const compatGrid = document.getElementById("compatGrid");
  const installHeadline = document.getElementById("installHeadline");
  const installSubhead = document.getElementById("installSubhead");
  const installStepsContainer = document.getElementById("installStepsContainer");
  const securityNoticeTitle = document.getElementById("securityNoticeTitle");
  const securityNoticeDesc = document.getElementById("securityNoticeDesc");
  const platformAnnouncer = document.getElementById("platformAnnouncer");

  function detectInitialPlatform() {
    // 1. Saved user preference
    try {
      const saved = localStorage.getItem("cookie_platform");
      if (saved && (saved === "windows" || saved === "mac")) {
        return saved;
      }
    } catch (e) {
      // Ignore localStorage exceptions in restrictive sandbox / privacy mode
    }

    // 2. Client Hints API if available
    if (navigator.userAgentData && navigator.userAgentData.platform) {
      const p = navigator.userAgentData.platform.toLowerCase();
      if (p.includes("win")) return "windows";
      if (p.includes("mac") || p.includes("ios")) return "mac";
    }

    // 3. Fallback to navigator.userAgent / navigator.platform
    const ua = (navigator.userAgent || "").toLowerCase();
    const plat = (navigator.platform || "").toLowerCase();

    if (plat.includes("win") || ua.includes("windows")) {
      return "windows";
    }
    if (plat.includes("mac") || ua.includes("macintosh") || ua.includes("mac os x")) {
      return "mac";
    }

    // Default to macOS as the flagship platform
    return "mac";
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function setPlatform(platformId, persist = true, announce = false) {
    const releasesObj = (typeof window !== "undefined" && window.CookieReleases) ||
                        (typeof CookieReleases !== "undefined" ? CookieReleases : null);
    if (!releasesObj) return;

    if (!releasesObj[platformId]) {
      platformId = "mac";
    }

    if (persist) {
      try {
        localStorage.setItem("cookie_platform", platformId);
      } catch (e) {
        // Ignore localStorage restrictions
      }
    }

    const rel = releasesObj[platformId];
    if (!rel) return;
    const isWin = platformId === "windows";

    // 1. Update Platform Selector Buttons (Hero & Download Section)
    const updatePill = (btnWin, btnMac) => {
      if (btnWin && btnMac) {
        btnWin.classList.toggle("active", isWin);
        btnWin.setAttribute("aria-checked", isWin ? "true" : "false");
        btnMac.classList.toggle("active", !isWin);
        btnMac.setAttribute("aria-checked", !isWin ? "true" : "false");
      }
    };

    updatePill(heroSelectWin, heroSelectMac);
    updatePill(downloadSelectWin, downloadSelectMac);

    // 2. Update Hero Action & Metadata
    if (downloadBtn && heroBtnLabel) {
      if (isWin) {
        const downloadUrl = (rel.isInstallerAvailable && rel.downloadUrl) ? rel.downloadUrl : rel.portable.downloadUrl;
        const artifactName = (rel.isInstallerAvailable && rel.artifactName) ? rel.artifactName : rel.portable.artifactName;
        downloadBtn.setAttribute("href", downloadUrl);
        downloadBtn.setAttribute("download", artifactName);
        heroBtnLabel.textContent = rel.heroButtonLabel;
      } else {
        downloadBtn.setAttribute("href", rel.downloadUrl);
        downloadBtn.setAttribute("download", rel.artifactName);
        heroBtnLabel.textContent = rel.heroButtonLabel;
      }
    }

    if (heroReleaseTag) {
      heroReleaseTag.textContent = rel.heroReleaseTag;
    }

    // 3. Update Download Section
    if (downloadBadgeText) {
      downloadBadgeText.textContent = `Cookie for ${rel.displayName} • Version ${rel.version}`;
    }
    if (downloadHeadline) {
      downloadHeadline.textContent = `Cookie for ${rel.displayName}`;
    }
    if (downloadSubhead) {
      downloadSubhead.textContent = isWin
        ? "A quiet desktop companion crafted with native Windows WPF and C#. Download the official installer (.exe) below."
        : "A quiet desktop companion crafted with native Mac technologies. Download the disk image below to get started.";
    }

    if (downloadCardTitle) {
      downloadCardTitle.textContent = `Cookie for ${rel.displayName}`;
    }
    if (downloadCardVersion) {
      downloadCardVersion.textContent = rel.cardMeta;
    }
    if (downloadCardSpecs) {
      downloadCardSpecs.innerHTML = isWin
        ? `<span>~54.5 MB Installer (.exe)</span><span class="meta-dot">·</span><span>Windows 10 &amp; 11 (x64)</span><span class="meta-dot">·</span><span>Free &amp; Open Source</span>`
        : `<span>~23 MB Disk Image</span><span class="meta-dot">·</span><span>Universal Binary</span><span class="meta-dot">·</span><span>Free &amp; Open Source</span>`;
    }

    if (mainDownloadBtn && mainDownloadBtnText) {
      if (isWin) {
        const downloadUrl = (rel.isInstallerAvailable && rel.downloadUrl) ? rel.downloadUrl : rel.portable.downloadUrl;
        const artifactName = (rel.isInstallerAvailable && rel.artifactName) ? rel.artifactName : rel.portable.artifactName;
        mainDownloadBtn.setAttribute("href", downloadUrl);
        mainDownloadBtn.setAttribute("download", artifactName);
        mainDownloadBtnText.textContent = "Download Cookie for Windows (.exe)";
      } else {
        mainDownloadBtn.setAttribute("href", rel.downloadUrl);
        mainDownloadBtn.setAttribute("download", rel.artifactName);
        mainDownloadBtnText.textContent = "Download for macOS (DMG)";
      }
    }

    // 4. Update Alternative Links & Honest Status Note
    if (downloadAltLinks) {
      if (isWin) {
        downloadAltLinks.innerHTML = `
          <div class="installer-status-box" style="margin-top: 16px; padding: 14px 18px; background: rgba(46, 125, 50, 0.05); border-radius: 10px; border: 1px solid rgba(46, 125, 50, 0.22); font-size: 0.88rem; color: var(--soft-brown); text-align: left;">
            <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap;">
              <strong style="color: var(--charcoal); display: inline-flex; align-items: center; gap: 6px;">
                <span class="status-dot" style="background: #2e7d32;"></span>
                Official Windows Installer (Cookie-Setup.exe):
              </strong>
              <span class="parity-badge badge-active" style="font-size: 0.72rem; padding: 2px 8px; background: rgba(46, 125, 50, 0.12); color: #2e7d32; border-color: rgba(46, 125, 50, 0.3);">Verified Release</span>
            </div>
            <div style="margin-top: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.76rem; color: var(--muted-sage); word-break: break-all;">
              SHA256: ${rel.sha256}
            </div>
            <div style="margin-top: 12px; padding-top: 10px; border-top: 1px dashed rgba(46, 125, 50, 0.25); display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px;">
              <span style="font-size: 0.82rem; color: var(--charcoal);">Prefer a portable standalone version?</span>
              <a href="${rel.portable.downloadUrl}" download="${rel.portable.artifactName}" class="alt-portable-link" style="color: var(--caramel); font-weight: 600; text-decoration: underline; font-size: 0.82rem; display: inline-flex; align-items: center; gap: 4px;">
                Download Portable Zip (${rel.portable.formattedSize}) →
              </a>
            </div>
          </div>
        `;
      } else {
        downloadAltLinks.innerHTML = `
          <div style="margin-top: 14px; font-size: 0.82rem; color: var(--muted-sage); text-align: center; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;">
            <span>SHA256: ${rel.sha256}</span>
            <span class="meta-dot">·</span>
            <span>Universal arm64 / x86_64</span>
          </div>
        `;
      }
    }

    // 5. Render Compatibility Specs Grid
    if (compatGrid && rel.specs) {
      compatGrid.innerHTML = rel.specs.map(s => `
        <div class="compat-card">
          <div class="compat-icon-badge">
            <span class="compat-pill-text">${escapeHtml(s.pill)}</span>
          </div>
          <h3 class="compat-card-title">${escapeHtml(s.title)}</h3>
          <p class="compat-card-desc">${escapeHtml(s.desc)}</p>
        </div>
      `).join("");
    }

    // 6. Render Installation Steps
    if (installHeadline) {
      installHeadline.textContent = `Installing Cookie on ${rel.displayName}`;
    }
    if (installSubhead) {
      installSubhead.textContent = isWin
        ? "Clean per-user installation with desktop shortcut. No admin elevation or system clutter."
        : "Simple drag-and-drop installation. No root privileges or complex setup needed.";
    }
    if (installStepsContainer && rel.installSteps) {
      installStepsContainer.innerHTML = rel.installSteps.map(step => `
        <div class="install-step-card">
          <div class="step-badge">${step.step}</div>
          <div class="step-content">
            <h3 class="step-title">${escapeHtml(step.title)}</h3>
            <p class="step-desc">${escapeHtml(step.desc)}</p>
          </div>
        </div>
      `).join("");
    }

    // 7. Security Notice
    if (securityNoticeTitle && securityNoticeDesc && rel.securityNotes) {
      securityNoticeTitle.textContent = rel.securityNotes.title;
      securityNoticeDesc.textContent = rel.securityNotes.desc;
    }

    // 8. Accessibility Announcement
    if (announce && platformAnnouncer) {
      platformAnnouncer.textContent = `Selected platform changed to ${rel.displayName}. Download button updated.`;
    }
  }

  function setupPlatformGroup(groupSelector) {
    const wrap = document.querySelector(groupSelector);
    if (!wrap) return;

    const buttons = Array.from(wrap.querySelectorAll(".platform-pill-btn"));
    buttons.forEach((btn, idx) => {
      btn.addEventListener("click", () => {
        const plat = btn.getAttribute("data-platform");
        setPlatform(plat, true, true);
      });

      btn.addEventListener("keydown", (e) => {
        let targetIdx = null;
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
          e.preventDefault();
          targetIdx = (idx - 1 + buttons.length) % buttons.length;
        } else if (e.key === "ArrowRight" || e.key === "ArrowDown") {
          e.preventDefault();
          targetIdx = (idx + 1) % buttons.length;
        } else if (e.key === "Home") {
          e.preventDefault();
          targetIdx = 0;
        } else if (e.key === "End") {
          e.preventDefault();
          targetIdx = buttons.length - 1;
        }

        if (targetIdx !== null) {
          const targetBtn = buttons[targetIdx];
          targetBtn.focus();
          const plat = targetBtn.getAttribute("data-platform");
          setPlatform(plat, true, true);
        }
      });
    });
  }

  // Setup platform selectors in Hero and Download sections
  setupPlatformGroup(".hero-section .platform-selector");
  setupPlatformGroup(".download-section .platform-selector");

  // Initial detection & render
  const initialPlatform = detectInitialPlatform();
  setPlatform(initialPlatform, false, false);
});
