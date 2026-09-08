# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : bench/harness.mojo
# Purpose     : Timing and statistics shared by every Knap benchmark, and the
#               machine readable line format the driver collects.
# Stage       : Milestone M5, SIMD and benchmarks. See docs/BENCHMARKS.md
# Depends on  : std.time
# Invariants  : Every reported figure carries its sample count and a spread.
#               A single number with no spread is not a measurement.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Shared timing and statistics for the Knap benchmarks.

One harness rather than five copies, because the statistics are the part
most easily got subtly wrong, and because docs/BENCHMARKS.md commits to
specific estimator definitions that every benchmark must actually use.

The estimators, stated here because stating them is the point:

  * The mean is the arithmetic mean of the sample durations.
  * The standard deviation is the sample standard deviation, dividing by
    n - 1, not the population form.
  * The coefficient of variation is the standard deviation over the mean,
    reported so a reader can see whether a difference between two numbers
    is larger than the noise in either.
  * A percentile uses the nearest rank method on the sorted samples: the
    p-th percentile is the sample at index ceil(p / 100 * n), one based.
    There is no interpolation between neighbouring samples.

Output is one line per measurement, in a fixed key equals value shape, so
bench/run_all.sh can collect results without parsing prose.
"""

from std.time import perf_counter_ns


@fieldwise_init
struct Samples(Copyable, Movable):
    """A collection of timing samples, in nanoseconds."""

    var values: List[Int]
    """One duration per measured iteration."""

    def __init__(out self):
        """Create an empty sample set."""
        self.values = List[Int]()

    def add(mut self, nanoseconds: Int):
        """Record one sample.

        Args:
            nanoseconds: The measured duration.
        """
        self.values.append(nanoseconds)

    def count(self) -> Int:
        """Return how many samples were recorded.

        Returns:
            The sample count.
        """
        return len(self.values)

    def mean(self) -> Float64:
        """Return the arithmetic mean of the samples.

        Returns:
            The mean in nanoseconds, or zero when there are no samples.
        """
        if len(self.values) == 0:
            return 0.0
        var total = 0.0
        for index in range(len(self.values)):
            total += Float64(self.values[index])
        return total / Float64(len(self.values))

    def deviation(self) -> Float64:
        """Return the sample standard deviation.

        Returns:
            The standard deviation in nanoseconds, or zero with fewer than
            two samples.

        Divides by n - 1 rather than n. With a handful of samples the
        difference is not negligible, and the sample form is the honest one
        when the samples are a sample rather than the whole population.
        """
        var count = len(self.values)
        if count < 2:
            return 0.0
        var average = self.mean()
        var total = 0.0
        for index in range(count):
            var delta = Float64(self.values[index]) - average
            total += delta * delta
        return (total / Float64(count - 1)) ** 0.5

    def coefficient_of_variation(self) -> Float64:
        """Return the standard deviation divided by the mean.

        Returns:
            The dimensionless spread, or zero when the mean is zero.
        """
        var average = self.mean()
        if average == 0.0:
            return 0.0
        return self.deviation() / average

    def sorted_values(self) -> List[Int]:
        """Return the samples in ascending order.

        Returns:
            A sorted copy.

        An insertion sort, which is the right choice here: sample counts are
        in the hundreds or thousands, and a simple sort that is obviously
        correct beats a clever one in code nobody profiles.
        """
        var out = List[Int](capacity=len(self.values))
        for index in range(len(self.values)):
            out.append(self.values[index])
        for index in range(1, len(out)):
            var current = out[index]
            var position = index - 1
            while position >= 0 and out[position] > current:
                out[position + 1] = out[position]
                position -= 1
            out[position + 1] = current
        return out^

    def percentile(self, fraction: Float64) raises -> Int:
        """Return a percentile by the nearest rank method.

        Args:
            fraction: The percentile as a fraction, so 0.5 is the median and
                0.99 is the ninety ninth percentile.

        Returns:
            The sample at that rank, in nanoseconds.

        Raises:
            Error: if there are no samples.

        Nearest rank, with no interpolation. Stated rather than assumed,
        because implementations differ and a p99 computed one way is not
        comparable with a p99 computed another.
        """
        if len(self.values) == 0:
            raise Error(String("knap bench: no samples to take a percentile"))
        var ordered = self.sorted_values()
        var rank = Int(fraction * Float64(len(ordered)) + 0.9999999)
        if rank < 1:
            rank = 1
        if rank > len(ordered):
            rank = len(ordered)
        return ordered[rank - 1]


def now() -> Int:
    """Return a monotonic timestamp in nanoseconds.

    Returns:
        The current value of the performance counter.
    """
    return perf_counter_ns()


def report_throughput(
    name: String, bytes_processed: Int, tokens: Int, samples: Samples
) raises:
    """Print one throughput measurement in the collected line format.

    Args:
        name: Benchmark name.
        bytes_processed: Input size for one iteration.
        tokens: Tokens produced by one iteration.
        samples: The measured durations.

    Raises:
        Error: if there are no samples.

    Both megabytes per second and tokens per second are printed, because
    docs/BENCHMARKS.md requires both and because the ratio between them is
    the compression ratio, which is the thing that actually varies between
    corpora.
    """
    var mean_ns = samples.mean()
    var seconds = mean_ns / 1.0e9
    var megabytes = Float64(bytes_processed) / 1048576.0
    var mb_per_second = megabytes / seconds if seconds > 0.0 else 0.0
    var tokens_per_second = Float64(tokens) / seconds if seconds > 0.0 else 0.0
    var ratio = (
        Float64(bytes_processed) / Float64(tokens) if tokens > 0 else 0.0
    )

    print(
        "BENCH name=",
        name,
        " kind=throughput samples=",
        samples.count(),
        " bytes=",
        bytes_processed,
        " tokens=",
        tokens,
        " mean_ns=",
        Int(mean_ns),
        " stddev_ns=",
        Int(samples.deviation()),
        " cv=",
        samples.coefficient_of_variation(),
        " mb_per_s=",
        mb_per_second,
        " tokens_per_s=",
        tokens_per_second,
        " bytes_per_token=",
        ratio,
        sep="",
    )


def report_latency(name: String, samples: Samples) raises:
    """Print one latency measurement in the collected line format.

    Args:
        name: Benchmark name.
        samples: The measured durations.

    Raises:
        Error: if there are no samples.

    Latency is reported as percentiles rather than as a mean, because the
    shape that matters for serving is the tail. A mean latency hides exactly
    the behaviour anyone would care about.
    """
    print(
        "BENCH name=",
        name,
        " kind=latency samples=",
        samples.count(),
        " mean_ns=",
        Int(samples.mean()),
        " stddev_ns=",
        Int(samples.deviation()),
        " cv=",
        samples.coefficient_of_variation(),
        " p50_ns=",
        samples.percentile(0.50),
        " p90_ns=",
        samples.percentile(0.90),
        " p99_ns=",
        samples.percentile(0.99),
        sep="",
    )


comptime PROSE_OFFSET: Int = 30408704
"""Byte offset where the corpus stops being generated hazard text.

