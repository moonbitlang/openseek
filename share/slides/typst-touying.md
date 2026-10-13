# Touying for PDF Animations

Use Touying only when the user needs PDF frame animations, such as progressive reveals with `#pause`, parallel reveal sequences with `#meanwhile`, or stepwise math equation animations. Use plain Typst for static slides.

```typst
#import "@preview/touying:0.7.4": *
```

PDF animations work by advancing through multiple pages (subslides) representing successive states of a logical slide. See the official [Dynamic Slides guide](https://touying-typ.github.io/docs/category/dynamic-slides).

Consult the [official tutorials](https://touying-typ.github.io/docs/category/tutorials) when implementing Touying features. Follow their setup and examples, check compatibility with the pinned version, and verify unfamiliar APIs rather than guessing syntax.

- [Simple animations](https://touying-typ.github.io/docs/tutorials/dynamic/simple): `#pause` and `#meanwhile`.
- [Math equation animations](https://touying-typ.github.io/docs/tutorials/dynamic/equation): reveal equations and derivations step by step.
