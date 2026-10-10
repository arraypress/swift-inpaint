# swift-inpaint

On-device **object, text, logo and watermark removal** via **LaMa** — say
what to remove, get the picture back with it gone. Nothing is uploaded.

```swift
let inpainter = try LaMaInpainter(modelURL: lamaURL)

// Two steps, so you can see what matched before anything changes.
let mask = try await Eraser.mask(for: [.text(matching: "shutterstock")], in: photo)
mask.regions      // [FoundRegion(kind: .text, rect: …, text: "Shutterstock")]
mask.isLarge      // false — under a fifth of the frame

let clean = try inpainter.erase(photo, mask: mask.image)
```

## What can be erased

| Target | How it is found |
|---|---|
| `.rectangle(CGRect)` | as given, top-left origin pixels — the convention `img crop` and `img detect` use |
| `.text(matching: "phrase")` | Vision text recognition; **only the phrase**, wherever it appears, not the rest of its line |
| `.text(matching: nil)` | every line of text |
| `.people` | Vision's person outlines, kept only where its body detector agrees (see below) |
| a painted mask | `extraMask:`, white = remove |

Every mask is grown by 6 px by default (`growth:`) so the anti-aliased fringe and
any drop shadow go with the thing itself, and the fill is composited back so
**pixels outside the mask are untouched** — measured as exactly zero change.

## Measured

On a synthetic scene whose background is known — a soft gradient under bold
diagonal stripes — with a centred square erased and the fill compared to what
was really there (mean absolute error out of 255, after a 3 px blur):

| Square | Share of frame | LaMa | Flat average-colour fill |
|---|---|---|---|
| 80 px | 0.4% | **2.7** | 17.5 |
| 320 px | 6.4% | **5.7** | 18.2 |
| 500 px | 15.6% | **6.5** | 18.4 |
| 600 px | 22.5% | 14.7 | 18.5 |
| 700 px | 30.6% | 31.8 | **18.7** |
| 900 px | 50.6% | 39.0 | **19.0** |

LaMa carries the stripes through the hole and is about three times better than
a flat fill — until the hole is a fifth of the frame. Past that it leaves a dark
ghost over the middle and from 30% it is *worse* than a flat colour. So
``EraseMask/coverage`` is reported with every mask and ``EraseMask/isLarge``
flips at 20%. A 1600×1000 image takes 0.24 s after a first call of about 0.5–1 s
that compiles and loads the model.

**The person detector, alone, sees people in text.** `GeneratePersonInstanceMaskRequest`
returned a "person" covering 15% of a card with nothing on it but two lines of
type, at an observation confidence of 1.0 (not a per-person score). Erasing it
would have taken the caption. An outline is now kept only where
`DetectHumanRectanglesRequest` also finds a body at 0.3 or more. **Not yet
measured on real photographs of people.**

## The model

LaMa (Big-LaMa weights, Apache-2.0) as Core ML: `jerhoads/lama-coreml` on Hugging
Face (~196 MB fp32, 800×800 in and out). That conversion repo states **no
licence of its own**, so this package neither bundles nor redistributes it.
`.mlpackage` files are compiled once and cached in `Caches/swift-inpaint`.

Best on small objects, logos, watermarks and text. Per-frame video removal of a
*moving* object flickers; a static object in a locked-off shot is clean when
filled once and held.

## Layout

- `Core/` — `LaMaInpainter` (the model, `erase` and the original `inpaint`
  on `CIImage`), `Eraser` (targets → mask)
- `Support/` — `RegionPlanner` (where the model looks: a square-ish window
  1.7× the content, never under 320 px, always covering it), `MaskBuilder`,
  `RegionFinder` (Vision)
- `Models/`, `Enums/`, `Errors/`

## Requirements

macOS 26 / iOS 26, Swift 6.2.

## License

MIT — see [LICENSE](LICENSE). Downloaded models keep their own licences.
