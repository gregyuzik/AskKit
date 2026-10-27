#!/usr/bin/env python3
"""String Catalog completeness ratchet.

Why it exists: nothing in a build fails when a key is added and never
translated, so incomplete keys pass every build and ship English to every other
locale.

AskKit needs its own because a host's catalog checks scan the host's own tree,
never a package's, and AskUI's strings live here.

Zero tolerance: every translatable key must carry a unit in all 24 non-English
locales. One escape, explicit: `"shouldTranslate": false` on the key — the
catalog's own marker for a string that is not for translation. That is what
"Private Cloud Compute" uses, and what the reveal renderer's format-only `%@%@`
key uses. `-exportLocalizations` is not run here, but if it ever is it adds its
own artifacts — an empty key, a bare `%@` — and those want the same marker
rather than deletion, since it recreates them.

A locale counts as covered when it carries a unit for the key *and* every one of
its units is `translated` with a value — `needs_review` is the state the
extractor writes by default, which is therefore evidence that nobody has
translated the string rather than evidence that somebody has, and a
`translated` unit with an empty value renders as nothing at all. A locale a
catalog carries and `LOCALES` doesn't name is reported too, since none of this
would grade it.

Plural categories are checked against the set each locale actually needs, not
against a single shape: Hebrew has a dual, Russian has four categories and
Arabic six, and a Hebrew entry with only `one`/`other` silently loses the
reading for exactly two. Every plural variation is graded, wherever it sits: at
the top of a localization, under a device variation, or inside a substitution.
A count key also fails in a locale that gives every count the same form,
unless that locale needs only `other`. A key is a count key when its source
passes an integer (`%lld`, `%ld`, `%d`, `%u` and the rest) or inflects
(`^[…](inflect: true)`), unless `NOT_COUNTS` names it, or when any
localization varies it by plural: waiting for a localization to pluralize it
first would pass a key every locale left flat.
Extra categories pass — Spanish, French, Italian and Portuguese add `many` for
large numbers on some keys and not others.

Separately, and for a harder reason than completeness: a key with a placeholder
is checked so that argument N carries the specifier the source gives argument
N. A translation that reorders `%lld` and `%@` without numbering them makes
Foundation read the integer as an object pointer, and the process crashes in
that locale only, so nothing run in English ever sees it. One placeholder is
enough to crash: `%lld read` translated with a `%@` does it too. A key whose
source passes nothing is graded as well, since a placeholder a translation adds
there reads an argument the call never passes.

That check reads a substitution reference (`%#@items@`) through the
localization's own `substitutions` map rather than as a specifier, because it is
not one. Xcode writes those the moment a plural key is opened — AskUI's evidence
line is one edit away from carrying one — and read as a bare `%@`, `%#@items@`
fails correct translations: 24 of them in one host app's catalogs. That is the
direction that costs something: a push gate failing a right answer, whose
obvious cure is to break the string.

The source is scanned too, from the other side. A literal looked up in a
package's own bundle (`bundle: #bundle`) has to be in that target's catalog —
`#bundle` is the target's own `Bundle.module`, so AskCore's literals are checked
against AskCore's catalog and AskUI's against AskUI's. A localized literal with
no bundle is looked up in the host's bundle, finds nothing, and shows the raw
key in every locale but English, so it fails wherever it is. Which calls count
as a lookup is `LOOKUP`'s list, with `.searchable`'s `prompt:` and
`.accessibilityInputLabels`'s array read apart; a key built away from its call,
such as a `LocalizedStringKey` held in a variable, isn't seen.

`self_test()` runs first on every invocation, this file being its own test
target. Silent when it passes; when it does not, nothing below it is worth
reading.

Run directly (`python3 scripts/check-catalog-completeness.py`), or through
`scripts/ci.sh checks`, which both the push gate and CI's `checks` job run.
"""
import json
import os
import re
import sys

# The 25 locales AskKit ships, minus the `en` source.
# Adding a locale means adding it here; the push gate should fail until it is
# actually translated, not quietly ignore it.
LOCALES = [
    "ar", "cs", "da", "de", "es", "es-MX", "fr", "he", "id", "it", "ja", "ko",
    "nb", "nl", "pl", "pt-BR", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans",
    "zh-Hant",
]

# The CLDR plural categories a locale must carry, derived from 2,000-odd plural
# entries in shipping app catalogs rather than from memory.
#
# The two that are easy to get wrong: Hebrew has a dual, so a count of exactly 2
# needs `two` (164 of the 173 he entries in those catalogs carry it); Russian
# needs all four. A locale the table doesn't name needs `one`/`other`.
#
# ar, cs, id, pl, th and uk come from CLDR's plural rules rather than from a
# shipping catalog: Arabic has all six categories (`zero` for 0, `two` for
# exactly 2, `few` for 3-10, `many` for 11-99); Czech has `few` (2-4) and
# `many` (fractions); Polish and Ukrainian have `few` and `many` like Russian;
# Indonesian and Thai have no plural inflection at all, so bare `other`, as for
# the CJK locales and Vietnamese.
#
# A *superset* passes. Spanish, French, Italian and Portuguese legitimately add
# `many` for large numbers on some keys and not others, and the CJK locales
# sometimes carry a `one` they do not need — neither is an error.
PLURAL_CATEGORIES = {
    "ar": {"zero", "one", "two", "few", "many", "other"},
    "cs": {"one", "few", "many", "other"},
    "he": {"one", "two", "other"},
    "id": {"other"},
    "ja": {"other"},
    "ko": {"other"},
    "pl": {"one", "few", "many", "other"},
    "ru": {"one", "few", "many", "other"},
    "th": {"other"},
    "uk": {"one", "few", "many", "other"},
    "vi": {"other"},
    "zh-Hans": {"other"},
    "zh-Hant": {"other"},
}
PLURAL_CATEGORIES_DEFAULT = {"one", "other"}
# CLDR's own order, for naming missing categories the way a translator reads them.
PLURAL_ORDER = ["zero", "one", "two", "few", "many", "other"]

# Discovered, not hand-listed: a hand-maintained list means a brand-new
# `.xcstrings` ships unchecked, which is the same silent gap this script exists
# to prevent. Anything genuinely out of scope goes in EXCLUDED with a reason.
CATALOG_ROOTS = ["Sources"]
EXCLUDED = {
    # No entries today. Add as `"path/to.xcstrings": "why"`.
}

# Keys whose source passes an integer that isn't a count, so a locale may give
# every value the same form: `"%lld%% of %@"` reads the same at 2% and at 5%.
NOT_COUNTS = {
    # No entries today. Add as `"key": "why"`, the key as the catalog spells it.
}

# The two catalogs the package must always carry. Discovery alone cannot tell a
# deleted catalog from one that never existed, and `.process("Resources")` fails
# the build only for a missing *directory* — an empty one builds fine and takes
# every AskUI string down to English with it.
REQUIRED = [
    "Sources/AskCore/Resources/Localizable.xcstrings",
    "Sources/AskUI/Resources/Localizable.xcstrings",
]


def discover_catalogs():
    found = []
    for root in CATALOG_ROOTS:
        for dirpath, _dirnames, filenames in os.walk(root):
            for name in sorted(filenames):
                if name.endswith(".xcstrings"):
                    path = os.path.join(dirpath, name)
                    if path not in EXCLUDED:
                        found.append(path)
    return sorted(found)


def string_units(node):
    """Every `stringUnit` under a localization, at any depth."""
    if not isinstance(node, dict):
        return
    unit = node.get("stringUnit")
    if isinstance(unit, dict):
        yield unit
        return
    for child in node.values():
        yield from string_units(child)


def coverage_gap(localization):
    """Why a locale isn't done for a key, or None when it is.

    Presence alone isn't enough: `needs_review` is the state the extractor
    writes by default, so it says nothing about whether anyone translated the
    string, and 348 of 824 units sat in it when that was measured. Grading it
    means a half-finished locale fails here rather than shipping. Nor is the
    state alone: a `translated` unit with an empty value renders as nothing.
    """
    if not localization:
        return "missing"
    if "stringUnit" not in localization and "variations" not in localization:
        return "missing"
    units = list(string_units(localization))
    if not units:
        return "missing"
    if any(unit.get("state") != "translated" for unit in units):
        return "not translated"
    if any(not str(unit.get("value", "")).strip() for unit in units):
        return "empty"
    return None


def is_plural_variation(path, name):
    """Whether `name`, reached at `path`, is a plural variation rather than a
    substitution or a device that happens to be called `plural`."""
    return name == "plural" and path[-1:] == ("variations",)


