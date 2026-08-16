with Ada.Numerics.Long_Elementary_Functions;

package body Graecus
  with SPARK_Mode
is

   package Elf renames Ada.Numerics.Long_Elementary_Functions;

   --  1 / sqrt (2 * pi).
   Inv_Sqrt_2_Pi : constant Real := 0.398942280401432678;

   --  Beyond |x| = 40 the normal tails are under 1e-300: saturating
   --  there keeps every Exp argument in a tame range and the function
   --  total.
   Cdf_Saturation : constant Real := 40.0;

   --  Bounded intermediates.  Each range below is a fact the clamps in
   --  the bodies already guarantee; naming it as a subtype hands the
   --  prover the interval ONCE, at the declaration, instead of making
   --  it re-derive the same bound through the min/max chain at every
   --  downstream use.  The clamps stay -- they are what makes each
   --  range check trivially provable, and they keep the saturating
   --  behaviour a bare subtype would turn into a Constraint_Error.
   subtype Unit_Real is Real range 0.0 .. 1.0;

   --  The Horner stages: every stage value lives in [-2, 2].
   subtype Stage_Real is Real range -2.0 .. 2.0;

   --  Saturated CDF arguments, and their squares: |x| <= 40 gives
   --  x * x <= 1600, so -0.5 * x * x >= -800 -- inside Exp_B's -801.0
   --  floor with 1.0 to spare.
   subtype Sat_Real is Real range -Cdf_Saturation .. Cdf_Saturation;
   subtype Abs_Sat_Real is Real range 0.0 .. Cdf_Saturation;
   subtype Sat_Square is Real range 0.0 .. 1_600.0;

   --  sqrt (T) floored away from zero so the vol-time product is total.
   subtype Root_Time is Real range 1.0e-9 .. 1.0;

   --  V * sqrt (T), floored: V <= 5.0 and sqrt (T) <= 1.0.
   subtype Vol_Time is Real range 1.0e-12 .. Max_Vol;

   --  The d1 numerator, clamped to its mathematical bound.
   subtype Numer_Range is Real range -30.0 .. 30.0;

   --  |Numer| <= 30 over a denominator floored at 1.0e-12.
   subtype Ratio_Range is Real range -3.0e13 .. 3.0e13;

   --  The trusted numerics boundary: the GNAT runtime's elementary
   --  functions carry no usable Posts, so the proof would treat every
   --  Exp as possibly 1.8e308.  These wrappers declare the bounds the
   --  callers actually use (their Pres are proved at every call site);
   --  the bodies are SPARK_Mode Off and the NUMBERS are pinned by the
   --  options_bot fixture parity test -- contracts carry the ranges,
   --  tests carry the accuracy.

   function Exp_B (X : Real) return Real
   with Pre => X in -801.0 .. 0.0, Post => Exp_B'Result in 0.0 .. 1.0;

   function Exp_B (X : Real) return Real with SPARK_Mode => Off is
   begin
      return Elf.Exp (X);
   end Exp_B;

   function Sqrt_B (X : Real) return Real
   with Pre => X in 0.0 .. 1.0, Post => Sqrt_B'Result in 0.0 .. 1.0;

   function Sqrt_B (X : Real) return Real with SPARK_Mode => Off is
   begin
      return Elf.Sqrt (X);
   end Sqrt_B;

   function Log_B (X : Real) return Real
   with Pre => X in 1.0e-10 .. 1.0e10, Post => Log_B'Result in -25.0 .. 25.0;

   function Log_B (X : Real) return Real with SPARK_Mode => Off is
   begin
      return Elf.Log (X);
   end Log_B;

   --  The Gaussian exponent's square, bounded by its argument subtype
   --  so Exp_B's precondition is a linear step rather than a nonlinear
   --  floating-point derivation the solver has to find on its own.
   function Square (X : Sat_Real) return Sat_Square
   is (X * X);

   function Decay_Weight (X : Real) return Real
   is (if X >= 800.0
       then 1.0
       else Real'Max (0.0, Real'Min (1.0, 1.0 - Exp_B (-X))));

   function Norm_Cdf (X : Real) return Real is
      Ax : constant Abs_Sat_Real := Real'Min (abs X, Cdf_Saturation);

      --  Abramowitz-Stegun 26.2.17.
      B1 : constant Real := 0.319381530;
      B2 : constant Real := -0.356563782;
      B3 : constant Real := 1.781477937;
      B4 : constant Real := -1.821255978;
      B5 : constant Real := 1.330274429;

      K : constant Unit_Real :=
        Real'Max (0.0, Real'Min (1.0, 1.0 / (1.0 + 0.2316419 * Ax)));

      --  Horner's rule one clamped stage at a time: every stage value
      --  lives in [-2, 2] mathematically, so the clamps never bind --
      --  they only hand the prover the interval each product needs.
      function Staged (X : Real) return Stage_Real
      is (Real'Min (2.0, Real'Max (-2.0, X)));

      P4 : constant Stage_Real := Staged (B4 + K * B5);
      P3 : constant Stage_Real := Staged (B3 + K * P4);
      P2 : constant Stage_Real := Staged (B2 + K * P3);
      P1 : constant Stage_Real := Staged (B1 + K * P2);

      --  The last Horner term is the same K * stage shape, so it takes
      --  the same never-binding clamp into [-2, 2].
      Poly : constant Stage_Real := Staged (K * P1);

      --  Pdf is naturally in [0, 0.399]; the [0, 1] clamp never binds
      --  either -- it just hands the Pdf * Poly product below a bounded
      --  operand so the overflow check discharges.
      Pdf : constant Unit_Real :=
        Real'Max
          (0.0, Real'Min (1.0, Inv_Sqrt_2_Pi * Exp_B (-0.5 * Square (Ax))));

      Upper : constant Unit_Real := Real'Min (Real'Max (Pdf * Poly, 0.0), 1.0);
   begin
      return (if X >= 0.0 then 1.0 - Upper else Upper);
   end Norm_Cdf;

   --  The d1 term; the vol-time denominator is clamped away from zero
   --  (its true floor here is ~1.6e-7) so the division is total, and
   --  the result saturates like the CDF (past +/-40 the price is
   --  pinned anyway).
   --
   --  The Post stays, and the result stays a bare Real: replacing it
   --  with a Sat_Real return subtype was MEASURED and is worse both
   --  ways.  A body-local function with no contract is one gnatprove
   --  INLINES, so every call site re-proves this whole body in its own
   --  context -- which costs more than it buys and does not discharge
   --  at all inside Implied_Vol's vega block.  Carrying both the Post
   --  and the subtype proves, but adds a return range check and a
   --  postcondition that together cost more than the intermediates
   --  below save.  The bounds belong on the intermediates here, not on
   --  the result.

   --  The floored root of time, named once rather than spelled out in
   --  the three places that need it.
   --
   --  Price used to compute it TWICE per call -- once for itself, once
   --  again inside D1 -- and Implied_Vol's vega block a third time.
   --  D1_At below is what closes that.
   function Root_Of (T : Year_Fraction) return Root_Time
   is (Real'Max (Sqrt_B (T), 1.0e-9));

   --  d1, given a root of time the caller has already paid for.  The
   --  root is a pure function of T, so this parameter is redundant with
   --  T by construction; it exists only so a caller that needs the root
   --  ANYWAY does not buy it twice.  Use D1 below wherever the root is
   --  not otherwise wanted.
   --
   --  Worth 4.4% off both Price and Implied_Vol, measured in the
   --  RELEASE profile.  Under `alr build` the same change reads as a
   --  0.4 ns gain against a 2.5 ns LOSS on Delta_Of -- that profile
   --  carries -gnata, so the extra wrapper's postcondition becomes a
   --  run-time check.  Release drops assertions and the cost is nil
   --  where it counts, which is why `make bench` pins the profile.
   function D1_At
     (S      : Spot_Range;
      K      : Spot_Range;
      T      : Year_Fraction;
      V      : Vol_Range;
      R      : Rate_Range;
      Sqrt_T : Root_Time) return Real
   with Post => D1_At'Result in -Cdf_Saturation .. Cdf_Saturation
   is
      Denom : constant Vol_Time := Real'Max (V * Sqrt_T, 1.0e-12);

      --  V <= 5.0, so the variance term is bounded before it is scaled.
      V_Sq : constant Real range 0.0 .. 25.0 := V * V;

      --  The drift and log terms are clamped to their mathematical
      --  bounds (|ln (S/K)| <= 25 by Log_B's Post; the drift tops out
      --  at (0.25 + 12.5) * 0.2) so the division's magnitude is
      --  provably finite before the saturation clamp.
      Numer : constant Numer_Range :=
        Real'Min
          (Real'Max (Log_B (S / K) + (R + 0.5 * V_Sq) * T, -30.0), 30.0);

      Raw : constant Ratio_Range := Numer / Denom;
   begin
      return Real'Min (Real'Max (Raw, -Cdf_Saturation), Cdf_Saturation);
   end D1_At;

   function D1
     (S : Spot_Range;
      K : Spot_Range;
      T : Year_Fraction;
      V : Vol_Range;
      R : Rate_Range) return Real
   is (D1_At (S, K, T, V, R, Root_Of (T)))
   with Post => D1'Result in -Cdf_Saturation .. Cdf_Saturation;

   function Price
     (S     : Spot_Range;
      K     : Spot_Range;
      T     : Year_Fraction;
      V     : Vol_Range;
      R     : Rate_Range;
      Right : Option_Right) return Real
   is
      --  One root of time for the whole call: D2v needs it below, and
      --  d1 needs it inside, so it is computed here and handed down.
      Sqrt_T : constant Root_Time := Root_Of (T);
      D1v    : constant Sat_Real := D1_At (S, K, T, V, R, Sqrt_T);

      D2v  : constant Real := D1v - V * Sqrt_T;
      Disc : constant Unit_Real := Exp_B (-(R * T));

      --  The discounted strike: both legs below are (bounded x CDF).
      Disc_K : constant Real range 0.0 .. 1.0e6 := K * Disc;

      --  Raw stays unbounded on purpose: a declared range here was
      --  MEASURED as the most expensive thing in the file.  The tight
      --  +/-1.0e6 does not discharge (the solver will not see that one
      --  leg is near zero exactly when the other is near its maximum),
      --  and the widened +/-2.0e6 that does discharge costs more than
      --  everything the rest of this subprogram saves.  Disc_K below is
      --  what actually pays: it bounds a leg BEFORE the subtraction.
      Raw : constant Real :=
        (if Right = Call
         then S * Norm_Cdf (D1v) - Disc_K * Norm_Cdf (D2v)
         else Disc_K * Norm_Cdf (-D2v) - S * Norm_Cdf (-D1v));
   begin
      return Real'Max (Raw, 0.0);
   end Price;

   function Delta_Of
     (S     : Spot_Range;
      K     : Spot_Range;
      T     : Year_Fraction;
      V     : Vol_Range;
      R     : Rate_Range;
      Right : Option_Right) return Real
   is
      N_D1 : constant Real := Norm_Cdf (D1 (S, K, T, V, R));
   begin
      return (if Right = Call then N_D1 else N_D1 - 1.0);
   end Delta_Of;

   procedure Implied_Vol
     (Premium : Premium_Range;
      S       : Spot_Range;
      K       : Spot_Range;
      T       : Year_Fraction;
      R       : Rate_Range;
      Right   : Option_Right;
      V       : out Vol_Range;
      Q       : out Quality)
   is
      Floor_Price   : constant Real := Price (S, K, T, Min_Vol, R, Right);
      Ceiling_Price : constant Real := Price (S, K, T, Max_Vol, R, Right);

      Lo : Vol_Range := Min_Vol;
      Hi : Vol_Range := Max_Vol;

      --  Stop bisecting once the bracket is narrower than anything a
      --  consumer can represent.  Every caller rounds this vol into an
      --  integer -- deltas into 1/1000ths, skew into ppm -- so a bracket
      --  three orders of magnitude below the finest of those quanta has
      --  already settled every digit anyone reads.  Running on to the
      --  float resolution floor instead costs a full Price per halving,
      --  and a Price is five transcendental calls.
      Vol_Resolution : constant Real := 1.0e-9;
   begin
      --  No time value (or an absurd one): the premium sits outside the
      --  invertible band -- classify, never chase.
      if Premium <= Floor_Price then
         V := Min_Vol;
         Q := Clamped;
         return;
      end if;
      if Premium >= Ceiling_Price then
         V := Max_Vol;
         Q := Clamped;
         return;
      end if;

      --  Price is monotone increasing in vol, so plain bisection.  The 60
      --  halvings remain the bound (they still outrun Long_Float's
      --  resolution, so termination and the bracket invariant are
      --  unchanged); Vol_Resolution is what actually ends the loop.
      for Step in 1 .. 60 loop
         pragma Loop_Invariant (Lo < Hi);
         exit when Hi - Lo <= Vol_Resolution;
         declare
            Mid : constant Real := Lo + (Hi - Lo) / 2.0;
         begin
            exit when Mid <= Lo or else Mid >= Hi;  --  resolution floor
            if Price (S, K, T, Mid, R, Right) < Premium then
               Lo := Mid;
            else
               Hi := Mid;
            end if;
         end;
      end loop;

      --  The float midpoint provably stays inside the bracket only with
      --  the explicit clamp (rounding could otherwise defeat the range
      --  check on Vol_Range).
      V := Real'Min (Max_Vol, Real'Max (Min_Vol, Lo + (Hi - Lo) / 2.0));

      --  Vega at the solution decides whether the number means anything:
      --  S * pdf (d1) * sqrt (T), in dollars per 1.00 of vol.
      declare
         Sqrt_T : constant Root_Time := Root_Of (T);
         D1v    : constant Sat_Real := D1_At (S, K, T, V, R, Sqrt_T);

         --  The peak of the density, scaled by spot: S <= 1.0e6 times
         --  1 / sqrt (2 * pi) is under 4.0e5.
         Peak : constant Real range 0.0 .. 4.0e5 := S * Inv_Sqrt_2_Pi;

         --  The Gaussian factor: in [0, 1] by Exp_B's own postcondition.
         Bell : constant Unit_Real := Exp_B (-0.5 * Square (D1v));

         Vega : constant Real range 0.0 .. 4.0e5 := Peak * Bell * Sqrt_T;
      begin
         Q := (if Vega < Vega_Floor then Faint else Computed);
      end;
   end Implied_Vol;

end Graecus;
