# Pin npm packages by running ./bin/importmap
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.esm.min.js"
pin "@popperjs/core", to: "https://cdn.jsdelivr.net/npm/@popperjs/core@2.11.8/dist/esm/index.js"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js"
# Engine JavaScript is now loaded via the engine's own config/importmap.rb
