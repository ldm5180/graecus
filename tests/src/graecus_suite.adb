with AUnit.Test_Cases;

with Graecus_Fixed_Tests;
with Graecus_Tests;

package body Graecus_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;

      procedure Add (T : AUnit.Test_Cases.Test_Case_Access) is
      begin
         AUnit.Test_Suites.Add_Test (Result, T);
      end Add;
   begin
      Add (new Graecus_Tests.Test);
      Add (new Graecus_Fixed_Tests.Test);
      return Result;
   end Suite;

end Graecus_Suite;
