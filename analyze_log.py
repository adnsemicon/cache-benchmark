#!/usr/bin/env python3
"""
Cache trace analyzer for RTL TRC logs.

Usage:
    python3 analyze_log.py ci_log.txt --vc 16 --ways 2 --lines 512 --linebytes 16 --policy PLRU

Options:
    --vc        Victim cache entries
    --ways      Cache associativity
    --lines     Total main-cache lines (CL)
    --linebytes Bytes per cache line
    --policy    Replacement policy to compare (LRU, PLRU, SRRIP, BRRIP, DRRIP)
"""

import re
import sys
import argparse


# ============================================================
# Arguments
# ============================================================

parser = argparse.ArgumentParser()

parser.add_argument("log")
parser.add_argument("--vc", type=int, default=16)
parser.add_argument("--ways", type=int, default=4)
parser.add_argument("--lines", type=int, default=256)
parser.add_argument("--linebytes", type=int, default=16)
parser.add_argument("--policy", type=str, default="PLRU", help="Cache replacement policy (LRU, PLRU, SRRIP, BRRIP, DRRIP)")

args = parser.parse_args()

CL = args.lines
WAYS = args.ways
VC_SIZE = args.vc
LINE_BYTES = args.linebytes
SELECTED_POLICY = args.policy.upper()

if WAYS < 1:
    sys.exit("ERROR: ways must be >= 1")

if CL < WAYS or CL % WAYS != 0:
    sys.exit("ERROR: lines must be divisible by ways")

if VC_SIZE < 0:
    sys.exit("ERROR: VC size cannot be negative")

if LINE_BYTES < 1 or (LINE_BYTES & (LINE_BYTES - 1)):
    sys.exit("ERROR: linebytes must be a power of two")

valid_policies = ["LRU", "PLRU", "SRRIP", "BRRIP", "DRRIP"]
if SELECTED_POLICY not in valid_policies:
    sys.exit(f"ERROR: Invalid policy '{SELECTED_POLICY}'. Choose from {valid_policies}")

SETS = CL // WAYS
OFFSET_BITS = LINE_BYTES.bit_length() - 1


# ============================================================
# Read RTL trace
# ============================================================

addresses = []
rtl_results = []

pattern = re.compile(
    r"\bTRC\s+([0-9a-fA-F]+)\s+([HVM])\b"
)

try:
    with open(args.log, "r", errors="ignore") as file:
        for line in file:

            match = pattern.search(line)

            if match:
                addresses.append(
                    int(match.group(1), 16)
                )

                rtl_results.append(
                    match.group(2)
                )

except OSError as error:
    sys.exit(f"ERROR: {error}")

if not addresses:
    sys.exit("ERROR: No TRC entries found")

lines = [
    address >> OFFSET_BITS
    for address in addresses
]

N = len(lines)

rtl_hit = rtl_results.count("H")
rtl_vc = rtl_results.count("V")
rtl_miss = rtl_results.count("M")
rtl_total = rtl_hit + rtl_vc


# ============================================================
# RTL statistics
# ============================================================

print("\n========== RTL STATISTICS ==========")

print(f"Requests       : {N}")
print(f"Main hits      : {rtl_hit}")
print(f"VC hits        : {rtl_vc}")
print(f"Total hits     : {rtl_total}")
print(f"Misses         : {rtl_miss}")

print(
    f"Hit rate       : {100.0 * rtl_total / N:.2f}%"
)


# ============================================================
# Trace statistics
# ============================================================

unique_lines = len(set(lines))

print("\n========== TRACE STATISTICS ==========")

print(f"Unique lines   : {unique_lines}")

print(
    f"Compulsory-miss upper bound: "
    f"{100.0 * (1 - unique_lines / N):.2f}%"
)

same_line = sum(
    1 for i in range(1, N)
    if lines[i] == lines[i - 1]
)

next_line = sum(
    1 for i in range(1, N)
    if lines[i] == lines[i - 1] + 1
)

print(
    f"Same line as previous request: "
    f"{100.0 * same_line / N:.2f}%"
)

print(
    f"Next sequential line: "
    f"{100.0 * next_line / N:.2f}%"
)


# ============================================================
# Reuse distance
# ============================================================

stack = []
reuse_distance = []

for line in lines:

    if line in stack:
        distance = stack.index(line)
        stack.pop(distance)
        reuse_distance.append(distance)

    else:
        reuse_distance.append(None)

    stack.insert(0, line)


def reuse_percent(condition):

    count = sum(
        1 for distance in reuse_distance
        if distance is not None and condition(distance)
    )

    return 100.0 * count / N


print("\n========== REUSE DISTANCE ==========")

capacity = CL + VC_SIZE

ranges = [
    (0, 1),
    (1, 16),
    (16, 64),
    (64, 256),
    (256, capacity),
    (capacity, 2 * capacity),
    (2 * capacity, 10**18)
]

for low, high in ranges:

    if high <= low:
        continue

    label = "inf" if high == 10**18 else str(high - 1)

    print(
        f"{low:>6} .. {label:>6}: "
        f"{reuse_percent(lambda d, lo=low, hi=high: lo <= d < hi):.2f}%"
    )

