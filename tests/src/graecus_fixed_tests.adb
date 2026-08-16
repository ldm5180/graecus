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

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Exp'Access, "fixed-point exp matches the runtime's");
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
