package body Graecus.Fixed
  with SPARK_Mode
is

   --  Working types.  All share Frac, so every product below rescales by
   --  a shift; only the ranges differ, and each is the interval its own
   --  operands can actually produce.
   type Abs_Sat is delta Frac range 0.0 .. 40.0;

   --  Signed so that negating the Gaussian exponent stays inside its own
   --  type rather than needing a wider one to pass through.
   type Square is delta Frac range -2_048.0 .. 2_048.0;

   --  The A-S coefficients: three of the five exceed 1.0 in magnitude.
   type Coef is delta Frac range -2.0 .. 2.0;

   --  The Horner accumulator.  Every stage provably lands in about
   --  [-0.36, 1.79]; the wider range is headroom so a rounding at an
   --  edge cannot raise Constraint_Error before the clamp runs.
   type Horner is delta Frac range -4.0 .. 4.0;
   type Stage is delta Frac range -2.0 .. 2.0;

   --  exp's range reduction.  Sixteen steps per octave: the table below
   --  absorbs the fractional part, leaving a remainder under ln (2) / 16
   --  where a degree-six series is good to ~6e-14 -- a fifteenth of an
   --  LSB, so the polynomial is not what limits accuracy.
   type Pos_Arg is delta Frac range 0.0 .. 32.0;
   type Reduced is delta Frac range 0.0 .. 1_024.0;
   type Scale is delta Frac range 0.0 .. 32.0;
   type Signed_Arg is delta Frac range -2_048.0 .. 2_048.0;

   --  The reduction's remainder.  Slack on BOTH sides: the step count is
   --  a floor of a ROUNDED product, so the remainder can land a hair
   --  below zero.
   type Rem_Arg is delta Frac range -1.0 .. 1.0;

   --  Every constant below is irrational or a repeating fraction, so
   --  none of them is an exact multiple of a binary Small and GNAT says
   --  so at each one.  Rounding each to the nearest representable value
   --  is exactly the intent -- that is what a fixed-point literal MEANS
   --  -- and the accuracy this costs is what Graecus_Fixed_Tests
   --  measures.  Warning suppressed here rather than crate-wide so any
   --  OTHER unit that hits it still fails the build.
   pragma
     Warnings (Off, "static fixed-point value is not a multiple of Small");

   Ln2_16     : constant Pos_Arg := 0.043_321_698_784_996_58;
   Inv_Ln2_16 : constant Scale := 23.083_120_654_223_414;

   --  Below this, exp is under half an LSB: 6.9e-13 against a 9.1e-13
   --  grid.  Answering exactly zero here is what makes the function
   --  total over the whole saturated argument range, and it is the
   --  fixed-point analogue of the float version's observation that the
   --  tails past |x| = 40 sit under 1e-300.
   Cutoff : constant Exp_Arg := -28.0;

   --  2 ** (-J / 16): the fractional half of the range reduction.
   Tab : constant array (0 .. 15) of Unit :=
     [0  => 1.0,
      1  => 0.957_603_280_698_573_6,
      2  => 0.917_004_043_204_671_2,
      3  => 0.878_126_080_186_649_5,
      4  => 0.840_896_415_253_714_5,
      5  => 0.805_245_165_974_627_1,
      6  => 0.771_105_412_703_970_4,
      7  => 0.738_413_072_969_749_6,
      8  => 0.707_106_781_186_547_6,
      9  => 0.677_127_773_468_446_3,
      10 => 0.648_419_777_325_504_8,
      11 => 0.620_928_906_036_742_0,
      12 => 0.594_603_557_501_360_5,
      13 => 0.569_394_317_378_345_8,
      14 => 0.545_253_866_332_628_8,
      15 => 0.522_136_891_213_706_9];

   --  The series coefficients, 1 / k!.
   C1 : constant Horner := 1.0;
   C2 : constant Horner := 0.5;
   C3 : constant Horner := 0.166_666_666_666_666_66;
   C4 : constant Horner := 0.041_666_666_666_666_664;
   C5 : constant Horner := 0.008_333_333_333_333_333;
   C6 : constant Horner := 0.001_388_888_888_888_889;

   --  The divisors, tabulated rather than written 2 ** N.  gnatprove
   --  will not bound an exponentiation by a variable -- it was the ONLY
   --  thing in this unit it could not discharge -- and a table turns
   --  each divide into an index check the guards below settle outright.
   --!format off
   Pow2 : constant array (0 .. 30) of Positive :=
     [1,          2,          4,           8,           16,
      32,         64,         128,         256,         512,
      1_024,      2_048,      4_096,       8_192,       16_384,
      32_768,     65_536,     131_072,     262_144,     524_288,
      1_048_576,  2_097_152,  4_194_304,   8_388_608,   16_777_216,
      33_554_432, 67_108_864, 134_217_728, 268_435_456, 536_870_912,
      1_073_741_824];
   --!format on

   --  Halve N times.  Ada's fixed-by-integer divide needs its divisor to
   --  fit an Integer and N reaches 40, so the shift is split in two.
   --  Past 40 the result is below one LSB and the answer is zero, which
   --  is what makes this total.
   function Halved (V : Unit; N : Natural) return Unit
   is (if N = 0
       then V
       elsif N >= 41
       then 0.0
       elsif N <= 30
       then V / Pow2 (N)
       else (V / Pow2 (30)) / Pow2 (N - 30));

   --  exp (-R) for a remainder under ln (2) / 16, by its series.
   function Series (R : Rem_Arg) return Stage is
      U  : constant Horner := Horner (-R);
      P5 : constant Horner := C5 + Horner (U * C6);
      P4 : constant Horner := C4 + Horner (U * P5);
      P3 : constant Horner := C3 + Horner (U * P4);
      P2 : constant Horner := C2 + Horner (U * P3);
      P1 : constant Horner := C1 + Horner (U * P2);
      P0 : constant Horner := C1 + Horner (U * P1);
   begin
      return Stage (Horner'Min (2.0, Horner'Max (-2.0, P0)));
   end Series;

   function Exp (X : Exp_Arg) return Unit is
   begin
      if X <= Cutoff then
         return 0.0;
      end if;

      declare
         Neg : constant Pos_Arg := Pos_Arg (-X);

         --  How many sixteenths of an octave down: under 28 * 16 / ln 2,
         --  just short of 647.
         Y : constant Reduced := Reduced (Neg * Inv_Ln2_16);

         --  Floor, the long way round: 'Truncation is a float-only
         --  attribute, and Ada's fixed-to-integer conversion rounds to
         --  NEAREST.  Round, then step back if that overshot.  The step
         --  cannot underflow: Reduced (0) is zero and Y is never
         --  negative, so a zero round is never the overshooting one.
         M0 : constant Natural := Natural (Y);
         M  : constant Natural := (if Reduced (M0) > Y then M0 - 1 else M0);

         N : constant Natural := M / 16;
         J : constant Natural := M mod 16;

         Rest : constant Signed_Arg :=
           Signed_Arg (Neg) - Signed_Arg (Ln2_16 * M);
         R    : constant Rem_Arg :=
           Rem_Arg (Signed_Arg'Min (1.0, Signed_Arg'Max (-1.0, Rest)));

         --  2 ** (-J / 16) * exp (-R): still inside one octave.
         Whole : constant Horner := Horner (Tab (J) * Series (R));
      begin
         return Halved (Unit (Horner'Min (1.0, Horner'Max (0.0, Whole))), N);
      end;
   end Exp;

   --  Abramowitz-Stegun 26.2.17, coefficient for coefficient with the
   --  float Norm_Cdf beside it.
   B1 : constant Coef := 0.319_381_530;
   B2 : constant Coef := -0.356_563_782;
   B3 : constant Coef := 1.781_477_937;
   B4 : constant Coef := -1.821_255_978;
   B5 : constant Coef := 1.330_274_429;

   Rate          : constant Coef := 0.231_641_9;
   Inv_Sqrt_2_Pi : constant Coef := 0.398_942_280_401_432_678;

   function Staged (X : Horner) return Stage
   is (Stage (Horner'Min (2.0, Horner'Max (-2.0, X))));

   function Norm_Cdf (X : Sat) return Unit is
      Ax : constant Abs_Sat := Abs_Sat (Sat'Min (abs X, 40.0));

      One_D : constant Reduced := 1.0;
      Denom : constant Reduced := One_D + Reduced (Rate * Ax);

      K : constant Unit := Unit (One_D / Denom);

      --  Horner's rule one clamped stage at a time, exactly as the float
      --  version does it: the clamps never bind, they hand each product
      --  a bounded operand.
      P4   : constant Stage := Staged (Horner (B4) + Horner (K * B5));
      P3   : constant Stage := Staged (Horner (B3) + Horner (K * P4));
      P2   : constant Stage := Staged (Horner (B2) + Horner (K * P3));
      P1   : constant Stage := Staged (Horner (B1) + Horner (K * P2));
      Poly : constant Stage := Staged (Horner (K * P1));

      Sq  : constant Square := Square (Ax * Ax);
      Arg : constant Exp_Arg := Exp_Arg (-(Sq / 2));

      Pdf   : constant Unit := Unit (Inv_Sqrt_2_Pi * Exp (Arg));
      Upper : constant Unit :=
        Unit (Horner'Min (1.0, Horner'Max (0.0, Horner (Pdf * Poly))));
   begin
      return (if X >= 0.0 then 1.0 - Upper else Upper);
   end Norm_Cdf;

end Graecus.Fixed;
