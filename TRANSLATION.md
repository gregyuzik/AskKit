# Translating AskKit

AskKit owns the Ask screen's copy, so a string wrong here is wrong in every host, and no host's catalog
check scans a package: the maintainers' push gate grades these catalogs, with the String Catalog checker
all their apps share, and `scripts/check-strings.py` checks AskKit's source against them. This file sits
at the root because Xcode 27's agent-driven translation reads it there.

**Apple's style guides win.** Where a rule or row here disagrees with the locale's translation style
guide in Xcode 27, follow the guide and correct the row.

## The catalogs

| Catalog | Holds |
|---|---|
| `Sources/AskCore/Resources/Localizable.xcstrings` | The error copy: what the reader is told when a turn can't finish. |
| `Sources/AskUI/Resources/Localizable.xcstrings` | The screen: the wait row, the evidence line, the chips, the composer, the settings card. |

Both carry `en` and these 24, each with every translatable key before a push:
`ar cs da de es es-MX fr he id it ja ko nb nl pl pt-BR ru sv th tr uk vi zh-Hans zh-Hant`. The one
exemption is `"shouldTranslate": false` on the key. Copy that names the app (the title, the help text,
the first-screen sentences, any error line naming it) is the host's: it stays in the host's catalog and
reaches AskUI through `AskBrand`.

**`bundle: #bundle` on every lookup**, `String(localized: "…", bundle: #bundle)` and
`Text("…", bundle: #bundle)`, format-only keys too (`Text("\(a)\(b)")` looks up `"%@%@"`). `#bundle` is
the target's `Bundle.module`, under `swift build` and Xcode alike. Without it a lookup searches the
host's main bundle and returns the key: silently, and only outside English, where the key is the text.
A host's `AskDomain.phrase(for:)` resolves its own strings, so its adapter in a package needs `#bundle`
too, and the check never reads it.

## What the checks enforce

The shared checker grades the catalogs in the maintainers' push gate, which CI doesn't run.
`scripts/check-strings.py`, in `scripts/ci.sh checks`, grades the count keys' forms and the source, in
CI and the push gate alike. Each runs its own self-test first, then fails on any of these.

**A unit that isn't `"state": "translated"` with a value.** `needs_review`, the extractor's default, is
evidence that nobody translated the string, and an empty value renders as nothing. A locale a catalog
carries beyond English and the 24 above is reported too.

**A missing plural category**, wherever the plural sits: at the top of a localization, under a device
variation or inside a substitution.

| Locale | Required categories |
|---|---|
| ar | `zero` `one` `two` `few` `many` `other`: `zero` is 0, `two` exactly 2, `few` 3 to 10, `many` 11 to 99 |
| he | `one` `two` `other`: a count of exactly 2 reads wrong without the dual |
| cs pl ru uk | `one` `few` `many` `other` |
| id ja ko th vi zh-Hans zh-Hant | `other` |
| everything else | `one` `other` |

A superset passes: Spanish, French, Italian and Portuguese add `many` on some keys.
`scripts/check-strings.py` also fails a count key in a locale that gives every count the same form,
unless that locale needs only `other`. A key is a count key when its source passes an integer (`%lld`,
`%d`, `%u` and the rest) or inflects (`^[…](inflect: true)`), or any localization varies it by plural.
A key whose integer isn't a count, such as a percentage, goes in that script's `NOT_COUNTS` with the
reason.

**An argument whose specifier changed.** Foundation resolves a format against the call's arguments, not
the words around them, so argument N must carry the specifier the source gives argument N. Swap an
integer's and an object's specifiers, numbered or not, and the integer reaches `%@` as an object
pointer: the process crashes, in that locale only. One `%@` where the source has `%lld` does the same.
Nor may a translation read an argument the source doesn't pass: a `%@` added to a key that takes none,
such as `Answer ready`, fails too.

