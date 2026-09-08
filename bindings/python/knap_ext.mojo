# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bindings/python/knap_ext.mojo
# Purpose     : CPython extension module exposing Knap to Python.
# Stage       : Milestone M6 Track B, Python consumers. See docs/ROADMAP.md
# Depends on  : knap.tokenizer, std.python.bindings
# Invariants  : The Mojo ABI is not stable, so this must be rebuilt for every
#               toolchain version. Nothing detects a mismatch at run time.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Knap as a native CPython extension module.

The project plan allowed for two outcomes here and asked for the question to
be answered rather than assumed. The answer: Mojo 1.0.0 can build a real
CPython extension module through PythonModuleBuilder, so this takes the
native path and the flat C surface with a ctypes wrapper is not needed.

Three things about Mojo 1.0.0 shaped this file, and all three were found by
compiling rather than by reading:

  * There are no global variables, so a module level registry of loaded
    tokenizers is not possible. State has to live in an exported type.
  * A type exported with add_type must conform to Writable. The failure
    without it is a constraint error deep inside the bindings library that
    does not mention your type.
  * A method reached through the auto downcast pointer cannot mutate the
    value. That is not a limitation here, because every tokenizer method is
    read only after loading.

The Mojo ABI is explicitly not stable. This extension is built against one
exact toolchain and must be rebuilt for any other. Nothing checks that at
import time, and a mismatch will not fail cleanly.

Build it with:

    python bindings/python/build.py
