with Ada.Characters.Handling;

with Fabula.Check;

package body Graecus_World is

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

   function Name (T : Term) return String
   is (Ada.Characters.Handling.To_Lower (T'Image));

   function First_Missing (C : Contract; Needs : Term_Set) return Term is
   begin
      for T in Term loop
         if Needs (T) and then not C.Given (T) then
            return T;
         end if;
      end loop;
      raise Program_Error with "nothing is missing";
   end First_Missing;

   --  A scenario's expiry in days, as the year fraction the crate takes.
   function Years (Days : Real) return Real
   is (Days / Days_Per_Year);

   function Fits (T : Term; X : Real) return Boolean
   is (case T is
         when Spot | Strike => X in Spot_Range,
         when Expiry        => Years (X) in Year_Fraction,
         when Vol           => X in Vol_Range,
         when Rate          => X in Rate_Range,
         when Premium       => X in Premium_Range);

   function Low (T : Term) return Real
   is (case T is
         when Spot | Strike => Spot_Range'First,
         when Expiry        => Year_Fraction'First * Days_Per_Year,
         when Vol           => Vol_Range'First,
         when Rate          => Rate_Range'First,
         when Premium       => Premium_Range'First);

   function High (T : Term) return Real
   is (case T is
         when Spot | Strike => Spot_Range'Last,
         when Expiry        => Year_Fraction'Last * Days_Per_Year,
         when Vol           => Vol_Range'Last,
         when Rate          => Rate_Range'Last,
         when Premium       => Premium_Range'Last);

   function Envelope (T : Term) return String
   is ("the "
       & Name (T)
       & " must be in "
       & Fabula.Check.Real_Image (Low (T))
       & " .. "
       & Fabula.Check.Real_Image (High (T))
       & (if T = Expiry then " days" else ""));

   procedure Give (C : in out Contract; T : Term; X : Real) is
   begin
      C.Value (T) := (if T = Expiry then Years (X) else X);
      C.Given (T) := True;
   end Give;

   function Price_Of (C : Contract) return Real
   is (Price
         (C.Value (Spot),
          C.Value (Strike),
          C.Value (Expiry),
          C.Value (Vol),
          C.Value (Rate),
          C.Right));

   procedure Seek
     (C : Contract; Iv : out Vol_Range; Quality : out Graecus.Quality) is
   begin
      Implied_Vol
        (C.Value (Premium),
         C.Value (Spot),
         C.Value (Strike),
         C.Value (Expiry),
         C.Value (Rate),
         C.Right,
         Iv,
         Quality);
   end Seek;

   function Delta_Of (C : Contract; Right : Option_Right) return Real
   is (Graecus.Delta_Of
         (C.Value (Spot),
          C.Value (Strike),
          C.Value (Expiry),
          C.Value (Vol),
          C.Value (Rate),
          Right));

end Graecus_World;
