with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;

with Graecus;
with Graecus_World;

--  The step registry the feature runner dispatches on: one Step_Kind
--  per pattern, one table that reads like the features, and one Execute
--  that offers each step to every feature's state machine.

package Graecus_Steps is

   --  The steps, grouped by the feature that reads them.  Each is an
   --  event of that feature's state machine, in its own child package.
   type Step_Kind is
     (E_Set_Spot,
      E_Set_Contract,
      E_Set_Days,
      E_Set_Vol,
      E_Set_Rate,
      E_Set_Premium,
      E_Check_Price,
      E_Check_Price_Floor,
      E_Check_Vol_Refused,
      E_Check_Delta,
      E_Check_Delta_Sign,
      E_Check_Delta_Sum,
      E_Implied,
      E_Check_Iv,
      E_Check_Quality,
      E_Check_Round_Trip,
      E_Load_Row,
      E_Check_Row_Iv,
      E_Check_Row_Delta,
      E_Check_Weight,
      E_Check_Weight_Refused);

   --  The steps that give the contract one of its terms.
   subtype Set_Step is Step_Kind range E_Set_Spot .. E_Set_Premium;

   type Hook_Kind is (Fresh_World);

   --  The vol a contract's premium implies, and whether to trust it.
   type Implied_Reading is record
      Iv      : Graecus.Vol_Range := Graecus.Min_Vol;
      Quality : Graecus.Quality := Graecus.Clamped;
   end record;

   --  What one scenario composes and reads back.
   type World is record
      Contract : Graecus_World.Contract;
      Implied  : Implied_Reading;
      Row      : Graecus_World.Fixture_Row;
   end record;

   --  One step as a machine sees it: the scenario, the step's arguments,
   --  frame and outcome, and the event an action asks to be taken next
   --  (Then_Take), which the runner posts before the step returns.
   type Step_Context is record
      W        : World;
      A        : Fabula.Args.List;
      Info     : Fabula.Frames.Frame;
      R        : Fabula.Check.Outcome;
      Has_Next : Boolean := False;
      Next     : Step_Kind := Step_Kind'First;
   end record;

   procedure Then_Take (Ctx : in out Step_Context; Evt : Step_Kind);

   --  Whether capture N reads as a number.
   function Real_Read (Ctx : Step_Context; N : Positive := 1) return Boolean;

   --  Capture N, which Real_Read said reads.
   function Real_Of (Ctx : Step_Context; N : Positive := 1) return Graecus.Real
   with Pre => Real_Read (Ctx, N);

   --  Fail the step for capture N: why it does not read as a number.
   procedure Refuse_Real (Ctx : in out Step_Context; N : Positive := 1);

   --  Whether the contract has every term Needs names and every capture
   --  reads as a number: the guard every check that prices shares.
   function Ready
     (Ctx : Step_Context; Needs : Graecus_World.Term_Set) return Boolean;

   --  Fail the step that Ready refused: the term the contract lacks, or
   --  the first capture that does not read.
   procedure Refuse_Unready
     (Ctx : in out Step_Context; Needs : Graecus_World.Term_Set);

   --  Check that Got is Want to within Tolerance; What names Got.
   procedure Check_Close
     (Ctx                  : in out Step_Context;
      What                 : String;
      Got, Want, Tolerance : Graecus.Real);

   --  Check Got against "{float} within {float}", captures 1 and 2.
   procedure Check_Within
     (Ctx : in out Step_Context; What : String; Got : Graecus.Real)
   with Pre => Real_Read (Ctx, 1) and then Real_Read (Ctx, 2);

   package Steps is new
     Fabula.Registry
       (Step_Kind => Step_Kind,
        Hook_Kind => Hook_Kind,
        Context   => World);
   use Steps;

   --!format off
   Step_Defs : constant Steps.Step_Table :=
     [Step ("an SPX at {float}")                     >= E_Set_Spot,
      Step ("a {word} struck at {float}")            >= E_Set_Contract,
      Step ("{float} days to expiry")                >= E_Set_Days,
      Step ("a vol of {float} is refused")           >= E_Check_Vol_Refused,
      Step ("a vol of {float}")                      >= E_Set_Vol,
      Step ("a rate of {float}")                     >= E_Set_Rate,
      Step ("a premium of {float}")                  >= E_Set_Premium,
      Step ("the price is {float} within {float}")   >= E_Check_Price,
      Step ("the price is at least {float}")         >= E_Check_Price_Floor,
      Step ("the delta is {float} within {float}")   >= E_Check_Delta,
      Step ("the delta is {word}")                   >= E_Check_Delta_Sign,
      Step ("the call and put deltas sum to {float} within {float}")
                                                     >= E_Check_Delta_Sum,
      Step ("the vol it implies is sought")          >= E_Implied,
      Step ("the implied vol recovers the vol that priced it within {float}")
                                                     >= E_Check_Round_Trip,
      Step ("the implied vol is {float} within {float}")
                                                     >= E_Check_Iv,
      Step ("the implied vol is {word}")             >= E_Check_Quality,
      Step ("the fixture row {word} {word}")         >= E_Load_Row,
      Step ("its implied vol matches the fixture's within {float}")
                                                     >= E_Check_Row_Iv,
      Step ("its delta matches the fixture's within {float}")
                                                     >= E_Check_Row_Delta,
      Step ("a sample {float} time constants after the last is refused")
                                                     >= E_Check_Weight_Refused,
      Step ("a sample {float} time constants after the last weighs {float} "
            & "within {float}")                      >= E_Check_Weight];
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
