# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w[ admin.js admin.css ]

# Add Stimulus controllers to precompile list (even though they're served via importmap)
# This prevents Sprockets from complaining in test environment
Rails.application.config.assets.precompile += %w[
  prompt_tracker/controllers/evaluator_form_controller.js
  prompt_tracker/controllers/evaluator_config_form_controller.js
]
