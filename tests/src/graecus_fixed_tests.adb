with Ada.Numerics.Long_Elementary_Functions;

with AUnit.Assertions; use AUnit.Assertions;

with Graecus.Fixed;

--  The SPIKE's accuracy guard.  Graecus.Fixed exists to answer three
--  questions with numbers -- how accurate, how fast, how provable -- and
--  this file settles the first.  The reference is the float
--  implementation beside it, not a fixture: the point is whether a
--  fixed-point core could REPLACE the float one, so the float one is
--  the thing to agree with.

package body Graecus_Fixed_Tests is

   use AUnit.Test_Cases.Registration;

   package Elf renames Ada.Numerics.Long_Elementary_Functions;

   subtype Real is Graecus.Real;
   subtype Raw is Graecus.Fixed.Raw;

   Scale : constant Real := Real (Graecus.Fixed.Scale);

   --  What the scaled integers can represent at all: 2**(-40).  Nothing
   --  below this is a meaningful disagreement, it is the grid.
   Lsb : constant Real := 1.0 / Scale;

   function Raw_Of (X : Real) return Raw
   is (Raw (X * Scale));

   function Val_Of (R : Raw) return Real
   is (Real (R) / Scale);

   function Img (X : Real) return String
   is (Real'Image (X));

   --  exp over the range Norm_Cdf actually hands it, against the
   --  runtime's own Exp.  Below the cutoff the answer is exactly zero by
   --  construction -- exp (-28) is 6.9e-13, under one LSB -- and that is
   --  asserted rather than tolerated, because a fixed-point core that
   --  quietly returned something else there would be hiding a bug.
   procedure Test_Exp (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Steps    : constant := 4_000;
      Worst    : Real := 0.0;
      Worst_At : Real := 0.0;
   begin
      for I in 0 .. Steps loop
         declare
            X : constant Real := -28.0 * Real (I) / Real (Steps);
            F : constant Real := Val_Of (Graecus.Fixed.Exp (Raw_Of (X)));
            E : constant Real := Elf.Exp (X);
            D : constant Real := abs (F - E);
         begin
            if D > Worst then
               Worst := D;
               Worst_At := X;
            end if;
         end;
      end loop;

      Assert
        (Worst <= 4.0 * Lsb,
         "fixed exp drifts from the runtime's by"
         & Img (Worst)
         & " at x ="
         & Img (Worst_At)
         & ", over 4 LSB");

      --  Past the cutoff the true value is under half an LSB.
      Assert
        (Graecus.Fixed.Exp (Raw_Of (-30.0)) = 0,
         "exp past the representable floor must be exactly zero");
      Assert
        (Graecus.Fixed.Exp (Raw_Of (-800.0)) = 0,
         "exp at the saturated CDF argument must be exactly zero");
      Assert
        (Graecus.Fixed.Exp (0) = Graecus.Fixed.Scale,
         "exp (0) must be exactly one");
   end Test_Exp;

   --  The spike's headline: does a fixed-point Norm_Cdf agree with the
   --  float one everywhere a real chain drives it?  |d1| over 8 is
   --  already 6e-16 into the tail, far past anything a delta in
   --  1/1000ths or a skew in ppm could resolve.
   procedure Test_Norm_Cdf (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Steps    : constant := 8_000;
      Worst    : Real := 0.0;
      Worst_At : Real := 0.0;
   begin
      for I in 0 .. Steps loop
         declare
            X : constant Real := -8.0 + 16.0 * Real (I) / Real (Steps);
            F : constant Real := Val_Of (Graecus.Fixed.Norm_Cdf (Raw_Of (X)));
            E : constant Real := Graecus.Norm_Cdf (X);
            D : constant Real := abs (F - E);
         begin
            if D > Worst then
               Worst := D;
               Worst_At := X;
            end if;
         end;
      end loop;

      Assert
        (Worst <= 1.0e-9,
         "fixed Norm_Cdf drifts from the float one by"
         & Img (Worst)
         & " at x ="
         & Img (Worst_At));
   end Test_Norm_Cdf;

   --  The saturating ends, where the float version's clamps bind.
   procedure Test_Norm_Cdf_Tails (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      One : constant Raw := Graecus.Fixed.Scale;
   begin
      --  Not "is it a half": A-S 26.2.17 answers 0.50000000527 at zero,
      --  5.3e-9 out, and the FLOAT Graecus.Norm_Cdf carries exactly the
      --  same bias -- it is the rational approximation's own error
      --  (|error| < 7.5e-8), not the arithmetic's.  What this spike has
      --  to show is that swapping the arithmetic does not move the
      --  answer, so the float version is the reference here too.
      Assert
        (abs (Val_Of (Graecus.Fixed.Norm_Cdf (0)) - Graecus.Norm_Cdf (0.0))
         <= 8.0 * Lsb,
         "Norm_Cdf (0) must track the float version, got"
         & Img (Val_Of (Graecus.Fixed.Norm_Cdf (0)))
         & " against"
         & Img (Graecus.Norm_Cdf (0.0)));
      Assert
        (Graecus.Fixed.Norm_Cdf (Graecus.Fixed.Sat'Last) = One,
         "the far right tail must saturate at one");
      Assert
        (Graecus.Fixed.Norm_Cdf (Graecus.Fixed.Sat'First) = 0,
         "the far left tail must saturate at zero");
      Assert
        (Graecus.Fixed.Norm_Cdf (-One) + Graecus.Fixed.Norm_Cdf (One) = One,
         "the CDF must stay symmetric about zero");
   end Test_Norm_Cdf_Tails;

   --  log over Spot_Range, swept GEOMETRICALLY -- a linear sweep would
   --  spend almost every sample in the top octave and never exercise
   --  the normalisation that finds the octave in the first place.
   procedure Test_Log (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Steps    : constant := 8_000;
      Worst    : Real := 0.0;
      Worst_At : Real := 0.0;
   begin
      for I in 0 .. Steps loop
         declare
            --  0.01 up to 1e6, eight decades, evenly in the exponent.
            --  Clamped because the endpoints are reconstructed through
            --  exp/log and land a hair outside the domain.
            X : constant Real :=
              Real'Min
                (1.0e6,
                 Real'Max
                   (0.01,
                    0.01
                    * Elf.Exp (Elf.Log (1.0e8) * Real (I) / Real (Steps))));
            F : constant Real := Val_Of (Graecus.Fixed.Log (Raw_Of (X)));
            E : constant Real := Elf.Log (X);
            D : constant Real := abs (F - E);
         begin
            if D > Worst then
               Worst := D;
               Worst_At := X;
            end if;
         end;
      end loop;

      Assert
        (Worst <= 1.0e-10,
         "fixed log drifts from the runtime's by"
         & Img (Worst)
         & " at x ="
         & Img (Worst_At));

      --  The exact points: ln 1 is zero, and the octave boundaries are
      --  where the normalisation hands over between exponents.
      Assert
        (Graecus.Fixed.Log (Graecus.Fixed.Scale) = 0,
         "log (1) must be exactly zero");
      Assert
        (abs (Val_Of (Graecus.Fixed.Log (2 * Graecus.Fixed.Scale))
              - Elf.Log (2.0))
         <= 4.0 * Lsb,
         "log (2) must land on ln 2");

      --  The whole point of the domain: D1 wants log (S / K), whose
      --  argument would overflow a 64-bit raw.  log (S) - log (K) is
      --  the same number and stays inside Spot_Range.
      declare
         S     : constant Real := 5_900.0;
         K     : constant Real := 5_860.0;
         Split : constant Real :=
           Val_Of (Graecus.Fixed.Log (Raw_Of (S)))
           - Val_Of (Graecus.Fixed.Log (Raw_Of (K)));
      begin
         Assert
           (abs (Split - Elf.Log (S / K)) <= 1.0e-10,
            "log (S) - log (K) must reproduce log (S / K), got"
            & Img (Split)
            & " against"
            & Img (Elf.Log (S / K)));
      end;
   end Test_Log;

   --  sqrt over Year_Fraction, the only thing the float Sqrt_B is ever
   --  handed.  Swept geometrically for the same reason log is: the
   --  normalisation works in octaves, so a linear sweep would leave
   --  almost all of them untested.
   procedure Test_Sqrt (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Steps    : constant := 8_000;
      Worst    : Real := 0.0;
      Worst_At : Real := 0.0;
   begin
      for I in 0 .. Steps loop
         declare
            --  1e-7 up to 1.0, the Sqrt_B domain from its floor up.
            X : constant Real :=
              Real'Min
                (1.0,
                 Real'Max
                   (1.0e-7,
                    1.0e-7
                    * Elf.Exp (Elf.Log (1.0e7) * Real (I) / Real (Steps))));
            F : constant Real := Val_Of (Graecus.Fixed.Sqrt (Raw_Of (X)));
            E : constant Real := Elf.Sqrt (X);
            D : constant Real := abs (F - E);

            --  What the INPUT's own quantisation already costs: half an
            --  LSB of x, magnified by d(sqrt)/dx = 1 / (2 sqrt x).  At
            --  the bottom of Year_Fraction this dominates completely --
            --  x = 1.1e-7 is only ~123_000 raw, seventeen significant
            --  bits -- so a flat tolerance here would be measuring the
            --  representation's dynamic range, not the algorithm.
            Floor_Err : constant Real := 0.5 * Lsb / (2.0 * E) + Lsb;
         begin
            if D / Floor_Err > Worst then
               Worst := D / Floor_Err;
               Worst_At := X;
            end if;
         end;
      end loop;

      Assert
        (Worst <= 3.0,
         "fixed sqrt exceeds the input's own quantisation limit by"
         & Img (Worst)
         & "x at x ="
         & Img (Worst_At));

      Assert (Graecus.Fixed.Sqrt (0) = 0, "sqrt (0) must be exactly zero");
      Assert
        (abs (Val_Of (Graecus.Fixed.Sqrt (Graecus.Fixed.Scale)) - 1.0)
         <= 4.0 * Lsb,
         "sqrt (1) must land on one, got"
         & Img (Val_Of (Graecus.Fixed.Sqrt (Graecus.Fixed.Scale))));
      Assert
        (abs (Val_Of (Graecus.Fixed.Sqrt (Graecus.Fixed.Scale / 4)) - 0.5)
         <= 4.0 * Lsb,
         "sqrt (1/4) must land on a half -- the normalisation's own edge");
   end Test_Sqrt;

   --  The whole price, against the float Graecus.Price, over a chain
   --  shaped like the one the bot actually reads: strikes either side
   --  of a 5900 index print, both rights, three terms, three vols.
   procedure Test_Price (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Rfr      : constant Real := 0.045;
      Under    : constant Real := 5_900.0;
      Worst    : Real := 0.0;
      Worst_At : Real := 0.0;

      type Real_List is array (Positive range <>) of Real;
      Terms : constant Real_List :=
        [4.0 / 365.25, 7.0 / 365.25, 30.0 / 365.25];
      Vols  : constant Real_List := [0.08, 0.18, 0.45];

      procedure Check (Strike, Term, Vol : Real; Right : Graecus.Option_Right)
      is
         F : constant Real :=
           Val_Of
             (Graecus.Fixed.Price
                (Graecus.Fixed.Spot (Raw_Of (Under)),
                 Graecus.Fixed.Spot (Raw_Of (Strike)),
                 Graecus.Fixed.Year (Raw_Of (Term)),
                 Graecus.Fixed.Vol (Raw_Of (Vol)),
                 Graecus.Fixed.Rate (Raw_Of (Rfr)),
                 Right));
         E : constant Real :=
           Graecus.Price (Under, Strike, Term, Vol, Rfr, Right);
         D : constant Real := abs (F - E);
      begin
         if D > Worst then
            Worst := D;
            Worst_At := Strike;
         end if;
      end Check;
   begin
      for Term of Terms loop
         for Vol of Vols loop
            for I in 0 .. 400 loop
               declare
                  Strike : constant Real := 4_900.0 + 5.0 * Real (I);
               begin
                  Check (Strike, Term, Vol, Graecus.Call);
                  Check (Strike, Term, Vol, Graecus.Put);
               end;
            end loop;
         end loop;
      end loop;

      --  The tolerance is in DOLLARS, because dollars is the unit a
      --  price is compared and ordered in.  A tenth of a cent is well
      --  under the $0.05 tick an SPX order actually rests on.
      Assert
        (Worst <= 0.001,
         "fixed Price drifts from the float one by $"
         & Img (Worst)
         & " at strike"
         & Img (Worst_At));
   end Test_Price;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Exp'Access, "fixed-point exp matches the runtime's");
      Register_Routine
        (T,
         Test_Price'Access,
         "fixed-point Price matches the float one across a chain");
      Register_Routine
        (T,
         Test_Sqrt'Access,
         "fixed-point sqrt matches the runtime's over Year_Fraction");
      Register_Routine
        (T,
         Test_Log'Access,
         "fixed-point log matches the runtime's across eight decades");
      Register_Routine
        (T,
         Test_Norm_Cdf'Access,
         "fixed-point Norm_Cdf matches the float one across the chain");
      Register_Routine
        (T,
         Test_Norm_Cdf_Tails'Access,
         "the CDF saturates and stays symmetric");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Graecus.Fixed (the fixed-point spike)");
   end Name;

end Graecus_Fixed_Tests;
