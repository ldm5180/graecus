with Ada.Characters.Handling;
with Ada.Text_IO;

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

   --  The fixture's columns, by number.
   Name_Field     : constant := 1;
   Right_Field    : constant := 2;
   Spot_Field     : constant := 3;
   Strike_Field   : constant := 4;
   Years_Field    : constant := 5;
   True_Vol_Field : constant := 6;
   Premium_Field  : constant := 7;
   Iv_Field       : constant := 9;
   Delta_Field    : constant := 10;

   function Number (Line : String; N : Positive) return Real
   is (Real'Value (Field (Line, N)));

   function Row_Of (Line : String) return Fixture_Row
   is (Right        =>
         (if Field (Line, Right_Field) = "CALL" then Call else Put),
       Spot         => Number (Line, Spot_Field),
       Strike       => Number (Line, Strike_Field),
       Years        => Number (Line, Years_Field),
       Has_True_Vol => Field (Line, True_Vol_Field)'Length > 0,
       True_Vol     =>
         (if Field (Line, True_Vol_Field)'Length > 0
          then Number (Line, True_Vol_Field)
          else 0.0),
       Premium      => Number (Line, Premium_Field),
       Go_Iv        => Number (Line, Iv_Field),
       Go_Delta     => Number (Line, Delta_Field));

   function Names (Line, Name, Right : String) return Boolean
   is (Field (Line, Name_Field) = Name
       and then Field (Line, Right_Field) = Right);

   --  The fixture line named Name for Right, or "" when there is none.
   function Line_Named (Name, Right : String) return String is
      use Ada.Text_IO;
      File : File_Type;
   begin
      Open (File, In_File, Fixture_Path);
      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            if Names (Line, Name, Right) then
               Close (File);
               return Line;
            end if;
         end;
      end loop;
      Close (File);
      return "";
   end Line_Named;

   function Has_Row (Name, Right : String) return Boolean
   is (Line_Named (Name, Right)'Length > 0);

   function Row (Name, Right : String) return Fixture_Row
   is (Row_Of (Line_Named (Name, Right)));

   function Contract_Of (Row : Fixture_Row) return Contract
   is ((Right => Row.Right,
        Value =>
          [Spot    => Row.Spot,
           Strike  => Row.Strike,
           Expiry  => Row.Years,
           Vol     => 0.0,
           Rate    => Fixture_Rate,
           Premium => Row.Premium],
        Given => Seeking_Terms));

end Graecus_World;
