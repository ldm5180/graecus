--  A SPIKE, not production.  Nothing in Graecus calls this, and no
--  consumer should: it exists to answer, with numbers rather than
--  argument, whether this crate's arithmetic could move from
--  Long_Float to fixed point.  Three questions, one per measurement in
--  docs/tdd-log.md: how accurate against the float original, how fast
--  under `make bench`, and how it proves.
--
--  The scope is deliberately one function.  Norm_Cdf is the right one:
--  it is the innermost thing in the crate (Price calls it twice, and
--  Implied_Vol calls Price once per bisection step), it needs exp and
--  nothing else, and it is where the float version's proof cost still
--  concentrates.
--
--  WHY SCALED INTEGERS RATHER THAN Ada's `delta` TYPES.  This was
--  written with real fixed-point types first, and they cannot be made
--  fast.  Ada computes a product in the smallest integer that holds it,
--  so A * B needs Value_Size (A) + Value_Size (B) bits; past 63 that is
--  a 128-bit intermediate, and GNAT lowers it to a CALL to
--  System.Arith_64.Scaled_Divide64 -- a general 128-by-64 DIVISION for
--  what is, at a binary scale, a shift.  Measured: 12.6 ns per multiply
--  against 1.2 ns for the same arithmetic promoted by hand into
--  Long_Long_Long_Integer.  Eighteen products in this unit, and
--  Norm_Cdf cost 239 ns against the float version's 35.
--
--  Dropping the scale to 2**(-25) keeps every product inside 64 bits
--  and does go fast (23.6 ns), but at 1.4e-7 of drift -- larger than
--  the 7.5e-8 error of the Abramowitz-Stegun approximation being
--  implemented, so the arithmetic would become the dominant error.
--
--  Doing the promotion by hand gives full accuracy AND the speed, which
--  is what is below.  The one thing it costs is Ada's `delta` types
--  themselves: the attributes that reinterpret a fixed-point value as
--  the scaled integer it already is ('Fixed_Value) are not permitted in
--  SPARK, so a provable fast path cannot use them at a boundary.  Hence
--  a scaled-integer API -- which is, not by coincidence, exactly the
--  shape this codebase already carries money in.

package Graecus.Fixed
  with SPARK_Mode
is

   --  Every value here is a RAW scaled integer: the mathematical
   --  quantity times Scale.  One LSB is 2**(-40), about 9.1e-13.
   Scale : constant := 2**40;

   subtype Raw is Long_Long_Integer;

   --  Probabilities, and anything else living in [0, 1].
   subtype Unit is Raw range 0 .. Scale;

   --  The CDF's argument, at the float original's saturation of +/-40.
   subtype Sat is Raw range -40 * Scale .. 40 * Scale;

   --  What exp is handed: -0.5 * Ax**2, which bottoms out at -800 when
   --  Ax saturates.
   subtype Exp_Arg is Raw range -2_048 * Scale .. 0;

   --  exp over the range Norm_Cdf drives it, to about one LSB.  Below
   --  roughly -28 the true value is under half an LSB and the result is
   --  exactly zero -- the fixed-point analogue of the float version's
   --  observation that the tails past |x| = 40 sit under 1e-300.
   function Exp (X : Exp_Arg) return Unit;

   --  The standard normal CDF: Abramowitz-Stegun 26.2.17, the same
   --  rational approximation and the same clamped Horner staging as the
   --  float Graecus.Norm_Cdf, so the two are comparable line by line.
   function Norm_Cdf (X : Sat) return Unit;

   --  The natural log, over Spot_Range -- 0.01 to 1e6, the domain a
   --  strike or a spot lives in.
   --
   --  NOT over the float version's domain, and that is the point.
   --  Graecus's D1 computes Log_B (S / K), whose argument spans 1e-8 to
   --  1e8; 1e8 scaled by 2**40 is 1.1e20, which overflows a 64-bit raw
   --  by more than an order of magnitude.  A fixed-point D1 therefore
   --  cannot take the ratio at all -- it has to compute
   --  Log (S) - Log (K), which is the same number, avoids the division
   --  entirely, and keeps both arguments inside Spot_Range where they
   --  started.  The representation forces the better formulation.
   subtype Log_Arg is Raw range Scale / 100 .. 1_000_000 * Scale;
   subtype Log_Result is Raw range -8 * Scale .. 16 * Scale;

   function Log (X : Log_Arg) return Log_Result;

   --  The square root over [0, 1], the float Sqrt_B's exact domain (it
   --  is only ever handed a Year_Fraction, at most 0.2).
   --
   --  This is the least favourable comparison in the crate: on the
   --  float side sqrt is ONE hardware instruction, so there is no
   --  library call to beat and nothing to be cleverer than.
   subtype Sqrt_Arg is Raw range 0 .. Scale;

   function Sqrt (X : Sqrt_Arg) return Unit;

end Graecus.Fixed;
