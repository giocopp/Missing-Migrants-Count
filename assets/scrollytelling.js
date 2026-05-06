// ============================================================
// Scrollytelling — fades each .reveal scene in as the reader scrolls.
//
// The .reveal-mode tag on <html> is set inline at the top of <body> in
// article.html so it activates before any scene is painted (avoiding a
// flash of visible content under a deferred script). This file only
// wires up the IntersectionObserver that adds .is-visible as scenes
// enter the viewport, with graceful fallbacks for reduced-motion and
// browsers without IntersectionObserver.
// ============================================================

document.addEventListener('DOMContentLoaded', function () {
  var revealEls = document.querySelectorAll('.reveal');
  if (!revealEls.length) return;

  var reduce = window.matchMedia &&
               window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || !('IntersectionObserver' in window)) {
    revealEls.forEach(function (el) { el.classList.add('is-visible'); });
    return;
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) {
        e.target.classList.add('is-visible');
        io.unobserve(e.target);   // one-shot reveal
      }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });

  revealEls.forEach(function (el) { io.observe(el); });
});