def plural_nodes(node, path=()):
    """(path, categories) for every plural variation under a localization.

    Wherever it sits: at the top, under a device variation, or inside a
    substitution — the `%#@name@` form Xcode writes the moment a plural key is
    edited. Reading only the top level graded none of the last two.
    """
    if not isinstance(node, dict):
        return
    for name, child in node.items():
        if not isinstance(child, dict):
            continue
        if is_plural_variation(path, name):
            yield path + (name,), set(child)
        yield from plural_nodes(child, path + (name,))


# The conversions that pass an integer, whatever the length modifier: `%lld`,
# `%ld`, `%d`, `%llu`, `%u`. Hex and octal (`%x`, `%o`) print a number as a code,
# not as a count.
INTEGER_CONVERSIONS = {"d", "D", "u", "U"}
INFLECTS = re.compile(r"\binflect:\s*true\b")


def is_count_key(key, entry, source_language="en", not_counts=None):
    """Whether this key's text has to change with a number.

    Yes when the source passes an integer, read the way `source_arguments`
    reads the call's arguments, or inflects (`^[%lld item](inflect: true)`),
    unless `not_counts` (`NOT_COUNTS` by default) names the key: `%lld read` is
    a count and `%lld%% of %@` isn't, and only a person can say which. Yes too
    when any localization already varies it by plural, so a key one locale
    pluralizes is a count key in all of them.

    Asking only the localizations would pass `%lld chats` left flat in all 24,
    and a Russian reader with two chats would see `2 чатов` for `2 чата`.
    """
    localizations = entry.get("localizations") or {}
    if any(next(plural_nodes(localization), None) is not None
           for localization in localizations.values()):
        return True
    if key in (NOT_COUNTS if not_counts is None else not_counts):
        return False
    source = localizations.get(source_language)
    if INFLECTS.search(key) or any(
        INFLECTS.search(str(value)) for value, _substitutions in source_values(source or {})
    ):
        return True
    return any(specifier[-1:] in INTEGER_CONVERSIONS
               for _index, specifier in source_arguments(key, entry, source_language))


def flat_units(localization):
    """The paths to a localization's units that no plural variation reaches.

    A unit under a plural category is reached, and so is one whose value splices
    in a substitution that varies by plural. Anything else gives every count the
    same form, which a count key can't afford in a locale with more than one.
    """
    flat = []

    def walk(node, path, substitutions, pluralized):
        if not isinstance(node, dict):
            return
        substitutions = in_scope(substitutions, node)
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            references = re.findall(r"%#@([^@]+)@", str(unit.get("value", "")))
            if not pluralized and not any(
                next(plural_nodes(substitutions.get(name)), None) is not None
                for name in references
            ):
                flat.append(path + ("stringUnit",))
            return
        for name, child in node.items():
            if name == "substitutions":
                continue
            walk(child, path + (name,), substitutions,
                 pluralized or is_plural_variation(path, name))

    walk(localization or {}, (), {}, False)
    return flat


def plural_gaps(localization, locale, count_key=False):
    """[(where, why)] for each way this locale's plural forms fall short."""
    required = PLURAL_CATEGORIES.get(locale, PLURAL_CATEGORIES_DEFAULT)
    named = ", ".join(category for category in PLURAL_ORDER if category in required)
    gaps = []
    for path, categories in plural_nodes(localization or {}):
        missing = [category for category in PLURAL_ORDER
                   if category in required - categories]
        if missing:
            gaps.append(("/".join(path), "missing " + ", ".join(missing)))
    if count_key and localization and required != {"other"}:
        for path in flat_units(localization):
            gaps.append(("/".join(path),
                         f"one form for every count, where it needs {named}"))
    return gaps


# A call that looks its first argument up as a localized key, when that argument
# is a literal. Two kinds:
#
# - `String(localized:)`, `AttributedString(localized:)`, `Text`,
#   `LocalizedStringResource` and `NSLocalizedString` take a bundle, and are
#   right with `bundle: #bundle` (or `.module`, which `#bundle` expands to in a
#   target with resources);
# - the SwiftUI views and modifiers that take a `LocalizedStringKey` title and
#   no bundle at all — `Button("Delete")`, `.accessibilityLabel("Close")`,
#   `.accessibilityAction(named: "Delete")` — are never right in a package,
#   whose strings they look up in the host's bundle.
#
# The literal may come wrapped, `Text(LocalizedStringKey("Done"))`, which is
# the same lookup spelled out: the call's own arguments still decide the
# bundle. Two lookups sit where no first-argument pattern reaches, and
# `KEYWORD_LOOKUPS` and `ARRAY_LOOKUPS` read them: `.searchable`'s `prompt:`,
# and the array `.accessibilityInputLabels` takes.
#
# A literal the code asks for and the catalog does not carry ships English to
# every locale AND passes the completeness check above, which only ever grades
# the keys already present — absence is invisible to it by construction. A
# literal with no bundle is worse: it ships the raw key, and no catalog edit
# can fix it.
#
# Left out on purpose, as no lookup: `Text(verbatim:)`, an empty literal
# (`TextField("", text:)`), a literal that is only the start of an expression
# (`Text("a" + b)` is a `String`), and every call not named here —
# `keyboardShortcut("n")`, `Logger`, `accessibilityIdentifier`. A
# `LocalizedStringKey` made in one place and passed in another can't be traced
# by a pattern, so a key held in a variable is not seen at all.
#
# `\(\s*` and `localized:\s*` — the argument is routinely on its own line once
# the comment is written out, and requiring them adjacent would make every
# wrapped call invisible to this check, which is the same silent gap in a
# different place.
LOOKUP = re.compile(
    r'(?:(?<!\w)(?:String|AttributedString)\(\s*localized:\s*'
    r'|(?<!\w)(?:Text|LocalizedStringResource|NSLocalizedString|Button|Label|Toggle'
    r'|Section|Picker|Menu|Link|TextField|SecureField|ContentUnavailableView'
    r'|LabeledContent|NavigationLink|GroupBox|DisclosureGroup|ProgressView|Tab'
    r'|TabSection|ShareLink|CommandMenu|Stepper|DatePicker|ColorPicker|PhotosPicker'
    r'|ControlGroup)\(\s*'
    r'|\.(?:navigationTitle|navigationSubtitle|accessibilityLabel|accessibilityHint'
    r'|accessibilityValue|accessibilityCustomContent|accessibilityRotor|help|alert'
    r'|confirmationDialog|badge)\(\s*'
    r'|\.accessibilityAction\(\s*named:\s*)'
    r'(?P<wrapped>LocalizedStringKey\(\s*)?'
    r'"(?!"")(?P<key>(?:[^"\\\n]|\\.)*)"'
)
# `(call, label)` for a modifier that takes a localized key as a labelled
# argument after its first: `.searchable(text: $query, prompt: "Search chats")`.
KEYWORD_LOOKUPS = [
    (re.compile(r"\.searchable\("), "prompt"),
]
# A modifier whose argument is an array of localized keys, each element looked
# up: `.accessibilityInputLabels(["History", "Chats"])`, or either array of a
# conditional.
ARRAY_LOOKUPS = re.compile(r"\.accessibilityInputLabels\(")
OWN_BUNDLE = re.compile(r"\bbundle:\s*(?:#bundle|\.module|Bundle\.module)\b")
HOST_BUNDLE = re.compile(r"\bbundle:\s*(?:\.main|Bundle\.main|nil)\b")
# `tableName:` for `Text` and `NSLocalizedString`, `table:` for
# `String(localized:)`, `AttributedString(localized:)` and
# `LocalizedStringResource`.
TABLE = re.compile(r'\b(?:tableName|table):\s*"([^"\\]*)"')
# What has to follow the literal for it to be the whole first argument.
ARGUMENT_ENDS = re.compile(r"\s*[,)]")
# The `LocalizedStringKey(` a wrapped literal closes.
WRAPPER_ENDS = re.compile(r"\s*\)")
# A string literal on one line, as LOOKUP reads one.
LITERAL = re.compile(r'"(?!"")((?:[^"\\\n]|\\.)*)"')


def call_arguments(source, start):
    """The rest of a call's arguments, from `start` to its closing paren.

    Counted rather than matched: `[^)]*` stops at the first `)`, which an
    interpolation (`\\(count)`) or a nested call puts before `bundle:`. None
    when the call never closes.
    """
    depth = 1
    index = start
    while index < len(source):
        char = source[index]
        if char == '"':
            index += 1
            while index < len(source) and source[index] != '"':
                index += 2 if source[index] == "\\" else 1
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return source[start:index]
        index += 1
    return None


