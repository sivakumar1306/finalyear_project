# Review-III presentation

`Review3_Presentation.pptx` is the Review-III template filled with the project content
(23 slides, speaker notes on every slide).

To rebuild it after changing `build_deck.py`:

```sh
python3 build_deck.py Review3_Template.pptx logo.png ../report/img ../report raw.pptx
```

then remove the unused template slides (the pptx skill's `clean.py`) and repack.
