with Ada.Text_IO;

with Graecus;

--  Invert one near-the-money SPX call premium (4 DTE) into its implied
--  vol, then price the signed delta at that vol.

procedure Iv_Of_Premium is
   V : Graecus.Vol_Range;
   Q : Graecus.Quality;
   D : Graecus.Real;
begin
   Graecus.Implied_Vol
     (Premium => 42.5,
      S       => 7_500.0,
      K       => 7_480.0,
      T       => 4.0 / 365.25,
      R       => 0.045,
      Right   => Graecus.Call,
      V       => V,
      Q       => Q);
   D :=
     Graecus.Delta_Of (7_500.0, 7_480.0, 4.0 / 365.25, V, 0.045, Graecus.Call);
   Ada.Text_IO.Put_Line
     ("iv =" & V'Image & "  quality = " & Q'Image & "  delta =" & D'Image);
end Iv_Of_Premium;