def literal_spans(arguments):
    """(start, end, key, enclosing) for each one-line string literal in a call's
    arguments, where `enclosing` is what is open around it, outermost first:
    `(` for a call or a group, `{` for a closure, `[` for an array literal and
    `s` for a subscript. A `[` straight after a name, a `)`, a `]`, a `!` or a
    `?` is a subscript (`labels[0]`, `item?[0]`); any other `[` starts an
    array."""
    spans = []
    enclosing = []
    index = 0
    while index < len(arguments):
        char = arguments[index]
        if char == '"':
            literal = LITERAL.match(arguments, index)
            if literal:
                spans.append((index, literal.end(), literal.group(1), tuple(enclosing)))
                index = literal.end()
                continue
            # A multi-line or unterminated literal: skipped, as `call_arguments`
            # skips one.
            index += 1
            while index < len(arguments) and arguments[index] != '"':
                index += 2 if arguments[index] == "\\" else 1
        elif char in "({":
            enclosing.append(char)
        elif char == "[":
            before = arguments[index - 1:index]
            enclosing.append("s" if before and (before.isalnum() or before in "_)]!?") else "[")
        elif char in ")]}" and enclosing:
            enclosing.pop()
        index += 1
    return spans


def lookups(source):
    """(position, key, the call's arguments) for each localized literal in
    comment-free source, in source order."""
    found = []
    for match in LOOKUP.finditer(source):
        key, end = match.group("key"), match.end()
        if match.group("wrapped"):
            closed = WRAPPER_ENDS.match(source, end)
            if not closed:
                continue
            end = closed.end()
        if not key or not ARGUMENT_ENDS.match(source, end):
            continue
        arguments = call_arguments(source, end)
        if arguments is not None:
            found.append((match.start(), key, arguments))
    # The labelled argument, read at the call's own level: a `prompt:` inside a
    # nested call is that call's.
    for call, label in KEYWORD_LOOKUPS:
        labelled = re.compile(rf"\b{label}:\s*$")
        for match in call.finditer(source):
            arguments = call_arguments(source, match.end())
            for start, end, key, enclosing in literal_spans(arguments or ""):
                if (key and not enclosing and labelled.search(arguments, 0, start)
                        and re.match(r"\s*(?:,|$)", arguments[end:])):
                    found.append((match.end() + start, key, arguments))
    # Each whole element of an array literal, but not a literal some call or
    # subscript inside the array takes: `[Text("History", bundle: #bundle)]` is
    # LOOKUP's, and `[names["history"]]` looks nothing up.
    for match in ARRAY_LOOKUPS.finditer(source):
        arguments = call_arguments(source, match.end())
        for start, end, key, enclosing in literal_spans(arguments or ""):
            if (key and enclosing and set(enclosing) == {"["}
                    and re.search(r"[\[,]\s*$", arguments[:start])
                    and re.match(r"\s*[,\]]", arguments[end:])):
                found.append((match.end() + start, key, arguments))
    return sorted(found, key=lambda lookup: lookup[0])


def scan_literals(path, source):
    """(key, line, table, bundle) for each localized literal in one file.

    `bundle` is "own" for `#bundle` or `.module`, "host" for none, `.main` or
    `nil`, and "other" for an expression this can't read, which is graded
    neither way.
    """
    source = without_comments(source)
    for position, key, arguments in lookups(source):
        if OWN_BUNDLE.search(arguments):
            bundle = "own"
        elif "bundle:" not in arguments or HOST_BUNDLE.search(arguments):
            bundle = "host"
        else:
            bundle = "other"
        table = TABLE.search(arguments)
        yield (
            key.replace('\\"', '"').replace("\\n", "\n"),
            source.count("\n", 0, position) + 1,
            table.group(1) if table else "Localizable",
            bundle,
        )


def target_of(path):
    """The SwiftPM target a file under `Sources/` belongs to, or None."""
    parts = path.replace(os.sep, "/").split("/")
    return parts[1] if len(parts) > 2 and parts[0] == "Sources" else None


def catalog_scope(path):
    """(target, table) a catalog serves: `#bundle` is its target's own bundle,
    and a lookup with no `tableName:` reads `Localizable`."""
    return target_of(path), os.path.splitext(os.path.basename(path))[0]


INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")

# What a catalog key can look like where the source interpolates a value. The
# extractor writes `%@` for a string and `%lld` for an integer, and the source
# alone cannot say which — `\(count)` is an Int and `\(scope)` is a String, and
# both are just `\(…)` to a regex. So every combination is a candidate and a key
# passes if the catalog carries any of them. Three interpolations is far more
# than any key here has; beyond that the check gives up rather than exploding.
SPECIFIERS = ("%@", "%lld")
MAX_INTERPOLATIONS = 3


def candidate_keys(literal):
    """Every catalog key this source literal could have been extracted as."""
    interpolations = INTERPOLATION.findall(literal)
    if not interpolations:
        return [literal]
    if len(interpolations) > MAX_INTERPOLATIONS:
        return []
    keys = [""]
    rest = literal
    for interpolation in interpolations:
        head, _sep, rest = rest.partition(interpolation)
        keys = [key + head + spec for key in keys for spec in SPECIFIERS]
    return [key + rest for key in keys]


def without_comments(source):
    """`source` with `//` line comments blanked out.

    A doc comment that *shows* the correct call — and this package's own
    `AskDomain.phrase(for:)` doc does, because forgetting the bundle is the
    trap it is warning about — otherwise reads to the scan below as a real
    localized literal with no catalog entry, and fails the push gate for being
    right. Scanning source that includes its own instructions is the bug.

    Line comments only, and quote-aware so a `//` inside a string literal
    stays. Block comments are left alone: this codebase does not use them, and
    a half-correct nesting scanner is worse than none.
    """
    out = []
    for line in source.splitlines():
        in_string = False
        escaped = False
        cut = None
        for index, char in enumerate(line):
            if escaped:
                escaped = False
                continue
            if char == "\\":
                escaped = True
                continue
            if char == '"':
                in_string = not in_string
                continue
            if not in_string and char == "/" and line[index + 1:index + 2] == "/":
                cut = index
                break
        out.append(line if cut is None else line[:cut])
    return "\n".join(out)


def read_sources():
    """{path: text} for every Swift file under the catalog roots."""
    sources = {}
    for root in CATALOG_ROOTS:
        for dirpath, _dirnames, filenames in os.walk(root):
            for name in sorted(filenames):
                if name.endswith(".swift"):
                    path = os.path.join(dirpath, name)
                    with open(path, encoding="utf-8") as handle:
                        sources[path] = handle.read()
    return sources


# A String Catalog *substitution reference* (`%#@items@`), or a `%` specifier —
# positional (`%2$@`) or not (`%@`), with the flags, width, precision and length
# modifier the extractor can emit between the two, and the `[tt]` technical-term
# flag Thai writes on a `%@` that holds a name (`%[tt]@`, `%2$[tt]@`).
#
# **The substitution alternative comes first, and the order is load-bearing.**
# `re` tries alternatives left to right at each position, and the specifier
# branch reads `%#@items@` quite happily as a bare `%@`: the `#` is swallowed by
# the flags class and `@` is taken for the conversion. That scores a *correct*
# plural translation as one handing an Int to `%@` — 24 false positives in one
# host app's catalogs — and the obvious way to make the push gate pass is to
# break the translation. Tried second, this branch would never get the chance.
# `%#@` as a printf form is "alternate-form object", which nothing writes, so
# the reference spelling has no rival.
#
# One spelling this does NOT match, deliberately: the legacy stringsdict form
# `%1$#@name@`, which carries its position inline and would fall through to the
# specifier branch as a `#`-flagged `%@`. Xcode does not write it — zero hits
# in the shipping catalogs this was checked against, migrated keys included — so
# handling it would be a branch nothing exercises. If it ever turns up, the
# first alternative grows `%(?:(\d+)\$)?#@…` and the metadata `argNum` still
# wins, because that is what Foundation reads.
#
# **`[tt]` is a spacing flag, not a type**, so the specifier a match reports is
# still the conversion: `%[tt]@` is the `@` the source's `%@` passes, and a
# Thai value holding it is graded like any other. Read as nothing, the token
# would match no alternative at all, its `%` would vanish from the tokens, and a
# Thai value that dropped or swapped an argument would pass for want of any
# specifier to grade. Two spellings are matched only to be refused: `[tt]` on
# anything but an object (`%[tt]lld`), and `[tt]` before the position
# (`%[tt]2$@`), which Foundation does not read as the guide's `%2$[tt]@`.
SPECIFIER = re.compile(
    r"%#@([^@]+)@"
    r"|%(?:(\d+)\$)?(\[tt\])?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfeEgGcCsSpaAF%])"
    r"|%\[tt\](\d+)\$"
)


