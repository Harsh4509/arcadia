# Pass 0 — Foundation

**Arcadia ALM · Sherlock Audit Engine · commit `753bd57b19617135640f570e980dc09f4d76af66`**

This is the bottom-up pass. You read the small leaf files **first**, in dependency order, so that
when you later trace a user flow top-down (Pass 1) every helper it calls is already in your head.

Everything below was read line by line from the pinned commit. Where I checked something and it
holds, I say so. Where I only *suspect* something, it is in the **Leads** list at the end, marked
as unverified — those are hypotheses for you to test, not findings.

---

## 0. How to use this document

Read it next to the code, one section at a time. For each file:

1. Read my section here.
2. Open the file and read it top to bottom.
3. Write one line in your own `notes/00-primitives.md`: *what it computes, which way it rounds.*
4. Tick it off in the checklist in section 2.

Do **not** skip the examples. The examples are where the rounding direction becomes obvious,
and rounding direction is where the money is in this codebase.

---

## 1. The ten-second mental model

One `ALMCore` sits on top of one Metadex concentrated-liquidity pool.

- It holds up to **14 tick ranges** plus an idle **buffer** of loose tokens.
- Each range is actually **two NFT positions**: an *unstaked* one (earns swap fees) and a *staked*
  one (sits in the gauge and earns AERO emissions).
- It issues an ERC-20 share token called **aLP**. `mint` takes both tokens, `burn` returns both.
- A **keeper** reshapes the ranges by submitting a small program (`execute`) — a list of opcodes.
- Four **vaults** sit in front for people who only have one token: two *sync* (swap-and-mint now)
  and two *async* (queue a request, a keeper settles it later).

Pass 0 is about the pieces that *all* of that is built from.

---

## 2. Reading order and checklist

Read strictly top to bottom. Each row only depends on rows above it.

### Part A — The alphabet (≈ 900 lines)

| # | File | Lines | Done |
|---|---|---|---|
| A1 | `src/core/abstracts/storage/Storage.sol` | 42 | ☐ |
| A2 | `src/core/abstracts/storage/Immutables.sol` | 80 | ☐ |
| A3 | `src/shared/abstracts/mixins/ReentrancyLock.sol` | 66 | ☐ |
| A4 | `src/core/types/State.sol` + 4 small type files | 174 + 65 | ☐ |
| A5 | `src/core/types/TokenDelta.sol` | 125 | ☐ |
| A6 | `src/shared/libraries/math/CLMath.sol` | 272 | ☐ |
| A7 | `src/vaults/libraries/math/QuadraticMath.sol` | 52 | ☐ |
| A8 | `src/core/libraries/Sentinels.sol` + `CommandLogic.sol` | 20 + 65 | ☐ |

### Part B — The vendored four (242 lines) ← do this on day one

| # | File | Lines | Done |
|---|---|---|---|
| B1 | `src/shared/libraries/vendored/MetadexOracle.sol` | 38 | ☐ |
| B2 | `src/shared/libraries/vendored/MetadexPositionValue.sol` | 46 | ☐ |
| B3 | `src/shared/libraries/vendored/MetadexTickBitmap.sol` | 62 | ☐ |
| B4 | `src/shared/libraries/vendored/MetadexSwapMath.sol` | 96 | ☐ |

### Part C — The core's state libraries (≈ 2 600 lines)

| # | File | Lines | Done |
|---|---|---|---|
| C1 | `src/core/libraries/state/ConfigLib.sol` | 87 | ☐ |
| C2 | `src/core/libraries/state/PoolTokensLib.sol` | 156 | ☐ |
| C3 | `src/core/libraries/state/ShareLib.sol` | 123 | ☐ |
| C4 | `src/shared/libraries/logic/PoolLogic.sol` + `PositionManagerLogic.sol` | 75 + 112 | ☐ |
| C5 | `src/core/libraries/state/RangesLib.sol` | 661 | ☐ |
| C6 | `src/core/libraries/state/QueueLib.sol` | 604 | ☐ |
| C7 | `src/core/libraries/logic/EmissionsLogic.sol` | 160 | ☐ |
| C8 | `src/core/libraries/state/RewardsLib.sol` | 361 | ☐ |
| C9 | `src/core/libraries/logic/CalldataLogic.sol` | 350 | ☐ |
| C10 | `src/core/types/PlanCache.sol` | 423 | ☐ |

### Part D — The vault's math (≈ 2 100 lines)

| # | File | Lines | Done |
|---|---|---|---|
| D1 | `src/vaults/types/Snapshot.sol` (+ `PricedRange.sol`) | 388 + 15 | ☐ |
| D2 | `src/vaults/libraries/math/EquivalentPositionMath.sol` (+ type) | 125 + 21 | ☐ |
| D3 | `src/vaults/types/SwapState.sol` | 235 | ☐ |
| D4 | `src/vaults/libraries/math/MintOptimizationMath.sol` | 230 | ☐ |
| D5 | `src/vaults/libraries/math/DepositOptimizationMath.sol` | 488 | ☐ |
| D6 | `src/vaults/libraries/math/RedeemOptimizationMath.sol` | 131 | ☐ |
| D7 | `src/vaults/libraries/math/WithdrawOptimizationMath.sol` | 473 | ☐ |

Then: **Part E** rounding table · **Part F** what I already verified · **Part G** leads · **Part H** self-test.

---

# PART A — The alphabet

## A1. `Storage.sol` — where the state actually lives

### What it does

Normally in Solidity you write `uint256 totalCap;` and the compiler puts it at slot 0, the next
variable at slot 1, and so on. **This file declares no variables at all.** Instead it *points* one
giant struct at a hashed slot number using assembly.

```solidity
bytes32 constant STATE_SLOT     = 0xf337e37bd3891692fb524a02eedc850180dbc2332ff323439b5031c95d778600;
bytes32 constant TRANSIENT_SLOT = 0x96a7a9e9ef75b4cd48bf368d0d27d3096ea7692bbe6eb8f0f0dcd3bdff116000;

function _state() internal pure returns (State storage state) {
    assembly ("memory-safe") { state.slot := STATE_SLOT }
}
function _checkpointed() internal pure returns (LibTransient.TBool storage) {
    return LibTransient.tBool(TRANSIENT_SLOT);
}
```

This pattern is called **ERC-7201 namespaced storage**.

### Simple analogy

Normal Solidity is a filing cabinet whose drawers are numbered 0, 1, 2 in the order you declared
them. ERC-7201 says: *"all my files live in the drawer whose number is `hash("arcadia.alm.core")`"*
— a number so enormous nothing else will ever pick it by accident.

### Why they did it — three reasons

**1. Delegatecall safety (the real reason).**
`ALMCore`, `ALMKeeperExtension` and `ALMAdminExtension` all inherit `Storage` through
`BaseCore.sol:17`. The two extensions run **inside the core's storage** via `delegatecall`.
With normal slot-0 layout, all three contracts would need an identical inheritance order or an
extension's write would land on a different variable than intended — the classic proxy storage
collision bug. Pinning to a hash makes the layout independent of inheritance, so that whole class
of bug is gone by construction.

**2. Slot 0 is deliberately left empty.** Because nothing lives at low slots, a standalone
extension's own storage is all zeros. The test suite asserts exactly that
(`test/fuzz/ALMCore/Constructor.fuzz.t.sol:385-387` checks `vm.load(keeperExtension, STATE_SLOT + 3) == 0`).

**3. Cheap external reads.** `ALMCore` inherits Uniswap V4's `Extsload`/`Exttload`
(`ALMCore.sol:32`), so anyone can read raw slots. `ALMCoreViewLogic` rebuilds every view by hand
as `STATE_SLOT + offset` — 39 call sites. One raw read instead of N getters.

### The transient flag

`_checkpointed()` is **EIP-1153 transient storage**, not real storage. Used in exactly three places:

```
ALMKeeperExtension.sol:119   _checkpointed().set(false)    // start of execute()
ALMKeeperExtension.sol:163   if (!_checkpointed().get())   // first checkpoint this plan?
ALMKeeperExtension.sol:164       _checkpointed().set(true)
```

Purpose: the emissions checkpoint must run **exactly once per plan**, not once per opcode.
Transient storage clears itself at the end of the transaction, so there is no cleanup code and no
stale flag leaking into the next transaction.

### Used where

`BaseCore` → `ALMCore`, `ALMKeeperExtension`, `ALMAdminExtension` (39 uses of `_state()`),
and `ALMCoreViewLogic` imports `STATE_SLOT` to rebuild slots for external reads.

### Audit notes

- **The trailing zero byte is load-bearing.** Both constants end in `0x00` (`…778600`, `…116000`)
  because ERC-7201 masks the last byte off. `ALMCoreViewLogic.sol:772-777` relies on it:

  ```solidity
  // Unchecked: STATE_SLOT ends in a zero byte and every offset is below 256.
  unchecked { slot = bytes32(uint256(STATE_SLOT) + offset); }
  ```

  Largest offset actually used is 20, plus queue offsets up to 7 → 27. No carry possible.
  **I checked this. It holds.** One `unchecked` bound closed.

- **The constants are hardcoded, and the tests cannot catch a wrong value.** Both
  `Constructor.fuzz.t.sol` and `Extsload.fuzz.t.sol` *import* `STATE_SLOT`, so a wrong constant is
  self-consistent and invisible to the whole suite. If you want to close it, compute
  `keccak256(abi.encode(uint256(keccak256("arcadia.alm.core")) - 1)) & ~0xff` by hand. Realistically
  Info severity even if wrong — it is a naming convention, not a safety property — unless the two
  namespaces collided, which visually they do not.

- **aLP balances are NOT in the `State` struct.** Solady's `ERC20` keeps them in its own hashed
  slots and `ERC20Share.sol` does not override storage. `share.shareAccounts` (offset 13) holds
  `claimableShares`/`pendingShares` — async request accounting, a different thing entirely.
  Two parallel accounting systems in two slot namespaces. Do not conflate them.

---

## A2. `Immutables.sol` — the 17 addresses baked into the bytecode

### What it does

Declares 17 `internal immutable` values and fills them all in the constructor from **one call**:

```solidity
constructor() {
    CoreParameters memory params = IBaseFactory(msg.sender).parameters();
    FACTORY = msg.sender;
    POSITION_MANAGER = params.positionManager;
    // … 15 more
}
```

The 17: `TICK_SPACING`, `ADMIN_EXTENSION`, `ASYNC_VAULT0`, `ASYNC_VAULT1`, `FACTORY`, `GAUGE`,
`GAUGE_FACTORY`, `KEEPER_EXTENSION`, `LEAF_VOTER`, `POOL`, `POSITION_MANAGER`, `REWARD_TOKEN`,
`ROUTER_TRAMPOLINE`, `SYNC_VAULT0`, `SYNC_VAULT1`, `TOKEN0`, `TOKEN1`.

### The key fact

`msg.sender` in the constructor **is the factory**, and the factory is asked for the parameters
rather than being passed them. This is the "transient parameters" deployment pattern: the factory
stores a `CoreParameters` struct, deploys with CREATE2, the constructor reads it back.

### Why immutables and not storage

Immutables are written into the contract's bytecode at deploy time. Reading one costs ~3 gas
instead of ~2100 for a cold storage read, and **it cannot be changed afterwards**. Combined with
CREATE2 and no proxy, the protocol has **no upgrade authority at all** — a broken core can only be
paused and exited in kind.

### The catch, and why `CalldataLogic` exists

An immutable belongs to **the contract that was deployed**. When the core `delegatecall`s into
`ALMKeeperExtension`, the extension's *own* immutables are used — and the extension is shared
across every pool, so it does not know which pool it is running for.

Solution: the core **appends nine words to the calldata** (an ERC-3448-style trick), and the
extension reads them off the **end** of calldata via `CalldataLogic.decodeCoreImmutables()`.
Those nine are exactly the `CoreImmutables` struct: `tickSpacing, pool, token0, token1, gauge,
asyncVault0, asyncVault1, syncVault0, syncVault1`.

So an extension has **two** sources of truth:
- its own immutables (chain-wide things: position manager, gauge factory, leaf voter, reward token),
- the appended words (pool-specific things).

Keep that split in your head. It is the authorisation surface for the whole extension system.

### Used where

`BaseCore` → core + both extensions. `CoreParameters.sol` (28 lines) and `Vaults.sol` (15 lines)
are the structs the factory fills.

### Audit notes

- The constructor trusts `msg.sender` completely. `ALMCore.sol:56` adds one check:
  `if (KEEPER_EXTENSION.code.length == 0 || ADMIN_EXTENSION.code.length == 0) revert InvalidExtension();`
  Nothing verifies that `POOL` really is a Metadex pool, or that `TOKEN0`/`TOKEN1` match the pool's
  tokens — that validation lives in the factory (`ALMFactory.createCore`), which is Trace 1.
- Nine appended words = `0x120` bytes. `decodeCoreImmutables` copies exactly `0x120`. Verified
  consistent.

---

## A3. `ReentrancyLock.sol` — the lock, and what it does not cover

### What it does

A transient-storage reentrancy guard on **Solady's** guard slot:

```solidity
uint256 constant GUARD_SLOT = 0x8000000000ab143c06;

modifier nonReentrant() { _lock(); _; _unlock(); }

function _lock() internal { _requireUnlocked(); assembly { tstore(GUARD_SLOT, address()) } }
function _unlock() internal { assembly { tstore(GUARD_SLOT, 0) } }
```

Three details worth noticing:

1. It stores `address()` (the contract's own address), not `1`. Solady's convention — the slot also
   encodes the error selector `0xab143c06` for a cheap revert.
2. It is **transient** (EIP-1153), so it clears automatically at the end of the transaction. There
   is no "lock stuck forever" failure mode.
3. `_requireUnlocked()` is exposed separately, so code can *check* the lock without taking it.

### Simple example

```
tx: attacker calls core.mint()
  → _lock()            GUARD_SLOT = core address
  → safeTransferFrom(attacker's token)   ← token is malicious, calls back into core.burn()
      → burn() has nonReentrant → _lock() → _requireUnlocked() sees non-zero → revert
```

### Used where

Inherited via `BaseCore`. On the core: `mint`, `burn`, `trustedBurn`, all four request functions,
all four claim/cancel functions, `execute`, `checkpoint`, `skim`, `claimEmissions`. On the vaults,
`BaseVault` has its own equivalent.

### Audit notes — this is the important bit

**Known issue S13 says the aLP's `transfer`, `approve` and `setOperator` are NOT under the lock.**
That is a disclosed design decision, so a plain re-entrancy report there is dead. But read the
sentence precisely: an acceptance covers *the behaviour and harm it describes*. `transfer` fires a
`RewardCheckpoint`, which touches `rewards`. If you can find harm **beyond** what S13 describes by
re-entering through a transfer during a plan, that is a different finding.

For Pass 3's reentrancy sweep, write down now: **which functions take the lock, and which external
calls happen while it is held.** The honest list of "external call while locked" is long here —
position manager, gauge, pool, router trampoline, both pool tokens, the reward token.

---

## A4. The type structs — the shape of all state

### `State` — the one struct at `STATE_SLOT`

```solidity
struct State {
    Config config;        // B+0  .. B+3
    Rewards rewards;      // B+4  .. B+8
    Share share;          // B+9  .. B+15
    PoolTokens poolTokens;// B+16 .. B+18
    Range[] ranges;       // B+19,  elements at keccak256(B+19) + 2i
    mapping(address vault => VaultQueue) vaultQueues; // B+20
}
```

`B` = `STATE_SLOT`. The slot comments in the file are a gift — they are exactly what
`ALMCoreViewLogic` hardcodes, so they are a cross-check you can run mechanically.

**`Config`** — three packed words plus an address:

| Word | Fields |
|---|---|
| B+0 | `uint128 totalCap`, `uint128 perUserCap` |
| B+1 | `bool paused`, `uint16 protocolEmissionFeeBps`, `uint16 protocolSwapFeeBps`, `uint32 twapWindow`, `uint64 maxSpotFromTwap`, `uint64 maxSpotFromTrusted`, `uint48 windowEnd`, `uint8 rewardPoolToken` |
| B+2 | `uint64 maxTwapFromTrusted`, `uint16 maxShortfallBps`, `uint16 maxSwapCostBps`, `uint32 minPlanInterval`, `uint8 rangeCap`, `uint32 lastPlanAt`, `bool arbBlockNumber` |
| B+3 | `address feeRecipient` |

Word B+1 is **exactly 256 bits full** (8+16+16+32+64+64+48+8). That is not an accident, and it
means any new field would force a storage change.

`rewardPoolToken` is a 3-state enum packed as a `uint8`: **1** = the reward token *is* token0,
**2** = it is token1, **0** = it is neither. You will meet this in `PoolTokensLib.skim`,
`checkSolvency` and `RewardsLib.getRewardTotals`, and it is the source of a lot of branching.

**`Rewards`**:
```solidity
uint128 rewardPerShare;              // B+4   intentionally wraps
uint128 highWater;                   //       never decreases
uint128 claimedCumulative;           // B+5
uint128 lastRewardBalance;           //       the core's measured reward-token balance
uint128 protocolFees;                // B+6   in reward token
uint128 protocolRewardPerSharePaid;  //
uint128 preCredited;                 // B+7   emissions credited ahead of the penalty window
mapping(address => RewardAccount);   // B+8   {rewardPerSharePaid, rewardOwed}
```

**`Share`**:
```solidity
ExchangeRate lastExchangeRate;  // B+9..B+10  {uint256 supplyPerValueX128; uint160 sqrtPriceX96;}
string name;                    // B+11
string symbol;                  // B+12
mapping(address => ShareAccount);              // B+13  {uint128 claimableShares; uint128 pendingShares;}
mapping(address => mapping(address => bool));  // B+14  isOperator
mapping(address => bool);                      // B+15  isExempt
```

**`PoolTokens`** — the three ledgers, each a packed `TokenAmounts`:
```solidity
TokenAmounts buffer;       // B+16   loose tokens the core owns
TokenAmounts protocolFees; // B+17   owed to the fee recipient
TokenAmounts escrowed;     // B+18   held for pending/claimable requests
```

**`VaultQueue` / `Queue` / `Record` / `Epoch` / `Claimable`** — the async machinery:
```solidity
struct VaultQueue { Queue deposits; /*+0..+3*/ Queue redeems; /*+4..+7*/ }
struct Queue {
    uint32 pendingEpoch; uint32 lastClearedEpoch;          // +0
    mapping(uint32 => Epoch) epochs;                       // +1
    mapping(address => Record) records;                    // +2
    mapping(address => Claimable) claimable;               // +3
}
struct Epoch     { uint128 amountIn; uint128 amountOut; }
struct Record    { uint32 epoch; uint128 amountIn; uint96 pendingShares; }   // exactly 256 bits
struct Claimable { uint128 amountIn; uint128 amountOut; }
```

**Why `pendingShares` is `uint96` and not `uint128`:** `Record` is 32 + 128 + 96 = exactly 256 bits.
They needed it to fit one word. The narrowing cast that results is known issues **S50 / S54** — do
not report the cast itself. (Look instead for a *consequence* those statements do not describe.)

### `Range` — two words per range

```solidity
struct Range {
    int24   tickLower;        // word 1, bits 0-23
    int24   tickUpper;        // word 1, bits 24-47
    uint80  unstakedTokenId;  // word 1, bits 48-127
    uint128 stakedLiquidity;  // word 1, bits 128-255   ← exactly full
    uint80  stakedTokenId;    // word 2, bits 0-79
    uint48  stakedBlock;      // word 2, bits 80-127
}
```

**The single most important thing about `Range`:** it stores `stakedLiquidity` but **not**
unstaked liquidity. Every reader asks the position manager live:
`positionManager.positions(unstakedTokenId).liquidity`. That is a deliberate design choice (anyone
may `increaseLiquidity` on the core's non-gauge NFTs and donate liquidity), and it means the
unstaked side's value can change **without any core transaction**.

`stakedTokenId == 0` is the sentinel for "no staked side". Token id 0 is therefore assumed never to
be a real position.

### The small ones

```solidity
struct TokenAmounts  { uint128 amount0; uint128 amount1; }               // TokenDelta.sol
struct RangeAmounts  { uint256 amount0; uint256 amount1; }               // mint budget per range
struct Vaults        { address syncVault0, syncVault1, asyncVault0, asyncVault1; }
struct CoreImmutables{ int24 tickSpacing; address pool, token0, token1, gauge,
                       asyncVault0, asyncVault1, syncVault0, syncVault1; }  // the 9 appended words
```

### Audit notes

- **The eleven invariants in context doc §2.9 are all statements about this struct.** When you get
  to Pass 2, you will be asking "can I reach a `State` where X is false". Knowing the layout cold
  is what makes that possible.
- **I verified all 20 bit-shift constants** in `ALMCoreViewLogic` against this packing. They all
  match. See **Part F** for the full table — that closes an avenue so you do not spend a day there.

---

## A5. `TokenDelta.sol` — two signed numbers in one word

This is the single most important primitive in the core. **Read it twice.**

### What it is

`TokenDelta` is Uniswap v4's `BalanceDelta`, renamed. It is one 256-bit word holding **two signed
128-bit numbers**:

```
 bit 255                      bit 128 | bit 127                        bit 0
+-------------------------------------+-------------------------------------+
|        int128 amount0               |        int128 amount1               |
+-------------------------------------+-------------------------------------+
```

Sign convention throughout the core: **positive means the core gained, negative means the core paid.**

### Simple example

The core removes liquidity and receives 100 token0 and 50 token1:

```
delta = fromAmounts(100, 50) = (100 << 128) | 50
```

The core then mints liquidity costing 30 token0 and 20 token1. `PositionManagerLogic` returns the
**negated** delta, because tokens left:

```
delta = fromAmounts(30, 20).neg()   ->  (-30, -20)
```

Add them:

```
add((100, 50), (-30, -20)) = (70, 30)
```

The core netted +70 token0 and +30 token1 over those two operations. That is the whole idea: a
keeper plan accumulates one running `TokenDelta` instead of tracking two separate signed numbers.

### The six functions

| Function | What it does | Overflow behaviour |
|---|---|---|
| `neg(d)` | negates both halves | reverts `SafeCastLib.Overflow` if a half was `int128.min` |
| `add(a,b)` | adds both halves | reverts `SafeCastLib.Overflow` on either half |
| `single(isToken0, amount)` | puts one signed amount in one half, zero in the other | none (caller passes `int128`) |
| `fromAmounts(a0, a1)` | packs two **non-negative** magnitudes | reverts if either is at least 2^127 |
| `toAmounts(d)` | reads both halves back as `uint256` | **none — see below** |
| `applyDelta(storage, d)` | adds a delta into a stored `TokenAmounts` | reverts Panic `0x11` |

### The crossover you must not miss

`TokenAmounts` is a normal Solidity struct:

```solidity
struct TokenAmounts { uint128 amount0; uint128 amount1; }
```

Solidity packs the **first** field in the **low** bits. So in *storage*:

```
 bit 255                      bit 128 | bit 127                        bit 0
+-------------------------------------+-------------------------------------+
|      uint128 amount1  (HIGH)        |      uint128 amount0  (LOW)         |
+-------------------------------------+-------------------------------------+
```

That is **the opposite way round** from `TokenDelta`, where amount0 is in the high bits.
`applyDelta` handles the crossover explicitly:

```solidity
let amount0 := add(and(packed, 0xffff...ffff), sar(128, delta))        // storage LOW  += delta HIGH
let amount1 := add(shr(128, packed), signextend(15, delta))           // storage HIGH += delta LOW
sstore(amounts.slot, or(amount0, shl(128, amount1)))
```

**I checked this. It is correct.** But it is exactly the kind of place where a future edit, or a new
caller, gets it backwards — and both halves are plausible token amounts, so a swap would not look
obviously wrong in a test using symmetric numbers. If you write any PoC touching these, use
**asymmetric** amounts (100 and 7, never 100 and 100).

### The clever overflow check in `applyDelta`

```solidity
if or(shr(128, amount0), shr(128, amount1)) { revert Panic(0x11) }
```

One check catches **both** directions:

- too big: bit 128 or above is set, caught.
- below zero: two's complement wraps to a huge number, high bits set, caught.

So the three ledgers (`buffer`, `protocolFees`, `escrowed`) can never go negative or exceed
`uint128`. That is the enforcement point for **invariant 1 (solvency)** at the write level.

Note also: `applyDelta` does nothing at all when `delta == 0` (`if delta { ... }`), so a zero delta
costs no SSTORE. Correct, and a gas optimisation you should not mistake for a missing write.

### Used where

`ALMCore`, `ALMAdminExtension`, `PositionManagerLogic`, `PoolTokensLib`, `QueueLib`, `RangesLib`,
`PlanCache`. Essentially every value-moving line in the core.

### Audit notes / leads

- **`toAmounts` returns `uint256` from signed reads.** `sar(128, d)` and `signextend(15, d)` are
  *signed* reads, but the return type is `uint256`. Pass it a negative half and you get a number
  near 2^256. The docstring says "the delta, positive in both components" — that is a **caller
  obligation, not an enforced check**. Pass 3 task: list every `toAmounts` caller and prove
  non-negativity at each. Callers I saw: `PoolTokensLib.creditCollected` (on `fees`, which comes
  from `collect` and is non-negative) and `PlanCache`. Worth closing properly.
- `neg()` on `int128.min` reverts rather than silently returning `int128.min`. Verified.
- `single(bool isToken0, int128 amount)` does `shl(mul(128, isToken0), ...)` and so relies on `bool`
  being exactly 1 in the EVM. True for Solidity-produced bools, and `CalldataLogic.readBool`
  normalises with `iszero(iszero(...))`, so the calldata path is safe too. Verified.

---

## A6. `CLMath.sol` — every value calculation bottoms out here

### What it does

Concentrated-liquidity maths: convert between tokens at a price, move a price, build a band around
a price, and work out what a position holds.

### Prices, in one paragraph

In a Uniswap-V3-style pool the price is stored as `sqrtPriceX96` — the **square root** of
(token1 per token0), times 2^96. Two consequences to internalise:

1. To get the price you square it. To go back you take a square root.
2. **A band on the sqrt price is roughly half as wide as the same band on the price.** A 1% band on
   `sqrtPriceX96` is about a 2% band on the price. Every deviation parameter in this protocol
   (`maxSpotFromTwap`, `maxSpotFromTrusted`, `maxTwapFromTrusted`) is a band on the **sqrt** price.
   Production values are 1e15 to 1e16, i.e. 0.1% to 1% on sqrt price, about 0.2% to 2% on price.

### `convert(sqrtPriceX96, zeroForOne, amount, roundUp)`

Converts an amount between the tokens at an exact price. **No slippage, no fees** — this is a
valuation function, not a swap.

**Example.** Price is 2000 token1 per token0, so `sqrtPriceX96 = sqrt(2000) * 2^96`.

```
convert(sqrtPrice, zeroForOne = true,  amount = 3,    roundDown) = 6000   // 3 token0 is worth 6000 token1
convert(sqrtPrice, zeroForOne = false, amount = 6000, roundDown) = 3      // and back
```

**The two branches.** Squaring a `uint160` can overflow `uint256`, so there is a split:

```solidity
if (sqrtPriceX96 > type(uint128).max) {       // big price: never form the full square
    ...fullMulDiv(sqrtPriceX96, 1 << 64)... then ...1 << 128...
} else {
    unchecked { uint256 priceX192 = sqrtPriceX96 * sqrtPriceX96; }
    ...fullMulDiv(priceX192, 1 << 192)...
}
```

**I checked the bound.** `(2^128 - 1)^2 = 2^256 - 2^129 + 1`, which fits `uint256`. The `unchecked`
is justified. One more stated bound closed.

**`roundUp` is a parameter, and who passes what is the whole game.** Mint paths pass `true` (the
payer pays more); valuation and burn paths pass `false` (the receiver gets less). Record this in
your notes.

### `getBand(sqrtPriceX96, deviation)`

```solidity
scale = 1e18 + deviation;
sqrtPriceLowerX96 = sqrtPriceX96.fullMulDivUp(1e18, scale);   // rounds UP   -> tighter
sqrtPriceUpperX96 = sqrtPriceX96.fullMulDiv(scale, 1e18);     // rounds DOWN -> tighter
```

**Example.** `sqrtPrice = 1000`, `deviation = 1e16` (1%), so `scale = 1.01e18`.

```
lower = ceil(1000 * 1e18 / 1.01e18) = ceil(990.099...) = 991
upper = floor(1000 * 1.01)          = 1010
```

Both bounds round **inward**, so the accepted band is strictly *inside* the nominal one. That makes
the deviation check slightly **stricter** than advertised — the safe direction. The asymmetry
(-9 / +10) is correct for a ratio band, not a bug.

### The position functions — the rounding pair

There are **two versions of the same calculation**, and the difference is the fairness mechanism:

| Function | Rounds | Used by |
|---|---|---|
| `getAmountsForLiquidityRoundingUp` | **UP** | mint: "the least amount that buys at least this liquidity" |
| `getAmountsForLiquidity` | **DOWN** | burn / valuation: "what this liquidity is worth, conservatively" |

Each splits into three cases by where the price sits relative to the range:

```
price <= lower         : all token0   (range entirely above the market)
lower < price < upper  : both tokens  (range active)
price >= upper         : all token1   (range entirely below the market)
```

**`getAmount0ForLiquidityRoundingUp` has a subtlety worth your time:**

```solidity
uint256 intermediate = uint256(sqrtPriceAX96).fullMulDivN(sqrtPriceBX96, 96);  // floor(a*b / 2^96)
if (intermediate == 0) revert NoLiquidityForToken0();
amount0 = uint256(liquidity).fullMulDivUp(sqrtPriceBX96 - sqrtPriceAX96, intermediate);
```

The comment calls `J = floor(a*b/2^96)` **"the position manager's own divisor"**. This function is
deliberately replicating the position manager's floor, then rounding the outer division up. If the
real position manager ever used a different divisor, every mint would ask for the wrong amount.
That is a cross-contract assumption — write it down for Pass 3's "external assumptions" sweep.

`NoLiquidityForToken0` fires when the product underflows to zero, only at extremely low prices.

### `getMintAmounts(...)` — the function that decides what a minter pays

```solidity
uint128 liquidity = SafeCastLib.toUint128(rangeLiquidity.fullMulDivUp(shares, supply));  // UP
(amount0, amount1) = getAmountsForLiquidityRoundingUp(..., liquidity);                   // UP
```

**Rounded up twice.** First the liquidity share, then the token amounts for it. Both go against the
minter and in favour of existing holders. That is **invariant 4** (in-kind fairness) in two lines.

**Example.** Supply is 1000 aLP, a range holds 7 liquidity, you mint 1 aLP.
`7 * 1 / 1000 = 0.007`, rounds up to **1** liquidity unit. You pay for a whole unit and receive
1/1000th of the shares. Across 14 ranges that is up to 14 units of overpayment per mint — tiny in
absolute terms, but exactly the kind of thing judging rule **3.4.4** turns into a real finding if
you can **replay** it profitably in the other direction.

### `getNextSqrtPrice(zeroForOne, sqrtPriceOld, sqrtPriceBound, sqrtPriceDelta)`

Moves the sqrt price of the input token by a **relative** amount `delta` (X192), stopping at a
bound. Used only by the vault's quadratic solver — you meet it again in D5.

```
zeroForOne : s_new = s_old * (1 - d)
oneForZero : s_new = s_old / (1 - d)
```

Both branches check "does d already reach the bound?" first and clamp if so.

### Used where

11 files: `ALMAdminExtension`, `ALMKeeperExtension`, `ALMCoreViewLogic`, `ConfigLib`, `RangesLib`,
`PlanCache`, `ALMCoreView`, `BaseVaultAccounting`, `DepositOptimizationMath`,
`WithdrawOptimizationMath`, `Snapshot`. If you deeply learn one maths file, learn this one.

### Audit notes

- Build the **rounding table** for this file first (Part E has mine). Every row where the
  beneficiary is the *caller* rather than the *remaining holders* is a candidate finding.
- `getAmountsForLiquidity` delegates to `SqrtPriceMath.getAmount0Delta` / `getAmount1Delta` from
  `@uniswap/v4-core` with `roundUp = false`. Those are **out of scope** (not vendored into `src/`),
  so a bug *inside* them is not your finding — but a wrong `roundUp` argument *is*.

---

## A7. `QuadraticMath.sol` — 52 lines, two known issues already in them

### What it does

Solves `a*x^2 - b*x + c = 0` for the **smallest** root, in X192 fixed point.

```solidity
function getRoot(int256 a, int256 b, int256 c) internal pure returns (uint256 x)
```

Three exits:

```solidity
if (c <= 0) return 0;                       // nothing to solve
if (c >= b || 4ac >= b^2) return 1 << 192;  // no real root below one -> return exactly 1.0
// ...otherwise compute...
```

### Why it is written so strangely

The textbook formula is `x = (b - sqrt(b^2 - 4ac)) / 2a`. When `c` is small the two terms in the
numerator are **nearly equal**, and subtracting nearly-equal numbers destroys precision. So they
use the algebraically identical but numerically stable form:

```
x = 2c / (b + sqrt(b^2 - 4ac))
```

Adding instead of subtracting. Then a second trick: never form `b^2` at full width. Work relative
to `b^2`:

```
w = 4ac / b^2                       (the discriminant, relative)
sqrt(b^2 - 4ac) = b * sqrt(1 - w)
x = 2 * (c/b) / (1 + sqrt(1 - w))
```

Only `c/b` and `w` are ever computed, both small. That is the whole file.

### Simple sanity example

Take `a = 0`, a degenerate linear equation `-b*x + c = 0`, so `x = c/b`.

```
x = 2c / (b + sqrt(b^2 - 0)) = 2c / (b + b) = c/b    correct
```

The stable form handles the degenerate case without a special branch.

### The rounding direction, and why it matters

```solidity
uint256 discriminantRoot = radicand.sqrt();
if (discriminantRoot * discriminantRoot < radicand) ++discriminantRoot;   // round UP
```

Since `x = 2*ratio / (1 + sqrt(...))`, a **larger** denominator gives a **smaller** `x`. So
rounding the square root **up** rounds the answer **down**. The comment says exactly that:
*"rounded up so the root never exceeds the exact one."* Consistent. Verified.

### Used where

Only two callers, both in the sync vault: `DepositOptimizationMath.getSqrtPrice` and
`WithdrawOptimizationMath.getSqrtPrice`. Both use it to find the price at which the vault's balances
match the core's composition.

### Audit notes — this is a priority target

- **Two known issues already live in this file (S85, S86).** That is the team telling you they are
  not fully confident here. Read `docs/proofs/QuadraticMath/getRoot.derivation.md` (5 statements)
  side by side with the code.
- The whole computation is one `unchecked` block with the stated bound *"c is below b and 4ac below
  b^2, so every term is at most 2^254."* That is a **falsifiable claim on in-scope code with no
  decisive protection** — a Pass 4 target. The guards above (`c >= b`, `4ac >= b^2`) are what
  enforce the bound, so the question becomes: are those guards exactly right **at the boundary**
  (`c == b`, `4ac == b^2`), and is `a` really always non-negative as the docstring requires?
- `uint256(a)`, `uint256(b)`, `uint256(c)` casts happen on values whose signs the function only
  partly checks. `c <= 0` is handled. `b` is only constrained via `c >= b`. The docstring says `a`
  is "nonnegative" — enforced by whom? Trace both callers and find out.
  **This is a lead, not a finding. I have proven nothing here.**

---

## A8. `Sentinels.sol` and `CommandLogic.sol` — the keeper's vocabulary

Two tiny files you need before Pass 1's Trace 4.

### `Sentinels.sol` (20 lines)

Four magic values a keeper can put in a payload instead of a literal number:

```solidity
uint256 constant OPEN_BALANCE    = 1 << 255;          // "use whatever the buffer holds"
uint256 constant TO_TARGET_RATIO = 1 << 254;          // "swap just enough to reach the target ratio"
uint128 constant RANGE_LIQUIDITY = type(uint128).max; // "all of this range's liquidity"
uint96  constant OPENED          = type(uint96).max;  // "the range this plan just opened"
```

Resolved in `ALMKeeperExtension._amount` (L840), `_amountIn` (L865), `_amountInToRatio` (L883) and
`_rangeAt` (L925).

Why they exist: a keeper computes its plan off-chain against a predicted state, but the real state
at execution time differs by a few wei. Sentinels let a plan say "all of it" instead of a number
that would be stale.

**Audit angle:** a sentinel is a value that means something other than itself. Ask: can a *real*
amount ever equal a sentinel? `OPEN_BALANCE` is 2^255, far above any token balance.
`RANGE_LIQUIDITY` is `uint128.max` — could a range genuinely hold exactly `uint128.max` liquidity?
`OPENED` is `uint96.max` used as a range index and `rangeCap` is at most 14, so no collision there.

### `CommandLogic.sol` (65 lines)

The 15 opcodes, grouped by high nibble:

```
nibble 0 - requests   0x00 CLEAR_REQUESTS       0x01 CLEAR_ALL_REQUESTS
                      0x02 CANCEL_REQUESTS      0x03 SETTLE_REQUESTS
nibble 1 - teardown   0x10 CLOSE_RANGE          0x11 DECREASE_LIQUIDITY
                      0x12 COLLECT              0x13 UNSTAKE
                      0x14 EMERGENCY_UNSTAKE
nibble 2 - swaps      0x20 SWAP_VIA_POOL        0x21 SWAP_VIA_ROUTER
nibble 3 - buildup    0x30 OPEN_RANGE           0x31 INCREASE_LIQUIDITY
                      0x32 STAKE                0x33 INCREASE_STAKED_LIQUIDITY
```

Plus a bitmask:

```solidity
function pausable(uint256 command) internal pure returns (bool) {
    return ((PAUSABLE >> command) & 1) == 1;
}
```

`PAUSABLE` covers exactly the six "add risk" opcodes: `OPEN_RANGE`, `INCREASE_LIQUIDITY`, `STAKE`,
`INCREASE_STAKED_LIQUIDITY`, `SWAP_VIA_POOL`, `SWAP_VIA_ROUTER`. When paused a keeper may still
tear down and settle, but may not build up or swap. That is the "exit in kind" design.

**Two ordering rules are enforced, and they matter:**

1. In `execute`'s loop:
   `if (command <= CANCEL_REQUESTS && previous > CANCEL_REQUESTS) revert InvalidOrder()`
   — request clearing (0x00 to 0x02) must come **before** anything else.
2. In `_dispatch` (L199) the buildup branch re-checks `cache.hasUnsettledEpochs()` and reverts
   `InvalidOrder` — you may not build up while cleared epochs are still unsettled.

Pass 2's "plans" invariant lives in those two lines. Write them down.

### Used where

Both only by `ALMKeeperExtension`.

---

# PART B — The vendored four (242 lines)

## Why this is the highest-value 242 lines in the engagement

Four files are copied ("vendored") from other projects into `src/shared/libraries/vendored/`.
Three facts make them your best early use of time:

1. **`context/scope.json` lists all four as in-scope files.** And statement **S1** in the engagement
   doc is classified `scope: decisive` — *"a defect in these ports is in scope."*
2. **The repo's own `docs/audit-doc.md` says they are out of scope.** So most researchers who read
   that doc will skip these files completely. The engagement doc wins (all 64 decisive
   classifications live in `context/Arcadia-Context-Doc-Final.md`), but your competition will not
   have checked that.
3. **They are the only files exempt from the project's "every `unchecked` states its bound" rule.**
   Their `unchecked` comments all just say *"vendored, unchecked under solc 0.7.6"* — which is not a
   bound at all, it is a statement about the original compiler.

That third point is the real seam. The originals were written for **Solidity 0.7.6**, where
arithmetic **wrapped silently**. These copies compile under **0.8.34**, where arithmetic **reverts**
on overflow — unless wrapped in `unchecked`. So every port had to decide, line by line, which
arithmetic to keep wrapping and which to let revert. Get one of those decisions wrong and you either
revert where the original wrapped (a liveness bug) or wrap where the original would have been fine
(a correctness bug).

## How to do the diff

```bash
# find the upstream copies
ls node_modules/@metadex* node_modules/*metadex* 2>/dev/null
find node_modules lib -iname "OracleLibrary.sol" -o -iname "PositionValue.sol" \
     -o -iname "TickBitmap.sol" -o -iname "SwapMath.sol"
```

Upstream sources, named in the file headers:

| Vendored file | Upstream |
|---|---|
| `MetadexOracle.sol` | `metadex-slipstream-public/contracts/periphery/libraries/OracleLibrary.sol` |
| `MetadexPositionValue.sol` | `metadex-slipstream-public/contracts/periphery/libraries/PositionValue.sol` |
| `MetadexTickBitmap.sol` | `Uniswap/v4-core/src/libraries/TickBitmap.sol` |
| `MetadexSwapMath.sol` | `metadex-slipstream-public/contracts/core/libraries/SwapMath.sol` |

For each difference, ask one question: **why?** Every intentional change is a decision, and a
decision can be wrong.

---

## B1. `MetadexOracle.sol` (38 lines) — the TWAP

### What it does

Reads the pool's **time-weighted average tick** over a window.

```solidity
function consult(address pool, uint32 secondsAgo) internal view returns (int24 arithmeticMeanTick) {
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = secondsAgo;          // secondsAgos[1] stays 0 == "now"

    int56[] memory tickCumulatives = IMetadexCLPool(pool).observe(secondsAgos);
    unchecked {
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        arithmeticMeanTick = int24(delta / int56(uint56(secondsAgo)));
        if (delta < 0 && (delta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;
    }
}
```

### Simple example

The pool keeps a running sum of (tick x seconds). Ask it for two points:

```
tickCumulatives[0] = the sum as of  secondsAgo  ago   = 1,000,000
tickCumulatives[1] = the sum as of  now                = 1,000,600
secondsAgo = 60

delta = 600
mean  = 600 / 60 = 10          ->  the average tick over the last minute was 10
```

### The one line that matters

```solidity
if (delta < 0 && (delta % secondsAgo != 0)) arithmeticMeanTick--;
```

Solidity integer division **truncates toward zero**, so `-7 / 2 == -3`. This line forces rounding
**toward negative infinity** instead, so `-3` becomes `-4`. Why? Because a tick maps to a price, and
rounding the tick down always rounds the price down. A consistent direction means the TWAP can never
be nudged upward by rounding.

### Used where

Three places, and all three are safety checks:

- `ConfigLib.checkTwapDeviation` — is spot inside the band around the TWAP? (called by `mint`)
- `ConfigLib.checkTrustedDeviation` — is the TWAP inside the band around the keeper's trusted price?
  (called by `execute`)
- `BaseVaultAccounting` and `ALMCoreViewLogic` — views.

So **this 38-line file is the oracle the whole protocol's manipulation defence rests on.**

### Audit notes

- `secondsAgo` comes from `config.twapWindow`, a `uint32` set by governance. `checkConfigured`
  requires it to be non-zero, so the division cannot be by zero — **as long as every path to
  `consult` goes through a configured core.** Check the view paths (`ALMCoreView`) too: a view on an
  unconfigured core would divide by zero. Low severity at worst, but it is a real question.
- `observe` reverts if the pool's observation history is shorter than `secondsAgo`. On a freshly
  deployed pool, or one with a small observation cardinality, that makes `mint` and `execute` revert.
  Is that reachable in production? The context doc pins the pools, so probably not — but **invariant
  8 (exits)** says `burn` must always work, and `burn` does not call this. Confirm that.
- `int24(delta / int56(...))` is an unchecked narrowing cast. `delta / secondsAgo` is a mean tick, so
  bounded by `MIN_TICK`/`MAX_TICK` **if** the cumulative values are well formed. A malformed pool
  could produce a mean outside `int24` and the cast would silently wrap. The pool is trusted here;
  write it down as an external assumption, not a finding.
- **Diff target:** the upstream `OracleLibrary.consult` also returns `harmonicMeanLiquidity`. This
  port drops it (the docstring says so). Confirm nothing in the original's tick path depended on the
  liquidity branch.

---

## B2. `MetadexPositionValue.sol` (46 lines) — uncollected fees

### What it does

Works out how much in swap fees a position has earned but not yet collected.

```solidity
function fees(address pool, Position memory position) internal view returns (uint256 amount0, uint256 amount1) {
    (uint256 growth0Now, uint256 growth1Now) = IMetadexCLPool(pool).getFeeGrowthInside(position.tickLower, position.tickUpper);
    unchecked {
        amount0 = position.tokensOwed0 + (growth0Now - position.feeGrowthInside0LastX128).fullMulDiv(position.liquidity, Q128);
        amount1 = position.tokensOwed1 + (growth1Now - position.feeGrowthInside1LastX128).fullMulDiv(position.liquidity, Q128);
    }
}
```

### The mental model

A V3-style pool does not store "fees owed" per position. It stores a global, ever-increasing
**fee growth per unit of liquidity**. A position remembers the value of that counter the last time
it was touched. Fees owed = (counter now − counter then) x your liquidity.

**Example.**

```
feeGrowthInside0 when you last collected : 1000  (per unit of liquidity, X128 scaled)
feeGrowthInside0 now                     : 1500
your liquidity                           :   40

uncollected fees = (1500 - 1000) * 40 / 2^128  = 500 * 40 / 2^128
plus tokensOwed0 (anything already credited but not transferred out)
```

### The `unchecked` that is load-bearing

`growth0Now - position.feeGrowthInside0LastX128` **is expected to underflow sometimes.** The global
fee growth counter is a `uint256` that wraps by design in Uniswap V3 and its forks. The subtraction
of two wrapping counters gives the correct delta *because* it wraps the same way. Under 0.8 that
needs `unchecked` or it would revert.

This is one of the few places where `unchecked` is not an optimisation but a **correctness
requirement**. If someone "fixed" it by removing the `unchecked`, fee collection would revert
permanently once the counter wrapped.

### Used where

One caller: `RangesLib.getUnstakedPositions`, which is called by `ALMCore.getUnstakedPositions`
(public view) and inside `mint`. So this function's output **feeds directly into how many tokens a
minter pays**.

### Audit notes

- Note it computes the fees of the **unstaked side only** — `getUnstakedPositions` reads
  `unstakedTokenId`. The staked side's swap fees go to the gauge mechanism, not here. Confirm that
  is actually true of Metadex gauges in the context doc §3.3, because if a staked position also
  accrued collectable swap fees, the core would be under-valuing itself in `mint`.
- `fullMulDiv` rounds **down**, so uncollected fees are under-reported by at most 1 wei per token
  per range. In `mint` that means the minter pays based on a slightly lower fee estimate. Which
  direction does that favour? Work it out — it is one row in your rounding table, and it is the kind
  of row that turns into a finding.
- **Diff target:** the docstring says the port reads "the fee growth inside from the pool" where the
  original computed it from tick data. That is a real behavioural change: the original recomputes
  from `ticks()`, this one trusts `pool.getFeeGrowthInside()`. Does the Metadex pool's
  `getFeeGrowthInside` apply the same tick arithmetic? That is the single highest-value question in
  this file.

---

## B3. `MetadexTickBitmap.sol` (62 lines) — finding the next tick

### What it does

In a concentrated-liquidity pool, liquidity changes only at **initialised ticks**. A swap must walk
from one to the next. The pool stores which ticks are initialised in a **bitmap**: one bit per tick,
packed 256 to a word.

This function answers: *"starting from this tick, where is the next initialised tick in this
direction — or the edge of the current 256-bit word, whichever comes first?"*

### Simple example

Think of one bitmap word as 256 light switches. Tick spacing is 100, so switch *k* means tick
`k * 100`. Suppose switches 3, 7 and 40 are on.

```
searching upward from switch 3  ->  next = switch 7  (initialized = true)
searching upward from switch 40 ->  nothing above in this word
                                ->  next = switch 255 (initialized = false)  "the word's end"
```

Returning the word's end un-initialised is what makes the walk bounded: the caller swaps to that
price, finds nothing there, and asks again from the next word.

### The two branches

```solidity
if (lte) {                                   // searching at or below
    (wordPos, bitPos) = position(compressed);
    mask   = type(uint256).max >> (255 - bitPos);     // all 1s at and right of bitPos
    masked = pool.tickBitmap(wordPos) & mask;
    initialized = masked != 0;
    next = initialized
        ? (compressed - (bitPos - mostSignificantBit(masked))) * tickSpacing
        : (compressed - bitPos) * tickSpacing;
} else {                                     // searching above
    (wordPos, bitPos) = position(++compressed);       // start from the NEXT tick
    mask   = ~((1 << bitPos) - 1);                    // all 1s at and left of bitPos
    masked = pool.tickBitmap(wordPos) & mask;
    initialized = masked != 0;
    next = initialized
        ? (compressed + (leastSignificantBit(masked) - bitPos)) * tickSpacing
        : (compressed + (255 - bitPos)) * tickSpacing;
}
```

Note the `++compressed` in the upward branch, with the comment *"the current tick state does not
matter"*. Off-by-one errors in tick walks are classic, and this is where one would live.

### Used where

One caller: `SwapStateLib.setNextTick`, which drives **every** swap simulation in the sync vault.
If this returns a wrong tick, every `previewDeposit`, `previewMint`, `previewWithdraw` and
`previewRedeem` is wrong, and so is every `maxDeposit`/`maxMint`/`maxWithdraw`/`maxRedeem`.

### Audit notes

- This one is vendored from **Uniswap v4-core**, not from Metadex. v4-core is already `^0.8.0`, so
  the arithmetic semantics did not change — the only change is **reading the bitmap word from the
  pool by external call** instead of from local storage. That makes it a `view` function with a
  `calls-loop` lint suppression. Lower risk than the other three.
- But: it imports `TickBitmap.compress` and `TickBitmap.position` from v4-core while implementing
  `nextInitializedTickWithinOneWord` itself. **Does Metadex's pool use the same `compress` and
  `position` convention as Uniswap v4?** v3 and v4 differ in how they handle tick spacing in the
  bitmap. If Metadex follows v3-style Slipstream rather than v4, the word/bit mapping could be off.
  **This is the single question to answer in this file.** Compare against the actual Metadex pool's
  `tickBitmap` writer (`contracts/core/libraries/TickBitmap.sol` upstream).
- `int24(uint24(bitPos - mostSignificantBit(masked)))` and friends are unchecked narrowing casts
  inside the `unchecked` block. In the upward branch, `leastSignificantBit(masked) - bitPos` is
  non-negative *because the mask cleared everything below `bitPos`* — so the subtraction is safe by
  construction. Satisfy yourself of that; it is a one-minute proof and it closes a bound.

---

## B4. `MetadexSwapMath.sol` (96 lines) — one step of a swap

### What it does

Given the current price, a target price, the available liquidity, how much is left to swap, and the
fee — compute what one swap step consumes and produces.

```solidity
function computeSwapStep(
    uint160 sqrtPriceCurrentX96,
    uint160 sqrtPriceTargetX96,
    uint128 liquidity,
    int256  amountRemaining,     // positive = exact input, negative = exact output
    uint24  feePips              // 1e-6 units, so 3000 == 0.3%
) returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount)
```

### Simple example

Price is 100, the next initialised tick is at 99, you want to sell 1000 token0, fee is 0.3%.

```
1. amountRemainingLessFee = 1000 * (1e6 - 3000) / 1e6 = 997
2. "how much token0 does it take to move 100 -> 99?"  say 400
3. 997 >= 400, so the step reaches the target:  sqrtPriceNext = 99
4. recompute amountIn/amountOut exactly at 99
5. feeAmount = amountIn * 3000 / (1e6 - 3000)      (fee ON TOP of the net input)
```

If instead it took 2000 token0 to reach 99, then `997 < 2000`, the step stops **short** of the
target at whatever price 997 token0 buys, and:

```
feeAmount = amountRemaining - amountIn = 1000 - amountIn     (the whole remainder is the fee)
```

That last line is the famous asymmetry: when a step stops short on an exact-input swap, the fee is
**the entire leftover**, not a percentage.

### The four rounding rules

This is the part to get exactly right, because the vault's simulation must match the pool to the wei:

```
amountIn  when zeroForOne : getAmount0Delta(..., roundUp = true)    // pool takes MORE
amountIn  when oneForZero : getAmount1Delta(..., roundUp = true)
amountOut either direction: getAmount*Delta(..., roundUp = false)   // pool pays LESS
feeAmount                 : fullMulDivUp                            // pool takes MORE
```

**Always against the swapper.** That is standard and correct, and it is why the vault's own
`SwapStateLib.computeSwapStep` has a `roundUp` boolean — in some of its passes it needs the
*optimistic* version to bound a search.

### The `max` flag

```solidity
bool max = sqrtPriceTargetX96 == sqrtPriceNextX96;
if (!max || !exactIn) { amountIn  = ...recompute... }
if (!max || exactIn)  { amountOut = ...recompute... }
```

Translation: *"if the step reached its target, keep the amount we already computed for that target;
otherwise recompute at the price we actually landed on."* Skipping the recomputation when the target
was reached is not just gas — recomputing could give a value one wei different and break the
invariant that the step's amounts correspond exactly to the price move.

### Used where

Two callers, both sync-vault previews:

- `MintOptimizationMath.computeSwap` — with a **negative** `amountRemaining` (exact output), to find
  the buy that exactly covers the mint's needs.
- `RedeemOptimizationMath.previewRedeem` and `maxRedeem` — with a **positive** `amountRemaining`
  (exact input), to sell the tokens a burn released.

Note `maxRedeem` passes `type(int256).max` as `amountRemaining` — "sell without limit, stop at the
price bound". Check that `uint256(type(int256).max).fullMulDiv(1e6 - feePips, 1e6)` does not
overflow. It cannot (it is a division), but confirm it.

### Audit notes — this is the densest of the four

- **The whole function body is one `unchecked` block** with the comment *"vendored, unchecked under
  solc 0.7.6"*. Under 0.7.6 every one of these lines could wrap. Under 0.8.34 they are told not to
  revert. So for each arithmetic line, ask: **can it overflow with inputs reachable from the two
  callers?** Specifically:
  - `uint256(amountRemaining) - amountIn` in the fee branch. Reached only when
    `exactIn && sqrtPriceNext != sqrtPriceTarget`, which the logic above should guarantee means
    `amountIn < amountRemaining`. **Prove it, or find the case where it does not hold** — a wrap
    here produces an astronomically large `feeAmount`, which in `previewRedeem` would make
    `state.amountIn` jump past `amountBurnIn` and end the loop early, under-reporting the payout.
    That is a concrete, checkable hypothesis and I like it as a lead.
  - `uint256(-amountRemaining)` when `amountRemaining == type(int256).min`. Negating `int256.min`
    wraps to itself. Can `MintOptimizationMath` pass that? It passes
    `-toInt256(someFullMulDivUp(...))`, so the magnitude would have to reach 2^255. Almost certainly
    unreachable, but it is one line to check and it is the kind of thing that is either impossible
    or critical.
- **Diff target:** the docstring claims it is ported *"with the same checked and unchecked
  arithmetic"*. That is a precise, falsifiable claim. Diff it line by line against upstream
  `SwapMath.computeSwapStep` and confirm every operation kept its semantics. If upstream had a
  `SafeMath` call somewhere that became plain arithmetic inside `unchecked`, that is a found bug.
- It calls `SqrtPriceMath.getNextSqrtPriceFromInput` / `FromOutput` from `@uniswap/v4-core`.
  Metadex-Slipstream is a **v3** fork. **Are v4's `SqrtPriceMath` and v3's bit-for-bit identical?**
  They are close, but "close" is not "identical", and this whole file exists to replicate the pool
  exactly. Compare `node_modules/@uniswap/v4-core/src/libraries/SqrtPriceMath.sol` against the
  Metadex pool's own `SqrtPriceMath.sol`. If they differ by even one rounding direction, every sync
  vault preview is off — and the vault's `_swapAndMint` relies on its simulation agreeing with the
  real swap to a few wei.

**That last bullet is, in my judgement, the single most promising concrete question in Pass 0.**
It is mechanical to answer, nobody who skipped the vendored files will ask it, and the blast radius
if the answer is "they differ" is the entire sync vault.

---

# PART C — The core's state libraries

These ten files **are** the core. `ALMCore.sol` and the two extensions are mostly glue: they check
permissions, call these libraries, and emit events. If you know these ten, Pass 1 becomes reading
glue code.

---

## C1. `ConfigLib.sol` (87 lines) — the governance bounds and the price checks

### The three constants

```solidity
uint256 constant BPS_DENOMINATOR = 10_000;   // basis points in a whole
uint256 constant MAX_FEE_BPS     = 5000;     // protocol may take at most 50%
uint8   constant MAX_RANGE_CAP   = 14;       // at most 14 ranges
```

`MAX_RANGE_CAP = 14` is why `PlanCache.openedRanges` can be a bitmask in one word, and why
`removeLiquidity`'s loop is bounded. It is also why the EIP-7825 gas cap (16.8M) is survivable.

### `checkConfigured(config)`

```solidity
if (config.twapWindow == 0 || config.rangeCap == 0 || config.totalCap == 0 || config.perUserCap == 0)
    revert NotConfigured();
```

Called once, from `ALMAdminExtension.seed`. A core cannot be seeded until governance has set all
four. **Note what is NOT in this list:** the deviation parameters, the plan limits, the protocol
fees, `feeRecipient`. A core can therefore be seeded with `maxSpotFromTwap == 0` — which would make
`getBand` return `(sqrtPrice, sqrtPrice)` and `checkTwapDeviation` require spot to equal the TWAP
*exactly*. In practice that bricks `mint` until governance sets a band. Is that a finding? Probably
not (governance error, and §4.1 says the steward is trusted), but it is a one-line question worth
noting: **does the deploy flow in Trace 1 set the deviations before `seedCore`?**

### `checkTwapDeviation(config, pool, sqrtPriceX96)` — the mint guard

```solidity
(lower, upper) = CLMath.getBand(TickMath.getSqrtPriceAtTick(MetadexOracle.consult(pool, config.twapWindow)),
                                config.maxSpotFromTwap);
if (sqrtPriceX96 < lower || sqrtPriceX96 > upper) revert PriceDeviation();
```

Plain English: *"take the average tick over the last `twapWindow` seconds, turn it into a price,
build a band of `maxSpotFromTwap` around it, and require the pool's current price to be inside."*

**Example.** `twapWindow = 300` (5 min), `maxSpotFromTwap = 1e16` (1% on sqrt price).
TWAP tick maps to `sqrtPrice = 1000`. Band = `[991, 1010]`. Spot must land in there or `mint` reverts.

Called from `ALMCore.mint` only. **Not** from `burn` — burning must always work (invariant 8).

### `checkTrustedDeviation(config, pool, trustedSqrtPriceX96)` — the plan guard

Two checks, both bands around the **keeper's own** supplied price:

```solidity
// 1. spot must be near the trusted price
(lower, upper) = CLMath.getBand(trustedSqrtPriceX96, config.maxSpotFromTrusted);
spotSqrtPriceX96 = PoolLogic.sqrtPriceX96(pool);
if (spot < lower || spot > upper) revert PriceDeviation();

// 2. the TWAP must also be near the trusted price
(lower, upper) = CLMath.getBand(trustedSqrtPriceX96, config.maxTwapFromTrusted);
twap = TickMath.getSqrtPriceAtTick(MetadexOracle.consult(pool, config.twapWindow));
if (twap < lower || twap > upper) revert PriceDeviation();
```

The keeper names the reference price, and then the pool has to agree with it **twice** — once on
spot, once on the TWAP. That is the manipulation defence for plans: a keeper cannot name a fake
price, because the pool's spot and its 5-minute average both have to match it.

Returns `spotSqrtPriceX96` so the caller does not re-read it.

### Used where

8 files: `ALMAdminExtension`, `ALMCore`, `ALMKeeperExtension`, `PoolTokensLib`, `RangesLib`,
`RewardsLib`, `PlanCache`, `State`. Mostly for `BPS_DENOMINATOR`.

### Audit notes

- **Which functions do NOT check any price?** `burn`, `trustedBurn`, all four cancels, all four
  claims, `skim`, `payProtocolFees`, `claimEmissions`. Each of those is either an exit (must always
  work) or settles at a rate fixed earlier. For Pass 2, the question for each is: *is the rate it
  settles at still correct if the price has moved since?*
- `maxSpotFromTwap`, `maxSpotFromTrusted` and `maxTwapFromTrusted` are all `uint64`. `getBand`'s
  `unchecked { scale = 1e18 + deviation }` is bounded because of that — `1e18 + 2^64` cannot
  overflow. Verified.
- There is **no upper bound enforced here** on the deviations. A `uint64` deviation can be
  ~1.8e19, i.e. a band of 18x. Where is the cap? In `ALMAdminExtension.setDeviation` (L204) /
  `ALMFactory.setDeviation` (L429). Read those in Trace 9 and check the bound. The context doc's
  production envelope says 1e15 to 1e16, and findings needing values outside that envelope are out
  of scope — so a "governance can set a stupid band" report is dead. But a finding where a
  **sensible** band (1e15–1e16) still permits harm is very much alive.

---

## C2. `PoolTokensLib.sol` (156 lines) — the three ledgers and solvency

### The model

The core's token0 and token1 are split into exactly three buckets:

```
buffer       - loose tokens the core owns on behalf of aLP holders
protocolFees - owed to the fee recipient
escrowed     - held on behalf of pending and claimable async requests
```

**Invariant 1 (solvency)** says the actual ERC-20 balance must cover all three:

```solidity
function checkSolvency(State storage state, address token0, address token1) internal view {
    (reserve0, reserve1) = getReserves(state.poolTokens);        // buffer + protocolFees + escrowed
    uint256 rewardPoolToken = state.config.rewardPoolToken;
    if (rewardPoolToken == 1) reserve0 += state.rewards.lastRewardBalance;
    else if (rewardPoolToken == 2) reserve1 += state.rewards.lastRewardBalance;
    if (token0.balanceOf(address(this)) < reserve0) revert AccountingMismatch();
    if (token1.balanceOf(address(this)) < reserve1) revert AccountingMismatch();
}
```

Note the `rewardPoolToken` branch: if the AERO-equivalent reward token happens to *be* one of the
pool's two tokens, then the reward balance also has to be covered by the same ERC-20 balance.
That is the "one token, two roles" case and it is a rich source of edge cases.

Called from `ALMKeeperExtension.execute` at the end of every plan.

### `creditCollected(state, principal, fees)` — where swap fees are split

```solidity
uint256 bps = state.config.protocolSwapFeeBps;
(fees0, fees1) = fees.toAmounts();
(protocolFee0, protocolFee1) = (fees0.fullMulDiv(bps, 10_000), fees1.fullMulDiv(bps, 10_000));  // DOWN

unchecked { delta = principal.add(fromAmounts(fees0 - protocolFee0, fees1 - protocolFee1)); }

state.poolTokens.protocolFees.applyDelta(fromAmounts(protocolFee0, protocolFee1));
state.poolTokens.buffer.applyDelta(delta);
```

**Example.** A plan collects 1000 token0 of fees and released 5000 token0 of principal.
`protocolSwapFeeBps = 1000` (10%).

```
protocolFee0 = floor(1000 * 1000 / 10000) = 100
buffer     += 5000 + (1000 - 100) = 5900
protocolFees += 100
```

**The protocol fee rounds DOWN**, so the dust goes to the buffer — i.e. to aLP holders.
Correct direction. The `unchecked` bound is *"the protocol fee is at most half of the collected
fees"*, which follows from `MAX_FEE_BPS = 5000`. Verified, assuming the setter enforces it
(check `ALMAdminExtension.setProtocolFees` L229 in Trace 9).

### `payProtocolFees(fees, token0, token1, recipient)`

Zeroes the ledger, then transfers. Classic correct ordering (state before external call).
**Permissionless** — anyone can call `ALMCore.payProtocolFees`, it just pays the configured
recipient. Nothing to steal, but it is an entry point anyone can hit at any time, which matters for
reentrancy ordering in Pass 3.

### `skim(state, token0, token1)` — untracked tokens become protocol fees

```solidity
(reserve0, reserve1) = getReserves(poolTokens);
uint256 rewardPoolToken = state.config.rewardPoolToken;
if (rewardPoolToken != 1) amount0 = token0.balanceOf(address(this)) - reserve0;
if (rewardPoolToken != 2) amount1 = token1.balanceOf(address(this)) - reserve1;
poolTokens.protocolFees.applyDelta(fromAmounts(amount0, amount1));
```

If someone sends tokens to the core directly, or a rounding dust accumulates, `skim` books the
excess to `protocolFees`.

**Two things to notice:**

1. The subtraction is **outside** `unchecked`, so under 0.8 it **reverts** if balance < reserve.
   `skim` therefore doubles as a solvency assertion. Nice.
2. The token that is also the reward token is **skipped** — because its excess is the unclaimed
   reward, not a donation. That is the `rewardPoolToken != 1` / `!= 2` guard.

**Also permissionless** (`ALMCore.skim` L565). Anyone can convert untracked tokens into protocol
fees at any moment.

### Used where

`ALMAdminExtension`, `QueueLib`, `State`.

### Audit notes / leads

- **`skim` is permissionless and moves value into `protocolFees`.** Think about who benefits from
  calling it at a particular moment. `getUnstakedPositions` values *uncollected* fees that are still
  inside the position NFTs, not in the core's balance — so skim should not be able to steal those.
  But a plan that `collect`s fees into the core's balance and then does something else before
  `creditCollected`... check the ordering in `execute` (L108–112: `collectFees` then
  `creditCollected`, same transaction, no external call between). Looks tight. Satisfy yourself.
- **`checkSolvency` uses `<` not `==`.** An excess balance is fine (that is what `skim` is for).
  So the invariant is "balances cover the ledgers", not "balances equal the ledgers". That is the
  correct and intended reading, and it means a *donation* can never break a plan. Good design.
- **The `rewardPoolToken` double-role case deserves its own Pass 2 hour.** When the reward token is
  token0: `lastRewardBalance` is added to `reserve0` in `checkSolvency`, `skim` skips token0
  entirely, and `RewardsLib.getRewardTotals` subtracts `reserve0` from the measured reward balance.
  Three different pieces of code have to agree about one balance. Trace a case where they do not:
  e.g. what if `escrowed.amount0` rises between a `getRewardTotals` and a `checkSolvency`? That is
  a concrete thing to try.
- `getReserves` sums three `uint128`s inside `unchecked` into a `uint256`. Three `uint128`s cannot
  overflow a `uint256`. Verified, bound closed.

---

## C3. `ShareLib.sol` (123 lines) — caps and the exchange rate

### The two caps

```solidity
function checkTotalCap(State storage state, uint256 supply) internal view {
    if (supply > state.config.totalCap) revert TotalCapExceeded();
}

function checkPerUserCap(State storage state, address account, uint256 shares) internal view {
    if (isCapExempt(state, account)) return;
    ShareAccount storage a = state.share.shareAccounts[account];
    unchecked {
        if (shares + a.claimableShares + a.pendingShares > state.config.perUserCap) revert PerUserCapExceeded();
    }
}

function isCapExempt(State storage state, address account) internal view returns (bool) {
    return account == address(this) || state.share.isExempt[account];
}
```

**The per-user cap counts three things, not one:** your aLP balance, your *claimable* aLP from
settled async deposits, and your *pending* aLP from unsettled async deposits. So you cannot dodge
the cap by parking shares in the async queue.

Two accounts are exempt: **the core itself** (it holds aLP as the protocol's emission fee accrual)
and anything governance flags via `setCapExempt`.

Where it is called: `ALMCore.mint` (on `receiver`), `ALMCore.transfer`/`transferFrom` (on `to`),
and inside the async request paths.

**That `transfer` check is interesting.** The cap is enforced on *receiving a transfer*, which means
a cap-limited user cannot be pushed over the cap by someone else's transfer — the transfer reverts
instead. That is a griefing surface worth a note: can I block someone's legitimate transfer by first
sending them dust aLP to fill their cap? Probably yes, but the harm is small and they can move it
on. Note it, do not report it yet.

### `setLastExchangeRate(share, lastSqrtPriceX96, supply, value)`

```solidity
lastExchangeRate.supplyPerValueX128 = supply.fullMulDivUp(1 << 128, value);   // rounds UP
lastExchangeRate.sqrtPriceX96 = lastSqrtPriceX96;
```

Called at the **very end** of `ALMKeeperExtension.execute`. It records "as of the last plan, one
unit of value was worth this many shares, at this price". Deposit requests arriving *after* that
plan are priced against this stored rate.

### `getPendingShares(share, isToken0, assets, sqrtPriceX96)`

```solidity
if (lastSqrtPriceX96 == 0) revert LastExchangeRateNotSet();

if (isToken0) {
    upper = max(sqrtPriceX96, lastSqrtPriceX96);                       // the WORSE price for the user
    value = assets.fullMulDivUp(upper, 1<<96).fullMulDivUp(upper, 1<<96);
} else {
    value = sqrtPriceX96 >= lastSqrtPriceX96
        ? assets
        : assets.fullMulDivUp(lastSqrtPriceX96, sqrtPriceX96).fullMulDivUp(lastSqrtPriceX96, sqrtPriceX96);
}
shares = value.fullMulDivUp(lastExchangeRate.supplyPerValueX128, 1 << 128);   // rounds UP
```

This computes a **conservative upper bound** on how many shares a pending deposit could become.
Everything rounds up and it deliberately picks the **larger** of the two prices.

**Why rounding up is correct here, and not a gift:** `pendingShares` is not a payout. It is only
used for (a) the per-user cap and (b) the `Record`'s bookkeeping. Over-estimating it makes the cap
**stricter**, not looser. So "round up" is the conservative direction. Confirm that reading holds
everywhere `pendingShares` is read — if you find a place where a larger `pendingShares` *benefits*
the holder, that is a finding.

**The revert matters too:** a core whose last exchange rate was never set cannot take async deposit
requests. `supplyPerValueX128` and `sqrtPriceX96` are only written by `execute`. So **the first plan
must run before the first async deposit**. Check what the deploy flow does about that in Trace 1.

### Used where

Only `State.sol` (as the `using ShareLib for State` binding), then through `State` everywhere.

### Audit notes

- `checkPerUserCap` sums three values inside `unchecked` with the bound *"every term is within the
  uint128 total cap"*. Three `uint128`s into a `uint256` cannot overflow regardless, so the bound is
  more conservative than it needs to be. Fine.
- **Asymmetry to chase:** `getPendingShares`'s token0 branch takes `max(spot, last)` — the worse of
  the two prices — while the token1 branch only adjusts when `spot < last`. Convince yourself the
  two branches are the *same* conservatism expressed in the two different directions. They look
  consistent to me, but the token1 branch's "if spot is higher, just use assets" is doing more work
  than it appears and is worth five minutes.
- `supplyPerValueX128 = supply / value` rounded up — and `value` can be small. If `value` were 0 it
  would divide by zero and `execute` would revert at the very last line. Does anything guarantee
  `value > 0`? `PlanCacheLib.getSettlementAmountsOut` reverts `ZeroValue` in some cases, and
  `getValueAfter` floors at zero. **A plan that legitimately ends with zero value would revert on
  the last line.** Is that reachable, and is it a liveness problem? Good Pass 2 question.

---

## C4. `PoolLogic.sol` (75) and `PositionManagerLogic.sol` (112) — talking to the outside

Two thin adapters. Short sections, but read them, because **every assumption the core makes about
Metadex lives here.**

### `PoolLogic.sol` — five reads of the pool

```solidity
sqrtPriceX96(pool)           -> slot0().sqrtPriceX96
liquidity(pool)              -> pool.liquidity()          // in-range liquidity
tryFee(pool)                 -> (ok, fee)  via try/catch
sqrtPriceLimit(zeroForOne)   -> MIN_SQRT_PRICE+1 or MAX_SQRT_PRICE-1
liquidityNet(pool, tick)     -> ticks(tick).liquidityNet
```

**`tryFee` is the one to think about.** It wraps `pool.fee()` in `try/catch` and returns
`(false, 0)` if it reverts. Why would a pool's `fee()` revert? Because **Metadex fees are dynamic
per block** — the context doc says so in §3.3. A pool using a dynamic-fee hook may not expose a
static `fee()` at all.

So: who calls `tryFee`, and what do they do with `ok == false`? Grep it in Pass 1. If any path
treats a failed fee read as "fee is zero", that is a finding waiting to happen.

**`sqrtPriceLimit`** returns the extreme price in the swap's direction, i.e. "no limit". Used by
every unbounded simulation walk.

### `PositionManagerLogic.sol` — five calls to the position manager

Every function returns a `TokenDelta` with the **sign already correct**:

| Function | Returns | Sign |
|---|---|---|
| `mint` | `(tokenId, liquidity, delta)` | `delta` is **negative** (tokens left the core) |
| `increaseLiquidity` | `(liquidity, delta)` | **negative** |
| `decreaseLiquidity` | `principal` | **positive** (tokens owed to the core) |
| `collect` | `gross` | **positive** |
| `decreaseLiquidityAndCollect` | `(principal, fees)` | both positive |

Two details it fills in for you:

```solidity
(params.recipient, params.deadline) = (address(this), block.timestamp);   // mint
(params.recipient, params.amount0Max, params.amount1Max) = (address(this), uint128.max, uint128.max);  // collect
params.deadline = block.timestamp;                                        // increase / decrease
```

`deadline = block.timestamp` means **the deadline is always "now"** — it can never expire, so it
provides no protection. That is intentional (the plan's own `minPlanInterval` and price checks are
the protection) but it is worth knowing that the position manager's deadline is a no-op here.

### The one line to stare at

```solidity
function decreaseLiquidityAndCollect(...) returns (TokenDelta principal, TokenDelta fees) {
    principal = decreaseLiquidity(positionManager, params);
    CollectParams memory collectParams;
    collectParams.tokenId = params.tokenId;
    fees = collect(positionManager, collectParams).add(principal.neg());   // fees = gross - principal
}
```

**`fees` is defined as "everything collected, minus the principal we just released".**

In a V3 position manager, `decreaseLiquidity` does not transfer anything — it adds the released
principal to the position's `tokensOwed`. Then `collect` sweeps **everything** owed
(`amount0Max = uint128.max`). So `gross = principal + accrued swap fees`, and subtracting the
principal leaves the fees. Correct.

**But**: it leaves fees as *whatever else was owed*. If the token id already had `tokensOwed` from
an **earlier** operation that was not collected, that amount is swept here and classified as
**fees** — which means the protocol takes `protocolSwapFeeBps` of it, even though it is principal.

Is that reachable? `decreaseLiquidity` alone (the `DECREASE_LIQUIDITY` opcode path) does not
collect... let me be precise: `_applyDecrease` (L363) and `_collect` (L340) are separate opcodes.
So a keeper *can* issue `DECREASE_LIQUIDITY` and then later `COLLECT`. **This is lead #1 in Part G.**
I have not proven it causes loss — go prove or disprove it.

### Used where

`PoolLogic`: 13 files, both core and vaults. `PositionManagerLogic`: `ALMKeeperExtension` and
`RangesLib` only.

### Audit notes

- Every function here is an external call to a third-party contract. For Pass 3's reentrancy sweep:
  the position manager is an ERC-721 contract, and `mint` to `address(this)` triggers
  `ALMCore.onERC721Received` (L804). So **every `mint` re-enters the core.** Read `onERC721Received`
  carefully — what does it do, and is the reentrancy lock held at that moment?
- `forge-lint: disable-next-item(calls-loop, unused-return)` at the top of `PositionManagerLogic`
  tells you the authors knowingly make external calls in loops and discard return values. Both are
  usually fine here, but "knowingly suppressed lint" is a good place to look.

---

## C5. `RangesLib.sol` (661 lines) — the ranges, and the two NFTs per range

**Budget three hours. This is the heart of the core.**

### The central idea: every range is two positions

```
Range i
 |
 +-- unstakedTokenId  ->  an NFT the core holds itself
 |                        earns SWAP FEES
 |                        freely withdrawable, no penalty
 |                        liquidity is NOT stored, read live from the position manager
 |
 +-- stakedTokenId    ->  an NFT deposited in the CL gauge
                          earns AERO EMISSIONS
                          has a PENALTY WINDOW (minStakeBlocks, 75 on Base)
                          liquidity IS stored, as range.stakedLiquidity
```

`stakedTokenId == 0` means there is no staked side.

**Why two?** Because Metadex forfeits 100% of accrued emissions if you withdraw inside the penalty
window. If the core had one position, every `burn` during a window would destroy emissions for
everybody. With two, a burn can take the **unstaked side first** and only touch the staked side when
it has to.

### The lifecycle functions

```
openRange              mints the unstaked side at new ticks, pushes a Range
mintStaked             mints the staked side at the SAME ticks, stakes it
increaseStakedLiquidity  unstake -> increaseLiquidity -> restake
decreaseStakedLiquidity  unstake (or emergencyWithdraw) -> decrease+collect -> burn if drained, else restake
closeRange             requires NO staked side, removes+collects+burns the unstaked side, swap-and-pop
stake / unstake        the gauge deposit/withdraw primitives
```

### `openRange` — the cap check

```solidity
uint256 index = state.ranges.length;
if (index >= state.config.rangeCap) revert RangeCapExceeded();
(tokenId, liquidity, delta) = PositionManagerLogic.mint(positionManager, params);
state.ranges.push(Range({ stakedLiquidity: 0, tickLower: params.tickLower, tickUpper: params.tickUpper,
                          unstakedTokenId: toUint80(tokenId), stakedTokenId: 0, stakedBlock: 0 }));
```

`toUint80(tokenId)` — a position manager token id must fit 80 bits. Metadex ids are sequential
counters, so 2^80 is unreachable in practice. `SafeCastLib` reverts if not. Fine.

**Note what is NOT checked:** nothing stops two ranges having **identical ticks**. You could have
range 3 and range 7 both at `[100, 200]`. Is that harmful? It would double up fee collection loops
and make `getMintAmounts` charge twice for the same band — but that is symmetric, so probably
harmless. Worth 10 minutes in Pass 2 anyway, because `EquivalentPositionMath` folds ranges together
and duplicate ranges exercise that fold differently.

### `closeRange` — and the swap-and-pop that moves indices

```solidity
Range storage range = ranges[index];
if (range.stakedTokenId != 0) revert RangeStaked();          // must fully unstake first
(tickLower, tickUpper) = (range.tickLower, range.tickUpper);
tokenId = range.unstakedTokenId;

liquidity = positionManager.positions(tokenId).liquidity;    // LIVE read
if (liquidity > 0) (principal, fees) = decreaseLiquidityAndCollect(...);
else               fees = collect(...);                      // still sweep what is owed

positionManager.burn(tokenId);

if (index != lastIndex) ranges[index] = ranges[lastIndex];   // <<< SWAP
ranges.pop();                                                // <<< POP
```

**The swap-and-pop is the most consequential line in this file.** Closing range 3 of 8 moves range 7
into slot 3. Any index a keeper computed off-chain before that point is now stale.

Two things depend on it:

1. `PlanCacheLib.closeRange(index, lastIndex)` has to move the "opened" bit the same way. It does:
   ```solidity
   opened = (opened & ~(1 << index)) | (((opened >> lastIndex) & 1) << index);
   cache.openedRanges = opened & ~(1 << lastIndex);
   ```
   Read that twice. It clears the closed index's bit, copies the last range's bit into it, then
   clears the last bit. Correct — **but only if the caller passes the right `lastIndex`.**
2. Every opcode after the close in the same plan must use post-swap indices. That is what
   `CalldataLogic.readKey` returning `(index, tokenId)` is for: the payload names **both** the index
   **and** the token id it expects to find there, so a stale index fails loudly instead of acting on
   the wrong range. Find the line that enforces the match — it is in the `ALMKeeperExtension`
   handlers, and it is the defence against index drift. **If any handler reads the index without
   checking the token id, that is a finding.**

### `decreaseStakedLiquidity` — the emergency branch

```solidity
if (emergency) {
    params.liquidity = range.stakedLiquidity;       // forced to ALL of it
    gauge.emergencyWithdraw(tokenId);               // no emissions claim
} else {
    unstake(gauge, tokenId);                        // normal withdraw, claims
}
params.tokenId = tokenId;
(principal, fees) = decreaseLiquidityAndCollect(positionManager, params);

uint128 stakedLiquidity = range.stakedLiquidity - params.liquidity;   // CHECKED: reverts on underflow
range.stakedLiquidity = stakedLiquidity;

if (stakedLiquidity == 0) {
    positionManager.burn(tokenId);
    range.stakedTokenId = 0;
} else {
    stake(state, range, positionManager, gauge, tokenId, config);      // restake, new window!
}
```

**Invariant 6** says `stakedTokenId != 0` if and only if `stakedLiquidity > 0`. This is the function
that maintains it, in those last seven lines. Attack it:

- What if `gauge.emergencyWithdraw` succeeds but `decreaseLiquidity` reverts? The whole transaction
  reverts. Safe.
- What if `emergencyWithdraw` leaves the NFT somewhere other than the core? Then `decreaseLiquidity`
  reverts (not the owner). Safe, assuming the gauge behaves.
- What if the gauge's `withdraw` silently does nothing? Then `decreaseLiquidity` is called on a
  position the gauge still holds and reverts. Safe.
- **What if `params.liquidity == 0`?** Then `stakedLiquidity` is unchanged, non-zero, and it
  restakes — starting a **fresh penalty window** on a range that nothing actually happened to.
  A keeper could repeatedly reset the penalty window. Combined with `_closeRange` requiring no
  staked side, that is a liveness angle. **Lead.**
- The restake path calls `stake()`, which sets a **new** `stakedBlock`. So *any* partial decrease
  restarts the penalty window for the remainder. That is inherent to the gauge design (withdraw and
  redeposit), not a bug — but it means a burn that touches a staked side resets the window for
  everyone. Note it for Pass 2's rewards work.

### `stake` — where `windowEnd` is written

```solidity
positionManager.approve(gauge, tokenId);
gauge.deposit(tokenId);

uint256 blockNumber = EmissionsLogic.getBlockNumber(state.config.arbBlockNumber);
range.stakedBlock = toUint48(blockNumber);

if (config.penaltyRate == 0 || config.minStakeBlocks == 0) return;        // <<< EARLY RETURN
uint256 windowEnd = blockNumber + config.minStakeBlocks;
if (windowEnd > state.config.windowEnd) state.config.windowEnd = uint48(windowEnd);
```

**That early return is important and I want you to sit with it.** If the gauge currently has
`penaltyRate == 0`, `stakedBlock` is still written but `state.config.windowEnd` is **not**.

Now: `RewardsLib.getRewardPerShare` only recomputes hidden emissions `if (windowEnd != 0)`.
And `penaltyRate` / `minStakeBlocks` are **admin-mutable on the gauge factory at any time**
(context doc §3.3 — and §4.1 says external protocol admins are NOT trusted the way the steward is).

So the sequence: stake while `penaltyRate == 0` (windowEnd stays 0) → Metadex admin raises
`penaltyRate` above 0 → the range is now inside a penalty window (`blockNumber < stakedBlock +
minStakeBlocks`) but `windowEnd == 0`, so the hidden-emissions branch is skipped entirely.

**This is lead #7 and it is the one I would personally chase first.** It is reachable without any
attacker (an ordinary Metadex parameter change does it), the context doc explicitly says ordinary
parameter changes are in scope, and the consequence lands on the rewards accumulator. Go verify the
exact behaviour and quantify the loss. **I have not proven harm — I have found a state worth
testing.**

### `collectFees` — the plan's opening move

```solidity
for (uint256 i; i < length; ++i) {
    Range storage range = unsafeAccess(ranges, i);
    uint128 unstakedLiquidity = positionManager.positions(range.unstakedTokenId).liquidity;  // LIVE
    unchecked { liquidity = unstakedLiquidity + range.stakedLiquidity; }
    if (liquidity == 0) continue;                                  // <<< SKIP

    (rangeAmount0, rangeAmount1) = CLMath.getPrincipalAmounts(sqrtPriceX96, tickLower, tickUpper, liquidity);
    unchecked { amount0 += rangeAmount0; amount1 += rangeAmount1; }

    if (unstakedLiquidity == 0) continue;                          // <<< SKIP fee collection

    params.tokenId = range.unstakedTokenId;
    fees = fees.add(PositionManagerLogic.collect(positionManager, params));
}
```

Called at the start of **every** plan (`ALMKeeperExtension.execute` L108). Does two jobs at once:
sums every range's principal (for `PlanCache.start`) and sweeps the unstaked sides' fees.

**Two `continue`s, two leads:**

- A range with `liquidity == 0` on both sides is skipped entirely — so its unstaked NFT's
  `tokensOwed` is never collected. When does a range hold zero liquidity but non-zero owed?
  After a `DECREASE_LIQUIDITY` to zero without a `COLLECT`. **Lead #2.**
- A range with staked liquidity but **zero** unstaked liquidity skips the fee collection. That is
  correct (no unstaked position, no swap fees to collect) — unless the unstaked NFT still has
  `tokensOwed` from earlier. Same lead.

### `addLiquidity` — the mint path

```solidity
for (uint256 i; i < length; ++i) {
    RangeAmounts memory rangeAmounts = mintAmounts[i];
    if ((rangeAmounts.amount0 | rangeAmounts.amount1) == 0) continue;
    (params.amount0Desired, params.amount1Desired) = (rangeAmounts.amount0, rangeAmounts.amount1);
    params.tokenId = state.ranges[i].unstakedTokenId;
    (, TokenDelta rangeDelta) = PositionManagerLogic.increaseLiquidity(positionManager, params);
    delta = delta.add(rangeDelta);
}
```

**A mint only ever adds to the UNSTAKED side.** Never the staked side. That means every mint
dilutes the staked/unstaked ratio slightly toward unstaked — i.e. toward swap fees and away from
emissions. Deliberate (no penalty window risk on a user action), and it is why keepers periodically
run `INCREASE_STAKED_LIQUIDITY`.

Note `params.amount0Min`/`amount1Min` are left at **zero**. There is no slippage bound on the
position manager call. The protection is instead that the caller already transferred exactly
`amount0Desired`/`amount1Desired` and gets the unused token0 refunded. Confirm that logic in
`ALMCore.mint` during Trace 2 — specifically: **only token0 is refunded**, token1 is expected to be
consumed in full. Why? Because of how `getMintAmounts` rounds. That asymmetry is worth real
attention in Trace 2.

### `removeLiquidity` — the burn path, unstaked first

The logic, unwrapped from its nested blocks:

```
for each range i:
    unstakedLiquidity = positions(unstakedTokenId).liquidity           // LIVE
    fromUnstaked = toUint128((unstakedLiquidity + stakedLiquidity) * shares / supplyBefore)   // ROUNDS DOWN

    if fromUnstaked == 0:
        if unstakedLiquidity > 0: collect its fees
        continue

    if fromUnstaked > unstakedLiquidity:
        fromStaked   = fromUnstaked - unstakedLiquidity                // the overflow goes to the staked side
        fromUnstaked = unstakedLiquidity

    if fromUnstaked > 0: decreaseLiquidityAndCollect on the unstaked NFT
    if fromStaked   > 0: decreaseStakedLiquidity(..., windowOpen = false, emergency = false, penalty)
```

**Read the last line carefully:** it passes `windowOpen = false`. So a burn that has to reach the
staked side **ignores the penalty window** and forfeits the emissions. That is the price of
guaranteeing exits (invariant 8), and it is disclosed design — but it is also a griefing surface:
a large burn forces everyone else to eat the forfeited emissions.

Is that disclosed? Check §6 before writing anything. My read is that the "burns take the unstaked
side first" design is disclosed; whether the *specific* harm of a forced-forfeit burn is disclosed
is a different question. That distinction is exactly what judging rule §2 means by "an acceptance
applies only to the behavior and harm it covers".

**Rounding: `fullMulDiv` — rounds DOWN.** The burner gets less. Correct direction, mirror image of
`getMintAmounts`. Good.

### The view functions

**`getUnstakedPositions(ranges, bps, pool, positionManager)`** — used by `mint`:

```solidity
for each range:
    position = positionManager.positions(unstakedTokenId)
    if (position.liquidity == 0) continue
    positionLiquidity[i] = position.liquidity
    (gross0, gross1) = MetadexPositionValue.fees(pool, position)
    fees0 += gross0; fees1 += gross1

unchecked {
    fees0 -= fees0.fullMulDiv(bps, 10_000);     // protocol share, floored ONCE on the TOTAL
    fees1 -= fees1.fullMulDiv(bps, 10_000);
}
```

**Note the "floored once on the totals" comment.** `PoolTokensLib.creditCollected` floors the
protocol share on **each collection batch**, while this floors it on the **sum across all ranges**.
Those give different answers by up to 1 wei per range per token.

- `mint` values the core using *this* function.
- A plan credits the buffer using *that* function.

So the value a minter pays against and the value actually booked can disagree by a few wei. Which
direction? Flooring once on a larger number loses *less* dust than flooring 14 times on smaller
numbers, so this function reports **more** net fees → the core looks **richer** → a minter pays
**more**. That favours existing holders, which is the safe direction. **But verify my arithmetic**,
and then ask whether a mint timed immediately before/after a plan can exploit the gap in the other
direction. **Lead #3.**

**`getMintAmounts(ranges, positionLiquidity, sqrtPriceX96, shares, supplyBefore)`** — loops the
ranges calling `CLMath.getMintAmounts` per range, sums the desired totals, and fills a
`RangeAmounts[]` so `addLiquidity` knows each range's budget. Uses `positionLiquidity[i] +
stakedLiquidity` as the range's whole liquidity. Rounds **up** (via `CLMath`).

**`stakedTokenIds(ranges)`** — collects non-zero `stakedTokenId`s, truncates with
`DynamicArrayLib.truncate`. Used by `RewardsLib.getRewardTotals` to ask the gauge `earned(...)`.

**`claimableTokenIds(ranges, gauge, gaugeFactory, blockNumber)`** — same, but **skips** any range
inside its penalty window and returns `skipped = true` if it skipped one. Used by
`claimGaugeEmissions` so a claim never forfeits. Reads the penalty config **lazily** (only on the
first staked range found) — a small gas optimisation that also means **a core with no staked ranges
never reads the penalty config at all.**

**`unsafeAccess(ranges, index)`**:

```solidity
assembly { mstore(0x00, ranges.slot); range.slot := add(keccak256(0x00, 0x20), shl(1, index)) }
```

`keccak256(slot) + 2*index`, because `Range` is exactly 2 words. **No bounds check** — the name says
so. Every caller must already know `index < ranges.length`. Grep every caller and confirm. The loops
all use `i < length`, which is fine. `EmissionsLogic.getHiddenEmissions` uses
`i < state.ranges.length`, fine. Confirm there is no path where a payload-supplied index reaches
`unsafeAccess`. (The payload paths use `state.ranges[index]`, which **is** bounds-checked. Good —
but verify, because mixing the two is exactly the mistake that would be made.)

### Used where

`ALMCore`, `ALMKeeperExtension`, `EmissionsLogic`, `RewardsLib`, `State`.

### Audit notes summary for this file

- **Invariants 4 and 6 both live here.** Pass 2 spends 3-4 hours on this file alone.
- The live-unstaked-liquidity design means **a donation changes the core's value with no core
  transaction.** Anyone can `increaseLiquidity` on a core-owned non-gauge NFT. What does a donation
  do to a `mint` in the same block? To a `burn`? To a plan's shortfall check? Context doc §6 has a
  donation known issue — read it before reporting, then look for harm beyond what it covers.
- Four `unchecked` blocks here carry the bound *"within the pool's max liquidity per tick"*. That is
  an assumption about **Metadex**, not about this code. If Metadex's `maxLiquidityPerTick` can be
  exceeded (e.g. by the gauge adding liquidity outside the position manager), the bound breaks.
  Pass 3 external-assumptions sweep.

---

## C6. `QueueLib.sol` (604 lines) — the async request machine

**Budget three hours. This is where escrow correctness lives (invariants 2 and 3).**

### The model, in one picture

```
                 pendingEpoch (id = P)                 lastClearedEpoch (id = C)
                 +---------------------+               +---------------------+
requestDeposit-> | epochs[P].amountIn  | --clear-->    | epochs[C].amountIn  |
                 +---------------------+               | epochs[C].amountOut | <- settle writes this
                                                       +---------------------+
                                                                  |
                                                            creditSettled
                                                                  v
                                                       +---------------------+
                                                       | claimable[user]     |
                                                       |  .amountIn/.amountOut|
                                                       +---------------------+
                                                                  |
                                                             takeClaimable
                                                                  v
                                                            paid to the user
```

A user's position moves through four places: `records[user]` (one record, in some epoch) →
`epochs[id]` (batched with everyone else) → `claimable[user]` (settled, waiting) → paid out.

### Epoch ids and the "is it settled?" test

```solidity
function nextEpoch(Queue storage queue) internal view returns (uint32) {
    return uint32(max(queue.pendingEpoch, queue.lastClearedEpoch)) + 1;
}

function isPending(recordEpoch, pendingEpoch, amountIn) returns (bool) {
    return amountIn != 0 && recordEpoch == pendingEpoch;
}
function isSettled(recordEpoch, pendingEpoch, amountIn) returns (bool) {
    return amountIn != 0 && recordEpoch != pendingEpoch;
}
```

**The entire pending/settled distinction is "does my record's epoch id equal the current pending
id?"** Nothing else. No flags, no timestamps.

That is elegant and it is also the whole attack surface. Note:

- Epoch ids start at **0** (fresh storage). So the first pending epoch is 0, and a record in it has
  `epoch == 0 == pendingEpoch` → pending. Correct.
- After any clear, `pendingEpoch >= 1`, so an old record at epoch 0 reads as **settled**. Correct.
- `isSettled` accepts **any** epoch other than the pending one, including ids that were never
  cleared. Can a record end up in an epoch that is neither pending nor ever settled? `record()`
  always writes `record_.epoch = pendingEpoch`, and the clears move it to `lastClearedEpoch`. So no
  — **as long as every write goes through those two functions.** Grep for direct `record_.epoch =`
  assignments. I see them in `record`, `clearDeposit`, `clearRedeem`, `cancel` (→0) and
  `creditSettled` (→0). Check each.

### Two kinds of clear, and they behave differently

**Named clear** (`CLEAR_REQUESTS`, a list of controllers):

```solidity
startClearedEpoch(queue):  queue.lastClearedEpoch = nextEpoch(queue);   // a FRESH id

clearDeposit(state, deposits, record_, isToken0):
    uint128 assets = record_.amountIn;
    record_.epoch = deposits.lastClearedEpoch;
    unchecked {
        deposits.epochs[deposits.pendingEpoch].amountIn -= assets;      // out of pending
        deposits.epochs[lastClearedEpoch].amountIn += assets;           // into cleared
    }
    delta = single(isToken0, int128(assets));
    poolTokens.buffer.applyDelta(delta);          // escrow -> buffer
    poolTokens.escrowed.applyDelta(delta.neg());
```

The pending epoch **stays open** with everyone who was not named. A brand-new id becomes the cleared
epoch and only the named records move into it.

**Whole-queue clear** (`CLEAR_ALL_REQUESTS`):

```solidity
clearAllDeposits(state, deposits, isToken0, assets):
    delta = single(isToken0, assets.toInt128());
    poolTokens.buffer.applyDelta(delta);
    poolTokens.escrowed.applyDelta(delta.neg());

    uint32 pendingEpoch = nextEpoch(deposits);
    deposits.lastClearedEpoch = deposits.pendingEpoch;   // the OLD pending becomes the cleared one
    deposits.pendingEpoch     = pendingEpoch;            // a fresh id opens
```

Here the **old pending epoch becomes the cleared epoch wholesale** and a fresh id opens for pending.
No record is touched — every record in the old epoch automatically becomes "settled" by virtue of
`pendingEpoch` having moved.

**These two are not symmetric, and that asymmetry is a rich Pass 2 target.** Specifically:

- After a named clear, `lastClearedEpoch > pendingEpoch` (the cleared id is `max+1`).
- After a whole clear, `lastClearedEpoch < pendingEpoch` (the cleared id is the old pending).

So the relative order of the two ids **flips** depending on which clear ran. `nextEpoch` uses
`max(...)+1`, which handles both. But anything else that compares the two ids has to be correct for
both orders. Grep for comparisons of `pendingEpoch` and `lastClearedEpoch`. **If you find code that
assumes one ordering, that is a finding.** I consider this the single most promising structural
question in this file.

### Settlement

```solidity
function settleRedeems(state, redeems, isToken0, assets) returns (TokenDelta delta) {
    if (assets > (isToken0 ? buffer.amount0 : buffer.amount1)) revert InsufficientBuffer();
    delta = single(isToken0, -assets.toInt128());
    buffer.applyDelta(delta);          // buffer -> escrow
    escrowed.applyDelta(delta.neg());
    settleEpoch(redeems.epochs[redeems.lastClearedEpoch], assets);   // epoch.amountOut = assets
}
```

Deposits do not have a `settleDeposits` here — the shares side is handled in
`ALMKeeperExtension._settleDeposits` plus `settleEpoch`. Note the buffer check: **redeems are
settled before deposits in a plan** (`_settleRedeems` L735 then `_settleDeposits` L766) precisely so
the buffer is funded.

### Crediting — the pro-rata split

```solidity
function creditSettled(record_, epoch, claimable) returns (uint256 amountOut, uint256 pendingShares) {
    uint256 amountIn = record_.amountIn;
    pendingShares = record_.pendingShares;

    amountOut = requestAmountOut(amountIn, epoch.amountIn, epoch.amountOut);   // amountIn * out / in, FLOOR

    unchecked {
        epoch.amountIn  -= uint128(amountIn);
        epoch.amountOut -= uint128(amountOut);
    }
    claimable.amountIn  += uint128(amountIn);
    claimable.amountOut += uint128(amountOut);
    (record_.epoch, record_.amountIn, record_.pendingShares) = (0, 0, 0);
}
```

**Example.** An epoch took 1000 assets and settled into 700 shares. Three users: 500, 300, 200.

```
user A credits: 500 * 700 / 1000 = 350.  epoch becomes (500 in, 350 out)
user B credits: 300 * 350 /  500 = 210.  epoch becomes (200 in, 140 out)
user C credits: 200 * 140 /  200 = 140.  epoch becomes (  0 in,   0 out)
                                          total out = 700  exactly
```

The split is **re-derived from what remains each time**, not from the original totals. That is the
mechanism that makes the dust come out right: floors lose a wei here and there, and the **last
claimer absorbs the remainder**. No wei is stranded and none is created.

That is a genuinely good design. It also means **the order of claims changes who gets the dust.**
Is that exploitable? Only for sub-wei amounts per claim, so almost certainly Info — but see judging
rule 3.4.4 on replayable dust before dismissing it.

### `takeClaimable` — and one odd branch

```solidity
function takeClaimable(claimable, amountIn, maxAmountOut) returns (uint256 amountOut) {
    (claimableIn, claimableOut) = (claimable.amountIn, claimable.amountOut);

    if (amountIn > claimableIn || claimableIn == 0 && claimableOut == 0) revert InsufficientClaimable();

    amountOut = min(claimableIn == 0 ? claimableOut
                                     : requestAmountOut(amountIn, claimableIn, claimableOut),
                    maxAmountOut);

    unchecked {
        (claimable.amountIn, claimable.amountOut) =
            (toUint128(claimableIn - amountIn), toUint128(claimableOut - amountOut));
    }
}
```

Operator precedence: the guard is `(amountIn > claimableIn) || (claimableIn == 0 && claimableOut == 0)`.

So there is a reachable state: **`claimableIn == 0` but `claimableOut > 0`.** In that state the
guard passes only when `amountIn == 0`, and then `amountOut = claimableOut` — **the caller takes the
entire remaining output for zero input.**

How does that state arise? `claimableIn` hits zero when someone claims their full `amountIn` but
`claimableOut` was not fully consumed — which happens if `maxAmountOut` capped the output. So:
claim your full input with a tight `maxAmountOut`, leaving output behind; then claim again with
`amountIn = 0` and sweep it.

Is that a loss? The leftover output was *yours* either way, so sweeping it is arguably the intended
recovery path for a capped claim. The question is whether **someone else** can reach it, and whether
the `escrowed` ledger is decremented correctly both times. `claimRedeem` does
`escrowed.applyDelta(single(isToken0, -assets.toInt128()))` on the amount taken, so the escrow
tracks the output, not the input. Looks consistent. **Lead #5 — worth 30 minutes to close properly,
because invariant 2 is exactly about this.**

### The cast asymmetry

```solidity
// requestDeposit:
shareAccount.pendingShares += SafeCastLib.toUint128(pendingShares);     // SAFE cast

// requestRedeem:
shareAccount.pendingShares += uint128(shares);                          // UNSAFE cast
```

`shares` in `requestRedeem` is aLP the core already took into escrow, so it is bounded by the supply,
which is bounded by `totalCap` (a `uint128`). So the unsafe cast is *probably* fine. But it is an
inconsistency in a file where the author was otherwise careful, and `totalCap` can be **lowered**
(`lowerTotalCap`) while supply stays above it. Prove the bound or find the gap. **Lead #4.**

And in `record()`:

```solidity
record_.pendingShares = SafeCastLib.toUint96(record_.pendingShares + pendingShares);
```

That `uint96` is the packing constraint from `Record`. It is **known issues S50 / S54** — do not
report the cast. Look for a consequence those statements do not describe.

### Used where

`ALMCore`, `ALMKeeperExtension`, `ALMCoreViewLogic`, `State`, `ALMVaultAsync`.

### Audit notes summary

- **Invariant 2 (escrow) and invariant 3 (queue) both live here.** Pass 2 spends 3-4 hours.
- The two things to try hardest: (a) make the sum of all claims exceed `escrowed`, (b) make a
  settled payout **unclaimable**. For (b), look at what happens if a controller's record is in an
  epoch that gets cleared twice, or if `creditDeposit` is called when `epoch.amountIn == 0` but
  `record_.amountIn != 0` — `requestAmountOut` would divide by zero and the claim would revert
  **permanently**. Can that state be built? That is a durable denial of a user's funds, which under
  judging rule 3.4.3 is high severity. **This is the single highest-value question in this file.**
- `record()` reverts `ZeroAddress` on `controller == 0` and `ZeroAmount` on `amountIn == 0`. Good —
  but note it only checks `amountIn`, not `pendingShares`. A deposit so small it computes to zero
  pending shares is accepted. Harmless? Probably. Note it.

---

## C7. `EmissionsLogic.sol` (160 lines) — reading the gauge

### The four small functions

```solidity
isMintable(leafVoter)              -> chainStatus is Active or Sunset
getBlockNumber(arbBlockNumber)     -> ArbSys(0x64).arbBlockNumber() or block.number
getPenaltyConfig(gaugeFactory, g)  -> gaugeFactory.effectivePenaltyConfig(gauge)
isPenaltyWindowOpen(stakedBlock, config, blockNumber)
    -> config.penaltyRate > 0 && blockNumber < stakedBlock + config.minStakeBlocks
```

**`getBlockNumber` exists because Arbitrum has two block numbers.** `block.number` on Arbitrum
returns the *L1* block number; `ArbSys.arbBlockNumber()` returns the L2 one. The gauge counts
penalty windows in whichever one the chain's gauges use, so the core must match.

`arbBlockNumber` is a `bool` in `Config`, set once in the constructor from `CoreParameters`.
**Nothing in the code verifies it was set correctly for the chain.** The context doc says deployment
sets it. If it were wrong on an Arbitrum deployment, every penalty window calculation would be
compared against the wrong clock — windows would appear permanently open or permanently closed.
Note it as a deployment assumption (§4.3 off-chain components), not a code finding.

**`isPenaltyWindowOpen`'s docstring is a gift:**

> *"isPenaltyWindowOpen duplicates Gauge._applyPenalty's strict comparison, so it must be
> re-verified on every Metadex release."*

That is the team telling you: **this is a hand-copy of someone else's comparison.** A strict `<` vs
`<=` difference here means the core thinks a window is closed when the gauge thinks it is open — and
then a claim forfeits emissions. Go read the real `CLGauge._applyPenalty` and compare the operator.
**That is a 15-minute check with a clear, quantifiable impact. Do it.**

### `getHiddenEmissions` — the hard one

**What problem it solves.** If a range is inside its penalty window, the gauge will only pay a
fraction of what it has accrued. The core wants to credit aLP holders the *full* accrued amount
anyway (so the share price does not jump when windows close), but it must not credit money that
would be destroyed if someone claimed now. So it computes the **hidden** part: what the gauge is
currently withholding.

```solidity
// 1. read the penalty rate and the referral share
config = getPenaltyConfig(gaugeFactory, gauge);
(, share) = gaugeFactory.referralConfig(gauge);

// 2. take the pool's reward growth and advance it by what the voter projects
rewardGrowthGlobalX128 = pool.rewardGrowthGlobalX128();
if (stakedLiquidity > 0) {
    projected = leafVoter.projectedCumulativeRewardShare(gauge);
    last      = gauge.lastCumulativeRewardShare();
    if (projected > last) unchecked {
        rewardGrowthGlobalX128 += (projected - last).fullMulDiv(1 << 128, stakedLiquidity);
    }
}

// 3. for every staked range inside a window
for each range with stakedTokenId != 0:
    if (!isPenaltyWindowOpen(range.stakedBlock, config, blockNumber)) continue;
    windowEnd = max(windowEnd, range.stakedBlock + config.minStakeBlocks);

    unchecked {
        accrued = (pool.getRewardGrowthInside(tickLower, tickUpper, rewardGrowthGlobalX128)
                   - gauge.rewardGrowthInside(range.stakedTokenId)).fullMulDiv(range.stakedLiquidity, 1 << 128);
    }

    unchecked {
        visible = accrued - accrued * config.penaltyRate / MAX_PIPS;
        hidden += (accrued - accrued * share / MAX_PIPS) - (visible - visible * share / MAX_PIPS);
    }
```

### Simple example

```
accrued      = 1000 AERO for this range
penaltyRate  = 300000 / 1e6 = 30%
referral     =  50000 / 1e6 =  5%

visible = 1000 - 300 = 700                         what the gauge would pay before referral
net of referral: full    = 1000 - 50 = 950
                 visible =  700 - 35 = 665
hidden  = 950 - 665 = 285
```

So 285 AERO are currently withheld by the penalty. When the window closes, the gauge will pay the
full 950 and `hidden` drops to zero — and `RewardsLib` folds that drop into the high-water mark so
it is not double counted.

### Audit notes

- **Two deliberate wrapping subtractions.** `projected - last` is guarded by `if (projected > last)`.
  But `pool.getRewardGrowthInside(...) - gauge.rewardGrowthInside(tokenId)` is **unguarded** and the
  comment says *"the reward growth can underflow, what matters is its delta."* That is the same
  wrapping-counter pattern as `MetadexPositionValue`. Correct **if** both sides are the same wrapping
  counter. Is `gauge.rewardGrowthInside(tokenId)` a snapshot of the *same* counter the pool reports?
  If the gauge ever stores something normalised differently, the "delta" is garbage and `hidden`
  becomes astronomically large — which would spike `rewardPerShare`. **Worth verifying against the
  real gauge.**
- `accrued * config.penaltyRate` and `accrued * share` are in `unchecked` with the bound *"accrued
  is a real emission amount, scaled by rates of at most MAX_PIPS."* `accrued` is a `uint256` from a
  `fullMulDiv` — bounded by the gauge's real emissions, which is a plausible bound but **not
  enforced in this code**. If the wrapping subtraction above ever produced a near-2^256 value, this
  multiplication overflows silently. The two leads compound. **This is a real chain to pull on.**
- `windowEnd` is `uint48` and is `max`-ed across ranges. `stakedBlock + minStakeBlocks` is cast with
  `uint48(...)` **unchecked**. `minStakeBlocks` is admin-controlled on the gauge factory. A huge
  `minStakeBlocks` would make the sum exceed `uint48` and wrap to a small number — making `windowEnd`
  look *past* and closing windows that are open. **Lead.** Is `minStakeBlocks` bounded anywhere?
  Not in this codebase. §4.1 does not list the Metadex gauge admin as trusted.

---

## C8. `RewardsLib.sol` (361 lines) — the emissions accumulator

### The core idea: reward-per-share with a high-water mark

Classic "rewards per share" accounting, with two twists.

**Classic part.** There is a global accumulator `rewardPerShare`. Each account remembers the value
it was last credited at (`rewardPerSharePaid`). What you are owed is:

```
owed = yourShares * (rewardPerShare - yourRewardPerSharePaid) / 1e18
```

**Twist 1 — it is driven by LIFETIME emissions, not by received tokens.**

```solidity
total = rewards.claimedCumulative + netReceived + earnedAtGauge;    // getRewardTotals
```

`total` counts: everything ever claimed, plus what arrived since the last checkpoint, plus what is
**still sitting at the gauge unclaimed**. So the accumulator rises as emissions *accrue*, not when
they are *claimed*. That is what lets aLP holders earn continuously without a keeper claiming every
block.

**Twist 2 — a high-water mark that never decreases.**

```solidity
if (total > highWater) {
    unchecked { credit += total - highWater; }
    highWater = total;
}
```

Because `total` includes `earnedAtGauge`, it can **fall** — e.g. when a claim converts "earned" into
"received" and the two are measured slightly differently, or when a forfeit destroys accrued
emissions. The high water stops a fall from un-crediting anyone. Only *rises* above the previous
peak create new credit.

### The pre-credit mechanism

```solidity
if (windowEnd != 0) {
    (hidden, windowEnd) = EmissionsLogic.getHiddenEmissions(state, gauge, gaugeFactory, leafVoter);
    unchecked { hidden -= hidden.fullMulDiv(state.config.protocolEmissionFeeBps, 10_000); }

    unchecked {
        if (hidden < preCredited) highWater += preCredited - hidden;   // a DROP folds into high water
        else credit = hidden - preCredited;                            // a RISE is credited now
    }
    preCredited = hidden;
}
```

**Example.**

```
block 100: a range is staked.  hidden = 0,   preCredited = 0
block 120: emissions accrue.   hidden = 285, preCredited = 0   -> credit = 285   (pre-credited!)
           preCredited = 285
block 140: more accrue.        hidden = 400, preCredited = 285 -> credit = 115
           preCredited = 400
block 175: window closes.      hidden = 0,   preCredited = 400
           -> hidden < preCredited, so highWater += 400         (the real emissions now arrive via
              total, and the raised high water stops them being counted a second time)
           preCredited = 0
```

That is genuinely clever and genuinely fiddly. **Read
`docs/proofs/EmissionsLogic/getHiddenEmissions.derivation.md` against it.**

### `rewardPerShare` wraps on purpose

```solidity
unchecked { rewardPerShare = rewardPerShare + toUint128(credit.fullMulDiv(1e18, supply)); }
```

and on the read side:

```solidity
unchecked { amountReward = shares.fullMulDiv(accumulator - rewardPerSharePaid, 1e18); }
```

Both unchecked, both commented *"rewardPerShare can overflow/underflow, what matters is the delta."*
Standard for a `uint128` accumulator. **The hazard is an account that goes a full 2^128 without
being credited** — then the delta wraps past a whole cycle and the account is paid the wrong amount.
With `1e18` scaling and realistic emissions that is unreachable, but it is the standard question to
ask, and the answer belongs in your notes with the numbers that make it unreachable.

### `getRewardTotals` — the measured-balance trick

```solidity
received = rewardToken.balanceOf(address(this));
if (rewardPoolToken != 0) {
    (reserve0, reserve1) = state.poolTokens.getReserves();
    received -= rewardPoolToken == 1 ? reserve0 : reserve1;      // CHECKED: reverts on underflow
}
received -= rewards.lastRewardBalance;                           // CHECKED

protocolFee = received.fullMulDiv(bps, 10_000);                  // DOWN

tokenIds = state.ranges.stakedTokenIds();
earnedAtGauge = tokenIds.length == 0 ? gauge.deferredEmissions(address(this))
                                     : gauge.earned(address(this), tokenIds);
earnedFee = earnedAtGauge.fullMulDiv(bps, 10_000);
unchecked { netReceived = received - protocolFee; earnedAtGauge -= earnedFee; }
total = rewards.claimedCumulative + netReceived + earnedAtGauge;
```

**Both subtractions are outside `unchecked`**, so they revert on underflow. That is deliberate: if
the measured balance does not cover the pool-token reserves plus the last known reward balance,
something is wrong and the checkpoint should fail loudly rather than compute garbage.

**But a revert in `checkpoint` is serious.** `checkpoint` runs inside `RewardCheckpoint`, which runs
on **every aLP transfer, mint and burn**. So a state where `getRewardTotals` underflows **bricks the
whole share token** — and with no upgrade authority, permanently.

That makes this the highest-impact liveness target in the protocol:

> **Can you construct a state where `rewardToken.balanceOf(core) < reserves + lastRewardBalance`?**

Candidate angles: the reward token *is* a pool token (`rewardPoolToken != 0`) and the reserves grow
between a `pay` and a `checkpoint`; or a reward token with a transfer fee / rebasing; or
`lastRewardBalance` is raised by a `checkpoint` and then tokens leave by some other path. Under
judging rule **3.4.3** a permanent brick of transfers and burns is the **Critical** path. **This is
lead #8 and in my judgement the best single target in Pass 0.**

### `pay` — one line worth noting

```solidity
function pay(Rewards storage rewards, address rewardToken, address to, uint256 amountReward) internal {
    rewards.lastRewardBalance -= uint128(amountReward);     // unchecked cast, CHECKED subtraction
    rewardToken.safeTransfer(to, amountReward);
}
```

State before transfer. Correct ordering. The subtraction is checked, and both callers clamp
`amountReward` to `lastRewardBalance` with `min(...)` first, so it cannot underflow. Verified.

Note `payReward` transfers **even when `amountReward == 0`** (no guard), while `payProtocolFees`
guards with `if (amountReward > 0)`. An inconsistency; a zero-value `safeTransfer` is harmless for
normal ERC-20s but reverts for a few weird ones. Context doc pins the tokens, so Info at most.

### `accrueBalanceReward` — the core's own shares

```solidity
bool isCore = account == address(this);
uint128 rewardPerSharePaid = isCore ? rewards.protocolRewardPerSharePaid
                                    : rewards.rewardAccounts[account].rewardPerSharePaid;
...
if (isCore) { rewards.protocolFees += toUint128(amountReward); rewards.protocolRewardPerSharePaid = accumulator; }
else        { rewardAccount.rewardOwed += toUint128(amountReward); rewardAccount.rewardPerSharePaid = accumulator; }
```

The **core itself holds aLP** (that is why it is cap-exempt in `ShareLib`), and the rewards those
shares earn go to `protocolFees` instead of a user account. A second accumulator pointer
(`protocolRewardPerSharePaid`) tracks it. Two ledgers, one accumulator.

Early exit: `if (accumulator == rewardPerSharePaid) return;` — nothing accrued, nothing to do.

### `claimGaugeEmissions`

```solidity
(tokenIds, skipped) = state.ranges.claimableTokenIds(gauge, gaugeFactory, getBlockNumber(...));
if (tokenIds.length != 0 || gauge.deferredEmissions(address(this)) != 0) {
    gauge.claimEmissions(address(this), address(this), tokenIds);
}
```

Only claims for ranges **outside** their penalty window, so a claim never forfeits. The
`deferredEmissions` check means it still calls through when there are no claimable ranges but the
gauge is holding deferred amounts. `skipped` is returned but — check whether any caller uses it.
`payReward` ignores it. If nothing uses `skipped`, that is a dead return value worth a note.

### Used where

`State.sol` only (as the binding), then everywhere through `State`.

### Audit notes summary

- **Invariant 10 lives here.** Pass 2 spends 2 hours.
- The three things to attack: (a) make `highWater` decrease, (b) pay one account's credit to another,
  (c) **make `checkpoint` revert** (the big one, above).
- Six `unchecked` blocks, each with a stated bound. Four say "the protocol fee is at most half of X",
  which depends on `MAX_FEE_BPS = 5000` being enforced by the setter. Verify
  `ALMAdminExtension.setProtocolFees` (L229) actually enforces it — that single check is what makes
  four `unchecked` bounds true.

---

## C9. `CalldataLogic.sol` (350 lines) — decoding the keeper's payloads

### What it does

Keeper payloads are **tight-packed bytes**, not ABI-encoded, to save calldata gas. This file decodes
them with assembly. Every decoder starts by asserting an exact length.

### The length table — memorise the shape, not the numbers

| Constant | Bytes | Payload |
|---|---|---|
| `QUEUE_LENGTH` | 2 | whole-queue clear: `isToken0`, `isDeposit` |
| `CONTROLLER_LENGTH` | 20 | one address in a controller list |
| `COLLECT_LENGTH` | 12 | a token id |
| `CLOSE_RANGE_LENGTH` | 13 | index (1) + tokenId (10) ... |
| `DECREASE_LIQUIDITY_LENGTH` | 93 | index+tokenId + liquidity + mins + deadline |
| `UNSTAKE_LENGTH` | 94 | the same + 1 byte `acceptPenalty` |
| `OPEN_RANGE_LENGTH` | 134 | two ticks (3+3) + 4 x 32-byte amounts |
| `STAKE_LENGTH` | 141 | index+tokenId + 4 x 32 |
| `INCREASE_LIQUIDITY_LENGTH` | 141 | same shape |
| `INCREASE_STAKED_LIQUIDITY_LENGTH` | 142 | the same + 1 byte `acceptPenalty` |
| `SWAP_VIA_POOL_LENGTH` | 85 | bool + amountIn(32) + sqrtLimit(20) + minOut(32) |
| `SWAP_VIA_ROUTER_LENGTH` | 85 | router(20) + amountIn(32) + bool + minOut(32), then router calldata |

**The pattern that matters:** the *staked* variants are exactly **1 byte longer** than the unstaked
ones, and that byte is `acceptPenalty`. So `UNSTAKE_LENGTH = DECREASE_LIQUIDITY_LENGTH + 1` and
`INCREASE_STAKED_LIQUIDITY_LENGTH = INCREASE_LIQUIDITY_LENGTH + 1`.

```solidity
assertLength(payload, staked ? UNSTAKE_LENGTH : DECREASE_LIQUIDITY_LENGTH);
...
if (staked) acceptPenalty = readBool(payload, UNSTAKE_ACCEPT_PENALTY_OFFSET);  // offset 93
```

So the only way to set `acceptPenalty` is to send the longer payload with the staked opcode.
**Check: can the unstaked opcode ever be dispatched with `staked = true`, or vice versa?** That is a
one-line check in `_dispatch` and it is worth doing, because `acceptPenalty` is what lets a keeper
forfeit everyone's emissions.

### `readKey` — the index/tokenId pair

```solidity
function readKey(bytes calldata payload) internal pure returns (uint256 index, uint256 tokenId) {
    assembly {
        index   := shr(248, calldataload(payload.offset))        // 1 byte  -> 0..255
        tokenId := shr(160, calldataload(add(payload.offset, 1))) // 10 bytes -> uint80
    }
}
```

**This is the defence against swap-and-pop index drift** (see C5). The payload names both the index
and the token id it expects to find there. The handler then checks the range at `index` really holds
`tokenId`, and reverts if not.

`index` is 1 byte so up to 255, while `rangeCap <= 14`. Out-of-range indices are caught by Solidity's
own bounds check on `state.ranges[index]`. **Confirm every handler uses `state.ranges[index]` and
not `RangesLib.unsafeAccess`.** Mixing those two is exactly the mistake that would be made, and it
would turn a 1-byte payload field into an arbitrary storage write.

### `readBool` — correctly normalised

```solidity
flag := iszero(iszero(shr(248, calldataload(add(payload.offset, offset)))))
```

Any non-zero byte becomes `true`, exactly `1`. That matters because `TokenDeltaLib.single` does
`mul(128, isToken0)` and would be wrong for a bool holding, say, `2`. Verified safe.

### `decodeSwapViaRouter` — the only variable-length payload

```solidity
if (payload.length <= SWAP_VIA_ROUTER_LENGTH) revert InvalidPayload();   // strict >
assembly {
    router       := shr(96, calldataload(payload.offset))
    amountIn     := calldataload(add(payload.offset, 20))
    minAmountOut := calldataload(add(payload.offset, 53))
    data.offset  := add(payload.offset, SWAP_VIA_ROUTER_LENGTH)
    data.length  := sub(payload.length, SWAP_VIA_ROUTER_LENGTH)
}
zeroForOne = readBool(payload, 52);
```

**Overlapping reads.** `amountIn` is 32 bytes at offset 20 (so bytes 20..51). `zeroForOne` is 1 byte
at offset 52. `minAmountOut` is 32 bytes at offset 53 (bytes 53..84). Total 85. The offsets are
tight and non-overlapping — but `calldataload` always reads 32 bytes, so a mis-set offset would
silently read neighbouring fields rather than revert. **Verify each offset against the encoder in
the test suite or the off-chain keeper.** This is a 10-minute arithmetic check with a high payoff if
wrong, because `minAmountOut` is the swap's only slippage protection.

`router` is arbitrary — the keeper names it. It is called through `ROUTER_TRAMPOLINE`, which is the
containment. Read `_swapViaRouter` (L539) in Trace 4 to see what the trampoline enforces.

### `decodeControllers` — the modular length check

```solidity
unchecked {
    if (payload.length < QUEUE_LENGTH || (payload.length - QUEUE_LENGTH) % CONTROLLER_LENGTH != 0)
        revert InvalidPayload();
    count = (payload.length - QUEUE_LENGTH) / CONTROLLER_LENGTH;
}
```

Note `count` can legitimately be **zero** (a payload of exactly 2 bytes). A named clear with no
controllers would call `startClearedEpoch` (opening a fresh cleared epoch) and then clear nobody —
leaving an empty cleared epoch that a later settle would settle at zero. **Does that break anything?
Does `hasUnsettledEpochs` see it?** `setCleared` is only called with a non-zero amount, so probably
not — but trace it. **Lead.**

### `decodeCoreImmutables` — reading off the end of calldata

```solidity
function decodeCoreImmutables() internal pure returns (CoreImmutables memory immutables) {
    assembly {
        let posOfMetadataSize := sub(calldatasize(), 0x20)
        calldatacopy(immutables, sub(posOfMetadataSize, calldataload(posOfMetadataSize)), 0x120)
    }
}
```

In words: *"the last 32 bytes of calldata hold a length N. Go back N bytes from there, and copy
0x120 bytes (9 words) into memory."*

**Three things to notice:**

1. It copies a **fixed** `0x120` regardless of the declared `N`. So the declared length is used only
   to locate the start, not to bound the copy.
2. `calldatacopy` **zero-fills** past the end of calldata rather than reverting. So a malformed
   length gives you zeros, not a revert.
3. `sub(posOfMetadataSize, calldataload(...))` can **underflow** (it is raw assembly, no checks). A
   huge declared length wraps the offset, and `calldatacopy` from a huge offset returns 32 words of
   zeros.

So: if anyone can call a delegatecall-reachable function with calldata whose trailing word is
attacker-controlled, they get `CoreImmutables` of **all zeros** — meaning `pool == address(0)`,
`gauge == address(0)`, and critically `syncVault0 == syncVault1 == asyncVault0 == asyncVault1 ==
address(0)`.

**Who appends this metadata?** The core, in `_delegate` (L707) and `_delegateAdmin` (L740). And
`ALMSyncExtension` (a *vault* extension, staticcall-only) also imports `CalldataLogic`. So there are
two independent appenders that must produce the identical layout.

**The defence** is `BaseExtension._requireDelegated()` (`if (address(this) == SELF) revert`), which
stops anyone calling an extension directly. So reaching `decodeCoreImmutables` with hostile calldata
requires either (a) a core that appends wrongly, or (b) a path into an extension that is not
`onlyDelegated`.

**Go check (b) exhaustively.** Grep every external/public function in `ALMKeeperExtension`,
`ALMAdminExtension` and `ALMSyncExtension` and confirm each is either `onlyDelegated` or safe
without the immutables. **Lead #6, and it is the highest-severity-if-true item in this file** —
a zeroed `CoreImmutables` means the vault-identity checks compare against `address(0)`.

### Used where

`BaseExtension`, `ALMAdminExtension`, `ALMKeeperExtension`, `ALMSyncExtension`.

---

## C10. `PlanCache.sol` (423 lines) — the hardest file in the protocol

**This is where a keeper plan is measured and where async settlement is priced. Budget 4 hours,
and read `docs/proofs/PlanCache*/` alongside.**

### The struct

```solidity
struct PlanCache {
    uint256 openedRanges;        // bitmask: which ranges THIS plan opened
    uint256 supplyBefore;
    uint256 valueBefore;         // in token1 at the trusted price
    uint256 depositAssets0;      // cleared, not yet settled
    uint256 depositAssets1;
    uint256 redeemShares0;
    uint256 redeemShares1;
    uint256 blockNumber;         // the gauge's clock, cached once
    uint160 trustedSqrtPriceX96;
    uint160 spotSqrtPriceX96;
    int256  amount0;             // running total of token0 the plan holds
    int256  amount1;
    TokenDelta swapDelta;        // what the plan's swap moved
    CoreImmutables immutables;
}
```

It lives in **memory** for the duration of one `execute` call. Nothing here is persisted.

### Everything is valued in token1 at the trusted price

```solidity
function getValue(uint160 trustedSqrtPriceX96, int256 amount0, int256 amount1, bool roundUp)
    internal pure returns (uint256 value) {
    value = uint256(max(amount1, 0));
    if (amount0 > 0) value += CLMath.convert(trustedSqrtPriceX96, true, uint256(amount0), roundUp);
}
```

**A negative amount is valued at ZERO**, not as a debt. Both halves are floored independently.
Keep that in mind: a plan that is temporarily short token0 and long token1 is valued as if the
shortfall did not exist. That makes `valueAfter` an *over*-estimate in exactly the states where the
plan is unbalanced — which is the direction that would let a bad plan pass `checkShortfall`.
**Is that reachable?** The running `amount0`/`amount1` are the plan's holdings, and a plan that
genuinely ends short would fail `checkSolvency`. But `checkShortfall` runs on `getValueAfter()`,
and the ordering in `execute` is `checkSolvency` then `getValueAfter` then `checkShortfall`.
So solvency gates it. Satisfy yourself of that ordering — it is L140-ish in `ALMKeeperExtension`.

### `start` — the opening measurement

```solidity
cache.supplyBefore = supplyBefore;
unchecked { amount0 += state.poolTokens.buffer.amount0; amount1 += state.poolTokens.buffer.amount1; }
cache.valueBefore = amount1 + CLMath.convert(trustedSqrtPriceX96, true, amount0, false);   // DOWN
(cache.amount0, cache.amount1) = (toInt256(amount0), toInt256(amount1));
cache.blockNumber = EmissionsLogic.getBlockNumber(state.config.arbBlockNumber);
```

`amount0`/`amount1` arrive from `RangesLib.collectFees` (the sum of every range's principal) and the
buffer is added. **Uncollected fees are NOT in `valueBefore`** — they were just collected into the
buffer by `collectFees` in the same transaction, before `start` is called. Check that ordering in
`execute`: `collectFees` → `creditCollected` → `PlanCacheLib.start`. Yes, L108-112. So the buffer
already includes them. Good.

`valueBefore` rounds **down** — a lower starting value makes `checkShortfall` **easier** to pass.
Think about that. A plan is compared against a deliberately low baseline.

### `checkShortfall` — the one guard on plan quality

```solidity
unchecked {
    if (valueAfter.fullMulDiv(cache.supplyBefore, supplyAfter)
        < cache.valueBefore.fullMulDiv(10_000 - config.maxShortfallBps, 10_000))
        revert MaxShortfallExceeded();
}
```

In words: *"value per share after, scaled back to the old supply, must be at least
(1 - maxShortfallBps) times the value per share before."*

With `maxShortfallBps = 100` (1%, the production ceiling), **a keeper may destroy up to 1% of the
vault's value per plan**, and plans are rate-limited only by `minPlanInterval` (at most 1 day in
production). That is the trusted-keeper envelope. A finding that needs more than 1% per plan, or a
shorter interval than production uses, is out of scope. A finding that extracts value **within** 1%
repeatedly is very much in scope.

### The opened-ranges bitmask

```solidity
function openRange(cache, index)  { cache.openedRanges |= 1 << index; }

function closeRange(cache, index, lastIndex) {
    uint256 opened = cache.openedRanges;
    opened = (opened & ~(1 << index)) | (((opened >> lastIndex) & 1) << index);
    cache.openedRanges = opened & ~(1 << lastIndex);
}

function isOpenedRange(cache, index) returns (bool) { return ((cache.openedRanges >> index) & 1) != 0; }
```

This mirrors `RangesLib`'s swap-and-pop exactly: clear the closed bit, copy the last range's bit
into its place, clear the last bit. Correct.

**Why track it at all?** Because the `OPENED` sentinel (`uint96.max`) lets a later opcode in the
same plan say "the range I just opened" without knowing its index. `_rangeAt` (L925) resolves it.
And because a range opened in this plan has no history, so some checks can be skipped for it.

`index` goes up to 13 (`rangeCap <= 14`), so a `uint256` mask is ample.

### `getSettlementAmountsOut` — the single densest function in the codebase

This computes, for one plan: how many shares each deposit epoch mints, and how many assets each
redeem epoch pays. **Read it with the derivation doc open.** Here is the shape:

```
1.  depositValue0 = convert(depositAssets0 -> token1, DOWN)

2.  strip the swap and the deposits out of the plan's holdings
    amount0 = cache.amount0 - swapDelta.amount0() - depositAssets0
    amount1 = cache.amount1 - swapDelta.amount1() - depositAssets1
    redeemValue = getValue(..., DOWN)      // the EXISTING aLP's value, before the swap
    valueUp     = getValue(..., UP)

3.  value = redeemValue + (what the swap gained), floored at 0
    valueUp = value + valueUp - redeemValue + swappedUp - swapped     // carry both roundings

4.  revert ZeroValue if there are deposits but value == 0
    revert ZeroSupply if supplyBefore == 0

5.  provisional: assets0 = redeemShares0 * value / supplyBefore       (DOWN)
                 assets1 = redeemShares1 * value / supplyBefore       (DOWN)

6.  held0/held1 = what the plan still holds AFTER paying those redeems (zeroFloorSub)

7.  (depositLevy, redeemLevy) = getLevies(...)   -- args ordered by the swap's direction

8.  redeemValue = min(redeemValue, value + depositLevy + redeemLevy)
    valueUp    += depositLevy + redeemLevy

9.  recompute assets from redeemValue, then subtract each levy from the flow that paid it

10. shares0 = depositValue0 * supplyBefore / valueUp                  (DOWN)
    shares1 = depositValue1 * supplyBefore / valueUp                  (DOWN)

11. assets0 = convert(assets0 token1 -> token0, DOWN)
```

**Two rounding observations that are the whole fairness story:**

- Deposits divide by `valueUp` (the value rounded **up**) → fewer shares minted → existing holders
  favoured. Correct.
- Redeems multiply by `redeemValue`/`value` (rounded **down**) → fewer assets paid → existing
  holders favoured. Correct.
- Step 8's `min(redeemValue, value + levies)` caps redeems at **their value before the swap**. So a
  swap *gain* does not flow to redeemers — it stays with the remaining shares. That is a deliberate
  design decision (the context doc states it), and it is the kind of thing someone will try to
  report as unfair. It is disclosed. Do not.

### `getLevies` — charging the swap's cost to whoever needed it

```solidity
if (swapCost == 0 || swapped == 0 || heldIn + heldOut == 0) return (0, 0);

depositSwap = depositIn.fullMulDiv(heldOut, heldIn + heldOut);
redeemSwap  = redeemOut.fullMulDiv(heldIn,  heldIn + heldOut);
offset      = depositOut.fullMulDiv(heldIn, heldIn + heldOut)
            + redeemIn.fullMulDiv(heldOut,  heldIn + heldOut);

if (depositSwap + redeemSwap <= offset) return (0, 0);      // the flows cancelled out

levy       = swapCost.fullMulDivUp(min(depositSwap + redeemSwap - offset, swapped), swapped);
depositLevy = min(levy.fullMulDivUp(depositSwap, depositSwap + redeemSwap), depositIn);
redeemLevy  = min(levy.fullMulDivUp(redeemSwap,  depositSwap + redeemSwap), redeemOut);
```

### Simple example of why levies exist

A plan settles a deposit of 1000 token1 and a redeem paid in token0. The core holds mostly token1,
so to pay the redeem it must **swap token1 for token0**, and that swap costs (fee + slippage), say 5.

Without levies, that 5 would be borne by *all* aLP holders — including people who did nothing.
With levies, the 5 is charged to the deposit and the redeem that **made the swap necessary**, split
pro rata to how much of the swap each caused.

The `offset` term is the netting: if a deposit of token1 and a redeem paid in token1 arrive together,
they cancel and no swap was needed, so no levy.

**`swapCost` rounds UP** (`fullMulDivUp` throughout) → levies are charged generously → remaining
holders favoured. Correct direction.

**The caps** `min(..., depositIn)` and `min(..., redeemOut)` mean a levy can never exceed the flow
it is charged to, so a flow can be zeroed but never go negative.

### Audit notes summary

- This file plus `_settleEpochs` (L709) in the keeper extension is where I would spend the most time
  in the whole audit if I were hunting a High. The arithmetic is dense, the rounding is subtle, and
  **every statement in `docs/proofs/PlanCache/getLevies.derivation.md` and
  `docs/proofs/PlanCacheLib/getSettlementAmountsOut.derivation.md` is `leans_accepted` only** — a
  derivation the code contradicts decides nothing.
- Concrete things to try: a levy that exceeds the swap cost; a settlement where `valueUp < value`
  (which would mint *more* shares than the down-rounded value justifies); `held0 + held1 == 0` with
  a non-zero swap cost; a plan with deposits on both sides and redeems on both sides at once
  (all four flows non-zero), which is the branch most likely to be under-tested.
- `start`'s `unchecked` bound is *"the principal of every range plus a uint128 buffer fits 256
  bits."* 14 ranges of `uint256` principal plus a `uint128`. Each range's principal is bounded by
  `uint128` liquidity converted at a price — the comment elsewhere says "below 2^224 each". 14 x
  2^224 is about 2^228, plus 2^128, well inside 256 bits. Verified.
- `checkShortfall`'s `unchecked` bound is *"maxShortfallBps is at most BPS_DENOMINATOR"*, which again
  depends on the setter. Same single check as C8.

---

# PART D — The vault's math

## What problem this whole part solves

The core only accepts **both tokens**, in exactly the right ratio (`mint`). But most people hold
**one** token. The **sync vaults** fix that:

```
you give 1000 USDC
  -> vault swaps some USDC for ETH, on the pool
  -> vault now holds USDC + ETH in exactly the core's ratio
  -> vault calls core.mint()
  -> you get aLP
```

The hard part is "swaps **some**". How much? Too little and the leftover USDC cannot be minted. Too
much and you are left with excess ETH. The optimal amount depends on the price **after** the swap,
and the swap moves the price, and the core's own liquidity is part of what the swap trades against.

**So the vault simulates the pool's swap on-chain, step by step, with the core's position changing
along the way, and solves a quadratic for the exact stopping point.** That is Part D.

There is also a scope fact that changes how hard you should push here. **Statement S22 (decisive):**
the core, keeper plans and async request/cancel/claim must work in **every** pool state; the vaults'
single-token conversions only need to work in **normal states of a liquid pair**, and reverts or
worse rates there are **accepted**. So:

- "the sync vault reverts in a weird pool state" → **out of scope.**
- "the sync vault mints more shares than the assets justify, diluting holders" → **in scope.**

Push on *value leaving the core*, not on liveness.

---

## D1. `Snapshot.sol` (388 lines) — read the core once, then compute

### The struct

```solidity
struct Snapshot {
    uint256 buffer0; uint256 buffer1;      // the core's loose tokens
    uint256 fees0;   uint256 fees1;        // uncollected swap fees, NET of the protocol share
    uint256 supply;                         // aLP total supply
    uint160 sqrtPriceX96; int24 tick;       // the pool's price and tick
    uint24  fee;                            // the pool's fee FOR THIS CALLER
    IALMCore core;
    PricedRange[] ranges;
}
```

`PricedRange` is the vault's view of a range — ticks already converted to prices:

```solidity
struct PricedRange {
    uint128 liquidity;            // unstaked + staked
    uint128 unstakedLiquidity;    // just the unstaked part (earns fees)
    uint160 sqrtPriceLowerX96;
    uint160 sqrtPriceUpperX96;
}
```

### `getSnapshot(core, pool, vault)`

```solidity
(fees0, fees1, positionLiquidity) = core.getUnstakedPositions();
(buffer0, buffer1)                = core.getBuffer();
ranges                            = decodePricedRanges(core.readRangeWords(), positionLiquidity);
supply                            = core.totalSupply();
(sqrtPriceX96, tick, , , , )      = pool.slot0();
swapParams.caller = vault;
fee                               = pool.beforeSwapFee(swapParams);
```

**`beforeSwapFee(swapParams)` with `caller = vault` is the line to notice.** Metadex fees are
dynamic *and caller-dependent*. The vault asks "what fee will **I** be charged?" — because it is the
vault that will execute the swap.

**Immediate question for Pass 3:** the core's own swaps (`SWAP_VIA_POOL`) are executed by the
**core**, not the vault. Does anything read the fee with `caller = core`? `PoolLogic.tryFee()` reads
the static `fee()` instead. If the pool charges the core a different fee than the static one, the
keeper's cost model is wrong. **Worth a grep.**

`readRangeWords()` returns the **raw storage words** for the ranges, which `decodePricedRanges`
then hand-decodes using `ALMCoreViewLogic.decodeRange`. That is the extsload path — and it is why
the 20 bit-shift constants had to be right. (They are; see Part F.)

### `getFeeShare(snapshot, pool)`

```solidity
unchecked {
    feeShare = (1e6 - uint256(pool.unstakedFee())) * (1e4 - uint256(protocolSwapFeeBps));
}
```

**Two haircuts on the swap fee the core's unstaked liquidity earns:**

1. The pool's `unstakedFee` — Metadex diverts part of the fee from unstaked positions toward the
   gauge. This is the economic reason the core bothers staking at all.
2. The protocol's `protocolSwapFeeBps`.

Result has 10 decimals of precision (1e6 x 1e4). Used by `SwapStateLib.getStepFees` to work out how
much of each step's fee the core keeps — which matters because **the core earning fees during the
vault's own swap changes the answer.** That feedback loop is why `accrueFees` exists.

Note it reads `protocolSwapFeeBps` by raw `extsload` with a shift, not through a getter. That shift
is `SWAP_FEE_BPS_SHIFT = 24`. Verified correct in Part F.

### `getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, zeroForOne)`

```solidity
unchecked {
    (lower, upper) = CLMath.getBand(sqrtPriceX96, (maxSwapCostBps * 100).zeroFloorSub(fee) * 5e11);
    return uint160(zeroForOne ? lower : upper);
}
```

The price past which a swap would cost more than the core allows. Unit chase:

```
maxSwapCostBps * 100  -> converts bps (1e-4) to the pool's fee units (1e-6)
.zeroFloorSub(fee)    -> the cost budget BEYOND the pool's fee (floored at 0)
* 5e11                -> 1e-6 -> 1e18 would be *1e12; *5e11 is HALF that
```

The halving is because **a given cost in price is half as much in sqrt price**. The docstring says
exactly that: *"half the cost beyond the fee in square root price."* Consistent.

**Note `zeroFloorSub`:** if the pool's fee alone already exceeds `maxSwapCostBps * 100`, the budget
is zero, the band collapses to the spot price, and **no swap is permitted at all**. On a
dynamic-fee pool in a volatile moment, that makes the sync vault revert. Per S22 that is accepted
(liveness in an abnormal state). Do not report it; do note it, because it means the sync vault has a
fee-dependent off switch.

### `getRounding(snapshot, sqrtPriceX96, isToken0)`

```solidity
unchecked {
    maxRounding = snapshot.ranges.length
        * ((isToken0 ? uint256(1 << 96).divUp(sqrtPriceX96) : sqrtPriceX96.divUp(1 << 96)) + 2) + 1;
}
```

**This is the single most important function for finding bugs in Part D.** It is the vault's claim
about *how far wrong* its own arithmetic can be, and every preview and max function adds or
subtracts it as a safety margin.

The docstring explains the terms:

> *"Per range: liquidity floor < u, amount floor < 1, second position < 1. Buffer floor < 1."*

So per range: one liquidity unit's worth of the token (that is the `1<<96 / sqrtPrice` term, the
value of one unit of liquidity), plus 2 wei for two ceilings. Then `+1` for the buffer's floor.

**If this bound is too small, the vault's margins are too thin, and a preview can over-report.**
That is a direct dilution path. Attack it:

- Does `+2` really cover both ceilings in every branch of `getMintAmounts` / `getBurnAmounts`?
- `getBurnAmounts` does **two** `getAmountsForLiquidity` calls per range (unstaked then staked), so
  **two** floors per range per token. Does `+2` cover two floors *and* the liquidity unit? The
  comment says "second position < 1", so they counted it. Verify by construction.
- `divUp(sqrtPriceX96)` with a tiny `sqrtPriceX96` gives a huge margin; with a huge one it gives
  `1`. At the extreme, `uint256(1<<96).divUp(sqrtPrice)` can be 0 if... no, `divUp` of a non-zero
  numerator is at least 1. Fine.
- The whole expression is `unchecked`. `ranges.length <= 14`, and the inner term is at most
  `2^96 / 1` = 2^96, so the product is at most about 2^100. No overflow. Verified.

**`docs/proofs/ALMVaultSync/roundingMargins.derivation.md` (6 statements) is the proof document for
this. It is `leans_accepted` only. Read it against the code.**

### `getMintAmounts` / `getMintShares` / `getBurnAmounts`

These are the vault's **mirror** of the core's mint and burn maths. They must agree with
`RangesLib` + `CLMath` or the vault will hand the core the wrong amounts.

`getMintAmounts` — rounds **UP** (mirrors the core), and adds a margin:

```solidity
liquidityDelta = toUint128(range.liquidity.fullMulDivUp(shares, supply));          // UP
(rangeAmount0, rangeAmount1) = CLMath.getAmountsForLiquidityRoundingUp(...);       // UP
...
if (zeroForOne) idle0 += ranges.length; else idle1 += ranges.length;               // +n margin on tokenIn
amount0 += idle0.fullMulDivUp(shares, supply);                                     // UP
amount1 += idle1.fullMulDivUp(shares, supply);
```

It also accumulates `activeLiquidityDelta` — the mint's liquidity in the ranges the swap's first
step will trade against. That matters because **the mint adds liquidity that the swap then trades
against**, so the swap's effective liquidity is not the pool's current liquidity.

Note the in-range test differs by direction:

```solidity
zeroForOne ? lower <  sqrtPrice && sqrtPrice <= upper
           : lower <= sqrtPrice && sqrtPrice <  upper
```

The boundary is inclusive on the side the price is moving *away* from. That is the standard V3
convention and getting it backwards is a classic off-by-one. **Check both directions against the
pool's own tick-crossing rule.**

`getBurnAmounts` — rounds **DOWN**, and crucially **mirrors the unstaked-first rule**:

```solidity
uint128 fromUnstaked = uint128(min(liquidityDelta, range.unstakedLiquidity));
liquidityDelta -= fromUnstaked;
(released0, released1) = CLMath.getAmountsForLiquidity(..., fromUnstaked);     // first position
amount0 += released0; amount1 += released1;
(released0, released1) = CLMath.getAmountsForLiquidity(..., liquidityDelta);   // second position
amount0 += released0; amount1 += released1;
```

**Two separate floor operations per range** — because the core really does two separate
`decreaseLiquidity` calls. Splitting the calculation the same way is what makes the vault's estimate
match reality. This is where the "second position < 1" term in `getRounding` comes from.

`getMintShares` — the inverse: given balances, how many shares do they mint?

```solidity
(amount0, amount1) = (amount0.zeroFloorSub(getRounding(snapshot, sqrtPrice, true)),
                      amount1.zeroFloorSub(getRounding(snapshot, sqrtPrice, false)));
...
shares = type(uint256).max;
if (cost0 > 0) shares = amount0.fullMulDiv(snapshot.supply, cost0);
if (cost1 > 0) shares = min(shares, amount1.fullMulDiv(snapshot.supply, cost1));
```

It subtracts the rounding margin from both balances **first**, then takes the minimum over the two
tokens — "limited by the scarcer token". Conservative in both directions. Good.

### Audit notes

- **The whole file is a shadow implementation of the core's accounting.** Every divergence between
  `Snapshot` and `RangesLib`/`CLMath` is a candidate finding. Diff them function by function:
  `Snapshot.getMintAmounts` vs `RangesLib.getMintAmounts`, `Snapshot.getBurnAmounts` vs
  `RangesLib.removeLiquidity`. **This is a mechanical, high-yield exercise and it is the thing I
  would do first in Part D.**
- `getAmountsAt` sums ranges with `CLMath.getAmountsForLiquidity` (DOWN) and adds `idle`. It does
  **not** apply `getRounding`. Callers must. Check they do.
- `idle()` returns `buffer + fees`. So the vault counts **uncollected** fees as part of the core's
  value. The core's own `mint` does the same (`ALMCore.mint` uses `buffer + fees`). Consistent.
  But `fees` here is already net of the protocol share (from `getUnstakedPositions`), floored once
  on the total. See lead #3 — the same dust question, now mirrored in the vault.

---

## D2. `EquivalentPositionMath.sol` (125 lines) — 14 ranges collapsed into 1

### The trick

Simulating a swap against 14 separate ranges would be 14x the work per step. But over any price
interval where **no range edge is crossed**, all 14 ranges plus the idle tokens behave *exactly*
like **one** position:

```
amount0 = L * 2^96 / sqrtPrice  -  constant0
amount1 = L * sqrtPrice / 2^96  -  constant1
```

valid until the price reaches `sqrtPriceBound` — the nearest range edge in the swap's direction.

### How the fold works

```solidity
// idle tokens are constant amounts -> fold into the constants (negated)
position.constant0 = -toInt256(idle0);
position.constant1 = -toInt256(idle1);
position.sqrtPriceBound = PoolLogic.sqrtPriceLimit(zeroForOne);     // start at the extreme

for each range with liquidity > 0:
    // tighten the bound to this range's nearest edge in the step's direction
    if (zeroForOne) { edge = upper < sqrtPrice ? upper : lower;
                      if (edge < sqrtPrice && edge > bound) bound = edge; }
    else            { edge = lower > sqrtPrice ? lower : upper;
                      if (edge > sqrtPrice && edge < bound) bound = edge; }

    if (range is IN range at sqrtPrice) {
        position.liquidity         += liquidity;
        position.unstakedLiquidity += range.unstakedLiquidity;
        position.constant0 += int256(liquidity.fullMulDiv(1 << 96, upper));    // the formula's offset
        position.constant1 += int256(liquidity.fullMulDivN(lower, 96));
    } else if (sqrtPrice <= lower) {
        // range is entirely above: holds a FIXED amount of token0
        amount0 = liquidity.fullMulDiv(1<<96, lower) - liquidity.fullMulDiv(1<<96, upper);
        position.constant0 -= int256(amount0);
    } else {
        // range is entirely below: holds a FIXED amount of token1
        amount1 = liquidity.fullMulDivN(upper - lower, 96);
        position.constant1 -= int256(amount1);
    }
```

### Simple example

Suppose the price is 100 and the core has:

- 50 loose token0 and 200 loose token1 (idle)
- range A `[90, 110]` with liquidity 1000 — **in range**
- range B `[120, 130]` with liquidity 500 — **above** the price, so pure token0

Then:

```
constant0 starts at -50,  constant1 starts at -200
range A: liquidity 1000;  constant0 += 1000*2^96/110;  constant1 += 1000*90/2^96
range B: holds a fixed X token0;  constant0 -= X
bound (if buying token0, price rising): the nearest edge above 100 is 110 (A's upper)
```

Now `amountsAt(position, s, zeroForOne)` evaluates the whole core at any price `s` up to 110 with
**two multiplications**, instead of looping 14 ranges. When the swap reaches 110, the caller calls
`getPosition` again to rebuild for the next interval — that is `SwapStateLib.crossTick`'s last step.

### `amountsAt`

```solidity
int256 own0 = int256(position.liquidity.fullMulDiv(1 << 96, sqrtPriceX96)) - position.constant0;
int256 own1 = int256(position.liquidity.fullMulDivN(sqrtPriceX96, 96))     - position.constant1;
(amount0, amount1) = (uint256(max(own0, 0)), uint256(max(own1, 0)));        // floor at zero
```

**Both amounts are floored at zero independently**, same as `PlanCache.getValue`. So in a price
region where the formula would give a negative amount for one token, it reports zero rather than a
debt.

### Audit notes

- **The `sqrtPriceBound` logic is where I would look hardest.** It must be the *nearest* edge in the
  direction of travel, strictly past the current price. If it ever returned an edge the price
  already passed, the equivalent position would stay stale across a range boundary and every amount
  after that point would be wrong — silently, with no revert.
  - `zeroForOne` (price falling): `edge = upper < sqrtPrice ? upper : lower`, then
    `if (edge < sqrtPrice && edge > bound) bound = edge`. So it picks the largest edge strictly
    below the price. Looks right.
  - `oneForZero` (price rising): `edge = lower > sqrtPrice ? lower : upper`, then
    `if (edge > sqrtPrice && edge < bound) bound = edge`. Smallest edge strictly above. Looks right.
  - **Edge case to test: a range whose edge lands exactly ON `sqrtPrice`.** Both tests are strict
    (`<` / `>`), so such an edge is **not** chosen as a bound. Is that correct? If the price sits
    exactly on a range boundary, that range's in-range test (`lower < s && s <= upper` or
    `lower <= s && s < upper`) decides which side it counts on — and the two are asymmetric by
    direction. Convince yourself the bound and the in-range test agree at the boundary for **both**
    directions. **If they disagree, you have a real finding.** This is my pick for the highest-value
    half hour in D2.
- `int256(liquidity.fullMulDiv(1 << 96, upper))` — an unchecked cast from `uint256` to `int256`
  inside `unchecked`. `liquidity <= uint128.max` and `2^96/upper <= 2^96`, so the product is at most
  about 2^224. Safe. Verified.
- `int256(amount0)` in the out-of-range branches is **not** inside the `unchecked` that covers the
  in-range branch — check which block each is in; the file has three separate `unchecked` blocks.

---

## D3. `SwapState.sol` (235 lines) — walking the pool's swap

### What it does

Replays the pool's swap loop, step by step, carrying the core's equivalent position along.

```solidity
struct SwapState {
    uint160 sqrtPriceX96; int24 tick; uint128 liquidity;   // the pool's state, as it moves
    int24 tickSpacing; uint24 fee;
    uint256 feeShare;                                       // the core's share of fees kept
    uint256 amountIn;  uint256 amountOut;                   // running totals
    EquivalentPosition position;                            // the core, at this price
}

struct StepComputations {
    int24 tickNext; bool initialized;
    uint160 sqrtPriceNextX96;   // price at tickNext
    uint160 sqrtPriceTargetX96; // where this step actually swaps to (next price, clamped to the limit)
    uint256 amountIn; uint256 amountOut; uint256 feeAmount;
}
```

### The loop, in five calls

Every caller in D4-D7 runs the same shape:

```solidity
SwapState memory state = SwapStateLib.getSwapState(snapshot, pool, zeroForOne);
StepComputations memory step;
while (<not done>) {
    step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);   // 1. where does this step end?
    state.computeSwapStep(step, zeroForOne, roundUp);               // 2. what does it cost/pay?
    state.accrueFees(snapshot, zeroForOne, state.getStepFees(step, roundUp));  // 3. core earns fees
    if (!state.crossTick(step, snapshot, pool, zeroForOne, limit)) break;      // 4. move + cross
}
```

### `setNextTick`

```solidity
(step.tickNext, step.initialized) = MetadexTickBitmap.nextInitializedTickWithinOneWord(pool, state.tick, state.tickSpacing, zeroForOne);
if (step.tickNext < TickMath.MIN_TICK) step.tickNext = TickMath.MIN_TICK;
else if (step.tickNext > TickMath.MAX_TICK) step.tickNext = TickMath.MAX_TICK;
step.sqrtPriceNextX96   = TickMath.getSqrtPriceAtTick(step.tickNext);
step.sqrtPriceTargetX96 = SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, sqrtPriceLimitX96);
```

The clamp comment says *"as the pool's swap does"* — another hand-copy of the pool's behaviour, so
another thing to verify against the real Metadex pool.

### `computeSwapStep` — note this is NOT the vendored one

```solidity
step.amountIn = zeroForOne ? SqrtPriceMath.getAmount0Delta(target, price, liquidity, roundUp)
                           : SqrtPriceMath.getAmount1Delta(price, target, liquidity, roundUp);
unchecked {
    step.feeAmount = roundUp ? step.amountIn.fullMulDivUp(fee, 1e6 - fee)
                             : step.amountIn.fullMulDiv(fee, 1e6 - fee);
}
step.amountOut = zeroForOne ? SqrtPriceMath.getAmount1Delta(target, price, liquidity, false)
                            : SqrtPriceMath.getAmount0Delta(price, target, liquidity, false);
```

**Two versions of the step calculation exist in this codebase:**

| | `MetadexSwapMath.computeSwapStep` | `SwapStateLib.computeSwapStep` |
|---|---|---|
| Rounding | always against the swapper | caller chooses via `roundUp` |
| Input | handles exact-in and exact-out | always "swap the whole interval" |
| Fee | the "whole remainder" rule when short | always a proportional fee |
| Used by | `MintOptimizationMath`, `RedeemOptimizationMath` | `DepositOptimizationMath`, `MintOptimizationMath`, `maxMint`, `maxDeposit` |

**That difference is deliberate and it is a prime confusion source.** The `roundUp` version is used
when the code needs an *optimistic or pessimistic bound* to drive a search; the vendored version is
used when the code needs to match the pool *exactly*. **Check every call site: is it using the
version whose rounding matches what it needs?** A single swapped call would bias every preview in
one direction. **High-value, mechanical check.**

Note `feeAmount` uses `fee / (1e6 - fee)` — the fee is computed **on top of** the net input, which
is the correct inversion of the pool's "fee taken from the gross input".

### `getStepFees` and `accrueFees` — the feedback loop

```solidity
feesIn = (step.feeAmount * state.feeShare).fullMulDiv*(state.position.unstakedLiquidity, 1e10 * state.liquidity);

// accrueFees:
if (zeroForOne) { state.position.constant0 -= toInt256(feesIn); snapshot.fees0 += feesIn; }
else            { state.position.constant1 -= toInt256(feesIn); snapshot.fees1 += feesIn; }
```

The core's unstaked liquidity is part of the pool's liquidity, so **the vault's own swap pays fees
to the core**, which makes the core slightly richer, which changes how many shares the mint produces.
`accrueFees` folds that into both the snapshot *and* the equivalent position's constants, so later
steps see it.

**Subtle and important:** it mutates `snapshot` — the same `Snapshot memory` the caller holds. So
`previewDeposit` ends with a snapshot whose `fees0`/`fees1` include the fees its own simulated swap
earned. That is intended (the docstring on `computeSwap` says *"whose fees rise by those the swap
earns the core"*), but it means **the snapshot is not reusable** across two independent
calculations. Check that no caller reuses one. **Concrete lead.**

Division by `state.liquidity`: if `state.liquidity` were 0 this divides by zero. The loops are
guarded by `while (state.liquidity > 0)` in most callers — but `MintOptimizationMath.computeSwap`
has `while (amountMintOut > state.amountOut && state.liquidity > 0)`, and `accrueFees` is called
**inside** the loop body after `computeSwapStep`. So liquidity is non-zero there. In
`DepositOptimizationMath.computeSwap` the guard is also `while (state.liquidity > 0)`. Verified —
but note `crossTick` can set `state.liquidity` to 0 mid-loop, and the *next* iteration's guard
catches it. Confirm `accrueFees` is never called after `crossTick` within the same iteration.
Looking at `DepositOptimizationMath`: `accrueFees` then `crossTick`. Correct order. Verified.

### `crossTick`

```solidity
state.sqrtPriceX96 = step.sqrtPriceTargetX96;
state.amountIn  += step.amountIn + step.feeAmount;
state.amountOut += step.amountOut;

if (state.sqrtPriceX96 != step.sqrtPriceNextX96 || state.sqrtPriceX96 == sqrtPriceLimitX96) return false;
if (step.initialized) {
    liquidityNet = PoolLogic.liquidityNet(pool, step.tickNext);
    state.liquidity = toUint128(toUint256(int256(uint256(state.liquidity)) + (zeroForOne ? -liquidityNet : liquidityNet)));
}
state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;

if (state.sqrtPriceX96 == state.position.sqrtPriceBound) {
    state.position = snapshot.getPosition(state.sqrtPriceX96, zeroForOne);   // REBUILD
}
return true;
```

Three things:

1. The `return false` condition: *"the step did not reach the next tick"* (the swap ended inside the
   step) **or** *"we hit the price limit"*. Either way the walk stops.
2. `state.tick = zeroForOne ? tickNext - 1 : tickNext` — the classic V3 asymmetry. When the price
   falls through a tick you land *below* it. Off-by-one heaven.
3. **The position is only rebuilt when the price exactly equals `position.sqrtPriceBound`.** If the
   price jumps *past* the bound without landing on it, the position is **not** rebuilt and goes
   stale. Can that happen? `getPosition` sets the bound to a range edge, and range edges are at
   ticks, and the walk stops at every initialised tick — so the price should land exactly on the
   bound. **Unless a range edge is at a tick that is not initialised in the pool's bitmap.** Can
   that happen? A range's position is minted through the position manager, which initialises its
   ticks... but if all liquidity at that tick is later removed, is the tick de-initialised while the
   core's range still has it as an edge? The core's own position holds liquidity there, so no.
   **But what about a range whose liquidity is zero on both sides?** `getPosition` skips
   `liquidity == 0` ranges entirely, so no bound from them. Consistent.
   **Still — this is lead #9, and it is the kind of thing that is either airtight or a High.**
   Spend the half hour.

---

## D4. `MintOptimizationMath.sol` (230 lines) — the buy that covers a mint

### The problem

`mint(shares)`: the user names the shares they want. The vault must buy exactly enough tokenOut to
cover what the mint will take, and the amount the mint takes **depends on the price after the buy**.

### `computeSwap` — the shape

```solidity
state = getSwapState(snapshot, pool, zeroForOne);
state.feeShare = snapshot.getFeeShare(pool);
(amountMintOut, activeLiquidityDelta) = getMintAmountOut(snapshot, snapshot.sqrtPriceX96, zeroForOne, shares);

while (amountMintOut > state.amountOut && state.liquidity > 0) {
    step.setNextTick(...);
    state.computeSwapStep(step, zeroForOne, true);                      // optimistic walk

    amountMintOutDelta = <how much the mint's need DROPS over this step>;

    if (state.amountOut + step.amountOut + amountMintOutDelta >= amountMintOut) {
        // the buy covers the mint inside THIS step: solve exactly, with an EXACT-OUTPUT step
        (...) = MetadexSwapMath.computeSwapStep(
            state.sqrtPriceX96, step.sqrtPriceTargetX96, state.liquidity,
            -toInt256((amountMintOut - state.amountOut)
                      .fullMulDivUp(state.liquidity, state.liquidity + activeLiquidityDelta)),
            state.fee);
    }
    amountMintOut = amountMintOut.zeroFloorSub(amountMintOutDelta);

    state.accrueFees(snapshot, zeroForOne, state.getStepFees(step, true));

    sqrtPriceBound = state.position.sqrtPriceBound;
    if (!state.crossTick(...)) break;
    if (state.sqrtPriceX96 == sqrtPriceBound) {
        (amountMintOut, activeLiquidityDelta) = getMintAmountOut(snapshot, state.sqrtPriceX96, zeroForOne, shares);
        if (amountMintOut == 0) amountMintOut = 1;       // <<< force at least a wei
    }
}
```

### Why the mint's need *drops* as the price moves

As the price moves, the composition the core wants changes. Buying token1 (price falling) means the
core's ranges hold more token1 and less token0, so a mint of the same shares needs **less** token1
than it did at spot. `amountMintOutDelta` is exactly that drop, computed from the mint's own
liquidity (`activeLiquidityDelta`) over the step.

### The two lines to stare at

**1. The liquidity scaling inside the exact-output solve:**

```solidity
(amountMintOut - state.amountOut).fullMulDivUp(state.liquidity, state.liquidity + activeLiquidityDelta)
```

The mint's liquidity gets added to the pool, so to buy `y` tokenOut from the *combined* liquidity
you only have to push the price as far as buying `y * L / (L + K)` from the pool alone. The comment
writes it as `y = (need - bought) - K*y/L`. Rounded **up** — a slightly larger buy. Which direction
does that favour? Think it through; it belongs in your rounding table.

**2. `if (amountMintOut == 0) amountMintOut = 1;`**

Comment: *"Spot moves to the edge only with a buy, of at least a wei."* A guard against an infinite
loop / zero-progress state at a range edge. It also means **the loop always buys at least one wei
past an edge.** Is that always harmless? At 14 range edges that is up to 14 wei of extra buying.
Covered by the margins? `maxMint`'s rounding budget includes `+ steps`, so they counted it.
Verify the count matches the worst case.

### `maxMint` — the rounding budget is the interesting part

```solidity
uint256 rounding = snapshot.getRounding(snapshot.sqrtPriceX96, !zeroForOne) + steps;

if (!zeroForOne) {
    uint256 priceX96 = uint256(snapshot.sqrtPriceX96).fullMulDivN(snapshot.sqrtPriceX96, 96);
    if (priceX96 == 0) return 0;                              // J0 == 0 -> unbounded rounding
    uint256 roundingSpot = amountMintOutSpot.divUp(priceX96);
    amountMintOutEnd += 2 * roundingSpot + roundingSpot.divUp(priceX96);
    uint256 roundingUnit = uint256(1 << 96).divUp(snapshot.sqrtPriceX96).divUp(priceX96);
    rounding += snapshot.ranges.length * (2 * roundingUnit + roundingUnit.divUp(priceX96) + 1) + 2;
}
rounding += 2;                                                 // the buy's last wei
if (state.amountOut <= rounding) return 0;
shares = (state.amountOut - rounding).fullMulDiv(snapshot.supply, amountMintOutEnd + 1);
```

The `!zeroForOne` branch exists because **token0 amounts divide by `J = floor(s^2 / 2^96)`** (see
`CLMath.getAmount0ForLiquidityRoundingUp`), so each token0 amount can be up to `1/J0` above exact.
The code reconstructs that error term explicitly: `C_hat = C + 2A + ceil(A/J0)` with `A = ceil(C/J0)`.

**This is the most elaborate rounding budget in the codebase, and `maxMint` is a *view* that users
and integrators rely on.** Two distinct questions:

- Is the budget **large enough**? Too small and `maxMint` over-reports, a mint at that size reverts,
  and integrators break. Per S22 a revert is accepted, so this is low value.
- Is the budget **so large** that `maxMint` under-reports badly? Also low value.
- **But:** is there any path where these margins are *subtracted from a payout* rather than from a
  bound? That would be real value loss. Grep where `getRounding` feeds a payout vs a limit.
  In `maxWithdraw` (D7) it feeds `roundingMarginIn`/`roundingMarginOut` which **reduce the reported
  payout** — a view, so still a bound. Check `_swapAndMint` / `_burnAndSwap` in Trace 7/8 for the
  real payout path.

`steps` is counted in the loop and added as 1 wei per step. **The number of steps is bounded by the
tick range walked**, which is bounded by the swap cost limit. Fine.

---

## D5. `DepositOptimizationMath.sol` (488 lines) — the hardest file in Part D

### The problem

`deposit(assets)`: the user gives one token. Swap **how much** of it so that what remains plus what
was bought lands in exactly the core's ratio?

### The answer: solve a quadratic

```
(alpha * m - kappa * delta) * (epsOut - omega * delta)
    = (beta + delta) * (epsIn + (omega + rho - epsIn) * delta),    m = 1 - delta
```

which expands to `A*d^2 - B*d + C = 0` with

```
A = (alpha + kappa - 1) * omega + epsIn - rho
B = C + (alpha + beta) * omega + kappa * epsOut + epsIn + beta * rho
C = alpha * epsOut - beta * epsIn
rho = (kappa - 1) * phi * omegaU          the fee the core's unstaked liquidity earns on the step
kappa = 1 / (1 - fee)
```

where `alpha`/`beta` are the normalised balances, `omega`/`epsIn`/`epsOut` the normalised position,
and `delta` the **relative move of the sqrt price of tokenIn**. `QuadraticMath.getRoot` solves it.

**You do not need to re-derive this.** You need to check three things:

1. the **normalisation** (does it lose precision or overflow?),
2. the **step selection** (is the quadratic solved in the right step?),
3. the **margins** (does the answer get a safety buffer in the right direction?).

### `computeSwap` — the step selection

```solidity
unchecked { roundingMargin = 2 * snapshot.ranges.length + 4; }

while (state.liquidity > 0) {
    step.setNextTick(...);
    state.computeSwapStep(step, zeroForOne, true);
    unchecked { balanceNet = balanceIn.zeroFloorSub(snapshot.getRounding(step.sqrtPriceTargetX96, zeroForOne) + 3); }
    feesIn = state.getStepFees(step, true);

    bool last = state.amountIn + step.amountIn + step.feeAmount > balanceNet;       // (a) balance runs out
    if (!last) {
        (positionAmountIn, positionAmountOut) = state.position.amountsAt(step.sqrtPriceTargetX96, zeroForOne);
        positionAmountIn += feesIn + roundingMargin;
        last = balanceNet <= getBalanceIn(state.amountIn + step.amountIn + step.feeAmount,
                                          state.amountOut + step.amountOut,
                                          positionAmountIn, positionAmountOut);      // (b) would overbuy
    }
    if (last) {
        (sqrtPriceNew,) = getAmountOut(zeroForOne, state, balanceNet.zeroFloorSub(state.amountIn),
                                       state.amountOut, roundingMargin);
        if (<sqrtPriceNew lies inside this step>) {
            step.sqrtPriceTargetX96 = sqrtPriceNew;
            state.computeSwapStep(step, zeroForOne, true);
            feesIn = state.getStepFees(step, true);
        }
    }
    state.accrueFees(snapshot, zeroForOne, feesIn);
    if (!state.crossTick(...)) break;
}
```

**Two independent "this is the last step" tests**, and that is the design:

- **(a)** the user's balance runs out inside this step — you simply cannot swap further.
- **(b)** swapping the *whole* step would buy **more** tokenOut than the core's position needs —
  so the optimum is inside this step.

`getBalanceIn(amountIn, amountOut, positionIn, positionOut)` answers *"what balance would make the
optimal swap end exactly here?"*:

```solidity
if (positionAmountOut == 0) return type(uint256).max;
balanceIn = amountIn.saturatingAdd(amountOut.fullMulDiv(positionAmountIn, positionAmountOut));
```

`saturatingAdd` and `type(uint256).max` as "no constraint" — note those sentinel-ish values and
check nothing compares against them wrongly.

**The `+3` and the `roundingMargin = 2n + 4` are the margins.** They are what stop the solver from
returning a swap that leaves the vault one wei short. Where do 3 and 4 come from? Not documented in
the file. **`docs/proofs/` should justify them — go find which doc, and check the arithmetic.**
An undocumented magic margin in the one function that decides how much of a user's deposit gets
swapped is exactly where I would look for an off-by-one with real value attached.

### `getNormalizedParameters` — the overflow guard

```solidity
uint256 constant MAX_NORMALIZED = 1 << 252;
...
balanceInNormalized  = zeroForOne ? balanceIn.fullMulDiv(uint256(sqrtPrice) << 96, liquidity)
                                  : balanceIn.fullMulDiv(1 << 128, liquidity).fullMulDiv(1 << 160, sqrtPrice);
balanceOutNormalized = <mirror>;
if (balanceInNormalized > MAX_NORMALIZED || balanceOutNormalized > MAX_NORMALIZED) revert AmountInTooLarge();
```

The balances are expressed **relative to the pool's liquidity**. A deposit enormous compared to the
pool reverts `AmountInTooLarge` rather than overflowing. Per S22 a revert is accepted — so the bug
to hunt is not the revert, it is a deposit that is **just under** the limit and produces a wrong
answer.

The position is normalised **by its own largest component**:

```solidity
uint256 largest = max(max(positionLiquidityNormalized, positionAmountInNormalized),
                      max(positionAmountOutNormalized, 1));
positionLiquidityNormalized  = positionLiquidityNormalized.fullMulDiv(1 << 192, largest);
positionAmountInNormalized   = positionAmountInNormalized.fullMulDiv(1 << 192, largest);
positionAmountOutNormalized  = positionAmountOutNormalized.fullMulDiv(1 << 192, largest);
```

The quadratic is **homogeneous** in the position (scaling all three scales the equation, not the
root), so this is legitimate. `max(..., 1)` guards division by zero.

**But the three `fullMulDiv`s round DOWN.** So the normalised position is slightly smaller than
exact, in all three components. Does that bias the root in a consistent direction? That is a real
question and it is the sort of thing a derivation doc should answer. **If the doc does not address
it, that is your opening.**

### Audit notes

- `getSqrtPrice` → `QuadraticMath.getRoot` → `CLMath.getNextSqrtPrice`. So **every concern in A7
  about `getRoot`'s argument signs lands here.** Specifically: does this function guarantee
  `quadraticCoefficient >= 0`? Look at `quadraticCoefficient -= int256(feeTerm);` — the quadratic
  coefficient is reduced by `rho`. **Can `feeTerm` exceed `A`, making it negative?** The docstring
  for `getQuadraticCoefficients` says the coefficients *"are nonnegative for either sign of c0 and
  c1"* — but that sentence is about `c0`/`c1`, not about `rho`. `getRoot`'s docstring requires
  `a` nonnegative. **This is lead #10 and it is my single best structural question in D5.**
  `feeTerm = rho = (kappa - 1) * phi * omegaU` and `A = (alpha + kappa - 1) * omega + epsIn - rho`.
  Since `omegaU <= omega`, `(kappa-1)*phi*omegaU <= (kappa-1)*omega <= (alpha + kappa-1)*omega`, so
  `A >= epsIn >= 0`. **That argument works** — but it depends on `phi <= 1`, i.e. `feeShare <= 1e10`,
  which depends on `unstakedFee <= 1e6` and `protocolSwapFeeBps <= 1e4`. Both are external/governed.
  Check the bounds, then this is closed. Write the proof in your notes either way.
- `getAmountOut` clamps the solved price against "where the whole balance net of fee would reach"
  and then re-derives the price from the `amountOut`. Two conversions, two chances to round the
  wrong way. Mechanical check.

---

## D6. `RedeemOptimizationMath.sol` (131 lines) — burn, then sell

The simplest of the four optimisation files. Worth reading *before* D7.

### `previewRedeem`

```solidity
(amountBurnIn, amountOut, activeLiquidityDelta) = snapshot.getBurnAmounts(snapshot.sqrtPriceX96, shares, zeroForOne);
amountBurnIn = amountBurnIn.zeroFloorSub(roundingMarginIn);          // leave a margin unsold

state = getSwapState(snapshot, pool, zeroForOne);
while (state.amountIn < amountBurnIn) {
    step.setNextTick(state, pool, zeroForOne, sqrtPriceLimitX96);
    (...) = MetadexSwapMath.computeSwapStep(
        state.sqrtPriceX96, step.sqrtPriceTargetX96,
        uint128(uint256(state.liquidity).zeroFloorSub(activeLiquidityDelta)),   // <<< LESS liquidity
        toInt256(amountBurnIn - state.amountIn),                                 // exact INPUT
        state.fee);

    sqrtPriceBound = state.position.sqrtPriceBound;
    if (!state.crossTick(...)) break;
    if (state.sqrtPriceX96 == sqrtPriceBound) {
        (,, activeLiquidityDelta) = snapshot.getBurnAmounts(state.sqrtPriceX96, shares, zeroForOne);
    }
}
amountOut += state.amountOut;
```

**The key line is the liquidity subtraction.** The burn **removes** the shares' liquidity from the
core's positions, and the core's positions are part of the pool. So the sale walks against
`poolLiquidity - burnedLiquidity`, giving a **worse** price than a naive simulation. Correct and
important — a simulation that forgot this would over-report the payout.

`zeroFloorSub` so it floors at zero rather than underflowing.

Note it uses the **vendored** `MetadexSwapMath` with a **positive** `amountRemaining` (exact input) —
because the sale really is "sell exactly this much", and the rounding must match the pool exactly.
Contrast D5, which uses the `roundUp`-parameterised version for its search. Right choice in both.

### `maxRedeem`

```solidity
(amountBurnIn,,) = snapshot.getBurnAmounts(snapshot.sqrtPriceX96, snapshot.supply, zeroForOne);
if (amountBurnIn == 0) return shares;                    // nothing to sell -> no limit

sqrtPriceLimitX96 = snapshot.getSwapCostLimit(zeroForOne);
while (state.liquidity > 0) {
    step.setNextTick(...);
    (...) = MetadexSwapMath.computeSwapStep(
        state.sqrtPriceX96, step.sqrtPriceTargetX96,
        uint128(uint256(state.liquidity).zeroFloorSub(state.position.liquidity.fullMulDivUp(shares, snapshot.supply))),
        type(int256).max,                                 // "sell without limit"
        state.fee);
    if (!state.crossTick(...)) break;
}
return min(shares, state.amountIn.fullMulDiv(snapshot.supply, amountBurnIn + 2 * snapshot.ranges.length));
```

*"How many shares can be redeemed before the sale exceeds the core's max swap cost?"* Walks to the
cost limit, sums the tokenIn absorbable, converts to shares pro rata.

`amountBurnIn + 2 * ranges.length` in the denominator — the `+2n` is the burn's two floors per range
(unstaked + staked), matching `getBurnAmounts`. Consistent with `getRounding`'s accounting. Good.

### Audit notes

- `type(int256).max` as `amountRemaining`: inside `MetadexSwapMath`,
  `uint256(amountRemaining).fullMulDiv(1e6 - feePips, 1e6)` is a division so it cannot overflow.
  And `amountRemainingLessFee >= amountIn` will be true, so the step always reaches its target.
  Verified safe.
- `state.position.liquidity.fullMulDivUp(shares, snapshot.supply)` rounds **UP** — a larger
  liquidity subtraction, so a worse simulated price, so a **smaller** `maxRedeem`. Conservative.
  Correct direction for a limit.
- `previewRedeem` does **not** call `accrueFees`. So it ignores the fees the core earns from the
  sale. That under-reports the payout slightly — conservative, and the opposite choice from
  `MintOptimizationMath`, which *does* accrue. **Is that asymmetry deliberate?** If a preview that
  should accrue does not, the payout is conservative (safe). If one that should not accrue does, it
  over-reports (unsafe). Check `MintOptimizationMath`'s accrual is on the safe side of that line.
  **Good lead.**

---

## D7. `WithdrawOptimizationMath.sol` (473 lines) — the inverse, in X96

### The problem

`withdraw(amountOut)`: the user names the tokenOut they want. How many shares must burn, given that
part of the payout comes from **selling** the tokenIn the burn released?

Inverting `previewRedeem` analytically is not possible step by step, so this file **walks the steps
keeping a running minimum of the shares needed**, and when the sale's cost becomes the binding
constraint, solves a quadratic for the exact crossover.

### The one design decision that defines the file

> *"The sale's amounts are in tokens with 96 binary precision, so the pool's and the core's rounding
> stay exact."*

```solidity
amountIn = snapshot.getRounding(snapshot.sqrtPriceX96, zeroForOne) * (1 << 96);
(holdingsIn, holdingsOut, amountOut) = (holdingsIn * (1 << 96), holdingsOut * (1 << 96), amountOut * (1 << 96));
```

**Everything is multiplied by 2^96.** That gives 96 binary digits *below* a wei, so the per-step
rounding the pool does (1 wei here, 1 wei there) can be tracked exactly instead of being swallowed.

```solidity
// 2 + phi per step: the pool rounds the input up, and its fee up on that input
amountIn += ((2e6 - uint256(state.fee)) << 96).divUp(1e6 - uint256(state.fee));
// 1 per step: the pool rounds the step's output down
amountOut += 1 << 96;
```

So each step adds a precisely-sized sub-wei penalty rather than a whole wei. That is a genuinely
careful piece of engineering **and it is the most likely place in Part D for an arithmetic slip**,
because every quantity now carries an implicit 2^96 and mixing a scaled quantity with an unscaled
one is a silent 2^96x error.

**Concrete Pass 0 task: go through `previewWithdraw` and `getSharesForAmounts` and mark every
variable as scaled or unscaled.** If you find one mixed, that is a finding with a very large
magnitude. Things to check: `state.amountOut` and `step.amountOut` come from `getSharesForAmounts`,
which *overwrites* `step.amountIn`/`step.amountOut` with its own scaled versions:

```solidity
step.amountIn  = liquidityCost.fullMulDivUp(1 << 192, sqrtPriceTarget * (1e6 - fee)) - ...;
step.amountOut = liquidity * (sqrtPrice - sqrtPriceTarget);
```

Those are scaled (note `1 << 192` and the bare `liquidity * (price difference)`, which carries 2^96).
But `state.amountOut` is accumulated by `crossTick` from the *previous* iteration's `step.amountOut`
— which was the scaled one, since `getSharesForAmounts` ran before `crossTick`. **Trace that
carefully.** It looks deliberate, and the file would be badly broken if it were not, but it is
exactly the check worth doing by hand.

### `getSharesForAmounts` — the two-constraint minimum

Returns the shares that **both** fund the sale and pay the amount:

```solidity
cost = amountIn + step.amountIn;
amountOutLeft = amountOut.zeroFloorSub(state.amountOut + step.amountOut);
(holdingsIn, holdingsOut) = (holdingsIn + holdingsInDelta, holdingsOut.zeroFloorSub(holdingsOutDelta));

costBinds = amountOutLeft == 0
    || (holdingsOut > 0 && (cost > holdingsIn || cost.fullMulDiv(holdingsOut, holdingsIn) >= amountOutLeft));

if (costBinds)       shares = cost > holdingsIn ? type(uint256).max : cost.fullMulDivUp(supply, holdingsIn);
else if (holdingsOut == 0 || amountOutLeft > holdingsOut) shares = type(uint256).max;
else                 shares = amountOutLeft.fullMulDivUp(supply, holdingsOut);
```

Two regimes:

- **cost binds** — the sale is expensive, so the shares are set by *funding the sale*:
  `shares = cost / holdingsIn * supply`.
- **output binds** — the sale is cheap, so the shares are set by *paying the amount*:
  `shares = amountOutLeft / holdingsOut * supply`.

`type(uint256).max` means "no number of shares within the supply does it". Both branches round
**UP** (`fullMulDivUp`) — more shares burned, which is **against the withdrawer**. Correct direction.

Note `cost > holdingsIn` and the division `cost.fullMulDiv(holdingsOut, holdingsIn)` — `holdingsIn`
is non-zero here because `previewWithdraw` returned early `if (holdingsIn == 0)`. Verified.

### The crossover: the root AND its neighbour

```solidity
if (costBinds) {
    if (amountIn > holdingsIn || amountOut - state.amountOut > holdingsOut + step.amountOut) return shares;

    step.sqrtPriceTargetX96 = getSqrtPrice(..., amountOut - state.amountOut + 1, ...);   // solve
    (sharesStep, costBinds,,) = getSharesForAmounts(...);
    shares = min(shares, sharesStep);

    step.sqrtPriceTargetX96 = costBinds == zeroForOne ? step.sqrtPriceTargetX96 + 1 : step.sqrtPriceTargetX96 - 1;
    (sharesStep,,,) = getSharesForAmounts(...);
    return min(shares, sharesStep);
}
```

**It evaluates the quadratic's root, then the price one wei away, and takes the minimum of both.**
Because the true minimum of a discrete function near a continuous root can be on either side, and
the root itself is computed with rounding. Checking the neighbour is the honest way to handle that.

`costBinds == zeroForOne` picks **which** neighbour. That single comparison decides the direction of
a one-wei step. If it is backwards, `previewWithdraw` returns a share count off by the slope of the
function at that point — potentially much more than one wei of value. **Reason it out from first
principles and confirm.** Short, high-leverage check.

### `maxWithdraw` — the big margins

```solidity
shares = RedeemOptimizationMath.maxRedeem(snapshot, pool, zeroForOne, shares);
sqrtPriceLimitX96 = snapshot.getSwapCostLimit(zeroForOne);

// the most steps a sale to the band can take
tickLimit = TickMath.getTickAtSqrtPrice(sqrtPriceLimitX96);
ticks = max(zeroForOne ? snapshot.tick - tickLimit : tickLimit - snapshot.tick, 0);
steps = ticks.divUp(uint256(int256(pool.tickSpacing()))) + 1;

roundingMarginIn = (zeroForOne ? getAmount0Delta(limit, spot, ranges, true)
                               : getAmount1Delta(spot, limit, ranges, true)).fullMulDivUp(1e6, 1e6 - snapshot.fee);
roundingMarginIn += snapshot.getRounding(spot, zeroForOne) + 2 * ranges
                  + ((2e6 - snapshot.fee) * steps).divUp(1e6 - snapshot.fee);
roundingMarginOut = snapshot.getRounding(spot, !zeroForOne) + steps + 2 * ranges;

amountOut = RedeemOptimizationMath.previewRedeem(snapshot, pool, zeroForOne, shares, roundingMarginIn)
                .zeroFloorSub(roundingMarginOut);
```

`steps` is **bounded by the tick distance to the cost band divided by the tick spacing**. Note
`uint256(int256(pool.tickSpacing()))` — if a pool ever reported `tickSpacing == 0` this divides by
zero; and a *negative* tick spacing would cast to an enormous number, making `steps` ~0 and the
margins too small. Metadex tick spacings are positive constants, so note it as an external
assumption, not a finding.

### Audit notes

- The deepest call chain in the codebase: `maxWithdraw` → `maxRedeem` → `MetadexSwapMath` →
  `SqrtPriceMath`, plus `previewRedeem` → the same. For a **view**. Under the EIP-7825 16.8M gas
  cap, with 14 ranges and a wide tick walk, is `maxWithdraw` always callable? Per S22 a revert in
  the vault is accepted, so this is at most Info — but it is worth knowing.
- **The `* (1 << 96)` scaling is where to hunt.** My concrete suggestion: write a Foundry test that
  calls `previewWithdraw` for an amount, then actually performs `withdraw` of that amount, and
  asserts the shares match. Then fuzz it. A 2^96 slip would show up as an absurd number immediately,
  and a one-wei slip would show up as an off-by-one. That is the single highest-value PoC you could
  build in Part D, and it is a reasonable amount of work.
- Same for D5/D6: **preview vs reality fuzz tests are the right tool for this entire part.** The
  proof documents are `leans_accepted` only — if your test disagrees with the code, the derivation
  decides nothing.

---

# PART E — The master rounding table

This is the reference you will use in every later pass. The rule the protocol claims to follow:

> **Round against whoever is acting, and in favour of whoever is staying.**

Every row below is from the code I read. **Any row where the beneficiary is the *caller* is a
candidate finding** — there are none in this table that I could see, which is itself useful
information: it means a rounding finding here will be subtle, in a *combination* of roundings rather
than a single wrong direction.

## Core — mint path (caller pays)

| Where | Operation | Direction | Favours |
|---|---|---|---|
| `ALMCore.mint` | `(buffer + fees) * shares / supply` | `fullMulDivUp` | holders |
| `CLMath.getMintAmounts` | `rangeLiquidity * shares / supply` | `fullMulDivUp` | holders |
| `CLMath.getAmountsForLiquidityRoundingUp` | token amounts for liquidity | **UP** | holders |
| `CLMath.getAmount0ForLiquidityRoundingUp` | `liquidity * (b-a) / J` | `fullMulDivUp` | holders |
| `CLMath.getAmount1ForLiquidityRoundingUp` | `liquidity * (b-a) / 2^96` | `fullMulDivUp` | holders |

## Core — burn path (caller receives)

| Where | Operation | Direction | Favours |
|---|---|---|---|
| `ALMCore._burn` | `(buffer + netFees) * shares / supply` | `fullMulDiv` | holders |
| `RangesLib.removeLiquidity` | `(unstaked + staked) * shares / supply` | `fullMulDiv` | holders |
| `CLMath.getAmountsForLiquidity` | via `SqrtPriceMath`, `roundUp = false` | **DOWN** | holders |

## Core — fees and protocol share

| Where | Operation | Direction | Favours |
|---|---|---|---|
| `PoolTokensLib.creditCollected` | protocol share of fees | `fullMulDiv` (DOWN) | holders (dust to buffer) |
| `RangesLib.getUnstakedPositions` | protocol share, floored **once on the total** | `fullMulDiv` | holders (reports more net fees) |
| `RewardsLib.getRewardTotals` | protocol share of received + earned | `fullMulDiv` | holders |
| `RewardsLib.getRewardPerShare` | protocol share of hidden emissions | `fullMulDiv` | holders |
| `MetadexPositionValue.fees` | growth delta x liquidity | `fullMulDiv` (DOWN) | under-reports fees |

## Core — rewards

| Where | Operation | Direction | Note |
|---|---|---|---|
| `RewardsLib.getRewardPerShare` | `credit * 1e18 / supply` | `fullMulDiv` (DOWN) | dust stays unassigned |
| `RewardsLib.accrueBalanceReward` | `shares * delta / 1e18` | `fullMulDiv` (DOWN) | favours the pool of claimants |

## Core — async settlement

| Where | Operation | Direction | Favours |
|---|---|---|---|
| `ShareLib.setLastExchangeRate` | `supply * 2^128 / value` | `fullMulDivUp` | — (a rate, used both ways) |
| `ShareLib.getPendingShares` | value, then shares | `fullMulDivUp` x3, picks worse price | stricter cap |
| `PlanCache.start` | `valueBefore` | `convert(..., DOWN)` | easier shortfall check |
| `PlanCache.getSettlementAmountsOut` | deposit shares `/ valueUp` | `fullMulDiv` (DOWN) | holders |
| `PlanCache.getSettlementAmountsOut` | redeem assets `* value / supply` | `fullMulDiv` (DOWN) | holders |
| `PlanCache.getSettlementAmountsOut` | final `convert` of `assets0` | DOWN | holders |
| `PlanCache.getLevies` | levy, and both splits | `fullMulDivUp` | holders (charges more) |
| `QueueLib.requestAmountOut` | `in * batchOut / batchIn` | `fullMulDiv` (DOWN) | last claimer absorbs dust |
| `QueueLib.requestAmountIn` | `out * batchIn / batchOut` | `fullMulDivUp` | the batch |
| `QueueLib.takeClaimable` | via `requestAmountOut` | DOWN | — |

## Vault — previews and limits

| Where | Operation | Direction | Favours |
|---|---|---|---|
| `Snapshot.getMintAmounts` | liquidity + idle shares | `fullMulDivUp`, `+n` margin | core |
| `Snapshot.getMintShares` | balances less `getRounding`, min over tokens | DOWN | core |
| `Snapshot.getBurnAmounts` | liquidity (two floors/range) + idle | `fullMulDiv` (DOWN) | core |
| `MintOptimization.computeSwap` | `y * L / (L+K)` | `fullMulDivUp` | — (check this one) |
| `MintOptimization.maxMint` | subtracts a large rounding budget | DOWN | under-reports the max |
| `DepositOptimization` | position normalised by largest | `fullMulDiv` (DOWN) x3 | — (check the bias) |
| `DepositOptimization.computeSwap` | `balanceIn - getRounding - 3` | DOWN | core |
| `RedeemOptimization.previewRedeem` | sells against `L - burnedLiquidity` | `zeroFloorSub` | under-reports payout |
| `RedeemOptimization.maxRedeem` | `position.liquidity * shares / supply` | `fullMulDivUp` | smaller max |
| `WithdrawOptimization.getSharesForAmounts` | both share formulas | `fullMulDivUp` | core (more shares burned) |
| `WithdrawOptimization.maxWithdraw` | subtracts both margins | `zeroFloorSub` | under-reports payout |
| `QuadraticMath.getRoot` | sqrt rounded UP, so the root rounds DOWN | DOWN | — |

**How to use this table:** when you find a path that moves value, trace which rows it touches and
ask whether the *composition* still favours holders. A single safe rounding in a chain of five can
be overwhelmed by the others. That composition question is where a real finding lives, not in a
single row.

---

# PART F — What I verified, so you do not have to

Everything in this section I checked against the pinned commit. Treat these as closed and spend your
time elsewhere. If you disagree with any of them, re-check it — I would rather be corrected than
have you trust a wrong clearance.

## F1. All 20 bit-shift constants in `ALMCoreViewLogic` match `State.sol`

The external-read path hand-decodes packed storage. One wrong shift would silently corrupt every
view (`ALMCoreView`, `Snapshot`, the periphery, the off-chain keeper) while the core itself behaved
correctly. I checked all 20 against the struct packing:

**Config word B+1** (`PAUSE_AND_FEES_OFFSET`) — sums to exactly 256 bits:

| Field | Bits | Constant | Value | OK |
|---|---|---|---|---|
| `paused` | 0-7 | — | — | — |
| `protocolEmissionFeeBps` | 8-23 | `EMISSION_FEE_BPS_SHIFT` | 8 | yes |
| `protocolSwapFeeBps` | 24-39 | `SWAP_FEE_BPS_SHIFT` | 24 | yes |
| `twapWindow` | 40-71 | `TWAP_WINDOW_SHIFT` | 40 | yes |
| `maxSpotFromTwap` | 72-135 | `MAX_SPOT_FROM_TWAP_SHIFT` | 72 | yes |
| `maxSpotFromTrusted` | 136-199 | `MAX_SPOT_FROM_TRUSTED_SHIFT` | 136 | yes |
| `windowEnd` | 200-247 | `WINDOW_END_SHIFT` | 200 | yes |
| `rewardPoolToken` | 248-255 | `REWARD_POOL_TOKEN_SHIFT` | 248 | yes |

**Config word B+2** (`PLAN_BOUNDS_OFFSET`) — 176 bits used:

| Field | Bits | Constant | Value | OK |
|---|---|---|---|---|
| `maxTwapFromTrusted` | 0-63 | — | — | — |
| `maxShortfallBps` | 64-79 | `MAX_SHORTFALL_BPS_SHIFT` | 64 | yes |
| `maxSwapCostBps` | 80-95 | `MAX_SWAP_COST_BPS_SHIFT` | 80 | yes |
| `minPlanInterval` | 96-127 | `MIN_PLAN_INTERVAL_SHIFT` | 96 | yes |
| `rangeCap` | 128-135 | `RANGE_CAP_SHIFT` | 128 | yes |
| `lastPlanAt` | 136-167 | `LAST_PLAN_AT_SHIFT` | 136 | yes |
| `arbBlockNumber` | 168-175 | `ARB_BLOCK_NUMBER_SHIFT` | 168 | yes |

**`Range`** — word 1 sums to exactly 256 bits:

| Field | Word.bits | Constant | Value | OK |
|---|---|---|---|---|
| `tickLower` | 1 . 0-23 | — | — | — |
| `tickUpper` | 1 . 24-47 | `TICK_UPPER_SHIFT` | 24 | yes |
| `unstakedTokenId` | 1 . 48-127 | `UNSTAKED_TOKEN_ID_SHIFT` | 48 | yes |
| `stakedLiquidity` | 1 . 128-255 | `STAKED_LIQUIDITY_SHIFT` | 128 | yes |
| `stakedTokenId` | 2 . 0-79 | — | — | — |
| `stakedBlock` | 2 . 80-127 | `STAKED_BLOCK_SHIFT` | 80 | yes |

**`Queue` and `Record`** — `Record` sums to exactly 256 bits, which is why `pendingShares` is
`uint96`:

| Field | Bits | Constant | Value | OK |
|---|---|---|---|---|
| `Queue.pendingEpoch` | 0-31 | — | — | — |
| `Queue.lastClearedEpoch` | 32-63 | `LAST_CLEARED_EPOCH_SHIFT` | 32 | yes |
| `Record.epoch` | 0-31 | — | — | — |
| `Record.amountIn` | 32-159 | `RECORD_AMOUNT_IN_SHIFT` | 32 | yes |
| `Record.pendingShares` | 160-255 | `RECORD_PENDING_SHARES_SHIFT` | 160 | yes |

**And all 24 word offsets** (`CAPS_OFFSET = 0` through `VAULT_QUEUES_OFFSET = 20`, plus the queue
offsets 0-7) match the slot comments in `State.sol`.

**Verdict: this whole avenue is clean.** Do not spend a day on it.

## F2. `unchecked` bounds I checked and closed

| File | Stated bound | Verdict |
|---|---|---|
| `ALMCoreViewLogic.memberSlot` | "STATE_SLOT ends in a zero byte and every offset is below 256" | holds (max offset 27, last byte `0x00`) |
| `CLMath.convert` | "sqrtPriceX96 fits uint128" | holds: `(2^128-1)^2 < 2^256` |
| `CLMath.getBand` | "the deviation is a uint64 at every caller" | holds: all three deviation fields are `uint64` |
| `PoolTokensLib.getReserves` | "every term is a uint128" | holds: 3 x `uint128` into `uint256` |
| `ShareLib.checkPerUserCap` | "every term is within the uint128 total cap" | holds (and is stronger than needed) |
| `PlanCacheLib.start` | "the principal of every range plus a uint128 buffer fits 256 bits" | holds: ~14 x 2^224 + 2^128 |
| `Snapshot.getRounding` | implicit | holds: at most ~14 x 2^96 |
| `EquivalentPositionMath` in-range casts | "uint128 liquidity, amounts below 2^192" | holds |
| `RedeemOptimizationMath.maxRedeem` | `type(int256).max` into `MetadexSwapMath` | holds (it is a division) |

## F3. Mechanics I checked and found correct

- **`TokenDeltaLib.applyDelta`'s high/low crossover** between `TokenDelta` (amount0 high) and
  `TokenAmounts` storage (amount0 low). Correct.
- **`applyDelta`'s single overflow check** catching both overflow and underflow via the high bits.
  Correct.
- **`neg()` reverting on `int128.min`.** Correct.
- **`CalldataLogic.readBool` normalising to exactly 0/1**, which `TokenDeltaLib.single`'s
  `mul(128, isToken0)` depends on. Correct.
- **`decodeCoreImmutables` copies `0x120` = 9 words**, matching `CoreImmutables`' 9 fields. Correct.
- **`RangesLib.unsafeAccess` strides 2 words per `Range`**, matching the 2-word packing. Correct.
- **`PlanCacheLib.closeRange`'s bit move** mirroring `RangesLib`'s swap-and-pop. Correct.
- **`QuadraticMath`'s sqrt rounding up to round the root down**, consistent with its comment.
- **`QueueLib.creditSettled`'s re-derived pro rata** making dust come out exactly, with the last
  claimer absorbing the remainder. Correct.
- **`SwapStateLib`: `accrueFees` is always called before `crossTick`** in `DepositOptimizationMath`
  and `MintOptimizationMath`, so `state.liquidity` is non-zero at the division. Correct.
- **`DepositOptimizationMath`'s `quadraticCoefficient >= 0`**: `A >= epsIn >= 0` follows from
  `omegaU <= omega` and `phi <= 1`. Correct **conditional on** `feeShare <= 1e10`, which depends on
  `unstakedFee <= 1e6` (pool) and `protocolSwapFeeBps <= 1e4` (governed). Confirm both bounds and
  this is fully closed.
- **`PoolTokensLib.skim`'s subtraction is outside `unchecked`**, so it reverts rather than
  underflowing. Correct, and it doubles as a solvency assertion.
- **`RewardsLib.getRewardTotals`' two subtractions are outside `unchecked`.** Correct — and that is
  precisely what makes lead #8 interesting.

---

# PART G — Leads (unverified hypotheses, ranked)

**None of these are findings.** They are states or questions I noticed while reading that look
reachable and consequential. I have proven nothing about any of them. Work them in Pass 2, record
the outcome either way in `notes/02-leads.md`, and check §6 before writing any report.

### Lead 1 — `windowEnd` is never set when the gauge's penalty rate is zero at stake time
**Where:** `RangesLib.stake` early return; `RewardsLib.getRewardPerShare`'s `if (windowEnd != 0)`.
**Hypothesis:** stake while `gaugeFactory.effectivePenaltyConfig(gauge).penaltyRate == 0` →
`state.config.windowEnd` stays 0 → the Metadex admin later raises `penaltyRate` → the range is now
inside a penalty window (`blockNumber < stakedBlock + minStakeBlocks`) but `windowEnd == 0`, so
`getRewardPerShare` **skips the hidden-emissions branch entirely**.
**Why I rank it first:** no attacker needed — an ordinary Metadex parameter change triggers it; the
context doc explicitly puts ordinary parameter changes in scope; §4.1 does not list the Metadex
gauge admin as trusted; and the consequence lands directly on the rewards accumulator.
**To do:** write the state, then quantify what holders lose or gain.

### Lead 2 — can `checkpoint` be made to revert permanently?
**Where:** `RewardsLib.getRewardTotals`, the two checked subtractions.
**Hypothesis:** reach `rewardToken.balanceOf(core) < reserves + lastRewardBalance`. `checkpoint`
runs via `RewardCheckpoint` on **every aLP transfer, mint and burn**, and there is no upgrade
authority — so a durable revert bricks the share token forever.
**Angles:** `rewardPoolToken != 0` (the reward token *is* a pool token) and `escrowed`/`buffer` grow
between a `pay` and a `checkpoint`; a sequence where `lastRewardBalance` is raised and then tokens
leave by another path.
**Why it matters:** under judging rule 3.4.3 this is the **Critical** shape. Highest impact ceiling
in Pass 0.

### Lead 3 — the two clears leave `pendingEpoch` and `lastClearedEpoch` in opposite orders
**Where:** `QueueLib.clearAllDeposits` vs `startClearedEpoch` + `clearDeposit`.
**Fact (verified):** after a named clear `lastClearedEpoch > pendingEpoch`; after a whole-queue clear
`lastClearedEpoch < pendingEpoch`. `nextEpoch` uses `max(...)+1` and handles both.
**Hypothesis:** some other code compares the two ids and assumes one ordering.
**To do:** grep every comparison of `pendingEpoch` and `lastClearedEpoch` across the core, the
keeper extension, `ALMCoreViewLogic` and `ALMVaultAsync`. Structural, mechanical, high payoff.

### Lead 4 — a settled record whose epoch has `amountIn == 0`
**Where:** `QueueLib.creditSettled` → `requestAmountOut(amountIn, epoch.amountIn, epoch.amountOut)`
→ `fullMulDiv(..., batchAmountIn)`.
**Hypothesis:** if a record is settled (`record.amountIn != 0`, `record.epoch != pendingEpoch`) but
its epoch's `amountIn` has already reached zero, the division is by zero and the claim reverts
**permanently** — a durable denial of that user's funds.
**To do:** can an epoch's `amountIn` be drained below the sum of the records still pointing at it?
Look at double clears of the same controller, and at `cancel` after a clear.
**Why it matters:** durable loss of access to funds is high severity under 3.4.3.

### Lead 5 — `decreaseLiquidityAndCollect` books stale `tokensOwed` as fees
**Where:** `PositionManagerLogic.decreaseLiquidityAndCollect`: `fees = collect(...) - principal`.
**Hypothesis:** if the token id already had `tokensOwed` from an earlier `DECREASE_LIQUIDITY` without
a `COLLECT`, the sweep classifies that principal as **fees**, so the protocol takes
`protocolSwapFeeBps` of returned principal.
**To do:** confirm a keeper can issue `DECREASE_LIQUIDITY` and `COLLECT` as separate opcodes with
state in between, then quantify the leak.

### Lead 6 — a range skipped by `collectFees` strands its fees
**Where:** `RangesLib.collectFees`, the two `continue` statements.
**Hypothesis:** a range with zero liquidity on both sides is skipped entirely, so its unstaked NFT's
`tokensOwed` is never collected and never valued. Combined with lead 5, does value get stranded, or
double counted when the range is later closed?

### Lead 7 — the protocol-fee dust gap between the mint path and the plan path
**Where:** `RangesLib.getUnstakedPositions` floors the protocol share **once on the total**;
`PoolTokensLib.creditCollected` floors it **per collection**.
**My arithmetic:** flooring once loses less dust, so `getUnstakedPositions` reports *more* net fees,
the core looks richer, a minter pays *more*. Safe direction.
**To do:** verify my arithmetic, then ask whether a mint timed immediately before or after a plan
can exploit the gap in the other direction.

### Lead 8 — `takeClaimable` with `claimableIn == 0` and `claimableOut > 0`
**Where:** `QueueLib.takeClaimable`'s guard
`(amountIn > claimableIn) || (claimableIn == 0 && claimableOut == 0)`.
**Fact:** in that state, `amountIn == 0` passes the guard and `amountOut = claimableOut` — the whole
remaining output for zero input.
**Hypothesis:** reachable by claiming your full input with a tight `maxAmountOut`. Probably the
intended recovery path, but confirm (a) only the owner can reach it and (b) `escrowed` is
decremented correctly both times. Invariant 2 is exactly about this.

### Lead 9 — `uint48(stakedBlock + minStakeBlocks)` can wrap
**Where:** `EmissionsLogic.getHiddenEmissions` and `RangesLib.stake`, both unchecked `uint48` casts.
**Hypothesis:** `minStakeBlocks` is admin-controlled on the gauge factory and bounded nowhere in
this codebase. A large value makes the sum exceed `uint48` and wrap to a small number, making
`windowEnd` look *past* and closing windows that are open.
**Pairs with lead 1.** Same mechanism, opposite trigger.

### Lead 10 — unguarded wrapping subtraction on the gauge's reward growth
**Where:** `EmissionsLogic.getHiddenEmissions`:
`pool.getRewardGrowthInside(...) - gauge.rewardGrowthInside(tokenId)`, unchecked and unguarded.
**Hypothesis:** correct only if both sides are snapshots of the **same** wrapping counter. If the
gauge normalises differently, the "delta" is garbage and `hidden` becomes astronomically large,
which then overflows `accrued * penaltyRate` in the next `unchecked` block and spikes
`rewardPerShare`. Two leads compounding.
**To do:** read the real `CLGauge.rewardGrowthInside` and confirm it is the same counter.

### Lead 11 — `isPenaltyWindowOpen`'s strict comparison is a hand-copy
**Where:** `EmissionsLogic.isPenaltyWindowOpen`, and its own docstring says *"duplicates
Gauge._applyPenalty's strict comparison, so it must be re-verified on every Metadex release."*
**To do:** read `CLGauge._applyPenalty` and compare `<` vs `<=`. A 15-minute check with a clear,
quantifiable impact (a claim that forfeits when the core thought it was safe).

### Lead 12 — `MetadexSwapMath` uses v4's `SqrtPriceMath` against a v3-fork pool
**Where:** `MetadexSwapMath.computeSwapStep` calls
`@uniswap/v4-core`'s `getNextSqrtPriceFromInput`/`FromOutput`.
**Hypothesis:** Metadex-Slipstream is a **v3** fork. If v4's `SqrtPriceMath` differs from v3's by
even one rounding direction, every sync vault preview is off — and `_swapAndMint` relies on the
simulation agreeing with the real swap to a few wei.
**To do:** diff `node_modules/@uniswap/v4-core/src/libraries/SqrtPriceMath.sol` against the Metadex
pool's own `SqrtPriceMath.sol`.
**Why I rank it high:** purely mechanical, nobody who skipped the vendored files will ask it, and the
blast radius if the answer is "they differ" is the entire sync vault.

### Lead 13 — `MetadexTickBitmap` uses v4's `compress`/`position` conventions
**Where:** imports `TickBitmap.compress` and `TickBitmap.position` from v4-core while implementing
`nextInitializedTickWithinOneWord` itself.
**Hypothesis:** v3 and v4 differ in how tick spacing enters the bitmap. If Metadex follows v3-style
Slipstream, the word/bit mapping could be off, and every swap simulation walks the wrong ticks.
**To do:** compare against the Metadex pool's own `TickBitmap.sol` writer.

### Lead 14 — `uint256(amountRemaining) - amountIn` in the vendored fee branch
**Where:** `MetadexSwapMath.computeSwapStep`'s last line, inside `unchecked`.
**Hypothesis:** reached only when `exactIn && sqrtPriceNext != sqrtPriceTarget`, which should imply
`amountIn < amountRemaining`. **Prove it or find the case where it fails.** A wrap gives an
astronomical `feeAmount`, which in `previewRedeem` makes `state.amountIn` jump past `amountBurnIn`
and ends the loop early — under-reporting the payout.

### Lead 15 — `EquivalentPositionMath`'s bound vs the in-range test at an exact boundary
**Where:** the `sqrtPriceBound` selection (strict `<` / `>`) and the in-range test
(`lower < s && s <= upper` vs `lower <= s && s < upper`).
**Hypothesis:** when the price sits exactly on a range edge, the bound and the in-range test must
agree for **both** swap directions. If they disagree, the equivalent position is built for the wrong
set of ranges at that price.
**To do:** reason it out for all four combinations (direction x which edge). Half an hour, and a
real finding if they disagree.

### Lead 16 — a stale equivalent position if the price passes its bound without landing on it
**Where:** `SwapStateLib.crossTick`'s
`if (state.sqrtPriceX96 == state.position.sqrtPriceBound) rebuild;`.
**Hypothesis:** an exact equality test. If the price can jump *past* the bound without equalling it,
the position goes stale silently with no revert. The walk stops at every initialised tick, and range
edges hold the core's own liquidity so they are initialised — so this should be airtight. **Confirm
it, because the failure mode is silent and large.**

### Lead 17 — `costBinds == zeroForOne` picks the neighbouring price
**Where:** `WithdrawOptimizationMath.previewWithdraw`:
`step.sqrtPriceTargetX96 = costBinds == zeroForOne ? target + 1 : target - 1;`.
**Hypothesis:** one comparison decides the direction of a one-wei probe around the quadratic's root.
If it is backwards, `previewWithdraw` returns a share count off by the slope of the function there —
potentially far more than one wei of value. Reason it out from first principles.

### Lead 18 — scaled vs unscaled mixing in `WithdrawOptimizationMath`
**Where:** the whole of `previewWithdraw` and `getSharesForAmounts`, where everything carries an
implicit `2^96`.
**To do:** mark every variable as scaled or unscaled and find a mixed one. A 2^96 slip would be
enormous. **The right tool is a fuzz test:** `previewWithdraw(x)` then actually `withdraw(x)` and
assert the shares match. Build that test — it is the highest-value PoC in Part D.

### Lead 19 — `accrueFees` mutates the caller's `Snapshot`
**Where:** `SwapStateLib.accrueFees` writes `snapshot.fees0`/`fees1`.
**Hypothesis:** the snapshot is **not reusable** across two independent calculations. If any caller
runs two simulations on one snapshot, the second sees fees the first invented.
**To do:** grep every `getSnapshot` caller in `ALMVaultSync` and `ALMSyncExtension` and check each
snapshot is used for exactly one simulation.

### Lead 20 — `previewRedeem` does not accrue fees but `MintOptimizationMath` does
**Where:** the asymmetry between D4 and D6.
**Hypothesis:** not accruing under-reports a payout (safe). Accruing where you should not
over-reports (unsafe). Check `MintOptimizationMath`'s accrual is on the safe side of that line.

### Smaller notes, worth a line each

- `ConfigLib.checkConfigured` does **not** require the deviations, the plan limits or
  `feeRecipient`. Does the deploy flow set the deviations before `seedCore`?
- `ShareLib.getPendingShares` reverts if the last exchange rate was never set, and only `execute`
  writes it. **So the first plan must run before the first async deposit.** What does the deploy flow
  do about that?
- `ShareLib.setLastExchangeRate` divides by `value`. A plan that legitimately ends with zero value
  would revert on `execute`'s last line. Reachable?
- `QueueLib.requestRedeem` uses an unchecked `uint128(shares)` where `requestDeposit` uses
  `SafeCastLib.toUint128`. `totalCap` can be **lowered** while supply stays above it. Prove the bound.
- `QueueLib.record` checks `amountIn != 0` but not `pendingShares != 0`. A deposit too small to
  compute any pending shares is accepted.
- `CalldataLogic.decodeControllers` allows `count == 0`. A named clear with no controllers opens an
  empty cleared epoch. Does `hasUnsettledEpochs` see it?
- `decodeSwapViaRouter`'s offsets (20 / 52 / 53) are tight and `calldataload` reads 32 bytes.
  Verify each offset against the encoder — `minAmountOut` is the swap's only slippage protection.
- Every handler must use the bounds-checked `state.ranges[index]`, never
  `RangesLib.unsafeAccess`, for a payload-supplied index. Grep and confirm.
- `RangesLib.decreaseStakedLiquidity` with `params.liquidity == 0` restakes and starts a **fresh**
  penalty window without changing anything. Repeatable window reset.
- Nothing stops two ranges having identical ticks. Harmless? `EquivalentPositionMath` folds them.
- `RewardsLib.claimGaugeEmissions` returns `skipped`, which `payReward` ignores. Dead return value?
- `PoolLogic.tryFee` returns `(false, 0)` on revert. Grep every caller: does any treat a failed fee
  read as "fee is zero"?
- `Snapshot.getSnapshot` reads `beforeSwapFee` with `caller = vault`. Does anything read the fee with
  `caller = core` for the keeper's own swaps, or does `PoolLogic.tryFee`'s static read get used?
- `DepositOptimizationMath`'s `+3` and `roundingMargin = 2n + 4` are undocumented magic margins in
  the one function that decides how much of a user's deposit gets swapped. Find the proof doc.
- `maxWithdraw` divides by `uint256(int256(pool.tickSpacing()))`. Zero would divide by zero; negative
  would cast huge and make the margins too small. External assumption.
- `RewardsLib.payReward` transfers even when `amountReward == 0`; `payProtocolFees` guards. Minor
  inconsistency.

---

# PART H — Self-test before you start Pass 1

Answer these **without opening a file.** If you cannot, re-read that section. This is the whole
point of Pass 0 — Pass 1 is cheap only if these are automatic.

1. Which direction does `CLMath.getMintAmounts` round, how many times, and who benefits?
2. In a `TokenDelta`, which half holds `amount0`? In `TokenAmounts` storage, which half?
3. What exactly makes a `Record` "settled"?
4. Name the three token ledgers and the inequality `checkSolvency` enforces.
5. Why does each range have two NFTs instead of one?
6. What does `closeRange` do to the indices of the other ranges, and what two things depend on it?
7. What are the only two writers of `state.config.windowEnd`?
8. What does `rewardPoolToken == 1` mean, and name three places that branch on it.
9. What is the `EquivalentPosition`, and when does it stop being valid?
10. Why is there a `uint96` in `Record`?
11. Which six opcodes are blocked when the core is paused, and why those six?
12. What does `maxShortfallBps = 100` permit a keeper to do?
13. Why does `getRoot` use `2c / (b + sqrt(...))` instead of the textbook formula?
14. Why do the vendored files' `unchecked` blocks say "0.7.6" instead of stating a bound?
15. Which function tells you how far wrong the vault's own arithmetic can be, and what are its terms?
16. Why do levies exist, and what does the `offset` term in `getLevies` do?
17. Which two functions compute a swap step, and why are there two?
18. What breaks if `checkpoint` reverts?

---

## Where to go next

**Pass 0 is done when the checklist in section 2 is ticked and you can answer section H.**

Then start **Pass 1, Trace 1** — the deployment and seed flow:

```
ALMFactory.createExtensions   (L166, onlySteward)
ALMFactory.createCore         (L177, onlySteward)
ALMFactory.resumeCore         (L212, onlySteward)
ALMFactory.seedCore           (L259, onlySteward)
  -> ALMAdminExtension.seed   (L381)  -> ConfigLib.checkConfigured, DEAD_SHARES -> address(1)
ALMCore.constructor           (L54)
```

Three of the "smaller notes" above are questions about exactly that flow, so you will answer them
for free on the way through.

Keep three files as you go:

```
notes/00-primitives.md    one line per helper: what it computes, which way it rounds
notes/01-coverage.md      67 in-scope files x which pass has covered them
notes/02-leads.md         every "that's odd", timestamped, even half-formed
```

`02-leads.md` is the one that wins contests. During Pass 1 you will notice things you cannot yet
evaluate because you do not understand the plan machinery. **Write them down and keep moving.**
Re-reading that file after Pass 2 is where the best findings get recognised — a lead that looked
like nothing alone becomes obvious once you understand the second flow it touches.

And before you write **any** report: check §6 and the 46 decisive known-issue statements. A dismissed
report is +0/1 on the Issues Ratio that gates your entire payout.