```
source:   From ^[%lld item](inflect: true) in your %@      (Int, String)
correct:  %2$@ içindeki %1$lld öğeden
wrong:    %@ içindeki %lld öğeden          reads the Int as an object
wrong:    %1$@ içindeki %2$lld öğeden      numbered, still swapped
```

It bites hardest where a plural category drops the numeral: Hebrew's dual, `מתוך שני פריטים ב%2$@`,
has no `%lld`, so without the `2$` its `%@` would be argument 1.

**A substitution reference read as a specifier.** Opening a plural key in Xcode rewrites the value
around one, `%1$@%#@items@`, moving the count into a `substitutions` entry with its own `argNum` and
`formatSpecifier` (`"items": { "argNum": 2, "formatSpecifier": "lld", … }`). The check reads
`%#@items@` through that entry, so it still catches a swapped number or type, and reports a reference
the localization doesn't declare.

**Thai's `[tt]` flag on the wrong placeholder.** `%[tt]@` (numbered `%2$[tt]@`) goes on a `%@` holding
a name against Thai text, and Foundation spaces a Latin value. The check reads it as a `%@` and refuses
`[tt]` on a number or before the position.

**The source, read from the other side.** A literal looked up with `bundle: #bundle` must be in its own
target's catalog. A localized literal with no bundle fails, as does a scan that finds no `#bundle`
literal at all, which would leave the check blind. A literal counts as a lookup in `Text`,
`String(localized:)` and the other calls `scripts/check-strings.py`'s `LOOKUP` names (the SwiftUI views
and modifiers that take a `LocalizedStringKey`, wrapped in `LocalizedStringKey("…")` or not), as
`.searchable`'s `prompt:` and as an element of `.accessibilityInputLabels`' array.

## What the checks can't see

**A key made away from its lookup.** A `LocalizedStringKey` held in a variable and passed in later, or
a literal in a call `LOOKUP` doesn't name, isn't read: its bundle and catalog entry go unchecked.

**The right-to-left mark.** A Hebrew or Arabic value that opens with a Latin name, as many open with
`Apple Intelligence` or `Private Cloud Compute`, starts with U+200F: a paragraph takes the direction of
its first strong character, so without the mark the whole line may lay out left to right. An Arabic
value ending in a Latin name or a placeholder, a full stop or ellipsis aside, ends with it too.

**A host's `%@` noun follows a fixed noun, never a possessive.** In the source's `in your %@` the host
fills in its own scope noun, in its own words, language, number and gender, so a translation can't
agree with it (`ton` or `ta`, `deinem` or `deiner`). Name the kind of thing and quote the host's word
after it, in the locale guide's quotes: `sección “%@”` (es, es-MX), `sektionen “%@”` (da),
`Bereich „%@“` (de), `section « %@ »` (fr) and `sektionen ”%@”` (sv). nb, it and tr have no possessive
to drop.

**No-break spaces (U+00A0)** inside `Apple Intelligence` and `Private Cloud Compute` in cs, de, es,
es-MX, fr, ko, nl, pl, ru, tr and uk, whose guides ask for them; fr joins two words at most
(`Private Cloud Compute`), and ja keeps the source's plain space. Also before de's ellipsis
(`wird gelesen …`) and, in cs, after a one-letter word (`a i k o s u v z`).

**A line that names the device or its Settings app carries a `mac` device variation** beside `other`:
`System Settings`, and `this Mac` for `this device`, as the system's own strings give them in the
locale. AskCore's `AskEnglishCatalogTests` checks the English pair.

**Not for translation.** `Text(verbatim:)` for anything that isn't words: a value, a name the reader
typed, glue. "Private Cloud Compute", a name, and `%@%@`, the reveal renderer's format-only key, are
`"shouldTranslate": false`. If `-exportLocalizations` runs, it adds an empty key and a bare `%@`: mark
them the same way, since it recreates them if deleted.

