// Cookie — Interactive Website Enhancements
document.addEventListener("DOMContentLoaded", () => {
  // 1. Hero Cookie Interactive Click (Purr & Boop)
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
      // Pick next quote
      petToast.textContent = purrQuotes[quoteIndex % purrQuotes.length];
      quoteIndex++;
      
      // Add active state
      petToast.classList.add("active");
      
      // Subtle tactile bounce
      cookieActor.style.transform = "scale(1.05) translateY(-6px)";
      setTimeout(() => {
        cookieActor.style.transform = "";
      }, 200);

      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        petToast.classList.remove("active");
      }, 1800);
    });
  }

  // 2. Care & Treats Interactive Tray
  const itemChips = document.querySelectorAll(".item-chip");
  const reactionText = document.getElementById("reactionText");
  const reactionIcon = document.getElementById("reactionIcon");

  const reactions = {
    "fish": { icon: "🐟", text: "Cookie's ears perk up immediately. She scampers over and chomps down happily." },
    "tuna": { icon: "🥫", text: "The aroma of savory tuna makes Cookie knead her paws on the desk with deep purrs." },
    "cookie": { icon: "🍪", text: "A little crunchy cat biscuit! Cookie nibbles delicately, crumbs and all." },
    "catnip": { icon: "🌿", text: "Cookie rolls onto her back, rubbing her cheeks against the floor in pure bliss." },
    "box": { icon: "📦", text: "If she fits, she sits. Cookie dives head-first into the cardboard box and peeks out." },
    "yarn": { icon: "🧶", text: "Cookie bats the warm wool yarn across the screen, pouncing and tumbling." },
    "feather": { icon: "🪶", text: "Eyes wide and dilated, Cookie wiggles her hindquarters and leaps for the feather!" },
    "bell": { icon: "🔔", text: "Jingle jingle! Cookie gives the little bell a gentle tap with her right paw." }
  };

  itemChips.forEach((chip) => {
    chip.addEventListener("click", () => {
      itemChips.forEach((c) => c.classList.remove("active"));
      chip.classList.add("active");

      const itemKey = chip.getAttribute("data-item");
      const reaction = reactions[itemKey];
      if (reaction && reactionText && reactionIcon) {
        reactionIcon.textContent = reaction.icon;
        reactionText.textContent = reaction.text;
      }
    });
  });
});
