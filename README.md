# swift-inpaint

On-device **object / logo / watermark removal** via **LaMa** (Apache) — give it
an image + a mask of what to remove (white = remove), get a plausibly filled
result. Pairs with a mask source like SAM 2 (see swift-object-cutout).

- `LaMaInpainter` — wraps the LaMa Core ML model (image + mask → filled at
  800×800); the fill is composited back onto the full-resolution original so
  only the masked region changes.

```swift
let inpainter = try LaMaInpainter(modelURL: lamaURL)
let cleaned = inpainter.inpaint(frame, mask: whereToRemove)   // white = remove
```

Model: `jerhoads/lama-coreml` (LaMa weights are Apache-2.0; ~196 MB fp32,
quantizable). Best on small objects / logos / watermarks; large-region removal
can leave a faint ghost, and per-frame video removal of a *moving* object
flickers (static object / locked-off shot = fill-once-and-hold is clean).
Requirements: macOS 26 / iOS 26, Swift 6.2.