**The typographic apostrophe**, `’` (U+2019), in English and the Latin-script locales (`Sur l’appareil`,
`Ayarlar’dan`), and in Hebrew the *geresh* `׳` (U+05F3), not a quotation mark (`צ׳אט חדש`). The keys
keep the ASCII `'` that code and translations hang on, so an `en` value differs from its key there.
`AskEnglishCatalogTests`, in both test targets, fails an English line with a typewriter apostrophe.

**One register per locale, the one Apple's own copy uses**, in every string:

| Locale | Addressing the reader |
|---|---|
| fr, ru, tr | formal: `vous`; `Вы`, capitalized; `siz` (`deneyin`, `sorunuz`) |
| cs | formal `vy`: `Zkuste`, `vaše` |
| uk | formal `ви`: `Спробуйте`; "your" left out where the sentence reads without it (`у розділі %@`), a status line an action noun (`Міркування…`) |
| pl | second-person singular imperative (`Spróbuj`, `Zapytaj`), with `Twoje` capitalized; a progress line in the first person (`Czytam: %@…`) |
| id | `Anda`, left out where the sentence reads without it (`Ajukan pertanyaan lagi`); `obrolan` for chat, `app` for the app |
| th | `คุณ`, left out where the sentence reads without it; no `ค่ะ` or `ครับ` |
| ar | Modern Standard Arabic: `يمكنك` and `يرجى` for an instruction, a verbal noun for a button (`إضافة`, `كتابة`). Each name takes its gender in Apple's own Arabic: Apple Intelligence masculine (`ما زال`, `متوقف`), Private Cloud Compute feminine (`متاحة`), as `ذكاء Apple` and `الحوسبة السحابية الخاصة` are |
| da, de, nb, sv | `du` |
| es | `tú`, `tu`; the present perfect (`No se ha podido`), `Añadir`, `Ajustes`, `Prueba a` |
| es-MX | `tú`, `tu`, as Spain, with Mexico's words and tense: the preterite where Spain has the present perfect (`No se pudo`, kept over the es-419 guide's compound past), `Configuración`, `Agregar`, `Listo`, `Intenta` |
| it | `tu` |
| nl, pt-BR | `je`, `você` |
| vi | `bạn` |
| zh-Hans, zh-Hant | `你` |
| ja | です/ます, with "you" and "your" left out |
| ko | 합쇼체 for statements and ~세요 for instructions, never 당신 |
| he | gender-neutral: `ניתן ל־` or `יש ל־` for an instruction, a gerund for a button (`שליחה`, `ניסיון נוסף`), and no `שלך` where the definite article says it |

No native reader has checked the ar, cs, id, pl, th, uk and es-MX rows or Arabic's name genders; one
who does corrects the row and its strings. Outside Hebrew, a button's bare imperative (`Sil`,
`Kopyala`) is a command rather than address, as is a first-person status line (`Czytam…`).

**Right to left.** Check every horizontal layout in the demo in the right-to-left locales, Hebrew
(`-AppleLanguages (he)`) and Arabic (`-AppleLanguages (ar)`); `rotationEffect` isn't mirrored, even
where the layout is.

**Length.** Vietnamese and German run about 1.5 times English. A string in a fixed frame needs
`lineLimit` and `minimumScaleFactor`; one that is the only signal on screen, like the summarized marker,
wraps at full size with `fixedSize(horizontal: false, vertical: true)`, since German, Polish and
Vietnamese need three lines. A bare `fixedSize()` suits only a one-line label, like the tier caption.

## Editing a catalog

Edit in Xcode, by hand or by script, never by regenerating the file wholesale, which buries the real
change. The catalogs are the bytes Xcode 27.2 writes: `" : "` after a key, two-space indents, every map
sorted by key (by code point), non-ASCII kept and no final newline, so a script's default `json.dump`
fails the maintainers' push gate, which checks them byte for byte.
`json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)`, with
nothing after it, writes them, but for an empty map or list, which Xcode writes with a blank line
inside. After any edit:

```
python3 scripts/check-strings.py
```

`scripts/ci.sh checks` runs it, in CI and in the push gate, which runs it on every push, docs-only
included.
