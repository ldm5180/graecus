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
   function D1
     (S : Spot_Range;
      K : Spot_Range;
      T : Year_Fraction;
      V : Vol_Range;
      R : Rate_Range) return Real
   with Post => D1'Result in -Cdf_Saturation .. Cdf_Saturation
   is
      Sqrt_T : constant Real := Real'Max (Sqrt_B (T), 1.0e-9);
      Denom  : constant Real := Real'Max (V * Sqrt_T, 1.0e-12);

      --  The drift and log terms are clamped to their mathematical
      --  bounds (|ln (S/K)| <= 25 by Log_B's Post; the drift tops out
      --  at (0.25 + 12.5) * 0.2) so the division's magnitude is
      --  provably finite before the saturation clamp.
      Numer : constant Real :=
        Real'Min
          (Real'Max (Log_B (S / K) + (R + 0.5 * V * V) * T, -30.0), 30.0);

      Raw : constant Real := Numer / Denom;
   begin
      return Real'Min (Real'Max (Raw, -Cdf_Saturation), Cdf_Saturation);
   end D1;

   function Price
     (S     : Spot_Range;
      K     : Spot_Range;
      T     : Year_Fraction;
      V     : Vol_Range;
      R     : Rate_Range;
      Right : Option_Right) return Real
   is
      Sqrt_T : constant Real := Real'Max (Sqrt_B (T), 1.0e-9);
      D1v    : constant Real := D1 (S, K, T, V, R);
      D2v    : constant Real := D1v - V * Sqrt_T;
      Disc   : constant Real := Exp_B (-(R * T));
      Raw    : constant Real :=
        (if Right = Call
         then S * Norm_Cdf (D1v) - K * Disc * Norm_Cdf (D2v)
         else K * Disc * Norm_Cdf (-D2v) - S * Norm_Cdf (-D1v));
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

      Lo : Real := Min_Vol;
      Hi : Real := Max_Vol;
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

      --  Price is monotone increasing in vol, so plain bisection: 60
      --  halvings of [Min_Vol, Max_Vol] land far past Long_Float's
      --  resolution.
      for Step in 1 .. 60 loop
         pragma Loop_Invariant (Lo >= Min_Vol);
         pragma Loop_Invariant (Hi <= Max_Vol);
         pragma Loop_Invariant (Lo < Hi);
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
         Sqrt_T : constant Real := Real'Max (Sqrt_B (T), 1.0e-9);
         D1v    : constant Real := D1 (S, K, T, V, R);
         Vega   : constant Real :=
           S * Inv_Sqrt_2_Pi * Exp_B (-0.5 * D1v * D1v) * Sqrt_T;
      begin
         Q := (if Vega < Vega_Floor then Faint else Computed);
      end;
   end Implied_Vol;

end Graecus;
