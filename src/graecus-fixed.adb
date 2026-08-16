package body Graecus.Fixed
  with SPARK_Mode
is

   subtype LLI is Long_Long_Integer;
   subtype LLLI is Long_Long_Long_Integer;

   --  Everything below is a RAW value: the mathematical quantity times
   --  Scale.  This is the same representation Ada's own fixed-point
   --  types use -- what differs is who rescales a product.
   --
   --  Ada's "*" lowers to a CALL to System.Arith_64.Scaled_Divide64
   --  whenever the product needs more than 63 bits, which at this scale
   --  is always: a general 128-by-64 DIVISION for what is, because
   --  Scale is a power of two, a shift.  Measured at 12.6 ns per
   --  multiply.  Doing the promotion by hand into the 128-bit integer
   --  GNAT has had since Ada 2022 costs 1.2 ns -- a 64x64 -> 128
   --  multiply and a shift, inline, no call.
   Half : constant LLLI := Scale / 2;

   --  The widest operand any multiply below is handed, and the bound
   --  that keeps the promoted product far inside 128 bits.
   Lim : constant LLI := 64 * Scale;

   subtype Operand is LLI range -Lim .. Lim;
   subtype R_Stage is Operand range -2 * Scale .. 2 * Scale;
   subtype R_Horner is Operand range -4 * Scale .. 4 * Scale;
   subtype R_Abs is Operand range 0 .. 40 * Scale;

   --  Round half away from zero, matching what Ada's fixed-point
   --  multiply does -- truncating instead would bias every one of the
   --  eighteen products the same direction and the drift would compound.
   function Mul (A, B : Operand) return LLI
   is (LLI
         (if LLLI (A) * LLLI (B) >= 0
          then (LLLI (A) * LLLI (B) + Half) / LLLI (Scale)
          else (LLLI (A) * LLLI (B) - Half) / LLLI (Scale)))
   with Post => abs Mul'Result <= 4_096 * Scale + 1;

   function Div (A, B : Operand) return LLI
   is (LLI ((LLLI (A) * LLLI (Scale) + LLLI (B) / 2) / LLLI (B)))
   with Pre => B > 0 and then A >= 0 and then A <= B;

   --  Raw constants: the value times Scale, rounded.
   Ln2_16     : constant LLI := 47_632_711_549;
   Inv_Ln2_16 : constant LLI := 25_380_159_564_675;

   --  exp is under half an LSB below here, so the answer is exactly
   --  zero -- the fixed-point analogue of the float version's
   --  observation that the tails past |x| = 40 sit under 1e-300.
   Cutoff : constant LLI := -28 * Scale;

   --  2 ** (-J / 16), raw.
   --!format off
   Tab : constant array (0 .. 15) of Unit :=
     [1_099_511_627_776, 1_052_895_941_925, 1_008_256_608_221,
        965_509_835_819,   924_575_386_327,   885_376_423_200,
        847_839_367_509,   811_893_759_832,   777_472_127_994,
        744_509_860_419,   712_945_084_849,   682_718_552_210,
        653_773_525_390,   626_055_672_747,   599_512_966_123,
        574_095_583_180];
   --!format on

   --  1 / k!, raw.
   C1 : constant LLI := 1_099_511_627_776;
   C2 : constant LLI := 549_755_813_888;
   C3 : constant LLI := 183_251_937_963;
   C4 : constant LLI := 45_812_984_491;
   C5 : constant LLI := 9_162_596_898;
   C6 : constant LLI := 1_527_099_483;

   --!format off
   Pow2 : constant array (0 .. 40) of LLI :=
     [1,             2,             4,             8,             16,
      32,            64,            128,           256,           512,
      1_024,         2_048,         4_096,         8_192,         16_384,
      32_768,        65_536,        131_072,       262_144,       524_288,
      1_048_576,     2_097_152,     4_194_304,     8_388_608,     16_777_216,
      33_554_432,    67_108_864,    134_217_728,   268_435_456,   536_870_912,
      1_073_741_824, 2_147_483_648, 4_294_967_296, 8_589_934_592,
      17_179_869_184, 34_359_738_368, 68_719_476_736, 137_438_953_472,
      274_877_906_944, 549_755_813_888, 1_099_511_627_776];
   --!format on

   --  Halve N times.  Past 40 the result is below one LSB and the answer
   --  is zero, which is what makes this total.
   function Halved (V : Unit; N : Natural) return Unit
   is (if N >= 41 then 0 else V / Pow2 (N));

   function Clamp (V, Lo, Hi : LLI) return LLI
   is (if V < Lo then Lo elsif V > Hi then Hi else V);

   --  exp (-R) for a remainder under ln (2) / 16, by its series.
   function Series (R : R_Horner) return R_Stage is
      U  : constant R_Horner := -R;
      P5 : constant LLI := C5 + Mul (U, C6);
      P4 : constant LLI := C4 + Mul (U, Clamp (P5, -4 * Scale, 4 * Scale));
      P3 : constant LLI := C3 + Mul (U, Clamp (P4, -4 * Scale, 4 * Scale));
      P2 : constant LLI := C2 + Mul (U, Clamp (P3, -4 * Scale, 4 * Scale));
      P1 : constant LLI := C1 + Mul (U, Clamp (P2, -4 * Scale, 4 * Scale));
      P0 : constant LLI := C1 + Mul (U, Clamp (P1, -4 * Scale, 4 * Scale));
   begin
      return Clamp (P0, -2 * Scale, 2 * Scale);
   end Series;

   function Exp (X : Exp_Arg) return Unit is
   begin
      if X <= Cutoff then
         return 0;
      end if;

      declare
         Neg : constant LLI := Clamp (-X, 0, 32 * Scale);

         --  How many sixteenths of an octave down: under 28 * 16 / ln 2,
         --  just short of 647.
         Y : constant LLI := Mul (Neg, Inv_Ln2_16);
         M : constant Natural := Natural (Clamp (Y / Scale, 0, 1_024));

         N : constant Natural := M / 16;
         J : constant Natural := M mod 16;

         R : constant R_Horner :=
           Clamp (Neg - Ln2_16 * LLI (M), -4 * Scale, 4 * Scale);

         --  2 ** (-J / 16) * exp (-R): still inside one octave.
         Whole : constant LLI := Mul (Tab (J), Series (R));
      begin
         return Halved (Clamp (Whole, 0, Scale), N);
      end;
   end Exp;

   --  Abramowitz-Stegun 26.2.17, raw.
   B1 : constant LLI := 351_163_705_932;
   B2 : constant LLI := -392_046_024_353;
   B3 : constant LLI := 1_958_755_706_358;
   B4 : constant LLI := -2_002_492_124_968;
   B5 : constant LLI := 1_462_652_202_819;

   Rate          : constant LLI := 254_692_962_530;
   Inv_Sqrt_2_Pi : constant LLI := 438_641_676_113;

   function Norm_Cdf (X : Sat) return Unit is
      Ax : constant R_Abs := Clamp (abs X, 0, 40 * Scale);

      Denom : constant LLI := Scale + Mul (Rate, Ax);
      K     : constant Unit := Div (Scale, Denom);

      --  Horner's rule one clamped stage at a time, exactly as the float
      --  version does it: the clamps never bind, they hand each product
      --  a bounded operand.
      P4   : constant R_Stage :=
        Clamp (B4 + Mul (K, B5), -2 * Scale, 2 * Scale);
      P3   : constant R_Stage :=
        Clamp (B3 + Mul (K, P4), -2 * Scale, 2 * Scale);
      P2   : constant R_Stage :=
        Clamp (B2 + Mul (K, P3), -2 * Scale, 2 * Scale);
      P1   : constant R_Stage :=
        Clamp (B1 + Mul (K, P2), -2 * Scale, 2 * Scale);
      Poly : constant R_Stage := Clamp (Mul (K, P1), -2 * Scale, 2 * Scale);

      Sq  : constant LLI := Mul (Ax, Ax);
      Arg : constant LLI := -(Sq / 2);

      Pdf   : constant Unit :=
        Clamp (Mul (Inv_Sqrt_2_Pi, Exp (Arg)), 0, Scale);
      Upper : constant Unit := Clamp (Mul (Pdf, Poly), 0, Scale);
   begin
      return (if X >= 0 then Scale - Upper else Upper);
   end Norm_Cdf;

   --  ln 2, raw: the whole-octave part of a log.
   Ln2 : constant LLI := 762_123_384_786;

   --  ln (1 + J / 16) and 1 / (1 + J / 16): the sixteenths of the
   --  mantissa's octave, exactly as Tab above does for exp.  Reducing
   --  the mantissa onto one of these leaves an argument so close to 1
   --  that four series terms are already past the grid.
   --!format off
   Log_T : constant array (0 .. 15) of LLI :=
     [0,               66_657_476_617, 129_503_817_259,
      188_951_355_727, 245_348_929_333, 298_994_282_159,
      350_143_580_273, 399_018_810_095, 445_813_601_022,
      490_697_858_666, 533_821_488_828, 575_317_418_281,
      615_304_065_922, 653_887_380_089, 691_162_530_356,
      727_215_321_822];

   Inv_T : constant array (0 .. 15) of Unit :=
     [1_099_511_627_776, 1_034_834_473_201, 977_343_669_134,
        925_904_528_653,   879_609_302_221, 837_723_144_972,
        799_644_820_201,   764_877_654_105, 733_007_751_851,
        703_687_441_777,   676_622_540_170, 651_562_446_089,
        628_292_358_729,   606_627_104_980, 586_406_201_481,
        567_489_872_401];
   --!format on

   --  1/3, 1/5, 1/7 -- the odd atanh series.  With |z| under 0.0304 the
   --  next term is 4.8e-15, a two-hundredth of an LSB, so the series is
   --  not what limits accuracy here.
   L3 : constant LLI := 366_503_875_925;
   L5 : constant LLI := 219_902_325_555;
   L7 : constant LLI := 157_073_089_682;

   --  Split X into a mantissa in [1, 2) and a power of two.  This step
   --  has no analogue in the float version because there the hardware
   --  format carries the octave; a fixed-point log has to find it.
   --  Four tests up and five down cover the whole domain, and each is a
   --  compare and a shift.
   procedure Normalize (X : Log_Arg; M : out Raw; E : out Integer) is
   begin
      M := X;
      E := 0;

      --  Up to at least 1.0: at most seven doublings, since X >= 0.01.
      if M < Scale / 2**4 then
         M := M * 2**4;
         E := E - 4;
      end if;
      if M < Scale / 2**2 then
         M := M * 2**2;
         E := E - 2;
      end if;
      if M < Scale / 2 then
         M := M * 2;
         E := E - 1;
      end if;
      if M < Scale then
         M := M * 2;
         E := E - 1;
      end if;

      --  Down to below 2.0: at most nineteen halvings, since X <= 1e6.
      if M >= Scale * 2**16 then
         M := M / 2**16;
         E := E + 16;
      end if;
      if M >= Scale * 2**8 then
         M := M / 2**8;
         E := E + 8;
      end if;
      if M >= Scale * 2**4 then
         M := M / 2**4;
         E := E + 4;
      end if;
      if M >= Scale * 2**2 then
         M := M / 2**2;
         E := E + 2;
      end if;
      if M >= Scale * 2 then
         M := M / 2;
         E := E + 1;
      end if;
   end Normalize;

   function Log (X : Log_Arg) return Log_Result is
      M : Raw;
      E : Integer;
   begin
      Normalize (X, M, E);

      declare
         Mant : constant LLI := Clamp (M, Scale, 2 * Scale - 1);
         J    : constant Natural :=
           Natural (Clamp ((Mant - Scale) * 16 / Scale, 0, 15));

         --  The mantissa over its sixteenth: within 1/16 of 1.0, and
         --  reached by a multiply rather than a divide.
         U : constant LLI := Mul (Mant, Inv_T (J));

         --  atanh's argument, (u - 1) / (u + 1), under 0.0304.
         Z : constant LLI := Div (Clamp (U - Scale, 0, Scale), U + Scale);
         --  Clamped like every other operand here, and for the reason
         --  the bounded-subtypes work established: Mul's postcondition
         --  is deliberately loose, so an UNclamped W leaves the solver
         --  deriving its bound through a nonlinear product.  Measured,
         --  that one range check cost 89,483 steps -- more than the
         --  whole rest of this unit put together.
         W : constant LLI := Clamp (Mul (Z, Z), 0, Scale);

         P5 : constant LLI := L5 + Mul (W, L7);
         P3 : constant LLI := L3 + Mul (W, Clamp (P5, 0, Scale));
         P1 : constant LLI := Scale + Mul (W, Clamp (P3, 0, Scale));
      begin
         return
           Clamp
             (LLI (E)
              * Ln2
              + Log_T (J)
              + 2 * Mul (Z, Clamp (P1, 0, 2 * Scale)),
              -8 * Scale,
              16 * Scale);
      end;
   end Log;

   Quarter : constant LLI := Scale / 4;
   Three   : constant LLI := 3 * Scale;

   --  1 / sqrt (m) at the midpoint of each sixteenth of [0.25, 1), the
   --  seed for the Newton iteration below.  Worst relative error 4.38%,
   --  which the recurrence e <- 1.5 * e**2 takes to 2.9e-3, 1.2e-5,
   --  2.3e-10, 8.1e-20 -- so four steps, because three would stop at
   --  2.3e-10 and the grid here is 9.1e-13.
   --!format off
   Rsq_T : constant array (0 .. 15) of LLI :=
     [2_102_668_406_102, 1_942_731_951_877, 1_814_495_445_435,
      1_708_704_159_290, 1_619_491_994_583, 1_542_936_784_740,
      1_476_303_458_016, 1_417_618_750_200, 1_365_418_444_670,
      1_318_590_091_900, 1_276_271_316_274, 1_237_781_890_729,
      1_202_577_080_556, 1_170_214_808_625, 1_140_332_049_941,
      1_112_627_538_436];
   --!format on

   --  1 / sqrt (M) for M in [0.25, 1), so the result is in [1, 2].
   subtype Rsq_Range is LLI range Scale .. 2 * Scale;

   --  One Newton step, y <- y * (3 - M * y**2) / 2.  Written for the
   --  RECIPROCAL root on purpose: the direct iteration needs a division
   --  per step, and a division is the one thing that is expensive in
   --  both representations.  This form is multiplies only.
   function Rsq_Step (Y : Rsq_Range; M : Unit) return Rsq_Range is
      Y2 : constant LLI := Clamp (Mul (Y, Y), 0, 4 * Scale);

      --  Bounded by THREE, not by two.  The seed carries up to 4.4% of
      --  error, so M * y**2 can fall to about 0.91 and the correction
      --  rise to 2.09; clamping it at two silently truncated the first
      --  iteration and left ~2e-2 of drift just above 0.25.
      Correction : constant LLI := Clamp (Three - Mul (M, Y2), 0, Three);
   begin
      return Clamp (Mul (Y, Correction / 2), Scale, 2 * Scale);
   end Rsq_Step;

   function Sqrt (X : Sqrt_Arg) return Unit is
      M : Raw := X;
      K : Natural := 0;
   begin
      if X = 0 then
         return 0;
      end if;

      --  Normalise into [0.25, 1) by EVEN powers of two -- the root
      --  halves the exponent, so the shift has to come in pairs of bits
      --  or it cannot be undone by a shift at the end.
      if M < Quarter / 4**16 then
         M := M * 4**16;
         K := K + 16;
      end if;
      if M < Quarter / 4**8 then
         M := M * 4**8;
         K := K + 8;
      end if;
      if M < Quarter / 4**4 then
         M := M * 4**4;
         K := K + 4;
      end if;
      if M < Quarter / 4**2 then
         M := M * 4**2;
         K := K + 2;
      end if;
      if M < Quarter / 4 then
         M := M * 4;
         K := K + 1;
      end if;

      --  The halving chain above only establishes M >= Quarter / 4:
      --  each step s leaves M >= Quarter / 4**s, so the last one lands a
      --  level short.  This is the step that closes it, and without it
      --  every exact power-of-four boundary -- 1/16 was the one the
      --  test caught -- comes back un-normalised and wrong.
      if M < Quarter then
         M := M * 4;
         K := K + 1;
      end if;

      declare
         Mant : constant Unit := Clamp (M, Quarter, Scale);
         J    : constant Natural :=
           Natural (Clamp ((Mant - Quarter) * 16 / (3 * Quarter), 0, 15));

         Y0 : constant Rsq_Range := Clamp (Rsq_T (J), Scale, 2 * Scale);
         Y1 : constant Rsq_Range := Rsq_Step (Y0, Mant);
         Y2 : constant Rsq_Range := Rsq_Step (Y1, Mant);
         Y3 : constant Rsq_Range := Rsq_Step (Y2, Mant);
         Y4 : constant Rsq_Range := Rsq_Step (Y3, Mant);
      begin
         --  sqrt (m) = m * (1 / sqrt (m)), then undo the even shift.
         return Halved (Clamp (Mul (Mant, Y4), 0, Scale), K);
      end;
   end Sqrt;

end Graecus.Fixed;