def format_arguments(value, substitutions=None):
    """[(argument index, specifier)] for one catalog value, in source order.

    A bare `%@` takes the next argument; `%2$@` names one. `%%` is a literal
    percent and consumes nothing.

    `%#@items@` is none of those: it is a substitution reference, and the plural
    or device variation it splices in lives in the *localization's* own
    `substitutions` map — which is also where its argument number and type live.
    So it is read as the explicit positional it really is, argument `argNum`
    carrying `formatSpecifier`, and `substitutions` is that map for the
    localization this value came from.

    A reference the localization does not declare is reported, not skipped, as
    `(None, name)`. Foundation cannot resolve it either, so passing it silently
    would be the same shape of gap this file exists to close — a broken catalog
    that nothing fails on.
    """
    substitutions = substitutions or {}
    arguments = []
    position = 0
    for match in SPECIFIER.finditer(value):
        name, explicit, technical, length, conversion, misplaced = match.groups()
        if misplaced is not None:
            index = int(misplaced)
            position = index
            arguments.append((index, f"[tt]{misplaced}$"))
            continue
        if name is not None:
            declared = substitutions.get(name)
            if not isinstance(declared, dict) or "argNum" not in declared:
                arguments.append((None, name))
                continue
            index = int(declared["argNum"])
            position = index
            arguments.append((index, str(declared.get("formatSpecifier", ""))))
            continue
        if conversion == "%":
            continue
        if explicit is None:
            position += 1
            index = position
        else:
            index = int(explicit)
            position = index
        # `[tt]` belongs to an object alone: on a number it is no type
        # Foundation has, so it is kept in the specifier to fail the comparison.
        flag = "[tt]" if technical and conversion != "@" else ""
        arguments.append((index, flag + (length or "") + conversion))
    return arguments


def in_scope(substitutions, node):
    """The substitutions a value under `node` can reference: its ancestors'
    and its own, the nearer declaration winning. Xcode writes the map beside
    the localization's `stringUnit` or `variations`, so a value under a plural
    or device variation reads the one declared above it."""
    declared = node.get("substitutions") if isinstance(node, dict) else None
    if isinstance(declared, dict):
        return {**substitutions, **declared}
    return substitutions


def source_values(node, substitutions=None):
    """(value, substitutions in scope) for every source value under a
    localization, substitution subtrees skipped.

    `string_units` is the same walk and cannot be reused here: it descends into
    `substitutions`, whose inner plural forms are `%arg`-shaped and tokenize as
    a `%a` hex float with the letters `rg` after it. That is the same reason
    `specifier_mismatches.walk` skips them — the reference has already been
    resolved through the map by then, and its inner forms are not a format.
    """
    if not isinstance(node, dict):
        return
    substitutions = in_scope(substitutions or {}, node)
    unit = node.get("stringUnit")
    if isinstance(unit, dict):
        yield unit.get("value", ""), substitutions
        return
    for name, child in node.items():
        if name == "substitutions":
            continue
        yield from source_values(child, substitutions)


def source_arguments(key, entry, source_language="en"):
    """The arguments the call site passes, in source order.

    Two shapes of key reach here, and only one carries its own arguments. A key
    that IS the source literal — `"%lld files in %@"`, what
    `String(localized:)` writes — is the developer's own format string. An
    *identifier* key — `"sync.partial.detail"`, what
    `String(localized:defaultValue:)` writes — is a name, and the source text
    lives in the catalog's source localization instead.

    Read from the key alone an identifier key yields nothing, the caller bails
    when there are no arguments, and every translation of it passes without
    being looked at. That is this file's own silent-pass failure arriving by
    another door: a three-argument identifier key in twenty-five locales went
    ungraded exactly this way.

    The key wins when it has arguments of its own, so the source localization
    is read only for a key with none. Its values are merged rather than the
    first one taken, because a plural form can drop the count: a `one` of
    "One file in %2$@" names argument 2 and not argument 1.

    `source_language` is the catalog's own `sourceLanguage` rather than `en`
    assumed; the field exists because it is not always English.
    """
    by_key = [pair for pair in format_arguments(key) if pair[0] is not None]
    if by_key:
        return by_key
    source = (entry.get("localizations") or {}).get(source_language)
    if not isinstance(source, dict):
        return by_key
    found = {}
    for value, substitutions in source_values(source):
        for index, specifier in format_arguments(value, substitutions):
            if index is not None:
                found.setdefault(index, specifier)
    return sorted(found.items())


def specifier_mismatches(key, entry, source_language="en"):
    """Where a translation would read an argument as the wrong type.

    Foundation resolves a format against the *call site's* argument list, so a
    translation that reorders two placeholders has to say which is which. Left
    non-positional, `%@ … %lld` against a call passing (Int, String) hands the
    integer to `%@`, which dereferences it as an object pointer and crashes.

    Being "fully positional" is not the property that matters and checking for
    it is not enough: `%1$@ … %2$lld` against the same call crashes identically.
    What has to hold is that argument N carries the specifier the source gives
    argument N — which is what this compares.

    One argument is enough to grade: `%lld read` translated as `%@ gelesen`
    hands the Int to `%@` just the same, and `%2$@` reads past the end of the
    arguments. A translation with none, such as a plural form that spells out
    "one", passes.

    None is graded too. A key whose source passes nothing has no argument for
    a translation to read, so `Antwort %@ bereit` for `Answer ready` is a
    finding: shown raw at best, and a read past the end of the arguments
    wherever the value goes through a formatter. `%%` is a literal percent and
    reads nothing.
    """
    # A `%#@…@` in the key is nothing the catalog declares — `source_arguments`
    # drops those rather than letting a `None` index reach `expected`, and
    # falls back to the source localization for an identifier key that carries
    # no arguments of its own.
    source = source_arguments(key, entry, source_language)

    expected = {}
    for index, specifier in source:
        expected[index] = specifier

    mismatches = []

    def walk(node, path, substitutions):
        if not isinstance(node, dict):
            return
        substitutions = in_scope(substitutions, node)
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            value = unit.get("value", "")
            arguments = format_arguments(value, substitutions)
            if not arguments:
                return
            for index, specifier in arguments:
                if index is None:
                    mismatches.append(
                        (path, value, f"references substitution %#@{specifier}@, "
                                      f"which this localization does not declare")
                    )
                    continue
                want = expected.get(index)
                if want is None and not expected:
                    mismatches.append(
                        (path, value, f"reads argument {index}; the source "
                                      f"passes none")
                    )
                elif want is None:
                    mismatches.append(
                        (path, value, f"reads argument {index}; the source has "
                                      f"only {len(expected)}")
                    )
                elif specifier != want:
                    mismatches.append(
                        (path, value, f"reads argument {index} as %{specifier}, "
                                      f"the source passes %{want}")
                    )
            return
        for name, child in node.items():
            # A substitution's own subtree is its inner plural forms, whose
            # values are `%arg`-shaped — which this tokenizer would read as a
            # `%a` hex float with the letters `rg` after it. They belong to the
            # reference resolved above, not to the format being graded here.
            if name == "substitutions":
                continue
            walk(child, path + [name], substitutions)

    for locale, localization in (entry.get("localizations") or {}).items():
        walk(localization, [locale], {})
    return mismatches



