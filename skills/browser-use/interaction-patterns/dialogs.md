# Browser Dialogs & Alerts

## Problem
Native browser dialogs (`alert`, `confirm`, `prompt`, `beforeunload`) block the page. `browser-use state` and `click` hang until the dialog is dismissed. File download dialogs are OS-level and can't be controlled by CDP.

## Strategy
1. Pre-empt: dismiss dialogs via JavaScript override before they appear
2. React: use CDP to accept/dismiss dialogs that already appeared
3. Downloads: configure download path and wait for file to appear

## Commands

### Pre-empt: suppress all dialogs
```bash
browser-use eval "
  window.__origAlert = window.alert;
  window.alert = () => {};
  window.confirm = () => true;
  window.prompt = () => '';
  'dialogs suppressed'
"
```

### Handle dialog via CDP (already showing)
```bash
# Via Python — access the CDP session directly
browser-use python "
import asyncio
page = browser.page
async def handle_dialog():
    async with page.context.expect_event('dialog') as dialog_info:
        pass  # dialog will be caught
    dialog = await dialog_info.value
    await dialog.accept()
asyncio.get_event_loop().run_until_complete(handle_dialog())
"
```

### Download files
```bash
# Set download path first
browser-use eval "
  // Downloads go to the browser's default download directory
  // Check where they go:
  JSON.stringify({downloadPath: 'check browser downloads folder'})
"

# Trigger download
browser-use click <download-button-index>

# Verify download completed (wait for file)
# This depends on the browser's download directory configuration
```

### Print dialog
Native print dialogs (`window.print()`) can't be dismissed via CDP. Pre-empt:
```bash
browser-use eval "window.print = () => { console.log('print suppressed') }"
```

## Fallback
- If a dialog is already blocking and CDP can't dismiss it, close the tab and reopen
- For download verification, check the file system after a reasonable wait