print(
    f"Never seen before: "
    f"{100.0 * reuse_distance.count(None) / N:.2f}%"
)


# ============================================================
# Suspicious miss detection
# ============================================================

suspicious = []

for i in range(N):

    distance = reuse_distance[i]

    if (
        rtl_results[i] == "M"
        and distance is not None
        and distance <= WAYS - 1
    ):
        suspicious.append(i)

print("\n========== MISS CHECK ==========")

print(
    f"Suspicious misses: {len(suspicious)}"
)

for i in suspicious[:10]:

    print(
        f"Request #{i}: "
        f"address=0x{addresses[i]:x}, "
        f"line=0x{lines[i]:x}, "
        f"distance={reuse_distance[i]}"
    )

print(
    "\nRecent reuse (<16 / <64 / <256): "
    f"{reuse_percent(lambda d: d < 16):.2f}% / "
    f"{reuse_percent(lambda d: d < 64):.2f}% / "
    f"{reuse_percent(lambda d: d < 256):.2f}%"
)


# ============================================================
# Cache model
# ============================================================

class CacheModel:

    def __init__(self, policy, vc_size):

        self.policy = policy
        self.vc_size = vc_size

        self.tags = [
            [None] * WAYS
            for _ in range(SETS)
        ]

        self.rank = [
            list(range(WAYS))
            for _ in range(SETS)
        ]

        self.rrpv = [
            [3] * WAYS
            for _ in range(SETS)
        ]

        self.tree = [
            [0, 0, 0]
            for _ in range(SETS)
        ]

        self.psel = 512
        self.bctr = 0

        self.vc = [None] * vc_size
        self.vc_wr_ptr = 0

        self.main_hits = 0
        self.vc_hits = 0
        self.misses = 0

    # --------------------------------------------------------
    # DRRIP leader sets
    # --------------------------------------------------------

    def leader(self, index):

        if SETS < 16:
            return None

        if index % 16 == 0:
            return "S"

        if index % 16 == 1:
            return "B"

        return None

    def use_brrip(self, index):

        if self.policy == "SRRIP":
            return False

        if self.policy == "BRRIP":
            return True

        if self.policy != "DRRIP":
            return False

        leader = self.leader(index)

        if leader == "S":
            return False

        if leader == "B":
            return True

        return self.psel >= 512

    # --------------------------------------------------------
    # LRU
    # --------------------------------------------------------

    def lru_touch(self, index, way):

        old_rank = self.rank[index][way]

        for w in range(WAYS):

            if w == way:
                self.rank[index][w] = WAYS - 1

            elif self.rank[index][w] > old_rank:
                self.rank[index][w] -= 1

    # --------------------------------------------------------
    # PLRU update
    # --------------------------------------------------------

    def plru_touch(self, index, way):

        t = self.tree[index]

        if WAYS == 1:
            return

        if WAYS == 2:
            t[0] = 1 if way == 0 else 0
            return

        if WAYS != 4:
            raise ValueError(
                "PLRU supports only 1, 2 or 4 ways"
            )

        if way == 0:
            t[0], t[1] = 1, 1

        elif way == 1:
            t[0], t[1] = 1, 0

        elif way == 2:
            t[0], t[2] = 0, 1

        else:
            t[0], t[2] = 0, 0

    # --------------------------------------------------------
    # PLRU victim
    # --------------------------------------------------------

    def plru_victim(self, index):

        t = self.tree[index]

        if WAYS == 1:
            return 0

        if WAYS == 2:
            return 1 if t[0] else 0

        if WAYS == 4:

            if not t[0]:
                return 1 if t[1] else 0

            return 3 if t[2] else 2

        raise ValueError("Unsupported PLRU associativity")

    # --------------------------------------------------------
    # Victim selection
    # --------------------------------------------------------

    def victim(self, index):

        for w in range(WAYS):

            if self.tags[index][w] is None:
                return w

        if self.policy == "LRU":
            return self.rank[index].index(0)

        if self.policy == "PLRU":
            return self.plru_victim(index)

        maximum = max(self.rrpv[index])

        return self.rrpv[index].index(maximum)

    # --------------------------------------------------------
    # Main hit update
    # --------------------------------------------------------

    def main_hit_update(self, index, way):

        if self.policy == "LRU":
            self.lru_touch(index, way)

        elif self.policy == "PLRU":
            self.plru_touch(index, way)

        else:
            self.rrpv[index][way] = 0

    # --------------------------------------------------------
    # DRRIP memory refill
    # --------------------------------------------------------

    def dr_rip_fill(self, index, way):

        maximum = max(self.rrpv[index])

        age_amount = 3 - maximum

        for w in range(WAYS):

            if (
                w != way
                and self.tags[index][w] is not None
            ):

                self.rrpv[index][w] = min(
                    3,
                    self.rrpv[index][w] + age_amount
                )

        use_b = self.use_brrip(index)

        if use_b:

            insertion_value = (
                2 if self.bctr % 32 == 31 else 3
            )

            self.bctr += 1

        else:
            insertion_value = 2

        self.rrpv[index][way] = insertion_value

        leader = self.leader(index)

        if leader == "S":
            self.psel = min(1023, self.psel + 1)

        elif leader == "B":
            self.psel = max(0, self.psel - 1)

    # --------------------------------------------------------
    # Victim cache lookup
    # --------------------------------------------------------

    def vc_lookup(self, line):

        for slot, entry in enumerate(self.vc):

            if entry == line:
                return slot

        return None

    # --------------------------------------------------------
    # Victim cache insertion
    # --------------------------------------------------------

    def vc_insert_evicted(self, line):

        if self.vc_size == 0 or line is None:
            return

        for slot in range(self.vc_size):

            if self.vc[slot] is None:
                self.vc[slot] = line
                return

        self.vc[self.vc_wr_ptr] = line

        self.vc_wr_ptr = (
            self.vc_wr_ptr + 1
        ) % self.vc_size

    # --------------------------------------------------------
    # Access
    # --------------------------------------------------------

    def access(self, line):

        index = line % SETS
        tag = line // SETS

        # Main cache hit
        if tag in self.tags[index]:

            way = self.tags[index].index(tag)

            self.main_hit_update(index, way)

            self.main_hits += 1
            return

        # Victim cache hit
        vc_slot = self.vc_lookup(line)

        if vc_slot is not None:

            way = self.victim(index)

            old_tag = self.tags[index][way]

            if old_tag is None:
                evicted_line = None
            else:
                evicted_line = old_tag * SETS + index

            # Swap
            self.vc[vc_slot] = evicted_line
            self.tags[index][way] = tag

            # Promotion is a re-reference, not a new insertion.
            if self.policy in ("LRU", "PLRU"):
                self.main_hit_update(index, way)
            else:
                self.rrpv[index][way] = 0

            self.vc_hits += 1
            return

        # Memory miss
        way = self.victim(index)

        old_tag = self.tags[index][way]

        if old_tag is None:
            evicted_line = None
        else:
            evicted_line = old_tag * SETS + index

        self.vc_insert_evicted(evicted_line)

        self.tags[index][way] = tag

        if self.policy == "LRU":
            self.lru_touch(index, way)

        elif self.policy == "PLRU":
            self.plru_touch(index, way)

        else:
            self.dr_rip_fill(index, way)

        self.misses += 1

    def run(self, sequence):

        for line in sequence:
            self.access(line)

        return (
            self.main_hits,
            self.vc_hits,
            self.misses
        )