# The shapes `specifier_mismatches` has to get right, checked before it grades
# anything. There is no Python test target here and no CI behind this file, so
# the alternative to a self-test is nothing at all — and this check's failure
# mode runs the dangerous way: it rejects a *correct* translation, and the
# obvious way to make the push gate pass again is to break the string it is
# complaining about. Pure string work, so the whole suite costs about a
# millisecond.
#
# `(key, entry, expected mismatch count[, source language])`. The substitution
# shapes are lifted verbatim from what Xcode writes, not from memory.
SELF_TESTS = [
    # --- Identifier keys -------------------------------------------------
    # The key is a NAME, not a format, so the source arguments have to come
    # from the source localization. Read from the key alone every case below
    # scores zero, which is why the reordered one is here: revert
    # `source_arguments` and this suite fails rather than going quiet.
    #
    # A three-argument identifier key, correctly translated.
    (
        "sync.progress",
        {"localizations": {
            "en": {"stringUnit": {"state": "translated",
                                  "value": "%1$lld of %2$lld files · %3$lld new"}},
            "da": {"stringUnit": {"state": "translated",
                                  "value": "%1$lld af %2$lld filer · %3$lld nye"}},
        }},
        0,
    ),
    # The same shape with the types crossed: the translation reads argument 1
    # as an object where the source passes an Int, and argument 2 the other
    # way. Two mismatches, and the crash this whole check exists for.
    (
        "sync.summary",
        {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": "%1$lld in %2$@"}},
            "de": {"stringUnit": {"state": "translated", "value": "%1$@ mit %2$lld"}},
        }},
        2,
    ),
    # An identifier key whose SOURCE is a plural `variations` node rather than
    # a flat `stringUnit`. Reading only the flat shape would skip it exactly
    # the way the key-only read skipped the entry — which is why
    # `source_values` recurses instead of calling `.get("stringUnit")`.
    (
        "sync.plural.summary",
        {"localizations": {
            "en": {"variations": {"plural": {
                "one": {"stringUnit": {"state": "translated", "value": "%1$lld file in %2$@"}},
                "other": {"stringUnit": {"state": "translated", "value": "%1$lld files in %2$@"}},
            }}},
            "nb": {"stringUnit": {"state": "translated", "value": "%1$@ med %2$lld"}},
        }},
        2,
    ),
    # An identifier key carrying a substitution, resolved through the source
    # localization's own map, and correct.
    (
        "sync.partial.detail",
        {"localizations": {
            "en": {
                "stringUnit": {"state": "translated",
                               "value": "Copied %1$lld of %2$lld. %#@skipped@."},
                "substitutions": {"skipped": {"argNum": 3, "formatSpecifier": "lld"}},
            },
            "da": {
                "stringUnit": {"state": "translated",
                               "value": "Kopierede %1$lld af %2$lld. %#@skipped@."},
                "substitutions": {"skipped": {"argNum": 3, "formatSpecifier": "lld"}},
            },
        }},
        0,
    ),
    # A source language that is not English — the reason `sourceLanguage` is
    # read from the catalog rather than assumed. Graded against `da`; the
    # German line crosses the two types.
    (
        "sync.nonenglish",
        {"localizations": {
            "da": {"stringUnit": {"state": "translated", "value": "%1$lld i %2$@"}},
            "de": {"stringUnit": {"state": "translated", "value": "%1$@ in %2$lld"}},
        }},
        2,
        "da",
    ),
    # --- Source-literal keys ---------------------------------------------
    # A plural key Xcode has spliced into a substitution, with the other
    # placeholder numbered around it. This is what AskUI's evidence line becomes
    # the moment anyone opens it in Xcode, and it is CORRECT.
    (
        "%@^[%lld item](inflect: true)",
        {"localizations": {"da": {
            "stringUnit": {"state": "translated", "value": "%1$@%#@items@"},
            "substitutions": {"items": {
                "argNum": 2, "formatSpecifier": "lld",
                "variations": {"plural": {
                    "one": {"stringUnit": {"state": "translated", "value": "%arg emne"}},
                    "other": {"stringUnit": {"state": "translated", "value": "%arg emner"}},
                }},
            }},
        }}},
        0,
    ),
    # Two substitutions and a numbered third argument, in one value.
    (
        "Imported ^[%lld file](inflect: true) and ^[%lld folder](inflect: true). Skipped %lld.",
        {"localizations": {"nb": {
            "stringUnit": {"state": "translated",
                           "value": "Importerte %#@files@ og %#@folders@. Hoppet over %3$lld."},
            "substitutions": {
                "files": {"argNum": 1, "formatSpecifier": "lld"},
                "folders": {"argNum": 2, "formatSpecifier": "lld"},
            },
        }}},
        0,
    ),
    # The same shape with the substitution's declared type swapped. The
    # translation reads argument 2 as an object; the source passes an Int.
    (
        "%@^[%lld item](inflect: true)",
        {"localizations": {"da": {
            "stringUnit": {"state": "translated", "value": "%1$@%#@items@"},
            "substitutions": {"items": {"argNum": 2, "formatSpecifier": "@"}},
        }}},
        1,
    ),
    # ...and with the argument numbers swapped, which crashes identically.
    (
        "%@^[%lld item](inflect: true)",
        {"localizations": {"da": {
            "stringUnit": {"state": "translated", "value": "%2$@%#@items@"},
            "substitutions": {"items": {"argNum": 1, "formatSpecifier": "lld"}},
        }}},
        2,
    ),
    # A reference to a substitution the localization never declares. Foundation
    # cannot render it either.
    (
        "%@^[%lld item](inflect: true)",
        {"localizations": {"da": {
            "stringUnit": {"state": "translated", "value": "%1$@%#@items@"},
        }}},
        1,
    ),
    # A localization whose substitutions sit beside `variations` rather than a
    # top-level `stringUnit`: the walk must not descend into the substitution's
    # own `%arg` forms, which tokenize as a `%a` hex float.
    (
        "%@^[%lld item](inflect: true)",
        {"localizations": {"da": {
            "variations": {"plural": {"other": {
                "stringUnit": {"state": "translated", "value": "%1$@%#@items@"},
                "substitutions": {"items": {"argNum": 2, "formatSpecifier": "lld"}},
            }}},
            "substitutions": {"items": {
                "argNum": 2, "formatSpecifier": "lld",
                "variations": {"plural": {
                    "other": {"stringUnit": {"state": "translated", "value": "%arg emner"}},
                }},
            }},
        }}},
        0,
    ),
    # The crash this check exists for, on AskUI's own evidence line: reordered
    # and unnumbered, so the Int lands on `%@`.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {"tr": {
            "stringUnit": {"state": "translated", "value": "%@ içindeki %lld ögeden"},
        }}},
        2,
    ),
    # Numbered and still swapped — the case "fully positional" would let through.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {"tr": {
            "stringUnit": {"state": "translated", "value": "%1$@ içindeki %2$lld ögeden"},
        }}},
        2,
    ),
    # Correctly reordered and numbered.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {"tr": {
            "stringUnit": {"state": "translated", "value": "%2$@ içindeki %1$lld ögeden"},
        }}},
        0,
    ),
    # `%%` is a literal percent and consumes no argument, so the `%@` after it
    # is still argument 2.
    (
        "%lld%% of %@",
        {"localizations": {"de": {
            "stringUnit": {"state": "translated", "value": "%1$lld%% von %2$@"},
        }}},
        0,
    ),
    # --- One placeholder -------------------------------------------------
    # The keys AskUI really has. A lone specifier crashes as surely as a
    # reordered pair, so these are graded too.
    (
        "%lld read",
        {"localizations": {"de": {
            "stringUnit": {"state": "translated", "value": "%@ gelesen"},
        }}},
        1,
    ),
    (
        "%lld read",
        {"localizations": {"de": {
            "stringUnit": {"state": "translated", "value": "%lld gelesen"},
        }}},
        0,
    ),
    (
        "It resets at %@.",
        {"localizations": {"fr": {
            "stringUnit": {"state": "translated", "value": "Réinitialisation à %lld."},
        }}},
        1,
    ),
    # Numbered past the end of the one argument the call passes.
    (
        "It resets at %@.",
        {"localizations": {"fr": {
            "stringUnit": {"state": "translated", "value": "Réinitialisation à %2$@."},
        }}},
        1,
    ),
    # Hebrew's `one` and `two` spell the count out, so they carry no specifier
    # at all, and that passes.
    (
        "%lld read",
        {"localizations": {"he": {"variations": {"plural": {
            "one": {"stringUnit": {"state": "translated", "value": "נקרא אחד"}},
            "two": {"stringUnit": {"state": "translated", "value": "נקראו שניים"}},
            "other": {"stringUnit": {"state": "translated", "value": "%lld נקראו"}},
        }}}}},
        0,
    ),
    # An identifier key with one argument, read from the source localization.
    (
        "quota.reset",
        {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": "It resets at %@."}},
            "de": {"stringUnit": {"state": "translated", "value": "Zurückgesetzt um %lld."}},
        }},
        1,
    ),
    # An identifier key whose source `one` drops the count. Taking the first
    # source value would make argument 2 the only one, and fail the correct
    # `%1$lld` below; the source's values are merged instead.
    (
        "files.in.place",
        {"localizations": {
            "en": {"variations": {"plural": {
                "one": {"stringUnit": {"state": "translated", "value": "One file in %2$@"}},
                "other": {"stringUnit": {"state": "translated", "value": "%1$lld files in %2$@"}},
            }}},
            "da": {"stringUnit": {"state": "translated", "value": "%1$lld filer i %2$@"}},
        }},
        0,
    ),
    # Substitutions declared once for the localization, referenced from under a
    # device variation. The values read the map declared above them; reading
    # only their own node would call both references undeclared.
    (
        "%lld read",
        {"localizations": {"ru": {
            "substitutions": {"n": {
                "argNum": 1, "formatSpecifier": "lld",
                "variations": {"plural": {
                    "one": {"stringUnit": {"state": "translated", "value": "%arg прочитан"}},
                    "few": {"stringUnit": {"state": "translated", "value": "%arg прочитано"}},
                    "many": {"stringUnit": {"state": "translated", "value": "%arg прочитано"}},
                    "other": {"stringUnit": {"state": "translated", "value": "%arg прочитано"}},
                }},
            }},
            "variations": {"device": {
                "iphone": {"stringUnit": {"state": "translated", "value": "%#@n@"}},
                "other": {"stringUnit": {"state": "translated", "value": "Прочитано: %#@n@"}},
            }},
        }}},
        0,
    ),
    # --- Thai's `[tt]` flag -----------------------------------------------
    # `%[tt]@` against the source's `%@`, which is how Thai writes a name that
    # sits against its text, and correct. Unparsed it matched no alternative, so
    # every case below here scored zero whatever the value said.
    (
        "Reading %@…",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated", "value": "กำลังอ่าน%[tt]@…"}},
        }},
        0,
    ),
    # The same with the position written, and the two arguments reordered:
    # argument 2 first, each carrying the type the source gives it.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated",
                                  "value": "ใน%2$[tt]@ จาก %1$lld รายการ"}},
        }},
        0,
    ),
    # A Thai value that dropped the count and kept only the name, unnumbered:
    # it reads argument 1 as an object where the source passes an Int. This is
    # the case that shows the check is no longer blind to the flag.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated", "value": "ใน%[tt]@ของคุณ"}},
        }},
        1,
    ),
    # Reordered and not numbered: both arguments read as the wrong type.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated",
                                  "value": "ใน%[tt]@ จาก %lld รายการ"}},
        }},
        2,
    ),
    # `[tt]` on the count: no such specifier, so it is refused even where the
    # conversion is the right one.
    (
        "%lld read",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated", "value": "อ่านแล้ว %[tt]lld"}},
        }},
        1,
    ),
    # `[tt]` before the position, which the guide writes the other way round.
    (
        "From ^[%lld item](inflect: true) in your %@",
        {"localizations": {
            "th": {"stringUnit": {"state": "translated",
                                  "value": "ใน%[tt]2$@ จาก %1$lld รายการ"}},
        }},
        1,
    ),
    # --- Device variations -------------------------------------------------
    # A key that names no argument has nothing to grade, a `mac` variation
    # included.
    (
        "This device can't run Apple Intelligence.",
        {"localizations": {
            "de": {"variations": {"device": {
                "mac": {"stringUnit": {"state": "translated", "value": "Dieser Mac kann Apple Intelligence nicht verwenden."}},
                "other": {"stringUnit": {"state": "translated", "value": "Dieses Gerät kann Apple Intelligence nicht verwenden."}},
            }}},
        }},
        0,
    ),
    # The same variation on a key that does take an argument: each branch is
    # graded, and a branch that reads the Int as an object is one crasher.
    (
        "%lld read",
        {"localizations": {
            "de": {"variations": {"device": {
                "mac": {"stringUnit": {"state": "translated", "value": "%lld gelesen"}},
                "other": {"stringUnit": {"state": "translated", "value": "%@ gelesen"}},
            }}},
        }},
        1,
    ),
    # --- No arguments ------------------------------------------------------
    # A placeholder a translation adds to a key that passes none reads an
    # argument that isn't there, which a check that returns when the source
    # has no arguments never sees.
    (
        "Answer ready",
        {"localizations": {"de": {
            "stringUnit": {"state": "translated", "value": "Antwort %@ bereit"},
        }}},
        1,
    ),
    (
        "Answer ready",
        {"localizations": {"de": {
            "stringUnit": {"state": "translated", "value": "Antwort bereit"},
        }}},
        0,
    ),
    # Numbered, under a device variation, in an identifier key whose source
    # passes nothing: still a read past the end.
    (
        "quota.title",
        {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": "Daily limit"}},
            "fr": {"variations": {"device": {
                "mac": {"stringUnit": {"state": "translated", "value": "Limite du jour"}},
                "other": {"stringUnit": {"state": "translated", "value": "Limite %1$lld"}},
            }}},
        }},
        1,
    ),
    # `%%` is a literal percent, which reads nothing.
    (
        "Fully private",
        {"localizations": {"fr": {
            "stringUnit": {"state": "translated", "value": "Privé à 100 %%"},
        }}},
        0,
    ),
]


