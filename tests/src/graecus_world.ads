with Graecus; use Graecus;

--  What a scenario and the parity test share: the contract a scenario
--  composes from its sentences, the fixture file the options_bot library
--  dumped, and how one of its lines splits.

package Graecus_World is

   --  The 36-row parity fixture, relative to the crate root.
   Fixture_Path : constant String := "tests/data/options_bot_greeks.csv";

   --  The Nth comma-separated field of a fixture line; "" past the last.
   function Field (Line : String; N : Positive) return String;

   --  The numbers a scenario names to make a contract.
   type Term is (Spot, Strike, Expiry, Vol, Rate, Premium);

   --  T as a sentence names it: "vol", "expiry".
   function Name (T : Term) return String;

   type Term_Set is array (Term) of Boolean;
   type Term_Values is array (Term) of Real;

   --  A contract as a scenario composes it: the terms given so far (the
   --  expiry in years), and the right that came with the strike.
   type Contract is record
      Right : Option_Right := Call;
      Value : Term_Values := [others => 0.0];
      Given : Term_Set := [others => False];
   end record;

   --  Calendar days in a year, as the fixture's year fractions count them.
   Days_Per_Year : constant := 365.25;

   --  The terms Price and Delta_Of read: all but a premium.
   Priced_Terms : constant Term_Set := [Premium => False, others => True];

   --  The terms Implied_Vol reads: all but a vol.
   Seeking_Terms : constant Term_Set := [Vol => False, others => True];

   function Has (C : Contract; Needs : Term_Set) return Boolean
   is (for all T in Term => C.Given (T) or else not Needs (T));

   --  The first term Needs names that C has not been given.
   function First_Missing (C : Contract; Needs : Term_Set) return Term
   with Pre => not Has (C, Needs);

   --  Whether X, as a scenario writes it (days for the expiry), lies in
   --  the crate's subtype for T: the proof envelope.
   function Fits (T : Term; X : Real) return Boolean;

   --  The envelope for T, as a scenario writes it: "the vol must be in
   --  <low> .. <high>".
   function Envelope (T : Term) return String;

   procedure Give (C : in out Contract; T : Term; X : Real)
   with Pre => Fits (T, X), Post => C.Given (T);

   function Price_Of (C : Contract) return Real
   with Pre => Has (C, Priced_Terms);

   --  The vol C's premium implies, and whether to trust it.
   procedure Seek
     (C : Contract; Iv : out Vol_Range; Quality : out Graecus.Quality)
   with Pre => Has (C, Seeking_Terms);

   --  The delta of C's terms for Right, whatever right C was given.
   function Delta_Of (C : Contract; Right : Option_Right) return Real
   with Pre => Has (C, Priced_Terms);

   --  The rate every fixture row was priced at.
   Fixture_Rate : constant Real := 0.045;

   --  One fixture row: the contract the Go library was handed, the vol
   --  that priced its premium (none where the premium has no time
   --  value), and the vol and delta the library answered.
   type Fixture_Row is record
      Right        : Option_Right := Call;
      Spot         : Real := 0.0;
      Strike       : Real := 0.0;
      Years        : Real := 0.0;
      Has_True_Vol : Boolean := False;
      True_Vol     : Real := 0.0;
      Premium      : Real := 0.0;
      Go_Iv        : Real := 0.0;
      Go_Delta     : Real := 0.0;
   end record;

   --  The row a fixture line holds, past its name.
   function Row_Of (Line : String) return Fixture_Row;

   --  Whether the fixture holds a row named Name for Right ("CALL",
   --  "PUT", as the file spells them).
   function Has_Row (Name, Right : String) return Boolean;

   --  The row named Name for Right.
   function Row (Name, Right : String) return Fixture_Row
   with Pre => Has_Row (Name, Right);

   --  The contract a row names: every term but a vol, at Fixture_Rate.
   function Contract_Of (Row : Fixture_Row) return Contract
   with Post => Has (Contract_Of'Result, Seeking_Terms);

end Graecus_World;
