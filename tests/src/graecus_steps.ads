with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;

--  The step registry the feature runner dispatches on: one Step_Kind
--  per pattern, one table that reads like the features, and one Execute
--  that offers each step to the feature's state machine.

package Graecus_Steps is

   --  The steps: each is an event of the feature's state machine.
   type Step_Kind is (E_Start, E_Add_Dollars, E_Check_Dollars);

   type Hook_Kind is (Fresh_World);

   --  What one scenario reads back.
   type World is record
      Total : Natural := 0;
   end record;

   package Steps is new
     Fabula.Registry
       (Step_Kind => Step_Kind,
        Hook_Kind => Hook_Kind,
        Context   => World);
   use Steps;

   --!format off
   Step_Defs : constant Steps.Step_Table :=
     [Step ("nothing has been priced")    >= E_Start,
      Step ("{int} dollars are added")    >= E_Add_Dollars,
      Step ("the total is {int} dollars") >= E_Check_Dollars];
   --!format on

   Hook_Defs : constant Steps.Hook_Table := [Before >= Fresh_World];

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out World;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out World;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

end Graecus_Steps;
