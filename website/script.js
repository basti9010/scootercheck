(() => {
  const steps = document.querySelectorAll(".flow__step");
  if (!steps.length) return;

  if (!("IntersectionObserver" in window)) {
    steps.forEach((el) => el.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.25, rootMargin: "0px 0px -8% 0px" }
  );

  steps.forEach((el) => observer.observe(el));
})();
