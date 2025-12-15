# Pin all JavaScript files from the engine
pin_all_from File.expand_path("../app/javascript/prompt_tracker", __dir__),
             under: "prompt_tracker",
             preload: true

# Pin Chart.js for analytics charts (UMD bundle includes all dependencies)
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js"