def unit(value, state="translated"):
    """A localization holding one unit, for the fixtures below."""
    return {"stringUnit": {"state": state, "value": value}}


def plural(**forms):
    """A localization varying by plural, one translated unit per category."""
    return {"variations": {"plural": {name: unit(value) for name, value in forms.items()}}}


def count_substitution(**forms):
    """A localization splicing its count in through `%#@n@`, as Xcode writes
    a plural key it has edited."""
    return {
        **unit("%#@n@"),
        "substitutions": {"n": {
            "argNum": 1, "formatSpecifier": "lld",
            "variations": {"plural": {name: unit(value) for name, value in forms.items()}},
        }},
    }


RU = {"one": "%arg один", "few": "%arg несколько", "many": "%arg много", "other": "%arg"}

# `(localization, why it isn't covered, or None)`.
COVERAGE_TESTS = [
    (unit("Hej"), None),
    (None, "missing"),
    ({"comment": "nothing translated"}, "missing"),
    (unit("Hej", state="needs_review"), "not translated"),
    # `translated` with nothing in it renders as nothing.
    (unit(""), "empty"),
    (unit("  "), "empty"),
    (plural(one="%lld fil", other=""), "empty"),
]

# `(key, entry, locale, expected gap count)`, graded the way `audit` grades it:
# the key and the entry decide whether it counts.
PLURAL_TESTS = [
    # Hebrew without its dual, at the top level.
    ("%lld x", {"localizations": {"he": plural(one="x", other="%lld x")}}, "he", 1),
    # ...inside a substitution, where reading only the top level never looked.
    ("%lld x", {"localizations": {"he": count_substitution(one="%arg", other="%arg")}}, "he", 1),
    # ...and under a device variation.
    ("%lld x", {"localizations": {"ru": {"variations": {"device": {
        "iphone": plural(one="x", other="%lld x"),
    }}}}}, "ru", 1),
    # A count key Russian flattened to one form, while Danish varies it.
    ("%lld read", {"localizations": {"da": plural(one="%lld læst", other="%lld læst"),
                                     "ru": unit("%lld прочитано")}}, "ru", 1),
    # The same for Japanese, which needs only `other`, passes.
    ("%lld read", {"localizations": {"da": plural(one="%lld læst", other="%lld læst"),
                                     "ja": unit("%lld 件既読")}}, "ja", 0),
    # A count key Russian varies through a substitution, complete.
    ("%lld read", {"localizations": {"da": plural(one="%lld læst", other="%lld læst"),
                                     "ru": count_substitution(**RU)}}, "ru", 0),
    # A count key no locale pluralizes: its `%lld` alone makes it one, so the
    # Russian form that serves every count fails. Waiting for a localization
    # to vary it first would pass this.
    ("%lld chats", {"localizations": {"da": unit("%lld chats"),
                                      "ru": unit("%lld чатов")}}, "ru", 1),
    # A key with no number in it is not a count key, and one form is right.
    ("Done", {"localizations": {"ru": unit("Готово")}}, "ru", 0),
    # A count key whose iPhone form varies and whose other device form doesn't.
    ("%lld read", {"localizations": {"da": plural(one="%lld læst", other="%lld læst"),
                                     "ru": {"variations": {"device": {
                                         "iphone": plural(**{k: v.replace("%arg", "%lld") for k, v in RU.items()}),
                                         "mac": unit("%lld прочитано"),
                                     }}}}}, "ru", 1),
    # A substitution that happens to be called `plural` is not a plural
    # variation, and an identifier key with no source names no number, so this
    # is no count key and has nothing missing.
    ("total.label", {"localizations": {"ru": {
        **unit("%#@plural@"),
        "substitutions": {"plural": {"argNum": 1, "formatSpecifier": "lld"}},
    }}}, "ru", 0),
]

