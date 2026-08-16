with Ada.Command_Line;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Real_Time;
with Ada.Text_IO;

with Graecus;
with Graecus.Fixed;

--  Times graecus's four public entry points over a synthetic SPXW chain
--  and prints one CSV row per measurement.
--
--  Two scenarios, because they exercise completely different amounts of
--  work and only reporting one of them would flatter the numbers:
--
--    0dte  -- four hours to expiry, the deployed bot shape.  One sigma
--             is ~23 points, so a 2000-point-wide chain is mostly deep
--             ITM/OTM: the premium sits outside the invertible band and
--             Implied_Vol returns Clamped after just two Price calls,
--             never reaching the bisection.
--    week  -- seven days, where most strikes carry real time value and
--             the bisection actually runs.
--
--  The quality mix is printed with every Implied_Vol row precisely so a
--  reader can tell which of those two they are looking at.  A change
--  that speeds up the bisection shows up in `week` and barely moves
--  `0dte`; quoting only the second would hide it, and only the first
--  would overstate it.
--
--  Usage: bench_graecus [passes]   (default 40)

procedure Bench_Graecus is
   use Ada.Text_IO;
   use type Ada.Real_Time.Time;
   use type Graecus.Quality;

   subtype Real is Graecus.Real;

   package Real_IO is new Ada.Text_IO.Float_IO (Real);

   Default_Passes : constant := 40;

   --  The book: 400 strikes a side on the 5-point grid, centred on the
   --  index print -- fructus's bench book, so the two are comparable.
   Strikes     : constant := 400;
   Strike_Step : constant Real := 5.0;
   Spot        : constant Graecus.Spot_Range := 5_900.0;
   Rfr         : constant Graecus.Rate_Range := 0.045;

   --  The vol every mark is generated AT, so an inversion has a known
   --  answer to find rather than an arbitrary premium to classify.
   True_Vol : constant Graecus.Vol_Range := 0.18;

   Zero_Dte : constant Graecus.Year_Fraction := 4.0 / (24.0 * 365.25);
   Week_Dte : constant Graecus.Year_Fraction := 7.0 / 365.25;

   type Strike_Index is range 1 .. Strikes;
   type Strike_Array is array (Strike_Index) of Graecus.Spot_Range;
   type Mark_Array is array (Strike_Index) of Graecus.Premium_Range;

   --  Accumulated into by every timed loop and printed at the end: with
   --  -O3 and no side effect, the compiler is entitled to delete the
   --  whole measurement otherwise.
   Checksum : Real := 0.0;

   function Strike_Of (I : Strike_Index) return Graecus.Spot_Range
   is (Spot
       - Real (Strikes / 2) * Strike_Step
       + Real (Long_Long_Integer (I) - 1) * Strike_Step);

   Grid : Strike_Array;

   function Ns_Per
     (A, B : Ada.Real_Time.Time; Calls : Long_Long_Integer) return Real
   is (Real (Ada.Real_Time.To_Duration (B - A)) * 1.0e9 / Real (Calls));

   procedure Row
     (Scenario : String;
      Op       : String;
      Calls    : Long_Long_Integer;
      A, B     : Ada.Real_Time.Time;
      Note     : String := "") is
   begin
      Put (Scenario & "," & Op & "," & Calls'Image (2 .. Calls'Image'Last));
      Put (",");
      Real_IO.Put (Ns_Per (A, B, Calls), Fore => 1, Aft => 1, Exp => 0);
      Put_Line ("," & Note);
   end Row;

   --  Marks for one right, priced at True_Vol -- the inversion's input.
   procedure Fill_Marks
     (T     : Graecus.Year_Fraction;
      Right : Graecus.Option_Right;
      Marks : out Mark_Array) is
   begin
      for I in Strike_Index loop
         Marks (I) :=
           Graecus.Premium_Range
             (Real'Min
                (2.0e6,
                 Graecus.Price (Spot, Grid (I), T, True_Vol, Rfr, Right)));
      end loop;
   end Fill_Marks;

   procedure Bench_Scenario
     (Scenario : String; T : Graecus.Year_Fraction; Passes : Positive)
   is
      Calls                    : constant Long_Long_Integer :=
        Long_Long_Integer (Passes) * Long_Long_Integer (Strikes) * 2;
      Puts, Calls_M            : Mark_Array;
      A, B                     : Ada.Real_Time.Time;
      Computed, Faint, Clamped : Natural := 0;
   begin
      Fill_Marks (T, Graecus.Put, Puts);
      Fill_Marks (T, Graecus.Call, Calls_M);

      --  Price
      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in Strike_Index loop
            Checksum :=
              Checksum
              + Graecus.Price (Spot, Grid (I), T, True_Vol, Rfr, Graecus.Put)
              + Graecus.Price (Spot, Grid (I), T, True_Vol, Rfr, Graecus.Call);
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row (Scenario, "price", Calls, A, B);

      --  Delta_Of
      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in Strike_Index loop
            Checksum :=
              Checksum
              + Graecus.Delta_Of
                  (Spot, Grid (I), T, True_Vol, Rfr, Graecus.Put)
              + Graecus.Delta_Of
                  (Spot, Grid (I), T, True_Vol, Rfr, Graecus.Call);
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row (Scenario, "delta_of", Calls, A, B);

      --  Implied_Vol -- the expensive one, and the only one the
      --  bisection bound can move.
      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         for I in Strike_Index loop
            declare
               V : Graecus.Vol_Range;
               Q : Graecus.Quality;
            begin
               Graecus.Implied_Vol
                 (Puts (I), Spot, Grid (I), T, Rfr, Graecus.Put, V, Q);
               Checksum := Checksum + V;
               if P = 1 then
                  case Q is
                     when Graecus.Computed =>
                        Computed := Computed + 1;

                     when Graecus.Faint    =>
                        Faint := Faint + 1;

                     when Graecus.Clamped  =>
                        Clamped := Clamped + 1;
                  end case;
               end if;

               Graecus.Implied_Vol
                 (Calls_M (I), Spot, Grid (I), T, Rfr, Graecus.Call, V, Q);
               Checksum := Checksum + V;
               if P = 1 then
                  case Q is
                     when Graecus.Computed =>
                        Computed := Computed + 1;

                     when Graecus.Faint    =>
                        Faint := Faint + 1;

                     when Graecus.Clamped  =>
                        Clamped := Clamped + 1;
                  end case;
               end if;
            end;
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row
        (Scenario,
         "implied_vol",
         Calls,
         A,
         B,
         "computed="
         & Computed'Image (2 .. Computed'Image'Last)
         & " faint="
         & Faint'Image (2 .. Faint'Image'Last)
         & " clamped="
         & Clamped'Image (2 .. Clamped'Image'Last));
   end Bench_Scenario;

   Passes : Positive := Default_Passes;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Passes := Positive'Value (Ada.Command_Line.Argument (1));
   end if;

   for I in Strike_Index loop
      Grid (I) := Strike_Of (I);
   end loop;

   Put_Line ("scenario,op,calls,ns_per_call,note");

   --  Norm_Cdf on its own: no scenario, just a sweep across the d1 range
   --  a real chain produces.
   declare
      Sweep : constant := 16_000;
      Calls : constant Long_Long_Integer := Long_Long_Integer (Passes) * Sweep;
      A, B  : Ada.Real_Time.Time;
   begin
      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum :=
              Checksum
              + Graecus.Norm_Cdf (-8.0 + 16.0 * Real (I) / Real (Sweep));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row ("sweep", "norm_cdf", Calls, A, B, "x in [-8, 8]");
   end;

   --  The same sweep through the fixed-point spike, so the two are timed
   --  on identical inputs in one process, and the worst disagreement
   --  between them is reported next to the cost of getting it.
   declare
      Sweep : constant := 16_000;
      Calls : constant Long_Long_Integer := Long_Long_Integer (Passes) * Sweep;
      A, B  : Ada.Real_Time.Time;
      Worst : Real := 0.0;
   begin
      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum :=
              Checksum
              + Real
                  (Graecus.Fixed.Norm_Cdf
                     (Graecus.Fixed.Sat
                        ((-8.0 + 16.0 * Real (I) / Real (Sweep))
                         * Real (Graecus.Fixed.Scale))));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;

      for I in 1 .. Sweep loop
         declare
            X : constant Real := -8.0 + 16.0 * Real (I) / Real (Sweep);
            D : constant Real :=
              abs (Real
                     (Graecus.Fixed.Norm_Cdf
                        (Graecus.Fixed.Sat (X * Real (Graecus.Fixed.Scale))))
                   / Real (Graecus.Fixed.Scale)
                   - Graecus.Norm_Cdf (X));
         begin
            Worst := Real'Max (Worst, D);
         end;
      end loop;

      Row
        ("sweep",
         "norm_cdf_fixed",
         Calls,
         A,
         B,
         "worst drift vs float" & Real'Image (Worst));
   end;

   --  log: the runtime's against the spike's, over Spot_Range, swept
   --  geometrically so every octave gets the same number of samples and
   --  the fixed version's octave-finding is actually exercised.
   declare
      package Elf renames Ada.Numerics.Long_Elementary_Functions;
      Sweep : constant := 16_000;
      Calls : constant Long_Long_Integer := Long_Long_Integer (Passes) * Sweep;
      A, B  : Ada.Real_Time.Time;
      Worst : Real := 0.0;

      --  Precomputed: building the sweep costs an exp and a log, and
      --  leaving that inside the timed loops would land on BOTH sides
      --  and quietly compress the ratio being measured.
      type Point_Array is array (1 .. Sweep) of Real;
      type Raw_Array is array (1 .. Sweep) of Graecus.Fixed.Log_Arg;
      Point     : Point_Array;
      Point_Raw : Raw_Array;
   begin
      for I in 1 .. Sweep loop
         Point (I) :=
           Real'Min
             (1.0e6,
              Real'Max
                (0.01,
                 0.01 * Elf.Exp (Elf.Log (1.0e8) * Real (I) / Real (Sweep))));
         Point_Raw (I) :=
           Graecus.Fixed.Log_Arg (Point (I) * Real (Graecus.Fixed.Scale));
      end loop;

      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum := Checksum + Elf.Log (Point (I));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row ("sweep", "log", Calls, A, B, "x in [0.01, 1e6]");

      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum := Checksum + Real (Graecus.Fixed.Log (Point_Raw (I)));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;

      for I in 1 .. Sweep loop
         declare
            D : constant Real :=
              abs (Real (Graecus.Fixed.Log (Point_Raw (I)))
                   / Real (Graecus.Fixed.Scale)
                   - Elf.Log (Point (I)));
         begin
            Worst := Real'Max (Worst, D);
         end;
      end loop;

      Row
        ("sweep",
         "log_fixed",
         Calls,
         A,
         B,
         "worst drift vs runtime" & Real'Image (Worst));
   end;

   --  sqrt: one hardware instruction on the float side, so this is the
   --  least favourable comparison in the crate.  Swept over
   --  Year_Fraction, geometrically, points precomputed.
   declare
      package Elf renames Ada.Numerics.Long_Elementary_Functions;
      Sweep : constant := 16_000;
      Calls : constant Long_Long_Integer := Long_Long_Integer (Passes) * Sweep;
      A, B  : Ada.Real_Time.Time;
      Worst : Real := 0.0;

      type Point_Array is array (1 .. Sweep) of Real;
      type Raw_Array is array (1 .. Sweep) of Graecus.Fixed.Sqrt_Arg;
      Point     : Point_Array;
      Point_Raw : Raw_Array;
   begin
      for I in 1 .. Sweep loop
         Point (I) :=
           Real'Min
             (1.0,
              Real'Max
                (1.0e-7,
                 1.0e-7
                 * Elf.Exp (Elf.Log (1.0e7) * Real (I) / Real (Sweep))));
         Point_Raw (I) :=
           Graecus.Fixed.Sqrt_Arg (Point (I) * Real (Graecus.Fixed.Scale));
      end loop;

      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum := Checksum + Elf.Sqrt (Point (I));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;
      Row ("sweep", "sqrt", Calls, A, B, "x in [1e-7, 1]");

      A := Ada.Real_Time.Clock;
      for P in 1 .. Passes loop
         pragma Unreferenced (P);
         for I in 1 .. Sweep loop
            Checksum := Checksum + Real (Graecus.Fixed.Sqrt (Point_Raw (I)));
         end loop;
      end loop;
      B := Ada.Real_Time.Clock;

      for I in 1 .. Sweep loop
         declare
            D : constant Real :=
              abs (Real (Graecus.Fixed.Sqrt (Point_Raw (I)))
                   / Real (Graecus.Fixed.Scale)
                   - Elf.Sqrt (Point (I)));
         begin
            Worst := Real'Max (Worst, D);
         end;
      end loop;

      Row
        ("sweep",
         "sqrt_fixed",
         Calls,
         A,
         B,
         "worst drift vs runtime" & Real'Image (Worst));
   end;

   Bench_Scenario ("0dte", Zero_Dte, Passes);
   Bench_Scenario ("week", Week_Dte, Passes);

   New_Line;
   Put ("checksum,");
   Real_IO.Put (Checksum, Fore => 1, Aft => 6, Exp => 1);
   New_Line;
end Bench_Graecus;
