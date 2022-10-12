# LibOracle

## Usage

Contracts that choose to implement LibOracle should inherit from the `LibOracle` contract. It exposes various methods as public (mostly views, but also the ring buffer extension method), and some internal routines that should be used by the implementing contract.

Updating the oracle is divided into 3 phases:

    // Phase 1: Load the context from storage:

    LibOracle.OracleContext memory oc = oracleLoadContext();

    // Phase 2: Apply updates to a temporary memory struct:

    LibOracle.OracleUpdateSet memory us = oracleGetUpdateSet(oc);

    // Phase 3: Write the updates out to storage along with a new tick:

    oracleUpdate(oc, us, newTick);

The `OracleUpdateSet` contains up-to-date moving averages, variances, and `tickAtStartOfBlock` so these can be used to parameterise an AMM, if desired.

Finally, once a new tick has been determined by the implementing contract, the updated values are written out to storage, as well as to the ring buffer (if applicable).

There is a method `LibOracleUtils.ratioToTick` that accepts two values (for example reserve balances) and computes the tick corresponding to their ratio. Neither of these values should exceed `(2**256 - 1) / 1e18` (about `1e59`).

## Ticks

In uniswap3 terminology, a "tick" refers to a log-space, quantised price-ratio between two assets. Let's break this down:

* *Price ratio*: Given two assets, a price can be considered as a ratio (or fraction). For example, consider ETH and USD. If 1500 USD will get you 1 ETH, then the price ratio would be `1500/1` or `1/1500`, depending on which asset you select as your base/quote. Because usually it's inconvenient to work with fractions, we represent this instead as a number, for example `1500`, or `0.0006666...`
* *Log-space*: The price ratio numbers can get very large/small, especially considering some tokens have different decimal values. In order to keep them within a reasonable range, we use the logarithms of the price ratios. For example, `ln(1500/1) = 7.313...` and `ln(1/1500) = -7.313...`. A very appealing property of logarithms is that inverting a price ratio is equivalent to negating its logarithm. There are several other benefits to using log-space that we will describe below.
* *Quantised*: Because we can't store our prices to an unlimited precision, we need to round their values to the nearest representable value. Using the previous example, we might round `7.313...` to `7.3`. Although this loses some precision, this loss can be quantified and maintained at an acceptable level. Note that this rounding operation is the source of the name "tick": Imagine the ticks on a chart as being evenly-spaced discrete values that data-points must conform to.

### Uniswap3 Ticks

Uniswap3's minimum and maximum supported tick values are `-887272` and `887272`. These numbers are a consequence of two design choices:

* Price ratios between `1/2**128` and `2**128` should be supported.
* The quantisation interval should be `0.01%`.

From these we can derive `MAX_TICK`:

    1.0001**MAX_TICK = 2**128
    MAX_TICK * ln(1.0001) = ln(2**128)
    MAX_TICK = ln(2**128) / ln(1.0001)
    MAX_TICK = 887272.7517...

Uniswap3 stores each tick as an `int24` type, which is more than large enough since Uniswap3 tick values contain about 20.8 bits of information:

    ln(887272 * 2 + 1)/ln(2) = 20.759...

### LibOracle Ticks

Since LibOracle is attempting to squeeze the maximum benefit out of a limited storage space, our ticks begin with slightly different requirements:

* Price ratios between `1/2**128` and `2**128` should be supported.
* It should maximise information density while fitting into an `int24`

So our `MAX_TICK` value is chosen to be `2**23 - 256` and `MIN_TICK` is the negation: `-8388352` and `8388352`.

(Subtracting 256 is done to allow round-tripping through "small" ticks, described below)

LibOracle ticks have a higher information density within `int24`s:

    ln((2**23 - 256) * 2 + 1)/ln(2) = 23.99995605...

We can compute the quantisation interval `B` like so:

    B**(2**23 - 256) = 2**128
    ln(B) * (2**23 - 256) = ln(2**128)
    ln(B) = ln(2**128) / (2**23 - 256)
    B = exp(ln(2**128) / (2**23 - 256))
    B = 1.000010576965334793...