# `(key, entry, NOT_COUNTS stand-in, whether it is a count key)`.
COUNT_KEY_TESTS = [
    # Every integer conversion, whatever its length modifier.
    ("%lld chats", {"localizations": {"ru": unit("%lld чатов")}}, {}, True),
    ("%ld chats", {}, {}, True),
    ("%d chats", {}, {}, True),
    ("%llu chats", {}, {}, True),
    ("%u chats", {}, {}, True),
    ("%2$lld chats in %1$@", {}, {}, True),
    # An inflected count.
    ("From ^[%lld item](inflect: true)", {}, {}, True),
    # An identifier key, whose number is in its source localization.
    ("chats.count", {"localizations": {"en": unit("%lld chats")}}, {}, True),
    # A count spliced in through a substitution the source declares.
    ("chats.spliced", {"localizations": {"en": count_substitution(one="%arg chat",
                                                                  other="%arg chats")}}, {}, True),
    # No integer: an object, a hex code, nothing at all.
    ("Reading %@…", {}, {}, False),
    ("Code %x", {}, {}, False),
    ("Answer ready", {}, {}, False),
    # An integer that isn't a count, named as such.
    ("%lld%% of %@", {}, {"%lld%% of %@": "a percentage"}, False),
    # Named or not, a key a localization pluralizes is a count key.
    ("%lld%% of %@", {"localizations": {"da": plural(one="%lld%%", other="%lld%%")}},
     {"%lld%% of %@": "a percentage"}, True),
]

# `(source, [(key, bundle)])` for one file under Sources/.
LITERAL_TESTS = [
    ('Text("New")', [("New", "host")]),
    ('Text("New", bundle: #bundle)', [("New", "own")]),
    ('Text("New", bundle: .module)', [("New", "own")]),
    ('Text("New", bundle: .main)', [("New", "host")]),
    ('Text("New", bundle: theirs)', [("New", "other")]),
    ('String(\n    localized: "Copy",\n    bundle: #bundle\n)', [("Copy", "own")]),
    ('String(localized: "Copy")', [("Copy", "host")]),
    # The parens of an interpolation, and a nested call, come before `bundle:`.
    ('Text("Reading \\(name(of: item))…", comment: note(1), bundle: #bundle)',
     [("Reading \\(name(of: item))…", "own")]),
    ('Text("\\(a)\\(b)")', [("\\(a)\\(b)", "host")]),
    # Views and modifiers with no bundle parameter.
    ('Button("Delete") { remove() }', [("Delete", "host")]),
    ('Label("Copy", systemImage: "doc.on.doc")', [("Copy", "host")]),
    ('.accessibilityLabel("Close")', [("Close", "host")]),
    # A literal inside another call's argument is that call's.
    ('Text(String(localized: "Copy", bundle: #bundle))', [("Copy", "own")]),
    ('Button(action: go) { Text("Go", bundle: #bundle) }', [("Go", "own")]),
    # More views and modifiers that take a `LocalizedStringKey` and no bundle.
    ('ProgressView("Loading")', [("Loading", "host")]),
    ('Tab("Ask", systemImage: "bubble") { AskScreen() }', [("Ask", "host")]),
    ('ShareLink("Share", item: report)', [("Share", "host")]),
    ('CommandMenu("Ask") { buttons }', [("Ask", "host")]),
    ('.accessibilityCustomContent("Rows", value)', [("Rows", "host")]),
    ('.accessibilityCustomContent(Text("Rows", bundle: #bundle), value)', [("Rows", "own")]),
    ('.accessibilityAction(named: "Delete") { remove() }', [("Delete", "host")]),
    ('.accessibilityAction(named: Text("Delete", bundle: #bundle)) { remove() }',
     [("Delete", "own")]),
    ('ProgressView().controlSize(.small)', []),
    ('ShareLink(item: report) { Label { Text("Share", bundle: #bundle) } icon: { icon } }',
     [("Share", "own")]),
    # The key spelled out: the call still decides the bundle.
    ('Text(LocalizedStringKey("Done"))', [("Done", "host")]),
    ('Text(LocalizedStringKey("Done"), bundle: #bundle)', [("Done", "own")]),
    ('Button(LocalizedStringKey("Delete")) { remove() }', [("Delete", "host")]),
    # `.searchable`'s prompt, by its label, at the call's own level.
    ('.searchable(text: $query, prompt: "Search chats")', [("Search chats", "host")]),
    ('.searchable(\n    text: $query,\n    placement: .toolbar,\n    prompt: "Search chats"\n)',
     [("Search chats", "host")]),
    ('.searchable(text: $query, prompt: Text("Search chats", bundle: #bundle))',
     [("Search chats", "own")]),
    ('.searchable(text: $query)', []),
    ('.searchable(text: $query, prompt: prompt)', []),
    ('.searchable(text: $query, prompt: "Search " + scope)', []),
    # `.accessibilityInputLabels`' array, every element, either side of a
    # conditional.
    ('.accessibilityInputLabels(["History", "Chats"])', [("History", "host"), ("Chats", "host")]),
    ('.accessibilityInputLabels(stopping ? [label, "Stop"] : [label])', [("Stop", "host")]),
    ('.accessibilityInputLabels([Text("History", bundle: #bundle), Text(verbatim: "AskKit")])',
     [("History", "own")]),
    ('.accessibilityInputLabels(inputLabels)', []),
    ('.accessibilityInputLabels([Self.label(for: "up"), names["history"]])', []),
    # No lookup.
    ('Text(verbatim: "New")', []),
    ('TextField("", text: $draft, axis: .vertical)', []),
    ('.keyboardShortcut("n", modifiers: [.command, .shift])', []),
    ('logger.info("Started \\(id)")', []),
    ('.accessibilityIdentifier("ask.composer")', []),
    ('AskText("New")', []),
    ('Text("a" + b)', []),
    ('// Text("New")', []),
    ('let x = 1 // Button("Delete")', []),
]


def fixture_catalog(*keys, extra=None):
    """A catalog translating every key into every locale, plus `extra` locales."""
    locales = list(LOCALES) + list(extra or [])
    return {"sourceLanguage": "en", "strings": {
        key: {"localizations": {locale: unit(key) for locale in locales}} for key in keys
    }}


CORE = "Sources/AskCore/Resources/Localizable.xcstrings"
UI = "Sources/AskUI/Resources/Localizable.xcstrings"

# `(catalogs, sources, {kind: count})`, with every kind not named expected to
# find nothing.
AUDIT_TESTS = [
    # Clean.
    ({CORE: fixture_catalog("Retry"), UI: fixture_catalog("Copy")},
     {"Sources/AskCore/A.swift": 'String(localized: "Retry", bundle: #bundle)',
      "Sources/AskUI/B.swift": 'Text("Copy", bundle: #bundle)'},
     {}),
    # AskCore asks its own bundle for a key only AskUI's catalog carries.
    ({CORE: fixture_catalog("Retry"), UI: fixture_catalog("Copy")},
     {"Sources/AskCore/A.swift": 'String(localized: "Copy", bundle: #bundle)'},
     {"orphans": 1}),
    # A table of its own is looked up in that table, in either spelling.
    ({CORE: fixture_catalog("Retry")},
     {"Sources/AskCore/A.swift": 'String(localized: "Retry", table: "Errors", bundle: #bundle)'},
     {"orphans": 1}),
    ({CORE: fixture_catalog("Retry")},
     {"Sources/AskCore/A.swift": 'Text("Retry", tableName: "Errors", bundle: #bundle)'},
     {"orphans": 1}),
    # A locale the catalog carries and LOCALES doesn't name.
    ({CORE: fixture_catalog("Retry", extra=["en-GB"])}, {}, {"locales": 1}),
    # A literal with no bundle, though the catalog has its key.
    ({UI: fixture_catalog("New")}, {"Sources/AskUI/B.swift": 'Text("New")'},
     {"unbundled": 1}),
    # An empty translation.
    ({UI: {"sourceLanguage": "en", "strings": {"Copy": {"localizations": {
        **{locale: unit("Copy") for locale in LOCALES}, "de": unit(""),
    }}}}}, {}, {"untranslated": 1}),
    # A count key every locale left flat: each of the 17 locales with more than
    # `other` reads one count wrong.
    ({UI: fixture_catalog("%lld chats")},
     {"Sources/AskUI/B.swift": 'Text("\\(count) chats", bundle: #bundle)'},
     {"plurals": 17}),
    # A placeholder one translation adds to a key that passes none.
    ({UI: {"sourceLanguage": "en", "strings": {"Answer ready": {"localizations": {
        **{locale: unit("Answer ready") for locale in LOCALES}, "de": unit("Antwort %@ bereit"),
    }}}}}, {}, {"crashers": 1}),
    # A prompt and an input label looked up in the host's bundle.
    ({UI: fixture_catalog("Search chats", "History")},
     {"Sources/AskUI/B.swift": '.searchable(text: $q, prompt: "Search chats")\n'
                               '.accessibilityInputLabels(["History"])'},
     {"unbundled": 2}),
]


