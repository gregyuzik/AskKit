#!/usr/bin/env python3
"""The String Catalog checks only AskKit's own source can answer.

The catalogs themselves are graded by the maintainers' push gate
(`gate_catalogs`, which PREPUSH_LIB provides), with the checker every one of
their apps shares: every key in all 24 locales beside English, every unit
translated and not blank, each argument's specifier, the CLDR plural
categories, no stray locale, and the bytes Xcode writes. That checker reads
catalogs alone, and a host's checks scan the host's own tree, never a
package's. What AskKit's code asks of its catalogs is checked here, in CI and
the push gate alike.

Both catalogs have to be there (`REQUIRED`).

A count key has to vary by plural in every locale whose counts take more than
one form. A key is a count key when its source passes an integer (`%lld`,
`%ld`, `%d`, `%u` and the rest) or inflects (`^[…](inflect: true)`), unless
`NOT_COUNTS` names it, or when any localization varies it by plural: waiting
for a localization to pluralize it first would pass a key every locale left
flat. Which categories a plural needs is the shared checker's to grade, once
the plural is there.

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

Run directly (`python3 scripts/check-strings.py`), or through
`scripts/ci.sh checks`, which both the push gate and CI's `checks` job run.
"""
import json
import os
import re
import sys

# The locales CLDR gives one plural category, `other`: Indonesian, Thai,
# Vietnamese and the CJK locales inflect nothing for a number, so one form
# serves every count there. Every other locale needs `one` and `other` at
# least, and a count key left flat in it reads some count wrong. The standard's
# whole table, which grades a plural's categories, is the shared checker's, and
# TRANSLATION.md lists it: a locale the standard adds with `other` alone goes
# here too.
OTHER_ONLY = {"id", "ja", "ko", "th", "vi", "zh-Hans", "zh-Hant"}

# Discovered, not hand-listed: a catalog added under a target serves that
# target's lookups, and its count keys are graded, without anyone listing it.
# The Swift files under the same roots are the source scanned.
CATALOG_ROOTS = ["Sources"]

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
                    found.append(os.path.join(dirpath, name))
    return sorted(found)


def is_plural_variation(path, name):
    """Whether `name`, reached at `path`, is a plural variation rather than a
    substitution or a device that happens to be called `plural`."""
    return name == "plural" and path[-1:] == ("variations",)


