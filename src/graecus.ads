--  Graecus (Latin: "Greek"): Black-Scholes IV and delta, computed
--  locally and proved.  European-style cash-settled index options
--  (SPX/SPXW/XSP) are exactly Black-Scholes' model; the normal CDF is
--  the Abramowitz-Stegun 26.2.17 rational approximation (|error| <
--  7.5e-8, far under the 2e-3 parity tolerance below) and the IV solver
--  is a fixed-iteration bisection -- no Newton, no convergence hazards.
--  Every input is clamped by subtype, every function is total, and the
--  ill-conditioned cases (a premium at or below the vol-floor price:
--  deep ITM at intrinsic, worthless OTM) come back CLASSIFIED as
--  Clamped rather than chased -- the delta at the clamped vol lands the
--  same +/-1 / ~0 the reference library emits, without special cases.
--  Deltas are SIGNED (puts negative).  Parity is pinned by
--  tests/data/options_bot_greeks.csv, dumped through the exact Go
--  library calls a production trading bot trades by.
--
--  The body withs Ada.Numerics' elementary functions -- pure math, no
--  IO -- behind a trusted boundary: contracts carry the ranges (proved
--  at every call site), the fixture carries the accuracy.

package Graecus
  with SPARK_Mode
is

   --  The option right HOMES here: the greeks compute over it, and a
   --  consumer's wire types subtype it (static constants on their side
   --  keep the literal names -- and case choices -- working unchanged).
   type Option_Right is (Call, Put);

   subtype Real is Long_Float;

   Min_Vol : constant Real := 5.0e-4;
   Max_Vol : constant Real := 5.0;

   subtype Vol_Range is Real range Min_Vol .. Max_Vol;

   --  Index levels and strikes in dollars (SPX ~7500, XSP ~750).
   subtype Spot_Range is Real range 0.01 .. 1.0e6;

   --  Up to ~73 calendar days -- the 0-8 DTE proof envelope; widening
   --  is a deliberate change with its own re-prove.
   subtype Year_Fraction is Real range 1.0e-7 .. 0.2;

   subtype Rate_Range is Real range 0.0 .. 0.25;

   subtype Premium_Range is Real range 0.0 .. 2.0e6;

   --  Computed: the premium identified a vol.  Faint: the inversion ran
   --  but vega at the solution is below the floor -- the price barely
   --  moves in vol there (deep ITM near expiry), so ANY vol reproduces
   --  the premium and the IV number is untrustworthy while the delta
   --  remains solid (the reference library returns its SEED in this
   --  regime; consumers of IV must skip Faint rows).  Clamped: the
   --  premium sits outside the invertible band entirely (at/below
   --  intrinsic, or absurd).
   type Quality is (Computed, Faint, Clamped);

   --  Dollars of price per 1.00 of vol below which IV is unidentifiable
   --  (living SPX rows measure vega in the tens; vega-dead rows in the
   --  1e-11s -- the gap is enormous).
   Vega_Floor : constant Real := 0.05;

   --  The standard normal CDF, total over Real (the input saturates at
   --  +/-40, where the tails are below 1e-300).
   function Norm_Cdf (X : Real) return Real
   with Post => Norm_Cdf'Result in 0.0 .. 1.0;

   --  1 - exp(-X): the EMA weight of a new sample X time constants
   --  after the last one (an IV-skew signal's smoothing); saturates
   --  at 1 past X = 800, where exp underflows anyway.
   function Decay_Weight (X : Real) return Real
   with Pre => X >= 0.0, Post => Decay_Weight'Result in 0.0 .. 1.0;

   --  The Black-Scholes European price; never negative.
   function Price
     (S     : Spot_Range;
      K     : Spot_Range;
      T     : Year_Fraction;
      V     : Vol_Range;
      R     : Rate_Range;
      Right : Option_Right) return Real
   with Post => Price'Result >= 0.0;

   --  The SIGNED delta: calls in (0, 1), puts in (-1, 0).
   function Delta_Of
     (S     : Spot_Range;
      K     : Spot_Range;
      T     : Year_Fraction;
      V     : Vol_Range;
      R     : Rate_Range;
      Right : Option_Right) return Real
   with Post => Delta_Of'Result in -1.0 .. 1.0;

   --  The implied volatility of a premium: bisection over Vol_Range
   --  (price is monotone in vol), 60 fixed iterations (bracket width
   --  ~4e-18, far past Long_Float's resolution).  A premium outside
   --  the [price at Min_Vol, price at Max_Vol] band cannot be inverted
   --  -- it carries no time value (or an absurd one) -- and comes back
   --  Clamped at the nearer bound.
   procedure Implied_Vol
     (Premium : Premium_Range;
      S       : Spot_Range;
      K       : Spot_Range;
      T       : Year_Fraction;
      R       : Rate_Range;
      Right   : Option_Right;
      V       : out Vol_Range;
      Q       : out Quality);

end Graecus;