def self_test():
    """Fail loudly if any check has stopped reading these shapes right."""
    failures = []
    for case in SELF_TESTS:
        # `(key, entry, expected)`, or a fourth element naming the catalog's
        # source language where it is not English.
        key, entry, expected = case[0], case[1], case[2]
        source_language = case[3] if len(case) > 3 else "en"
        found = specifier_mismatches(key, entry, source_language)
        if len(found) != expected:
            failures.append(f"specifiers of {key!r}: expected {expected} mismatch(es), "
                            f"got {[(('/'.join(p)), v, w) for p, v, w in found]}")
    for localization, expected in COVERAGE_TESTS:
        found = coverage_gap(localization)
        if found != expected:
            failures.append(f"coverage of {localization!r}: expected {expected!r}, got {found!r}")
    for key, entry, locale, expected in PLURAL_TESTS:
        found = plural_gaps(entry["localizations"].get(locale), locale, is_count_key(key, entry))
        if len(found) != expected:
            failures.append(f"plurals of {locale} in {key!r}, {entry!r}: expected {expected} "
                            f"gap(s), got {found}")
    for key, entry, not_counts, expected in COUNT_KEY_TESTS:
        found = is_count_key(key, entry, not_counts=not_counts)
        if found != expected:
            failures.append(f"count key {key!r}, {entry!r}: expected {expected}, got {found}")
    for source, expected in LITERAL_TESTS:
        found = [(key, bundle) for key, _line, _table, bundle
                 in scan_literals("Sources/AskUI/Fixture.swift", source)]
        if found != expected:
            failures.append(f"literals in {source!r}: expected {expected}, got {found}")
    for catalogs, sources, expected in AUDIT_TESTS:
        findings, _checked, _referenced = audit(catalogs, sources)
        counts = {kind: len(items) for kind, items in findings.items() if items}
        if counts != expected:
            failures.append(f"audit of {sorted(catalogs)} and {sources!r}: expected {expected}, "
                            f"got {counts}")
    if not failures:
        return
    print("✗ the catalog checker's own self-test failed — do not trust its verdict:")
    for failure in failures:
        print(f"    {failure}")
    sys.exit(1)


def audit(catalogs, sources):
    """Every finding for these catalogs and this source, by kind.

    `catalogs` maps a catalog's path to its parsed JSON and `sources` a Swift
    file's path to its text, so the self-test hands it fixtures and `main` the
    tree. Returns `(findings, keys graded, literals looked up in their own
    bundle)`.
    """
    findings = {kind: [] for kind in
                ("crashers", "untranslated", "plurals", "locales", "unbundled", "orphans")}
    checked = 0
    known = {}
    for path, catalog in sorted(catalogs.items()):
        strings = catalog.get("strings", {})
        source_language = catalog.get("sourceLanguage", "en")
        known.setdefault(catalog_scope(path), set()).update(strings)
        stray = sorted(
            {locale for entry in strings.values() for locale in (entry.get("localizations") or {})}
            - set(LOCALES) - {source_language}
        )
        if stray:
            findings["locales"].append((path, stray))
        for key, entry in sorted(strings.items()):
            if entry.get("shouldTranslate") is False:
                continue
            checked += 1
            localizations = entry.get("localizations") or {}
            gaps = {}
            for locale in LOCALES:
                why = coverage_gap(localizations.get(locale))
                if why:
                    gaps.setdefault(why, []).append(locale)
            if gaps:
                findings["untranslated"].append((path, key, gaps))
            for where, value, why in specifier_mismatches(key, entry, source_language):
                findings["crashers"].append((path, key, where, value, why))
            count_key = is_count_key(key, entry, source_language)
            for locale in LOCALES:
                for where, why in plural_gaps(localizations.get(locale), locale, count_key):
                    findings["plurals"].append((path, key, locale, where, why))

    looked_up = {}
    for path, source in sorted(sources.items()):
        target = target_of(path)
        for key, line, table, bundle in scan_literals(path, source):
            if bundle == "host":
                findings["unbundled"].append((path, line, key))
            elif bundle == "own":
                looked_up.setdefault((target, table, key), (path, line))
    for (target, table, key), (path, line) in sorted(looked_up.items(), key=str):
        if not any(candidate in known.get((target, table), set())
                   for candidate in candidate_keys(key)):
            findings["orphans"].append((path, line, key, target, table))
    return findings, checked, len(looked_up)


def shown(key):
    return key if len(key) <= 72 else key[:69] + "..."


def report(findings):
    """Print every kind of finding there is; False when there were any."""
    crashers = findings["crashers"]
    if crashers:
        print(f"✗ {len(crashers)} translation(s) read an argument as the wrong type, or one")
        print("  the call never passes — Foundation dereferences the mismatch and the")
        print("  process crashes:")
        for path, key, where, value, why in crashers:
            print(f"    {path}")
            print(f"      {shown(key)!r}")
            print(f"      {'/'.join(where)}: {value!r}")
            print(f"      {why}")
        print("  Number every placeholder in the reordered translation — `%2$@`,")
        print("  `%1$lld` — so each one names the argument it means, and take out any")
        print("  the source doesn't have.")

    untranslated = findings["untranslated"]
    if untranslated:
        print(f"✗ String Catalog completeness: {len(untranslated)} key(s) not translated "
              "in every locale")
        for path, key, gaps in untranslated:
            print(f"    {path}")
            print(f"      {shown(key)!r}")
            for why, locales in sorted(gaps.items()):
                print(f"      {why} {len(locales)}/{len(LOCALES)}: {', '.join(locales)}")
        print("  Translate them, or mark the key \"shouldTranslate\": false if it is not")
        print("  for translation. Do not delete extractor artifacts — -exportLocalizations")
        print("  recreates them.")

    plurals = findings["plurals"]
    if plurals:
        print(f"✗ {len(plurals)} plural form(s) fall short of the CLDR categories their")
        print("  locale needs — the count that falls in a missing one reads wrong:")
        for path, key, locale, where, why in plurals:
            print(f"    {path}")
            print(f"      {shown(key)!r}")
            print(f"      {locale}/{where}: {why}")
        print("  Hebrew has a dual; Russian, Polish, Czech and Ukrainian have four")
        print("  categories and Arabic six. Extra categories beyond the required set are fine.")
        print("  A key whose integer is no count, such as a percentage, goes in NOT_COUNTS")
        print("  with the reason.")

    locales = findings["locales"]
    if locales:
        print(f"✗ {len(locales)} catalog(s) carry a locale LOCALES doesn't name, so nothing")
        print("  here grades it:")
        for path, stray in locales:
            print(f"    {path}: {', '.join(stray)}")
        print("  Add it to LOCALES, with its plural categories in PLURAL_CATEGORIES, or")
        print("  take it out of the catalog.")

    unbundled = findings["unbundled"]
    if unbundled:
        print(f"✗ {len(unbundled)} localized literal(s) name no bundle — looked up in the")
        print("  host's bundle, they show the raw key in every locale but English:")
        for path, line, key in unbundled:
            print(f"    {path}:{line}: {shown(key)!r}")
        print("  Pass `bundle: #bundle`, through `Text(_:bundle:)` or")
        print("  `String(localized:bundle:)` where the view takes no bundle, or use")
        print("  `Text(verbatim:)` for what isn't words.")

    orphans = findings["orphans"]
    if orphans:
        print(f"✗ {len(orphans)} localized literal(s) have no entry in their own target's")
        print(f"  catalog, the only one `#bundle` reads — they ship English to all "
              f"{len(LOCALES)} other locales:")
        for path, line, key, target, table in orphans:
            print(f"    {shown(key)!r}")
            print(f"      {path}:{line}, looked up in {target}'s {table}.xcstrings")

    return not any(findings.values())


def main():
    self_test()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    paths = discover_catalogs()

    missing_required = [p for p in REQUIRED if p not in paths]
    if missing_required:
        print("✗ a required String Catalog is missing:")
        for path in missing_required:
            print(f"    {path}")
        return 1

    catalogs = {}
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            catalogs[path] = json.load(handle)
    findings, checked, referenced = audit(catalogs, read_sources())
    clean = report(findings)

    # A scan that finds nothing has stopped scanning; it has not found a clean
    # tree. When the package's strings moved from `bundle: .module` to
    # `#bundle`, the old pattern read 0 of 79 literals and this check passed.
    if not referenced:
        print("✗ no literal looked up with `bundle: #bundle` found in source — `LOOKUP`")
        print("  no longer matches how the code names its bundle, so the orphan check")
        print("  read nothing")
        return 1
    if not clean:
        return 1

    # Name the discovered set, so a catalog that silently stopped being found is
    # visible in the passing output rather than only in a future failure.
    print(f"✓ String Catalogs complete ({checked} keys × {len(LOCALES)} locales, "
          f"{len(paths)} catalogs; {referenced} literal(s) referenced in source)")
    for path in paths:
        print(f"    {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