def plural_nodes(node, path=()):
    """(path, categories) for every plural variation under a localization.

    Wherever it sits: at the top, under a device variation, or inside a
    substitution — the `%#@name@` form Xcode writes the moment a plural key is
    edited. Reading only the top level saw none of the last two.
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


def flat_forms(entry, source_language="en"):
    """[(locale, where)] for each unit of a count key's localizations that gives
    every count one form, in a locale whose counts take more than one.

    Asked of a count key only. The source isn't graded, since it is the
    contract the translations are held to, and nor is a locale CLDR gives
    `other` alone.
    """
    found = []
    for locale, localization in sorted((entry.get("localizations") or {}).items()):
        if locale == source_language or locale in OTHER_ONLY:
            continue
        found += [(locale, "/".join(path)) for path in flat_units(localization)]
    return found


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
# every locale AND passes the shared catalog checker, which only ever grades
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
# modifier the extractor can emit between the two.
#
# **The substitution alternative comes first, and the order is load-bearing.**
# `re` tries alternatives left to right at each position, and the specifier
# branch reads `%#@items@` quite happily as a bare `%@`: the `#` is swallowed by
# the flags class and `@` is taken for the conversion, so a count spliced in
# through a substitution would read as an object. `%#@` as a printf form is
# "alternate-form object", which nothing writes, so the reference spelling has
# no rival. The legacy stringsdict spelling `%1$#@name@` isn't matched as one:
# Xcode doesn't write it.
SPECIFIER = re.compile(
    r"%#@([^@]+)@"
    r"|%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfeEgGcCsSpaAF%])"
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
    localization this value came from. A reference the map doesn't declare
    names no argument, and is passed over.
    """
    substitutions = substitutions or {}
    arguments = []
    position = 0
    for match in SPECIFIER.finditer(value):
        name, explicit, length, conversion = match.groups()
        if name is not None:
            declared = substitutions.get(name)
            if isinstance(declared, dict) and "argNum" in declared:
                position = int(declared["argNum"])
                arguments.append((position, str(declared.get("formatSpecifier", ""))))
            continue
        if conversion == "%":
            continue
        if explicit is None:
            position += 1
        else:
            position = int(explicit)
        arguments.append((position, (length or "") + conversion))
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

    A substitution's inner plural forms are `%arg`-shaped, and tokenize as a
    `%a` hex float with the letters `rg` after it. They are no format: the
    reference that splices them in is read through the map, as its argument
    `argNum` carrying `formatSpecifier`.
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

    Read from the key alone an identifier key yields nothing, so `chats.count`,
    whose source is `%lld chats`, would be no count key, and every locale could
    leave it flat.

    The key wins when it has arguments of its own, so the source localization
    is read only for a key with none. Its values are merged rather than the
    first one taken, because a plural form can drop the count: a `one` of
    "One file in %2$@" names argument 2 and not argument 1.

    `source_language` is the catalog's own `sourceLanguage` rather than `en`
    assumed; the field exists because it is not always English.
    """
    by_key = format_arguments(key)
    if by_key:
        return by_key
    source = (entry.get("localizations") or {}).get(source_language)
    if not isinstance(source, dict):
        return by_key
    found = {}
    for value, substitutions in source_values(source):
        for index, specifier in format_arguments(value, substitutions):
            found.setdefault(index, specifier)
    return sorted(found.items())


def unit(value):
    """A localization holding one translated unit, for the fixtures below."""
    return {"stringUnit": {"state": "translated", "value": value}}


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

# `(key, entry, locale, expected count of flat forms there)`, graded the way
# `audit` grades it: the key and the entry decide whether it counts.
FLAT_TESTS = [
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
    # The source is the contract the translations are held to, and isn't graded.
    ("%lld chats", {"localizations": {"en": unit("%lld chats"),
                                      "ru": unit("%lld чатов")}}, "en", 0),
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
    # is no count key, and one form is right.
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
    # ...and one whose substitution only declares its type: read as a specifier,
    # `%#@n@` would be a `%@`, and the key no count key.
    ("chats.typed", {"localizations": {"en": {
        **unit("%#@n@"), "substitutions": {"n": {"argNum": 1, "formatSpecifier": "lld"}},
    }}}, {}, True),
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


# The source and a few locales, for the fixtures below: which locales a catalog
# carries is the shared checker's to grade. Two of these need only `other`.
FIXTURE_LOCALES = ("en", "de", "he", "ja", "ru", "zh-Hans")


def fixture_catalog(*keys):
    """A catalog giving every key one form in each of `FIXTURE_LOCALES`."""
    return {"sourceLanguage": "en", "strings": {
        key: {"localizations": {locale: unit(key) for locale in FIXTURE_LOCALES}} for key in keys
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
    # A literal with no bundle, though the catalog has its key.
    ({UI: fixture_catalog("New")}, {"Sources/AskUI/B.swift": 'Text("New")'},
     {"unbundled": 1}),
    # A count key every locale left flat: each of the three locales with more
    # than `other` reads one count wrong, and the source isn't graded.
    ({UI: fixture_catalog("%lld chats")},
     {"Sources/AskUI/B.swift": 'Text("\\(count) chats", bundle: #bundle)'},
     {"counts": 3}),
    # A prompt and an input label looked up in the host's bundle.
    ({UI: fixture_catalog("Search chats", "History")},
     {"Sources/AskUI/B.swift": '.searchable(text: $q, prompt: "Search chats")\n'
                               '.accessibilityInputLabels(["History"])'},
     {"unbundled": 2}),
]


def self_test():
    """Fail loudly if any check has stopped reading these shapes right."""
    failures = []
    for key, entry, locale, expected in FLAT_TESTS:
        flat = flat_forms(entry) if is_count_key(key, entry) else []
        found = [where for at, where in flat if at == locale]
        if len(found) != expected:
            failures.append(f"flat forms of {locale} in {key!r}, {entry!r}: expected {expected}, "
                            f"got {found}")
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
        findings, _counted, _referenced = audit(catalogs, sources)
        counts = {kind: len(items) for kind, items in findings.items() if items}
        if counts != expected:
            failures.append(f"audit of {sorted(catalogs)} and {sources!r}: expected {expected}, "
                            f"got {counts}")
    if not failures:
        return
    print("✗ the string checks' own self-test failed — do not trust their verdict:")
    for failure in failures:
        print(f"    {failure}")
    sys.exit(1)


def audit(catalogs, sources):
    """Every finding for these catalogs and this source, by kind.

    `catalogs` maps a catalog's path to its parsed JSON and `sources` a Swift
    file's path to its text, so the self-test hands it fixtures and `main` the
    tree. Returns `(findings, count keys graded, literals looked up in their own
    bundle)`.
    """
    findings = {kind: [] for kind in ("counts", "unbundled", "orphans")}
    counted = 0
    known = {}
    for path, catalog in sorted(catalogs.items()):
        strings = catalog.get("strings", {})
        source_language = catalog.get("sourceLanguage", "en")
        known.setdefault(catalog_scope(path), set()).update(strings)
        for key, entry in sorted(strings.items()):
            if entry.get("shouldTranslate") is False:
                continue
            if not is_count_key(key, entry, source_language):
                continue
            counted += 1
            for locale, where in flat_forms(entry, source_language):
                findings["counts"].append((path, key, locale, where))

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
    return findings, counted, len(looked_up)


def shown(key):
    return key if len(key) <= 72 else key[:69] + "..."


def report(findings):
    """Print every kind of finding there is; False when there were any."""
    counts = findings["counts"]
    if counts:
        print(f"✗ {len(counts)} form(s) of a count key read the same for every count, in a")
        print("  locale whose counts take more than one form, so some count reads wrong:")
        for path, key, locale, where in counts:
            print(f"    {path}")
            print(f"      {shown(key)!r}")
            print(f"      {locale}/{where}: one form for every count")
        print("  Vary each by plural, with the categories TRANSLATION.md lists for its")
        print("  locale. A key whose integer is no count, such as a percentage, goes in")
        print("  NOT_COUNTS with the reason.")

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
        print("  catalog, the only one `#bundle` reads — they ship English to every other")
        print("  locale:")
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
    findings, counted, referenced = audit(catalogs, read_sources())
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
    print(f"✓ String lookups and count keys ({referenced} literal(s) looked up in their own "
          f"bundle, {counted} count key(s), {len(paths)} catalogs)")
    for path in paths:
        print(f"    {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