It is approximately `0.001%`.

### Small Ticks

Internally, LibOracle quantises these ticks down further into `int16`s for storage in its ring buffer. Essentially it divides the tick values by `256` and then rounds (it adds or subtracts `128` and then truncates -- this is a mid-step quantisation).

Small ticks have minimum and maximum vaues of `-32767` and `32767`, providing the following density:

    ln(32767 * 2 + 1)/ln(2) = 15.9999779

The quantisation interval for small ticks `Bs` is:

    Bs = exp(ln(2**128) / 32767)
    Bs = 1.002711357906348953...

Approximately `0.27%`

### Converting Between Ticks

One useful property of logarithms is that it is very easy to convert bases. For example, here is a javascript function to convert Uniswap3 ticks into LibOracle ticks:

    function uniswapTickToLibOracleTick(x) {
        return Math.round(x * Math.log(1.0001) / Math.log(1.000010576965334793));
    }

Javascript is unable to represent the `B` value to enough precision, so this conversion is approximate (but good enough for plotting).

For on-chain implementations, note that this is approximately equivalent to simply multiplying by `9.454084984590639502`.




## Moving Average and Variance

Although the ring buffer oracle can provide a geometric time-weighted average, for some applications querying this data structure can be too expensive. In particular, an AMM that implements LibOracle might want to use a moving average of a price to influence the behaviour of swaps (as in Curve2 for example), and the AMM might not be competitive if swapping could consume a large and/or unpredictable amount of gas.

Additionally, for some AMM designs it may be useful to know the variance (or standard deviation) of a price over a time period.

### Exponential Decay

To support this, LibOracle maintains two exponential moving averages (EMAs): A "short" EMA (default 30 minutes) and a "long" EMA (default 1 week). In addition, the variance of each of these is also tracked.

An EMA works by maintaining an accumulator value that "decays" over time as it is replaced by more current data:

    newAccum = oldAccum * alpha + newData * (1 - alpha)

`alpha` is a an exponential function based on a time factor, here represented how much time has elapsed since the last update, relative to the window size (ie 30 minutes):

    alpha = e**(-elapsed / window)

LibOracle uses `e` as the base of the exponent, but other bases will also work. The nice feature of `e` is that if the initial decay rate remained constant, then the decay would be exactly complete after 1 window's duration. Of course, this doesn't happen because the rate of decay reduces with the magnitude and after 1 window the magnitude is reduced to `1/e = 0.367879...`.

An important feature of exponential decay is that the decay is unaffected by the frequency of updates to the accumulator. This means that the reported moving averages will be unaffected by the amount of activity tracked by the oracle. Additionally, in cases where the tick doesn't change in an update, there is no need to spend the gas to update the accumulator -- it can be put off until needed.

Variance is also tracked through a slight modification of the above process.

### Variance/Standard Deviation

Moving averages are stored as tick values (`int24`), so can be used in the ways described above.

Variance are stored scaled down by `256`. This means that they fit inside `uint40` values as opposed to `int48` that would otherwise be required.

For example, suppose we have a variance of `5000`. We can compute the standard deviation in ticks like so:

    sqrt(5000 * 256) = 1131.37084

And this can be approximately converted into price percentage by exponentiating it with `B`, our tick base:

    1.000010576965334793**1131.37084 = 1.01203

So over the EMA period, the standard deviation of the price was about 1.2%.



## Excess-Slippage Detection

LibOracle maintains a special variable called `tickAtStartOfBlock`. This is stored as a small tick. Its purpose is to allow an integrating contract to determine if a potential price movement is outside of some per-block price-movement restriction.

Log-space makes this check especially easy. For example, suppose we want to disallow any price movements beyond a doubling (or halving) within a single block. Compute the number of small ticks this corresponds to using the `Bs` value above:

    ln(2) / ln(1.002711357906348953) = 255.992187499999988085

This means that if the current price (converted to a small tick) is more than `256` away from `tickAtStartOfBlock` then we know we have exceeded our restriction.
