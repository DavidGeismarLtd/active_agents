# Client Setup: Pure Webpacker (Without Importmap)

⚠️ **Note**: This approach is more complex than using importmap. We recommend installing importmap-rails even if you use Webpacker. See [Quick Fix](QUICK_FIX_WEBPACKER.md) for the easier approach.

## Prerequisites

- Webpacker or Shakapacker installed
- Node.js and Yarn/NPM

## Step-by-Step Setup

### 1. Update Gemfile

```ruby
gem "prompt_tracker", git: "https://github.com/DavidGeismarLtd/PromptTracker.git"
```

```bash
bundle install
```

### 2. Install JavaScript Dependencies

```bash
yarn add @hotwired/turbo-rails @hotwired/stimulus @hotwired/stimulus-loading
```

Or with npm:

```bash
npm install @hotwired/turbo-rails @hotwired/stimulus @hotwired/stimulus-loading
```

### 3. Create Symlink to Engine Assets

This is the easiest way to make PromptTracker's JavaScript available to Webpacker:

```bash
cd app/javascript
ln -s $(bundle show prompt_tracker)/app/javascript/prompt_tracker prompt_tracker
```

Verify the symlink:

```bash
ls -la app/javascript/prompt_tracker
# Should show: prompt_tracker -> /path/to/gems/prompt_tracker-.../app/javascript/prompt_tracker
```

### 4. Import PromptTracker in Your Pack

**File: `app/javascript/packs/application.js`**

```javascript
// Your existing imports
import Rails from "@rails/ujs"
import "@hotwired/turbo-rails"
import "controllers"

// Add PromptTracker
import "prompt_tracker/application"

// Your other imports...
```

### 5. Mount the Engine

**File: `config/routes.rb`**

```ruby
Rails.application.routes.draw do
  mount PromptTracker::Engine, at: "/prompt_tracker"
  
  # Your other routes...
end
```

### 6. Run Migrations

```bash
bin/rails prompt_tracker:install:migrations
bin/rails db:migrate
```

### 7. Recompile Assets

```bash
bin/webpack
```

Or if using webpack-dev-server:

```bash
bin/webpack-dev-server
```

### 8. Start Your Server

```bash
bin/rails server
```

Visit: http://localhost:3000/prompt_tracker

## Troubleshooting

### Error: Cannot resolve 'prompt_tracker/application'

**Cause**: Symlink not created or pointing to wrong location.

**Fix**:

```bash
# Remove old symlink if exists
rm app/javascript/prompt_tracker

# Recreate symlink
cd app/javascript
ln -s $(bundle show prompt_tracker)/app/javascript/prompt_tracker prompt_tracker
```

### Error: Module not found after `bundle update`

**Cause**: The gem path changed (different commit hash in folder name).

**Fix**: Recreate the symlink:

```bash
cd app/javascript
rm prompt_tracker
ln -s $(bundle show prompt_tracker)/app/javascript/prompt_tracker prompt_tracker
bin/webpack
```

### Stimulus Controllers Not Working

**Cause**: Stimulus not properly configured.

**Fix**: Make sure you have Stimulus installed and configured:

```bash
yarn add @hotwired/stimulus @hotwired/stimulus-loading
```

**File: `app/javascript/controllers/application.js`**

```javascript
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false
window.Stimulus = application

export { application }
```

### Webpacker Compilation Errors

If you see errors like "Can't resolve module", try:

1. **Clear cache**:
```bash
bin/rails tmp:clear
rm -rf public/packs
rm -rf tmp/cache/webpacker
```

2. **Reinstall node_modules**:
```bash
rm -rf node_modules
yarn install
```

3. **Recompile**:
```bash
bin/webpack
```

## Maintenance

### After Each `bundle update prompt_tracker`

You need to recreate the symlink:

```bash
cd app/javascript
rm prompt_tracker
ln -s $(bundle show prompt_tracker)/app/javascript/prompt_tracker prompt_tracker
bin/webpack
```

### Automation Script

Create `bin/update_prompt_tracker`:

```bash
#!/bin/bash
set -e

echo "Updating PromptTracker..."
bundle update prompt_tracker

echo "Recreating symlink..."
cd app/javascript
rm -f prompt_tracker
ln -s $(bundle show prompt_tracker)/app/javascript/prompt_tracker prompt_tracker
cd ../..

echo "Running migrations..."
bin/rails prompt_tracker:install:migrations
bin/rails db:migrate

echo "Recompiling assets..."
bin/webpack

echo "✅ PromptTracker updated successfully!"
```

Make it executable:

```bash
chmod +x bin/update_prompt_tracker
```

Usage:

```bash
bin/update_prompt_tracker
```

## Why We Recommend Importmap Instead

This pure Webpacker approach has several drawbacks:

1. ❌ **Manual symlink management** after each update
2. ❌ **Longer compilation times** (Webpacker needs to process engine assets)
3. ❌ **More complex troubleshooting**
4. ❌ **Potential version conflicts** with JavaScript dependencies

**With importmap-rails**:

1. ✅ **Zero configuration** needed
2. ✅ **No symlinks** to manage
3. ✅ **Instant updates** with `bundle update`
4. ✅ **Complete isolation** from your app's Webpacker

**To switch to importmap**:

```bash
bundle add importmap-rails
bin/rails importmap:install
rm app/javascript/prompt_tracker  # Remove symlink
# Remove "import prompt_tracker/application" from your pack
bin/rails server
```

See [Quick Fix Guide](QUICK_FIX_WEBPACKER.md) for details.

## Need Help?

- Check [Troubleshooting Guide](troubleshooting/webpacker_importmap_conflict.md)
- Open an issue on GitHub
- See [Documentation Index](README.md)

