# File Upload

## Problem
File inputs are often hidden behind styled buttons. `browser-use state` may not show the file input, or the index may point to a wrapper element instead.

## Strategy
1. Use `browser-use upload <index> <path>` first (simplest)
2. If that fails, find the hidden `<input type="file">` via eval and set files programmatically
3. For drag-and-drop uploads, use JS to dispatch drop events

## Commands

### Standard upload (visible input)
```bash
browser-use upload 5 /path/to/file.pdf
```

### Upload via hidden input
```bash
browser-use eval "
  const input = document.querySelector('input[type=\"file\"]');
  const dt = new DataTransfer();
  const file = new File(['content'], 'filename.txt', {type: 'text/plain'});
  dt.items.add(file);
  input.files = dt.files;
  input.dispatchEvent(new Event('change', {bubbles: true}));
  'uploaded'
"
```

### Upload via clicking the styled button first
```bash
# Click the visible upload button, then use the hidden input
browser-use click 8
# The click may open a native file dialog — use upload on the file input
browser-use eval "document.querySelector('input[type=file]').id = 'file-input-found'"
browser-use upload <index-of-file-input> /path/to/file.pdf
```

### Multiple files
```bash
browser-use eval "
  const input = document.querySelector('input[type=\"file\"]');
  const dt = new DataTransfer();
  ['file1.txt', 'file2.txt'].forEach(name => {
    dt.items.add(new File(['content'], name, {type: 'text/plain'}));
  });
  input.files = dt.files;
  input.dispatchEvent(new Event('change', {bubbles: true}));
  'uploaded ' + input.files.length + ' files'
"
```

## Fallback
- If JS file creation doesn't work (content too large or binary), use `browser-use --headed` and ask user to manually select files
- For remote browsers, the file must exist on the remote machine — use `browser-use eval` to create the file content first
