with Ada.Text_IO;

with AUnit.Assertions; use AUnit.Assertions;

with Graecus;

package body Graecus_Tests is

   use AUnit.Test_Cases.Registration;
   use type Graecus.Quality;

   Rfr : constant Graecus.Real := 0.045;

   --  The parity centerpiece: every row of the options_bot fixture
   --  (dumped through the exact library calls its stop logic makes)
   --  within the agreed tolerances -- 2e-3 IV / 0.005 delta, bounded by
   --  the Go library's own ~1e-3 bisection coarseness.  The
   --  ill-conditioned rows (premium at/below intrinsic, zero premium)
   --  must CLASSIFY as clamped and still land the library's +/-1 / ~0
   --  deltas without special cases.
   procedure Test_Fixture_Parity (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Ada.Text_IO;

      File    : File_Type;
      Checked : Natural := 0;

      --  The Nth comma-separated field of a fixture line.
      function Field (Line : String; N : Positive) return String is
         Start : Positive := Line'First;
         Count : Positive := 1;
      begin
         for I in Line'Range loop
            if Line (I) = ',' then
               if Count = N then
                  return Line (Start .. I - 1);
               end if;
               Count := Count + 1;
               Start := I + 1;
            end if;
         end loop;
         if Count = N then
            return Line (Start .. Line'Last);
         end if;
         return "";
      end Field;

   begin
      Open (File, In_File, "tests/data/options_bot_greeks.csv");
      Skip_Line (File);  --  header
      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               declare
                  Name     : constant String := Field (Line, 1);
                  Right    : constant Graecus.Option_Right :=
                    (if Field (Line, 2) = "CALL"
                     then Graecus.Call
                     else Graecus.Put);
                  S        : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 3));
                  K        : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 4));
                  T_Years  : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 5));
                  Premium  : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 7));
                  Go_Iv    : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 9));
                  Go_Delta : constant Graecus.Real :=
                    Graecus.Real'Value (Field (Line, 10));

                  --  The fixture classifies itself: rows with no true
                  --  vol are the outside-the-band cases (Clamped), and
                  --  rows where the GO library itself missed its own
                  --  true vol (it returns the seed when vega is dead)
                  --  are exactly the ones we must call Faint -- IV
                  --  numbers disagree there BY CONSTRUCTION, so only
                  --  the delta is asserted.
                  True_Vol_Text : constant String := Field (Line, 6);

                  Sick : constant Boolean := True_Vol_Text'Length = 0;

                  Go_Identified : constant Boolean :=
                    not Sick
                    and then abs (Go_Iv - Graecus.Real'Value (True_Vol_Text))
                             <= 2.0e-3;

                  Iv : Graecus.Vol_Range;
                  Q  : Graecus.Quality;
                  D  : Graecus.Real;
               begin
                  Graecus.Implied_Vol
                    (Premium, S, K, T_Years, Rfr, Right, Iv, Q);
                  D := Graecus.Delta_Of (S, K, T_Years, Iv, Rfr, Right);

                  if Sick then
                     Assert
                       (Q = Graecus.Clamped,
                        Name & ": no time value must classify as clamped");
                  elsif not Go_Identified then
                     --  Faint or Clamped, depending on which side of the
                     --  band edge the float noise lands -- either way the
                     --  IV is flagged untrustworthy, which is the point.
                     Assert
                       (Q /= Graecus.Computed,
                        Name
                        & ": a vega-dead row must not claim Computed; got "
                        & Q'Image);
                  else
                     Assert
                       (Q = Graecus.Computed,
                        Name & ": a living premium computes; got " & Q'Image);
                     Assert
                       (abs (Iv - Go_Iv) <= 2.0e-3,
                        Name
                        & ": IV within 2e-3 of options_bot; got"
                        & Iv'Image
                        & " want"
                        & Go_Iv'Image);
                  end if;
                  Assert
                    (abs (D - Go_Delta) <= 5.0e-3,
                     Name
                     & ": delta within 0.005 of options_bot; got"
                     & D'Image
                     & " want"
                     & Go_Delta'Image);
                  Checked := Checked + 1;
               end;
            end if;
         end;
      end loop;
      Close (File);
      Assert (Checked = 36, "all 36 fixture rows checked");
   end Test_Fixture_Parity;

   --  Structural sanity, independent of the fixture: the CDF's fixed
   --  points, put-call parity, and the signed delta conventions a
   --  stop logic depends on (puts NEGATIVE, calls positive).
   procedure Test_Properties (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Graecus;
      S  : constant Real := 7_500.0;
      K  : constant Real := 7_480.0;
      Tm : constant Real := 4.0 / 365.25;
      V  : constant Real := 0.18;

      C  : constant Real := Price (S, K, Tm, V, Rfr, Call);
      P  : constant Real := Price (S, K, Tm, V, Rfr, Put);
      Dc : constant Real := Delta_Of (S, K, Tm, V, Rfr, Call);
      Dp : constant Real := Delta_Of (S, K, Tm, V, Rfr, Put);

      --  e^(-r T) without an Exp import: parity holds to first order at
      --  these tiny T; keep a loose bound.
      Forward_Gap : constant Real := C - P - (S - K * (1.0 - Rfr * Tm));
   begin
      Assert (abs Forward_Gap < 0.05, "put-call parity holds");
      Assert (Dc > 0.0 and then Dc < 1.0, "call delta in (0, 1)");
      Assert (Dp < 0.0 and then Dp > -1.0, "put delta in (-1, 0), SIGNED");
      Assert
        (abs (Dc - Dp - 1.0) < 1.0e-9, "call delta - put delta = 1 (same d1)");
   end Test_Properties;

   --  Price then invert: the bisection must land back on the vol it was
   --  given.  This is what bounds Implied_Vol's early exit -- the loop
   --  stops on a bracket width, so loosening that width past ~2e-8 shows
   --  up here as a vol the round trip no longer recovers.  Strikes stay
   --  near the money and vols in the living range, where vega is healthy
   --  and the inversion is well conditioned; the ill-conditioned rows are
   --  the fixture's job (they come back Faint or Clamped).
   procedure Test_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Graecus;
      S       : constant Real := 7_500.0;
      Tm      : constant Real := 4.0 / 365.25;
      Checked : Natural := 0;
   begin
      for Right in Option_Right loop
         for Ks in -20 .. 20 loop
            for Vs in 1 .. 8 loop
               declare
                  K       : constant Real := S + Real (Ks) * 5.0;
                  Ref     : constant Real := 0.10 + Real (Vs) * 0.04;
                  Premium : constant Real := Price (S, K, Tm, Ref, Rfr, Right);
                  Iv      : Vol_Range;
                  Q       : Quality;
               begin
                  Implied_Vol (Premium, S, K, Tm, Rfr, Right, Iv, Q);
                  if Q = Computed then
                     Checked := Checked + 1;
                     Assert
                       (abs (Iv - Ref) < 1.0e-8,
                        "round trip recovers the vol it priced:"
                        & Real'Image (Ref)
                        & " ->"
                        & Real'Image (Iv));
                  end if;
               end;
            end loop;
         end loop;
      end loop;
      Assert (Checked > 100, "the grid exercised a real number of rows");
   end Test_Round_Trip;

   --  The EMA weight an IV-skew signal rides: 1 - exp(-X), pinned
   --  at the classic X = 1 point and saturated at both ends.
   procedure Test_Decay (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Graecus;
   begin
      Assert (Decay_Weight (0.0) = 0.0, "no time, no weight");
      Assert
        (abs (Decay_Weight (1.0) - 0.632_120_558_8) < 1.0e-9,
         "one time constant weighs 1 - 1/e");
      Assert (Decay_Weight (1.0e6) = 1.0, "a huge gap saturates at 1");
   end Test_Decay;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T,
         Test_Fixture_Parity'Access,
         "36 fixture rows within 2e-3 IV / 0.005 delta");
      Register_Routine
        (T, Test_Properties'Access, "parity, bounds, signed deltas");
      Register_Routine
        (T,
         Test_Round_Trip'Access,
         "price then invert recovers the vol, bounding the early exit");
      Register_Routine (T, Test_Decay'Access, "the EMA decay weight");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Graecus (local Black-Scholes IV and delta)"));

end Graecus_Tests;
