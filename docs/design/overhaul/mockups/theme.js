// Applies ?theme=light|redNight from the URL so render.sh can capture each palette without separate files.
(function () { const t = new URLSearchParams(location.search).get("theme"); if (t) document.documentElement.setAttribute("data-theme", t); })();