"""

from std.os import abort
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder

from knap.tokenizer import (
    Tokenizer,
    load_cl100k_base_tokenizer,
    load_o200k_base_tokenizer,
)


struct KnapTokenizer(Movable, Writable):
    """A loaded Knap tokenizer, owned by a Python object."""

    var inner: Tokenizer
    """The tokenizer itself, built once when the Python object is created."""

    var encoding: String
    """The encoding name, kept for the representation."""

    def __init__(out self, var inner: Tokenizer, var encoding: String):
        """Take ownership of a loaded tokenizer.

        Args:
            inner: The loaded tokenizer.
            encoding: The encoding name, for diagnostics.
        """
        self.inner = inner^
        self.encoding = encoding^

    def write_to(self, mut writer: Some[Writer]):
        """Render the object for Python's repr.

        Args:
            writer: The destination.

        Required rather than decorative: add_type refuses a type that is not
        Writable, and the error it produces does not say so.
        """
        writer.write("KnapTokenizer(", self.encoding, ")")

    def write_repr_to(self, mut writer: Some[Writer]):
        """Render the object for Python's repr.

        Args:
            writer: The destination.

        Provided explicitly alongside write_to. Mojo would otherwise try to
        derive it by reflection over the fields, which fails because a
        Tokenizer holds a vocabulary and a rank table and is not Writable.
        """
        writer.write("KnapTokenizer(", self.encoding, ")")

    @staticmethod
    def py_init(
        out self: KnapTokenizer, args: PythonObject, kwargs: PythonObject
    ) raises:
        """Construct from Python arguments.

        Args:
            self: The slot to fill.
            args: Positional arguments: the vocabulary path and the encoding
                name.
            kwargs: Ignored.

        Raises:
            Error: if the arguments are wrong, the encoding is unknown, or
                the vocabulary will not load. Mojo errors reach Python as
                exceptions.
        """
        if Int(args.__len__()) != 2:
            raise Error(
                String(
                    "knap: KnapTokenizer takes two arguments, the vocabulary"
                    " path and the encoding name"
                )
            )

        var path = String(py=args[0])
        var name = String(py=args[1])

        if name == "o200k_base":
            self = Self(load_o200k_base_tokenizer(path), name^)
        elif name == "cl100k_base":
            self = Self(load_cl100k_base_tokenizer(path), name^)
        else:
            raise Error(
                String(
                    t"knap: unknown encoding '{name}'. Use cl100k_base or"
                    t" o200k_base."
                )
            )

    @staticmethod
    def encode_ordinary(
        self_ptr: Pointer[KnapTokenizer, MutAnyOrigin], text: PythonObject
    ) raises -> PythonObject:
        """Encode text, treating special token literals as ordinary text.

        Args:
            self_ptr: The tokenizer, downcast automatically.
            text: The text to encode.

        Returns:
            A Python list of integer token ids.

        Raises:
            Error: if encoding fails.
        """
        var ids = self_ptr[].inner.encode_ordinary(String(py=text))
        var out = Python.list()
        for index in range(len(ids)):
            out.append(PythonObject(ids[index]))
        return out

    @staticmethod
    def encode(
        self_ptr: Pointer[KnapTokenizer, MutAnyOrigin],
        text: PythonObject,
        allowed: PythonObject,
    ) raises -> PythonObject:
        """Encode text, permitting the listed special tokens.

        Args:
            self_ptr: The tokenizer, downcast automatically.
            text: The text to encode.
            allowed: A sequence of permitted special token literals.

        Returns:
            A Python list of integer token ids.

        Raises:
            Error: if a special token appears that the caller did not
                permit. That refusal is the point: it stops untrusted input
                injecting a control token.
        """
        var permitted = List[String]()
        var count = Int(allowed.__len__())
        for index in range(count):
            permitted.append(String(py=allowed[index]))

        var ids = self_ptr[].inner.encode(String(py=text), permitted)
        var out = Python.list()
        for index in range(len(ids)):
            out.append(PythonObject(ids[index]))
        return out

    @staticmethod
    def decode_bytes(
        self_ptr: Pointer[KnapTokenizer, MutAnyOrigin], ids: PythonObject
    ) raises -> PythonObject:
        """Decode token ids to raw bytes.

        Args:
            self_ptr: The tokenizer, downcast automatically.
            ids: A sequence of integer token ids.

        Returns:
            A Python list of integers, one per byte. The Python wrapper turns
            this into a bytes object.

        Raises:
            Error: if any id is unassigned in this encoding.

        Bytes rather than text, deliberately. Byte level BPE can decode to a
        partial UTF-8 sequence when a caller decodes a slice of a longer
        token list, and returning text would force a lossy decision here
        instead of leaving it with the caller.
        """
        var token_ids = List[Int]()
        var count = Int(ids.__len__())
        for index in range(count):
            token_ids.append(Int(py=ids[index]))

        var raw = self_ptr[].inner.decode_bytes(token_ids)
        var out = Python.list()
        for index in range(len(raw)):
            out.append(PythonObject(Int(raw[index])))
        return out

    @staticmethod
    def n_vocab(
        self_ptr: Pointer[KnapTokenizer, MutAnyOrigin]
    ) raises -> PythonObject:
        """Return one past the highest assigned token id.

        Args:
            self_ptr: The tokenizer, downcast automatically.

        Returns:
            The size of the id space, matching what tiktoken calls n_vocab.

        Raises:
            Error: never in practice.
        """
        return PythonObject(self_ptr[].inner.vocabulary.id_space_size())


@export
def PyInit_knap_ext() abi("C") -> PythonObject:
    """Initialise the extension module.

    Returns:
        The finished module object.

    Declared abi("C") because CPython calls it directly across the C
    boundary, which is also why it cannot raise: a failure has to abort
    rather than propagate. The methods registered below are ordinary Mojo
    functions wrapped in a trampoline that turns their errors into Python
    exceptions.
    """
    try:
        var module = PythonModuleBuilder("knap_ext")
        _ = (
            module.add_type[KnapTokenizer]("KnapTokenizer")
            .def_py_init[KnapTokenizer.py_init]()
            .def_method[KnapTokenizer.encode_ordinary]("encode_ordinary")
            .def_method[KnapTokenizer.encode]("encode")
            .def_method[KnapTokenizer.decode_bytes]("decode_bytes")
            .def_method[KnapTokenizer.n_vocab]("n_vocab")
        )
        return module.finalize()
    except e:
        abort(String("knap: failed to create the extension module: ", e))


# =============================================================================
# End of file: bindings/python/knap_ext.mojo
# =============================================================================
