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
  // 3. Chapter 2: "Sometimes curious." (Cursor Tracking Stage)
  // ------------------------------------------------------------------------
  const curiousStage = document.getElementById("curiousStage");
  const curiousCat = document.getElementById("curiousCat");
  const curiousPointer = document.getElementById("curiousPointer");
  const curiousCatImg = document.getElementById("curiousCatImg");
  const curiousCatWebp = document.getElementById("curiousCatWebp");

  if (curiousStage && curiousCat) {
    let isClose = false;

    curiousStage.addEventListener("mousemove", (e) => {
      const rect = curiousStage.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const mouseY = e.clientY - rect.top;

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
    });

    curiousStage.addEventListener("mouseleave", () => {
      curiousCat.style.transform = "translate(0, 0) rotate(0deg)";
      isClose = false;
      if (curiousCatImg) curiousCatImg.src = "assets/hero-cookie-open.png";
      if (curiousCatWebp) curiousCatWebp.srcset = "assets/hero-cookie-open.webp";
    });
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
      dragDistance += Math.hypot(e.movementX, e.movementY);

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
  // 7. Chapter 6: Customizer Atelier (Personalities & Looks)
  // ------------------------------------------------------------------------
  const customizerCatView = document.getElementById("customizerCatView");
  const customizerImg = document.getElementById("customizerImg");
  const customizerWebp = document.getElementById("customizerWebp");
  const customizerDesc = document.getElementById("customizerDesc");

  const personalityPills = document.querySelectorAll("#personalityPills .style-pill");
  const accessoryPills = document.querySelectorAll("#accessoryPills .style-pill");

  let currentMood = "calm";
  let currentStyle = "classic";

  const personalityDescriptions = {
    "calm": "<strong>Calm & Gentle:</strong> Naps peacefully beside your windows, strolls slowly, and brings quiet focus to your day.",
    "playful": "<strong>Playful & Curious:</strong> Loves following your cursor, chases yarn balls, and trots around your workspace with curiosity.",
    "sleepy": "<strong>Sleepyhead:</strong> A master of naps. Spends cozy hours curled up next to cardboard boxes, conserving CPU.",
    "sassy": "<strong>Sassy & Bold:</strong> Independent and proud. Swishes her tail, bats at toys, and commands your desktop presence."
  };

  const updateCustomizerView = () => {
    // Choose appropriate sprite based on style preference first, then mood
    let spriteName = "cookie";

    if (currentStyle === "cool") {
      spriteName = "cookie-cool";
    } else if (currentStyle === "shy") {
      spriteName = "cookie-shy";
    } else if (currentStyle === "mischief") {
      spriteName = "cookie-mischievous";
    } else {
      // Classic look, reflect mood
      if (currentMood === "sleepy") spriteName = "cookie-sleep";
      else if (currentMood === "playful") spriteName = "cookie-walk";
      else if (currentMood === "sassy") spriteName = "cookie-angry";
      else spriteName = "cookie";
    }

    if (customizerImg && customizerWebp) {
      customizerImg.src = `assets/${spriteName}.png`;
      customizerWebp.srcset = `assets/${spriteName}.webp`;

      // Tactile bounce on avatar switch
      if (customizerCatView) {
        customizerCatView.style.transform = "scale(1.08) translateY(-4px)";
        setTimeout(() => {
          customizerCatView.style.transform = "";
        }, 200);
      }
    }

    if (customizerDesc && personalityDescriptions[currentMood]) {
      customizerDesc.innerHTML = personalityDescriptions[currentMood];
    }
  };

  personalityPills.forEach((pill) => {
    pill.addEventListener("click", () => {
      personalityPills.forEach((p) => p.classList.remove("active"));
      pill.classList.add("active");
      currentMood = pill.getAttribute("data-mood") || "calm";
      updateCustomizerView();
    });
  });

  accessoryPills.forEach((pill) => {
    pill.addEventListener("click", () => {
      accessoryPills.forEach((p) => p.classList.remove("active"));
      pill.classList.add("active");
      currentStyle = pill.getAttribute("data-style") || "classic";
      updateCustomizerView();
    });
  });
});
