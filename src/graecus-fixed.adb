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

end Graecus.Fixed;