# ============================================================
# Run models
# ============================================================

def run_policy(policy, vc_size):

    model = CacheModel(policy, vc_size)

    return model.run(lines)


# ============================================================
# OPT upper bound
# ============================================================

def opt_fully_associative(capacity):

    if capacity <= 0:
        return 0

    next_use = [10**18] * N
    last_seen = {}

    for i in range(N - 1, -1, -1):

        next_use[i] = last_seen.get(
            lines[i], 10**18
        )

        last_seen[lines[i]] = i

    cache = {}
    hits = 0

    for i, line in enumerate(lines):

        if line in cache:
            hits += 1

        elif len(cache) >= capacity:

            victim_line = max(
                cache,
                key=lambda x: cache[x]
            )

            del cache[victim_line]

        cache[line] = next_use[i]

    return hits


# ============================================================
# Results
# ============================================================

print("\n========== CACHE MODEL RESULTS ==========")

print(
    f"CL={CL}, NW={WAYS}, SETS={SETS}, "
    f"VC={VC_SIZE}, LINE_BYTES={LINE_BYTES}"
)

print(
    f"\n{'Policy':<10}"
    f"{'Main':>10}"
    f"{'VC':>10}"
    f"{'Total':>10}"
    f"{'Rate':>10}"
)

for policy in valid_policies:

    if policy == "PLRU" and WAYS not in (1, 2, 4):
        print(f"{policy:<10} unsupported")
        continue

    main_hits, vc_hits, misses = run_policy(
        policy,
        VC_SIZE
    )

    total = main_hits + vc_hits

    rate = 100.0 * total / N

    print(
        f"{policy:<10}"
        f"{main_hits:>10}"
        f"{vc_hits:>10}"
        f"{total:>10}"
        f"{rate:>9.2f}%"
    )


# ============================================================
# Final comparison
# ============================================================

opt_hits = opt_fully_associative(CL + VC_SIZE)

print(
    f"\nOPT upper bound: {opt_hits} "
    f"({100.0 * opt_hits / N:.2f}%)"
)

model_main, model_vc, model_miss = run_policy(
    SELECTED_POLICY,
    VC_SIZE
)

model_total = model_main + model_vc

print(f"\n========== RTL vs {SELECTED_POLICY} ==========")

print(f"RTL hits   : {rtl_total}")
print(f"Model hits : {model_total}")
print(f"Difference : {rtl_total - model_total:+d}")

print(
    "\nEnsure the model and RTL use identical "
    "CL, NW, VC_SIZE, line size and request trace."
)
