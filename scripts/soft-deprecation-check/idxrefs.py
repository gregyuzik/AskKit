#!/usr/bin/env python3
"""Dump every symbol reference an index store records for files under a root.

Usage: idxrefs.py <DataStore> <source-root> [exclude-substring ...] > refs.tsv
Excludes default to /SourcePackages/ and /Intermediates.noindex/ (generated sources).
Output rows: usr \t name \t file \t line \t col \t roles

It exits 1 rather than print nothing when the store can't be read: a store
that won't open, a walk of its units the library reports as failed, a store
with no units, a unit or record that won't open, or no record for a file under
the root. Each of those prints no rows, which the caller would report as
"0 deprecated symbols", a pass that checked nothing.
"""
import ctypes as C
import subprocess
import sys

# The selected Xcode's, which `xcode-select -p` names (DEVELOPER_DIR, when set, overrides it).
DEVELOPER = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
LIB = DEVELOPER + "/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib"
lib = C.CDLL(LIB)


class StrRef(C.Structure):
    _fields_ = [("data", C.c_char_p), ("length", C.c_size_t)]

    def s(self):
        if not self.data:
            return ""
        return C.string_at(self.data, self.length).decode("utf-8", "replace")


vp = C.c_void_p
lib.indexstore_error_get_description.restype = C.c_char_p
lib.indexstore_error_get_description.argtypes = [vp]
lib.indexstore_store_create.restype = vp
lib.indexstore_store_create.argtypes = [C.c_char_p, C.POINTER(vp)]
UNIT_CB = C.CFUNCTYPE(C.c_bool, vp, StrRef)
lib.indexstore_store_units_apply_f.restype = C.c_bool
lib.indexstore_store_units_apply_f.argtypes = [vp, C.c_uint, vp, UNIT_CB]
lib.indexstore_unit_reader_create.restype = vp
lib.indexstore_unit_reader_create.argtypes = [vp, C.c_char_p, C.POINTER(vp)]
lib.indexstore_unit_reader_dispose.argtypes = [vp]
lib.indexstore_unit_reader_is_system_unit.restype = C.c_bool
lib.indexstore_unit_reader_is_system_unit.argtypes = [vp]
DEP_CB = C.CFUNCTYPE(C.c_bool, vp, vp)
lib.indexstore_unit_reader_dependencies_apply_f.restype = C.c_bool
lib.indexstore_unit_reader_dependencies_apply_f.argtypes = [vp, vp, DEP_CB]
lib.indexstore_unit_dependency_get_kind.restype = C.c_int
lib.indexstore_unit_dependency_get_kind.argtypes = [vp]
lib.indexstore_unit_dependency_get_name.restype = StrRef
lib.indexstore_unit_dependency_get_name.argtypes = [vp]
lib.indexstore_unit_dependency_get_filepath.restype = StrRef
lib.indexstore_unit_dependency_get_filepath.argtypes = [vp]
lib.indexstore_record_reader_create.restype = vp
lib.indexstore_record_reader_create.argtypes = [vp, C.c_char_p, C.POINTER(vp)]
lib.indexstore_record_reader_dispose.argtypes = [vp]
OCC_CB = C.CFUNCTYPE(C.c_bool, vp, vp)
lib.indexstore_record_reader_occurrences_apply_f.restype = C.c_bool
lib.indexstore_record_reader_occurrences_apply_f.argtypes = [vp, vp, OCC_CB]
lib.indexstore_occurrence_get_symbol.restype = vp
lib.indexstore_occurrence_get_symbol.argtypes = [vp]
lib.indexstore_occurrence_get_roles.restype = C.c_uint64
lib.indexstore_occurrence_get_roles.argtypes = [vp]
lib.indexstore_occurrence_get_line_col.argtypes = [vp, C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
lib.indexstore_symbol_get_usr.restype = StrRef
lib.indexstore_symbol_get_usr.argtypes = [vp]
lib.indexstore_symbol_get_name.restype = StrRef
lib.indexstore_symbol_get_name.argtypes = [vp]

RECORD_KIND = 2
ROLE_REFERENCE = 1 << 2

store_path, root = sys.argv[1].encode(), sys.argv[2]
excludes = sys.argv[3:] or ["/SourcePackages/", "/Intermediates.noindex/"]
err = vp()


def fail(what):
    """Exit naming what couldn't be read, and the library's reason when it gave one."""
    reason = lib.indexstore_error_get_description(err).decode("utf-8", "replace") if err else ""
    sys.exit(f"idxrefs: {what}" + (f": {reason}" if reason else ""))


store = lib.indexstore_store_create(store_path, C.byref(err))
if not store:
    fail(f"cannot open the index store at {sys.argv[1]}")

units = []


@UNIT_CB
def on_unit(_ctx, name):
    units.append(name.s())
    return True


if not lib.indexstore_store_units_apply_f(store, 0, None, on_unit):
    fail("reading the store's units failed")
if not units:
    fail(f"the index store at {sys.argv[1]} holds no units: was it built with indexing on?")

records = {}  # record name -> source path


for unit in units:
    reader = lib.indexstore_unit_reader_create(store, unit.encode(), C.byref(err))
    if not reader:
        fail(f"cannot read unit {unit}")
    if lib.indexstore_unit_reader_is_system_unit(reader):
        lib.indexstore_unit_reader_dispose(reader)
        continue

    @DEP_CB
    def on_dep(_ctx, dep):
        if lib.indexstore_unit_dependency_get_kind(dep) == RECORD_KIND:
            path = lib.indexstore_unit_dependency_get_filepath(dep).s()
            if path.startswith(root) and not any(x in path for x in excludes):
                records[lib.indexstore_unit_dependency_get_name(dep).s()] = path
        return True

    # The walks inside a unit or a record return false for an empty one too: a
    # file `#if` compiles out of a platform leaves a record with no
    # occurrences. So their results say nothing, and only the store's own walk
    # and the readers are held to.
    lib.indexstore_unit_reader_dependencies_apply_f(reader, None, on_dep)
    lib.indexstore_unit_reader_dispose(reader)

if not records:
    fail(f"no record in the index is for a file under {root}: is that the root the build compiled?")

seen = set()
out = sys.stdout
for rec, path in records.items():
    reader = lib.indexstore_record_reader_create(store, rec.encode(), C.byref(err))
    if not reader:
        fail(f"cannot read the record for {path}")

    @OCC_CB
    def on_occ(_ctx, occ):
        roles = lib.indexstore_occurrence_get_roles(occ)
        if not roles & ROLE_REFERENCE:
            return True
        sym = lib.indexstore_occurrence_get_symbol(occ)
        line, col = C.c_uint(), C.c_uint()
        lib.indexstore_occurrence_get_line_col(occ, C.byref(line), C.byref(col))
        usr = lib.indexstore_symbol_get_usr(sym).s()
        key = (usr, path, line.value, col.value)
        if key not in seen:
            seen.add(key)
            name = lib.indexstore_symbol_get_name(sym).s()
            out.write(f"{usr}\t{name}\t{path}\t{line.value}\t{col.value}\t{roles}\n")
        return True

    lib.indexstore_record_reader_occurrences_apply_f(reader, None, on_occ)
    lib.indexstore_record_reader_dispose(reader)

print(f"records={len(records)} refs={len(seen)}", file=sys.stderr)
