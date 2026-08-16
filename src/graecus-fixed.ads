--  A SPIKE, not production.  Nothing in Graecus calls this, and no
--  consumer should: it exists to answer, with numbers rather than
--  argument, whether this crate's arithmetic could move from
--  Long_Float to Ada fixed point.  Three questions, one per measurement
--  in docs/tdd-log.md: how accurate against the float original, how
--  fast under `make bench`, and how it proves.
--
--  The scope is deliberately one function.  Norm_Cdf is the right one:
--  it is the innermost thing in the crate (Price calls it twice, and
--  Implied_Vol calls Price once per bisection step), it needs exp and
--  nothing else, and it is where the float version's proof cost still
--  concentrates.
--
--  Every type below shares ONE scale, 2**(-40).  That is the whole
--  design: a product of two of them rescales by a shift rather than by
--  a division, which is what keeps fixed-point multiplication cheap.
--  It is also why the money scale a caller would want at the API
--  boundary (1/10000, to match the wire) is NOT the scale used here --
--  the two wants are in tension, and this spike answers only the
--  arithmetic half.

package Graecus.Fixed
  with SPARK_Mode
is

   --  One LSB, and the single most consequential number in this spike.
   --
   --  Ada computes a fixed-point product in the smallest integer that
   --  holds it, so A * B needs Value_Size (A) + Value_Size (B) bits.
   --  Past 63 that is a 128-bit intermediate, which GNAT implements as a
   --  CALL to System.Arith_64.Scaled_Divide64 -- a function call and a
   --  128-by-64 divide for every multiply.  At 2**(-40) all eighteen
   --  products in this unit take that path and Norm_Cdf costs 239 ns
   --  against the float version's 35.
   --
   --  2**(-25) is the largest scale that keeps every product inside 64
   --  bits -- the binding constraint is Ax * Ax, and Ax reaches 40, so
   --  it needs log2 (40) + 25 = 31 bits and its square needs 62.  At
   --  that scale the eighteen calls collapse to one and Norm_Cdf costs
   --  23.6 ns, comfortably BEATING the float version.
   --
   --  It is still the wrong answer, and this is the spike's finding.
   --  2**(-25) drifts 1.4e-7 from the float original -- larger than the
   --  7.5e-8 error of the Abramowitz-Stegun approximation it is
   --  implementing, so the arithmetic would be the dominant error
   --  rather than the method.  Propagated through an inversion that
   --  divides by vega, that is worth roughly 15 ppm on a published skew
   --  reading, which the ppm consumer resolves.
   --
   --  So the scale below is the faithful one, and the cost of being
   --  faithful is the 128-bit path.  Flip this single constant to
   --  1.0 / 2**25 to reproduce the fast-and-loose end of the curve;
   --  both measurements are in docs/tdd-log.md.
   Frac : constant := 1.0 / 2**40;

   --  Probabilities, and anything else living in [0, 1].
   type Unit is delta Frac range 0.0 .. 1.0;

   --  The CDF's argument, at exactly the float original's saturation.
   --  There is no headroom past 40 and there cannot be: 64 / 2**(-25) is
   --  2**31, one step past Integer'Last, so a wider range would force a
   --  wider base type and put every product back over 63 bits.  This is
   --  the scale and the range pushing against each other, which is the
   --  characteristic difficulty of the whole approach.
   type Sat is delta Frac range -40.0 .. 40.0;

   --  What exp is handed: -0.5 * Ax**2, which bottoms out at -800 when
   --  Ax saturates.
   type Exp_Arg is delta Frac range -2_048.0 .. 0.0;

   --  exp over the range Norm_Cdf drives it, to one LSB.  Below about
   --  -28 the true value is under half an LSB and the result is exactly
   --  zero -- the fixed-point analogue of the float version's
   --  observation that the tails past |x| = 40 are under 1e-300.
   function Exp (X : Exp_Arg) return Unit;

   --  The standard normal CDF: Abramowitz-Stegun 26.2.17, the same
   --  rational approximation and the same clamped Horner staging as the
   --  float Graecus.Norm_Cdf, so the two are comparable line by line.
   function Norm_Cdf (X : Sat) return Unit;

end Graecus.Fixed;
