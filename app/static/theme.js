/* Tailwind-farver -> temaets palet (se app/static/theme.css).
   Skal indlaeses EFTER cdn.tailwindcss.com, saa markup som bg-zinc-900,
   text-emerald-400 og border-rose-500/30 faar messing/læder-farverne uden at
   klasserne i skabelonerne aendres. */
(function () {
  if (typeof tailwind === "undefined") return;

  var SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950];

  function scale(name) {
    var out = {};
    SHADES.forEach(function (s) {
      out[s] = "rgb(var(--cc-" + name + "-" + s + ") / <alpha-value>)";
    });
    return out;
  }

  tailwind.config = {
    theme: {
      extend: {
        colors: {
          zinc: scale("ink"),      // graa flader og tekst -> varm lædergraa
          emerald: scale("brass"), // primaer accent      -> messing
          amber: scale("copper"),  // advarsler           -> kobber
          rose: scale("oxblood"),  // fejl                -> okseblod
          red: scale("oxblood"),
          yellow: scale("brass"),
          purple: scale("patina")  // AI/sekundaer        -> irr
        },
        fontFamily: {
          sans: ['"Inter"', "ui-sans-serif", "system-ui", "-apple-system", '"Segoe UI"', "sans-serif"],
          display: ['"Cormorant Garamond"', '"Iowan Old Style"', "Georgia", "serif"]
        },
        borderRadius: { xl: "0.55rem", "2xl": "0.8rem" }
      }
    }
  };
})();