The mixed corpus is three sections joined in order: a generated hazard
section, five books, then a few million sentences. The hazard section is
first and it is large, and it is nothing like natural language. Its first
two megabytes contain 205 distinct whitespace separated words, against tens
of thousands in the same volume of prose.

Benchmarking a prefix of this file therefore measures the hazard section and
nothing else, which flatters everything that likes repetition. The piece
cache is the clearest case: measured on the prefix it reported a 99.99
percent hit rate from 127 distinct pieces, which says nothing about real
text. Every throughput benchmark here starts at this offset instead.

The hazard section is not junk and it is not removed. It is exactly the
right input for the correctness gates, which is why it exists. It is the
wrong input for a throughput claim.
"""


def read_corpus_slice(
    path: String, offset: Int, limit: Int
) raises -> List[UInt8]:
    """Read a whole-line slice of the corpus.

    Args:
        path: File to read.
        offset: Byte offset to start near.
        limit: How many bytes to keep, before trimming to a line boundary.

    Returns:
        The slice, beginning just after a line feed and ending on one.

    Raises:
        Error: if the file cannot be opened or holds no line feed after the
            offset, which would mean the corpus is not what this expects.

    Snapped to line boundaries in both directions, for two reasons. A slice
    starting inside a multi-byte sequence is not valid UTF-8, and the
    reference implementations take text rather than bytes, so they could not
    be given the same input. And a slice ending mid-word would make the last
    pre-token an artefact of the cut rather than of the text.
    """
    try:
        var handle = open(path, "r")
        var data = handle.read_bytes()
        handle.close()

        var start = offset
        if start >= len(data):
            start = 0
        while start < len(data) and data[start] != 10:
            start += 1
        if start >= len(data):
            raise Error(
                String(t"knap bench: no line boundary after offset {offset}")
            )
        start += 1

        var end = start + limit
        if end > len(data):
            end = len(data)
        while end > start and data[end - 1] != 10:
            end -= 1
        if end <= start:
            end = start + limit
            if end > len(data):
                end = len(data)

        var out = List[UInt8](capacity=end - start)
        for index in range(start, end):
            out.append(data[index])
        return out^
    except:
        var message = String(t"knap bench: cannot read '{path}'.")
        message += " Run 'python scripts/fetch_corpus.py' first."
        raise Error(message)


# =============================================================================
# End of file: bench/harness.mojo
# =============================================================================
